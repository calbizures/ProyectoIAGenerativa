/*
================================================================================
 86_saldos_iniciales_cxc_cxp.sql
 Facturas y compras pendientes al arrancar el sistema (saldos iniciales de
 Cuentas por cobrar y por pagar), desde Excel.

 La partida de apertura (script 38) lleva el saldo de clientes y proveedores
 a su cuenta contable, pero sin los documentos de cada uno no se puede cobrar
 ni pagar desde el sistema, ni ver la antigüedad. Esta carga crea, por cada
 factura o compra pendiente, un documento con sus cuotas:

   - Una fila del Excel por cuota pendiente: código, nombre y NIT del
     cliente o proveedor, sucursal (opcional), serie y número del documento,
     fecha, número de cuota (opcional), vencimiento y saldo pendiente.
     Facturas de venta: serie, número y UUID de SAT de la factura
     electrónica (opcionales), para poder emitir después una nota de crédito
     electrónica sobre ella.
   - El cliente o proveedor que no existe se crea con su nombre y NIT.
   - Tipos de documento internos SIFAC (saldo inicial de factura de cliente) y SICOM (de compra a
     proveedor): no entran a ventas, compras, tableros ni libros. Llevan una
     línea de servicio "Saldo inicial" en una bodega de la sucursal (la nota
     de crédito toma de ahí la sucursal).
   - No generan póliza: su valor ya está en la partida de apertura. La
     conciliación de CxC y CxP (script 85) compara su total con lo que la
     apertura llevó a la cuenta.
   - Se valida todo antes de grabar; con un error no se graba nada.
   - Una carga se puede anular mientras ninguno de sus documentos tenga
     cobros, pagos, notas o contraseñas de pago.

   cxs_carga, cxs_carga_documento, dbo.cxs_carga_type
   paCxSaldoInicialProcesar   validar (@SoloValidar = 1) o grabar
   paCxSaldoInicialConsultar  cargas de un módulo
   paCxSaldoInicialAnular
   Permisos CXC_SALDOS_INICIALES y CXP_SALDOS_INICIALES (Administrador,
   Contador y Contador general).

 @Modulo: 'CXC' (clientes) o 'CXP' (proveedores).
 Errores nuevos: 55990 a 55994.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Tipos de documento, permisos y tablas
------------------------------------------------------------
INSERT INTO dbo.inv_documento_tipo (tdo_codigo, tdo_descripcion, tdo_naturaleza, afecta_costo, tdo_estado, tdo_es_nota, tdo_fel_certifica, tdo_es_interno)
SELECT tipo.codigo, tipo.descripcion, tipo.naturaleza, 'N', 'A', 0, 0, 1
FROM (VALUES ('SIFAC', 'Saldo inicial de factura', '-'), ('SICOM', 'Saldo inicial de compra', '+')) tipo(codigo, descripcion, naturaleza)
WHERE NOT EXISTS (SELECT 1 FROM dbo.inv_documento_tipo WHERE tdo_codigo = tipo.codigo);
GO

INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT perm.modulo, perm.codigo, perm.descripcion
FROM (VALUES ('CXC', 'CXC_SALDOS_INICIALES', 'Cuentas por cobrar: cargar y anular las facturas pendientes al arrancar el sistema'),
			 ('CXP', 'CXP_SALDOS_INICIALES', 'Cuentas por pagar: cargar y anular las compras pendientes al arrancar el sistema')) perm(modulo, codigo, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_codigo = perm.codigo);
GO

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT rol.rol_id, perm.per_id
FROM dbo.sec_rol rol CROSS JOIN dbo.sec_permiso perm
WHERE rol.rol_codigo IN ('ADMIN', 'CONTADOR', 'CONTADOR_GENERAL') AND perm.per_codigo IN ('CXC_SALDOS_INICIALES', 'CXP_SALDOS_INICIALES')
  AND NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO

IF OBJECT_ID('dbo.cxs_carga', 'U') IS NULL
CREATE TABLE [dbo].[cxs_carga](
	[csc_id]				INT IDENTITY(1, 1)	NOT NULL CONSTRAINT [PK_cxs_carga] PRIMARY KEY,
	[csc_modulo]			CHAR(3)				NOT NULL CONSTRAINT [CK_cxs_carga_modulo] CHECK ([csc_modulo] IN ('CXC', 'CXP')),
	[csc_fecha]				DATE				NOT NULL,
	[csc_archivo]			NVARCHAR(200)		NULL,
	[csc_documentos]		INT					NOT NULL,
	[csc_cuotas]			INT					NOT NULL,
	[csc_terceros_nuevos]	INT					NOT NULL,
	[csc_total]				NUMERIC(14, 2)		NOT NULL,
	[csc_estado]			CHAR(1)				NOT NULL CONSTRAINT [DF_cxs_carga_estado] DEFAULT ('V')
											CONSTRAINT [CK_cxs_carga_estado] CHECK ([csc_estado] IN ('V', 'A')),	-- V vigente, A anulada
	[csc_motivo_anulacion]	VARCHAR(256)		NULL,
	[usu_id]				INT					NULL CONSTRAINT [FK_cxs_carga_usuario] REFERENCES dbo.gen_usuario (usu_id),
	[usu_id_anulacion]		INT					NULL CONSTRAINT [FK_cxs_carga_usuario_anulacion] REFERENCES dbo.gen_usuario (usu_id),
	[csc_fecha_anulacion]	DATETIME2(0)		NULL,
	[InsUsuario]			INT					NULL,
	[InsFechaHora]			DATETIME2(0)		NOT NULL CONSTRAINT [DF_cxs_carga_ins] DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT					NULL,
	[UpdFechaHora]			DATETIME2(0)		NULL
);
GO

IF OBJECT_ID('dbo.cxs_carga_documento', 'U') IS NULL
CREATE TABLE [dbo].[cxs_carga_documento](
	[csc_id]	INT	NOT NULL CONSTRAINT [FK_cxs_carga_documento_carga] REFERENCES dbo.cxs_carga (csc_id),
	[enc_id]	INT	NOT NULL CONSTRAINT [FK_cxs_carga_documento_documento] REFERENCES dbo.inv_documento_enc (enc_id),
	CONSTRAINT [PK_cxs_carga_documento] PRIMARY KEY ([csc_id], [enc_id]),
	CONSTRAINT [UQ_cxs_carga_documento_enc] UNIQUE ([enc_id])
);
GO

IF TYPE_ID('dbo.cxs_carga_type') IS NULL
	CREATE TYPE [dbo].[cxs_carga_type] AS TABLE (
		Fila			INT				NOT NULL PRIMARY KEY,
		Codigo			VARCHAR(40)		NULL,
		Nombre			VARCHAR(200)	NULL,
		Nit				VARCHAR(30)		NULL,
		Sucursal		VARCHAR(30)		NULL,
		Serie			VARCHAR(40)		NULL,
		Numero			VARCHAR(40)		NULL,
		FechaDocumento	DATE			NULL,
		Cuota			INT				NULL,
		Vencimiento		DATE			NULL,
		Saldo			NUMERIC(16, 4)	NULL,
		FelSerie		VARCHAR(40)		NULL,
		FelNumero		VARCHAR(40)		NULL,
		FelUuid			VARCHAR(64)		NULL
	);
GO

------------------------------------------------------------
-- 2. Validar y grabar
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCxSaldoInicialProcesar]
	@Modulo			CHAR(3),
	@Fecha			DATE,
	@Filas			dbo.cxs_carga_type READONLY,
	@Archivo		NVARCHAR(200) = NULL,
	@SoloValidar	BIT = 1,
	@UsuId			INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @Modulo NOT IN ('CXC', 'CXP')
		THROW 55990, 'El módulo debe ser CXC o CXP.', 1;
	DECLARE @es_cliente BIT = IIF(@Modulo = 'CXC', 1, 0);
	DECLARE @tercero NVARCHAR(20) = IIF(@es_cliente = 1, N'cliente', N'proveedor');
	DECLARE @largo_codigo INT = IIF(@es_cliente = 1, 32, 16), @largo_nombre INT = IIF(@es_cliente = 1, 64, 128);
	DECLARE @tdo_id INT = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo = IIF(@es_cliente = 1, 'SIFAC', 'SICOM'));
	DECLARE @mon_id INT = (SELECT TOP (1) mon_id FROM dbo.gen_moneda WHERE mon_es_local = 1 ORDER BY mon_id);
	DECLARE @suc_defecto INT = (SELECT TOP (1) suc_id FROM dbo.gen_sucursal WHERE suc_estado = 'A' ORDER BY suc_id);

	-- Filas limpias, con el cliente o proveedor y la sucursal resueltos.
	DECLARE @datos TABLE (
		Fila INT PRIMARY KEY, Codigo VARCHAR(40), Nombre VARCHAR(200), NitTexto VARCHAR(30), Nit VARCHAR(30), NitValido BIT,
		SucursalTexto VARCHAR(30), suc_id INT, bod_id INT, Serie VARCHAR(40), Numero VARCHAR(40), FechaDocumento DATE, Cuota INT,
		Vencimiento DATE, Saldo NUMERIC(16, 4), FelSerie VARCHAR(40), FelNumero VARCHAR(40), FelUuid VARCHAR(64),
		tercero_id INT, tercero_nit VARCHAR(16), Clave NVARCHAR(160));
	INSERT INTO @datos
	SELECT fila.Fila, NULLIF(LTRIM(RTRIM(fila.Codigo)), ''), NULLIF(LTRIM(RTRIM(fila.Nombre)), ''),
		   NULLIF(LTRIM(RTRIM(fila.Nit)), ''), nit.Normalizado, ISNULL(dbo.fnNitValido(fila.Nit), 0),
		   NULLIF(LTRIM(RTRIM(fila.Sucursal)), ''), NULL, NULL,
		   NULLIF(LTRIM(RTRIM(fila.Serie)), ''), NULLIF(LTRIM(RTRIM(fila.Numero)), ''), fila.FechaDocumento, fila.Cuota,
		   fila.Vencimiento, fila.Saldo, NULLIF(LTRIM(RTRIM(fila.FelSerie)), ''), NULLIF(LTRIM(RTRIM(fila.FelNumero)), ''),
		   NULLIF(LTRIM(RTRIM(fila.FelUuid)), ''), NULL, NULL, NULL
	FROM @Filas fila
	-- Como se guarda el NIT: "1234567-8", "CF" o el CUI de 13 dígitos.
	CROSS APPLY (SELECT dbo.fnNitNormalizar(fila.Nit) AS n) norm
	CROSS APPLY (SELECT CASE WHEN norm.n IS NULL OR norm.n = 'CF' OR (LEN(norm.n) = 13 AND norm.n NOT LIKE '%[^0-9]%') OR LEN(norm.n) < 2
							 THEN norm.n ELSE CONCAT(LEFT(norm.n, LEN(norm.n) - 1), '-', RIGHT(norm.n, 1)) END AS Normalizado) nit;

	UPDATE dato
	   SET suc_id = ISNULL(sucu.suc_id, IIF(dato.SucursalTexto IS NULL, @suc_defecto, NULL))
	FROM @datos dato
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_codigo = dato.SucursalTexto;
	UPDATE dato
	   SET bod_id = (SELECT TOP (1) bode.bod_id FROM dbo.inv_bodega bode WHERE bode.suc_id = dato.suc_id AND bode.bod_estado = 'A' ORDER BY bode.bod_id)
	FROM @datos dato WHERE dato.suc_id IS NOT NULL;

	IF @es_cliente = 1
		UPDATE dato SET tercero_id = clie.cli_id, tercero_nit = clie.cli_nit
		FROM @datos dato INNER JOIN dbo.pos_cliente clie ON clie.cli_codigo = dato.Codigo;
	ELSE
		UPDATE dato SET tercero_id = prov.prv_id, tercero_nit = prov.prv_nit
		FROM @datos dato INNER JOIN dbo.inv_proveedor prov ON prov.prv_codigo = dato.Codigo;

	-- Un documento = el mismo cliente o proveedor, serie y número.
	UPDATE @datos SET Clave = CONCAT(Codigo, NCHAR(31), ISNULL(Serie, ''), NCHAR(31), Numero) WHERE Codigo IS NOT NULL AND Numero IS NOT NULL;

	DECLARE @mensajes TABLE (Fila INT, Tipo CHAR(1), Mensaje NVARCHAR(500));

	IF @Fecha IS NULL
		INSERT INTO @mensajes VALUES (0, 'E', N'Indique la fecha de los saldos iniciales.');
	IF NOT EXISTS (SELECT 1 FROM @datos)
		INSERT INTO @mensajes VALUES (0, 'E', N'El archivo no tiene filas: llene una fila por cada cuota pendiente.');
	IF @tdo_id IS NULL OR @mon_id IS NULL
		INSERT INTO @mensajes VALUES (0, 'E', N'Falta configurar el tipo de documento o la moneda local.');

	-- Errores de cada fila (el primero que aplique).
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT Fila, 'E', Mensaje FROM (
		SELECT dato.Fila, CASE
			WHEN dato.Codigo IS NULL THEN CONCAT(N'Falta el código del ', @tercero, N'.')
			WHEN LEN(dato.Codigo) > @largo_codigo THEN CONCAT(N'El código del ', @tercero, N' admite ', @largo_codigo, N' caracteres.')
			WHEN dato.tercero_id IS NULL AND dato.Nombre IS NULL THEN CONCAT(N'El ', @tercero, N' "', dato.Codigo, N'" no existe: indique su nombre para crearlo.')
			WHEN dato.tercero_id IS NULL AND LEN(dato.Nombre) > @largo_nombre THEN CONCAT(N'El nombre del ', @tercero, N' admite ', @largo_nombre, N' caracteres.')
			WHEN dato.tercero_id IS NULL AND dato.NitTexto IS NULL THEN CONCAT(N'El ', @tercero, N' "', dato.Codigo, N'" no existe: indique su NIT para crearlo.')
			WHEN dato.NitTexto IS NOT NULL AND dato.NitValido = 0 THEN CONCAT(N'El NIT ', dato.NitTexto, N' no es válido: revise el dígito verificador (o use C/F o el CUI de 13 dígitos).')
			WHEN dato.SucursalTexto IS NOT NULL AND dato.suc_id IS NULL THEN CONCAT(N'La sucursal "', dato.SucursalTexto, N'" no existe.')
			WHEN dato.suc_id IS NULL THEN N'No hay ninguna sucursal activa.'
			WHEN dato.bod_id IS NULL THEN N'La sucursal no tiene ninguna bodega activa.'
			WHEN dato.Numero IS NULL THEN N'Falta el número del documento.'
			WHEN LEN(dato.Numero) > 32 OR LEN(ISNULL(dato.Serie, '')) > 32 THEN N'La serie y el número del documento admiten 32 caracteres cada uno.'
			WHEN dato.FechaDocumento IS NULL THEN N'Falta la fecha del documento.'
			WHEN @Fecha IS NOT NULL AND dato.FechaDocumento > @Fecha THEN N'La fecha del documento es posterior a la fecha de los saldos iniciales.'
			WHEN dato.Vencimiento IS NULL THEN N'Falta la fecha de vencimiento de la cuota.'
			WHEN dato.Vencimiento < dato.FechaDocumento THEN N'El vencimiento es anterior a la fecha del documento.'
			WHEN dato.Cuota IS NOT NULL AND dato.Cuota < 1 THEN N'El número de cuota debe ser 1 o mayor.'
			WHEN ISNULL(dato.Saldo, 0) <= 0 THEN N'El saldo pendiente debe ser mayor a cero.'
			WHEN dato.Saldo <> ROUND(dato.Saldo, 2) THEN N'El saldo admite solo dos decimales.'
			WHEN @es_cliente = 0 AND COALESCE(dato.FelSerie, dato.FelNumero, dato.FelUuid) IS NOT NULL THEN N'Los datos de factura electrónica solo aplican a facturas de clientes.'
			WHEN dato.FelUuid IS NOT NULL AND TRY_CONVERT(UNIQUEIDENTIFIER, dato.FelUuid) IS NULL THEN CONCAT(N'El UUID de SAT "', dato.FelUuid, N'" no es válido (36 caracteres, p. ej. 1A2B3C4D-1A2B-1A2B-1A2B-1A2B3C4D5E6F).')
			WHEN LEN(ISNULL(dato.FelSerie, '')) > 32 OR LEN(ISNULL(dato.FelNumero, '')) > 32 THEN N'La serie y el número de la factura electrónica admiten 32 caracteres cada uno.'
		END AS Mensaje
		FROM @datos dato
	) errores
	WHERE Mensaje IS NOT NULL;

	-- Un cliente o proveedor nuevo con datos distintos en dos filas, o con el NIT de otro.
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT dato.Fila, 'E', CONCAT(N'El ', @tercero, N' nuevo "', dato.Codigo, N'" viene con otro nombre o NIT en la fila ', otro.Fila, N'.')
	FROM @datos dato
	CROSS APPLY (SELECT TOP (1) x.Fila FROM @datos x WHERE x.Codigo = dato.Codigo AND x.Fila < dato.Fila
				 AND (ISNULL(x.Nombre, '') <> ISNULL(dato.Nombre, '') OR ISNULL(x.Nit, '') <> ISNULL(dato.Nit, '')) ORDER BY x.Fila) otro
	WHERE dato.tercero_id IS NULL AND NOT EXISTS (SELECT 1 FROM @mensajes m WHERE m.Fila = dato.Fila);

	IF @es_cliente = 1
		INSERT INTO @mensajes (Fila, Tipo, Mensaje)
		SELECT dato.Fila, 'E', CONCAT(N'El NIT ', dato.Nit, N' ya es del cliente ', clie.cli_codigo, N' (', clie.cli_nombres, N'): use ese código.')
		FROM @datos dato INNER JOIN dbo.pos_cliente clie ON clie.cli_nit = dato.Nit
		WHERE dato.tercero_id IS NULL AND dato.Nit <> 'CF' AND NOT EXISTS (SELECT 1 FROM @mensajes m WHERE m.Fila = dato.Fila);
	ELSE
		INSERT INTO @mensajes (Fila, Tipo, Mensaje)
		SELECT dato.Fila, 'E', CONCAT(N'El NIT ', dato.Nit, N' ya es del proveedor ', prov.prv_codigo, N' (', prov.prv_nombre_comercial, N'): use ese código.')
		FROM @datos dato INNER JOIN dbo.inv_proveedor prov ON prov.prv_nit = dato.Nit
		WHERE dato.tercero_id IS NULL AND dato.Nit <> 'CF' AND NOT EXISTS (SELECT 1 FROM @mensajes m WHERE m.Fila = dato.Fila);

	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT dato.Fila, 'E', CONCAT(N'El NIT ', dato.Nit, N' viene con otro código de ', @tercero, N' en la fila ', otro.Fila, N'.')
	FROM @datos dato
	CROSS APPLY (SELECT TOP (1) x.Fila FROM @datos x WHERE x.tercero_id IS NULL AND x.Nit = dato.Nit AND x.Codigo <> dato.Codigo AND x.Fila < dato.Fila ORDER BY x.Fila) otro
	WHERE dato.tercero_id IS NULL AND dato.Nit <> 'CF' AND NOT EXISTS (SELECT 1 FROM @mensajes m WHERE m.Fila = dato.Fila);

	-- Las filas de un mismo documento deben coincidir en fecha, sucursal y datos de FEL.
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT dato.Fila, 'E', CONCAT(N'El documento ', CONCAT(dato.Serie + '-', dato.Numero), N' viene con otra fecha, sucursal o datos de factura electrónica en la fila ', otro.Fila, N'.')
	FROM @datos dato
	CROSS APPLY (SELECT TOP (1) x.Fila FROM @datos x WHERE x.Clave = dato.Clave AND x.Fila < dato.Fila
				 AND (x.FechaDocumento <> dato.FechaDocumento OR ISNULL(x.suc_id, 0) <> ISNULL(dato.suc_id, 0)
					  OR ISNULL(x.FelSerie, '') <> ISNULL(dato.FelSerie, '') OR ISNULL(x.FelNumero, '') <> ISNULL(dato.FelNumero, '')
					  OR ISNULL(x.FelUuid, '') <> ISNULL(dato.FelUuid, '')) ORDER BY x.Fila) otro
	WHERE NOT EXISTS (SELECT 1 FROM @mensajes m WHERE m.Fila = dato.Fila);

	-- Cuotas: todas numeradas o ninguna, sin repetir.
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT dato.Fila, 'E', CONCAT(N'El documento ', CONCAT(dato.Serie + '-', dato.Numero), N' tiene filas con número de cuota y filas sin él: numérelas todas o deje la columna vacía.')
	FROM @datos dato
	WHERE EXISTS (SELECT 1 FROM @datos x WHERE x.Clave = dato.Clave AND x.Cuota IS NULL)
	  AND EXISTS (SELECT 1 FROM @datos x WHERE x.Clave = dato.Clave AND x.Cuota IS NOT NULL)
	  AND NOT EXISTS (SELECT 1 FROM @mensajes m WHERE m.Fila = dato.Fila);

	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT dato.Fila, 'E', CONCAT(N'La cuota ', dato.Cuota, N' del documento ', CONCAT(dato.Serie + '-', dato.Numero), N' se repite en la fila ', otro.Fila, N'.')
	FROM @datos dato
	CROSS APPLY (SELECT TOP (1) x.Fila FROM @datos x WHERE x.Clave = dato.Clave AND x.Cuota = dato.Cuota AND x.Fila < dato.Fila ORDER BY x.Fila) otro
	WHERE NOT EXISTS (SELECT 1 FROM @mensajes m WHERE m.Fila = dato.Fila);

	-- El documento ya está en el sistema (cargado antes o registrado en ventas o compras).
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT dato.Fila, 'E', CONCAT(N'El documento ', CONCAT(dato.Serie + '-', dato.Numero), N' del ', @tercero, N' ', dato.Codigo,
		N' ya existe en el sistema (', tipo.tdo_descripcion, N').')
	FROM @datos dato
	CROSS APPLY (SELECT TOP (1) docu.tdo_id FROM dbo.inv_documento_enc docu
				 WHERE docu.enc_estado = 'G' AND docu.enc_numero_docto = dato.Numero AND ISNULL(docu.enc_serie_docto, '') = ISNULL(dato.Serie, '')
				   AND ((@es_cliente = 1 AND docu.cli_id = dato.tercero_id) OR (@es_cliente = 0 AND docu.prv_id = dato.tercero_id))) exis
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = exis.tdo_id
	WHERE dato.tercero_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM @mensajes m WHERE m.Fila = dato.Fila);

	-- Documentos y cuotas que se grabarían.
	DECLARE @docs TABLE (Clave NVARCHAR(160) PRIMARY KEY, Codigo VARCHAR(40), Serie VARCHAR(40), Numero VARCHAR(40), FechaDocumento DATE,
						 suc_id INT, bod_id INT, FelSerie VARCHAR(40), FelNumero VARCHAR(40), FelUuid VARCHAR(64), Total NUMERIC(14, 2),
						 Cuotas INT, PrimerVencimiento DATE, enc_id INT);
	INSERT INTO @docs (Clave, Codigo, Serie, Numero, FechaDocumento, suc_id, bod_id, FelSerie, FelNumero, FelUuid, Total, Cuotas, PrimerVencimiento)
	SELECT Clave, MIN(Codigo), MIN(Serie), MIN(Numero), MIN(FechaDocumento), MIN(suc_id), MIN(bod_id), MIN(FelSerie), MIN(FelNumero), MIN(FelUuid),
		   SUM(Saldo), COUNT(*), MIN(Vencimiento)
	FROM @datos WHERE Clave IS NOT NULL GROUP BY Clave;

	DECLARE @nuevos INT = (SELECT COUNT(DISTINCT Codigo) FROM @datos WHERE tercero_id IS NULL AND Codigo IS NOT NULL);
	DECLARE @total NUMERIC(14, 2) = (SELECT ISNULL(SUM(Saldo), 0) FROM @datos);

	-- Contra la partida de apertura: lo que llevó a la cuenta y lo ya cargado.
	DECLARE @cta INT = (SELECT CtaId FROM dbo.fnAuditoriaSubmayorSaldos(@Modulo));
	DECLARE @apertura NUMERIC(14, 2) = (
		SELECT ISNULL(SUM(IIF(@es_cliente = 1, deta.asd_debe - deta.asd_haber, deta.asd_haber - deta.asd_debe)), 0)
		FROM dbo.cont_asiento_det deta
		INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id AND asie.asi_estado = 'A' AND asie.asi_origen = 'APERTURA'
		WHERE deta.cta_id = @cta);
	DECLARE @cargado NUMERIC(14, 2) = (
		SELECT ISNULL(SUM(docu.enc_monto_total), 0) FROM dbo.inv_documento_enc docu
		WHERE docu.tdo_id = @tdo_id AND docu.enc_estado = 'G');
	DECLARE @hay_apertura BIT = IIF(EXISTS (SELECT 1 FROM dbo.cont_asiento_enc WHERE asi_origen = 'APERTURA' AND asi_estado = 'A'), 1, 0);

	IF @hay_apertura = 0
		INSERT INTO @mensajes VALUES (0, 'A', N'Todavía no hay partida de apertura: cargue los saldos iniciales en Contabilidad para que la cuenta cuadre con estos documentos.');
	ELSE IF @apertura <> @cargado + @total
		INSERT INTO @mensajes VALUES (0, 'A', CONCAT(N'La partida de apertura lleva Q', FORMAT(@apertura, 'N2'), N' a la cuenta ',
			(SELECT cta_codigo FROM dbo.cont_cuenta_contable WHERE cta_id = @cta), N'; con esta carga los documentos pendientes suman Q',
			FORMAT(@cargado + @total, 'N2'), N' (diferencia Q', FORMAT(ABS(@apertura - @cargado - @total), 'N2'), N').',
			IIF(@cargado > 0, CONCAT(N' Ya había Q', FORMAT(@cargado, 'N2'), N' cargados.'), N'')));

	DECLARE @grabado BIT = 0, @csc_id INT;
	IF @SoloValidar = 0 AND NOT EXISTS (SELECT 1 FROM @mensajes WHERE Tipo = 'E')
	BEGIN
		BEGIN TRY
			BEGIN TRANSACTION;

			-- Clientes o proveedores nuevos.
			DECLARE @terceros TABLE (Codigo VARCHAR(40) PRIMARY KEY, Nombre VARCHAR(200), Nit VARCHAR(30));
			INSERT INTO @terceros SELECT Codigo, MIN(Nombre), MIN(Nit) FROM @datos WHERE tercero_id IS NULL GROUP BY Codigo;
			IF @es_cliente = 1
			BEGIN
				INSERT INTO dbo.pos_cliente (cli_codigo, cli_nombres, cli_nit, InsUsuario, InsFechaHora)
				SELECT Codigo, Nombre, Nit, @UsuId, SYSDATETIME() FROM @terceros;
				UPDATE dato SET tercero_id = clie.cli_id, tercero_nit = clie.cli_nit
				FROM @datos dato INNER JOIN dbo.pos_cliente clie ON clie.cli_codigo = dato.Codigo WHERE dato.tercero_id IS NULL;
			END
			ELSE
			BEGIN
				INSERT INTO dbo.inv_proveedor (prv_codigo, prv_nombre_comercial, prv_nit, InsUsuario, InsFechaHora)
				SELECT Codigo, Nombre, Nit, @UsuId, SYSDATETIME() FROM @terceros;
				UPDATE dato SET tercero_id = prov.prv_id, tercero_nit = prov.prv_nit
				FROM @datos dato INNER JOIN dbo.inv_proveedor prov ON prov.prv_codigo = dato.Codigo WHERE dato.tercero_id IS NULL;
			END

			INSERT INTO dbo.cxs_carga (csc_modulo, csc_fecha, csc_archivo, csc_documentos, csc_cuotas, csc_terceros_nuevos, csc_total, usu_id, InsUsuario)
			VALUES (@Modulo, @Fecha, @Archivo, (SELECT COUNT(*) FROM @docs), (SELECT COUNT(*) FROM @datos), @nuevos, @total, @UsuId, @UsuId);
			SET @csc_id = SCOPE_IDENTITY();

			-- Un documento por factura o compra, con la relación clave -> enc_id.
			DECLARE @motivo VARCHAR(256) = CONCAT('Saldo inicial al ', FORMAT(@Fecha, 'dd/MM/yyyy'), ' (carga #', @csc_id, ')');
			DECLARE @mapa TABLE (Clave NVARCHAR(160) PRIMARY KEY, enc_id INT);
			MERGE dbo.inv_documento_enc AS dest
			USING (SELECT docs.*, tdat.tercero_id, tdat.tercero_nit, tdat.Nombre
				   FROM @docs docs
				   CROSS APPLY (SELECT TOP (1) dato.tercero_id, dato.tercero_nit,
									   COALESCE(clie.cli_nombres + ISNULL(' ' + clie.cli_apellidos, ''), prov.prv_nombre_comercial) AS Nombre
								FROM @datos dato
								LEFT JOIN dbo.pos_cliente clie ON @es_cliente = 1 AND clie.cli_id = dato.tercero_id
								LEFT JOIN dbo.inv_proveedor prov ON @es_cliente = 0 AND prov.prv_id = dato.tercero_id
								WHERE dato.Clave = docs.Clave) tdat) AS orig
			ON 1 = 0
			WHEN NOT MATCHED THEN
				INSERT (enc_fecha_docto, enc_serie_docto, enc_numero_docto, cli_id, enc_nombres_cliente, cli_nit,
						prv_id, prv_enc_nombres_proveedor, prv_nit, tdo_id, enc_fecha_primer_pago, enc_numero_cuotas, enc_monto_total,
						mon_id, usu_id_creacion, enc_estado, enc_motivo, InsUsuario, InsFechaHora)
				VALUES (orig.FechaDocumento, orig.Serie, orig.Numero, IIF(@es_cliente = 1, orig.tercero_id, NULL), IIF(@es_cliente = 1, LEFT(orig.Nombre, 128), NULL),
						IIF(@es_cliente = 1, orig.tercero_nit, NULL), IIF(@es_cliente = 0, orig.tercero_id, NULL), IIF(@es_cliente = 0, LEFT(orig.Nombre, 128), NULL),
						IIF(@es_cliente = 0, orig.tercero_nit, NULL), @tdo_id, orig.PrimerVencimiento, orig.Cuotas, orig.Total,
						@mon_id, @UsuId, 'G', @motivo, @UsuId, SYSDATETIME())
			OUTPUT orig.Clave, inserted.enc_id INTO @mapa (Clave, enc_id);

			UPDATE docs SET enc_id = mapa.enc_id FROM @docs docs INNER JOIN @mapa mapa ON mapa.Clave = docs.Clave;

			-- Línea de servicio en la bodega de la sucursal (sin producto: no mueve inventario).
			INSERT INTO dbo.inv_documento_det (enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario,
											   det_valor_descuento, det_sub_total, bod_id, InsUsuario, InsFechaHora)
			SELECT enc_id, 1, 'S', 1, LEFT(@motivo, 256), Total, 0, Total, bod_id, @UsuId, SYSDATETIME() FROM @docs;

			-- Cuotas: las numeradas como vienen; sin número, por vencimiento.
			IF @es_cliente = 1
				INSERT INTO dbo.pos_cliente_plan_pagos (cpp_nro_cuota, cpp_valor_cuota, cpp_saldo_cuota, cpp_fecha_maxima_pago, enc_id, cli_id, cpp_estado, InsUsuario, InsFechaHora)
				SELECT ISNULL(dato.Cuota, ROW_NUMBER() OVER (PARTITION BY dato.Clave ORDER BY dato.Vencimiento, dato.Fila)),
					   dato.Saldo, dato.Saldo, dato.Vencimiento, docs.enc_id, dato.tercero_id, 'P', @UsuId, SYSDATETIME()
				FROM @datos dato INNER JOIN @docs docs ON docs.Clave = dato.Clave;
			ELSE
				INSERT INTO dbo.inv_proveedor_plan_pago (ppg_nro_pago, ppg_fecha_pago, ppg_valor_pago, enc_id, prv_id, ppg_estado, InsUsuario, InsFechaHora)
				SELECT ISNULL(dato.Cuota, ROW_NUMBER() OVER (PARTITION BY dato.Clave ORDER BY dato.Vencimiento, dato.Fila)),
					   dato.Vencimiento, dato.Saldo, docs.enc_id, dato.tercero_id, 'P', @UsuId, SYSDATETIME()
				FROM @datos dato INNER JOIN @docs docs ON docs.Clave = dato.Clave;

			-- Factura electrónica original: como certificada por un certificador externo,
			-- para que una nota de crédito electrónica la pueda referir.
			INSERT INTO dbo.fel_documento (enc_id, fdo_tipo_dte, fdo_estado, fdo_certificador, fdo_uuid, fdo_serie, fdo_numero,
										   fdo_fecha_certificacion, fdo_mensaje, fdo_intentos, InsUsuario, InsFechaHora)
			SELECT enc_id, 'FACT', 'C', 'EXTERNO', UPPER(FelUuid), FelSerie, FelNumero, CAST(FechaDocumento AS DATETIME2),
				   'Factura certificada antes de usar este sistema (saldo inicial).', 0, @UsuId, SYSDATETIME()
			FROM @docs WHERE @es_cliente = 1 AND COALESCE(FelUuid, FelSerie, FelNumero) IS NOT NULL;

			INSERT INTO dbo.cxs_carga_documento (csc_id, enc_id) SELECT @csc_id, enc_id FROM @docs;

			COMMIT TRANSACTION;
			SET @grabado = 1;
		END TRY
		BEGIN CATCH
			IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
			THROW;
		END CATCH
	END

	SELECT Fila, Tipo, Mensaje FROM @mensajes ORDER BY Fila, Tipo DESC, Mensaje;

	SELECT (SELECT COUNT(*) FROM @datos) AS Filas, (SELECT COUNT(*) FROM @docs) AS Documentos, @nuevos AS TercerosNuevos,
		   @total AS Total, @apertura AS Apertura, @cargado AS CargadoAntes, @apertura - @cargado - @total AS Diferencia,
		   @hay_apertura AS HayApertura, @grabado AS Grabado, @csc_id AS CscId;
END;
GO

------------------------------------------------------------
-- 3. Cargas grabadas y anulación
------------------------------------------------------------
-- Movimientos que impiden anular una carga: cobros o pagos vigentes, notas,
-- contraseñas de pago o cuotas con algo pagado.
CREATE OR ALTER FUNCTION [dbo].[fnCxSaldoInicialMovimientos] (@CscId INT)
RETURNS INT
AS
BEGIN
	RETURN (
		SELECT COUNT(*) FROM dbo.cxs_carga_documento cdoc
		WHERE cdoc.csc_id = @CscId
		  AND (EXISTS (SELECT 1 FROM dbo.inv_documento_enc nota WHERE nota.enc_id_referencia = cdoc.enc_id AND nota.enc_estado = 'G')
			OR EXISTS (SELECT 1 FROM dbo.pos_cliente_plan_pagos cuot
					   INNER JOIN dbo.pos_pago_det deta ON deta.cpp_id = cuot.cpp_id
					   INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
					   WHERE cuot.enc_id = cdoc.enc_id)
			OR EXISTS (SELECT 1 FROM dbo.inv_proveedor_plan_pago cuot
					   WHERE cuot.enc_id = cdoc.enc_id
						 AND (ISNULL(cuot.ppg_valor_real_pago, 0) > 0
						   OR EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_det deta
									  INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = deta.bce_id AND cheq.bce_estado_cheque <> 'A'
									  WHERE deta.ppg_id = cuot.ppg_id)
						   OR EXISTS (SELECT 1 FROM dbo.bco_lote_transferencia_cuota blcu
									  INNER JOIN dbo.bco_lote_transferencia_det line ON line.bld_id = blcu.bld_id
									  INNER JOIN dbo.bco_lote_transferencia lote ON lote.blt_id = line.blt_id AND lote.blt_estado = 'A'
									  WHERE blcu.ppg_id = cuot.ppg_id)
						   OR EXISTS (SELECT 1 FROM dbo.cxp_contrasena_det deta
									  INNER JOIN dbo.cxp_contrasena_enc cont ON cont.cpa_id = deta.cpa_id AND cont.cpa_estado = 'E'
									  WHERE deta.ppg_id = cuot.ppg_id))))
	);
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCxSaldoInicialConsultar]
	@Modulo	CHAR(3)
AS
BEGIN
	SET NOCOUNT ON;
	SELECT carg.csc_id AS CscId, carg.csc_fecha AS Fecha, carg.csc_archivo AS Archivo, carg.csc_documentos AS Documentos,
		   carg.csc_cuotas AS Cuotas, carg.csc_terceros_nuevos AS TercerosNuevos, carg.csc_total AS Total,
		   -- Lo que queda pendiente de esa carga hoy (cobrado o pagado desde entonces).
		   CAST(ISNULL(pend.Pendiente, 0) AS NUMERIC(14, 2)) AS Pendiente,
		   carg.csc_estado AS Estado, usua.usu_usuario AS Usuario, carg.InsFechaHora AS FechaGrabado,
		   carg.csc_motivo_anulacion AS MotivoAnulacion, anul.usu_usuario AS UsuarioAnulacion, carg.csc_fecha_anulacion AS FechaAnulacion,
		   CAST(IIF(carg.csc_estado = 'V' AND movi.Movimientos = 0, 1, 0) AS BIT) AS PuedeAnular
	FROM dbo.cxs_carga carg
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = carg.usu_id
	LEFT JOIN dbo.gen_usuario anul ON anul.usu_id = carg.usu_id_anulacion
	OUTER APPLY (SELECT CASE carg.csc_modulo
						WHEN 'CXC' THEN (SELECT SUM(cuot.cpp_saldo_cuota) FROM dbo.pos_cliente_plan_pagos cuot
										 INNER JOIN dbo.cxs_carga_documento cdoc ON cdoc.enc_id = cuot.enc_id AND cdoc.csc_id = carg.csc_id)
						ELSE (SELECT SUM(cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0)) FROM dbo.inv_proveedor_plan_pago cuot
							  INNER JOIN dbo.cxs_carga_documento cdoc ON cdoc.enc_id = cuot.enc_id AND cdoc.csc_id = carg.csc_id) END AS Pendiente) pend
	OUTER APPLY (SELECT dbo.fnCxSaldoInicialMovimientos(carg.csc_id) AS Movimientos) movi
	WHERE carg.csc_modulo = @Modulo
	ORDER BY carg.csc_id DESC;

	-- Documentos de cada carga (para ver el detalle).
	SELECT cdoc.csc_id AS CscId, docu.enc_id AS EncId, docu.enc_fecha_docto AS Fecha,
		   CONCAT(docu.enc_serie_docto + '-', docu.enc_numero_docto) AS Documento,
		   ISNULL(docu.cli_id, docu.prv_id) AS TerceroId,
		   COALESCE(clie.cli_codigo, prov.prv_codigo) AS TerceroCodigo,
		   COALESCE(LTRIM(RTRIM(CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos))), prov.prv_nombre_comercial) AS Tercero,
		   docu.enc_monto_total AS Total, docu.enc_numero_cuotas AS Cuotas, felo.fdo_uuid AS FelUuid
	FROM dbo.cxs_carga_documento cdoc
	INNER JOIN dbo.cxs_carga carg ON carg.csc_id = cdoc.csc_id AND carg.csc_modulo = @Modulo
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cdoc.enc_id
	LEFT JOIN dbo.pos_cliente clie ON clie.cli_id = docu.cli_id
	LEFT JOIN dbo.inv_proveedor prov ON prov.prv_id = docu.prv_id
	LEFT JOIN dbo.fel_documento felo ON felo.enc_id = docu.enc_id
	ORDER BY cdoc.csc_id DESC, Tercero, docu.enc_fecha_docto, docu.enc_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCxSaldoInicialAnular]
	@CscId	INT,
	@Motivo	VARCHAR(256),
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.cxs_carga WHERE csc_id = @CscId AND csc_estado = 'V')
		THROW 55991, 'La carga no existe o ya está anulada.', 1;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 55992, 'Indique el motivo de la anulación.', 1;
	IF dbo.fnCxSaldoInicialMovimientos(@CscId) > 0
		THROW 55993, 'La carga tiene documentos con cobros, pagos, notas o contraseñas de pago: anúlelos primero.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;
		UPDATE docu
		   SET enc_estado = 'A', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		FROM dbo.inv_documento_enc docu
		INNER JOIN dbo.cxs_carga_documento cdoc ON cdoc.enc_id = docu.enc_id AND cdoc.csc_id = @CscId;

		UPDATE felo
		   SET fdo_estado = 'A', fdo_motivo_anulacion = 'Carga de saldos iniciales anulada', fdo_fecha_anulacion = SYSDATETIME(),
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		FROM dbo.fel_documento felo
		INNER JOIN dbo.cxs_carga_documento cdoc ON cdoc.enc_id = felo.enc_id AND cdoc.csc_id = @CscId
		WHERE felo.fdo_certificador = 'EXTERNO';

		UPDATE dbo.cxs_carga
		   SET csc_estado = 'A', csc_motivo_anulacion = LTRIM(RTRIM(@Motivo)), usu_id_anulacion = @UsuId,
			   csc_fecha_anulacion = SYSDATETIME(), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE csc_id = @CscId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO
