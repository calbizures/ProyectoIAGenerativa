/*
================================================================================
 83_contrasenas_pbkdf2.sql
 Contraseñas con PBKDF2 (hallazgo 5 de la auditoría del 02/11/2026).

 Antes la contraseña viajaba en texto hasta SQL Server y se guardaba como
 SHA-256(sal + contraseña): un solo cálculo, muy rápido de adivinar por
 fuerza bruta si alguien obtiene una copia de la base. Ahora:

   - La aplicación calcula PBKDF2-HMAC-SHA256 con sal aleatoria de 16 bytes
     y 600,000 iteraciones (recomendación de OWASP), y la base solo recibe y
     guarda el resultado. La contraseña ya no llega a la base.
   - gen_usuario.usu_password_iteraciones: iteraciones del hash. NULL = hash
     anterior (SHA-256), que se sigue aceptando y se reemplaza por PBKDF2 la
     primera vez que el usuario entra. Nadie tiene que cambiar su contraseña.
   - La regla de contraseña (8 caracteres, letras y números) y "la nueva debe
     ser distinta" se validan en la aplicación.

   paSeguridadLoginDatos                datos del usuario para verificar el
                                        hash en la aplicación.
   paSeguridadLoginRegistrar            resultado del intento: reinicia o suma
                                        intentos fallidos (bloqueo a los 5).
   paSeguridadPasswordLegadoVerificar   verifica un hash SHA-256 anterior (solo
                                        hasta que el usuario entra una vez).
   paUsuarioPasswordGuardar             guarda un hash nuevo (cambio,
                                        restablecimiento o migración).
   paUsuarioInsertar                    acepta el hash ya calculado (sigue
                                        aceptando @UsuPassword para los datos
                                        de prueba de los scripts 12 y 57).
   paUsuarioPasswordCambiar, paUsuarioPasswordRestablecer y paSeguridadLogin
   (anteriores, ya no los usa la aplicación) solo manejan hashes anteriores y
   marcan el que guardan como tal (iteraciones NULL).

 Si vuelves a correr el 66 o el 75, corre después este script.

 Errores nuevos: 55970.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('dbo.gen_usuario', 'usu_password_iteraciones') IS NULL
	ALTER TABLE dbo.gen_usuario ADD [usu_password_iteraciones] INT NULL;
GO

-- Por nombre de acceso (inicio de sesión) o por id (cambio de contraseña).
CREATE OR ALTER PROCEDURE [dbo].[paSeguridadLoginDatos]
	@UsuUsuario	VARCHAR(128) = NULL,
	@UsuId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT usu_id AS UsuId, usu_estado AS Estado, usu_bloqueado AS Bloqueado,
		   usu_cambiar_password AS CambiarPassword,
		   usu_password_hash AS Hash, usu_password_salt AS Salt,
		   usu_password_iteraciones AS Iteraciones
	FROM dbo.gen_usuario
	WHERE (@UsuId IS NOT NULL AND usu_id = @UsuId)
	   OR (@UsuId IS NULL AND usu_usuario = @UsuUsuario);
END;
GO

-- Mismo resultado que paSeguridadLogin (script 75): estado, mensaje, usu_id
-- y cambiar_password.
CREATE OR ALTER PROCEDURE [dbo].[paSeguridadLoginRegistrar]
	@UsuId	INT,
	@Exito	BIT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @usuario VARCHAR(128), @estado CHAR(1), @bloqueado BIT, @cambiar BIT;
	SELECT @usuario = usu_usuario, @estado = usu_estado, @bloqueado = usu_bloqueado,
		   @cambiar = usu_cambiar_password
	FROM dbo.gen_usuario WHERE usu_id = @UsuId;

	IF @usuario IS NULL
	BEGIN
		SELECT 'error' AS estado, 'Usuario o contraseña no son válidos.' AS mensaje;
		RETURN;
	END

	IF @estado = 'I' OR @bloqueado = 1
	BEGIN
		SELECT 'error' AS estado, 'El usuario está inactivo o bloqueado. Contacte al administrador.' AS mensaje;
		RETURN;
	END

	IF @Exito = 1
	BEGIN
		UPDATE dbo.gen_usuario
		   SET usu_intentos_fallidos = 0, usu_ultimo_login = SYSDATETIME(),
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE usu_id = @UsuId;

		SELECT 'success' AS estado, 'Bienvenido, ' + @usuario + '.' AS mensaje, @UsuId AS usu_id,
			   @cambiar AS cambiar_password;
	END
	ELSE
	BEGIN
		UPDATE dbo.gen_usuario
		   SET usu_intentos_fallidos = usu_intentos_fallidos + 1,
			   usu_bloqueado = CASE WHEN usu_intentos_fallidos + 1 >= 5 THEN 1 ELSE 0 END,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE usu_id = @UsuId;

		SELECT 'error' AS estado, 'Usuario o contraseña no son válidos.' AS mensaje;
	END
END;
GO

-- Solo para hashes anteriores (usu_password_iteraciones NULL).
CREATE OR ALTER PROCEDURE [dbo].[paSeguridadPasswordLegadoVerificar]
	@UsuId		INT,
	@Password	VARCHAR(256)
AS
BEGIN
	SET NOCOUNT ON;
	SELECT CAST(CASE WHEN EXISTS (
		SELECT 1 FROM dbo.gen_usuario
		WHERE usu_id = @UsuId
		  AND usu_password_iteraciones IS NULL
		  AND usu_password_hash = HASHBYTES('SHA2_256', CAST(usu_password_salt AS VARCHAR(36)) + @Password)
	) THEN 1 ELSE 0 END AS BIT) AS Valido;
END;
GO

-- @CambiarPassword: 1 = contraseña temporal (restablecida por el
-- administrador), 0 = la puso el propio usuario, NULL = no cambia la marca
-- (migración del hash al iniciar sesión). @Desbloquear quita el bloqueo.
CREATE OR ALTER PROCEDURE [dbo].[paUsuarioPasswordGuardar]
	@UsuId				INT,
	@Hash				VARBINARY(64),
	@Salt				UNIQUEIDENTIFIER,
	@Iteraciones		INT,
	@CambiarPassword	BIT = NULL,
	@Desbloquear		BIT = 0,
	@UsuIdAccion		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_id = @UsuId)
		THROW 51032, 'El usuario indicado no existe.', 1;

	IF @Hash IS NULL OR DATALENGTH(@Hash) < 32 OR @Salt IS NULL OR ISNULL(@Iteraciones, 0) < 100000
		THROW 55970, 'El hash de la contraseña no es válido.', 1;

	UPDATE dbo.gen_usuario
	   SET usu_password_hash = @Hash,
		   usu_password_salt = @Salt,
		   usu_password_iteraciones = @Iteraciones,
		   usu_cambiar_password = ISNULL(@CambiarPassword, usu_cambiar_password),
		   usu_intentos_fallidos = CASE WHEN @Desbloquear = 1 THEN 0 ELSE usu_intentos_fallidos END,
		   usu_bloqueado = CASE WHEN @Desbloquear = 1 THEN 0 ELSE usu_bloqueado END,
		   UpdUsuario = ISNULL(@UsuIdAccion, @UsuId),
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @UsuId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioInsertar]
	@UsuCodigo				VARCHAR(32),
	@UsuUsuario				VARCHAR(128),
	@UsuPassword			VARCHAR(256) = NULL,
	@UsuEmail				VARCHAR(128) = NULL,
	@UsuIdAccion			INT = NULL,
	@UsuId					INT OUTPUT,
	@UsuCambiarPassword		BIT = 0,
	@UsuPasswordHash		VARBINARY(64) = NULL,
	@UsuPasswordSalt		UNIQUEIDENTIFIER = NULL,
	@UsuPasswordIteraciones	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_usuario = @UsuUsuario)
		THROW 51031, 'Ya existe un usuario con ese nombre de acceso.', 1;

	DECLARE @hash VARBINARY(64), @salt UNIQUEIDENTIFIER, @iteraciones INT;

	IF @UsuPasswordHash IS NOT NULL
	BEGIN
		IF DATALENGTH(@UsuPasswordHash) < 32 OR @UsuPasswordSalt IS NULL OR ISNULL(@UsuPasswordIteraciones, 0) < 100000
			THROW 55970, 'El hash de la contraseña no es válido.', 1;
		SELECT @hash = @UsuPasswordHash, @salt = @UsuPasswordSalt, @iteraciones = @UsuPasswordIteraciones;
	END
	ELSE
	BEGIN
		-- Datos de prueba de los scripts: hash anterior, se migra al entrar.
		IF dbo.fnSeguridadPasswordValido(@UsuPassword) = 0
			THROW 55920, 'La contraseña debe tener al menos 8 caracteres, con letras y números.', 1;
		SET @salt = NEWID();
		SET @hash = HASHBYTES('SHA2_256', CAST(@salt AS VARCHAR(36)) + @UsuPassword);
	END

	INSERT INTO dbo.gen_usuario
		(usu_codigo, usu_usuario, usu_password_hash, usu_password_salt, usu_password_iteraciones,
		 usu_email, usu_cambiar_password, InsUsuario, InsFechaHora)
	VALUES
		(@UsuCodigo, @UsuUsuario, @hash, @salt, @iteraciones,
		 @UsuEmail, @UsuCambiarPassword, @UsuIdAccion, SYSDATETIME());

	SET @UsuId = SCOPE_IDENTITY();
END;
GO

-- Los procedimientos anteriores que calculaban SHA-256 con la contraseña en
-- texto ya no los usa la aplicación. Se dejan para quien los llame desde
-- scripts, pero ahora también marcan el hash como anterior (iteraciones NULL),
-- para que el inicio de sesión lo reconozca.
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
		   usu_password_iteraciones = NULL,
		   usu_cambiar_password = 1,
		   usu_intentos_fallidos = 0,
		   usu_bloqueado = 0,
		   UpdUsuario = @UsuIdAccion,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @UsuId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioPasswordCambiar]
	@UsuId				INT,
	@PasswordActual	VARCHAR(256),
	@PasswordNuevo		VARCHAR(256)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @salt UNIQUEIDENTIFIER, @hash VARBINARY(64), @iteraciones INT;

	SELECT @salt = usu_password_salt, @hash = usu_password_hash, @iteraciones = usu_password_iteraciones
	FROM dbo.gen_usuario WHERE usu_id = @UsuId;

	IF @salt IS NULL
		THROW 51032, 'El usuario indicado no existe.', 1;

	-- Un hash PBKDF2 solo lo puede verificar la aplicación.
	IF @iteraciones IS NOT NULL OR HASHBYTES('SHA2_256', CAST(@salt AS VARCHAR(36)) + @PasswordActual) <> @hash
		THROW 51033, 'La contraseña actual no es correcta.', 1;

	IF dbo.fnSeguridadPasswordValido(@PasswordNuevo) = 0
		THROW 55920, 'La contraseña debe tener al menos 8 caracteres, con letras y números.', 1;

	IF @PasswordNuevo = @PasswordActual
		THROW 55921, 'La contraseña nueva debe ser distinta de la actual.', 1;

	DECLARE @salt_nuevo UNIQUEIDENTIFIER = NEWID();

	UPDATE dbo.gen_usuario
	   SET usu_password_hash = HASHBYTES('SHA2_256', CAST(@salt_nuevo AS VARCHAR(36)) + @PasswordNuevo),
		   usu_password_salt = @salt_nuevo,
		   usu_password_iteraciones = NULL,
		   usu_cambiar_password = 0,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @UsuId;
END;
GO

-- Inicio de sesión anterior (la aplicación ya usa paSeguridadLoginDatos y
-- paSeguridadLoginRegistrar): solo acepta hashes anteriores.
CREATE OR ALTER PROCEDURE [dbo].[paSeguridadLogin]
	@UsuUsuario	VARCHAR(128),
	@UsuPassword	VARCHAR(256)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @usu_id INT, @valido BIT = 0;
	SELECT @usu_id = usu_id,
		   @valido = CASE WHEN usu_password_iteraciones IS NULL
						   AND usu_password_hash = HASHBYTES('SHA2_256', CAST(usu_password_salt AS VARCHAR(36)) + @UsuPassword)
						  THEN 1 ELSE 0 END
	FROM dbo.gen_usuario
	WHERE usu_usuario = @UsuUsuario;

	IF @usu_id IS NULL
	BEGIN
		SELECT 'error' AS estado, 'Usuario o contraseña no son válidos.' AS mensaje;
		RETURN;
	END

	EXEC dbo.paSeguridadLoginRegistrar @UsuId = @usu_id, @Exito = @valido;
END;
GO
