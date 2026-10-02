------------------------------------------------------------------------------
-- 32_cuentas_por_cobrar_pagar.sql
--
-- Cuentas por cobrar (clientes) y por pagar (proveedores):
--
--   1. Notas de crédito y de débito, a cliente y de proveedor, ligadas al
--      documento que afectan (enc_id_referencia). Son documentos de
--      inv_documento_enc con tipos propios (tdo_es_nota = 1):
--        NCC Nota de crédito a cliente     NDC Nota de débito a cliente
--        NCP Nota de crédito de proveedor  NDP Nota de débito de proveedor
--      * Nota de crédito: rebaja el saldo del documento desde la última cuota
--        hacia atrás. Sus líneas pueden ser una devolución (producto y
--        cantidad de una línea del documento original: reingresa o sale del
--        inventario) o una rebaja por monto.
--      * Nota de débito: cargo adicional (intereses, gastos...); agrega una
--        cuota nueva al plan del documento con su propio vencimiento.
--      * Cada nota genera su póliza (ver README).
--   2. Cobro de cuota y pago con cheque validan el monto contra el saldo.
--   3. Consultas: documentos con saldo, estado de cuenta con saldo corrido y
--      antigüedad de saldos por vencimiento (No vencido, 1-30, 31-60, 61-90,
--      más de 90 días), para clientes y proveedores.
--   4. Permisos CXC_ADMIN y CXP_ADMIN.
--
-- Requiere 29 y 31. Se puede volver a correr.
------------------------------------------------------------------------------

USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Estructura
------------------------------------------------------------
IF COL_LENGTH('dbo.inv_documento_tipo', 'tdo_es_nota') IS NULL
	ALTER TABLE dbo.inv_documento_tipo ADD [tdo_es_nota] BIT NOT NULL CONSTRAINT [DF_inv_documento_tipo_es_nota] DEFAULT (0);
IF COL_LENGTH('dbo.inv_documento_enc', 'enc_motivo') IS NULL
	ALTER TABLE dbo.inv_documento_enc ADD [enc_motivo] VARCHAR(256) NULL;	-- motivo de una nota
IF COL_LENGTH('dbo.inv_documento_det', 'det_id_origen') IS NULL
	ALTER TABLE dbo.inv_documento_det ADD [det_id_origen] INT NULL;			-- línea devuelta del documento original
GO
IF OBJECT_ID('dbo.FK_inv_documento_det_origen', 'F') IS NULL
	ALTER TABLE dbo.inv_documento_det ADD CONSTRAINT [FK_inv_documento_det_origen] FOREIGN KEY ([det_id_origen]) REFERENCES dbo.inv_documento_det ([det_id]);
IF OBJECT_ID('dbo.FK_inv_documento_enc_referencia', 'F') IS NULL
	ALTER TABLE dbo.inv_documento_enc ADD CONSTRAINT [FK_inv_documento_enc_referencia] FOREIGN KEY ([enc_id_referencia]) REFERENCES dbo.inv_documento_enc ([enc_id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_inv_documento_enc_referencia' AND object_id = OBJECT_ID('dbo.inv_documento_enc'))
	CREATE INDEX [IX_inv_documento_enc_referencia] ON dbo.inv_documento_enc ([enc_id_referencia]) WHERE [enc_id_referencia] IS NOT NULL;
GO

-- La naturaleza indica el movimiento de inventario de sus devoluciones: la
-- mercadería que devuelve el cliente entra (+) y la que se devuelve al
-- proveedor sale (-). Las notas de débito no llevan productos.
INSERT INTO dbo.inv_documento_tipo (tdo_codigo, tdo_descripcion, tdo_naturaleza, afecta_costo, tdo_es_nota)
SELECT v.c, v.d, v.n, v.a, 1
FROM (VALUES ('NCC', 'Nota de crédito a cliente', '+', 'S'), ('NDC', 'Nota de débito a cliente', '-', 'N'),
			 ('NCP', 'Nota de crédito de proveedor', '-', 'S'), ('NDP', 'Nota de débito de proveedor', '+', 'N')) v(c, d, n, a)
WHERE NOT EXISTS (SELECT 1 FROM dbo.inv_documento_tipo tipo WHERE tipo.tdo_codigo = v.c);
UPDATE dbo.inv_documento_tipo SET tdo_es_nota = 1 WHERE tdo_codigo IN ('NCC', 'NDC', 'NCP', 'NDP') AND tdo_es_nota = 0;

-- Las notas a clientes llevan correlativo propio; las de proveedor usan el
-- número del documento del proveedor.
INSERT INTO dbo.conf_correlativos (tdo_id, serie, correlativo)
SELECT tipo.tdo_id, v.s, 0
FROM (VALUES ('NCC', 'NC-A'), ('NDC', 'ND-A')) v(c, s)
INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_codigo = v.c
WHERE NOT EXISTS (SELECT 1 FROM dbo.conf_correlativos corr WHERE corr.tdo_id = tipo.tdo_id);
GO

-- Aplicación de cada nota al plan de pagos: qué cuota rebajó (crédito) o
-- creó (débito) y por cuánto.
IF OBJECT_ID('dbo.pos_cliente_nota_aplicacion', 'U') IS NULL
CREATE TABLE [dbo].[pos_cliente_nota_aplicacion](
	[cna_id]		INT				IDENTITY(1,1)	NOT NULL,
	[enc_id_nota]	INT				NOT NULL,
	[cpp_id]		INT				NOT NULL,
	[cna_monto]		NUMERIC(12, 2)	NOT NULL,
	[InsUsuario]	INT				NULL,
	[InsFechaHora]	DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	CONSTRAINT [PK_pos_cliente_nota_aplicacion] PRIMARY KEY CLUSTERED ([cna_id]),
	CONSTRAINT [FK_pos_cliente_nota_aplicacion_nota] FOREIGN KEY ([enc_id_nota]) REFERENCES dbo.inv_documento_enc ([enc_id]),
	CONSTRAINT [FK_pos_cliente_nota_aplicacion_cuota] FOREIGN KEY ([cpp_id]) REFERENCES dbo.pos_cliente_plan_pagos ([cpp_id])
);
IF OBJECT_ID('dbo.inv_proveedor_nota_aplicacion', 'U') IS NULL
CREATE TABLE [dbo].[inv_proveedor_nota_aplicacion](
	[pna_id]		INT				IDENTITY(1,1)	NOT NULL,
	[enc_id_nota]	INT				NOT NULL,
	[ppg_id]		INT				NOT NULL,
	[pna_monto]		NUMERIC(12, 2)	NOT NULL,
	[InsUsuario]	INT				NULL,
	[InsFechaHora]	DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	CONSTRAINT [PK_inv_proveedor_nota_aplicacion] PRIMARY KEY CLUSTERED ([pna_id]),
	CONSTRAINT [FK_inv_proveedor_nota_aplicacion_nota] FOREIGN KEY ([enc_id_nota]) REFERENCES dbo.inv_documento_enc ([enc_id]),
	CONSTRAINT [FK_inv_proveedor_nota_aplicacion_cuota] FOREIGN KEY ([ppg_id]) REFERENCES dbo.inv_proveedor_plan_pago ([ppg_id])
);
GO

-- Subcuenta de devoluciones y rebajas sobre ventas (cuenta de naturaleza
-- deudora dentro de 411 Ventas), si no existe.
IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_codigo = '4110028')
   AND EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_codigo = '411')
BEGIN
	DECLARE @padre INT = (SELECT cta_id FROM dbo.cont_cuenta_contable WHERE cta_codigo = '411'), @nueva INT;
	EXEC dbo.paCuentaContableNodoGuardar @CtaId = NULL, @IdPadre = @padre, @Codigo = '4110028',
		@Nombre = 'DEVOLUCIONES Y REBAJAS SOBRE VENTAS', @Naturaleza = 'D', @UsuId = NULL, @IdResultado = @nueva OUTPUT;
END
GO

INSERT INTO dbo.cont_cuenta_parametro (ccp_codigo, ccp_descripcion, ccp_naturaleza, cta_id)
SELECT v.c, v.d, v.n, cuen.cta_id
FROM (VALUES
	('NC_CLIENTE_REBAJA',   'Nota de crédito a cliente: devolución o rebaja sobre ventas (sin IVA)', 'D', '4110028'),
	('ND_CLIENTE_INGRESO',  'Nota de débito a cliente: ingreso por el cargo (sin IVA)',             'H', '4110026'),
	('NC_PROVEEDOR_REBAJA', 'Nota de crédito de proveedor: rebaja por monto (sin IVA)',             'H', '4110026'),
	('ND_PROVEEDOR_GASTO',  'Nota de débito de proveedor: gasto por el cargo (sin IVA)',            'D', '5110033')
) v(c, d, n, cuenta)
LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_codigo = v.cuenta
WHERE NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_parametro para WHERE para.ccp_codigo = v.c);
UPDATE para SET cta_id = cuen.cta_id
FROM dbo.cont_cuenta_parametro para
INNER JOIN (VALUES ('NC_CLIENTE_REBAJA', '4110028'), ('ND_CLIENTE_INGRESO', '4110026'),
				   ('NC_PROVEEDOR_REBAJA', '4110026'), ('ND_PROVEEDOR_GASTO', '5110033')) v(c, cuenta) ON v.c = para.ccp_codigo
INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_codigo = v.cuenta
WHERE para.cta_id IS NULL;
GO

------------------------------------------------------------
-- 2. Notas de crédito y débito
------------------------------------------------------------
IF TYPE_ID(N'dbo.nota_det_type') IS NULL
CREATE TYPE [dbo].[nota_det_type] AS TABLE
(
	[det_item]				INT				NOT NULL,
	[det_descripcion]		VARCHAR(256)	NOT NULL,
	[det_cantidad]			NUMERIC(12, 4)	NOT NULL,
	[det_precio_unitario]	NUMERIC(12, 2)	NOT NULL,	-- sin IVA
	[det_porc_iva]			NUMERIC(8, 2)	NULL,
	[ume_id]				INT				NULL,
	[det_id_origen]			INT				NULL		-- devolución: línea del documento original; NULL = rebaja o cargo por monto
);
GO

CREATE OR ALTER PROCEDURE [dbo].[paNotaCrear]
	@TipoNota			CHAR(3),			-- NCC, NDC, NCP, NDP
	@EncIdReferencia	INT,
	@Fecha				DATE,
	@NumeroDocto		VARCHAR(32) = NULL,	-- número del proveedor (NCP/NDP)
	@Motivo				VARCHAR(256),
	@FechaVencimiento	DATE = NULL,		-- nota de débito: vencimiento de la cuota nueva
	@UsuId				INT = NULL,
	@Detalle			dbo.nota_det_type READONLY,
	@EncId				INT OUTPUT,
	@NumeroUnico		VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- Los parámetros OUTPUT también llegan con el valor que traiga quien llama.
	SELECT @EncId = NULL, @NumeroUnico = NULL;

	DECLARE @es_cliente BIT = CASE WHEN @TipoNota IN ('NCC', 'NDC') THEN 1 ELSE 0 END,
			@es_credito BIT = CASE WHEN @TipoNota IN ('NCC', 'NCP') THEN 1 ELSE 0 END;

	IF @TipoNota NOT IN ('NCC', 'NDC', 'NCP', 'NDP')
		THROW 53101, 'El tipo de nota debe ser NCC, NDC, NCP o NDP.', 1;
	IF ISNULL(LTRIM(RTRIM(@Motivo)), '') = ''
		THROW 53102, 'Ingrese el motivo de la nota.', 1;
	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 53103, 'La nota debe tener al menos una línea.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE det_cantidad <= 0 OR det_precio_unitario < 0 OR LTRIM(RTRIM(det_descripcion)) = '')
		THROW 53104, 'Cada línea necesita descripción, cantidad mayor a cero y precio no negativo.', 1;
	IF @es_credito = 0 AND EXISTS (SELECT 1 FROM @Detalle WHERE det_id_origen IS NOT NULL)
		THROW 53105, 'Una nota de débito no lleva devoluciones de producto.', 1;
	IF @es_credito = 0 AND @FechaVencimiento IS NULL
		THROW 53106, 'Indique la fecha de vencimiento del cargo de la nota de débito.', 1;
	IF @es_cliente = 0 AND ISNULL(LTRIM(RTRIM(@NumeroDocto)), '') = ''
		THROW 53107, 'Ingrese el número de la nota del proveedor.', 1;

	-- Documento de referencia: factura (cliente) o compra (proveedor) grabada.
	DECLARE @ref_cli INT, @ref_prv INT, @ref_estado CHAR(1), @ref_es_nota BIT, @ref_naturaleza CHAR(1), @ref_afecta_costo CHAR(1),
			@ref_mon INT, @ref_bod INT;
	SELECT @ref_cli = enca.cli_id, @ref_prv = enca.prv_id, @ref_estado = enca.enc_estado, @ref_es_nota = tipo.tdo_es_nota,
		   @ref_naturaleza = tipo.tdo_naturaleza, @ref_afecta_costo = tipo.afecta_costo, @ref_mon = enca.mon_id,
		   @ref_bod = (SELECT TOP 1 bod_id FROM dbo.inv_documento_det WHERE enc_id = enca.enc_id ORDER BY det_item)
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @EncIdReferencia;

	IF @ref_estado IS NULL OR @ref_es_nota = 1
		THROW 53108, 'El documento de referencia no existe o es otra nota.', 1;
	IF @ref_estado <> 'G'
		THROW 53109, 'El documento de referencia debe estar grabado (no anulado).', 1;
	IF @es_cliente = 1 AND (@ref_cli IS NULL OR @ref_naturaleza <> '-')
		THROW 53110, 'Una nota a cliente debe referirse a una factura.', 1;
	IF @es_cliente = 0 AND (@ref_prv IS NULL OR @ref_naturaleza <> '+')
		THROW 53111, 'Una nota de proveedor debe referirse a una compra.', 1;

	-- Líneas con los datos que faltan tomados de la línea original.
	DECLARE @lineas TABLE (det_item INT PRIMARY KEY, det_descripcion VARCHAR(256), det_cantidad NUMERIC(12, 4), det_precio_unitario NUMERIC(12, 2),
		det_sub_total NUMERIC(12, 2), det_porc_iva NUMERIC(8, 2), ume_id INT, det_id_origen INT, pro_id INT, bod_id INT, maneja_existencia BIT,
		costo_unitario NUMERIC(14, 5));
	INSERT INTO @lineas
	SELECT deta.det_item, deta.det_descripcion, deta.det_cantidad, deta.det_precio_unitario,
		   ROUND(deta.det_cantidad * deta.det_precio_unitario, 2), ISNULL(deta.det_porc_iva, orig.det_porc_iva),
		   COALESCE(orig.ume_id, deta.ume_id), deta.det_id_origen, orig.pro_id, ISNULL(orig.bod_id, @ref_bod),
		   ISNULL(prod.pro_maneja_existencia, 0),
		   -- costo con que vuelve (o sale) la mercadería: el costo de la venta
		   -- original; en compras, el costo de compra de la línea.
		   CASE WHEN @es_cliente = 1 THEN COALESCE(orig.det_costo_unitario, prod.pro_costo_unitario, 0)
				ELSE deta.det_precio_unitario END
	FROM @Detalle deta
	LEFT JOIN dbo.inv_documento_det orig ON orig.det_id = deta.det_id_origen
	LEFT JOIN dbo.inv_producto prod ON prod.pro_id = orig.pro_id;

	IF EXISTS (SELECT 1 FROM @lineas lin LEFT JOIN dbo.inv_documento_det orig ON orig.det_id = lin.det_id_origen
			   WHERE lin.det_id_origen IS NOT NULL AND (orig.enc_id IS NULL OR orig.enc_id <> @EncIdReferencia OR orig.pro_id IS NULL))
		THROW 53112, 'Una línea de devolución no corresponde a un producto del documento de referencia.', 1;

	-- No se puede devolver más de lo vendido/comprado menos lo ya devuelto.
	IF EXISTS (
		SELECT 1
		FROM (SELECT det_id_origen, SUM(det_cantidad) AS cantidad FROM @lineas WHERE det_id_origen IS NOT NULL GROUP BY det_id_origen) dev
		INNER JOIN dbo.inv_documento_det orig ON orig.det_id = dev.det_id_origen
		CROSS APPLY (SELECT ISNULL(SUM(prev.det_cantidad), 0) AS devuelto
					 FROM dbo.inv_documento_det prev
					 INNER JOIN dbo.inv_documento_enc nota ON nota.enc_id = prev.enc_id AND nota.enc_estado = 'G'
					 WHERE prev.det_id_origen = orig.det_id) ante
		WHERE dev.cantidad > orig.det_cantidad - ante.devuelto)
		THROW 53113, 'La cantidad devuelta supera lo que queda por devolver de esa línea.', 1;

	IF EXISTS (SELECT 1 FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1 AND det_cantidad <> ROUND(det_cantidad, 0))
		THROW 53114, 'Los productos con existencia se devuelven en cantidades enteras.', 1;

	-- Devolución al proveedor: la mercadería debe estar en la bodega.
	IF @es_cliente = 0 AND @es_credito = 1 AND EXISTS (
		SELECT 1
		FROM (SELECT pro_id, bod_id, SUM(det_cantidad) AS cantidad FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1 GROUP BY pro_id, bod_id) dev
		LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = dev.pro_id AND exis.bod_id = dev.bod_id
		WHERE ISNULL(exis.existencia, 0) < dev.cantidad)
		THROW 53115, 'No hay existencia suficiente en la bodega para devolver esa mercadería al proveedor.', 1;

	DECLARE @neto NUMERIC(14, 2) = (SELECT SUM(det_sub_total) FROM @lineas),
			@neto_devolucion NUMERIC(14, 2) = (SELECT ISNULL(SUM(det_sub_total), 0) FROM @lineas WHERE det_id_origen IS NOT NULL),
			@costo_devolucion NUMERIC(14, 2) = (SELECT ISNULL(SUM(ROUND(det_cantidad * costo_unitario, 2)), 0) FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1),
			@total NUMERIC(14, 2) = (SELECT ROUND(SUM(det_sub_total * (1 + ISNULL(det_porc_iva, 0) / 100.0)), 2) FROM @lineas);
	DECLARE @iva NUMERIC(14, 2) = @total - @neto;

	IF @total <= 0
		THROW 53116, 'El total de la nota debe ser mayor a cero.', 1;

	-- Una nota de crédito no puede dejar el documento con saldo negativo.
	DECLARE @pendiente NUMERIC(14, 2) = CASE WHEN @es_cliente = 1
		THEN (SELECT ISNULL(SUM(cpp_saldo_cuota), 0) FROM dbo.pos_cliente_plan_pagos WHERE enc_id = @EncIdReferencia AND cpp_saldo_cuota > 0)
		ELSE (SELECT ISNULL(SUM(ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0)), 0) FROM dbo.inv_proveedor_plan_pago
			  WHERE enc_id = @EncIdReferencia AND ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0) > 0) END;
	IF @es_credito = 1 AND @total > @pendiente
	BEGIN
		DECLARE @msg_saldo NVARCHAR(300) = CONCAT(N'La nota de crédito (Q', FORMAT(@total, 'N2'), N') supera el saldo pendiente del documento (Q',
			FORMAT(@pendiente, 'N2'), N').');
		THROW 53117, @msg_saldo, 1;
	END

	-- Cuentas de la póliza (se validan antes de grabar nada).
	DECLARE @cta_clientes INT, @cta_iva_debito INT, @cta_inventario INT, @cta_costo INT, @cta_proveedores INT, @cta_iva_credito INT,
			@cta_gasto_compra INT, @cta_contrapartida INT;
	IF @es_cliente = 1
	BEGIN
		EXEC dbo.paCuentaParametroObtener @Codigo = 'VENTA_CLIENTES', @CtaId = @cta_clientes OUTPUT;
		EXEC dbo.paCuentaParametroObtener @Codigo = 'VENTA_IVA_DEBITO', @CtaId = @cta_iva_debito OUTPUT;
		IF @es_credito = 1
		BEGIN
			EXEC dbo.paCuentaParametroObtener @Codigo = 'NC_CLIENTE_REBAJA', @CtaId = @cta_contrapartida OUTPUT;
			IF @costo_devolucion > 0
			BEGIN
				EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO', @CtaId = @cta_inventario OUTPUT;
				EXEC dbo.paCuentaParametroObtener @Codigo = 'VENTA_COSTO', @CtaId = @cta_costo OUTPUT;
			END
		END
		ELSE
			EXEC dbo.paCuentaParametroObtener @Codigo = 'ND_CLIENTE_INGRESO', @CtaId = @cta_contrapartida OUTPUT;
	END
	ELSE
	BEGIN
		EXEC dbo.paCuentaParametroObtener @Codigo = 'COMPRA_PROVEEDORES', @CtaId = @cta_proveedores OUTPUT;
		EXEC dbo.paCuentaParametroObtener @Codigo = 'COMPRA_IVA_CREDITO', @CtaId = @cta_iva_credito OUTPUT;
		IF @es_credito = 1
		BEGIN
			IF @neto - @neto_devolucion > 0
				EXEC dbo.paCuentaParametroObtener @Codigo = 'NC_PROVEEDOR_REBAJA', @CtaId = @cta_contrapartida OUTPUT;
			IF @neto_devolucion > 0
			BEGIN
				-- EXEC no acepta una expresión como valor de un parámetro.
				DECLARE @concepto_devolucion VARCHAR(40) = CASE WHEN @ref_afecta_costo = 'S' THEN 'INVENTARIO' ELSE 'COMPRA_GASTO' END;
				EXEC dbo.paCuentaParametroObtener @Codigo = @concepto_devolucion, @CtaId = @cta_inventario OUTPUT;
			END
		END
		ELSE
			EXEC dbo.paCuentaParametroObtener @Codigo = 'ND_PROVEEDOR_GASTO', @CtaId = @cta_contrapartida OUTPUT;
	END

	DECLARE @tdo_id INT = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo = @TipoNota);
	DECLARE @referencia VARCHAR(40);

	BEGIN TRANSACTION;

	-- Correlativo (solo notas a clientes).
	IF @es_cliente = 1
	BEGIN
		DECLARE @serie VARCHAR(32), @correlativo NUMERIC(12, 0);
		SELECT @serie = serie, @correlativo = correlativo + 1 FROM dbo.conf_correlativos WITH (UPDLOCK, ROWLOCK) WHERE tdo_id = @tdo_id;
		IF @serie IS NULL
			THROW 51403, 'No existe una serie de correlativos configurada para este tipo de documento.', 1;
		UPDATE dbo.conf_correlativos SET correlativo = @correlativo, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE tdo_id = @tdo_id;
		SET @NumeroUnico = @serie + '-' + CAST(@correlativo AS VARCHAR(20));
	END

	INSERT INTO dbo.inv_documento_enc
		(enc_fecha_docto, enc_numero_docto, cli_id, enc_nombres_cliente, enc_apellidos_cliente, cli_nit,
		 prv_id, prv_enc_nombres_proveedor, prv_enc_apellidos_proveedor, prv_nit, tdo_id, enc_monto_total, enc_id_referencia,
		 mon_id, enc_numero_unico, enc_motivo, usu_id_creacion, enc_estado, InsUsuario, InsFechaHora)
	SELECT @Fecha, @NumeroDocto, refe.cli_id, refe.enc_nombres_cliente, refe.enc_apellidos_cliente, refe.cli_nit,
		   refe.prv_id, refe.prv_enc_nombres_proveedor, refe.prv_enc_apellidos_proveedor, refe.prv_nit, @tdo_id, @total, @EncIdReferencia,
		   @ref_mon, @NumeroUnico, LTRIM(RTRIM(@Motivo)), @UsuId, 'G', @UsuId, SYSDATETIME()
	FROM dbo.inv_documento_enc refe WHERE refe.enc_id = @EncIdReferencia;
	SET @EncId = SCOPE_IDENTITY();
	SET @referencia = CONCAT(@TipoNota, ' ', ISNULL(@NumeroUnico, @NumeroDocto));

	INSERT INTO dbo.inv_documento_det
		(enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total, det_costo_unitario,
		 det_porc_iva, bod_id, pro_id, ume_id, det_id_origen, InsUsuario, InsFechaHora)
	SELECT @EncId, det_item, CASE WHEN pro_id IS NULL THEN 'S' ELSE 'B' END, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total,
		   CASE WHEN maneja_existencia = 1 THEN costo_unitario END, det_porc_iva, bod_id, pro_id, ume_id, det_id_origen, @UsuId, SYSDATETIME()
	FROM @lineas;

	-- Inventario de las devoluciones: entra (cliente) o sale (proveedor) al
	-- costo de la línea, y se recalcula el costo promedio.
	IF EXISTS (SELECT 1 FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1)
	BEGIN
		DECLARE @signo INT = CASE WHEN @es_cliente = 1 THEN 1 ELSE -1 END;
		DECLARE @movimientos TABLE (pro_id INT, bod_id INT, cantidad NUMERIC(14, 4), costo NUMERIC(14, 2), PRIMARY KEY (pro_id, bod_id));
		INSERT INTO @movimientos
		SELECT pro_id, bod_id, SUM(det_cantidad) * @signo, SUM(ROUND(det_cantidad * costo_unitario, 2)) * @signo
		FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1
		GROUP BY pro_id, bod_id;

		MERGE dbo.inv_producto_existencia_bodega AS destino
		USING @movimientos AS origen ON destino.pro_id = origen.pro_id AND destino.bod_id = origen.bod_id
		WHEN MATCHED THEN UPDATE SET existencia = destino.existencia + origen.cantidad, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		WHEN NOT MATCHED THEN INSERT (bod_id, pro_id, existencia, InsUsuario, InsFechaHora) VALUES (origen.bod_id, origen.pro_id, origen.cantidad, @UsuId, SYSDATETIME());

		;WITH totales AS (SELECT pro_id, SUM(cantidad) AS cantidad, SUM(costo) AS costo FROM @movimientos GROUP BY pro_id)
		UPDATE prod
		   SET prod.pro_total_cantidad = prod.pro_total_cantidad + tota.cantidad,
			   prod.pro_total_costo = prod.pro_total_costo + tota.costo,
			   prod.pro_costo_unitario = CASE WHEN prod.pro_total_cantidad + tota.cantidad > 0
											  THEN (prod.pro_total_costo + tota.costo) / (prod.pro_total_cantidad + tota.cantidad) ELSE 0 END,
			   prod.UpdUsuario = @UsuId, prod.UpdFechaHora = SYSDATETIME()
		FROM dbo.inv_producto prod INNER JOIN totales tota ON tota.pro_id = prod.pro_id;
	END

	-- Plan de pagos.
	IF @es_credito = 1
	BEGIN
		-- Rebaja desde la última cuota hacia atrás.
		DECLARE @restante NUMERIC(14, 2) = @total, @cuota INT, @saldo_cuota NUMERIC(14, 2), @aplicado NUMERIC(14, 2);
		IF @es_cliente = 1
		BEGIN
			DECLARE cuotas_cur CURSOR LOCAL FAST_FORWARD FOR
				SELECT cpp_id, cpp_saldo_cuota FROM dbo.pos_cliente_plan_pagos
				WHERE enc_id = @EncIdReferencia AND cpp_saldo_cuota > 0 ORDER BY cpp_nro_cuota DESC;
			OPEN cuotas_cur;
			FETCH NEXT FROM cuotas_cur INTO @cuota, @saldo_cuota;
			WHILE @@FETCH_STATUS = 0 AND @restante > 0
			BEGIN
				SET @aplicado = CASE WHEN @saldo_cuota < @restante THEN @saldo_cuota ELSE @restante END;
				UPDATE dbo.pos_cliente_plan_pagos
				   SET cpp_saldo_cuota = cpp_saldo_cuota - @aplicado,
					   cpp_estado = CASE WHEN cpp_saldo_cuota - @aplicado <= 0 THEN 'A' ELSE cpp_estado END,
					   cpp_fecha_real_pago = CASE WHEN cpp_saldo_cuota - @aplicado <= 0 THEN @Fecha ELSE cpp_fecha_real_pago END,
					   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
				 WHERE cpp_id = @cuota;
				INSERT INTO dbo.pos_cliente_nota_aplicacion (enc_id_nota, cpp_id, cna_monto, InsUsuario) VALUES (@EncId, @cuota, @aplicado, @UsuId);
				SET @restante = @restante - @aplicado;
				FETCH NEXT FROM cuotas_cur INTO @cuota, @saldo_cuota;
			END
			CLOSE cuotas_cur; DEALLOCATE cuotas_cur;
		END
		ELSE
		BEGIN
			DECLARE pagos_cur CURSOR LOCAL FAST_FORWARD FOR
				SELECT ppg_id, ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0) FROM dbo.inv_proveedor_plan_pago
				WHERE enc_id = @EncIdReferencia AND ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0) > 0 ORDER BY ppg_nro_pago DESC;
			OPEN pagos_cur;
			FETCH NEXT FROM pagos_cur INTO @cuota, @saldo_cuota;
			WHILE @@FETCH_STATUS = 0 AND @restante > 0
			BEGIN
				SET @aplicado = CASE WHEN @saldo_cuota < @restante THEN @saldo_cuota ELSE @restante END;
				UPDATE dbo.inv_proveedor_plan_pago
				   SET ppg_valor_pago = ppg_valor_pago - @aplicado,
					   ppg_estado = CASE WHEN ppg_valor_pago - @aplicado <= ISNULL(ppg_valor_real_pago, 0) THEN 'A' ELSE ppg_estado END,
					   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
				 WHERE ppg_id = @cuota;
				INSERT INTO dbo.inv_proveedor_nota_aplicacion (enc_id_nota, ppg_id, pna_monto, InsUsuario) VALUES (@EncId, @cuota, @aplicado, @UsuId);
				SET @restante = @restante - @aplicado;
				FETCH NEXT FROM pagos_cur INTO @cuota, @saldo_cuota;
			END
			CLOSE pagos_cur; DEALLOCATE pagos_cur;
		END
	END
	ELSE
	BEGIN
		-- Nota de débito: cuota nueva al final del plan del documento.
		DECLARE @nueva_cuota INT;
		IF @es_cliente = 1
		BEGIN
			INSERT INTO dbo.pos_cliente_plan_pagos
				(cpp_nro_cuota, cpp_fecha_maxima_pago, cpp_valor_cuota, cpp_saldo_cuota, enc_id, cli_id, cpp_estado, InsUsuario, InsFechaHora)
			SELECT ISNULL(MAX(cpp_nro_cuota), 0) + 1, @FechaVencimiento, @total, @total, @EncIdReferencia, @ref_cli, 'P', @UsuId, SYSDATETIME()
			FROM dbo.pos_cliente_plan_pagos WHERE enc_id = @EncIdReferencia;
			SET @nueva_cuota = SCOPE_IDENTITY();
			INSERT INTO dbo.pos_cliente_nota_aplicacion (enc_id_nota, cpp_id, cna_monto, InsUsuario) VALUES (@EncId, @nueva_cuota, @total, @UsuId);
		END
		ELSE
		BEGIN
			INSERT INTO dbo.inv_proveedor_plan_pago (ppg_nro_pago, ppg_fecha_pago, ppg_valor_pago, enc_id, prv_id, ppg_estado, InsUsuario, InsFechaHora)
			SELECT ISNULL(MAX(ppg_nro_pago), 0) + 1, @FechaVencimiento, @total, @EncIdReferencia, @ref_prv, 'P', @UsuId, SYSDATETIME()
			FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @EncIdReferencia;
			SET @nueva_cuota = SCOPE_IDENTITY();
			INSERT INTO dbo.inv_proveedor_nota_aplicacion (enc_id_nota, ppg_id, pna_monto, InsUsuario) VALUES (@EncId, @nueva_cuota, @total, @UsuId);
		END
	END

	-- Póliza.
	DECLARE @partida dbo.cont_asiento_det_type, @asi_id INT;
	IF @TipoNota = 'NCC'
	BEGIN
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_contrapartida, @neto, 0, @referencia);
		IF @iva > 0 INSERT INTO @partida VALUES (@cta_iva_debito, @iva, 0, @referencia);
		INSERT INTO @partida VALUES (@cta_clientes, 0, @total, @referencia);
		IF @costo_devolucion > 0
			INSERT INTO @partida VALUES (@cta_inventario, @costo_devolucion, 0, CONCAT(@referencia, ' - reingreso')),
										(@cta_costo, 0, @costo_devolucion, CONCAT(@referencia, ' - reingreso'));
	END
	ELSE IF @TipoNota = 'NDC'
	BEGIN
		INSERT INTO @partida VALUES (@cta_clientes, @total, 0, @referencia), (@cta_contrapartida, 0, @neto, @referencia);
		IF @iva > 0 INSERT INTO @partida VALUES (@cta_iva_debito, 0, @iva, @referencia);
	END
	ELSE IF @TipoNota = 'NCP'
	BEGIN
		INSERT INTO @partida VALUES (@cta_proveedores, @total, 0, @referencia);
		IF @neto_devolucion > 0 INSERT INTO @partida VALUES (@cta_inventario, 0, @neto_devolucion, CONCAT(@referencia, ' - devolución'));
		IF @neto - @neto_devolucion > 0 INSERT INTO @partida VALUES (@cta_contrapartida, 0, @neto - @neto_devolucion, @referencia);
		IF @iva > 0 INSERT INTO @partida VALUES (@cta_iva_credito, 0, @iva, @referencia);
	END
	ELSE
	BEGIN
		INSERT INTO @partida VALUES (@cta_contrapartida, @neto, 0, @referencia);
		IF @iva > 0 INSERT INTO @partida VALUES (@cta_iva_credito, @iva, 0, @referencia);
		INSERT INTO @partida VALUES (@cta_proveedores, 0, @total, @referencia);
	END

	DECLARE @origen VARCHAR(20) = CASE WHEN @es_credito = 1 THEN 'NOTA_CREDITO' ELSE 'NOTA_DEBITO' END;
	DECLARE @descripcion VARCHAR(256) = CONCAT(@referencia, ' - ', LTRIM(RTRIM(@Motivo)));
	EXEC dbo.sp_contabilidad_insertar_asiento
		@asi_fecha = @Fecha, @asi_descripcion = @descripcion, @asi_origen = @origen, @asi_origen_id = @EncId, @enc_id = @EncId,
		@usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;

	COMMIT TRANSACTION;
END;
GO

-- Anular: las notas no se anulan (se corrige con la nota contraria) y un
-- documento con notas tampoco, porque su plan de pagos ya las incluye.
CREATE OR ALTER PROCEDURE [dbo].[sp_documento_anular]
	@enc_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado_actual CHAR(1), @es_nota BIT;
	SELECT @estado_actual = enca.enc_estado, @es_nota = tipo.tdo_es_nota
	FROM dbo.inv_documento_enc enca INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @enc_id;

	IF @estado_actual IS NULL
		THROW 51421, 'El documento indicado no existe.', 1;
	IF @estado_actual <> 'G'
		THROW 51422, 'Solo se pueden anular documentos que estén en estado Grabado.', 1;
	IF @es_nota = 1
		THROW 51423, 'Una nota de crédito o débito no se anula; emita la nota contraria.', 1;
	IF EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_id_referencia = @enc_id AND enc_estado = 'G')
		THROW 51424, 'El documento tiene notas de crédito o débito; no se puede anular.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		EXEC dbo.sp_inventario_ajustar_existencia_documento @enc_id = @enc_id, @reversar = 1, @usu_id = @usu_id;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'A',
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @enc_id;

		UPDATE dbo.cont_asiento_enc
		   SET asi_estado = 'N',
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @enc_id;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 3. Cobro de cuota y pago con cheque con validación del saldo
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_pos_registrar_pago_cuota]
	@cpp_id			INT,
	@valor_pago		NUMERIC(12, 2),
	@pca_id			INT,
	@usu_id			INT = NULL,
	@formas_pago	dbo.pago_forma_type READONLY,	-- pasar tabla vacía si no aplica
	@ppe_id			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @valor_pago <= 0
		THROW 51501, 'El valor del pago debe ser mayor a cero.', 1;

	DECLARE @cli_id INT, @saldo NUMERIC(12, 2), @estado CHAR(1), @enc_id INT;
	SELECT @cli_id = cli_id, @saldo = cpp_saldo_cuota, @estado = cpp_estado, @enc_id = enc_id
	FROM dbo.pos_cliente_plan_pagos WHERE cpp_id = @cpp_id;

	IF @cli_id IS NULL
		THROW 51502, 'La cuota indicada no existe.', 1;
	IF @estado = 'A' OR @saldo <= 0
		THROW 51503, 'La cuota indicada ya está abonada por completo.', 1;
	IF @valor_pago > @saldo
	BEGIN
		DECLARE @msg NVARCHAR(200) = CONCAT(N'El pago (Q', FORMAT(@valor_pago, 'N2'), N') supera el saldo de la cuota (Q', FORMAT(@saldo, 'N2'), N').');
		THROW 51504, @msg, 1;
	END
	IF EXISTS (SELECT 1 FROM @formas_pago) AND (SELECT SUM(ppf_monto) FROM @formas_pago) <> @valor_pago
		THROW 51505, 'La suma de las formas de pago debe ser igual al valor del pago.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id AND pca_estado = 'A')
		THROW 51506, 'No hay una caja abierta para recibir el pago.', 1;
	IF EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_id = @enc_id AND enc_estado <> 'G')
		THROW 51507, 'La factura de esa cuota está anulada.', 1;

	DECLARE @cta_caja INT, @cta_clientes INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'COBRO_CAJA', @CtaId = @cta_caja OUTPUT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'COBRO_CLIENTES', @CtaId = @cta_clientes OUTPUT;

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

		DECLARE @asi_id INT, @detalle dbo.cont_asiento_det_type, @fecha_hoy DATE = CAST(GETDATE() AS DATE);
		DECLARE @referencia VARCHAR(64) = CONCAT('Recibo ', @ppe_id, ' - cuota ', @cpp_id);
		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_caja, @valor_pago, 0, @referencia), (@cta_clientes, 0, @valor_pago, @referencia);

		EXEC dbo.sp_contabilidad_insertar_asiento
			@asi_fecha = @fecha_hoy, @asi_descripcion = 'Cobro cuota de cliente',
			@asi_origen = 'PAGO_CLIENTE', @asi_origen_id = @ppe_id, @enc_id = @enc_id,
			@usu_id = @usu_id, @detalle = @detalle, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_bancos_emitir_cheque_pago_proveedor]
	@ppg_id				INT,
	@cbc_id				INT,
	@bce_numero_cheque	VARCHAR(16),
	@valor_pago			NUMERIC(12, 2),
	@bmp_id				INT = NULL,
	@usu_id				INT = NULL,
	@bce_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @valor_pago <= 0
		THROW 51601, 'El valor del pago debe ser mayor a cero.', 1;
	IF ISNULL(LTRIM(RTRIM(@bce_numero_cheque)), '') = ''
		THROW 51605, 'Ingrese el número de cheque.', 1;

	DECLARE @enc_id INT, @valor_programado NUMERIC(12, 2), @valor_pagado NUMERIC(12, 2), @estado CHAR(1);
	SELECT @enc_id = enc_id, @valor_programado = ppg_valor_pago, @valor_pagado = ISNULL(ppg_valor_real_pago, 0), @estado = ppg_estado
	FROM dbo.inv_proveedor_plan_pago WHERE ppg_id = @ppg_id;

	IF @enc_id IS NULL
		THROW 51602, 'La cuota de proveedor indicada no existe.', 1;
	IF @estado = 'A' OR @valor_programado - @valor_pagado <= 0
		THROW 51603, 'La cuota de proveedor indicada ya está pagada por completo.', 1;
	IF @valor_pago > @valor_programado - @valor_pagado
	BEGIN
		DECLARE @msg NVARCHAR(200) = CONCAT(N'El pago (Q', FORMAT(@valor_pago, 'N2'), N') supera el saldo de la cuota (Q',
			FORMAT(@valor_programado - @valor_pagado, 'N2'), N').');
		THROW 51604, @msg, 1;
	END
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @cbc_id)
		THROW 51606, 'La chequera indicada no existe.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_enc WHERE cbc_id = @cbc_id AND bce_numero_cheque = @bce_numero_cheque)
		THROW 51607, 'Ese número de cheque ya fue emitido en la chequera.', 1;

	DECLARE @cta_proveedores INT, @cta_bancos INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_PROVEEDORES', @CtaId = @cta_proveedores OUTPUT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_bancos OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.bco_cheque_emitido_enc
			(cbc_id, bce_fecha_emision, usu_id, bce_numero_cheque, bce_documento_ref, bce_valor, bmp_id, InsUsuario, InsFechaHora)
		VALUES
			(@cbc_id, CAST(GETDATE() AS DATE), @usu_id, @bce_numero_cheque, CAST(@enc_id AS VARCHAR(16)), @valor_pago, @bmp_id, @usu_id, SYSDATETIME());

		SET @bce_id = SCOPE_IDENTITY();

		INSERT INTO dbo.bco_cheque_emitido_det (bce_id, bmp_id, enc_id, ced_valor, ced_abono_cancelacion, InsUsuario, InsFechaHora)
		VALUES (@bce_id, @bmp_id, @enc_id, @valor_pago,
				CASE WHEN @valor_pagado + @valor_pago >= @valor_programado THEN 'C' ELSE 'A' END,
				@usu_id, SYSDATETIME());

		UPDATE dbo.inv_proveedor_plan_pago
		   SET ppg_valor_real_pago = @valor_pagado + @valor_pago,
			   ppg_fecha_real_pago = CAST(GETDATE() AS DATE),
			   ppg_numero_cheque = @bce_numero_cheque,
			   cbc_id = @cbc_id,
			   ppg_estado = CASE WHEN @valor_pagado + @valor_pago >= @valor_programado THEN 'A' ELSE ppg_estado END,
			   UpdUsuario = @usu_id,
			   UpdFechaHora = SYSDATETIME()
		 WHERE ppg_id = @ppg_id;

		DECLARE @asi_id INT, @detalle dbo.cont_asiento_det_type, @fecha_hoy DATE = CAST(GETDATE() AS DATE);
		DECLARE @referencia VARCHAR(64) = 'Pago a proveedor - cheque ' + @bce_numero_cheque;
		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_proveedores, @valor_pago, 0, @referencia), (@cta_bancos, 0, @valor_pago, @referencia);

		DECLARE @asi_descripcion VARCHAR(256) = 'Pago a proveedor con cheque ' + @bce_numero_cheque;
		EXEC dbo.sp_contabilidad_insertar_asiento
			@asi_fecha = @fecha_hoy, @asi_descripcion = @asi_descripcion,
			@asi_origen = 'PAGO_PROVEEDOR', @asi_origen_id = @bce_id, @enc_id = @enc_id,
			@usu_id = @usu_id, @detalle = @detalle, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 4. Consultas de cuentas por cobrar
------------------------------------------------------------
-- Facturas del cliente con total, pagos, notas y saldo.
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

-- Movimientos del cliente con saldo corrido. El saldo inicial es lo
-- acumulado antes de @Desde.
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
	INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id
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

-- Antigüedad de saldos por vencimiento de cada cuota a la fecha de corte.
CREATE OR ALTER PROCEDURE [dbo].[paCxcAntiguedadConsultar]
	@FechaCorte	DATE = NULL,
	@CliId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @FechaCorte = ISNULL(@FechaCorte, CAST(GETDATE() AS DATE));

	SELECT clie.cli_id AS Id, clie.cli_codigo AS Codigo, CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos) AS Nombre,
		   enca.enc_id, ISNULL(enca.enc_numero_unico, CONCAT(enca.enc_serie_docto, '-', enca.enc_numero_docto)) AS Documento,
		   enca.enc_fecha_docto AS FechaDocumento, cuot.cpp_nro_cuota AS Cuota, cuot.cpp_fecha_maxima_pago AS Vencimiento,
		   dias.Dias, cuot.cpp_saldo_cuota AS Saldo,
		   CASE WHEN dias.Dias <= 0 THEN cuot.cpp_saldo_cuota ELSE 0 END AS NoVencido,
		   CASE WHEN dias.Dias BETWEEN 1 AND 30 THEN cuot.cpp_saldo_cuota ELSE 0 END AS De1a30,
		   CASE WHEN dias.Dias BETWEEN 31 AND 60 THEN cuot.cpp_saldo_cuota ELSE 0 END AS De31a60,
		   CASE WHEN dias.Dias BETWEEN 61 AND 90 THEN cuot.cpp_saldo_cuota ELSE 0 END AS De61a90,
		   CASE WHEN dias.Dias > 90 THEN cuot.cpp_saldo_cuota ELSE 0 END AS Mas90
	FROM dbo.pos_cliente_plan_pagos cuot
	INNER JOIN dbo.inv_documento_enc enca ON enca.enc_id = cuot.enc_id AND enca.enc_estado = 'G'
	INNER JOIN dbo.pos_cliente clie ON clie.cli_id = enca.cli_id
	CROSS APPLY (SELECT DATEDIFF(DAY, cuot.cpp_fecha_maxima_pago, @FechaCorte) AS Dias) dias
	WHERE cuot.cpp_saldo_cuota > 0
	  AND enca.enc_fecha_docto <= @FechaCorte
	  AND (@CliId IS NULL OR clie.cli_id = @CliId)
	ORDER BY Nombre, enca.enc_fecha_docto, enca.enc_id, cuot.cpp_nro_cuota;
END;
GO

------------------------------------------------------------
-- 5. Consultas de cuentas por pagar
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paProveedorPlanPagosConsultar]
	@EncId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT ppg_id, ppg_nro_pago, ppg_fecha_pago, ppg_valor_pago, ISNULL(ppg_valor_real_pago, 0) AS ppg_valor_real_pago,
		   ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0) AS Saldo, ppg_fecha_real_pago, ppg_numero_cheque, ppg_estado, enc_id, prv_id
	FROM dbo.inv_proveedor_plan_pago
	WHERE enc_id = @EncId
	ORDER BY ppg_nro_pago;
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
	OUTER APPLY (SELECT SUM(chdt.ced_valor) AS Pagado FROM dbo.bco_cheque_emitido_det chdt WHERE chdt.enc_id = enca.enc_id) pago
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
	INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = chdt.bce_id
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

CREATE OR ALTER PROCEDURE [dbo].[paCxpAntiguedadConsultar]
	@FechaCorte	DATE = NULL,
	@PrvId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @FechaCorte = ISNULL(@FechaCorte, CAST(GETDATE() AS DATE));

	SELECT prov.prv_id AS Id, prov.prv_codigo AS Codigo, prov.prv_nombre_comercial AS Nombre,
		   enca.enc_id, CONCAT(tipo.tdo_codigo, ' ', ISNULL(enca.enc_serie_docto + '-', ''), enca.enc_numero_docto) AS Documento,
		   enca.enc_fecha_docto AS FechaDocumento, cuot.ppg_nro_pago AS Cuota, cuot.ppg_fecha_pago AS Vencimiento,
		   dias.Dias, saldo.Saldo,
		   CASE WHEN dias.Dias <= 0 THEN saldo.Saldo ELSE 0 END AS NoVencido,
		   CASE WHEN dias.Dias BETWEEN 1 AND 30 THEN saldo.Saldo ELSE 0 END AS De1a30,
		   CASE WHEN dias.Dias BETWEEN 31 AND 60 THEN saldo.Saldo ELSE 0 END AS De31a60,
		   CASE WHEN dias.Dias BETWEEN 61 AND 90 THEN saldo.Saldo ELSE 0 END AS De61a90,
		   CASE WHEN dias.Dias > 90 THEN saldo.Saldo ELSE 0 END AS Mas90
	FROM dbo.inv_proveedor_plan_pago cuot
	INNER JOIN dbo.inv_documento_enc enca ON enca.enc_id = cuot.enc_id AND enca.enc_estado = 'G'
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = enca.prv_id
	CROSS APPLY (SELECT DATEDIFF(DAY, cuot.ppg_fecha_pago, @FechaCorte) AS Dias,
						cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) AS Pendiente) dias
	CROSS APPLY (SELECT dias.Pendiente AS Saldo) saldo
	WHERE dias.Pendiente > 0
	  AND enca.enc_fecha_docto <= @FechaCorte
	  AND (@PrvId IS NULL OR prov.prv_id = @PrvId)
	ORDER BY Nombre, enca.enc_fecha_docto, enca.enc_id, cuot.ppg_nro_pago;
END;
GO

-- Notas registradas (para los listados de CxC y CxP).
CREATE OR ALTER PROCEDURE [dbo].[paNotaConsultar]
	@EsCliente	BIT,
	@CliId		INT = NULL,
	@PrvId		INT = NULL,
	@EncIdReferencia INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT nota.enc_id, tipo.tdo_codigo, tipo.tdo_descripcion, nota.enc_fecha_docto,
		   ISNULL(nota.enc_numero_unico, nota.enc_numero_docto) AS Numero, nota.enc_motivo, nota.enc_monto_total,
		   nota.enc_id_referencia,
		   CASE WHEN @EsCliente = 1 THEN ISNULL(refe.enc_numero_unico, CONCAT(refe.enc_serie_docto, '-', refe.enc_numero_docto))
				ELSE refe.enc_numero_docto END AS DocumentoReferencia,
		   CASE WHEN @EsCliente = 1 THEN CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos) ELSE prov.prv_nombre_comercial END AS Tercero,
		   (SELECT COUNT(*) FROM dbo.inv_documento_det deta WHERE deta.enc_id = nota.enc_id AND deta.det_id_origen IS NOT NULL) AS LineasDevolucion
	FROM dbo.inv_documento_enc nota
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = nota.tdo_id AND tipo.tdo_es_nota = 1
	INNER JOIN dbo.inv_documento_enc refe ON refe.enc_id = nota.enc_id_referencia
	LEFT JOIN dbo.pos_cliente clie ON clie.cli_id = nota.cli_id
	LEFT JOIN dbo.inv_proveedor prov ON prov.prv_id = nota.prv_id
	WHERE ((@EsCliente = 1 AND tipo.tdo_codigo IN ('NCC', 'NDC')) OR (@EsCliente = 0 AND tipo.tdo_codigo IN ('NCP', 'NDP')))
	  AND (@CliId IS NULL OR nota.cli_id = @CliId)
	  AND (@PrvId IS NULL OR nota.prv_id = @PrvId)
	  AND (@EncIdReferencia IS NULL OR nota.enc_id_referencia = @EncIdReferencia)
	ORDER BY nota.enc_fecha_docto DESC, nota.enc_id DESC;
END;
GO

-- Líneas del documento que se pueden devolver, con lo ya devuelto.
CREATE OR ALTER PROCEDURE [dbo].[paDocumentoLineasDevolucionConsultar]
	@EncId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT deta.det_id, deta.det_item, deta.pro_id, prod.pro_codigo, deta.det_descripcion, deta.det_cantidad,
		   ISNULL(ante.Devuelto, 0) AS Devuelto, deta.det_cantidad - ISNULL(ante.Devuelto, 0) AS Disponible,
		   deta.det_precio_unitario, deta.det_porc_iva, deta.ume_id, unid.ume_codigo
	FROM dbo.inv_documento_det deta
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = deta.ume_id
	OUTER APPLY (SELECT SUM(prev.det_cantidad) AS Devuelto
				 FROM dbo.inv_documento_det prev
				 INNER JOIN dbo.inv_documento_enc nota ON nota.enc_id = prev.enc_id AND nota.enc_estado = 'G'
				 WHERE prev.det_id_origen = deta.det_id) ante
	WHERE deta.enc_id = @EncId
	ORDER BY deta.det_item;
END;
GO

------------------------------------------------------------
-- 6. Permisos
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT v.modulo, v.codigo, v.descripcion
FROM (VALUES
	('CXC', 'CXC_ADMIN', 'Cuentas por cobrar: estado de cuenta, cobros, notas y antigüedad de saldos'),
	('CXP', 'CXP_ADMIN', 'Cuentas por pagar: estado de cuenta, pagos, notas y antigüedad de saldos')
) v(modulo, codigo, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso perm WHERE perm.per_codigo = v.codigo);

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id, InsFechaHora)
SELECT rol.rol_id, perm.per_id, SYSDATETIME()
FROM dbo.sec_rol rol
INNER JOIN (VALUES ('ADMIN', 'CXC_ADMIN'), ('ADMIN', 'CXP_ADMIN'), ('CONTADOR', 'CXC_ADMIN'), ('CONTADOR', 'CXP_ADMIN'),
				   ('CAJERO', 'CXC_ADMIN')) v(rol, permiso) ON v.rol = rol.rol_codigo
INNER JOIN dbo.sec_permiso perm ON perm.per_codigo = v.permiso
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO
