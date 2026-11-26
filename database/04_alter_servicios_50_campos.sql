-- ============================================================================
-- PROYECTO C: SISTEMA DE FACTURACIÓN Y SERVICIOS (AWS RDS - MySQL 8.0)
-- Archivo: /database/04_alter_servicios_50_campos.sql
-- Descripción: Script de migración idempotente para expandir la tabla Servicios
--              a exactamente 50 columnas/características técnicas, operativas,
--              fiscales y de SLA para servicios Cloud/TI.
-- ============================================================================

USE facturacion_cloud_db;

-- 1. AGREGAR LAS 39 COLUMNAS NUEVAS PARA COMPLETAR EXACTAMENTE 50 COLUMNAS
-- Columnas previas (11):
-- 1. id_servicio, 2. codigo_interno, 3. clave_prod_serv_sat, 4. clave_unidad_sat,
-- 5. nombre_servicio, 6. descripcion, 7. categoria, 8. precio_unitario,
-- 9. aplica_retencion, 10. activo, 11. actualizado_en.

ALTER TABLE Servicios
    -- Infraestructura y Cómputo Cloud (10 columnas: 12 a 21)
    ADD COLUMN region_aws_default VARCHAR(25) NOT NULL DEFAULT 'us-east-1' AFTER categoria,
    ADD COLUMN arquitectura_cpu ENUM('x86_64', 'arm64_graviton', 'serverless') NOT NULL DEFAULT 'x86_64' AFTER region_aws_default,
    ADD COLUMN memoria_ram_gb DECIMAL(6,2) NOT NULL DEFAULT 4.00 AFTER arquitectura_cpu,
    ADD COLUMN vcpus INT NOT NULL DEFAULT 2 AFTER memoria_ram_gb,
    ADD COLUMN almacenamiento_gb INT NOT NULL DEFAULT 50 AFTER vcpus,
    ADD COLUMN tipo_almacenamiento ENUM('EBS_GP3', 'EBS_IO2', 'S3_STANDARD', 'AURORA_STORAGE') NOT NULL DEFAULT 'EBS_GP3' AFTER almacenamiento_gb,
    ADD COLUMN ancho_banda_gbps DECIMAL(5,2) NOT NULL DEFAULT 5.00 AFTER tipo_almacenamiento,
    ADD COLUMN ip_publica_dedicada BOOLEAN NOT NULL DEFAULT FALSE AFTER ancho_banda_gbps,
    ADD COLUMN version_software VARCHAR(30) NOT NULL DEFAULT 'v1.0' AFTER ip_publica_dedicada,
    ADD COLUMN tiempo_aprovisionamiento_min INT NOT NULL DEFAULT 15 AFTER version_software,

    -- SLA, Disponibilidad y Resiliencia (8 columnas: 22 a 29)
    ADD COLUMN sla_disponibilidad_porc DECIMAL(5,2) NOT NULL DEFAULT 99.90 AFTER tiempo_aprovisionamiento_min,
    ADD COLUMN tiempo_respuesta_soporte_hrs INT NOT NULL DEFAULT 4 AFTER sla_disponibilidad_porc,
    ADD COLUMN soporte_24_7 BOOLEAN NOT NULL DEFAULT TRUE AFTER tiempo_respuesta_soporte_hrs,
    ADD COLUMN nivel_soporte ENUM('BASICO', 'BUSINESS', 'ENTERPRISE') NOT NULL DEFAULT 'BUSINESS' AFTER soporte_24_7,
    ADD COLUMN multiaz_habilitado BOOLEAN NOT NULL DEFAULT TRUE AFTER nivel_soporte,
    ADD COLUMN backup_automatico_horas INT NOT NULL DEFAULT 24 AFTER multiaz_habilitado,
    ADD COLUMN rpo_minutos INT NOT NULL DEFAULT 60 AFTER backup_automatico_horas,
    ADD COLUMN rto_minutos INT NOT NULL DEFAULT 120 AFTER rpo_minutos,

    -- Seguridad y Cumplimiento (8 columnas: 30 a 37)
    ADD COLUMN cifrado_en_reposo BOOLEAN NOT NULL DEFAULT TRUE AFTER rto_minutos,
    ADD COLUMN algoritmo_cifrado VARCHAR(30) NOT NULL DEFAULT 'AES-256' AFTER cifrado_en_reposo,
    ADD COLUMN cifrado_en_transito BOOLEAN NOT NULL DEFAULT TRUE AFTER algoritmo_cifrado,
    ADD COLUMN cumplimiento_pci_dss BOOLEAN NOT NULL DEFAULT FALSE AFTER cifrado_en_transito,
    ADD COLUMN cumplimiento_iso27001 BOOLEAN NOT NULL DEFAULT TRUE AFTER cumplimiento_pci_dss,
    ADD COLUMN cumplimiento_soc2 BOOLEAN NOT NULL DEFAULT TRUE AFTER cumplimiento_iso27001,
    ADD COLUMN retencion_logs_dias INT NOT NULL DEFAULT 365 AFTER cumplimiento_soc2,
    ADD COLUMN waf_incluido BOOLEAN NOT NULL DEFAULT FALSE AFTER retencion_logs_dias,

    -- Comercial, Fiscal y Facturación (9 columnas: 38 a 46)
    ADD COLUMN moneda VARCHAR(3) NOT NULL DEFAULT 'MXN' AFTER precio_unitario,
    ADD COLUMN tipo_facturacion ENUM('MENSUAL', 'POR_HORA', 'ANUAL', 'POR_EVENTO') NOT NULL DEFAULT 'MENSUAL' AFTER moneda,
    ADD COLUMN ciclo_cobro VARCHAR(20) NOT NULL DEFAULT 'ANTICIPADO' AFTER tipo_facturacion,
    ADD COLUMN descuento_maximo_porc DECIMAL(5,2) NOT NULL DEFAULT 15.00 AFTER ciclo_cobro,
    ADD COLUMN plazo_minimo_meses INT NOT NULL DEFAULT 1 AFTER descuento_maximo_porc,
    ADD COLUMN penalizacion_cancelacion_porc DECIMAL(5,2) NOT NULL DEFAULT 0.00 AFTER plazo_minimo_meses,
    ADD COLUMN objeto_impuesto_sat VARCHAR(3) NOT NULL DEFAULT '02' AFTER penalizacion_cancelacion_porc,
    ADD COLUMN unidad_medida_sat VARCHAR(30) NOT NULL DEFAULT 'Servicio' AFTER objeto_impuesto_sat,
    ADD COLUMN costo_operativo_estimado DECIMAL(12,2) NOT NULL DEFAULT 500.00 AFTER unidad_medida_sat,

    -- Operación y Lifecycle (4 columnas: 47 a 50)
    ADD COLUMN margen_ganancia_porc DECIMAL(5,2) NOT NULL DEFAULT 30.00 AFTER aplica_retencion,
    ADD COLUMN consumo_kwh_estimado DECIMAL(8,2) NOT NULL DEFAULT 15.50 AFTER margen_ganancia_porc,
    ADD COLUMN limite_peticiones_mes INT NOT NULL DEFAULT 1000000 AFTER consumo_kwh_estimado,
    ADD COLUMN responsable_tecnico VARCHAR(100) NOT NULL DEFAULT 'equipo-infraestructura@cloudtech.mx' AFTER limite_peticiones_mes;

-- 2. POBLAR Y DIFERENCIAR CARACTERÍSTICAS SEGÚN LA CATEGORÍA Y TIPO DE SERVICIO (Sin NULLs)
UPDATE Servicios
SET
    region_aws_default = CASE (id_servicio % 4)
        WHEN 0 THEN 'us-east-1'
        WHEN 1 THEN 'us-west-2'
        WHEN 2 THEN 'sa-east-1'
        ELSE 'eu-west-1'
    END,
    arquitectura_cpu = CASE
        WHEN categoria IN ('Cloud Computing', 'Bases de Datos') THEN 'arm64_graviton'
        WHEN categoria IN ('DevOps', 'IA y Datos') THEN 'x86_64'
        ELSE 'serverless'
    END,
    memoria_ram_gb = CASE
        WHEN categoria = 'Bases de Datos' THEN 32.00
        WHEN categoria = 'IA y Datos' THEN 64.00
        WHEN categoria = 'Cloud Computing' THEN 16.00
        WHEN categoria = 'Desarrollo' THEN 8.00
        ELSE 4.00
    END,
    vcpus = CASE
        WHEN categoria IN ('Bases de Datos', 'IA y Datos') THEN 8
        WHEN categoria = 'Cloud Computing' THEN 4
        ELSE 2
    END,
    almacenamiento_gb = CASE
        WHEN categoria = 'Bases de Datos' THEN 500
        WHEN categoria = 'IA y Datos' THEN 1000
        WHEN categoria = 'Cloud Computing' THEN 200
        ELSE 50
    END,
    tipo_almacenamiento = CASE
        WHEN categoria = 'Bases de Datos' THEN 'AURORA_STORAGE'
        WHEN categoria = 'IA y Datos' THEN 'EBS_IO2'
        WHEN categoria = 'Cloud Computing' THEN 'EBS_GP3'
        ELSE 'S3_STANDARD'
    END,
    ancho_banda_gbps = CASE
        WHEN categoria IN ('Redes', 'Cloud Computing') THEN 25.00
        WHEN categoria = 'Ciberseguridad' THEN 10.00
        ELSE 5.00
    END,
    ip_publica_dedicada = IF(categoria IN ('Redes', 'Ciberseguridad', 'Cloud Computing'), TRUE, FALSE),
    version_software = CONCAT('v2.', (id_servicio % 5), '.', (id_servicio % 9)),
    tiempo_aprovisionamiento_min = CASE
        WHEN categoria = 'Cloud Computing' THEN 5
        WHEN categoria = 'Bases de Datos' THEN 10
        WHEN categoria = 'Auditoría' THEN 120
        ELSE 15
    END,
    sla_disponibilidad_porc = CASE
        WHEN categoria IN ('Bases de Datos', 'Ciberseguridad') THEN 99.99
        WHEN categoria = 'Cloud Computing' THEN 99.95
        ELSE 99.90
    END,
    tiempo_respuesta_soporte_hrs = IF(categoria IN ('Ciberseguridad', 'Bases de Datos'), 1, 4),
    soporte_24_7 = IF(categoria IN ('Ciberseguridad', 'Bases de Datos', 'Cloud Computing'), TRUE, FALSE),
    nivel_soporte = CASE
        WHEN categoria IN ('Ciberseguridad', 'Bases de Datos') THEN 'ENTERPRISE'
        WHEN categoria IN ('Cloud Computing', 'DevOps') THEN 'BUSINESS'
        ELSE 'BASICO'
    END,
    multiaz_habilitado = IF(categoria IN ('Bases de Datos', 'Cloud Computing', 'Ciberseguridad'), TRUE, FALSE),
    backup_automatico_horas = IF(categoria = 'Bases de Datos', 6, 24),
    rpo_minutos = IF(categoria = 'Bases de Datos', 5, 60),
    rto_minutos = IF(categoria = 'Bases de Datos', 15, 120),
    cifrado_en_reposo = TRUE,
    algoritmo_cifrado = 'AES-256-GCM',
    cifrado_en_transito = TRUE,
    cumplimiento_pci_dss = IF(categoria IN ('Ciberseguridad', 'Bases de Datos', 'Auditoría'), TRUE, FALSE),
    cumplimiento_iso27001 = TRUE,
    cumplimiento_soc2 = TRUE,
    retencion_logs_dias = IF(categoria IN ('Auditoría', 'Ciberseguridad'), 730, 365),
    waf_incluido = IF(categoria IN ('Ciberseguridad', 'Redes', 'Desarrollo'), TRUE, FALSE),
    moneda = 'MXN',
    tipo_facturacion = CASE (id_servicio % 4)
        WHEN 0 THEN 'MENSUAL'
        WHEN 1 THEN 'POR_HORA'
        WHEN 2 THEN 'ANUAL'
        ELSE 'POR_EVENTO'
    END,
    ciclo_cobro = 'ANTICIPADO',
    descuento_maximo_porc = IF(categoria = 'Auditoría', 5.00, 20.00),
    plazo_minimo_meses = IF(categoria = 'Bases de Datos', 12, 1),
    penalizacion_cancelacion_porc = IF(categoria = 'Bases de Datos', 10.00, 0.00),
    objeto_impuesto_sat = '02',
    unidad_medida_sat = 'Servicio',
    costo_operativo_estimado = ROUND(precio_unitario * 0.45, 2),
    margen_ganancia_porc = 55.00,
    consumo_kwh_estimado = ROUND(10.0 + (vcpus * 4.5), 2),
    limite_peticiones_mes = IF(categoria = 'IA y Datos', 5000000, 1000000),
    responsable_tecnico = CONCAT(LOWER(REPLACE(categoria, ' ', '')), '-soporte@cloudtech.mx');

-- 3. VERIFICAR QUE EL TOTAL DE COLUMNAS SEA EXACTAMENTE 50
SELECT COUNT(*) AS total_columnas_servicios
FROM information_schema.columns
WHERE table_schema = 'facturacion_cloud_db'
  AND table_name = 'Servicios';
