------------------------------------------------------------------------------
-- 18_procedimientos_detalle_producto.sql
--
-- Agrega procedimientos para gestionar el detalle de un producto que hasta
-- ahora solo se veía (nunca se podía dar de alta/editar/eliminar) desde el
-- frontend:
--
--   * inv_producto_caracteristica: CRUD completo (alta física sin estado,
--     ya que la tabla no tiene columna de baja lógica).
--   * inv_producto_tipo_caracteristica: solo consulta, para el combo de
--     tipo de característica (Marca, Modelo, Garantía, Capacidad...).
--   * inv_producto_existencia_bodega: solo consulta; la existencia la
--     mantienen los procesos de negocio al grabar/anular documentos, no
--     se edita a mano.
--   * inv_producto_precio: CRUD completo (baja lógica con ppr_estado).
--
-- Seguro de correr una sola vez contra una base ya creada con 00-17.
------------------------------------------------------------------------------

USE [erp_db];
GO

------------------------------------------------------------
-- inv_producto_tipo_caracteristica (catálogo, solo consulta desde el
-- frontend; se siembra con 12_datos_sinteticos.sql)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_producto_tipo_caracteristica_consultar]
	@ptc_estado CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT ptc_id, ptc_codigo, ptc_descripcion, ptc_orden, ptc_estado
	FROM dbo.inv_producto_tipo_caracteristica
	WHERE (@ptc_estado IS NULL OR ptc_estado = @ptc_estado)
	ORDER BY ptc_orden, ptc_descripcion;
END;
GO

------------------------------------------------------------
-- inv_producto_caracteristica
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_producto_caracteristica_insertar]
	@pro_id				INT,
	@ptc_id				INT,
	@pca_valor			VARCHAR(64),
	@pca_descripcion	VARCHAR(64) = NULL,
	@usu_id				INT = NULL,
	@pca_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_id = @pro_id)
		THROW 51101, 'El producto indicado no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.inv_producto_caracteristica WHERE pro_id = @pro_id AND ptc_id = @ptc_id)
		THROW 51102, 'El producto ya tiene un valor asignado para esa característica.', 1;

	INSERT INTO dbo.inv_producto_caracteristica
		(pca_valor, pca_descripcion, pro_id, ptc_id, InsUsuario, InsFechaHora)
	VALUES
		(@pca_valor, @pca_descripcion, @pro_id, @ptc_id, @usu_id, SYSDATETIME());

	SET @pca_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_producto_caracteristica_actualizar]
	@pca_id				INT,
	@pca_valor			VARCHAR(64),
	@pca_descripcion	VARCHAR(64) = NULL,
	@usu_id				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto_caracteristica WHERE pca_id = @pca_id)
		THROW 51103, 'La característica indicada no existe.', 1;

	UPDATE dbo.inv_producto_caracteristica
	   SET pca_valor = @pca_valor,
		   pca_descripcion = @pca_descripcion,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pca_id = @pca_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_producto_caracteristica_eliminar]
	@pca_id INT
AS
BEGIN
	SET NOCOUNT ON;

	-- inv_producto_caracteristica no tiene columna de estado (es un valor
	-- puntual por producto/característica), así que la baja es física.
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto_caracteristica WHERE pca_id = @pca_id)
		THROW 51103, 'La característica indicada no existe.', 1;

	DELETE FROM dbo.inv_producto_caracteristica WHERE pca_id = @pca_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_producto_caracteristica_consultar]
	@pro_id INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	SELECT pca.pca_id, pca.pca_valor, pca.pca_descripcion, pca.pro_id,
		   pro.pro_codigo, pro.pro_descripcion,
		   pca.ptc_id, ptc.ptc_codigo, ptc.ptc_descripcion
	FROM dbo.inv_producto_caracteristica pca
	INNER JOIN dbo.inv_producto pro ON pro.pro_id = pca.pro_id
	INNER JOIN dbo.inv_producto_tipo_caracteristica ptc ON ptc.ptc_id = pca.ptc_id
	WHERE (@pro_id IS NULL OR pca.pro_id = @pro_id)
	ORDER BY pro.pro_descripcion, ptc.ptc_orden;
END;
GO

------------------------------------------------------------
-- inv_producto_existencia_bodega (solo consulta; la existencia la
-- mantienen los procesos de negocio al grabar/anular documentos)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_producto_existencia_consultar]
	@pro_id	INT = NULL,
	@bod_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	SELECT peb.peb_id, peb.pro_id, pro.pro_codigo, pro.pro_descripcion,
		   peb.bod_id, bod.bod_descripcion, peb.existencia
	FROM dbo.inv_producto_existencia_bodega peb
	INNER JOIN dbo.inv_producto pro ON pro.pro_id = peb.pro_id
	INNER JOIN dbo.inv_bodega bod ON bod.bod_id = peb.bod_id
	WHERE (@pro_id IS NULL OR peb.pro_id = @pro_id)
	  AND (@bod_id IS NULL OR peb.bod_id = @bod_id)
	ORDER BY pro.pro_descripcion, bod.bod_descripcion;
END;
GO

------------------------------------------------------------
-- inv_producto_precio
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_producto_precio_insertar]
	@pro_id							INT,
	@bod_id							INT,
	@mon_id							INT,
	@ppr_precio_unitario_venta		NUMERIC(12, 2),
	@ppr_descripcion				VARCHAR(128) = NULL,
	@ppr_vigencia_desde				DATE,
	@ppr_vigencia_hasta				DATE = NULL,
	@usu_id							INT = NULL,
	@ppr_id							INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_id = @pro_id)
		THROW 51111, 'El producto indicado no existe.', 1;

	INSERT INTO dbo.inv_producto_precio
		(ppr_precio_unitario_venta, ppr_descripcion, ppr_vigencia_desde, ppr_vigencia_hasta,
		 pro_id, bod_id, mon_id, ppr_estado, InsUsuario, InsFechaHora)
	VALUES
		(@ppr_precio_unitario_venta, @ppr_descripcion, @ppr_vigencia_desde, @ppr_vigencia_hasta,
		 @pro_id, @bod_id, @mon_id, 'A', @usu_id, SYSDATETIME());

	SET @ppr_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_producto_precio_actualizar]
	@ppr_id							INT,
	@bod_id							INT,
	@mon_id							INT,
	@ppr_precio_unitario_venta		NUMERIC(12, 2),
	@ppr_descripcion				VARCHAR(128) = NULL,
	@ppr_vigencia_desde				DATE,
	@ppr_vigencia_hasta				DATE = NULL,
	@usu_id							INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto_precio WHERE ppr_id = @ppr_id)
		THROW 51112, 'El precio indicado no existe.', 1;

	UPDATE dbo.inv_producto_precio
	   SET bod_id = @bod_id,
		   mon_id = @mon_id,
		   ppr_precio_unitario_venta = @ppr_precio_unitario_venta,
		   ppr_descripcion = @ppr_descripcion,
		   ppr_vigencia_desde = @ppr_vigencia_desde,
		   ppr_vigencia_hasta = @ppr_vigencia_hasta,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE ppr_id = @ppr_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_producto_precio_eliminar]
	@ppr_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto_precio WHERE ppr_id = @ppr_id)
		THROW 51112, 'El precio indicado no existe.', 1;

	UPDATE dbo.inv_producto_precio
	   SET ppr_estado = 'I',
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE ppr_id = @ppr_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_producto_precio_consultar]
	@pro_id		INT = NULL,
	@bod_id		INT = NULL,
	@ppr_estado	CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT ppr.ppr_id, ppr.pro_id, pro.pro_codigo, pro.pro_descripcion,
		   ppr.bod_id, bod.bod_descripcion, ppr.mon_id, mon.mon_codigo,
		   ppr.ppr_precio_unitario_venta, ppr.ppr_descripcion,
		   ppr.ppr_vigencia_desde, ppr.ppr_vigencia_hasta, ppr.ppr_estado
	FROM dbo.inv_producto_precio ppr
	INNER JOIN dbo.inv_producto pro ON pro.pro_id = ppr.pro_id
	INNER JOIN dbo.inv_bodega bod ON bod.bod_id = ppr.bod_id
	INNER JOIN dbo.gen_moneda mon ON mon.mon_id = ppr.mon_id
	WHERE (@pro_id IS NULL OR ppr.pro_id = @pro_id)
	  AND (@bod_id IS NULL OR ppr.bod_id = @bod_id)
	  AND (@ppr_estado IS NULL OR ppr.ppr_estado = @ppr_estado)
	ORDER BY pro.pro_descripcion, bod.bod_descripcion, ppr.ppr_vigencia_desde DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_producto_precio_consultar_por_id]
	@ppr_id INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT ppr.*
	FROM dbo.inv_producto_precio ppr
	WHERE ppr.ppr_id = @ppr_id;
END;
GO
