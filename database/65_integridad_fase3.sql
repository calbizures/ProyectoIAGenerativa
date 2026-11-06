/*
================================================================================
 65_integridad_fase3.sql
 Revisión de integridad (Contabilidad > Revisión de integridad): seis
 controles nuevos para la caja chica, los activos fijos, la conciliación
 bancaria y los estados financieros (14 a 19), además de los 13 anteriores.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[paAuditoriaIntegridadConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @r TABLE (Orden INT, Control VARCHAR(120), Casos INT, Ejemplo VARCHAR(200));

	INSERT INTO @r
	SELECT 1, 'Pólizas descuadradas (Debe distinto del Haber)', COUNT(*), MIN(CAST(asi_id AS VARCHAR(20)))
	FROM (SELECT asi_id FROM dbo.cont_asiento_det GROUP BY asi_id HAVING SUM(asd_debe) <> SUM(asd_haber)) desc_;

	INSERT INTO @r
	SELECT 2, 'Líneas de póliza en cuentas de agrupación', COUNT(*), MIN(CONCAT('póliza ', deta.asi_id, ' cuenta ', cuen.cta_codigo))
	FROM dbo.cont_asiento_det deta INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = deta.cta_id
	WHERE cuen.cta_acepta_movimiento = 0;

	INSERT INTO @r
	SELECT 3, 'Documentos vigentes sin póliza vigente', COUNT(*), MIN(CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_numero_unico, docu.enc_numero_docto)))
	FROM dbo.inv_documento_enc docu
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	WHERE docu.enc_estado = 'G' AND tipo.tdo_codigo <> 'INVI'
	  AND NOT EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.enc_id = docu.enc_id AND asie.asi_estado = 'A')
	  AND NOT EXISTS (SELECT 1 FROM dbo.inv_traslado tras WHERE docu.enc_id IN (tras.enc_id_salida, tras.enc_id_ingreso, tras.enc_id_devolucion));

	INSERT INTO @r
	SELECT 4, 'Documentos anulados con póliza vigente', COUNT(*), MIN(CAST(docu.enc_id AS VARCHAR(20)))
	FROM dbo.inv_documento_enc docu
	WHERE docu.enc_estado = 'A' AND EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.enc_id = docu.enc_id AND asie.asi_estado = 'A'
											 AND asie.asi_origen NOT IN ('PAGO_CLIENTE', 'PAGO_PROVEEDOR'));

	INSERT INTO @r
	-- La nota de crédito rebaja el saldo de la cuota; la de débito crea una
	-- cuota nueva por su monto (no se resta).
	SELECT 5, 'Cuotas de clientes: saldo distinto de valor - cobros vigentes - notas de crédito', COUNT(*), MIN(CAST(cuot.cpp_id AS VARCHAR(20)))
	FROM dbo.pos_cliente_plan_pagos cuot
	CROSS APPLY (SELECT ISNULL(SUM(deta.ppd_valor_aplicado), 0) AS Cobrado
				 FROM dbo.pos_pago_det deta INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id
				 WHERE deta.cpp_id = cuot.cpp_id AND pago.ppe_estado = 'A') cobr
	CROSS APPLY (SELECT ISNULL(SUM(apli.cna_monto), 0) AS Notas
				 FROM dbo.pos_cliente_nota_aplicacion apli
				 INNER JOIN dbo.inv_documento_enc nota ON nota.enc_id = apli.enc_id_nota
				 INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = nota.tdo_id
				 WHERE apli.cpp_id = cuot.cpp_id AND tipo.tdo_codigo = 'NCC') nota
	WHERE ABS(cuot.cpp_valor_cuota - cobr.Cobrado - nota.Notas - cuot.cpp_saldo_cuota) > 0.01;

	INSERT INTO @r
	-- Las notas a proveedores cambian el valor de la cuota (o crean una), no lo pagado.
	SELECT 6, 'Cuotas de proveedores: pagado distinto de los cheques y transferencias vigentes', COUNT(*), MIN(CAST(cuot.ppg_id AS VARCHAR(20)))
	FROM dbo.inv_proveedor_plan_pago cuot
	CROSS APPLY (SELECT ISNULL(SUM(deta.ced_valor), 0) AS Pagado
				 FROM dbo.bco_cheque_emitido_det deta INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = deta.bce_id
				 WHERE deta.ppg_id = cuot.ppg_id AND cheq.bce_estado_cheque <> 'A') cheq
	CROSS APPLY (SELECT ISNULL(SUM(blcu.blc_monto), 0) AS Pagado
				 FROM dbo.bco_lote_transferencia_cuota blcu
				 INNER JOIN dbo.bco_lote_transferencia_det line ON line.bld_id = blcu.bld_id
				 INNER JOIN dbo.bco_lote_transferencia lote ON lote.blt_id = line.blt_id AND lote.blt_estado = 'A'
				 WHERE blcu.ppg_id = cuot.ppg_id) trns
	WHERE ABS(ISNULL(cuot.ppg_valor_real_pago, 0) - cheq.Pagado - trns.Pagado) > 0.01
	   OR ISNULL(cuot.ppg_valor_real_pago, 0) > cuot.ppg_valor_pago + 0.01;

	INSERT INTO @r
	SELECT 7, 'Existencias negativas', COUNT(*), MIN(CONCAT('producto ', pro_id, ' bodega ', bod_id))
	FROM dbo.inv_producto_existencia_bodega WHERE existencia < 0;

	INSERT INTO @r
	SELECT 8, 'Nóminas aprobadas sin póliza vigente', COUNT(*), MIN(nomi.Descripcion)
	FROM dbo.rrhhNomina nomi
	WHERE nomi.Estado = 'A' AND NOT EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.asi_origen = 'NOMINA' AND asie.asi_origen_id = nomi.IdNomina AND asie.asi_estado = 'A');

	INSERT INTO @r
	SELECT 9, 'Pagos de nómina vigentes que no suman el líquido de sus empleados', COUNT(*), MIN(CAST(pago.IdNominaPago AS VARCHAR(20)))
	FROM dbo.rrhhNominaPago pago
	CROSS APPLY (SELECT ISNULL(SUM(nemp.Liquido), 0) AS Liquido FROM dbo.rrhhNominaEmpleado nemp WHERE nemp.IdNominaPago = pago.IdNominaPago) suma
	WHERE pago.Estado = 'A' AND pago.Monto <> suma.Liquido;

	INSERT INTO @r
	SELECT 10, 'Empleados pagados en una nómina no aprobada', COUNT(*), MIN(CAST(nemp.IdNominaEmpleado AS VARCHAR(20)))
	FROM dbo.rrhhNominaEmpleado nemp INNER JOIN dbo.rrhhNomina nomi ON nomi.IdNomina = nemp.IdNomina
	WHERE nemp.IdNominaPago IS NOT NULL AND nomi.Estado <> 'A';

	INSERT INTO @r
	SELECT 11, 'Traslados en tránsito sin salida de inventario', COUNT(*), MIN(CAST(tras.tra_numero AS VARCHAR(20)))
	FROM dbo.inv_traslado tras
	WHERE tras.tra_estado = 'E' AND (tras.enc_id_salida IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.inv_documento_enc docu WHERE docu.enc_id = tras.enc_id_salida AND docu.enc_estado = 'G'));

	INSERT INTO @r
	SELECT 12, 'Recibos vigentes sin póliza vigente', COUNT(*), MIN(CAST(pago.ppe_id AS VARCHAR(20)))
	FROM dbo.pos_pago_enc pago
	WHERE pago.ppe_estado = 'A'
	  AND NOT EXISTS (SELECT 1 FROM dbo.pos_pago_det deta WHERE deta.ppe_id = pago.ppe_id AND deta.enc_id IS NOT NULL)
	  AND NOT EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.asi_origen = 'PAGO_CLIENTE' AND asie.asi_origen_id = pago.ppe_id AND asie.asi_estado = 'A');

	INSERT INTO @r
	-- Script 51: una nota se aplica completa a las cuotas o no se graba.
	SELECT 13, 'Notas vigentes cuyo total no coincide con lo aplicado a las cuotas', COUNT(*), MIN(CONCAT(tipo.tdo_codigo, ' ', ISNULL(nota.enc_numero_unico, nota.enc_numero_docto)))
	FROM dbo.inv_documento_enc nota
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = nota.tdo_id
	CROSS APPLY (SELECT ISNULL((SELECT SUM(apli.cna_monto) FROM dbo.pos_cliente_nota_aplicacion apli WHERE apli.enc_id_nota = nota.enc_id), 0)
					  + ISNULL((SELECT SUM(apli.pna_monto) FROM dbo.inv_proveedor_nota_aplicacion apli WHERE apli.enc_id_nota = nota.enc_id), 0) AS Aplicado) apli
	WHERE tipo.tdo_es_nota = 1 AND nota.enc_estado = 'G'
	  AND (EXISTS (SELECT 1 FROM dbo.pos_cliente_nota_aplicacion x WHERE x.enc_id_nota = nota.enc_id)
		   OR EXISTS (SELECT 1 FROM dbo.inv_proveedor_nota_aplicacion x WHERE x.enc_id_nota = nota.enc_id))
	  AND ABS(nota.enc_monto_total - apli.Aplicado) > 0.01;

	-- Script 65: caja chica, activos fijos, conciliación y estados financieros.
	INSERT INTO @r
	SELECT 14, 'Liquidaciones de caja chica vigentes sin póliza vigente', COUNT(*), MIN(liqu.lcc_numero)
	FROM dbo.cch_liquidacion liqu
	WHERE liqu.lcc_estado = 'V'
	  AND NOT EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.asi_id = liqu.asi_id AND asie.asi_estado = 'A');

	INSERT INTO @r
	SELECT 15, 'Caja chica: saldo de la cuenta distinto del fondo menos lo liquidado sin reponer', COUNT(*), MIN(fondo.Cuenta)
	FROM (SELECT fond.cta_id, MIN(cuen.cta_codigo) AS Cuenta, SUM(sald.Constituido - sald.PorReponer) AS Esperado
		  FROM dbo.cch_fondo fond
		  INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = fond.cta_id
		  CROSS APPLY dbo.fnCajaChicaSaldo(fond.cch_id) sald
		  GROUP BY fond.cta_id) fondo
	WHERE fondo.Esperado <> (SELECT ISNULL(SUM(deta.asd_debe - deta.asd_haber), 0) FROM dbo.cont_asiento_det deta
							 INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id AND asie.asi_estado = 'A'
							 WHERE deta.cta_id = fondo.cta_id);

	INSERT INTO @r
	SELECT 16, 'Depreciaciones vigentes sin póliza vigente', COUNT(*), MIN(CONCAT(corr.adc_mes, '/', corr.adc_anio))
	FROM dbo.afi_depreciacion_corrida corr
	WHERE corr.adc_estado = 'V'
	  AND NOT EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.asi_id = corr.asi_id AND asie.asi_estado = 'A');

	INSERT INTO @r
	SELECT 17, 'Activos fijos con depreciación acumulada mayor que el costo menos el valor residual', COUNT(*), MIN(acfi.afa_codigo)
	FROM dbo.afi_activo acfi INNER JOIN dbo.fnActivoFijoSaldo() sald ON sald.afa_id = acfi.afa_id
	WHERE sald.Acumulada > acfi.afa_costo - acfi.afa_valor_residual;

	INSERT INTO @r
	SELECT 18, 'Movimientos conciliados con el banco cuya póliza se anuló después', COUNT(*), MIN(CONCAT('póliza ', asie.asi_id))
	FROM dbo.bco_conciliacion_libro libr
	INNER JOIN dbo.cont_asiento_det deta ON deta.asd_id = libr.asd_id
	INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id AND asie.asi_estado <> 'A';

	INSERT INTO @r
	SELECT 19, 'Balance General que no cuadra (activo distinto de pasivo + capital + resultados)', IIF(SUM(deta.asd_debe - deta.asd_haber) <> 0, 1, 0), NULL
	FROM dbo.cont_asiento_det deta
	INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id AND asie.asi_estado = 'A'
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = deta.cta_id AND cuen.cta_tipo IN ('A', 'P', 'K', 'I', 'G');

	SELECT Orden, Control, Casos, CASE WHEN Casos = 0 THEN NULL ELSE Ejemplo END AS Ejemplo,
		   CASE WHEN Casos = 0 THEN 'OK' ELSE 'REVISAR' END AS Resultado
	FROM @r ORDER BY Orden;
END;
GO

PRINT '65_integridad_fase3.sql aplicado.';
GO
