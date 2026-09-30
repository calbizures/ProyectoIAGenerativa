/*
================================================================================
 42_cxp_cheque_varias_cuotas.sql
 Pago a proveedores con un solo cheque por una factura completa o por el saldo
 de varias facturas del mismo proveedor.

 Requiere 34 (ppg_id en el detalle del cheque), 36 (paBcoChequeValidarNumero,
 tipo y beneficiario del cheque) y 40 (fnBcoCuentaContable por cuenta bancaria).
 Se puede ejecutar varias veces.

   1. Tipo tabla dbo.cxp_pago_cuota_type (cuota + monto a pagar).
   2. paCxpCuotasPendientesConsultar: cuotas con saldo de un proveedor (todas
      sus compras o solo una), de la más antigua a la más reciente.
   3. paCxpChequeEmitir: un cheque para varias cuotas. Una línea de detalle por
      cuota (abono o cancelación), el concepto automático en las observaciones
      (editable desde la pantalla) y una sola póliza:
        Debe  PAGO_PROVEEDORES   (una línea por factura)
        Haber cuenta de abonos de la cuenta bancaria (o PAGO_BANCOS)
      La anulación sigue siendo paCxpChequeAnular (36): ya devuelve el saldo a
      cada cuota del detalle y anula la póliza del cheque.
   4. paCxpChequeDetalleConsultar: facturas y cuotas que pagó un cheque.
   5. paCxpChequesConsultar: una fila por cheque, con los documentos agrupados
      (antes repetía el cheque por cada línea de detalle).
   6. paTableroCompras (38) devuelve la compra de cada próximo pago, para
      pagarla desde el tablero. Si se vuelve a correr 38, correr 42 después.

 Errores: 53701-53707.
================================================================================
*/
USE [erp_db];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Cuotas a pagar con el cheque
------------------------------------------------------------
IF TYPE_ID('dbo.cxp_pago_cuota_type') IS NULL
	CREATE TYPE [dbo].[cxp_pago_cuota_type] AS TABLE (
		[ppg_id]	INT				NOT NULL PRIMARY KEY,
		[monto]		NUMERIC(12, 2)	NOT NULL
	);
GO

------------------------------------------------------------
-- 2. Cuotas pendientes del proveedor
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCxpCuotasPendientesConsultar]
	@PrvId	INT,
	@EncId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cuot.ppg_id AS PpgId, docu.enc_id AS EncId,
		   CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto) AS Documento,
		   CONCAT(ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto) AS NumeroDocumento,
		   docu.enc_fecha_docto AS FechaDocumento, cuot.ppg_nro_pago AS Cuota, cuot.ppg_fecha_pago AS Vencimiento,
		   DATEDIFF(DAY, cuot.ppg_fecha_pago, CAST(GETDATE() AS DATE)) AS Dias,
		   cuot.ppg_valor_pago AS ValorCuota, ISNULL(cuot.ppg_valor_real_pago, 0) AS Pagado,
		   cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) AS Saldo
	FROM dbo.inv_proveedor_plan_pago cuot
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	WHERE docu.prv_id = @PrvId
	  AND (@EncId IS NULL OR docu.enc_id = @EncId)
	  AND cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) > 0
	ORDER BY cuot.ppg_fecha_pago, docu.enc_fecha_docto, docu.enc_id, cuot.ppg_nro_pago;
END;
GO

------------------------------------------------------------
-- 3. Cheque por varias cuotas (de una o varias facturas)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCxpChequeEmitir]
	@PrvId		INT,
	@CbcId		INT,
	@Numero		VARCHAR(16) = NULL,		-- vacío = siguiente de la chequera
	@BmpId		INT = NULL,
	@Concepto	VARCHAR(250) = NULL,	-- vacío = "Pago factura(s) ..." automático
	@Cuotas		dbo.cxp_pago_cuota_type READONLY,
	@UsuId		INT = NULL,
	@BceId		INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @beneficiario VARCHAR(150) = (SELECT prv_nombre_comercial FROM dbo.inv_proveedor WHERE prv_id = @PrvId);
	IF @beneficiario IS NULL
		THROW 53701, 'El proveedor indicado no existe.', 1;
	IF NOT EXISTS (SELECT 1 FROM @Cuotas)
		THROW 53702, 'Seleccione al menos una cuota a pagar.', 1;
	IF EXISTS (SELECT 1 FROM @Cuotas WHERE monto <= 0)
		THROW 53703, 'Cada cuota seleccionada debe llevar un monto mayor a cero.', 1;

	-- Chequera activa, número dentro del rango y sin repetir (vacío = siguiente).
	EXEC dbo.paBcoChequeValidarNumero @CbcId = @CbcId, @Numero = @Numero OUTPUT;

	DECLARE @cta_proveedores INT, @cta_bancos INT = dbo.fnBcoCuentaContable((SELECT bcb_id FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @CbcId));
	EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_PROVEEDORES', @CtaId = @cta_proveedores OUTPUT;
	IF @cta_bancos IS NULL
		EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_bancos OUTPUT;

	DECLARE @hoy DATE = CAST(GETDATE() AS DATE), @mensaje NVARCHAR(300);
	DECLARE @lineas TABLE (
		ppg_id		INT PRIMARY KEY,
		enc_id		INT,
		prv_id		INT,
		enc_estado	CHAR(1),
		documento	VARCHAR(40),
		nro_pago	INT,
		fecha_pago	DATE,
		fecha_docto	DATE,
		programado	NUMERIC(12, 2),
		pagado		NUMERIC(12, 2),
		monto		NUMERIC(12, 2)
	);

	BEGIN TRY
		BEGIN TRANSACTION;

		-- Bloquea las cuotas mientras se validan y se pagan.
		INSERT INTO @lineas (ppg_id, enc_id, prv_id, enc_estado, documento, nro_pago, fecha_pago, fecha_docto, programado, pagado, monto)
		SELECT pago.ppg_id, cuot.enc_id, docu.prv_id, docu.enc_estado,
			   CONCAT(ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto),
			   cuot.ppg_nro_pago, cuot.ppg_fecha_pago, docu.enc_fecha_docto,
			   cuot.ppg_valor_pago, ISNULL(cuot.ppg_valor_real_pago, 0), pago.monto
		FROM @Cuotas pago
		LEFT JOIN dbo.inv_proveedor_plan_pago cuot WITH (UPDLOCK, HOLDLOCK) ON cuot.ppg_id = pago.ppg_id
		LEFT JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id;

		IF EXISTS (SELECT 1 FROM @lineas WHERE enc_id IS NULL OR prv_id IS NULL OR prv_id <> @PrvId)
			THROW 53704, 'Una de las cuotas no existe o no es de este proveedor.', 1;
		IF EXISTS (SELECT 1 FROM @lineas WHERE enc_estado <> 'G')
		BEGIN
			SELECT TOP 1 @mensaje = CONCAT(N'La compra ', documento, N' está anulada; quítela del pago.') FROM @lineas WHERE enc_estado <> 'G';
			THROW 53705, @mensaje, 1;
		END
		IF EXISTS (SELECT 1 FROM @lineas WHERE monto > programado - pagado)
		BEGIN
			SELECT TOP 1 @mensaje = CONCAT(N'El pago a la cuota ', nro_pago, N' de ', documento, N' (Q', FORMAT(monto, 'N2'),
					N') supera su saldo (Q', FORMAT(programado - pagado, 'N2'), N').')
			FROM @lineas WHERE monto > programado - pagado ORDER BY fecha_pago, nro_pago;
			THROW 53706, @mensaje, 1;
		END

		DECLARE @total NUMERIC(12, 2) = (SELECT SUM(monto) FROM @lineas);
		DECLARE @facturas INT = (SELECT COUNT(DISTINCT enc_id) FROM @lineas);
		DECLARE @enc_unico INT = CASE WHEN @facturas = 1 THEN (SELECT MIN(enc_id) FROM @lineas) END;

		-- Concepto automático: los documentos pagados, del más antiguo al más reciente.
		SET @Concepto = NULLIF(LTRIM(RTRIM(@Concepto)), '');
		IF @Concepto IS NULL
		BEGIN
			DECLARE @documentos VARCHAR(MAX) = (
				SELECT STRING_AGG(CAST(docs.documento AS VARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY docs.fecha_docto, docs.enc_id)
				FROM (SELECT enc_id, MIN(documento) AS documento, MIN(fecha_docto) AS fecha_docto FROM @lineas GROUP BY enc_id) docs);
			SET @Concepto = CONCAT(CASE WHEN @facturas = 1 THEN 'Pago factura ' ELSE 'Pago facturas ' END, @documentos);
			IF LEN(@Concepto) > 250
				SET @Concepto = LEFT(@Concepto, 247) + '...';
		END

		INSERT INTO dbo.bco_cheque_emitido_enc
			(cbc_id, bce_fecha_emision, usu_id, bce_numero_cheque, bce_observaciones, bce_documento_ref, bce_valor, bmp_id,
			 bce_tipo, bce_beneficiario, InsUsuario, InsFechaHora)
		VALUES
			(@CbcId, @hoy, @UsuId, @Numero, @Concepto, CAST(@enc_unico AS VARCHAR(16)), @total, @BmpId,
			 'P', @beneficiario, @UsuId, SYSDATETIME());

		SET @BceId = SCOPE_IDENTITY();

		INSERT INTO dbo.bco_cheque_emitido_det (bce_id, bmp_id, enc_id, ppg_id, ced_valor, ced_abono_cancelacion, InsUsuario, InsFechaHora)
		SELECT @BceId, @BmpId, enc_id, ppg_id, monto,
			   CASE WHEN pagado + monto >= programado THEN 'C' ELSE 'A' END,
			   @UsuId, SYSDATETIME()
		FROM @lineas
		ORDER BY fecha_pago, fecha_docto, enc_id, nro_pago;

		UPDATE cuot
		   SET ppg_valor_real_pago = line.pagado + line.monto,
			   ppg_fecha_real_pago = @hoy,
			   ppg_numero_cheque = @Numero,
			   cbc_id = @CbcId,
			   ppg_estado = CASE WHEN line.pagado + line.monto >= line.programado THEN 'A' ELSE cuot.ppg_estado END,
			   UpdUsuario = @UsuId,
			   UpdFechaHora = SYSDATETIME()
		FROM dbo.inv_proveedor_plan_pago cuot
		INNER JOIN @lineas line ON line.ppg_id = cuot.ppg_id;

		-- Póliza: una línea al Debe por factura y el total al Haber del banco.
		DECLARE @asi_id INT, @partida dbo.cont_asiento_det_type;
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT @cta_proveedores, SUM(monto), 0, LEFT(CONCAT('Pago doc. ', MIN(documento), ' - cheque ', @Numero), 256)
		FROM @lineas
		GROUP BY enc_id;
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_bancos, 0, @total, 'Pago a proveedor - cheque ' + @Numero);

		DECLARE @asi_descripcion VARCHAR(256) = LEFT(CONCAT('Pago a proveedor con cheque ', @Numero,
			CASE WHEN @facturas > 1 THEN CONCAT(' (', @facturas, ' facturas)') END), 256);
		EXEC dbo.sp_contabilidad_insertar_asiento
			@asi_fecha = @hoy, @asi_descripcion = @asi_descripcion,
			@asi_origen = 'PAGO_PROVEEDOR', @asi_origen_id = @BceId, @enc_id = @enc_unico,
			@usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 4. Qué pagó un cheque
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCxpChequeDetalleConsultar]
	@BceId	INT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_enc WHERE bce_id = @BceId)
		THROW 53707, 'El cheque indicado no existe.', 1;

	SELECT chdt.ced_id AS CedId, docu.enc_id AS EncId,
		   CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto) AS Documento,
		   docu.enc_fecha_docto AS FechaDocumento, cuot.ppg_nro_pago AS Cuota, cuot.ppg_fecha_pago AS Vencimiento,
		   cuot.ppg_valor_pago AS ValorCuota, chdt.ced_valor AS Monto,
		   CASE chdt.ced_abono_cancelacion WHEN 'C' THEN 'Cancelación' ELSE 'Abono' END AS Aplicacion
	FROM dbo.bco_cheque_emitido_det chdt
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = chdt.enc_id
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	LEFT JOIN dbo.inv_proveedor_plan_pago cuot ON cuot.ppg_id = chdt.ppg_id
	WHERE chdt.bce_id = @BceId
	ORDER BY chdt.ced_id;
END;
GO

------------------------------------------------------------
-- 5. Cheques a proveedores: una fila por cheque
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCxpChequesConsultar]
	@PrvId	INT = NULL,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cheq.bce_id AS BceId, cheq.bce_fecha_emision AS Fecha, cheq.bce_numero_cheque AS Numero,
		   CONCAT(cuen.bcb_descripcion, ' ', cuen.bcb_numero_cuenta) AS Cuenta,
		   prov.prv_id AS PrvId, prov.prv_nombre_comercial AS Proveedor,
		   docs.Documento, docs.Cuotas,
		   cheq.bce_valor AS Valor, cheq.bce_estado_cheque AS EstadoCheque, cheq.bce_observaciones AS Observaciones,
		   usua.usu_usuario AS Usuario
	FROM dbo.bco_cheque_emitido_enc cheq
	-- Documentos del cheque: "FAC B-48213 #1, #2; FAC REST-9 #1".
	CROSS APPLY (SELECT STRING_AGG(CAST(porf.Texto AS VARCHAR(MAX)), '; ') WITHIN GROUP (ORDER BY porf.Orden) AS Documento,
						SUM(porf.Cuotas) AS Cuotas, MIN(porf.PrvId) AS PrvId
				 FROM (SELECT docu.enc_id, docu.prv_id AS PrvId, MIN(chdt.ced_id) AS Orden, COUNT(*) AS Cuotas,
							  CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto,
									 ' ' + STRING_AGG(CONCAT('#', cuot.ppg_nro_pago), ', ') WITHIN GROUP (ORDER BY cuot.ppg_nro_pago)) AS Texto
					   FROM dbo.bco_cheque_emitido_det chdt
					   INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = chdt.enc_id
					   INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
					   LEFT JOIN dbo.inv_proveedor_plan_pago cuot ON cuot.ppg_id = chdt.ppg_id
					   WHERE chdt.bce_id = cheq.bce_id
					   GROUP BY docu.enc_id, docu.prv_id, tipo.tdo_codigo, docu.enc_serie_docto, docu.enc_numero_docto) porf) docs
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = docs.PrvId
	LEFT JOIN dbo.bco_cuenta_bancaria_chequera cheqra ON cheqra.cbc_id = cheq.cbc_id
	LEFT JOIN dbo.bco_cuenta_bancaria cuen ON cuen.bcb_id = cheqra.bcb_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = cheq.usu_id
	WHERE (@PrvId IS NULL OR prov.prv_id = @PrvId)
	  AND (@Desde IS NULL OR cheq.bce_fecha_emision >= @Desde)
	  AND (@Hasta IS NULL OR cheq.bce_fecha_emision <= @Hasta)
	ORDER BY cheq.bce_id DESC;
END;
GO

------------------------------------------------------------
-- 6. Tablero de compras: la compra de cada próximo pago
--    Igual que en 38; "Próximos pagos" devuelve también EncId para pagar
--    la compra con cheque desde el tablero.
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paTableroCompras]
	@Desde	DATE,
	@Hasta	DATE,
	@SucId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @Hasta < @Desde
		THROW 53314, 'La fecha final no puede ser anterior a la inicial.', 1;
	DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
	DECLARE @dias INT = DATEDIFF(DAY, @Desde, @Hasta) + 1;
	DECLARE @antDesde DATE = DATEADD(DAY, -@dias, @Desde);

	DECLARE @docs TABLE (enc_id INT PRIMARY KEY, fecha DATE, actual BIT, prv_id INT, neto NUMERIC(14, 2), total NUMERIC(14, 2));
	INSERT INTO @docs
	SELECT docu.enc_id, docu.enc_fecha_docto, CASE WHEN docu.enc_fecha_docto >= @Desde THEN 1 ELSE 0 END, docu.prv_id,
		   (SELECT SUM(deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) FROM dbo.inv_documento_det deta WHERE deta.enc_id = docu.enc_id),
		   docu.enc_monto_total
	FROM dbo.inv_documento_enc docu
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id AND tipo.tdo_naturaleza = '+' AND tipo.tdo_es_nota = 0 AND tipo.tdo_es_interno = 0
	WHERE docu.enc_estado = 'G' AND docu.enc_fecha_docto BETWEEN @antDesde AND @Hasta
	  AND (@SucId IS NULL OR dbo.fnDocumentoSucursal(docu.enc_id) = @SucId);

	-- Cuotas por pagar (todas las compras vigentes, no solo las del período).
	DECLARE @cuotas TABLE (ppg_id INT PRIMARY KEY, enc_id INT, prv_id INT, nro INT, vence DATE, saldo NUMERIC(14, 2));
	INSERT INTO @cuotas
	SELECT cuot.ppg_id, cuot.enc_id, docu.prv_id, cuot.ppg_nro_pago, cuot.ppg_fecha_pago, cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0)
	FROM dbo.inv_proveedor_plan_pago cuot
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
	WHERE cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) > 0
	  AND (@SucId IS NULL OR dbo.fnDocumentoSucursal(docu.enc_id) = @SucId);

	DECLARE @pagos TABLE (bce_id INT PRIMARY KEY, fecha DATE, valor NUMERIC(14, 2));
	INSERT INTO @pagos
	SELECT cheq.bce_id, cheq.bce_fecha_emision, cheq.bce_valor
	FROM dbo.bco_cheque_emitido_enc cheq
	WHERE cheq.bce_estado_cheque <> 'A' AND cheq.bce_fecha_emision BETWEEN @Desde AND @Hasta
	  AND (@SucId IS NULL OR EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_det chdt WHERE chdt.bce_id = cheq.bce_id
									 AND dbo.fnDocumentoSucursal(chdt.enc_id) = @SucId));

	SELECT ISNULL(SUM(CASE WHEN actual = 1 THEN neto END), 0) AS Compras,
		   COUNT(CASE WHEN actual = 1 THEN 1 END) AS Documentos,
		   ISNULL(SUM(CASE WHEN actual = 0 THEN neto END), 0) AS ComprasAnterior,
		   ISNULL((SELECT SUM(saldo) FROM @cuotas), 0) AS PorPagar,
		   ISNULL((SELECT SUM(saldo) FROM @cuotas WHERE vence < @hoy), 0) AS Vencido,
		   ISNULL((SELECT SUM(saldo) FROM @cuotas WHERE vence BETWEEN @hoy AND DATEADD(DAY, 30, @hoy)), 0) AS Proximos30,
		   ISNULL((SELECT SUM(valor) FROM @pagos), 0) AS Pagado,
		   (SELECT COUNT(*) FROM @pagos) AS Cheques,
		   CAST(CASE WHEN @dias <= 62 THEN 'D' ELSE 'M' END AS CHAR(1)) AS Agrupacion
	FROM @docs;

	;WITH compras AS (
		SELECT dbo.fnTableroPeriodo(fecha, @Desde, @Hasta) AS Periodo, SUM(neto) AS Monto FROM @docs WHERE actual = 1
		GROUP BY dbo.fnTableroPeriodo(fecha, @Desde, @Hasta)
	), pagado AS (
		SELECT dbo.fnTableroPeriodo(fecha, @Desde, @Hasta) AS Periodo, SUM(valor) AS Monto FROM @pagos
		GROUP BY dbo.fnTableroPeriodo(fecha, @Desde, @Hasta)
	)
	SELECT COALESCE(comp.Periodo, paga.Periodo) AS Periodo, ISNULL(comp.Monto, 0) AS Compras, ISNULL(paga.Monto, 0) AS Pagado
	FROM compras comp FULL OUTER JOIN pagado paga ON paga.Periodo = comp.Periodo
	ORDER BY Periodo;

	SELECT TOP 10 prov.prv_id AS Id, prov.prv_codigo AS Codigo, prov.prv_nombre_comercial AS Nombre,
		   ISNULL(SUM(docs.neto), 0) AS Compras,
		   ISNULL((SELECT SUM(cuot.saldo) FROM @cuotas cuot WHERE cuot.prv_id = prov.prv_id), 0) AS Saldo
	FROM @docs docs INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = docs.prv_id
	WHERE docs.actual = 1
	GROUP BY prov.prv_id, prov.prv_codigo, prov.prv_nombre_comercial
	ORDER BY Compras DESC;

	-- Compromisos de pago: lo vencido y las próximas 12 semanas (lunes a domingo).
	DECLARE @lunes DATE = DATEADD(DAY, -((DATEPART(WEEKDAY, @hoy) + @@DATEFIRST - 2) % 7), @hoy);
	;WITH semanas AS (
		SELECT 0 AS Orden, CAST(NULL AS DATE) AS Desde, DATEADD(DAY, -1, @hoy) AS Hasta
		UNION ALL
		SELECT n.n, DATEADD(WEEK, n.n - 1, @lunes), DATEADD(DAY, 6, DATEADD(WEEK, n.n - 1, @lunes))
		FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12)) n(n)
	)
	SELECT sema.Orden, sema.Desde, sema.Hasta, ISNULL(SUM(cuot.saldo), 0) AS Monto, COUNT(cuot.ppg_id) AS Cuotas
	FROM semanas sema
	LEFT JOIN @cuotas cuot ON (sema.Orden = 0 AND cuot.vence < @hoy)
						   OR (sema.Orden > 0 AND cuot.vence BETWEEN CASE WHEN sema.Desde < @hoy THEN @hoy ELSE sema.Desde END AND sema.Hasta)
	GROUP BY sema.Orden, sema.Desde, sema.Hasta
	ORDER BY sema.Orden;

	SELECT TOP 15 prov.prv_id AS PrvId, prov.prv_nombre_comercial AS Proveedor, cuot.enc_id AS EncId,
		   CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto) AS Documento,
		   cuot.nro AS Cuota, cuot.vence AS Vence, cuot.saldo AS Saldo, DATEDIFF(DAY, @hoy, cuot.vence) AS Dias
	FROM @cuotas cuot
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = cuot.prv_id
	ORDER BY cuot.vence, cuot.ppg_id;
END;
GO

PRINT '42_cxp_cheque_varias_cuotas.sql aplicado.';
GO
