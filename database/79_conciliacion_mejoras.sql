/*
================================================================================
 79_conciliacion_mejoras.sql
 Conciliación bancaria: mejoras de la revisión con la metodología de
 conciliación (clasificar, confirmar, antigüedad, varios con uno).

   1. Parámetros (bco_conciliacion_parametro, una sola fila):
        - tolerancia de días de la conciliación automática (antes fija en 5);
        - días para marcar "revisar" un depósito en tránsito y un cheque o
          pago en circulación.
      paConciliacionParametroConsultar / paConciliacionParametroGuardar.
   2. Clasificación de las líneas del banco sin registrar
      (fnConciliacionClase): COMISION (comisión, cargo, manejo,
      mantenimiento, chequera, timbres...), INTERES (interés, rendimiento) o
      SIN_CLASIFICAR. Una línea sin clasificar ya no va sola a "comisiones
      bancarias" u "otros ingresos": paConciliacionAjuste exige elegir la
      cuenta (55422).
   3. Antigüedad: paConciliacionDetalle devuelve los días de cada movimiento
      de libros sin conciliar al corte y la marca Revisar cuando pasa los
      días del parámetro; y la clase de cada línea del banco.
   4. Emparejar varios con uno (paConciliacionEmparejarGrupo): una o varias
      líneas del banco con uno o varios movimientos de libros que suman lo
      mismo (por ejemplo, un depósito que agrupa varios cobros). Quedan como
      un grupo (bex_grupo, bcl_grupo; forma G) y se deshacen juntas.

 Requiere el 64. Errores nuevos: 55422 a 55427.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Parámetros, grupos y forma G
------------------------------------------------------------
IF OBJECT_ID('dbo.bco_conciliacion_parametro', 'U') IS NULL
CREATE TABLE dbo.bco_conciliacion_parametro (
	[bcp_id]				INT				NOT NULL CONSTRAINT [PK_bco_conciliacion_parametro] PRIMARY KEY
												CONSTRAINT [CK_bco_conciliacion_parametro_unico] CHECK ([bcp_id] = 1),
	[bcp_tolerancia_dias]	INT				NOT NULL CONSTRAINT [CK_bco_conciliacion_parametro_tolerancia] CHECK ([bcp_tolerancia_dias] BETWEEN 0 AND 31),
	[bcp_dias_deposito]		INT				NOT NULL CONSTRAINT [CK_bco_conciliacion_parametro_deposito] CHECK ([bcp_dias_deposito] BETWEEN 1 AND 365),
	[bcp_dias_cheque]		INT				NOT NULL CONSTRAINT [CK_bco_conciliacion_parametro_cheque] CHECK ([bcp_dias_cheque] BETWEEN 1 AND 365),
	[UpdUsuario]			INT				NULL CONSTRAINT [FK_bco_conciliacion_parametro_upd] REFERENCES dbo.gen_usuario ([usu_id]),
	[UpdFechaHora]			DATETIME2(0)	NULL
);
GO
-- Un depósito tarda uno o dos días hábiles en acreditarse; un cheque se
-- cobra en días o semanas (el que no se cobra en meses hay que investigarlo).
IF NOT EXISTS (SELECT 1 FROM dbo.bco_conciliacion_parametro)
	INSERT INTO dbo.bco_conciliacion_parametro (bcp_id, bcp_tolerancia_dias, bcp_dias_deposito, bcp_dias_cheque) VALUES (1, 5, 3, 30);
GO

IF COL_LENGTH('dbo.bco_extracto', 'bex_grupo') IS NULL
	ALTER TABLE dbo.bco_extracto ADD [bex_grupo] INT NULL;	-- emparejada en grupo: el bex_id menor del grupo
GO
IF COL_LENGTH('dbo.bco_conciliacion_libro', 'bcl_grupo') IS NULL
	ALTER TABLE dbo.bco_conciliacion_libro ADD [bcl_grupo] INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_bco_extracto_forma' AND definition LIKE '%G%')
BEGIN
	ALTER TABLE dbo.bco_extracto DROP CONSTRAINT [CK_bco_extracto_forma];
	ALTER TABLE dbo.bco_extracto ADD CONSTRAINT [CK_bco_extracto_forma] CHECK ([bex_forma] IN ('A', 'M', 'J', 'G'));	-- automática, manual, ajuste, grupo
END
GO

CREATE OR ALTER PROCEDURE [dbo].[paConciliacionParametroConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT bcp_tolerancia_dias AS ToleranciaDias, bcp_dias_deposito AS DiasDeposito, bcp_dias_cheque AS DiasCheque
	FROM dbo.bco_conciliacion_parametro WHERE bcp_id = 1;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paConciliacionParametroGuardar]
	@ToleranciaDias	INT,
	@DiasDeposito	INT,
	@DiasCheque		INT,
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @ToleranciaDias NOT BETWEEN 0 AND 31 OR @DiasDeposito NOT BETWEEN 1 AND 365 OR @DiasCheque NOT BETWEEN 1 AND 365
		THROW 55427, 'La tolerancia va de 0 a 31 días y los días para revisar, de 1 a 365.', 1;
	UPDATE dbo.bco_conciliacion_parametro
	   SET bcp_tolerancia_dias = @ToleranciaDias, bcp_dias_deposito = @DiasDeposito, bcp_dias_cheque = @DiasCheque,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE bcp_id = 1;
END;
GO

------------------------------------------------------------
-- 2. Clase de una línea del banco
------------------------------------------------------------
-- Por palabras de la descripción: es un primer corte; lo que no se reconoce
-- queda SIN_CLASIFICAR y lo decide una persona.
CREATE OR ALTER FUNCTION [dbo].[fnConciliacionClase] (@Descripcion VARCHAR(300), @Debito NUMERIC(14, 2), @Credito NUMERIC(14, 2))
RETURNS VARCHAR(20)
AS
BEGIN
	-- Sin tildes, para que «Comisión» y «comision» sean lo mismo.
	DECLARE @texto VARCHAR(300) = TRANSLATE(LOWER(ISNULL(@Descripcion, '')), 'áéíóúü', 'aeiouu');
	IF @Debito > 0 AND (@texto LIKE '%comision%' OR @texto LIKE '%cargo%' OR @texto LIKE '%manejo%' OR @texto LIKE '%mantenimiento%'
						OR @texto LIKE '%chequera%' OR @texto LIKE '%timbre%' OR @texto LIKE '%membresia%' OR @texto LIKE '%fee%'
						OR @texto LIKE '%servicio bancario%')
		RETURN 'COMISION';
	IF @Credito > 0 AND (@texto LIKE '%interes%' OR @texto LIKE '%rendimiento%')
		RETURN 'INTERES';
	RETURN 'SIN_CLASIFICAR';
END;
GO

------------------------------------------------------------
-- 3. Detalle con clase, antigüedad y grupos
------------------------------------------------------------
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
	DECLARE @dias_deposito INT, @dias_cheque INT;
	SELECT @dias_deposito = bcp_dias_deposito, @dias_cheque = bcp_dias_cheque FROM dbo.bco_conciliacion_parametro WHERE bcp_id = 1;

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
		   extr.CreditosNoRegistrados, extr.DebitosNoRegistrados,
		   @dias_deposito AS DiasDeposito, @dias_cheque AS DiasCheque
	FROM dbo.bco_conciliacion conc
	INNER JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = conc.bcb_id
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuba.gef_id
	CROSS APPLY (SELECT ISNULL(SUM(bex_credito), 0) AS Creditos, ISNULL(SUM(bex_debito), 0) AS Debitos,
						ISNULL(SUM(IIF(asd_id IS NULL, bex_credito, 0)), 0) AS CreditosNoRegistrados,
						ISNULL(SUM(IIF(asd_id IS NULL, bex_debito, 0)), 0) AS DebitosNoRegistrados
				 FROM dbo.bco_extracto WHERE bcn_id = conc.bcn_id) extr
	WHERE conc.bcn_id = @BcnId;

	SELECT extr.bex_id AS BexId, extr.bex_fecha AS Fecha, extr.bex_descripcion AS Descripcion, extr.bex_referencia AS Referencia,
		   extr.bex_debito AS Debito, extr.bex_credito AS Credito, extr.asd_id AS AsdId, extr.bex_forma AS Forma, deta.asi_id AS AsiId,
		   extr.bex_grupo AS Grupo, dbo.fnConciliacionClase(extr.bex_descripcion, extr.bex_debito, extr.bex_credito) AS Clase
	FROM dbo.bco_extracto extr
	LEFT JOIN dbo.cont_asiento_det deta ON deta.asd_id = extr.asd_id
	WHERE extr.bcn_id = @BcnId
	ORDER BY extr.bex_fecha, extr.bex_id;

	SELECT libr.asd_id AS AsdId, libr.asi_id AS AsiId, libr.asi_fecha AS Fecha, libr.asi_origen AS Origen,
		   ISNULL(NULLIF(libr.asd_descripcion, ''), libr.asi_descripcion) AS Descripcion, libr.asd_debe AS Debe, libr.asd_haber AS Haber,
		   libr.bex_id AS BexId, CAST(libr.conciliado AS BIT) AS Conciliado, conl.bcl_grupo AS Grupo,
		   DATEDIFF(DAY, libr.asi_fecha, @corte) AS Dias,
		   CAST(IIF(libr.conciliado = 0 AND DATEDIFF(DAY, libr.asi_fecha, @corte) > IIF(libr.asd_debe > 0, @dias_deposito, @dias_cheque), 1, 0) AS BIT) AS Revisar
	FROM dbo.fnConciliacionLibros(@BcnId) libr
	LEFT JOIN dbo.bco_conciliacion_libro conl ON conl.asd_id = libr.asd_id
	ORDER BY libr.asi_fecha, libr.asd_id;
END;
GO

------------------------------------------------------------
-- 4. Conciliación automática con la tolerancia del parámetro
------------------------------------------------------------
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
	DECLARE @tolerancia INT = ISNULL((SELECT bcp_tolerancia_dias FROM dbo.bco_conciliacion_parametro WHERE bcp_id = 1), 5);

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
			  AND ABS(DATEDIFF(DAY, fecha, @fecha)) <= @tolerancia
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

------------------------------------------------------------
-- 5. Ajuste: una línea sin clasificar exige la cuenta
------------------------------------------------------------
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
	-- La cuenta por omisión solo para lo reconocido (comisión o interés).
	IF @CtaId IS NULL AND dbo.fnConciliacionClase(@texto, @debito, @credito) = 'SIN_CLASIFICAR'
		THROW 55422, 'No se reconoce qué es esta línea del banco: elija la cuenta contable del ajuste (por ejemplo, un cheque rechazado o una nota de débito no es una comisión).', 1;
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

------------------------------------------------------------
-- 6. Emparejar varios con uno
------------------------------------------------------------
-- @Extracto y @Libros: listas de ids separadas por comas. Lo del banco
-- (créditos − débitos) debe sumar lo mismo que lo de libros (Debe − Haber).
CREATE OR ALTER PROCEDURE [dbo].[paConciliacionEmparejarGrupo]
	@BcnId		INT,
	@Extracto	VARCHAR(MAX),
	@Libros		VARCHAR(MAX)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_conciliacion WHERE bcn_id = @BcnId AND bcn_estado = 'B')
		THROW 55406, 'La conciliación no existe o ya está cerrada.', 1;

	DECLARE @bex TABLE (bex_id INT PRIMARY KEY);
	DECLARE @asd TABLE (asd_id INT PRIMARY KEY);
	INSERT INTO @bex SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@Extracto, ',') WHERE TRY_CAST(value AS INT) IS NOT NULL;
	INSERT INTO @asd SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@Libros, ',') WHERE TRY_CAST(value AS INT) IS NOT NULL;
	IF NOT EXISTS (SELECT 1 FROM @bex) OR NOT EXISTS (SELECT 1 FROM @asd) OR (SELECT COUNT(*) FROM @bex) + (SELECT COUNT(*) FROM @asd) < 3
		THROW 55423, 'Elija al menos una línea del banco y un movimiento de libros, y más de uno en alguno de los dos lados.', 1;
	IF EXISTS (SELECT 1 FROM @bex lst LEFT JOIN dbo.bco_extracto extr ON extr.bex_id = lst.bex_id AND extr.bcn_id = @BcnId AND extr.asd_id IS NULL
			   WHERE extr.bex_id IS NULL)
		THROW 55424, 'Una de las líneas del banco elegidas no existe o ya está conciliada.', 1;
	IF EXISTS (SELECT 1 FROM @asd lst LEFT JOIN dbo.fnConciliacionLibros(@BcnId) libr ON libr.asd_id = lst.asd_id AND libr.conciliado = 0
			   WHERE libr.asd_id IS NULL)
		THROW 55425, 'Uno de los movimientos de libros elegidos no existe o ya está conciliado.', 1;

	DECLARE @banco NUMERIC(16, 2) = (SELECT SUM(extr.bex_credito - extr.bex_debito) FROM dbo.bco_extracto extr INNER JOIN @bex lst ON lst.bex_id = extr.bex_id);
	DECLARE @libro NUMERIC(16, 2) = (SELECT SUM(libr.asd_debe - libr.asd_haber) FROM dbo.fnConciliacionLibros(@BcnId) libr INNER JOIN @asd lst ON lst.asd_id = libr.asd_id);
	IF @banco <> @libro OR @banco = 0
	BEGIN
		DECLARE @mensaje NVARCHAR(300) = CONCAT(N'No suman lo mismo: el banco da Q', FORMAT(@banco, 'N2'), N' y libros Q', FORMAT(@libro, 'N2'), N'.');
		THROW 55426, @mensaje, 1;
	END

	DECLARE @grupo INT = (SELECT MIN(bex_id) FROM @bex), @primero INT = (SELECT MIN(asd_id) FROM @asd);
	BEGIN TRANSACTION;
		UPDATE extr SET asd_id = @primero, bex_forma = 'G', bex_grupo = @grupo
		FROM dbo.bco_extracto extr INNER JOIN @bex lst ON lst.bex_id = extr.bex_id;
		INSERT INTO dbo.bco_conciliacion_libro (bcn_id, asd_id, bex_id, bcl_grupo)
		SELECT @BcnId, asd_id, @grupo, @grupo FROM @asd;
	COMMIT TRANSACTION;
END;
GO

-- Igual que en 64; si la línea o el movimiento está en un grupo, se deshace
-- todo el grupo.
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
	DECLARE @grupo INT = COALESCE((SELECT bex_grupo FROM dbo.bco_extracto WHERE bex_id = @BexId AND bcn_id = @BcnId),
								  (SELECT bcl_grupo FROM dbo.bco_conciliacion_libro WHERE asd_id = @AsdId AND bcn_id = @BcnId));
	BEGIN TRANSACTION;
	IF @grupo IS NOT NULL
	BEGIN
		UPDATE dbo.bco_extracto SET asd_id = NULL, bex_forma = NULL, bex_grupo = NULL WHERE bcn_id = @BcnId AND bex_grupo = @grupo;
		DELETE FROM dbo.bco_conciliacion_libro WHERE bcn_id = @BcnId AND bcl_grupo = @grupo;
	END
	ELSE
	BEGIN
		IF @AsdId IS NULL
			SELECT @AsdId = asd_id FROM dbo.bco_extracto WHERE bex_id = @BexId AND bcn_id = @BcnId;
		UPDATE dbo.bco_extracto SET asd_id = NULL, bex_forma = NULL WHERE bcn_id = @BcnId AND (bex_id = @BexId OR asd_id = @AsdId);
		DELETE FROM dbo.bco_conciliacion_libro WHERE bcn_id = @BcnId AND asd_id = @AsdId;
	END
	COMMIT TRANSACTION;
END;
GO
