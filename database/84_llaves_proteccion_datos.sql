/*
================================================================================
 84_llaves_proteccion_datos.sql
 Llaves de Data Protection en la base (hallazgo 9 de la auditoría del
 02/11/2026).

 ASP.NET Core cifra con estas llaves la cookie de sesión, los borradores que
 se guardan en el navegador y la contraseña del correo (SMTP). Antes quedaban
 en una carpeta del servidor: al reinstalar, mover la aplicación o correrla
 en más de un servidor (nube), todos perdían la sesión y la contraseña del
 correo ya no se podía leer. En la base las comparten todos los servidores y
 se respaldan con ella.

   gen_proteccion_llave             una fila por llave (XML de ASP.NET Core).
   paProteccionLlaveListar          todas las llaves.
   paProteccionLlaveGuardar         agrega una llave (ASP.NET Core las rota
                                    cada 90 días; nunca se modifican).

 Las llaves permiten descifrar la sesión: la tabla no se expone en ninguna
 pantalla, y los respaldos de la base deben guardarse con el mismo cuidado.

 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.gen_proteccion_llave', 'U') IS NULL
CREATE TABLE [dbo].[gen_proteccion_llave](
	[gpl_id]			INT IDENTITY(1, 1)	NOT NULL CONSTRAINT [PK_gen_proteccion_llave] PRIMARY KEY,
	[gpl_nombre]		VARCHAR(200)		NOT NULL CONSTRAINT [UQ_gen_proteccion_llave_nombre] UNIQUE,
	[gpl_xml]			NVARCHAR(MAX)		NOT NULL,
	[InsFechaHora]		DATETIME2(0)		NOT NULL CONSTRAINT [DF_gen_proteccion_llave_fecha] DEFAULT (SYSDATETIME())
);
GO

CREATE OR ALTER PROCEDURE [dbo].[paProteccionLlaveListar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT gpl_xml AS Xml FROM dbo.gen_proteccion_llave ORDER BY gpl_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProteccionLlaveGuardar]
	@Nombre	VARCHAR(200),
	@Xml	NVARCHAR(MAX)
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_proteccion_llave WHERE gpl_nombre = @Nombre)
		INSERT INTO dbo.gen_proteccion_llave (gpl_nombre, gpl_xml) VALUES (@Nombre, @Xml);
END;
GO
