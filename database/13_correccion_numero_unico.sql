------------------------------------------------------------------------------
-- 13_correccion_numero_unico.sql
--
-- Corrige un bug real encontrado al usar el módulo de Ventas/POS desde el
-- frontend: la restricción UQ_inv_documento_enc_numero_unico era una UNIQUE
-- constraint normal sobre una columna nullable. En SQL Server ese tipo de
-- restricción solo permite UN valor NULL en toda la tabla (no varios, como
-- en PostgreSQL/Oracle). Como paCompraDocumentoCrear nunca llena
-- enc_numero_unico (las compras no usan ese correlativo), la primera compra
-- de la vida del sistema deja esa columna en NULL, y CUALQUIER documento
-- posterior que también intente insertarse con NULL en ese instante (toda
-- factura nueva, porque el INSERT original de paVentaFacturaCrear lo
-- dejaba en NULL momentáneamente) choca contra ese primer NULL y falla con:
--   "Violation of UNIQUE KEY constraint 'UQ_inv_documento_enc_numero_unico'.
--    Cannot insert duplicate key... The duplicate key value is (<NULL>)."
--
-- Efecto colateral en tus datos sintéticos: el bloque de "Compras
-- adicionales de reabastecimiento" en 12_datos_sinteticos.sql atrapa el
-- error con TRY/CATCH y solo lo imprime ("Compra de reabastecimiento #N
-- omitida: ..."), así que probablemente solo tengas 1 compra real en tu
-- base (la inicial) en vez de 11 - los mensajes "omitida" quedaron en la
-- pestaña Messages de SSMS sin que fuera obviamente un error.
--
-- Este script:
--   1) Cambia esa restricción por un ÍNDICE ÚNICO FILTRADO (permite muchos
--      NULL, pero sigue evitando que dos documentos comparta un número real).
--   2) Redespliega paVentaFacturaCrear ya corregido (graba
--      enc_numero_unico directo en el INSERT en vez de dejarlo en NULL y
--      actualizarlo después).
--
-- Es seguro correrlo una sola vez contra tu base ya creada; no borra ni
-- modifica los datos existentes (00-12 también quedaron corregidos en el
-- repositorio para cualquier instalación nueva desde cero).
------------------------------------------------------------------------------
USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF EXISTS (
	SELECT 1 FROM sys.key_constraints
	WHERE name = 'UQ_inv_documento_enc_numero_unico'
	  AND parent_object_id = OBJECT_ID('dbo.inv_documento_enc')
)
BEGIN
	ALTER TABLE dbo.inv_documento_enc DROP CONSTRAINT UQ_inv_documento_enc_numero_unico;
END;
GO

IF NOT EXISTS (
	SELECT 1 FROM sys.indexes
	WHERE name = 'UQ_inv_documento_enc_numero_unico'
	  AND object_id = OBJECT_ID('dbo.inv_documento_enc')
)
BEGIN
	CREATE UNIQUE INDEX [UQ_inv_documento_enc_numero_unico]
		ON [dbo].[inv_documento_enc] ([enc_numero_unico])
		WHERE [enc_numero_unico] IS NOT NULL;
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
			 det_precio_unitario, det_valor_descuento, det_sub_total, det_porc_iva, bod_id, pro_id, ppr_id,
			 InsUsuario, InsFechaHora)
		SELECT
			@EncId, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			det_precio_unitario, det_valor_descuento, det_sub_total, det_porc_iva, bod_id, pro_id, ppr_id,
			@UsuId, SYSDATETIME()
		FROM @Detalle;

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

------------------------------------------------------------------------------
-- Opcional: reintenta ahora las 10 compras de reabastecimiento que tu base
-- probablemente omitió en silencio por este mismo bug. Si prefieres no
-- tocar tus datos actuales, puedes borrar/comentar este bloque; no afecta
-- la corrección de arriba, que ya quedó aplicada.
------------------------------------------------------------------------------
DECLARE @i INT = 1;
DECLARE @bod1 INT = (SELECT TOP 1 bode.bod_id FROM dbo.inv_bodega bode INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
				   WHERE bode.bod_codigo = 'BOD01' ORDER BY CASE sucu.suc_codigo WHEN 'SUC01' THEN 0 ELSE 1 END, sucu.cia_id, bode.bod_id);
DECLARE @tdo_comp INT = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo = 'COMP');
DECLARE @compras_creadas INT = 0;

-- Con el 12 ya corregido las compras de reabastecimiento sí existen; solo se
-- reintentan en una base donde no se creó ninguna.
IF EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_numero_docto LIKE 'REST-%')
BEGIN
	PRINT 'La base ya tiene compras de reabastecimiento; no se reintentan.';
	SET @i = 11;
END

WHILE @i <= 10
BEGIN
	BEGIN TRY
		DECLARE @det2 dbo.compra_det_type;
		-- Una variable de tabla declarada dentro del WHILE no se reinicia en cada
		-- vuelta: conserva las filas anteriores y repetiría det_item. Se vacía aquí.
		DELETE FROM @det2;
		DECLARE @pro_sel INT, @precio_sel NUMERIC(12, 2), @cant_sel INT = 10 + (ABS(CHECKSUM(NEWID())) % 30);
		DECLARE @prv_sel INT;
		DECLARE @fecha_compra_i DATE = DATEADD(DAY, -1 * (ABS(CHECKSUM(NEWID())) % 120), CAST(GETDATE() AS DATE));
		DECLARE @numero_docto_compra VARCHAR(32) = CONCAT('REST-FIX-', @i);

		SELECT TOP 1 @pro_sel = pro.pro_id, @precio_sel = precio.ppr_precio_unitario_venta
		FROM dbo.inv_producto pro
		INNER JOIN dbo.inv_producto_precio precio ON precio.pro_id = pro.pro_id AND precio.ppr_estado = 'A'
		WHERE pro.pro_maneja_existencia = 1
		ORDER BY NEWID();

		SELECT @prv_sel = prv_id FROM dbo.inv_producto_proveedor WHERE pro_id = @pro_sel;

		INSERT INTO @det2 (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total, det_porc_iva, bod_id, pro_id)
		SELECT 1, 'B', @cant_sel, pro_descripcion, @precio_sel * 0.62, (@precio_sel * 0.62) * @cant_sel, 12, @bod1, @pro_sel
		FROM dbo.inv_producto WHERE pro_id = @pro_sel;

		DECLARE @enc_compra INT;
		EXEC dbo.paCompraDocumentoCrear
			@EncFechaDocto = @fecha_compra_i,
			@EncNumeroDocto = @numero_docto_compra,
			@PrvId = @prv_sel, @TdoId = @tdo_comp, @EncNumeroCuotas = 1,
			@Detalle = @det2, @EncId = @enc_compra OUTPUT;

		SET @compras_creadas = @compras_creadas + 1;
	END TRY
	BEGIN CATCH
		PRINT 'Compra de reabastecimiento (fix) #' + CAST(@i AS VARCHAR) + ' omitida: ' + ERROR_MESSAGE();
	END CATCH

	SET @i = @i + 1;
END;

PRINT 'Compras de reabastecimiento creadas en este reintento: ' + CAST(@compras_creadas AS VARCHAR);
GO
