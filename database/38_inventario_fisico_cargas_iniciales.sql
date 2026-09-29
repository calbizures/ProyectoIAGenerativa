------------------------------------------------------------------------------
-- 38_inventario_fisico_cargas_iniciales.sql
--
-- Fase B del segundo bloque de requerimientos:
--
--   1. Documentos internos de inventario. Nuevos tipos con
--      tdo_es_interno = 1 (no son ventas ni compras: no aparecen en Facturas,
--      Compras, cuentas por cobrar/pagar ni tableros):
--          INVI  Inventario inicial                 (+)
--          AJIS  Sobrante de inventario físico      (+)
--          AJIF  Faltante de inventario físico      (-)
--      paInvDocumentoInternoCrear graba el documento y mueve existencias y
--      costo promedio con sp_inventario_ajustar_existencia_documento.
--
--   2. Inventario físico por bodega (inv_toma_fisica): se abre una toma con
--      los productos que manejan existencia, se registra el conteo y al
--      aplicarla la diferencia contra la existencia de ese momento genera
--      los documentos de ajuste y sus partidas:
--          Sobrante: Debe INVENTARIO           / Haber INVENTARIO_SOBRANTE
--          Faltante: Debe INVENTARIO_FALTANTE  / Haber INVENTARIO
--      Los productos sin conteo no se ajustan. Anular una toma aplicada anula
--      sus documentos (revierte existencias) y sus partidas.
--
--   3. Carga del inventario inicial (desde Excel): sucursal, bodega,
--      producto + unidad de medida, cantidad, costo total y precio de venta
--      con IVA. Crea los productos que no existen, un documento INVI por
--      bodega (existencias y costo promedio = costo total / cantidad) y el
--      precio de venta de cada producto en su bodega. No genera partida: su
--      valor entra en la partida de saldos iniciales.
--
--   4. Saldos iniciales (desde Excel): la nomenclatura se exporta, el
--      contador pone el Debe o el Haber de cada cuenta de movimiento y al
--      cargarla se genera la partida de apertura (origen APERTURA). Avisa si
--      la cuenta de inventario no coincide con el inventario inicial cargado.
--
--   5. Carga de empleados (desde Excel): alta o actualización por código,
--      con su plaza, salario y datos de pago de nómina.
--
-- Las cargas se validan completas antes de grabar: si una fila tiene error no
-- se graba nada. Todas devuelven (Fila, Tipo E = error / A = advertencia,
-- Mensaje) y un resumen; con @SoloValidar = 1 solo validan.
--
-- Errores 53501-53510. Requiere 36. Se puede volver a correr.
------------------------------------------------------------------------------

USE [erp_db];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Documentos internos de inventario
------------------------------------------------------------
IF COL_LENGTH('dbo.inv_documento_tipo', 'tdo_es_interno') IS NULL
	ALTER TABLE dbo.inv_documento_tipo ADD [tdo_es_interno] BIT NOT NULL
		CONSTRAINT [DF_inv_documento_tipo_es_interno] DEFAULT (0);	-- 1 = ajuste o carga inicial (no es venta ni compra)
GO

INSERT INTO dbo.inv_documento_tipo (tdo_codigo, tdo_descripcion, tdo_naturaleza, afecta_costo, tdo_es_nota, tdo_es_interno, tdo_fel_certifica)
SELECT v.c, v.d, v.n, 'S', 0, 1, 0
FROM (VALUES ('INVI', 'Inventario inicial', '+'),
			 ('AJIS', 'Sobrante de inventario físico', '+'),
			 ('AJIF', 'Faltante de inventario físico', '-')) v(c, d, n)
WHERE NOT EXISTS (SELECT 1 FROM dbo.inv_documento_tipo tipo WHERE tipo.tdo_codigo = v.c);
UPDATE dbo.inv_documento_tipo SET tdo_es_interno = 1 WHERE tdo_codigo IN ('INVI', 'AJIS', 'AJIF') AND tdo_es_interno = 0;
GO

-- Nuevos orígenes de partida.
IF OBJECT_ID('dbo.CK_cont_asiento_enc_origen', 'C') IS NOT NULL
	ALTER TABLE dbo.cont_asiento_enc DROP CONSTRAINT [CK_cont_asiento_enc_origen];
ALTER TABLE dbo.cont_asiento_enc ADD CONSTRAINT [CK_cont_asiento_enc_origen]
	CHECK ([asi_origen] IN ('MANUAL','VENTA','COMPRA','PAGO_CLIENTE','PAGO_PROVEEDOR','DEPOSITO','CIERRE_CAJA','NOMINA',
							'NOTA_CREDITO','NOTA_DEBITO',		-- 32
							'CHEQUE','PAGO_NOMINA',				-- 36
							'AJUSTE_INVENTARIO','APERTURA'));	-- 38
GO

-- Cuentas y conceptos del ajuste por inventario físico. Si la nomenclatura
-- no tiene las cuentas, se crean bajo ingresos (411) y gastos (511).
DECLARE @padre INT, @codigo VARCHAR(20), @cta INT;
IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_nombre = 'SOBRANTES DE INVENTARIO')
BEGIN
	SET @padre = (SELECT cta_id FROM dbo.cont_cuenta_contable WHERE cta_codigo = '411');
	IF @padre IS NOT NULL
	BEGIN
		EXEC dbo.paCuentaContableSiguienteCodigo @IdPadre = @padre, @Codigo = @codigo OUTPUT;
		EXEC dbo.paCuentaContableNodoGuardar @IdPadre = @padre, @Codigo = @codigo, @Nombre = 'SOBRANTES DE INVENTARIO',
			@Tipo = 'I', @Naturaleza = 'H', @IdResultado = @cta OUTPUT;
	END
END
IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_nombre = 'FALTANTES DE INVENTARIO')
BEGIN
	SET @padre = (SELECT cta_id FROM dbo.cont_cuenta_contable WHERE cta_codigo = '511');
	IF @padre IS NOT NULL
	BEGIN
		EXEC dbo.paCuentaContableSiguienteCodigo @IdPadre = @padre, @Codigo = @codigo OUTPUT;
		EXEC dbo.paCuentaContableNodoGuardar @IdPadre = @padre, @Codigo = @codigo, @Nombre = 'FALTANTES DE INVENTARIO',
			@Tipo = 'G', @Naturaleza = 'D', @IdResultado = @cta OUTPUT;
	END
END

INSERT INTO dbo.cont_cuenta_parametro (ccp_codigo, ccp_descripcion, ccp_naturaleza, cta_id)
SELECT v.codigo, v.descripcion, v.naturaleza,
	   (SELECT TOP 1 cuen.cta_id FROM dbo.cont_cuenta_contable cuen WHERE cuen.cta_nombre = v.cuenta AND cuen.cta_acepta_movimiento = 1)
FROM (VALUES
	('INVENTARIO_FALTANTE', 'Inventario físico: faltante (gasto)',   'D', 'FALTANTES DE INVENTARIO'),
	('INVENTARIO_SOBRANTE', 'Inventario físico: sobrante (ingreso)', 'H', 'SOBRANTES DE INVENTARIO')
) v(codigo, descripcion, naturaleza, cuenta)
WHERE NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_parametro para WHERE para.ccp_codigo = v.codigo);
GO

IF TYPE_ID(N'dbo.inv_documento_interno_type') IS NULL
CREATE TYPE [dbo].[inv_documento_interno_type] AS TABLE
(
	[bod_id]			INT				NOT NULL,
	[pro_id]			INT				NOT NULL,
	[cantidad]			NUMERIC(12, 4)	NOT NULL,
	[costo_total]		NUMERIC(12, 2)	NOT NULL,	-- en un egreso lo pone el costo promedio
	PRIMARY KEY ([bod_id], [pro_id])
);
GO

-- Graba un documento interno (INVI, AJIS o AJIF) y mueve existencias y costo.
CREATE OR ALTER PROCEDURE [dbo].[paInvDocumentoInternoCrear]
	@TdoCodigo	VARCHAR(8),
	@Fecha		DATE,
	@Motivo		VARCHAR(256) = NULL,
	@Lineas		dbo.inv_documento_interno_type READONLY,
	@UsuId		INT,
	@EncId		INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @tdo_id INT, @naturaleza CHAR(1);
	SELECT @tdo_id = tdo_id, @naturaleza = tdo_naturaleza FROM dbo.inv_documento_tipo WHERE tdo_codigo = @TdoCodigo AND tdo_es_interno = 1;
	IF @tdo_id IS NULL
		THROW 53501, 'El tipo de documento interno no existe.', 1;
	IF NOT EXISTS (SELECT 1 FROM @Lineas WHERE cantidad > 0)
		THROW 53502, 'El documento no tiene líneas.', 1;

	DECLARE @numero INT = (SELECT COUNT(*) + 1 FROM dbo.inv_documento_enc WHERE tdo_id = @tdo_id);

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.inv_documento_enc
			(enc_fecha_docto, enc_serie_docto, enc_numero_docto, tdo_id, enc_monto_total, mon_id, usu_id_creacion, enc_estado, enc_motivo,
			 InsUsuario, InsFechaHora)
		VALUES
			(@Fecha, @TdoCodigo, CAST(@numero AS VARCHAR(32)), @tdo_id, (SELECT SUM(costo_total) FROM @Lineas WHERE cantidad > 0), dbo.fn_moneda_local(),
			 @UsuId, 'G', @Motivo, @UsuId, SYSDATETIME());
		SET @EncId = SCOPE_IDENTITY();

		INSERT INTO dbo.inv_documento_det
			(enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_valor_descuento, det_sub_total,
			 det_porc_iva, bod_id, pro_id, ume_id, InsUsuario, InsFechaHora)
		SELECT @EncId, ROW_NUMBER() OVER (ORDER BY prod.pro_codigo, lins.bod_id), 'B', lins.cantidad, LEFT(prod.pro_descripcion, 512),
			   ROUND(lins.costo_total / lins.cantidad, 2), 0, lins.costo_total, 0, lins.bod_id, lins.pro_id, prod.ume_id, @UsuId, SYSDATETIME()
		FROM @Lineas lins
		INNER JOIN dbo.inv_producto prod ON prod.pro_id = lins.pro_id
		WHERE lins.cantidad > 0;

		-- Un ingreso toma como costo subtotal / cantidad; un egreso, el costo
		-- promedio del producto.
		EXEC dbo.sp_inventario_ajustar_existencia_documento @enc_id = @EncId, @reversar = 0, @usu_id = @UsuId;

		IF @naturaleza = '-'
			UPDATE enca
			   SET enc_monto_total = (SELECT ROUND(SUM(deta.det_cantidad * deta.det_costo_unitario), 2) FROM dbo.inv_documento_det deta WHERE deta.enc_id = enca.enc_id)
			FROM dbo.inv_documento_enc enca WHERE enca.enc_id = @EncId;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 2. Inventario físico
------------------------------------------------------------
IF OBJECT_ID('dbo.inv_toma_fisica', 'U') IS NULL
CREATE TABLE [dbo].[inv_toma_fisica](
	[tfi_id]				INT				IDENTITY(1,1)	NOT NULL,
	[bod_id]				INT				NOT NULL,
	[tfi_fecha]				DATE			NOT NULL,
	[tfi_observaciones]		VARCHAR(250)	NULL,
	[tfi_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_inv_toma_fisica_estado] DEFAULT ('B'),	-- B = en conteo, A = aplicada, N = anulada
	[enc_id_sobrante]		INT				NULL,
	[enc_id_faltante]		INT				NULL,
	[tfi_fecha_aplicacion]	DATETIME2(0)	NULL,
	[tfi_motivo_anulacion]	VARCHAR(250)	NULL,
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_toma_fisica] PRIMARY KEY CLUSTERED ([tfi_id]),
	CONSTRAINT [CK_inv_toma_fisica_estado] CHECK ([tfi_estado] IN ('B','A','N')),
	CONSTRAINT [FK_inv_toma_fisica_bodega] FOREIGN KEY ([bod_id]) REFERENCES [dbo].[inv_bodega]([bod_id]),
	CONSTRAINT [FK_inv_toma_fisica_sobrante] FOREIGN KEY ([enc_id_sobrante]) REFERENCES [dbo].[inv_documento_enc]([enc_id]),
	CONSTRAINT [FK_inv_toma_fisica_faltante] FOREIGN KEY ([enc_id_faltante]) REFERENCES [dbo].[inv_documento_enc]([enc_id]),
	CONSTRAINT [FK_inv_toma_fisica_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES [dbo].[gen_usuario]([usu_id]),
	CONSTRAINT [FK_inv_toma_fisica_UpdUsuario] FOREIGN KEY ([UpdUsuario]) REFERENCES [dbo].[gen_usuario]([usu_id])
);
GO

IF OBJECT_ID('dbo.inv_toma_fisica_det', 'U') IS NULL
CREATE TABLE [dbo].[inv_toma_fisica_det](
	[tfd_id]				INT				IDENTITY(1,1)	NOT NULL,
	[tfi_id]				INT				NOT NULL,
	[pro_id]				INT				NOT NULL,
	[tfd_existencia]		NUMERIC(12, 4)	NOT NULL,	-- al abrir la toma; al aplicarla, la que se usó para la diferencia
	[tfd_conteo]			NUMERIC(12, 4)	NULL,		-- NULL = no se contó (no se ajusta)
	[tfd_costo_unitario]	NUMERIC(14, 5)	NULL,		-- costo promedio al aplicar
	CONSTRAINT [PK_inv_toma_fisica_det] PRIMARY KEY CLUSTERED ([tfd_id]),
	CONSTRAINT [UQ_inv_toma_fisica_det] UNIQUE ([tfi_id], [pro_id]),
	CONSTRAINT [CK_inv_toma_fisica_det_conteo] CHECK ([tfd_conteo] IS NULL OR [tfd_conteo] >= 0),
	CONSTRAINT [FK_inv_toma_fisica_det_toma] FOREIGN KEY ([tfi_id]) REFERENCES [dbo].[inv_toma_fisica]([tfi_id]),
	CONSTRAINT [FK_inv_toma_fisica_det_producto] FOREIGN KEY ([pro_id]) REFERENCES [dbo].[inv_producto]([pro_id])
);
GO

IF TYPE_ID(N'dbo.inv_toma_conteo_type') IS NULL
CREATE TYPE [dbo].[inv_toma_conteo_type] AS TABLE
(
	[pro_id]	INT				NOT NULL PRIMARY KEY,
	[conteo]	NUMERIC(12, 4)	NULL
);
GO

CREATE OR ALTER PROCEDURE [dbo].[paInvTomaConsultar]
	@SucId	INT = NULL,
	@BodId	INT = NULL,
	@Estado	CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT toma.tfi_id AS TfiId, toma.bod_id AS BodId, bode.bod_descripcion AS Bodega, sucu.suc_id AS SucId, sucu.suc_descripcion AS Sucursal,
		   toma.tfi_fecha AS Fecha, toma.tfi_observaciones AS Observaciones, toma.tfi_estado AS Estado, toma.tfi_fecha_aplicacion AS FechaAplicacion,
		   toma.tfi_motivo_anulacion AS MotivoAnulacion, resu.Productos, resu.Contados,
		   ISNULL(sobr.enc_monto_total, 0) AS ValorSobrante, ISNULL(falt.enc_monto_total, 0) AS ValorFaltante,
		   usua.usu_usuario AS Usuario
	FROM dbo.inv_toma_fisica toma
	INNER JOIN dbo.inv_bodega bode ON bode.bod_id = toma.bod_id
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
	CROSS APPLY (SELECT COUNT(*) AS Productos, COUNT(deta.tfd_conteo) AS Contados FROM dbo.inv_toma_fisica_det deta WHERE deta.tfi_id = toma.tfi_id) resu
	LEFT JOIN dbo.inv_documento_enc sobr ON sobr.enc_id = toma.enc_id_sobrante
	LEFT JOIN dbo.inv_documento_enc falt ON falt.enc_id = toma.enc_id_faltante
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = toma.InsUsuario
	WHERE (@SucId IS NULL OR sucu.suc_id = @SucId)
	  AND (@BodId IS NULL OR toma.bod_id = @BodId)
	  AND (@Estado IS NULL OR toma.tfi_estado = @Estado)
	ORDER BY toma.tfi_fecha DESC, toma.tfi_id DESC;
END;
GO

-- Abre una toma con los productos activos que manejan existencia (todos o
-- solo los que tienen existencia en la bodega). Una toma abierta por bodega.
CREATE OR ALTER PROCEDURE [dbo].[paInvTomaCrear]
	@BodId				INT,
	@Fecha				DATE,
	@Observaciones		VARCHAR(250) = NULL,
	@SoloConExistencia	BIT = 0,
	@UsuId				INT,
	@IdResultado		INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE bod_id = @BodId AND bod_estado = 'A')
		THROW 53503, 'La bodega no existe o está inactiva.', 1;
	IF EXISTS (SELECT 1 FROM dbo.inv_toma_fisica WHERE bod_id = @BodId AND tfi_estado = 'B')
		THROW 53504, 'Esta bodega ya tiene una toma de inventario abierta; aplíquela o anúlela antes de abrir otra.', 1;

	BEGIN TRANSACTION;
	INSERT INTO dbo.inv_toma_fisica (bod_id, tfi_fecha, tfi_observaciones, InsUsuario)
	VALUES (@BodId, ISNULL(@Fecha, CAST(GETDATE() AS DATE)), NULLIF(LTRIM(RTRIM(@Observaciones)), ''), @UsuId);
	SET @IdResultado = SCOPE_IDENTITY();

	INSERT INTO dbo.inv_toma_fisica_det (tfi_id, pro_id, tfd_existencia)
	SELECT @IdResultado, prod.pro_id, ISNULL(exis.existencia, 0)
	FROM dbo.inv_producto prod
	LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = prod.pro_id AND exis.bod_id = @BodId
	WHERE prod.pro_estado = 'A' AND prod.pro_maneja_existencia = 1
	  AND (@SoloConExistencia = 0 OR ISNULL(exis.existencia, 0) <> 0);

	IF @@ROWCOUNT = 0
		THROW 53505, 'No hay productos para contar en esta bodega.', 1;
	COMMIT TRANSACTION;
END;
GO

-- Líneas de la toma. Mientras está abierta se muestra la existencia actual
-- (la que se usará al aplicar); aplicada, la que se usó.
CREATE OR ALTER PROCEDURE [dbo].[paInvTomaDetalleConsultar]
	@TfiId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT deta.tfd_id AS TfdId, deta.pro_id AS ProId, prod.pro_codigo AS Codigo, prod.pro_descripcion AS Descripcion,
		   unid.ume_codigo AS Unidad, tipo.prt_descripcion AS TipoProducto,
		   CASE WHEN toma.tfi_estado = 'B' THEN ISNULL(exis.existencia, 0) ELSE deta.tfd_existencia END AS Existencia,
		   deta.tfd_conteo AS Conteo,
		   CASE WHEN toma.tfi_estado = 'B' THEN prod.pro_costo_unitario ELSE deta.tfd_costo_unitario END AS CostoUnitario
	FROM dbo.inv_toma_fisica_det deta
	INNER JOIN dbo.inv_toma_fisica toma ON toma.tfi_id = deta.tfi_id
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
	LEFT JOIN dbo.inv_producto_tipo tipo ON tipo.prt_id = prod.prt_id
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = prod.ume_id
	LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = deta.pro_id AND exis.bod_id = toma.bod_id
	WHERE deta.tfi_id = @TfiId
	ORDER BY tipo.prt_descripcion, prod.pro_descripcion;
END;
GO

-- Guarda el conteo de los productos recibidos (NULL = no contado).
CREATE OR ALTER PROCEDURE [dbo].[paInvTomaConteoGuardar]
	@TfiId		INT,
	@Conteos	dbo.inv_toma_conteo_type READONLY,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_toma_fisica WHERE tfi_id = @TfiId AND tfi_estado = 'B')
		THROW 53506, 'Solo se registra el conteo de una toma abierta.', 1;
	IF EXISTS (SELECT 1 FROM @Conteos WHERE conteo < 0)
		THROW 53507, 'El conteo no puede ser negativo.', 1;

	UPDATE deta SET tfd_conteo = cont.conteo
	FROM dbo.inv_toma_fisica_det deta
	INNER JOIN @Conteos cont ON cont.pro_id = deta.pro_id
	WHERE deta.tfi_id = @TfiId;

	UPDATE dbo.inv_toma_fisica SET UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE tfi_id = @TfiId;
END;
GO

-- Aplica la toma: diferencia = conteo - existencia actual. Los sobrantes
-- entran al costo promedio del producto y los faltantes salen a ese costo.
CREATE OR ALTER PROCEDURE [dbo].[paInvTomaAplicar]
	@TfiId	INT,
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @bod_id INT, @fecha DATE, @bodega VARCHAR(128);
	SELECT @bod_id = toma.bod_id, @fecha = toma.tfi_fecha, @bodega = bode.bod_descripcion
	FROM dbo.inv_toma_fisica toma INNER JOIN dbo.inv_bodega bode ON bode.bod_id = toma.bod_id
	WHERE toma.tfi_id = @TfiId AND toma.tfi_estado = 'B';
	IF @bod_id IS NULL
		THROW 53506, 'Solo se aplica una toma abierta.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_toma_fisica_det WHERE tfi_id = @TfiId AND tfd_conteo IS NOT NULL)
		THROW 53508, 'La toma no tiene ningún producto contado.', 1;

	DECLARE @cta_inventario INT, @cta_faltante INT, @cta_sobrante INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO', @CtaId = @cta_inventario OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		-- La existencia y el costo que valen son los de este momento.
		UPDATE deta
		   SET tfd_existencia = ISNULL(exis.existencia, 0), tfd_costo_unitario = prod.pro_costo_unitario
		FROM dbo.inv_toma_fisica_det deta
		INNER JOIN dbo.inv_producto prod WITH (UPDLOCK) ON prod.pro_id = deta.pro_id
		LEFT JOIN dbo.inv_producto_existencia_bodega exis WITH (UPDLOCK) ON exis.pro_id = deta.pro_id AND exis.bod_id = @bod_id
		WHERE deta.tfi_id = @TfiId;

		DECLARE @sobrantes dbo.inv_documento_interno_type, @faltantes dbo.inv_documento_interno_type;
		INSERT INTO @sobrantes (bod_id, pro_id, cantidad, costo_total)
		SELECT @bod_id, pro_id, tfd_conteo - tfd_existencia, ROUND((tfd_conteo - tfd_existencia) * ISNULL(tfd_costo_unitario, 0), 2)
		FROM dbo.inv_toma_fisica_det WHERE tfi_id = @TfiId AND tfd_conteo > tfd_existencia;
		INSERT INTO @faltantes (bod_id, pro_id, cantidad, costo_total)
		SELECT @bod_id, pro_id, tfd_existencia - tfd_conteo, ROUND((tfd_existencia - tfd_conteo) * ISNULL(tfd_costo_unitario, 0), 2)
		FROM dbo.inv_toma_fisica_det WHERE tfi_id = @TfiId AND tfd_conteo < tfd_existencia;

		DECLARE @enc_sobrante INT, @enc_faltante INT, @valor NUMERIC(14, 2), @asi_id INT, @partida dbo.cont_asiento_det_type, @texto VARCHAR(256);
		DECLARE @motivo VARCHAR(256) = CONCAT('Inventario físico #', @TfiId, ' - ', @bodega);

		IF EXISTS (SELECT 1 FROM @sobrantes)
		BEGIN
			EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO_SOBRANTE', @CtaId = @cta_sobrante OUTPUT;
			EXEC dbo.paInvDocumentoInternoCrear @TdoCodigo = 'AJIS', @Fecha = @fecha, @Motivo = @motivo, @Lineas = @sobrantes,
				@UsuId = @UsuId, @EncId = @enc_sobrante OUTPUT;
			SET @valor = (SELECT enc_monto_total FROM dbo.inv_documento_enc WHERE enc_id = @enc_sobrante);
			IF @valor > 0
			BEGIN
				SET @texto = CONCAT('Sobrante de ', LOWER(@motivo));
				INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
				VALUES (@cta_inventario, @valor, 0, @texto), (@cta_sobrante, 0, @valor, @texto);
				EXEC dbo.sp_contabilidad_insertar_asiento @asi_fecha = @fecha, @asi_descripcion = @texto, @asi_origen = 'AJUSTE_INVENTARIO',
					@asi_origen_id = @TfiId, @enc_id = @enc_sobrante, @usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;
			END
		END

		IF EXISTS (SELECT 1 FROM @faltantes)
		BEGIN
			EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO_FALTANTE', @CtaId = @cta_faltante OUTPUT;
			EXEC dbo.paInvDocumentoInternoCrear @TdoCodigo = 'AJIF', @Fecha = @fecha, @Motivo = @motivo, @Lineas = @faltantes,
				@UsuId = @UsuId, @EncId = @enc_faltante OUTPUT;
			SET @valor = (SELECT enc_monto_total FROM dbo.inv_documento_enc WHERE enc_id = @enc_faltante);
			IF @valor > 0
			BEGIN
				DELETE FROM @partida;
				SET @texto = CONCAT('Faltante de ', LOWER(@motivo));
				INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
				VALUES (@cta_faltante, @valor, 0, @texto), (@cta_inventario, 0, @valor, @texto);
				EXEC dbo.sp_contabilidad_insertar_asiento @asi_fecha = @fecha, @asi_descripcion = @texto, @asi_origen = 'AJUSTE_INVENTARIO',
					@asi_origen_id = @TfiId, @enc_id = @enc_faltante, @usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;
			END
		END

		UPDATE dbo.inv_toma_fisica
		   SET tfi_estado = 'A', enc_id_sobrante = @enc_sobrante, enc_id_faltante = @enc_faltante, tfi_fecha_aplicacion = SYSDATETIME(),
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE tfi_id = @TfiId;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Anula una toma. Si estaba aplicada, anula sus documentos de ajuste
-- (revierte existencias) y sus partidas.
CREATE OR ALTER PROCEDURE [dbo].[paInvTomaAnular]
	@TfiId	INT,
	@Motivo	VARCHAR(250),
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado CHAR(1), @sobrante INT, @faltante INT;
	SELECT @estado = tfi_estado, @sobrante = enc_id_sobrante, @faltante = enc_id_faltante FROM dbo.inv_toma_fisica WHERE tfi_id = @TfiId;
	IF @estado IS NULL OR @estado = 'N'
		THROW 53509, 'La toma no existe o ya está anulada.', 1;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 53214, 'Indique el motivo de la anulación (al menos 5 caracteres).', 1;

	BEGIN TRY
		BEGIN TRANSACTION;
		IF @sobrante IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_id = @sobrante AND enc_estado = 'G')
			EXEC dbo.sp_documento_anular @enc_id = @sobrante, @usu_id = @UsuId;
		IF @faltante IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_id = @faltante AND enc_estado = 'G')
			EXEC dbo.sp_documento_anular @enc_id = @faltante, @usu_id = @UsuId;
		UPDATE dbo.inv_toma_fisica
		   SET tfi_estado = 'N', tfi_motivo_anulacion = LEFT(LTRIM(RTRIM(@Motivo)), 250), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE tfi_id = @TfiId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 3. Carga del inventario inicial
------------------------------------------------------------
IF TYPE_ID(N'dbo.inv_carga_inicial_type') IS NULL
CREATE TYPE [dbo].[inv_carga_inicial_type] AS TABLE
(
	[Fila]			INT				NOT NULL PRIMARY KEY,
	[Sucursal]		VARCHAR(16)		NULL,	-- código de la sucursal
	[Bodega]		VARCHAR(16)		NULL,	-- código de la bodega
	[Producto]		VARCHAR(64)		NULL,	-- código del producto
	[Descripcion]	VARCHAR(256)	NULL,	-- para crear el producto si no existe
	[Tipo]			VARCHAR(16)		NULL,	-- código del tipo de producto (para crearlo)
	[Unidad]		VARCHAR(16)		NULL,	-- código de la unidad de medida
	[Cantidad]		NUMERIC(12, 4)	NULL,
	[CostoTotal]	NUMERIC(12, 2)	NULL,
	[PrecioVenta]	NUMERIC(12, 2)	NULL	-- precio unitario de venta con IVA
);
GO

CREATE OR ALTER PROCEDURE [dbo].[paInvCargaInicialProcesar]
	@Fecha			DATE,
	@Filas			dbo.inv_carga_inicial_type READONLY,
	@SoloValidar	BIT = 1,
	@UsuId			INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @datos TABLE (Fila INT PRIMARY KEY, suc_id INT, bod_id INT, bod_suc_id INT, pro_id INT, pro_ume_id INT, pro_maneja BIT,
						  prt_id INT, ume_id INT, Producto VARCHAR(64), Descripcion VARCHAR(256), Cantidad NUMERIC(12, 4),
						  CostoTotal NUMERIC(12, 2), PrecioVenta NUMERIC(12, 2), Sucursal VARCHAR(16), Bodega VARCHAR(16),
						  Tipo VARCHAR(16), Unidad VARCHAR(16));
	INSERT INTO @datos
	SELECT fila.Fila, sucu.suc_id, bode.bod_id, bode.suc_id, prod.pro_id, prod.ume_id, prod.pro_maneja_existencia,
		   tipo.prt_id, unid.ume_id, NULLIF(LTRIM(RTRIM(fila.Producto)), ''), NULLIF(LTRIM(RTRIM(fila.Descripcion)), ''),
		   fila.Cantidad, fila.CostoTotal, fila.PrecioVenta, fila.Sucursal, fila.Bodega, fila.Tipo, fila.Unidad
	FROM @Filas fila
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_codigo = LTRIM(RTRIM(fila.Sucursal))
	LEFT JOIN dbo.inv_bodega bode ON bode.bod_codigo = LTRIM(RTRIM(fila.Bodega))
	LEFT JOIN dbo.inv_producto prod ON prod.pro_codigo = LTRIM(RTRIM(fila.Producto))
	LEFT JOIN dbo.inv_producto_tipo tipo ON tipo.prt_codigo = LTRIM(RTRIM(fila.Tipo))
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_codigo = LTRIM(RTRIM(fila.Unidad));

	DECLARE @mensajes TABLE (Fila INT, Tipo CHAR(1), Mensaje NVARCHAR(400));
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT Fila, 'E', Mensaje FROM (
		SELECT Fila, CASE
			WHEN suc_id IS NULL THEN CONCAT(N'La sucursal "', Sucursal, N'" no existe.')
			WHEN bod_id IS NULL THEN CONCAT(N'La bodega "', Bodega, N'" no existe.')
			WHEN bod_suc_id <> suc_id THEN CONCAT(N'La bodega "', Bodega, N'" no pertenece a la sucursal "', Sucursal, N'".')
			WHEN Producto IS NULL THEN N'Falta el código del producto.'
			WHEN pro_id IS NOT NULL AND pro_maneja = 0 THEN CONCAT(N'El producto "', Producto, N'" es un servicio: no maneja existencia.')
			WHEN pro_id IS NULL AND Descripcion IS NULL THEN CONCAT(N'El producto "', Producto, N'" no existe: indique su descripción para crearlo.')
			WHEN pro_id IS NULL AND prt_id IS NULL THEN CONCAT(N'El producto "', Producto, N'" no existe: indique un tipo de producto válido para crearlo.')
			WHEN Unidad IS NOT NULL AND ume_id IS NULL THEN CONCAT(N'La unidad de medida "', Unidad, N'" no existe.')
			WHEN pro_id IS NULL AND ume_id IS NULL THEN CONCAT(N'El producto "', Producto, N'" no existe: indique su unidad de medida para crearlo.')
			WHEN pro_id IS NOT NULL AND ume_id IS NOT NULL AND ISNULL(pro_ume_id, 0) <> ume_id
				THEN CONCAT(N'El producto "', Producto, N'" ya existe con otra unidad de medida.')
			WHEN ISNULL(Cantidad, 0) <= 0 THEN N'La cantidad debe ser mayor a cero.'
			WHEN CostoTotal IS NULL OR CostoTotal < 0 THEN N'El costo total debe ser cero o mayor.'
			WHEN PrecioVenta IS NOT NULL AND PrecioVenta < 0 THEN N'El precio de venta no puede ser negativo.'
		END AS Mensaje
		FROM @datos) vali
	WHERE Mensaje IS NOT NULL;

	-- El mismo producto dos veces en la misma bodega.
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT dato.Fila, 'E', CONCAT(N'El producto "', dato.Producto, N'" se repite en la bodega "', dato.Bodega, N'".')
	FROM @datos dato
	WHERE dato.Producto IS NOT NULL AND dato.bod_id IS NOT NULL
	  AND EXISTS (SELECT 1 FROM @datos otro WHERE otro.Producto = dato.Producto AND otro.bod_id = dato.bod_id AND otro.Fila < dato.Fila);

	-- Advertencias: la bodega ya tiene existencia de ese producto (se suma).
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT dato.Fila, 'A', CONCAT(N'El producto "', dato.Producto, N'" ya tiene ', FORMAT(exis.existencia, 'N2'), N' en la bodega; la carga se suma.')
	FROM @datos dato
	INNER JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = dato.pro_id AND exis.bod_id = dato.bod_id AND exis.existencia <> 0
	WHERE NOT EXISTS (SELECT 1 FROM @mensajes mens WHERE mens.Fila = dato.Fila AND mens.Tipo = 'E');

	IF NOT EXISTS (SELECT 1 FROM @datos)
		INSERT INTO @mensajes VALUES (0, 'E', N'El archivo no tiene filas.');

	DECLARE @nuevos INT = (SELECT COUNT(DISTINCT Producto) FROM @datos WHERE pro_id IS NULL);
	IF @SoloValidar = 0 AND NOT EXISTS (SELECT 1 FROM @mensajes WHERE Tipo = 'E')
	BEGIN
		BEGIN TRY
			BEGIN TRANSACTION;

			-- Productos nuevos (una sola vez por código aunque venga en varias bodegas).
			INSERT INTO dbo.inv_producto (pro_codigo, pro_descripcion, pro_tipo_item, pro_maneja_existencia, pro_total_cantidad, pro_total_costo,
										  pro_costo_unitario, prt_id, pro_estado, ume_id, InsUsuario, InsFechaHora)
			SELECT prim.Producto, prim.Descripcion, 'B', 1, 0, 0, 0, prim.prt_id, 'A', prim.ume_id, @UsuId, SYSDATETIME()
			FROM (SELECT dato.*, ROW_NUMBER() OVER (PARTITION BY dato.Producto ORDER BY dato.Fila) AS orden FROM @datos dato WHERE dato.pro_id IS NULL) prim
			WHERE prim.orden = 1;

			UPDATE dato SET pro_id = prod.pro_id
			FROM @datos dato INNER JOIN dbo.inv_producto prod ON prod.pro_codigo = dato.Producto
			WHERE dato.pro_id IS NULL;

			-- Un documento INVI por bodega.
			DECLARE @bod_id INT, @enc_id INT, @lineas dbo.inv_documento_interno_type, @motivo VARCHAR(256);
			DECLARE bodegas CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT bod_id FROM @datos;
			OPEN bodegas;
			FETCH NEXT FROM bodegas INTO @bod_id;
			WHILE @@FETCH_STATUS = 0
			BEGIN
				DELETE FROM @lineas;
				INSERT INTO @lineas (bod_id, pro_id, cantidad, costo_total)
				SELECT bod_id, pro_id, Cantidad, CostoTotal FROM @datos WHERE bod_id = @bod_id;
				SET @motivo = CONCAT('Inventario inicial - ', (SELECT bod_descripcion FROM dbo.inv_bodega WHERE bod_id = @bod_id));
				EXEC dbo.paInvDocumentoInternoCrear @TdoCodigo = 'INVI', @Fecha = @Fecha, @Motivo = @motivo, @Lineas = @lineas,
					@UsuId = @UsuId, @EncId = @enc_id OUTPUT;
				FETCH NEXT FROM bodegas INTO @bod_id;
			END
			CLOSE bodegas; DEALLOCATE bodegas;

			-- Precio de venta (con IVA) de cada producto en su bodega: se
			-- actualiza el vigente o se crea uno nuevo.
			DECLARE @mon_id INT = dbo.fn_moneda_local();
			UPDATE prec
			   SET ppr_precio_unitario_venta = dato.PrecioVenta, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
			FROM dbo.inv_producto_precio prec
			INNER JOIN @datos dato ON dato.pro_id = prec.pro_id AND dato.bod_id = prec.bod_id
			WHERE dato.PrecioVenta IS NOT NULL AND prec.mon_id = @mon_id AND prec.ppr_estado = 'A'
			  AND (prec.ppr_vigencia_hasta IS NULL OR prec.ppr_vigencia_hasta >= @Fecha);

			INSERT INTO dbo.inv_producto_precio (ppr_precio_unitario_venta, ppr_descripcion, ppr_vigencia_desde, pro_id, bod_id, mon_id, ppr_estado,
												 InsUsuario, InsFechaHora)
			SELECT dato.PrecioVenta, 'Precio de venta (inventario inicial)', @Fecha, dato.pro_id, dato.bod_id, @mon_id, 'A', @UsuId, SYSDATETIME()
			FROM @datos dato
			WHERE dato.PrecioVenta IS NOT NULL
			  AND NOT EXISTS (SELECT 1 FROM dbo.inv_producto_precio prec
							  WHERE prec.pro_id = dato.pro_id AND prec.bod_id = dato.bod_id AND prec.mon_id = @mon_id AND prec.ppr_estado = 'A'
								AND (prec.ppr_vigencia_hasta IS NULL OR prec.ppr_vigencia_hasta >= @Fecha));

			COMMIT TRANSACTION;
		END TRY
		BEGIN CATCH
			IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
			THROW;
		END CATCH
	END

	SELECT Fila, Tipo, Mensaje FROM @mensajes ORDER BY Fila, Tipo DESC;

	SELECT COUNT(*) AS Filas,
		   @nuevos AS ProductosNuevos,
		   COUNT(DISTINCT bod_id) AS Bodegas,
		   ISNULL(SUM(Cantidad), 0) AS Cantidad,
		   ISNULL(SUM(CostoTotal), 0) AS CostoTotal,
		   CAST(CASE WHEN @SoloValidar = 0 AND NOT EXISTS (SELECT 1 FROM @mensajes WHERE Tipo = 'E') THEN 1 ELSE 0 END AS BIT) AS Grabado
	FROM @datos;
END;
GO

-- Cargas iniciales grabadas (documentos INVI).
CREATE OR ALTER PROCEDURE [dbo].[paInvCargaInicialConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT enca.enc_id AS EncId, enca.enc_fecha_docto AS Fecha, CONCAT(enca.enc_serie_docto, '-', enca.enc_numero_docto) AS Documento,
		   bode.bod_descripcion AS Bodega, sucu.suc_descripcion AS Sucursal, resu.Lineas, resu.Cantidad, enca.enc_monto_total AS Valor,
		   enca.enc_estado AS Estado, usua.usu_usuario AS Usuario, enca.InsFechaHora AS FechaGrabado
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_codigo = 'INVI'
	CROSS APPLY (SELECT COUNT(*) AS Lineas, SUM(deta.det_cantidad) AS Cantidad, MIN(deta.bod_id) AS bod_id
				 FROM dbo.inv_documento_det deta WHERE deta.enc_id = enca.enc_id) resu
	LEFT JOIN dbo.inv_bodega bode ON bode.bod_id = resu.bod_id
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = enca.usu_id_creacion
	ORDER BY enca.enc_id DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paInvCargaInicialAnular]
	@EncId	INT,
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_documento_enc enca
				   INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_codigo = 'INVI'
				   WHERE enca.enc_id = @EncId AND enca.enc_estado = 'G')
		THROW 53510, 'La carga de inventario inicial no existe o ya está anulada.', 1;
	EXEC dbo.sp_documento_anular @enc_id = @EncId, @usu_id = @UsuId;
END;
GO

------------------------------------------------------------
-- 4. Saldos iniciales (partida de apertura)
------------------------------------------------------------
IF TYPE_ID(N'dbo.cont_saldo_inicial_type') IS NULL
CREATE TYPE [dbo].[cont_saldo_inicial_type] AS TABLE
(
	[Fila]		INT				NOT NULL PRIMARY KEY,
	[Codigo]	VARCHAR(20)		NULL,
	[Debe]		DECIMAL(14, 2)	NULL,
	[Haber]		DECIMAL(14, 2)	NULL
);
GO

-- Nomenclatura para exportar a Excel, con los saldos de la partida de
-- apertura vigente (si ya hay una).
CREATE OR ALTER PROCEDURE [dbo].[paContabilidadSaldosInicialesPlantilla]
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @asi_id INT = (SELECT TOP 1 asi_id FROM dbo.cont_asiento_enc WHERE asi_origen = 'APERTURA' AND asi_estado = 'A' ORDER BY asi_id DESC);
	SELECT cuen.cta_id AS CtaId, cuen.cta_codigo AS Codigo, cuen.cta_nombre AS Nombre, cuen.cta_tipo AS Tipo, cuen.cta_naturaleza AS Naturaleza,
		   cuen.cta_nivel AS Nivel, cuen.cta_acepta_movimiento AS AceptaMovimiento,
		   sald.Debe, sald.Haber
	FROM dbo.cont_cuenta_contable cuen
	OUTER APPLY (SELECT NULLIF(SUM(deta.asd_debe), 0) AS Debe, NULLIF(SUM(deta.asd_haber), 0) AS Haber
				 FROM dbo.cont_asiento_det deta WHERE deta.asi_id = @asi_id AND deta.cta_id = cuen.cta_id) sald
	WHERE cuen.cta_estado = 'A'
	ORDER BY cuen.cta_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paContabilidadSaldosInicialesProcesar]
	@Fecha			DATE,
	@Filas			dbo.cont_saldo_inicial_type READONLY,
	@SoloValidar	BIT = 1,
	@Reemplazar		BIT = 0,	-- anula la partida de apertura vigente y graba la nueva
	@UsuId			INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- Las filas sin montos se ignoran (son las cuentas que el contador dejó vacías).
	DECLARE @datos TABLE (Fila INT PRIMARY KEY, Codigo VARCHAR(20), cta_id INT, acepta BIT, estado CHAR(1), naturaleza CHAR(1), nombre VARCHAR(128),
						  Debe DECIMAL(14, 2), Haber DECIMAL(14, 2));
	INSERT INTO @datos
	SELECT fila.Fila, LTRIM(RTRIM(fila.Codigo)), cuen.cta_id, cuen.cta_acepta_movimiento, cuen.cta_estado, cuen.cta_naturaleza, cuen.cta_nombre,
		   ISNULL(fila.Debe, 0), ISNULL(fila.Haber, 0)
	FROM @Filas fila
	LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_codigo = LTRIM(RTRIM(fila.Codigo))
	WHERE ISNULL(fila.Debe, 0) <> 0 OR ISNULL(fila.Haber, 0) <> 0;

	DECLARE @mensajes TABLE (Fila INT, Tipo CHAR(1), Mensaje NVARCHAR(400));
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT Fila, 'E', Mensaje FROM (
		SELECT Fila, CASE
			WHEN cta_id IS NULL THEN CONCAT(N'La cuenta "', Codigo, N'" no existe en la nomenclatura.')
			WHEN estado <> 'A' THEN CONCAT(N'La cuenta ', Codigo, N' está inactiva.')
			WHEN acepta = 0 THEN CONCAT(N'La cuenta ', Codigo, N' es de agrupación: el saldo va en sus cuentas de movimiento.')
			WHEN Debe < 0 OR Haber < 0 THEN CONCAT(N'La cuenta ', Codigo, N' tiene un monto negativo; use la otra columna.')
			WHEN Debe > 0 AND Haber > 0 THEN CONCAT(N'La cuenta ', Codigo, N' tiene Debe y Haber: deje solo su saldo neto.')
		END AS Mensaje FROM @datos) vali
	WHERE Mensaje IS NOT NULL;

	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT dato.Fila, 'E', CONCAT(N'La cuenta ', dato.Codigo, N' se repite en el archivo.')
	FROM @datos dato
	WHERE dato.cta_id IS NOT NULL AND EXISTS (SELECT 1 FROM @datos otro WHERE otro.cta_id = dato.cta_id AND otro.Fila < dato.Fila);

	-- Saldo contrario a la naturaleza de la cuenta: se permite, pero se avisa.
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT Fila, 'A', CONCAT(N'La cuenta ', Codigo, N' ', nombre, N' es de naturaleza ', CASE naturaleza WHEN 'D' THEN N'deudora' ELSE N'acreedora' END,
							 N' y queda con saldo ', CASE WHEN Debe > 0 THEN N'deudor' ELSE N'acreedor' END, N'.')
	FROM @datos
	WHERE cta_id IS NOT NULL AND ((naturaleza = 'D' AND Haber > 0) OR (naturaleza = 'H' AND Debe > 0));

	DECLARE @debe DECIMAL(14, 2) = (SELECT ISNULL(SUM(Debe), 0) FROM @datos),
			@haber DECIMAL(14, 2) = (SELECT ISNULL(SUM(Haber), 0) FROM @datos);
	IF NOT EXISTS (SELECT 1 FROM @datos)
		INSERT INTO @mensajes VALUES (0, 'E', N'El archivo no tiene saldos: llene la columna Debe o Haber de las cuentas de movimiento.');
	ELSE IF @debe <> @haber
		INSERT INTO @mensajes VALUES (0, 'E', CONCAT(N'La partida no cuadra: Debe Q', FORMAT(@debe, 'N2'), N', Haber Q', FORMAT(@haber, 'N2'),
													 N', diferencia Q', FORMAT(ABS(@debe - @haber), 'N2'), N'.'));

	DECLARE @apertura INT = (SELECT TOP 1 asi_id FROM dbo.cont_asiento_enc WHERE asi_origen = 'APERTURA' AND asi_estado = 'A' ORDER BY asi_id DESC);
	IF @apertura IS NOT NULL AND @Reemplazar = 0
		INSERT INTO @mensajes VALUES (0, 'E', N'Ya existe una partida de apertura vigente; marque "Reemplazar" para anularla y grabar la nueva.');
	ELSE IF @apertura IS NOT NULL
		INSERT INTO @mensajes VALUES (0, 'A', CONCAT(N'Se anulará la partida de apertura vigente (#', @apertura, N').'));

	-- La cuenta de inventario contra el inventario inicial cargado.
	DECLARE @cta_inventario INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'INVENTARIO');
	DECLARE @inv_partida DECIMAL(14, 2) = (SELECT ISNULL(SUM(Debe - Haber), 0) FROM @datos WHERE cta_id = @cta_inventario);
	DECLARE @inv_cargado DECIMAL(14, 2) = (SELECT ISNULL(SUM(enca.enc_monto_total), 0) FROM dbo.inv_documento_enc enca
										   INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_codigo = 'INVI'
										   WHERE enca.enc_estado = 'G');
	IF @inv_partida <> @inv_cargado
		INSERT INTO @mensajes VALUES (0, 'A', CONCAT(N'La cuenta de inventario (', (SELECT cta_codigo FROM dbo.cont_cuenta_contable WHERE cta_id = @cta_inventario),
			N') queda en Q', FORMAT(@inv_partida, 'N2'), N' y el inventario inicial cargado vale Q', FORMAT(@inv_cargado, 'N2'),
			N': diferencia Q', FORMAT(ABS(@inv_partida - @inv_cargado), 'N2'), N'.'));

	DECLARE @asi_id INT;
	IF @SoloValidar = 0 AND NOT EXISTS (SELECT 1 FROM @mensajes WHERE Tipo = 'E')
	BEGIN
		DECLARE @partida dbo.cont_asiento_det_type;
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, Debe, Haber, 'Saldo inicial' FROM @datos ORDER BY Codigo;

		BEGIN TRY
			BEGIN TRANSACTION;
			IF @apertura IS NOT NULL
				UPDATE dbo.cont_asiento_enc SET asi_estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE asi_id = @apertura;
			DECLARE @descripcion VARCHAR(256) = CONCAT('Partida de apertura: saldos iniciales al ', FORMAT(@Fecha, 'dd/MM/yyyy'));
			EXEC dbo.sp_contabilidad_insertar_asiento @asi_fecha = @Fecha, @asi_descripcion = @descripcion, @asi_origen = 'APERTURA',
				@usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;
			COMMIT TRANSACTION;
		END TRY
		BEGIN CATCH
			IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
			THROW;
		END CATCH
	END

	SELECT Fila, Tipo, Mensaje FROM @mensajes ORDER BY Fila, Tipo DESC;

	SELECT (SELECT COUNT(*) FROM @datos) AS Cuentas, @debe AS TotalDebe, @haber AS TotalHaber,
		   @inv_partida AS InventarioPartida, @inv_cargado AS InventarioCargado, @asi_id AS AsiId,
		   CAST(CASE WHEN @asi_id IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS Grabado;
END;
GO

-- Partida de apertura vigente (encabezado y líneas).
CREATE OR ALTER PROCEDURE [dbo].[paContabilidadAperturaConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @asi_id INT = (SELECT TOP 1 asi_id FROM dbo.cont_asiento_enc WHERE asi_origen = 'APERTURA' AND asi_estado = 'A' ORDER BY asi_id DESC);
	SELECT asie.asi_id AS AsiId, asie.asi_fecha AS Fecha, asie.asi_descripcion AS Descripcion, usua.usu_usuario AS Usuario,
		   asie.asi_fecha_creacion AS FechaCreacion,
		   (SELECT SUM(asd_debe) FROM dbo.cont_asiento_det WHERE asi_id = asie.asi_id) AS TotalDebe
	FROM dbo.cont_asiento_enc asie
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = asie.usu_id
	WHERE asie.asi_id = @asi_id;

	SELECT cuen.cta_codigo AS Codigo, cuen.cta_nombre AS Nombre, deta.asd_debe AS Debe, deta.asd_haber AS Haber
	FROM dbo.cont_asiento_det deta
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = deta.cta_id
	WHERE deta.asi_id = @asi_id
	ORDER BY cuen.cta_codigo;
END;
GO

------------------------------------------------------------
-- 5. Carga de empleados
------------------------------------------------------------
IF TYPE_ID(N'dbo.rrhh_empleado_carga_type') IS NULL
CREATE TYPE [dbo].[rrhh_empleado_carga_type] AS TABLE
(
	[Fila]				INT				NOT NULL PRIMARY KEY,
	[Codigo]			VARCHAR(16)		NULL,
	[PrimerNombre]		VARCHAR(50)		NULL,
	[SegundoNombre]		VARCHAR(50)		NULL,
	[PrimerApellido]	VARCHAR(50)		NULL,
	[SegundoApellido]	VARCHAR(50)		NULL,
	[Genero]			CHAR(1)			NULL,
	[FechaNacimiento]	DATE			NULL,
	[FechaIngreso]		DATE			NULL,
	[TipoDocumento]		VARCHAR(50)		NULL,	-- descripción del catálogo (DPI, Pasaporte)
	[NumeroDocumento]	VARCHAR(32)		NULL,
	[AfiliacionIGSS]	VARCHAR(20)		NULL,
	[Nit]				VARCHAR(20)		NULL,
	[Email]				VARCHAR(100)	NULL,
	[Direccion]			VARCHAR(200)	NULL,
	[Plaza]				VARCHAR(100)	NULL,	-- descripción de la plaza
	[SalarioBase]		NUMERIC(12, 2)	NULL,
	[TipoNomina]		CHAR(1)			NULL,	-- S, Q o M
	[FormaPago]			CHAR(1)			NULL,	-- T o C
	[Banco]				VARCHAR(16)		NULL,	-- código de la entidad financiera
	[TipoCuenta]		CHAR(1)			NULL,	-- M o A
	[NumeroCuenta]		VARCHAR(30)		NULL
);
GO

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

------------------------------------------------------------
-- 6. Tableros sin documentos internos
------------------------------------------------------------
-- Iguales que en 35, sin contar los documentos internos (inventario inicial y
-- ajustes) como ventas o compras.
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
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id AND tipo.tdo_naturaleza = '-' AND tipo.tdo_es_nota = 0 AND tipo.tdo_es_interno = 0
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
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id AND tipo.tdo_naturaleza = '+' AND tipo.tdo_es_nota = 0 AND tipo.tdo_es_interno = 0
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
-- 7. Permisos (administrador y contador)
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT v.modulo, v.codigo, v.descripcion
FROM (VALUES
	('INVENTARIO',   'INVENTARIO_FISICO',             'Inventario físico: tomas por bodega y ajustes'),
	('INVENTARIO',   'INVENTARIO_CARGA_INICIAL',      'Carga del inventario inicial desde Excel'),
	('CONTABILIDAD', 'CONTABILIDAD_SALDOS_INICIALES', 'Saldos iniciales: exportar la nomenclatura y cargar la partida de apertura')
) v(modulo, codigo, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso perm WHERE perm.per_codigo = v.codigo);

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id, InsFechaHora)
SELECT rol.rol_id, perm.per_id, SYSDATETIME()
FROM dbo.sec_rol rol
INNER JOIN (VALUES ('ADMIN', 'INVENTARIO_FISICO'), ('CONTADOR', 'INVENTARIO_FISICO'),
				   ('ADMIN', 'INVENTARIO_CARGA_INICIAL'), ('CONTADOR', 'INVENTARIO_CARGA_INICIAL'),
				   ('ADMIN', 'CONTABILIDAD_SALDOS_INICIALES'), ('CONTADOR', 'CONTABILIDAD_SALDOS_INICIALES')) v(rol, permiso) ON v.rol = rol.rol_codigo
INNER JOIN dbo.sec_permiso perm ON perm.per_codigo = v.permiso
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO
