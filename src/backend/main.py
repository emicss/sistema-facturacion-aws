import json
import time
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import List, Optional

from boto3.dynamodb.conditions import Key
from fastapi import Depends, FastAPI, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from db import dynamo_table, get_db_connection, registrar_auditoria
from security import (
    create_access_token,
    get_current_user,
    hash_password,
    require_roles,
    verify_password,
)

app = FastAPI(
    title="API Sistema de Facturación y Servicios (Cloud Híbrido AWS)",
    description="Backend híbrido con Amazon RDS (MySQL 8.0 + 10 SP) y Amazon DynamoDB (Sesiones, Carrito y Auditoría).",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # En producción restringir al dominio del frontend
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================================
# MODELOS PYDANTIC (Validación de entrada y documentación OpenAPI/Swagger)
# ============================================================================
class LoginRequest(BaseModel):
    email: str
    password: str


class RegisterUserRequest(BaseModel):
    nombre_completo: str
    email: str
    password: str = Field(..., min_length=8)
    rol: str = Field(..., pattern="^(ADMIN|CONTADOR|OPERADOR|CLIENTE)$")


class CartItemRequest(BaseModel):
    id_servicio: int
    cantidad: float = Field(1.0, gt=0)


class FacturaItemInput(BaseModel):
    id_servicio: int
    cantidad: float = Field(1.0, gt=0)


class EmitirFacturaRequest(BaseModel):
    id_cliente: int
    serie: str = Field("FAC", pattern="^(FAC|HON|NC)$")
    usar_carrito_dynamo: bool = True
    items: Optional[List[FacturaItemInput]] = None


class CancelarFacturaRequest(BaseModel):
    motivo: str = Field(..., min_length=5, max_length=250)


class RegistrarPagoRequest(BaseModel):
    monto_pagado: float = Field(..., gt=0)
    metodo_pago: str = Field("TRANSFERENCIA", pattern="^(TRANSFERENCIA|TARJETA|EFECTIVO|CHEQUE)$")
    referencia_bancaria: str = Field(..., min_length=3, max_length=80)


class AsignacionMasivaRequest(BaseModel):
    categoria: str
    id_caracteristica: int
    valor_configurado: str


class CambioTarifaRequest(BaseModel):
    nuevo_precio: float = Field(..., ge=0)
    motivo: str = Field(..., min_length=5, max_length=200)


# ============================================================================
# HEALTH CHECK (Verifica RDS + DynamoDB)
# ============================================================================
@app.get("/health", tags=["Sistema"])
def health_check():
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS total_servicios FROM Servicios")
            servicios = cur.fetchone()["total_servicios"]
        dynamo_status = dynamo_table.table_status
        return {
            "status": "ok",
            "rds_mysql": "conectado",
            "servicios_en_catalogo": servicios,
            "dynamodb_tabla": dynamo_table.name,
            "dynamodb_estado": dynamo_status,
        }
    finally:
        conn.close()


# ============================================================================
# 1. AUTENTICACIÓN JWT, RBAC Y SESIONES EN DYNAMODB
# ============================================================================
@app.post("/auth/login", tags=["Autenticación"])
def login(payload: LoginRequest):
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id_usuario, nombre_completo, email, password_hash, rol, activo "
                "FROM Usuarios_Roles WHERE email = %s",
                (payload.email,),
            )
            user = cur.fetchone()

        if not user or not user["activo"] or not verify_password(payload.password, user["password_hash"]):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Credenciales inválidas")

        token = create_access_token(user["id_usuario"], user["email"], user["rol"])
        ahora = datetime.now(timezone.utc).isoformat()
        session_id = str(uuid.uuid4())[:12]

        # Guardar sesión activa en DynamoDB con TTL (2 horas)
        dynamo_table.put_item(
            Item={
                "PK": f"USER#{user['id_usuario']}",
                "SK": f"SESSION#{session_id}",
                "GSI1PK": "TYPE#SESSION",
                "GSI1SK": ahora,
                "email": user["email"],
                "rol": user["rol"],
                "ttl_expira": int(time.time()) + 7200,
            }
        )
        registrar_auditoria(user["id_usuario"], "LOGIN_EXITOSO", {"email": user["email"], "rol": user["rol"]})

        return {
            "access_token": token,
            "token_type": "bearer",
            "usuario": {
                "id_usuario": user["id_usuario"],
                "nombre_completo": user["nombre_completo"],
                "email": user["email"],
                "rol": user["rol"],
            },
        }
    finally:
        conn.close()


@app.post("/auth/register", tags=["Autenticación"])
def register_user(
    payload: RegisterUserRequest,
    current_user: dict = Depends(require_roles(["ADMIN"])),
):
    conn = get_db_connection()
    try:
        hashed = hash_password(payload.password)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO Usuarios_Roles (nombre_completo, email, password_hash, rol) VALUES (%s, %s, %s, %s)",
                (payload.nombre_completo, payload.email, hashed, payload.rol),
            )
            nuevo_id = cur.lastrowid
        conn.commit()
        registrar_auditoria(current_user["id_usuario"], "CREAR_USUARIO", {"nuevo_id": nuevo_id, "rol": payload.rol})
        return {"mensaje": "Usuario creado", "id_usuario": nuevo_id}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(e))
    finally:
        conn.close()


# ============================================================================
# 2. CATÁLOGO DE SERVICIOS, CARACTERÍSTICAS Y CLIENTES (RDS + SP 9 y SP 10)
# ============================================================================
@app.get("/servicios", tags=["Catálogo"])
def listar_servicios(
    categoria: Optional[str] = None,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: dict = Depends(get_current_user),
):
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            if categoria:
                cur.execute(
                    "SELECT * FROM Servicios WHERE activo = TRUE AND categoria = %s LIMIT %s OFFSET %s",
                    (categoria, limit, offset),
                )
            else:
                cur.execute(
                    "SELECT * FROM Servicios WHERE activo = TRUE LIMIT %s OFFSET %s",
                    (limit, offset),
                )
            servicios = cur.fetchall()
        return {"total_devueltos": len(servicios), "servicios": servicios}
    finally:
        conn.close()


@app.get("/servicios/{id_servicio}/caracteristicas", tags=["Catálogo"])
def listar_caracteristicas_de_servicio(
    id_servicio: int,
    current_user: dict = Depends(get_current_user),
):
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT cc.codigo_caracteristica, cc.nombre_caracteristica, cc.unidad_medida, cs.valor_configurado
                FROM Caracteristicas_Servicio cs
                INNER JOIN Catalogo_Caracteristicas cc ON cs.id_caracteristica = cc.id_caracteristica
                WHERE cs.id_servicio = %s
                """,
                (id_servicio,),
            )
            return {"id_servicio": id_servicio, "caracteristicas": cur.fetchall()}
    finally:
        conn.close()


@app.get("/caracteristicas", tags=["Catálogo"])
def listar_catalogo_caracteristicas(current_user: dict = Depends(get_current_user)):
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM Catalogo_Caracteristicas ORDER BY id_caracteristica ASC")
            rows = cur.fetchall()
        return {"total": len(rows), "caracteristicas": rows}
    finally:
        conn.close()


@app.get("/clientes", tags=["Catálogo"])
def listar_clientes(current_user: dict = Depends(require_roles(["ADMIN", "CONTADOR", "OPERADOR"]))):
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM Clientes WHERE activo = TRUE ORDER BY id_cliente ASC")
            return {"clientes": cur.fetchall()}
    finally:
        conn.close()


@app.post("/servicios/asignar-caracteristicas-masivas", tags=["Catálogo (SP)"])
def asignar_caracteristicas_masivas(
    payload: AsignacionMasivaRequest,
    current_user: dict = Depends(require_roles(["ADMIN"])),
):
    """Ejecuta SP 9: Asignación masiva de características por categoría."""
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.callproc(
                "sp_asignar_caracteristicas_masivas",
                (payload.categoria, payload.id_caracteristica, payload.valor_configurado),
            )
            res = cur.fetchone()
        conn.commit()
        registrar_auditoria(
            current_user["id_usuario"],
            "SP9_ASIGNACION_MASIVA",
            {
                "categoria": payload.categoria,
                "id_caracteristica": payload.id_caracteristica,
                "valor": payload.valor_configurado,
            },
        )
        return {"mensaje": "Asignación masiva ejecutada", "resultado": res}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(e))
    finally:
        conn.close()


@app.put("/servicios/{id_servicio}/tarifa", tags=["Catálogo (SP)"])
def actualizar_tarifa_servicio(
    id_servicio: int,
    payload: CambioTarifaRequest,
    current_user: dict = Depends(require_roles(["ADMIN", "CONTADOR"])),
):
    """Ejecuta SP 10: Auditoría de cambios en tarifas de servicios."""
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.callproc(
                "sp_auditar_cambio_tarifa",
                (id_servicio, payload.nuevo_precio, current_user["id_usuario"], payload.motivo),
            )
        conn.commit()
        registrar_auditoria(
            current_user["id_usuario"],
            "SP10_CAMBIO_TARIFA",
            {"id_servicio": id_servicio, "nuevo_precio": str(payload.nuevo_precio), "motivo": payload.motivo},
        )
        return {"mensaje": "Tarifa actualizada y auditada correctamente", "id_servicio": id_servicio}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(e))
    finally:
        conn.close()


# ============================================================================
# 3. CARRITO TEMPORAL DE FACTURACIÓN (Amazon DynamoDB)
# ============================================================================
@app.get("/carrito", tags=["Carrito Temporal (DynamoDB)"])
def ver_carrito(current_user: dict = Depends(get_current_user)):
    pk = f"CART#{current_user['id_usuario']}"
    resp = dynamo_table.query(KeyConditionExpression=Key("PK").eq(pk))
    return {"id_usuario": current_user["id_usuario"], "items": resp.get("Items", [])}


@app.post("/carrito/items", tags=["Carrito Temporal (DynamoDB)"])
def agregar_al_carrito(
    payload: CartItemRequest,
    current_user: dict = Depends(require_roles(["ADMIN", "OPERADOR"])),
):
    # Validar que el servicio exista en RDS
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id_servicio, nombre_servicio, precio_unitario FROM Servicios WHERE id_servicio = %s AND activo = TRUE",
                (payload.id_servicio,),
            )
            srv = cur.fetchone()
        if not srv:
            raise HTTPException(status_code=404, detail="Servicio no encontrado")
    finally:
        conn.close()

    ahora = datetime.now(timezone.utc).isoformat()
    dynamo_table.put_item(
        Item={
            "PK": f"CART#{current_user['id_usuario']}",
            "SK": f"ITEM#{payload.id_servicio}",
            "GSI1PK": "TYPE#CART",
            "GSI1SK": ahora,
            "id_servicio": payload.id_servicio,
            "nombre_servicio": srv["nombre_servicio"],
            "precio_unitario": Decimal(str(srv["precio_unitario"])),
            "cantidad": Decimal(str(payload.cantidad)),
            "ttl_expira": int(time.time()) + 86400,
        }
    )
    return {"mensaje": "Servicio agregado al carrito temporal en DynamoDB", "id_servicio": payload.id_servicio}


@app.delete("/carrito/items/{id_servicio}", tags=["Carrito Temporal (DynamoDB)"])
def quitar_del_carrito(
    id_servicio: int,
    current_user: dict = Depends(require_roles(["ADMIN", "OPERADOR"])),
):
    dynamo_table.delete_item(
        Key={"PK": f"CART#{current_user['id_usuario']}", "SK": f"ITEM#{id_servicio}"}
    )
    return {"mensaje": "Servicio eliminado del carrito"}


# ============================================================================
# 4. FACTURACIÓN, DESCUENTOS, IMPUESTOS, TIMBRADO Y CANCELACIÓN (SP 1,2,3,4,8)
# ============================================================================
@app.post("/facturas/emitir", tags=["Facturación (SP)"])
def emitir_factura(
    payload: EmitirFacturaRequest,
    current_user: dict = Depends(require_roles(["ADMIN", "OPERADOR"])),
):
    """
    Flujo transaccional completo:
    1. Lee carrito en DynamoDB (o usa items enviados en JSON).
    2. SP 1: Genera folio atómico y cabecera de factura.
    3. Inserta Detalle_Factura con precios vigentes de RDS.
    4. SP 3 + SP 2: Aplica descuento (cliente/volumen) y calcula Subtotal, IVA y Retenciones.
    5. SP 8: Timbra factura (genera UUID y JSON CFDI).
    6. Limpia carrito en DynamoDB y guarda log de auditoría.
    """
    items_a_facturar = []
    pk_cart = f"CART#{current_user['id_usuario']}"

    if payload.usar_carrito_dynamo:
        resp = dynamo_table.query(KeyConditionExpression=Key("PK").eq(pk_cart))
        cart_items = resp.get("Items", [])
        for it in cart_items:
            items_a_facturar.append(
                {"id_servicio": int(it["id_servicio"]), "cantidad": float(it["cantidad"])}
            )
    elif payload.items:
        items_a_facturar = [it.model_dump() for it in payload.items]

    if not items_a_facturar:
        raise HTTPException(status_code=400, detail="No hay servicios en el carrito ni en la petición.")

    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            # SP 1: Generación atómica de folio
            cur.callproc(
                "sp_generar_folio_factura",
                (payload.serie, payload.id_cliente, current_user["id_usuario"], 0, 0),
            )
            cur.execute(
                "SELECT @_sp_generar_folio_factura_3 AS id_factura, @_sp_generar_folio_factura_4 AS folio"
            )
            out_sp1 = cur.fetchone()
            id_factura = out_sp1["id_factura"]
            folio = out_sp1["folio"]

            # Insertar líneas en Detalle_Factura
            for item in items_a_facturar:
                cur.execute(
                    "SELECT precio_unitario FROM Servicios WHERE id_servicio = %s",
                    (item["id_servicio"],),
                )
                srv = cur.fetchone()
                if not srv:
                    raise HTTPException(status_code=404, detail=f"Servicio {item['id_servicio']} no existe")
                precio = float(srv["precio_unitario"])
                importe = round(precio * item["cantidad"], 2)
                cur.execute(
                    "INSERT INTO Detalle_Factura (id_factura, id_servicio, cantidad, precio_unitario, importe_linea) "
                    "VALUES (%s, %s, %s, %s, %s)",
                    (id_factura, item["id_servicio"], item["cantidad"], precio, importe),
                )
            conn.commit()

            # SP 3 (aplica descuento y llama internamente a SP 2 para calcular impuestos)
            cur.callproc("sp_aplicar_descuento", (id_factura,))
            conn.commit()

            # SP 8 (timbrado y generación de comprobante JSON)
            cur.callproc("sp_generar_estructura_timbrado", (id_factura,))
            timbrado_row = cur.fetchone()
            conn.commit()

        # Vaciar carrito en DynamoDB si se usó
        if payload.usar_carrito_dynamo:
            for item in items_a_facturar:
                dynamo_table.delete_item(Key={"PK": pk_cart, "SK": f"ITEM#{item['id_servicio']}"})

        comprobante = json.loads(timbrado_row["comprobante_json"]) if timbrado_row else {}
        registrar_auditoria(
            current_user["id_usuario"],
            "EMITIR_Y_TIMBRAR_FACTURA",
            {"id_factura": id_factura, "serie": payload.serie, "folio": folio},
        )
        return {
            "mensaje": "Factura emitida y timbrada exitosamente",
            "id_factura": id_factura,
            "folio": f"{payload.serie}-{folio}",
            "comprobante_cfdi": comprobante,
        }
    except HTTPException:
        conn.rollback()
        raise
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(e))
    finally:
        conn.close()


@app.get("/facturas", tags=["Facturación (SP)"])
def listar_facturas(current_user: dict = Depends(get_current_user)):
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT f.*, c.rfc, c.razon_social
                FROM Facturas f
                INNER JOIN Clientes c ON f.id_cliente = c.id_cliente
                ORDER BY f.id_factura DESC LIMIT 50
                """
            )
            return {"facturas": cur.fetchall()}
    finally:
        conn.close()


@app.get("/facturas/{id_factura}/timbrado", tags=["Facturación (SP)"])
def obtener_comprobante_timbrado(
    id_factura: int,
    current_user: dict = Depends(get_current_user),
):
    """Ejecuta SP 8: Devuelve estructura JSON para comprobante/timbrado."""
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.callproc("sp_generar_estructura_timbrado", (id_factura,))
            row = cur.fetchone()
        conn.commit()
        if not row:
            raise HTTPException(status_code=404, detail="Factura no encontrada")
        return {"comprobante_cfdi": json.loads(row["comprobante_json"])}
    finally:
        conn.close()


@app.post("/facturas/{id_factura}/cancelar", tags=["Facturación (SP)"])
def cancelar_factura(
    id_factura: int,
    payload: CancelarFacturaRequest,
    current_user: dict = Depends(require_roles(["ADMIN", "CONTADOR"])),
):
    """Ejecuta SP 4: Cancelación formal de factura y reversión contable."""
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.callproc("sp_cancelar_factura", (id_factura, payload.motivo))
        conn.commit()
        registrar_auditoria(
            current_user["id_usuario"],
            "SP4_CANCELAR_FACTURA",
            {"id_factura": id_factura, "motivo": payload.motivo},
        )
        return {"mensaje": "Factura cancelada y pagos revertidos contablemente", "id_factura": id_factura}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(e))
    finally:
        conn.close()


# ============================================================================
# 5. PAGOS Y VALIDACIÓN DE SALDOS (SP 6)
# ============================================================================
@app.post("/facturas/{id_factura}/pagos", tags=["Pagos (SP)"])
def registrar_pago(
    id_factura: int,
    payload: RegistrarPagoRequest,
    current_user: dict = Depends(require_roles(["ADMIN", "CONTADOR"])),
):
    """Inserta abono en Pagos y ejecuta SP 6 para recalcular saldo y estado_pago."""
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO Pagos (id_factura, id_usuario_registro, monto_pagado, metodo_pago, referencia_bancaria) "
                "VALUES (%s, %s, %s, %s, %s)",
                (
                    id_factura,
                    current_user["id_usuario"],
                    payload.monto_pagado,
                    payload.metodo_pago,
                    payload.referencia_bancaria,
                ),
            )
            conn.commit()
            cur.callproc("sp_validar_estado_pago", (id_factura,))
            conn.commit()

            cur.execute(
                "SELECT id_factura, total, saldo_pendiente, estado_pago FROM Facturas WHERE id_factura = %s",
                (id_factura,),
            )
            estado = cur.fetchone()

        registrar_auditoria(
            current_user["id_usuario"],
            "SP6_REGISTRAR_PAGO",
            {"id_factura": id_factura, "monto": str(payload.monto_pagado), "referencia": payload.referencia_bancaria},
        )
        return {"mensaje": "Pago registrado y estado validado", "factura": estado}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(e))
    finally:
        conn.close()


# ============================================================================
# 6. REPORTES FISCALES (SP 5 y SP 7) Y AUDITORÍA EN DYNAMODB (GSI1)
# ============================================================================
@app.get("/reportes/cierre-fiscal", tags=["Reportes Fiscales (SP)"])
def reporte_cierre_fiscal(
    fecha_inicio: date = Query(..., description="Formato YYYY-MM-DD"),
    fecha_fin: date = Query(..., description="Formato YYYY-MM-DD"),
    current_user: dict = Depends(require_roles(["ADMIN", "CONTADOR"])),
):
    """Ejecuta SP 5: Cierre y consolidado fiscal diario/mensual."""
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.callproc("sp_cierre_fiscal_consolidado", (str(fecha_inicio), str(fecha_fin)))
            return {"cierre_fiscal": cur.fetchall()}
    finally:
        conn.close()


@app.get("/reportes/antiguedad-saldos", tags=["Reportes Fiscales (SP)"])
def reporte_antiguedad_saldos(
    current_user: dict = Depends(require_roles(["ADMIN", "CONTADOR"])),
):
    """Ejecuta SP 7: Reporte de antigüedad de saldos (30, 60, 90+ días)."""
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.callproc("sp_reporte_antiguedad_saldos")
            return {"antiguedad_saldos": cur.fetchall()}
    finally:
        conn.close()


@app.get("/auditoria/eventos", tags=["Auditoría (DynamoDB)"])
def listar_logs_auditoria(
    current_user: dict = Depends(require_roles(["ADMIN", "CONTADOR"])),
):
    """Consulta logs inmutables usando el Índice Secundario Global GSI1_Tipo_Fecha."""
    resp = dynamo_table.query(
        IndexName="GSI1_Tipo_Fecha",
        KeyConditionExpression=Key("GSI1PK").eq("TYPE#AUDIT"),
        ScanIndexForward=False,
        Limit=50,
    )
    return {"total": len(resp.get("Items", [])), "eventos": resp.get("Items", [])}

from fastapi.responses import FileResponse
import os

@app.get("/", include_in_schema=False)
def serve_frontend():
    return FileResponse(os.path.join(os.path.dirname(__file__), "../frontend/index.html"))
