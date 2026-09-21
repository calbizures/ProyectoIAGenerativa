------------------------------------------------------------------------------
-- 19_procedimientos_tipo_caracteristica.sql
--
-- Completa el CRUD de inv_producto_tipo_caracteristica (hasta ahora solo
-- tenía consulta, para el combo de tipo de característica). Agrega alta,
-- edición y baja lógica (ptc_estado) para poder mantenerlo desde un
-- módulo propio en Inventario, sin depender de los datos sintéticos.
--
-- Usa el estándar de nomenclatura vigente para procedimientos nuevos
-- (pa + PascalCase, ver "Estándares de nomenclatura" en README.md).
--
-- Seguro de correr una sola vez contra una base ya creada con 00-18.
------------------------------------------------------------------------------

USE [erp_db];
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoTipoCaracteristicaInsertar]
	@ptc_codigo			VARCHAR(16),
	@ptc_descripcion	VARCHAR(64),
	@ptc_orden			INT = 0,
	@usu_id				INT = NULL,
	@ptc_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.inv_producto_tipo_caracteristica WHERE ptc_codigo = @ptc_codigo)
		THROW 51121, 'Ya existe un tipo de característica con ese código.', 1;

	INSERT INTO dbo.inv_producto_tipo_caracteristica
		(ptc_codigo, ptc_descripcion, ptc_orden, ptc_estado, InsUsuario, InsFechaHora)
	VALUES
		(@ptc_codigo, @ptc_descripcion, @ptc_orden, 'A', @usu_id, SYSDATETIME());

	SET @ptc_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoTipoCaracteristicaActualizar]
	@ptc_id				INT,
	@ptc_codigo			VARCHAR(16),
	@ptc_descripcion	VARCHAR(64),
	@ptc_orden			INT,
	@usu_id				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto_tipo_caracteristica WHERE ptc_id = @ptc_id)
		THROW 51122, 'El tipo de característica indicado no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.inv_producto_tipo_caracteristica WHERE ptc_codigo = @ptc_codigo AND ptc_id <> @ptc_id)
		THROW 51121, 'Ya existe otro tipo de característica con ese código.', 1;

	UPDATE dbo.inv_producto_tipo_caracteristica
	   SET ptc_codigo = @ptc_codigo,
		   ptc_descripcion = @ptc_descripcion,
		   ptc_orden = @ptc_orden,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE ptc_id = @ptc_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoTipoCaracteristicaEliminar]
	@ptc_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto_tipo_caracteristica WHERE ptc_id = @ptc_id)
		THROW 51122, 'El tipo de característica indicado no existe.', 1;

	UPDATE dbo.inv_producto_tipo_caracteristica
	   SET ptc_estado = 'I',
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE ptc_id = @ptc_id;
END;
GO
