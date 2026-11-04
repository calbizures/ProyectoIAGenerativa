/*
================================================================================
 servidor/02_login_aplicacion.sql
 Login propio para la aplicación, en lugar de "sa" (hallazgo 3 de la
 auditoría del 02/11/2026).

 No es parte de instalar_01_al_NN.sql: lo corre quien administra el servidor,
 conectado como sysadmin.

 Crea el login erp_app (autenticación de SQL Server) con usuario en erp_db y
 solo estos permisos:
   - db_datareader y db_datawriter: leer y grabar datos (la aplicación hace
     algunas consultas directas y hay procedimientos con SQL dinámico, que no
     heredan el permiso del procedimiento).
   - EXECUTE sobre el esquema dbo: procedimientos, funciones y tipos tabla.
 No puede crear ni borrar tablas, ni tocar otras bases, ni administrar el
 servidor. Los scripts de instalación (NN_*.sql) se siguen corriendo como
 sysadmin.

 Antes de correrlo, escriba la contraseña en @Clave (mínimo 12 caracteres,
 con mayúsculas, minúsculas, números y símbolos). NO guarde este archivo con
 la contraseña ni la suba a GitHub: después de correrlo, borre la contraseña
 del archivo.

 Después:
   1. Cambie la cadena de conexión de la aplicación (no en appsettings.json
      del repositorio, sino en user-secrets o en el servidor):
        Server=<servidor>;Database=erp_db;User Id=erp_app;Password=<la clave>;TrustServerCertificate=True;
   2. Abra la aplicación y pruebe: login, una factura, una compra, un pago.
   3. Cuando todo funcione, cambie la contraseña de "sa" o desactívelo
      (ALTER LOGIN sa DISABLE) si usa otro login sysadmin para administrar.

 Se puede ejecutar más de una vez (si el login existe, le cambia la clave).
================================================================================
*/
USE master;
GO

-- ===== Ajuste aquí =====
DECLARE @Clave NVARCHAR(128) = N'';
-- =======================

IF LEN(@Clave) < 12
	THROW 50002, 'Escriba en @Clave una contraseña de al menos 12 caracteres.', 1;

DECLARE @sql NVARCHAR(MAX);
IF SUSER_ID(N'erp_app') IS NULL
	SET @sql = N'CREATE LOGIN [erp_app] WITH PASSWORD = N''' + REPLACE(@Clave, '''', '''''')
		+ N''', DEFAULT_DATABASE = [erp_db], CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;';
ELSE
	SET @sql = N'ALTER LOGIN [erp_app] WITH PASSWORD = N''' + REPLACE(@Clave, '''', '''''') + N''';';
EXEC sys.sp_executesql @sql;
GO

USE erp_db;
GO
-- Si el bloque anterior falló (sin contraseña), no hay login y no se hace nada.
IF SUSER_ID(N'erp_app') IS NOT NULL
BEGIN
	IF DATABASE_PRINCIPAL_ID(N'erp_app') IS NULL
		CREATE USER [erp_app] FOR LOGIN [erp_app] WITH DEFAULT_SCHEMA = [dbo];
	ALTER ROLE [db_datareader] ADD MEMBER [erp_app];
	ALTER ROLE [db_datawriter] ADD MEMBER [erp_app];
	GRANT EXECUTE ON SCHEMA::[dbo] TO [erp_app];
	PRINT 'Login erp_app listo. Cambie la cadena de conexión de la aplicación y pruebe antes de desactivar sa.';
END
GO
