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

-- 5. CATÁLOGO DE 100 SERVICIOS (Generación sintética estructurada en 10 categorías)
INSERT INTO Servicios (
    codigo_interno, clave_prod_serv_sat, clave_unidad_sat,
    nombre_servicio, descripcion, categoria, precio_unitario, aplica_retencion, activo
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
    ROUND(1500.00 + ((n * 375.50) % 18500), 2) AS precio_unitario,
    IF(n % 3 = 0, TRUE, FALSE) AS aplica_retencion,
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
