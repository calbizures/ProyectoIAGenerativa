------------------------------------------------------------------------------
-- 14_procedimientos_vendedor.sql
--
-- Agrega el CRUD de pos_vendedor, que hasta ahora solo existía como tabla
-- (sembrada por 12_datos_sinteticos.sql) sin procedimientos de alta, baja,
-- edición o consulta.
--
-- Nota de nomenclatura: a solicitud explícita, estos procedimientos usan el
-- estándar "pa" + PascalCase (paVendedorInsertar, paVendedorActualizar,
-- paVendedorEliminar, paVendedorConsultar, paVendedorConsultarPorId) en vez
-- del "sp_<entidad>_<accion>" usado en el resto de la base. Es el único
-- módulo con este estándar por ahora; los procedimientos existentes no se
-- renombraron para no romper nada ya desplegado.
--
-- Seguro de correr una sola vez contra una base ya creada con 00-13; no
-- modifica datos existentes. En una instalación nueva desde cero ya viene
-- incluido en 10_procedimientos_crud.sql.
------------------------------------------------------------------------------
USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[paVendedorInsertar]
	@pve_codigo			VARCHAR(16),
	@pve_nombres		VARCHAR(64),
	@pve_apellidos		VARCHAR(64) = NULL,
	@pve_fecha_ingreso	DATE = NULL,
	@pve_porc_comision	NUMERIC(8, 2) = 0,
	@usu_id				INT = NULL,
	@pve_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.pos_vendedor WHERE pve_codigo = @pve_codigo)
		THROW 51091, 'Ya existe un vendedor con ese código.', 1;

	INSERT INTO dbo.pos_vendedor
		(pve_codigo, pve_nombres, pve_apellidos, pve_fecha_ingreso, pve_porc_comision, InsUsuario, InsFechaHora)
	VALUES
		(@pve_codigo, @pve_nombres, @pve_apellidos, @pve_fecha_ingreso, @pve_porc_comision, @usu_id, SYSDATETIME());

	SET @pve_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paVendedorActualizar]
	@pve_id				INT,
	@pve_nombres		VARCHAR(64),
	@pve_apellidos		VARCHAR(64) = NULL,
	@pve_fecha_ingreso	DATE = NULL,
	@pve_porc_comision	NUMERIC(8, 2) = 0,
	@usu_id				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_vendedor WHERE pve_id = @pve_id)
		THROW 51092, 'El vendedor indicado no existe.', 1;

	UPDATE dbo.pos_vendedor
	   SET pve_nombres = @pve_nombres,
		   pve_apellidos = @pve_apellidos,
		   pve_fecha_ingreso = @pve_fecha_ingreso,
		   pve_porc_comision = @pve_porc_comision,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pve_id = @pve_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paVendedorEliminar]
	@pve_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_vendedor WHERE pve_id = @pve_id)
		THROW 51092, 'El vendedor indicado no existe.', 1;

	UPDATE dbo.pos_vendedor
	   SET pve_estado = 'I',
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pve_id = @pve_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paVendedorConsultar]
	@pve_estado CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;
	SELECT pve_id, pve_codigo, pve_nombres, pve_apellidos, pve_fecha_ingreso, pve_porc_comision, pve_estado
	FROM dbo.pos_vendedor
	WHERE (@pve_estado IS NULL OR pve_estado = @pve_estado)
	ORDER BY pve_nombres, pve_apellidos;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paVendedorConsultarPorId]
	@pve_id INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.pos_vendedor WHERE pve_id = @pve_id;
END;
GO
