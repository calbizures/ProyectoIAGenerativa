------------------------------------------------------------------------------
-- 31_sucursales_unidades_organigrama.sql
--
--   1. Sucursales y bodegas: procedimientos para su mantenimiento. Una
--      sucursal tiene una o más bodegas (inv_bodega.suc_id ya lo exigía).
--   2. Unidades de medida: catálogo inv_unidad_medida. El producto tiene una
--      unidad por defecto y cada línea de documento guarda la suya.
--   3. Factura con líneas de bien o servicio: el detalle acepta cantidades
--      con decimales (p. ej. 1.5 horas) y la unidad de medida. Una línea de
--      servicio no necesita producto: basta la descripción.
--   4. Unidades organizativas recursivas: cada unidad puede colgar de otra
--      (Junta Directiva > Gerencias > ...). Mantenimiento por nodos y
--      consulta del organigrama con departamentos, plazas y empleados.
--
-- Requiere 25. Se puede volver a correr.
------------------------------------------------------------------------------

USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Sucursales y bodegas
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paSucursalConsultar]
	@CiaId			INT = NULL,
	@SoloActivas	BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT sucu.suc_id, sucu.suc_codigo, sucu.suc_descripcion, sucu.suc_direccion, sucu.suc_telefono,
		   sucu.cia_id, comp.cia_nombre_comercial, sucu.suc_estado,
		   (SELECT COUNT(*) FROM dbo.inv_bodega bode WHERE bode.suc_id = sucu.suc_id) AS CantidadBodegas
	FROM dbo.gen_sucursal sucu
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	WHERE (@CiaId IS NULL OR sucu.cia_id = @CiaId)
	  AND (@SoloActivas = 0 OR sucu.suc_estado = 'A')
	ORDER BY comp.cia_nombre_comercial, sucu.suc_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paSucursalGuardar]
	@SucId			INT = NULL,
	@CiaId			INT,
	@Codigo			VARCHAR(8),
	@Descripcion	VARCHAR(128),
	@Direccion		VARCHAR(128) = NULL,
	@Telefono		VARCHAR(16) = NULL,
	@UsuId			INT = NULL,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET @Codigo = UPPER(LTRIM(RTRIM(@Codigo)));
	SET @Descripcion = LTRIM(RTRIM(@Descripcion));

	IF ISNULL(@Codigo, '') = '' OR ISNULL(@Descripcion, '') = ''
		THROW 53001, 'Ingrese el código y la descripción de la sucursal.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_id = @CiaId)
		THROW 53002, 'La compañía indicada no existe.', 1;
	IF EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE cia_id = @CiaId AND suc_codigo = @Codigo AND suc_id <> ISNULL(@SucId, 0))
		THROW 53003, 'Ya existe una sucursal con ese código en la compañía.', 1;

	IF @SucId IS NULL
	BEGIN
		INSERT INTO dbo.gen_sucursal (suc_codigo, suc_descripcion, suc_direccion, suc_telefono, cia_id, InsUsuario, InsFechaHora)
		VALUES (@Codigo, @Descripcion, @Direccion, @Telefono, @CiaId, @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE suc_id = @SucId)
			THROW 53004, 'La sucursal indicada no existe.', 1;
		UPDATE dbo.gen_sucursal
		   SET suc_codigo = @Codigo, suc_descripcion = @Descripcion, suc_direccion = @Direccion, suc_telefono = @Telefono,
			   cia_id = @CiaId, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE suc_id = @SucId;
		SET @IdResultado = @SucId;
	END
END;
GO

-- No se eliminan: tienen cajas, usuarios, documentos y empleados ligados.
CREATE OR ALTER PROCEDURE [dbo].[paSucursalCambiarEstado]
	@SucId	INT,
	@Estado	CHAR(1),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @Estado NOT IN ('A', 'I')
		THROW 53005, 'El estado debe ser A (activa) o I (inactiva).', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE suc_id = @SucId)
		THROW 53004, 'La sucursal indicada no existe.', 1;
	IF @Estado = 'I' AND EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE suc_id = @SucId AND bod_estado = 'A')
		THROW 53006, 'La sucursal tiene bodegas activas; inactívelas primero.', 1;
	IF @Estado = 'I' AND EXISTS (SELECT 1 FROM dbo.pos_caja_apertura aper INNER JOIN dbo.pos_caja_receptora caja ON caja.pcr_id = aper.pcr_id
								 WHERE caja.suc_id = @SucId AND aper.pca_estado = 'A')
		THROW 53007, 'La sucursal tiene una caja abierta; ciérrela primero.', 1;

	UPDATE dbo.gen_sucursal SET suc_estado = @Estado, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE suc_id = @SucId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBodegaConsultar]
	@SucId			INT = NULL,
	@SoloActivas	BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT bode.bod_id, bode.bod_codigo, bode.bod_descripcion, bode.suc_id, sucu.suc_codigo, sucu.suc_descripcion, bode.bod_estado,
		   (SELECT COUNT(*) FROM dbo.inv_producto_existencia_bodega exis WHERE exis.bod_id = bode.bod_id AND exis.existencia <> 0) AS ProductosConExistencia
	FROM dbo.inv_bodega bode
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
	WHERE (@SucId IS NULL OR bode.suc_id = @SucId)
	  AND (@SoloActivas = 0 OR bode.bod_estado = 'A')
	ORDER BY sucu.suc_codigo, bode.bod_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBodegaGuardar]
	@BodId			INT = NULL,
	@SucId			INT,
	@Codigo			VARCHAR(8),
	@Descripcion	VARCHAR(128),
	@UsuId			INT = NULL,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET @Codigo = UPPER(LTRIM(RTRIM(@Codigo)));
	SET @Descripcion = LTRIM(RTRIM(@Descripcion));

	IF ISNULL(@Codigo, '') = '' OR ISNULL(@Descripcion, '') = ''
		THROW 53011, 'Ingrese el código y la descripción de la bodega.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE suc_id = @SucId)
		THROW 53004, 'La sucursal indicada no existe.', 1;
	IF EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE suc_id = @SucId AND bod_codigo = @Codigo AND bod_id <> ISNULL(@BodId, 0))
		THROW 53012, 'Ya existe una bodega con ese código en la sucursal.', 1;

	IF @BodId IS NULL
	BEGIN
		INSERT INTO dbo.inv_bodega (bod_codigo, bod_descripcion, suc_id, InsUsuario, InsFechaHora)
		VALUES (@Codigo, @Descripcion, @SucId, @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE bod_id = @BodId)
			THROW 53013, 'La bodega indicada no existe.', 1;
		-- Cambiarla de sucursal movería existencias de una sucursal a otra.
		IF EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE bod_id = @BodId AND suc_id <> @SucId)
		   AND EXISTS (SELECT 1 FROM dbo.inv_producto_existencia_bodega WHERE bod_id = @BodId AND existencia <> 0)
			THROW 53014, 'La bodega tiene existencias; no se puede cambiar de sucursal.', 1;
		UPDATE dbo.inv_bodega
		   SET bod_codigo = @Codigo, bod_descripcion = @Descripcion, suc_id = @SucId, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE bod_id = @BodId;
		SET @IdResultado = @BodId;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBodegaCambiarEstado]
	@BodId	INT,
	@Estado	CHAR(1),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @Estado NOT IN ('A', 'I')
		THROW 53015, 'El estado debe ser A (activa) o I (inactiva).', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE bod_id = @BodId)
		THROW 53013, 'La bodega indicada no existe.', 1;
	IF @Estado = 'I' AND EXISTS (SELECT 1 FROM dbo.inv_producto_existencia_bodega WHERE bod_id = @BodId AND existencia <> 0)
		THROW 53016, 'La bodega tiene existencias; trasládelas o ajústelas antes de inactivarla.', 1;
	IF @Estado = 'A' AND EXISTS (SELECT 1 FROM dbo.inv_bodega bode INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
								 WHERE bode.bod_id = @BodId AND sucu.suc_estado <> 'A')
		THROW 53017, 'La sucursal de la bodega está inactiva; actívela primero.', 1;

	UPDATE dbo.inv_bodega SET bod_estado = @Estado, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE bod_id = @BodId;
END;
GO

------------------------------------------------------------
-- 2. Unidades de medida
------------------------------------------------------------
IF OBJECT_ID('dbo.inv_unidad_medida', 'U') IS NULL
CREATE TABLE [dbo].[inv_unidad_medida](
	[ume_id]			INT				IDENTITY(1,1)	NOT NULL,
	[ume_codigo]		VARCHAR(10)		NOT NULL,
	[ume_descripcion]	VARCHAR(64)		NOT NULL,
	[ume_estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_unidad_medida] PRIMARY KEY CLUSTERED ([ume_id]),
	CONSTRAINT [UQ_inv_unidad_medida_codigo] UNIQUE ([ume_codigo]),
	CONSTRAINT [CK_inv_unidad_medida_estado] CHECK ([ume_estado] IN ('A','I'))
);
GO

INSERT INTO dbo.inv_unidad_medida (ume_codigo, ume_descripcion)
SELECT v.c, v.d
FROM (VALUES ('UND', 'Unidad'), ('SRV', 'Servicio'), ('HR', 'Hora'), ('DIA', 'Día'), ('MES', 'Mes'),
			 ('LIC', 'Licencia'), ('CJ', 'Caja'), ('PQ', 'Paquete'), ('MT', 'Metro'), ('KIT', 'Kit')) v(c, d)
WHERE NOT EXISTS (SELECT 1 FROM dbo.inv_unidad_medida unid WHERE unid.ume_codigo = v.c);
GO

IF COL_LENGTH('dbo.inv_producto', 'ume_id') IS NULL
	ALTER TABLE dbo.inv_producto ADD [ume_id] INT NULL;
IF COL_LENGTH('dbo.inv_documento_det', 'ume_id') IS NULL
	ALTER TABLE dbo.inv_documento_det ADD [ume_id] INT NULL;
GO
IF OBJECT_ID('dbo.FK_inv_producto_unidad_medida', 'F') IS NULL
	ALTER TABLE dbo.inv_producto ADD CONSTRAINT [FK_inv_producto_unidad_medida] FOREIGN KEY ([ume_id]) REFERENCES dbo.inv_unidad_medida ([ume_id]);
IF OBJECT_ID('dbo.FK_inv_documento_det_unidad_medida', 'F') IS NULL
	ALTER TABLE dbo.inv_documento_det ADD CONSTRAINT [FK_inv_documento_det_unidad_medida] FOREIGN KEY ([ume_id]) REFERENCES dbo.inv_unidad_medida ([ume_id]);
GO

-- Productos existentes: los bienes en unidades y los servicios como servicio.
UPDATE prod SET ume_id = unid.ume_id
FROM dbo.inv_producto prod
INNER JOIN dbo.inv_unidad_medida unid ON unid.ume_codigo = CASE WHEN prod.pro_tipo_item = 'S' THEN 'SRV' ELSE 'UND' END
WHERE prod.ume_id IS NULL;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUnidadMedidaConsultar]
	@SoloActivas BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT unid.ume_id, unid.ume_codigo, unid.ume_descripcion, unid.ume_estado,
		   (SELECT COUNT(*) FROM dbo.inv_producto prod WHERE prod.ume_id = unid.ume_id)
		   + (SELECT COUNT(*) FROM dbo.inv_documento_det deta WHERE deta.ume_id = unid.ume_id) AS CantidadUsos
	FROM dbo.inv_unidad_medida unid
	WHERE @SoloActivas = 0 OR unid.ume_estado = 'A'
	ORDER BY unid.ume_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUnidadMedidaGuardar]
	@UmeId			INT = NULL,
	@Codigo			VARCHAR(10),
	@Descripcion	VARCHAR(64),
	@Estado			CHAR(1) = 'A',
	@UsuId			INT = NULL,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET @Codigo = UPPER(LTRIM(RTRIM(@Codigo)));
	SET @Descripcion = LTRIM(RTRIM(@Descripcion));

	IF ISNULL(@Codigo, '') = '' OR ISNULL(@Descripcion, '') = ''
		THROW 53021, 'Ingrese el código y la descripción de la unidad de medida.', 1;
	IF @Estado NOT IN ('A', 'I')
		THROW 53022, 'El estado debe ser A (activa) o I (inactiva).', 1;
	IF EXISTS (SELECT 1 FROM dbo.inv_unidad_medida WHERE ume_codigo = @Codigo AND ume_id <> ISNULL(@UmeId, 0))
		THROW 53023, 'Ya existe una unidad de medida con ese código.', 1;

	IF @UmeId IS NULL
	BEGIN
		INSERT INTO dbo.inv_unidad_medida (ume_codigo, ume_descripcion, ume_estado, InsUsuario, InsFechaHora)
		VALUES (@Codigo, @Descripcion, @Estado, @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM dbo.inv_unidad_medida WHERE ume_id = @UmeId)
			THROW 53024, 'La unidad de medida indicada no existe.', 1;
		UPDATE dbo.inv_unidad_medida
		   SET ume_codigo = @Codigo, ume_descripcion = @Descripcion, ume_estado = @Estado, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE ume_id = @UmeId;
		SET @IdResultado = @UmeId;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUnidadMedidaEliminar]
	@UmeId INT
AS
BEGIN
	SET NOCOUNT ON;
	IF EXISTS (SELECT 1 FROM dbo.inv_producto WHERE ume_id = @UmeId)
	   OR EXISTS (SELECT 1 FROM dbo.inv_documento_det WHERE ume_id = @UmeId)
		THROW 53025, 'La unidad de medida está en uso en productos o documentos; inactívela en lugar de eliminarla.', 1;
	DELETE FROM dbo.inv_unidad_medida WHERE ume_id = @UmeId;
END;
GO

-- Producto: se agrega la unidad de medida (opcional; si no viene se deja la actual).
CREATE OR ALTER PROCEDURE [dbo].[sp_producto_insertar]
	@pro_codigo				VARCHAR(64),
	@pro_descripcion		VARCHAR(256),
	@prt_id					INT,
	@pro_tipo_item			CHAR(1) = 'B',
	@pro_maneja_existencia	BIT = 1,
	@pro_id_padre			INT = NULL,
	@usu_id					INT = NULL,
	@pro_id					INT OUTPUT,
	@ume_id					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_codigo = @pro_codigo)
		THROW 51001, 'Ya existe un producto con ese código.', 1;

	IF @ume_id IS NULL
		SET @ume_id = (SELECT ume_id FROM dbo.inv_unidad_medida WHERE ume_codigo = CASE WHEN @pro_tipo_item = 'S' THEN 'SRV' ELSE 'UND' END);

	INSERT INTO dbo.inv_producto
		(pro_codigo, pro_descripcion, prt_id, pro_tipo_item, pro_maneja_existencia, pro_id_padre, ume_id, InsUsuario, InsFechaHora)
	VALUES
		(@pro_codigo, @pro_descripcion, @prt_id, @pro_tipo_item, @pro_maneja_existencia, @pro_id_padre, @ume_id, @usu_id, SYSDATETIME());

	SET @pro_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_producto_actualizar]
	@pro_id					INT,
	@pro_codigo				VARCHAR(64),
	@pro_descripcion		VARCHAR(256),
	@prt_id					INT,
	@pro_tipo_item			CHAR(1),
	@pro_maneja_existencia	BIT,
	@pro_id_padre			INT = NULL,
	@pro_ptje_rentabilidad	NUMERIC(8, 2) = NULL,
	@usu_id					INT = NULL,
	@ume_id					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_id = @pro_id)
		THROW 51002, 'El producto indicado no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_codigo = @pro_codigo AND pro_id <> @pro_id)
		THROW 51001, 'Ya existe otro producto con ese código.', 1;

	UPDATE dbo.inv_producto
	   SET pro_codigo = @pro_codigo,
		   pro_descripcion = @pro_descripcion,
		   prt_id = @prt_id,
		   pro_tipo_item = @pro_tipo_item,
		   pro_maneja_existencia = @pro_maneja_existencia,
		   pro_id_padre = @pro_id_padre,
		   pro_ptje_rentabilidad = @pro_ptje_rentabilidad,
		   ume_id = ISNULL(@ume_id, ume_id),
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pro_id = @pro_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_producto_consultar]
	@pro_codigo			VARCHAR(64) = NULL,
	@pro_descripcion	VARCHAR(256) = NULL,
	@prt_id				INT = NULL,
	@pro_estado			CHAR(1) = 'A',
	@pagina				INT = 1,
	@tamanio_pagina		INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT pro.pro_id, pro.pro_codigo, pro.pro_descripcion, pro.pro_tipo_item,
		   pro.pro_maneja_existencia, pro.pro_total_cantidad, pro.pro_costo_unitario,
		   pro.prt_id, prt.prt_descripcion, pro.pro_estado,
		   pro.ume_id, unid.ume_codigo, unid.ume_descripcion
	FROM dbo.inv_producto pro
	INNER JOIN dbo.inv_producto_tipo prt ON prt.prt_id = pro.prt_id
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = pro.ume_id
	WHERE (@pro_codigo IS NULL OR pro.pro_codigo LIKE '%' + @pro_codigo + '%')
	  AND (@pro_descripcion IS NULL OR pro.pro_descripcion LIKE '%' + @pro_descripcion + '%')
	  AND (@prt_id IS NULL OR pro.prt_id = @prt_id)
	  AND (@pro_estado IS NULL OR pro.pro_estado = @pro_estado)
	ORDER BY pro.pro_descripcion
	OFFSET (@pagina - 1) * @tamanio_pagina ROWS FETCH NEXT @tamanio_pagina ROWS ONLY;
END;
GO

------------------------------------------------------------
-- 3. Factura con líneas de bien o servicio
------------------------------------------------------------
-- El tipo de tabla no se puede alterar: se quita el procedimiento que lo
-- usa, se recrea con la cantidad decimal y la unidad, y se vuelve a crear
-- el procedimiento (21 hace lo mismo con la versión anterior).
DROP PROCEDURE IF EXISTS [dbo].[sp_ventas_crear_factura];
GO
DROP TYPE IF EXISTS [dbo].[factura_det_type];
GO
CREATE TYPE [dbo].[factura_det_type] AS TABLE
(
	[det_item]				INT				NOT NULL,
	[det_bien_o_servicio]	CHAR(1)			NOT NULL,	-- B = bien (producto), S = servicio
	[det_cantidad]			NUMERIC(12, 4)	NOT NULL,
	[det_descripcion]		VARCHAR(256)	NOT NULL,
	[det_precio_unitario]	NUMERIC(12, 2)	NOT NULL,	-- precio unitario de venta sin IVA
	[det_valor_descuento]	NUMERIC(12, 2)	NOT NULL DEFAULT (0),
	[det_sub_total]			NUMERIC(12, 2)	NOT NULL,
	[det_costo_unitario]	NUMERIC(12, 5)	NULL,
	[det_porc_iva]			NUMERIC(8, 2)	NULL,
	[bod_id]				INT				NOT NULL,
	[pro_id]				INT				NULL,		-- obligatorio en bienes; opcional en servicios
	[ppr_id]				INT				NULL,
	[ume_id]				INT				NULL		-- si no viene, la del producto
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
	@pca_id						INT = NULL,				-- apertura de caja activa donde se recibe el pago inicial
	@formas_pago				dbo.pago_forma_type READONLY,	-- pago de contado, o enganche si es a crédito; pasar tabla vacía si no aplica
	@enc_id						INT OUTPUT,
	@enc_numero_unico			VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @detalle)
		THROW 51401, 'La factura debe tener al menos una línea de detalle.', 1;
	IF EXISTS (SELECT 1 FROM @detalle WHERE det_bien_o_servicio NOT IN ('B', 'S'))
		THROW 53031, 'Cada línea debe ser bien (B) o servicio (S).', 1;
	IF EXISTS (SELECT 1 FROM @detalle WHERE det_bien_o_servicio = 'B' AND pro_id IS NULL)
		THROW 53032, 'Una línea de bien debe indicar el producto.', 1;
	IF EXISTS (SELECT 1 FROM @detalle WHERE LTRIM(RTRIM(det_descripcion)) = '')
		THROW 53033, 'Toda línea debe tener descripción; en un servicio, describa el servicio prestado.', 1;
	IF EXISTS (SELECT 1 FROM @detalle WHERE det_cantidad <= 0 OR det_precio_unitario < 0)
		THROW 53034, 'La cantidad debe ser mayor a cero y el precio no puede ser negativo.', 1;
	IF EXISTS (SELECT 1 FROM @detalle deta INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
			   WHERE prod.pro_maneja_existencia = 1 AND deta.det_cantidad <> ROUND(deta.det_cantidad, 0))
		THROW 53035, 'Los productos con existencia se venden en cantidades enteras.', 1;

	IF @mon_id IS NULL
		SET @mon_id = dbo.fn_moneda_local();

	IF EXISTS (
		SELECT 1
		FROM (SELECT pro_id, bod_id, SUM(det_cantidad) AS cantidad FROM @detalle WHERE pro_id IS NOT NULL GROUP BY pro_id, bod_id) d
		INNER JOIN dbo.inv_producto p ON p.pro_id = d.pro_id
		LEFT JOIN dbo.inv_producto_existencia_bodega e ON e.pro_id = d.pro_id AND e.bod_id = d.bod_id
		WHERE p.pro_maneja_existencia = 1
		  AND ISNULL(e.existencia, 0) < d.cantidad
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
			 det_precio_unitario, det_valor_descuento, det_sub_total, det_costo_unitario, det_porc_iva, bod_id, pro_id, ppr_id, ume_id,
			 InsUsuario, InsFechaHora)
		SELECT
			@enc_id, deta.det_item, deta.det_bien_o_servicio, deta.det_cantidad, deta.det_descripcion,
			deta.det_precio_unitario, deta.det_valor_descuento, deta.det_sub_total, deta.det_costo_unitario, deta.det_porc_iva,
			deta.bod_id, deta.pro_id, deta.ppr_id, COALESCE(deta.ume_id, prod.ume_id),
			@usu_id, SYSDATETIME()
		FROM @detalle deta
		LEFT JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id;

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

------------------------------------------------------------
-- 4. Unidades organizativas recursivas y organigrama
------------------------------------------------------------
IF COL_LENGTH('dbo.rrhhUnidadOrganizativa', 'IdUnidadPadre') IS NULL
	ALTER TABLE dbo.rrhhUnidadOrganizativa ADD [IdUnidadPadre] INT NULL;
IF COL_LENGTH('dbo.rrhhUnidadOrganizativa', 'Orden') IS NULL
	ALTER TABLE dbo.rrhhUnidadOrganizativa ADD [Orden] SMALLINT NOT NULL CONSTRAINT [DF_rrhhUnidadOrganizativa_Orden] DEFAULT (0);
GO
IF OBJECT_ID('dbo.FK_rrhhUnidadOrganizativa_Padre', 'F') IS NULL
	ALTER TABLE dbo.rrhhUnidadOrganizativa ADD CONSTRAINT [FK_rrhhUnidadOrganizativa_Padre]
		FOREIGN KEY ([IdUnidadPadre]) REFERENCES dbo.rrhhUnidadOrganizativa ([IdUnidadOrganizativa]);
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_rrhhUnidadOrganizativa_Padre')
	ALTER TABLE dbo.rrhhUnidadOrganizativa ADD CONSTRAINT [CK_rrhhUnidadOrganizativa_Padre]
		CHECK ([IdUnidadPadre] IS NULL OR [IdUnidadPadre] <> [IdUnidadOrganizativa]);
GO

-- Árbol completo con su nivel y ruta (para ordenar), en el orden en que se
-- dibuja: cada nodo seguido de sus hijos.
CREATE OR ALTER PROCEDURE [dbo].[paRrhhUnidadArbolConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	;WITH arbol AS (
		SELECT unid.IdUnidadOrganizativa, unid.IdUnidadPadre, unid.Descripcion, unid.Estado, unid.Orden, 1 AS Nivel,
			   CAST(RIGHT('0000' + CAST(unid.Orden AS VARCHAR(4)), 4) + '|' + unid.Descripcion AS NVARCHAR(4000)) AS Ruta
		FROM dbo.rrhhUnidadOrganizativa unid
		WHERE unid.IdUnidadPadre IS NULL
		UNION ALL
		SELECT hijo.IdUnidadOrganizativa, hijo.IdUnidadPadre, hijo.Descripcion, hijo.Estado, hijo.Orden, arbol.Nivel + 1,
			   CAST(arbol.Ruta + '/' + RIGHT('0000' + CAST(hijo.Orden AS VARCHAR(4)), 4) + '|' + hijo.Descripcion AS NVARCHAR(4000))
		FROM dbo.rrhhUnidadOrganizativa hijo
		INNER JOIN arbol ON arbol.IdUnidadOrganizativa = hijo.IdUnidadPadre
	)
	SELECT arbol.IdUnidadOrganizativa, arbol.IdUnidadPadre, arbol.Descripcion, arbol.Estado, arbol.Orden, arbol.Nivel,
		   (SELECT COUNT(*) FROM dbo.rrhhUnidadOrganizativa hijo WHERE hijo.IdUnidadPadre = arbol.IdUnidadOrganizativa) AS CantidadHijos,
		   (SELECT COUNT(*) FROM dbo.rrhhDepartamento depa WHERE depa.IdUnidadOrganizativa = arbol.IdUnidadOrganizativa) AS CantidadDepartamentos
	FROM arbol
	ORDER BY arbol.Ruta
	OPTION (MAXRECURSION 100);
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhUnidadGuardar]
	@IdUnidad		INT = NULL,
	@IdPadre		INT = NULL,
	@Descripcion	VARCHAR(100),
	@Orden			SMALLINT = 0,
	@UsuId			INT = NULL,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET @Descripcion = LTRIM(RTRIM(@Descripcion));
	IF ISNULL(@Descripcion, '') = ''
		THROW 53041, 'Ingrese la descripción de la unidad organizativa.', 1;
	IF EXISTS (SELECT 1 FROM dbo.rrhhUnidadOrganizativa WHERE Descripcion = @Descripcion AND IdUnidadOrganizativa <> ISNULL(@IdUnidad, 0))
		THROW 53042, 'Ya existe una unidad organizativa con esa descripción.', 1;
	IF @IdPadre IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.rrhhUnidadOrganizativa WHERE IdUnidadOrganizativa = @IdPadre)
		THROW 53043, 'La unidad superior indicada no existe.', 1;

	IF @IdUnidad IS NULL
	BEGIN
		INSERT INTO dbo.rrhhUnidadOrganizativa (Descripcion, IdUnidadPadre, Orden, InsUsuario, InsFechaHora)
		VALUES (@Descripcion, @IdPadre, ISNULL(@Orden, 0), @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM dbo.rrhhUnidadOrganizativa WHERE IdUnidadOrganizativa = @IdUnidad)
			THROW 53044, 'La unidad organizativa indicada no existe.', 1;
		-- Cambiar de padre se hace con paRrhhUnidadMover (valida ciclos).
		UPDATE dbo.rrhhUnidadOrganizativa
		   SET Descripcion = @Descripcion, Orden = ISNULL(@Orden, 0), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE IdUnidadOrganizativa = @IdUnidad;
		SET @IdResultado = @IdUnidad;
	END
END;
GO

-- Mueve la unidad (con toda su rama) bajo otra unidad, o a la raíz si
-- @IdPadreNuevo es NULL. No puede quedar bajo sí misma ni bajo una de sus
-- propias subunidades.
CREATE OR ALTER PROCEDURE [dbo].[paRrhhUnidadMover]
	@IdUnidad		INT,
	@IdPadreNuevo	INT = NULL,
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhUnidadOrganizativa WHERE IdUnidadOrganizativa = @IdUnidad)
		THROW 53044, 'La unidad organizativa indicada no existe.', 1;
	IF @IdPadreNuevo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.rrhhUnidadOrganizativa WHERE IdUnidadOrganizativa = @IdPadreNuevo)
		THROW 53043, 'La unidad superior indicada no existe.', 1;

	IF @IdPadreNuevo IS NOT NULL
	BEGIN
		DECLARE @rama TABLE (Id INT PRIMARY KEY);
		;WITH descendientes AS (
			SELECT IdUnidadOrganizativa FROM dbo.rrhhUnidadOrganizativa WHERE IdUnidadOrganizativa = @IdUnidad
			UNION ALL
			SELECT hijo.IdUnidadOrganizativa FROM dbo.rrhhUnidadOrganizativa hijo
			INNER JOIN descendientes ON descendientes.IdUnidadOrganizativa = hijo.IdUnidadPadre
		)
		INSERT INTO @rama SELECT IdUnidadOrganizativa FROM descendientes OPTION (MAXRECURSION 100);
		IF EXISTS (SELECT 1 FROM @rama WHERE Id = @IdPadreNuevo)
			THROW 53045, 'Una unidad no puede quedar bajo sí misma ni bajo una de sus subunidades.', 1;
	END

	UPDATE dbo.rrhhUnidadOrganizativa
	   SET IdUnidadPadre = @IdPadreNuevo, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdUnidadOrganizativa = @IdUnidad;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhUnidadCambiarEstado]
	@IdUnidad	INT,
	@Estado		CHAR(1),
	@UsuId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @Estado NOT IN ('A', 'I')
		THROW 53046, 'El estado debe ser A (activa) o I (inactiva).', 1;
	IF @Estado = 'I' AND EXISTS (SELECT 1 FROM dbo.rrhhUnidadOrganizativa WHERE IdUnidadPadre = @IdUnidad AND Estado = 'A')
		THROW 53047, 'La unidad tiene subunidades activas; inactívelas primero.', 1;
	IF @Estado = 'I' AND EXISTS (SELECT 1 FROM dbo.rrhhDepartamento WHERE IdUnidadOrganizativa = @IdUnidad AND Estado = 'A')
		THROW 53048, 'La unidad tiene departamentos activos; muévalos o inactívelos primero.', 1;
	IF @Estado = 'A' AND EXISTS (SELECT 1 FROM dbo.rrhhUnidadOrganizativa hijo INNER JOIN dbo.rrhhUnidadOrganizativa padre
								 ON padre.IdUnidadOrganizativa = hijo.IdUnidadPadre WHERE hijo.IdUnidadOrganizativa = @IdUnidad AND padre.Estado <> 'A')
		THROW 53049, 'La unidad superior está inactiva; actívela primero.', 1;

	UPDATE dbo.rrhhUnidadOrganizativa SET Estado = @Estado, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdUnidadOrganizativa = @IdUnidad;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhUnidadEliminar]
	@IdUnidad INT
AS
BEGIN
	SET NOCOUNT ON;
	IF EXISTS (SELECT 1 FROM dbo.rrhhUnidadOrganizativa WHERE IdUnidadPadre = @IdUnidad)
		THROW 53050, 'La unidad tiene subunidades; elimínelas o muévalas primero.', 1;
	IF EXISTS (SELECT 1 FROM dbo.rrhhDepartamento WHERE IdUnidadOrganizativa = @IdUnidad)
		THROW 53051, 'La unidad tiene departamentos; muévalos a otra unidad primero.', 1;
	DELETE FROM dbo.rrhhUnidadOrganizativa WHERE IdUnidadOrganizativa = @IdUnidad;
END;
GO

-- Organigrama: nodos de unidades, departamentos y plazas (con el empleado
-- que ocupa cada plaza). Clave y ClavePadre identifican el nodo sin chocar
-- entre tipos: U12, D5, P7.
CREATE OR ALTER PROCEDURE [dbo].[paRrhhOrganigramaConsultar]
	@SoloActivos BIT = 1
AS
BEGIN
	SET NOCOUNT ON;
	SELECT CONCAT('U', unid.IdUnidadOrganizativa) AS Clave,
		   CASE WHEN unid.IdUnidadPadre IS NULL THEN NULL ELSE CONCAT('U', unid.IdUnidadPadre) END AS ClavePadre,
		   'U' AS Tipo, unid.Descripcion, CAST(NULL AS VARCHAR(400)) AS Detalle, unid.Orden, unid.Estado
	FROM dbo.rrhhUnidadOrganizativa unid
	WHERE @SoloActivos = 0 OR unid.Estado = 'A'
	UNION ALL
	SELECT CONCAT('D', depa.IdDepartamento),
		   CASE WHEN depa.IdUnidadOrganizativa IS NULL THEN NULL ELSE CONCAT('U', depa.IdUnidadOrganizativa) END,
		   'D', depa.Descripcion, sucu.suc_descripcion, 0, depa.Estado
	FROM dbo.rrhhDepartamento depa
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_id = depa.suc_id
	WHERE @SoloActivos = 0 OR depa.Estado = 'A'
	UNION ALL
	SELECT CONCAT('P', plaz.IdPlaza), CONCAT('D', depu.IdDepartamento), 'P',
		   CONCAT(pues.Descripcion, ' - ', plaz.Descripcion),
		   ISNULL((SELECT STRING_AGG(CONCAT(empl.PrimerNombre, ' ', empl.PrimerApellido), ', ')
				   FROM dbo.rrhhEmpleado empl WHERE empl.IdPlaza = plaz.IdPlaza AND empl.Estado = 'A'), 'Vacante'),
		   0, plaz.Estado
	FROM dbo.rrhhPlaza plaz
	INNER JOIN dbo.rrhhDepartamentoPuesto depu ON depu.IdDepartamentoPuesto = plaz.IdDepartamentoPuesto
	INNER JOIN dbo.rrhhPuesto pues ON pues.IdPuesto = depu.IdPuesto
	WHERE @SoloActivos = 0 OR plaz.Estado = 'A'
	ORDER BY 3 DESC, 6, 4;
END;
GO
