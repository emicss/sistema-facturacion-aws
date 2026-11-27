import json
import os
import time
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Dict, Optional, Union

import boto3
from botocore.exceptions import ClientError
from dotenv import load_dotenv
import pymysql

load_dotenv()


# ============================================================================
# 1. CONEXIÓN A AMAZON RDS (MySQL 8.0 - Fuente Única de Verdad para Datos Maestros)
# ============================================================================
def get_db_connection():
    return pymysql.connect(
        host=os.getenv("RDS_HOST"),
        port=int(os.getenv("RDS_PORT", 3306)),
        user=os.getenv("RDS_USER"),
        password=os.getenv("RDS_PASSWORD"),
        database=os.getenv("RDS_DB"),
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
    )


# ============================================================================
# 2. CONEXIÓN A AMAZON DYNAMODB (Eventos Inmutables, Carrito e Idempotencia)
# ============================================================================
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
DYNAMO_TABLE = os.getenv("DYNAMO_TABLE", "FacturacionEventos")
DYNAMO_IDEMPOTENCY_TABLE = os.getenv("DYNAMO_IDEMPOTENCY_TABLE", "facturacion_idempotencia")

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
dynamo_table = dynamodb.Table(DYNAMO_TABLE)
idempotency_table = dynamodb.Table(DYNAMO_IDEMPOTENCY_TABLE)


def sanitize_for_dynamodb(data: Any) -> Any:
    """Convierte floats a Decimal o strings para compatibilidad estricta con DynamoDB."""
    if isinstance(data, float):
        return Decimal(str(data))
    if isinstance(data, dict):
        return {k: sanitize_for_dynamodb(v) for k, v in data.items()}
    if isinstance(data, list):
        return [sanitize_for_dynamodb(v) for v in data]
    return data


# ============================================================================
# 3. AUDITORÍA INMUTABLE EN DYNAMODB (GSI1_Tipo_Fecha)
# ============================================================================
def registrar_auditoria(
    id_usuario: int,
    accion: str,
    detalle: Dict[str, Any],
    estado: str = "EXITOSO",
):
    """Guarda un log inmutable en DynamoDB con llaves PK, SK y GSI1."""
    ahora = datetime.now(timezone.utc)
    iso_ts = ahora.isoformat()
    mes = ahora.strftime("%Y-%m")
    event_id = str(uuid.uuid4())[:8]

    # Asegurar que detalle tenga la estructura mínima requerida para auditoría fiscal
    detalle_sanitizado = sanitize_for_dynamodb(detalle)

    dynamo_table.put_item(
        Item={
            "PK": f"AUDIT#{mes}",
            "SK": f"EVENT#{iso_ts}#{event_id}",
            "GSI1PK": "TYPE#AUDIT",
            "GSI1SK": f"USER#{id_usuario}#{iso_ts}",
            "id_usuario": id_usuario,
            "accion": accion,
            "estado": estado,
            "detalle": detalle_sanitizado,
            "timestamp": iso_ts,
        }
    )


# ============================================================================
# 4. CONTROL DE IDEMPOTENCIA (Tabla facturacion_idempotencia)
# ============================================================================
def verificar_idempotencia(idempotency_key: str) -> Optional[Dict[str, Any]]:
    """Consulta si una llave de idempotencia ya fue procesada o está en curso."""
    if not idempotency_key:
        return None
    try:
        resp = idempotency_table.get_item(Key={"idempotency_key": idempotency_key}, ConsistentRead=True)
        return resp.get("Item")
    except ClientError as e:
        print(f"[WARN] Error consultando idempotencia ({idempotency_key}): {e}")
        return None


def iniciar_idempotencia(
    idempotency_key: str,
    operacion: str,
    id_usuario: int,
    request_payload: Dict[str, Any],
    ttl_seconds: int = 86400,
) -> bool:
    """
    Registra atómicamente la llave en estado 'EN_PROCESO'.
    Retorna True si la llave es nueva; False si ya existía (colisión o reintento concurrente).
    """
    if not idempotency_key:
        return True

    ahora = datetime.now(timezone.utc).isoformat()
    item = {
        "idempotency_key": idempotency_key,
        "operacion": operacion,
        "id_usuario": id_usuario,
        "estado": "EN_PROCESO",
        "timestamp": ahora,
        "request_payload": sanitize_for_dynamodb(request_payload),
        "ttl": int(time.time()) + ttl_seconds,
    }

    try:
        idempotency_table.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(idempotency_key)",
        )
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return False
        print(f"[ERROR] Error al registrar inicio de idempotencia: {e}")
        return False


def completar_idempotencia(
    idempotency_key: str,
    estado: str,
    response_data: Dict[str, Any],
):
    """Actualiza el estado de la llave a 'COMPLETADO' o 'FALLIDO' y almacena la respuesta generada."""
    if not idempotency_key:
        return

    ahora = datetime.now(timezone.utc).isoformat()
    sanitized_resp = sanitize_for_dynamodb(response_data)

    try:
        idempotency_table.update_item(
            Key={"idempotency_key": idempotency_key},
            UpdateExpression="SET estado = :est, response_data = :resp, finalizado_en = :fin",
            ExpressionAttributeValues={
                ":est": estado,
                ":resp": sanitized_resp,
                ":fin": ahora,
            },
        )
    except ClientError as e:
        print(f"[ERROR] Error al completar idempotencia ({idempotency_key}): {e}")
