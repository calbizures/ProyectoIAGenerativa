/*
================================================================================
 59_correo_estado_cuenta.sql
 Envío del estado de cuenta al cliente por correo electrónico.

   - Compañía: servidor de correo saliente (SMTP) de la empresa: servidor,
     puerto, STARTTLS, usuario, contraseña (la guarda la aplicación cifrada,
     nunca en texto plano), remitente y una copia opcional (p. ej. cobros).
   - Bitácora de correos enviados (gen_correo_bitacora): a quién, qué, cuándo,
     quién lo envió y si el servidor lo aceptó o el error que devolvió.
   - La aplicación arma el estado de cuenta en PDF (datos del cliente, límite
     y crédito disponible, antigüedad, documentos y cuotas pendientes y
     movimientos) y lo envía al correo registrado del cliente.
   - Datos de ejemplo: correo @example.com (dominio reservado, no llega a
     nadie) para los clientes sin correo.

 Errores nuevos: 54901 a 54910.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Servidor de correo de la compañía
------------------------------------------------------------
IF COL_LENGTH('dbo.gen_compania', 'cia_smtp_servidor') IS NULL
	ALTER TABLE dbo.gen_compania ADD
		[cia_smtp_servidor]			VARCHAR(120)	NULL,
		[cia_smtp_puerto]			INT				NULL,
		[cia_smtp_ssl]				BIT				NOT NULL CONSTRAINT [DF_gen_compania_smtp_ssl] DEFAULT (1),	-- STARTTLS
		[cia_smtp_usuario]			VARCHAR(120)	NULL,
		[cia_smtp_clave]			VARCHAR(1000)	NULL,	-- cifrada por la aplicación
		[cia_smtp_remitente]		VARCHAR(120)	NULL,
		[cia_smtp_remitente_nombre]	VARCHAR(120)	NULL,
		[cia_smtp_copia]			VARCHAR(250)	NULL;	-- copia de cada envío (opcional)
GO
IF OBJECT_ID('dbo.CK_gen_compania_smtp', 'C') IS NULL
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [CK_gen_compania_smtp]
		CHECK ([cia_smtp_puerto] IS NULL OR [cia_smtp_puerto] BETWEEN 1 AND 65535);
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaCorreoConsultar]
	@CiaId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT comp.cia_id AS CiaId, comp.cia_nombre_comercial AS NombreComercial, comp.cia_smtp_servidor AS Servidor,
		   ISNULL(comp.cia_smtp_puerto, 587) AS Puerto, comp.cia_smtp_ssl AS Ssl, comp.cia_smtp_usuario AS Usuario,
		   comp.cia_smtp_clave AS ClaveCifrada, comp.cia_smtp_remitente AS Remitente, comp.cia_smtp_remitente_nombre AS RemitenteNombre,
		   comp.cia_smtp_copia AS Copia, comp.cia_telefono AS Telefono
	FROM dbo.gen_compania comp
	WHERE comp.cia_id = @CiaId;
END;
GO

-- @ClaveCifrada NULL conserva la contraseña guardada; @BorrarClave = 1 la quita.
CREATE OR ALTER PROCEDURE [dbo].[paCompaniaCorreoGuardar]
	@CiaId				INT,
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
		   @Copia = NULLIF(REPLACE(LTRIM(RTRIM(@Copia)), ' ', ''), ''), @ClaveCifrada = NULLIF(@ClaveCifrada, '');
	IF @Servidor IS NOT NULL AND @Remitente IS NULL
		THROW 54901, 'Indique el correo del remitente (la dirección desde la que se envían los correos).', 1;
	IF @Remitente IS NOT NULL AND @Remitente NOT LIKE '_%@_%._%'
		THROW 54902, 'El correo del remitente no es válido.', 1;
	IF @Copia IS NOT NULL AND EXISTS (SELECT 1 FROM STRING_SPLIT(REPLACE(@Copia, ';', ','), ',') WHERE value <> '' AND value NOT LIKE '_%@_%._%')
		THROW 54903, 'Uno de los correos de copia no es válido.', 1;
	IF @Puerto IS NOT NULL AND @Puerto NOT BETWEEN 1 AND 65535
		THROW 54904, 'El puerto va de 1 a 65535 (normalmente 587).', 1;
	UPDATE dbo.gen_compania
	   SET cia_smtp_servidor = @Servidor, cia_smtp_puerto = @Puerto, cia_smtp_ssl = ISNULL(@Ssl, 1), cia_smtp_usuario = @Usuario,
		   cia_smtp_clave = CASE WHEN @BorrarClave = 1 THEN NULL ELSE ISNULL(@ClaveCifrada, cia_smtp_clave) END,
		   cia_smtp_remitente = @Remitente, cia_smtp_remitente_nombre = @RemitenteNombre, cia_smtp_copia = @Copia,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cia_id = @CiaId;
	IF @@ROWCOUNT = 0
		THROW 54905, 'La compañía no existe.', 1;
END;
GO

------------------------------------------------------------
-- 2. Bitácora de correos
------------------------------------------------------------
IF OBJECT_ID('dbo.gen_correo_bitacora', 'U') IS NULL
CREATE TABLE [dbo].[gen_correo_bitacora](
	[gcb_id]			INT				IDENTITY(1, 1) NOT NULL,
	[cia_id]			INT				NOT NULL,
	[gcb_tipo]			VARCHAR(30)		NOT NULL,		-- ESTADO_CUENTA, PRUEBA
	[gcb_referencia_id]	INT				NULL,			-- cliente, documento...
	[gcb_destinatario]	VARCHAR(400)	NOT NULL,
	[gcb_copia]			VARCHAR(400)	NULL,
	[gcb_asunto]		VARCHAR(200)	NOT NULL,
	[gcb_adjunto]		VARCHAR(150)	NULL,
	[gcb_estado]		CHAR(1)			NOT NULL,		-- E enviado (el servidor lo aceptó), F falló
	[gcb_error]			VARCHAR(500)	NULL,
	[usu_id]			INT				NULL,
	[gcb_fecha]			DATETIME2(0)	NOT NULL CONSTRAINT [DF_gen_correo_bitacora_fecha] DEFAULT (SYSDATETIME()),
	CONSTRAINT [PK_gen_correo_bitacora] PRIMARY KEY ([gcb_id]),
	CONSTRAINT [FK_gen_correo_bitacora_compania] FOREIGN KEY ([cia_id]) REFERENCES dbo.gen_compania ([cia_id]),
	CONSTRAINT [FK_gen_correo_bitacora_usuario] FOREIGN KEY ([usu_id]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [CK_gen_correo_bitacora_estado] CHECK ([gcb_estado] IN ('E', 'F'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_gen_correo_bitacora_referencia')
	CREATE INDEX [IX_gen_correo_bitacora_referencia] ON dbo.gen_correo_bitacora ([gcb_tipo], [gcb_referencia_id], [gcb_fecha] DESC);
GO

CREATE OR ALTER PROCEDURE [dbo].[paCorreoBitacoraRegistrar]
	@CiaId			INT,
	@Tipo			VARCHAR(30),
	@ReferenciaId	INT = NULL,
	@Destinatario	VARCHAR(400),
	@Copia			VARCHAR(400) = NULL,
	@Asunto			VARCHAR(200),
	@Adjunto		VARCHAR(150) = NULL,
	@Estado			CHAR(1),
	@Error			VARCHAR(500) = NULL,
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @Estado NOT IN ('E', 'F')
		THROW 54906, 'El estado del envío es E (enviado) o F (falló).', 1;
	INSERT INTO dbo.gen_correo_bitacora (cia_id, gcb_tipo, gcb_referencia_id, gcb_destinatario, gcb_copia, gcb_asunto, gcb_adjunto, gcb_estado, gcb_error, usu_id)
	VALUES (@CiaId, @Tipo, @ReferenciaId, LEFT(@Destinatario, 400), LEFT(NULLIF(@Copia, ''), 400), LEFT(@Asunto, 200), @Adjunto, @Estado, LEFT(@Error, 500), @UsuId);
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCorreoBitacoraConsultar]
	@Tipo			VARCHAR(30) = NULL,
	@ReferenciaId	INT = NULL,
	@Cantidad		INT = 20
AS
BEGIN
	SET NOCOUNT ON;
	SELECT TOP (@Cantidad) bita.gcb_id AS GcbId, bita.gcb_tipo AS Tipo, bita.gcb_referencia_id AS ReferenciaId, bita.gcb_destinatario AS Destinatario,
		   bita.gcb_copia AS Copia, bita.gcb_asunto AS Asunto, bita.gcb_adjunto AS Adjunto, bita.gcb_estado AS Estado, bita.gcb_error AS Error,
		   bita.gcb_fecha AS Fecha, usua.usu_codigo AS Usuario
	FROM dbo.gen_correo_bitacora bita
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = bita.usu_id
	WHERE (@Tipo IS NULL OR bita.gcb_tipo = @Tipo) AND (@ReferenciaId IS NULL OR bita.gcb_referencia_id = @ReferenciaId)
	ORDER BY bita.gcb_id DESC;
END;
GO

------------------------------------------------------------
-- 3. Datos del cliente para el estado de cuenta
------------------------------------------------------------
-- Encabezado del estado de cuenta: datos de contacto, límite y crédito.
CREATE OR ALTER PROCEDURE [dbo].[paClienteEstadoCuentaDatos]
	@CliId	INT
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
	-- Límite, saldo y disponible como en la factura y los cobros (fnClienteCredito).
	SELECT clie.cli_id AS CliId, clie.cli_codigo AS Codigo, CONCAT_WS(' ', clie.cli_nombres, NULLIF(clie.cli_apellidos, '')) AS Nombre,
		   clie.cli_nit AS Nit, clie.cli_direccion AS Direccion, clie.cli_email AS Correo, clie.cli_telefono_celular AS Telefono,
		   cred.Limite, cred.Saldo, cred.Disponible,
		   (SELECT ISNULL(SUM(cuot.cpp_saldo_cuota), 0)
			FROM dbo.pos_cliente_plan_pagos cuot
			INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
			WHERE docu.cli_id = clie.cli_id AND cuot.cpp_saldo_cuota > 0 AND cuot.cpp_fecha_maxima_pago < @hoy) AS Vencido,
		   clie.cli_fecha_ultima_compra AS UltimaCompra,
		   (SELECT MAX(pago.ppe_fecha_pago) FROM dbo.pos_pago_enc pago WHERE pago.cli_id = clie.cli_id AND pago.ppe_estado = 'A') AS UltimoPago
	FROM dbo.pos_cliente clie
	CROSS APPLY dbo.fnClienteCredito(clie.cli_id) cred
	WHERE clie.cli_id = @CliId;
END;
GO

------------------------------------------------------------
-- 4. Datos de ejemplo
------------------------------------------------------------
-- Dominio reservado (RFC 2606): los correos de prueba no llegan a nadie.
UPDATE dbo.pos_cliente
   SET cli_email = CONCAT(LOWER(cli_codigo), '@example.com')
 WHERE cli_email IS NULL AND cli_codigo LIKE 'CLI%';
GO

PRINT '59_correo_estado_cuenta.sql aplicado.';
GO
