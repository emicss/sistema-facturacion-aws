from enum import Enum
from typing import Any, Dict, Optional


class TipoEvento(str, Enum):
    LOGIN = "LOGIN"
    LOGOUT = "LOGOUT"
    CREAR_USUARIO = "CREAR_USUARIO"
    EMISION_FACTURA = "EMISION_FACTURA"
    CANCELACION_FACTURA = "CANCELACION_FACTURA"
    PAGO_PARCIAL = "PAGO_PARCIAL"
    PAGO_TOTAL = "PAGO_TOTAL"
    CAMBIO_TARIFA = "CAMBIO_TARIFA"
    ASIGNACION_MASIVA = "ASIGNACION_MASIVA"
    CONSULTA_REPORTE = "CONSULTA_REPORTE"
    ERROR_SISTEMA = "ERROR_SISTEMA"


class EstadoEvento(str, Enum):
    EXITOSO = "EXITOSO"
    PENDIENTE = "PENDIENTE"
    FALLIDO = "FALLIDO"
    CANCELADO = "CANCELADO"


def construir_detalle_evento(
    folio: Optional[str] = None,
    emisor: Optional[str] = "CloudTech Systems S.A. de C.V.",
    receptor: Optional[str] = None,
    monto: Optional[float] = None,
    estado: Optional[str] = None,
    metadatos: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    Estandariza el objeto 'detalle' para los eventos en DynamoDB, garantizando
    consistencia para auditoría fiscal, conciliación de pagos y trazabilidad.
    """
    detalle = {
        "folio": folio or "N/A",
        "emisor": emisor or "CloudTech Systems S.A. de C.V.",
        "receptor": receptor or "N/A",
        "monto": f"{monto:.2f}" if monto is not None else "0.00",
        "estado": estado or EstadoEvento.EXITOSO.value,
    }
    if metadatos:
        detalle.update(metadatos)
    return detalle
