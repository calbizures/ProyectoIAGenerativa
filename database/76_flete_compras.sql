/*
================================================================================
 76_flete_compras.sql
 Flete de las compras, prorrateado al costo del inventario.

 En Guatemala el flete para traer la mercadería es parte de su costo de
 adquisición (NIC 2 / NIIF para PYMES, sección 13): se suma al costo de los
 productos, no se registra como gasto. El IVA del flete es crédito fiscal,
 como el de la mercadería. Hay dos casos:

   A. Flete incluido en la factura del proveedor (una sola factura FEL):
      se escribe en la compra (o al recibir la orden de compra). La compra
      lleva una línea de servicio "Flete" (det_es_flete = 1) y su valor sin
      IVA se reparte entre los productos de la compra en proporción a su
      valor: el costo unitario de cada producto (det_costo_unitario) ya
      incluye su parte del flete.
        paCompraDocumentoCrear  @EncFlete: flete sin IVA de esta factura.
        paInventarioExistenciaDocumentoAjustar  reparte el flete al grabar.

   B. Flete en otra factura (el transportista, o el mismo proveedor en una
      factura aparte): se graba como una compra del transportista con el
      servicio de flete, vinculada a la compra de la mercadería
      (enc_id_compra_flete). Su valor sin IVA se reparte entre los productos
      de esa compra por valor y se suma al costo promedio de la existencia
      actual (inv_compra_flete). La parte de productos que ya no tienen
      existencia (se vendieron) va al costo de ventas.
        paCompraDocumentoCrear  @EncIdCompraFlete: compra a la que se carga.
        paCompraFleteAplicar / paCompraFleteReversar  (al grabar y anular).
        paContabilidadAsientoDocumentoGenerar  póliza del flete: inventario
                                y costo de ventas, IVA crédito fiscal y
                                cuenta por pagar al transportista.
        paDocumentoAnular       no anula una compra con flete vigente en
                                otra factura; al anular el flete reversa
                                lo que sumó al costo.
        paInventarioKardexConsultar  muestra el flete sumado al costo.

   Órdenes de compra: cmp_orden_compra_enc.ocp_flete_tipo
        N  sin flete (lo absorbe el proveedor: precio puesto en bodega)
        I  incluido en la factura del proveedor: ocp_flete (con IVA) se suma
           al total de la orden y se propone al recibirla
        S  facturado aparte (estimado, no suma al total)
        paOrdenCompraGuardar        @FleteTipo y @Flete.
        paOrdenCompraRecibir        @Flete (con IVA) de esa factura.
        paOrdenCompraConsultarPorId devuelve el flete y lo ya recibido.

 Requiere el 75. Errores nuevos: 55930 a 55937.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Columnas y tabla del reparto
------------------------------------------------------------
IF COL_LENGTH('dbo.inv_documento_det', 'det_es_flete') IS NULL
	ALTER TABLE dbo.inv_documento_det ADD [det_es_flete] BIT NOT NULL
		CONSTRAINT DF_inv_documento_det_es_flete DEFAULT (0);
GO

IF COL_LENGTH('dbo.inv_documento_enc', 'enc_id_compra_flete') IS NULL
	ALTER TABLE dbo.inv_documento_enc ADD [enc_id_compra_flete] INT NULL
		CONSTRAINT FK_inv_documento_enc_compra_flete FOREIGN KEY REFERENCES dbo.inv_documento_enc ([enc_id]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_inv_documento_enc_compra_flete')
	CREATE INDEX [IX_inv_documento_enc_compra_flete] ON dbo.inv_documento_enc ([enc_id_compra_flete])
		WHERE [enc_id_compra_flete] IS NOT NULL;
GO

IF COL_LENGTH('dbo.cmp_orden_compra_enc', 'ocp_flete_tipo') IS NULL
	ALTER TABLE dbo.cmp_orden_compra_enc ADD
		[ocp_flete_tipo] CHAR(1) NOT NULL CONSTRAINT DF_cmp_orden_compra_enc_flete_tipo DEFAULT ('N'),
		[ocp_flete] NUMERIC(14, 2) NOT NULL CONSTRAINT DF_cmp_orden_compra_enc_flete DEFAULT (0);
GO

IF OBJECT_ID('dbo.CK_cmp_orden_compra_enc_flete', 'C') IS NULL
	ALTER TABLE dbo.cmp_orden_compra_enc ADD CONSTRAINT [CK_cmp_orden_compra_enc_flete]
		CHECK ([ocp_flete_tipo] IN ('N', 'I', 'S') AND [ocp_flete] >= 0 AND ([ocp_flete_tipo] <> 'N' OR [ocp_flete] = 0));
GO

-- Reparto de una factura de flete (caso B) entre los productos de la compra.
IF OBJECT_ID('dbo.inv_compra_flete', 'U') IS NULL
CREATE TABLE [dbo].[inv_compra_flete](
	[icf_id]			INT				IDENTITY(1, 1) NOT NULL,
	[enc_id]			INT				NOT NULL,	-- la factura del flete
	[enc_id_compra]		INT				NOT NULL,	-- la compra de la mercadería
	[pro_id]			INT				NOT NULL,
	[bod_id]			INT				NOT NULL,
	[icf_monto]			NUMERIC(14, 2)	NOT NULL,	-- parte del flete sin IVA
	[icf_capitalizado]	BIT				NOT NULL,	-- 1 sumado al costo del inventario; 0 al costo de ventas
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL CONSTRAINT [DF_inv_compra_flete_InsFechaHora] DEFAULT (SYSDATETIME()),
	CONSTRAINT [PK_inv_compra_flete] PRIMARY KEY ([icf_id]),
	CONSTRAINT [FK_inv_compra_flete_flete] FOREIGN KEY ([enc_id]) REFERENCES dbo.inv_documento_enc ([enc_id]),
	CONSTRAINT [FK_inv_compra_flete_compra] FOREIGN KEY ([enc_id_compra]) REFERENCES dbo.inv_documento_enc ([enc_id]),
	CONSTRAINT [FK_inv_compra_flete_producto] FOREIGN KEY ([pro_id]) REFERENCES dbo.inv_producto ([pro_id]),
	CONSTRAINT [FK_inv_compra_flete_bodega] FOREIGN KEY ([bod_id]) REFERENCES dbo.inv_bodega ([bod_id]),
	CONSTRAINT [FK_inv_compra_flete_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES dbo.gen_usuario ([usu_id])
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_inv_compra_flete_producto')
	CREATE INDEX [IX_inv_compra_flete_producto] ON dbo.inv_compra_flete ([pro_id]) INCLUDE ([enc_id], [bod_id], [icf_monto], [icf_capitalizado]);
GO

------------------------------------------------------------
-- 2. Costo de los ingresos con el flete de la misma factura (caso A)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paInventarioExistenciaDocumentoAjustar]
	@EncId		INT,
	@Reversar	BIT = 0,	-- 1 = revertir el efecto (usado al anular un documento)
	@UsuId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @naturaleza_signo INT, @reversar_signo INT = CASE WHEN @Reversar = 1 THEN -1 ELSE 1 END;

	SELECT @naturaleza_signo = CASE WHEN tipo.tdo_naturaleza = '+' THEN 1 ELSE -1 END
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @EncId;

	IF @naturaleza_signo IS NULL
		THROW 51201, 'El documento indicado no existe.', 1;

	-- Al grabar, cada línea con producto guarda su costo unitario: en un
	-- ingreso (compra) es lo pagado sin IVA y neto de descuento, más su parte
	-- del flete de la misma factura (por valor, solo entre los productos que
	-- manejan existencia); en un egreso (venta) es el costo promedio del
	-- producto en este momento.
	IF @Reversar = 0
	BEGIN
		DECLARE @flete NUMERIC(14, 2) = 0, @base NUMERIC(16, 2) = 0;
		IF @naturaleza_signo = 1
		BEGIN
			SELECT @flete = ISNULL(SUM(det_sub_total - ISNULL(det_valor_descuento, 0)), 0)
			FROM dbo.inv_documento_det WHERE enc_id = @EncId AND det_es_flete = 1;
			SELECT @base = ISNULL(SUM(deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)), 0)
			FROM dbo.inv_documento_det deta
			INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id AND prod.pro_maneja_existencia = 1
			WHERE deta.enc_id = @EncId AND deta.det_cantidad > 0 AND deta.det_es_flete = 0;
		END

		UPDATE deta
		   SET det_costo_unitario = CASE WHEN @naturaleza_signo = 1
										 THEN (deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)
											   + CASE WHEN @flete > 0 AND @base > 0 AND prod.pro_maneja_existencia = 1
													  THEN @flete * (deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) / @base
													  ELSE 0 END) / NULLIF(deta.det_cantidad, 0)
										 ELSE prod.pro_costo_unitario END
		FROM dbo.inv_documento_det deta
		INNER JOIN dbo.inv_producto prod WITH (UPDLOCK) ON prod.pro_id = deta.pro_id
		WHERE deta.enc_id = @EncId AND deta.det_cantidad > 0;
	END

	DECLARE @movimientos TABLE (
		[pro_id]	INT				NOT NULL,
		[bod_id]	INT				NOT NULL,
		[cantidad]	NUMERIC(12, 4)	NOT NULL,
		[costo]		NUMERIC(14, 2)	NOT NULL,
		PRIMARY KEY ([pro_id], [bod_id])
	);

	INSERT INTO @movimientos ([pro_id], [bod_id], [cantidad], [costo])
	SELECT deta2.pro_id, deta2.bod_id,
		   SUM(deta2.det_cantidad) * @naturaleza_signo * @reversar_signo,
		   SUM(deta2.det_cantidad * COALESCE(deta2.det_costo_unitario, prod2.pro_costo_unitario)) * @naturaleza_signo * @reversar_signo
	FROM dbo.inv_documento_det deta2
	INNER JOIN dbo.inv_producto prod2 ON prod2.pro_id = deta2.pro_id
	WHERE deta2.enc_id = @EncId
	  AND deta2.pro_id IS NOT NULL
	  AND prod2.pro_maneja_existencia = 1
	GROUP BY deta2.pro_id, deta2.bod_id;

	MERGE dbo.inv_producto_existencia_bodega AS destino
	USING @movimientos AS origen
		ON destino.pro_id = origen.pro_id AND destino.bod_id = origen.bod_id
	WHEN MATCHED THEN
		UPDATE SET existencia = destino.existencia + origen.cantidad,
				   UpdUsuario = @UsuId,
				   UpdFechaHora = SYSDATETIME()
	WHEN NOT MATCHED THEN
		INSERT (bod_id, pro_id, existencia, InsUsuario, InsFechaHora)
		VALUES (origen.bod_id, origen.pro_id, origen.cantidad, @UsuId, SYSDATETIME());

	-- Costo promedio ponderado: (costo acumulado + costo del movimiento) /
	-- (cantidad acumulada + cantidad del movimiento). Sin existencia el
	-- producto conserva su último costo promedio.
	;WITH totales AS (
		SELECT pro_id, SUM(cantidad) AS cantidad, SUM(costo) AS costo
		FROM @movimientos
		GROUP BY pro_id
	)
	UPDATE prod3
	   SET prod3.pro_total_cantidad = prod3.pro_total_cantidad + tota.cantidad,
		   prod3.pro_total_costo = CASE WHEN prod3.pro_total_cantidad + tota.cantidad > 0 THEN prod3.pro_total_costo + tota.costo ELSE 0 END,
		   prod3.pro_costo_unitario = CASE WHEN prod3.pro_total_cantidad + tota.cantidad > 0
									   THEN (prod3.pro_total_costo + tota.costo) / (prod3.pro_total_cantidad + tota.cantidad)
									   ELSE prod3.pro_costo_unitario END,
		   prod3.UpdUsuario = @UsuId,
		   prod3.UpdFechaHora = SYSDATETIME()
	FROM dbo.inv_producto prod3
	INNER JOIN totales tota ON tota.pro_id = prod3.pro_id;
END;
GO

------------------------------------------------------------
-- 3. Flete en otra factura (caso B): reparto y reversa
------------------------------------------------------------
-- Reparte el flete (sin IVA) de la factura @EncId entre los productos de la
-- compra vinculada, por valor; lo suma al costo de la existencia actual o,
-- si el producto ya no tiene existencia, lo deja para el costo de ventas.
CREATE OR ALTER PROCEDURE [dbo].[paCompraFleteAplicar]
	@EncId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @compra INT = (SELECT enc_id_compra_flete FROM dbo.inv_documento_enc WHERE enc_id = @EncId);
	IF @compra IS NULL
		THROW 55931, 'Elija una compra de mercadería vigente para cargarle el flete.', 1;

	DECLARE @flete NUMERIC(14, 2) = (SELECT ISNULL(SUM(det_sub_total - ISNULL(det_valor_descuento, 0)), 0)
									 FROM dbo.inv_documento_det WHERE enc_id = @EncId);

	DECLARE @reparto TABLE (pro_id INT, bod_id INT, base NUMERIC(16, 4), monto NUMERIC(14, 2), PRIMARY KEY (pro_id, bod_id));
	INSERT INTO @reparto (pro_id, bod_id, base, monto)
	SELECT deta.pro_id, deta.bod_id, SUM(deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)), 0
	FROM dbo.inv_documento_det deta
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id AND prod.pro_maneja_existencia = 1
	WHERE deta.enc_id = @compra AND deta.det_cantidad > 0 AND deta.det_es_flete = 0
	GROUP BY deta.pro_id, deta.bod_id;

	IF NOT EXISTS (SELECT 1 FROM @reparto)
		THROW 55933, 'La compra elegida no tiene productos de inventario a los que cargar el flete.', 1;

	-- Sin valor (mercadería sin costo) se reparte por cantidad.
	IF (SELECT SUM(base) FROM @reparto) <= 0
		UPDATE repa SET base = cant.cantidad
		FROM @reparto repa
		CROSS APPLY (SELECT SUM(deta.det_cantidad) AS cantidad FROM dbo.inv_documento_det deta
					 WHERE deta.enc_id = @compra AND deta.pro_id = repa.pro_id AND deta.bod_id = repa.bod_id) cant;

	DECLARE @total_base NUMERIC(16, 4) = (SELECT SUM(base) FROM @reparto);
	UPDATE @reparto SET monto = ROUND(@flete * base / @total_base, 2);
	-- El centavo del redondeo va a la línea de mayor valor.
	UPDATE TOP (1) repa SET monto = monto + (@flete - (SELECT SUM(monto) FROM @reparto))
	FROM @reparto repa
	WHERE repa.base = (SELECT MAX(base) FROM @reparto);

	INSERT INTO dbo.inv_compra_flete (enc_id, enc_id_compra, pro_id, bod_id, icf_monto, icf_capitalizado, InsUsuario, InsFechaHora)
	SELECT @EncId, @compra, repa.pro_id, repa.bod_id, repa.monto,
		   CASE WHEN prod.pro_total_cantidad > 0 THEN 1 ELSE 0 END, @UsuId, SYSDATETIME()
	FROM @reparto repa
	INNER JOIN dbo.inv_producto prod WITH (UPDLOCK) ON prod.pro_id = repa.pro_id
	WHERE repa.monto <> 0;

	;WITH sumas AS (
		SELECT pro_id, SUM(icf_monto) AS monto FROM dbo.inv_compra_flete
		WHERE enc_id = @EncId AND icf_capitalizado = 1 GROUP BY pro_id
	)
	UPDATE prod
	   SET prod.pro_total_costo = prod.pro_total_costo + suma.monto,
		   prod.pro_costo_unitario = (prod.pro_total_costo + suma.monto) / prod.pro_total_cantidad,
		   prod.UpdUsuario = @UsuId, prod.UpdFechaHora = SYSDATETIME()
	FROM dbo.inv_producto prod
	INNER JOIN sumas suma ON suma.pro_id = prod.pro_id
	WHERE prod.pro_total_cantidad > 0;
END;
GO

-- Al anular la factura del flete: se resta del costo lo que se le sumó, si el
-- producto todavía tiene existencia (si no, ya salió en el costo de ventas).
CREATE OR ALTER PROCEDURE [dbo].[paCompraFleteReversar]
	@EncId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	;WITH sumas AS (
		SELECT pro_id, SUM(icf_monto) AS monto FROM dbo.inv_compra_flete
		WHERE enc_id = @EncId AND icf_capitalizado = 1 GROUP BY pro_id
	)
	UPDATE prod
	   SET prod.pro_total_costo = prod.pro_total_costo - suma.monto,
		   prod.pro_costo_unitario = (prod.pro_total_costo - suma.monto) / prod.pro_total_cantidad,
		   prod.UpdUsuario = @UsuId, prod.UpdFechaHora = SYSDATETIME()
	FROM dbo.inv_producto prod WITH (UPDLOCK)
	INNER JOIN sumas suma ON suma.pro_id = prod.pro_id
	WHERE prod.pro_total_cantidad > 0;
END;
GO

------------------------------------------------------------
-- 4. Compra con flete
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCompraDocumentoCrear]
	@EncFechaDocto				DATE,
	@EncNumeroAutorizacion		VARCHAR(64) = NULL,
	@EncSerieDocto				VARCHAR(32) = NULL,
	@EncNumeroDocto				VARCHAR(32) = NULL,
	@PrvId							INT,
	@PrvEncNombresProveedor		VARCHAR(128) = NULL,
	@PrvEncApellidosProveedor	VARCHAR(128) = NULL,
	@PrvNit						VARCHAR(16) = NULL,
	@TdoId							INT,
	@EncFechaPrimerPago			DATE = NULL,
	@EncMontoEnganche				NUMERIC(12, 2) = 0,
	@EncNumeroCuotas				INT = 1,
	@EncValorDescuento			NUMERIC(13, 2) = 0,
	@MonId							INT = NULL,
	@UsuId							INT = NULL,
	@Detalle						dbo.compra_det_type READONLY,
	@EncId							INT OUTPUT,
	-- Líneas que son activo fijo (det_item → categoría y centro de costo).
	@Activos						dbo.compra_activo_type READONLY,
	-- Flete sin IVA incluido en esta factura: se agrega como línea de servicio
	-- y se reparte al costo de los productos (caso A).
	@EncFlete						NUMERIC(12, 2) = 0,
	-- Esta factura es el flete de otra compra (caso B): todo su detalle es
	-- el servicio de flete y se reparte al costo de los productos de esa compra.
	@EncIdCompraFlete				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 51411, 'La compra debe tener al menos una línea de detalle.', 1;

	IF @MonId IS NULL
		SET @MonId = dbo.fnMonedaLocal();

	IF EXISTS (SELECT 1 FROM @Activos acti LEFT JOIN @Detalle deta ON deta.det_item = acti.det_item WHERE deta.det_item IS NULL)
		THROW 55221, 'Una línea marcada como activo fijo no existe en el detalle de la compra.', 1;
	IF EXISTS (SELECT 1 FROM @Activos acti LEFT JOIN dbo.afi_categoria cate ON cate.afc_id = acti.afc_id AND cate.afc_estado = 'A' WHERE cate.afc_id IS NULL)
		THROW 55222, 'Elija una categoría de activo fijo activa para cada línea de activo.', 1;
	IF EXISTS (SELECT 1 FROM @Activos acti INNER JOIN @Detalle deta ON deta.det_item = acti.det_item WHERE deta.pro_id IS NOT NULL)
		THROW 55223, 'Una línea de activo fijo no lleva producto de inventario: escriba la descripción del bien.', 1;

	SET @EncFlete = ISNULL(@EncFlete, 0);
	IF @EncFlete < 0
		THROW 55930, 'El flete no puede ser negativo.', 1;

	IF @EncIdCompraFlete IS NOT NULL
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM dbo.inv_documento_enc enca
					   INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
					   WHERE enca.enc_id = @EncIdCompraFlete AND enca.enc_estado = 'G' AND tipo.tdo_naturaleza = '+'
						 AND tipo.afecta_costo = 'S' AND tipo.tdo_es_nota = 0 AND enca.enc_id_compra_flete IS NULL)
			THROW 55931, 'Elija una compra de mercadería vigente para cargarle el flete.', 1;
		IF EXISTS (SELECT 1 FROM @Detalle WHERE pro_id IS NOT NULL) OR EXISTS (SELECT 1 FROM @Activos)
			THROW 55932, 'La factura del flete solo lleva el servicio de flete, sin productos ni activos fijos.', 1;
		IF @EncFlete > 0
			THROW 55934, 'Una factura de flete de otra compra no lleva además flete propio.', 1;
	END

	-- Detalle a grabar: el recibido más, si viene, la línea del flete.
	DECLARE @lineas dbo.compra_det_type;
	INSERT INTO @lineas SELECT * FROM @Detalle;
	DECLARE @item_flete INT = NULL;
	IF @EncFlete > 0
	BEGIN
		SET @item_flete = (SELECT MAX(det_item) FROM @Detalle) + 1;
		INSERT INTO @lineas (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario,
							 det_valor_descuento, det_sub_total, det_porc_iva, bod_id, pro_id)
		SELECT TOP (1) @item_flete, 'S', 1, 'Flete', @EncFlete, 0, @EncFlete,
			   COALESCE(det_porc_iva, (SELECT TOP (1) comp.cia_porc_iva FROM dbo.gen_compania comp ORDER BY comp.cia_id), 12),
			   bod_id, NULL
		FROM @Detalle ORDER BY det_item;
	END

	-- El total es el de la factura del proveedor: costo unitario con IVA
	-- redondeado a centavos × cantidad, menos el descuento con IVA (igual que
	-- en paVentaFacturaCrear desde el script 52). El asiento sigue
	-- cuadrado: inventario o gasto = total - IVA.
	DECLARE @monto_total NUMERIC(12, 2) = (
		SELECT SUM(ROUND(ROUND(det_precio_unitario * (1 + ISNULL(det_porc_iva, 0) / 100.0), 2) * det_cantidad, 2)
				 - ROUND(det_valor_descuento * (1 + ISNULL(det_porc_iva, 0) / 100.0), 2))
		FROM @lineas
	);

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.inv_documento_enc
			(enc_fecha_docto, enc_numero_autorizacion, enc_serie_docto, enc_numero_docto,
			 prv_id, prv_enc_nombres_proveedor, prv_enc_apellidos_proveedor, prv_nit, tdo_id,
			 enc_fecha_primer_pago, enc_monto_enganche, enc_numero_cuotas, enc_monto_total,
			 enc_valor_descuento, mon_id, usu_id_creacion, enc_id_compra_flete,
			 InsUsuario, InsFechaHora)
		VALUES
			(@EncFechaDocto, @EncNumeroAutorizacion, @EncSerieDocto, @EncNumeroDocto,
			 @PrvId, @PrvEncNombresProveedor, @PrvEncApellidosProveedor, @PrvNit, @TdoId,
			 @EncFechaPrimerPago, @EncMontoEnganche, @EncNumeroCuotas, @monto_total,
			 @EncValorDescuento, @MonId, @UsuId, @EncIdCompraFlete,
			 @UsuId, SYSDATETIME());

		SET @EncId = SCOPE_IDENTITY();

		INSERT INTO dbo.inv_documento_det
			(enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			 det_precio_unitario, det_valor_descuento, det_sub_total, det_porc_iva, bod_id, pro_id, det_es_flete,
			 InsUsuario, InsFechaHora)
		SELECT
			@EncId, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			det_precio_unitario, det_valor_descuento, det_sub_total, det_porc_iva, bod_id, pro_id,
			CASE WHEN det_item = @item_flete OR @EncIdCompraFlete IS NOT NULL THEN 1 ELSE 0 END,
			@UsuId, SYSDATETIME()
		FROM @lineas;

		UPDATE deta SET afc_id = acti.afc_id
		FROM dbo.inv_documento_det deta INNER JOIN @Activos acti ON acti.det_item = deta.det_item
		WHERE deta.enc_id = @EncId;

		EXEC dbo.paProveedorPlanPagosGenerar @EncId = @EncId, @UsuId = @UsuId;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'G',
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId;

		EXEC dbo.paInventarioExistenciaDocumentoAjustar @EncId = @EncId, @UsuId = @UsuId;

		IF @EncIdCompraFlete IS NOT NULL
			EXEC dbo.paCompraFleteAplicar @EncId = @EncId, @UsuId = @UsuId;

		DECLARE @asi_id INT;
		EXEC dbo.paContabilidadAsientoDocumentoGenerar @EncId = @EncId, @UsuId = @UsuId, @AsiId = @asi_id OUTPUT;

		IF EXISTS (SELECT 1 FROM @Activos)
			EXEC dbo.paActivoFijoCrearDesdeCompra @EncId = @EncId, @Departamentos = @Activos, @UsuId = @UsuId;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 5. Póliza: la factura del flete (caso B) va a inventario y costo de ventas
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paContabilidadAsientoDocumentoGenerar]
	@EncId	INT,
	@UsuId	INT = NULL,
	@AsiId	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @tdo_naturaleza CHAR(1), @afecta_costo CHAR(1), @fecha DATE, @monto_total NUMERIC(12, 2), @origen VARCHAR(20);

	SELECT @tdo_naturaleza = tipo.tdo_naturaleza, @afecta_costo = tipo.afecta_costo,
		   @fecha = enca.enc_fecha_docto, @monto_total = enca.enc_monto_total,
		   @origen = CASE WHEN tipo.tdo_naturaleza = '+' THEN 'COMPRA' ELSE 'VENTA' END
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @EncId;

	IF @fecha IS NULL
		THROW 51303, 'El documento indicado no existe.', 1;

	DECLARE @cuentas TABLE (ccp_codigo VARCHAR(40) PRIMARY KEY, cta_id INT);
	INSERT INTO @cuentas SELECT ccp_codigo, cta_id FROM dbo.cont_cuenta_parametro
	WHERE ccp_codigo IN ('VENTA_CAJA','VENTA_CLIENTES','VENTA_INGRESO','VENTA_IVA_DEBITO','VENTA_COSTO','INVENTARIO',
						 'COMPRA_GASTO','COMPRA_IVA_CREDITO','COMPRA_PROVEEDORES');

	DECLARE @faltante VARCHAR(40) = (SELECT TOP 1 conc.codigo FROM (VALUES ('VENTA_CAJA'),('VENTA_CLIENTES'),('VENTA_INGRESO'),('VENTA_IVA_DEBITO'),
		('VENTA_COSTO'),('INVENTARIO'),('COMPRA_GASTO'),('COMPRA_IVA_CREDITO'),('COMPRA_PROVEEDORES')) conc(codigo)
		LEFT JOIN @cuentas cuen ON cuen.ccp_codigo = conc.codigo WHERE cuen.cta_id IS NULL);
	IF @faltante IS NOT NULL
	BEGIN
		DECLARE @msg_faltante NVARCHAR(200) = CONCAT(N'El concepto contable ', @faltante, N' no tiene cuenta asignada; configúrelo en cont_cuenta_parametro.');
		THROW 51304, @msg_faltante, 1;
	END

	DECLARE @cta_caja INT, @cta_clientes INT, @cta_ingreso INT, @cta_iva_debito INT, @cta_costo INT, @cta_inventario INT,
			@cta_gasto INT, @cta_iva_credito INT, @cta_proveedores INT;
	SELECT @cta_caja = MAX(CASE ccp_codigo WHEN 'VENTA_CAJA' THEN cta_id END),
		   @cta_clientes = MAX(CASE ccp_codigo WHEN 'VENTA_CLIENTES' THEN cta_id END),
		   @cta_ingreso = MAX(CASE ccp_codigo WHEN 'VENTA_INGRESO' THEN cta_id END),
		   @cta_iva_debito = MAX(CASE ccp_codigo WHEN 'VENTA_IVA_DEBITO' THEN cta_id END),
		   @cta_costo = MAX(CASE ccp_codigo WHEN 'VENTA_COSTO' THEN cta_id END),
		   @cta_inventario = MAX(CASE ccp_codigo WHEN 'INVENTARIO' THEN cta_id END),
		   @cta_gasto = MAX(CASE ccp_codigo WHEN 'COMPRA_GASTO' THEN cta_id END),
		   @cta_iva_credito = MAX(CASE ccp_codigo WHEN 'COMPRA_IVA_CREDITO' THEN cta_id END),
		   @cta_proveedores = MAX(CASE ccp_codigo WHEN 'COMPRA_PROVEEDORES' THEN cta_id END)
	FROM @cuentas;

	DECLARE @iva NUMERIC(14, 2) =
		(SELECT ISNULL(SUM((det_sub_total - det_valor_descuento) * ISNULL(det_porc_iva, 0) / 100.0), 0) FROM dbo.inv_documento_det WHERE enc_id = @EncId);

	DECLARE @costo_venta NUMERIC(14, 2);
	SELECT @costo_venta = ISNULL(SUM(deta2.det_cantidad * COALESCE(deta2.det_costo_unitario, prod.pro_costo_unitario)), 0)
	FROM dbo.inv_documento_det deta2
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta2.pro_id
	WHERE deta2.enc_id = @EncId AND prod.pro_maneja_existencia = 1;

	DECLARE @pdo_id INT;
	EXEC dbo.paContabilidadPeriodoObtenerOCrear @Fecha = @fecha, @UsuId = @UsuId, @PdoId = @pdo_id OUTPUT;

	DECLARE @detalle dbo.cont_asiento_det_type;
	DECLARE @ref VARCHAR(10) = CAST(@EncId AS VARCHAR(10));

	IF @tdo_naturaleza = '-' -- venta
	BEGIN
		DECLARE @cobrado NUMERIC(12, 2) = (SELECT ISNULL(SUM(ppd_valor_aplicado), 0) FROM dbo.pos_pago_det WHERE enc_id = @EncId);
		IF @cobrado > @monto_total SET @cobrado = @monto_total;

		IF @cobrado > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_caja, @cobrado, 0, 'Cobro al facturar - documento ' + @ref);
		IF @monto_total - @cobrado > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_clientes, @monto_total - @cobrado, 0, 'Cuentas por cobrar - documento ' + @ref);

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_ingreso, 0, @monto_total - @iva, 'Venta - documento ' + @ref);

		IF @iva > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_iva_debito, 0, @iva, 'IVA débito fiscal - documento ' + @ref);

		IF @costo_venta > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			VALUES (@cta_costo, @costo_venta, 0, 'Costo de venta - documento ' + @ref),
				   (@cta_inventario, 0, @costo_venta, 'Salida de inventario - documento ' + @ref);
	END
	ELSE IF EXISTS (SELECT 1 FROM dbo.inv_compra_flete WHERE enc_id = @EncId) -- flete de otra compra
	BEGIN
		-- Lo que se sumó al costo de la existencia va a inventario; la parte de
		-- productos ya vendidos (y el redondeo del IVA), al costo de ventas.
		DECLARE @flete_inventario NUMERIC(14, 2) = (SELECT ISNULL(SUM(icf_monto), 0) FROM dbo.inv_compra_flete WHERE enc_id = @EncId AND icf_capitalizado = 1);
		IF @flete_inventario <> 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_inventario, @flete_inventario, 0, 'Flete al costo del inventario - documento ' + @ref);
		IF @monto_total - @iva - @flete_inventario <> 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_costo, @monto_total - @iva - @flete_inventario, 0, 'Flete de mercadería ya vendida - documento ' + @ref);
		IF @iva > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_iva_credito, @iva, 0, 'IVA crédito fiscal - documento ' + @ref);
		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_proveedores, 0, @monto_total, 'Cuentas por pagar - documento ' + @ref);
	END
	ELSE -- compra
	BEGIN
		-- Las líneas de activo fijo van a la cuenta de su categoría; el resto
		-- (que absorbe el redondeo, y el flete de la misma factura) a
		-- inventario o gasto como antes.
		DECLARE @activos TABLE (cta_id INT PRIMARY KEY, neto NUMERIC(14, 2));
		INSERT INTO @activos (cta_id, neto)
		SELECT cate.cta_id_activo, SUM(deta.det_sub_total - deta.det_valor_descuento)
		FROM dbo.inv_documento_det deta
		INNER JOIN dbo.afi_categoria cate ON cate.afc_id = deta.afc_id
		WHERE deta.enc_id = @EncId
		GROUP BY cate.cta_id_activo;
		DECLARE @neto_activos NUMERIC(14, 2) = ISNULL((SELECT SUM(neto) FROM @activos), 0);

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, neto, 0, 'Compra de activo fijo - documento ' + @ref FROM @activos WHERE neto > 0;

		IF @monto_total - @iva - @neto_activos <> 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			VALUES (CASE WHEN @afecta_costo = 'S' THEN @cta_inventario ELSE @cta_gasto END, @monto_total - @iva - @neto_activos, 0, 'Compra - documento ' + @ref);

		IF @iva > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_iva_credito, @iva, 0, 'IVA crédito fiscal - documento ' + @ref);

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_proveedores, 0, @monto_total, 'Cuentas por pagar - documento ' + @ref);
	END

	DECLARE @asi_descripcion VARCHAR(256) = 'Generado automáticamente desde documento ' + @ref;

	EXEC dbo.paContabilidadAsientoInsertar
		@AsiFecha = @fecha, @AsiDescripcion = @asi_descripcion, @AsiOrigen = @origen,
		@EncId = @EncId, @PdoId = @pdo_id, @UsuId = @UsuId, @Detalle = @detalle, @AsiId = @AsiId OUTPUT;
END;
GO

------------------------------------------------------------
-- 6. Anulación
------------------------------------------------------------
-- Igual que en 66; además, una compra con flete vigente en otra factura no
-- se anula, y al anular la factura del flete se reversa lo que sumó al costo.
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
	IF EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_id_compra_flete = @EncId AND enc_estado = 'G')
		THROW 55935, 'La compra tiene su flete registrado en otra factura; anule primero esa factura de flete.', 1;
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
	IF EXISTS (SELECT 1 FROM dbo.bco_lote_transferencia_cuota blcu
			   INNER JOIN dbo.bco_lote_transferencia_det line ON line.bld_id = blcu.bld_id
			   INNER JOIN dbo.bco_lote_transferencia lote ON lote.blt_id = line.blt_id AND lote.blt_estado = 'A'
			   WHERE blcu.enc_id = @EncId)
		THROW 54838, 'La compra se pagó por transferencia; anule primero ese lote en Cuentas por pagar › Pagos programados.', 1;
	IF EXISTS (SELECT 1 FROM dbo.cxp_contrasena_det deta
			   INNER JOIN dbo.cxp_contrasena_enc cont ON cont.cpa_id = deta.cpa_id AND cont.cpa_estado = 'E'
			   WHERE deta.enc_id = @EncId)
		THROW 54839, 'La compra está en una contraseña de pago pendiente; anule primero la contraseña.', 1;

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

		IF EXISTS (SELECT 1 FROM dbo.inv_compra_flete WHERE enc_id = @EncId)
			EXEC dbo.paCompraFleteReversar @EncId = @EncId, @UsuId = @UsuId;

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
-- 7. Compras a las que se les puede cargar un flete (pantalla de Compras)
------------------------------------------------------------
-- Compras de mercadería vigentes de los últimos @Dias días, con el flete que
-- ya tienen (en la misma factura y en otras).
CREATE OR ALTER PROCEDURE [dbo].[paCompraFleteCandidatasConsultar]
	@Dias	INT = 120
AS
BEGIN
	SET NOCOUNT ON;
	SELECT enca.enc_id AS EncId, enca.enc_fecha_docto AS Fecha,
		   CONCAT(enca.enc_serie_docto, IIF(enca.enc_serie_docto IS NULL, '', '-'), enca.enc_numero_docto) AS Documento,
		   prov.prv_nombre_comercial AS Proveedor, enca.enc_monto_total AS Total,
		   (SELECT TOP (1) deta.bod_id FROM dbo.inv_documento_det deta WHERE deta.enc_id = enca.enc_id ORDER BY deta.det_item) AS BodId,
		   ISNULL((SELECT SUM(deta.det_sub_total) FROM dbo.inv_documento_det deta WHERE deta.enc_id = enca.enc_id AND deta.det_es_flete = 1), 0)
		   + ISNULL((SELECT SUM(flet.icf_monto) FROM dbo.inv_compra_flete flet
					 INNER JOIN dbo.inv_documento_enc fact ON fact.enc_id = flet.enc_id AND fact.enc_estado = 'G'
					 WHERE flet.enc_id_compra = enca.enc_id), 0) AS FleteSinIva
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	LEFT JOIN dbo.inv_proveedor prov ON prov.prv_id = enca.prv_id
	WHERE enca.enc_estado = 'G' AND tipo.tdo_naturaleza = '+' AND tipo.afecta_costo = 'S' AND tipo.tdo_es_nota = 0
	  AND tipo.tdo_es_interno = 0 AND enca.enc_id_compra_flete IS NULL
	  AND enca.enc_fecha_docto >= DATEADD(DAY, -@Dias, CAST(GETDATE() AS DATE))
	  AND EXISTS (SELECT 1 FROM dbo.inv_documento_det deta
				  INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id AND prod.pro_maneja_existencia = 1
				  WHERE deta.enc_id = enca.enc_id)
	ORDER BY enca.enc_fecha_docto DESC, enca.enc_id DESC;
END;
GO

-- El flete de una compra: el de su propia factura y el de otras facturas.
CREATE OR ALTER PROCEDURE [dbo].[paCompraFleteConsultar]
	@EncId	INT
AS
BEGIN
	SET NOCOUNT ON;
	-- 1. Las facturas de flete vinculadas a esta compra, o la compra a la que
	--    se cargó este flete.
	SELECT fact.enc_id AS EncId, fact.enc_fecha_docto AS Fecha,
		   CONCAT(fact.enc_serie_docto, IIF(fact.enc_serie_docto IS NULL, '', '-'), fact.enc_numero_docto) AS Documento,
		   prov.prv_nombre_comercial AS Proveedor, fact.enc_monto_total AS Total, fact.enc_estado AS Estado,
		   CAST(IIF(fact.enc_id_compra_flete = @EncId, 1, 0) AS BIT) AS EsFleteDeEsta
	FROM dbo.inv_documento_enc fact
	LEFT JOIN dbo.inv_proveedor prov ON prov.prv_id = fact.prv_id
	WHERE fact.enc_id_compra_flete = @EncId
	   OR fact.enc_id = (SELECT enc_id_compra_flete FROM dbo.inv_documento_enc WHERE enc_id = @EncId)
	ORDER BY fact.enc_fecha_docto, fact.enc_id;

	-- 2. Por línea de la compra: costo sin flete, flete de la misma factura y
	--    de otras facturas vigentes.
	SELECT deta.det_id AS DetId,
		   (deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) AS NetoSinFlete,
		   CAST(ISNULL(deta.det_costo_unitario, 0) * deta.det_cantidad - (deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) AS NUMERIC(14, 2)) AS FleteMismaFactura,
		   CAST(ISNULL(otro.monto * (deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) / NULLIF(base.neto, 0), 0) AS NUMERIC(14, 2)) AS FleteOtrasFacturas
	FROM dbo.inv_documento_det deta
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id AND prod.pro_maneja_existencia = 1
	OUTER APPLY (SELECT SUM(flet.icf_monto) AS monto
				 FROM dbo.inv_compra_flete flet
				 INNER JOIN dbo.inv_documento_enc fact ON fact.enc_id = flet.enc_id AND fact.enc_estado = 'G'
				 WHERE flet.enc_id_compra = deta.enc_id AND flet.pro_id = deta.pro_id AND flet.bod_id = deta.bod_id) otro
	OUTER APPLY (SELECT SUM(otra.det_sub_total - ISNULL(otra.det_valor_descuento, 0)) AS neto
				 FROM dbo.inv_documento_det otra
				 WHERE otra.enc_id = deta.enc_id AND otra.pro_id = deta.pro_id AND otra.bod_id = deta.bod_id
				   AND otra.det_es_flete = 0 AND otra.det_cantidad > 0) base
	WHERE deta.enc_id = @EncId AND deta.det_es_flete = 0 AND deta.det_cantidad > 0;
END;
GO

------------------------------------------------------------
-- 8. Kárdex con el flete de otras facturas
------------------------------------------------------------
-- Igual que en 69; además, el flete de otra factura aparece como una línea
-- sin cantidad que suma su valor al saldo (y lo resta si se anula).
CREATE OR ALTER PROCEDURE [dbo].[paInventarioKardexConsultar]
	@ProId	INT,
	@BodId	INT = NULL,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_id = @ProId)
		THROW 55601, 'El producto no existe.', 1;
	IF @Hasta < @Desde
		THROW 55602, 'La fecha final no puede ser anterior a la inicial.', 1;

	CREATE TABLE #mov (
		orden			INT IDENTITY(1,1) PRIMARY KEY,
		momento			DATETIME2(0),
		fecha			DATE,
		enc_id			INT,
		det_id			INT,
		bod_id			INT,
		tipo			VARCHAR(10),
		tipo_nombre		VARCHAR(100),
		documento		VARCHAR(60),
		tercero			VARCHAR(250),
		es_reversa		BIT,
		cantidad		NUMERIC(14, 4),		-- + entra, - sale
		costo_unitario	NUMERIC(14, 4),
		costo_total		NUMERIC(16, 2),		-- con el signo del movimiento
		saldo_cantidad	NUMERIC(14, 4),
		saldo_valor		NUMERIC(16, 2),
		promedio		NUMERIC(14, 4),
		saldo_bodega	NUMERIC(14, 4)
	);

	;WITH lineas AS (
		SELECT enca.enc_id, deta.det_id, deta.bod_id, tipo.tdo_codigo, tipo.tdo_descripcion, enca.enc_estado,
			   ISNULL(enca.enc_numero_unico, CONCAT(enca.enc_serie_docto, IIF(enca.enc_serie_docto IS NULL, '', '-'), enca.enc_numero_docto)) AS documento,
			   COALESCE(NULLIF(LTRIM(CONCAT(enca.enc_nombres_cliente, ' ', enca.enc_apellidos_cliente)), ''), prov.prv_nombre_comercial, enca.enc_motivo) AS tercero,
			   enca.enc_fecha_docto, enca.InsFechaHora, enca.UpdFechaHora,
			   IIF(tipo.tdo_naturaleza = '+', 1, -1) * deta.det_cantidad AS cantidad,
			   COALESCE(deta.det_costo_unitario, 0) AS costo_unitario
		FROM dbo.inv_documento_det deta
		INNER JOIN dbo.inv_documento_enc enca ON enca.enc_id = deta.enc_id
		INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
		INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id AND prod.pro_maneja_existencia = 1
		LEFT JOIN dbo.inv_proveedor prov ON prov.prv_id = enca.prv_id
		WHERE deta.pro_id = @ProId AND deta.det_cantidad > 0 AND deta.bod_id IS NOT NULL
		  -- Las notas solo mueven inventario en las líneas de devolución.
		  AND (tipo.tdo_codigo NOT IN ('NCC', 'NCP', 'NDC', 'NDP') OR deta.det_id_origen IS NOT NULL)
	), fletes AS (
		SELECT fact.enc_id, flet.bod_id, tipo.tdo_codigo, fact.enc_estado,
			   CONCAT(fact.enc_serie_docto, IIF(fact.enc_serie_docto IS NULL, '', '-'), fact.enc_numero_docto) AS documento,
			   prov.prv_nombre_comercial AS tercero, fact.enc_fecha_docto, flet.InsFechaHora, fact.UpdFechaHora,
			   IIF(flet.icf_capitalizado = 1, flet.icf_monto, 0) AS monto
		FROM dbo.inv_compra_flete flet
		INNER JOIN dbo.inv_documento_enc fact ON fact.enc_id = flet.enc_id
		INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = fact.tdo_id
		LEFT JOIN dbo.inv_proveedor prov ON prov.prv_id = fact.prv_id
		WHERE flet.pro_id = @ProId
	), eventos AS (
		SELECT InsFechaHora AS momento, enc_fecha_docto AS fecha, enc_id, det_id, bod_id, tdo_codigo, tdo_descripcion, documento, tercero,
			   CAST(0 AS BIT) AS es_reversa, cantidad, costo_unitario, CAST(cantidad * costo_unitario AS NUMERIC(16, 2)) AS costo_total
		FROM lineas
		UNION ALL
		SELECT UpdFechaHora, CAST(UpdFechaHora AS DATE), enc_id, det_id, bod_id, tdo_codigo, tdo_descripcion, documento, tercero,
			   CAST(1 AS BIT), -cantidad, costo_unitario, CAST(-cantidad * costo_unitario AS NUMERIC(16, 2))
		FROM lineas WHERE enc_estado = 'A'
		UNION ALL
		SELECT InsFechaHora, enc_fecha_docto, enc_id, NULL, bod_id, tdo_codigo, 'Flete de la compra', documento, tercero,
			   CAST(0 AS BIT), 0, 0, monto
		FROM fletes
		UNION ALL
		SELECT UpdFechaHora, CAST(UpdFechaHora AS DATE), enc_id, NULL, bod_id, tdo_codigo, 'Flete de la compra', documento, tercero,
			   CAST(1 AS BIT), 0, 0, -monto
		FROM fletes WHERE enc_estado = 'A'
	)
	INSERT INTO #mov (momento, fecha, enc_id, det_id, bod_id, tipo, tipo_nombre, documento, tercero, es_reversa, cantidad, costo_unitario, costo_total)
	SELECT momento, fecha, enc_id, det_id, bod_id, tdo_codigo, tdo_descripcion, documento, tercero, es_reversa, cantidad, costo_unitario, costo_total
	FROM eventos
	ORDER BY momento, es_reversa, enc_id, det_id;

	-- Saldos, en el orden del sistema.
	DECLARE @orden INT = 1, @maximo INT = (SELECT MAX(orden) FROM #mov), @cantidad NUMERIC(14, 4) = 0, @valor NUMERIC(16, 2) = 0,
			@promedio NUMERIC(14, 4) = 0, @mov_cantidad NUMERIC(14, 4), @mov_costo NUMERIC(16, 2), @bod INT;
	DECLARE @bodegas TABLE (bod_id INT PRIMARY KEY, saldo NUMERIC(14, 4));
	WHILE @orden <= @maximo
	BEGIN
		SELECT @mov_cantidad = cantidad, @mov_costo = costo_total, @bod = bod_id FROM #mov WHERE orden = @orden;
		IF @cantidad + @mov_cantidad > 0
		BEGIN
			SET @valor = @valor + @mov_costo;
			SET @promedio = @valor / (@cantidad + @mov_cantidad);
		END
		ELSE SET @valor = 0;
		SET @cantidad = @cantidad + @mov_cantidad;
		IF NOT EXISTS (SELECT 1 FROM @bodegas WHERE bod_id = @bod) INSERT INTO @bodegas VALUES (@bod, 0);
		UPDATE @bodegas SET saldo = saldo + @mov_cantidad WHERE bod_id = @bod;
		UPDATE #mov SET saldo_cantidad = @cantidad, saldo_valor = @valor, promedio = @promedio,
						saldo_bodega = (SELECT saldo FROM @bodegas WHERE bod_id = @bod)
		WHERE orden = @orden;
		SET @orden += 1;
	END

	SELECT prod.pro_id AS ProId, prod.pro_codigo AS Codigo, prod.pro_descripcion AS Descripcion, prod.pro_maneja_existencia AS ManejaExistencia
	FROM dbo.inv_producto prod WHERE prod.pro_id = @ProId;

	SELECT movi.orden AS Orden, movi.momento AS Registrado, movi.fecha AS Fecha, movi.enc_id AS EncId, movi.bod_id AS BodId,
		   bode.bod_descripcion AS Bodega, movi.tipo AS Tipo, movi.tipo_nombre AS TipoNombre, movi.documento AS Documento,
		   movi.tercero AS Tercero, movi.es_reversa AS EsReversa,
		   IIF(movi.cantidad > 0, movi.cantidad, 0) AS Entrada, IIF(movi.cantidad < 0, -movi.cantidad, 0) AS Salida,
		   movi.costo_unitario AS CostoUnitario, movi.costo_total AS CostoTotal,
		   movi.saldo_cantidad AS SaldoCantidad, movi.saldo_valor AS SaldoValor, movi.promedio AS CostoPromedio,
		   movi.saldo_bodega AS SaldoBodega
	FROM #mov movi
	LEFT JOIN dbo.inv_bodega bode ON bode.bod_id = movi.bod_id
	WHERE (@BodId IS NULL OR movi.bod_id = @BodId)
	  AND (@Desde IS NULL OR movi.fecha >= @Desde)
	  AND (@Hasta IS NULL OR movi.fecha <= @Hasta)
	ORDER BY movi.orden;

	SELECT
		-- Saldo al inicio del período (último movimiento antes de @Desde).
		ISNULL((SELECT TOP 1 saldo_cantidad FROM #mov WHERE @Desde IS NOT NULL AND fecha < @Desde ORDER BY orden DESC), 0) AS InicialCantidad,
		ISNULL((SELECT TOP 1 saldo_valor FROM #mov WHERE @Desde IS NOT NULL AND fecha < @Desde ORDER BY orden DESC), 0) AS InicialValor,
		ISNULL((SELECT TOP 1 promedio FROM #mov WHERE @Desde IS NOT NULL AND fecha < @Desde ORDER BY orden DESC), 0) AS InicialPromedio,
		ISNULL((SELECT SUM(cantidad) FROM #mov WHERE @BodId IS NOT NULL AND bod_id = @BodId AND @Desde IS NOT NULL AND fecha < @Desde), 0) AS InicialBodega,
		-- Saldo final calculado con todos los movimientos.
		@cantidad AS CalculadoCantidad, @valor AS CalculadoValor, @promedio AS CalculadoPromedio,
		-- Lo guardado.
		prod.pro_total_cantidad AS GuardadoCantidad, prod.pro_total_costo AS GuardadoValor, prod.pro_costo_unitario AS GuardadoPromedio,
		ISNULL((SELECT SUM(exis.existencia) FROM dbo.inv_producto_existencia_bodega exis WHERE exis.pro_id = @ProId), 0) AS ExistenciaBodegas,
		ISNULL((SELECT SUM(exis.existencia) FROM dbo.inv_producto_existencia_bodega exis WHERE exis.pro_id = @ProId AND exis.bod_id = @BodId), 0) AS ExistenciaBodega,
		ISNULL((SELECT SUM(cantidad) FROM #mov WHERE bod_id = @BodId), 0) AS CalculadoBodega
	FROM dbo.inv_producto prod WHERE prod.pro_id = @ProId;
END;
GO

------------------------------------------------------------
-- 9. Órdenes de compra con flete
------------------------------------------------------------
-- @OcpId NULL crea la orden en borrador; con valor, reemplaza la orden (solo en borrador).
-- @FleteTipo: N sin flete, I incluido en la factura del proveedor (suma al
-- total), S facturado aparte (estimado). @Flete con IVA.
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraGuardar]
	@OcpId			INT OUTPUT,
	@Fecha			DATE,
	@FechaEntrega	DATE = NULL,
	@PrvId			INT,
	@BodId			INT,
	@MonId			INT = NULL,
	@Condiciones	VARCHAR(256) = NULL,
	@Observaciones	VARCHAR(500) = NULL,
	@UsuId			INT = NULL,
	@Detalle		dbo.orden_compra_det_type READONLY,
	@Numero			VARCHAR(16) OUTPUT,
	@FleteTipo		CHAR(1) = 'N',
	@Flete			NUMERIC(14, 2) = 0
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @Numero = NULL;

	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 54501, 'La orden de compra debe tener al menos un producto.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE cantidad <= 0 OR costo_unitario < 0)
		THROW 54502, 'La cantidad debe ser mayor a cero y el costo no puede ser negativo.', 1;
	IF EXISTS (SELECT pro_id FROM @Detalle GROUP BY pro_id HAVING COUNT(*) > 1)
		THROW 54503, 'Un producto aparece en más de una línea: sume las cantidades en una sola.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle deta LEFT JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
			   WHERE prod.pro_id IS NULL OR prod.pro_estado <> 'A' OR prod.pro_tipo_item <> 'B')
		THROW 54504, 'Solo se ordenan productos (bienes) activos.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_proveedor WHERE prv_id = @PrvId AND prv_estado = 'A')
		THROW 54505, 'Elija un proveedor activo.', 1;

	SET @FleteTipo = ISNULL(NULLIF(@FleteTipo, ''), 'N');
	SET @Flete = CASE WHEN @FleteTipo = 'N' THEN 0 ELSE ISNULL(@Flete, 0) END;
	IF @FleteTipo NOT IN ('N', 'I', 'S') OR @Flete < 0
		THROW 55936, 'Indique si el flete va incluido en la factura del proveedor o se factura aparte, y su monto (no negativo).', 1;

	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));
	IF @FechaEntrega IS NOT NULL AND @FechaEntrega < @Fecha
		THROW 54506, 'La fecha de entrega no puede ser anterior a la fecha de la orden.', 1;

	DECLARE @suc_id INT, @iva NUMERIC(8, 2);
	SELECT @suc_id = bode.suc_id, @iva = comp.cia_porc_iva
	FROM dbo.inv_bodega bode
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	WHERE bode.bod_id = @BodId AND bode.bod_estado = 'A';
	IF @suc_id IS NULL
		THROW 54507, 'Elija una bodega activa para recibir la orden.', 1;

	SET @MonId = ISNULL(@MonId, dbo.fnMonedaLocal());
	-- El flete incluido en la factura del proveedor suma al total de la orden.
	DECLARE @total NUMERIC(14, 2) = (SELECT SUM(ROUND(cantidad * costo_unitario, 2)) FROM @Detalle)
								  + CASE WHEN @FleteTipo = 'I' THEN @Flete ELSE 0 END;

	BEGIN TRANSACTION;
	IF @OcpId IS NULL
	BEGIN
		DECLARE @siguiente INT = ISNULL((SELECT MAX(CAST(SUBSTRING(ocp_numero, 4, 12) AS INT)) FROM dbo.cmp_orden_compra_enc WITH (UPDLOCK, HOLDLOCK)), 0) + 1;
		INSERT INTO dbo.cmp_orden_compra_enc
			(ocp_numero, ocp_fecha, ocp_fecha_entrega, prv_id, suc_id, bod_id, mon_id, ocp_porc_iva, ocp_total,
			 ocp_condiciones, ocp_observaciones, ocp_estado, ocp_flete_tipo, ocp_flete, usu_id, InsUsuario, InsFechaHora)
		VALUES
			(CONCAT('OC-', RIGHT(CONCAT('000000', @siguiente), 6)), @Fecha, @FechaEntrega, @PrvId, @suc_id, @BodId, @MonId, @iva, @total,
			 NULLIF(LTRIM(RTRIM(@Condiciones)), ''), NULLIF(LTRIM(RTRIM(@Observaciones)), ''), 'B', @FleteTipo, @Flete, @UsuId, @UsuId, SYSDATETIME());
		SET @OcpId = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.cmp_orden_compra_enc
		   SET ocp_fecha = @Fecha, ocp_fecha_entrega = @FechaEntrega, prv_id = @PrvId, suc_id = @suc_id, bod_id = @BodId,
			   mon_id = @MonId, ocp_porc_iva = @iva, ocp_total = @total,
			   ocp_condiciones = NULLIF(LTRIM(RTRIM(@Condiciones)), ''), ocp_observaciones = NULLIF(LTRIM(RTRIM(@Observaciones)), ''),
			   ocp_flete_tipo = @FleteTipo, ocp_flete = @Flete,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE ocp_id = @OcpId AND ocp_estado = 'B';
		IF @@ROWCOUNT = 0
			THROW 54508, 'Solo se modifica una orden de compra en borrador.', 1;
		DELETE FROM dbo.cmp_orden_compra_det WHERE ocp_id = @OcpId;
	END

	INSERT INTO dbo.cmp_orden_compra_det (ocp_id, ocd_item, pro_id, ume_id, ocd_descripcion, ocd_cantidad, ocd_costo_unitario, ocd_total)
	SELECT @OcpId, ROW_NUMBER() OVER (ORDER BY deta.item), deta.pro_id, prod.ume_id,
		   ISNULL(NULLIF(LTRIM(RTRIM(deta.descripcion)), ''), prod.pro_descripcion), deta.cantidad, deta.costo_unitario,
		   ROUND(deta.cantidad * deta.costo_unitario, 2)
	FROM @Detalle deta
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id;

	SELECT @Numero = ocp_numero FROM dbo.cmp_orden_compra_enc WHERE ocp_id = @OcpId;
	COMMIT;
END;
GO

-- @Lineas: lo que llegó en esta factura del proveedor (cantidad y costo con IVA).
-- @Flete: el flete (con IVA) que trae esta misma factura.
-- Contado si @FechaPrimerPago es NULL; crédito con @NumeroCuotas cuotas.
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraRecibir]
	@OcpId				INT,
	@Fecha				DATE,
	@Serie				VARCHAR(32) = NULL,
	@NumeroDocumento	VARCHAR(32),
	@Autorizacion		VARCHAR(64) = NULL,
	@FechaPrimerPago	DATE = NULL,
	@NumeroCuotas		INT = 1,
	@Enganche			NUMERIC(12, 2) = 0,
	@UsuId				INT = NULL,
	@Lineas				dbo.orden_compra_recepcion_type READONLY,
	@EncId				INT OUTPUT,
	@Flete				NUMERIC(14, 2) = 0
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @EncId = NULL;

	IF ISNULL(LTRIM(RTRIM(@NumeroDocumento)), '') = ''
		THROW 54515, 'Indique el número de la factura del proveedor.', 1;
	IF NOT EXISTS (SELECT 1 FROM @Lineas WHERE cantidad > 0)
		THROW 54516, 'Indique la cantidad recibida de al menos un producto.', 1;
	IF EXISTS (SELECT 1 FROM @Lineas WHERE cantidad < 0 OR costo_unitario < 0)
		THROW 54517, 'La cantidad y el costo no pueden ser negativos.', 1;
	IF ISNULL(@Flete, 0) < 0
		THROW 55930, 'El flete no puede ser negativo.', 1;
	SELECT @Serie = NULLIF(LTRIM(RTRIM(@Serie)), ''), @NumeroDocumento = LTRIM(RTRIM(@NumeroDocumento));
	IF @FechaPrimerPago IS NOT NULL AND ISNULL(@NumeroCuotas, 0) < 1
		THROW 54518, 'Para una compra al crédito indique el número de cuotas.', 1;

	DECLARE @tdo_id INT = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo = 'COMP');

	BEGIN TRANSACTION;

	DECLARE @prv_id INT, @bod_id INT, @mon_id INT, @iva NUMERIC(8, 2), @estado CHAR(1), @numero_oc VARCHAR(16);
	SELECT @prv_id = prv_id, @bod_id = bod_id, @mon_id = mon_id, @iva = ocp_porc_iva, @estado = ocp_estado, @numero_oc = ocp_numero
	FROM dbo.cmp_orden_compra_enc WITH (UPDLOCK, HOLDLOCK)
	WHERE ocp_id = @OcpId;
	IF @estado IS NULL OR @estado <> 'A'
		THROW 54519, 'Solo se recibe mercadería de una orden aprobada (no en borrador, cerrada ni anulada).', 1;
	IF EXISTS (SELECT 1 FROM @Lineas line LEFT JOIN dbo.cmp_orden_compra_det deta ON deta.ocd_id = line.ocd_id AND deta.ocp_id = @OcpId
			   WHERE deta.ocd_id IS NULL)
		THROW 54520, 'Una línea recibida no pertenece a la orden.', 1;

	DECLARE @msg NVARCHAR(400) = (
		SELECT TOP 1 CONCAT(N'De ', deta.ocd_descripcion, N' quedan ', deta.ocd_cantidad - reci.recibido,
							N' pendientes y se quieren recibir ', line.cantidad, N'.')
		FROM @Lineas line
		INNER JOIN dbo.cmp_orden_compra_det deta ON deta.ocd_id = line.ocd_id
		INNER JOIN dbo.fnOrdenCompraRecibido(@OcpId) reci ON reci.ocd_id = deta.ocd_id
		WHERE line.cantidad > deta.ocd_cantidad - reci.recibido);
	IF @msg IS NOT NULL
		THROW 54521, @msg, 1;

	IF EXISTS (SELECT 1 FROM dbo.inv_documento_enc
			   WHERE prv_id = @prv_id AND tdo_id = @tdo_id AND enc_estado = 'G'
				 AND ISNULL(enc_serie_docto, '') = ISNULL(@Serie, '') AND enc_numero_docto = @NumeroDocumento)
		THROW 54522, 'Esa factura del proveedor ya está registrada como compra vigente.', 1;

	DECLARE @nombre VARCHAR(128), @nit VARCHAR(16);
	SELECT @nombre = LEFT(prv_nombre_comercial, 128), @nit = prv_nit FROM dbo.inv_proveedor WHERE prv_id = @prv_id;

	-- Costos con IVA a neto, como lo hace la pantalla de Compras.
	DECLARE @detalle dbo.compra_det_type;
	INSERT INTO @detalle (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario,
						  det_valor_descuento, det_sub_total, det_porc_iva, bod_id, pro_id)
	SELECT ROW_NUMBER() OVER (ORDER BY deta.ocd_item), 'B', line.cantidad, deta.ocd_descripcion,
		   ROUND(line.costo_unitario / (1 + @iva / 100.0), 2), 0,
		   ROUND(ROUND(line.costo_unitario / (1 + @iva / 100.0), 2) * line.cantidad, 2), @iva, @bod_id, deta.pro_id
	FROM @Lineas line
	INNER JOIN dbo.cmp_orden_compra_det deta ON deta.ocd_id = line.ocd_id
	WHERE line.cantidad > 0;

	DECLARE @flete_neto NUMERIC(12, 2) = ROUND(ISNULL(@Flete, 0) / (1 + @iva / 100.0), 2);

	EXEC dbo.paCompraDocumentoCrear
		@EncFechaDocto = @Fecha, @EncNumeroAutorizacion = @Autorizacion,
		@EncSerieDocto = @Serie, @EncNumeroDocto = @NumeroDocumento,
		@PrvId = @prv_id, @PrvEncNombresProveedor = @nombre, @PrvEncApellidosProveedor = NULL, @PrvNit = @nit,
		@TdoId = @tdo_id, @EncFechaPrimerPago = @FechaPrimerPago, @EncMontoEnganche = @Enganche,
		@EncNumeroCuotas = @NumeroCuotas, @EncValorDescuento = 0, @MonId = @mon_id, @UsuId = @UsuId,
		@Detalle = @detalle, @EncId = @EncId OUTPUT, @EncFlete = @flete_neto;

	DECLARE @ocr_id INT;
	INSERT INTO dbo.cmp_orden_compra_recepcion (ocp_id, enc_id, ocr_fecha, usu_id, InsUsuario, InsFechaHora)
	VALUES (@OcpId, @EncId, @Fecha, @UsuId, @UsuId, SYSDATETIME());
	SET @ocr_id = SCOPE_IDENTITY();

	INSERT INTO dbo.cmp_orden_compra_recepcion_det (ocr_id, ocd_id, ord_cantidad, ord_costo_unitario)
	SELECT @ocr_id, ocd_id, cantidad, costo_unitario FROM @Lineas WHERE cantidad > 0;

	-- Marca de la última actividad de la orden.
	UPDATE dbo.cmp_orden_compra_enc SET UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE ocp_id = @OcpId;

	COMMIT;
END;
GO

-- Igual que en 57, con el flete de la orden.
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraConsultarPorId]
	@OcpId	INT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @ordenado INT, @recibido INT;
	SELECT @ordenado = SUM(deta.ocd_cantidad), @recibido = SUM(reci.recibido)
	FROM dbo.cmp_orden_compra_det deta
	INNER JOIN dbo.fnOrdenCompraRecibido(@OcpId) reci ON reci.ocd_id = deta.ocd_id;

	SELECT orde.ocp_id AS OcpId, orde.ocp_numero AS Numero, orde.ocp_fecha AS Fecha, orde.ocp_fecha_entrega AS FechaEntrega,
		   CASE WHEN orde.ocp_estado <> 'A' THEN orde.ocp_estado
				WHEN @recibido >= @ordenado THEN 'R'
				WHEN @recibido > 0 THEN 'P'
				ELSE 'A' END AS Estado,
		   orde.prv_id AS PrvId, prov.prv_codigo AS ProveedorCodigo, prov.prv_nombre_comercial AS Proveedor, prov.prv_nit AS Nit,
		   prov.prv_direccion AS ProveedorDireccion, prov.prv_contacto AS ProveedorContacto,
		   COALESCE(prov.prv_telefono_oficina, prov.prv_celular) AS ProveedorTelefono,
		   COALESCE(prov.prv_email_contacto, prov.prv_email_empresa) AS ProveedorCorreo,
		   orde.suc_id AS SucId, orde.bod_id AS BodId, bode.bod_descripcion AS Bodega, orde.mon_id AS MonId,
		   ISNULL(mone.mon_codigo, 'GTQ') AS Moneda, ISNULL(mone.mon_simbolo, 'Q') AS Simbolo,
		   orde.ocp_porc_iva AS PorcentajeIva, orde.ocp_total AS Total,
		   CAST(ROUND(orde.ocp_total * orde.ocp_porc_iva / (100 + orde.ocp_porc_iva), 2) AS NUMERIC(14, 2)) AS IvaIncluido,
		   orde.ocp_condiciones AS Condiciones, orde.ocp_observaciones AS Observaciones, orde.ocp_motivo_cierre AS MotivoCierre,
		   usua.usu_codigo AS Usuario, apro.usu_codigo AS Aprobo, orde.ocp_fecha_aprobacion AS FechaAprobacion,
		   vobo.usu_codigo AS VistoBueno, orde.ocp_fecha_visto_bueno AS FechaVistoBueno, orde.ocp_motivo_devolucion AS MotivoDevolucion,
		   ISNULL(@ordenado, 0) AS Ordenado, ISNULL(@recibido, 0) AS Recibido,
		   -- Flete (con IVA): tipo, monto de la orden y lo que ya trajeron las
		   -- facturas vigentes de sus recepciones.
		   orde.ocp_flete_tipo AS FleteTipo, orde.ocp_flete AS Flete,
		   ISNULL((SELECT SUM(ROUND(fdet.det_sub_total * (1 + ISNULL(fdet.det_porc_iva, 0) / 100.0), 2))
				   FROM dbo.cmp_orden_compra_recepcion frec
				   INNER JOIN dbo.inv_documento_enc fcom ON fcom.enc_id = frec.enc_id AND fcom.enc_estado = 'G'
				   INNER JOIN dbo.inv_documento_det fdet ON fdet.enc_id = fcom.enc_id AND fdet.det_es_flete = 1
				   WHERE frec.ocp_id = orde.ocp_id), 0) AS FleteRecibido,
		   -- Emisor y lugar de entrega
		   comp.cia_id AS CiaId, comp.cia_nit AS NitEmisor, ISNULL(comp.cia_fel_nombre_emisor, comp.cia_nombre_comercial) AS NombreEmisor,
		   ISNULL(sucu.suc_fel_nombre_comercial, comp.cia_nombre_comercial) AS NombreComercial,
		   ISNULL(sucu.suc_direccion, comp.cia_direccion) AS DireccionEmisor, ISNULL(sucu.suc_telefono, comp.cia_telefono) AS TelefonoEmisor,
		   ISNULL(comp.cia_fel_correo_emisor, comp.cia_email) AS CorreoEmisor, sucu.suc_descripcion AS Sucursal,
		   CAST(CASE WHEN comp.cia_logo IS NULL THEN 0 ELSE 1 END AS BIT) AS TieneLogo, comp.cia_logo_actualizado AS LogoActualizado
	FROM dbo.cmp_orden_compra_enc orde
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = orde.prv_id
	INNER JOIN dbo.inv_bodega bode ON bode.bod_id = orde.bod_id
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = orde.suc_id
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	LEFT JOIN dbo.gen_moneda mone ON mone.mon_id = orde.mon_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = orde.usu_id
	LEFT JOIN dbo.gen_usuario apro ON apro.usu_id = orde.usu_id_aprobacion
	LEFT JOIN dbo.gen_usuario vobo ON vobo.usu_id = orde.usu_id_visto_bueno
	WHERE orde.ocp_id = @OcpId;

	SELECT deta.ocd_id AS OcdId, deta.ocd_item AS Item, deta.pro_id AS ProId, prod.pro_codigo AS Codigo,
		   rela.ppp_codigo_proveedor AS CodigoProveedor, deta.ocd_descripcion AS Descripcion,
		   ISNULL(unid.ume_codigo, 'UND') AS Unidad, deta.ocd_cantidad AS Cantidad, reci.recibido AS Recibido,
		   IIF(deta.ocd_cantidad > reci.recibido, deta.ocd_cantidad - reci.recibido, 0) AS Pendiente,
		   deta.ocd_costo_unitario AS CostoUnitario, deta.ocd_total AS Total, exis.existencia AS Existencia
	FROM dbo.cmp_orden_compra_det deta
	INNER JOIN dbo.cmp_orden_compra_enc orde ON orde.ocp_id = deta.ocp_id
	INNER JOIN dbo.fnOrdenCompraRecibido(@OcpId) reci ON reci.ocd_id = deta.ocd_id
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = deta.ume_id
	LEFT JOIN dbo.inv_producto_proveedor rela ON rela.pro_id = deta.pro_id AND rela.prv_id = orde.prv_id
	LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = deta.pro_id AND exis.bod_id = orde.bod_id
	WHERE deta.ocp_id = @OcpId
	ORDER BY deta.ocd_item;

	SELECT rece.ocr_id AS OcrId, rece.enc_id AS EncId, rece.ocr_fecha AS Fecha,
		   CONCAT(comp.enc_serie_docto, IIF(comp.enc_serie_docto IS NULL, '', '-'), comp.enc_numero_docto) AS Documento,
		   comp.enc_monto_total AS Total, comp.enc_estado AS EstadoCompra, usua.usu_codigo AS Usuario,
		   (SELECT SUM(rdet.ord_cantidad) FROM dbo.cmp_orden_compra_recepcion_det rdet WHERE rdet.ocr_id = rece.ocr_id) AS Unidades
	FROM dbo.cmp_orden_compra_recepcion rece
	INNER JOIN dbo.inv_documento_enc comp ON comp.enc_id = rece.enc_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = rece.usu_id
	WHERE rece.ocp_id = @OcpId
	ORDER BY rece.ocr_fecha, rece.ocr_id;
END;
GO
