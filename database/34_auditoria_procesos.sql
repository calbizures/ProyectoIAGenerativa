------------------------------------------------------------------------------
-- 34_auditoria_procesos.sql
--
-- Correcciones de procesos halladas en la segunda auditoría:
--
--   1. Recibos de cobro con estado (pos_pago_enc.ppe_estado A/N) y motivo de
--      anulación. Los recibos grabados sin forma de pago en una caja abierta
--      se completan como Efectivo: sin forma de pago el cobro no entraba al
--      cuadre de caja.
--   2. Cobro de varias cuotas en un solo recibo (paCxcCobroRegistrar, TVP
--      cobro_cuota_type) con una sola póliza. paClienteCuotaPagoRegistrar
--      queda como atajo de una cuota; si no recibe formas de pago toma el
--      monto como Efectivo.
--   3. Anulación de recibos (paCxcReciboAnular): solo mientras la caja donde
--      se cobró siga abierta. Devuelve el saldo a las cuotas y anula la póliza.
--      Consultas de recibos y del detalle para imprimirlo.
--   4. Anulación de cheques a proveedor (paCxpChequeAnular) en cualquier
--      momento: devuelve el saldo a la cuota y anula la póliza. El detalle del
--      cheque guarda ahora la cuota que paga (ppg_id).
--   5. El corte de caja, los saldos y los estados de cuenta ignoran los
--      recibos y cheques anulados.
--   6. Anular una factura: se bloquea si tiene cobros de cuotas; su pago de
--      contado o enganche se anula con ella si la caja sigue abierta, y si la
--      caja ya cerró se bloquea (corresponde una nota de crédito). Anular una
--      compra se bloquea si tiene cheques vigentes.
--   7. Factura: límite de crédito del cliente (0 = sin límite) y formas de
--      pago validadas contra el total (contado) o el enganche (crédito).
--
-- Errores 53201-53229. Requiere 32. Se puede volver a correr.
------------------------------------------------------------------------------

USE [erp_db];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Estructura
------------------------------------------------------------
IF COL_LENGTH('dbo.pos_pago_enc', 'ppe_estado') IS NULL
	ALTER TABLE dbo.pos_pago_enc ADD [ppe_estado] CHAR(1) NOT NULL CONSTRAINT [DF_pos_pago_enc_estado] DEFAULT ('A');
IF COL_LENGTH('dbo.pos_pago_enc', 'ppe_motivo_anulacion') IS NULL
	ALTER TABLE dbo.pos_pago_enc ADD [ppe_motivo_anulacion] VARCHAR(256) NULL;
IF COL_LENGTH('dbo.pos_pago_enc', 'ppe_fecha_anulacion') IS NULL
	ALTER TABLE dbo.pos_pago_enc ADD [ppe_fecha_anulacion] DATETIME2(0) NULL;
IF COL_LENGTH('dbo.pos_pago_enc', 'usu_id_anulacion') IS NULL
	ALTER TABLE dbo.pos_pago_enc ADD [usu_id_anulacion] INT NULL;
IF COL_LENGTH('dbo.bco_cheque_emitido_det', 'ppg_id') IS NULL
	ALTER TABLE dbo.bco_cheque_emitido_det ADD [ppg_id] INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_pos_pago_enc_estado')
	ALTER TABLE dbo.pos_pago_enc ADD CONSTRAINT [CK_pos_pago_enc_estado] CHECK ([ppe_estado] IN ('A', 'N'));
IF OBJECT_ID('dbo.FK_pos_pago_enc_usuario_anulacion', 'F') IS NULL
	ALTER TABLE dbo.pos_pago_enc ADD CONSTRAINT [FK_pos_pago_enc_usuario_anulacion] FOREIGN KEY ([usu_id_anulacion]) REFERENCES dbo.gen_usuario ([usu_id]);
IF OBJECT_ID('dbo.FK_bco_cheque_emitido_det_cuota', 'F') IS NULL
	ALTER TABLE dbo.bco_cheque_emitido_det ADD CONSTRAINT [FK_bco_cheque_emitido_det_cuota] FOREIGN KEY ([ppg_id]) REFERENCES dbo.inv_proveedor_plan_pago ([ppg_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_pos_pago_enc_pca_id' AND object_id = OBJECT_ID('dbo.pos_pago_enc'))
	CREATE INDEX [IX_pos_pago_enc_pca_id] ON dbo.pos_pago_enc ([pca_id]) INCLUDE ([ppe_estado]);
GO

-- Recibos sin forma de pago en una caja que sigue abierta: se registran como
-- Efectivo por el monto aplicado. Los de cajas ya cerradas no se tocan: el
-- cierre se hizo con esos montos (el 30 los completa antes de cerrar).
INSERT INTO dbo.pos_pago_forma (pft_id, ppf_monto, ppe_id, InsUsuario, InsFechaHora)
SELECT tipo.pft_id, apli.Monto, pago.ppe_id, pago.usu_id, SYSDATETIME()
FROM dbo.pos_pago_enc pago
INNER JOIN dbo.pos_caja_apertura aper ON aper.pca_id = pago.pca_id AND aper.pca_estado = 'A'
CROSS APPLY (SELECT SUM(deta.ppd_valor_aplicado) AS Monto FROM dbo.pos_pago_det deta WHERE deta.ppe_id = pago.ppe_id) apli
INNER JOIN dbo.pos_pago_forma_tipo tipo ON tipo.pft_descripcion = 'Efectivo'
WHERE apli.Monto > 0
  AND NOT EXISTS (SELECT 1 FROM dbo.pos_pago_forma form WHERE form.ppe_id = pago.ppe_id);

-- Cuota que paga cada cheque ya emitido: la del documento con ese número de cheque.
UPDATE chdt
   SET ppg_id = cuot.ppg_id
FROM dbo.bco_cheque_emitido_det chdt
INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = chdt.bce_id
CROSS APPLY (SELECT TOP 1 plan_.ppg_id FROM dbo.inv_proveedor_plan_pago plan_
			 WHERE plan_.enc_id = chdt.enc_id AND plan_.ppg_numero_cheque = cheq.bce_numero_cheque
			 ORDER BY plan_.ppg_nro_pago) cuot
WHERE chdt.ppg_id IS NULL;

-- Pólizas de pagos grabadas antes de asi_origen_id (29): se ligan a su cheque
-- o recibo para poder anularlas con él.
UPDATE asie
   SET asi_origen_id = cheq.bce_id
FROM dbo.cont_asiento_enc asie
CROSS APPLY (SELECT TOP 1 chen.bce_id FROM dbo.bco_cheque_emitido_enc chen
			 INNER JOIN dbo.bco_cheque_emitido_det chdt ON chdt.bce_id = chen.bce_id AND chdt.enc_id = asie.enc_id
			 WHERE asie.asi_descripcion = 'Pago a proveedor con cheque ' + chen.bce_numero_cheque
			 ORDER BY chen.bce_id) cheq
WHERE asie.asi_origen = 'PAGO_PROVEEDOR' AND asie.asi_origen_id IS NULL;

UPDATE asie
   SET asi_origen_id = pago.ppe_id
FROM dbo.cont_asiento_enc asie
CROSS APPLY (SELECT TOP 1 asd_descripcion, asd_debe FROM dbo.cont_asiento_det WHERE asi_id = asie.asi_id AND asd_debe > 0) part
CROSS APPLY (SELECT TOP 1 deta.ppe_id FROM dbo.pos_pago_det deta
			 WHERE part.asd_descripcion = CONCAT('Cobro cuota ', deta.cpp_id) AND deta.ppd_valor_aplicado = part.asd_debe
			   AND NOT EXISTS (SELECT 1 FROM dbo.cont_asiento_enc otro WHERE otro.asi_origen = 'PAGO_CLIENTE' AND otro.asi_origen_id = deta.ppe_id)
			 ORDER BY deta.ppe_id) pago
WHERE asie.asi_origen = 'PAGO_CLIENTE' AND asie.asi_origen_id IS NULL;
GO

-- Cuotas a cobrar en un recibo y el monto que se aplica a cada una.
IF OBJECT_ID('dbo.paCxcCobroRegistrar', 'P') IS NOT NULL
	DROP PROCEDURE dbo.paCxcCobroRegistrar;
IF TYPE_ID(N'dbo.cobro_cuota_type') IS NOT NULL
	DROP TYPE dbo.cobro_cuota_type;
GO
CREATE TYPE dbo.cobro_cuota_type AS TABLE
(
	[cpp_id]	INT				NOT NULL,
	[monto]		NUMERIC(12, 2)	NOT NULL
);
GO

------------------------------------------------------------
-- 2. Cobro de una o varias cuotas en un recibo
------------------------------------------------------------
CREATE PROCEDURE [dbo].[paCxcCobroRegistrar]
	@CliId	INT,
	@PcaId	INT,
	@UsuId	INT = NULL,
	@Cuotas	dbo.cobro_cuota_type READONLY,
	@Formas	dbo.pago_forma_type READONLY,
	@PpeId	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @PpeId = NULL;

	DECLARE @total NUMERIC(12, 2) = (SELECT SUM(monto) FROM @Cuotas);
	DECLARE @msg NVARCHAR(400);

	IF @total IS NULL
		THROW 53201, 'Seleccione al menos una cuota a cobrar.', 1;
	IF EXISTS (SELECT 1 FROM @Cuotas WHERE monto <= 0)
		THROW 53202, 'El monto aplicado a cada cuota debe ser mayor a cero.', 1;
	IF EXISTS (SELECT cpp_id FROM @Cuotas GROUP BY cpp_id HAVING COUNT(*) > 1)
		THROW 53203, 'Una cuota aparece más de una vez en el cobro.', 1;
	IF EXISTS (SELECT 1 FROM @Cuotas apli
			   LEFT JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = apli.cpp_id
			   WHERE cuot.cpp_id IS NULL OR cuot.cli_id <> @CliId)
		THROW 53204, 'Una de las cuotas no existe o no es del cliente.', 1;
	IF EXISTS (SELECT 1 FROM @Cuotas apli
			   INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = apli.cpp_id
			   INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
			   WHERE docu.enc_estado <> 'G')
		THROW 53205, 'Una de las cuotas es de una factura anulada.', 1;

	SELECT TOP 1 @msg = CONCAT(N'El monto aplicado a la cuota ', cuot.cpp_nro_cuota, N' de ', ISNULL(docu.enc_numero_unico, docu.enc_numero_docto),
		N' (Q', FORMAT(apli.monto, 'N2'), N') supera su saldo (Q', FORMAT(cuot.cpp_saldo_cuota, 'N2'), N').')
	FROM @Cuotas apli
	INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = apli.cpp_id
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
	WHERE apli.monto > cuot.cpp_saldo_cuota;
	IF @msg IS NOT NULL
		THROW 53206, @msg, 1;

	IF NOT EXISTS (SELECT 1 FROM @Formas)
		THROW 53207, 'Indique la forma de pago del cobro.', 1;
	IF EXISTS (SELECT 1 FROM @Formas WHERE ppf_monto <= 0)
		THROW 53208, 'El monto de cada forma de pago debe ser mayor a cero.', 1;
	IF (SELECT SUM(ppf_monto) FROM @Formas) <> @total
	BEGIN
		SET @msg = CONCAT(N'Las formas de pago suman Q', FORMAT((SELECT SUM(ppf_monto) FROM @Formas), 'N2'),
			N' y el cobro es de Q', FORMAT(@total, 'N2'), N'.');
		THROW 53209, @msg, 1;
	END
	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @PcaId AND pca_estado = 'A')
		THROW 53210, 'No hay una caja abierta para recibir el cobro.', 1;

	DECLARE @cta_caja INT, @cta_clientes INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'COBRO_CAJA', @CtaId = @cta_caja OUTPUT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'COBRO_CLIENTES', @CtaId = @cta_clientes OUTPUT;

	-- La póliza queda ligada a la factura solo si el recibo cobra una sola.
	DECLARE @enc_id INT = (SELECT CASE WHEN COUNT(DISTINCT cuot.enc_id) = 1 THEN MIN(cuot.enc_id) END
						   FROM @Cuotas apli INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = apli.cpp_id);

	BEGIN TRY
		BEGIN TRANSACTION;

		-- El saldo se vuelve a comprobar al rebajarlo por si otro cajero cobró
		-- la misma cuota entre la validación y este punto.
		UPDATE cuot
		   SET cpp_saldo_cuota = cuot.cpp_saldo_cuota - apli.monto,
			   cpp_fecha_real_pago = CASE WHEN cuot.cpp_saldo_cuota - apli.monto <= 0 THEN CAST(GETDATE() AS DATE) ELSE cuot.cpp_fecha_real_pago END,
			   cpp_estado = CASE WHEN cuot.cpp_saldo_cuota - apli.monto <= 0 THEN 'A' ELSE cuot.cpp_estado END,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		FROM dbo.pos_cliente_plan_pagos cuot WITH (UPDLOCK, ROWLOCK)
		INNER JOIN @Cuotas apli ON apli.cpp_id = cuot.cpp_id
		WHERE cuot.cpp_saldo_cuota >= apli.monto;

		IF @@ROWCOUNT <> (SELECT COUNT(*) FROM @Cuotas)
			THROW 53211, 'El saldo de una de las cuotas cambió mientras se registraba el cobro. Vuelva a consultar y cobre de nuevo.', 1;

		INSERT INTO dbo.pos_pago_enc (cli_id, pca_id, usu_id, InsUsuario, InsFechaHora)
		VALUES (@CliId, @PcaId, @UsuId, @UsuId, SYSDATETIME());
		SET @PpeId = SCOPE_IDENTITY();

		INSERT INTO dbo.pos_pago_det (ppe_id, cpp_id, ppd_valor_aplicado, InsUsuario, InsFechaHora)
		SELECT @PpeId, cpp_id, monto, @UsuId, SYSDATETIME() FROM @Cuotas;

		INSERT INTO dbo.pos_pago_forma
			(gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, ppe_id, pft_id, InsUsuario, InsFechaHora)
		SELECT gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, @PpeId, pft_id, @UsuId, SYSDATETIME()
		FROM @Formas;

		DECLARE @asi_id INT, @partida dbo.cont_asiento_det_type, @fecha_hoy DATE = CAST(GETDATE() AS DATE);
		DECLARE @referencia VARCHAR(64) = CONCAT('Recibo ', @PpeId);
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_caja, @total, 0, @referencia), (@cta_clientes, 0, @total, @referencia);

		EXEC dbo.paContabilidadAsientoInsertar
			@AsiFecha = @fecha_hoy, @AsiDescripcion = 'Cobro a cliente',
			@AsiOrigen = 'PAGO_CLIENTE', @AsiOrigenId = @PpeId, @EncId = @enc_id,
			@UsuId = @UsuId, @Detalle = @partida, @AsiId = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Atajo de una sola cuota (lo usan los datos de prueba). Sin formas de pago
-- el monto se toma como Efectivo.
CREATE OR ALTER PROCEDURE [dbo].[paClienteCuotaPagoRegistrar]
	@CppId			INT,
	@ValorPago		NUMERIC(12, 2),
	@PcaId			INT,
	@UsuId			INT = NULL,
	@FormasPago	dbo.pago_forma_type READONLY,
	@PpeId			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @cli_id INT = (SELECT cli_id FROM dbo.pos_cliente_plan_pagos WHERE cpp_id = @CppId);
	IF @cli_id IS NULL
		THROW 51502, 'La cuota indicada no existe.', 1;

	DECLARE @cuotas dbo.cobro_cuota_type, @formas dbo.pago_forma_type;
	INSERT INTO @cuotas (cpp_id, monto) VALUES (@CppId, @ValorPago);
	INSERT INTO @formas SELECT * FROM @FormasPago;
	IF NOT EXISTS (SELECT 1 FROM @formas)
		INSERT INTO @formas (pft_id, ppf_monto)
		SELECT pft_id, @ValorPago FROM dbo.pos_pago_forma_tipo WHERE pft_descripcion = 'Efectivo';

	EXEC dbo.paCxcCobroRegistrar @CliId = @cli_id, @PcaId = @PcaId, @UsuId = @UsuId,
		@Cuotas = @cuotas, @Formas = @formas, @PpeId = @PpeId OUTPUT;
END;
GO

-- Cuotas con saldo del cliente en todas sus facturas, de la más antigua a la
-- más reciente (orden en que se aplica un cobro).
CREATE OR ALTER PROCEDURE [dbo].[paCxcCuotasPendientesConsultar]
	@CliId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cuot.cpp_id AS CppId, docu.enc_id AS EncId,
		   ISNULL(docu.enc_numero_unico, CONCAT(docu.enc_serie_docto, '-', docu.enc_numero_docto)) AS Documento,
		   docu.enc_fecha_docto AS FechaDocumento, cuot.cpp_nro_cuota AS Cuota, cuot.cpp_fecha_maxima_pago AS Vencimiento,
		   DATEDIFF(DAY, cuot.cpp_fecha_maxima_pago, CAST(GETDATE() AS DATE)) AS Dias,
		   cuot.cpp_valor_cuota AS ValorCuota, cuot.cpp_saldo_cuota AS Saldo
	FROM dbo.pos_cliente_plan_pagos cuot
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
	WHERE cuot.cli_id = @CliId AND cuot.cpp_saldo_cuota > 0
	ORDER BY cuot.cpp_fecha_maxima_pago, docu.enc_id, cuot.cpp_nro_cuota;
END;
GO

------------------------------------------------------------
-- 3. Recibos: consulta, detalle y anulación
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCxcRecibosConsultar]
	@PcaId	INT = NULL,
	@CliId	INT = NULL,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT pago.ppe_id AS PpeId, pago.ppe_fecha_pago AS Fecha, pago.cli_id AS CliId,
		   CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos) AS Cliente,
		   ISNULL(apli.Total, 0) AS Total, apli.Documentos, form.Formas,
		   pago.ppe_estado AS Estado, pago.ppe_motivo_anulacion AS MotivoAnulacion,
		   pago.pca_id AS PcaId, caja.pcr_descripcion AS Caja, usua.usu_usuario AS Usuario,
		   CAST(CASE WHEN aper.pca_estado = 'A' THEN 1 ELSE 0 END AS BIT) AS CajaAbierta,
		   CAST(CASE WHEN apli.Contado > 0 THEN 1 ELSE 0 END AS BIT) AS EsPagoFactura
	FROM dbo.pos_pago_enc pago
	INNER JOIN dbo.pos_cliente clie ON clie.cli_id = pago.cli_id
	LEFT JOIN dbo.pos_caja_apertura aper ON aper.pca_id = pago.pca_id
	LEFT JOIN dbo.pos_caja_receptora caja ON caja.pcr_id = aper.pcr_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = pago.usu_id
	OUTER APPLY (SELECT SUM(deta.ppd_valor_aplicado) AS Total,
						SUM(CASE WHEN deta.enc_id IS NOT NULL THEN 1 ELSE 0 END) AS Contado,
						STRING_AGG(CAST(CONCAT(ISNULL(docu.enc_numero_unico, docu.enc_numero_docto),
							CASE WHEN cuot.cpp_id IS NOT NULL THEN CONCAT(' #', cuot.cpp_nro_cuota) ELSE ' (pago inicial)' END) AS VARCHAR(MAX)), ', ') AS Documentos
				 FROM dbo.pos_pago_det deta
				 LEFT JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = deta.cpp_id
				 INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = COALESCE(deta.enc_id, cuot.enc_id)
				 WHERE deta.ppe_id = pago.ppe_id) apli
	OUTER APPLY (SELECT STRING_AGG(CAST(tipo.pft_descripcion AS VARCHAR(MAX)), ', ') AS Formas
				 FROM dbo.pos_pago_forma forma INNER JOIN dbo.pos_pago_forma_tipo tipo ON tipo.pft_id = forma.pft_id
				 WHERE forma.ppe_id = pago.ppe_id) form
	WHERE (@PcaId IS NULL OR pago.pca_id = @PcaId)
	  AND (@CliId IS NULL OR pago.cli_id = @CliId)
	  AND (@Desde IS NULL OR CAST(pago.ppe_fecha_pago AS DATE) >= @Desde)
	  AND (@Hasta IS NULL OR CAST(pago.ppe_fecha_pago AS DATE) <= @Hasta)
	ORDER BY pago.ppe_id DESC;
END;
GO

-- Tres resultados: encabezado, documentos/cuotas aplicados y formas de pago.
CREATE OR ALTER PROCEDURE [dbo].[paCxcReciboDetalleConsultar]
	@PpeId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT pago.ppe_id AS PpeId, pago.ppe_fecha_pago AS Fecha, pago.ppe_estado AS Estado, pago.ppe_motivo_anulacion AS MotivoAnulacion,
		   clie.cli_codigo AS ClienteCodigo, CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos) AS Cliente, clie.cli_nit AS ClienteNit,
		   comp.cia_nombre_comercial AS Compania, comp.cia_nit AS CompaniaNit, comp.cia_direccion AS CompaniaDireccion,
		   sucu.suc_descripcion AS Sucursal, caja.pcr_descripcion AS Caja, usua.usu_usuario AS Usuario
	FROM dbo.pos_pago_enc pago
	INNER JOIN dbo.pos_cliente clie ON clie.cli_id = pago.cli_id
	LEFT JOIN dbo.pos_caja_apertura aper ON aper.pca_id = pago.pca_id
	LEFT JOIN dbo.pos_caja_receptora caja ON caja.pcr_id = aper.pcr_id
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_id = caja.suc_id
	LEFT JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = pago.usu_id
	WHERE pago.ppe_id = @PpeId;

	SELECT ISNULL(docu.enc_numero_unico, docu.enc_numero_docto) AS Documento, cuot.cpp_nro_cuota AS Cuota,
		   cuot.cpp_fecha_maxima_pago AS Vencimiento, deta.ppd_valor_aplicado AS Monto, cuot.cpp_saldo_cuota AS SaldoCuota
	FROM dbo.pos_pago_det deta
	LEFT JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = deta.cpp_id
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = COALESCE(deta.enc_id, cuot.enc_id)
	WHERE deta.ppe_id = @PpeId
	ORDER BY deta.ppd_id;

	SELECT tipo.pft_descripcion AS Forma, forma.ppf_monto AS Monto, enti.gef_descripcion AS Entidad,
		   COALESCE(forma.ppf_numero_cheque, forma.ppf_numero_tarjeta_ult4) AS Referencia
	FROM dbo.pos_pago_forma forma
	INNER JOIN dbo.pos_pago_forma_tipo tipo ON tipo.pft_id = forma.pft_id
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = forma.gef_id
	WHERE forma.ppe_id = @PpeId
	ORDER BY forma.ppf_id;
END;
GO

-- Uso interno: anula un recibo ya validado dentro de la transacción del llamador.
CREATE OR ALTER PROCEDURE [dbo].[paCxcReciboReversar]
	@PpeId	INT,
	@Motivo	VARCHAR(256),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	UPDATE cuot
	   SET cpp_saldo_cuota = cuot.cpp_saldo_cuota + deta.ppd_valor_aplicado,
		   cpp_estado = 'P',
		   cpp_fecha_real_pago = NULL,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	FROM dbo.pos_cliente_plan_pagos cuot
	INNER JOIN dbo.pos_pago_det deta ON deta.cpp_id = cuot.cpp_id
	WHERE deta.ppe_id = @PpeId;

	UPDATE dbo.pos_pago_enc
	   SET ppe_estado = 'N', ppe_motivo_anulacion = @Motivo, ppe_fecha_anulacion = SYSDATETIME(), usu_id_anulacion = @UsuId,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE ppe_id = @PpeId;

	UPDATE dbo.cont_asiento_enc
	   SET asi_estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE asi_origen = 'PAGO_CLIENTE' AND asi_origen_id = @PpeId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCxcReciboAnular]
	@PpeId	INT,
	@Motivo	VARCHAR(256),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado CHAR(1), @caja_estado CHAR(1);
	SELECT @estado = pago.ppe_estado, @caja_estado = aper.pca_estado
	FROM dbo.pos_pago_enc pago LEFT JOIN dbo.pos_caja_apertura aper ON aper.pca_id = pago.pca_id
	WHERE pago.ppe_id = @PpeId;

	IF @estado IS NULL
		THROW 53212, 'El recibo indicado no existe.', 1;
	IF @estado = 'N'
		THROW 53213, 'El recibo ya está anulado.', 1;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 53214, 'Indique el motivo de la anulación (al menos 5 caracteres).', 1;
	IF EXISTS (SELECT 1 FROM dbo.pos_pago_det WHERE ppe_id = @PpeId AND enc_id IS NOT NULL)
		THROW 53215, 'Es el pago de contado o enganche de una factura: se anula junto con la factura.', 1;
	IF ISNULL(@caja_estado, 'C') <> 'A'
		THROW 53216, 'La caja donde se cobró este recibo ya se cerró; corrija el saldo con una nota de débito.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;
		EXEC dbo.paCxcReciboReversar @PpeId = @PpeId, @Motivo = @Motivo, @UsuId = @UsuId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 4. Cheques a proveedor: emisión con cuota, consulta y anulación
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paBancoChequePagoProveedorEmitir]
	@PpgId				INT,
	@CbcId				INT,
	@BceNumeroCheque	VARCHAR(16),
	@ValorPago			NUMERIC(12, 2),
	@BmpId				INT = NULL,
	@UsuId				INT = NULL,
	@BceId				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @ValorPago <= 0
		THROW 51601, 'El valor del pago debe ser mayor a cero.', 1;
	IF ISNULL(LTRIM(RTRIM(@BceNumeroCheque)), '') = ''
		THROW 51605, 'Ingrese el número de cheque.', 1;

	DECLARE @enc_id INT, @valor_programado NUMERIC(12, 2), @valor_pagado NUMERIC(12, 2), @estado CHAR(1);
	SELECT @enc_id = enc_id, @valor_programado = ppg_valor_pago, @valor_pagado = ISNULL(ppg_valor_real_pago, 0), @estado = ppg_estado
	FROM dbo.inv_proveedor_plan_pago WHERE ppg_id = @PpgId;

	IF @enc_id IS NULL
		THROW 51602, 'La cuota de proveedor indicada no existe.', 1;
	IF @estado = 'A' OR @valor_programado - @valor_pagado <= 0
		THROW 51603, 'La cuota de proveedor indicada ya está pagada por completo.', 1;
	IF @ValorPago > @valor_programado - @valor_pagado
	BEGIN
		DECLARE @msg NVARCHAR(200) = CONCAT(N'El pago (Q', FORMAT(@ValorPago, 'N2'), N') supera el saldo de la cuota (Q',
			FORMAT(@valor_programado - @valor_pagado, 'N2'), N').');
		THROW 51604, @msg, 1;
	END
	IF EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_id = @enc_id AND enc_estado <> 'G')
		THROW 53217, 'La compra de esa cuota está anulada.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @CbcId)
		THROW 51606, 'La chequera indicada no existe.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_enc WHERE cbc_id = @CbcId AND bce_numero_cheque = @BceNumeroCheque)
		THROW 51607, 'Ese número de cheque ya fue emitido en la chequera.', 1;

	DECLARE @cta_proveedores INT, @cta_bancos INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_PROVEEDORES', @CtaId = @cta_proveedores OUTPUT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_bancos OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.bco_cheque_emitido_enc
			(cbc_id, bce_fecha_emision, usu_id, bce_numero_cheque, bce_documento_ref, bce_valor, bmp_id, InsUsuario, InsFechaHora)
		VALUES
			(@CbcId, CAST(GETDATE() AS DATE), @UsuId, @BceNumeroCheque, CAST(@enc_id AS VARCHAR(16)), @ValorPago, @BmpId, @UsuId, SYSDATETIME());

		SET @BceId = SCOPE_IDENTITY();

		INSERT INTO dbo.bco_cheque_emitido_det (bce_id, bmp_id, enc_id, ppg_id, ced_valor, ced_abono_cancelacion, InsUsuario, InsFechaHora)
		VALUES (@BceId, @BmpId, @enc_id, @PpgId, @ValorPago,
				CASE WHEN @valor_pagado + @ValorPago >= @valor_programado THEN 'C' ELSE 'A' END,
				@UsuId, SYSDATETIME());

		UPDATE dbo.inv_proveedor_plan_pago
		   SET ppg_valor_real_pago = @valor_pagado + @ValorPago,
			   ppg_fecha_real_pago = CAST(GETDATE() AS DATE),
			   ppg_numero_cheque = @BceNumeroCheque,
			   cbc_id = @CbcId,
			   ppg_estado = CASE WHEN @valor_pagado + @ValorPago >= @valor_programado THEN 'A' ELSE ppg_estado END,
			   UpdUsuario = @UsuId,
			   UpdFechaHora = SYSDATETIME()
		 WHERE ppg_id = @PpgId;

		DECLARE @asi_id INT, @partida dbo.cont_asiento_det_type, @fecha_hoy DATE = CAST(GETDATE() AS DATE);
		DECLARE @referencia VARCHAR(64) = 'Pago a proveedor - cheque ' + @BceNumeroCheque;
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_proveedores, @ValorPago, 0, @referencia), (@cta_bancos, 0, @ValorPago, @referencia);

		DECLARE @asi_descripcion VARCHAR(256) = 'Pago a proveedor con cheque ' + @BceNumeroCheque;
		EXEC dbo.paContabilidadAsientoInsertar
			@AsiFecha = @fecha_hoy, @AsiDescripcion = @asi_descripcion,
			@AsiOrigen = 'PAGO_PROVEEDOR', @AsiOrigenId = @BceId, @EncId = @enc_id,
			@UsuId = @UsuId, @Detalle = @partida, @AsiId = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

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
		   CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto,
				  CASE WHEN cuot.ppg_nro_pago IS NOT NULL THEN CONCAT(' #', cuot.ppg_nro_pago) ELSE '' END) AS Documento,
		   cheq.bce_valor AS Valor, cheq.bce_estado_cheque AS EstadoCheque, cheq.bce_observaciones AS Observaciones,
		   usua.usu_usuario AS Usuario
	FROM dbo.bco_cheque_emitido_enc cheq
	INNER JOIN dbo.bco_cheque_emitido_det chdt ON chdt.bce_id = cheq.bce_id
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = chdt.enc_id
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = docu.prv_id
	LEFT JOIN dbo.inv_proveedor_plan_pago cuot ON cuot.ppg_id = chdt.ppg_id
	LEFT JOIN dbo.bco_cuenta_bancaria_chequera cheqra ON cheqra.cbc_id = cheq.cbc_id
	LEFT JOIN dbo.bco_cuenta_bancaria cuen ON cuen.bcb_id = cheqra.bcb_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = cheq.usu_id
	WHERE (@PrvId IS NULL OR prov.prv_id = @PrvId)
	  AND (@Desde IS NULL OR cheq.bce_fecha_emision >= @Desde)
	  AND (@Hasta IS NULL OR cheq.bce_fecha_emision <= @Hasta)
	ORDER BY cheq.bce_id DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCxpChequeAnular]
	@BceId	INT,
	@Motivo	VARCHAR(256),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado CHAR(1) = (SELECT bce_estado_cheque FROM dbo.bco_cheque_emitido_enc WHERE bce_id = @BceId);
	IF @estado IS NULL
		THROW 53218, 'El cheque indicado no existe.', 1;
	IF @estado = 'A'
		THROW 53219, 'El cheque ya está anulado.', 1;
	IF @estado = 'C'
		THROW 53220, 'El cheque ya fue cobrado por el proveedor; no se puede anular.', 1;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 53214, 'Indique el motivo de la anulación (al menos 5 caracteres).', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_det WHERE bce_id = @BceId AND ppg_id IS NULL)
		THROW 53221, 'No se puede determinar la cuota que pagó este cheque; anúlelo manualmente con contabilidad.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		UPDATE cuot
		   SET ppg_valor_real_pago = ISNULL(cuot.ppg_valor_real_pago, 0) - chdt.ced_valor,
			   ppg_estado = 'P',
			   ppg_numero_cheque = CASE WHEN cuot.ppg_numero_cheque = cheq.bce_numero_cheque THEN NULL ELSE cuot.ppg_numero_cheque END,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		FROM dbo.inv_proveedor_plan_pago cuot
		INNER JOIN dbo.bco_cheque_emitido_det chdt ON chdt.ppg_id = cuot.ppg_id
		INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = chdt.bce_id
		WHERE chdt.bce_id = @BceId;

		UPDATE dbo.bco_cheque_emitido_enc
		   SET bce_estado_cheque = 'A',
			   bce_observaciones = LEFT(CONCAT('ANULADO: ', LTRIM(RTRIM(@Motivo)), ISNULL(' | ' + bce_observaciones, '')), 256),
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE bce_id = @BceId;

		UPDATE dbo.cont_asiento_enc
		   SET asi_estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE asi_origen = 'PAGO_PROVEEDOR' AND asi_origen_id = @BceId;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 5. Corte de caja, saldos y estados de cuenta sin anulados
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCorteCajaTeoricoConsultar]
	@pca_id INT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @monto_inicial NUMERIC(12, 2) = (SELECT pca_monto_inicial FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id);
	DECLARE @depositos NUMERIC(12, 2) = (SELECT ISNULL(SUM(pcd_valor_deposito), 0) FROM dbo.pos_caja_deposito WHERE pca_id = @pca_id);

	SELECT tipo.pft_id, tipo.pft_descripcion,
		   ISNULL(cobrado.monto, 0)
		   + CASE WHEN tipo.pft_descripcion = 'Efectivo' THEN ISNULL(@monto_inicial, 0) - @depositos ELSE 0 END AS monto_teorico
	FROM dbo.pos_pago_forma_tipo tipo
	LEFT JOIN (
		SELECT forma.pft_id, SUM(forma.ppf_monto) AS monto
		FROM dbo.pos_pago_forma forma
		INNER JOIN dbo.pos_pago_enc penc ON penc.ppe_id = forma.ppe_id
		WHERE penc.pca_id = @pca_id AND penc.ppe_estado = 'A'
		GROUP BY forma.pft_id
	) cobrado ON cobrado.pft_id = tipo.pft_id
	WHERE tipo.pft_estado = 'A'
	ORDER BY tipo.pft_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCorteCajaCuadreConsultar]
	@pca_id INT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @monto_inicial NUMERIC(12, 2), @tolerancia NUMERIC(12, 2);
	SELECT @monto_inicial = aper.pca_monto_inicial, @tolerancia = ISNULL(comp.cia_tolerancia_cierre_caja, 0)
	FROM dbo.pos_caja_apertura aper
	INNER JOIN dbo.pos_caja_receptora caja ON caja.pcr_id = aper.pcr_id
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = caja.suc_id
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	WHERE aper.pca_id = @pca_id;

	IF @monto_inicial IS NULL
		THROW 51702, 'La apertura de caja indicada no existe.', 1;

	DECLARE @efectivo NUMERIC(12, 2), @cheques NUMERIC(12, 2), @tarjetas NUMERIC(12, 2), @otras NUMERIC(12, 2);
	SELECT @efectivo = ISNULL(SUM(CASE WHEN tipo.pft_descripcion = 'Efectivo' THEN forma.ppf_monto ELSE 0 END), 0),
		   @cheques  = ISNULL(SUM(CASE WHEN tipo.pft_descripcion = 'Cheque' THEN forma.ppf_monto ELSE 0 END), 0),
		   @tarjetas = ISNULL(SUM(CASE WHEN tipo.pft_descripcion = 'Tarjeta' THEN forma.ppf_monto ELSE 0 END), 0),
		   @otras    = ISNULL(SUM(CASE WHEN tipo.pft_descripcion NOT IN ('Efectivo','Cheque','Tarjeta') THEN forma.ppf_monto ELSE 0 END), 0)
	FROM dbo.pos_pago_forma forma
	INNER JOIN dbo.pos_pago_enc penc ON penc.ppe_id = forma.ppe_id
	INNER JOIN dbo.pos_pago_forma_tipo tipo ON tipo.pft_id = forma.pft_id
	WHERE penc.pca_id = @pca_id AND penc.ppe_estado = 'A';

	DECLARE @depositos NUMERIC(12, 2) = (SELECT ISNULL(SUM(pcd_valor_deposito), 0) FROM dbo.pos_caja_deposito WHERE pca_id = @pca_id);
	DECLARE @fisico_efectivo NUMERIC(12, 2) = (SELECT ISNULL(SUM(def_denominacion * def_cantidad), 0) FROM dbo.pos_caja_desglose_efectivo WHERE pca_id = @pca_id);
	DECLARE @fisico_otras NUMERIC(12, 2) = (SELECT ISNULL(SUM(pcf_monto_fisico), 0) FROM dbo.pos_caja_corte_forma WHERE pca_id = @pca_id);

	DECLARE @teorico NUMERIC(12, 2) = @monto_inicial + @efectivo - @depositos + @cheques + @tarjetas + @otras;
	DECLARE @fisico NUMERIC(12, 2) = @fisico_efectivo + @fisico_otras;

	SELECT @monto_inicial AS MontoInicial, @efectivo AS EfectivoCobrado, @depositos AS Depositos,
		   @cheques AS Cheques, @tarjetas AS Tarjetas, @otras AS OtrasFormas,
		   @teorico AS TeoricoTotal, @fisico_efectivo AS FisicoEfectivo, @fisico_otras AS FisicoOtrasFormas, @fisico AS FisicoTotal,
		   @fisico - @teorico AS Diferencia, @tolerancia AS Tolerancia,
		   CAST(CASE WHEN ABS(@fisico - @teorico) <= @tolerancia THEN 1 ELSE 0 END AS BIT) AS Cuadra;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCxcDocumentosConsultar]
	@CliId			INT = NULL,
	@SoloPendientes	BIT = 1
AS
BEGIN
	SET NOCOUNT ON;
	SELECT enca.enc_id, enca.cli_id, CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos) AS Cliente,
		   ISNULL(enca.enc_numero_unico, CONCAT(enca.enc_serie_docto, '-', enca.enc_numero_docto)) AS Documento,
		   enca.enc_fecha_docto, enca.enc_monto_total,
		   ISNULL(pago.Pagado, 0) AS Pagado,
		   ISNULL(nota.Creditos, 0) AS NotasCredito, ISNULL(nota.Debitos, 0) AS NotasDebito,
		   ISNULL(plan_.Saldo, 0) AS Saldo, plan_.ProximoVencimiento, plan_.CuotasPendientes
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_naturaleza = '-' AND tipo.tdo_es_nota = 0
	INNER JOIN dbo.pos_cliente clie ON clie.cli_id = enca.cli_id
	OUTER APPLY (SELECT SUM(deta.ppd_valor_aplicado) AS Pagado
				 FROM dbo.pos_pago_det deta
				 INNER JOIN dbo.pos_pago_enc penc ON penc.ppe_id = deta.ppe_id AND penc.ppe_estado = 'A'
				 LEFT JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = deta.cpp_id
				 WHERE COALESCE(deta.enc_id, cuot.enc_id) = enca.enc_id) pago
	OUTER APPLY (SELECT SUM(CASE WHEN tnot.tdo_codigo = 'NCC' THEN nota.enc_monto_total END) AS Creditos,
						SUM(CASE WHEN tnot.tdo_codigo = 'NDC' THEN nota.enc_monto_total END) AS Debitos
				 FROM dbo.inv_documento_enc nota INNER JOIN dbo.inv_documento_tipo tnot ON tnot.tdo_id = nota.tdo_id
				 WHERE nota.enc_id_referencia = enca.enc_id AND nota.enc_estado = 'G') nota
	OUTER APPLY (SELECT SUM(cuot.cpp_saldo_cuota) AS Saldo,
						MIN(CASE WHEN cuot.cpp_saldo_cuota > 0 THEN cuot.cpp_fecha_maxima_pago END) AS ProximoVencimiento,
						SUM(CASE WHEN cuot.cpp_saldo_cuota > 0 THEN 1 ELSE 0 END) AS CuotasPendientes
				 FROM dbo.pos_cliente_plan_pagos cuot WHERE cuot.enc_id = enca.enc_id) plan_
	WHERE enca.enc_estado = 'G'
	  AND (@CliId IS NULL OR enca.cli_id = @CliId)
	  AND (@SoloPendientes = 0 OR ISNULL(plan_.Saldo, 0) > 0)
	ORDER BY enca.enc_fecha_docto, enca.enc_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCxcEstadoCuentaConsultar]
	@CliId	INT,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @Hasta = ISNULL(@Hasta, CAST(GETDATE() AS DATE));

	DECLARE @movimientos TABLE (Fecha DATE, Orden INT, Id INT, Tipo VARCHAR(20), Documento VARCHAR(40), Referencia VARCHAR(80),
		Cargo NUMERIC(14, 2), Abono NUMERIC(14, 2));

	INSERT INTO @movimientos
	SELECT enca.enc_fecha_docto, 1, enca.enc_id, 'Factura',
		   ISNULL(enca.enc_numero_unico, CONCAT(enca.enc_serie_docto, '-', enca.enc_numero_docto)),
		   CONCAT(enca.enc_numero_cuotas, ' cuota(s)'), enca.enc_monto_total, 0
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_naturaleza = '-' AND tipo.tdo_es_nota = 0
	WHERE enca.cli_id = @CliId AND enca.enc_estado = 'G'
	UNION ALL
	SELECT nota.enc_fecha_docto, 2, nota.enc_id, CASE tnot.tdo_codigo WHEN 'NCC' THEN 'Nota de crédito' ELSE 'Nota de débito' END,
		   nota.enc_numero_unico, CONCAT('Doc. ', ISNULL(refe.enc_numero_unico, refe.enc_numero_docto), ': ', LEFT(nota.enc_motivo, 60)),
		   CASE WHEN tnot.tdo_codigo = 'NDC' THEN nota.enc_monto_total ELSE 0 END,
		   CASE WHEN tnot.tdo_codigo = 'NCC' THEN nota.enc_monto_total ELSE 0 END
	FROM dbo.inv_documento_enc nota
	INNER JOIN dbo.inv_documento_tipo tnot ON tnot.tdo_id = nota.tdo_id AND tnot.tdo_codigo IN ('NCC', 'NDC')
	INNER JOIN dbo.inv_documento_enc refe ON refe.enc_id = nota.enc_id_referencia AND refe.enc_estado = 'G'
	WHERE nota.cli_id = @CliId AND nota.enc_estado = 'G'
	UNION ALL
	SELECT CAST(pago.ppe_fecha_pago AS DATE), 3, deta.ppd_id, 'Pago', CONCAT('Recibo ', pago.ppe_id),
		   CONCAT('Doc. ', ISNULL(docu.enc_numero_unico, docu.enc_numero_docto), CASE WHEN cuot.cpp_id IS NOT NULL THEN CONCAT(', cuota ', cuot.cpp_nro_cuota) ELSE '' END),
		   0, deta.ppd_valor_aplicado
	FROM dbo.pos_pago_det deta
	INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
	LEFT JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = deta.cpp_id
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = COALESCE(deta.enc_id, cuot.enc_id) AND docu.enc_estado = 'G'
	WHERE docu.cli_id = @CliId;

	DECLARE @saldo_inicial NUMERIC(14, 2) = (SELECT ISNULL(SUM(Cargo - Abono), 0) FROM @movimientos WHERE @Desde IS NOT NULL AND Fecha < @Desde);

	SELECT Fecha, Tipo, Documento, Referencia, Cargo, Abono,
		   @saldo_inicial + SUM(Cargo - Abono) OVER (ORDER BY Fecha, Orden, Id ROWS UNBOUNDED PRECEDING) AS Saldo,
		   @saldo_inicial AS SaldoInicial
	FROM @movimientos
	WHERE (@Desde IS NULL OR Fecha >= @Desde) AND Fecha <= @Hasta
	ORDER BY Fecha, Orden, Id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCxpDocumentosConsultar]
	@PrvId			INT = NULL,
	@SoloPendientes	BIT = 1
AS
BEGIN
	SET NOCOUNT ON;
	SELECT enca.enc_id, enca.prv_id, prov.prv_nombre_comercial AS Proveedor,
		   CONCAT(tipo.tdo_codigo, ' ', ISNULL(enca.enc_serie_docto + '-', ''), enca.enc_numero_docto) AS Documento,
		   enca.enc_fecha_docto, enca.enc_monto_total,
		   ISNULL(pago.Pagado, 0) AS Pagado,
		   ISNULL(nota.Creditos, 0) AS NotasCredito, ISNULL(nota.Debitos, 0) AS NotasDebito,
		   ISNULL(plan_.Saldo, 0) AS Saldo, plan_.ProximoVencimiento, plan_.CuotasPendientes
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_naturaleza = '+' AND tipo.tdo_es_nota = 0
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = enca.prv_id
	OUTER APPLY (SELECT SUM(chdt.ced_valor) AS Pagado FROM dbo.bco_cheque_emitido_det chdt
				 INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = chdt.bce_id AND cheq.bce_estado_cheque <> 'A'
				 WHERE chdt.enc_id = enca.enc_id) pago
	OUTER APPLY (SELECT SUM(CASE WHEN tnot.tdo_codigo = 'NCP' THEN nota.enc_monto_total END) AS Creditos,
						SUM(CASE WHEN tnot.tdo_codigo = 'NDP' THEN nota.enc_monto_total END) AS Debitos
				 FROM dbo.inv_documento_enc nota INNER JOIN dbo.inv_documento_tipo tnot ON tnot.tdo_id = nota.tdo_id
				 WHERE nota.enc_id_referencia = enca.enc_id AND nota.enc_estado = 'G') nota
	OUTER APPLY (SELECT SUM(cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0)) AS Saldo,
						MIN(CASE WHEN cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) > 0 THEN cuot.ppg_fecha_pago END) AS ProximoVencimiento,
						SUM(CASE WHEN cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) > 0 THEN 1 ELSE 0 END) AS CuotasPendientes
				 FROM dbo.inv_proveedor_plan_pago cuot WHERE cuot.enc_id = enca.enc_id) plan_
	WHERE enca.enc_estado = 'G'
	  AND (@PrvId IS NULL OR enca.prv_id = @PrvId)
	  AND (@SoloPendientes = 0 OR ISNULL(plan_.Saldo, 0) > 0)
	ORDER BY enca.enc_fecha_docto, enca.enc_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCxpEstadoCuentaConsultar]
	@PrvId	INT,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @Hasta = ISNULL(@Hasta, CAST(GETDATE() AS DATE));

	-- Desde el punto de vista de lo que se le debe al proveedor: la compra y
	-- la nota de débito son cargos; el cheque y la nota de crédito, abonos.
	DECLARE @movimientos TABLE (Fecha DATE, Orden INT, Id INT, Tipo VARCHAR(20), Documento VARCHAR(40), Referencia VARCHAR(80),
		Cargo NUMERIC(14, 2), Abono NUMERIC(14, 2));

	INSERT INTO @movimientos
	SELECT enca.enc_fecha_docto, 1, enca.enc_id, 'Compra',
		   CONCAT(tipo.tdo_codigo, ' ', ISNULL(enca.enc_serie_docto + '-', ''), enca.enc_numero_docto),
		   CONCAT(enca.enc_numero_cuotas, ' cuota(s)'), enca.enc_monto_total, 0
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_naturaleza = '+' AND tipo.tdo_es_nota = 0
	WHERE enca.prv_id = @PrvId AND enca.enc_estado = 'G'
	UNION ALL
	SELECT nota.enc_fecha_docto, 2, nota.enc_id, CASE tnot.tdo_codigo WHEN 'NCP' THEN 'Nota de crédito' ELSE 'Nota de débito' END,
		   CONCAT(tnot.tdo_codigo, ' ', nota.enc_numero_docto), CONCAT('Doc. ', refe.enc_numero_docto, ': ', LEFT(nota.enc_motivo, 60)),
		   CASE WHEN tnot.tdo_codigo = 'NDP' THEN nota.enc_monto_total ELSE 0 END,
		   CASE WHEN tnot.tdo_codigo = 'NCP' THEN nota.enc_monto_total ELSE 0 END
	FROM dbo.inv_documento_enc nota
	INNER JOIN dbo.inv_documento_tipo tnot ON tnot.tdo_id = nota.tdo_id AND tnot.tdo_codigo IN ('NCP', 'NDP')
	INNER JOIN dbo.inv_documento_enc refe ON refe.enc_id = nota.enc_id_referencia AND refe.enc_estado = 'G'
	WHERE nota.prv_id = @PrvId AND nota.enc_estado = 'G'
	UNION ALL
	SELECT cheq.bce_fecha_emision, 3, chdt.ced_id, 'Cheque', CONCAT('Cheque ', cheq.bce_numero_cheque),
		   CONCAT('Doc. ', docu.enc_numero_docto), 0, chdt.ced_valor
	FROM dbo.bco_cheque_emitido_det chdt
	INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = chdt.bce_id AND cheq.bce_estado_cheque <> 'A'
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = chdt.enc_id AND docu.enc_estado = 'G'
	WHERE docu.prv_id = @PrvId;

	DECLARE @saldo_inicial NUMERIC(14, 2) = (SELECT ISNULL(SUM(Cargo - Abono), 0) FROM @movimientos WHERE @Desde IS NOT NULL AND Fecha < @Desde);

	SELECT Fecha, Tipo, Documento, Referencia, Cargo, Abono,
		   @saldo_inicial + SUM(Cargo - Abono) OVER (ORDER BY Fecha, Orden, Id ROWS UNBOUNDED PRECEDING) AS Saldo,
		   @saldo_inicial AS SaldoInicial
	FROM @movimientos
	WHERE (@Desde IS NULL OR Fecha >= @Desde) AND Fecha <= @Hasta
	ORDER BY Fecha, Orden, Id;
END;
GO

------------------------------------------------------------
-- 6. Anulación de facturas y compras con pagos
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paDocumentoAnular]
	@EncId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado_actual CHAR(1), @es_nota BIT;
	SELECT @estado_actual = enca.enc_estado, @es_nota = tipo.tdo_es_nota
	FROM dbo.inv_documento_enc enca INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @EncId;

	IF @estado_actual IS NULL
		THROW 51421, 'El documento indicado no existe.', 1;
	IF @estado_actual <> 'G'
		THROW 51422, 'Solo se pueden anular documentos que estén en estado Grabado.', 1;
	IF @es_nota = 1
		THROW 51423, 'Una nota de crédito o débito no se anula; emita la nota contraria.', 1;
	IF EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_id_referencia = @EncId AND enc_estado = 'G')
		THROW 51424, 'El documento tiene notas de crédito o débito; no se puede anular.', 1;
	IF EXISTS (SELECT 1 FROM dbo.pos_pago_det deta
			   INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
			   INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = deta.cpp_id
			   WHERE cuot.enc_id = @EncId)
		THROW 53227, 'La factura tiene cobros de cuotas; anule primero esos recibos en Cuentas por cobrar › Cobros.', 1;
	IF EXISTS (SELECT 1 FROM dbo.pos_pago_det deta
			   INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
			   LEFT JOIN dbo.pos_caja_apertura aper ON aper.pca_id = pago.pca_id
			   WHERE deta.enc_id = @EncId AND ISNULL(aper.pca_estado, 'C') <> 'A')
		THROW 53228, 'El pago de esta factura entró a una caja que ya se cerró; no se puede anular: emita una nota de crédito.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_det chdt
			   INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = chdt.bce_id AND cheq.bce_estado_cheque <> 'A'
			   WHERE chdt.enc_id = @EncId)
		THROW 53229, 'La compra tiene cheques emitidos; anule primero esos cheques en Cuentas por pagar › Pagos.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		-- El pago de contado o enganche sale del cuadre de la caja (sigue abierta).
		DECLARE @ppe_id INT;
		DECLARE recibos CURSOR LOCAL FAST_FORWARD FOR
			SELECT DISTINCT deta.ppe_id FROM dbo.pos_pago_det deta
			INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
			WHERE deta.enc_id = @EncId;
		OPEN recibos;
		FETCH NEXT FROM recibos INTO @ppe_id;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			EXEC dbo.paCxcReciboReversar @PpeId = @ppe_id, @Motivo = 'Anulación de la factura', @UsuId = @UsuId;
			FETCH NEXT FROM recibos INTO @ppe_id;
		END
		CLOSE recibos; DEALLOCATE recibos;

		EXEC dbo.paInventarioExistenciaDocumentoAjustar @EncId = @EncId, @Reversar = 1, @UsuId = @UsuId;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'A',
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId;

		UPDATE dbo.cont_asiento_enc
		   SET asi_estado = 'N',
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 7. Factura: límite de crédito y formas de pago
------------------------------------------------------------
-- Límite y saldo pendiente del cliente (facturas vigentes). Límite 0 = sin límite.
CREATE OR ALTER FUNCTION [dbo].[fnClienteCredito] (@CliId INT)
RETURNS TABLE
AS
RETURN
	SELECT clie.cli_id AS CliId, ISNULL(clie.cli_limite_credito, 0) AS Limite, ISNULL(sald.Saldo, 0) AS Saldo,
		   CASE WHEN ISNULL(clie.cli_limite_credito, 0) = 0 THEN NULL
				WHEN clie.cli_limite_credito - ISNULL(sald.Saldo, 0) < 0 THEN 0
				ELSE clie.cli_limite_credito - ISNULL(sald.Saldo, 0) END AS Disponible
	FROM dbo.pos_cliente clie
	OUTER APPLY (SELECT SUM(cuot.cpp_saldo_cuota) AS Saldo
				 FROM dbo.pos_cliente_plan_pagos cuot
				 INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
				 WHERE cuot.cli_id = clie.cli_id) sald
	WHERE clie.cli_id = @CliId;
GO

CREATE OR ALTER PROCEDURE [dbo].[paClienteCreditoConsultar]
	@CliId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT CliId, Limite, Saldo, Disponible FROM dbo.fnClienteCredito(@CliId);
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paVentaFacturaCrear]
	@EncFechaDocto			DATE,
	@EncNumeroAutorizacion	VARCHAR(64) = NULL,
	@EncSerieDocto			VARCHAR(32) = NULL,
	@EncNumeroDocto			VARCHAR(32) = NULL,
	@CliId						INT,
	@EncNombresCliente		VARCHAR(128) = NULL,
	@EncApellidosCliente		VARCHAR(128) = NULL,
	@CliNit					VARCHAR(16) = NULL,
	@TdoId						INT,
	@PveId						INT = NULL,
	@EncFechaPrimerPago		DATE = NULL,
	@EncMontoEnganche			NUMERIC(12, 2) = 0,
	@EncNumeroCuotas			INT = 1,
	@EncValorDescuento		NUMERIC(13, 2) = 0,
	@EncDireccionCliente		VARCHAR(256) = NULL,
	@MonId						INT = NULL,
	@UsuId						INT = NULL,
	@Detalle					dbo.factura_det_type READONLY,
	@PcaId						INT = NULL,				-- apertura de caja activa donde se recibe el pago inicial
	@FormasPago				dbo.pago_forma_type READONLY,	-- pago de contado, o enganche si es a crédito; pasar tabla vacía si no aplica
	@EncId						INT OUTPUT,
	@EncNumeroUnico			VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 51401, 'La factura debe tener al menos una línea de detalle.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE det_bien_o_servicio NOT IN ('B', 'S'))
		THROW 53031, 'Cada línea debe ser bien (B) o servicio (S).', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE det_bien_o_servicio = 'B' AND pro_id IS NULL)
		THROW 53032, 'Una línea de bien debe indicar el producto.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE LTRIM(RTRIM(det_descripcion)) = '')
		THROW 53033, 'Toda línea debe tener descripción; en un servicio, describa el servicio prestado.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE det_cantidad <= 0 OR det_precio_unitario < 0)
		THROW 53034, 'La cantidad debe ser mayor a cero y el precio no puede ser negativo.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle deta INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
			   WHERE prod.pro_maneja_existencia = 1 AND deta.det_cantidad <> ROUND(deta.det_cantidad, 0))
		THROW 53035, 'Los productos con existencia se venden en cantidades enteras.', 1;

	IF @MonId IS NULL
		SET @MonId = dbo.fnMonedaLocal();

	IF EXISTS (
		SELECT 1
		FROM (SELECT pro_id, bod_id, SUM(det_cantidad) AS cantidad FROM @Detalle WHERE pro_id IS NOT NULL GROUP BY pro_id, bod_id) pedi
		INNER JOIN dbo.inv_producto prod2 ON prod2.pro_id = pedi.pro_id
		LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = pedi.pro_id AND exis.bod_id = pedi.bod_id
		WHERE prod2.pro_maneja_existencia = 1
		  AND ISNULL(exis.existencia, 0) < pedi.cantidad
	)
		THROW 51402, 'No hay existencia suficiente para uno o más productos del detalle.', 1;

	-- El monto total del documento es el neto (subtotal - descuento) más el
	-- IVA de cada línea; los precios unitarios se manejan sin impuesto
	-- incluido (ver también paContabilidadAsientoDocumentoGenerar).
	DECLARE @monto_total NUMERIC(12, 2) = (
		SELECT SUM((det_sub_total - det_valor_descuento) * (1 + ISNULL(det_porc_iva, 0) / 100.0))
		FROM @Detalle
	);

	-- Contado: las formas de pago cubren el total. Crédito: cubren el enganche
	-- y el resto (lo financiado) no puede pasar del crédito disponible.
	DECLARE @es_credito BIT = CASE WHEN @EncFechaPrimerPago IS NOT NULL AND ISNULL(@EncNumeroCuotas, 0) > 0 THEN 1 ELSE 0 END;
	DECLARE @a_pagar NUMERIC(12, 2) = CASE WHEN @es_credito = 1 THEN ISNULL(@EncMontoEnganche, 0) ELSE @monto_total END;
	DECLARE @formas_total NUMERIC(12, 2) = (SELECT SUM(ppf_monto) FROM @FormasPago);
	DECLARE @msg NVARCHAR(400);

	IF @es_credito = 1 AND (ISNULL(@EncMontoEnganche, 0) < 0 OR ISNULL(@EncMontoEnganche, 0) >= @monto_total)
		THROW 53222, 'El enganche debe ser mayor o igual a cero y menor que el total de la factura.', 1;
	IF @a_pagar > 0 AND @formas_total IS NULL
		THROW 53223, 'Registre la forma de pago del contado o del enganche.', 1;
	IF @formas_total IS NOT NULL AND @formas_total <> @a_pagar
	BEGIN
		SET @msg = CONCAT(N'Las formas de pago suman Q', FORMAT(@formas_total, 'N2'), N' y deben sumar Q', FORMAT(@a_pagar, 'N2'),
			CASE WHEN @es_credito = 1 THEN N' (enganche).' ELSE N' (total de la factura).' END);
		THROW 53224, @msg, 1;
	END
	IF @formas_total IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @PcaId AND pca_estado = 'A')
		THROW 53225, 'No hay una caja abierta para recibir el pago de la factura.', 1;

	IF @es_credito = 1
	BEGIN
		DECLARE @limite NUMERIC(14, 2), @saldo_actual NUMERIC(14, 2);
		SELECT @limite = credito.Limite, @saldo_actual = credito.Saldo FROM dbo.fnClienteCredito(@CliId) credito;
		IF @limite > 0 AND @saldo_actual + (@monto_total - ISNULL(@EncMontoEnganche, 0)) > @limite
		BEGIN
			SET @msg = CONCAT(N'La factura excede el límite de crédito del cliente: límite Q', FORMAT(@limite, 'N2'),
				N', saldo actual Q', FORMAT(@saldo_actual, 'N2'), N', disponible Q', FORMAT(IIF(@limite - @saldo_actual > 0, @limite - @saldo_actual, 0), 'N2'),
				N', a financiar Q', FORMAT(@monto_total - ISNULL(@EncMontoEnganche, 0), 'N2'), N'.');
			THROW 53226, @msg, 1;
		END
	END

	BEGIN TRY
		BEGIN TRANSACTION;

		DECLARE @serie VARCHAR(32), @correlativo NUMERIC(12, 0);

		SELECT @serie = serie, @correlativo = correlativo + 1
		FROM dbo.conf_correlativos WITH (UPDLOCK, ROWLOCK)
		WHERE tdo_id = @TdoId;

		IF @serie IS NULL
			THROW 51403, 'No existe una serie de correlativos configurada para este tipo de documento.', 1;

		UPDATE dbo.conf_correlativos
		   SET correlativo = @correlativo,
			   UpdUsuario = @UsuId,
			   UpdFechaHora = SYSDATETIME()
		 WHERE tdo_id = @TdoId;

		SET @EncNumeroUnico = @serie + '-' + CAST(@correlativo AS VARCHAR(20));

		INSERT INTO dbo.inv_documento_enc
			(enc_fecha_docto, enc_numero_autorizacion, enc_serie_docto, enc_numero_docto,
			 cli_id, enc_nombres_cliente, enc_apellidos_cliente, cli_nit, tdo_id, pve_id,
			 enc_fecha_primer_pago, enc_monto_enganche, enc_numero_cuotas, enc_monto_total,
			 enc_valor_descuento, enc_direccion_cliente, mon_id, usu_id_creacion, enc_numero_unico,
			 InsUsuario, InsFechaHora)
		VALUES
			(@EncFechaDocto, @EncNumeroAutorizacion, @EncSerieDocto, @EncNumeroDocto,
			 @CliId, @EncNombresCliente, @EncApellidosCliente, @CliNit, @TdoId, @PveId,
			 @EncFechaPrimerPago, @EncMontoEnganche, @EncNumeroCuotas, @monto_total,
			 @EncValorDescuento, @EncDireccionCliente, @MonId, @UsuId, @EncNumeroUnico,
			 @UsuId, SYSDATETIME());

		SET @EncId = SCOPE_IDENTITY();

		INSERT INTO dbo.inv_documento_det
			(enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			 det_precio_unitario, det_valor_descuento, det_sub_total, det_costo_unitario, det_porc_iva, bod_id, pro_id, ppr_id, ume_id,
			 InsUsuario, InsFechaHora)
		SELECT
			@EncId, deta.det_item, deta.det_bien_o_servicio, deta.det_cantidad, deta.det_descripcion,
			deta.det_precio_unitario, deta.det_valor_descuento, deta.det_sub_total, deta.det_costo_unitario, deta.det_porc_iva,
			deta.bod_id, deta.pro_id, deta.ppr_id, COALESCE(deta.ume_id, prod.ume_id),
			@UsuId, SYSDATETIME()
		FROM @Detalle deta
		LEFT JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id;

		IF @PcaId IS NOT NULL AND EXISTS (SELECT 1 FROM @FormasPago)
		BEGIN
			DECLARE @ppe_id INT;

			INSERT INTO dbo.pos_pago_enc (cli_id, pca_id, usu_id, InsUsuario, InsFechaHora)
			VALUES (@CliId, @PcaId, @UsuId, @UsuId, SYSDATETIME());

			SET @ppe_id = SCOPE_IDENTITY();

			INSERT INTO dbo.pos_pago_forma
				(gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, ppe_id, pft_id, InsUsuario, InsFechaHora)
			SELECT gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, @ppe_id, pft_id, @UsuId, SYSDATETIME()
			FROM @FormasPago;

			INSERT INTO dbo.pos_pago_det (ppe_id, enc_id, ppd_valor_aplicado, InsUsuario, InsFechaHora)
			SELECT @ppe_id, @EncId, SUM(ppf_monto), @UsuId, SYSDATETIME()
			FROM @FormasPago;
		END

		EXEC dbo.paClientePlanPagosGenerar @EncId = @EncId, @UsuId = @UsuId;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'G',
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId;

		EXEC dbo.paInventarioExistenciaDocumentoAjustar @EncId = @EncId, @UsuId = @UsuId;

		DECLARE @asi_id INT;
		EXEC dbo.paContabilidadAsientoDocumentoGenerar @EncId = @EncId, @UsuId = @UsuId, @AsiId = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

