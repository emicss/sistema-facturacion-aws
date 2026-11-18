-- ============================================================================
-- PROYECTO C: SISTEMA DE FACTURACIÓN Y SERVICIOS (AWS RDS - MySQL 8.0)
-- Archivo: /database/01_schema_ddl.sql
-- ============================================================================

CREATE DATABASE IF NOT EXISTS facturacion_cloud_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE facturacion_cloud_db;

-- 1. TABLA: Usuarios_Roles (RBAC y hashing bcrypt/Argon2)
CREATE TABLE Usuarios_Roles (
    id_usuario INT AUTO_INCREMENT PRIMARY KEY,
    nombre_completo VARCHAR(120) NOT NULL,
    email VARCHAR(120) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    rol ENUM('ADMIN', 'CONTADOR', 'OPERADOR', 'CLIENTE') NOT NULL DEFAULT 'OPERADOR',
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_usuarios_rol (rol)
) ENGINE=InnoDB;

-- 2. TABLA: Clientes (Datos fiscales y reglas de descuento/crédito)
CREATE TABLE Clientes (
    id_cliente INT AUTO_INCREMENT PRIMARY KEY,
    rfc VARCHAR(13) NOT NULL UNIQUE,
    razon_social VARCHAR(180) NOT NULL,
    regimen_fiscal VARCHAR(10) NOT NULL DEFAULT '601',
    codigo_postal VARCHAR(5) NOT NULL,
    email_facturacion VARCHAR(120) NOT NULL,
    nivel_descuento ENUM('ESTANDAR', 'PLATA', 'ORO', 'VIP') NOT NULL DEFAULT 'ESTANDAR',
    porcentaje_descuento DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    dias_credito INT NOT NULL DEFAULT 30,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_clientes_nivel (nivel_descuento)
) ENGINE=InnoDB;

-- 3. TABLA: Impuestos_Historico (Tasas de IVA y Retenciones por vigencia)
CREATE TABLE Impuestos_Historico (
    id_impuesto INT AUTO_INCREMENT PRIMARY KEY,
    codigo_impuesto VARCHAR(30) NOT NULL UNIQUE,
    descripcion VARCHAR(100) NOT NULL,
    tasa_iva DECIMAL(5,4) NOT NULL DEFAULT 0.1600,
    tasa_retencion_isr DECIMAL(5,4) NOT NULL DEFAULT 0.1000,
    tasa_retencion_iva DECIMAL(5,4) NOT NULL DEFAULT 0.1067,
    fecha_inicio_vigencia DATE NOT NULL,
    fecha_fin_vigencia DATE NULL,
    es_vigente BOOLEAN NOT NULL DEFAULT TRUE,
    INDEX idx_impuestos_vigente (es_vigente, fecha_inicio_vigencia)
) ENGINE=InnoDB;

-- 4. TABLA: Servicios (Catálogo de al menos 100 servicios)
CREATE TABLE Servicios (
    id_servicio INT AUTO_INCREMENT PRIMARY KEY,
    codigo_interno VARCHAR(20) NOT NULL UNIQUE,
    clave_prod_serv_sat VARCHAR(10) NOT NULL DEFAULT '81112000',
    clave_unidad_sat VARCHAR(5) NOT NULL DEFAULT 'E48',
    nombre_servicio VARCHAR(150) NOT NULL,
    descripcion TEXT NULL,
    categoria VARCHAR(60) NOT NULL,
    precio_unitario DECIMAL(12,2) NOT NULL CHECK (precio_unitario >= 0),
    aplica_retencion BOOLEAN NOT NULL DEFAULT FALSE,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    actualizado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_servicios_categoria (categoria),
    INDEX idx_servicios_activo (activo)
) ENGINE=InnoDB;

-- 5. TABLA: Catalogo_Caracteristicas (Al menos 50 características configurables)
CREATE TABLE Catalogo_Caracteristicas (
    id_caracteristica INT AUTO_INCREMENT PRIMARY KEY,
    codigo_caracteristica VARCHAR(25) NOT NULL UNIQUE,
    nombre_caracteristica VARCHAR(100) NOT NULL,
    tipo_dato ENUM('TEXTO', 'NUMERICO', 'BOOLEANO', 'SLA') NOT NULL DEFAULT 'TEXTO',
    unidad_medida VARCHAR(30) NULL,
    descripcion VARCHAR(200) NULL
) ENGINE=InnoDB;

-- 6. TABLA: Caracteristicas_Servicio (Relación N:M entre Servicios y Características)
CREATE TABLE Caracteristicas_Servicio (
    id_caracteristica_servicio INT AUTO_INCREMENT PRIMARY KEY,
    id_servicio INT NOT NULL,
    id_caracteristica INT NOT NULL,
    valor_configurado VARCHAR(120) NOT NULL,
    asignado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_servicio_caracteristica (id_servicio, id_caracteristica),
    CONSTRAINT fk_caract_servicio FOREIGN KEY (id_servicio)
        REFERENCES Servicios(id_servicio) ON DELETE CASCADE,
    CONSTRAINT fk_caract_catalogo FOREIGN KEY (id_caracteristica)
        REFERENCES Catalogo_Caracteristicas(id_caracteristica) ON DELETE RESTRICT,
    INDEX idx_caract_id (id_caracteristica)
) ENGINE=InnoDB;

-- 7. TABLA: Series_Folios (Control de concurrencia para SP1: Folios atómicos)
CREATE TABLE Series_Folios (
    serie VARCHAR(10) PRIMARY KEY,
    descripcion VARCHAR(100) NOT NULL,
    folio_actual INT NOT NULL DEFAULT 0,
    actualizado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 8. TABLA: Facturas (Cabecera transaccional y fiscal)
CREATE TABLE Facturas (
    id_factura INT AUTO_INCREMENT PRIMARY KEY,
    serie VARCHAR(10) NOT NULL,
    folio INT NOT NULL,
    uuid_fiscal CHAR(36) NULL UNIQUE,
    id_cliente INT NOT NULL,
    id_usuario_emisor INT NOT NULL,
    id_impuesto INT NOT NULL,
    fecha_emision DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_vencimiento DATE NOT NULL,
    moneda CHAR(3) NOT NULL DEFAULT 'MXN',
    subtotal DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    descuento_monto DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    iva_monto DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    retencion_isr_monto DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    retencion_iva_monto DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    total DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    saldo_pendiente DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    estado_factura ENUM('BORRADOR', 'TIMBRADA', 'CANCELADA') NOT NULL DEFAULT 'BORRADOR',
    estado_pago ENUM('PENDIENTE', 'PARCIAL', 'PAGADA', 'CANCELADA') NOT NULL DEFAULT 'PENDIENTE',
    motivo_cancelacion VARCHAR(250) NULL,
    fecha_cancelacion DATETIME NULL,
    UNIQUE KEY uq_serie_folio (serie, folio),
    CONSTRAINT fk_factura_serie FOREIGN KEY (serie)
        REFERENCES Series_Folios(serie),
    CONSTRAINT fk_factura_cliente FOREIGN KEY (id_cliente)
        REFERENCES Clientes(id_cliente),
    CONSTRAINT fk_factura_usuario FOREIGN KEY (id_usuario_emisor)
        REFERENCES Usuarios_Roles(id_usuario),
    CONSTRAINT fk_factura_impuesto FOREIGN KEY (id_impuesto)
        REFERENCES Impuestos_Historico(id_impuesto),
    INDEX idx_facturas_cliente_estado (id_cliente, estado_pago),
    INDEX idx_facturas_fechas (fecha_emision, fecha_vencimiento),
    INDEX idx_facturas_estado (estado_factura)
) ENGINE=InnoDB;

-- 9. TABLA: Detalle_Factura (Partidas de servicios por factura)
CREATE TABLE Detalle_Factura (
    id_detalle INT AUTO_INCREMENT PRIMARY KEY,
    id_factura INT NOT NULL,
    id_servicio INT NOT NULL,
    cantidad DECIMAL(10,2) NOT NULL DEFAULT 1.00 CHECK (cantidad > 0),
    precio_unitario DECIMAL(12,2) NOT NULL,
    descuento_linea DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    importe_linea DECIMAL(12,2) NOT NULL,
    CONSTRAINT fk_detalle_factura FOREIGN KEY (id_factura)
        REFERENCES Facturas(id_factura) ON DELETE CASCADE,
    CONSTRAINT fk_detalle_servicio FOREIGN KEY (id_servicio)
        REFERENCES Servicios(id_servicio),
    INDEX idx_detalle_factura (id_factura),
    INDEX idx_detalle_servicio (id_servicio)
) ENGINE=InnoDB;

-- 10. TABLA: Pagos (Abonos, liquidaciones y reversiones contables)
CREATE TABLE Pagos (
    id_pago INT AUTO_INCREMENT PRIMARY KEY,
    id_factura INT NOT NULL,
    id_usuario_registro INT NOT NULL,
    fecha_pago DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    monto_pagado DECIMAL(12,2) NOT NULL CHECK (monto_pagado > 0),
    metodo_pago ENUM('TRANSFERENCIA', 'TARJETA', 'EFECTIVO', 'CHEQUE') NOT NULL DEFAULT 'TRANSFERENCIA',
    referencia_bancaria VARCHAR(80) NOT NULL,
    estatus_pago ENUM('APLICADO', 'REVERTIDO') NOT NULL DEFAULT 'APLICADO',
    CONSTRAINT fk_pago_factura FOREIGN KEY (id_factura)
        REFERENCES Facturas(id_factura),
    CONSTRAINT fk_pago_usuario FOREIGN KEY (id_usuario_registro)
        REFERENCES Usuarios_Roles(id_usuario),
    INDEX idx_pagos_factura (id_factura, estatus_pago)
) ENGINE=InnoDB;

-- 11. TABLA: Auditoria_Tarifas (Soporte directo para SP10: Auditoría de cambios en tarifas)
CREATE TABLE Auditoria_Tarifas (
    id_auditoria INT AUTO_INCREMENT PRIMARY KEY,
    id_servicio INT NOT NULL,
    id_usuario INT NOT NULL,
    precio_anterior DECIMAL(12,2) NOT NULL,
    precio_nuevo DECIMAL(12,2) NOT NULL,
    motivo_cambio VARCHAR(200) NOT NULL,
    fecha_cambio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_auditoria_servicio FOREIGN KEY (id_servicio)
        REFERENCES Servicios(id_servicio),
    CONSTRAINT fk_auditoria_usuario FOREIGN KEY (id_usuario)
        REFERENCES Usuarios_Roles(id_usuario),
    INDEX idx_auditoria_servicio_fecha (id_servicio, fecha_cambio)
) ENGINE=InnoDB;
