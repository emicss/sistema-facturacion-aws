-- ============================================================================
-- PROYECTO C: SISTEMA DE FACTURACIÓN Y SERVICIOS (AWS RDS - MySQL 8.0)
-- Archivo: /database/03_stored_procedures.sql
-- Descripción: 10 Stored Procedures transaccionales obligatorios
-- ============================================================================

USE facturacion_cloud_db;

DELIMITER //

-- ----------------------------------------------------------------------------
-- SP 1: Generación e iteración atómica de folios de factura
-- Bloquea la fila de la serie (FOR UPDATE) para evitar folios duplicados
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_generar_folio_factura //
CREATE PROCEDURE sp_generar_folio_factura(
    IN p_serie VARCHAR(10),
    IN p_id_cliente INT,
    IN p_id_usuario INT,
    OUT p_id_factura INT,
    OUT p_folio_asignado INT
)
BEGIN
    DECLARE v_dias_credito INT DEFAULT 30;
    DECLARE v_id_impuesto INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Bloqueo pesimista sobre la serie para atomicidad
    SELECT folio_actual + 1 INTO p_folio_asignado
    FROM Series_Folios
    WHERE serie = p_serie
    FOR UPDATE;

    IF p_folio_asignado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La serie especificada no existe.';
    END IF;

    UPDATE Series_Folios
    SET folio_actual = p_folio_asignado
    WHERE serie = p_serie;

    -- Obtener días de crédito del cliente e impuesto vigente
    SELECT dias_credito INTO v_dias_credito
    FROM Clientes WHERE id_cliente = p_id_cliente;

    SELECT id_impuesto INTO v_id_impuesto
    FROM Impuestos_Historico
    WHERE es_vigente = TRUE
    ORDER BY fecha_inicio_vigencia DESC
    LIMIT 1;

    -- Insertar cabecera de factura en estado BORRADOR
    INSERT INTO Facturas (
        serie, folio, id_cliente, id_usuario_emisor, id_impuesto,
        fecha_emision, fecha_vencimiento, estado_factura, estado_pago
    ) VALUES (
        p_serie, p_folio_asignado, p_id_cliente, p_id_usuario, v_id_impuesto,
        NOW(), DATE_ADD(CURDATE(), INTERVAL v_dias_credito DAY), 'BORRADOR', 'PENDIENTE'
    );

    SET p_id_factura = LAST_INSERT_ID();
    COMMIT;
END //

-- ----------------------------------------------------------------------------
-- SP 2: Cálculo automático de Subtotal, IVA y Retenciones
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_calcular_impuestos_factura //
CREATE PROCEDURE sp_calcular_impuestos_factura(
    IN p_id_factura INT
)
BEGIN
    DECLARE v_subtotal DECIMAL(12,2) DEFAULT 0.00;
    DECLARE v_descuento DECIMAL(12,2) DEFAULT 0.00;
    DECLARE v_base_gravable DECIMAL(12,2) DEFAULT 0.00;
    DECLARE v_base_retencion DECIMAL(12,2) DEFAULT 0.00;
    DECLARE v_tasa_iva DECIMAL(5,4);
    DECLARE v_tasa_ret_isr DECIMAL(5,4);
    DECLARE v_tasa_ret_iva DECIMAL(5,4);
    DECLARE v_iva DECIMAL(12,2);
    DECLARE v_ret_isr DECIMAL(12,2);
    DECLARE v_ret_iva DECIMAL(12,2);
    DECLARE v_total DECIMAL(12,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Obtener tasas desde Impuestos_Historico asociadas a la factura
    SELECT ih.tasa_iva, ih.tasa_retencion_isr, ih.tasa_retencion_iva, f.descuento_monto
    INTO v_tasa_iva, v_tasa_ret_isr, v_tasa_ret_iva, v_descuento
    FROM Facturas f
    INNER JOIN Impuestos_Historico ih ON f.id_impuesto = ih.id_impuesto
    WHERE f.id_factura = p_id_factura
    FOR UPDATE;

    -- Calcular subtotal total y base sujeta a retención
    SELECT
        COALESCE(SUM(df.importe_linea), 0.00),
        COALESCE(SUM(IF(s.aplica_retencion = TRUE, df.importe_linea, 0.00)), 0.00)
    INTO v_subtotal, v_base_retencion
    FROM Detalle_Factura df
    INNER JOIN Servicios s ON df.id_servicio = s.id_servicio
    WHERE df.id_factura = p_id_factura;

    SET v_base_gravable = GREATEST(v_subtotal - v_descuento, 0.00);
    SET v_iva = ROUND(v_base_gravable * v_tasa_iva, 2);
    SET v_ret_isr = ROUND(v_base_retencion * v_tasa_ret_isr, 2);
    SET v_ret_iva = ROUND(v_base_retencion * v_tasa_ret_iva, 2);
    SET v_total = ROUND(v_base_gravable + v_iva - v_ret_isr - v_ret_iva, 2);

    UPDATE Facturas
    SET subtotal = v_subtotal,
        iva_monto = v_iva,
        retencion_isr_monto = v_ret_isr,
        retencion_iva_monto = v_ret_iva,
        total = v_total,
        saldo_pendiente = v_total
    WHERE id_factura = p_id_factura;

    COMMIT;
END //

-- ----------------------------------------------------------------------------
-- SP 3: Aplicación de reglas de descuento por cliente o volumen
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_aplicar_descuento //
CREATE PROCEDURE sp_aplicar_descuento(
    IN p_id_factura INT
)
BEGIN
    DECLARE v_subtotal DECIMAL(12,2) DEFAULT 0.00;
    DECLARE v_porc_cliente DECIMAL(5,2) DEFAULT 0.00;
    DECLARE v_porc_volumen DECIMAL(5,2) DEFAULT 0.00;
    DECLARE v_porc_final DECIMAL(5,2) DEFAULT 0.00;
    DECLARE v_descuento_monto DECIMAL(12,2) DEFAULT 0.00;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT c.porcentaje_descuento
    INTO v_porc_cliente
    FROM Facturas f
    INNER JOIN Clientes c ON f.id_cliente = c.id_cliente
    WHERE f.id_factura = p_id_factura
    FOR UPDATE;

    SELECT COALESCE(SUM(importe_linea), 0.00)
    INTO v_subtotal
    FROM Detalle_Factura
    WHERE id_factura = p_id_factura;

    -- Regla de volumen: 5% si supera $20,000, 10% si supera $50,000
    IF v_subtotal >= 50000.00 THEN
        SET v_porc_volumen = 10.00;
    ELSEIF v_subtotal >= 20000.00 THEN
        SET v_porc_volumen = 5.00;
    END IF;

    -- Aplica el mayor descuento entre nivel de cliente o volumen
    SET v_porc_final = GREATEST(v_porc_cliente, v_porc_volumen);
    SET v_descuento_monto = ROUND(v_subtotal * (v_porc_final / 100), 2);

    UPDATE Facturas
    SET descuento_monto = v_descuento_monto
    WHERE id_factura = p_id_factura;

    COMMIT;

    -- Recalcular impuestos automáticamente tras aplicar descuento
    CALL sp_calcular_impuestos_factura(p_id_factura);
END //

-- ----------------------------------------------------------------------------
-- SP 4: Cancelación formal de facturas y reversión contable
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_cancelar_factura //
CREATE PROCEDURE sp_cancelar_factura(
    IN p_id_factura INT,
    IN p_motivo VARCHAR(250)
)
BEGIN
    DECLARE v_estado_actual VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT estado_factura INTO v_estado_actual
    FROM Facturas
    WHERE id_factura = p_id_factura
    FOR UPDATE;

    IF v_estado_actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Factura no encontrada.';
    ELSEIF v_estado_actual = 'CANCELADA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La factura ya se encuentra cancelada.';
    END IF;

    -- Revertir contablemente los pagos aplicados sin borrar registros
    UPDATE Pagos
    SET estatus_pago = 'REVERTIDO'
    WHERE id_factura = p_id_factura AND estatus_pago = 'APLICADO';

    -- Marcar factura como cancelada y saldar cuenta
    UPDATE Facturas
    SET estado_factura = 'CANCELADA',
        estado_pago = 'CANCELADA',
        saldo_pendiente = 0.00,
        motivo_cancelacion = p_motivo,
        fecha_cancelacion = NOW()
    WHERE id_factura = p_id_factura;

    COMMIT;
END //

-- ----------------------------------------------------------------------------
-- SP 5: Cierre y consolidado fiscal diario/mensual
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_cierre_fiscal_consolidado //
CREATE PROCEDURE sp_cierre_fiscal_consolidado(
    IN p_fecha_inicio DATE,
    IN p_fecha_fin DATE
)
BEGIN
    SELECT
        DATE(fecha_emision) AS fecha_corte,
        COUNT(id_factura) AS total_facturas_timbradas,
        COALESCE(SUM(subtotal), 0.00) AS suma_subtotal,
        COALESCE(SUM(descuento_monto), 0.00) AS suma_descuentos,
        COALESCE(SUM(iva_monto), 0.00) AS iva_trasladado,
        COALESCE(SUM(retencion_isr_monto), 0.00) AS isr_retenido,
        COALESCE(SUM(retencion_iva_monto), 0.00) AS iva_retenido,
        COALESCE(SUM(total), 0.00) AS total_facturado,
        COALESCE(SUM(total - saldo_pendiente), 0.00) AS total_cobrado
    FROM Facturas
    WHERE estado_factura = 'TIMBRADA'
      AND DATE(fecha_emision) BETWEEN p_fecha_inicio AND p_fecha_fin
    GROUP BY DATE(fecha_emision)
    ORDER BY fecha_corte ASC;
END //

-- ----------------------------------------------------------------------------
-- SP 6: Validación de estados de pago (actualiza saldo y estatus tras abono)
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_validar_estado_pago //
CREATE PROCEDURE sp_validar_estado_pago(
    IN p_id_factura INT
)
BEGIN
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_pagado DECIMAL(12,2);
    DECLARE v_saldo DECIMAL(12,2);
    DECLARE v_nuevo_estado VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT total INTO v_total
    FROM Facturas
    WHERE id_factura = p_id_factura AND estado_factura <> 'CANCELADA'
    FOR UPDATE;

    SELECT COALESCE(SUM(monto_pagado), 0.00) INTO v_pagado
    FROM Pagos
    WHERE id_factura = p_id_factura AND estatus_pago = 'APLICADO';

    SET v_saldo = GREATEST(v_total - v_pagado, 0.00);

    IF v_saldo = 0.00 AND v_total > 0.00 THEN
        SET v_nuevo_estado = 'PAGADA';
    ELSEIF v_pagado > 0.00 THEN
        SET v_nuevo_estado = 'PARCIAL';
    ELSE
        SET v_nuevo_estado = 'PENDIENTE';
    END IF;

    UPDATE Facturas
    SET saldo_pendiente = v_saldo,
        estado_pago = v_nuevo_estado
    WHERE id_factura = p_id_factura;

    COMMIT;
END //

-- ----------------------------------------------------------------------------
-- SP 7: Reporte de antigüedad de saldos (Cartera vencida: 30, 60, 90+ días)
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_reporte_antiguedad_saldos //
CREATE PROCEDURE sp_reporte_antiguedad_saldos()
BEGIN
    SELECT
        c.rfc,
        c.razon_social,
        CONCAT(f.serie, '-', f.folio) AS folio_factura,
        f.fecha_emision,
        f.fecha_vencimiento,
        GREATEST(DATEDIFF(CURDATE(), f.fecha_vencimiento), 0) AS dias_vencidos,
        f.saldo_pendiente,
        CASE
            WHEN DATEDIFF(CURDATE(), f.fecha_vencimiento) <= 0 THEN 'AL CORRIENTE'
            WHEN DATEDIFF(CURDATE(), f.fecha_vencimiento) BETWEEN 1 AND 30 THEN '1-30 DÍAS'
            WHEN DATEDIFF(CURDATE(), f.fecha_vencimiento) BETWEEN 31 AND 60 THEN '31-60 DÍAS'
            WHEN DATEDIFF(CURDATE(), f.fecha_vencimiento) BETWEEN 61 AND 90 THEN '61-90 DÍAS'
            ELSE 'MÁS DE 90 DÍAS'
        END AS bucket_antiguedad
    FROM Facturas f
    INNER JOIN Clientes c ON f.id_cliente = c.id_cliente
    WHERE f.estado_factura = 'TIMBRADA'
      AND f.estado_pago IN ('PENDIENTE', 'PARCIAL')
      AND f.saldo_pendiente > 0
    ORDER BY dias_vencidos DESC, f.saldo_pendiente DESC;
END //

-- ----------------------------------------------------------------------------
-- SP 8: Generación de estructura para comprobante/timbrado (CFDI simulado JSON)
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_generar_estructura_timbrado //
CREATE PROCEDURE sp_generar_estructura_timbrado(
    IN p_id_factura INT
)
BEGIN
    DECLARE v_uuid CHAR(36);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT uuid_fiscal INTO v_uuid
    FROM Facturas
    WHERE id_factura = p_id_factura
    FOR UPDATE;

    -- Si aún no tiene UUID, generar uno y marcar como TIMBRADA
    IF v_uuid IS NULL THEN
        SET v_uuid = UPPER(UUID());
        UPDATE Facturas
        SET uuid_fiscal = v_uuid,
            estado_factura = 'TIMBRADA'
        WHERE id_factura = p_id_factura;
    END IF;

    COMMIT;

    -- Devolver estructura JSON lista para comprobante fiscal
    SELECT JSON_OBJECT(
        'version', '4.0',
        'uuid_fiscal', f.uuid_fiscal,
        'serie', f.serie,
        'folio', f.folio,
        'fecha_emision', DATE_FORMAT(f.fecha_emision, '%Y-%m-%dT%H:%i:%s'),
        'moneda', f.moneda,
        'receptor', JSON_OBJECT(
            'rfc', c.rfc,
            'razon_social', c.razon_social,
            'regimen_fiscal', c.regimen_fiscal,
            'codigo_postal', c.codigo_postal
        ),
        'totales', JSON_OBJECT(
            'subtotal', f.subtotal,
            'descuento', f.descuento_monto,
            'iva', f.iva_monto,
            'retencion_isr', f.retencion_isr_monto,
            'retencion_iva', f.retencion_iva_monto,
            'total', f.total
        ),
        'conceptos', (
            SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'clave_sat', s.clave_prod_serv_sat,
                    'codigo', s.codigo_interno,
                    'descripcion', s.nombre_servicio,
                    'cantidad', df.cantidad,
                    'precio_unitario', df.precio_unitario,
                    'importe', df.importe_linea
                )
            )
            FROM Detalle_Factura df
            INNER JOIN Servicios s ON df.id_servicio = s.id_servicio
            WHERE df.id_factura = f.id_factura
        )
    ) AS comprobante_json
    FROM Facturas f
    INNER JOIN Clientes c ON f.id_cliente = c.id_cliente
    WHERE f.id_factura = p_id_factura;
END //

-- ----------------------------------------------------------------------------
-- SP 9: Asignación masiva de características a servicios por categoría
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_asignar_caracteristicas_masivas //
CREATE PROCEDURE sp_asignar_caracteristicas_masivas(
    IN p_categoria VARCHAR(60),
    IN p_id_caracteristica INT,
    IN p_valor_configurado VARCHAR(120)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO Caracteristicas_Servicio (id_servicio, id_caracteristica, valor_configurado)
    SELECT id_servicio, p_id_caracteristica, p_valor_configurado
    FROM Servicios
    WHERE categoria = p_categoria AND activo = TRUE
    ON DUPLICATE KEY UPDATE
        valor_configurado = VALUES(valor_configurado),
        asignado_en = NOW();

    SELECT ROW_COUNT() AS servicios_afectados;
    COMMIT;
END //

-- ----------------------------------------------------------------------------
-- SP 10: Auditoría de cambios en tarifas de servicios
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_auditar_cambio_tarifa //
CREATE PROCEDURE sp_auditar_cambio_tarifa(
    IN p_id_servicio INT,
    IN p_nuevo_precio DECIMAL(12,2),
    IN p_id_usuario INT,
    IN p_motivo VARCHAR(200)
)
BEGIN
    DECLARE v_precio_anterior DECIMAL(12,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_nuevo_precio < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El nuevo precio no puede ser negativo.';
    END IF;

    START TRANSACTION;

    SELECT precio_unitario INTO v_precio_anterior
    FROM Servicios
    WHERE id_servicio = p_id_servicio
    FOR UPDATE;

    IF v_precio_anterior IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Servicio no encontrado.';
    END IF;

    UPDATE Servicios
    SET precio_unitario = p_nuevo_precio
    WHERE id_servicio = p_id_servicio;

    INSERT INTO Auditoria_Tarifas (
        id_servicio, id_usuario, precio_anterior, precio_nuevo, motivo_cambio
    ) VALUES (
        p_id_servicio, p_id_usuario, v_precio_anterior, p_nuevo_precio, p_motivo
    );

    COMMIT;
END //

DELIMITER ;

-- VERIFICACIÓN: Listar los 10 Stored Procedures creados
SHOW PROCEDURE STATUS WHERE Db = 'facturacion_cloud_db';
