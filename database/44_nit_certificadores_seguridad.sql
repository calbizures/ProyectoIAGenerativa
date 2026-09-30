/*
================================================================================
 44_nit_certificadores_seguridad.sql
 Validación del NIT y del CUI, consulta del NIT al certificador FEL, registro
 automático de clientes, proveedores con saldo, usuarios con su empleado y
 vendedor, y permisos nuevos.

   1. Funciones: fnNitNormalizar, fnCuiValido y fnNitValido.
        NIT: dígito verificador módulo 11 (posiciones de derecha a izquierda
             desde 2; 11 - residuo; 10 = K; 11 = 0).
        CUI/DPI (13 dígitos, válido como NIT desde 2025): verificador del
             correlativo (dígitos 1-8 por su posición + 1, módulo 11 igual
             al noveno dígito) y departamento/municipio existentes.
        NIT de 9 dígitos tomado del CUI: se acepta si pasa cualquiera de
             los dos verificadores.
        C/F es válido. Un NIT vacío no se valida (el campo es opcional).
   2. Se aplica en toda la base con triggers que solo revisan el NIT nuevo o
      cambiado (los datos que ya existían se pueden seguir usando mientras
      no se toque su NIT; paNitRevisionConsultar los lista para corregirlos):
        clientes (NIT y DPI, excepto receptores extranjeros EXT), proveedores,
        compañías, empleados (NIT y DPI) y documentos (NIT del cliente o del
        proveedor en facturas, compras y notas).
      La carga de empleados desde Excel marca el NIT o DPI inválido en su fila.
   3. Catálogo de certificadores FEL (fel_certificador) con el servicio de
      consulta de NIT de cada uno: método, URLs, cuerpo con marcadores
      {nit} {usuario} {llave}, encabezado de autenticación y campo del
      nombre en la respuesta. La compañía elige su certificador en la
      configuración FEL y puede activar la consulta o cambiar la URL.
   4. Clientes por NIT: búsqueda por NIT normalizado (columna calculada con
      índice) y registro automático del cliente que no existe, con el nombre
      que devuelve el certificador (formato SAT "APELLIDO,APELLIDO,CASADA,
      NOMBRE,NOMBRE" o nombre libre).
   5. Proveedores con saldo pendiente (Pagos a proveedores).
   6. Usuarios con el nombre completo del empleado y el código del vendedor.
      El nombre del vendedor vinculado a un empleado se toma del empleado
      (se sincroniza al cambiar el empleado; ya no se escribe dos veces).
   7. Permisos nuevos: anular compras, vendedores y comisiones, traslados
      (enviar y recibir) y revisión de NIT; los cheques libres aceptan
      BANCOS_CHEQUE_EMITIR.

 Requiere 38. Errores 53801-53812. Se puede volver a correr.
================================================================================
*/
USE [erp_db];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Funciones de NIT y CUI
------------------------------------------------------------
-- Sin espacios, guiones, puntos ni diagonales y en mayúsculas: '1234567-9'
-- -> '12345679', 'c/f' -> 'CF'. Determinista para la columna calculada.
-- La usa la columna calculada pos_cliente.cli_nit_normalizado (con índice):
-- se crea una sola vez; para cambiarla hay que quitar antes esa columna.
IF OBJECT_ID('dbo.fnNitNormalizar', 'FN') IS NULL
	EXEC ('CREATE FUNCTION [dbo].[fnNitNormalizar] (@Nit VARCHAR(32))
RETURNS VARCHAR(32)
WITH SCHEMABINDING
AS
BEGIN
	RETURN NULLIF(UPPER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Nit)), '' '', ''''), ''-'', ''''), ''/'', ''''), ''.'', ''''), CHAR(9), '''')), '''');
END');
GO

-- Verificador del correlativo del CUI (dígitos 1 a 8, pesos 2 a 9, módulo 11).
CREATE OR ALTER FUNCTION [dbo].[fnCuiCorrelativoValido] (@Digitos VARCHAR(32))
RETURNS BIT
AS
BEGIN
	IF LEN(@Digitos) < 9 OR LEFT(@Digitos, 9) LIKE '%[^0-9]%'
		RETURN 0;
	DECLARE @i INT = 1, @suma INT = 0;
	WHILE @i <= 8
	BEGIN
		SET @suma += CAST(SUBSTRING(@Digitos, @i, 1) AS INT) * (@i + 1);
		SET @i += 1;
	END
	RETURN CASE WHEN @suma % 11 = CAST(SUBSTRING(@Digitos, 9, 1) AS INT) THEN 1 ELSE 0 END;
END;
GO

-- CUI/DPI de 13 dígitos: correlativo (8) + verificador (1) + departamento (2)
-- + municipio (2), con el municipio dentro de los del departamento.
CREATE OR ALTER FUNCTION [dbo].[fnCuiValido] (@Cui VARCHAR(32))
RETURNS BIT
AS
BEGIN
	DECLARE @c VARCHAR(32) = dbo.fnNitNormalizar(@Cui);
	IF @c IS NULL OR LEN(@c) <> 13 OR @c LIKE '%[^0-9]%'
		RETURN 0;
	DECLARE @depto INT = CAST(SUBSTRING(@c, 10, 2) AS INT), @muni INT = CAST(SUBSTRING(@c, 12, 2) AS INT);
	-- Municipios por departamento (01 Guatemala ... 22 Jutiapa).
	DECLARE @municipios CHAR(44) = '17081616141419082421093033210817140511110717';
	IF @depto NOT BETWEEN 1 AND 22 OR @muni < 1 OR @muni > CAST(SUBSTRING(@municipios, (@depto - 1) * 2 + 1, 2) AS INT)
		RETURN 0;
	RETURN dbo.fnCuiCorrelativoValido(@c);
END;
GO

-- 1 = válido (o vacío), 0 = inválido.
CREATE OR ALTER FUNCTION [dbo].[fnNitValido] (@Nit VARCHAR(32))
RETURNS BIT
AS
BEGIN
	DECLARE @n VARCHAR(32) = dbo.fnNitNormalizar(@Nit);
	IF @n IS NULL OR @n = 'CF'
		RETURN 1;
	IF LEN(@n) = 13 AND @n NOT LIKE '%[^0-9]%'
		RETURN dbo.fnCuiValido(@n);

	DECLARE @cuerpo VARCHAR(32) = LEFT(@n, LEN(@n) - 1), @verificador CHAR(1) = RIGHT(@n, 1);
	IF LEN(@n) < 2 OR @cuerpo LIKE '%[^0-9]%' OR @verificador NOT LIKE '[0-9K]'
		RETURN 0;

	DECLARE @i INT = LEN(@cuerpo), @peso INT = 2, @suma INT = 0;
	WHILE @i >= 1
	BEGIN
		SET @suma += CAST(SUBSTRING(@cuerpo, @i, 1) AS INT) * @peso;
		SET @peso += 1;
		SET @i -= 1;
	END
	DECLARE @resultado INT = (11 - @suma % 11) % 11;
	IF @verificador = CASE WHEN @resultado = 10 THEN 'K' ELSE CAST(@resultado AS CHAR(1)) END
		RETURN 1;
	-- NIT de 9 dígitos asignado con el CUI (inscritos desde 2023).
	IF LEN(@n) = 9 AND dbo.fnCuiCorrelativoValido(@n) = 1
		RETURN 1;
	RETURN 0;
END;
GO

------------------------------------------------------------
-- 2. Validación en toda la base (solo NIT nuevos o cambiados)
------------------------------------------------------------
CREATE OR ALTER TRIGGER [dbo].[trg_pos_cliente_nit] ON [dbo].[pos_cliente]
AFTER INSERT, UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT (UPDATE(cli_nit) OR UPDATE(cli_DPI) OR UPDATE(cli_fel_tipo_receptor))
		RETURN;
	DECLARE @dato VARCHAR(64), @mensaje NVARCHAR(300);
	SELECT TOP 1 @dato = ins.cli_nit
	FROM inserted ins LEFT JOIN deleted del ON del.cli_id = ins.cli_id
	WHERE ISNULL(ins.cli_fel_tipo_receptor, '') <> 'EXT'
	  AND (del.cli_id IS NULL OR ISNULL(del.cli_nit, '') <> ISNULL(ins.cli_nit, '') OR ISNULL(del.cli_fel_tipo_receptor, '') <> ISNULL(ins.cli_fel_tipo_receptor, ''))
	  AND dbo.fnNitValido(ins.cli_nit) = 0;
	IF @dato IS NOT NULL
	BEGIN
		SET @mensaje = CONCAT(N'El NIT ', @dato, N' no es válido: revise el dígito verificador (o use C/F o el CUI de 13 dígitos).');
		THROW 53801, @mensaje, 1;
	END
	SELECT TOP 1 @dato = ins.cli_DPI
	FROM inserted ins LEFT JOIN deleted del ON del.cli_id = ins.cli_id
	WHERE ISNULL(ins.cli_fel_tipo_receptor, '') <> 'EXT' AND NULLIF(LTRIM(RTRIM(ins.cli_DPI)), '') IS NOT NULL
	  AND (del.cli_id IS NULL OR ISNULL(del.cli_DPI, '') <> ISNULL(ins.cli_DPI, ''))
	  AND dbo.fnCuiValido(ins.cli_DPI) = 0;
	IF @dato IS NOT NULL
	BEGIN
		SET @mensaje = CONCAT(N'El DPI ', @dato, N' no es válido: el CUI tiene 13 dígitos y su verificador, departamento o municipio no cuadran.');
		THROW 53802, @mensaje, 1;
	END
END;
GO

CREATE OR ALTER TRIGGER [dbo].[trg_inv_proveedor_nit] ON [dbo].[inv_proveedor]
AFTER INSERT, UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT UPDATE(prv_nit)
		RETURN;
	DECLARE @dato VARCHAR(64), @mensaje NVARCHAR(300);
	SELECT TOP 1 @dato = ins.prv_nit
	FROM inserted ins LEFT JOIN deleted del ON del.prv_id = ins.prv_id
	WHERE (del.prv_id IS NULL OR ISNULL(del.prv_nit, '') <> ISNULL(ins.prv_nit, ''))
	  AND dbo.fnNitValido(ins.prv_nit) = 0;
	IF @dato IS NOT NULL
	BEGIN
		SET @mensaje = CONCAT(N'El NIT del proveedor ', @dato, N' no es válido: revise el dígito verificador.');
		THROW 53803, @mensaje, 1;
	END
END;
GO

CREATE OR ALTER TRIGGER [dbo].[trg_gen_compania_nit] ON [dbo].[gen_compania]
AFTER INSERT, UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT UPDATE(cia_nit)
		RETURN;
	DECLARE @dato VARCHAR(64), @mensaje NVARCHAR(300);
	SELECT TOP 1 @dato = ins.cia_nit
	FROM inserted ins LEFT JOIN deleted del ON del.cia_id = ins.cia_id
	WHERE (del.cia_id IS NULL OR ISNULL(del.cia_nit, '') <> ISNULL(ins.cia_nit, ''))
	  AND (dbo.fnNitValido(ins.cia_nit) = 0 OR dbo.fnNitNormalizar(ins.cia_nit) = 'CF');
	IF @dato IS NOT NULL
	BEGIN
		SET @mensaje = CONCAT(N'El NIT de la compañía ', @dato, N' no es válido: revise el dígito verificador.');
		THROW 53804, @mensaje, 1;
	END
END;
GO

CREATE OR ALTER TRIGGER [dbo].[trg_rrhhEmpleado_nit] ON [dbo].[rrhhEmpleado]
AFTER INSERT, UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @dato VARCHAR(64), @mensaje NVARCHAR(300);
	IF UPDATE(Nit)
	BEGIN
		SELECT TOP 1 @dato = ins.Nit
		FROM inserted ins LEFT JOIN deleted del ON del.IdEmpleado = ins.IdEmpleado
		WHERE (del.IdEmpleado IS NULL OR ISNULL(del.Nit, '') <> ISNULL(ins.Nit, ''))
		  AND (dbo.fnNitValido(ins.Nit) = 0 OR dbo.fnNitNormalizar(ins.Nit) = 'CF');
		IF @dato IS NOT NULL
		BEGIN
			SET @mensaje = CONCAT(N'El NIT del empleado ', @dato, N' no es válido: revise el dígito verificador.');
			THROW 53805, @mensaje, 1;
		END
	END
	IF UPDATE(NumeroDocumento) OR UPDATE(IdTipoDocumentoIdentificacion)
	BEGIN
		SELECT TOP 1 @dato = ins.NumeroDocumento
		FROM inserted ins
		INNER JOIN dbo.rrhhTipoDocumentoIdentificacion tdoc ON tdoc.IdTipoDocumentoIdentificacion = ins.IdTipoDocumentoIdentificacion AND tdoc.Descripcion = 'DPI'
		LEFT JOIN deleted del ON del.IdEmpleado = ins.IdEmpleado
		WHERE NULLIF(LTRIM(RTRIM(ins.NumeroDocumento)), '') IS NOT NULL
		  AND (del.IdEmpleado IS NULL OR ISNULL(del.NumeroDocumento, '') <> ISNULL(ins.NumeroDocumento, '')
			   OR ISNULL(del.IdTipoDocumentoIdentificacion, 0) <> ISNULL(ins.IdTipoDocumentoIdentificacion, 0))
		  AND dbo.fnCuiValido(ins.NumeroDocumento) = 0;
		IF @dato IS NOT NULL
		BEGIN
			SET @mensaje = CONCAT(N'El DPI del empleado ', @dato, N' no es válido: el CUI tiene 13 dígitos y su verificador, departamento o municipio no cuadran.');
			THROW 53806, @mensaje, 1;
		END
	END
END;
GO

-- Facturas, compras y notas: el NIT que se graba en el documento.
CREATE OR ALTER TRIGGER [dbo].[trg_inv_documento_enc_nit] ON [dbo].[inv_documento_enc]
AFTER INSERT, UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT (UPDATE(cli_nit) OR UPDATE(prv_nit))
		RETURN;
	DECLARE @dato VARCHAR(64), @mensaje NVARCHAR(300);
	SELECT TOP 1 @dato = ins.cli_nit
	FROM inserted ins
	LEFT JOIN deleted del ON del.enc_id = ins.enc_id
	LEFT JOIN dbo.pos_cliente clie ON clie.cli_id = ins.cli_id
	WHERE ISNULL(clie.cli_fel_tipo_receptor, '') <> 'EXT'
	  AND (del.enc_id IS NULL OR ISNULL(del.cli_nit, '') <> ISNULL(ins.cli_nit, ''))
	  AND dbo.fnNitValido(ins.cli_nit) = 0;
	IF @dato IS NULL
		SELECT TOP 1 @dato = ins.prv_nit
		FROM inserted ins LEFT JOIN deleted del ON del.enc_id = ins.enc_id
		WHERE (del.enc_id IS NULL OR ISNULL(del.prv_nit, '') <> ISNULL(ins.prv_nit, ''))
		  AND dbo.fnNitValido(ins.prv_nit) = 0;
	IF @dato IS NOT NULL
	BEGIN
		SET @mensaje = CONCAT(N'El NIT ', @dato, N' del documento no es válido: corrija el NIT del cliente o del proveedor.');
		THROW 53807, @mensaje, 1;
	END
END;
GO

-- NIT y DPI ya grabados que no pasan la validación, para corregirlos.
CREATE OR ALTER PROCEDURE [dbo].[paNitRevisionConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT 'Cliente' AS Tipo, cli_id AS Id, cli_codigo AS Codigo, LTRIM(RTRIM(CONCAT(cli_nombres, ' ', cli_apellidos))) AS Nombre,
		   'NIT' AS Dato, cli_nit AS Valor, '/clientes' AS Pantalla
	FROM dbo.pos_cliente
	WHERE ISNULL(cli_fel_tipo_receptor, '') <> 'EXT' AND dbo.fnNitValido(cli_nit) = 0
	UNION ALL
	SELECT 'Cliente', cli_id, cli_codigo, LTRIM(RTRIM(CONCAT(cli_nombres, ' ', cli_apellidos))), 'DPI', cli_DPI, '/clientes'
	FROM dbo.pos_cliente
	WHERE ISNULL(cli_fel_tipo_receptor, '') <> 'EXT' AND NULLIF(LTRIM(RTRIM(cli_DPI)), '') IS NOT NULL AND dbo.fnCuiValido(cli_DPI) = 0
	UNION ALL
	SELECT 'Proveedor', prv_id, prv_codigo, prv_nombre_comercial, 'NIT', prv_nit, '/proveedores'
	FROM dbo.inv_proveedor WHERE dbo.fnNitValido(prv_nit) = 0
	UNION ALL
	SELECT 'Compañía', cia_id, CAST(cia_id AS VARCHAR(16)), cia_nombre_comercial, 'NIT', cia_nit, '/general/companias'
	FROM dbo.gen_compania WHERE dbo.fnNitValido(cia_nit) = 0 OR dbo.fnNitNormalizar(cia_nit) = 'CF'
	UNION ALL
	SELECT 'Empleado', empl.IdEmpleado, empl.CodigoEmpleado, CONCAT_WS(' ', empl.PrimerNombre, empl.SegundoNombre, empl.PrimerApellido, empl.SegundoApellido),
		   'NIT', empl.Nit, '/rrhh/empleados'
	FROM dbo.rrhhEmpleado empl WHERE dbo.fnNitValido(empl.Nit) = 0
	UNION ALL
	SELECT 'Empleado', empl.IdEmpleado, empl.CodigoEmpleado, CONCAT_WS(' ', empl.PrimerNombre, empl.SegundoNombre, empl.PrimerApellido, empl.SegundoApellido),
		   'DPI', empl.NumeroDocumento, '/rrhh/empleados'
	FROM dbo.rrhhEmpleado empl
	INNER JOIN dbo.rrhhTipoDocumentoIdentificacion tdoc ON tdoc.IdTipoDocumentoIdentificacion = empl.IdTipoDocumentoIdentificacion AND tdoc.Descripcion = 'DPI'
	WHERE NULLIF(LTRIM(RTRIM(empl.NumeroDocumento)), '') IS NOT NULL AND dbo.fnCuiValido(empl.NumeroDocumento) = 0
	ORDER BY Tipo, Codigo;
END;
GO

-- Para probar un NIT desde la aplicación o SSMS.
CREATE OR ALTER PROCEDURE [dbo].[paNitValidar]
	@Nit	VARCHAR(32)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @n VARCHAR(32) = dbo.fnNitNormalizar(@Nit);
	SELECT @n AS Normalizado, dbo.fnNitValido(@Nit) AS Valido,
		   CASE WHEN @n IS NULL THEN 'VACIO' WHEN @n = 'CF' THEN 'CF'
				WHEN LEN(@n) = 13 AND @n NOT LIKE '%[^0-9]%' THEN 'CUI' ELSE 'NIT' END AS Tipo;
END;
GO

------------------------------------------------------------
-- 3. Certificadores FEL y su consulta de NIT
------------------------------------------------------------
IF OBJECT_ID('dbo.fel_certificador', 'U') IS NULL
CREATE TABLE [dbo].[fel_certificador](
	[fce_codigo]			VARCHAR(20)		NOT NULL,
	[fce_nombre]			VARCHAR(128)	NOT NULL,
	[fce_nit]				VARCHAR(16)		NULL,
	[fce_api_consulta_nit]	VARCHAR(128)	NULL,	-- nombre del servicio de consulta de NIT del certificador
	[fce_nit_metodo]		VARCHAR(6)		NULL,	-- GET o POST
	[fce_nit_url_pruebas]	VARCHAR(256)	NULL,	-- admite {nit}
	[fce_nit_url_produccion] VARCHAR(256)	NULL,
	[fce_nit_cuerpo]		VARCHAR(512)	NULL,	-- JSON con {nit} {usuario} {llave}
	[fce_nit_encabezado]	VARCHAR(64)		NULL,	-- encabezado que lleva {llave} (p. ej. Authorization)
	[fce_nit_campo_nombre]	VARCHAR(64)		NULL,	-- propiedad del JSON con el nombre (admite a.b)
	[fce_nit_implementado]	BIT				NOT NULL CONSTRAINT [DF_fel_certificador_implementado] DEFAULT (0),
	[fce_documentacion]		VARCHAR(256)	NULL,
	[fce_notas]				VARCHAR(512)	NULL,
	[fce_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_fel_certificador_estado] DEFAULT ('A'),
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NULL CONSTRAINT [DF_fel_certificador_ins] DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_fel_certificador] PRIMARY KEY ([fce_codigo]),
	CONSTRAINT [CK_fel_certificador_metodo] CHECK ([fce_nit_metodo] IS NULL OR [fce_nit_metodo] IN ('GET', 'POST'))
);
GO

-- Catálogo con lo que publica cada certificador. Los que no publican su
-- servicio quedan registrados para completar URL, cuerpo y campo del nombre
-- cuando el certificador los entregue (la aplicación usa estos datos tal cual).
MERGE dbo.fel_certificador AS dest
USING (VALUES
	('SIMULADOR', 'Simulador interno (sin validez fiscal)', NULL, 'Consulta simulada', NULL, NULL, NULL, NULL, NULL, 'nombre', 1, NULL,
	 'Devuelve un nombre de prueba para cualquier NIT válido. Para desarrollo y demostraciones.'),
	('INFILE', 'INFILE, S.A.', NULL, 'Consulta de Receptores (REST)', 'POST',
	 'https://consultareceptores.feel.com.gt/rest/action', 'https://consultareceptores.feel.com.gt/rest/action',
	 '{"emisor_codigo":"{usuario}","emisor_clave":"{llave}","nit_consulta":"{nit}"}', NULL, 'nombre', 1,
	 'https://consultareceptores.feel.com.gt',
	 'Usuario = prefijo/usuario del emisor asignado por INFILE; llave = clave del emisor. Devuelve nit, nombre y mensaje.'),
	('DIGIFACT', 'DIGIFACT, S.A.', NULL, 'Consulta RTU (GET api/RTU?NIT=)', 'GET',
	 'https://felgttestaws.digifact.com.gt/felapiv2/api/RTU?NIT={nit}', 'https://fel.digifact.com.gt/api/RTU?NIT={nit}',
	 NULL, 'Authorization', 'NOMBRE', 1, 'https://fel.digifact.com.gt/Help/Api/GET-api-RTU_NIT',
	 'Llave = token de Digifact (api/login/get_token). Confirme con Digifact la URL de pruebas y el campo del nombre.'),
	('G4S', 'G4S DOCUMENTA, S.A.', '60010207', 'Consulta de NIT (solicitar documentación)', NULL, NULL, NULL, NULL, NULL, NULL, 0,
	 'https://www.documenta.com.gt/', 'Integración por API/WebService; pida al certificador el servicio de consulta de NIT.'),
	('COFIDI', 'COFIDI, S.A.', '62469045', 'Consulta de NIT (solicitar documentación)', NULL, NULL, NULL, NULL, NULL, NULL, 0,
	 NULL, 'Pida al certificador el servicio de consulta de NIT.'),
	('MEGAPRINT', 'MEGAPRINT, S.A.', NULL, 'Consulta de NIT (solicitar documentación)', NULL, NULL, NULL, NULL, NULL, NULL, 0,
	 NULL, 'Pida al certificador el servicio de consulta de NIT.'),
	('AINNOVA', 'AINNOVA, S.A.', '56407734', 'Consulta de NIT (solicitar documentación)', NULL, NULL, NULL, NULL, NULL, NULL, 0,
	 NULL, 'Pida al certificador el servicio de consulta de NIT.'),
	('CCG', 'Cámara de Comercio de Guatemala', '351598', 'Consulta de NIT (solicitar documentación)', NULL, NULL, NULL, NULL, NULL, NULL, 0,
	 NULL, 'Pida al certificador el servicio de consulta de NIT.'),
	('CARI', 'CARI Latinoamérica, S.A.', '96941243', 'Consulta de NIT (solicitar documentación)', NULL, NULL, NULL, NULL, NULL, NULL, 0,
	 NULL, 'Pida al certificador el servicio de consulta de NIT.'),
	('EDICOM', 'EDICOM', NULL, 'Consulta de NIT (solicitar documentación)', NULL, NULL, NULL, NULL, NULL, NULL, 0,
	 NULL, 'Pida al certificador el servicio de consulta de NIT.')
) src (codigo, nombre, nit, api, metodo, url_pruebas, url_prod, cuerpo, encabezado, campo, implementado, documentacion, notas)
ON dest.fce_codigo = src.codigo
WHEN NOT MATCHED THEN
	INSERT (fce_codigo, fce_nombre, fce_nit, fce_api_consulta_nit, fce_nit_metodo, fce_nit_url_pruebas, fce_nit_url_produccion,
			fce_nit_cuerpo, fce_nit_encabezado, fce_nit_campo_nombre, fce_nit_implementado, fce_documentacion, fce_notas)
	VALUES (src.codigo, src.nombre, src.nit, src.api, src.metodo, src.url_pruebas, src.url_prod, src.cuerpo, src.encabezado,
			src.campo, src.implementado, src.documentacion, src.notas);
GO

IF COL_LENGTH('dbo.fel_configuracion', 'fco_consulta_nit_activa') IS NULL
	ALTER TABLE dbo.fel_configuracion ADD [fco_consulta_nit_activa] BIT NOT NULL
		CONSTRAINT [DF_fel_configuracion_consulta_nit] DEFAULT (1);
IF COL_LENGTH('dbo.fel_configuracion', 'fco_url_consulta_nit') IS NULL
	ALTER TABLE dbo.fel_configuracion ADD [fco_url_consulta_nit] VARCHAR(256) NULL;	-- NULL = la del catálogo según el ambiente
GO
-- Certificadores configurados que no estén en el catálogo (se agregan para la FK).
INSERT INTO dbo.fel_certificador (fce_codigo, fce_nombre)
SELECT DISTINCT conf.fco_certificador, conf.fco_certificador
FROM dbo.fel_configuracion conf
WHERE conf.fco_certificador IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.fel_certificador cert WHERE cert.fce_codigo = conf.fco_certificador);
IF OBJECT_ID('dbo.FK_fel_configuracion_certificador', 'F') IS NULL
	ALTER TABLE dbo.fel_configuracion ADD CONSTRAINT [FK_fel_configuracion_certificador]
		FOREIGN KEY ([fco_certificador]) REFERENCES dbo.fel_certificador ([fce_codigo]);
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelCertificadorConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT fce_codigo AS Codigo, fce_nombre AS Nombre, fce_nit AS Nit, fce_api_consulta_nit AS ApiConsultaNit,
		   fce_nit_metodo AS Metodo, fce_nit_url_pruebas AS UrlPruebas, fce_nit_url_produccion AS UrlProduccion,
		   fce_nit_cuerpo AS Cuerpo, fce_nit_encabezado AS Encabezado, fce_nit_campo_nombre AS CampoNombre,
		   fce_nit_implementado AS Implementado, fce_documentacion AS Documentacion, fce_notas AS Notas
	FROM dbo.fel_certificador
	WHERE fce_estado = 'A'
	ORDER BY CASE fce_codigo WHEN 'SIMULADOR' THEN 0 ELSE 1 END, fce_nombre;
END;
GO

-- Datos para consultar un NIT con el certificador de la compañía.
CREATE OR ALTER PROCEDURE [dbo].[paFelConsultaNitConfiguracion]
	@CiaId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT comp.cia_id AS CiaId, REPLACE(comp.cia_nit, '-', '') AS NitEmisor,
		   ISNULL(conf.fco_certificador, 'SIMULADOR') AS Certificador, cert.fce_nombre AS NombreCertificador,
		   ISNULL(conf.fco_consulta_nit_activa, 1) AS Activa, ISNULL(conf.fco_ambiente, 'PRUEBAS') AS Ambiente,
		   COALESCE(conf.fco_url_consulta_nit,
					CASE WHEN conf.fco_ambiente = 'PRODUCCION' THEN cert.fce_nit_url_produccion ELSE cert.fce_nit_url_pruebas END) AS Url,
		   cert.fce_nit_metodo AS Metodo, cert.fce_nit_cuerpo AS Cuerpo, cert.fce_nit_encabezado AS Encabezado,
		   cert.fce_nit_campo_nombre AS CampoNombre, ISNULL(cert.fce_nit_implementado, 0) AS Implementado,
		   conf.fco_usuario_api AS UsuarioApi, ISNULL(conf.fco_timeout_segundos, 30) AS TimeoutSegundos,
		   conf.fco_url_consulta_nit AS UrlPropia
	FROM dbo.gen_compania comp
	LEFT JOIN dbo.fel_configuracion conf ON conf.cia_id = comp.cia_id
	LEFT JOIN dbo.fel_certificador cert ON cert.fce_codigo = ISNULL(conf.fco_certificador, 'SIMULADOR')
	WHERE comp.cia_id = @CiaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelConsultaNitGuardar]
	@CiaId		INT,
	@Activa		BIT,
	@UrlPropia	VARCHAR(256) = NULL,
	@UsuId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.fel_configuracion WHERE cia_id = @CiaId)
		THROW 53808, 'Guarde primero la configuración FEL de la compañía.', 1;
	UPDATE dbo.fel_configuracion
	   SET fco_consulta_nit_activa = @Activa, fco_url_consulta_nit = NULLIF(LTRIM(RTRIM(@UrlPropia)), ''),
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cia_id = @CiaId;
END;
GO

------------------------------------------------------------
-- 4. Clientes por NIT
------------------------------------------------------------
IF COL_LENGTH('dbo.pos_cliente', 'cli_nit_normalizado') IS NULL
	ALTER TABLE dbo.pos_cliente ADD [cli_nit_normalizado] AS dbo.fnNitNormalizar(cli_nit) PERSISTED;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_pos_cliente_nit_normalizado' AND object_id = OBJECT_ID('dbo.pos_cliente'))
	CREATE INDEX [IX_pos_cliente_nit_normalizado] ON dbo.pos_cliente ([cli_nit_normalizado]);
GO

CREATE OR ALTER PROCEDURE [dbo].[paClienteBuscarPorNit]
	@Nit	VARCHAR(32)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @n VARCHAR(32) = dbo.fnNitNormalizar(@Nit);
	SELECT TOP 1 cli_id AS CliId, cli_codigo AS CliCodigo, cli_nombres AS CliNombres, cli_apellidos AS CliApellidos,
		   cli_nit AS CliNit, cli_estado AS CliEstado
	FROM dbo.pos_cliente
	WHERE cli_nit_normalizado = @n
	ORDER BY CASE cli_estado WHEN 'A' THEN 0 ELSE 1 END, cli_id;
END;
GO

-- Registra el cliente que no existe (devuelve el existente si ya está).
-- @Nombre en formato SAT "APELLIDO1,APELLIDO2,APELLIDO CASADA,NOMBRE1,NOMBRE2"
-- o libre (queda completo en nombres, p. ej. una empresa).
CREATE OR ALTER PROCEDURE [dbo].[paClienteRegistrarPorNit]
	@Nit		VARCHAR(32),
	@Nombre		VARCHAR(256),
	@Direccion	VARCHAR(128) = NULL,
	@UsuId		INT = NULL,
	@CliId		INT OUTPUT,
	@Nuevo		BIT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @n VARCHAR(32) = dbo.fnNitNormalizar(@Nit);
	IF @n IS NULL
		THROW 53809, 'Indique el NIT del cliente (o C/F).', 1;
	IF dbo.fnNitValido(@n) = 0
	BEGIN
		DECLARE @mensaje NVARCHAR(200) = CONCAT(N'El NIT ', @Nit, N' no es válido: revise el dígito verificador.');
		THROW 53801, @mensaje, 1;
	END

	SET @Nuevo = 0;
	SET @CliId = (SELECT TOP 1 cli_id FROM dbo.pos_cliente WHERE cli_nit_normalizado = @n
				  ORDER BY CASE cli_estado WHEN 'A' THEN 0 ELSE 1 END, cli_id);
	IF @CliId IS NOT NULL
		RETURN;

	SET @Nombre = NULLIF(LTRIM(RTRIM(@Nombre)), '');
	IF @n = 'CF' AND @Nombre IS NULL SET @Nombre = 'CONSUMIDOR FINAL';
	IF @Nombre IS NULL
		THROW 53810, 'Indique el nombre del cliente.', 1;

	-- Nombre SAT separado por comas.
	DECLARE @nombres VARCHAR(64), @apellidos VARCHAR(64);
	IF LEN(@Nombre) - LEN(REPLACE(@Nombre, ',', '')) >= 3
	BEGIN
		DECLARE @partes TABLE (orden INT IDENTITY(1, 1), parte VARCHAR(128));
		DECLARE @resto VARCHAR(256) = @Nombre + ',', @pos INT;
		WHILE LEN(@resto) > 0
		BEGIN
			SET @pos = CHARINDEX(',', @resto);
			INSERT INTO @partes (parte) VALUES (LTRIM(RTRIM(LEFT(@resto, @pos - 1))));
			SET @resto = SUBSTRING(@resto, @pos + 1, 256);
		END
		SELECT @apellidos = LEFT(CONCAT_WS(' ', NULLIF(MAX(CASE orden WHEN 1 THEN parte END), ''), NULLIF(MAX(CASE orden WHEN 2 THEN parte END), ''),
										   'DE ' + NULLIF(MAX(CASE orden WHEN 3 THEN parte END), '')), 64),
			   @nombres = LEFT(CONCAT_WS(' ', NULLIF(MAX(CASE orden WHEN 4 THEN parte END), ''), NULLIF(MAX(CASE orden WHEN 5 THEN parte END), ''),
										 NULLIF(MAX(CASE WHEN orden > 5 THEN parte END), '')), 64)
		FROM @partes;
		IF NULLIF(@nombres, '') IS NULL
			SELECT @nombres = LEFT(@apellidos, 64), @apellidos = NULL;
	END
	ELSE
		SET @nombres = LEFT(@Nombre, 64);

	BEGIN TRY
		BEGIN TRANSACTION;
		-- Siguiente código CLI### disponible.
		DECLARE @siguiente INT = ISNULL((SELECT MAX(TRY_CAST(SUBSTRING(cli_codigo, 4, 20) AS INT)) FROM dbo.pos_cliente WITH (UPDLOCK, HOLDLOCK)
										 WHERE cli_codigo LIKE 'CLI%'), 0) + 1;
		DECLARE @codigo VARCHAR(32) = CONCAT('CLI', RIGHT(CONCAT('000', @siguiente), CASE WHEN @siguiente > 999 THEN LEN(@siguiente) ELSE 3 END));
		DECLARE @nit_grabar VARCHAR(16) = CASE WHEN @n = 'CF' THEN 'CF'
											   WHEN LEN(@n) = 13 THEN @n
											   ELSE CONCAT(LEFT(@n, LEN(@n) - 1), '-', RIGHT(@n, 1)) END;
		EXEC dbo.sp_cliente_insertar @cli_codigo = @codigo, @cli_nombres = @nombres, @cli_apellidos = @apellidos,
			@cli_direccion = @Direccion, @cli_nit = @nit_grabar, @usu_id = @UsuId, @cli_id = @CliId OUTPUT;
		SET @Nuevo = 1;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 5. Proveedores con saldo pendiente
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCxpProveedoresConSaldoConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT prov.prv_id AS PrvId, prov.prv_codigo AS Codigo, prov.prv_nombre_comercial AS Nombre,
		   SUM(cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0)) AS Saldo,
		   SUM(CASE WHEN cuot.ppg_fecha_pago < CAST(GETDATE() AS DATE) THEN cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) ELSE 0 END) AS Vencido,
		   COUNT(DISTINCT docu.enc_id) AS Facturas
	FROM dbo.inv_proveedor_plan_pago cuot
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = docu.prv_id
	WHERE cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) > 0
	GROUP BY prov.prv_id, prov.prv_codigo, prov.prv_nombre_comercial
	ORDER BY prov.prv_nombre_comercial;
END;
GO

------------------------------------------------------------
-- 6. Usuarios con su empleado y vendedor
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_usuario_consultar]
	@usu_usuario	VARCHAR(128) = NULL,
	@usu_estado		CHAR(1) = 'A',
	@pagina			INT = 1,
	@tamanio_pagina	INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT usua.usu_id, usua.usu_codigo, usua.usu_usuario, usua.usu_email, usua.usu_fecha_ingreso,
		   usua.usu_bloqueado, usua.usu_ultimo_login, usua.usu_estado,
		   usua.IdEmpleado AS IdEmpleado,
		   NULLIF(CONCAT_WS(' ', empl.PrimerNombre, empl.SegundoNombre, empl.PrimerApellido, empl.SegundoApellido,
							'de ' + NULLIF(empl.ApellidoCasada, '')), '') AS Empleado,
		   vend.pve_codigo AS VendedorCodigo
	FROM dbo.gen_usuario usua
	LEFT JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = usua.IdEmpleado
	OUTER APPLY (SELECT TOP 1 vend.pve_codigo FROM dbo.pos_vendedor vend
				 WHERE vend.IdEmpleado = usua.IdEmpleado AND usua.IdEmpleado IS NOT NULL
				 ORDER BY CASE vend.pve_estado WHEN 'A' THEN 0 ELSE 1 END, vend.pve_id) vend
	WHERE (@usu_estado IS NULL OR usua.usu_estado = @usu_estado)
	  AND (@usu_usuario IS NULL OR usua.usu_usuario LIKE '%' + @usu_usuario + '%'
		   OR CONCAT_WS(' ', empl.PrimerNombre, empl.SegundoNombre, empl.PrimerApellido, empl.SegundoApellido) LIKE '%' + @usu_usuario + '%')
	ORDER BY usua.usu_usuario
	OFFSET (@pagina - 1) * @tamanio_pagina ROWS FETCH NEXT @tamanio_pagina ROWS ONLY;
END;
GO

-- El nombre del vendedor vinculado a un empleado es el del empleado: se
-- mantiene al día cuando cambia el empleado o cuando se vincula el vendedor.
CREATE OR ALTER TRIGGER [dbo].[trg_rrhhEmpleado_vendedor_nombre] ON [dbo].[rrhhEmpleado]
AFTER UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT (UPDATE(PrimerNombre) OR UPDATE(SegundoNombre) OR UPDATE(PrimerApellido) OR UPDATE(SegundoApellido))
		RETURN;
	UPDATE vend
	   SET pve_nombres = LEFT(CONCAT_WS(' ', ins.PrimerNombre, ins.SegundoNombre), 64),
		   pve_apellidos = LEFT(CONCAT_WS(' ', ins.PrimerApellido, ins.SegundoApellido), 64),
		   UpdFechaHora = SYSDATETIME()
	FROM dbo.pos_vendedor vend
	INNER JOIN inserted ins ON ins.IdEmpleado = vend.IdEmpleado;
END;
GO

CREATE OR ALTER TRIGGER [dbo].[trg_pos_vendedor_empleado_nombre] ON [dbo].[pos_vendedor]
AFTER INSERT, UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT (UPDATE(IdEmpleado) OR UPDATE(pve_nombres) OR UPDATE(pve_apellidos))
		RETURN;
	UPDATE vend
	   SET pve_nombres = LEFT(CONCAT_WS(' ', empl.PrimerNombre, empl.SegundoNombre), 64),
		   pve_apellidos = LEFT(CONCAT_WS(' ', empl.PrimerApellido, empl.SegundoApellido), 64)
	FROM dbo.pos_vendedor vend
	INNER JOIN inserted ins ON ins.pve_id = vend.pve_id
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = ins.IdEmpleado
	WHERE ISNULL(vend.pve_nombres, '') <> LEFT(CONCAT_WS(' ', empl.PrimerNombre, empl.SegundoNombre), 64)
	   OR ISNULL(vend.pve_apellidos, '') <> LEFT(CONCAT_WS(' ', empl.PrimerApellido, empl.SegundoApellido), 64);
END;
GO

-- Los vendedores ya vinculados quedan con el nombre de su empleado.
UPDATE vend
   SET pve_nombres = LEFT(CONCAT_WS(' ', empl.PrimerNombre, empl.SegundoNombre), 64),
	   pve_apellidos = LEFT(CONCAT_WS(' ', empl.PrimerApellido, empl.SegundoApellido), 64)
FROM dbo.pos_vendedor vend
INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = vend.IdEmpleado
WHERE ISNULL(vend.pve_nombres, '') <> LEFT(CONCAT_WS(' ', empl.PrimerNombre, empl.SegundoNombre), 64)
   OR ISNULL(vend.pve_apellidos, '') <> LEFT(CONCAT_WS(' ', empl.PrimerApellido, empl.SegundoApellido), 64);
GO

------------------------------------------------------------
-- 7. Permisos nuevos
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT v.modulo, v.codigo, v.descripcion
FROM (VALUES
	('COMPRAS',    'COMPRAS_DOCUMENTO_ANULAR',     'Anular compras'),
	('VENTAS',     'VENTAS_VENDEDOR_ADMIN',        'Vendedores y comisiones'),
	('INVENTARIO', 'INVENTARIO_TRASLADO_ENVIAR',   'Traslados entre bodegas: enviar'),
	('INVENTARIO', 'INVENTARIO_TRASLADO_RECIBIR',  'Traslados entre bodegas: recibir (en la bodega destino)'),
	('GENERAL',    'GENERAL_NIT_REVISION',         'Revisión de NIT y DPI inválidos')
) v (modulo, codigo, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso perm WHERE perm.per_codigo = v.codigo);
GO

-- Asignación inicial: el administrador todo; el contador anula compras, revisa
-- NIT y recibe traslados; el cajero recibe traslados en su sucursal.
INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT rol.rol_id, perm.per_id
FROM (VALUES
	('Administrador', 'COMPRAS_DOCUMENTO_ANULAR'), ('Administrador', 'VENTAS_VENDEDOR_ADMIN'),
	('Administrador', 'INVENTARIO_TRASLADO_ENVIAR'), ('Administrador', 'INVENTARIO_TRASLADO_RECIBIR'),
	('Administrador', 'GENERAL_NIT_REVISION'),
	('Contador', 'COMPRAS_DOCUMENTO_ANULAR'), ('Contador', 'GENERAL_NIT_REVISION'), ('Contador', 'INVENTARIO_TRASLADO_RECIBIR'),
	('Cajero', 'INVENTARIO_TRASLADO_RECIBIR')
) v (rol, permiso)
INNER JOIN dbo.sec_rol rol ON rol.rol_nombre = v.rol
INNER JOIN dbo.sec_permiso perm ON perm.per_codigo = v.permiso
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO

UPDATE dbo.sec_permiso SET per_descripcion = 'Emitir cheques libres (sin administrar cuentas bancarias)'
WHERE per_codigo = 'BANCOS_CHEQUE_EMITIR' AND per_descripcion = 'Emitir cheques';
UPDATE dbo.sec_permiso SET per_descripcion = 'Registrar asientos manuales (reservado: aún no hay pantalla de pólizas manuales)'
WHERE per_codigo = 'CONTABILIDAD_ASIENTO_MANUAL' AND per_descripcion = 'Registrar asientos manuales';
GO

------------------------------------------------------------
-- 8. Carga de empleados: NIT y DPI inválidos en su fila
------------------------------------------------------------
-- Igual que en 38, con el NIT y el DPI validados en cada fila.
CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoCargaProcesar]
	@CiaId			INT,
	@Filas			dbo.rrhh_empleado_carga_type READONLY,
	@SoloValidar	BIT = 1,
	@UsuId			INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @periodicidad CHAR(1) = (SELECT cia_periodicidad_nomina FROM dbo.gen_compania WHERE cia_id = @CiaId);

	DECLARE @datos TABLE (Fila INT PRIMARY KEY, IdEmpleado INT, Codigo VARCHAR(16), PrimerNombre VARCHAR(50), SegundoNombre VARCHAR(50),
						  PrimerApellido VARCHAR(50), SegundoApellido VARCHAR(50), Genero CHAR(1), FechaNacimiento DATE, FechaIngreso DATE,
						  TipoDocumento VARCHAR(50), IdTipoDocumento INT, NumeroDocumento VARCHAR(32), AfiliacionIGSS VARCHAR(20), Nit VARCHAR(20),
						  Email VARCHAR(100), Direccion VARCHAR(200), Plaza VARCHAR(100), IdPlaza INT, PlazasIguales INT, SalarioBase NUMERIC(12, 2),
						  TipoNomina CHAR(1), FormaPago CHAR(1), Banco VARCHAR(16), GefId INT, TipoCuenta CHAR(1), NumeroCuenta VARCHAR(30));
	INSERT INTO @datos
	SELECT fila.Fila, empl.IdEmpleado, NULLIF(LTRIM(RTRIM(fila.Codigo)), ''), NULLIF(LTRIM(RTRIM(fila.PrimerNombre)), ''),
		   NULLIF(LTRIM(RTRIM(fila.SegundoNombre)), ''), NULLIF(LTRIM(RTRIM(fila.PrimerApellido)), ''), NULLIF(LTRIM(RTRIM(fila.SegundoApellido)), ''),
		   NULLIF(UPPER(LTRIM(RTRIM(fila.Genero))), ''), fila.FechaNacimiento, fila.FechaIngreso,
		   NULLIF(LTRIM(RTRIM(fila.TipoDocumento)), ''), tdoc.IdTipoDocumentoIdentificacion, NULLIF(LTRIM(RTRIM(fila.NumeroDocumento)), ''),
		   NULLIF(LTRIM(RTRIM(fila.AfiliacionIGSS)), ''), NULLIF(LTRIM(RTRIM(fila.Nit)), ''), NULLIF(LTRIM(RTRIM(fila.Email)), ''),
		   NULLIF(LTRIM(RTRIM(fila.Direccion)), ''), NULLIF(LTRIM(RTRIM(fila.Plaza)), ''), plaz.IdPlaza, plaz.Iguales, fila.SalarioBase,
		   ISNULL(NULLIF(UPPER(LTRIM(RTRIM(fila.TipoNomina))), ''), @periodicidad), NULLIF(UPPER(LTRIM(RTRIM(fila.FormaPago))), ''),
		   NULLIF(LTRIM(RTRIM(fila.Banco)), ''), enti.gef_id, NULLIF(UPPER(LTRIM(RTRIM(fila.TipoCuenta))), ''), NULLIF(LTRIM(RTRIM(fila.NumeroCuenta)), '')
	FROM @Filas fila
	LEFT JOIN dbo.rrhhEmpleado empl ON empl.CodigoEmpleado = LTRIM(RTRIM(fila.Codigo))
	LEFT JOIN dbo.rrhhTipoDocumentoIdentificacion tdoc ON tdoc.Descripcion = LTRIM(RTRIM(fila.TipoDocumento))
	OUTER APPLY (SELECT MIN(plza.IdPlaza) AS IdPlaza, COUNT(*) AS Iguales FROM dbo.rrhhPlaza plza
				 WHERE plza.Descripcion = LTRIM(RTRIM(fila.Plaza)) AND plza.Estado = 'A') plaz
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_codigo = LTRIM(RTRIM(fila.Banco));

	DECLARE @mensajes TABLE (Fila INT, Tipo CHAR(1), Mensaje NVARCHAR(400));
	IF @periodicidad IS NULL
		INSERT INTO @mensajes VALUES (0, 'E', N'La compañía indicada no existe.');

	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT Fila, 'E', Mensaje FROM (
		SELECT Fila, CASE
			WHEN Codigo IS NULL OR PrimerNombre IS NULL OR PrimerApellido IS NULL THEN N'El código, el primer nombre y el primer apellido son obligatorios.'
			WHEN IdEmpleado IS NULL AND FechaIngreso IS NULL THEN N'Falta la fecha de ingreso.'
			WHEN SalarioBase IS NULL OR SalarioBase < 0 THEN N'El salario base es obligatorio y no puede ser negativo.'
			WHEN Genero IS NOT NULL AND Genero NOT IN ('M','F') THEN N'El género debe ser M o F.'
			WHEN TipoDocumento IS NOT NULL AND IdTipoDocumento IS NULL THEN CONCAT(N'El tipo de documento "', TipoDocumento, N'" no existe.')
			WHEN Nit IS NOT NULL AND (dbo.fnNitValido(Nit) = 0 OR dbo.fnNitNormalizar(Nit) = 'CF') THEN CONCAT(N'El NIT ', Nit, N' no es válido: revise el dígito verificador.')
			WHEN TipoDocumento = 'DPI' AND NumeroDocumento IS NOT NULL AND dbo.fnCuiValido(NumeroDocumento) = 0
				THEN CONCAT(N'El DPI ', NumeroDocumento, N' no es válido: el CUI tiene 13 dígitos con verificador, departamento y municipio.')
			WHEN Plaza IS NOT NULL AND IdPlaza IS NULL THEN CONCAT(N'La plaza "', Plaza, N'" no existe o está inactiva.')
			WHEN Plaza IS NOT NULL AND PlazasIguales > 1 THEN CONCAT(N'Hay varias plazas llamadas "', Plaza, N'"; renómbrelas para distinguirlas.')
			WHEN TipoNomina NOT IN ('S','Q','M') THEN N'El tipo de nómina debe ser S (semanal), Q (quincenal) o M (mensual).'
			WHEN FormaPago IS NULL OR FormaPago NOT IN ('T','C') THEN N'La forma de pago debe ser T (transferencia) o C (cheque); no se paga en efectivo.'
			WHEN Banco IS NOT NULL AND GefId IS NULL THEN CONCAT(N'El banco "', Banco, N'" no existe.')
			WHEN TipoCuenta IS NOT NULL AND TipoCuenta NOT IN ('M','A') THEN N'El tipo de cuenta debe ser M (monetaria) o A (ahorro).'
			WHEN FormaPago = 'T' AND (GefId IS NULL OR TipoCuenta IS NULL OR NumeroCuenta IS NULL)
				THEN N'Para pagar por transferencia indique el banco, el tipo y el número de cuenta.'
		END AS Mensaje FROM @datos) vali
	WHERE Mensaje IS NOT NULL;

	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT dato.Fila, 'E', CONCAT(N'El código ', dato.Codigo, N' se repite en el archivo.')
	FROM @datos dato WHERE dato.Codigo IS NOT NULL AND EXISTS (SELECT 1 FROM @datos otro WHERE otro.Codigo = dato.Codigo AND otro.Fila < dato.Fila);

	-- Una plaza solo puede tener un empleado activo (en la base o en el archivo).
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT dato.Fila, 'E', CONCAT(N'La plaza "', dato.Plaza, N'" ya la ocupa ', ISNULL(ocup.CodigoEmpleado, N'otra fila del archivo'), N'.')
	FROM @datos dato
	OUTER APPLY (SELECT TOP 1 empl.CodigoEmpleado FROM dbo.rrhhEmpleado empl
				 WHERE empl.IdPlaza = dato.IdPlaza AND empl.Estado = 'A' AND empl.CodigoEmpleado <> dato.Codigo
				   AND NOT EXISTS (SELECT 1 FROM @datos otro WHERE otro.Codigo = empl.CodigoEmpleado AND ISNULL(otro.IdPlaza, 0) <> dato.IdPlaza)) ocup
	WHERE dato.IdPlaza IS NOT NULL
	  AND (ocup.CodigoEmpleado IS NOT NULL
		   OR EXISTS (SELECT 1 FROM @datos otro WHERE otro.IdPlaza = dato.IdPlaza AND otro.Fila < dato.Fila));

	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT Fila, 'A', CONCAT(N'El empleado ', Codigo, N' ya existe: se actualizarán sus datos.')
	FROM @datos WHERE IdEmpleado IS NOT NULL;

	IF NOT EXISTS (SELECT 1 FROM @datos)
		INSERT INTO @mensajes VALUES (0, 'E', N'El archivo no tiene filas.');

	DECLARE @grabados INT = 0;
	IF @SoloValidar = 0 AND NOT EXISTS (SELECT 1 FROM @mensajes WHERE Tipo = 'E')
	BEGIN
		DECLARE @fila INT, @id INT, @resultado INT;
		BEGIN TRY
			BEGIN TRANSACTION;
			DECLARE filas CURSOR LOCAL FAST_FORWARD FOR SELECT Fila FROM @datos ORDER BY Fila;
			OPEN filas;
			FETCH NEXT FROM filas INTO @fila;
			WHILE @@FETCH_STATUS = 0
			BEGIN
				-- Los datos opcionales que vienen vacíos conservan lo que ya tenía el empleado.
				DECLARE @Codigo VARCHAR(16), @PrimerNombre VARCHAR(50), @SegundoNombre VARCHAR(50), @PrimerApellido VARCHAR(50),
						@SegundoApellido VARCHAR(50), @ApellidoCasada VARCHAR(50), @Genero CHAR(1), @FechaNacimiento DATE, @FechaIngreso DATE,
						@Direccion VARCHAR(200), @IdTipoDocumento INT, @NumeroDocumento VARCHAR(32), @AfiliacionIGSS VARCHAR(20), @Nit VARCHAR(20),
						@Email VARCHAR(100), @IdPlaza INT, @SalarioBase NUMERIC(12, 2), @TipoNomina CHAR(1), @FormaPago CHAR(1), @GefId INT,
						@TipoCuenta CHAR(1), @NumeroCuenta VARCHAR(30);
				SELECT @id = dato.IdEmpleado, @Codigo = dato.Codigo, @PrimerNombre = dato.PrimerNombre,
					   @SegundoNombre = COALESCE(dato.SegundoNombre, empl.SegundoNombre), @PrimerApellido = dato.PrimerApellido,
					   @SegundoApellido = COALESCE(dato.SegundoApellido, empl.SegundoApellido), @ApellidoCasada = empl.ApellidoCasada,
					   @Genero = COALESCE(dato.Genero, empl.Genero), @FechaNacimiento = COALESCE(dato.FechaNacimiento, empl.FechaNacimiento),
					   @FechaIngreso = COALESCE(dato.FechaIngreso, empl.FechaIngreso), @Direccion = COALESCE(dato.Direccion, empl.Direccion),
					   @IdTipoDocumento = COALESCE(dato.IdTipoDocumento, empl.IdTipoDocumentoIdentificacion),
					   @NumeroDocumento = COALESCE(dato.NumeroDocumento, empl.NumeroDocumento),
					   @AfiliacionIGSS = COALESCE(dato.AfiliacionIGSS, empl.NumeroAfiliacionIGSS), @Nit = COALESCE(dato.Nit, empl.Nit),
					   @Email = COALESCE(dato.Email, empl.Email), @IdPlaza = COALESCE(dato.IdPlaza, empl.IdPlaza), @SalarioBase = dato.SalarioBase,
					   @TipoNomina = dato.TipoNomina, @FormaPago = dato.FormaPago, @GefId = dato.GefId, @TipoCuenta = dato.TipoCuenta,
					   @NumeroCuenta = dato.NumeroCuenta
				FROM @datos dato
				LEFT JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = dato.IdEmpleado
				WHERE dato.Fila = @fila;

				EXEC dbo.paRrhhEmpleadoGuardar @IdEmpleado = @id, @CodigoEmpleado = @Codigo, @CiaId = @CiaId,
					@PrimerNombre = @PrimerNombre, @SegundoNombre = @SegundoNombre, @PrimerApellido = @PrimerApellido,
					@SegundoApellido = @SegundoApellido, @ApellidoCasada = @ApellidoCasada, @Genero = @Genero,
					@FechaNacimiento = @FechaNacimiento, @FechaIngreso = @FechaIngreso, @Direccion = @Direccion,
					@IdTipoDocumentoIdentificacion = @IdTipoDocumento, @NumeroDocumento = @NumeroDocumento,
					@NumeroAfiliacionIGSS = @AfiliacionIGSS, @Nit = @Nit, @Email = @Email, @IdPlaza = @IdPlaza,
					@SalarioBase = @SalarioBase, @UsuId = @UsuId, @IdResultado = @resultado OUTPUT;
				EXEC dbo.paRrhhEmpleadoPagoGuardar @IdEmpleado = @resultado, @TipoNomina = @TipoNomina, @FormaPago = @FormaPago,
					@GefId = @GefId, @TipoCuenta = @TipoCuenta, @NumeroCuenta = @NumeroCuenta, @UsuId = @UsuId;
				SET @grabados += 1;
				FETCH NEXT FROM filas INTO @fila;
			END
			CLOSE filas; DEALLOCATE filas;
			COMMIT TRANSACTION;
		END TRY
		BEGIN CATCH
			IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
			SET @grabados = 0;
			INSERT INTO @mensajes VALUES (@fila, 'E', CONCAT(N'No se grabó ninguna fila: ', ERROR_MESSAGE()));
		END CATCH
	END

	SELECT Fila, Tipo, Mensaje FROM @mensajes ORDER BY Fila, Tipo DESC;

	SELECT (SELECT COUNT(*) FROM @datos) AS Filas,
		   (SELECT COUNT(*) FROM @datos WHERE IdEmpleado IS NULL) AS Nuevos,
		   (SELECT COUNT(*) FROM @datos WHERE IdEmpleado IS NOT NULL) AS Actualizados,
		   CAST(CASE WHEN @grabados > 0 THEN 1 ELSE 0 END AS BIT) AS Grabado;
END;
GO

PRINT '44_nit_certificadores_seguridad.sql aplicado.';
GO
