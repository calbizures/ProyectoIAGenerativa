/*
================================================================================
 64_conciliacion_bancaria.sql
 Conciliación bancaria mensual con el estado de cuenta del banco.

   - Una conciliación por cuenta bancaria y mes, en orden: saldo inicial y
     final según el banco y las líneas del estado de cuenta (se importan desde
     Excel o CSV en la aplicación: fecha, descripción, referencia, débito y
     crédito).
   - Movimientos en libros: las líneas de póliza vigentes de la cuenta contable
     del banco hasta la fecha de corte que no se conciliaron antes.
   - Conciliación automática: mismo monto y sentido (débito del banco = Haber
     en libros; crédito = Debe), por número de documento (cheque) o por fecha
     cercana (±5 días). El resto se empareja o se marca a mano.
   - Lo que el banco registró y libros no (comisiones, intereses, notas de
     débito o crédito) se registra con una póliza de ajuste CONCILIACION.
   - Reporte: saldo según banco + depósitos en tránsito − cheques en
     circulación = saldo según libros + créditos − débitos no registrados.
     Se cierra cuando la diferencia es cero; los movimientos en tránsito pasan
     a la conciliación del mes siguiente.

 Errores nuevos: 55401 a 55440.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Origen de partida CONCILIACION
------------------------------------------------------------
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

------------------------------------------------------------
-- 2. Tablas
------------------------------------------------------------
-- Estado: B en proceso, C cerrada.
IF OBJECT_ID('dbo.bco_conciliacion', 'U') IS NULL
CREATE TABLE dbo.bco_conciliacion (
	[bcn_id]				INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_bco_conciliacion] PRIMARY KEY,
	[bcb_id]				INT				NOT NULL CONSTRAINT [FK_bco_conciliacion_cuenta] REFERENCES dbo.bco_cuenta_bancaria ([bcb_id]),
	[bcn_anio]				INT				NOT NULL,
	[bcn_mes]				INT				NOT NULL CONSTRAINT [CK_bco_conciliacion_mes] CHECK ([bcn_mes] BETWEEN 1 AND 12),
	[bcn_fecha_corte]		DATE			NOT NULL,
	[bcn_saldo_inicial_banco] NUMERIC(16, 2) NOT NULL CONSTRAINT [DF_bco_conciliacion_inicial] DEFAULT (0),
	[bcn_saldo_banco]		NUMERIC(16, 2)	NOT NULL CONSTRAINT [DF_bco_conciliacion_saldo] DEFAULT (0),
	[bcn_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_bco_conciliacion_estado] DEFAULT ('B') CONSTRAINT [CK_bco_conciliacion_estado] CHECK ([bcn_estado] IN ('B', 'C')),
	[bcn_fecha_cierre]		DATETIME2(0)	NULL,
	[usu_id_cierre]			INT				NULL CONSTRAINT [FK_bco_conciliacion_cierre] REFERENCES dbo.gen_usuario ([usu_id]),
	[InsUsuario]			INT				NULL CONSTRAINT [FK_bco_conciliacion_ins] REFERENCES dbo.gen_usuario ([usu_id]),
	[InsFechaHora]			DATETIME2(0)	NOT NULL CONSTRAINT [DF_bco_conciliacion_ins] DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL CONSTRAINT [FK_bco_conciliacion_upd] REFERENCES dbo.gen_usuario ([usu_id]),
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [UQ_bco_conciliacion_mes] UNIQUE ([bcb_id], [bcn_anio], [bcn_mes])
);
GO

-- Líneas del estado de cuenta; asd_id es la línea de póliza con la que se concilió.
IF OBJECT_ID('dbo.bco_extracto', 'U') IS NULL
CREATE TABLE dbo.bco_extracto (
	[bex_id]				INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_bco_extracto] PRIMARY KEY,
	[bcn_id]				INT				NOT NULL CONSTRAINT [FK_bco_extracto_conciliacion] REFERENCES dbo.bco_conciliacion ([bcn_id]),
	[bex_fecha]				DATE			NOT NULL,
	[bex_descripcion]		VARCHAR(250)	NULL,
	[bex_referencia]		VARCHAR(50)		NULL,
	[bex_debito]			NUMERIC(14, 2)	NOT NULL CONSTRAINT [DF_bco_extracto_debito] DEFAULT (0),
	[bex_credito]			NUMERIC(14, 2)	NOT NULL CONSTRAINT [DF_bco_extracto_credito] DEFAULT (0),
	[asd_id]				INT				NULL CONSTRAINT [FK_bco_extracto_asiento_det] REFERENCES dbo.cont_asiento_det ([asd_id]),
	[bex_forma]				CHAR(1)			NULL CONSTRAINT [CK_bco_extracto_forma] CHECK ([bex_forma] IN ('A', 'M', 'J')),	-- automática, manual, ajuste
	[InsUsuario]			INT				NULL CONSTRAINT [FK_bco_extracto_ins] REFERENCES dbo.gen_usuario ([usu_id]),
	[InsFechaHora]			DATETIME2(0)	NOT NULL CONSTRAINT [DF_bco_extracto_ins] DEFAULT (SYSDATETIME()),
	CONSTRAINT [CK_bco_extracto_montos] CHECK ([bex_debito] >= 0 AND [bex_credito] >= 0 AND ([bex_debito] > 0 OR [bex_credito] > 0) AND NOT ([bex_debito] > 0 AND [bex_credito] > 0))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bco_extracto_conciliacion')
	CREATE INDEX [IX_bco_extracto_conciliacion] ON dbo.bco_extracto ([bcn_id]) INCLUDE ([asd_id], [bex_debito], [bex_credito]);
GO

-- Líneas de libros conciliadas (con su línea del estado de cuenta o marcadas a mano).
IF OBJECT_ID('dbo.bco_conciliacion_libro', 'U') IS NULL
CREATE TABLE dbo.bco_conciliacion_libro (
	[bcn_id]				INT				NOT NULL CONSTRAINT [FK_bco_conciliacion_libro_conciliacion] REFERENCES dbo.bco_conciliacion ([bcn_id]),
	[asd_id]				INT				NOT NULL CONSTRAINT [FK_bco_conciliacion_libro_asiento_det] REFERENCES dbo.cont_asiento_det ([asd_id]),
	[bex_id]				INT				NULL CONSTRAINT [FK_bco_conciliacion_libro_extracto] REFERENCES dbo.bco_extracto ([bex_id]),
	CONSTRAINT [PK_bco_conciliacion_libro] PRIMARY KEY ([asd_id])
);
GO

IF TYPE_ID('dbo.bco_extracto_type') IS NULL
	CREATE TYPE dbo.bco_extracto_type AS TABLE (
		[bex_fecha]			DATE			NOT NULL,
		[bex_descripcion]	VARCHAR(250)	NULL,
		[bex_referencia]	VARCHAR(50)		NULL,
		[bex_debito]		NUMERIC(14, 2)	NOT NULL,
		[bex_credito]		NUMERIC(14, 2)	NOT NULL
	);
GO

INSERT INTO dbo.cont_cuenta_parametro (ccp_codigo, ccp_descripcion, ccp_naturaleza, cta_id, InsFechaHora)
SELECT v.codigo, v.descripcion, v.naturaleza, (SELECT TOP 1 cta_id FROM dbo.cont_cuenta_contable WHERE cta_acepta_movimiento = 1 AND cta_nombre LIKE v.nombre ORDER BY cta_codigo), SYSDATETIME()
FROM (VALUES
	('CONCILIACION_GASTO', 'Conciliación: comisiones y cargos bancarios', 'D', 'COMISIONES BANCARIAS%'),
	('CONCILIACION_INGRESO', 'Conciliación: intereses y otros créditos del banco', 'H', 'Otros ingresos%')) v (codigo, descripcion, naturaleza, nombre)
WHERE NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_parametro parm WHERE parm.ccp_codigo = v.codigo);
GO

INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT 'BANCOS', 'CONCILIACION_BANCARIA', 'Conciliación bancaria: importar el estado de cuenta, conciliar, ajustar y cerrar'
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_codigo = 'CONCILIACION_BANCARIA');
INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT rol.rol_id, perm.per_id
FROM dbo.sec_rol rol CROSS JOIN dbo.sec_permiso perm
WHERE rol.rol_codigo IN ('ADMIN', 'CONTADOR', 'CONTADOR_GENERAL') AND perm.per_codigo = 'CONCILIACION_BANCARIA'
  AND NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO

------------------------------------------------------------
-- 3. Movimientos en libros
------------------------------------------------------------
-- Cuentas contables de una cuenta bancaria (depósitos y cheques/pagos).
CREATE OR ALTER FUNCTION [dbo].[fnConciliacionCuentas] (@BcbId INT)
RETURNS TABLE
AS
RETURN
	SELECT cta_id FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId AND cta_id IS NOT NULL
	UNION
	SELECT cta_id_cargo FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId AND cta_id_cargo IS NOT NULL;
GO

-- Líneas de libros de la conciliación: las de las cuentas del banco hasta el
-- corte que no se conciliaron en otra conciliación.
CREATE OR ALTER FUNCTION [dbo].[fnConciliacionLibros] (@BcnId INT)
RETURNS TABLE
AS
RETURN
	SELECT deta.asd_id, asie.asi_id, asie.asi_fecha, asie.asi_origen, asie.asi_descripcion, deta.asd_descripcion,
		   deta.asd_debe, deta.asd_haber, libr.bex_id, IIF(libr.asd_id IS NULL, 0, 1) AS conciliado
	FROM dbo.bco_conciliacion conc
	INNER JOIN dbo.cont_asiento_det deta ON deta.cta_id IN (SELECT cta_id FROM dbo.fnConciliacionCuentas(conc.bcb_id))
	INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id AND asie.asi_estado = 'A' AND asie.asi_fecha <= conc.bcn_fecha_corte
	LEFT JOIN dbo.bco_conciliacion_libro libr ON libr.asd_id = deta.asd_id
	WHERE conc.bcn_id = @BcnId
	  AND (libr.asd_id IS NULL OR libr.bcn_id = @BcnId);
GO

------------------------------------------------------------
-- 4. Conciliaciones
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paConciliacionConsultar]
	@BcbId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT conc.bcn_id AS BcnId, conc.bcb_id AS BcbId, CONCAT(enti.gef_descripcion, ' ', cuba.bcb_numero_cuenta) AS Cuenta,
		   conc.bcn_anio AS Anio, conc.bcn_mes AS Mes, conc.bcn_fecha_corte AS FechaCorte, conc.bcn_saldo_inicial_banco AS SaldoInicialBanco,
		   conc.bcn_saldo_banco AS SaldoBanco, conc.bcn_estado AS Estado, conc.bcn_fecha_cierre AS FechaCierre, usua.usu_codigo AS CerradaPor,
		   (SELECT COUNT(*) FROM dbo.bco_extracto extr WHERE extr.bcn_id = conc.bcn_id) AS LineasExtracto,
		   (SELECT COUNT(*) FROM dbo.bco_extracto extr WHERE extr.bcn_id = conc.bcn_id AND extr.asd_id IS NULL) AS Pendientes
	FROM dbo.bco_conciliacion conc
	INNER JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = conc.bcb_id
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuba.gef_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = conc.usu_id_cierre
	WHERE @BcbId IS NULL OR conc.bcb_id = @BcbId
	ORDER BY conc.bcn_anio DESC, conc.bcn_mes DESC, conc.bcb_id;
END;
GO

-- Crea la conciliación del mes; el saldo inicial del banco se propone con el
-- final de la conciliación anterior.
CREATE OR ALTER PROCEDURE [dbo].[paConciliacionCrear]
	@BcbId				INT,
	@Anio				INT,
	@Mes				INT,
	@SaldoInicialBanco	NUMERIC(16, 2) = NULL,
	@SaldoBanco			NUMERIC(16, 2) = NULL,
	@UsuId				INT = NULL,
	@BcnId				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET @BcnId = NULL;
	DECLARE @mensaje NVARCHAR(300);
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId)
		THROW 55401, 'La cuenta bancaria no existe.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.fnConciliacionCuentas(@BcbId))
		THROW 55402, 'La cuenta bancaria no tiene cuenta contable: asígnela en Bancos > Cuentas y chequeras.', 1;
	IF @Mes NOT BETWEEN 1 AND 12 OR DATEFROMPARTS(@Anio, @Mes, 1) > CAST(GETDATE() AS DATE)
		THROW 55403, 'Elija un mes que ya empezó.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_conciliacion WHERE bcb_id = @BcbId AND bcn_estado = 'B')
		THROW 55404, 'La cuenta ya tiene una conciliación en proceso: termínela o elimínela antes de empezar otra.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_conciliacion WHERE bcb_id = @BcbId AND bcn_anio * 100 + bcn_mes >= @Anio * 100 + @Mes)
	BEGIN
		SET @mensaje = CONCAT(N'La cuenta ya tiene la conciliación de ', @Mes, N'/', @Anio, N' o de un mes posterior.');
		THROW 55405, @mensaje, 1;
	END
	SET @SaldoInicialBanco = ISNULL(@SaldoInicialBanco, (SELECT TOP 1 bcn_saldo_banco FROM dbo.bco_conciliacion WHERE bcb_id = @BcbId ORDER BY bcn_anio DESC, bcn_mes DESC));
	INSERT INTO dbo.bco_conciliacion (bcb_id, bcn_anio, bcn_mes, bcn_fecha_corte, bcn_saldo_inicial_banco, bcn_saldo_banco, InsUsuario)
	VALUES (@BcbId, @Anio, @Mes, EOMONTH(DATEFROMPARTS(@Anio, @Mes, 1)), ISNULL(@SaldoInicialBanco, 0), ISNULL(@SaldoBanco, 0), @UsuId);
	SET @BcnId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paConciliacionGuardarSaldos]
	@BcnId				INT,
	@SaldoInicialBanco	NUMERIC(16, 2),
	@SaldoBanco			NUMERIC(16, 2),
	@UsuId				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_conciliacion WHERE bcn_id = @BcnId AND bcn_estado = 'B')
		THROW 55406, 'La conciliación no existe o ya está cerrada.', 1;
	UPDATE dbo.bco_conciliacion
	   SET bcn_saldo_inicial_banco = ISNULL(@SaldoInicialBanco, 0), bcn_saldo_banco = ISNULL(@SaldoBanco, 0), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE bcn_id = @BcnId;
END;
GO

-- Solo una conciliación en proceso; se borran sus líneas (las pólizas de
-- ajuste que ya se grabaron quedan, y se concilian en la siguiente).
CREATE OR ALTER PROCEDURE [dbo].[paConciliacionEliminar]
	@BcnId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_conciliacion WHERE bcn_id = @BcnId AND bcn_estado = 'B')
		THROW 55407, 'Solo se elimina una conciliación en proceso.', 1;
	BEGIN TRANSACTION;
		DELETE FROM dbo.bco_conciliacion_libro WHERE bcn_id = @BcnId;
		DELETE FROM dbo.bco_extracto WHERE bcn_id = @BcnId;
		DELETE FROM dbo.bco_conciliacion WHERE bcn_id = @BcnId;
	COMMIT TRANSACTION;
END;
GO

-- Resultado 1: encabezado y resumen. 2: estado de cuenta. 3: libros.
CREATE OR ALTER PROCEDURE [dbo].[paConciliacionDetalle]
	@BcnId	INT
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @bcb_id INT, @corte DATE;
	SELECT @bcb_id = bcb_id, @corte = bcn_fecha_corte FROM dbo.bco_conciliacion WHERE bcn_id = @BcnId;
	IF @bcb_id IS NULL
		THROW 55408, 'La conciliación no existe.', 1;

	DECLARE @libros TABLE (asd_id INT PRIMARY KEY, debe NUMERIC(14, 2), haber NUMERIC(14, 2), conciliado BIT);
	INSERT INTO @libros SELECT asd_id, asd_debe, asd_haber, conciliado FROM dbo.fnConciliacionLibros(@BcnId);
	DECLARE @saldo_libros NUMERIC(16, 2) = (
		SELECT ISNULL(SUM(deta.asd_debe - deta.asd_haber), 0)
		FROM dbo.cont_asiento_det deta
		INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id AND asie.asi_estado = 'A' AND asie.asi_fecha <= @corte
		WHERE deta.cta_id IN (SELECT cta_id FROM dbo.fnConciliacionCuentas(@bcb_id)));

	SELECT conc.bcn_id AS BcnId, conc.bcb_id AS BcbId, CONCAT(enti.gef_descripcion, ' ', cuba.bcb_numero_cuenta) AS Cuenta,
		   conc.bcn_anio AS Anio, conc.bcn_mes AS Mes, conc.bcn_fecha_corte AS FechaCorte, conc.bcn_estado AS Estado,
		   conc.bcn_saldo_inicial_banco AS SaldoInicialBanco, conc.bcn_saldo_banco AS SaldoBanco,
		   extr.Creditos AS CreditosExtracto, extr.Debitos AS DebitosExtracto,
		   ISNULL((SELECT SUM(debe) FROM @libros WHERE conciliado = 0 AND debe > 0), 0) AS DepositosTransito,
		   ISNULL((SELECT SUM(haber) FROM @libros WHERE conciliado = 0 AND haber > 0), 0) AS ChequesCirculacion,
		   @saldo_libros AS SaldoLibros,
		   extr.CreditosNoRegistrados, extr.DebitosNoRegistrados
	FROM dbo.bco_conciliacion conc
	INNER JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = conc.bcb_id
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuba.gef_id
	CROSS APPLY (SELECT ISNULL(SUM(bex_credito), 0) AS Creditos, ISNULL(SUM(bex_debito), 0) AS Debitos,
						ISNULL(SUM(IIF(asd_id IS NULL, bex_credito, 0)), 0) AS CreditosNoRegistrados,
						ISNULL(SUM(IIF(asd_id IS NULL, bex_debito, 0)), 0) AS DebitosNoRegistrados
				 FROM dbo.bco_extracto WHERE bcn_id = conc.bcn_id) extr
	WHERE conc.bcn_id = @BcnId;

	SELECT extr.bex_id AS BexId, extr.bex_fecha AS Fecha, extr.bex_descripcion AS Descripcion, extr.bex_referencia AS Referencia,
		   extr.bex_debito AS Debito, extr.bex_credito AS Credito, extr.asd_id AS AsdId, extr.bex_forma AS Forma, deta.asi_id AS AsiId
	FROM dbo.bco_extracto extr
	LEFT JOIN dbo.cont_asiento_det deta ON deta.asd_id = extr.asd_id
	WHERE extr.bcn_id = @BcnId
	ORDER BY extr.bex_fecha, extr.bex_id;

	SELECT asd_id AS AsdId, asi_id AS AsiId, asi_fecha AS Fecha, asi_origen AS Origen,
		   ISNULL(NULLIF(asd_descripcion, ''), asi_descripcion) AS Descripcion, asd_debe AS Debe, asd_haber AS Haber,
		   bex_id AS BexId, CAST(conciliado AS BIT) AS Conciliado
	FROM dbo.fnConciliacionLibros(@BcnId)
	ORDER BY asi_fecha, asd_id;
END;
GO

------------------------------------------------------------
-- 5. Estado de cuenta del banco
------------------------------------------------------------
-- @Reemplazar = 1 borra antes las líneas que todavía no están conciliadas.
CREATE OR ALTER PROCEDURE [dbo].[paConciliacionExtractoCargar]
	@BcnId		INT,
	@Lineas		dbo.bco_extracto_type READONLY,
	@Reemplazar	BIT = 0,
	@UsuId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	DECLARE @anio INT, @mes INT, @mensaje NVARCHAR(300);
	SELECT @anio = bcn_anio, @mes = bcn_mes FROM dbo.bco_conciliacion WHERE bcn_id = @BcnId AND bcn_estado = 'B';
	IF @anio IS NULL
		THROW 55406, 'La conciliación no existe o ya está cerrada.', 1;
	IF NOT EXISTS (SELECT 1 FROM @Lineas)
		THROW 55409, 'El estado de cuenta no tiene líneas.', 1;
	IF EXISTS (SELECT 1 FROM @Lineas WHERE bex_debito < 0 OR bex_credito < 0 OR (bex_debito = 0 AND bex_credito = 0) OR (bex_debito > 0 AND bex_credito > 0))
		THROW 55410, 'Cada línea del estado de cuenta lleva un débito o un crédito mayor a cero (no los dos).', 1;
	IF EXISTS (SELECT 1 FROM @Lineas WHERE bex_fecha > EOMONTH(DATEFROMPARTS(@anio, @mes, 1)))
	BEGIN
		SET @mensaje = CONCAT(N'Hay líneas con fecha posterior al ', FORMAT(EOMONTH(DATEFROMPARTS(@anio, @mes, 1)), 'dd/MM/yyyy'), N', el corte de la conciliación.');
		THROW 55411, @mensaje, 1;
	END
	BEGIN TRANSACTION;
		IF @Reemplazar = 1
			DELETE FROM dbo.bco_extracto WHERE bcn_id = @BcnId AND asd_id IS NULL;
		INSERT INTO dbo.bco_extracto (bcn_id, bex_fecha, bex_descripcion, bex_referencia, bex_debito, bex_credito, InsUsuario)
		SELECT @BcnId, bex_fecha, NULLIF(LTRIM(RTRIM(bex_descripcion)), ''), NULLIF(LTRIM(RTRIM(bex_referencia)), ''), bex_debito, bex_credito, @UsuId
		FROM @Lineas;
	COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paConciliacionExtractoEliminar]
	@BexId	INT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_extracto extr INNER JOIN dbo.bco_conciliacion conc ON conc.bcn_id = extr.bcn_id AND conc.bcn_estado = 'B'
				   WHERE extr.bex_id = @BexId AND extr.asd_id IS NULL)
		THROW 55412, 'Solo se elimina una línea no conciliada de una conciliación en proceso.', 1;
	DELETE FROM dbo.bco_extracto WHERE bex_id = @BexId;
END;
GO

------------------------------------------------------------
-- 6. Conciliar
------------------------------------------------------------
-- Empareja una línea del banco con una de libros (mismo monto y sentido).
CREATE OR ALTER PROCEDURE [dbo].[paConciliacionEmparejar]
	@BcnId	INT,
	@BexId	INT,
	@AsdId	INT,
	@Forma	CHAR(1) = 'M'
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	DECLARE @debito NUMERIC(14, 2), @credito NUMERIC(14, 2), @debe NUMERIC(14, 2), @haber NUMERIC(14, 2);
	SELECT @debito = extr.bex_debito, @credito = extr.bex_credito
	FROM dbo.bco_extracto extr INNER JOIN dbo.bco_conciliacion conc ON conc.bcn_id = extr.bcn_id AND conc.bcn_estado = 'B'
	WHERE extr.bex_id = @BexId AND extr.bcn_id = @BcnId AND extr.asd_id IS NULL;
	IF @debito IS NULL
		THROW 55413, 'La línea del estado de cuenta no existe, ya está conciliada o la conciliación está cerrada.', 1;
	SELECT @debe = asd_debe, @haber = asd_haber FROM dbo.fnConciliacionLibros(@BcnId) WHERE asd_id = @AsdId AND conciliado = 0;
	IF @debe IS NULL
		THROW 55414, 'El movimiento de libros no existe o ya está conciliado.', 1;
	IF NOT ((@debito > 0 AND @haber = @debito) OR (@credito > 0 AND @debe = @credito))
		THROW 55415, 'Los montos no coinciden: un débito del banco va con un pago (Haber) y un crédito con un depósito (Debe) por el mismo monto.', 1;
	BEGIN TRANSACTION;
		UPDATE dbo.bco_extracto SET asd_id = @AsdId, bex_forma = @Forma WHERE bex_id = @BexId;
		INSERT INTO dbo.bco_conciliacion_libro (bcn_id, asd_id, bex_id) VALUES (@BcnId, @AsdId, @BexId);
	COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paConciliacionDesemparejar]
	@BcnId	INT,
	@BexId	INT = NULL,
	@AsdId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_conciliacion WHERE bcn_id = @BcnId AND bcn_estado = 'B')
		THROW 55406, 'La conciliación no existe o ya está cerrada.', 1;
	IF @AsdId IS NULL
		SELECT @AsdId = asd_id FROM dbo.bco_extracto WHERE bex_id = @BexId AND bcn_id = @BcnId;
	BEGIN TRANSACTION;
		UPDATE dbo.bco_extracto SET asd_id = NULL, bex_forma = NULL WHERE bcn_id = @BcnId AND (bex_id = @BexId OR asd_id = @AsdId);
		DELETE FROM dbo.bco_conciliacion_libro WHERE bcn_id = @BcnId AND asd_id = @AsdId;
	COMMIT TRANSACTION;
END;
GO

-- Marca o desmarca un movimiento de libros como conciliado sin línea del
-- banco (por ejemplo, el saldo de apertura o algo que ya aparece en el
-- saldo inicial del banco).
CREATE OR ALTER PROCEDURE [dbo].[paConciliacionMarcarLibro]
	@BcnId	INT,
	@AsdId	INT,
	@Marcar	BIT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_conciliacion WHERE bcn_id = @BcnId AND bcn_estado = 'B')
		THROW 55406, 'La conciliación no existe o ya está cerrada.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.fnConciliacionLibros(@BcnId) WHERE asd_id = @AsdId)
		THROW 55414, 'El movimiento de libros no existe o ya está conciliado.', 1;
	IF @Marcar = 1
		INSERT INTO dbo.bco_conciliacion_libro (bcn_id, asd_id) SELECT @BcnId, @AsdId
		WHERE NOT EXISTS (SELECT 1 FROM dbo.bco_conciliacion_libro WHERE asd_id = @AsdId);
	ELSE
		EXEC dbo.paConciliacionDesemparejar @BcnId = @BcnId, @AsdId = @AsdId;
END;
GO

-- Empareja solo: primero por número de documento (cheque) y monto, luego por
-- monto y fecha cercana (±5 días, la más cercana). Devuelve cuántas emparejó.
CREATE OR ALTER PROCEDURE [dbo].[paConciliacionAutomatica]
	@BcnId		INT,
	@Emparejadas INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @Emparejadas = 0;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_conciliacion WHERE bcn_id = @BcnId AND bcn_estado = 'B')
		THROW 55406, 'La conciliación no existe o ya está cerrada.', 1;

	DECLARE @libros TABLE (asd_id INT PRIMARY KEY, fecha DATE, texto VARCHAR(600), debe NUMERIC(14, 2), haber NUMERIC(14, 2), usado BIT);
	INSERT INTO @libros
	SELECT asd_id, asi_fecha, CONCAT(asi_descripcion, ' ', asd_descripcion), asd_debe, asd_haber, 0
	FROM dbo.fnConciliacionLibros(@BcnId) WHERE conciliado = 0;

	DECLARE @bex_id INT, @fecha DATE, @referencia VARCHAR(50), @debito NUMERIC(14, 2), @credito NUMERIC(14, 2), @asd_id INT;
	DECLARE lineas CURSOR LOCAL FAST_FORWARD FOR
		SELECT bex_id, bex_fecha, bex_referencia, bex_debito, bex_credito FROM dbo.bco_extracto WHERE bcn_id = @BcnId AND asd_id IS NULL ORDER BY bex_fecha, bex_id;
	OPEN lineas;
	FETCH NEXT FROM lineas INTO @bex_id, @fecha, @referencia, @debito, @credito;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @asd_id = NULL;
		IF LEN(ISNULL(@referencia, '')) >= 3
			SELECT TOP 1 @asd_id = asd_id FROM @libros
			WHERE usado = 0 AND ((@debito > 0 AND haber = @debito) OR (@credito > 0 AND debe = @credito))
			  AND texto LIKE '%' + @referencia + '%'
			ORDER BY ABS(DATEDIFF(DAY, fecha, @fecha));
		IF @asd_id IS NULL
			SELECT TOP 1 @asd_id = asd_id FROM @libros
			WHERE usado = 0 AND ((@debito > 0 AND haber = @debito) OR (@credito > 0 AND debe = @credito))
			  AND ABS(DATEDIFF(DAY, fecha, @fecha)) <= 5
			ORDER BY ABS(DATEDIFF(DAY, fecha, @fecha)), asd_id;
		IF @asd_id IS NOT NULL
		BEGIN
			EXEC dbo.paConciliacionEmparejar @BcnId = @BcnId, @BexId = @bex_id, @AsdId = @asd_id, @Forma = 'A';
			UPDATE @libros SET usado = 1 WHERE asd_id = @asd_id;
			SET @Emparejadas += 1;
		END
		FETCH NEXT FROM lineas INTO @bex_id, @fecha, @referencia, @debito, @credito;
	END
	CLOSE lineas; DEALLOCATE lineas;
END;
GO

-- Póliza de ajuste por una línea del banco que no está en libros: débito del
-- banco = Debe @CtaId / Haber banco; crédito = Debe banco / Haber @CtaId.
-- Queda conciliada con esa línea.
CREATE OR ALTER PROCEDURE [dbo].[paConciliacionAjuste]
	@BcnId			INT,
	@BexId			INT,
	@CtaId			INT = NULL,
	@Descripcion	VARCHAR(256) = NULL,
	@UsuId			INT = NULL,
	@AsiId			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @AsiId = NULL;
	DECLARE @bcb_id INT, @fecha DATE, @debito NUMERIC(14, 2), @credito NUMERIC(14, 2), @texto VARCHAR(250);
	SELECT @bcb_id = conc.bcb_id, @fecha = extr.bex_fecha, @debito = extr.bex_debito, @credito = extr.bex_credito, @texto = extr.bex_descripcion
	FROM dbo.bco_extracto extr INNER JOIN dbo.bco_conciliacion conc ON conc.bcn_id = extr.bcn_id AND conc.bcn_estado = 'B'
	WHERE extr.bex_id = @BexId AND extr.bcn_id = @BcnId AND extr.asd_id IS NULL;
	IF @bcb_id IS NULL
		THROW 55413, 'La línea del estado de cuenta no existe, ya está conciliada o la conciliación está cerrada.', 1;
	SET @CtaId = ISNULL(@CtaId, (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = IIF(@debito > 0, 'CONCILIACION_GASTO', 'CONCILIACION_INGRESO')));
	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId AND cta_acepta_movimiento = 1 AND cta_estado = 'A')
		THROW 55416, 'Elija la cuenta contable del ajuste (de detalle y activa).', 1;
	DECLARE @cta_banco INT = IIF(@debito > 0, dbo.fnBcoCuentaContable(@bcb_id),
								 ISNULL((SELECT cta_id_cargo FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @bcb_id), dbo.fnBcoCuentaContable(@bcb_id)));
	DECLARE @monto NUMERIC(14, 2) = IIF(@debito > 0, @debito, @credito);
	SET @Descripcion = LEFT(ISNULL(NULLIF(LTRIM(RTRIM(@Descripcion)), ''), CONCAT('Conciliación bancaria: ', ISNULL(@texto, IIF(@debito > 0, 'cargo del banco', 'crédito del banco')))), 256);

	BEGIN TRY
		BEGIN TRANSACTION;
			DECLARE @partida dbo.cont_asiento_det_cc_type;
			INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
			VALUES (IIF(@debito > 0, @CtaId, @cta_banco), @monto, 0, @Descripcion), (IIF(@debito > 0, @cta_banco, @CtaId), 0, @monto, @Descripcion);
			EXEC dbo.paContabilidadAsientoInsertarCc @asi_fecha = @fecha, @asi_descripcion = @Descripcion, @asi_origen = 'CONCILIACION',
				@asi_origen_id = @BcnId, @usu_id = @UsuId, @detalle = @partida, @asi_id = @AsiId OUTPUT;
			DECLARE @asd_id INT = (SELECT asd_id FROM dbo.cont_asiento_det WHERE asi_id = @AsiId AND cta_id = @cta_banco);
			UPDATE dbo.bco_extracto SET asd_id = @asd_id, bex_forma = 'J' WHERE bex_id = @BexId;
			INSERT INTO dbo.bco_conciliacion_libro (bcn_id, asd_id, bex_id) VALUES (@BcnId, @asd_id, @BexId);
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Cierra si cuadra: todas las líneas del banco conciliadas y diferencia cero.
CREATE OR ALTER PROCEDURE [dbo].[paConciliacionCerrar]
	@BcnId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @mensaje NVARCHAR(300);
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_conciliacion WHERE bcn_id = @BcnId AND bcn_estado = 'B')
		THROW 55406, 'La conciliación no existe o ya está cerrada.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_extracto WHERE bcn_id = @BcnId AND asd_id IS NULL)
		THROW 55417, 'Hay líneas del estado de cuenta sin conciliar: emparéjelas o regístrelas con una póliza de ajuste.', 1;

	DECLARE @bcb_id INT, @corte DATE, @saldo_banco NUMERIC(16, 2), @inicial NUMERIC(16, 2);
	SELECT @bcb_id = bcb_id, @corte = bcn_fecha_corte, @saldo_banco = bcn_saldo_banco, @inicial = bcn_saldo_inicial_banco FROM dbo.bco_conciliacion WHERE bcn_id = @BcnId;
	DECLARE @saldo_libros NUMERIC(16, 2) = (
		SELECT ISNULL(SUM(deta.asd_debe - deta.asd_haber), 0) FROM dbo.cont_asiento_det deta
		INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id AND asie.asi_estado = 'A' AND asie.asi_fecha <= @corte
		WHERE deta.cta_id IN (SELECT cta_id FROM dbo.fnConciliacionCuentas(@bcb_id)));
	DECLARE @transito NUMERIC(16, 2), @circulacion NUMERIC(16, 2);
	SELECT @transito = ISNULL(SUM(IIF(conciliado = 0, asd_debe, 0)), 0), @circulacion = ISNULL(SUM(IIF(conciliado = 0, asd_haber, 0)), 0)
	FROM dbo.fnConciliacionLibros(@BcnId);
	DECLARE @diferencia NUMERIC(16, 2) = (@saldo_banco + @transito - @circulacion) - @saldo_libros;
	IF @diferencia <> 0
	BEGIN
		SET @mensaje = CONCAT(N'La conciliación no cuadra: diferencia de Q', FORMAT(@diferencia, 'N2'), N'. Revise el saldo final del banco y los movimientos marcados.');
		THROW 55418, @mensaje, 1;
	END
	DECLARE @movimiento NUMERIC(16, 2) = (SELECT ISNULL(SUM(bex_credito - bex_debito), 0) FROM dbo.bco_extracto WHERE bcn_id = @BcnId);
	IF EXISTS (SELECT 1 FROM dbo.bco_extracto WHERE bcn_id = @BcnId) AND @inicial + @movimiento <> @saldo_banco
	BEGIN
		SET @mensaje = CONCAT(N'El estado de cuenta no cuadra: saldo inicial Q', FORMAT(@inicial, 'N2'), N' + movimientos Q', FORMAT(@movimiento, 'N2'),
			N' no da el saldo final Q', FORMAT(@saldo_banco, 'N2'), N'. Falta o sobra alguna línea.');
		THROW 55419, @mensaje, 1;
	END
	UPDATE dbo.bco_conciliacion SET bcn_estado = 'C', bcn_fecha_cierre = SYSDATETIME(), usu_id_cierre = @UsuId, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE bcn_id = @BcnId;
END;
GO

-- Vuelve a abrir la última conciliación cerrada de la cuenta.
CREATE OR ALTER PROCEDURE [dbo].[paConciliacionReabrir]
	@BcnId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @bcb_id INT, @periodo INT;
	SELECT @bcb_id = bcb_id, @periodo = bcn_anio * 100 + bcn_mes FROM dbo.bco_conciliacion WHERE bcn_id = @BcnId AND bcn_estado = 'C';
	IF @bcb_id IS NULL
		THROW 55420, 'La conciliación no existe o no está cerrada.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_conciliacion WHERE bcb_id = @bcb_id AND bcn_anio * 100 + bcn_mes > @periodo)
		THROW 55421, 'Solo se vuelve a abrir la última conciliación de la cuenta.', 1;
	UPDATE dbo.bco_conciliacion SET bcn_estado = 'B', bcn_fecha_cierre = NULL, usu_id_cierre = NULL, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE bcn_id = @BcnId;
END;
GO

------------------------------------------------------------
-- 7. Datos de demostración: conciliación de septiembre de la cuenta
-- monetaria del Banco Industrial (cheque 1013 en circulación, comisión e
-- intereses del banco registrados con ajuste).
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.bco_conciliacion)
   AND EXISTS (SELECT 1 FROM dbo.cont_asiento_enc WHERE asi_descripcion LIKE 'Desembolso de préstamo bancario%' AND asi_estado = 'A')
   AND EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = 1)
   AND NOT EXISTS (SELECT 1 FROM dbo.cont_periodo_contable WHERE pdo_anio = 2026 AND pdo_mes = 9 AND pdo_estado = 'C')
BEGIN
	DECLARE @bcn_id INT, @emparejadas INT, @asi_id INT, @bex_id INT, @asd_apertura INT, @lineas dbo.bco_extracto_type;
	EXEC dbo.paConciliacionCrear @BcbId = 1, @Anio = 2026, @Mes = 9, @SaldoInicialBanco = 150000, @UsuId = 1, @BcnId = @bcn_id OUTPUT;

	-- El estado de cuenta: los movimientos de libros del mes que el banco ya
	-- pagó o acreditó (un día después), más comisión e intereses.
	INSERT INTO @lineas (bex_fecha, bex_descripcion, bex_referencia, bex_debito, bex_credito)
	SELECT DATEADD(DAY, IIF(asi_fecha < '20260930', 1, 0), asi_fecha),
		   CASE WHEN asd_haber > 0 THEN 'CHEQUE PAGADO' ELSE 'CREDITO POR DESEMBOLSO' END,
		   (SELECT TOP 1 emit.bce_numero_cheque FROM dbo.bco_cheque_emitido_enc emit WHERE emit.bce_id = libr.asi_origen_id_cheque),
		   asd_haber, asd_debe
	FROM (SELECT libr.*, IIF(asie.asi_origen = 'CHEQUE', asie.asi_origen_id, NULL) AS asi_origen_id_cheque
		  FROM dbo.fnConciliacionLibros(@bcn_id) libr INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = libr.asi_id
		  WHERE libr.asi_fecha >= '20260901' AND libr.asi_descripcion NOT LIKE 'Cheque 1013 %') libr;
	INSERT INTO @lineas VALUES ('20260930', 'COMISION MANEJO DE CUENTA', NULL, 45.00, 0), ('20260930', 'INTERESES GANADOS', NULL, 0, 12.50);
	EXEC dbo.paConciliacionExtractoCargar @BcnId = @bcn_id, @Lineas = @lineas, @UsuId = 1;
	UPDATE dbo.bco_conciliacion
	   SET bcn_saldo_banco = bcn_saldo_inicial_banco + (SELECT SUM(bex_credito - bex_debito) FROM dbo.bco_extracto WHERE bcn_id = @bcn_id)
	 WHERE bcn_id = @bcn_id;

	-- La apertura ya está en el saldo inicial del banco.
	SELECT TOP 1 @asd_apertura = asd_id FROM dbo.fnConciliacionLibros(@bcn_id) WHERE asi_origen = 'APERTURA';
	IF @asd_apertura IS NOT NULL
		EXEC dbo.paConciliacionMarcarLibro @BcnId = @bcn_id, @AsdId = @asd_apertura, @Marcar = 1;
	EXEC dbo.paConciliacionAutomatica @BcnId = @bcn_id, @Emparejadas = @emparejadas OUTPUT;

	DECLARE ajustes CURSOR LOCAL FAST_FORWARD FOR SELECT bex_id FROM dbo.bco_extracto WHERE bcn_id = @bcn_id AND asd_id IS NULL;
	OPEN ajustes;
	FETCH NEXT FROM ajustes INTO @bex_id;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		EXEC dbo.paConciliacionAjuste @BcnId = @bcn_id, @BexId = @bex_id, @UsuId = 1, @AsiId = @asi_id OUTPUT;
		FETCH NEXT FROM ajustes INTO @bex_id;
	END
	CLOSE ajustes; DEALLOCATE ajustes;
	-- Se deja en proceso si algo no cuadra (por ejemplo, con otros datos).
	BEGIN TRY
		EXEC dbo.paConciliacionCerrar @BcnId = @bcn_id, @UsuId = 1;
	END TRY
	BEGIN CATCH
		PRINT CONCAT('Conciliación de demostración en proceso: ', ERROR_MESSAGE());
	END CATCH
END
GO

PRINT '64_conciliacion_bancaria.sql aplicado.';
GO
