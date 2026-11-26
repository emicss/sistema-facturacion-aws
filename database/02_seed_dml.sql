-- ============================================================================
-- PROYECTO C: SISTEMA DE FACTURACIÓN Y SERVICIOS (AWS RDS - MySQL 8.0)
-- Archivo: /database/02_seed_dml.sql
-- Descripción: Carga inicial (DML) de usuarios, clientes, impuestos, folios,
--              100 servicios y 50 características configurables.
-- ============================================================================

USE facturacion_cloud_db;

-- 1. USUARIOS Y ROLES (RBAC)
-- Nota: Los hashes corresponden a bcrypt de ejemplo; en el backend se validan con bcrypt/Argon2.
INSERT INTO Usuarios_Roles (nombre_completo, email, password_hash, rol, activo) VALUES
('Administrador General', 'admin@cloudtech.mx', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyY2qK3.Q7W2', 'ADMIN', TRUE),
('Laura Méndez (Contadora)', 'contabilidad@cloudtech.mx', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyY2qK3.Q7W2', 'CONTADOR', TRUE),
('Carlos Ruiz (Operador)', 'operaciones@cloudtech.mx', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyY2qK3.Q7W2', 'OPERADOR', TRUE),
('Portal Cliente Demo', 'cliente@constructora.mx', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyY2qK3.Q7W2', 'CLIENTE', TRUE);

-- 2. CLIENTES FISCALES (Diferentes niveles de descuento y días de crédito)
INSERT INTO Clientes (rfc, razon_social, regimen_fiscal, codigo_postal, email_facturacion, nivel_descuento, porcentaje_descuento, dias_credito) VALUES
('CSUR980115AB1', 'Constructora del Sur S.A. de C.V.', '601', '62000', 'facturas@constructorasur.mx', 'VIP', 15.00, 45),
('LOGM050420CD2', 'Logística Morelos S. de R.L.', '601', '62760', 'pagos@logisticamorelos.mx', 'ORO', 10.00, 30),
('TIND120810EF3', 'Tecnología Industrial del Centro S.A.', '601', '06600', 'cuentas@tecindustrial.mx', 'PLATA', 5.00, 15),
('GARC850322GH4', 'Roberto García Morales', '612', '62210', 'rgarcia@consultoria.mx', 'ESTANDAR', 0.00, 0),
('FINA191105IJ5', 'Financiera Azteca Digital S.A.P.I.', '601', '01210', 'tesoreria@finazteca.mx', 'VIP', 15.00, 60);

-- 3. IMPUESTOS HISTÓRICO (Tasas fiscales vigentes y anteriores)
INSERT INTO Impuestos_Historico (codigo_impuesto, descripcion, tasa_iva, tasa_retencion_isr, tasa_retencion_iva, fecha_inicio_vigencia, fecha_fin_vigencia, es_vigente) VALUES
('MX-2025-GEN', 'Régimen General México 2025 (Histórico)', 0.1600, 0.1000, 0.1067, '2025-01-01', '2025-12-31', FALSE),
('MX-2026-GEN', 'Régimen General México 2026 (Vigente)', 0.1600, 0.1000, 0.1067, '2026-01-01', NULL, TRUE),
('MX-2026-FRON', 'Zona Fronteriza Norte 2026 (IVA 8%)', 0.0800, 0.1000, 0.0533, '2026-01-01', NULL, TRUE);

-- 4. SERIES Y FOLIOS (Base para SP1: Generación atómica de folios)
INSERT INTO Series_Folios (serie, descripcion, folio_actual) VALUES
('FAC', 'Facturación General de Servicios', 1000),
('HON', 'Recibos de Honorarios y Consultoría', 500),
('NC', 'Notas de Crédito y Reversiones', 100);

-- 5. CATÁLOGO DE 100 SERVICIOS (Generación sintética con 50 columnas estructuradas en 10 categorías)
INSERT INTO Servicios (
    codigo_interno, clave_prod_serv_sat, clave_unidad_sat,
    nombre_servicio, descripcion, categoria,
    region_aws_default, arquitectura_cpu, memoria_ram_gb, vcpus, almacenamiento_gb,
    tipo_almacenamiento, ancho_banda_gbps, ip_publica_dedicada, version_software, tiempo_aprovisionamiento_min,
    sla_disponibilidad_porc, tiempo_respuesta_soporte_hrs, soporte_24_7, nivel_soporte,
    multiaz_habilitado, backup_automatico_horas, rpo_minutos, rto_minutos,
    cifrado_en_reposo, algoritmo_cifrado, cifrado_en_transito, cumplimiento_pci_dss,
    cumplimiento_iso27001, cumplimiento_soc2, retencion_logs_dias, waf_incluido,
    precio_unitario, moneda, tipo_facturacion, ciclo_cobro, descuento_maximo_porc,
    plazo_minimo_meses, penalizacion_cancelacion_porc, objeto_impuesto_sat, unidad_medida_sat,
    costo_operativo_estimado, aplica_retencion, margen_ganancia_porc, consumo_kwh_estimado,
    limite_peticiones_mes, responsable_tecnico, activo
)
WITH RECURSIVE seq(n) AS (
    SELECT 1
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 100
)
SELECT
    CONCAT('SRV-', LPAD(n, 3, '0')) AS codigo_interno,
    CASE (n % 5)
        WHEN 0 THEN '81112000' -- Servicios de datos / nube
        WHEN 1 THEN '81111500' -- Ingeniería de software
        WHEN 2 THEN '81111800' -- Administración de sistemas
        WHEN 3 THEN '81112200' -- Mantenimiento de software
        ELSE '80101500'        -- Consultoría de negocios TI
    END AS clave_prod_serv_sat,
    'E48' AS clave_unidad_sat,
    CONCAT(
        ELT((n % 10) + 1,
            'Infraestructura Cloud', 'Ciberseguridad', 'Bases de Datos', 'Desarrollo Web',
            'DevOps & CI/CD', 'Analítica & BI', 'Soporte Técnico', 'Auditoría TI',
            'Redes & VPN', 'Inteligencia Artificial'
        ),
        ' - Nivel ',
        ELT((n % 4) + 1, 'Básico', 'Estándar', 'Empresarial', 'Dedicado'),
        ' #', LPAD(n, 3, '0')
    ) AS nombre_servicio,
    CONCAT('Servicio administrado de tecnología y cumplimiento operativo código SRV-', LPAD(n, 3, '0')) AS descripcion,
    ELT((n % 10) + 1,
        'Cloud Computing', 'Ciberseguridad', 'Bases de Datos', 'Desarrollo',
        'DevOps', 'Analítica', 'Soporte', 'Auditoría', 'Redes', 'IA y Datos'
    ) AS categoria,

    -- Infraestructura y Cómputo Cloud
    ELT((n % 4) + 1, 'us-east-1', 'us-west-2', 'sa-east-1', 'eu-west-1') AS region_aws_default,
    CASE
        WHEN (n % 10) + 1 IN (1, 3) THEN 'arm64_graviton'
        WHEN (n % 10) + 1 IN (5, 10) THEN 'x86_64'
        ELSE 'serverless'
    END AS arquitectura_cpu,
    CASE
        WHEN (n % 10) + 1 = 3 THEN 32.00
        WHEN (n % 10) + 1 = 10 THEN 64.00
        WHEN (n % 10) + 1 = 1 THEN 16.00
        WHEN (n % 10) + 1 = 4 THEN 8.00
        ELSE 4.00
    END AS memoria_ram_gb,
    CASE
        WHEN (n % 10) + 1 IN (3, 10) THEN 8
        WHEN (n % 10) + 1 = 1 THEN 4
        ELSE 2
    END AS vcpus,
    CASE
        WHEN (n % 10) + 1 = 3 THEN 500
        WHEN (n % 10) + 1 = 10 THEN 1000
        WHEN (n % 10) + 1 = 1 THEN 200
        ELSE 50
    END AS almacenamiento_gb,
    CASE
        WHEN (n % 10) + 1 = 3 THEN 'AURORA_STORAGE'
        WHEN (n % 10) + 1 = 10 THEN 'EBS_IO2'
        WHEN (n % 10) + 1 = 1 THEN 'EBS_GP3'
        ELSE 'S3_STANDARD'
    END AS tipo_almacenamiento,
    IF((n % 10) + 1 IN (1, 9), 25.00, IF((n % 10) + 1 = 2, 10.00, 5.00)) AS ancho_banda_gbps,
    IF((n % 10) + 1 IN (1, 2, 9), TRUE, FALSE) AS ip_publica_dedicada,
    CONCAT('v2.', (n % 5), '.', (n % 9)) AS version_software,
    CASE
        WHEN (n % 10) + 1 = 1 THEN 5
        WHEN (n % 10) + 1 = 3 THEN 10
        WHEN (n % 10) + 1 = 8 THEN 120
        ELSE 15
    END AS tiempo_aprovisionamiento_min,

    -- SLA, Disponibilidad y Resiliencia
    CASE
        WHEN (n % 10) + 1 IN (2, 3) THEN 99.99
        WHEN (n % 10) + 1 = 1 THEN 99.95
        ELSE 99.90
    END AS sla_disponibilidad_porc,
    IF((n % 10) + 1 IN (2, 3), 1, 4) AS tiempo_respuesta_soporte_hrs,
    IF((n % 10) + 1 IN (1, 2, 3), TRUE, FALSE) AS soporte_24_7,
    CASE
        WHEN (n % 10) + 1 IN (2, 3) THEN 'ENTERPRISE'
        WHEN (n % 10) + 1 IN (1, 5) THEN 'BUSINESS'
        ELSE 'BASICO'
    END AS nivel_soporte,
    IF((n % 10) + 1 IN (1, 2, 3), TRUE, FALSE) AS multiaz_habilitado,
    IF((n % 10) + 1 = 3, 6, 24) AS backup_automatico_horas,
    IF((n % 10) + 1 = 3, 5, 60) AS rpo_minutos,
    IF((n % 10) + 1 = 3, 15, 120) AS rto_minutos,

    -- Seguridad y Cumplimiento
    TRUE AS cifrado_en_reposo,
    'AES-256-GCM' AS algoritmo_cifrado,
    TRUE AS cifrado_en_transito,
    IF((n % 10) + 1 IN (2, 3, 8), TRUE, FALSE) AS cumplimiento_pci_dss,
    TRUE AS cumplimiento_iso27001,
    TRUE AS cumplimiento_soc2,
    IF((n % 10) + 1 IN (2, 8), 730, 365) AS retencion_logs_dias,
    IF((n % 10) + 1 IN (2, 4, 9), TRUE, FALSE) AS waf_incluido,

    -- Comercial, Fiscal y Facturación
    ROUND(1500.00 + ((n * 375.50) % 18500), 2) AS precio_unitario,
    'MXN' AS moneda,
    ELT((n % 4) + 1, 'MENSUAL', 'POR_HORA', 'ANUAL', 'POR_EVENTO') AS tipo_facturacion,
    'ANTICIPADO' AS ciclo_cobro,
    IF((n % 10) + 1 = 8, 5.00, 20.00) AS descuento_maximo_porc,
    IF((n % 10) + 1 = 3, 12, 1) AS plazo_minimo_meses,
    IF((n % 10) + 1 = 3, 10.00, 0.00) AS penalizacion_cancelacion_porc,
    '02' AS objeto_impuesto_sat,
    'Servicio' AS unidad_medida_sat,
    ROUND((1500.00 + ((n * 375.50) % 18500)) * 0.45, 2) AS costo_operativo_estimado,

    -- Operación y Lifecycle
    IF(n % 3 = 0, TRUE, FALSE) AS aplica_retencion,
    55.00 AS margen_ganancia_porc,
    ROUND(10.0 + (CASE WHEN (n % 10) + 1 IN (3, 10) THEN 8 WHEN (n % 10) + 1 = 1 THEN 4 ELSE 2 END * 4.5), 2) AS consumo_kwh_estimado,
    IF((n % 10) + 1 = 10, 5000000, 1000000) AS limite_peticiones_mes,
    CONCAT(LOWER(REPLACE(ELT((n % 10) + 1, 'Cloud Computing', 'Ciberseguridad', 'Bases de Datos', 'Desarrollo', 'DevOps', 'Analítica', 'Soporte', 'Auditoría', 'Redes', 'IA y Datos'), ' ', '')), '-soporte@cloudtech.mx') AS responsable_tecnico,
    TRUE AS activo
FROM seq;

-- 6. CATÁLOGO DE 50 CARACTERÍSTICAS CONFIGURABLES
INSERT INTO Catalogo_Caracteristicas (
    codigo_caracteristica, nombre_caracteristica, tipo_dato, unidad_medida, descripcion
)
WITH RECURSIVE seq(n) AS (
    SELECT 1
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 50
)
SELECT
    CONCAT('CAR-', LPAD(n, 3, '0')) AS codigo_caracteristica,
    CONCAT(
        ELT((n % 10) + 1,
            'Disponibilidad SLA', 'Tiempo de Respuesta', 'Almacenamiento Incluido',
            'Ancho de Banda', 'Nivel de Cifrado', 'Respaldos Automáticos',
            'Región de Despliegue', 'Soporte Especializado', 'Horas de Consultoría',
            'Monitoreo Continuo'
        ),
        ' (Parámetro ', n, ')'
    ) AS nombre_caracteristica,
    ELT((n % 4) + 1, 'SLA', 'NUMERICO', 'TEXTO', 'BOOLEANO') AS tipo_dato,
    ELT((n % 5) + 1, '%', 'Horas', 'GB', 'Mbps', 'N/A') AS unidad_medida,
    CONCAT('Característica técnica configurable #', n, ' para catálogo de servicios.') AS descripcion
FROM seq;

-- 7. ASIGNACIÓN INICIAL DE CARACTERÍSTICAS A SERVICIOS (3 características por cada uno de los 100 servicios = 300 registros)
INSERT INTO Caracteristicas_Servicio (id_servicio, id_caracteristica, valor_configurado)
SELECT
    s.id_servicio,
    ((s.id_servicio + offset_val) % 50) + 1 AS id_caracteristica,
    CASE offset_val
        WHEN 0 THEN '99.95%'
        WHEN 1 THEN '24/7 Prioritario'
        ELSE 'AES-256 / Multi-AZ'
    END AS valor_configurado
FROM Servicios s
CROSS JOIN (SELECT 0 AS offset_val UNION ALL SELECT 1 UNION ALL SELECT 2) AS offsets;

-- 8. CONSULTAS DE VERIFICACIÓN DE VOLUMEN (Rubro 1 de la Rúbrica)
SELECT 'Usuarios_Roles' AS Tabla, COUNT(*) AS Total_Registros FROM Usuarios_Roles
UNION ALL SELECT 'Clientes', COUNT(*) FROM Clientes
UNION ALL SELECT 'Impuestos_Historico', COUNT(*) FROM Impuestos_Historico
UNION ALL SELECT 'Series_Folios', COUNT(*) FROM Series_Folios
UNION ALL SELECT 'Servicios (Mín 100)', COUNT(*) FROM Servicios
UNION ALL SELECT 'Catalogo_Caracteristicas (Mín 50)', COUNT(*) FROM Catalogo_Caracteristicas
UNION ALL SELECT 'Caracteristicas_Servicio', COUNT(*) FROM Caracteristicas_Servicio;
