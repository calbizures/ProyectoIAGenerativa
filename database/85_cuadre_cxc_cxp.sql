/*
================================================================================
 85_cuadre_cxc_cxp.sql
 Cuadre de Cuentas por cobrar y por pagar con contabilidad, explicado.

 El saldo de las cuotas (el de la antigüedad de saldos) debe ser igual al de
 la cuenta contable de clientes (VENTA_CLIENTES) o de proveedores
 (COMPRA_PROVEEDORES). Cuando no lo es, este script dice POR QUÉ, partida por
 partida, en tres grupos que suman la diferencia:

   D  Documentos: el valor de las cuotas de una factura o compra (con sus
      notas) no coincide con lo que su póliza cargó a la cuenta. Ej.: una
      compra al contado sin cuota, una factura anulada con póliza vigente.
   P  Cobros y pagos: lo aplicado a cuotas de documentos vigentes no coincide
      con la póliza del recibo, cheque o transferencia. Ej.: un cobro
      aplicado a una factura que después se anuló.
   O  Pólizas directas: movimientos en la cuenta que no vienen de los módulos
      de clientes o proveedores (pólizas manuales, partida de apertura, otro
      módulo). No tienen cuotas que los respalden.

 Lo que no explican esos grupos queda como "sin explicar": saldos de cuotas
 que no coinciden con sus cobros o pagos (controles 5 y 6) o documentos con
 fecha futura.

   fnAuditoriaSubmayorSaldos(@Modulo)       saldo de cuotas y de la cuenta.
   fnAuditoriaSubmayorPartidas(@Modulo)     partidas que explican la diferencia.
   paAuditoriaCuadreSubmayorConsultar       resumen y partidas para la pantalla.
   paAuditoriaIntegridadConsultar           controles 20 a 24 nuevos, y el área
                                            y el detalle de cada control.

 @Modulo: 'CXC' (clientes) o 'CXP' (proveedores).
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Saldos: cuotas (como la antigüedad) y cuenta contable
------------------------------------------------------------
CREATE OR ALTER FUNCTION [dbo].[fnAuditoriaSubmayorSaldos] (@Modulo CHAR(3))
RETURNS TABLE
AS
RETURN
	SELECT para.cta_id AS CtaId, cuen.cta_codigo AS CuentaCodigo, cuen.cta_nombre AS CuentaNombre,
		   CAST(CASE @Modulo
				WHEN 'CXC' THEN (SELECT ISNULL(SUM(cuot.cpp_saldo_cuota), 0)
								 FROM dbo.pos_cliente_plan_pagos cuot
								 INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
								 WHERE cuot.cpp_saldo_cuota > 0 AND docu.enc_fecha_docto <= CAST(GETDATE() AS DATE))
				ELSE (SELECT ISNULL(SUM(cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0)), 0)
					  FROM dbo.inv_proveedor_plan_pago cuot
					  INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
					  WHERE cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) > 0
						AND docu.enc_fecha_docto <= CAST(GETDATE() AS DATE))
		   END AS NUMERIC(14, 2)) AS SaldoCuotas,
		   -- Clientes es deudora (debe - haber); proveedores, acreedora (haber - debe).
		   CAST((SELECT ISNULL(SUM(CASE @Modulo WHEN 'CXC' THEN deta.asd_debe - deta.asd_haber ELSE deta.asd_haber - deta.asd_debe END), 0)
				 FROM dbo.cont_asiento_det deta
				 INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id AND asie.asi_estado = 'A'
				 WHERE deta.cta_id = para.cta_id) AS NUMERIC(14, 2)) AS SaldoContable
	FROM dbo.cont_cuenta_parametro para
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = para.cta_id
	WHERE para.ccp_codigo = CASE @Modulo WHEN 'CXC' THEN 'VENTA_CLIENTES' ELSE 'COMPRA_PROVEEDORES' END;
GO

------------------------------------------------------------
-- 2. Partidas que explican la diferencia (cuotas - contabilidad)
------------------------------------------------------------
CREATE OR ALTER FUNCTION [dbo].[fnAuditoriaSubmayorPartidas] (@Modulo CHAR(3))
RETURNS @partidas TABLE (
	Grupo		CHAR(1),			-- D documentos, P cobros y pagos, O pólizas directas
	Fecha		DATE NULL,
	Referencia	NVARCHAR(120) NULL,
	Tercero		NVARCHAR(260) NULL,
	TerceroId	INT NULL,
	Descripcion	NVARCHAR(250) NULL,
	Submodulo	NUMERIC(14, 2),		-- lo que dicen las cuotas
	Contable	NUMERIC(14, 2),		-- lo que dice la cuenta
	Efecto		NUMERIC(14, 2),		-- Submodulo - Contable: cuánto explica de la diferencia
	AsiId		INT NULL,
	EncId		INT NULL,
	PagoId		INT NULL,
	Diagnostico	NVARCHAR(300) NULL
)
AS
BEGIN
	DECLARE @cta INT = (SELECT CtaId FROM dbo.fnAuditoriaSubmayorSaldos(@Modulo));
	IF @cta IS NULL RETURN;

	-- Movimientos vigentes de la cuenta, con el signo del saldo.
	DECLARE @mov TABLE (asi_id INT PRIMARY KEY, origen VARCHAR(30), origen_id INT, enc_id INT, fecha DATE, descripcion NVARCHAR(250), neto NUMERIC(14, 2));
	INSERT INTO @mov
	SELECT asie.asi_id, asie.asi_origen, asie.asi_origen_id, asie.enc_id, asie.asi_fecha, asie.asi_descripcion,
		   SUM(CASE @Modulo WHEN 'CXC' THEN deta.asd_debe - deta.asd_haber ELSE deta.asd_haber - deta.asd_debe END)
	FROM dbo.cont_asiento_det deta
	INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id AND asie.asi_estado = 'A'
	WHERE deta.cta_id = @cta
	GROUP BY asie.asi_id, asie.asi_origen, asie.asi_origen_id, asie.enc_id, asie.asi_fecha, asie.asi_descripcion;

	-- Documento "dueño" de cada documento: la nota se cuenta con su factura o compra.
	-- inicial: documento pendiente cargado al arrancar (script 86), sin póliza propia:
	-- su valor está en la partida de apertura y se compara con ella aparte.
	DECLARE @docs TABLE (enc_id INT PRIMARY KEY, clave INT, vigente BIT, inicial BIT, monto NUMERIC(14, 2));
	INSERT INTO @docs
	SELECT docu.enc_id, CASE WHEN tipo.tdo_es_nota = 1 THEN ISNULL(docu.enc_id_referencia, docu.enc_id) ELSE docu.enc_id END,
		   IIF(docu.enc_estado = 'G', 1, 0), IIF(tipo.tdo_codigo IN ('SIFAC', 'SICOM'), 1, 0), docu.enc_monto_total
	FROM dbo.inv_documento_enc docu
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	WHERE (@Modulo = 'CXC' AND docu.cli_id IS NOT NULL) OR (@Modulo = 'CXP' AND docu.prv_id IS NOT NULL);

	DECLARE @porDocumento TABLE (clave INT PRIMARY KEY, submodulo NUMERIC(14, 2), contable NUMERIC(14, 2));

	IF @Modulo = 'CXC'
	BEGIN
		------------------------------------------------------------
		-- CxC · D: valor de las cuotas menos notas de crédito aplicadas,
		-- contra lo que cargaron a Clientes la venta y sus notas.
		------------------------------------------------------------
		INSERT INTO @porDocumento
		SELECT clave, SUM(submodulo), SUM(contable)
		FROM (
			SELECT docs.clave, cuot.cpp_valor_cuota
				   - ISNULL((SELECT SUM(apli.cna_monto) FROM dbo.pos_cliente_nota_aplicacion apli
							 INNER JOIN dbo.inv_documento_enc nota ON nota.enc_id = apli.enc_id_nota AND nota.enc_estado = 'G'
							 INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = nota.tdo_id AND tipo.tdo_codigo = 'NCC'
							 WHERE apli.cpp_id = cuot.cpp_id), 0) AS submodulo, 0 AS contable
			FROM dbo.pos_cliente_plan_pagos cuot
			INNER JOIN @docs docs ON docs.enc_id = cuot.enc_id AND docs.vigente = 1
			UNION ALL
			SELECT docs.clave, 0, movi.neto
			FROM @mov movi INNER JOIN @docs docs ON docs.enc_id = movi.enc_id
			WHERE movi.origen IN ('VENTA', 'NOTA_CREDITO', 'NOTA_DEBITO')
			UNION ALL
			SELECT docs.clave, 0, docs.monto FROM @docs docs WHERE docs.inicial = 1 AND docs.vigente = 1
		) partes
		GROUP BY clave;

		------------------------------------------------------------
		-- CxC · P: lo aplicado por cada recibo vigente a cuotas de facturas
		-- vigentes, contra su póliza (que abona Clientes).
		------------------------------------------------------------
		INSERT INTO @partidas
		SELECT 'P', CAST(pago.ppe_fecha_pago AS DATE), CONCAT(N'Recibo #', reci.ppe_id),
			   CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos), clie.cli_id, NULL,
			   -reci.aplicado, reci.contable, -reci.aplicado - reci.contable,
			   reci.asi_id, NULL, reci.ppe_id,
			   CASE WHEN reci.contable = 0 THEN N'El cobro rebaja cuotas pero no tiene póliza vigente.'
					WHEN reci.aplicado = 0 THEN N'La póliza del cobro sigue vigente, pero el cobro está anulado o se aplicó a facturas anuladas.'
					ELSE N'Parte del cobro está aplicada a una factura anulada: su póliza abonó a clientes un monto que ya no está en las cuotas.' END
		FROM (
			SELECT ids.ppe_id,
				   ISNULL((SELECT SUM(deta.ppd_valor_aplicado) FROM dbo.pos_pago_det deta
						   INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
						   INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = deta.cpp_id
						   INNER JOIN @docs docs ON docs.enc_id = cuot.enc_id AND docs.vigente = 1
						   WHERE deta.ppe_id = ids.ppe_id), 0) AS aplicado,
				   ISNULL((SELECT SUM(movi.neto) FROM @mov movi WHERE movi.origen = 'PAGO_CLIENTE' AND movi.origen_id = ids.ppe_id), 0) AS contable,
				   (SELECT MIN(movi.asi_id) FROM @mov movi WHERE movi.origen = 'PAGO_CLIENTE' AND movi.origen_id = ids.ppe_id) AS asi_id
			FROM (SELECT deta.ppe_id FROM dbo.pos_pago_det deta WHERE deta.cpp_id IS NOT NULL
				  UNION SELECT movi.origen_id FROM @mov movi WHERE movi.origen = 'PAGO_CLIENTE' AND movi.origen_id IS NOT NULL) ids
		) reci
		INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = reci.ppe_id
		LEFT JOIN dbo.pos_cliente clie ON clie.cli_id = pago.cli_id
		WHERE ABS(-reci.aplicado - reci.contable) >= 0.005;

		-- O: lo que no viene de ventas, notas o cobros (o no dice de cuál).
		INSERT INTO @partidas
		SELECT 'O', movi.fecha, CONCAT(N'Póliza #', movi.asi_id), NULL, NULL, movi.descripcion,
			   0, movi.neto, -movi.neto, movi.asi_id, NULL, NULL,
			   CASE movi.origen
					WHEN 'APERTURA' THEN N'Saldo inicial cargado a la cuenta sin las facturas pendientes de cada cliente.'
					WHEN 'MANUAL' THEN N'Póliza manual en la cuenta de clientes: no tiene cuotas que la respalden.'
					ELSE CONCAT(N'Póliza de otro módulo (', movi.origen, N') en la cuenta de clientes.') END
		FROM @mov movi
		WHERE NOT ((movi.origen IN ('VENTA', 'NOTA_CREDITO', 'NOTA_DEBITO') AND movi.enc_id IN (SELECT enc_id FROM @docs))
				OR (movi.origen = 'PAGO_CLIENTE' AND movi.origen_id IS NOT NULL)
				OR movi.origen = 'APERTURA');
	END
	ELSE
	BEGIN
		------------------------------------------------------------
		-- CxP · D: valor de las cuotas (las notas ya lo ajustan) contra lo que
		-- abonaron a Proveedores la compra y sus notas.
		------------------------------------------------------------
		INSERT INTO @porDocumento
		SELECT clave, SUM(submodulo), SUM(contable)
		FROM (
			SELECT docs.clave, cuot.ppg_valor_pago AS submodulo, 0 AS contable
			FROM dbo.inv_proveedor_plan_pago cuot
			INNER JOIN @docs docs ON docs.enc_id = cuot.enc_id AND docs.vigente = 1
			UNION ALL
			SELECT docs.clave, 0, movi.neto
			FROM @mov movi INNER JOIN @docs docs ON docs.enc_id = movi.enc_id
			WHERE movi.origen IN ('COMPRA', 'NOTA_CREDITO', 'NOTA_DEBITO')
			UNION ALL
			SELECT docs.clave, 0, docs.monto FROM @docs docs WHERE docs.inicial = 1 AND docs.vigente = 1
		) partes
		GROUP BY clave;

		------------------------------------------------------------
		-- CxP · P: cheques y transferencias. Lo aplicado a cuotas de compras
		-- vigentes contra su póliza (que carga Proveedores).
		------------------------------------------------------------
		INSERT INTO @partidas
		SELECT 'P', cheq.bce_fecha_emision, CONCAT(N'Cheque ', cheq.bce_numero_cheque), cheq.bce_beneficiario, NULL, NULL,
			   -pago.aplicado, pago.contable, -pago.aplicado - pago.contable, pago.asi_id, NULL, pago.bce_id,
			   CASE WHEN pago.contable = 0 THEN N'El cheque rebaja cuotas pero no tiene póliza vigente.'
					WHEN pago.aplicado = 0 THEN N'La póliza del cheque sigue vigente, pero el cheque está anulado o pagó compras anuladas.'
					ELSE N'Parte del cheque pagó una compra anulada: su póliza cargó a proveedores un monto que ya no está en las cuotas.' END
		FROM (
			SELECT ids.bce_id,
				   ISNULL((SELECT SUM(deta.ced_valor) FROM dbo.bco_cheque_emitido_det deta
						   INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = deta.bce_id AND cheq.bce_estado_cheque <> 'A'
						   INNER JOIN dbo.inv_proveedor_plan_pago cuot ON cuot.ppg_id = deta.ppg_id
						   INNER JOIN @docs docs ON docs.enc_id = cuot.enc_id AND docs.vigente = 1
						   WHERE deta.bce_id = ids.bce_id), 0) AS aplicado,
				   ISNULL((SELECT SUM(movi.neto) FROM @mov movi WHERE movi.origen = 'PAGO_PROVEEDOR' AND movi.origen_id = ids.bce_id), 0) AS contable,
				   (SELECT MIN(movi.asi_id) FROM @mov movi WHERE movi.origen = 'PAGO_PROVEEDOR' AND movi.origen_id = ids.bce_id) AS asi_id
			FROM (SELECT deta.bce_id FROM dbo.bco_cheque_emitido_det deta WHERE deta.ppg_id IS NOT NULL
				  UNION SELECT movi.origen_id FROM @mov movi WHERE movi.origen = 'PAGO_PROVEEDOR' AND movi.origen_id IS NOT NULL) ids
		) pago
		INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = pago.bce_id
		WHERE ABS(-pago.aplicado - pago.contable) >= 0.005;

		INSERT INTO @partidas
		SELECT 'P', lote.blt_fecha, CONCAT(N'Transferencias, lote ', lote.blt_numero), NULL, NULL, NULL,
			   -pago.aplicado, pago.contable, -pago.aplicado - pago.contable, pago.asi_id, NULL, pago.blt_id,
			   CASE WHEN pago.contable = 0 THEN N'El lote de transferencias rebaja cuotas pero no tiene póliza vigente.'
					WHEN pago.aplicado = 0 THEN N'La póliza del lote sigue vigente, pero el lote está anulado o pagó compras anuladas.'
					ELSE N'Parte del lote pagó una compra anulada: su póliza cargó a proveedores un monto que ya no está en las cuotas.' END
		FROM (
			SELECT ids.blt_id,
				   ISNULL((SELECT SUM(blcu.blc_monto) FROM dbo.bco_lote_transferencia_cuota blcu
						   INNER JOIN dbo.bco_lote_transferencia_det line ON line.bld_id = blcu.bld_id
						   INNER JOIN dbo.bco_lote_transferencia lote ON lote.blt_id = line.blt_id AND lote.blt_estado = 'A'
						   INNER JOIN dbo.inv_proveedor_plan_pago cuot ON cuot.ppg_id = blcu.ppg_id
						   INNER JOIN @docs docs ON docs.enc_id = cuot.enc_id AND docs.vigente = 1
						   WHERE line.blt_id = ids.blt_id), 0) AS aplicado,
				   ISNULL((SELECT SUM(movi.neto) FROM @mov movi WHERE movi.origen = 'PAGO_TRANSFERENCIA' AND movi.origen_id = ids.blt_id), 0) AS contable,
				   (SELECT MIN(movi.asi_id) FROM @mov movi WHERE movi.origen = 'PAGO_TRANSFERENCIA' AND movi.origen_id = ids.blt_id) AS asi_id
			FROM (SELECT line.blt_id FROM dbo.bco_lote_transferencia_cuota blcu
				  INNER JOIN dbo.bco_lote_transferencia_det line ON line.bld_id = blcu.bld_id WHERE blcu.ppg_id IS NOT NULL
				  UNION SELECT movi.origen_id FROM @mov movi WHERE movi.origen = 'PAGO_TRANSFERENCIA' AND movi.origen_id IS NOT NULL) ids
		) pago
		INNER JOIN dbo.bco_lote_transferencia lote ON lote.blt_id = pago.blt_id
		WHERE ABS(-pago.aplicado - pago.contable) >= 0.005;

		INSERT INTO @partidas
		SELECT 'O', movi.fecha, CONCAT(N'Póliza #', movi.asi_id), NULL, NULL, movi.descripcion,
			   0, movi.neto, -movi.neto, movi.asi_id, NULL, NULL,
			   CASE movi.origen
					WHEN 'APERTURA' THEN N'Saldo inicial cargado a la cuenta sin las compras pendientes de cada proveedor.'
					WHEN 'MANUAL' THEN N'Póliza manual en la cuenta de proveedores: no tiene cuotas que la respalden.'
					ELSE CONCAT(N'Póliza de otro módulo (', movi.origen, N') en la cuenta de proveedores.') END
		FROM @mov movi
		WHERE NOT ((movi.origen IN ('COMPRA', 'NOTA_CREDITO', 'NOTA_DEBITO') AND movi.enc_id IN (SELECT enc_id FROM @docs))
				OR (movi.origen IN ('PAGO_PROVEEDOR', 'PAGO_TRANSFERENCIA') AND movi.origen_id IS NOT NULL)
				OR movi.origen = 'APERTURA');
	END

	-- O: la partida de apertura contra los documentos pendientes iniciales (86).
	DECLARE @inicial NUMERIC(14, 2) = (SELECT ISNULL(SUM(monto), 0) FROM @docs WHERE inicial = 1 AND vigente = 1),
			@apertura NUMERIC(14, 2) = (SELECT ISNULL(SUM(neto), 0) FROM @mov WHERE origen = 'APERTURA');
	IF ABS(@inicial - @apertura) >= 0.005
		INSERT INTO @partidas
		SELECT 'O', (SELECT MAX(fecha) FROM @mov WHERE origen = 'APERTURA'), N'Partida de apertura', NULL, NULL, NULL,
			   @inicial, @apertura, @inicial - @apertura, (SELECT MAX(asi_id) FROM @mov WHERE origen = 'APERTURA'), NULL, NULL,
			   CASE WHEN @inicial = 0 AND @Modulo = 'CXC' THEN N'La apertura llevó saldo a la cuenta de clientes, pero no se han cargado las facturas pendientes: cárguelas en Cuentas por cobrar › Saldos iniciales.'
					WHEN @inicial = 0 THEN N'La apertura llevó saldo a la cuenta de proveedores, pero no se han cargado las compras pendientes: cárguelas en Cuentas por pagar › Saldos iniciales.'
					WHEN @apertura = 0 THEN N'Hay documentos pendientes cargados como saldo inicial, pero la partida de apertura no lleva saldo a la cuenta.'
					ELSE N'Los documentos pendientes cargados como saldo inicial no suman lo que la partida de apertura llevó a la cuenta.' END;

	-- D: un renglón por documento que no cuadra.
	INSERT INTO @partidas
	SELECT 'D', docu.enc_fecha_docto,
		   CONCAT(tipo.tdo_codigo, N' ', ISNULL(docu.enc_numero_unico, CONCAT(docu.enc_serie_docto, IIF(docu.enc_serie_docto IS NULL, '', '-'), docu.enc_numero_docto))),
		   CASE WHEN @Modulo = 'CXC' THEN CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos) ELSE prov.prv_nombre_comercial END,
		   ISNULL(docu.cli_id, docu.prv_id), NULL,
		   pdoc.submodulo, pdoc.contable, pdoc.submodulo - pdoc.contable,
		   (SELECT MIN(movi.asi_id) FROM @mov movi WHERE movi.enc_id = pdoc.clave), pdoc.clave, NULL,
		   CASE WHEN docu.enc_estado <> 'G' AND pdoc.contable <> 0 THEN N'El documento está anulado pero su póliza sigue vigente.'
				WHEN pdoc.submodulo = 0 THEN CASE @Modulo WHEN 'CXC' THEN N'La factura tiene póliza con cargo a clientes pero no tiene cuotas por cobrar.'
														ELSE N'La compra tiene póliza con abono a proveedores pero no tiene cuotas por pagar (p. ej., compra al contado sin cuota).' END
				WHEN pdoc.contable = 0 THEN N'El documento tiene cuotas pero no tiene póliza vigente en la cuenta.'
				ELSE N'El valor de las cuotas no coincide con el monto que la póliza llevó a la cuenta.' END
	FROM @porDocumento pdoc
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = pdoc.clave
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	LEFT JOIN dbo.pos_cliente clie ON clie.cli_id = docu.cli_id
	LEFT JOIN dbo.inv_proveedor prov ON prov.prv_id = docu.prv_id
	WHERE ABS(pdoc.submodulo - pdoc.contable) >= 0.005;

	RETURN;
END;
GO

------------------------------------------------------------
-- 3. Para la pantalla: resumen y partidas
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paAuditoriaCuadreSubmayorConsultar]
	@Modulo	CHAR(3)
AS
BEGIN
	SET NOCOUNT ON;
	IF @Modulo NOT IN ('CXC', 'CXP')
		THROW 55980, 'El módulo debe ser CXC o CXP.', 1;

	DECLARE @partidas TABLE (Grupo CHAR(1), Fecha DATE, Referencia NVARCHAR(120), Tercero NVARCHAR(260), TerceroId INT,
		Descripcion NVARCHAR(250), Submodulo NUMERIC(14, 2), Contable NUMERIC(14, 2), Efecto NUMERIC(14, 2),
		AsiId INT, EncId INT, PagoId INT, Diagnostico NVARCHAR(300));
	INSERT INTO @partidas SELECT * FROM dbo.fnAuditoriaSubmayorPartidas(@Modulo);

	SELECT @Modulo AS Modulo, sald.CtaId, sald.CuentaCodigo, sald.CuentaNombre, sald.SaldoCuotas, sald.SaldoContable,
		   sald.SaldoCuotas - sald.SaldoContable AS Diferencia,
		   ISNULL((SELECT SUM(Efecto) FROM @partidas WHERE Grupo = 'D'), 0) AS Documentos,
		   ISNULL((SELECT SUM(Efecto) FROM @partidas WHERE Grupo = 'P'), 0) AS Pagos,
		   ISNULL((SELECT SUM(Efecto) FROM @partidas WHERE Grupo = 'O'), 0) AS Directas,
		   sald.SaldoCuotas - sald.SaldoContable - ISNULL((SELECT SUM(Efecto) FROM @partidas), 0) AS SinExplicar
	FROM dbo.fnAuditoriaSubmayorSaldos(@Modulo) sald;

	SELECT Grupo, Fecha, Referencia, Tercero, TerceroId, Descripcion, Submodulo, Contable, Efecto, AsiId, EncId, PagoId, Diagnostico
	FROM @partidas
	ORDER BY CASE Grupo WHEN 'O' THEN 1 WHEN 'D' THEN 2 ELSE 3 END, ABS(Efecto) DESC, Fecha;
END;
GO

------------------------------------------------------------
-- 4. Revisión de integridad: controles 20 a 24, área y detalle
------------------------------------------------------------
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
	-- Inventario inicial y documentos pendientes iniciales (86): su valor está en la apertura.
	WHERE docu.enc_estado = 'G' AND tipo.tdo_codigo NOT IN ('INVI', 'SIFAC', 'SICOM')
	  AND NOT EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.enc_id = docu.enc_id AND asie.asi_estado = 'A')
	  AND NOT EXISTS (SELECT 1 FROM dbo.inv_traslado tras WHERE docu.enc_id IN (tras.enc_id_salida, tras.enc_id_ingreso, tras.enc_id_devolucion));

	INSERT INTO @r
	SELECT 4, 'Documentos anulados con póliza vigente', COUNT(*), MIN(CAST(docu.enc_id AS VARCHAR(20)))
	FROM dbo.inv_documento_enc docu
	WHERE docu.enc_estado = 'A' AND EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.enc_id = docu.enc_id AND asie.asi_estado = 'A'
											 AND asie.asi_origen NOT IN ('PAGO_CLIENTE', 'PAGO_PROVEEDOR'));

	INSERT INTO @r
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
	SELECT 13, 'Notas vigentes cuyo total no coincide con lo aplicado a las cuotas', COUNT(*), MIN(CONCAT(tipo.tdo_codigo, ' ', ISNULL(nota.enc_numero_unico, nota.enc_numero_docto)))
	FROM dbo.inv_documento_enc nota
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = nota.tdo_id
	CROSS APPLY (SELECT ISNULL((SELECT SUM(apli.cna_monto) FROM dbo.pos_cliente_nota_aplicacion apli WHERE apli.enc_id_nota = nota.enc_id), 0)
					  + ISNULL((SELECT SUM(apli.pna_monto) FROM dbo.inv_proveedor_nota_aplicacion apli WHERE apli.enc_id_nota = nota.enc_id), 0) AS Aplicado) apli
	WHERE tipo.tdo_es_nota = 1 AND nota.enc_estado = 'G'
	  AND (EXISTS (SELECT 1 FROM dbo.pos_cliente_nota_aplicacion x WHERE x.enc_id_nota = nota.enc_id)
		   OR EXISTS (SELECT 1 FROM dbo.inv_proveedor_nota_aplicacion x WHERE x.enc_id_nota = nota.enc_id))
	  AND ABS(nota.enc_monto_total - apli.Aplicado) > 0.01;

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

	-- Script 85: cuadre de los submódulos con contabilidad.
	INSERT INTO @r
	SELECT 20, 'Cuentas por cobrar: el saldo de las cuotas no cuadra con la cuenta de clientes',
		   IIF(ABS(SaldoCuotas - SaldoContable) >= 0.01, 1, 0),
		   CONCAT('Diferencia ', FORMAT(SaldoCuotas - SaldoContable, 'N2'))
	FROM dbo.fnAuditoriaSubmayorSaldos('CXC');

	INSERT INTO @r
	SELECT 21, 'Cuentas por pagar: el saldo de las cuotas no cuadra con la cuenta de proveedores',
		   IIF(ABS(SaldoCuotas - SaldoContable) >= 0.01, 1, 0),
		   CONCAT('Diferencia ', FORMAT(SaldoCuotas - SaldoContable, 'N2'))
	FROM dbo.fnAuditoriaSubmayorSaldos('CXP');

	INSERT INTO @r
	SELECT 22, 'Cobros vigentes aplicados a facturas anuladas', COUNT(DISTINCT pago.ppe_id), MIN(CONCAT('recibo ', pago.ppe_id))
	FROM dbo.pos_pago_det deta
	INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
	INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = deta.cpp_id
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado <> 'G';

	INSERT INTO @r
	SELECT 23, 'Cheques o transferencias vigentes que pagan compras anuladas', COUNT(*), MIN(Pago)
	FROM (SELECT DISTINCT CONCAT('cheque ', cheq.bce_numero_cheque) AS Pago
		  FROM dbo.bco_cheque_emitido_det deta
		  INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = deta.bce_id AND cheq.bce_estado_cheque <> 'A'
		  INNER JOIN dbo.inv_proveedor_plan_pago cuot ON cuot.ppg_id = deta.ppg_id
		  INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado <> 'G'
		  UNION
		  SELECT CONCAT('lote ', lote.blt_numero)
		  FROM dbo.bco_lote_transferencia_cuota blcu
		  INNER JOIN dbo.bco_lote_transferencia_det line ON line.bld_id = blcu.bld_id
		  INNER JOIN dbo.bco_lote_transferencia lote ON lote.blt_id = line.blt_id AND lote.blt_estado = 'A'
		  INNER JOIN dbo.inv_proveedor_plan_pago cuot ON cuot.ppg_id = blcu.ppg_id
		  INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado <> 'G') pagos;

	INSERT INTO @r
	SELECT 24, 'Compras vigentes sin plan de pagos al proveedor', COUNT(*), MIN(CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_numero_unico, docu.enc_numero_docto)))
	FROM dbo.inv_documento_enc docu
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id AND tipo.tdo_codigo IN ('COMP', 'GAST')
	WHERE docu.enc_estado = 'G' AND docu.prv_id IS NOT NULL AND docu.enc_monto_total > 0
	  AND NOT EXISTS (SELECT 1 FROM dbo.inv_proveedor_plan_pago cuot WHERE cuot.enc_id = docu.enc_id);

	SELECT Orden,
		   CASE WHEN Orden IN (1, 2, 3, 4, 19) THEN 'Contabilidad'
				WHEN Orden IN (5, 12, 20, 22) THEN 'Cuentas por cobrar'
				WHEN Orden IN (6, 21, 23, 24) THEN 'Cuentas por pagar'
				WHEN Orden = 13 THEN 'Cuentas por cobrar y por pagar'
				WHEN Orden IN (7, 11) THEN 'Inventario'
				WHEN Orden IN (8, 9, 10) THEN 'Nómina'
				WHEN Orden IN (14, 15, 18) THEN 'Caja y bancos'
				WHEN Orden IN (16, 17) THEN 'Activos fijos' END AS Area,
		   CASE WHEN Orden IN (5, 12, 20, 22) THEN 'CXC' WHEN Orden IN (6, 21, 23, 24) THEN 'CXP' END AS Detalle,
		   Control, Casos, CASE WHEN Casos = 0 THEN NULL ELSE Ejemplo END AS Ejemplo,
		   CASE WHEN Casos = 0 THEN 'OK' ELSE 'REVISAR' END AS Resultado
	FROM @r ORDER BY Orden;
END;
GO
