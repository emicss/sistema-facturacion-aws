# Catálogo Centralizado de Tipos de Eventos y Estados del Sistema

Este documento describe la especificación formal del modelo de eventos y auditoría inmutable persistido en **Amazon DynamoDB (`FacturacionEventos`)** y del control de estado transaccional en **`facturacion_idempotencia`**.

---

## 1. Catálogo de Estados (`EstadoEvento`)

Cada operación registrada en el sistema se etiqueta con uno de los siguientes cuatro estados normalizados:

| Estado | Significado Técnico | Comportamiento en el Backend |
| :--- | :--- | :--- |
| **`EXITOSO`** | La operación se completó en su totalidad cumpliendo validaciones de negocio y persistencia en RDS. | Se confirma la transacción en MySQL y se almacena la respuesta final. |
| **`PENDIENTE`** | La operación ha sido recibida y se encuentra bloqueada en procesamiento concurrente (bloqueo de idempotencia). | Registrado en `facturacion_idempotencia` como `EN_PROCESO` para evitar carreras de peticiones simultáneas. |
| **`FALLIDO`** | La operación fue rechazada por error de validación, excepción SQL, saldo insuficiente o violación de regla. | Se ejecuta `conn.rollback()` en MySQL y se guarda el log del error con trazabilidad. |
| **`CANCELADO`** | La entidad (factura o comprobante) fue revertida formalmente mediante procedimiento fiscal (SP 4). | Cancela el folio fiscal SAT, revierte saldos contables y emite evento de auditoría inmutable. |

---

## 2. Catálogo de Tipos de Eventos (`TipoEvento`)

| Tipo de Evento (`accion`) | Endpoint que lo Dispara | Método HTTP | Roles Autorizados (RBAC) | Estructura del Objeto `detalle` en DynamoDB |
| :--- | :--- | :---: | :--- | :--- |
| **`LOGIN`** | `/auth/login` | `POST` | Público (Cualquiera con credenciales) | `{"folio": "N/A", "emisor": "CloudTech Systems S.A. de C.V.", "receptor": "<email>", "monto": "0.00", "estado": "EXITOSO", "rol": "<ROL>"}` |
| **`CREAR_USUARIO`** | `/auth/register` | `POST` | `ADMIN` | `{"folio": "N/A", "emisor": "CloudTech Systems S.A. de C.V.", "receptor": "<nuevo_email>", "monto": "0.00", "estado": "EXITOSO", "nuevo_id": 5, "rol": "<ROL>"}` |
| **`EMISION_FACTURA`** | `/facturas/emitir` | `POST` | `ADMIN`, `OPERADOR` | `{"folio": "FAC-1001", "emisor": "CloudTech Systems S.A. de C.V.", "receptor": "<id_cliente>", "monto": "12500.00", "estado": "EXITOSO", "id_factura": 1, "serie": "FAC"}` |
| **`CANCELACION_FACTURA`** | `/facturas/{id}/cancelar` | `POST` | `ADMIN`, `CONTADOR` | `{"folio": "FAC-ID#1", "emisor": "CloudTech Systems S.A. de C.V.", "receptor": "Cancelación Fiscal SAT", "monto": "0.00", "estado": "CANCELADO", "id_factura": 1, "motivo": "<motivo>"}` |
| **`PAGO_PARCIAL`** | `/facturas/{id}/pagos` | `POST` | `ADMIN`, `CONTADOR` | `{"folio": "FAC-1001", "emisor": "CloudTech Systems S.A. de C.V.", "receptor": "Factura #1", "monto": "5000.00", "estado": "EXITOSO", "saldo_restante": "7500.00", "referencia": "SPEI-123456"}` |
| **`PAGO_TOTAL`** | `/facturas/{id}/pagos` | `POST` | `ADMIN`, `CONTADOR` | `{"folio": "FAC-1001", "emisor": "CloudTech Systems S.A. de C.V.", "receptor": "Factura #1", "monto": "7500.00", "estado": "EXITOSO", "saldo_restante": "0.00", "referencia": "SPEI-789012"}` |
| **`CAMBIO_TARIFA`** | `/servicios/{id}/tarifa` | `PUT` | `ADMIN`, `CONTADOR` | `{"folio": "N/A", "emisor": "CloudTech Systems S.A. de C.V.", "receptor": "Servicio #1", "monto": "2500.00", "estado": "EXITOSO", "id_servicio": 1, "motivo": "<motivo>"}` |
| **`ASIGNACION_MASIVA`** | `/servicios/asignar-caracteristicas-masivas` | `POST` | `ADMIN` | `{"folio": "N/A", "emisor": "CloudTech Systems S.A. de C.V.", "receptor": "<categoria>", "monto": "0.00", "estado": "EXITOSO", "id_caracteristica": 2, "valor": "<valor>"}` |
| **`CONSULTA_REPORTE`** | `/reportes/cierre-fiscal`<br>`/reportes/antiguedad-saldos` | `GET` | `ADMIN`, `CONTADOR` | `{"folio": "N/A", "emisor": "CloudTech Systems S.A. de C.V.", "receptor": "Auditoría Interna", "monto": "0.00", "estado": "EXITOSO", "reporte": "sp_cierre_fiscal_consolidado"}` |
| **`ERROR_SISTEMA`** | Capturador global de excepciones | `ALL` | N/A | `{"folio": "N/A", "emisor": "CloudTech Systems S.A. de C.V.", "receptor": "Soporte TI", "monto": "0.00", "estado": "FALLIDO", "error": "<mensaje_error>"}` |

---

## 3. Estructura Estándar de Almacenamiento en DynamoDB

### Tabla: `FacturacionEventos`
* **Partition Key (`PK`):** `AUDIT#YYYY-MM` (Particionado por mes fiscal para consultas archivables).
* **Sort Key (`SK`):** `EVENT#<ISO_TIMESTAMP>#<UUID>` (Ordenamiento cronológico y unicidad de evento).
* **Global Secondary Index (`GSI1`):**
  - **GSI1PK:** `TYPE#AUDIT`
  - **GSI1SK:** `USER#<id_usuario>#<ISO_TIMESTAMP>`
* **Atributos:**
  - `id_usuario` (Number)
  - `accion` (String - Valor de `TipoEvento`)
  - `estado` (String - Valor de `EstadoEvento`)
  - `timestamp` (String ISO 8601 UTC)
  - `detalle` (Map con `folio`, `emisor`, `receptor`, `monto`, `estado` y metadatos complementarios).

### Tabla: `facturacion_idempotencia`
* **Partition Key (`idempotency_key`):** `String` (UUID o Hash provisto en el header `Idempotency-Key`).
* **Atributos:**
  - `operacion` (`EMITIR_Y_TIMBRAR_FACTURA` o `REGISTRAR_PAGO`)
  - `id_usuario` (Number)
  - `estado` (`EN_PROCESO`, `COMPLETADO`, `FALLIDO`)
  - `timestamp` (String ISO 8601 UTC)
  - `ttl` (Number epoch - 24 horas para expirar llaves resueltas)
  - `request_payload` (Map con la entrada recibida)
  - `response_data` (Map con la respuesta idéntica generada para replay)
  - `finalizado_en` (String ISO 8601 UTC)

---

## 4. Guía para la Defensa ante el Profesor

1. **¿Por qué centralizar en un Enum?**
   Evita valores mágicos (`magic strings`), previene discrepancias de sintaxis y permite que los filtros del GSI1 y los dashboards de auditoría consuman claves consistentes.
2. **¿Qué información contiene el objeto `detalle`?**
   Siempre garantiza los 5 campos canónicos: `folio`, `emisor`, `receptor`, `monto` y `estado`, complementados con los metadatos específicos del endpoint.
3. **¿Cómo se previene la facturación doble?**
   Mediante la tabla `facturacion_idempotencia` con un `put_item` condicional `attribute_not_exists(idempotency_key)` que actúa como cerrojo distribuido. Si la petición ya fue procesada, el backend devuelve la factura original sin volver a ejecutar los Stored Procedures ni incrementar folios.
