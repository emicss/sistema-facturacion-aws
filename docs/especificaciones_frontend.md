# Especificaciones Técnicas y Funcionales para el Frontend
**Proyecto:** Sistema Cloud Híbrido de Facturación, Catálogo de Servicios y Auditoría Fiscal (AWS)  
**Destinatarios:** Equipo de desarrollo Frontend  
**Backend:** FastAPI + Mangum desplegado en AWS Lambda & API Gateway  
**Bases de Datos:** Amazon RDS MySQL 8.0 (10 SPs) + Amazon DynamoDB (Eventos, Carrito e Idempotencia)

---

## 1. Visión General del Frontend

El frontend debe ser una aplicación web moderna (SPA o estática) que permita a los usuarios autenticarse, consultar el catálogo técnico de servicios en la nube, gestionar un carrito temporal en DynamoDB, emitir facturas fiscales timbradas, registrar pagos con recálculo automático de saldos, consultar reportes fiscales y auditar eventos inmutables.

### Entorno de Conexión
* **Endpoint Base de la API (AWS API Gateway):**  
  `https://bvw7s0kuu6.execute-api.us-east-1.amazonaws.com`
* **Protocolo:** Exclusivamente **HTTPS (puerto 443)**.
* **CORS:** Ya habilitado en el backend para cualquier origen (`*`).
* **Regla de Alojamiento:** La aplicación final debe compilarse a archivos estáticos (HTML/CSS/JS) para poder alojarse en un bucket **Amazon S3** con *Static Website Hosting* o en **CloudFront**. No debe requerir un servidor Node.js corriendo 24/7 en producción.

---

## 2. Autenticación y Control de Acceso Basado en Roles (RBAC)

### Flujo de Sesión
1. **Login:** `POST /auth/login` con `{ "email": "...", "password": "..." }`.
2. **Respuesta:** Devuelve `access_token` (JWT), `token_type: "bearer"` y el objeto `usuario` (`id_usuario`, `nombre_completo`, `email`, `rol`).
3. **Persistencia:** Guardar el token en `sessionStorage` o `localStorage`.
4. **Cabecera Obligatoria:** Todas las peticiones posteriores deben incluir:
   ```http
   Authorization: Bearer <access_token>
   ```
5. **Fuente de Verdad:** La identidad y roles residen **exclusivamente en RDS MySQL**. No se debe simular gestión de usuarios en el cliente.

### Matriz de Permisos por Rol

| Módulo / Acción | ADMIN | CONTADOR | OPERADOR | CLIENTE |
| :--- | :---: | :---: | :---: | :---: |
| **Ver Catálogo y 50 características** |  |  |  |  |
| **Gestionar Carrito (DynamoDB)** |  |  |  |  |
| **SP 10: Cambio de Tarifas** |  |  | ❌ | ❌ |
| **SP 9: Asignación Masiva** |  | ❌ | ❌ | ❌ |
| **SP 1,2,3,8: Emitir Facturas** |  | ❌ |  | ❌ |
| **SP 6: Registrar Pagos** |  |  | ❌ | ❌ |
| **SP 4: Cancelar Facturas** |  |  | ❌ | ❌ |
| **SP 5 y 7: Reportes Fiscales** |  |  | ❌ | ❌ |
| **Auditoría Inmutable (DynamoDB)** |  |  | ❌ | ❌ |
| **Registrar Nuevos Usuarios** |  | ❌ | ❌ | ❌ |

---

## 3. Requerimientos Críticos de Integración (Criterios de Evaluación)

### A. Control Estricto de Idempotencia (Obligatorio)
Para evitar cobros dobles o duplicidad de folios fiscales por dobles clics o fallas de red:
1. En cada intento de **Emisión de Factura** (`POST /facturas/emitir`) y **Registro de Pago** (`POST /facturas/{id}/pagos`), el frontend **DEBE enviar una cabecera HTTP con un UUID único**:
   ```http
   Idempotency-Key: c9b8e21a-4d76-47b2-9a3b-28f09d8e7123
   ```
2. Generar este identificador al momento de enviar el formulario usando:
   ```javascript
   const idempotencyKey = crypto.randomUUID();
   ```
3. Si el usuario reintenta la misma petición o el backend devuelve `"idempotente": true`, la interfaz debe notificar visualmente:
   > *"Esta transacción ya había sido procesada previamente. Mostrando el comprobante original sin duplicar cargos."*

---

### B. Visualización de las 50 Características de `Servicios`
La tabla `Servicios` en RDS cuenta con **exactamente 50 columnas**. El frontend no debe saturar la tabla principal con 50 columnas horizontales; debe diseñarse con una vista resumida y un **Detalle Expandido / Modal / Drawer**:

* **Vista Resumida (Tabla principal):**
  * `codigo_interno` (ej. `SRV-001`)
  * `nombre_servicio`
  * `categoria` (badge con color)
  * `precio_unitario` (formato moneda `$ MXN`)
  * Botones de acción: `[+ Carrito]`, `[Ver 50 Características]`, `[Ajustar Tarifa (SP10)]`.

* **Vista Detallada (Al presionar "Ver 50 Características" - `GET /servicios/{id}`):**
  Organizar los 50 campos en pestañas o acordeones temáticos:
  1. **Infraestructura Cloud:** `region_aws_default`, `arquitectura_cpu`, `memoria_ram_gb`, `vcpus`, `almacenamiento_gb`, `tipo_almacenamiento`, `ancho_banda_gbps`, `ip_publica_dedicada`, `version_software`, `tiempo_aprovisionamiento_min`.
  2. **SLA y Resiliencia:** `sla_disponibilidad_porc`, `tiempo_respuesta_soporte_hrs`, `soporte_24_7`, `nivel_soporte`, `multiaz_habilitado`, `backup_automatico_horas`, `rpo_minutos`, `rto_minutos`.
  3. **Seguridad y Normativa:** `cifrado_en_reposo`, `algoritmo_cifrado`, `cifrado_en_transito`, `cumplimiento_pci_dss`, `cumplimiento_iso27001`, `cumplimiento_soc2`, `retencion_logs_dias`, `waf_incluido`.
  4. **Comercial y Fiscal:** `moneda`, `tipo_facturacion`, `ciclo_cobro`, `descuento_maximo_porc`, `plazo_minimo_meses`, `penalizacion_cancelacion_porc`, `objeto_impuesto_sat`, `unidad_medida_sat`, `costo_operativo_estimado`, `clave_prod_serv_sat`, `clave_unidad_sat`.
  5. **Operación y Métricas:** `margen_ganancia_porc`, `consumo_kwh_estimado`, `limite_peticiones_mes`, `responsable_tecnico`, `activo`.

---

### C. Mapeo Visual de los 10 Procedimientos Almacenados (SPs)
La interfaz debe reflejar claramente el resultado de cada SP ejecutado en RDS:

| SP en Base de Datos | Nombre y Propósito | Componente en Frontend |
| :---: | :--- | :--- |
| **SP 1** | `sp_generar_folio_factura` (Folios atómicos) | Muestra el folio asignado (ej. `FAC-1002`). |
| **SP 2** | `sp_calcular_impuestos_factura` (IVA y Retenciones) | Desglose en el resumen de factura (Subtotal, IVA 16%, Retenciones). |
| **SP 3** | `sp_aplicar_descuento` (Reglas de volumen y cliente) | Muestra el ahorro obtenido según el nivel del cliente (`VIP`, `ORO`, etc.). |
| **SP 4** | `sp_cancelar_factura` (Cancelación y reversión) | Botón "Cancelar Factura" con modal para ingresar motivo fiscal. |
| **SP 5** | `sp_cierre_fiscal_consolidado` (Cierre por fechas) | Selector de rango de fechas y tabla resumen con totales facturados y cobrados. |
| **SP 6** | `sp_validar_estado_pago` (Conciliación de saldo) | Formulario de abono (SPEI/Tarjeta) y badge dinámico (`PAGADA`, `PARCIAL`, `PENDIENTE`). |
| **SP 7** | `sp_reporte_antiguedad_saldos` (Cartera vencida) | Vista de cartera clasificada en buckets: Corriente, 1-30 días, 31-60 días, 90+ días. |
| **SP 8** | `sp_generar_estructura_timbrado` (CFDI 4.0 JSON) | Modal con visor de JSON timbrado y botón para copiar al portapapeles. |
| **SP 9** | `sp_asignar_caracteristicas_masivas` (Config por lote) | Formulario para aplicar un parámetro a toda una categoría. |
| **SP 10** | `sp_auditar_cambio_tarifa` (Auditoría de precios) | Modal para actualizar precio con motivo auditado. |

---

### D. Interacción con Amazon DynamoDB
1. **Carrito Temporal (`FacturacionEventos` con PK `CART#<id_usuario>`):**
   - Debe actualizarse dinámicamente al agregar o remover items.
   - Mostrar indicador de cantidad en la cabecera.
   - Opción para vaciar carrito o facturar directo desde el carrito.
2. **Auditoría Inmutable (`FacturacionEventos` con GSI1 `TYPE#AUDIT`):**
   - Tabla paginada con fecha/hora UTC localizable, usuario, acción (`LOGIN`, `EMISION_FACTURA`, `PAGO_PARCIAL`, etc.), estado (`EXITOSO`, `FALLIDO`, `CANCELADO`) y visor del objeto `detalle` canónico (`folio`, `emisor`, `receptor`, `monto`).

---

## 4. Hoja de Referencia de Endpoints del Backend

| Endpoint | Método | Auth Requerida | Headers Especiales | Descripción |
| :--- | :---: | :---: | :--- | :--- |
| `/health` | `GET` | No | - | Estado de RDS, DynamoDB y tabla de Idempotencia. |
| `/auth/login` | `POST` | No | - | Autenticación con email/password. Devuelve JWT. |
| `/auth/register` | `POST` | ADMIN | - | Registro de nuevos usuarios en RDS. |
| `/servicios` | `GET` | Sí | - | Lista servicios (filtros: `?categoria=Cloud Computing&limit=50`). |
| `/servicios/{id}` | `GET` | Sí | - | Devuelve **todas las 50 columnas** de un servicio. |
| `/clientes` | `GET` | ADMIN, CONTADOR, OPERADOR | - | Lista clientes y sus niveles de descuento. |
| `/carrito` | `GET` | Sí | - | Obtiene los items del carrito temporal en DynamoDB. |
| `/carrito/items` | `POST` | Sí | - | Agrega un servicio al carrito temporal (`id_servicio`, `cantidad`). |
| `/carrito/items/{id}` | `DELETE` | Sí | - | Elimina un item del carrito temporal. |
| `/facturas/emitir` | `POST` | ADMIN, OPERADOR | `Idempotency-Key` | Emite y timbra factura (SP 1, 2, 3, 8). |
| `/facturas` | `GET` | Sí | - | Lista las últimas 50 facturas emitidas con saldos. |
| `/facturas/{id}/timbrado`| `GET` | Sí | - | Devuelve el comprobante CFDI JSON (SP 8). |
| `/facturas/{id}/pagos` | `POST` | ADMIN, CONTADOR | `Idempotency-Key` | Aplica un pago y recalcula saldo (SP 6). |
| `/facturas/{id}/cancelar`| `POST` | ADMIN, CONTADOR | - | Cancela factura con motivo (SP 4). |
| `/servicios/{id}/tarifa` | `PUT` | ADMIN, CONTADOR | - | Actualiza precio y audita cambio (SP 10). |
| `/servicios/asignar-caracteristicas-masivas` | `POST` | ADMIN | - | Asignación masiva por categoría (SP 9). |
| `/reportes/cierre-fiscal` | `GET` | ADMIN, CONTADOR | - | Reporte consolidado (`?fecha_inicio=YYYY-MM-DD&fecha_fin=YYYY-MM-DD`). |
| `/reportes/antiguedad-saldos` | `GET` | ADMIN, CONTADOR | - | Reporte de cartera vencida (SP 7). |
| `/auditoria/eventos` | `GET` | ADMIN, CONTADOR | - | Lista logs inmutables desde DynamoDB GSI1. |

---

## 5. Cuentas de Prueba Preconfiguradas en Base de Datos

Todas las cuentas comparten la contraseña maestra: `CloudTech2026!`

* **ADMIN:** `admin@cloudtech.mx` (Acceso total al sistema)
* **CONTADOR:** `contabilidad@cloudtech.mx` (Facturación, Pagos, Cancelación, Reportes y Auditoría)
* **OPERADOR:** `operaciones@cloudtech.mx` (Catálogo, Carrito y Emisión)
* **CLIENTE:** `cliente@constructora.mx` (Catálogo y Consulta)

---

## 6. Entregables Esperados de las Propuestas

1. **Diseño Visual & UX:**
   - Tema moderno (modo oscuro o claro profesional, estilo consola Cloud tipo AWS / Vercel / Stripe).
   - *Feedback* visual claro para operaciones asíncronas (Loaders, Toasts de éxito/error, avisos de idempotencia).
2. **Estructura de Código:**
   - Modular y desacoplado (servicios API separados de la vista).
   - Manejo centralizado de tokens JWT y expiración (redirección a login ante 401).
   - Generación automática de `Idempotency-Key` mediante UUID v4 en emisión y pagos.
3. **Instrucciones de Despliegue:**
   - Un solo comando de build (`npm run build` o archivo estático listo para servir).
   - Variable de entorno o archivo de configuración para cambiar la URL base de API Gateway sin tocar código fuente.
