/*
================================================================================
 45_traslados_bodegas.sql
 Traslados de inventario entre bodegas de la misma sucursal o de otra.

   Envío (bodega origen): documento "Salida por traslado" (TRS) al costo
   promedio; la mercadería queda EN TRÁNSITO, fuera de las dos bodegas.
     Póliza: Debe Inventario en tránsito / Haber Inventario.
   Recepción (bodega destino, usuario asignado a esa sucursal): se confirma
   la cantidad recibida de cada línea; lo recibido entra con un "Ingreso por
   traslado" (TRE) al mismo costo.
     Póliza: Debe Inventario / Haber Inventario en tránsito.
   Diferencias (lo que no llegó), según decida quien recibe:
     D = se devuelve a la bodega origen (TRE en origen, misma póliza), o
     P = pérdida: Debe Faltantes de inventario / Haber Inventario en tránsito.
   Rechazo (destino) o cancelación (origen) antes de recibir: todo vuelve a la
   bodega origen.

   Estados: E enviado (en tránsito), R recibido completo, P recibido con
   diferencias, X rechazado por el destino, N cancelado por el origen.

 Crea la cuenta INVENTARIO EN TRÁNSITO junto a la de inventario y el
 concepto INVENTARIO_TRANSITO. Los documentos TRS/TRE son internos (no son
 ventas ni compras). El costo promedio no cambia: sale y entra al mismo costo.

 Requiere 38 y 44 (permisos). Errores 53901-53914. Se puede volver a correr.
================================================================================
*/
USE [erp_db];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Tipos de documento, origen de póliza y cuenta en tránsito
------------------------------------------------------------
INSERT INTO dbo.inv_documento_tipo (tdo_codigo, tdo_descripcion, tdo_naturaleza, afecta_costo, tdo_es_nota, tdo_es_interno, tdo_fel_certifica)
SELECT v.c, v.d, v.n, 'S', 0, 1, 0
FROM (VALUES ('TRS', 'Salida por traslado', '-'),
			 ('TRE', 'Ingreso por traslado', '+')) v(c, d, n)
WHERE NOT EXISTS (SELECT 1 FROM dbo.inv_documento_tipo tipo WHERE tipo.tdo_codigo = v.c);
GO

-- La lista es la misma en todos los scripts que la tocan (36, 38, 45, 58);
-- si ya tiene el último origen agregado no se vuelve a crear, así correr de
-- nuevo un script anterior no la deja sin los orígenes nuevos.
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_cont_asiento_enc_origen' AND definition LIKE '%CONCILIACION%')
BEGIN
	IF OBJECT_ID('dbo.CK_cont_asiento_enc_origen', 'C') IS NOT NULL
		ALTER TABLE dbo.cont_asiento_enc DROP CONSTRAINT [CK_cont_asiento_enc_origen];
	ALTER TABLE dbo.cont_asiento_enc ADD CONSTRAINT [CK_cont_asiento_enc_origen]
		CHECK ([asi_origen] IN ('MANUAL','VENTA','COMPRA','PAGO_CLIENTE','PAGO_PROVEEDOR','DEPOSITO','CIERRE_CAJA','NOMINA',
								'NOTA_CREDITO','NOTA_DEBITO',		-- 32
								'CHEQUE','PAGO_NOMINA',				-- 36
								'AJUSTE_INVENTARIO','APERTURA',		-- 38
								'TRASLADO',							-- 45
								'PAGO_TRANSFERENCIA',				-- 58
								'CAJA_CHICA','DEPRECIACION','ACTIVO_FIJO','CIERRE_ANUAL',
								'CONCILIACION'));	-- 60 en adelante
END
GO

-- Cuenta hermana de la de inventario (mismo padre), si no existe.
DECLARE @inventario INT, @padre INT, @codigo VARCHAR(20), @cta INT;
EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO', @CtaId = @inventario OUTPUT;
SET @padre = (SELECT cta_id_padre FROM dbo.cont_cuenta_contable WHERE cta_id = @inventario);
IF @padre IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_nombre = 'INVENTARIO EN TRANSITO')
BEGIN
	EXEC dbo.paCuentaContableSiguienteCodigo @IdPadre = @padre, @Codigo = @codigo OUTPUT;
	EXEC dbo.paCuentaContableNodoGuardar @IdPadre = @padre, @Codigo = @codigo, @Nombre = 'INVENTARIO EN TRANSITO',
		@Tipo = 'A', @Naturaleza = 'D', @IdResultado = @cta OUTPUT;
END

INSERT INTO dbo.cont_cuenta_parametro (ccp_codigo, ccp_descripcion, ccp_naturaleza, cta_id)
SELECT 'INVENTARIO_TRANSITO', 'Traslados: mercadería en tránsito entre bodegas', 'D',
	   (SELECT TOP 1 cta_id FROM dbo.cont_cuenta_contable WHERE cta_nombre = 'INVENTARIO EN TRANSITO' AND cta_acepta_movimiento = 1)
WHERE NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'INVENTARIO_TRANSITO');
GO

------------------------------------------------------------
-- 2. Tablas
------------------------------------------------------------
IF OBJECT_ID('dbo.inv_traslado', 'U') IS NULL
CREATE TABLE [dbo].[inv_traslado](
	[tra_id]				INT				IDENTITY(1, 1) NOT NULL,
	[tra_numero]			VARCHAR(16)		NOT NULL,
	[tra_fecha]				DATE			NOT NULL,
	[bod_id_origen]			INT				NOT NULL,
	[bod_id_destino]		INT				NOT NULL,
	[tra_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_inv_traslado_estado] DEFAULT ('E'),
	[tra_observaciones]		VARCHAR(256)	NULL,
	[tra_valor]				NUMERIC(14, 2)	NOT NULL CONSTRAINT [DF_inv_traslado_valor] DEFAULT (0),
	[usu_id_envia]			INT				NULL,
	[usu_id_recibe]			INT				NULL,
	[tra_fecha_recepcion]	DATETIME2(0)	NULL,
	[tra_nota_recepcion]	VARCHAR(256)	NULL,
	[tra_diferencia]		CHAR(1)			NULL,	-- D devuelto a origen, P pérdida
	[enc_id_salida]			INT				NULL,
	[enc_id_ingreso]		INT				NULL,
	[enc_id_devolucion]		INT				NULL,
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NULL,
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_traslado] PRIMARY KEY ([tra_id]),
	CONSTRAINT [UQ_inv_traslado_numero] UNIQUE ([tra_numero]),
	CONSTRAINT [FK_inv_traslado_origen] FOREIGN KEY ([bod_id_origen]) REFERENCES dbo.inv_bodega ([bod_id]),
	CONSTRAINT [FK_inv_traslado_destino] FOREIGN KEY ([bod_id_destino]) REFERENCES dbo.inv_bodega ([bod_id]),
	CONSTRAINT [FK_inv_traslado_salida] FOREIGN KEY ([enc_id_salida]) REFERENCES dbo.inv_documento_enc ([enc_id]),
	CONSTRAINT [FK_inv_traslado_ingreso] FOREIGN KEY ([enc_id_ingreso]) REFERENCES dbo.inv_documento_enc ([enc_id]),
	CONSTRAINT [FK_inv_traslado_devolucion] FOREIGN KEY ([enc_id_devolucion]) REFERENCES dbo.inv_documento_enc ([enc_id]),
	CONSTRAINT [FK_inv_traslado_usu_envia] FOREIGN KEY ([usu_id_envia]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_inv_traslado_usu_recibe] FOREIGN KEY ([usu_id_recibe]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [CK_inv_traslado_estado] CHECK ([tra_estado] IN ('E','R','P','X','N')),
	CONSTRAINT [CK_inv_traslado_diferencia] CHECK ([tra_diferencia] IS NULL OR [tra_diferencia] IN ('D','P')),
	CONSTRAINT [CK_inv_traslado_bodegas] CHECK ([bod_id_origen] <> [bod_id_destino])
);
GO

IF OBJECT_ID('dbo.inv_traslado_det', 'U') IS NULL
CREATE TABLE [dbo].[inv_traslado_det](
	[trd_id]				INT				IDENTITY(1, 1) NOT NULL,
	[tra_id]				INT				NOT NULL,
	[pro_id]				INT				NOT NULL,
	[trd_cantidad]			NUMERIC(12, 4)	NOT NULL,
	[trd_costo_unitario]	NUMERIC(14, 4)	NOT NULL CONSTRAINT [DF_inv_traslado_det_costo] DEFAULT (0),
	[trd_cantidad_recibida]	NUMERIC(12, 4)	NULL,
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NULL,
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_traslado_det] PRIMARY KEY ([trd_id]),
	CONSTRAINT [UQ_inv_traslado_det_producto] UNIQUE ([tra_id], [pro_id]),
	CONSTRAINT [FK_inv_traslado_det_traslado] FOREIGN KEY ([tra_id]) REFERENCES dbo.inv_traslado ([tra_id]),
	CONSTRAINT [FK_inv_traslado_det_producto] FOREIGN KEY ([pro_id]) REFERENCES dbo.inv_producto ([pro_id]),
	CONSTRAINT [CK_inv_traslado_det_cantidades] CHECK ([trd_cantidad] > 0
		AND ([trd_cantidad_recibida] IS NULL OR [trd_cantidad_recibida] BETWEEN 0 AND [trd_cantidad]))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_inv_traslado_estado' AND object_id = OBJECT_ID('dbo.inv_traslado'))
	CREATE INDEX [IX_inv_traslado_estado] ON dbo.inv_traslado ([tra_estado], [bod_id_destino]) INCLUDE ([bod_id_origen], [tra_fecha]);
GO

IF TYPE_ID(N'dbo.inv_traslado_linea_type') IS NULL
CREATE TYPE [dbo].[inv_traslado_linea_type] AS TABLE
(
	[pro_id]	INT				NOT NULL PRIMARY KEY,
	[cantidad]	NUMERIC(12, 4)	NOT NULL		-- en el envío: lo enviado; en la recepción: lo recibido
);
GO

------------------------------------------------------------
-- 3. Procedimientos
------------------------------------------------------------
-- Póliza de un movimiento del traslado (interna).
CREATE OR ALTER PROCEDURE [dbo].[paInvTrasladoPoliza]
	@TraId		INT,
	@Fecha		DATE,
	@Valor		NUMERIC(14, 2),
	@CtaDebe	INT,
	@CtaHaber	INT,
	@Texto		VARCHAR(256),
	@EncId		INT,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(@Valor, 0) <= 0
		RETURN;
	DECLARE @partida dbo.cont_asiento_det_type, @asi_id INT;
	INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
	VALUES (@CtaDebe, @Valor, 0, @Texto), (@CtaHaber, 0, @Valor, @Texto);
	EXEC dbo.sp_contabilidad_insertar_asiento @asi_fecha = @Fecha, @asi_descripcion = @Texto, @asi_origen = 'TRASLADO',
		@asi_origen_id = @TraId, @enc_id = @EncId, @usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;
END;
GO

-- Productos con existencia en una bodega (para armar el envío).
CREATE OR ALTER PROCEDURE [dbo].[paInvTrasladoProductosConsultar]
	@BodId	INT,
	@Texto	VARCHAR(64) = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT TOP 30 prod.pro_id AS ProId, prod.pro_codigo AS Codigo, prod.pro_descripcion AS Descripcion,
		   exis.existencia AS Existencia, prod.pro_costo_unitario AS CostoUnitario, unid.ume_codigo AS Unidad
	FROM dbo.inv_producto_existencia_bodega exis
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = exis.pro_id AND prod.pro_estado = 'A' AND prod.pro_maneja_existencia = 1
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = prod.ume_id
	WHERE exis.bod_id = @BodId AND exis.existencia > 0
	  AND (@Texto IS NULL OR prod.pro_codigo = @Texto OR prod.pro_codigo LIKE @Texto + '%' OR prod.pro_descripcion LIKE '%' + @Texto + '%')
	ORDER BY CASE WHEN prod.pro_codigo = @Texto THEN 0 ELSE 1 END, prod.pro_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paInvTrasladoEnviar]
	@BodIdOrigen	INT,
	@BodIdDestino	INT,
	@Fecha			DATE = NULL,
	@Observaciones	VARCHAR(256) = NULL,
	@Lineas			dbo.inv_traslado_linea_type READONLY,
	@UsuId			INT,
	@TraId			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));

	IF @BodIdOrigen = @BodIdDestino
		THROW 53901, 'La bodega destino debe ser distinta de la de origen.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE bod_id = @BodIdOrigen AND bod_estado = 'A')
	   OR NOT EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE bod_id = @BodIdDestino AND bod_estado = 'A')
		THROW 53902, 'La bodega de origen o de destino no existe o está inactiva.', 1;
	IF NOT EXISTS (SELECT 1 FROM @Lineas WHERE cantidad > 0)
		THROW 53903, 'Agregue al menos un producto con cantidad mayor a cero.', 1;
	IF EXISTS (SELECT 1 FROM @Lineas WHERE cantidad <= 0)
		THROW 53904, 'Las cantidades a trasladar deben ser mayores a cero.', 1;
	IF EXISTS (SELECT 1 FROM @Lineas lins LEFT JOIN dbo.inv_producto prod ON prod.pro_id = lins.pro_id
			   WHERE prod.pro_id IS NULL OR prod.pro_maneja_existencia = 0)
		THROW 53905, 'Solo se trasladan productos que manejan existencia.', 1;

	DECLARE @cta_inventario INT, @cta_transito INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO', @CtaId = @cta_inventario OUTPUT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO_TRANSITO', @CtaId = @cta_transito OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		-- Existencia suficiente en la bodega origen (bloqueada mientras se envía).
		DECLARE @falta NVARCHAR(300);
		SELECT TOP 1 @falta = CONCAT(N'No hay existencia suficiente de ', prod.pro_codigo, N' en la bodega origen: hay ',
									 FORMAT(ISNULL(exis.existencia, 0), 'N2'), N' y se quieren enviar ', FORMAT(lins.cantidad, 'N2'), N'.')
		FROM @Lineas lins
		INNER JOIN dbo.inv_producto prod ON prod.pro_id = lins.pro_id
		LEFT JOIN dbo.inv_producto_existencia_bodega exis WITH (UPDLOCK, HOLDLOCK) ON exis.pro_id = lins.pro_id AND exis.bod_id = @BodIdOrigen
		WHERE lins.cantidad > ISNULL(exis.existencia, 0)
		ORDER BY prod.pro_codigo;
		IF @falta IS NOT NULL
			THROW 53906, @falta, 1;

		DECLARE @siguiente INT = ISNULL((SELECT MAX(tra_id) FROM dbo.inv_traslado WITH (UPDLOCK, HOLDLOCK)), 0) + 1;
		INSERT INTO dbo.inv_traslado (tra_numero, tra_fecha, bod_id_origen, bod_id_destino, tra_estado, tra_observaciones, usu_id_envia, InsUsuario, InsFechaHora)
		VALUES (CONCAT('TR-', RIGHT(CONCAT('000000', @siguiente), 6)), @Fecha, @BodIdOrigen, @BodIdDestino, 'E',
				NULLIF(LTRIM(RTRIM(@Observaciones)), ''), @UsuId, @UsuId, SYSDATETIME());
		SET @TraId = SCOPE_IDENTITY();

		-- Salida al costo promedio del momento.
		DECLARE @salida dbo.inv_documento_interno_type, @enc_salida INT, @numero VARCHAR(16), @destino VARCHAR(128);
		SELECT @numero = tra_numero FROM dbo.inv_traslado WHERE tra_id = @TraId;
		SELECT @destino = bod_descripcion FROM dbo.inv_bodega WHERE bod_id = @BodIdDestino;
		INSERT INTO @salida (bod_id, pro_id, cantidad, costo_total)
		SELECT @BodIdOrigen, lins.pro_id, lins.cantidad, ROUND(lins.cantidad * prod.pro_costo_unitario, 2)
		FROM @Lineas lins INNER JOIN dbo.inv_producto prod ON prod.pro_id = lins.pro_id;
		DECLARE @motivo VARCHAR(256) = CONCAT('Traslado ', @numero, ' a ', @destino);
		EXEC dbo.paInvDocumentoInternoCrear @TdoCodigo = 'TRS', @Fecha = @Fecha, @Motivo = @motivo, @Lineas = @salida,
			@UsuId = @UsuId, @EncId = @enc_salida OUTPUT;

		INSERT INTO dbo.inv_traslado_det (tra_id, pro_id, trd_cantidad, trd_costo_unitario, InsUsuario, InsFechaHora)
		SELECT @TraId, deta.pro_id, deta.det_cantidad, deta.det_costo_unitario, @UsuId, SYSDATETIME()
		FROM dbo.inv_documento_det deta WHERE deta.enc_id = @enc_salida;

		DECLARE @valor NUMERIC(14, 2) = (SELECT enc_monto_total FROM dbo.inv_documento_enc WHERE enc_id = @enc_salida);
		UPDATE dbo.inv_traslado SET enc_id_salida = @enc_salida, tra_valor = @valor WHERE tra_id = @TraId;

		SET @motivo = CONCAT('Traslado ', @numero, ': envío a ', @destino, ' (en tránsito)');
		EXEC dbo.paInvTrasladoPoliza @TraId = @TraId, @Fecha = @Fecha, @Valor = @valor, @CtaDebe = @cta_transito, @CtaHaber = @cta_inventario,
			@Texto = @motivo, @EncId = @enc_salida, @UsuId = @UsuId;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Ingreso interno (TRE) en una bodega a partir del detalle del traslado.
CREATE OR ALTER PROCEDURE [dbo].[paInvTrasladoIngresar]
	@TraId		INT,
	@BodId		INT,
	@Fecha		DATE,
	@Lineas		dbo.inv_traslado_linea_type READONLY,		-- cantidad que entra a la bodega
	@Motivo		VARCHAR(256),
	@UsuId		INT,
	@EncId		INT OUTPUT,
	@Valor		NUMERIC(14, 2) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET @EncId = NULL; SET @Valor = 0;
	DECLARE @ingreso dbo.inv_documento_interno_type;
	INSERT INTO @ingreso (bod_id, pro_id, cantidad, costo_total)
	SELECT @BodId, lins.pro_id, lins.cantidad, ROUND(lins.cantidad * deta.trd_costo_unitario, 2)
	FROM @Lineas lins INNER JOIN dbo.inv_traslado_det deta ON deta.tra_id = @TraId AND deta.pro_id = lins.pro_id
	WHERE lins.cantidad > 0;
	IF NOT EXISTS (SELECT 1 FROM @ingreso)
		RETURN;
	EXEC dbo.paInvDocumentoInternoCrear @TdoCodigo = 'TRE', @Fecha = @Fecha, @Motivo = @Motivo, @Lineas = @ingreso,
		@UsuId = @UsuId, @EncId = @EncId OUTPUT;
	SET @Valor = (SELECT enc_monto_total FROM dbo.inv_documento_enc WHERE enc_id = @EncId);
END;
GO

-- Recepción en la bodega destino. @Diferencia: D devolver lo que no llegó a
-- origen, P registrarlo como pérdida.
CREATE OR ALTER PROCEDURE [dbo].[paInvTrasladoRecibir]
	@TraId		INT,
	@Lineas		dbo.inv_traslado_linea_type READONLY,	-- cantidad recibida por producto
	@Diferencia	CHAR(1) = 'D',
	@Nota		VARCHAR(256) = NULL,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado CHAR(1), @origen INT, @destino INT, @numero VARCHAR(16), @suc_destino INT, @bod_origen VARCHAR(128), @bod_destino VARCHAR(128);
	SELECT @estado = tras.tra_estado, @origen = tras.bod_id_origen, @destino = tras.bod_id_destino, @numero = tras.tra_numero,
		   @suc_destino = bdes.suc_id, @bod_origen = bori.bod_descripcion, @bod_destino = bdes.bod_descripcion
	FROM dbo.inv_traslado tras
	INNER JOIN dbo.inv_bodega bori ON bori.bod_id = tras.bod_id_origen
	INNER JOIN dbo.inv_bodega bdes ON bdes.bod_id = tras.bod_id_destino
	WHERE tras.tra_id = @TraId;
	IF @estado IS NULL
		THROW 53907, 'El traslado no existe.', 1;
	IF @estado <> 'E'
		THROW 53908, 'Solo se recibe un traslado enviado (en tránsito).', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.sec_usuario_sucursal WHERE usu_id = @UsuId AND suc_id = @suc_destino)
		THROW 53909, 'Solo recibe un usuario asignado a la sucursal de la bodega destino.', 1;
	IF ISNULL(@Diferencia, '') NOT IN ('D', 'P')
		THROW 53910, 'Indique qué hacer con lo que no llegó: devolverlo a origen (D) o registrarlo como pérdida (P).', 1;
	IF EXISTS (SELECT 1 FROM @Lineas lins LEFT JOIN dbo.inv_traslado_det deta ON deta.tra_id = @TraId AND deta.pro_id = lins.pro_id
			   WHERE deta.trd_id IS NULL OR lins.cantidad < 0 OR lins.cantidad > deta.trd_cantidad)
		THROW 53911, 'Cada cantidad recibida debe estar entre cero y lo enviado.', 1;

	DECLARE @cta_inventario INT, @cta_transito INT, @cta_faltante INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO', @CtaId = @cta_inventario OUTPUT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO_TRANSITO', @CtaId = @cta_transito OUTPUT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO_FALTANTE', @CtaId = @cta_faltante OUTPUT;

	DECLARE @hoy DATE = CAST(GETDATE() AS DATE);

	BEGIN TRY
		BEGIN TRANSACTION;

		-- Líneas sin cantidad indicada: se reciben completas.
		DECLARE @recibido dbo.inv_traslado_linea_type, @faltante dbo.inv_traslado_linea_type;
		INSERT INTO @recibido (pro_id, cantidad)
		SELECT deta.pro_id, ISNULL(lins.cantidad, deta.trd_cantidad)
		FROM dbo.inv_traslado_det deta WITH (UPDLOCK)
		LEFT JOIN @Lineas lins ON lins.pro_id = deta.pro_id
		WHERE deta.tra_id = @TraId;
		INSERT INTO @faltante (pro_id, cantidad)
		SELECT deta.pro_id, deta.trd_cantidad - reci.cantidad
		FROM dbo.inv_traslado_det deta INNER JOIN @recibido reci ON reci.pro_id = deta.pro_id
		WHERE deta.tra_id = @TraId AND deta.trd_cantidad > reci.cantidad;

		UPDATE deta SET trd_cantidad_recibida = reci.cantidad, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		FROM dbo.inv_traslado_det deta INNER JOIN @recibido reci ON reci.pro_id = deta.pro_id
		WHERE deta.tra_id = @TraId;

		DECLARE @enc_ingreso INT, @enc_devolucion INT, @valor NUMERIC(14, 2), @texto VARCHAR(256);
		SET @texto = CONCAT('Traslado ', @numero, ' desde ', @bod_origen);
		EXEC dbo.paInvTrasladoIngresar @TraId = @TraId, @BodId = @destino, @Fecha = @hoy, @Lineas = @recibido, @Motivo = @texto,
			@UsuId = @UsuId, @EncId = @enc_ingreso OUTPUT, @Valor = @valor OUTPUT;
		SET @texto = CONCAT('Traslado ', @numero, ': recibido en ', @bod_destino);
		EXEC dbo.paInvTrasladoPoliza @TraId = @TraId, @Fecha = @hoy, @Valor = @valor, @CtaDebe = @cta_inventario, @CtaHaber = @cta_transito,
			@Texto = @texto, @EncId = @enc_ingreso, @UsuId = @UsuId;

		IF EXISTS (SELECT 1 FROM @faltante)
		BEGIN
			IF @Diferencia = 'D'
			BEGIN
				SET @texto = CONCAT('Traslado ', @numero, ': devolución de lo no recibido');
				EXEC dbo.paInvTrasladoIngresar @TraId = @TraId, @BodId = @origen, @Fecha = @hoy, @Lineas = @faltante, @Motivo = @texto,
					@UsuId = @UsuId, @EncId = @enc_devolucion OUTPUT, @Valor = @valor OUTPUT;
				EXEC dbo.paInvTrasladoPoliza @TraId = @TraId, @Fecha = @hoy, @Valor = @valor, @CtaDebe = @cta_inventario, @CtaHaber = @cta_transito,
					@Texto = @texto, @EncId = @enc_devolucion, @UsuId = @UsuId;
			END
			ELSE
			BEGIN
				SET @valor = (SELECT ROUND(SUM(falt.cantidad * deta.trd_costo_unitario), 2)
							  FROM @faltante falt INNER JOIN dbo.inv_traslado_det deta ON deta.tra_id = @TraId AND deta.pro_id = falt.pro_id);
				SET @texto = CONCAT('Traslado ', @numero, ': pérdida en tránsito');
				EXEC dbo.paInvTrasladoPoliza @TraId = @TraId, @Fecha = @hoy, @Valor = @valor, @CtaDebe = @cta_faltante, @CtaHaber = @cta_transito,
					@Texto = @texto, @EncId = NULL, @UsuId = @UsuId;
			END
		END

		UPDATE dbo.inv_traslado
		   SET tra_estado = CASE WHEN EXISTS (SELECT 1 FROM @faltante) THEN 'P' ELSE 'R' END,
			   tra_diferencia = CASE WHEN EXISTS (SELECT 1 FROM @faltante) THEN @Diferencia END,
			   usu_id_recibe = @UsuId, tra_fecha_recepcion = SYSDATETIME(), tra_nota_recepcion = NULLIF(LTRIM(RTRIM(@Nota)), ''),
			   enc_id_ingreso = @enc_ingreso, enc_id_devolucion = @enc_devolucion, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE tra_id = @TraId;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Rechazo (destino) o cancelación (origen) de un traslado en tránsito: todo
-- vuelve a la bodega origen.
CREATE OR ALTER PROCEDURE [dbo].[paInvTrasladoDevolver]
	@TraId			INT,
	@Motivo			VARCHAR(256),
	@EsCancelacion	BIT,		-- 1 = lo cancela el origen, 0 = lo rechaza el destino
	@UsuId			INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado CHAR(1), @origen INT, @numero VARCHAR(16), @suc INT;
	SELECT @estado = tras.tra_estado, @origen = tras.bod_id_origen, @numero = tras.tra_numero,
		   @suc = CASE WHEN @EsCancelacion = 1 THEN bori.suc_id ELSE bdes.suc_id END
	FROM dbo.inv_traslado tras
	INNER JOIN dbo.inv_bodega bori ON bori.bod_id = tras.bod_id_origen
	INNER JOIN dbo.inv_bodega bdes ON bdes.bod_id = tras.bod_id_destino
	WHERE tras.tra_id = @TraId;
	IF @estado IS NULL
		THROW 53907, 'El traslado no existe.', 1;
	IF @estado <> 'E'
		THROW 53912, 'Solo se rechaza o cancela un traslado en tránsito.', 1;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 53913, 'Indique el motivo (al menos 5 caracteres).', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.sec_usuario_sucursal WHERE usu_id = @UsuId AND suc_id = @suc)
		THROW 53914, 'Solo cancela un usuario de la sucursal origen y solo rechaza uno de la sucursal destino.', 1;

	DECLARE @cta_inventario INT, @cta_transito INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO', @CtaId = @cta_inventario OUTPUT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO_TRANSITO', @CtaId = @cta_transito OUTPUT;
	DECLARE @hoy DATE = CAST(GETDATE() AS DATE);

	BEGIN TRY
		BEGIN TRANSACTION;
		DECLARE @todo dbo.inv_traslado_linea_type, @enc_devolucion INT, @valor NUMERIC(14, 2);
		INSERT INTO @todo (pro_id, cantidad) SELECT pro_id, trd_cantidad FROM dbo.inv_traslado_det WITH (UPDLOCK) WHERE tra_id = @TraId;
		DECLARE @texto VARCHAR(256) = CONCAT('Traslado ', @numero, CASE WHEN @EsCancelacion = 1 THEN ' cancelado: ' ELSE ' rechazado: ' END,
											 LEFT(LTRIM(RTRIM(@Motivo)), 180));
		EXEC dbo.paInvTrasladoIngresar @TraId = @TraId, @BodId = @origen, @Fecha = @hoy, @Lineas = @todo, @Motivo = @texto,
			@UsuId = @UsuId, @EncId = @enc_devolucion OUTPUT, @Valor = @valor OUTPUT;
		EXEC dbo.paInvTrasladoPoliza @TraId = @TraId, @Fecha = @hoy, @Valor = @valor, @CtaDebe = @cta_inventario, @CtaHaber = @cta_transito,
			@Texto = @texto, @EncId = @enc_devolucion, @UsuId = @UsuId;

		UPDATE dbo.inv_traslado_det SET trd_cantidad_recibida = 0, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE tra_id = @TraId;
		UPDATE dbo.inv_traslado
		   SET tra_estado = CASE WHEN @EsCancelacion = 1 THEN 'N' ELSE 'X' END, usu_id_recibe = @UsuId, tra_fecha_recepcion = SYSDATETIME(),
			   tra_nota_recepcion = LEFT(LTRIM(RTRIM(@Motivo)), 256), enc_id_devolucion = @enc_devolucion,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE tra_id = @TraId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Traslados de una sucursal (enviados desde o hacia sus bodegas).
CREATE OR ALTER PROCEDURE [dbo].[paInvTrasladoConsultar]
	@SucId	INT = NULL,
	@Estado	CHAR(1) = NULL,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT tras.tra_id AS TraId, tras.tra_numero AS Numero, tras.tra_fecha AS Fecha, tras.tra_estado AS Estado,
		   tras.bod_id_origen AS BodIdOrigen, CONCAT(bori.bod_codigo, ' · ', bori.bod_descripcion) AS BodegaOrigen, sori.suc_id AS SucIdOrigen, sori.suc_descripcion AS SucursalOrigen,
		   tras.bod_id_destino AS BodIdDestino, CONCAT(bdes.bod_codigo, ' · ', bdes.bod_descripcion) AS BodegaDestino, sdes.suc_id AS SucIdDestino, sdes.suc_descripcion AS SucursalDestino,
		   tras.tra_valor AS Valor, tras.tra_observaciones AS Observaciones, uenv.usu_usuario AS Envia, urec.usu_usuario AS Recibe,
		   tras.tra_fecha_recepcion AS FechaRecepcion, tras.tra_nota_recepcion AS NotaRecepcion, tras.tra_diferencia AS Diferencia,
		   (SELECT COUNT(*) FROM dbo.inv_traslado_det deta WHERE deta.tra_id = tras.tra_id) AS Lineas,
		   (SELECT SUM(deta.trd_cantidad) FROM dbo.inv_traslado_det deta WHERE deta.tra_id = tras.tra_id) AS Unidades
	FROM dbo.inv_traslado tras
	INNER JOIN dbo.inv_bodega bori ON bori.bod_id = tras.bod_id_origen
	INNER JOIN dbo.gen_sucursal sori ON sori.suc_id = bori.suc_id
	INNER JOIN dbo.inv_bodega bdes ON bdes.bod_id = tras.bod_id_destino
	INNER JOIN dbo.gen_sucursal sdes ON sdes.suc_id = bdes.suc_id
	LEFT JOIN dbo.gen_usuario uenv ON uenv.usu_id = tras.usu_id_envia
	LEFT JOIN dbo.gen_usuario urec ON urec.usu_id = tras.usu_id_recibe
	WHERE (@SucId IS NULL OR sori.suc_id = @SucId OR sdes.suc_id = @SucId)
	  AND (@Estado IS NULL OR tras.tra_estado = @Estado)
	  AND (@Desde IS NULL OR tras.tra_fecha >= @Desde)
	  AND (@Hasta IS NULL OR tras.tra_fecha <= @Hasta)
	ORDER BY CASE tras.tra_estado WHEN 'E' THEN 0 ELSE 1 END, tras.tra_id DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paInvTrasladoDetalleConsultar]
	@TraId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT deta.trd_id AS TrdId, deta.pro_id AS ProId, prod.pro_codigo AS Codigo, prod.pro_descripcion AS Descripcion,
		   unid.ume_codigo AS Unidad, deta.trd_cantidad AS Cantidad, deta.trd_costo_unitario AS CostoUnitario,
		   ROUND(deta.trd_cantidad * deta.trd_costo_unitario, 2) AS Valor, deta.trd_cantidad_recibida AS CantidadRecibida
	FROM dbo.inv_traslado_det deta
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = prod.ume_id
	WHERE deta.tra_id = @TraId
	ORDER BY prod.pro_codigo;
END;
GO

-- Mercadería en tránsito (valor total), para el tablero y la conciliación con
-- la cuenta INVENTARIO EN TRANSITO.
CREATE OR ALTER PROCEDURE [dbo].[paInvTransitoConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT COUNT(*) AS Traslados, ISNULL(SUM(tra_valor), 0) AS Valor FROM dbo.inv_traslado WHERE tra_estado = 'E';
END;
GO

PRINT '45_traslados_bodegas.sql aplicado.';
GO
