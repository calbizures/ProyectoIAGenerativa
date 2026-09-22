------------------------------------------------------------------------------
-- 24_formas_pago_factura_cobro.sql
--
-- Habilita las formas de pago (efectivo, cheque, tarjeta) tanto en el pago
-- inicial de una factura (de contado, o el enganche si es a crédito) como
-- en el cobro de una cuota:
--   * sp_ventas_crear_factura recibe @pca_id (apertura de caja activa) y
--     @formas_pago; si vienen, graba pos_pago_enc/pos_pago_forma/pos_pago_det
--     (este último ahora con enc_id, ver 22_sucursal_caja_formas_pago_tablas.sql).
--   * sp_pos_registrar_pago_cuota recibe @formas_pago y también graba
--     pos_pago_forma (antes esa tabla nunca se llenaba).
--   * Siembra pos_pago_forma_tipo con Efectivo/Tarjeta/Cheque/Transferencia
--     por si no se corrió 12_datos_sinteticos.sql (es opcional).
--
-- Seguro de correr una sola vez contra una base ya creada con 00-23.
------------------------------------------------------------------------------

USE [erp_db];
GO

-- Por si ya corriste una versión anterior de este mismo script: hay que
-- quitar primero los procedimientos que usan el tipo de tabla antes de
-- poder recrearlo (SQL Server no permite DROP TYPE si sigue en uso).
DROP PROCEDURE IF EXISTS [dbo].[sp_ventas_crear_factura];
DROP PROCEDURE IF EXISTS [dbo].[sp_pos_registrar_pago_cuota];
GO

-- Forma(s) de pago del monto pagado al momento de facturar (de contado, o
-- el enganche si es a crédito) y del cobro de una cuota. Un mismo pago
-- puede dividirse en varias formas (p.ej. parte efectivo, parte cheque).
IF TYPE_ID(N'dbo.pago_forma_type') IS NOT NULL
	DROP TYPE [dbo].[pago_forma_type];
GO
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

CREATE OR ALTER PROCEDURE [dbo].[sp_ventas_crear_factura]
	@enc_fecha_docto			DATE,
	@enc_numero_autorizacion	VARCHAR(64) = NULL,
	@enc_serie_docto			VARCHAR(32) = NULL,
	@enc_numero_docto			VARCHAR(32) = NULL,
	@cli_id						INT,
	@enc_nombres_cliente		VARCHAR(128) = NULL,
	@enc_apellidos_cliente		VARCHAR(128) = NULL,
	@cli_nit					VARCHAR(16) = NULL,
	@tdo_id						INT,
	@pve_id						INT = NULL,
	@enc_fecha_primer_pago		DATE = NULL,
	@enc_monto_enganche			NUMERIC(12, 2) = 0,
	@enc_numero_cuotas			INT = 1,
	@enc_valor_descuento		NUMERIC(13, 2) = 0,
	@enc_direccion_cliente		VARCHAR(256) = NULL,
	@mon_id						INT = NULL,
	@usu_id						INT = NULL,
	@detalle					dbo.factura_det_type READONLY,
	@pca_id						INT = NULL,				-- apertura de caja activa donde se recibe el pago inicial
	@formas_pago				dbo.pago_forma_type READONLY = NULL,	-- pago de contado, o enganche si es a crédito
	@enc_id						INT OUTPUT,
	@enc_numero_unico			VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @detalle)
		THROW 51401, 'La factura debe tener al menos una línea de detalle.', 1;

	IF @mon_id IS NULL
		SET @mon_id = dbo.fn_moneda_local();

	IF EXISTS (
		SELECT 1
		FROM @detalle d
		INNER JOIN dbo.inv_producto p ON p.pro_id = d.pro_id
		LEFT JOIN dbo.inv_producto_existencia_bodega e ON e.pro_id = d.pro_id AND e.bod_id = d.bod_id
		WHERE p.pro_maneja_existencia = 1
		  AND ISNULL(e.existencia, 0) < d.det_cantidad
	)
		THROW 51402, 'No hay existencia suficiente para uno o más productos del detalle.', 1;

	-- El monto total del documento es el neto (subtotal - descuento) más el
	-- IVA de cada línea; los precios unitarios se manejan sin impuesto
	-- incluido (ver también sp_contabilidad_generar_asiento_documento).
	DECLARE @monto_total NUMERIC(12, 2) = (
		SELECT SUM((det_sub_total - det_valor_descuento) * (1 + ISNULL(det_porc_iva, 0) / 100.0))
		FROM @detalle
	);

	BEGIN TRY
		BEGIN TRANSACTION;

		DECLARE @serie VARCHAR(32), @correlativo NUMERIC(12, 0);

		SELECT @serie = serie, @correlativo = correlativo + 1
		FROM dbo.conf_correlativos WITH (UPDLOCK, ROWLOCK)
		WHERE tdo_id = @tdo_id;

		IF @serie IS NULL
			THROW 51403, 'No existe una serie de correlativos configurada para este tipo de documento.', 1;

		UPDATE dbo.conf_correlativos
		   SET correlativo = @correlativo,
			   UpdUsuario = @usu_id,
			   UpdFechaHora = SYSDATETIME()
		 WHERE tdo_id = @tdo_id;

		SET @enc_numero_unico = @serie + '-' + CAST(@correlativo AS VARCHAR(20));

		INSERT INTO dbo.inv_documento_enc
			(enc_fecha_docto, enc_numero_autorizacion, enc_serie_docto, enc_numero_docto,
			 cli_id, enc_nombres_cliente, enc_apellidos_cliente, cli_nit, tdo_id, pve_id,
			 enc_fecha_primer_pago, enc_monto_enganche, enc_numero_cuotas, enc_monto_total,
			 enc_valor_descuento, enc_direccion_cliente, mon_id, usu_id_creacion, enc_numero_unico,
			 InsUsuario, InsFechaHora)
		VALUES
			(@enc_fecha_docto, @enc_numero_autorizacion, @enc_serie_docto, @enc_numero_docto,
			 @cli_id, @enc_nombres_cliente, @enc_apellidos_cliente, @cli_nit, @tdo_id, @pve_id,
			 @enc_fecha_primer_pago, @enc_monto_enganche, @enc_numero_cuotas, @monto_total,
			 @enc_valor_descuento, @enc_direccion_cliente, @mon_id, @usu_id, @enc_numero_unico,
			 @usu_id, SYSDATETIME());

		SET @enc_id = SCOPE_IDENTITY();

		INSERT INTO dbo.inv_documento_det
			(enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			 det_precio_unitario, det_valor_descuento, det_sub_total, det_costo_unitario, det_porc_iva, bod_id, pro_id, ppr_id,
			 InsUsuario, InsFechaHora)
		SELECT
			@enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			det_precio_unitario, det_valor_descuento, det_sub_total, det_costo_unitario, det_porc_iva, bod_id, pro_id, ppr_id,
			@usu_id, SYSDATETIME()
		FROM @detalle;

		IF @pca_id IS NOT NULL AND EXISTS (SELECT 1 FROM @formas_pago)
		BEGIN
			DECLARE @ppe_id INT;

			INSERT INTO dbo.pos_pago_enc (cli_id, pca_id, usu_id, InsUsuario, InsFechaHora)
			VALUES (@cli_id, @pca_id, @usu_id, @usu_id, SYSDATETIME());

			SET @ppe_id = SCOPE_IDENTITY();

			INSERT INTO dbo.pos_pago_forma
				(gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, ppe_id, pft_id, InsUsuario, InsFechaHora)
			SELECT gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, @ppe_id, pft_id, @usu_id, SYSDATETIME()
			FROM @formas_pago;

			INSERT INTO dbo.pos_pago_det (ppe_id, enc_id, ppd_valor_aplicado, InsUsuario, InsFechaHora)
			SELECT @ppe_id, @enc_id, SUM(ppf_monto), @usu_id, SYSDATETIME()
			FROM @formas_pago;
		END

		EXEC dbo.sp_pos_generar_plan_pagos_cliente @enc_id = @enc_id, @usu_id = @usu_id;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'G',
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @enc_id;

		EXEC dbo.sp_inventario_ajustar_existencia_documento @enc_id = @enc_id, @usu_id = @usu_id;

		DECLARE @asi_id INT;
		EXEC dbo.sp_contabilidad_generar_asiento_documento @enc_id = @enc_id, @usu_id = @usu_id, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_pos_registrar_pago_cuota]
	@cpp_id			INT,
	@valor_pago		NUMERIC(12, 2),
	@pca_id			INT,
	@usu_id			INT = NULL,
	@formas_pago	dbo.pago_forma_type READONLY = NULL,
	@ppe_id			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @valor_pago <= 0
		THROW 51501, 'El valor del pago debe ser mayor a cero.', 1;

	DECLARE @cli_id INT, @saldo NUMERIC(12, 2), @estado CHAR(1);
	SELECT @cli_id = cli_id, @saldo = cpp_saldo_cuota, @estado = cpp_estado
	FROM dbo.pos_cliente_plan_pagos WHERE cpp_id = @cpp_id;

	IF @cli_id IS NULL
		THROW 51502, 'La cuota indicada no existe.', 1;

	IF @estado = 'A'
		THROW 51503, 'La cuota indicada ya está abonada por completo.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.pos_pago_enc (cli_id, pca_id, usu_id, InsUsuario, InsFechaHora)
		VALUES (@cli_id, @pca_id, @usu_id, @usu_id, SYSDATETIME());

		SET @ppe_id = SCOPE_IDENTITY();

		INSERT INTO dbo.pos_pago_det (ppe_id, cpp_id, ppd_valor_aplicado, InsUsuario, InsFechaHora)
		VALUES (@ppe_id, @cpp_id, @valor_pago, @usu_id, SYSDATETIME());

		INSERT INTO dbo.pos_pago_forma
			(gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, ppe_id, pft_id, InsUsuario, InsFechaHora)
		SELECT gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, @ppe_id, pft_id, @usu_id, SYSDATETIME()
		FROM @formas_pago;

		UPDATE dbo.pos_cliente_plan_pagos
		   SET cpp_saldo_cuota = cpp_saldo_cuota - @valor_pago,
			   cpp_fecha_real_pago = CASE WHEN cpp_saldo_cuota - @valor_pago <= 0 THEN CAST(GETDATE() AS DATE) ELSE cpp_fecha_real_pago END,
			   cpp_estado = CASE WHEN cpp_saldo_cuota - @valor_pago <= 0 THEN 'A' ELSE cpp_estado END,
			   UpdUsuario = @usu_id,
			   UpdFechaHora = SYSDATETIME()
		 WHERE cpp_id = @cpp_id;

		DECLARE @pdo_id INT, @asi_id INT, @detalle dbo.cont_asiento_det_type, @fecha_hoy DATE = CAST(GETDATE() AS DATE);
		EXEC dbo.sp_contabilidad_obtener_o_crear_periodo @fecha = NULL, @usu_id = @usu_id, @pdo_id = @pdo_id OUTPUT;

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, @valor_pago, 0, 'Cobro cuota ' + CAST(@cpp_id AS VARCHAR(10)) FROM dbo.cont_cuenta_contable WHERE cta_codigo = '1105'
		UNION ALL
		SELECT cta_id, 0, @valor_pago, 'Cobro cuota ' + CAST(@cpp_id AS VARCHAR(10)) FROM dbo.cont_cuenta_contable WHERE cta_codigo = '1205';

		-- EXEC no acepta una expresión directamente como valor de un
		-- parámetro con nombre; @fecha_hoy ya se calculó arriba.
		EXEC dbo.sp_contabilidad_insertar_asiento
			@asi_fecha = @fecha_hoy, @asi_descripcion = 'Cobro cuota de cliente',
			@asi_origen = 'PAGO_CLIENTE', @usu_id = @usu_id, @detalle = @detalle, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO
