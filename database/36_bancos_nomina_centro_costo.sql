------------------------------------------------------------------------------
-- 36_bancos_nomina_centro_costo.sql
--
-- Fase A del segundo bloque de requerimientos:
--
--   1. Bancos (solo administrador y contador: permiso BANCOS_ADMIN).
--      * Cuentas bancarias con tipo (monetaria/ahorro) y su cuenta contable;
--        si no tiene, se usa el concepto PAGO_BANCOS.
--      * Chequeras por cuenta (rangos sin traslape, siguiente número).
--      * Motivos de pago.
--      * Cheques de todos los tipos en una sola consulta:
--            P = pago a proveedor (se sigue emitiendo desde CxP > Pagos)
--            L = cheque libre con beneficiario, motivo y cuenta de gasto
--            N = pago de nómina
--        El cheque libre genera su partida (Debe gasto / Haber banco) con
--        origen CHEQUE. Anular un cheque anula su partida; si era de
--        proveedor devuelve el saldo a la cuota y si era de nómina el
--        empleado vuelve a quedar pendiente de pago.
--
--   2. Centro de costo = departamento.
--      * cont_asiento_det.IdDepartamento: cada línea de partida puede llevar
--        su centro de costo.
--      * Nuevo tipo cont_asiento_det_cc_type y paContabilidadAsientoInsertarCc
--        (el tipo y el procedimiento anteriores quedan intactos).
--      * La nómina aprobada desglosa sus gastos por departamento.
--      * Reporte de gasto por centro de costo (permiso CONTABILIDAD_CENTRO_COSTO).
--
--   3. Nómina por período.
--      * Tipo semanal (S), quincenal (Q) o mensual (M). Cada empleado
--        pertenece a un tipo de nómina y solo entra en las de su tipo.
--      * paRrhhNominaPeriodoSugerido propone el siguiente período del tipo
--        elegido (semana lunes-domingo, quincena 1-15 / 16-fin, mes).
--      * Solo se valida traslape entre nóminas del mismo tipo.
--
--   4. Pago de nómina por empleado (no se paga en efectivo).
--      * Cada empleado tiene forma de pago (T = transferencia, C = cheque),
--        entidad financiera, tipo y número de cuenta.
--      * Transferencias: un pago por lote con su listado por banco y una
--        partida (Debe NOMINA_SUELDOS_POR_PAGAR / Haber banco).
--      * Cheques: uno por empleado desde la chequera elegida, con su partida.
--      * Una nómina con pagos vigentes no se puede anular.
--
-- Requiere 25, 29 y 34. Se puede volver a correr.
------------------------------------------------------------------------------

USE [erp_db];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Nuevos orígenes de partida
------------------------------------------------------------
IF OBJECT_ID('dbo.CK_cont_asiento_enc_origen', 'C') IS NOT NULL
	ALTER TABLE dbo.cont_asiento_enc DROP CONSTRAINT [CK_cont_asiento_enc_origen];
ALTER TABLE dbo.cont_asiento_enc ADD CONSTRAINT [CK_cont_asiento_enc_origen]
	CHECK ([asi_origen] IN ('MANUAL','VENTA','COMPRA','PAGO_CLIENTE','PAGO_PROVEEDOR','DEPOSITO','CIERRE_CAJA','NOMINA',
							'NOTA_CREDITO','NOTA_DEBITO',		-- 32
							'CHEQUE','PAGO_NOMINA',				-- 36
							'AJUSTE_INVENTARIO','APERTURA'));	-- 38
GO

------------------------------------------------------------
-- 2. Centro de costo en la línea de partida
------------------------------------------------------------
IF COL_LENGTH('dbo.cont_asiento_det', 'IdDepartamento') IS NULL
	ALTER TABLE dbo.cont_asiento_det ADD [IdDepartamento] INT NULL;	-- centro de costo
GO
IF OBJECT_ID('dbo.FK_cont_asiento_det_departamento', 'F') IS NULL
	ALTER TABLE dbo.cont_asiento_det ADD CONSTRAINT [FK_cont_asiento_det_departamento]
		FOREIGN KEY ([IdDepartamento]) REFERENCES dbo.rrhhDepartamento ([IdDepartamento]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cont_asiento_det_departamento' AND object_id = OBJECT_ID('dbo.cont_asiento_det'))
	CREATE INDEX [IX_cont_asiento_det_departamento] ON dbo.cont_asiento_det ([IdDepartamento], [cta_id]) WHERE [IdDepartamento] IS NOT NULL;
GO

IF TYPE_ID(N'dbo.cont_asiento_det_cc_type') IS NULL
CREATE TYPE [dbo].[cont_asiento_det_cc_type] AS TABLE
(
	[cta_id]			INT				NOT NULL,
	[asd_debe]			DECIMAL(14, 2)	NOT NULL DEFAULT (0),
	[asd_haber]			DECIMAL(14, 2)	NOT NULL DEFAULT (0),
	[asd_descripcion]	VARCHAR(256)	NULL,
	[IdDepartamento]	INT				NULL
);
GO

-- Igual que sp_contabilidad_insertar_asiento, con centro de costo por línea.
CREATE OR ALTER PROCEDURE [dbo].[paContabilidadAsientoInsertarCc]
	@asi_fecha			DATE,
	@asi_descripcion	VARCHAR(256) = NULL,
	@asi_origen			VARCHAR(20) = 'MANUAL',
	@enc_id				INT = NULL,
	@usu_id				INT = NULL,
	@detalle			dbo.cont_asiento_det_cc_type READONLY,
	@asi_id				INT OUTPUT,
	@asi_origen_id		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @detalle)
		THROW 51301, 'El asiento debe tener al menos una línea.', 1;
	IF (SELECT ISNULL(SUM(asd_debe), 0) FROM @detalle) <> (SELECT ISNULL(SUM(asd_haber), 0) FROM @detalle)
		THROW 51302, 'El asiento no está balanceado: la suma del Debe debe ser igual a la suma del Haber.', 1;

	DECLARE @pdo_id INT;
	EXEC dbo.sp_contabilidad_obtener_o_crear_periodo @fecha = @asi_fecha, @usu_id = @usu_id, @pdo_id = @pdo_id OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.cont_asiento_enc
			(asi_fecha, asi_descripcion, asi_origen, asi_origen_id, enc_id, pdo_id, usu_id, InsUsuario, InsFechaHora)
		VALUES
			(@asi_fecha, @asi_descripcion, @asi_origen, @asi_origen_id, @enc_id, @pdo_id, @usu_id, @usu_id, SYSDATETIME());
		SET @asi_id = SCOPE_IDENTITY();

		INSERT INTO dbo.cont_asiento_det (asi_id, cta_id, asd_debe, asd_haber, asd_descripcion, IdDepartamento, InsUsuario, InsFechaHora)
		SELECT @asi_id, cta_id, asd_debe, asd_haber, asd_descripcion, IdDepartamento, @usu_id, SYSDATETIME()
		FROM @detalle;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Departamento (centro de costo) actual de un empleado, a través de su plaza.
CREATE OR ALTER FUNCTION [dbo].[fnRrhhEmpleadoDepartamento] (@IdEmpleado INT)
RETURNS INT
AS
BEGIN
	RETURN (SELECT depu.IdDepartamento
			FROM dbo.rrhhEmpleado empl
			INNER JOIN dbo.rrhhPlaza plaz ON plaz.IdPlaza = empl.IdPlaza
			INNER JOIN dbo.rrhhDepartamentoPuesto depu ON depu.IdDepartamentoPuesto = plaz.IdDepartamentoPuesto
			WHERE empl.IdEmpleado = @IdEmpleado);
END;
GO

-- Gasto por centro de costo: saldo por departamento y cuenta en el rango.
CREATE OR ALTER PROCEDURE [dbo].[paContabilidadCentroCostoConsultar]
	@Desde			DATE,
	@Hasta			DATE,
	@IdDepartamento	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT depa.IdDepartamento, depa.Descripcion AS Departamento,
		   cuen.cta_id AS CtaId, cuen.cta_codigo AS CuentaCodigo, cuen.cta_nombre AS CuentaNombre,
		   SUM(deta.asd_debe) AS Debe, SUM(deta.asd_haber) AS Haber, SUM(deta.asd_debe - deta.asd_haber) AS Saldo,
		   COUNT(DISTINCT asie.asi_id) AS Partidas
	FROM dbo.cont_asiento_det deta
	INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id
	INNER JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = deta.IdDepartamento
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = deta.cta_id
	WHERE asie.asi_estado = 'A'
	  AND asie.asi_fecha BETWEEN @Desde AND @Hasta
	  AND (@IdDepartamento IS NULL OR deta.IdDepartamento = @IdDepartamento)
	GROUP BY depa.IdDepartamento, depa.Descripcion, cuen.cta_id, cuen.cta_codigo, cuen.cta_nombre
	ORDER BY depa.Descripcion, cuen.cta_codigo;
END;
GO

-- Líneas de partida de un centro de costo (y opcionalmente una cuenta).
CREATE OR ALTER PROCEDURE [dbo].[paContabilidadCentroCostoDetalle]
	@Desde			DATE,
	@Hasta			DATE,
	@IdDepartamento	INT,
	@CtaId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT asie.asi_id AS AsiId, asie.asi_fecha AS Fecha, asie.asi_origen AS Origen, asie.asi_descripcion AS Partida,
		   cuen.cta_codigo AS CuentaCodigo, cuen.cta_nombre AS CuentaNombre,
		   deta.asd_descripcion AS Descripcion, deta.asd_debe AS Debe, deta.asd_haber AS Haber
	FROM dbo.cont_asiento_det deta
	INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = deta.cta_id
	WHERE asie.asi_estado = 'A'
	  AND asie.asi_fecha BETWEEN @Desde AND @Hasta
	  AND deta.IdDepartamento = @IdDepartamento
	  AND (@CtaId IS NULL OR deta.cta_id = @CtaId)
	ORDER BY asie.asi_fecha, asie.asi_id, deta.asd_id;
END;
GO

------------------------------------------------------------
-- 3. Bancos: columnas nuevas
------------------------------------------------------------
IF COL_LENGTH('dbo.bco_cuenta_bancaria', 'bcb_tipo') IS NULL
	ALTER TABLE dbo.bco_cuenta_bancaria ADD [bcb_tipo] CHAR(1) NOT NULL
		CONSTRAINT [DF_bco_cuenta_bancaria_tipo] DEFAULT ('M');	-- M = monetaria, A = ahorro
GO
IF COL_LENGTH('dbo.bco_cuenta_bancaria', 'cta_id') IS NULL
	ALTER TABLE dbo.bco_cuenta_bancaria ADD [cta_id] INT NULL;	-- cuenta contable del banco
GO
IF OBJECT_ID('dbo.CK_bco_cuenta_bancaria_tipo', 'C') IS NULL
	ALTER TABLE dbo.bco_cuenta_bancaria ADD CONSTRAINT [CK_bco_cuenta_bancaria_tipo] CHECK ([bcb_tipo] IN ('M','A'));
IF OBJECT_ID('dbo.FK_bco_cuenta_bancaria_cuenta_contable', 'F') IS NULL
	ALTER TABLE dbo.bco_cuenta_bancaria ADD CONSTRAINT [FK_bco_cuenta_bancaria_cuenta_contable]
		FOREIGN KEY ([cta_id]) REFERENCES dbo.cont_cuenta_contable ([cta_id]);
GO
-- Las cuentas que ya existían quedan con la cuenta contable del concepto PAGO_BANCOS.
UPDATE dbo.bco_cuenta_bancaria
   SET cta_id = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'PAGO_BANCOS')
 WHERE cta_id IS NULL;
GO

IF COL_LENGTH('dbo.bco_cheque_emitido_enc', 'bce_tipo') IS NULL
	ALTER TABLE dbo.bco_cheque_emitido_enc ADD [bce_tipo] CHAR(1) NOT NULL
		CONSTRAINT [DF_bco_cheque_emitido_enc_tipo] DEFAULT ('P');	-- P = proveedor, L = libre, N = nómina
GO
IF COL_LENGTH('dbo.bco_cheque_emitido_enc', 'bce_beneficiario') IS NULL
	ALTER TABLE dbo.bco_cheque_emitido_enc ADD [bce_beneficiario] VARCHAR(150) NULL;
IF COL_LENGTH('dbo.bco_cheque_emitido_enc', 'cta_id') IS NULL
	ALTER TABLE dbo.bco_cheque_emitido_enc ADD [cta_id] INT NULL;			-- cuenta del Debe (cheque libre)
IF COL_LENGTH('dbo.bco_cheque_emitido_enc', 'IdDepartamento') IS NULL
	ALTER TABLE dbo.bco_cheque_emitido_enc ADD [IdDepartamento] INT NULL;	-- centro de costo (cheque libre)
IF COL_LENGTH('dbo.bco_cheque_emitido_enc', 'IdNominaEmpleado') IS NULL
	ALTER TABLE dbo.bco_cheque_emitido_enc ADD [IdNominaEmpleado] INT NULL;	-- cheque de nómina
IF COL_LENGTH('dbo.bco_cheque_emitido_enc', 'bce_fecha_cobro') IS NULL
	ALTER TABLE dbo.bco_cheque_emitido_enc ADD [bce_fecha_cobro] DATE NULL;
GO
IF OBJECT_ID('dbo.CK_bco_cheque_emitido_enc_tipo', 'C') IS NULL
	ALTER TABLE dbo.bco_cheque_emitido_enc ADD CONSTRAINT [CK_bco_cheque_emitido_enc_tipo] CHECK ([bce_tipo] IN ('P','L','N'));
IF OBJECT_ID('dbo.FK_bco_cheque_emitido_enc_cuenta_contable', 'F') IS NULL
	ALTER TABLE dbo.bco_cheque_emitido_enc ADD CONSTRAINT [FK_bco_cheque_emitido_enc_cuenta_contable]
		FOREIGN KEY ([cta_id]) REFERENCES dbo.cont_cuenta_contable ([cta_id]);
IF OBJECT_ID('dbo.FK_bco_cheque_emitido_enc_departamento', 'F') IS NULL
	ALTER TABLE dbo.bco_cheque_emitido_enc ADD CONSTRAINT [FK_bco_cheque_emitido_enc_departamento]
		FOREIGN KEY ([IdDepartamento]) REFERENCES dbo.rrhhDepartamento ([IdDepartamento]);
IF OBJECT_ID('dbo.FK_bco_cheque_emitido_enc_nomina_empleado', 'F') IS NULL
	ALTER TABLE dbo.bco_cheque_emitido_enc ADD CONSTRAINT [FK_bco_cheque_emitido_enc_nomina_empleado]
		FOREIGN KEY ([IdNominaEmpleado]) REFERENCES dbo.rrhhNominaEmpleado ([IdNominaEmpleado]);
GO
-- Beneficiario de los cheques a proveedor que ya existían.
UPDATE cheq SET bce_beneficiario = prov.prv_nombre_comercial
FROM dbo.bco_cheque_emitido_enc cheq
CROSS APPLY (SELECT TOP 1 chdt.enc_id FROM dbo.bco_cheque_emitido_det chdt WHERE chdt.bce_id = cheq.bce_id) chdt
INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = chdt.enc_id
INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = docu.prv_id
WHERE cheq.bce_beneficiario IS NULL AND cheq.bce_tipo = 'P';
GO

-- Motivo para los cheques de nómina (catálogo).
IF NOT EXISTS (SELECT 1 FROM dbo.bco_motivo_pago WHERE bmp_descripcion = 'Pago de nómina')
	INSERT INTO dbo.bco_motivo_pago (bmp_descripcion) VALUES ('Pago de nómina');
GO

------------------------------------------------------------
-- 4. Bancos: funciones
------------------------------------------------------------
-- Cuenta contable de una cuenta bancaria (o la del concepto PAGO_BANCOS).
CREATE OR ALTER FUNCTION [dbo].[fnBcoCuentaContable] (@BcbId INT)
RETURNS INT
AS
BEGIN
	RETURN COALESCE((SELECT cta_id FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId),
					(SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'PAGO_BANCOS'));
END;
GO

-- Siguiente número libre de una chequera (NULL si ya se agotó). Los cheques
-- anulados consumen su número.
CREATE OR ALTER FUNCTION [dbo].[fnBcoChequeSiguiente] (@CbcId INT)
RETURNS INT
AS
BEGIN
	DECLARE @del INT, @al INT, @siguiente INT;
	SELECT @del = cbc_cheque_del, @al = cbc_cheque_al FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @CbcId;
	IF @del IS NULL RETURN NULL;
	SELECT @siguiente = ISNULL(MAX(TRY_CAST(bce_numero_cheque AS INT)), @del - 1) + 1
	FROM dbo.bco_cheque_emitido_enc
	WHERE cbc_id = @CbcId AND TRY_CAST(bce_numero_cheque AS INT) BETWEEN @del AND @al;
	RETURN CASE WHEN @siguiente > @al THEN NULL ELSE @siguiente END;
END;
GO

------------------------------------------------------------
-- 5. Bancos: cuentas bancarias
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paBcoCuentaBancariaConsultar]
	@SoloActivas BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cuba.bcb_id AS BcbId, cuba.bcb_numero_cuenta AS NumeroCuenta, cuba.bcb_descripcion AS Descripcion,
		   cuba.gef_id AS GefId, enti.gef_descripcion AS Banco, cuba.bcb_tipo AS Tipo,
		   cuba.cta_id AS CtaId, cuen.cta_codigo AS CuentaCodigo, cuen.cta_nombre AS CuentaNombre,
		   cuba.bcb_estado AS Estado,
		   (SELECT COUNT(*) FROM dbo.bco_cuenta_bancaria_chequera cheq WHERE cheq.bcb_id = cuba.bcb_id AND cheq.cbc_estado = 'A') AS ChequerasActivas
	FROM dbo.bco_cuenta_bancaria cuba
	INNER JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuba.gef_id
	LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = cuba.cta_id
	WHERE @SoloActivas = 0 OR cuba.bcb_estado = 'A'
	ORDER BY enti.gef_descripcion, cuba.bcb_numero_cuenta;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBcoCuentaBancariaGuardar]
	@BcbId			INT = NULL,
	@NumeroCuenta	VARCHAR(16),
	@Descripcion	VARCHAR(64) = NULL,
	@GefId			INT,
	@Tipo			CHAR(1),
	@CtaId			INT = NULL,
	@Estado			CHAR(1) = 'A',
	@UsuId			INT,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET @NumeroCuenta = LTRIM(RTRIM(ISNULL(@NumeroCuenta, '')));
	IF @NumeroCuenta = ''
		THROW 53401, 'Ingrese el número de cuenta.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_numero_cuenta = @NumeroCuenta AND bcb_id <> ISNULL(@BcbId, 0))
		THROW 53402, 'Ya existe una cuenta bancaria con ese número.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_entidad_financiera enti
				   INNER JOIN dbo.gen_entidad_financiera_tipo tipo ON tipo.geft_id = enti.geft_id
				   WHERE enti.gef_id = @GefId AND tipo.geft_descripcion = 'Banco')
		THROW 53403, 'Elija un banco (entidad financiera de tipo Banco).', 1;
	IF @Tipo NOT IN ('M','A')
		THROW 53405, 'El tipo de cuenta debe ser monetaria o de ahorro.', 1;
	IF @CtaId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId AND cta_estado = 'A' AND cta_acepta_movimiento = 1)
		THROW 53404, 'La cuenta contable debe existir, estar activa y aceptar movimientos.', 1;

	IF @BcbId IS NULL
	BEGIN
		INSERT INTO dbo.bco_cuenta_bancaria (bcb_numero_cuenta, bcb_descripcion, gef_id, bcb_tipo, cta_id, bcb_estado, InsUsuario, InsFechaHora)
		VALUES (@NumeroCuenta, NULLIF(LTRIM(RTRIM(@Descripcion)), ''), @GefId, @Tipo, @CtaId, ISNULL(@Estado, 'A'), @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId)
			THROW 53406, 'La cuenta bancaria indicada no existe.', 1;
		UPDATE dbo.bco_cuenta_bancaria
		   SET bcb_numero_cuenta = @NumeroCuenta, bcb_descripcion = NULLIF(LTRIM(RTRIM(@Descripcion)), ''), gef_id = @GefId,
			   bcb_tipo = @Tipo, cta_id = @CtaId, bcb_estado = ISNULL(@Estado, bcb_estado),
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE bcb_id = @BcbId;
		SET @IdResultado = @BcbId;
	END
END;
GO

------------------------------------------------------------
-- 6. Bancos: chequeras
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paBcoChequeraConsultar]
	@BcbId			INT = NULL,
	@SoloActivas	BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cheq.cbc_id AS CbcId, cheq.bcb_id AS BcbId, CONCAT(enti.gef_descripcion, ' ', cuba.bcb_numero_cuenta) AS Cuenta,
		   cheq.cbc_cheque_del AS ChequeDel, cheq.cbc_cheque_al AS ChequeAl, cheq.cbc_fecha_recepcion_chequera AS FechaRecepcion,
		   cheq.cbc_estado AS Estado, emit.Emitidos,
		   dbo.fnBcoChequeSiguiente(cheq.cbc_id) AS Siguiente,
		   CASE WHEN dbo.fnBcoChequeSiguiente(cheq.cbc_id) IS NULL THEN 0
				ELSE cheq.cbc_cheque_al - dbo.fnBcoChequeSiguiente(cheq.cbc_id) + 1 END AS Disponibles
	FROM dbo.bco_cuenta_bancaria_chequera cheq
	INNER JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = cheq.bcb_id
	INNER JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuba.gef_id
	CROSS APPLY (SELECT COUNT(*) AS Emitidos FROM dbo.bco_cheque_emitido_enc emit WHERE emit.cbc_id = cheq.cbc_id) emit
	WHERE (@BcbId IS NULL OR cheq.bcb_id = @BcbId)
	  AND (@SoloActivas = 0 OR (cheq.cbc_estado = 'A' AND cuba.bcb_estado = 'A'))
	ORDER BY enti.gef_descripcion, cuba.bcb_numero_cuenta, cheq.cbc_cheque_del;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBcoChequeraGuardar]
	@CbcId			INT = NULL,
	@BcbId			INT,
	@ChequeDel		INT,
	@ChequeAl		INT,
	@FechaRecepcion	DATE = NULL,
	@Estado			CHAR(1) = 'A',
	@UsuId			INT,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId)
		THROW 53406, 'La cuenta bancaria indicada no existe.', 1;
	IF ISNULL(@ChequeDel, 0) <= 0 OR ISNULL(@ChequeAl, 0) < @ChequeDel
		THROW 53407, 'El rango de cheques no es válido: el número final debe ser mayor o igual al inicial y ambos mayores a cero.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria_chequera
			   WHERE bcb_id = @BcbId AND cbc_id <> ISNULL(@CbcId, 0)
				 AND cbc_cheque_del <= @ChequeAl AND cbc_cheque_al >= @ChequeDel)
		THROW 53408, 'El rango se traslapa con otra chequera de la misma cuenta.', 1;

	IF @CbcId IS NULL
	BEGIN
		INSERT INTO dbo.bco_cuenta_bancaria_chequera (bcb_id, cbc_cheque_del, cbc_cheque_al, cbc_fecha_recepcion_chequera, cbc_estado, InsUsuario, InsFechaHora)
		VALUES (@BcbId, @ChequeDel, @ChequeAl, @FechaRecepcion, ISNULL(@Estado, 'A'), @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @CbcId)
			THROW 53410, 'La chequera indicada no existe.', 1;
		IF EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_enc WHERE cbc_id = @CbcId)
		   AND (EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @CbcId AND bcb_id <> @BcbId)
				OR EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_enc
						   WHERE cbc_id = @CbcId AND (TRY_CAST(bce_numero_cheque AS INT) IS NULL
													  OR TRY_CAST(bce_numero_cheque AS INT) NOT BETWEEN @ChequeDel AND @ChequeAl)))
			THROW 53409, 'La chequera ya tiene cheques emitidos: no se puede cambiar de cuenta ni dejar cheques emitidos fuera del rango.', 1;
		UPDATE dbo.bco_cuenta_bancaria_chequera
		   SET bcb_id = @BcbId, cbc_cheque_del = @ChequeDel, cbc_cheque_al = @ChequeAl, cbc_fecha_recepcion_chequera = @FechaRecepcion,
			   cbc_estado = ISNULL(@Estado, cbc_estado), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE cbc_id = @CbcId;
		SET @IdResultado = @CbcId;
	END
END;
GO

------------------------------------------------------------
-- 7. Bancos: motivos de pago
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paBcoMotivoPagoConsultar]
	@SoloActivos BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT moti.bmp_id AS BmpId, moti.bmp_descripcion AS Descripcion, moti.bmp_estado AS Estado,
		   (SELECT COUNT(*) FROM dbo.bco_cheque_emitido_enc cheq WHERE cheq.bmp_id = moti.bmp_id) AS Cheques
	FROM dbo.bco_motivo_pago moti
	WHERE @SoloActivos = 0 OR moti.bmp_estado = 'A'
	ORDER BY moti.bmp_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBcoMotivoPagoGuardar]
	@BmpId			INT = NULL,
	@Descripcion	VARCHAR(64),
	@Estado			CHAR(1) = 'A',
	@UsuId			INT,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET @Descripcion = LTRIM(RTRIM(ISNULL(@Descripcion, '')));
	IF @Descripcion = ''
		THROW 53411, 'Ingrese la descripción del motivo.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_motivo_pago WHERE bmp_descripcion = @Descripcion AND bmp_id <> ISNULL(@BmpId, 0))
		THROW 53412, 'Ya existe un motivo con esa descripción.', 1;

	IF @BmpId IS NULL
	BEGIN
		INSERT INTO dbo.bco_motivo_pago (bmp_descripcion, bmp_estado, InsUsuario, InsFechaHora)
		VALUES (@Descripcion, ISNULL(@Estado, 'A'), @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.bco_motivo_pago
		   SET bmp_descripcion = @Descripcion, bmp_estado = ISNULL(@Estado, bmp_estado), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE bmp_id = @BmpId;
		SET @IdResultado = @BmpId;
	END
END;
GO

------------------------------------------------------------
-- 8. Bancos: cheques
------------------------------------------------------------
-- Valida chequera y número; si @Numero viene vacío toma el siguiente.
CREATE OR ALTER PROCEDURE [dbo].[paBcoChequeValidarNumero]
	@CbcId	INT,
	@Numero	VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @del INT, @al INT;
	SELECT @del = cheq.cbc_cheque_del, @al = cheq.cbc_cheque_al
	FROM dbo.bco_cuenta_bancaria_chequera cheq
	INNER JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = cheq.bcb_id
	WHERE cheq.cbc_id = @CbcId AND cheq.cbc_estado = 'A' AND cuba.bcb_estado = 'A';
	IF @del IS NULL
		THROW 53413, 'La chequera no existe o está inactiva (ella o su cuenta bancaria).', 1;

	SET @Numero = NULLIF(LTRIM(RTRIM(@Numero)), '');
	IF @Numero IS NULL
	BEGIN
		SET @Numero = CAST(dbo.fnBcoChequeSiguiente(@CbcId) AS VARCHAR(16));
		IF @Numero IS NULL
			THROW 53414, 'La chequera ya no tiene cheques disponibles; registre una nueva.', 1;
	END
	IF TRY_CAST(@Numero AS INT) IS NULL OR TRY_CAST(@Numero AS INT) NOT BETWEEN @del AND @al
	BEGIN
		DECLARE @mensaje NVARCHAR(200) = CONCAT(N'El número de cheque debe estar entre ', @del, N' y ', @al, N'.');
		THROW 53414, @mensaje, 1;
	END
	SET @Numero = CAST(TRY_CAST(@Numero AS INT) AS VARCHAR(16));
	IF EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_enc WHERE cbc_id = @CbcId AND bce_numero_cheque = @Numero)
		THROW 51607, 'Ese número de cheque ya fue emitido en la chequera.', 1;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBcoChequesConsultar]
	@BcbId	INT = NULL,
	@Tipo	CHAR(1) = NULL,
	@Estado	CHAR(1) = NULL,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cheq.bce_id AS BceId, cheq.bce_tipo AS Tipo, cheq.bce_fecha_emision AS Fecha, cheq.bce_numero_cheque AS Numero,
		   cuba.bcb_id AS BcbId, CONCAT(enti.gef_descripcion, ' ', cuba.bcb_numero_cuenta) AS Cuenta,
		   cheq.bce_beneficiario AS Beneficiario, moti.bmp_descripcion AS Motivo,
		   cuen.cta_codigo AS CuentaCodigo, cuen.cta_nombre AS CuentaNombre, depa.Descripcion AS Departamento,
		   cheq.bce_valor AS Valor, cheq.bce_estado_cheque AS EstadoCheque, cheq.bce_fecha_cobro AS FechaCobro,
		   cheq.bce_observaciones AS Observaciones, usua.usu_usuario AS Usuario,
		   nomi.Descripcion AS Nomina
	FROM dbo.bco_cheque_emitido_enc cheq
	INNER JOIN dbo.bco_cuenta_bancaria_chequera cheqra ON cheqra.cbc_id = cheq.cbc_id
	INNER JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = cheqra.bcb_id
	INNER JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuba.gef_id
	LEFT JOIN dbo.bco_motivo_pago moti ON moti.bmp_id = cheq.bmp_id
	LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = cheq.cta_id
	LEFT JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = cheq.IdDepartamento
	LEFT JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = cheq.IdNominaEmpleado
	LEFT JOIN dbo.rrhhNomina nomi ON nomi.IdNomina = nemp.IdNomina
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = cheq.usu_id
	WHERE (@BcbId IS NULL OR cuba.bcb_id = @BcbId)
	  AND (@Tipo IS NULL OR cheq.bce_tipo = @Tipo)
	  AND (@Estado IS NULL OR cheq.bce_estado_cheque = @Estado)
	  AND (@Desde IS NULL OR cheq.bce_fecha_emision >= @Desde)
	  AND (@Hasta IS NULL OR cheq.bce_fecha_emision <= @Hasta)
	ORDER BY cheq.bce_fecha_emision DESC, cheq.bce_id DESC;
END;
GO

-- Cheque libre: beneficiario, motivo y cuenta de gasto (con centro de costo
-- opcional). Partida: Debe cuenta elegida / Haber cuenta del banco.
CREATE OR ALTER PROCEDURE [dbo].[paBcoChequeEmitirLibre]
	@CbcId			INT,
	@Numero			VARCHAR(16) = NULL,
	@Fecha			DATE = NULL,
	@Beneficiario	VARCHAR(150),
	@BmpId			INT,
	@CtaId			INT,
	@IdDepartamento	INT = NULL,
	@Valor			NUMERIC(12, 2),
	@Observaciones	VARCHAR(250) = NULL,
	@UsuId			INT,
	@BceId			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));
	SET @Beneficiario = LTRIM(RTRIM(ISNULL(@Beneficiario, '')));
	IF LEN(@Beneficiario) < 3
		THROW 53416, 'Ingrese el nombre del beneficiario del cheque.', 1;
	IF ISNULL(@Valor, 0) <= 0
		THROW 51601, 'El valor del cheque debe ser mayor a cero.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_motivo_pago WHERE bmp_id = @BmpId AND bmp_estado = 'A')
		THROW 53418, 'Elija un motivo de pago activo.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId AND cta_estado = 'A' AND cta_acepta_movimiento = 1)
		THROW 53404, 'La cuenta contable debe existir, estar activa y aceptar movimientos.', 1;
	IF @IdDepartamento IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.rrhhDepartamento WHERE IdDepartamento = @IdDepartamento AND Estado = 'A')
		THROW 53419, 'El centro de costo (departamento) no existe o está inactivo.', 1;

	EXEC dbo.paBcoChequeValidarNumero @CbcId = @CbcId, @Numero = @Numero OUTPUT;

	DECLARE @cta_banco INT = dbo.fnBcoCuentaContable((SELECT bcb_id FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @CbcId));
	IF @cta_banco IS NULL
		EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_banco OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.bco_cheque_emitido_enc
			(cbc_id, bce_fecha_emision, usu_id, bce_numero_cheque, bce_observaciones, bce_valor, bmp_id,
			 bce_tipo, bce_beneficiario, cta_id, IdDepartamento, InsUsuario, InsFechaHora)
		VALUES
			(@CbcId, @Fecha, @UsuId, @Numero, NULLIF(LTRIM(RTRIM(@Observaciones)), ''), @Valor, @BmpId,
			 'L', @Beneficiario, @CtaId, @IdDepartamento, @UsuId, SYSDATETIME());
		SET @BceId = SCOPE_IDENTITY();

		DECLARE @partida dbo.cont_asiento_det_cc_type, @asi_id INT;
		DECLARE @referencia VARCHAR(256) = LEFT(CONCAT('Cheque ', @Numero, ' a ', @Beneficiario), 256);
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion, IdDepartamento)
		VALUES (@CtaId, @Valor, 0, @referencia, @IdDepartamento),
			   (@cta_banco, 0, @Valor, @referencia, NULL);

		EXEC dbo.paContabilidadAsientoInsertarCc
			@asi_fecha = @Fecha, @asi_descripcion = @referencia, @asi_origen = 'CHEQUE', @asi_origen_id = @BceId,
			@usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Marca un cheque como cobrado (el banco lo pagó).
CREATE OR ALTER PROCEDURE [dbo].[paBcoChequeCobrar]
	@BceId	INT,
	@Fecha	DATE = NULL,
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_enc WHERE bce_id = @BceId AND bce_estado_cheque = 'E')
		THROW 53424, 'Solo se puede marcar como cobrado un cheque emitido (no anulado ni ya cobrado).', 1;
	UPDATE dbo.bco_cheque_emitido_enc
	   SET bce_estado_cheque = 'C', bce_fecha_cobro = ISNULL(@Fecha, CAST(GETDATE() AS DATE)), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE bce_id = @BceId;
END;
GO

------------------------------------------------------------
-- 9. Cheque a proveedor: tipo, beneficiario y cuenta del banco
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_bancos_emitir_cheque_pago_proveedor]
	@ppg_id				INT,
	@cbc_id				INT,
	@bce_numero_cheque	VARCHAR(16),
	@valor_pago			NUMERIC(12, 2),
	@bmp_id				INT = NULL,
	@usu_id				INT = NULL,
	@bce_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @valor_pago <= 0
		THROW 51601, 'El valor del pago debe ser mayor a cero.', 1;

	DECLARE @enc_id INT, @valor_programado NUMERIC(12, 2), @valor_pagado NUMERIC(12, 2), @estado CHAR(1);
	SELECT @enc_id = enc_id, @valor_programado = ppg_valor_pago, @valor_pagado = ISNULL(ppg_valor_real_pago, 0), @estado = ppg_estado
	FROM dbo.inv_proveedor_plan_pago WHERE ppg_id = @ppg_id;

	IF @enc_id IS NULL
		THROW 51602, 'La cuota de proveedor indicada no existe.', 1;
	IF @estado = 'A' OR @valor_programado - @valor_pagado <= 0
		THROW 51603, 'La cuota de proveedor indicada ya está pagada por completo.', 1;
	IF @valor_pago > @valor_programado - @valor_pagado
	BEGIN
		DECLARE @msg NVARCHAR(200) = CONCAT(N'El pago (Q', FORMAT(@valor_pago, 'N2'), N') supera el saldo de la cuota (Q',
			FORMAT(@valor_programado - @valor_pagado, 'N2'), N').');
		THROW 51604, @msg, 1;
	END
	IF EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_id = @enc_id AND enc_estado <> 'G')
		THROW 53217, 'La compra de esa cuota está anulada.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @cbc_id)
		THROW 51606, 'La chequera indicada no existe.', 1;
	-- Chequera activa, número dentro del rango y sin repetir (vacío = siguiente).
	EXEC dbo.paBcoChequeValidarNumero @CbcId = @cbc_id, @Numero = @bce_numero_cheque OUTPUT;

	DECLARE @cta_proveedores INT, @cta_bancos INT = dbo.fnBcoCuentaContable((SELECT bcb_id FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @cbc_id));
	EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_PROVEEDORES', @CtaId = @cta_proveedores OUTPUT;
	IF @cta_bancos IS NULL
		EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_bancos OUTPUT;

	DECLARE @beneficiario VARCHAR(150) = (SELECT prov.prv_nombre_comercial FROM dbo.inv_documento_enc docu
										  INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = docu.prv_id WHERE docu.enc_id = @enc_id);

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.bco_cheque_emitido_enc
			(cbc_id, bce_fecha_emision, usu_id, bce_numero_cheque, bce_documento_ref, bce_valor, bmp_id, bce_tipo, bce_beneficiario, InsUsuario, InsFechaHora)
		VALUES
			(@cbc_id, CAST(GETDATE() AS DATE), @usu_id, @bce_numero_cheque, CAST(@enc_id AS VARCHAR(16)), @valor_pago, @bmp_id, 'P', @beneficiario, @usu_id, SYSDATETIME());

		SET @bce_id = SCOPE_IDENTITY();

		INSERT INTO dbo.bco_cheque_emitido_det (bce_id, bmp_id, enc_id, ppg_id, ced_valor, ced_abono_cancelacion, InsUsuario, InsFechaHora)
		VALUES (@bce_id, @bmp_id, @enc_id, @ppg_id, @valor_pago,
				CASE WHEN @valor_pagado + @valor_pago >= @valor_programado THEN 'C' ELSE 'A' END,
				@usu_id, SYSDATETIME());

		UPDATE dbo.inv_proveedor_plan_pago
		   SET ppg_valor_real_pago = @valor_pagado + @valor_pago,
			   ppg_fecha_real_pago = CAST(GETDATE() AS DATE),
			   ppg_numero_cheque = @bce_numero_cheque,
			   cbc_id = @cbc_id,
			   ppg_estado = CASE WHEN @valor_pagado + @valor_pago >= @valor_programado THEN 'A' ELSE ppg_estado END,
			   UpdUsuario = @usu_id,
			   UpdFechaHora = SYSDATETIME()
		 WHERE ppg_id = @ppg_id;

		DECLARE @asi_id INT, @partida dbo.cont_asiento_det_type, @fecha_hoy DATE = CAST(GETDATE() AS DATE);
		DECLARE @referencia VARCHAR(64) = 'Pago a proveedor - cheque ' + @bce_numero_cheque;
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_proveedores, @valor_pago, 0, @referencia), (@cta_bancos, 0, @valor_pago, @referencia);

		DECLARE @asi_descripcion VARCHAR(256) = 'Pago a proveedor con cheque ' + @bce_numero_cheque;
		EXEC dbo.sp_contabilidad_insertar_asiento
			@asi_fecha = @fecha_hoy, @asi_descripcion = @asi_descripcion,
			@asi_origen = 'PAGO_PROVEEDOR', @asi_origen_id = @bce_id, @enc_id = @enc_id,
			@usu_id = @usu_id, @detalle = @partida, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 10. Empleado: tipo de nómina y datos de pago
------------------------------------------------------------
IF COL_LENGTH('dbo.rrhhEmpleado', 'TipoNomina') IS NULL
BEGIN
	ALTER TABLE dbo.rrhhEmpleado ADD [TipoNomina] CHAR(1) NOT NULL
		CONSTRAINT [DF_rrhhEmpleado_TipoNomina] DEFAULT ('M');	-- S = semanal, Q = quincenal, M = mensual
	-- Solo la primera vez: los empleados que ya existían quedan en la nómina
	-- de la periodicidad de su compañía.
	EXEC ('UPDATE empl SET TipoNomina = comp.cia_periodicidad_nomina
		   FROM dbo.rrhhEmpleado empl
		   INNER JOIN dbo.gen_compania comp ON comp.cia_id = empl.cia_id');
END
GO
IF COL_LENGTH('dbo.rrhhEmpleado', 'FormaPago') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD [FormaPago] CHAR(1) NULL;		-- T = transferencia, C = cheque
IF COL_LENGTH('dbo.rrhhEmpleado', 'gef_id') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD [gef_id] INT NULL;			-- banco del empleado
IF COL_LENGTH('dbo.rrhhEmpleado', 'TipoCuenta') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD [TipoCuenta] CHAR(1) NULL;	-- M = monetaria, A = ahorro
IF COL_LENGTH('dbo.rrhhEmpleado', 'NumeroCuenta') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD [NumeroCuenta] VARCHAR(30) NULL;
GO
IF OBJECT_ID('dbo.CK_rrhhEmpleado_TipoNomina', 'C') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD CONSTRAINT [CK_rrhhEmpleado_TipoNomina] CHECK ([TipoNomina] IN ('S','Q','M'));
IF OBJECT_ID('dbo.CK_rrhhEmpleado_Pago', 'C') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD CONSTRAINT [CK_rrhhEmpleado_Pago] CHECK (
		([FormaPago] IS NULL OR [FormaPago] IN ('T','C'))
		AND ([TipoCuenta] IS NULL OR [TipoCuenta] IN ('M','A'))
		AND ([FormaPago] IS NULL OR [FormaPago] = 'C' OR ([gef_id] IS NOT NULL AND [TipoCuenta] IS NOT NULL AND [NumeroCuenta] IS NOT NULL)));
IF OBJECT_ID('dbo.FK_rrhhEmpleado_EntidadFinanciera', 'F') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD CONSTRAINT [FK_rrhhEmpleado_EntidadFinanciera]
		FOREIGN KEY ([gef_id]) REFERENCES dbo.gen_entidad_financiera ([gef_id]);
GO
-- La compañía también puede tener periodicidad semanal (solo es el valor sugerido).
IF OBJECT_ID('dbo.CK_gen_compania_parametros', 'C') IS NOT NULL
	ALTER TABLE dbo.gen_compania DROP CONSTRAINT [CK_gen_compania_parametros];
ALTER TABLE dbo.gen_compania ADD CONSTRAINT [CK_gen_compania_parametros] CHECK (
	[cia_porc_iva] >= 0 AND [cia_porc_iva] < 100
	AND [cia_tolerancia_cierre_caja] >= 0
	AND [cia_periodicidad_nomina] IN ('S','Q','M'));
GO

-- Igual que en 26, aceptando la periodicidad semanal.
CREATE OR ALTER PROCEDURE [dbo].[paCompaniaGuardar]
	@CiaId								INT = NULL,
	@NombreComercial					VARCHAR(128),
	@Direccion							VARCHAR(128) = NULL,
	@RepresentanteLegal					VARCHAR(128) = NULL,
	@DpiRepresentanteLegal				VARCHAR(32) = NULL,
	@FechaNacimientoRepresentanteLegal	DATE = NULL,
	@Nit								VARCHAR(32),
	@Telefono							VARCHAR(16) = NULL,
	@Email								VARCHAR(64) = NULL,
	@PorcIva							NUMERIC(5, 2),
	@PagaComision						BIT,
	@ToleranciaCierreCaja				NUMERIC(12, 2),
	@PeriodicidadNomina					CHAR(1),
	@UsuId								INT,
	@IdResultado						INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(LTRIM(RTRIM(@NombreComercial)), '') = '' OR ISNULL(LTRIM(RTRIM(@Nit)), '') = ''
		THROW 52200, 'El nombre comercial y el NIT son obligatorios.', 1;
	IF @PorcIva < 0 OR @PorcIva >= 100
		THROW 52201, 'El porcentaje de IVA debe estar entre 0 y 99.99.', 1;
	IF @ToleranciaCierreCaja < 0
		THROW 52202, 'La tolerancia del cierre de caja no puede ser negativa.', 1;
	IF @PeriodicidadNomina NOT IN ('S','Q','M')
		THROW 52203, 'La periodicidad de nómina debe ser semanal, quincenal o mensual.', 1;
	IF EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_nit = @Nit AND (@CiaId IS NULL OR cia_id <> @CiaId))
		THROW 52204, 'Ya existe una compañía con ese NIT.', 1;

	IF @CiaId IS NULL
	BEGIN
		INSERT INTO dbo.gen_compania (cia_nombre_comercial, cia_direccion, cia_representante_legal, cia_DPI_representante_legal,
			cia_fecha_nacimiento_representante_legal, cia_nit, cia_telefono, cia_email,
			cia_porc_iva, cia_paga_comision, cia_tolerancia_cierre_caja, cia_periodicidad_nomina, InsUsuario, InsFechaHora)
		VALUES (@NombreComercial, @Direccion, @RepresentanteLegal, @DpiRepresentanteLegal,
			@FechaNacimientoRepresentanteLegal, @Nit, @Telefono, @Email,
			@PorcIva, @PagaComision, @ToleranciaCierreCaja, @PeriodicidadNomina, @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.gen_compania
		   SET cia_nombre_comercial = @NombreComercial, cia_direccion = @Direccion, cia_representante_legal = @RepresentanteLegal,
			   cia_DPI_representante_legal = @DpiRepresentanteLegal, cia_fecha_nacimiento_representante_legal = @FechaNacimientoRepresentanteLegal,
			   cia_nit = @Nit, cia_telefono = @Telefono, cia_email = @Email,
			   cia_porc_iva = @PorcIva, cia_paga_comision = @PagaComision, cia_tolerancia_cierre_caja = @ToleranciaCierreCaja,
			   cia_periodicidad_nomina = @PeriodicidadNomina, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE cia_id = @CiaId;
		SET @IdResultado = @CiaId;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoPagoGuardar]
	@IdEmpleado		INT,
	@TipoNomina		CHAR(1),
	@FormaPago		CHAR(1),
	@GefId			INT = NULL,
	@TipoCuenta		CHAR(1) = NULL,
	@NumeroCuenta	VARCHAR(30) = NULL,
	@UsuId			INT
AS
BEGIN
	SET NOCOUNT ON;
	SET @NumeroCuenta = NULLIF(LTRIM(RTRIM(@NumeroCuenta)), '');
	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhEmpleado WHERE IdEmpleado = @IdEmpleado)
		THROW 53439, 'El empleado indicado no existe.', 1;
	IF ISNULL(@TipoNomina, '') NOT IN ('S','Q','M')
		THROW 53438, 'El tipo de nómina debe ser semanal, quincenal o mensual.', 1;
	IF ISNULL(@FormaPago, '') NOT IN ('T','C')
		THROW 53436, 'La forma de pago debe ser transferencia o cheque (no se paga en efectivo).', 1;
	IF @TipoCuenta IS NOT NULL AND @TipoCuenta NOT IN ('M','A')
		THROW 53405, 'El tipo de cuenta debe ser monetaria o de ahorro.', 1;
	IF @FormaPago = 'T' AND (@GefId IS NULL OR @TipoCuenta IS NULL OR @NumeroCuenta IS NULL)
		THROW 53437, 'Para pagar por transferencia indique el banco, el tipo y el número de cuenta del empleado.', 1;
	IF @GefId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.gen_entidad_financiera enti
										  INNER JOIN dbo.gen_entidad_financiera_tipo tipo ON tipo.geft_id = enti.geft_id
										  WHERE enti.gef_id = @GefId AND tipo.geft_descripcion = 'Banco')
		THROW 53403, 'Elija un banco (entidad financiera de tipo Banco).', 1;

	UPDATE dbo.rrhhEmpleado
	   SET TipoNomina = @TipoNomina, FormaPago = @FormaPago, gef_id = @GefId, TipoCuenta = @TipoCuenta, NumeroCuenta = @NumeroCuenta,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdEmpleado = @IdEmpleado;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoConsultar]
	@Filtro	VARCHAR(100) = NULL,
	@Estado	CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT empl.IdEmpleado, empl.CodigoEmpleado,
		   LTRIM(CONCAT(empl.PrimerNombre, ' ', empl.SegundoNombre)) AS Nombres,
		   LTRIM(CONCAT(empl.PrimerApellido, ' ', empl.SegundoApellido)) AS Apellidos,
		   empl.FechaIngreso, empl.FechaBaja, empl.SalarioBase, empl.Estado,
		   plaz.Descripcion AS Plaza, pues.Descripcion AS Puesto, depa.Descripcion AS Departamento,
		   empl.TipoNomina, empl.FormaPago, enti.gef_descripcion AS Banco
	FROM dbo.rrhhEmpleado empl
	LEFT JOIN dbo.rrhhPlaza plaz ON plaz.IdPlaza = empl.IdPlaza
	LEFT JOIN dbo.rrhhDepartamentoPuesto depu ON depu.IdDepartamentoPuesto = plaz.IdDepartamentoPuesto
	LEFT JOIN dbo.rrhhPuesto pues ON pues.IdPuesto = depu.IdPuesto
	LEFT JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = depu.IdDepartamento
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = empl.gef_id
	WHERE (@Estado IS NULL OR empl.Estado = @Estado)
	  AND (@Filtro IS NULL OR empl.CodigoEmpleado LIKE '%' + @Filtro + '%'
		   OR CONCAT(empl.PrimerNombre, ' ', empl.SegundoNombre, ' ', empl.PrimerApellido, ' ', empl.SegundoApellido) LIKE '%' + @Filtro + '%')
	ORDER BY empl.PrimerApellido, empl.PrimerNombre;
END;
GO

------------------------------------------------------------
-- 11. Nómina: período semanal, sugerido y por tipo
------------------------------------------------------------
IF OBJECT_ID('dbo.CK_rrhhNomina_TipoPeriodo', 'C') IS NOT NULL
	ALTER TABLE dbo.rrhhNomina DROP CONSTRAINT [CK_rrhhNomina_TipoPeriodo];
ALTER TABLE dbo.rrhhNomina ADD CONSTRAINT [CK_rrhhNomina_TipoPeriodo] CHECK ([TipoPeriodo] IN ('S','Q','M'));
GO

-- Foto de los datos de pago y del centro de costo de cada empleado en la nómina.
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'IdDepartamento') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [IdDepartamento] INT NULL;
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'FormaPago') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [FormaPago] CHAR(1) NULL;
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'gef_id') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [gef_id] INT NULL;
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'TipoCuenta') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [TipoCuenta] CHAR(1) NULL;
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'NumeroCuenta') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [NumeroCuenta] VARCHAR(30) NULL;
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'IdNominaPago') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [IdNominaPago] INT NULL;	-- pago vigente que lo cubrió
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'bce_id') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [bce_id] INT NULL;			-- cheque vigente (pago con cheque)
GO
IF OBJECT_ID('dbo.FK_rrhhNominaEmpleado_Departamento', 'F') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD CONSTRAINT [FK_rrhhNominaEmpleado_Departamento]
		FOREIGN KEY ([IdDepartamento]) REFERENCES dbo.rrhhDepartamento ([IdDepartamento]);
IF OBJECT_ID('dbo.FK_rrhhNominaEmpleado_EntidadFinanciera', 'F') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD CONSTRAINT [FK_rrhhNominaEmpleado_EntidadFinanciera]
		FOREIGN KEY ([gef_id]) REFERENCES dbo.gen_entidad_financiera ([gef_id]);
IF OBJECT_ID('dbo.FK_rrhhNominaEmpleado_Cheque', 'F') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD CONSTRAINT [FK_rrhhNominaEmpleado_Cheque]
		FOREIGN KEY ([bce_id]) REFERENCES dbo.bco_cheque_emitido_enc ([bce_id]);
GO

IF OBJECT_ID('dbo.rrhhNominaPago', 'U') IS NULL
CREATE TABLE [dbo].[rrhhNominaPago](
	[IdNominaPago]		INT				IDENTITY(1,1)	NOT NULL,
	[IdNomina]			INT				NOT NULL,
	[Tipo]				CHAR(1)			NOT NULL,	-- T = transferencias, C = cheques
	[bcb_id]			INT				NOT NULL,	-- cuenta bancaria de la empresa
	[cbc_id]			INT				NULL,		-- chequera (pago con cheques)
	[FechaPago]			DATE			NOT NULL,
	[Monto]				NUMERIC(14, 2)	NOT NULL,
	[Empleados]			INT				NOT NULL,
	[Referencia]		VARCHAR(60)		NULL,
	[Estado]			CHAR(1)			NOT NULL DEFAULT ('A'),	-- A = vigente, N = anulado
	[MotivoAnulacion]	VARCHAR(250)	NULL,
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhNominaPago] PRIMARY KEY CLUSTERED ([IdNominaPago]),
	CONSTRAINT [CK_rrhhNominaPago_Tipo] CHECK ([Tipo] IN ('T','C')),
	CONSTRAINT [CK_rrhhNominaPago_Estado] CHECK ([Estado] IN ('A','N')),
	CONSTRAINT [CK_rrhhNominaPago_Monto] CHECK ([Monto] >= 0),
	CONSTRAINT [FK_rrhhNominaPago_Nomina] FOREIGN KEY ([IdNomina]) REFERENCES [dbo].[rrhhNomina]([IdNomina]),
	CONSTRAINT [FK_rrhhNominaPago_CuentaBancaria] FOREIGN KEY ([bcb_id]) REFERENCES [dbo].[bco_cuenta_bancaria]([bcb_id]),
	CONSTRAINT [FK_rrhhNominaPago_Chequera] FOREIGN KEY ([cbc_id]) REFERENCES [dbo].[bco_cuenta_bancaria_chequera]([cbc_id]),
	CONSTRAINT [FK_rrhhNominaPago_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES [dbo].[gen_usuario]([usu_id]),
	CONSTRAINT [FK_rrhhNominaPago_UpdUsuario] FOREIGN KEY ([UpdUsuario]) REFERENCES [dbo].[gen_usuario]([usu_id])
);
GO
IF OBJECT_ID('dbo.FK_rrhhNominaEmpleado_NominaPago', 'F') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD CONSTRAINT [FK_rrhhNominaEmpleado_NominaPago]
		FOREIGN KEY ([IdNominaPago]) REFERENCES dbo.rrhhNominaPago ([IdNominaPago]);
GO

-- Siguiente período del tipo elegido: el que sigue a la última nómina no
-- anulada de ese tipo o, si no hay, el período que contiene la fecha de hoy.
-- Semana de lunes a domingo; quincena del 1 al 15 o del 16 a fin de mes.
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaPeriodoSugerido]
	@CiaId			INT,
	@TipoPeriodo	CHAR(1)
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(@TipoPeriodo, '') NOT IN ('S','Q','M')
		THROW 52070, 'El período debe ser semanal, quincenal o mensual.', 1;

	DECLARE @ultima DATE = (SELECT MAX(FechaAl) FROM dbo.rrhhNomina WHERE cia_id = @CiaId AND TipoPeriodo = @TipoPeriodo AND Estado <> 'N');
	DECLARE @del DATE, @al DATE, @hoy DATE = CAST(GETDATE() AS DATE);

	IF @ultima IS NOT NULL
		SET @del = DATEADD(DAY, 1, @ultima);
	ELSE
		SET @del = CASE @TipoPeriodo
					   -- 1900-01-01 fue lunes: no depende de SET DATEFIRST.
					   WHEN 'S' THEN DATEADD(DAY, -(DATEDIFF(DAY, '19000101', @hoy) % 7), @hoy)
					   WHEN 'Q' THEN DATEFROMPARTS(YEAR(@hoy), MONTH(@hoy), CASE WHEN DAY(@hoy) <= 15 THEN 1 ELSE 16 END)
					   ELSE DATEFROMPARTS(YEAR(@hoy), MONTH(@hoy), 1) END;

	SET @al = CASE @TipoPeriodo
				  WHEN 'S' THEN DATEADD(DAY, 6, @del)
				  WHEN 'Q' THEN CASE WHEN DAY(@del) <= 15 THEN DATEFROMPARTS(YEAR(@del), MONTH(@del), 15) ELSE EOMONTH(@del) END
				  ELSE EOMONTH(@del) END;

	DECLARE @mes VARCHAR(30) = FORMAT(@del, 'MMMM yyyy', 'es-GT');
	SET @mes = UPPER(LEFT(@mes, 1)) + SUBSTRING(@mes, 2, 30);

	SELECT @del AS FechaDel, @al AS FechaAl, @al AS FechaPago,
		   CASE @TipoPeriodo
			   WHEN 'S' THEN CONCAT('Semana del ', FORMAT(@del, 'dd/MM'), ' al ', FORMAT(@al, 'dd/MM/yyyy'))
			   WHEN 'Q' THEN CONCAT(CASE WHEN DAY(@del) <= 15 THEN 'Primera' ELSE 'Segunda' END, ' quincena de ', LOWER(@mes))
			   ELSE @mes END AS Descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaCrear]
	@CiaId			INT,
	@Descripcion	VARCHAR(100),
	@TipoPeriodo	CHAR(1),
	@FechaDel		DATE,
	@FechaAl		DATE,
	@FechaPago		DATE = NULL,
	@UsuId			INT,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(@TipoPeriodo, '') NOT IN ('S','Q','M')
		THROW 52070, 'El período debe ser semanal, quincenal o mensual.', 1;
	IF @FechaAl < @FechaDel
		THROW 52071, 'La fecha final no puede ser anterior a la inicial.', 1;
	IF DATEDIFF(DAY, @FechaDel, @FechaAl) + 1 > CASE @TipoPeriodo WHEN 'M' THEN 31 WHEN 'Q' THEN 16 ELSE 7 END
		THROW 52072, 'El rango de fechas es más largo que el período elegido.', 1;
	-- Nóminas de distinto tipo pueden cubrir las mismas fechas: cada empleado
	-- pertenece a un solo tipo de nómina.
	IF EXISTS (SELECT 1 FROM dbo.rrhhNomina
			   WHERE cia_id = @CiaId AND TipoPeriodo = @TipoPeriodo AND Estado <> 'N' AND FechaDel <= @FechaAl AND FechaAl >= @FechaDel)
		THROW 52073, 'Ya existe una nómina de este tipo que se traslapa con esas fechas.', 1;

	INSERT INTO dbo.rrhhNomina (cia_id, Descripcion, TipoPeriodo, FechaDel, FechaAl, FechaPago, InsUsuario)
	VALUES (@CiaId, @Descripcion, @TipoPeriodo, @FechaDel, @FechaAl, @FechaPago, @UsuId);
	SET @IdResultado = SCOPE_IDENTITY();
END;
GO

-- Igual que en 25, con tres cambios: solo entran los empleados del tipo de
-- nómina, el período semanal tiene 7 días base (monto semanal = mensual ×
-- 12 / 52) y se guarda la foto del departamento y los datos de pago.
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaCalcular]
	@IdNomina	INT,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @CiaId INT, @FechaDel DATE, @FechaAl DATE, @TipoPeriodo CHAR(1), @Estado CHAR(1);
	SELECT @CiaId = cia_id, @FechaDel = FechaDel, @FechaAl = FechaAl, @TipoPeriodo = TipoPeriodo, @Estado = Estado
	FROM dbo.rrhhNomina WHERE IdNomina = @IdNomina;

	IF @Estado IS NULL
		THROW 52080, 'La nómina indicada no existe.', 1;
	IF @Estado NOT IN ('B','C')
		THROW 52081, 'Solo se puede calcular una nómina en borrador o ya calculada (no aprobada ni anulada).', 1;

	-- Días base del período y fracción del mes que representa: mes comercial
	-- de 30 días, quincena de 15 (medio mes) y semana de 7 (12/52 del mes).
	DECLARE @DiasPeriodo NUMERIC(5, 2) = CASE @TipoPeriodo WHEN 'M' THEN 30 WHEN 'Q' THEN 15 ELSE 7 END;
	DECLARE @FraccionMes NUMERIC(12, 10) = CASE @TipoPeriodo WHEN 'M' THEN 1 WHEN 'Q' THEN 0.5 ELSE 12.0 / 52.0 END;

	BEGIN TRANSACTION;

	DELETE deta FROM dbo.rrhhNominaDetalle deta
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = deta.IdNominaEmpleado
	WHERE nemp.IdNomina = @IdNomina;
	DELETE FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina;

	INSERT INTO dbo.rrhhNominaEmpleado (IdNomina, IdEmpleado, SalarioBase, DiasLaborados, IdDepartamento, FormaPago, gef_id, TipoCuenta, NumeroCuenta)
	SELECT @IdNomina, empl.IdEmpleado, empl.SalarioBase,
		   CASE WHEN empl.FechaIngreso <= @FechaDel AND (empl.FechaBaja IS NULL OR empl.FechaBaja >= @FechaAl)
				THEN @DiasPeriodo
				ELSE CASE WHEN rango.Dias > @DiasPeriodo THEN @DiasPeriodo ELSE rango.Dias END
		   END,
		   dbo.fnRrhhEmpleadoDepartamento(empl.IdEmpleado), empl.FormaPago, empl.gef_id, empl.TipoCuenta, empl.NumeroCuenta
	FROM dbo.rrhhEmpleado empl
	CROSS APPLY (SELECT CAST(DATEDIFF(DAY,
					CASE WHEN empl.FechaIngreso > @FechaDel THEN empl.FechaIngreso ELSE @FechaDel END,
					CASE WHEN empl.FechaBaja IS NOT NULL AND empl.FechaBaja < @FechaAl THEN empl.FechaBaja ELSE @FechaAl END) + 1 AS NUMERIC(5, 2)) AS Dias) rango
	WHERE empl.cia_id = @CiaId
	  AND empl.TipoNomina = @TipoPeriodo
	  AND empl.FechaIngreso <= @FechaAl
	  AND (empl.FechaBaja IS NULL OR empl.FechaBaja >= @FechaDel)
	  AND (empl.Estado = 'A' OR empl.FechaBaja IS NOT NULL);

	-- 1) Sueldo (S) e ingresos/descuentos fijos (F) automáticos: montos
	--    mensuales llevados al período y proporcionales a los días laborados.
	INSERT INTO dbo.rrhhNominaDetalle (IdNominaEmpleado, IdTipoMovimientoNomina, Naturaleza, Descripcion, Monto)
	SELECT nemp.IdNominaEmpleado, tipo.IdTipoMovimientoNomina, tipo.Naturaleza, tipo.Descripcion,
		   ROUND(CASE tipo.FormaCalculo WHEN 'S' THEN nemp.SalarioBase ELSE tipo.Valor END * @FraccionMes * nemp.DiasLaborados / @DiasPeriodo, 2)
	FROM dbo.rrhhNominaEmpleado nemp
	CROSS JOIN dbo.rrhhTipoMovimientoNomina tipo
	WHERE nemp.IdNomina = @IdNomina
	  AND tipo.Estado = 'A' AND tipo.EsAutomatico = 1 AND tipo.FormaCalculo IN ('S','F');

	-- 2) Movimientos manuales (M) del período no aplicados en otra nómina.
	INSERT INTO dbo.rrhhNominaDetalle (IdNominaEmpleado, IdTipoMovimientoNomina, IdMovimientoNomina, Naturaleza, Descripcion, Monto)
	SELECT nemp.IdNominaEmpleado, tipo.IdTipoMovimientoNomina, movi.IdMovimientoNomina, tipo.Naturaleza,
		   ISNULL(NULLIF(movi.Descripcion, ''), tipo.Descripcion), movi.Monto
	FROM dbo.rrhhMovimientoNomina movi
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdEmpleado = movi.IdEmpleado AND nemp.IdNomina = @IdNomina
	INNER JOIN dbo.rrhhTipoMovimientoNomina tipo ON tipo.IdTipoMovimientoNomina = movi.IdTipoMovimientoNomina
	WHERE movi.Estado = 'A' AND movi.IdNomina IS NULL
	  AND movi.FechaAplicacion BETWEEN @FechaDel AND @FechaAl;

	-- 3) Porcentajes (P) automáticos sobre los ingresos que forman la base.
	INSERT INTO dbo.rrhhNominaDetalle (IdNominaEmpleado, IdTipoMovimientoNomina, Naturaleza, Descripcion, Monto)
	SELECT nemp.IdNominaEmpleado, tipo.IdTipoMovimientoNomina, tipo.Naturaleza, tipo.Descripcion,
		   ROUND(base.Monto * tipo.Valor / 100.0, 2)
	FROM dbo.rrhhNominaEmpleado nemp
	CROSS APPLY (SELECT ISNULL(SUM(deta.Monto), 0) AS Monto
				 FROM dbo.rrhhNominaDetalle deta
				 INNER JOIN dbo.rrhhTipoMovimientoNomina tbas ON tbas.IdTipoMovimientoNomina = deta.IdTipoMovimientoNomina
				 WHERE deta.IdNominaEmpleado = nemp.IdNominaEmpleado AND tbas.EsBaseCalculo = 1) base
	CROSS JOIN dbo.rrhhTipoMovimientoNomina tipo
	WHERE nemp.IdNomina = @IdNomina
	  AND tipo.Estado = 'A' AND tipo.EsAutomatico = 1 AND tipo.FormaCalculo = 'P'
	  AND base.Monto > 0;

	DELETE deta FROM dbo.rrhhNominaDetalle deta
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = deta.IdNominaEmpleado
	WHERE nemp.IdNomina = @IdNomina AND deta.Monto <= 0;

	UPDATE nemp
	   SET TotalIngresos = tota.Ingresos, TotalDescuentos = tota.Descuentos, Liquido = tota.Ingresos - tota.Descuentos
	FROM dbo.rrhhNominaEmpleado nemp
	CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN deta.Naturaleza = 'I' THEN deta.Monto ELSE 0 END), 0) AS Ingresos,
						ISNULL(SUM(CASE WHEN deta.Naturaleza = 'D' THEN deta.Monto ELSE 0 END), 0) AS Descuentos
				 FROM dbo.rrhhNominaDetalle deta WHERE deta.IdNominaEmpleado = nemp.IdNominaEmpleado) tota
	WHERE nemp.IdNomina = @IdNomina;

	UPDATE nomi
	   SET TotalIngresos = tota.Ingresos, TotalDescuentos = tota.Descuentos, TotalLiquido = tota.Liquido,
		   Estado = 'C', FechaCalculo = SYSDATETIME(), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	FROM dbo.rrhhNomina nomi
	CROSS APPLY (SELECT ISNULL(SUM(TotalIngresos), 0) AS Ingresos, ISNULL(SUM(TotalDescuentos), 0) AS Descuentos, ISNULL(SUM(Liquido), 0) AS Liquido
				 FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina) tota
	WHERE nomi.IdNomina = @IdNomina;

	COMMIT TRANSACTION;
END;
GO

-- Aprobación con centro de costo: cada ingreso se desglosa por el
-- departamento del empleado; descuentos y líquido van sin centro de costo.
-- Antes de aprobar refresca la foto de pago y exige que cada empleado con
-- líquido tenga forma de pago (y banco y cuenta si es transferencia).
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaAprobar]
	@IdNomina	INT,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhNomina WHERE IdNomina = @IdNomina AND Estado = 'C')
		THROW 52090, 'Solo se puede aprobar una nómina calculada.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina)
		THROW 52091, 'La nómina no tiene empleados; revise las fechas, el tipo de nómina y los empleados activos.', 1;

	UPDATE nemp
	   SET IdDepartamento = dbo.fnRrhhEmpleadoDepartamento(empl.IdEmpleado),
		   FormaPago = empl.FormaPago, gef_id = empl.gef_id, TipoCuenta = empl.TipoCuenta, NumeroCuenta = empl.NumeroCuenta
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = nemp.IdEmpleado
	WHERE nemp.IdNomina = @IdNomina;

	DECLARE @sin_pago VARCHAR(200);
	SELECT @sin_pago = STRING_AGG(CAST(empl.CodigoEmpleado AS VARCHAR(20)), ', ')
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = nemp.IdEmpleado
	WHERE nemp.IdNomina = @IdNomina AND nemp.Liquido > 0
	  AND (nemp.FormaPago IS NULL OR (nemp.FormaPago = 'T' AND (nemp.gef_id IS NULL OR nemp.NumeroCuenta IS NULL)));
	IF @sin_pago IS NOT NULL
	BEGIN
		DECLARE @msg_pago NVARCHAR(400) = CONCAT(N'Estos empleados no tienen forma de pago o datos bancarios completos: ', @sin_pago,
			N'. Complételos en RRHH > Empleados (Pago de nómina) antes de aprobar.');
		THROW 53428, @msg_pago, 1;
	END

	DECLARE @cta_sueldos INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'NOMINA_SUELDOS_GASTO'),
			@cta_bonificacion INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'NOMINA_BONIFICACION'),
			@cta_igss INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'NOMINA_IGSS_POR_PAGAR'),
			@cta_liquido INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'NOMINA_SUELDOS_POR_PAGAR', @CtaId = @cta_liquido OUTPUT;

	DECLARE @lineas TABLE (cta_id INT NULL, Codigo VARCHAR(20) NOT NULL, Descripcion VARCHAR(100) NOT NULL, Naturaleza CHAR(1) NOT NULL,
						   IdDepartamento INT NULL, Departamento VARCHAR(100) NULL, Monto NUMERIC(14, 2) NOT NULL);
	INSERT INTO @lineas (cta_id, Codigo, Descripcion, Naturaleza, IdDepartamento, Departamento, Monto)
	SELECT COALESCE(tipo.cta_id,
					CASE WHEN tipo.Codigo = 'BONIF_INCENTIVO' THEN @cta_bonificacion
						 WHEN tipo.Codigo = 'IGSS_LABORAL' THEN @cta_igss
						 WHEN deta.Naturaleza = 'I' THEN @cta_sueldos END),
		   tipo.Codigo, tipo.Descripcion, deta.Naturaleza,
		   CASE WHEN deta.Naturaleza = 'I' THEN nemp.IdDepartamento END,
		   CASE WHEN deta.Naturaleza = 'I' THEN depa.Descripcion END,
		   SUM(deta.Monto)
	FROM dbo.rrhhNominaDetalle deta
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = deta.IdNominaEmpleado
	INNER JOIN dbo.rrhhTipoMovimientoNomina tipo ON tipo.IdTipoMovimientoNomina = deta.IdTipoMovimientoNomina
	LEFT JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = nemp.IdDepartamento
	WHERE nemp.IdNomina = @IdNomina
	GROUP BY tipo.IdTipoMovimientoNomina, tipo.cta_id, tipo.Codigo, tipo.Descripcion, deta.Naturaleza,
			 CASE WHEN deta.Naturaleza = 'I' THEN nemp.IdDepartamento END,
			 CASE WHEN deta.Naturaleza = 'I' THEN depa.Descripcion END;

	DECLARE @sin_cuenta VARCHAR(20) = (SELECT TOP 1 Codigo FROM @lineas WHERE cta_id IS NULL ORDER BY Codigo);
	IF @sin_cuenta IS NOT NULL
	BEGIN
		DECLARE @mensaje NVARCHAR(300) = CONCAT(N'El tipo de movimiento ', @sin_cuenta,
			N' no tiene cuenta contable; asígnela en RRHH > Tipos de movimiento antes de aprobar la nómina.');
		THROW 52502, @mensaje, 1;
	END

	DECLARE @liquido NUMERIC(14, 2) = (SELECT ISNULL(SUM(Liquido), 0) FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina);
	DECLARE @descripcion_nomina VARCHAR(100), @fecha DATE;
	SELECT @descripcion_nomina = Descripcion, @fecha = ISNULL(FechaPago, FechaAl) FROM dbo.rrhhNomina WHERE IdNomina = @IdNomina;

	DECLARE @detalle dbo.cont_asiento_det_cc_type, @asi_id INT;
	INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion, IdDepartamento)
	SELECT cta_id,
		   CASE WHEN Naturaleza = 'I' THEN Monto ELSE 0 END,
		   CASE WHEN Naturaleza = 'D' THEN Monto ELSE 0 END,
		   LEFT(CONCAT(Descripcion, ISNULL(' - ' + Departamento, '')), 256),
		   IdDepartamento
	FROM @lineas;
	IF @liquido <> 0
		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_liquido, CASE WHEN @liquido < 0 THEN -@liquido ELSE 0 END, CASE WHEN @liquido > 0 THEN @liquido ELSE 0 END, 'Líquido a pagar a empleados');

	BEGIN TRANSACTION;

	UPDATE movi SET IdNomina = @IdNomina, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	FROM dbo.rrhhMovimientoNomina movi
	INNER JOIN dbo.rrhhNominaDetalle deta ON deta.IdMovimientoNomina = movi.IdMovimientoNomina
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = deta.IdNominaEmpleado
	WHERE nemp.IdNomina = @IdNomina;

	UPDATE dbo.rrhhNomina
	   SET Estado = 'A', UsuarioAprobo = @UsuId, FechaAprobacion = SYSDATETIME(), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdNomina = @IdNomina;

	DECLARE @descripcion VARCHAR(256) = CONCAT('Nómina ', @descripcion_nomina);
	EXEC dbo.paContabilidadAsientoInsertarCc
		@asi_fecha = @fecha, @asi_descripcion = @descripcion, @asi_origen = 'NOMINA', @asi_origen_id = @IdNomina,
		@usu_id = @UsuId, @detalle = @detalle, @asi_id = @asi_id OUTPUT;

	COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaAnular]
	@IdNomina	INT,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhNomina WHERE IdNomina = @IdNomina AND Estado <> 'N')
		THROW 52092, 'La nómina no existe o ya está anulada.', 1;
	IF EXISTS (SELECT 1 FROM dbo.rrhhNominaPago WHERE IdNomina = @IdNomina AND Estado = 'A')
		THROW 53435, 'La nómina tiene pagos vigentes (transferencias o cheques); anúlelos primero.', 1;

	BEGIN TRANSACTION;
	UPDATE dbo.rrhhMovimientoNomina SET IdNomina = NULL, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE IdNomina = @IdNomina;
	UPDATE dbo.rrhhNomina SET Estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE IdNomina = @IdNomina;
	UPDATE dbo.cont_asiento_enc SET asi_estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE asi_origen = 'NOMINA' AND asi_origen_id = @IdNomina AND asi_estado = 'A';
	COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaConsultar]
	@CiaId INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT nomi.IdNomina, nomi.cia_id, comp.cia_nombre_comercial, nomi.Descripcion, nomi.TipoPeriodo, nomi.FechaDel, nomi.FechaAl,
		   nomi.FechaPago, nomi.TotalIngresos, nomi.TotalDescuentos, nomi.TotalLiquido, nomi.Estado, nomi.FechaCalculo, nomi.FechaAprobacion,
		   resu.CantidadEmpleados, resu.TotalPagado, resu.PendientesPago
	FROM dbo.rrhhNomina nomi
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = nomi.cia_id
	CROSS APPLY (SELECT COUNT(*) AS CantidadEmpleados,
						ISNULL(SUM(CASE WHEN nemp.IdNominaPago IS NOT NULL THEN nemp.Liquido END), 0) AS TotalPagado,
						SUM(CASE WHEN nemp.IdNominaPago IS NULL AND nemp.Liquido > 0 THEN 1 ELSE 0 END) AS PendientesPago
				 FROM dbo.rrhhNominaEmpleado nemp WHERE nemp.IdNomina = nomi.IdNomina) resu
	WHERE @CiaId IS NULL OR nomi.cia_id = @CiaId
	ORDER BY nomi.FechaDel DESC, nomi.IdNomina DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaEmpleadoConsultar]
	@IdNomina INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT nemp.IdNominaEmpleado, nemp.IdEmpleado, empl.CodigoEmpleado,
		   empl.PrimerNombre + ' ' + empl.PrimerApellido AS Empleado,
		   nemp.SalarioBase, nemp.DiasLaborados, nemp.TotalIngresos, nemp.TotalDescuentos, nemp.Liquido,
		   depa.Descripcion AS Departamento,
		   -- Antes de aprobar se muestran los datos de pago vigentes del empleado.
		   ISNULL(nemp.FormaPago, empl.FormaPago) AS FormaPago,
		   enti.gef_descripcion AS Banco,
		   ISNULL(nemp.TipoCuenta, empl.TipoCuenta) AS TipoCuenta,
		   ISNULL(nemp.NumeroCuenta, empl.NumeroCuenta) AS NumeroCuenta,
		   nemp.IdNominaPago, cheq.bce_numero_cheque AS NumeroCheque, pago.Tipo AS TipoPago, pago.FechaPago
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = nemp.IdEmpleado
	LEFT JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = nemp.IdDepartamento
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = ISNULL(nemp.gef_id, empl.gef_id)
	LEFT JOIN dbo.rrhhNominaPago pago ON pago.IdNominaPago = nemp.IdNominaPago
	LEFT JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = nemp.bce_id
	WHERE nemp.IdNomina = @IdNomina
	ORDER BY empl.PrimerApellido, empl.PrimerNombre;
END;
GO

------------------------------------------------------------
-- 12. Pago de nómina: transferencias y cheques
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaPagoValidar]
	@IdNomina	INT,
	@BcbId		INT,
	@FormaPago	CHAR(1)
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhNomina WHERE IdNomina = @IdNomina AND Estado = 'A')
		THROW 53429, 'Solo se paga una nómina aprobada.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId AND bcb_estado = 'A')
		THROW 53431, 'Elija una cuenta bancaria activa de la empresa.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina AND FormaPago = @FormaPago AND Liquido > 0 AND IdNominaPago IS NULL)
	BEGIN
		DECLARE @mensaje NVARCHAR(200) = CONCAT(N'No hay empleados pendientes de pago por ',
			CASE @FormaPago WHEN 'T' THEN N'transferencia' ELSE N'cheque' END, N' en esta nómina.');
		THROW 53430, @mensaje, 1;
	END
END;
GO

-- Un lote de transferencias con todos los empleados pendientes que cobran
-- por transferencia. Partida: Debe NOMINA_SUELDOS_POR_PAGAR / Haber banco.
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaPagarTransferencias]
	@IdNomina		INT,
	@BcbId			INT,
	@Fecha			DATE = NULL,
	@Referencia		VARCHAR(60) = NULL,
	@UsuId			INT,
	@IdNominaPago	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));

	EXEC dbo.paRrhhNominaPagoValidar @IdNomina = @IdNomina, @BcbId = @BcbId, @FormaPago = 'T';

	DECLARE @cta_por_pagar INT, @cta_banco INT = dbo.fnBcoCuentaContable(@BcbId);
	EXEC dbo.paCuentaParametroObtener @Codigo = 'NOMINA_SUELDOS_POR_PAGAR', @CtaId = @cta_por_pagar OUTPUT;
	IF @cta_banco IS NULL
		EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_banco OUTPUT;

	DECLARE @monto NUMERIC(14, 2), @empleados INT, @descripcion_nomina VARCHAR(100);
	SELECT @monto = SUM(Liquido), @empleados = COUNT(*)
	FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina AND FormaPago = 'T' AND Liquido > 0 AND IdNominaPago IS NULL;
	SELECT @descripcion_nomina = Descripcion FROM dbo.rrhhNomina WHERE IdNomina = @IdNomina;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.rrhhNominaPago (IdNomina, Tipo, bcb_id, FechaPago, Monto, Empleados, Referencia, InsUsuario)
		VALUES (@IdNomina, 'T', @BcbId, @Fecha, @monto, @empleados, NULLIF(LTRIM(RTRIM(@Referencia)), ''), @UsuId);
		SET @IdNominaPago = SCOPE_IDENTITY();

		UPDATE dbo.rrhhNominaEmpleado SET IdNominaPago = @IdNominaPago
		 WHERE IdNomina = @IdNomina AND FormaPago = 'T' AND Liquido > 0 AND IdNominaPago IS NULL;

		DECLARE @partida dbo.cont_asiento_det_cc_type, @asi_id INT;
		DECLARE @texto VARCHAR(256) = LEFT(CONCAT('Transferencias nómina ', @descripcion_nomina, ISNULL(' - ' + NULLIF(LTRIM(RTRIM(@Referencia)), ''), '')), 256);
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_por_pagar, @monto, 0, @texto), (@cta_banco, 0, @monto, @texto);
		EXEC dbo.paContabilidadAsientoInsertarCc
			@asi_fecha = @Fecha, @asi_descripcion = @texto, @asi_origen = 'PAGO_NOMINA', @asi_origen_id = @IdNominaPago,
			@usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Un cheque por cada empleado pendiente que cobra con cheque, con números
-- correlativos de la chequera y una partida por cheque.
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaEmitirCheques]
	@IdNomina		INT,
	@CbcId			INT,
	@Fecha			DATE = NULL,
	@UsuId			INT,
	@IdNominaPago	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));

	DECLARE @BcbId INT = (SELECT bcb_id FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @CbcId AND cbc_estado = 'A');
	IF @BcbId IS NULL
		THROW 53413, 'La chequera no existe o está inactiva (ella o su cuenta bancaria).', 1;
	EXEC dbo.paRrhhNominaPagoValidar @IdNomina = @IdNomina, @BcbId = @BcbId, @FormaPago = 'C';

	DECLARE @pendientes TABLE (Orden INT IDENTITY(1,1), IdNominaEmpleado INT, Beneficiario VARCHAR(150), Liquido NUMERIC(14, 2));
	INSERT INTO @pendientes (IdNominaEmpleado, Beneficiario, Liquido)
	SELECT nemp.IdNominaEmpleado,
		   LEFT(CONCAT_WS(' ', empl.PrimerNombre, NULLIF(empl.SegundoNombre, ''), empl.PrimerApellido, NULLIF(empl.SegundoApellido, '')), 150),
		   nemp.Liquido
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = nemp.IdEmpleado
	WHERE nemp.IdNomina = @IdNomina AND nemp.FormaPago = 'C' AND nemp.Liquido > 0 AND nemp.IdNominaPago IS NULL
	ORDER BY empl.PrimerApellido, empl.PrimerNombre;

	DECLARE @cantidad INT = (SELECT COUNT(*) FROM @pendientes);
	DECLARE @siguiente INT = dbo.fnBcoChequeSiguiente(@CbcId), @al INT = (SELECT cbc_cheque_al FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @CbcId);
	IF @siguiente IS NULL OR @al - @siguiente + 1 < @cantidad
	BEGIN
		DECLARE @msg NVARCHAR(200) = CONCAT(N'La chequera no alcanza: se necesitan ', @cantidad, N' cheques y quedan ',
			CASE WHEN @siguiente IS NULL THEN 0 ELSE @al - @siguiente + 1 END, N'.');
		THROW 53432, @msg, 1;
	END

	DECLARE @cta_por_pagar INT, @cta_banco INT = dbo.fnBcoCuentaContable(@BcbId), @bmp_id INT = (SELECT bmp_id FROM dbo.bco_motivo_pago WHERE bmp_descripcion = 'Pago de nómina');
	EXEC dbo.paCuentaParametroObtener @Codigo = 'NOMINA_SUELDOS_POR_PAGAR', @CtaId = @cta_por_pagar OUTPUT;
	IF @cta_banco IS NULL
		EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_banco OUTPUT;
	DECLARE @descripcion_nomina VARCHAR(100) = (SELECT Descripcion FROM dbo.rrhhNomina WHERE IdNomina = @IdNomina);

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.rrhhNominaPago (IdNomina, Tipo, bcb_id, cbc_id, FechaPago, Monto, Empleados, Referencia, InsUsuario)
		SELECT @IdNomina, 'C', @BcbId, @CbcId, @Fecha, SUM(Liquido), COUNT(*),
			   CONCAT('Cheques ', @siguiente, CASE WHEN COUNT(*) > 1 THEN CONCAT(' al ', @siguiente + COUNT(*) - 1) ELSE '' END), @UsuId
		FROM @pendientes;
		SET @IdNominaPago = SCOPE_IDENTITY();

		DECLARE @orden INT = 1, @IdNominaEmpleado INT, @beneficiario VARCHAR(150), @liquido NUMERIC(14, 2), @numero VARCHAR(16), @bce_id INT, @asi_id INT;
		DECLARE @partida dbo.cont_asiento_det_cc_type, @texto VARCHAR(256);
		WHILE @orden <= @cantidad
		BEGIN
			SELECT @IdNominaEmpleado = IdNominaEmpleado, @beneficiario = Beneficiario, @liquido = Liquido FROM @pendientes WHERE Orden = @orden;
			SET @numero = CAST(@siguiente + @orden - 1 AS VARCHAR(16));

			INSERT INTO dbo.bco_cheque_emitido_enc
				(cbc_id, bce_fecha_emision, usu_id, bce_numero_cheque, bce_documento_ref, bce_valor, bmp_id, bce_tipo, bce_beneficiario, IdNominaEmpleado, InsUsuario, InsFechaHora)
			VALUES
				(@CbcId, @Fecha, @UsuId, @numero, CAST(@IdNomina AS VARCHAR(16)), @liquido, @bmp_id, 'N', @beneficiario, @IdNominaEmpleado, @UsuId, SYSDATETIME());
			SET @bce_id = SCOPE_IDENTITY();

			UPDATE dbo.rrhhNominaEmpleado SET IdNominaPago = @IdNominaPago, bce_id = @bce_id WHERE IdNominaEmpleado = @IdNominaEmpleado;

			DELETE FROM @partida;
			SET @texto = LEFT(CONCAT('Cheque ', @numero, ' nómina ', @descripcion_nomina, ' - ', @beneficiario), 256);
			INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
			VALUES (@cta_por_pagar, @liquido, 0, @texto), (@cta_banco, 0, @liquido, @texto);
			EXEC dbo.paContabilidadAsientoInsertarCc
				@asi_fecha = @Fecha, @asi_descripcion = @texto, @asi_origen = 'CHEQUE', @asi_origen_id = @bce_id,
				@usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;

			SET @orden += 1;
		END

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaPagoConsultar]
	@IdNomina INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT pago.IdNominaPago, pago.Tipo, pago.FechaPago, pago.Monto, pago.Empleados, pago.Referencia, pago.Estado, pago.MotivoAnulacion,
		   CONCAT(enti.gef_descripcion, ' ', cuba.bcb_numero_cuenta) AS Cuenta, usua.usu_usuario AS Usuario
	FROM dbo.rrhhNominaPago pago
	INNER JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = pago.bcb_id
	INNER JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuba.gef_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = pago.InsUsuario
	WHERE pago.IdNomina = @IdNomina
	ORDER BY pago.IdNominaPago DESC;
END;
GO

-- Listado de un lote de transferencias (para el banco), ordenado por banco.
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaTransferenciaListado]
	@IdNominaPago INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT enti.gef_codigo AS BancoCodigo, enti.gef_descripcion AS Banco,
		   CASE nemp.TipoCuenta WHEN 'A' THEN 'Ahorro' ELSE 'Monetaria' END AS TipoCuenta, nemp.NumeroCuenta,
		   empl.CodigoEmpleado, CONCAT_WS(' ', empl.PrimerNombre, NULLIF(empl.SegundoNombre, ''), empl.PrimerApellido, NULLIF(empl.SegundoApellido, '')) AS Empleado,
		   empl.NumeroDocumento, nemp.Liquido AS Monto,
		   nomi.Descripcion AS Nomina, pago.FechaPago, pago.Referencia,
		   CONCAT(enor.gef_descripcion, ' ', cuba.bcb_numero_cuenta) AS CuentaOrigen
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = nemp.IdEmpleado
	INNER JOIN dbo.rrhhNominaPago pago ON pago.IdNominaPago = nemp.IdNominaPago
	INNER JOIN dbo.rrhhNomina nomi ON nomi.IdNomina = pago.IdNomina
	INNER JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = pago.bcb_id
	INNER JOIN dbo.gen_entidad_financiera enor ON enor.gef_id = cuba.gef_id
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = nemp.gef_id
	WHERE nemp.IdNominaPago = @IdNominaPago
	ORDER BY enti.gef_descripcion, empl.PrimerApellido, empl.PrimerNombre;
END;
GO

-- Quita un cheque de nómina de su pago: el empleado vuelve a quedar pendiente
-- y el lote se ajusta (o se anula si ya no le queda ningún cheque).
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaChequeLiberar]
	@BceId	INT,
	@Motivo	VARCHAR(250),
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @IdNominaPago INT = (SELECT IdNominaPago FROM dbo.rrhhNominaEmpleado WHERE bce_id = @BceId);
	UPDATE dbo.rrhhNominaEmpleado SET IdNominaPago = NULL, bce_id = NULL WHERE bce_id = @BceId;
	IF @IdNominaPago IS NOT NULL
		UPDATE pago
		   -- Si ya no le queda ningún cheque, el lote se anula conservando su monto.
		   SET Monto = CASE WHEN resu.Empleados = 0 THEN pago.Monto ELSE resu.Monto END,
			   Empleados = CASE WHEN resu.Empleados = 0 THEN pago.Empleados ELSE resu.Empleados END,
			   Estado = CASE WHEN resu.Empleados = 0 THEN 'N' ELSE pago.Estado END,
			   MotivoAnulacion = CASE WHEN resu.Empleados = 0 THEN LEFT(@Motivo, 250) ELSE pago.MotivoAnulacion END,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		FROM dbo.rrhhNominaPago pago
		CROSS APPLY (SELECT SUM(nemp.Liquido) AS Monto, COUNT(*) AS Empleados
					 FROM dbo.rrhhNominaEmpleado nemp WHERE nemp.IdNominaPago = pago.IdNominaPago) resu
		WHERE pago.IdNominaPago = @IdNominaPago;
END;
GO

------------------------------------------------------------
-- 13. Anulación de cheques (todos los tipos) y de pagos de nómina
------------------------------------------------------------
-- Igual que en 34; la observación se recorta a 250 (el largo de la columna).
CREATE OR ALTER PROCEDURE [dbo].[paCxpChequeAnular]
	@BceId	INT,
	@Motivo	VARCHAR(256),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado CHAR(1) = (SELECT bce_estado_cheque FROM dbo.bco_cheque_emitido_enc WHERE bce_id = @BceId);
	IF @estado IS NULL
		THROW 53218, 'El cheque indicado no existe.', 1;
	IF @estado = 'A'
		THROW 53219, 'El cheque ya está anulado.', 1;
	IF @estado = 'C'
		THROW 53220, 'El cheque ya fue cobrado por el proveedor; no se puede anular.', 1;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 53214, 'Indique el motivo de la anulación (al menos 5 caracteres).', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_det WHERE bce_id = @BceId AND ppg_id IS NULL)
		THROW 53221, 'No se puede determinar la cuota que pagó este cheque; anúlelo manualmente con contabilidad.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		UPDATE cuot
		   SET ppg_valor_real_pago = ISNULL(cuot.ppg_valor_real_pago, 0) - chdt.ced_valor,
			   ppg_estado = 'P',
			   ppg_numero_cheque = CASE WHEN cuot.ppg_numero_cheque = cheq.bce_numero_cheque THEN NULL ELSE cuot.ppg_numero_cheque END,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		FROM dbo.inv_proveedor_plan_pago cuot
		INNER JOIN dbo.bco_cheque_emitido_det chdt ON chdt.ppg_id = cuot.ppg_id
		INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = chdt.bce_id
		WHERE chdt.bce_id = @BceId;

		UPDATE dbo.bco_cheque_emitido_enc
		   SET bce_estado_cheque = 'A',
			   bce_observaciones = LEFT(CONCAT('ANULADO: ', LTRIM(RTRIM(@Motivo)), ISNULL(' | ' + bce_observaciones, '')), 250),
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE bce_id = @BceId;

		UPDATE dbo.cont_asiento_enc
		   SET asi_estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE asi_origen = 'PAGO_PROVEEDOR' AND asi_origen_id = @BceId AND asi_estado = 'A';

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBcoChequeAnular]
	@BceId	INT,
	@Motivo	VARCHAR(250),
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado CHAR(1), @tipo CHAR(1);
	SELECT @estado = bce_estado_cheque, @tipo = bce_tipo FROM dbo.bco_cheque_emitido_enc WHERE bce_id = @BceId;
	IF @estado IS NULL
		THROW 53218, 'El cheque indicado no existe.', 1;

	-- El de proveedor devuelve el saldo a la cuota: lo resuelve CxP.
	IF @tipo = 'P'
	BEGIN
		EXEC dbo.paCxpChequeAnular @BceId = @BceId, @Motivo = @Motivo, @UsuId = @UsuId;
		RETURN;
	END

	IF @estado = 'A'
		THROW 53219, 'El cheque ya está anulado.', 1;
	IF @estado = 'C'
		THROW 53422, 'El cheque ya fue cobrado; no se puede anular.', 1;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 53214, 'Indique el motivo de la anulación (al menos 5 caracteres).', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		UPDATE dbo.bco_cheque_emitido_enc
		   SET bce_estado_cheque = 'A',
			   bce_observaciones = LEFT(CONCAT('ANULADO: ', LTRIM(RTRIM(@Motivo)), ISNULL(' | ' + bce_observaciones, '')), 250),
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE bce_id = @BceId;

		UPDATE dbo.cont_asiento_enc
		   SET asi_estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE asi_origen = 'CHEQUE' AND asi_origen_id = @BceId AND asi_estado = 'A';

		IF @tipo = 'N'
			EXEC dbo.paRrhhNominaChequeLiberar @BceId = @BceId, @Motivo = @Motivo, @UsuId = @UsuId;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaPagoAnular]
	@IdNominaPago	INT,
	@Motivo			VARCHAR(250),
	@UsuId			INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @tipo CHAR(1) = (SELECT Tipo FROM dbo.rrhhNominaPago WHERE IdNominaPago = @IdNominaPago AND Estado = 'A');
	IF @tipo IS NULL
		THROW 53433, 'El pago no existe o ya está anulado.', 1;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 53214, 'Indique el motivo de la anulación (al menos 5 caracteres).', 1;
	IF @tipo = 'C' AND EXISTS (SELECT 1 FROM dbo.rrhhNominaEmpleado nemp
							   INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = nemp.bce_id
							   WHERE nemp.IdNominaPago = @IdNominaPago AND cheq.bce_estado_cheque = 'C')
		THROW 53434, 'Algún cheque de este pago ya fue cobrado; anule individualmente los que no se hayan cobrado desde Bancos > Cheques.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		IF @tipo = 'T'
		BEGIN
			UPDATE dbo.rrhhNominaEmpleado SET IdNominaPago = NULL WHERE IdNominaPago = @IdNominaPago;
			UPDATE dbo.rrhhNominaPago
			   SET Estado = 'N', MotivoAnulacion = LEFT(LTRIM(RTRIM(@Motivo)), 250), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
			 WHERE IdNominaPago = @IdNominaPago;
			UPDATE dbo.cont_asiento_enc
			   SET asi_estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
			 WHERE asi_origen = 'PAGO_NOMINA' AND asi_origen_id = @IdNominaPago AND asi_estado = 'A';
		END
		ELSE
		BEGIN
			-- Anula cheque por cheque; al liberar el último, el lote queda anulado.
			DECLARE @bce_id INT = (SELECT MIN(bce_id) FROM dbo.rrhhNominaEmpleado WHERE IdNominaPago = @IdNominaPago);
			WHILE @bce_id IS NOT NULL
			BEGIN
				EXEC dbo.paBcoChequeAnular @BceId = @bce_id, @Motivo = @Motivo, @UsuId = @UsuId;
				SET @bce_id = (SELECT MIN(bce_id) FROM dbo.rrhhNominaEmpleado WHERE IdNominaPago = @IdNominaPago);
			END
			UPDATE dbo.rrhhNominaPago
			   SET Estado = 'N', MotivoAnulacion = LEFT(LTRIM(RTRIM(@Motivo)), 250), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
			 WHERE IdNominaPago = @IdNominaPago;
		END

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 14. Permisos (administrador y contador)
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT v.modulo, v.codigo, v.descripcion
FROM (VALUES
	('BANCOS',       'BANCOS_ADMIN',              'Bancos: cuentas bancarias, chequeras, motivos, cheques y pago de nómina'),
	('CONTABILIDAD', 'CONTABILIDAD_CENTRO_COSTO', 'Reporte de gasto por centro de costo (departamento)')
) v(modulo, codigo, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso perm WHERE perm.per_codigo = v.codigo);

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id, InsFechaHora)
SELECT rol.rol_id, perm.per_id, SYSDATETIME()
FROM dbo.sec_rol rol
INNER JOIN (VALUES ('ADMIN', 'BANCOS_ADMIN'), ('CONTADOR', 'BANCOS_ADMIN'),
				   ('ADMIN', 'CONTABILIDAD_CENTRO_COSTO'), ('CONTADOR', 'CONTABILIDAD_CENTRO_COSTO')) v(rol, permiso) ON v.rol = rol.rol_codigo
INNER JOIN dbo.sec_permiso perm ON perm.per_codigo = v.permiso
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO
