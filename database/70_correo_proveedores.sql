/*
================================================================================
 70_correo_proveedores.sql
 Fase 4, punto 6: correo saliente por defecto con la cuenta de Gmail
 calbizures@gmail.com y otros tipos de salida configurables.

   - gen_compania.cia_smtp_proveedor: GMAIL, OUTLOOK (Outlook.com / Hotmail),
     OFFICE365 (Microsoft 365), YAHOO, SMTP (cualquier otro servidor) o
     CARPETA (no envía: guarda cada correo como archivo .eml en una carpeta
     del servidor, para pruebas o para revisarlo antes de mandarlo).
   - Por defecto (compañías sin correo configurado y compañías nuevas):
     Gmail, smtp.gmail.com, puerto 587, STARTTLS, usuario y remitente
     calbizures@gmail.com. La contraseña no se guarda aquí: Gmail exige una
     contraseña de aplicación (cuenta con verificación en dos pasos), que se
     escribe en General › Compañías › Correo saliente y queda cifrada.
   - No cambia el correo de una compañía que ya lo tenía configurado; solo le
     asigna el tipo según su servidor.

 Errores nuevos: 54906.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('dbo.gen_compania', 'cia_smtp_proveedor') IS NULL
	ALTER TABLE dbo.gen_compania ADD [cia_smtp_proveedor] VARCHAR(20) NULL;
GO
IF OBJECT_ID('dbo.CK_gen_compania_smtp_proveedor', 'C') IS NULL
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [CK_gen_compania_smtp_proveedor]
		CHECK ([cia_smtp_proveedor] IS NULL OR [cia_smtp_proveedor] IN ('GMAIL', 'OUTLOOK', 'OFFICE365', 'YAHOO', 'SMTP', 'CARPETA'));
GO

-- Valores por defecto para las compañías nuevas.
IF OBJECT_ID('dbo.DF_gen_compania_smtp_proveedor', 'D') IS NULL
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [DF_gen_compania_smtp_proveedor] DEFAULT ('GMAIL') FOR [cia_smtp_proveedor];
IF OBJECT_ID('dbo.DF_gen_compania_smtp_servidor', 'D') IS NULL
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [DF_gen_compania_smtp_servidor] DEFAULT ('smtp.gmail.com') FOR [cia_smtp_servidor];
IF OBJECT_ID('dbo.DF_gen_compania_smtp_puerto', 'D') IS NULL
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [DF_gen_compania_smtp_puerto] DEFAULT (587) FOR [cia_smtp_puerto];
IF OBJECT_ID('dbo.DF_gen_compania_smtp_usuario', 'D') IS NULL
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [DF_gen_compania_smtp_usuario] DEFAULT ('calbizures@gmail.com') FOR [cia_smtp_usuario];
IF OBJECT_ID('dbo.DF_gen_compania_smtp_remitente', 'D') IS NULL
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [DF_gen_compania_smtp_remitente] DEFAULT ('calbizures@gmail.com') FOR [cia_smtp_remitente];
GO

-- Compañías sin correo: Gmail por defecto. Las que ya tienen servidor
-- conservan su configuración y reciben el tipo que corresponde.
UPDATE dbo.gen_compania
   SET cia_smtp_proveedor = 'GMAIL', cia_smtp_servidor = 'smtp.gmail.com', cia_smtp_puerto = 587, cia_smtp_ssl = 1,
	   cia_smtp_usuario = 'calbizures@gmail.com', cia_smtp_remitente = 'calbizures@gmail.com',
	   cia_smtp_remitente_nombre = ISNULL(cia_smtp_remitente_nombre, cia_nombre_comercial), UpdFechaHora = SYSDATETIME()
 WHERE NULLIF(LTRIM(RTRIM(cia_smtp_servidor)), '') IS NULL;
UPDATE dbo.gen_compania
   SET cia_smtp_proveedor = CASE WHEN cia_smtp_servidor LIKE '%gmail%' THEN 'GMAIL'
								 WHEN cia_smtp_servidor LIKE '%office365%' THEN 'OFFICE365'
								 WHEN cia_smtp_servidor LIKE '%outlook%' OR cia_smtp_servidor LIKE '%hotmail%' OR cia_smtp_servidor LIKE '%live.com%' THEN 'OUTLOOK'
								 WHEN cia_smtp_servidor LIKE '%yahoo%' THEN 'YAHOO'
								 ELSE 'SMTP' END
 WHERE cia_smtp_proveedor IS NULL;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaCorreoConsultar]
	@CiaId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT comp.cia_id AS CiaId, comp.cia_nombre_comercial AS NombreComercial, ISNULL(comp.cia_smtp_proveedor, 'SMTP') AS Proveedor,
		   comp.cia_smtp_servidor AS Servidor, ISNULL(comp.cia_smtp_puerto, 587) AS Puerto, comp.cia_smtp_ssl AS Ssl, comp.cia_smtp_usuario AS Usuario,
		   comp.cia_smtp_clave AS ClaveCifrada, comp.cia_smtp_remitente AS Remitente, comp.cia_smtp_remitente_nombre AS RemitenteNombre,
		   comp.cia_smtp_copia AS Copia, comp.cia_telefono AS Telefono
	FROM dbo.gen_compania comp
	WHERE comp.cia_id = @CiaId;
END;
GO

-- @ClaveCifrada NULL conserva la contraseña guardada; @BorrarClave = 1 la quita.
-- Con @Proveedor CARPETA, @Servidor es la carpeta donde se guardan los .eml.
CREATE OR ALTER PROCEDURE [dbo].[paCompaniaCorreoGuardar]
	@CiaId				INT,
	@Proveedor			VARCHAR(20) = 'SMTP',
	@Servidor			VARCHAR(120) = NULL,
	@Puerto				INT = NULL,
	@Ssl				BIT = 1,
	@Usuario			VARCHAR(120) = NULL,
	@ClaveCifrada		VARCHAR(1000) = NULL,
	@BorrarClave		BIT = 0,
	@Remitente			VARCHAR(120) = NULL,
	@RemitenteNombre	VARCHAR(120) = NULL,
	@Copia				VARCHAR(250) = NULL,
	@UsuId				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT @Servidor = NULLIF(LTRIM(RTRIM(@Servidor)), ''), @Usuario = NULLIF(LTRIM(RTRIM(@Usuario)), ''),
		   @Remitente = NULLIF(LTRIM(RTRIM(@Remitente)), ''), @RemitenteNombre = NULLIF(LTRIM(RTRIM(@RemitenteNombre)), ''),
		   @Copia = NULLIF(REPLACE(LTRIM(RTRIM(@Copia)), ' ', ''), ''), @ClaveCifrada = NULLIF(@ClaveCifrada, ''),
		   @Proveedor = ISNULL(NULLIF(UPPER(LTRIM(RTRIM(@Proveedor))), ''), 'SMTP');
	IF @Proveedor NOT IN ('GMAIL', 'OUTLOOK', 'OFFICE365', 'YAHOO', 'SMTP', 'CARPETA')
		THROW 54906, 'El tipo de salida del correo es Gmail, Outlook, Microsoft 365, Yahoo, otro servidor SMTP o carpeta.', 1;
	IF @Servidor IS NOT NULL AND @Remitente IS NULL
		THROW 54901, 'Indique el correo del remitente (la dirección desde la que se envían los correos).', 1;
	IF @Remitente IS NOT NULL AND @Remitente NOT LIKE '_%@_%._%'
		THROW 54902, 'El correo del remitente no es válido.', 1;
	IF @Copia IS NOT NULL AND EXISTS (SELECT 1 FROM STRING_SPLIT(REPLACE(@Copia, ';', ','), ',') WHERE value <> '' AND value NOT LIKE '_%@_%._%')
		THROW 54903, 'Uno de los correos de copia no es válido.', 1;
	IF @Puerto IS NOT NULL AND @Puerto NOT BETWEEN 1 AND 65535
		THROW 54904, 'El puerto va de 1 a 65535 (normalmente 587).', 1;
	UPDATE dbo.gen_compania
	   SET cia_smtp_proveedor = @Proveedor, cia_smtp_servidor = @Servidor, cia_smtp_puerto = @Puerto, cia_smtp_ssl = ISNULL(@Ssl, 1),
		   cia_smtp_usuario = @Usuario,
		   cia_smtp_clave = CASE WHEN @BorrarClave = 1 THEN NULL ELSE ISNULL(@ClaveCifrada, cia_smtp_clave) END,
		   cia_smtp_remitente = @Remitente, cia_smtp_remitente_nombre = @RemitenteNombre, cia_smtp_copia = @Copia,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cia_id = @CiaId;
	IF @@ROWCOUNT = 0
		THROW 54905, 'La compañía no existe.', 1;
END;
GO

PRINT '70_correo_proveedores.sql aplicado.';
GO
