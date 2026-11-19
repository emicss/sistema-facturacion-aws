import os
import uuid
from datetime import datetime, timezone
import pymysql
import boto3
from dotenv import load_dotenv

load_dotenv()

# Conexión a Amazon RDS (MySQL 8.0)
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

# Conexión a Amazon DynamoDB (usa automáticamente LabRole vía IMDS en EC2)
dynamodb = boto3.resource("dynamodb", region_name=os.getenv("AWS_REGION", "us-east-1"))
dynamo_table = dynamodb.Table(os.getenv("DYNAMO_TABLE", "FacturacionEventos"))

def registrar_auditoria(id_usuario: int, accion: str, detalle: dict):
    """Guarda un log inmutable en DynamoDB con llaves PK, SK y GSI1."""
    ahora = datetime.now(timezone.utc)
    iso_ts = ahora.isoformat()
    mes = ahora.strftime("%Y-%m")
    event_id = str(uuid.uuid4())[:8]

    dynamo_table.put_item(
        Item={
            "PK": f"AUDIT#{mes}",
            "SK": f"EVENT#{iso_ts}#{event_id}",
            "GSI1PK": "TYPE#AUDIT",
            "GSI1SK": f"USER#{id_usuario}#{iso_ts}",
            "id_usuario": id_usuario,
            "accion": accion,
            "detalle": detalle,
            "timestamp": iso_ts,
        }
    )

