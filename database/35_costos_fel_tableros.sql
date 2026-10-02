------------------------------------------------------------------------------
-- 35_costos_fel_tableros.sql
--
--   1. Costo unitario en cada línea:
--      * Venta: det_costo_unitario se toma del costo promedio del producto en
--        el momento de grabar (antes lo mandaba la pantalla y podía quedar
--        desactualizado). La partida usa ese costo.
--      * Compra: det_costo_unitario = (subtotal - descuento) / cantidad, sin
--        IVA, y el costo promedio ponderado del producto se recalcula con ese
--        neto (antes no restaba el descuento). Si la existencia queda en cero
--        el producto conserva su último costo promedio.
--      * Se completan las líneas ya grabadas que no tenían costo.
--   2. Factura electrónica (FEL) parametrizada:
--      * fel_configuracion (por compañía): certificador (SIMULADOR / INFILE),
--        ambiente, URLs, usuarios, correo de copia, espacio de nombres y
--        versión del DTE, datos por defecto del receptor. Las llaves (firma y
--        API) NO se guardan en la base: van en la configuración de la
--        aplicación (Fel:Credenciales:<NIT>).
--      * gen_compania: afiliación IVA, nombre del emisor y correo.
--      * gen_sucursal: código de establecimiento, nombre comercial, código
--        postal y municipio (departamento y país salen del catálogo).
--      * inv_documento_tipo: tipo de DTE (FACT, FCAM, NCRE, NDEB), tipo para
--        la venta de contado y si se certifica.
--      * inv_unidad_medida: código FEL (3 caracteres).
--      * pos_cliente: código postal y tipo de receptor (NIT, CUI, EXT).
--      * fel_frase: frases por compañía (tipo y escenario).
--      * fel_documento: estado FEL de cada documento, UUID, serie, número,
--        XML enviado y certificado; fel_bitacora: cada intento.
--      * paFelDocumentoDatosConsultar reúne lo que la aplicación necesita
--        para armar el XML (reemplaza a spr_sel_pos_factura_xml).
--   3. Consultas de los tableros de ventas, cartera y compras.
--   4. Permisos TABLERO_GERENCIAL y FEL_ADMIN.
--
-- Errores 53301-53320. Requiere 34. Se puede volver a correr.
------------------------------------------------------------------------------

USE [erp_db];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Costo unitario en ventas y compras
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_inventario_ajustar_existencia_documento]
	@enc_id		INT,
	@reversar	BIT = 0,	-- 1 = revertir el efecto (usado al anular un documento)
	@usu_id		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @naturaleza_signo INT, @reversar_signo INT = CASE WHEN @reversar = 1 THEN -1 ELSE 1 END;

	SELECT @naturaleza_signo = CASE WHEN tdo.tdo_naturaleza = '+' THEN 1 ELSE -1 END
	FROM dbo.inv_documento_enc enc
	INNER JOIN dbo.inv_documento_tipo tdo ON tdo.tdo_id = enc.tdo_id
	WHERE enc.enc_id = @enc_id;

	IF @naturaleza_signo IS NULL
		THROW 51201, 'El documento indicado no existe.', 1;

	-- Al grabar, cada línea con producto guarda su costo unitario: en un
	-- ingreso (compra) es lo pagado sin IVA y neto de descuento; en un egreso
	-- (venta) es el costo promedio del producto en este momento.
	IF @reversar = 0
		UPDATE deta
		   SET det_costo_unitario = CASE WHEN @naturaleza_signo = 1
										 THEN (deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) / NULLIF(deta.det_cantidad, 0)
										 ELSE prod.pro_costo_unitario END
		FROM dbo.inv_documento_det deta
		INNER JOIN dbo.inv_producto prod WITH (UPDLOCK) ON prod.pro_id = deta.pro_id
		WHERE deta.enc_id = @enc_id AND deta.det_cantidad > 0;

	DECLARE @movimientos TABLE (
		[pro_id]	INT				NOT NULL,
		[bod_id]	INT				NOT NULL,
		[cantidad]	NUMERIC(12, 4)	NOT NULL,
		[costo]		NUMERIC(14, 2)	NOT NULL,
		PRIMARY KEY ([pro_id], [bod_id])
	);

	INSERT INTO @movimientos ([pro_id], [bod_id], [cantidad], [costo])
	SELECT det.pro_id, det.bod_id,
		   SUM(det.det_cantidad) * @naturaleza_signo * @reversar_signo,
		   SUM(det.det_cantidad * COALESCE(det.det_costo_unitario, pro.pro_costo_unitario)) * @naturaleza_signo * @reversar_signo
	FROM dbo.inv_documento_det det
	INNER JOIN dbo.inv_producto pro ON pro.pro_id = det.pro_id
	WHERE det.enc_id = @enc_id
	  AND det.pro_id IS NOT NULL
	  AND pro.pro_maneja_existencia = 1
	GROUP BY det.pro_id, det.bod_id;

	MERGE dbo.inv_producto_existencia_bodega AS destino
	USING @movimientos AS origen
		ON destino.pro_id = origen.pro_id AND destino.bod_id = origen.bod_id
	WHEN MATCHED THEN
		UPDATE SET existencia = destino.existencia + origen.cantidad,
				   UpdUsuario = @usu_id,
				   UpdFechaHora = SYSDATETIME()
	WHEN NOT MATCHED THEN
		INSERT (bod_id, pro_id, existencia, InsUsuario, InsFechaHora)
		VALUES (origen.bod_id, origen.pro_id, origen.cantidad, @usu_id, SYSDATETIME());

	-- Costo promedio ponderado: (costo acumulado + costo del movimiento) /
	-- (cantidad acumulada + cantidad del movimiento). Sin existencia el
	-- producto conserva su último costo promedio.
	;WITH totales AS (
		SELECT pro_id, SUM(cantidad) AS cantidad, SUM(costo) AS costo
		FROM @movimientos
		GROUP BY pro_id
	)
	UPDATE p
	   SET p.pro_total_cantidad = p.pro_total_cantidad + t.cantidad,
		   p.pro_total_costo = CASE WHEN p.pro_total_cantidad + t.cantidad > 0 THEN p.pro_total_costo + t.costo ELSE 0 END,
		   p.pro_costo_unitario = CASE WHEN p.pro_total_cantidad + t.cantidad > 0
									   THEN (p.pro_total_costo + t.costo) / (p.pro_total_cantidad + t.cantidad)
									   ELSE p.pro_costo_unitario END,
		   p.UpdUsuario = @usu_id,
		   p.UpdFechaHora = SYSDATETIME()
	FROM dbo.inv_producto p
	INNER JOIN totales t ON t.pro_id = p.pro_id;
END;
GO

-- La partida de la venta usa el costo grabado en cada línea.
CREATE OR ALTER PROCEDURE [dbo].[sp_contabilidad_generar_asiento_documento]
	@enc_id	INT,
	@usu_id	INT = NULL,
	@asi_id	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @tdo_naturaleza CHAR(1), @afecta_costo CHAR(1), @fecha DATE, @monto_total NUMERIC(12, 2), @origen VARCHAR(20);

	SELECT @tdo_naturaleza = tdo.tdo_naturaleza, @afecta_costo = tdo.afecta_costo,
		   @fecha = enc.enc_fecha_docto, @monto_total = enc.enc_monto_total,
		   @origen = CASE WHEN tdo.tdo_naturaleza = '+' THEN 'COMPRA' ELSE 'VENTA' END
	FROM dbo.inv_documento_enc enc
	INNER JOIN dbo.inv_documento_tipo tdo ON tdo.tdo_id = enc.tdo_id
	WHERE enc.enc_id = @enc_id;

	IF @fecha IS NULL
		THROW 51303, 'El documento indicado no existe.', 1;

	DECLARE @cuentas TABLE (ccp_codigo VARCHAR(40) PRIMARY KEY, cta_id INT);
	INSERT INTO @cuentas SELECT ccp_codigo, cta_id FROM dbo.cont_cuenta_parametro
	WHERE ccp_codigo IN ('VENTA_CAJA','VENTA_CLIENTES','VENTA_INGRESO','VENTA_IVA_DEBITO','VENTA_COSTO','INVENTARIO',
						 'COMPRA_GASTO','COMPRA_IVA_CREDITO','COMPRA_PROVEEDORES');

	DECLARE @faltante VARCHAR(40) = (SELECT TOP 1 v.c FROM (VALUES ('VENTA_CAJA'),('VENTA_CLIENTES'),('VENTA_INGRESO'),('VENTA_IVA_DEBITO'),
		('VENTA_COSTO'),('INVENTARIO'),('COMPRA_GASTO'),('COMPRA_IVA_CREDITO'),('COMPRA_PROVEEDORES')) v(c)
		LEFT JOIN @cuentas cuen ON cuen.ccp_codigo = v.c WHERE cuen.cta_id IS NULL);
	IF @faltante IS NOT NULL
	BEGIN
		DECLARE @msg_faltante NVARCHAR(200) = CONCAT(N'El concepto contable ', @faltante, N' no tiene cuenta asignada; configúrelo en cont_cuenta_parametro.');
		THROW 51304, @msg_faltante, 1;
	END

	DECLARE @cta_caja INT, @cta_clientes INT, @cta_ingreso INT, @cta_iva_debito INT, @cta_costo INT, @cta_inventario INT,
			@cta_gasto INT, @cta_iva_credito INT, @cta_proveedores INT;
	SELECT @cta_caja = MAX(CASE ccp_codigo WHEN 'VENTA_CAJA' THEN cta_id END),
		   @cta_clientes = MAX(CASE ccp_codigo WHEN 'VENTA_CLIENTES' THEN cta_id END),
		   @cta_ingreso = MAX(CASE ccp_codigo WHEN 'VENTA_INGRESO' THEN cta_id END),
		   @cta_iva_debito = MAX(CASE ccp_codigo WHEN 'VENTA_IVA_DEBITO' THEN cta_id END),
		   @cta_costo = MAX(CASE ccp_codigo WHEN 'VENTA_COSTO' THEN cta_id END),
		   @cta_inventario = MAX(CASE ccp_codigo WHEN 'INVENTARIO' THEN cta_id END),
		   @cta_gasto = MAX(CASE ccp_codigo WHEN 'COMPRA_GASTO' THEN cta_id END),
		   @cta_iva_credito = MAX(CASE ccp_codigo WHEN 'COMPRA_IVA_CREDITO' THEN cta_id END),
		   @cta_proveedores = MAX(CASE ccp_codigo WHEN 'COMPRA_PROVEEDORES' THEN cta_id END)
	FROM @cuentas;

	DECLARE @iva NUMERIC(14, 2) =
		(SELECT ISNULL(SUM((det_sub_total - det_valor_descuento) * ISNULL(det_porc_iva, 0) / 100.0), 0) FROM dbo.inv_documento_det WHERE enc_id = @enc_id);

	DECLARE @costo_venta NUMERIC(14, 2);
	SELECT @costo_venta = ISNULL(SUM(det.det_cantidad * COALESCE(det.det_costo_unitario, pro.pro_costo_unitario)), 0)
	FROM dbo.inv_documento_det det
	INNER JOIN dbo.inv_producto pro ON pro.pro_id = det.pro_id
	WHERE det.enc_id = @enc_id AND pro.pro_maneja_existencia = 1;

	DECLARE @pdo_id INT;
	EXEC dbo.sp_contabilidad_obtener_o_crear_periodo @fecha = @fecha, @usu_id = @usu_id, @pdo_id = @pdo_id OUTPUT;

	DECLARE @detalle dbo.cont_asiento_det_type;
	DECLARE @ref VARCHAR(10) = CAST(@enc_id AS VARCHAR(10));

	IF @tdo_naturaleza = '-' -- venta
	BEGIN
		DECLARE @cobrado NUMERIC(12, 2) = (SELECT ISNULL(SUM(ppd_valor_aplicado), 0) FROM dbo.pos_pago_det WHERE enc_id = @enc_id);
		IF @cobrado > @monto_total SET @cobrado = @monto_total;

		IF @cobrado > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_caja, @cobrado, 0, 'Cobro al facturar - documento ' + @ref);
		IF @monto_total - @cobrado > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_clientes, @monto_total - @cobrado, 0, 'Cuentas por cobrar - documento ' + @ref);

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_ingreso, 0, @monto_total - @iva, 'Venta - documento ' + @ref);

		IF @iva > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_iva_debito, 0, @iva, 'IVA débito fiscal - documento ' + @ref);

		IF @costo_venta > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			VALUES (@cta_costo, @costo_venta, 0, 'Costo de venta - documento ' + @ref),
				   (@cta_inventario, 0, @costo_venta, 'Salida de inventario - documento ' + @ref);
	END
	ELSE -- compra
	BEGIN
		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (CASE WHEN @afecta_costo = 'S' THEN @cta_inventario ELSE @cta_gasto END, @monto_total - @iva, 0, 'Compra - documento ' + @ref);

		IF @iva > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_iva_credito, @iva, 0, 'IVA crédito fiscal - documento ' + @ref);

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_proveedores, 0, @monto_total, 'Cuentas por pagar - documento ' + @ref);
	END

	DECLARE @asi_descripcion VARCHAR(256) = 'Generado automáticamente desde documento ' + @ref;

	EXEC dbo.sp_contabilidad_insertar_asiento
		@asi_fecha = @fecha, @asi_descripcion = @asi_descripcion, @asi_origen = @origen,
		@enc_id = @enc_id, @pdo_id = @pdo_id, @usu_id = @usu_id, @detalle = @detalle, @asi_id = @asi_id OUTPUT;
END;
GO

-- Líneas ya grabadas sin costo: compras con su costo neto; ventas con el
-- costo promedio actual del producto (aproximación: no hay historial).
UPDATE deta
   SET det_costo_unitario = CASE WHEN tipo.tdo_naturaleza = '+' AND tipo.tdo_es_nota = 0
								 THEN (deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) / deta.det_cantidad
								 ELSE prod.pro_costo_unitario END
FROM dbo.inv_documento_det deta
INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = deta.enc_id
INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
WHERE deta.det_costo_unitario IS NULL AND deta.det_cantidad > 0;
GO

------------------------------------------------------------
-- 2. FEL: estructura y parámetros
------------------------------------------------------------
IF COL_LENGTH('dbo.gen_compania', 'cia_fel_afiliacion_iva') IS NULL
	ALTER TABLE dbo.gen_compania ADD [cia_fel_afiliacion_iva] VARCHAR(3) NOT NULL CONSTRAINT [DF_gen_compania_fel_afiliacion] DEFAULT ('GEN');
IF COL_LENGTH('dbo.gen_compania', 'cia_fel_nombre_emisor') IS NULL
	ALTER TABLE dbo.gen_compania ADD [cia_fel_nombre_emisor] VARCHAR(256) NULL;		-- razón social ante SAT
IF COL_LENGTH('dbo.gen_compania', 'cia_fel_correo_emisor') IS NULL
	ALTER TABLE dbo.gen_compania ADD [cia_fel_correo_emisor] VARCHAR(128) NULL;

IF COL_LENGTH('dbo.gen_sucursal', 'suc_fel_codigo_establecimiento') IS NULL
	ALTER TABLE dbo.gen_sucursal ADD [suc_fel_codigo_establecimiento] INT NULL;
IF COL_LENGTH('dbo.gen_sucursal', 'suc_fel_nombre_comercial') IS NULL
	ALTER TABLE dbo.gen_sucursal ADD [suc_fel_nombre_comercial] VARCHAR(256) NULL;
IF COL_LENGTH('dbo.gen_sucursal', 'suc_codigo_postal') IS NULL
	ALTER TABLE dbo.gen_sucursal ADD [suc_codigo_postal] VARCHAR(10) NULL;
IF COL_LENGTH('dbo.gen_sucursal', 'prov_id') IS NULL
	ALTER TABLE dbo.gen_sucursal ADD [prov_id] INT NULL;							-- municipio

IF COL_LENGTH('dbo.inv_documento_tipo', 'tdo_fel_tipo_dte') IS NULL
	ALTER TABLE dbo.inv_documento_tipo ADD [tdo_fel_tipo_dte] VARCHAR(4) NULL;
IF COL_LENGTH('dbo.inv_documento_tipo', 'tdo_fel_tipo_dte_contado') IS NULL
	ALTER TABLE dbo.inv_documento_tipo ADD [tdo_fel_tipo_dte_contado] VARCHAR(4) NULL;	-- p. ej. FCAM a crédito, FACT de contado
IF COL_LENGTH('dbo.inv_documento_tipo', 'tdo_fel_certifica') IS NULL
	ALTER TABLE dbo.inv_documento_tipo ADD [tdo_fel_certifica] BIT NOT NULL CONSTRAINT [DF_inv_documento_tipo_fel_certifica] DEFAULT (0);

IF COL_LENGTH('dbo.inv_unidad_medida', 'ume_fel_codigo') IS NULL
	ALTER TABLE dbo.inv_unidad_medida ADD [ume_fel_codigo] VARCHAR(3) NULL;

IF COL_LENGTH('dbo.pos_cliente', 'cli_codigo_postal') IS NULL
	ALTER TABLE dbo.pos_cliente ADD [cli_codigo_postal] VARCHAR(10) NULL;
IF COL_LENGTH('dbo.pos_cliente', 'cli_fel_tipo_receptor') IS NULL
	ALTER TABLE dbo.pos_cliente ADD [cli_fel_tipo_receptor] VARCHAR(3) NULL;		-- NULL = NIT; CUI o EXT
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_gen_compania_fel_afiliacion')
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [CK_gen_compania_fel_afiliacion] CHECK ([cia_fel_afiliacion_iva] IN ('GEN', 'PEQ', 'EXE', 'AGR', 'AGE', 'ECE'));
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_inv_documento_tipo_fel_dte')
	ALTER TABLE dbo.inv_documento_tipo ADD CONSTRAINT [CK_inv_documento_tipo_fel_dte]
		CHECK ([tdo_fel_tipo_dte] IS NULL OR [tdo_fel_tipo_dte] IN ('FACT', 'FCAM', 'FPEQ', 'FCAP', 'FESP', 'NABN', 'RDON', 'RECI', 'NDEB', 'NCRE'));
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_pos_cliente_fel_tipo_receptor')
	ALTER TABLE dbo.pos_cliente ADD CONSTRAINT [CK_pos_cliente_fel_tipo_receptor] CHECK ([cli_fel_tipo_receptor] IS NULL OR [cli_fel_tipo_receptor] IN ('CUI', 'EXT'));
IF OBJECT_ID('dbo.FK_gen_sucursal_municipio', 'F') IS NULL
	ALTER TABLE dbo.gen_sucursal ADD CONSTRAINT [FK_gen_sucursal_municipio] FOREIGN KEY ([prov_id]) REFERENCES dbo.gen_provincia ([prov_id]);
GO

IF OBJECT_ID('dbo.fel_configuracion', 'U') IS NULL
CREATE TABLE [dbo].[fel_configuracion](
	[cia_id]						INT				NOT NULL,
	[fco_certificador]				VARCHAR(20)		NOT NULL CONSTRAINT [DF_fel_configuracion_certificador] DEFAULT ('SIMULADOR'),
	[fco_activo]					BIT				NOT NULL CONSTRAINT [DF_fel_configuracion_activo] DEFAULT (1),
	[fco_ambiente]					VARCHAR(10)		NOT NULL CONSTRAINT [DF_fel_configuracion_ambiente] DEFAULT ('PRUEBAS'),
	[fco_url_certificacion]			VARCHAR(256)	NULL,
	[fco_url_anulacion]				VARCHAR(256)	NULL,
	[fco_usuario_firma]				VARCHAR(64)		NULL,
	[fco_usuario_api]				VARCHAR(64)		NULL,
	[fco_correo_copia]				VARCHAR(128)	NULL,
	[fco_timeout_segundos]			INT				NOT NULL CONSTRAINT [DF_fel_configuracion_timeout] DEFAULT (30),
	[fco_xmlns_dte]					VARCHAR(128)	NOT NULL CONSTRAINT [DF_fel_configuracion_xmlns] DEFAULT ('http://www.sat.gob.gt/dte/fel/0.2.0'),
	[fco_version_dte]				VARCHAR(10)		NOT NULL CONSTRAINT [DF_fel_configuracion_version] DEFAULT ('0.1'),
	[fco_receptor_direccion]		VARCHAR(128)	NOT NULL CONSTRAINT [DF_fel_configuracion_rec_dir] DEFAULT ('Ciudad'),
	[fco_receptor_codigo_postal]	VARCHAR(10)		NOT NULL CONSTRAINT [DF_fel_configuracion_rec_cp] DEFAULT ('01001'),
	[fco_receptor_municipio]		VARCHAR(64)		NOT NULL CONSTRAINT [DF_fel_configuracion_rec_mun] DEFAULT ('Guatemala'),
	[fco_receptor_departamento]		VARCHAR(64)		NOT NULL CONSTRAINT [DF_fel_configuracion_rec_dep] DEFAULT ('Guatemala'),
	[fco_receptor_pais]				CHAR(2)			NOT NULL CONSTRAINT [DF_fel_configuracion_rec_pais] DEFAULT ('GT'),
	[InsUsuario]					INT				NULL,
	[InsFechaHora]					DATETIME2(0)	NOT NULL CONSTRAINT [DF_fel_configuracion_ins] DEFAULT (SYSDATETIME()),
	[UpdUsuario]					INT				NULL,
	[UpdFechaHora]					DATETIME2(0)	NULL,
	CONSTRAINT [PK_fel_configuracion] PRIMARY KEY ([cia_id]),
	CONSTRAINT [FK_fel_configuracion_compania] FOREIGN KEY ([cia_id]) REFERENCES dbo.gen_compania ([cia_id]),
	CONSTRAINT [CK_fel_configuracion_certificador] CHECK ([fco_certificador] IN ('SIMULADOR', 'INFILE')),
	CONSTRAINT [CK_fel_configuracion_ambiente] CHECK ([fco_ambiente] IN ('PRUEBAS', 'PRODUCCION')),
	CONSTRAINT [CK_fel_configuracion_timeout] CHECK ([fco_timeout_segundos] BETWEEN 5 AND 300)
);

IF OBJECT_ID('dbo.fel_frase', 'U') IS NULL
CREATE TABLE [dbo].[fel_frase](
	[ffr_id]				INT IDENTITY(1,1)	NOT NULL,
	[cia_id]				INT					NOT NULL,
	[ffr_tipo_frase]		SMALLINT			NOT NULL,
	[ffr_codigo_escenario]	SMALLINT			NOT NULL,
	[ffr_descripcion]		VARCHAR(256)		NULL,
	[ffr_aplica_notas]		BIT					NOT NULL CONSTRAINT [DF_fel_frase_notas] DEFAULT (0),
	[ffr_estado]			CHAR(1)				NOT NULL CONSTRAINT [DF_fel_frase_estado] DEFAULT ('A'),
	[InsUsuario]			INT					NULL,
	[InsFechaHora]			DATETIME2(0)		NOT NULL CONSTRAINT [DF_fel_frase_ins] DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT					NULL,
	[UpdFechaHora]			DATETIME2(0)		NULL,
	CONSTRAINT [PK_fel_frase] PRIMARY KEY ([ffr_id]),
	CONSTRAINT [FK_fel_frase_compania] FOREIGN KEY ([cia_id]) REFERENCES dbo.gen_compania ([cia_id]),
	CONSTRAINT [UQ_fel_frase] UNIQUE ([cia_id], [ffr_tipo_frase], [ffr_codigo_escenario]),
	CONSTRAINT [CK_fel_frase_estado] CHECK ([ffr_estado] IN ('A', 'I'))
);

-- Estado FEL de cada documento: P pendiente de certificar (falla de
-- comunicación), R rechazado por el certificador, C certificado, A anulado
-- ante SAT, X anulación pendiente. Sin fila = no enviado.
IF OBJECT_ID('dbo.fel_documento', 'U') IS NULL
CREATE TABLE [dbo].[fel_documento](
	[enc_id]					INT				NOT NULL,
	[fdo_tipo_dte]				VARCHAR(4)		NOT NULL,
	[fdo_estado]				CHAR(1)			NOT NULL,
	[fdo_certificador]			VARCHAR(20)		NOT NULL,
	[fdo_uuid]					VARCHAR(64)		NULL,
	[fdo_serie]					VARCHAR(32)		NULL,
	[fdo_numero]				VARCHAR(32)		NULL,
	[fdo_fecha_certificacion]	DATETIME2(0)	NULL,
	[fdo_xml_enviado]			NVARCHAR(MAX)	NULL,
	[fdo_xml_certificado]		NVARCHAR(MAX)	NULL,
	[fdo_mensaje]				NVARCHAR(2000)	NULL,
	[fdo_intentos]				INT				NOT NULL CONSTRAINT [DF_fel_documento_intentos] DEFAULT (0),
	[fdo_fecha_ultimo_intento]	DATETIME2(0)	NULL,
	[fdo_motivo_anulacion]		VARCHAR(256)	NULL,
	[fdo_fecha_anulacion]		DATETIME2(0)	NULL,
	[fdo_xml_anulacion]			NVARCHAR(MAX)	NULL,
	[InsUsuario]				INT				NULL,
	[InsFechaHora]				DATETIME2(0)	NOT NULL CONSTRAINT [DF_fel_documento_ins] DEFAULT (SYSDATETIME()),
	[UpdUsuario]				INT				NULL,
	[UpdFechaHora]				DATETIME2(0)	NULL,
	CONSTRAINT [PK_fel_documento] PRIMARY KEY ([enc_id]),
	CONSTRAINT [FK_fel_documento_documento] FOREIGN KEY ([enc_id]) REFERENCES dbo.inv_documento_enc ([enc_id]),
	CONSTRAINT [CK_fel_documento_estado] CHECK ([fdo_estado] IN ('P', 'R', 'C', 'A', 'X'))
);

IF OBJECT_ID('dbo.fel_bitacora', 'U') IS NULL
CREATE TABLE [dbo].[fel_bitacora](
	[fbi_id]		INT IDENTITY(1,1)	NOT NULL,
	[enc_id]		INT					NOT NULL,
	[fbi_fecha]		DATETIME2(0)		NOT NULL CONSTRAINT [DF_fel_bitacora_fecha] DEFAULT (SYSDATETIME()),
	[fbi_operacion]	VARCHAR(12)			NOT NULL,
	[fbi_exito]		BIT					NOT NULL,
	[fbi_mensaje]	NVARCHAR(2000)		NULL,
	[fbi_respuesta]	NVARCHAR(MAX)		NULL,
	[usu_id]		INT					NULL,
	CONSTRAINT [PK_fel_bitacora] PRIMARY KEY ([fbi_id]),
	CONSTRAINT [FK_fel_bitacora_documento] FOREIGN KEY ([enc_id]) REFERENCES dbo.inv_documento_enc ([enc_id]),
	CONSTRAINT [CK_fel_bitacora_operacion] CHECK ([fbi_operacion] IN ('CERTIFICAR', 'ANULAR'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fel_bitacora_enc_id' AND object_id = OBJECT_ID('dbo.fel_bitacora'))
	CREATE INDEX [IX_fel_bitacora_enc_id] ON dbo.fel_bitacora ([enc_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fel_documento_estado' AND object_id = OBJECT_ID('dbo.fel_documento'))
	CREATE INDEX [IX_fel_documento_estado] ON dbo.fel_documento ([fdo_estado]);
GO

-- Valores iniciales (solo donde no hay nada configurado).
-- Con el catálogo de certificadores del 44 (FK), al volver a correr después
-- del 12 (que vacía las tablas) el catálogo está vacío: se deja la fila mínima
-- del simulador y el 44 la completa.
IF OBJECT_ID('dbo.fel_certificador', 'U') IS NOT NULL
	EXEC (N'INSERT INTO dbo.fel_certificador (fce_codigo, fce_nombre)
			SELECT ''SIMULADOR'', ''SIMULADOR'' WHERE NOT EXISTS (SELECT 1 FROM dbo.fel_certificador WHERE fce_codigo = ''SIMULADOR'');');

INSERT INTO dbo.fel_configuracion (cia_id, fco_certificador, fco_activo, fco_ambiente, fco_url_certificacion, fco_url_anulacion)
SELECT comp.cia_id, 'SIMULADOR', 1, 'PRUEBAS',
	   'https://certificador.feel.com.gt/fel/procesounificado/transaccion/v2/xml',
	   'https://certificador.feel.com.gt/fel/procesounificado/transaccion/v2/xml'
FROM dbo.gen_compania comp
WHERE NOT EXISTS (SELECT 1 FROM dbo.fel_configuracion conf WHERE conf.cia_id = comp.cia_id);

UPDATE dbo.gen_compania
   SET cia_fel_nombre_emisor = ISNULL(cia_fel_nombre_emisor, cia_nombre_comercial),
	   cia_fel_correo_emisor = ISNULL(cia_fel_correo_emisor, cia_email)
WHERE cia_fel_nombre_emisor IS NULL OR cia_fel_correo_emisor IS NULL;

-- Frase 1 escenario 1: sujeto a pagos trimestrales ISR (la más común).
INSERT INTO dbo.fel_frase (cia_id, ffr_tipo_frase, ffr_codigo_escenario, ffr_descripcion)
SELECT comp.cia_id, 1, 1, 'Sujeto a pagos trimestrales ISR'
FROM dbo.gen_compania comp
WHERE NOT EXISTS (SELECT 1 FROM dbo.fel_frase frase WHERE frase.cia_id = comp.cia_id);

-- Establecimientos: número correlativo por compañía y municipio de la capital.
;WITH numeradas AS (
	SELECT suc_id, ROW_NUMBER() OVER (PARTITION BY cia_id ORDER BY suc_id) AS numero FROM dbo.gen_sucursal
)
UPDATE sucu
   SET suc_fel_codigo_establecimiento = ISNULL(sucu.suc_fel_codigo_establecimiento, nume.numero),
	   suc_fel_nombre_comercial = ISNULL(sucu.suc_fel_nombre_comercial, sucu.suc_descripcion),
	   suc_codigo_postal = ISNULL(sucu.suc_codigo_postal, '01010'),
	   prov_id = ISNULL(sucu.prov_id, (SELECT TOP 1 prov_id FROM dbo.gen_provincia ORDER BY CASE WHEN prov_nombre LIKE '%Guatemala%' THEN 0 ELSE 1 END, prov_id))
FROM dbo.gen_sucursal sucu
INNER JOIN numeradas nume ON nume.suc_id = sucu.suc_id
WHERE sucu.suc_fel_codigo_establecimiento IS NULL OR sucu.prov_id IS NULL;

UPDATE dbo.inv_documento_tipo
   SET tdo_fel_tipo_dte = CASE tdo_codigo WHEN 'FCAM' THEN 'FCAM' WHEN 'NCC' THEN 'NCRE' WHEN 'NDC' THEN 'NDEB' END,
	   tdo_fel_tipo_dte_contado = CASE tdo_codigo WHEN 'FCAM' THEN 'FACT' END,
	   tdo_fel_certifica = 1
WHERE tdo_codigo IN ('FCAM', 'NCC', 'NDC') AND tdo_fel_tipo_dte IS NULL;

UPDATE dbo.inv_unidad_medida SET ume_fel_codigo = LEFT(ume_codigo, 3) WHERE ume_fel_codigo IS NULL;
GO

------------------------------------------------------------
-- 3. FEL: mantenimiento de parámetros
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paFelConfiguracionConsultar]
	@CiaId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT comp.cia_id AS CiaId, comp.cia_nombre_comercial AS Compania, comp.cia_nit AS Nit,
		   comp.cia_fel_afiliacion_iva AS AfiliacionIva, comp.cia_fel_nombre_emisor AS NombreEmisor, comp.cia_fel_correo_emisor AS CorreoEmisor,
		   conf.fco_certificador AS Certificador, conf.fco_activo AS Activo, conf.fco_ambiente AS Ambiente,
		   conf.fco_url_certificacion AS UrlCertificacion, conf.fco_url_anulacion AS UrlAnulacion,
		   conf.fco_usuario_firma AS UsuarioFirma, conf.fco_usuario_api AS UsuarioApi, conf.fco_correo_copia AS CorreoCopia,
		   conf.fco_timeout_segundos AS TimeoutSegundos, conf.fco_xmlns_dte AS XmlnsDte, conf.fco_version_dte AS VersionDte,
		   conf.fco_receptor_direccion AS ReceptorDireccion, conf.fco_receptor_codigo_postal AS ReceptorCodigoPostal,
		   conf.fco_receptor_municipio AS ReceptorMunicipio, conf.fco_receptor_departamento AS ReceptorDepartamento,
		   conf.fco_receptor_pais AS ReceptorPais
	FROM dbo.gen_compania comp
	LEFT JOIN dbo.fel_configuracion conf ON conf.cia_id = comp.cia_id
	WHERE comp.cia_id = @CiaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelConfiguracionGuardar]
	@CiaId					INT,
	@AfiliacionIva			VARCHAR(3),
	@NombreEmisor			VARCHAR(256),
	@CorreoEmisor			VARCHAR(128) = NULL,
	@Certificador			VARCHAR(20),
	@Activo					BIT,
	@Ambiente				VARCHAR(10),
	@UrlCertificacion		VARCHAR(256) = NULL,
	@UrlAnulacion			VARCHAR(256) = NULL,
	@UsuarioFirma			VARCHAR(64) = NULL,
	@UsuarioApi				VARCHAR(64) = NULL,
	@CorreoCopia			VARCHAR(128) = NULL,
	@TimeoutSegundos		INT = 30,
	@XmlnsDte				VARCHAR(128),
	@VersionDte				VARCHAR(10),
	@ReceptorDireccion		VARCHAR(128),
	@ReceptorCodigoPostal	VARCHAR(10),
	@ReceptorMunicipio		VARCHAR(64),
	@ReceptorDepartamento	VARCHAR(64),
	@ReceptorPais			CHAR(2),
	@UsuId					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_id = @CiaId)
		THROW 53301, 'La compañía indicada no existe.', 1;
	IF LTRIM(RTRIM(ISNULL(@NombreEmisor, ''))) = ''
		THROW 53302, 'Indique el nombre del emisor (razón social registrada en SAT).', 1;
	IF @Certificador = 'INFILE' AND @Activo = 1
	   AND (ISNULL(@UrlCertificacion, '') = '' OR ISNULL(@UsuarioFirma, '') = '' OR ISNULL(@UsuarioApi, '') = '')
		THROW 53303, 'Para certificar con INFILE indique la URL de certificación, el usuario de firma y el usuario de la API.', 1;

	BEGIN TRANSACTION;

	UPDATE dbo.gen_compania
	   SET cia_fel_afiliacion_iva = @AfiliacionIva, cia_fel_nombre_emisor = LTRIM(RTRIM(@NombreEmisor)),
		   cia_fel_correo_emisor = NULLIF(LTRIM(RTRIM(@CorreoEmisor)), ''),
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cia_id = @CiaId;

	MERGE dbo.fel_configuracion AS dest
	USING (SELECT @CiaId AS cia_id) AS orig ON dest.cia_id = orig.cia_id
	WHEN MATCHED THEN UPDATE SET
		fco_certificador = @Certificador, fco_activo = @Activo, fco_ambiente = @Ambiente,
		fco_url_certificacion = NULLIF(@UrlCertificacion, ''), fco_url_anulacion = NULLIF(@UrlAnulacion, ''),
		fco_usuario_firma = NULLIF(@UsuarioFirma, ''), fco_usuario_api = NULLIF(@UsuarioApi, ''), fco_correo_copia = NULLIF(@CorreoCopia, ''),
		fco_timeout_segundos = @TimeoutSegundos, fco_xmlns_dte = @XmlnsDte, fco_version_dte = @VersionDte,
		fco_receptor_direccion = @ReceptorDireccion, fco_receptor_codigo_postal = @ReceptorCodigoPostal,
		fco_receptor_municipio = @ReceptorMunicipio, fco_receptor_departamento = @ReceptorDepartamento, fco_receptor_pais = @ReceptorPais,
		UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	WHEN NOT MATCHED THEN INSERT
		(cia_id, fco_certificador, fco_activo, fco_ambiente, fco_url_certificacion, fco_url_anulacion, fco_usuario_firma, fco_usuario_api,
		 fco_correo_copia, fco_timeout_segundos, fco_xmlns_dte, fco_version_dte, fco_receptor_direccion, fco_receptor_codigo_postal,
		 fco_receptor_municipio, fco_receptor_departamento, fco_receptor_pais, InsUsuario)
	VALUES
		(@CiaId, @Certificador, @Activo, @Ambiente, NULLIF(@UrlCertificacion, ''), NULLIF(@UrlAnulacion, ''), NULLIF(@UsuarioFirma, ''),
		 NULLIF(@UsuarioApi, ''), NULLIF(@CorreoCopia, ''), @TimeoutSegundos, @XmlnsDte, @VersionDte, @ReceptorDireccion,
		 @ReceptorCodigoPostal, @ReceptorMunicipio, @ReceptorDepartamento, @ReceptorPais, @UsuId);

	COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelFraseConsultar]
	@CiaId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT ffr_id AS FfrId, cia_id AS CiaId, ffr_tipo_frase AS TipoFrase, ffr_codigo_escenario AS CodigoEscenario,
		   ffr_descripcion AS Descripcion, ffr_aplica_notas AS AplicaNotas, ffr_estado AS Estado
	FROM dbo.fel_frase WHERE cia_id = @CiaId ORDER BY ffr_tipo_frase, ffr_codigo_escenario;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelFraseGuardar]
	@FfrId			INT = NULL,
	@CiaId			INT,
	@TipoFrase		SMALLINT,
	@CodigoEscenario SMALLINT,
	@Descripcion	VARCHAR(256) = NULL,
	@AplicaNotas	BIT = 0,
	@Estado			CHAR(1) = 'A',
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @TipoFrase <= 0 OR @CodigoEscenario <= 0
		THROW 53304, 'El tipo de frase y el código de escenario deben ser mayores a cero.', 1;
	IF EXISTS (SELECT 1 FROM dbo.fel_frase WHERE cia_id = @CiaId AND ffr_tipo_frase = @TipoFrase AND ffr_codigo_escenario = @CodigoEscenario
			   AND ffr_id <> ISNULL(@FfrId, 0))
		THROW 53305, 'Esa combinación de tipo de frase y escenario ya está registrada.', 1;

	IF @FfrId IS NULL
		INSERT INTO dbo.fel_frase (cia_id, ffr_tipo_frase, ffr_codigo_escenario, ffr_descripcion, ffr_aplica_notas, ffr_estado, InsUsuario)
		VALUES (@CiaId, @TipoFrase, @CodigoEscenario, @Descripcion, @AplicaNotas, @Estado, @UsuId);
	ELSE
		UPDATE dbo.fel_frase
		   SET ffr_tipo_frase = @TipoFrase, ffr_codigo_escenario = @CodigoEscenario, ffr_descripcion = @Descripcion,
			   ffr_aplica_notas = @AplicaNotas, ffr_estado = @Estado, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE ffr_id = @FfrId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelFraseEliminar]
	@FfrId INT
AS
BEGIN
	SET NOCOUNT ON;
	DELETE FROM dbo.fel_frase WHERE ffr_id = @FfrId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelEstablecimientoConsultar]
	@CiaId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT sucu.suc_id AS SucId, sucu.suc_codigo AS SucCodigo, sucu.suc_descripcion AS SucDescripcion, sucu.suc_direccion AS Direccion,
		   sucu.suc_fel_codigo_establecimiento AS CodigoEstablecimiento, sucu.suc_fel_nombre_comercial AS NombreComercial,
		   sucu.suc_codigo_postal AS CodigoPostal, sucu.prov_id AS ProvId, muni.prov_nombre AS Municipio, depa.est_nombre AS Departamento,
		   pais.pai_codigo_alfa2 AS Pais, sucu.suc_estado AS Estado
	FROM dbo.gen_sucursal sucu
	LEFT JOIN dbo.gen_provincia muni ON muni.prov_id = sucu.prov_id
	LEFT JOIN dbo.gen_estado depa ON depa.est_id = muni.est_id
	LEFT JOIN dbo.gen_pais pais ON pais.pai_id = depa.pai_id
	WHERE sucu.cia_id = @CiaId
	ORDER BY sucu.suc_fel_codigo_establecimiento, sucu.suc_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelEstablecimientoGuardar]
	@SucId					INT,
	@CodigoEstablecimiento	INT,
	@NombreComercial		VARCHAR(256),
	@CodigoPostal			VARCHAR(10),
	@ProvId					INT,
	@UsuId					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @cia_id INT = (SELECT cia_id FROM dbo.gen_sucursal WHERE suc_id = @SucId);
	IF @cia_id IS NULL
		THROW 53306, 'La sucursal indicada no existe.', 1;
	IF @CodigoEstablecimiento <= 0
		THROW 53307, 'El código de establecimiento debe ser mayor a cero (el que SAT asignó al establecimiento).', 1;
	IF EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE cia_id = @cia_id AND suc_fel_codigo_establecimiento = @CodigoEstablecimiento AND suc_id <> @SucId)
		THROW 53308, 'Otra sucursal de la compañía ya usa ese código de establecimiento.', 1;
	IF LTRIM(RTRIM(ISNULL(@NombreComercial, ''))) = '' OR NOT EXISTS (SELECT 1 FROM dbo.gen_provincia WHERE prov_id = @ProvId)
		THROW 53309, 'Indique el nombre comercial y el municipio del establecimiento.', 1;

	UPDATE dbo.gen_sucursal
	   SET suc_fel_codigo_establecimiento = @CodigoEstablecimiento, suc_fel_nombre_comercial = LTRIM(RTRIM(@NombreComercial)),
		   suc_codigo_postal = NULLIF(LTRIM(RTRIM(@CodigoPostal)), ''), prov_id = @ProvId,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE suc_id = @SucId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelMunicipiosConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT muni.prov_id AS ProvId, muni.prov_nombre AS Municipio, depa.est_nombre AS Departamento, pais.pai_codigo_alfa2 AS Pais
	FROM dbo.gen_provincia muni
	INNER JOIN dbo.gen_estado depa ON depa.est_id = muni.est_id
	INNER JOIN dbo.gen_pais pais ON pais.pai_id = depa.pai_id
	ORDER BY pais.pai_codigo_alfa2, depa.est_nombre, muni.prov_nombre;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelTipoDocumentoConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT tdo_id AS TdoId, tdo_codigo AS TdoCodigo, tdo_descripcion AS TdoDescripcion, tdo_naturaleza AS Naturaleza,
		   tdo_es_nota AS EsNota, tdo_fel_tipo_dte AS TipoDte, tdo_fel_tipo_dte_contado AS TipoDteContado, tdo_fel_certifica AS Certifica
	FROM dbo.inv_documento_tipo
	ORDER BY tdo_naturaleza, tdo_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelTipoDocumentoGuardar]
	@TdoId			INT,
	@TipoDte		VARCHAR(4) = NULL,
	@TipoDteContado	VARCHAR(4) = NULL,
	@Certifica		BIT,
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @Certifica = 1 AND ISNULL(@TipoDte, '') = ''
		THROW 53310, 'Indique el tipo de DTE para certificar este tipo de documento.', 1;
	IF @Certifica = 1 AND EXISTS (SELECT 1 FROM dbo.inv_documento_tipo WHERE tdo_id = @TdoId AND tdo_naturaleza = '+' AND tdo_es_nota = 0)
		THROW 53311, 'Las compras las certifica el proveedor; solo se certifican ventas y notas a clientes.', 1;

	UPDATE dbo.inv_documento_tipo
	   SET tdo_fel_tipo_dte = NULLIF(@TipoDte, ''), tdo_fel_tipo_dte_contado = NULLIF(@TipoDteContado, ''), tdo_fel_certifica = @Certifica
	 WHERE tdo_id = @TdoId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelUnidadMedidaConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT ume_id AS UmeId, ume_codigo AS UmeCodigo, ume_descripcion AS UmeDescripcion, ume_fel_codigo AS FelCodigo, ume_estado AS Estado
	FROM dbo.inv_unidad_medida ORDER BY ume_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelUnidadMedidaGuardar]
	@UmeId		INT,
	@FelCodigo	VARCHAR(3),
	@UsuId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF LEN(LTRIM(RTRIM(ISNULL(@FelCodigo, '')))) = 0
		THROW 53312, 'Indique el código FEL de la unidad (hasta 3 caracteres).', 1;
	UPDATE dbo.inv_unidad_medida SET ume_fel_codigo = UPPER(LTRIM(RTRIM(@FelCodigo))), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE ume_id = @UmeId;
END;
GO

------------------------------------------------------------
-- 4. FEL: datos del DTE, resultado y consultas
------------------------------------------------------------
-- Cinco resultados: encabezado (emisor, receptor, nota y configuración),
-- líneas, frases, abonos (factura cambiaria) y la bitácora no se incluye.
-- Los montos de las líneas vienen sin IVA, como se graban; la aplicación
-- arma los montos con IVA que pide SAT.
CREATE OR ALTER PROCEDURE [dbo].[paFelDocumentoDatosConsultar]
	@EncId INT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @suc_id INT = (SELECT TOP 1 bode.suc_id FROM dbo.inv_documento_det deta
						   INNER JOIN dbo.inv_bodega bode ON bode.bod_id = deta.bod_id
						   WHERE deta.enc_id = @EncId ORDER BY deta.det_item);
	IF @suc_id IS NULL
		SET @suc_id = (SELECT TOP 1 suc_id FROM dbo.gen_sucursal ORDER BY suc_id);

	SELECT docu.enc_id AS EncId, tipo.tdo_codigo AS TdoCodigo, tipo.tdo_es_nota AS EsNota, tipo.tdo_fel_certifica AS Certifica,
		   CASE WHEN tipo.tdo_fel_tipo_dte_contado IS NOT NULL
					 AND NOT EXISTS (SELECT 1 FROM dbo.pos_cliente_plan_pagos cuot WHERE cuot.enc_id = docu.enc_id)
				THEN tipo.tdo_fel_tipo_dte_contado ELSE tipo.tdo_fel_tipo_dte END AS TipoDte,
		   DATEADD(SECOND, DATEDIFF(SECOND, CAST(docu.enc_fecha_grabado AS DATE), docu.enc_fecha_grabado),
				   CAST(docu.enc_fecha_docto AS DATETIME2(0))) AS FechaHoraEmision,
		   ISNULL(mone.mon_codigo, 'GTQ') AS CodigoMoneda, docu.enc_numero_unico AS NumeroUnico, docu.enc_estado AS EstadoDocumento,
		   docu.enc_monto_total AS MontoTotal,
		   -- Emisor
		   comp.cia_id AS CiaId, REPLACE(comp.cia_nit, '-', '') AS NitEmisor, ISNULL(comp.cia_fel_nombre_emisor, comp.cia_nombre_comercial) AS NombreEmisor,
		   ISNULL(sucu.suc_fel_nombre_comercial, sucu.suc_descripcion) AS NombreComercial, comp.cia_fel_afiliacion_iva AS AfiliacionIva,
		   sucu.suc_fel_codigo_establecimiento AS CodigoEstablecimiento, comp.cia_fel_correo_emisor AS CorreoEmisor,
		   ISNULL(sucu.suc_direccion, comp.cia_direccion) AS DireccionEmisor, ISNULL(sucu.suc_codigo_postal, '01001') AS CodigoPostalEmisor,
		   muni.prov_nombre AS MunicipioEmisor, depa.est_nombre AS DepartamentoEmisor, ISNULL(pais.pai_codigo_alfa2, 'GT') AS PaisEmisor,
		   -- Receptor (consumidor final si no hay NIT)
		   CASE WHEN clie.cli_fel_tipo_receptor = 'CUI' THEN REPLACE(REPLACE(ISNULL(clie.cli_DPI, ''), ' ', ''), '-', '')
				ELSE UPPER(REPLACE(ISNULL(NULLIF(LTRIM(RTRIM(ISNULL(docu.cli_nit, clie.cli_nit))), ''), 'CF'), '-', '')) END AS IdReceptor,
		   clie.cli_fel_tipo_receptor AS TipoEspecial,
		   LTRIM(RTRIM(CONCAT(ISNULL(docu.enc_nombres_cliente, clie.cli_nombres), ' ', ISNULL(docu.enc_apellidos_cliente, clie.cli_apellidos)))) AS NombreReceptor,
		   clie.cli_email AS CorreoReceptor,
		   COALESCE(NULLIF(docu.enc_direccion_cliente, ''), NULLIF(clie.cli_direccion, ''), conf.fco_receptor_direccion) AS DireccionReceptor,
		   ISNULL(clie.cli_codigo_postal, conf.fco_receptor_codigo_postal) AS CodigoPostalReceptor,
		   ISNULL(cmun.prov_nombre, conf.fco_receptor_municipio) AS MunicipioReceptor,
		   ISNULL(cdep.est_nombre, conf.fco_receptor_departamento) AS DepartamentoReceptor,
		   ISNULL(cpai.pai_codigo_alfa2, conf.fco_receptor_pais) AS PaisReceptor,
		   -- Nota: documento de origen
		   docu.enc_motivo AS MotivoAjuste, orig.fdo_uuid AS OrigenUuid, orig.fdo_serie AS OrigenSerie, orig.fdo_numero AS OrigenNumero,
		   refe.enc_fecha_docto AS OrigenFechaEmision, refe.enc_id AS OrigenEncId,
		   -- Configuración
		   conf.fco_certificador AS Certificador, ISNULL(conf.fco_activo, 0) AS Activo, conf.fco_ambiente AS Ambiente,
		   conf.fco_url_certificacion AS UrlCertificacion, conf.fco_url_anulacion AS UrlAnulacion,
		   conf.fco_usuario_firma AS UsuarioFirma, conf.fco_usuario_api AS UsuarioApi, conf.fco_correo_copia AS CorreoCopia,
		   ISNULL(conf.fco_timeout_segundos, 30) AS TimeoutSegundos, conf.fco_xmlns_dte AS XmlnsDte, conf.fco_version_dte AS VersionDte,
		   -- Estado FEL actual
		   feld.fdo_estado AS FelEstado, feld.fdo_uuid AS FelUuid, feld.fdo_fecha_certificacion AS FelFechaCertificacion,
		   feld.fdo_tipo_dte AS FelTipoDte, ISNULL(feld.fdo_intentos, 0) AS FelIntentos
	FROM dbo.inv_documento_enc docu
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = @suc_id
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	LEFT JOIN dbo.fel_configuracion conf ON conf.cia_id = comp.cia_id
	LEFT JOIN dbo.gen_moneda mone ON mone.mon_id = docu.mon_id
	LEFT JOIN dbo.gen_provincia muni ON muni.prov_id = sucu.prov_id
	LEFT JOIN dbo.gen_estado depa ON depa.est_id = muni.est_id
	LEFT JOIN dbo.gen_pais pais ON pais.pai_id = depa.pai_id
	LEFT JOIN dbo.pos_cliente clie ON clie.cli_id = docu.cli_id
	LEFT JOIN dbo.gen_provincia cmun ON cmun.prov_id = clie.cli_direccion_provincia
	LEFT JOIN dbo.gen_estado cdep ON cdep.est_id = ISNULL(cmun.est_id, clie.cli_direccion_estado)
	LEFT JOIN dbo.gen_pais cpai ON cpai.pai_id = ISNULL(cdep.pai_id, clie.cli_direccion_pais)
	LEFT JOIN dbo.inv_documento_enc refe ON refe.enc_id = docu.enc_id_referencia
	LEFT JOIN dbo.fel_documento orig ON orig.enc_id = docu.enc_id_referencia
	LEFT JOIN dbo.fel_documento feld ON feld.enc_id = docu.enc_id
	WHERE docu.enc_id = @EncId;

	SELECT deta.det_item AS NumeroLinea, deta.det_bien_o_servicio AS BienOServicio, deta.det_cantidad AS Cantidad,
		   COALESCE(unid.ume_fel_codigo, LEFT(unid.ume_codigo, 3), 'UND') AS UnidadMedida, deta.det_descripcion AS Descripcion,
		   deta.det_precio_unitario AS PrecioUnitarioNeto, deta.det_sub_total AS SubTotalNeto,
		   ISNULL(deta.det_valor_descuento, 0) AS DescuentoNeto, ISNULL(deta.det_porc_iva, 0) AS PorcIva
	FROM dbo.inv_documento_det deta
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = deta.ume_id
	WHERE deta.enc_id = @EncId
	ORDER BY deta.det_item;

	SELECT frase.ffr_tipo_frase AS TipoFrase, frase.ffr_codigo_escenario AS CodigoEscenario, frase.ffr_aplica_notas AS AplicaNotas
	FROM dbo.fel_frase frase
	WHERE frase.ffr_estado = 'A'
	  AND frase.cia_id = (SELECT sucu.cia_id FROM dbo.gen_sucursal sucu WHERE sucu.suc_id = @suc_id)
	ORDER BY frase.ffr_tipo_frase, frase.ffr_codigo_escenario;

	SELECT cuot.cpp_nro_cuota AS NumeroAbono, cuot.cpp_fecha_maxima_pago AS FechaVencimiento, cuot.cpp_valor_cuota AS MontoAbono
	FROM dbo.pos_cliente_plan_pagos cuot
	WHERE cuot.enc_id = @EncId
	ORDER BY cuot.cpp_nro_cuota;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelResultadoRegistrar]
	@EncId				INT,
	@Operacion			VARCHAR(12),	-- CERTIFICAR | ANULAR
	@Exito				BIT,
	@Estado				CHAR(1),		-- estado resultante (P, R, C, A, X)
	@TipoDte			VARCHAR(4),
	@Certificador		VARCHAR(20),
	@Uuid				VARCHAR(64) = NULL,
	@Serie				VARCHAR(32) = NULL,
	@Numero				VARCHAR(32) = NULL,
	@FechaCertificacion	DATETIME2(0) = NULL,
	@Mensaje			NVARCHAR(2000) = NULL,
	@XmlEnviado			NVARCHAR(MAX) = NULL,
	@XmlCertificado		NVARCHAR(MAX) = NULL,
	@Respuesta			NVARCHAR(MAX) = NULL,
	@MotivoAnulacion	VARCHAR(256) = NULL,
	@UsuId				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @Operacion NOT IN ('CERTIFICAR', 'ANULAR')
		THROW 53313, 'Operación FEL no válida.', 1;

	BEGIN TRANSACTION;

	IF @Operacion = 'CERTIFICAR'
		MERGE dbo.fel_documento AS dest
		USING (SELECT @EncId AS enc_id) AS orig ON dest.enc_id = orig.enc_id
		WHEN MATCHED THEN UPDATE SET
			fdo_tipo_dte = @TipoDte, fdo_estado = @Estado, fdo_certificador = @Certificador,
			fdo_uuid = CASE WHEN @Exito = 1 THEN @Uuid ELSE dest.fdo_uuid END,
			fdo_serie = CASE WHEN @Exito = 1 THEN @Serie ELSE dest.fdo_serie END,
			fdo_numero = CASE WHEN @Exito = 1 THEN @Numero ELSE dest.fdo_numero END,
			fdo_fecha_certificacion = CASE WHEN @Exito = 1 THEN @FechaCertificacion ELSE dest.fdo_fecha_certificacion END,
			fdo_xml_enviado = ISNULL(@XmlEnviado, dest.fdo_xml_enviado),
			fdo_xml_certificado = CASE WHEN @Exito = 1 THEN @XmlCertificado ELSE dest.fdo_xml_certificado END,
			fdo_mensaje = @Mensaje, fdo_intentos = dest.fdo_intentos + 1, fdo_fecha_ultimo_intento = SYSDATETIME(),
			UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		WHEN NOT MATCHED THEN INSERT
			(enc_id, fdo_tipo_dte, fdo_estado, fdo_certificador, fdo_uuid, fdo_serie, fdo_numero, fdo_fecha_certificacion,
			 fdo_xml_enviado, fdo_xml_certificado, fdo_mensaje, fdo_intentos, fdo_fecha_ultimo_intento, InsUsuario)
		VALUES
			(@EncId, @TipoDte, @Estado, @Certificador, @Uuid, @Serie, @Numero, @FechaCertificacion,
			 @XmlEnviado, @XmlCertificado, @Mensaje, 1, SYSDATETIME(), @UsuId);
	ELSE
		UPDATE dbo.fel_documento
		   SET fdo_estado = @Estado, fdo_mensaje = @Mensaje, fdo_motivo_anulacion = ISNULL(@MotivoAnulacion, fdo_motivo_anulacion),
			   fdo_fecha_anulacion = CASE WHEN @Exito = 1 THEN ISNULL(@FechaCertificacion, SYSDATETIME()) ELSE fdo_fecha_anulacion END,
			   fdo_xml_anulacion = ISNULL(@XmlEnviado, fdo_xml_anulacion), fdo_fecha_ultimo_intento = SYSDATETIME(),
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId;

	-- La autorización (UUID) queda también en el documento.
	IF @Operacion = 'CERTIFICAR' AND @Exito = 1
		UPDATE dbo.inv_documento_enc
		   SET enc_numero_autorizacion = @Uuid, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId;

	INSERT INTO dbo.fel_bitacora (enc_id, fbi_operacion, fbi_exito, fbi_mensaje, fbi_respuesta, usu_id)
	VALUES (@EncId, @Operacion, @Exito, @Mensaje, @Respuesta, @UsuId);

	COMMIT TRANSACTION;
END;
GO

-- Documentos que se certifican (según su tipo), con su estado FEL. Estado
-- 'N' = todavía no enviado.
CREATE OR ALTER PROCEDURE [dbo].[paFelDocumentosConsultar]
	@Estado	CHAR(1) = NULL,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT docu.enc_id AS EncId, docu.enc_fecha_docto AS Fecha, tipo.tdo_codigo AS TdoCodigo,
		   ISNULL(docu.enc_numero_unico, CONCAT(docu.enc_serie_docto, '-', docu.enc_numero_docto)) AS Documento,
		   LTRIM(RTRIM(CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos))) AS Cliente, docu.enc_monto_total AS Total,
		   docu.enc_estado AS EstadoDocumento, ISNULL(feld.fdo_estado, 'N') AS FelEstado, feld.fdo_tipo_dte AS TipoDte,
		   feld.fdo_uuid AS Uuid, feld.fdo_serie AS Serie, feld.fdo_numero AS Numero, feld.fdo_fecha_certificacion AS FechaCertificacion,
		   feld.fdo_mensaje AS Mensaje, ISNULL(feld.fdo_intentos, 0) AS Intentos, feld.fdo_fecha_ultimo_intento AS UltimoIntento,
		   feld.fdo_certificador AS Certificador
	FROM dbo.inv_documento_enc docu
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id AND tipo.tdo_fel_certifica = 1
	LEFT JOIN dbo.pos_cliente clie ON clie.cli_id = docu.cli_id
	LEFT JOIN dbo.fel_documento feld ON feld.enc_id = docu.enc_id
	WHERE (@Estado IS NULL OR ISNULL(feld.fdo_estado, 'N') = @Estado)
	  AND (@Desde IS NULL OR docu.enc_fecha_docto >= @Desde)
	  AND (@Hasta IS NULL OR docu.enc_fecha_docto <= @Hasta)
	  -- Un documento anulado en el sistema que nunca se certificó no hay que enviarlo.
	  AND NOT (docu.enc_estado <> 'G' AND feld.enc_id IS NULL)
	ORDER BY docu.enc_fecha_docto DESC, docu.enc_id DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelDocumentoDetalleConsultar]
	@EncId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT enc_id AS EncId, fdo_tipo_dte AS TipoDte, fdo_estado AS Estado, fdo_certificador AS Certificador, fdo_uuid AS Uuid,
		   fdo_serie AS Serie, fdo_numero AS Numero, fdo_fecha_certificacion AS FechaCertificacion, fdo_xml_enviado AS XmlEnviado,
		   fdo_xml_certificado AS XmlCertificado, fdo_mensaje AS Mensaje, fdo_intentos AS Intentos, fdo_motivo_anulacion AS MotivoAnulacion,
		   fdo_fecha_anulacion AS FechaAnulacion, fdo_xml_anulacion AS XmlAnulacion
	FROM dbo.fel_documento WHERE enc_id = @EncId;

	SELECT fbi_id AS FbiId, fbi_fecha AS Fecha, fbi_operacion AS Operacion, fbi_exito AS Exito, fbi_mensaje AS Mensaje,
		   usua.usu_usuario AS Usuario
	FROM dbo.fel_bitacora bita
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = bita.usu_id
	WHERE bita.enc_id = @EncId
	ORDER BY bita.fbi_id DESC;
END;
GO

------------------------------------------------------------
-- 5. Tableros
------------------------------------------------------------
-- Sucursal de un documento: la de la bodega de su primera línea.
CREATE OR ALTER FUNCTION [dbo].[fnDocumentoSucursal] (@EncId INT)
RETURNS INT
AS
BEGIN
	RETURN (SELECT TOP 1 bode.suc_id FROM dbo.inv_documento_det deta
			INNER JOIN dbo.inv_bodega bode ON bode.bod_id = deta.bod_id
			WHERE deta.enc_id = @EncId ORDER BY deta.det_item);
END;
GO

-- Agrupa por día si el rango es de hasta 62 días; si no, por mes.
CREATE OR ALTER FUNCTION [dbo].[fnTableroPeriodo] (@Fecha DATE, @Desde DATE, @Hasta DATE)
RETURNS DATE
AS
BEGIN
	RETURN CASE WHEN DATEDIFF(DAY, @Desde, @Hasta) <= 62 THEN @Fecha ELSE DATEFROMPARTS(YEAR(@Fecha), MONTH(@Fecha), 1) END;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paTableroVentas]
	@Desde	DATE,
	@Hasta	DATE,
	@SucId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @Hasta < @Desde
		THROW 53314, 'La fecha final no puede ser anterior a la inicial.', 1;

	DECLARE @dias INT = DATEDIFF(DAY, @Desde, @Hasta) + 1;
	DECLARE @antDesde DATE = DATEADD(DAY, -@dias, @Desde), @antHasta DATE = DATEADD(DAY, -1, @Desde);

	-- Facturas vigentes de ambos períodos con sus montos netos (sin IVA) y costo.
	DECLARE @docs TABLE (enc_id INT PRIMARY KEY, fecha DATE, actual BIT, cli_id INT, pve_id INT, neto NUMERIC(14, 2), costo NUMERIC(14, 2),
						 total NUMERIC(14, 2), credito BIT);
	INSERT INTO @docs
	SELECT docu.enc_id, docu.enc_fecha_docto, CASE WHEN docu.enc_fecha_docto >= @Desde THEN 1 ELSE 0 END, docu.cli_id, docu.pve_id,
		   lins.neto, lins.costo, docu.enc_monto_total,
		   CASE WHEN EXISTS (SELECT 1 FROM dbo.pos_cliente_plan_pagos cuot WHERE cuot.enc_id = docu.enc_id) THEN 1 ELSE 0 END
	FROM dbo.inv_documento_enc docu
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id AND tipo.tdo_naturaleza = '-' AND tipo.tdo_es_nota = 0
	CROSS APPLY (SELECT SUM(deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) AS neto,
						SUM(deta.det_cantidad * ISNULL(deta.det_costo_unitario, 0)) AS costo
				 FROM dbo.inv_documento_det deta WHERE deta.enc_id = docu.enc_id) lins
	WHERE docu.enc_estado = 'G' AND docu.enc_fecha_docto BETWEEN @antDesde AND @Hasta
	  AND (@SucId IS NULL OR dbo.fnDocumentoSucursal(docu.enc_id) = @SucId);

	DECLARE @notas NUMERIC(14, 2) = (
		SELECT ISNULL(SUM(nota.enc_monto_total), 0) FROM dbo.inv_documento_enc nota
		INNER JOIN dbo.inv_documento_tipo tnot ON tnot.tdo_id = nota.tdo_id AND tnot.tdo_codigo = 'NCC'
		WHERE nota.enc_estado = 'G' AND nota.enc_fecha_docto BETWEEN @Desde AND @Hasta
		  AND (@SucId IS NULL OR dbo.fnDocumentoSucursal(nota.enc_id_referencia) = @SucId));

	SELECT ISNULL(SUM(CASE WHEN actual = 1 THEN neto END), 0) AS Ventas,
		   COUNT(CASE WHEN actual = 1 THEN 1 END) AS Facturas,
		   ISNULL(SUM(CASE WHEN actual = 1 THEN costo END), 0) AS Costo,
		   ISNULL(SUM(CASE WHEN actual = 1 AND credito = 1 THEN neto END), 0) AS VentasCredito,
		   ISNULL(SUM(CASE WHEN actual = 1 THEN total END), 0) AS VentasConIva,
		   @notas AS NotasCredito,
		   ISNULL(SUM(CASE WHEN actual = 0 THEN neto END), 0) AS VentasAnterior,
		   COUNT(CASE WHEN actual = 0 THEN 1 END) AS FacturasAnterior,
		   ISNULL(SUM(CASE WHEN actual = 0 THEN costo END), 0) AS CostoAnterior,
		   COUNT(DISTINCT CASE WHEN actual = 1 THEN cli_id END) AS Clientes,
		   CAST(CASE WHEN @dias <= 62 THEN 'D' ELSE 'M' END AS CHAR(1)) AS Agrupacion
	FROM @docs;

	SELECT dbo.fnTableroPeriodo(fecha, @Desde, @Hasta) AS Periodo, SUM(neto) AS Ventas, SUM(costo) AS Costo, COUNT(*) AS Facturas
	FROM @docs WHERE actual = 1
	GROUP BY dbo.fnTableroPeriodo(fecha, @Desde, @Hasta)
	ORDER BY Periodo;

	SELECT TOP 10 clie.cli_id AS Id, clie.cli_codigo AS Codigo, LTRIM(RTRIM(CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos))) AS Nombre,
		   SUM(docs.neto) AS Ventas, SUM(docs.costo) AS Costo, COUNT(*) AS Facturas
	FROM @docs docs INNER JOIN dbo.pos_cliente clie ON clie.cli_id = docs.cli_id
	WHERE docs.actual = 1
	GROUP BY clie.cli_id, clie.cli_codigo, clie.cli_nombres, clie.cli_apellidos
	ORDER BY Ventas DESC;

	SELECT TOP 10 CASE WHEN deta.pro_id IS NULL THEN 0 ELSE deta.pro_id END AS Id,
		   CASE WHEN deta.pro_id IS NULL THEN 'S' ELSE 'B' END AS Tipo,
		   CASE WHEN deta.pro_id IS NULL THEN MAX(deta.det_descripcion) ELSE MAX(prod.pro_descripcion) END AS Nombre,
		   SUM(deta.det_cantidad) AS Cantidad, SUM(deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) AS Ventas,
		   SUM(deta.det_cantidad * ISNULL(deta.det_costo_unitario, 0)) AS Costo
	FROM @docs docs
	INNER JOIN dbo.inv_documento_det deta ON deta.enc_id = docs.enc_id
	LEFT JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
	WHERE docs.actual = 1
	GROUP BY deta.pro_id, CASE WHEN deta.pro_id IS NULL THEN deta.det_descripcion END
	ORDER BY Ventas DESC;

	SELECT ISNULL(vend.pve_id, 0) AS Id, ISNULL(LTRIM(RTRIM(CONCAT(vend.pve_nombres, ' ', vend.pve_apellidos))), 'Sin vendedor') AS Nombre,
		   SUM(docs.neto) AS Ventas, COUNT(*) AS Facturas
	FROM @docs docs LEFT JOIN dbo.pos_vendedor vend ON vend.pve_id = docs.pve_id
	WHERE docs.actual = 1
	GROUP BY vend.pve_id, vend.pve_nombres, vend.pve_apellidos
	ORDER BY Ventas DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paTableroCartera]
	@Desde	DATE,
	@Hasta	DATE,
	@SucId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @Hasta < @Desde
		THROW 53314, 'La fecha final no puede ser anterior a la inicial.', 1;
	DECLARE @hoy DATE = CAST(GETDATE() AS DATE);

	DECLARE @cuotas TABLE (cpp_id INT PRIMARY KEY, cli_id INT, vence DATE, valor NUMERIC(14, 2), saldo NUMERIC(14, 2));
	INSERT INTO @cuotas
	SELECT cuot.cpp_id, cuot.cli_id, cuot.cpp_fecha_maxima_pago, cuot.cpp_valor_cuota, cuot.cpp_saldo_cuota
	FROM dbo.pos_cliente_plan_pagos cuot
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
	WHERE @SucId IS NULL OR dbo.fnDocumentoSucursal(docu.enc_id) = @SucId;

	-- Cobros de cuotas (no los pagos de contado al facturar), vigentes.
	DECLARE @cobros TABLE (ppd_id INT PRIMARY KEY, ppe_id INT, fecha DATE, cpp_id INT, monto NUMERIC(14, 2));
	INSERT INTO @cobros
	SELECT deta.ppd_id, pago.ppe_id, CAST(pago.ppe_fecha_pago AS DATE), deta.cpp_id, deta.ppd_valor_aplicado
	FROM dbo.pos_pago_det deta
	INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
	INNER JOIN @cuotas cuot ON cuot.cpp_id = deta.cpp_id;

	SELECT ISNULL((SELECT SUM(saldo) FROM @cuotas), 0) AS Cartera,
		   ISNULL((SELECT SUM(saldo) FROM @cuotas WHERE vence < @hoy), 0) AS Vencida,
		   ISNULL((SELECT SUM(monto) FROM @cobros WHERE fecha BETWEEN @Desde AND @Hasta), 0) AS Cobrado,
		   (SELECT COUNT(DISTINCT ppe_id) FROM @cobros WHERE fecha BETWEEN @Desde AND @Hasta) AS Recibos,
		   ISNULL((SELECT SUM(valor) FROM @cuotas WHERE vence BETWEEN @Desde AND @Hasta), 0) AS Vencia,
		   -- De lo que vencía en el período, cuánto ya se cobró (a cualquier fecha).
		   ISNULL((SELECT SUM(cobr.monto) FROM @cobros cobr INNER JOIN @cuotas cuot ON cuot.cpp_id = cobr.cpp_id
				   WHERE cuot.vence BETWEEN @Desde AND @Hasta), 0) AS CobradoDeLoQueVencia,
		   (SELECT COUNT(DISTINCT cli_id) FROM @cuotas WHERE saldo > 0 AND vence < @hoy) AS ClientesMorosos,
		   CAST(CASE WHEN DATEDIFF(DAY, @Desde, @Hasta) <= 62 THEN 'D' ELSE 'M' END AS CHAR(1)) AS Agrupacion;

	-- Por período: lo que vencía y lo cobrado.
	;WITH vencia AS (
		SELECT dbo.fnTableroPeriodo(vence, @Desde, @Hasta) AS Periodo, SUM(valor) AS Monto
		FROM @cuotas WHERE vence BETWEEN @Desde AND @Hasta GROUP BY dbo.fnTableroPeriodo(vence, @Desde, @Hasta)
	), cobrado AS (
		SELECT dbo.fnTableroPeriodo(fecha, @Desde, @Hasta) AS Periodo, SUM(monto) AS Monto
		FROM @cobros WHERE fecha BETWEEN @Desde AND @Hasta GROUP BY dbo.fnTableroPeriodo(fecha, @Desde, @Hasta)
	)
	SELECT COALESCE(venc.Periodo, cobr.Periodo) AS Periodo, ISNULL(venc.Monto, 0) AS Vencia, ISNULL(cobr.Monto, 0) AS Cobrado
	FROM vencia venc FULL OUTER JOIN cobrado cobr ON cobr.Periodo = venc.Periodo
	ORDER BY Periodo;

	-- Antigüedad del saldo a hoy.
	SELECT rang.Orden, rang.Rango, ISNULL(SUM(cuot.saldo), 0) AS Saldo, COUNT(cuot.cpp_id) AS Cuotas
	FROM (VALUES (1, 'No vencido', -100000, 0), (2, '1-30 días', 1, 30), (3, '31-60 días', 31, 60), (4, '61-90 días', 61, 90), (5, 'Más de 90 días', 91, 100000))
		 rang(Orden, Rango, DiasDesde, DiasHasta)
	LEFT JOIN @cuotas cuot ON cuot.saldo > 0 AND DATEDIFF(DAY, cuot.vence, @hoy) BETWEEN rang.DiasDesde AND rang.DiasHasta
	GROUP BY rang.Orden, rang.Rango
	ORDER BY rang.Orden;

	SELECT TOP 10 clie.cli_id AS Id, clie.cli_codigo AS Codigo, LTRIM(RTRIM(CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos))) AS Nombre,
		   SUM(CASE WHEN cuot.vence < @hoy THEN cuot.saldo ELSE 0 END) AS Vencido, SUM(cuot.saldo) AS Saldo,
		   MAX(CASE WHEN cuot.saldo > 0 AND cuot.vence < @hoy THEN DATEDIFF(DAY, cuot.vence, @hoy) END) AS DiasMaximo
	FROM @cuotas cuot INNER JOIN dbo.pos_cliente clie ON clie.cli_id = cuot.cli_id
	WHERE cuot.saldo > 0
	GROUP BY clie.cli_id, clie.cli_codigo, clie.cli_nombres, clie.cli_apellidos
	HAVING SUM(CASE WHEN cuot.vence < @hoy THEN cuot.saldo ELSE 0 END) > 0
	ORDER BY Vencido DESC;

	SELECT tipo.pft_descripcion AS Forma, SUM(forma.ppf_monto) AS Monto
	FROM dbo.pos_pago_forma forma
	INNER JOIN dbo.pos_pago_forma_tipo tipo ON tipo.pft_id = forma.pft_id
	WHERE forma.ppe_id IN (SELECT ppe_id FROM @cobros WHERE fecha BETWEEN @Desde AND @Hasta)
	GROUP BY tipo.pft_descripcion
	ORDER BY Monto DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paTableroCompras]
	@Desde	DATE,
	@Hasta	DATE,
	@SucId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @Hasta < @Desde
		THROW 53314, 'La fecha final no puede ser anterior a la inicial.', 1;
	DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
	DECLARE @dias INT = DATEDIFF(DAY, @Desde, @Hasta) + 1;
	DECLARE @antDesde DATE = DATEADD(DAY, -@dias, @Desde);

	DECLARE @docs TABLE (enc_id INT PRIMARY KEY, fecha DATE, actual BIT, prv_id INT, neto NUMERIC(14, 2), total NUMERIC(14, 2));
	INSERT INTO @docs
	SELECT docu.enc_id, docu.enc_fecha_docto, CASE WHEN docu.enc_fecha_docto >= @Desde THEN 1 ELSE 0 END, docu.prv_id,
		   (SELECT SUM(deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) FROM dbo.inv_documento_det deta WHERE deta.enc_id = docu.enc_id),
		   docu.enc_monto_total
	FROM dbo.inv_documento_enc docu
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id AND tipo.tdo_naturaleza = '+' AND tipo.tdo_es_nota = 0
	WHERE docu.enc_estado = 'G' AND docu.enc_fecha_docto BETWEEN @antDesde AND @Hasta
	  AND (@SucId IS NULL OR dbo.fnDocumentoSucursal(docu.enc_id) = @SucId);

	-- Cuotas por pagar (todas las compras vigentes, no solo las del período).
	DECLARE @cuotas TABLE (ppg_id INT PRIMARY KEY, enc_id INT, prv_id INT, nro INT, vence DATE, saldo NUMERIC(14, 2));
	INSERT INTO @cuotas
	SELECT cuot.ppg_id, cuot.enc_id, docu.prv_id, cuot.ppg_nro_pago, cuot.ppg_fecha_pago, cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0)
	FROM dbo.inv_proveedor_plan_pago cuot
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
	WHERE cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) > 0
	  AND (@SucId IS NULL OR dbo.fnDocumentoSucursal(docu.enc_id) = @SucId);

	DECLARE @pagos TABLE (bce_id INT PRIMARY KEY, fecha DATE, valor NUMERIC(14, 2));
	INSERT INTO @pagos
	SELECT cheq.bce_id, cheq.bce_fecha_emision, cheq.bce_valor
	FROM dbo.bco_cheque_emitido_enc cheq
	WHERE cheq.bce_estado_cheque <> 'A' AND cheq.bce_fecha_emision BETWEEN @Desde AND @Hasta
	  AND (@SucId IS NULL OR EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_det chdt WHERE chdt.bce_id = cheq.bce_id
									 AND dbo.fnDocumentoSucursal(chdt.enc_id) = @SucId));

	SELECT ISNULL(SUM(CASE WHEN actual = 1 THEN neto END), 0) AS Compras,
		   COUNT(CASE WHEN actual = 1 THEN 1 END) AS Documentos,
		   ISNULL(SUM(CASE WHEN actual = 0 THEN neto END), 0) AS ComprasAnterior,
		   ISNULL((SELECT SUM(saldo) FROM @cuotas), 0) AS PorPagar,
		   ISNULL((SELECT SUM(saldo) FROM @cuotas WHERE vence < @hoy), 0) AS Vencido,
		   ISNULL((SELECT SUM(saldo) FROM @cuotas WHERE vence BETWEEN @hoy AND DATEADD(DAY, 30, @hoy)), 0) AS Proximos30,
		   ISNULL((SELECT SUM(valor) FROM @pagos), 0) AS Pagado,
		   (SELECT COUNT(*) FROM @pagos) AS Cheques,
		   CAST(CASE WHEN @dias <= 62 THEN 'D' ELSE 'M' END AS CHAR(1)) AS Agrupacion
	FROM @docs;

	;WITH compras AS (
		SELECT dbo.fnTableroPeriodo(fecha, @Desde, @Hasta) AS Periodo, SUM(neto) AS Monto FROM @docs WHERE actual = 1
		GROUP BY dbo.fnTableroPeriodo(fecha, @Desde, @Hasta)
	), pagado AS (
		SELECT dbo.fnTableroPeriodo(fecha, @Desde, @Hasta) AS Periodo, SUM(valor) AS Monto FROM @pagos
		GROUP BY dbo.fnTableroPeriodo(fecha, @Desde, @Hasta)
	)
	SELECT COALESCE(comp.Periodo, paga.Periodo) AS Periodo, ISNULL(comp.Monto, 0) AS Compras, ISNULL(paga.Monto, 0) AS Pagado
	FROM compras comp FULL OUTER JOIN pagado paga ON paga.Periodo = comp.Periodo
	ORDER BY Periodo;

	SELECT TOP 10 prov.prv_id AS Id, prov.prv_codigo AS Codigo, prov.prv_nombre_comercial AS Nombre,
		   ISNULL(SUM(docs.neto), 0) AS Compras,
		   ISNULL((SELECT SUM(cuot.saldo) FROM @cuotas cuot WHERE cuot.prv_id = prov.prv_id), 0) AS Saldo
	FROM @docs docs INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = docs.prv_id
	WHERE docs.actual = 1
	GROUP BY prov.prv_id, prov.prv_codigo, prov.prv_nombre_comercial
	ORDER BY Compras DESC;

	-- Compromisos de pago: lo vencido y las próximas 12 semanas (lunes a domingo).
	DECLARE @lunes DATE = DATEADD(DAY, -((DATEPART(WEEKDAY, @hoy) + @@DATEFIRST - 2) % 7), @hoy);
	;WITH semanas AS (
		SELECT 0 AS Orden, CAST(NULL AS DATE) AS Desde, DATEADD(DAY, -1, @hoy) AS Hasta
		UNION ALL
		SELECT n.n, DATEADD(WEEK, n.n - 1, @lunes), DATEADD(DAY, 6, DATEADD(WEEK, n.n - 1, @lunes))
		FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12)) n(n)
	)
	SELECT sema.Orden, sema.Desde, sema.Hasta, ISNULL(SUM(cuot.saldo), 0) AS Monto, COUNT(cuot.ppg_id) AS Cuotas
	FROM semanas sema
	LEFT JOIN @cuotas cuot ON (sema.Orden = 0 AND cuot.vence < @hoy)
						   OR (sema.Orden > 0 AND cuot.vence BETWEEN CASE WHEN sema.Desde < @hoy THEN @hoy ELSE sema.Desde END AND sema.Hasta)
	GROUP BY sema.Orden, sema.Desde, sema.Hasta
	ORDER BY sema.Orden;

	SELECT TOP 15 prov.prv_id AS PrvId, prov.prv_nombre_comercial AS Proveedor,
		   CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto) AS Documento,
		   cuot.nro AS Cuota, cuot.vence AS Vence, cuot.saldo AS Saldo, DATEDIFF(DAY, @hoy, cuot.vence) AS Dias
	FROM @cuotas cuot
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = cuot.prv_id
	ORDER BY cuot.vence, cuot.ppg_id;
END;
GO

------------------------------------------------------------
-- 6. Permisos
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT v.modulo, v.codigo, v.descripcion
FROM (VALUES
	('GENERAL', 'TABLERO_GERENCIAL', 'Tableros de ventas, cartera, compras y compromisos de pago'),
	('VENTAS',  'FEL_ADMIN',         'Factura electrónica: configuración, certificación y reintentos')
) v(modulo, codigo, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso perm WHERE perm.per_codigo = v.codigo);

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id, InsFechaHora)
SELECT rol.rol_id, perm.per_id, SYSDATETIME()
FROM dbo.sec_rol rol
INNER JOIN (VALUES ('ADMIN', 'TABLERO_GERENCIAL'), ('ADMIN', 'FEL_ADMIN'), ('CONTADOR', 'FEL_ADMIN')) v(rol, permiso) ON v.rol = rol.rol_codigo
INNER JOIN dbo.sec_permiso perm ON perm.per_codigo = v.permiso
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO
