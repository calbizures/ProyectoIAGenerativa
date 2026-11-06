/*
================================================================================
 74_ubicacion_clientes_sucursales.sql
 Ubicación en cascada País › Departamento › Municipio (script 73) también en
 los clientes (pos_cliente) y las sucursales (gen_sucursal).

   1. Clientes: pos_cliente ya tenía cli_direccion_pais, cli_direccion_estado
      y cli_direccion_provincia. Se conservan las tres (la factura
      electrónica las usa), pero ahora el municipio manda: al grabarlo, el
      departamento y el país se toman de él, así nunca se contradicen.
        paClienteInsertar      deduce departamento y país del municipio.
        paClienteActualizar    recibe @CliDireccionProvincia; -1 (valor por
                               omisión) conserva el que ya tenía.
        paClienteConsultarPorId devuelve municipio, departamento, país y la
                               dirección completa.
      Los clientes que ya tenían municipio se corrigen para que su
      departamento y país coincidan con él.
   2. Sucursales: gen_sucursal.prov_id ya existía (lo usa la factura
      electrónica como municipio del establecimiento).
        paSucursalGuardar      recibe @ProvId; -1 conserva el actual.
        paSucursalConsultar    devuelve municipio, departamento, país y la
                               dirección completa.

 Requiere el 73. Errores nuevos: 55915.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Clientes
------------------------------------------------------------
UPDATE clie
   SET cli_direccion_estado = ubic.EstId, cli_direccion_pais = ubic.PaiId
FROM dbo.pos_cliente clie
INNER JOIN dbo.vwGenUbicacion ubic ON ubic.ProvId = clie.cli_direccion_provincia
WHERE ISNULL(clie.cli_direccion_estado, 0) <> ubic.EstId OR ISNULL(clie.cli_direccion_pais, 0) <> ubic.PaiId;
GO

CREATE OR ALTER PROCEDURE [dbo].[paClienteInsertar]
	@CliCodigo				VARCHAR(32),
	@CliNombres				VARCHAR(64),
	@CliApellidos			VARCHAR(64) = NULL,
	@CliDireccion			VARCHAR(128) = NULL,
	@CliTelefonoCelular		VARCHAR(16) = NULL,
	@CliNit					VARCHAR(16) = NULL,
	@CliEmail				VARCHAR(64) = NULL,
	@CliLimiteCredito		DECIMAL(14, 2) = 0,
	@CliDireccionPais		INT = NULL,
	@CliDireccionEstado		INT = NULL,
	@CliDireccionProvincia	INT = NULL,
	@UsuId					INT = NULL,
	@CliId					INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_codigo = @CliCodigo)
		THROW 51011, 'Ya existe un cliente con ese código.', 1;

	IF @CliNit IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_nit = @CliNit)
		THROW 51012, 'Ya existe un cliente con ese NIT.', 1;

	-- El municipio manda: departamento y país salen de él (o el país, del departamento).
	IF @CliDireccionProvincia IS NOT NULL
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM dbo.vwGenUbicacion WHERE ProvId = @CliDireccionProvincia AND Activo = 1)
			THROW 55914, 'El municipio indicado no existe o está inactivo.', 1;
		SELECT @CliDireccionEstado = EstId, @CliDireccionPais = PaiId FROM dbo.vwGenUbicacion WHERE ProvId = @CliDireccionProvincia;
	END
	ELSE IF @CliDireccionEstado IS NOT NULL
		SELECT @CliDireccionPais = pai_id FROM dbo.gen_estado WHERE est_id = @CliDireccionEstado;

	INSERT INTO dbo.pos_cliente
		(cli_codigo, cli_nombres, cli_apellidos, cli_direccion, cli_telefono_celular,
		 cli_nit, cli_email, cli_limite_credito, cli_direccion_pais, cli_direccion_estado, cli_direccion_provincia,
		 InsUsuario, InsFechaHora)
	VALUES
		(@CliCodigo, @CliNombres, @CliApellidos, @CliDireccion, @CliTelefonoCelular,
		 @CliNit, @CliEmail, @CliLimiteCredito, @CliDireccionPais, @CliDireccionEstado, @CliDireccionProvincia,
		 @UsuId, SYSDATETIME());

	SET @CliId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paClienteActualizar]
	@CliId					INT,
	@CliNombres				VARCHAR(64),
	@CliApellidos			VARCHAR(64) = NULL,
	@CliDireccion			VARCHAR(128) = NULL,
	@CliTelefonoCelular		VARCHAR(16) = NULL,
	@CliNit					VARCHAR(16) = NULL,
	@CliEmail				VARCHAR(64) = NULL,
	@CliLimiteCredito		DECIMAL(14, 2) = 0,
	@UsuId					INT = NULL,
	@CliDireccionProvincia	INT = -1	-- -1 = conservar el municipio actual
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_id = @CliId)
		THROW 51013, 'El cliente indicado no existe.', 1;

	IF @CliNit IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_nit = @CliNit AND cli_id <> @CliId)
		THROW 51012, 'Ya existe otro cliente con ese NIT.', 1;

	DECLARE @provAnterior INT = (SELECT cli_direccion_provincia FROM dbo.pos_cliente WHERE cli_id = @CliId);
	IF @CliDireccionProvincia IS NOT NULL AND @CliDireccionProvincia <> -1 AND ISNULL(@provAnterior, 0) <> @CliDireccionProvincia
		AND NOT EXISTS (SELECT 1 FROM dbo.vwGenUbicacion WHERE ProvId = @CliDireccionProvincia AND Activo = 1)
		THROW 55914, 'El municipio indicado no existe o está inactivo.', 1;

	UPDATE clie
	   SET cli_nombres = @CliNombres,
		   cli_apellidos = @CliApellidos,
		   cli_direccion = @CliDireccion,
		   cli_telefono_celular = @CliTelefonoCelular,
		   cli_nit = @CliNit,
		   cli_email = @CliEmail,
		   cli_limite_credito = @CliLimiteCredito,
		   cli_direccion_provincia = CASE WHEN @CliDireccionProvincia = -1 THEN clie.cli_direccion_provincia ELSE @CliDireccionProvincia END,
		   -- Sin municipio se conservan el departamento y el país que tuviera.
		   cli_direccion_estado = CASE WHEN @CliDireccionProvincia IS NULL OR @CliDireccionProvincia = -1 THEN clie.cli_direccion_estado
									   ELSE (SELECT EstId FROM dbo.vwGenUbicacion WHERE ProvId = @CliDireccionProvincia) END,
		   cli_direccion_pais = CASE WHEN @CliDireccionProvincia IS NULL OR @CliDireccionProvincia = -1 THEN clie.cli_direccion_pais
									 ELSE (SELECT PaiId FROM dbo.vwGenUbicacion WHERE ProvId = @CliDireccionProvincia) END,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	FROM dbo.pos_cliente clie
	WHERE clie.cli_id = @CliId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paClienteConsultarPorId]
	@CliId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT clie.*,
		   ubic.Municipio, ISNULL(ubic.Departamento, depa.est_nombre) AS Departamento, ISNULL(ubic.Pais, pais.pai_nombre) AS Pais,
		   NULLIF(CONCAT_WS(', ', NULLIF(LTRIM(RTRIM(clie.cli_direccion)), ''), ubic.Municipio, ISNULL(ubic.Departamento, depa.est_nombre),
				CASE WHEN ISNULL(ubic.PaisCodigo, pais.pai_codigo_alfa2) <> 'GT' THEN ISNULL(ubic.Pais, pais.pai_nombre) END), '') AS DireccionCompleta
	FROM dbo.pos_cliente clie
	LEFT JOIN dbo.vwGenUbicacion ubic ON ubic.ProvId = clie.cli_direccion_provincia
	LEFT JOIN dbo.gen_estado depa ON depa.est_id = clie.cli_direccion_estado
	LEFT JOIN dbo.gen_pais pais ON pais.pai_id = clie.cli_direccion_pais
	WHERE clie.cli_id = @CliId;
END;
GO

------------------------------------------------------------
-- 2. Sucursales
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paSucursalGuardar]
	@SucId			INT = NULL,
	@CiaId			INT,
	@Codigo			VARCHAR(8),
	@Descripcion	VARCHAR(128),
	@Direccion		VARCHAR(128) = NULL,
	@Telefono		VARCHAR(16) = NULL,
	@UsuId			INT = NULL,
	@IdResultado	INT OUTPUT,
	@ProvId			INT = -1	-- -1 = conservar el municipio actual
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

	DECLARE @provAnterior INT = (SELECT prov_id FROM dbo.gen_sucursal WHERE suc_id = @SucId);
	IF @ProvId = -1
		SET @ProvId = @provAnterior;
	ELSE IF @ProvId IS NOT NULL AND ISNULL(@provAnterior, 0) <> @ProvId
		AND NOT EXISTS (SELECT 1 FROM dbo.vwGenUbicacion WHERE ProvId = @ProvId AND Activo = 1)
		THROW 55914, 'El municipio indicado no existe o está inactivo.', 1;
	-- La factura electrónica necesita el municipio del establecimiento.
	IF @ProvId IS NULL AND EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE suc_id = @SucId AND suc_fel_codigo_establecimiento IS NOT NULL)
		THROW 55915, 'La sucursal es un establecimiento de factura electrónica: indique su municipio.', 1;

	IF @SucId IS NULL
	BEGIN
		INSERT INTO dbo.gen_sucursal (suc_codigo, suc_descripcion, suc_direccion, suc_telefono, cia_id, prov_id, InsUsuario, InsFechaHora)
		VALUES (@Codigo, @Descripcion, @Direccion, @Telefono, @CiaId, @ProvId, @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE suc_id = @SucId)
			THROW 53004, 'La sucursal indicada no existe.', 1;
		UPDATE dbo.gen_sucursal
		   SET suc_codigo = @Codigo, suc_descripcion = @Descripcion, suc_direccion = @Direccion, suc_telefono = @Telefono,
			   cia_id = @CiaId, prov_id = @ProvId, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE suc_id = @SucId;
		SET @IdResultado = @SucId;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paSucursalConsultar]
	@CiaId			INT = NULL,
	@SoloActivas	BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT sucu.suc_id, sucu.suc_codigo, sucu.suc_descripcion, sucu.suc_direccion, sucu.suc_telefono,
		   sucu.cia_id, comp.cia_nombre_comercial, sucu.suc_estado,
		   (SELECT COUNT(*) FROM dbo.inv_bodega bode WHERE bode.suc_id = sucu.suc_id) AS CantidadBodegas,
		   sucu.prov_id, ubic.Municipio, ubic.Departamento, ubic.Pais,
		   dbo.fnGenDireccionCompleta(sucu.suc_direccion, sucu.prov_id, 0) AS DireccionCompleta
	FROM dbo.gen_sucursal sucu
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	LEFT JOIN dbo.vwGenUbicacion ubic ON ubic.ProvId = sucu.prov_id
	WHERE (@CiaId IS NULL OR sucu.cia_id = @CiaId)
	  AND (@SoloActivas = 0 OR sucu.suc_estado = 'A')
	ORDER BY comp.cia_nombre_comercial, sucu.suc_codigo;
END;
GO

PRINT '74_ubicacion_clientes_sucursales.sql aplicado.';
GO
