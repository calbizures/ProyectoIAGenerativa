------------------------------------------------------------------------------
-- 21_costo_unitario_ppr_id_factura.sql
--
-- inv_documento_det ya tenía las columnas det_costo_unitario y ppr_id desde
-- el diseño original, pero sp_ventas_crear_factura nunca las llenaba:
--   * det_precio_unitario queda con el precio de venta (ya funcionaba).
--   * det_costo_unitario ahora se llena con el costo unitario del producto
--     al momento de la venta (antes quedaba NULL).
--   * ppr_id ahora se llena con el inv_producto_precio.ppr_id de la lista
--     de precios con el que se vendió (antes quedaba NULL: el frontend
--     nunca lo enviaba, aunque el procedimiento sí lo recibía).
--   * det_bien_o_servicio ('B' o 'S') ya se llenaba correctamente desde el
--     tipo de producto; no cambia con este script.
--
-- Como dbo.factura_det_type es un parámetro con tipo de tabla, no se puede
-- alterar in-place: hay que quitar temporalmente el procedimiento que lo
-- usa, recrear el tipo con la columna nueva, y volver a crear el
-- procedimiento.
--
-- Seguro de correr una sola vez contra una base ya creada con 00-20.
------------------------------------------------------------------------------

USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DROP PROCEDURE IF EXISTS [dbo].[sp_ventas_crear_factura];
GO

DROP TYPE IF EXISTS [dbo].[factura_det_type];
GO

CREATE TYPE [dbo].[factura_det_type] AS TABLE
(
	[det_item]				INT				NOT NULL,
	[det_bien_o_servicio]	CHAR(1)			NOT NULL,
	[det_cantidad]			INT				NOT NULL,
	[det_descripcion]		VARCHAR(256)	NOT NULL,
	[det_precio_unitario]	NUMERIC(12, 2)	NOT NULL,	-- precio unitario de venta
	[det_valor_descuento]	NUMERIC(12, 2)	NOT NULL DEFAULT (0),
	[det_sub_total]			NUMERIC(12, 2)	NOT NULL,
	[det_costo_unitario]	NUMERIC(12, 5)	NULL,		-- costo unitario del producto al momento de la venta
	[det_porc_iva]			NUMERIC(8, 2)	NULL,
	[bod_id]				INT				NOT NULL,
	[pro_id]				INT				NULL,
	[ppr_id]				INT				NULL		-- inv_producto_precio.ppr_id con el que se vendió
);
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
