/*
================================================================================
 75_seguridad_contrasenas.sql
 Contraseñas temporales, desbloqueo y protección del último administrador.

   1. gen_usuario.usu_cambiar_password: el usuario debe cambiar su contraseña
      al iniciar sesión (contraseña temporal puesta por el administrador o
      usuario recién creado).
   2. Política mínima de contraseñas: 8 caracteres o más, con letras y
      números (dbo.fnSeguridadPasswordValido).
        paUsuarioInsertar           valida la contraseña; @UsuCambiarPassword
                                    (por omisión 0) la marca como temporal.
        paUsuarioPasswordCambiar    valida la nueva, no permite repetir la
                                    actual y quita la marca de temporal.
        paUsuarioPasswordRestablecer  NUEVO. El administrador pone una
                                    contraseña temporal sin conocer la
                                    anterior; además desbloquea la cuenta.
        paUsuarioDesbloquear        NUEVO. Quita el bloqueo por intentos
                                    fallidos sin cambiar la contraseña.
        paSeguridadLogin            devuelve cambiar_password.
        paUsuarioConsultarPorId     devuelve usu_cambiar_password.
   3. Siempre queda al menos un administrador (usuario activo con un rol
      activo que tenga el permiso SEGURIDAD_USUARIO_ADMIN):
        paUsuarioEliminar      no permite desactivarse a sí mismo ni
                               desactivar al último administrador.
        paUsuarioRolRevocar    no permite quitar el rol que deja sin
                               administradores (@UsuIdAccion nuevo, opcional).
        paRolEliminar          no permite inactivar el último rol
                               administrador.
        paRolPermisoRevocar    no permite quitarle SEGURIDAD_USUARIO_ADMIN al
                               último rol que lo da.

 Si el único administrador queda bloqueado por intentos fallidos, se
 desbloquea desde SSMS con:
   EXEC dbo.paUsuarioDesbloquear @UsuId = <usu_id>;

 Errores nuevos: 55920 a 55925.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Marca de contraseña temporal
------------------------------------------------------------
IF COL_LENGTH('dbo.gen_usuario', 'usu_cambiar_password') IS NULL
	ALTER TABLE dbo.gen_usuario ADD [usu_cambiar_password] BIT NOT NULL
		CONSTRAINT DF_gen_usuario_cambiar_password DEFAULT (0);
GO

------------------------------------------------------------
-- 2. Política de contraseñas
------------------------------------------------------------
CREATE OR ALTER FUNCTION [dbo].[fnSeguridadPasswordValido] (@Password VARCHAR(256))
RETURNS BIT
AS
BEGIN
	RETURN CASE WHEN LEN(@Password) >= 8
				 AND @Password LIKE '%[A-Za-z]%'
				 AND @Password LIKE '%[0-9]%' THEN 1 ELSE 0 END;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioInsertar]
	@UsuCodigo			VARCHAR(32),
	@UsuUsuario		VARCHAR(128),
	@UsuPassword		VARCHAR(256),
	@UsuEmail			VARCHAR(128) = NULL,
	@UsuIdAccion		INT = NULL,
	@UsuId				INT OUTPUT,
	@UsuCambiarPassword	BIT = 0
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_usuario = @UsuUsuario)
		THROW 51031, 'Ya existe un usuario con ese nombre de acceso.', 1;

	IF dbo.fnSeguridadPasswordValido(@UsuPassword) = 0
		THROW 55920, 'La contraseña debe tener al menos 8 caracteres, con letras y números.', 1;

	DECLARE @salt UNIQUEIDENTIFIER = NEWID();

	INSERT INTO dbo.gen_usuario
		(usu_codigo, usu_usuario, usu_password_hash, usu_password_salt, usu_email, usu_cambiar_password, InsUsuario, InsFechaHora)
	VALUES
		(@UsuCodigo, @UsuUsuario,
		 HASHBYTES('SHA2_256', CAST(@salt AS VARCHAR(36)) + @UsuPassword),
		 @salt, @UsuEmail, @UsuCambiarPassword, @UsuIdAccion, SYSDATETIME());

	SET @UsuId = SCOPE_IDENTITY();
END;
GO

-- Cambio hecho por el propio usuario (conoce la contraseña actual).
CREATE OR ALTER PROCEDURE [dbo].[paUsuarioPasswordCambiar]
	@UsuId				INT,
	@PasswordActual	VARCHAR(256),
	@PasswordNuevo		VARCHAR(256)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @salt UNIQUEIDENTIFIER, @hash VARBINARY(64);

	SELECT @salt = usu_password_salt, @hash = usu_password_hash
	FROM dbo.gen_usuario WHERE usu_id = @UsuId;

	IF @salt IS NULL
		THROW 51032, 'El usuario indicado no existe.', 1;

	IF HASHBYTES('SHA2_256', CAST(@salt AS VARCHAR(36)) + @PasswordActual) <> @hash
		THROW 51033, 'La contraseña actual no es correcta.', 1;

	IF dbo.fnSeguridadPasswordValido(@PasswordNuevo) = 0
		THROW 55920, 'La contraseña debe tener al menos 8 caracteres, con letras y números.', 1;

	IF @PasswordNuevo = @PasswordActual
		THROW 55921, 'La contraseña nueva debe ser distinta de la actual.', 1;

	DECLARE @salt_nuevo UNIQUEIDENTIFIER = NEWID();

	-- Es un cambio hecho por el propio usuario: UpdUsuario queda como el
	-- mismo @usu_id que se está actualizando.
	UPDATE dbo.gen_usuario
	   SET usu_password_hash = HASHBYTES('SHA2_256', CAST(@salt_nuevo AS VARCHAR(36)) + @PasswordNuevo),
		   usu_password_salt = @salt_nuevo,
		   usu_cambiar_password = 0,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @UsuId;
END;
GO

-- El administrador pone una contraseña temporal sin conocer la anterior: el
-- usuario tendrá que cambiarla al iniciar sesión. También quita el bloqueo
-- por intentos fallidos.
CREATE OR ALTER PROCEDURE [dbo].[paUsuarioPasswordRestablecer]
	@UsuId			INT,
	@PasswordNuevo	VARCHAR(256),
	@UsuIdAccion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_id = @UsuId)
		THROW 51032, 'El usuario indicado no existe.', 1;

	IF dbo.fnSeguridadPasswordValido(@PasswordNuevo) = 0
		THROW 55920, 'La contraseña debe tener al menos 8 caracteres, con letras y números.', 1;

	DECLARE @salt_nuevo UNIQUEIDENTIFIER = NEWID();

	UPDATE dbo.gen_usuario
	   SET usu_password_hash = HASHBYTES('SHA2_256', CAST(@salt_nuevo AS VARCHAR(36)) + @PasswordNuevo),
		   usu_password_salt = @salt_nuevo,
		   usu_cambiar_password = 1,
		   usu_intentos_fallidos = 0,
		   usu_bloqueado = 0,
		   UpdUsuario = @UsuIdAccion,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @UsuId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioDesbloquear]
	@UsuId			INT,
	@UsuIdAccion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_id = @UsuId)
		THROW 51032, 'El usuario indicado no existe.', 1;

	UPDATE dbo.gen_usuario
	   SET usu_intentos_fallidos = 0,
		   usu_bloqueado = 0,
		   UpdUsuario = @UsuIdAccion,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @UsuId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paSeguridadLogin]
	@UsuUsuario	VARCHAR(128),
	@UsuPassword	VARCHAR(256)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @usu_id INT, @hash VARBINARY(64), @salt UNIQUEIDENTIFIER, @intentos INT, @bloqueado BIT, @estado CHAR(1), @cambiar BIT;

	SELECT @usu_id = usu_id, @hash = usu_password_hash, @salt = usu_password_salt,
		   @intentos = usu_intentos_fallidos, @bloqueado = usu_bloqueado, @estado = usu_estado,
		   @cambiar = usu_cambiar_password
	FROM dbo.gen_usuario
	WHERE usu_usuario = @UsuUsuario;

	IF @usu_id IS NULL
	BEGIN
		SELECT 'error' AS estado, 'Usuario o contraseña no son válidos.' AS mensaje;
		RETURN;
	END

	IF @estado = 'I' OR @bloqueado = 1
	BEGIN
		SELECT 'error' AS estado, 'El usuario está inactivo o bloqueado. Contacte al administrador.' AS mensaje;
		RETURN;
	END

	-- Es el propio usuario quien produce el cambio (éxito o intento fallido):
	-- UpdUsuario queda como el mismo @usu_id encontrado arriba.
	IF HASHBYTES('SHA2_256', CAST(@salt AS VARCHAR(36)) + @UsuPassword) = @hash
	BEGIN
		UPDATE dbo.gen_usuario
		   SET usu_intentos_fallidos = 0, usu_ultimo_login = SYSDATETIME(),
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE usu_id = @usu_id;

		SELECT 'success' AS estado, 'Bienvenido, ' + @UsuUsuario + '.' AS mensaje, @usu_id AS usu_id,
			   @cambiar AS cambiar_password;
	END
	ELSE
	BEGIN
		UPDATE dbo.gen_usuario
		   SET usu_intentos_fallidos = usu_intentos_fallidos + 1,
			   usu_bloqueado = CASE WHEN usu_intentos_fallidos + 1 >= 5 THEN 1 ELSE 0 END,
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE usu_id = @usu_id;

		SELECT 'error' AS estado, 'Usuario o contraseña no son válidos.' AS mensaje;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioConsultarPorId]
	@UsuId INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT usu_id, usu_codigo, usu_usuario, usu_email, usu_fecha_ingreso,
		   usu_bloqueado, usu_ultimo_login, usu_estado, usu_cambiar_password
	FROM dbo.gen_usuario
	WHERE usu_id = @UsuId;

	SELECT srol.rol_id, srol.rol_codigo, srol.rol_nombre
	FROM dbo.sec_usuario_rol urol
	INNER JOIN dbo.sec_rol srol ON srol.rol_id = urol.rol_id
	WHERE urol.usu_id = @UsuId;
END;
GO

------------------------------------------------------------
-- 3. Siempre queda al menos un administrador
------------------------------------------------------------
-- Usuarios activos que pueden administrar usuarios (con un rol activo que
-- tenga el permiso SEGURIDAD_USUARIO_ADMIN activo).
CREATE OR ALTER FUNCTION [dbo].[fnSeguridadAdministradores] ()
RETURNS INT
AS
BEGIN
	RETURN (SELECT COUNT(DISTINCT usua.usu_id)
			FROM dbo.gen_usuario usua
			INNER JOIN dbo.sec_usuario_rol urol ON urol.usu_id = usua.usu_id
			INNER JOIN dbo.sec_rol srol ON srol.rol_id = urol.rol_id AND srol.rol_estado = 'A'
			INNER JOIN dbo.sec_rol_permiso rper ON rper.rol_id = srol.rol_id
			INNER JOIN dbo.sec_permiso perm ON perm.per_id = rper.per_id AND perm.per_estado = 'A'
			WHERE usua.usu_estado = 'A' AND perm.per_codigo = 'SEGURIDAD_USUARIO_ADMIN');
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioEliminar]
	@UsuId			INT,
	@UsuIdAccion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_id = @UsuId)
		THROW 51032, 'El usuario indicado no existe.', 1;

	IF @UsuId = @UsuIdAccion
		THROW 55922, 'No puede desactivar su propio usuario.', 1;

	BEGIN TRANSACTION;

	UPDATE dbo.gen_usuario
	   SET usu_estado = 'I',
		   UpdUsuario = @UsuIdAccion,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @UsuId;

	IF dbo.fnSeguridadAdministradores() = 0
		THROW 55923, 'Es el último usuario que puede administrar usuarios: asigne ese acceso a otro usuario antes de quitárselo.', 1;

	COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioRolRevocar]
	@UsuId			INT,
	@RolId			INT,
	@UsuIdAccion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	BEGIN TRANSACTION;

	DELETE FROM dbo.sec_usuario_rol WHERE usu_id = @UsuId AND rol_id = @RolId;

	IF dbo.fnSeguridadAdministradores() = 0
		THROW 55923, 'Es el último usuario que puede administrar usuarios: asigne ese acceso a otro usuario antes de quitárselo.', 1;

	COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRolEliminar]
	@RolId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.sec_rol WHERE rol_id = @RolId)
		THROW 51072, 'El rol indicado no existe.', 1;

	BEGIN TRANSACTION;

	UPDATE dbo.sec_rol
	   SET rol_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE rol_id = @RolId;

	IF dbo.fnSeguridadAdministradores() = 0
		THROW 55924, 'Es el último rol que permite administrar usuarios: no se puede inactivar.', 1;

	COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRolPermisoRevocar]
	@RolId INT,
	@PerId INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	BEGIN TRANSACTION;

	DELETE FROM dbo.sec_rol_permiso WHERE rol_id = @RolId AND per_id = @PerId;

	IF dbo.fnSeguridadAdministradores() = 0
		THROW 55925, 'Sin este permiso nadie podría administrar usuarios: asígnelo a otro rol activo antes de quitarlo.', 1;

	COMMIT;
END;
GO
