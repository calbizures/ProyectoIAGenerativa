------------------------------------------------------------------------------
-- 24_formas_pago_factura_cobro.sql
--
-- Habilita las formas de pago (efectivo, cheque, tarjeta) tanto en el pago
-- inicial de una factura (de contado, o el enganche si es a crédito) como
-- en el cobro de una cuota:
--   * paVentaFacturaCrear recibe @pca_id (apertura de caja activa) y
--     @formas_pago; si vienen, graba pos_pago_enc/pos_pago_forma/pos_pago_det
--     (este último ahora con enc_id, ver 22_sucursal_caja_formas_pago_tablas.sql).
--   * paClienteCuotaPagoRegistrar recibe @formas_pago y también graba
--     pos_pago_forma (antes esa tabla nunca se llenaba).
--   * Siembra pos_pago_forma_tipo con Efectivo/Tarjeta/Cheque/Transferencia
--     por si no se corrió 12_datos_sinteticos.sql (es opcional).
--
-- Seguro de correr una sola vez contra una base ya creada con 00-23.
------------------------------------------------------------------------------

USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Por si ya corriste una versión anterior de este mismo script: hay que
-- quitar primero los procedimientos que usan el tipo de tabla antes de
-- poder recrearlo (SQL Server no permite DROP TYPE si sigue en uso).
DROP PROCEDURE IF EXISTS [dbo].[paVentaFacturaCrear];
DROP PROCEDURE IF EXISTS [dbo].[paClienteCuotaPagoRegistrar];
GO

-- Forma(s) de pago del monto pagado al momento de facturar (de contado, o
-- el enganche si es a crédito) y del cobro de una cuota. Un mismo pago
-- puede dividirse en varias formas (p.ej. parte efectivo, parte cheque).
-- Solo se crea si no existe: al volver a correr el script no se puede borrar
-- porque ya lo usan procedimientos de scripts posteriores (p. ej. 34).
IF TYPE_ID(N'dbo.pago_forma_type') IS NULL
CREATE TYPE [dbo].[pago_forma_type] AS TABLE
(
	[pft_id]							INT				NOT NULL,
	[ppf_monto]							NUMERIC(12, 2)	NOT NULL,
	[gef_id]							INT				NULL,
	[ppf_numero_tarjeta_ult4]			VARCHAR(4)		NULL,
	[ppf_fecha_vencimiento_tarjeta]	VARCHAR(4)		NULL,
	[ppf_numero_cheque]					VARCHAR(16)		NULL
);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.pos_pago_forma_tipo)
	INSERT INTO dbo.pos_pago_forma_tipo (pft_descripcion) VALUES ('Efectivo'), ('Tarjeta'), ('Cheque'), ('Transferencia');
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
	@FormasPago				dbo.pago_forma_type READONLY,	-- pago de contado, o enganche si es a crédito; SQL Server no permite default en un TVP, pasar tabla vacía si no aplica
	@EncId						INT OUTPUT,
	@EncNumeroUnico			VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 51401, 'La factura debe tener al menos una línea de detalle.', 1;

	IF @MonId IS NULL
		SET @MonId = dbo.fnMonedaLocal();

	IF EXISTS (
		SELECT 1
		FROM @Detalle line
		INNER JOIN dbo.inv_producto prod ON prod.pro_id = line.pro_id
		LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = line.pro_id AND exis.bod_id = line.bod_id
		WHERE prod.pro_maneja_existencia = 1
		  AND ISNULL(exis.existencia, 0) < line.det_cantidad
	)
		THROW 51402, 'No hay existencia suficiente para uno o más productos del detalle.', 1;

	-- El monto total del documento es el neto (subtotal - descuento) más el
	-- IVA de cada línea; los precios unitarios se manejan sin impuesto
	-- incluido (ver también paContabilidadAsientoDocumentoGenerar).
	DECLARE @monto_total NUMERIC(12, 2) = (
		SELECT SUM((det_sub_total - det_valor_descuento) * (1 + ISNULL(det_porc_iva, 0) / 100.0))
		FROM @Detalle
	);

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
			 det_precio_unitario, det_valor_descuento, det_sub_total, det_costo_unitario, det_porc_iva, bod_id, pro_id, ppr_id,
			 InsUsuario, InsFechaHora)
		SELECT
			@EncId, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			det_precio_unitario, det_valor_descuento, det_sub_total, det_costo_unitario, det_porc_iva, bod_id, pro_id, ppr_id,
			@UsuId, SYSDATETIME()
		FROM @Detalle;

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

CREATE OR ALTER PROCEDURE [dbo].[paClienteCuotaPagoRegistrar]
	@CppId			INT,
	@ValorPago		NUMERIC(12, 2),
	@PcaId			INT,
	@UsuId			INT = NULL,
	@FormasPago	dbo.pago_forma_type READONLY,	-- SQL Server no permite default en un TVP, pasar tabla vacía si no aplica
	@PpeId			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @ValorPago <= 0
		THROW 51501, 'El valor del pago debe ser mayor a cero.', 1;

	DECLARE @cli_id INT, @saldo NUMERIC(12, 2), @estado CHAR(1);
	SELECT @cli_id = cli_id, @saldo = cpp_saldo_cuota, @estado = cpp_estado
	FROM dbo.pos_cliente_plan_pagos WHERE cpp_id = @CppId;

	IF @cli_id IS NULL
		THROW 51502, 'La cuota indicada no existe.', 1;

	IF @estado = 'A'
		THROW 51503, 'La cuota indicada ya está abonada por completo.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.pos_pago_enc (cli_id, pca_id, usu_id, InsUsuario, InsFechaHora)
		VALUES (@cli_id, @PcaId, @UsuId, @UsuId, SYSDATETIME());

		SET @PpeId = SCOPE_IDENTITY();

		INSERT INTO dbo.pos_pago_det (ppe_id, cpp_id, ppd_valor_aplicado, InsUsuario, InsFechaHora)
		VALUES (@PpeId, @CppId, @ValorPago, @UsuId, SYSDATETIME());

		INSERT INTO dbo.pos_pago_forma
			(gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, ppe_id, pft_id, InsUsuario, InsFechaHora)
		SELECT gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, @PpeId, pft_id, @UsuId, SYSDATETIME()
		FROM @FormasPago;

		UPDATE dbo.pos_cliente_plan_pagos
		   SET cpp_saldo_cuota = cpp_saldo_cuota - @ValorPago,
			   cpp_fecha_real_pago = CASE WHEN cpp_saldo_cuota - @ValorPago <= 0 THEN CAST(GETDATE() AS DATE) ELSE cpp_fecha_real_pago END,
			   cpp_estado = CASE WHEN cpp_saldo_cuota - @ValorPago <= 0 THEN 'A' ELSE cpp_estado END,
			   UpdUsuario = @UsuId,
			   UpdFechaHora = SYSDATETIME()
		 WHERE cpp_id = @CppId;

		DECLARE @pdo_id INT, @asi_id INT, @detalle dbo.cont_asiento_det_type, @fecha_hoy DATE = CAST(GETDATE() AS DATE);
		EXEC dbo.paContabilidadPeriodoObtenerOCrear @Fecha = NULL, @UsuId = @UsuId, @PdoId = @pdo_id OUTPUT;

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, @ValorPago, 0, 'Cobro cuota ' + CAST(@CppId AS VARCHAR(10)) FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'COBRO_CAJA'
		UNION ALL
		SELECT cta_id, 0, @ValorPago, 'Cobro cuota ' + CAST(@CppId AS VARCHAR(10)) FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'COBRO_CLIENTES';

		-- EXEC no acepta una expresión directamente como valor de un
		-- parámetro con nombre; @fecha_hoy ya se calculó arriba.
		EXEC dbo.paContabilidadAsientoInsertar
			@AsiFecha = @fecha_hoy, @AsiDescripcion = 'Cobro cuota de cliente',
			@AsiOrigen = 'PAGO_CLIENTE', @UsuId = @UsuId, @Detalle = @detalle, @AsiId = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO
