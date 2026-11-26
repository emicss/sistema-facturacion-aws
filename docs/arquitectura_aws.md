# Arquitectura Cloud y Separación de Responsabilidades: RDS vs DynamoDB

## 1. Visión General del Sistema Híbrido

El sistema de facturación y servicios opera bajo una **arquitectura híbrida en la nube de AWS** que combina las fortalezas del modelo relacional ACID con el modelo NoSQL de alta concurrencia y baja latencia.

```
                              ┌─────────────────────────────────────────┐
                              │            Amazon API Gateway           │
                              │          (HTTPS / Puerto 443)           │
                              └────────────────────┬────────────────────┘
                                                   │ Proxy
                                                   ▼
                              ┌─────────────────────────────────────────┐
                              │               AWS Lambda                │
                              │         (FastAPI + ASGI Mangum)         │
                              └────────────┬───────────────┬────────────┘
                                           │               │
                     Consultas ACID / SPs  │               │ Operaciones NoSQL / SDK Boto3
                                           ▼               ▼
                      ┌──────────────────────┐   ┌──────────────────────────────┐
                      │   Amazon RDS MySQL   │   │       Amazon DynamoDB        │
                      │ facturacion_cloud_db │   │ • FacturacionEventos         │
                      │                      │   │ • facturacion_idempotencia   │
                      │ (Fuente de Verdad)   │   │ (Eventos, Carrito & Idem)    │
                      └──────────────────────┘   └──────────────────────────────┘
```

---

## 2. Decisión Arquitectónica: Fuente Única de Verdad (Single Source of Truth)

### Problema Identificado:
Tener registros maestros o réplicas de usuarios tanto en Amazon RDS (`Usuarios_Roles`) como en DynamoDB (`USER#<id>`) genera **riesgo crítico de desincronización (Split-Brain)**:
1. Si un administrador revoca permisos o desactiva a un usuario en RDS, la sesión o perfil en DynamoDB podría seguir activa permitiendo acciones indebidas.
2. La duplicidad viola el principio de diseño de base de datos relacional de integridad referencial para roles, auditorías fiscales y llaves foráneas en facturas (`id_usuario_registro`, `id_cliente`).

### Resolución Aplicada:
* **Amazon RDS MySQL (`facturacion_cloud_db`) es la ÚNICA FUENTE DE VERDAD** para:
  - Usuarios, contraseñas hasheadas (bcrypt) y roles (RBAC: `ADMIN`, `CONTADOR`, `OPERADOR`, `CLIENTE`).
  - Clientes fiscales, direcciones, regímenes fiscales y políticas de crédito/descuento.
  - Catálogo denso de **50 características técnicas y fiscales** de Servicios Cloud.
  - Procedimientos almacenados transaccionales (SPs 1 al 10), cabeceras de facturas, detalles timbrados y saldos de pagos.
* **Amazon DynamoDB queda estrictamente delimitado** a:
  - **Auditoría inmutable y cumplimiento fiscal (`FacturacionEventos`):** Almacenamiento append-only particionado por mes (`AUDIT#YYYY-MM`) y consultable por índice secundario global (`GSI1_Tipo_Fecha`).
  - **Carrito temporal de compra:** Almacenamiento efímero (`CART#<id_usuario>`) con tiempo de vida (TTL) para armar facturas antes de su emisión transaccional.
  - **Control de Idempotencia (`facturacion_idempotencia`):** Bloqueo transaccional contra peticiones duplicadas o reintentos de red al emitir facturas y registrar abonos.

---

## 3. Matriz de Responsabilidades y Persistencia

| Dominio de Información | Servicio AWS | Motor / Tabla | Justificación Técnica |
| :--- | :--- | :--- | :--- |
| **Identidad, Credenciales y RBAC** | Amazon RDS | `Usuarios_Roles` | Cumplimiento ACID, llaves únicas por email, integridad referencial y prevención de sesiones huérfanas. |
| **Clientes y Reglas Comerciales** | Amazon RDS | `Clientes`, `Impuestos_Historico` | Relaciones 1:N con facturas y vigencias fiscales de IVA/retenciones. |
| **Catálogo de Servicios (50 Campos)** | Amazon RDS | `Servicios` | Consultas filtradas por categoría, precio, SLA, ordenamiento y consistencia relacional. |
| **Emisión, Timbrado y Folios** | Amazon RDS | `Facturas`, `Detalle_Factura`, `Series_Folios` | Bloqueo pesimista y procedimientos almacenados (SPs 1, 2, 3, 4, 8). |
| **Conciliación de Saldos y Pagos** | Amazon RDS | `Pagos` | Recálculo atómico de saldos mediante SP 6. |
| **Auditoría Inmutable y Trazabilidad** | Amazon DynamoDB | `FacturacionEventos` | Alta tasa de escritura append-only sin sobrecargar la base de datos relacional; consultas rápidas vía GSI1. |
| **Carrito Temporal de Usuario** | Amazon DynamoDB | `FacturacionEventos` (`CART#`) | Clave-valor ultrarrápido con limpieza automática post-facturación. |
| **Idempotencia de Facturación y Pagos** | Amazon DynamoDB | `facturacion_idempotencia` | `put_item` condicional atómico para evitar cargos duplicados ante reintentos de red. |

---

## 4. Garantía de Seguridad y Tokens

1. Durante el `/auth/login`, las credenciales se validan exclusivamente contra RDS MySQL con `verify_password(hash)`.
2. Se emite un JWT firmado (`HS256`) que viaja en la cabecera `Authorization: Bearer <token>`.
3. Cada endpoint verifica la firma del token y su vigencia (120 minutos) de forma *stateless* y descentralizada, garantizando que el rol no dependa de escrituras redundantes en DynamoDB.
