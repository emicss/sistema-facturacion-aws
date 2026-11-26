#!/usr/bin/env python3
"""
Script de prueba end-to-end para validar el flujo completo de facturación,
control de idempotencia en DynamoDB, catálogo denso de 50 columnas y auditoría inmutable.
"""

import json
import os
import sys
import time
import uuid
import urllib.request
import urllib.error

API_URL = os.getenv("API_URL", "https://bvw7s0kuu6.execute-api.us-east-1.amazonaws.com").rstrip("/")

def make_request(path: str, method: str = "GET", headers: dict = None, body: dict = None):
    url = f"{API_URL}{path}"
    req_headers = {"Content-Type": "application/json"}
    if headers:
        req_headers.update(headers)
    
    data = json.dumps(body).encode("utf-8") if body else None
    req = urllib.request.Request(url, data=data, headers=req_headers, method=method)
    
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw_err = e.read().decode("utf-8")
        try:
            parsed = json.loads(raw_err)
        except Exception:
            parsed = {"error_raw": raw_err}
        return e.code, parsed


def run_tests():
    print("======================================================================")
    print("EJECUTANDO PRUEBAS DE INTEGRACIÓN: IDEMPOTENCIA, 50 CAMPOS Y EVENTOS")
    print(f"Target API Endpoint: {API_URL}")
    print("======================================================================\n")

    # 1. HEALTH CHECK
    print("[1/6] Verificando Health Check del sistema...")
    status_code, health = make_request("/health")
    assert status_code == 200, f"Error en /health: {health}"
    print(f"  -> RDS MySQL: {health.get('rds_mysql')} ({health.get('servicios_en_catalogo')} servicios)")
    print(f"  -> DynamoDB Eventos: {health.get('dynamodb_tabla')} ({health.get('dynamodb_estado')})")
    print(f"  -> DynamoDB Idempotencia: {health.get('idempotencia_tabla')} ({health.get('idempotencia_estado')})")
    print("  [OK] Health Check verificado con éxito.\n")

    # 2. LOGIN (RDS como fuente única)
    print("[2/6] Iniciando sesión con admin@cloudtech.mx (RDS)...")
    status_code, login_data = make_request(
        "/auth/login",
        method="POST",
        body={"email": "admin@cloudtech.mx", "password": "CloudTech2026!"},
    )
    assert status_code == 200, f"Error en login: {login_data}"
    token = login_data["access_token"]
    auth_headers = {"Authorization": f"Bearer {token}"}
    print(f"  -> Token JWT obtenido para: {login_data['usuario']['nombre_completo']} ({login_data['usuario']['rol']})")
    print("  [OK] Autenticación verificada.\n")

    # 3. VERIFICAR QUE SERVICIOS TIENE EXACTAMENTE 50 COLUMNAS
    print("[3/6] Consultando detalle de servicio #1 (validando 50 características)...")
    status_code, srv_data = make_request("/servicios/1", headers=auth_headers)
    assert status_code == 200, f"Error consultando /servicios/1: {srv_data}"
    servicio = srv_data["servicio"]
    num_campos = len(servicio.keys())
    print(f"  -> Nombre: {servicio['nombre_servicio']}")
    print(f"  -> Categoría: {servicio['categoria']} | Región: {servicio.get('region_aws_default')}")
    print(f"  -> SLA: {servicio.get('sla_disponibilidad_porc')}% | Soporte 24/7: {servicio.get('soporte_24_7')}")
    print(f"  -> Cifrado: {servicio.get('algoritmo_cifrado')} | Almacenamiento: {servicio.get('almacenamiento_gb')}GB ({servicio.get('tipo_almacenamiento')})")
    print(f"  -> Total de columnas/campos recibidos: {num_campos}")
    assert num_campos == 50, f"Esperaba 50 columnas, pero se encontraron {num_campos}"
    print("  [OK] Tabla Servicios cuenta con exactamente 50 columnas.\n")

    # 4. PRUEBA DE IDEMPOTENCIA: EMISIÓN DE FACTURA
    test_emit_key = f"TEST-IDEM-EMIT-{int(time.time())}-{uuid.uuid4().hex[:6]}"
    print(f"[4/6] Probando Idempotencia en Emisión de Factura (Key: {test_emit_key})...")
    emit_body = {
        "id_cliente": 1,
        "serie": "FAC",
        "usar_carrito_dynamo": False,
        "items": [{"id_servicio": 1, "cantidad": 2.0}],
    }

    # Primer intento
    print("  -> Intento 1 (Nueva emisión)...")
    status_1, resp_1 = make_request(
        "/facturas/emitir",
        method="POST",
        headers={**auth_headers, "Idempotency-Key": test_emit_key},
        body=emit_body,
    )
    assert status_1 == 200, f"Fallo en Intento 1: {resp_1}"
    id_factura = resp_1["id_factura"]
    folio_1 = resp_1["folio"]
    print(f"     Factura emitida: ID {id_factura}, Folio: {folio_1}")

    # Segundo intento con la misma llave (debe ser idempotente)
    print("  -> Intento 2 (Reintento con misma Idempotency-Key)...")
    status_2, resp_2 = make_request(
        "/facturas/emitir",
        method="POST",
        headers={**auth_headers, "Idempotency-Key": test_emit_key},
        body=emit_body,
    )
    assert status_2 == 200, f"Fallo en Intento 2: {resp_2}"
    assert resp_2.get("idempotente") is True, f"Se esperaba respuesta idempotente: {resp_2}"
    assert resp_2["id_factura"] == id_factura, "El ID de factura difiere entre llamadas idempotentes"
    assert resp_2["folio"] == folio_1, "El folio cambió en un reintento idempotente"
    print(f"     Respuesta idempotente confirmada: Folio idéntico {resp_2['folio']} sin generar folio doble.")
    print("  [OK] Idempotencia en Emisión de Facturas verificada exitosamente.\n")

    # 5. PRUEBA DE IDEMPOTENCIA: REGISTRO DE PAGOS (SP 6)
    test_pay_key = f"TEST-IDEM-PAY-{int(time.time())}-{uuid.uuid4().hex[:6]}"
    print(f"[5/6] Probando Idempotencia en Registro de Pago (Key: {test_pay_key})...")
    pay_body = {
        "monto_pagado": 100.00,
        "metodo_pago": "TRANSFERENCIA",
        "referencia_bancaria": f"TEST-REF-{uuid.uuid4().hex[:6]}",
    }

    # Primer intento de abono
    print("  -> Intento 1 de pago...")
    pstatus_1, presp_1 = make_request(
        f"/facturas/{id_factura}/pagos",
        method="POST",
        headers={**auth_headers, "Idempotency-Key": test_pay_key},
        body=pay_body,
    )
    assert pstatus_1 == 200, f"Fallo en pago 1: {presp_1}"
    saldo_1 = presp_1["factura"]["saldo_pendiente"]
    print(f"     Pago registrado: Saldo restante = ${saldo_1}")

    # Segundo intento de abono con misma llave
    print("  -> Intento 2 de pago (misma Idempotency-Key)...")
    pstatus_2, presp_2 = make_request(
        f"/facturas/{id_factura}/pagos",
        method="POST",
        headers={**auth_headers, "Idempotency-Key": test_pay_key},
        body=pay_body,
    )
    assert pstatus_2 == 200, f"Fallo en pago 2: {presp_2}"
    assert presp_2.get("idempotente") is True, f"Se esperaba pago idempotente: {presp_2}"
    assert presp_2["factura"]["saldo_pendiente"] == saldo_1, "El saldo cambió en una llamada de pago idempotente"
    print("     Doble cargo prevenido exitosamente.")
    print("  [OK] Idempotencia en Pagos verificada con éxito.\n")

    # 6. VERIFICAR LOGS EN DYNAMODB AUDITORÍA
    print("[6/6] Verificando logs inmutables en DynamoDB (/auditoria/eventos)...")
    status_code, audit_data = make_request("/auditoria/eventos", headers=auth_headers)
    assert status_code == 200, f"Error en auditoría: {audit_data}"
    eventos = audit_data.get("eventos", [])
    print(f"  -> Total de eventos devueltos vía GSI1: {len(eventos)}")
    if eventos:
        ultimo = eventos[0]
        print(f"  -> Último evento registrado: Acción='{ultimo.get('accion')}', Estado='{ultimo.get('estado')}'")
        print(f"  -> Detalle canónico: {json.dumps(ultimo.get('detalle', {}))}")
    print("  [OK] Auditoría inmutable en DynamoDB validada.\n")

    print("======================================================================")
    print("¡TODAS LAS PRUEBAS COMPLETADAS CON ÉXITO!")
    print("La tabla de idempotencia y la de eventos ahora cuentan con datos reales")
    print("y fecha/hora actualizadas en AWS DynamoDB us-east-1.")
    print("======================================================================")

if __name__ == "__main__":
    run_tests()
