/*
================================================================================
 52_cotizaciones.sql
 Cotizaciones a clientes con vigencia, convertibles en factura.

   - ven_cotizacion_enc / ven_cotizacion_det: la cotización con sus líneas
     (bienes y servicios) y los precios CON IVA, como se ofrecen al cliente.
   - Vigencia: gen_compania.cia_cotizacion_vigencia_dias (15 por defecto). La
     cotización vence el día fecha + vigencia; ese día todavía es válida.
   - Estados: V vigente (o vencida si ya pasó la fecha), F facturada, A anulada.
   - Conversión: paVentaFacturaCrear recibe @cot_id. Dentro de la misma
     transacción de la factura marca la cotización como facturada y le liga la
     factura; si ya venció, ya se facturó o se anuló, la factura no se graba.
     Dos usuarios no pueden facturar la misma cotización.
   - La cotización no aparta existencia: se valida al facturar.
   - Permiso VENTAS_COTIZACION (crear, duplicar y anular cotizaciones).
   - Corrección: el total de la factura se calcula como lo certifica FEL
     (precio con IVA por unidad × cantidad). Antes, con cantidades mayores a
     uno, podía diferir un centavo y la factura de contado se rechazaba.

 Errores nuevos: 54401 a 54412.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Vigencia por compañía
------------------------------------------------------------
IF COL_LENGTH('dbo.gen_compania', 'cia_cotizacion_vigencia_dias') IS NULL
	ALTER TABLE dbo.gen_compania ADD [cia_cotizacion_vigencia_dias] INT NOT NULL
		CONSTRAINT [DF_gen_compania_cotizacion_vigencia] DEFAULT (15);
GO
IF OBJECT_ID('dbo.CK_gen_compania_cotizacion_vigencia', 'C') IS NULL
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [CK_gen_compania_cotizacion_vigencia]
		CHECK ([cia_cotizacion_vigencia_dias] BETWEEN 1 AND 365);
GO

------------------------------------------------------------
-- 2. Tablas
------------------------------------------------------------
IF OBJECT_ID('dbo.ven_cotizacion_enc', 'U') IS NULL
CREATE TABLE [dbo].[ven_cotizacion_enc](
	[cot_id]				INT				IDENTITY(1, 1) NOT NULL,
	[cot_numero]			VARCHAR(16)		NOT NULL,
	[cot_fecha]				DATE			NOT NULL,
	[cot_vigencia_dias]		INT				NOT NULL,
	[cot_fecha_vencimiento]	DATE			NOT NULL,
	[suc_id]				INT				NOT NULL,
	[bod_id]				INT				NOT NULL,
	[mon_id]				INT				NOT NULL,
	[cli_id]				INT				NULL,		-- NULL: prospecto (se registra al facturar)
	[cot_nit]				VARCHAR(16)		NULL,
	[cot_nombre]			VARCHAR(256)	NOT NULL,
	[cot_direccion]			VARCHAR(256)	NULL,
	[cot_telefono]			VARCHAR(64)		NULL,
	[cot_correo]			VARCHAR(128)	NULL,
	[pve_id]				INT				NULL,
	[cot_porc_iva]			NUMERIC(8, 2)	NOT NULL,
	[cot_descuento]			NUMERIC(14, 2)	NOT NULL CONSTRAINT [DF_ven_cotizacion_enc_descuento] DEFAULT (0),
	[cot_total]				NUMERIC(14, 2)	NOT NULL,	-- con IVA, después de descuentos
	[cot_observaciones]		VARCHAR(500)	NULL,
	[cot_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_ven_cotizacion_enc_estado] DEFAULT ('V'),
	[enc_id]				INT				NULL,		-- factura en que se convirtió
	[cot_motivo_anulacion]	VARCHAR(256)	NULL,
	[usu_id]				INT				NULL,
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NULL,
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_ven_cotizacion_enc] PRIMARY KEY ([cot_id]),
	CONSTRAINT [UQ_ven_cotizacion_enc_numero] UNIQUE ([cot_numero]),
	CONSTRAINT [FK_ven_cotizacion_enc_sucursal] FOREIGN KEY ([suc_id]) REFERENCES dbo.gen_sucursal ([suc_id]),
	CONSTRAINT [FK_ven_cotizacion_enc_bodega] FOREIGN KEY ([bod_id]) REFERENCES dbo.inv_bodega ([bod_id]),
	CONSTRAINT [FK_ven_cotizacion_enc_moneda] FOREIGN KEY ([mon_id]) REFERENCES dbo.gen_moneda ([mon_id]),
	CONSTRAINT [FK_ven_cotizacion_enc_cliente] FOREIGN KEY ([cli_id]) REFERENCES dbo.pos_cliente ([cli_id]),
	CONSTRAINT [FK_ven_cotizacion_enc_vendedor] FOREIGN KEY ([pve_id]) REFERENCES dbo.pos_vendedor ([pve_id]),
	CONSTRAINT [FK_ven_cotizacion_enc_factura] FOREIGN KEY ([enc_id]) REFERENCES dbo.inv_documento_enc ([enc_id]),
	CONSTRAINT [FK_ven_cotizacion_enc_usuario] FOREIGN KEY ([usu_id]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_ven_cotizacion_enc_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_ven_cotizacion_enc_UpdUsuario] FOREIGN KEY ([UpdUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [CK_ven_cotizacion_enc_estado] CHECK ([cot_estado] IN ('V', 'F', 'A')),
	CONSTRAINT [CK_ven_cotizacion_enc_factura] CHECK (([cot_estado] = 'F' AND [enc_id] IS NOT NULL) OR ([cot_estado] <> 'F' AND [enc_id] IS NULL)),
	CONSTRAINT [CK_ven_cotizacion_enc_vigencia] CHECK ([cot_vigencia_dias] > 0 AND [cot_fecha_vencimiento] = DATEADD(DAY, [cot_vigencia_dias], [cot_fecha])),
	CONSTRAINT [CK_ven_cotizacion_enc_montos] CHECK ([cot_total] >= 0 AND [cot_descuento] >= 0)
);
GO

IF OBJECT_ID('dbo.ven_cotizacion_det', 'U') IS NULL
CREATE TABLE [dbo].[ven_cotizacion_det](
	[cod_id]				INT				IDENTITY(1, 1) NOT NULL,
	[cot_id]				INT				NOT NULL,
	[cod_item]				INT				NOT NULL,
	[cod_bien_o_servicio]	CHAR(1)			NOT NULL,
	[pro_id]				INT				NULL,
	[ppr_id]				INT				NULL,
	[ume_id]				INT				NULL,
	[cod_descripcion]		VARCHAR(256)	NOT NULL,
	[cod_cantidad]			NUMERIC(12, 4)	NOT NULL,
	[cod_precio_unitario]	NUMERIC(12, 2)	NOT NULL,	-- con IVA
	[cod_valor_descuento]	NUMERIC(12, 2)	NOT NULL CONSTRAINT [DF_ven_cotizacion_det_descuento] DEFAULT (0),
	[cod_total]				NUMERIC(14, 2)	NOT NULL,	-- cantidad × precio - descuento, con IVA
	CONSTRAINT [PK_ven_cotizacion_det] PRIMARY KEY ([cod_id]),
	CONSTRAINT [UQ_ven_cotizacion_det_item] UNIQUE ([cot_id], [cod_item]),
	CONSTRAINT [FK_ven_cotizacion_det_cotizacion] FOREIGN KEY ([cot_id]) REFERENCES dbo.ven_cotizacion_enc ([cot_id]),
	CONSTRAINT [FK_ven_cotizacion_det_producto] FOREIGN KEY ([pro_id]) REFERENCES dbo.inv_producto ([pro_id]),
	CONSTRAINT [FK_ven_cotizacion_det_precio] FOREIGN KEY ([ppr_id]) REFERENCES dbo.inv_producto_precio ([ppr_id]),
	CONSTRAINT [FK_ven_cotizacion_det_unidad] FOREIGN KEY ([ume_id]) REFERENCES dbo.inv_unidad_medida ([ume_id]),
	CONSTRAINT [CK_ven_cotizacion_det_bs] CHECK ([cod_bien_o_servicio] IN ('B', 'S')),
	CONSTRAINT [CK_ven_cotizacion_det_montos] CHECK ([cod_cantidad] > 0 AND [cod_precio_unitario] >= 0 AND [cod_valor_descuento] >= 0 AND [cod_total] >= 0)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ven_cotizacion_enc_fecha')
	CREATE INDEX [IX_ven_cotizacion_enc_fecha] ON dbo.ven_cotizacion_enc ([cot_fecha]) INCLUDE ([cot_estado], [suc_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ven_cotizacion_enc_cliente')
	CREATE INDEX [IX_ven_cotizacion_enc_cliente] ON dbo.ven_cotizacion_enc ([cli_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ven_cotizacion_enc_factura')
	CREATE INDEX [IX_ven_cotizacion_enc_factura] ON dbo.ven_cotizacion_enc ([enc_id]);
GO

IF TYPE_ID('dbo.cotizacion_det_type') IS NULL
	CREATE TYPE dbo.cotizacion_det_type AS TABLE (
		item				INT				NOT NULL PRIMARY KEY,
		bien_o_servicio		CHAR(1)			NOT NULL,
		pro_id				INT				NULL,
		ppr_id				INT				NULL,
		ume_id				INT				NULL,
		descripcion			VARCHAR(256)	NOT NULL,
		cantidad			NUMERIC(12, 4)	NOT NULL,
		precio_unitario		NUMERIC(12, 2)	NOT NULL,	-- con IVA
		valor_descuento		NUMERIC(12, 2)	NOT NULL
	);
GO

------------------------------------------------------------
-- 3. Grabar, consultar y anular
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCotizacionGuardar]
	@Fecha			DATE,
	@BodId			INT,
	@MonId			INT = NULL,
	@CliId			INT = NULL,
	@Nit			VARCHAR(16) = NULL,
	@Nombre			VARCHAR(256) = NULL,
	@Direccion		VARCHAR(256) = NULL,
	@Telefono		VARCHAR(64) = NULL,
	@Correo			VARCHAR(128) = NULL,
	@PveId			INT = NULL,
	@Observaciones	VARCHAR(500) = NULL,
	@UsuId			INT = NULL,
	@Detalle		dbo.cotizacion_det_type READONLY,
	@CotId			INT OUTPUT,
	@Numero			VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SELECT @CotId = NULL, @Numero = NULL;

	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 54401, 'La cotización debe tener al menos una línea.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE bien_o_servicio NOT IN ('B', 'S'))
		THROW 54402, 'Cada línea debe ser bien (B) o servicio (S).', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE bien_o_servicio = 'B' AND pro_id IS NULL)
		THROW 54403, 'Una línea de bien debe indicar el producto.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE LTRIM(RTRIM(descripcion)) = '')
		THROW 54404, 'Toda línea debe tener descripción.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE cantidad <= 0 OR precio_unitario < 0 OR valor_descuento < 0
				OR valor_descuento > ROUND(cantidad * precio_unitario, 2))
		THROW 54405, 'La cantidad debe ser mayor a cero, el precio no negativo y el descuento no mayor que el valor de la línea.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle deta INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
			   WHERE prod.pro_maneja_existencia = 1 AND deta.cantidad <> ROUND(deta.cantidad, 0))
		THROW 54406, 'Los productos con existencia se cotizan en cantidades enteras.', 1;

	DECLARE @suc_id INT, @cia_id INT, @vigencia INT, @iva NUMERIC(8, 2);
	SELECT @suc_id = bode.suc_id, @cia_id = sucu.cia_id, @vigencia = comp.cia_cotizacion_vigencia_dias, @iva = comp.cia_porc_iva
	FROM dbo.inv_bodega bode
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	WHERE bode.bod_id = @BodId AND bode.bod_estado = 'A';
	IF @suc_id IS NULL
		THROW 54407, 'Elija una bodega activa.', 1;

	-- Datos del cliente: los de su ficha si no se escribieron otros.
	IF @CliId IS NOT NULL
		SELECT @Nombre = ISNULL(NULLIF(LTRIM(RTRIM(@Nombre)), ''), LTRIM(RTRIM(CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos)))),
			   @Nit = ISNULL(NULLIF(LTRIM(RTRIM(@Nit)), ''), clie.cli_nit),
			   @Direccion = ISNULL(NULLIF(LTRIM(RTRIM(@Direccion)), ''), clie.cli_direccion),
			   @Telefono = ISNULL(NULLIF(LTRIM(RTRIM(@Telefono)), ''), COALESCE(clie.cli_telefono_celular, clie.cli_telefono_casa, clie.cli_telefono_trabajo)),
			   @Correo = ISNULL(NULLIF(LTRIM(RTRIM(@Correo)), ''), clie.cli_email)
		FROM dbo.pos_cliente clie WHERE clie.cli_id = @CliId;
	IF ISNULL(LTRIM(RTRIM(@Nombre)), '') = ''
		THROW 54408, 'Indique el cliente o el nombre a quien se dirige la cotización.', 1;

	SET @MonId = ISNULL(@MonId, dbo.fnMonedaLocal());
	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));

	DECLARE @descuento NUMERIC(14, 2) = (SELECT SUM(valor_descuento) FROM @Detalle),
			@total NUMERIC(14, 2) = (SELECT SUM(ROUND(cantidad * precio_unitario, 2) - valor_descuento) FROM @Detalle);

	BEGIN TRANSACTION;
	DECLARE @siguiente INT = ISNULL((SELECT MAX(CAST(SUBSTRING(cot_numero, 5, 12) AS INT)) FROM dbo.ven_cotizacion_enc WITH (UPDLOCK, HOLDLOCK)), 0) + 1;
	INSERT INTO dbo.ven_cotizacion_enc
		(cot_numero, cot_fecha, cot_vigencia_dias, cot_fecha_vencimiento, suc_id, bod_id, mon_id, cli_id, cot_nit, cot_nombre,
		 cot_direccion, cot_telefono, cot_correo, pve_id, cot_porc_iva, cot_descuento, cot_total, cot_observaciones, cot_estado,
		 usu_id, InsUsuario, InsFechaHora)
	VALUES
		(CONCAT('COT-', RIGHT(CONCAT('000000', @siguiente), 6)), @Fecha, @vigencia, DATEADD(DAY, @vigencia, @Fecha), @suc_id, @BodId,
		 @MonId, @CliId, NULLIF(UPPER(LTRIM(RTRIM(@Nit))), ''), LTRIM(RTRIM(@Nombre)), NULLIF(LTRIM(RTRIM(@Direccion)), ''),
		 NULLIF(LTRIM(RTRIM(@Telefono)), ''), NULLIF(LTRIM(RTRIM(@Correo)), ''), @PveId, @iva, @descuento, @total,
		 NULLIF(LTRIM(RTRIM(@Observaciones)), ''), 'V', @UsuId, @UsuId, SYSDATETIME());
	SET @CotId = SCOPE_IDENTITY();

	INSERT INTO dbo.ven_cotizacion_det
		(cot_id, cod_item, cod_bien_o_servicio, pro_id, ppr_id, ume_id, cod_descripcion, cod_cantidad, cod_precio_unitario,
		 cod_valor_descuento, cod_total)
	SELECT @CotId, ROW_NUMBER() OVER (ORDER BY deta.item), deta.bien_o_servicio, deta.pro_id, deta.ppr_id,
		   COALESCE(deta.ume_id, prod.ume_id), LTRIM(RTRIM(deta.descripcion)), deta.cantidad, deta.precio_unitario,
		   deta.valor_descuento, ROUND(deta.cantidad * deta.precio_unitario, 2) - deta.valor_descuento
	FROM @Detalle deta
	LEFT JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id;

	SELECT @Numero = cot_numero FROM dbo.ven_cotizacion_enc WHERE cot_id = @CotId;
	COMMIT;
END;
GO

-- Lista de cotizaciones. Estado efectivo: X = vigente pero ya vencida.
-- @Estado: V vigentes (sin vencer), X vencidas, F facturadas, A anuladas, NULL todas.
CREATE OR ALTER PROCEDURE [dbo].[paCotizacionConsultar]
	@SucId	INT = NULL,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL,
	@Estado	CHAR(1) = NULL,
	@Texto	VARCHAR(100) = NULL
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
	SET @Texto = NULLIF(LTRIM(RTRIM(@Texto)), '');

	SELECT coti.cot_id AS CotId, coti.cot_numero AS Numero, coti.cot_fecha AS Fecha, coti.cot_fecha_vencimiento AS Vence,
		   coti.cot_vigencia_dias AS VigenciaDias,
		   CASE WHEN coti.cot_estado = 'V' AND coti.cot_fecha_vencimiento < @hoy THEN 'X' ELSE coti.cot_estado END AS Estado,
		   CASE WHEN coti.cot_estado = 'V' THEN DATEDIFF(DAY, @hoy, coti.cot_fecha_vencimiento) END AS DiasRestantes,
		   coti.cli_id AS CliId, coti.cot_nombre AS Cliente, coti.cot_nit AS Nit,
		   NULLIF(LTRIM(RTRIM(CONCAT(vend.pve_nombres, ' ', vend.pve_apellidos))), '') AS Vendedor,
		   ISNULL(mone.mon_simbolo, 'Q') AS Simbolo, coti.cot_total AS Total,
		   coti.enc_id AS EncId, fact.enc_numero_unico AS Factura, sucu.suc_descripcion AS Sucursal
	FROM dbo.ven_cotizacion_enc coti
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = coti.suc_id
	LEFT JOIN dbo.pos_vendedor vend ON vend.pve_id = coti.pve_id
	LEFT JOIN dbo.gen_moneda mone ON mone.mon_id = coti.mon_id
	LEFT JOIN dbo.inv_documento_enc fact ON fact.enc_id = coti.enc_id
	WHERE (@SucId IS NULL OR coti.suc_id = @SucId)
	  AND (@Desde IS NULL OR coti.cot_fecha >= @Desde)
	  AND (@Hasta IS NULL OR coti.cot_fecha <= @Hasta)
	  AND (@Estado IS NULL
		   OR (@Estado = 'V' AND coti.cot_estado = 'V' AND coti.cot_fecha_vencimiento >= @hoy)
		   OR (@Estado = 'X' AND coti.cot_estado = 'V' AND coti.cot_fecha_vencimiento < @hoy)
		   OR (@Estado IN ('F', 'A') AND coti.cot_estado = @Estado))
	  AND (@Texto IS NULL OR coti.cot_numero LIKE '%' + @Texto + '%' OR coti.cot_nombre LIKE '%' + @Texto + '%'
		   OR coti.cot_nit LIKE '%' + @Texto + '%')
	ORDER BY coti.cot_id DESC;
END;
GO

-- Una cotización: encabezado (con los datos del emisor para imprimirla) y líneas
-- (con la existencia actual en la bodega, para avisar antes de facturar).
CREATE OR ALTER PROCEDURE [dbo].[paCotizacionConsultarPorId]
	@CotId	INT
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @hoy DATE = CAST(GETDATE() AS DATE);

	SELECT coti.cot_id AS CotId, coti.cot_numero AS Numero, coti.cot_fecha AS Fecha, coti.cot_fecha_vencimiento AS Vence,
		   coti.cot_vigencia_dias AS VigenciaDias,
		   CASE WHEN coti.cot_estado = 'V' AND coti.cot_fecha_vencimiento < @hoy THEN 'X' ELSE coti.cot_estado END AS Estado,
		   CASE WHEN coti.cot_estado = 'V' THEN DATEDIFF(DAY, @hoy, coti.cot_fecha_vencimiento) END AS DiasRestantes,
		   coti.suc_id AS SucId, coti.bod_id AS BodId, coti.mon_id AS MonId, coti.pve_id AS PveId,
		   coti.cli_id AS CliId, coti.cot_nit AS Nit, coti.cot_nombre AS Cliente, coti.cot_direccion AS Direccion,
		   coti.cot_telefono AS Telefono, coti.cot_correo AS Correo, clie.cli_codigo AS ClienteCodigo,
		   NULLIF(LTRIM(RTRIM(CONCAT(vend.pve_nombres, ' ', vend.pve_apellidos))), '') AS Vendedor,
		   coti.cot_porc_iva AS PorcentajeIva, coti.cot_descuento AS Descuento, coti.cot_total AS Total,
		   ROUND(coti.cot_total * coti.cot_porc_iva / (100 + coti.cot_porc_iva), 2) AS IvaIncluido,
		   coti.cot_observaciones AS Observaciones, coti.cot_motivo_anulacion AS MotivoAnulacion,
		   coti.enc_id AS EncId, fact.enc_numero_unico AS Factura,
		   ISNULL(mone.mon_codigo, 'GTQ') AS Moneda, ISNULL(mone.mon_simbolo, 'Q') AS Simbolo,
		   bode.bod_descripcion AS Bodega, usua.usu_codigo AS Usuario,
		   -- Emisor
		   comp.cia_id AS CiaId, comp.cia_nit AS NitEmisor, ISNULL(comp.cia_fel_nombre_emisor, comp.cia_nombre_comercial) AS NombreEmisor,
		   ISNULL(sucu.suc_fel_nombre_comercial, comp.cia_nombre_comercial) AS NombreComercial,
		   ISNULL(sucu.suc_direccion, comp.cia_direccion) AS DireccionEmisor, ISNULL(sucu.suc_telefono, comp.cia_telefono) AS TelefonoEmisor,
		   ISNULL(comp.cia_fel_correo_emisor, comp.cia_email) AS CorreoEmisor, sucu.suc_descripcion AS Sucursal,
		   CAST(CASE WHEN comp.cia_logo IS NULL THEN 0 ELSE 1 END AS BIT) AS TieneLogo, comp.cia_logo_actualizado AS LogoActualizado
	FROM dbo.ven_cotizacion_enc coti
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = coti.suc_id
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	INNER JOIN dbo.inv_bodega bode ON bode.bod_id = coti.bod_id
	LEFT JOIN dbo.pos_cliente clie ON clie.cli_id = coti.cli_id
	LEFT JOIN dbo.pos_vendedor vend ON vend.pve_id = coti.pve_id
	LEFT JOIN dbo.gen_moneda mone ON mone.mon_id = coti.mon_id
	LEFT JOIN dbo.inv_documento_enc fact ON fact.enc_id = coti.enc_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = coti.usu_id
	WHERE coti.cot_id = @CotId;

	SELECT deta.cod_item AS Item, deta.cod_bien_o_servicio AS BienOServicio, deta.pro_id AS ProId, deta.ppr_id AS PprId,
		   deta.ume_id AS UmeId, ISNULL(unid.ume_codigo, 'UND') AS Unidad, prod.pro_codigo AS Codigo,
		   deta.cod_descripcion AS Descripcion, deta.cod_cantidad AS Cantidad, deta.cod_precio_unitario AS PrecioUnitario,
		   deta.cod_valor_descuento AS Descuento, deta.cod_total AS Total,
		   CAST(ISNULL(prod.pro_maneja_existencia, 0) AS BIT) AS ManejaExistencia, prod.pro_costo_unitario AS CostoUnitario,
		   exis.existencia AS Existencia
	FROM dbo.ven_cotizacion_det deta
	INNER JOIN dbo.ven_cotizacion_enc coti ON coti.cot_id = deta.cot_id
	LEFT JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = deta.ume_id
	LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = deta.pro_id AND exis.bod_id = coti.bod_id
	WHERE deta.cot_id = @CotId
	ORDER BY deta.cod_item;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCotizacionAnular]
	@CotId	INT,
	@Motivo	VARCHAR(256),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(LTRIM(RTRIM(@Motivo)), '') = ''
		THROW 54409, 'Indique el motivo de la anulación.', 1;
	UPDATE dbo.ven_cotizacion_enc
	   SET cot_estado = 'A', cot_motivo_anulacion = LTRIM(RTRIM(@Motivo)), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cot_id = @CotId AND cot_estado = 'V';
	IF @@ROWCOUNT = 0
		THROW 54410, 'Solo se anula una cotización que no se ha facturado ni anulado.', 1;
END;
GO

-- Vigencia y configuración de impresión de la compañía (amplía el 48).
CREATE OR ALTER PROCEDURE [dbo].[paCompaniaImpresionConsultar]
	@CiaId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cia_id AS CiaId, cia_factura_impresora AS Impresora, cia_factura_ancho_termica AS AnchoTermica, cia_factura_pie AS Pie,
		   cia_cotizacion_vigencia_dias AS VigenciaCotizacion
	FROM dbo.gen_compania
	WHERE cia_id = @CiaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaImpresionGuardar]
	@CiaId				INT,
	@Impresora			CHAR(1),
	@AnchoTermica		TINYINT = 80,
	@Pie				VARCHAR(256) = NULL,
	@VigenciaCotizacion	INT = NULL,
	@UsuId				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_id = @CiaId)
		THROW 54001, 'La compañía no existe.', 1;
	IF ISNULL(@Impresora, '') NOT IN ('C', 'T')
		THROW 54002, 'Elija la impresora de la factura: C (carta) o T (térmica).', 1;
	IF ISNULL(@AnchoTermica, 0) NOT IN (58, 80)
		THROW 54003, 'El ancho del rollo de la impresora térmica debe ser 58 u 80 mm.', 1;
	IF @VigenciaCotizacion IS NOT NULL AND @VigenciaCotizacion NOT BETWEEN 1 AND 365
		THROW 54411, 'La vigencia de las cotizaciones debe estar entre 1 y 365 días.', 1;
	UPDATE dbo.gen_compania
	   SET cia_factura_impresora = @Impresora, cia_factura_ancho_termica = @AnchoTermica,
		   cia_factura_pie = NULLIF(LTRIM(RTRIM(@Pie)), ''),
		   cia_cotizacion_vigencia_dias = ISNULL(@VigenciaCotizacion, cia_cotizacion_vigencia_dias),
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cia_id = @CiaId;
END;
GO

------------------------------------------------------------
-- 4. Factura desde una cotización (paVentaFacturaCrear con @cot_id)
------------------------------------------------------------
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
	@EncNumeroUnico			VARCHAR(16) OUTPUT,
	@CotId						INT = NULL				-- cotización que se convierte en esta factura (script 52)
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

	-- El total del documento es el que certifica FEL: precio unitario con IVA
	-- redondeado a centavos × cantidad, menos el descuento con IVA (ver
	-- FelXmlBuilder.Calcular). Antes se sumaba el IVA al neto de la línea y,
	-- con cantidades mayores a uno, el total podía quedar un centavo abajo o
	-- arriba del que ve el cliente. El asiento sigue cuadrado: el ingreso es
	-- el total menos el IVA (paContabilidadAsientoDocumentoGenerar).
	DECLARE @monto_total NUMERIC(12, 2) = (
		SELECT SUM(ROUND(ROUND(det_precio_unitario * (1 + ISNULL(det_porc_iva, 0) / 100.0), 2) * det_cantidad, 2)
				 - ROUND(det_valor_descuento * (1 + ISNULL(det_porc_iva, 0) / 100.0), 2))
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

		-- Factura desde una cotización: solo una vigente (hoy no ha pasado su
		-- fecha de vencimiento) y que nadie más haya facturado o anulado.
		IF @CotId IS NOT NULL
		BEGIN
			UPDATE dbo.ven_cotizacion_enc
			   SET cot_estado = 'F', enc_id = @EncId, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
			 WHERE cot_id = @CotId AND cot_estado = 'V' AND cot_fecha_vencimiento >= CAST(GETDATE() AS DATE);
			IF @@ROWCOUNT = 0
				THROW 54412, 'La cotización ya venció, ya se facturó o está anulada: no se puede convertir en factura. Haga una cotización nueva.', 1;
		END

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

------------------------------------------------------------
-- 5. Permiso
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT v.modulo, v.codigo, v.descripcion
FROM (VALUES ('VENTAS', 'VENTAS_COTIZACION', 'Cotizaciones: crear, duplicar y anular')) v (modulo, codigo, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso perm WHERE perm.per_codigo = v.codigo);
GO

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT rol.rol_id, perm.per_id
FROM (VALUES ('Administrador', 'VENTAS_COTIZACION'), ('Vendedor', 'VENTAS_COTIZACION')) v (rol, permiso)
INNER JOIN dbo.sec_rol rol ON rol.rol_nombre = v.rol
INNER JOIN dbo.sec_permiso perm ON perm.per_codigo = v.permiso
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO

PRINT '52_cotizaciones.sql aplicado.';
GO
