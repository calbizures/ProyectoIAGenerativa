/*
================================================================================
 61_caja_chica.sql
 Caja chica con fondo fijo.

   - Fondo: sucursal, responsable, monto autorizado y cuenta contable (por
     omisión CAJA CHICA). Se constituye con un cheque al responsable
     (Debe caja chica / Haber banco) y se puede aumentar con otro cheque.
   - Gastos: factura (con IVA crédito fiscal), factura de pequeño contribuyente
     (sin crédito), recibo o vale; proveedor/NIT, número, concepto, cuenta de
     gasto y centro de costo. No pueden pasar del disponible del fondo.
   - Liquidación (LCC-000001): reúne gastos pendientes y graba la póliza
     CAJA_CHICA: Debe cada gasto (sin IVA) + IVA por cobrar / Haber caja chica.
   - Reposición: cheque al responsable por el total liquidado
     (Debe caja chica / Haber banco); el fondo vuelve a su monto completo.
   - Arqueo: conteo del efectivo contra el disponible del fondo.
   Disponible = constituido − gastos pendientes − liquidado sin reponer.
   Un cheque anulado (Bancos > Cheques) deja de contar: si era la reposición,
   la liquidación vuelve a quedar pendiente de reponer.

 Errores nuevos: 55101 a 55140.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Tablas
------------------------------------------------------------
IF OBJECT_ID('dbo.cch_fondo', 'U') IS NULL
CREATE TABLE dbo.cch_fondo (
	[cch_id]				INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_cch_fondo] PRIMARY KEY,
	[cch_codigo]			VARCHAR(10)		NOT NULL CONSTRAINT [UQ_cch_fondo_codigo] UNIQUE,
	[cch_nombre]			VARCHAR(100)	NOT NULL,
	[suc_id]				INT				NOT NULL CONSTRAINT [FK_cch_fondo_sucursal] REFERENCES dbo.gen_sucursal ([suc_id]),
	[cch_responsable]		VARCHAR(150)	NOT NULL,
	[cch_monto_autorizado]	NUMERIC(12, 2)	NOT NULL CONSTRAINT [CK_cch_fondo_monto] CHECK ([cch_monto_autorizado] > 0),
	[cta_id]				INT				NOT NULL CONSTRAINT [FK_cch_fondo_cuenta] REFERENCES dbo.cont_cuenta_contable ([cta_id]),
	[cch_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_cch_fondo_estado] DEFAULT ('A') CONSTRAINT [CK_cch_fondo_estado] CHECK ([cch_estado] IN ('A', 'I')),
	[InsUsuario]			INT				NULL CONSTRAINT [FK_cch_fondo_ins] REFERENCES dbo.gen_usuario ([usu_id]),
	[InsFechaHora]			DATETIME2(0)	NOT NULL CONSTRAINT [DF_cch_fondo_ins] DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL CONSTRAINT [FK_cch_fondo_upd] REFERENCES dbo.gen_usuario ([usu_id]),
	[UpdFechaHora]			DATETIME2(0)	NULL
);
GO

-- Liquidaciones (se crean antes que los gastos por la referencia).
IF OBJECT_ID('dbo.cch_liquidacion', 'U') IS NULL
CREATE TABLE dbo.cch_liquidacion (
	[lcc_id]				INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_cch_liquidacion] PRIMARY KEY,
	[cch_id]				INT				NOT NULL CONSTRAINT [FK_cch_liquidacion_fondo] REFERENCES dbo.cch_fondo ([cch_id]),
	[lcc_numero]			VARCHAR(12)		NOT NULL CONSTRAINT [UQ_cch_liquidacion_numero] UNIQUE,
	[lcc_fecha]				DATE			NOT NULL,
	[lcc_total]				NUMERIC(12, 2)	NOT NULL,
	[lcc_iva]				NUMERIC(12, 2)	NOT NULL,
	[asi_id]				INT				NULL CONSTRAINT [FK_cch_liquidacion_asiento] REFERENCES dbo.cont_asiento_enc ([asi_id]),
	[lcc_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_cch_liquidacion_estado] DEFAULT ('V') CONSTRAINT [CK_cch_liquidacion_estado] CHECK ([lcc_estado] IN ('V', 'A')),
	[lcc_motivo_anulacion]	VARCHAR(250)	NULL,
	[InsUsuario]			INT				NULL CONSTRAINT [FK_cch_liquidacion_ins] REFERENCES dbo.gen_usuario ([usu_id]),
	[InsFechaHora]			DATETIME2(0)	NOT NULL CONSTRAINT [DF_cch_liquidacion_ins] DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL CONSTRAINT [FK_cch_liquidacion_upd] REFERENCES dbo.gen_usuario ([usu_id]),
	[UpdFechaHora]			DATETIME2(0)	NULL
);
GO

-- Tipo: F factura (IVA crédito), P factura de pequeño contribuyente (sin
-- crédito), R recibo, V vale. Estado: P pendiente, L liquidado, A anulado.
IF OBJECT_ID('dbo.cch_gasto', 'U') IS NULL
CREATE TABLE dbo.cch_gasto (
	[ccg_id]				INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_cch_gasto] PRIMARY KEY,
	[cch_id]				INT				NOT NULL CONSTRAINT [FK_cch_gasto_fondo] REFERENCES dbo.cch_fondo ([cch_id]),
	[ccg_fecha]				DATE			NOT NULL,
	[ccg_tipo]				CHAR(1)			NOT NULL CONSTRAINT [CK_cch_gasto_tipo] CHECK ([ccg_tipo] IN ('F', 'P', 'R', 'V')),
	[prv_id]				INT				NULL CONSTRAINT [FK_cch_gasto_proveedor] REFERENCES dbo.inv_proveedor ([prv_id]),
	[ccg_nit]				VARCHAR(20)		NULL,
	[ccg_proveedor]			VARCHAR(150)	NOT NULL,
	[ccg_serie]				VARCHAR(20)		NULL,
	[ccg_numero]			VARCHAR(30)		NULL,
	[ccg_concepto]			VARCHAR(250)	NOT NULL,
	[cta_id]				INT				NOT NULL CONSTRAINT [FK_cch_gasto_cuenta] REFERENCES dbo.cont_cuenta_contable ([cta_id]),
	[IdDepartamento]		INT				NULL CONSTRAINT [FK_cch_gasto_departamento] REFERENCES dbo.rrhhDepartamento ([IdDepartamento]),
	[ccg_total]				NUMERIC(12, 2)	NOT NULL CONSTRAINT [CK_cch_gasto_total] CHECK ([ccg_total] > 0),
	[ccg_iva]				NUMERIC(12, 2)	NOT NULL CONSTRAINT [DF_cch_gasto_iva] DEFAULT (0),
	[ccg_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_cch_gasto_estado] DEFAULT ('P') CONSTRAINT [CK_cch_gasto_estado] CHECK ([ccg_estado] IN ('P', 'L', 'A')),
	[lcc_id]				INT				NULL CONSTRAINT [FK_cch_gasto_liquidacion] REFERENCES dbo.cch_liquidacion ([lcc_id]),
	[ccg_motivo_anulacion]	VARCHAR(250)	NULL,
	[InsUsuario]			INT				NULL CONSTRAINT [FK_cch_gasto_ins] REFERENCES dbo.gen_usuario ([usu_id]),
	[InsFechaHora]			DATETIME2(0)	NOT NULL CONSTRAINT [DF_cch_gasto_ins] DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL CONSTRAINT [FK_cch_gasto_upd] REFERENCES dbo.gen_usuario ([usu_id]),
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [CK_cch_gasto_iva] CHECK ([ccg_iva] >= 0 AND [ccg_iva] < [ccg_total])
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cch_gasto_fondo')
	CREATE INDEX [IX_cch_gasto_fondo] ON dbo.cch_gasto ([cch_id], [ccg_estado]) INCLUDE ([ccg_total]);
GO

-- Cheques del fondo: C constitución, A aumento, R reposición (de una liquidación).
IF OBJECT_ID('dbo.cch_fondo_cheque', 'U') IS NULL
CREATE TABLE dbo.cch_fondo_cheque (
	[cfc_id]				INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_cch_fondo_cheque] PRIMARY KEY,
	[cch_id]				INT				NOT NULL CONSTRAINT [FK_cch_fondo_cheque_fondo] REFERENCES dbo.cch_fondo ([cch_id]),
	[cfc_tipo]				CHAR(1)			NOT NULL CONSTRAINT [CK_cch_fondo_cheque_tipo] CHECK ([cfc_tipo] IN ('C', 'A', 'R')),
	[bce_id]				INT				NOT NULL CONSTRAINT [FK_cch_fondo_cheque_cheque] REFERENCES dbo.bco_cheque_emitido_enc ([bce_id]),
	[lcc_id]				INT				NULL CONSTRAINT [FK_cch_fondo_cheque_liquidacion] REFERENCES dbo.cch_liquidacion ([lcc_id]),
	[cfc_monto]				NUMERIC(12, 2)	NOT NULL,
	[InsUsuario]			INT				NULL CONSTRAINT [FK_cch_fondo_cheque_ins] REFERENCES dbo.gen_usuario ([usu_id]),
	[InsFechaHora]			DATETIME2(0)	NOT NULL CONSTRAINT [DF_cch_fondo_cheque_ins] DEFAULT (SYSDATETIME())
);
GO

IF OBJECT_ID('dbo.cch_arqueo', 'U') IS NULL
CREATE TABLE dbo.cch_arqueo (
	[cca_id]				INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_cch_arqueo] PRIMARY KEY,
	[cch_id]				INT				NOT NULL CONSTRAINT [FK_cch_arqueo_fondo] REFERENCES dbo.cch_fondo ([cch_id]),
	[cca_fecha]				DATETIME2(0)	NOT NULL,
	[cca_disponible]		NUMERIC(12, 2)	NOT NULL,
	[cca_efectivo]			NUMERIC(12, 2)	NOT NULL,
	[cca_observaciones]		VARCHAR(250)	NULL,
	[InsUsuario]			INT				NULL CONSTRAINT [FK_cch_arqueo_ins] REFERENCES dbo.gen_usuario ([usu_id]),
	[InsFechaHora]			DATETIME2(0)	NOT NULL CONSTRAINT [DF_cch_arqueo_ins] DEFAULT (SYSDATETIME())
);
GO

------------------------------------------------------------
-- 2. Cuenta, motivo de pago y permisos
------------------------------------------------------------
INSERT INTO dbo.cont_cuenta_parametro (ccp_codigo, ccp_descripcion, ccp_naturaleza, cta_id, InsFechaHora)
SELECT 'CAJA_CHICA', 'Caja chica: fondo fijo (cuenta por omisión de los fondos)', 'D',
	   (SELECT TOP 1 cta_id FROM dbo.cont_cuenta_contable WHERE cta_acepta_movimiento = 1 AND cta_tipo = 'A' AND cta_nombre LIKE 'CAJA CHICA%' ORDER BY cta_codigo),
	   SYSDATETIME()
WHERE NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'CAJA_CHICA');
GO
IF NOT EXISTS (SELECT 1 FROM dbo.bco_motivo_pago WHERE bmp_descripcion = 'Caja chica')
	INSERT INTO dbo.bco_motivo_pago (bmp_descripcion, bmp_estado, InsFechaHora) VALUES ('Caja chica', 'A', SYSDATETIME());
GO

INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT v.modulo, v.codigo, v.descripcion
FROM (VALUES
	('BANCOS', 'CAJA_CHICA_GASTOS', 'Caja chica: registrar y anular gastos y hacer arqueos'),
	('BANCOS', 'CAJA_CHICA_ADMIN', 'Caja chica: fondos, constitución, liquidación y reposición')) v (modulo, codigo, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso perm WHERE perm.per_codigo = v.codigo);

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT rol.rol_id, perm.per_id
FROM (VALUES ('ADMIN', 'CAJA_CHICA_GASTOS'), ('ADMIN', 'CAJA_CHICA_ADMIN'),
			 ('CONTADOR', 'CAJA_CHICA_GASTOS'), ('CONTADOR', 'CAJA_CHICA_ADMIN'),
			 ('CONTADOR_GENERAL', 'CAJA_CHICA_GASTOS'), ('CONTADOR_GENERAL', 'CAJA_CHICA_ADMIN'),
			 ('CAJERO', 'CAJA_CHICA_GASTOS')) v (rol, permiso)
INNER JOIN dbo.sec_rol rol ON rol.rol_codigo = v.rol
INNER JOIN dbo.sec_permiso perm ON perm.per_codigo = v.permiso
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO

------------------------------------------------------------
-- 3. Saldos del fondo
------------------------------------------------------------
-- Constituido: cheques de constitución y aumento vigentes.
-- Pendiente: gastos sin liquidar. Por reponer: liquidaciones vigentes sin
-- cheque de reposición vigente.
CREATE OR ALTER FUNCTION [dbo].[fnCajaChicaSaldo] (@CchId INT)
RETURNS TABLE
AS
RETURN
	SELECT
		ISNULL((SELECT SUM(cheq.cfc_monto) FROM dbo.cch_fondo_cheque cheq
				INNER JOIN dbo.bco_cheque_emitido_enc emit ON emit.bce_id = cheq.bce_id AND emit.bce_estado_cheque <> 'A'
				WHERE cheq.cch_id = @CchId AND cheq.cfc_tipo IN ('C', 'A')), 0) AS Constituido,
		ISNULL((SELECT SUM(gast.ccg_total) FROM dbo.cch_gasto gast WHERE gast.cch_id = @CchId AND gast.ccg_estado = 'P'), 0) AS Pendiente,
		ISNULL((SELECT COUNT(*) FROM dbo.cch_gasto gast WHERE gast.cch_id = @CchId AND gast.ccg_estado = 'P'), 0) AS GastosPendientes,
		ISNULL((SELECT SUM(liqu.lcc_total) FROM dbo.cch_liquidacion liqu
				WHERE liqu.cch_id = @CchId AND liqu.lcc_estado = 'V'
				  AND NOT EXISTS (SELECT 1 FROM dbo.cch_fondo_cheque cheq
								  INNER JOIN dbo.bco_cheque_emitido_enc emit ON emit.bce_id = cheq.bce_id AND emit.bce_estado_cheque <> 'A'
								  WHERE cheq.lcc_id = liqu.lcc_id AND cheq.cfc_tipo = 'R')), 0) AS PorReponer;
GO

------------------------------------------------------------
-- 4. Fondos
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCajaChicaFondoConsultar]
	@CchId			INT = NULL,
	@SoloActivos	BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT fond.cch_id AS CchId, fond.cch_codigo AS Codigo, fond.cch_nombre AS Nombre, fond.suc_id AS SucId, sucu.suc_descripcion AS Sucursal,
		   fond.cch_responsable AS Responsable, fond.cch_monto_autorizado AS MontoAutorizado, fond.cta_id AS CtaId,
		   cuen.cta_codigo AS CuentaCodigo, cuen.cta_nombre AS CuentaNombre, fond.cch_estado AS Estado,
		   sald.Constituido, sald.Pendiente, sald.GastosPendientes, sald.PorReponer,
		   sald.Constituido - sald.Pendiente - sald.PorReponer AS Disponible,
		   (SELECT TOP 1 arqu.cca_fecha FROM dbo.cch_arqueo arqu WHERE arqu.cch_id = fond.cch_id ORDER BY arqu.cca_fecha DESC) AS UltimoArqueo
	FROM dbo.cch_fondo fond
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = fond.suc_id
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = fond.cta_id
	CROSS APPLY dbo.fnCajaChicaSaldo(fond.cch_id) sald
	WHERE (@CchId IS NULL OR fond.cch_id = @CchId)
	  AND (@SoloActivos = 0 OR fond.cch_estado = 'A')
	ORDER BY fond.cch_codigo;
END;
GO

-- El monto autorizado no se cambia aquí una vez constituido el fondo: se
-- aumenta con paCajaChicaFondoCheque (tipo A).
CREATE OR ALTER PROCEDURE [dbo].[paCajaChicaFondoGuardar]
	@CchId			INT = NULL OUTPUT,
	@Nombre			VARCHAR(100),
	@SucId			INT,
	@Responsable	VARCHAR(150),
	@MontoAutorizado NUMERIC(12, 2),
	@CtaId			INT = NULL,
	@Estado			CHAR(1) = 'A',
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @Nombre = NULLIF(LTRIM(RTRIM(@Nombre)), '');
	SET @Responsable = NULLIF(LTRIM(RTRIM(@Responsable)), '');
	IF @Nombre IS NULL OR @Responsable IS NULL
		THROW 55101, 'Indique el nombre del fondo y el responsable.', 1;
	IF ISNULL(@MontoAutorizado, 0) <= 0
		THROW 55102, 'El monto del fondo debe ser mayor a cero.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE suc_id = @SucId)
		THROW 55103, 'Elija la sucursal del fondo.', 1;
	IF @CtaId IS NULL
		SELECT @CtaId = cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'CAJA_CHICA';
	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId AND cta_acepta_movimiento = 1 AND cta_estado = 'A' AND cta_tipo = 'A')
		THROW 55104, 'La cuenta del fondo debe ser una cuenta de activo de detalle y activa (por ejemplo CAJA CHICA).', 1;

	DECLARE @saldo TABLE (Constituido NUMERIC(12, 2), Pendiente NUMERIC(12, 2), PorReponer NUMERIC(12, 2));
	IF @CchId IS NOT NULL
	BEGIN
		INSERT INTO @saldo SELECT Constituido, Pendiente, PorReponer FROM dbo.fnCajaChicaSaldo(@CchId);
		IF EXISTS (SELECT 1 FROM @saldo WHERE Constituido > 0)
		BEGIN
			IF EXISTS (SELECT 1 FROM dbo.cch_fondo WHERE cch_id = @CchId AND (cch_monto_autorizado <> @MontoAutorizado OR cta_id <> @CtaId))
				THROW 55105, 'El fondo ya está constituido: su monto se aumenta con un cheque (Aumentar fondo) y su cuenta ya no se cambia.', 1;
			IF @Estado = 'I' AND EXISTS (SELECT 1 FROM @saldo WHERE Pendiente > 0 OR PorReponer > 0)
				THROW 55106, 'Antes de inactivar el fondo liquide los gastos pendientes y reponga las liquidaciones.', 1;
		END
		UPDATE dbo.cch_fondo
		   SET cch_nombre = @Nombre, suc_id = @SucId, cch_responsable = @Responsable, cch_monto_autorizado = @MontoAutorizado,
			   cta_id = @CtaId, cch_estado = ISNULL(@Estado, 'A'), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE cch_id = @CchId;
		RETURN;
	END

	DECLARE @codigo VARCHAR(10);
	BEGIN TRANSACTION;
		SELECT @codigo = CONCAT('CCH-', RIGHT(CONCAT('00', ISNULL(MAX(CAST(SUBSTRING(cch_codigo, 5, 6) AS INT)), 0) + 1), 3))
		FROM dbo.cch_fondo WITH (UPDLOCK, HOLDLOCK) WHERE cch_codigo LIKE 'CCH-[0-9][0-9][0-9]%';
		INSERT INTO dbo.cch_fondo (cch_codigo, cch_nombre, suc_id, cch_responsable, cch_monto_autorizado, cta_id, cch_estado, InsUsuario)
		VALUES (@codigo, @Nombre, @SucId, @Responsable, @MontoAutorizado, @CtaId, 'A', @UsuId);
		SET @CchId = SCOPE_IDENTITY();
	COMMIT TRANSACTION;
END;
GO

-- Cheque al responsable: C constitución (por el monto autorizado), A aumento
-- (por @Monto; sube el monto autorizado) o R reposición de una liquidación.
CREATE OR ALTER PROCEDURE [dbo].[paCajaChicaFondoCheque]
	@CchId		INT,
	@Tipo		CHAR(1),
	@CbcId		INT,
	@Numero		VARCHAR(16) = NULL,
	@Fecha		DATE = NULL,
	@Monto		NUMERIC(12, 2) = NULL,
	@LccId		INT = NULL,
	@UsuId		INT,
	@BceId		INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @BceId = NULL;
	DECLARE @cta_id INT, @responsable VARCHAR(150), @autorizado NUMERIC(12, 2), @estado CHAR(1), @nombre VARCHAR(100), @codigo VARCHAR(10),
			@mensaje NVARCHAR(300), @motivo INT = (SELECT TOP 1 bmp_id FROM dbo.bco_motivo_pago WHERE bmp_descripcion = 'Caja chica' AND bmp_estado = 'A');
	SELECT @cta_id = cta_id, @responsable = cch_responsable, @autorizado = cch_monto_autorizado, @estado = cch_estado, @nombre = cch_nombre, @codigo = cch_codigo
	FROM dbo.cch_fondo WHERE cch_id = @CchId;
	IF @cta_id IS NULL
		THROW 55107, 'El fondo de caja chica no existe.', 1;
	IF @estado <> 'A'
		THROW 55108, 'El fondo de caja chica está inactivo.', 1;
	IF @Tipo NOT IN ('C', 'A', 'R')
		THROW 55109, 'Tipo de cheque de caja chica no válido.', 1;
	DECLARE @constituido NUMERIC(12, 2) = (SELECT Constituido FROM dbo.fnCajaChicaSaldo(@CchId));

	IF @Tipo = 'C'
	BEGIN
		IF @constituido > 0
			THROW 55110, 'El fondo ya está constituido; para subirlo use Aumentar fondo.', 1;
		SET @Monto = @autorizado;
	END
	ELSE IF @Tipo = 'A'
	BEGIN
		IF @constituido = 0
			THROW 55111, 'Primero constituya el fondo.', 1;
		IF ISNULL(@Monto, 0) <= 0
			THROW 55112, 'Indique el monto del aumento.', 1;
	END
	ELSE
	BEGIN
		SELECT @Monto = lcc_total FROM dbo.cch_liquidacion WHERE lcc_id = @LccId AND cch_id = @CchId AND lcc_estado = 'V';
		IF @Monto IS NULL
			THROW 55113, 'La liquidación no existe, es de otro fondo o está anulada.', 1;
		IF EXISTS (SELECT 1 FROM dbo.cch_fondo_cheque cheq INNER JOIN dbo.bco_cheque_emitido_enc emit ON emit.bce_id = cheq.bce_id AND emit.bce_estado_cheque <> 'A'
				   WHERE cheq.lcc_id = @LccId AND cheq.cfc_tipo = 'R')
			THROW 55114, 'La liquidación ya tiene su cheque de reposición.', 1;
	END

	DECLARE @observaciones VARCHAR(250) = LEFT(CONCAT(CASE @Tipo WHEN 'C' THEN 'Constitución' WHEN 'A' THEN 'Aumento' ELSE 'Reposición' END,
		' de caja chica ', @codigo, ' ', @nombre,
		CASE WHEN @Tipo = 'R' THEN CONCAT(' (liquidación ', (SELECT lcc_numero FROM dbo.cch_liquidacion WHERE lcc_id = @LccId), ')') ELSE '' END), 250);
	BEGIN TRY
		BEGIN TRANSACTION;
			EXEC dbo.paBcoChequeEmitirLibre @CbcId = @CbcId, @Numero = @Numero, @Fecha = @Fecha, @Beneficiario = @responsable, @BmpId = @motivo,
				@CtaId = @cta_id, @Valor = @Monto, @Observaciones = @observaciones, @UsuId = @UsuId, @BceId = @BceId OUTPUT;
			INSERT INTO dbo.cch_fondo_cheque (cch_id, cfc_tipo, bce_id, lcc_id, cfc_monto, InsUsuario)
			VALUES (@CchId, @Tipo, @BceId, IIF(@Tipo = 'R', @LccId, NULL), @Monto, @UsuId);
			IF @Tipo = 'A'
				UPDATE dbo.cch_fondo SET cch_monto_autorizado = @constituido + @Monto, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE cch_id = @CchId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaChicaChequesConsultar]
	@CchId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cheq.cfc_id AS CfcId, cheq.cfc_tipo AS Tipo, cheq.bce_id AS BceId, emit.bce_numero_cheque AS Numero, emit.bce_fecha_emision AS Fecha,
		   cheq.cfc_monto AS Monto, emit.bce_estado_cheque AS EstadoCheque, liqu.lcc_numero AS Liquidacion, cuba.Nombre AS Cuenta
	FROM dbo.cch_fondo_cheque cheq
	INNER JOIN dbo.bco_cheque_emitido_enc emit ON emit.bce_id = cheq.bce_id
	LEFT JOIN dbo.cch_liquidacion liqu ON liqu.lcc_id = cheq.lcc_id
	OUTER APPLY (SELECT CONCAT(enti.gef_descripcion, ' ', banc.bcb_numero_cuenta) AS Nombre
				 FROM dbo.bco_cuenta_bancaria_chequera cheq2
				 INNER JOIN dbo.bco_cuenta_bancaria banc ON banc.bcb_id = cheq2.bcb_id
				 LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = banc.gef_id
				 WHERE cheq2.cbc_id = emit.cbc_id) cuba
	WHERE cheq.cch_id = @CchId
	ORDER BY emit.bce_fecha_emision DESC, cheq.cfc_id DESC;
END;
GO

------------------------------------------------------------
-- 5. Gastos
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCajaChicaGastoConsultar]
	@CchId	INT,
	@Estado	CHAR(1) = NULL,
	@LccId	INT = NULL,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT gast.ccg_id AS CcgId, gast.cch_id AS CchId, gast.ccg_fecha AS Fecha, gast.ccg_tipo AS Tipo, gast.prv_id AS PrvId, gast.ccg_nit AS Nit,
		   gast.ccg_proveedor AS Proveedor, gast.ccg_serie AS Serie, gast.ccg_numero AS Numero, gast.ccg_concepto AS Concepto,
		   gast.cta_id AS CtaId, cuen.cta_codigo AS CuentaCodigo, cuen.cta_nombre AS CuentaNombre, gast.IdDepartamento,
		   depa.Descripcion AS Departamento, gast.ccg_total AS Total, gast.ccg_iva AS Iva, gast.ccg_estado AS Estado,
		   gast.lcc_id AS LccId, liqu.lcc_numero AS Liquidacion, gast.ccg_motivo_anulacion AS MotivoAnulacion
	FROM dbo.cch_gasto gast
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = gast.cta_id
	LEFT JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = gast.IdDepartamento
	LEFT JOIN dbo.cch_liquidacion liqu ON liqu.lcc_id = gast.lcc_id
	WHERE gast.cch_id = @CchId
	  AND (@Estado IS NULL OR gast.ccg_estado = @Estado)
	  AND (@LccId IS NULL OR gast.lcc_id = @LccId)
	  AND (@Desde IS NULL OR gast.ccg_fecha >= @Desde)
	  AND (@Hasta IS NULL OR gast.ccg_fecha <= @Hasta)
	ORDER BY gast.ccg_fecha DESC, gast.ccg_id DESC;
END;
GO

-- Graba o corrige un gasto pendiente. IVA: solo factura normal (F), incluido
-- en el total: total × tasa / (100 + tasa).
CREATE OR ALTER PROCEDURE [dbo].[paCajaChicaGastoGuardar]
	@CcgId			INT = NULL OUTPUT,
	@CchId			INT,
	@Fecha			DATE,
	@Tipo			CHAR(1),
	@PrvId			INT = NULL,
	@Nit			VARCHAR(20) = NULL,
	@Proveedor		VARCHAR(150),
	@Serie			VARCHAR(20) = NULL,
	@Numero			VARCHAR(30) = NULL,
	@Concepto		VARCHAR(250),
	@CtaId			INT,
	@IdDepartamento	INT = NULL,
	@Total			NUMERIC(12, 2),
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	DECLARE @mensaje NVARCHAR(300);
	SET @Proveedor = NULLIF(LTRIM(RTRIM(@Proveedor)), '');
	SET @Concepto = NULLIF(LTRIM(RTRIM(@Concepto)), '');
	SET @Nit = NULLIF(UPPER(REPLACE(REPLACE(LTRIM(RTRIM(@Nit)), '-', ''), ' ', '')), '');
	SET @Serie = NULLIF(UPPER(LTRIM(RTRIM(@Serie))), '');
	SET @Numero = NULLIF(LTRIM(RTRIM(@Numero)), '');

	IF NOT EXISTS (SELECT 1 FROM dbo.cch_fondo WHERE cch_id = @CchId AND cch_estado = 'A')
		THROW 55115, 'El fondo de caja chica no existe o está inactivo.', 1;
	IF @Tipo NOT IN ('F', 'P', 'R', 'V')
		THROW 55116, 'El tipo de comprobante es F (factura), P (factura de pequeño contribuyente), R (recibo) o V (vale).', 1;
	IF @Fecha IS NULL OR @Fecha > CAST(GETDATE() AS DATE)
		THROW 55117, 'La fecha del gasto no puede ser futura.', 1;
	IF @Proveedor IS NULL OR @Concepto IS NULL
		THROW 55118, 'Indique a quién se pagó y el concepto del gasto.', 1;
	IF @Tipo IN ('F', 'P') AND (@Nit IS NULL OR @Numero IS NULL)
		THROW 55119, 'Para una factura indique el NIT del proveedor y el número de la factura.', 1;
	IF ISNULL(@Total, 0) <= 0
		THROW 55120, 'El monto del gasto debe ser mayor a cero.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId AND cta_acepta_movimiento = 1 AND cta_estado = 'A')
		THROW 55121, 'Elija una cuenta de gasto de detalle y activa.', 1;
	IF @IdDepartamento IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.rrhhDepartamento WHERE IdDepartamento = @IdDepartamento AND Estado = 'A')
		THROW 55122, 'El centro de costo (departamento) no existe o está inactivo.', 1;
	IF @CcgId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.cch_gasto WHERE ccg_id = @CcgId AND cch_id = @CchId AND ccg_estado = 'P')
		THROW 55123, 'Solo se corrige un gasto pendiente (no liquidado ni anulado).', 1;
	IF @Tipo IN ('F', 'P') AND EXISTS (SELECT 1 FROM dbo.cch_gasto WHERE ccg_nit = @Nit AND ISNULL(ccg_serie, '') = ISNULL(@Serie, '')
									   AND ccg_numero = @Numero AND ccg_estado <> 'A' AND ccg_id <> ISNULL(@CcgId, 0))
		THROW 55124, 'Esa factura (NIT, serie y número) ya está registrada en caja chica.', 1;

	DECLARE @disponible NUMERIC(12, 2) = (SELECT Constituido - Pendiente - PorReponer FROM dbo.fnCajaChicaSaldo(@CchId))
		+ ISNULL((SELECT ccg_total FROM dbo.cch_gasto WHERE ccg_id = @CcgId), 0);
	IF @Total > @disponible
	BEGIN
		SET @mensaje = CONCAT(N'El gasto (Q', FORMAT(@Total, 'N2'), N') pasa del disponible del fondo (Q', FORMAT(@disponible, 'N2'),
			N'). Liquide y reponga el fondo, o auméntelo.');
		THROW 55125, @mensaje, 1;
	END

	DECLARE @tasa NUMERIC(5, 2) = ISNULL((SELECT TOP 1 comp.cia_porc_iva FROM dbo.cch_fondo fond
										   INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = fond.suc_id
										   INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id WHERE fond.cch_id = @CchId), 12);
	DECLARE @iva NUMERIC(12, 2) = IIF(@Tipo = 'F', ROUND(@Total * @tasa / (100 + @tasa), 2), 0);

	IF @CcgId IS NULL
	BEGIN
		INSERT INTO dbo.cch_gasto (cch_id, ccg_fecha, ccg_tipo, prv_id, ccg_nit, ccg_proveedor, ccg_serie, ccg_numero, ccg_concepto, cta_id,
								   IdDepartamento, ccg_total, ccg_iva, InsUsuario)
		VALUES (@CchId, @Fecha, @Tipo, @PrvId, @Nit, @Proveedor, @Serie, @Numero, @Concepto, @CtaId, @IdDepartamento, @Total, @iva, @UsuId);
		SET @CcgId = SCOPE_IDENTITY();
	END
	ELSE
		UPDATE dbo.cch_gasto
		   SET ccg_fecha = @Fecha, ccg_tipo = @Tipo, prv_id = @PrvId, ccg_nit = @Nit, ccg_proveedor = @Proveedor, ccg_serie = @Serie,
			   ccg_numero = @Numero, ccg_concepto = @Concepto, cta_id = @CtaId, IdDepartamento = @IdDepartamento, ccg_total = @Total,
			   ccg_iva = @iva, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE ccg_id = @CcgId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaChicaGastoAnular]
	@CcgId	INT,
	@Motivo	VARCHAR(250),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.cch_gasto WHERE ccg_id = @CcgId AND ccg_estado = 'P')
		THROW 55126, 'Solo se anula un gasto pendiente; uno liquidado se corrige anulando su liquidación.', 1;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 55127, 'Indique el motivo de la anulación (al menos 5 caracteres).', 1;
	UPDATE dbo.cch_gasto
	   SET ccg_estado = 'A', ccg_motivo_anulacion = LTRIM(RTRIM(@Motivo)), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE ccg_id = @CcgId;
END;
GO

------------------------------------------------------------
-- 6. Liquidación
------------------------------------------------------------
-- @Gastos vacío: todos los pendientes del fondo hasta @Fecha.
CREATE OR ALTER PROCEDURE [dbo].[paCajaChicaLiquidar]
	@CchId	INT,
	@Fecha	DATE = NULL,
	@Gastos	dbo.id_lista_type READONLY,
	@UsuId	INT = NULL,
	@LccId	INT OUTPUT,
	@Numero	VARCHAR(12) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @LccId = NULL;
	SET @Numero = NULL;
	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));
	DECLARE @cta_fondo INT, @codigo VARCHAR(10), @nombre VARCHAR(100), @cta_iva INT, @mensaje NVARCHAR(300);
	SELECT @cta_fondo = cta_id, @codigo = cch_codigo, @nombre = cch_nombre FROM dbo.cch_fondo WHERE cch_id = @CchId AND cch_estado = 'A';
	IF @cta_fondo IS NULL
		THROW 55115, 'El fondo de caja chica no existe o está inactivo.', 1;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'COMPRA_IVA_CREDITO', @CtaId = @cta_iva OUTPUT;

	DECLARE @lista TABLE (ccg_id INT PRIMARY KEY);
	IF EXISTS (SELECT 1 FROM @Gastos)
		INSERT INTO @lista SELECT DISTINCT id FROM @Gastos;
	ELSE
		INSERT INTO @lista SELECT ccg_id FROM dbo.cch_gasto WHERE cch_id = @CchId AND ccg_estado = 'P' AND ccg_fecha <= @Fecha;
	IF NOT EXISTS (SELECT 1 FROM @lista)
		THROW 55128, 'No hay gastos pendientes para liquidar.', 1;
	IF EXISTS (SELECT 1 FROM @lista list LEFT JOIN dbo.cch_gasto gast ON gast.ccg_id = list.ccg_id AND gast.cch_id = @CchId AND gast.ccg_estado = 'P'
			   WHERE gast.ccg_id IS NULL)
		THROW 55129, 'Algún gasto elegido no es de este fondo o ya no está pendiente.', 1;
	IF EXISTS (SELECT 1 FROM @lista list INNER JOIN dbo.cch_gasto gast ON gast.ccg_id = list.ccg_id WHERE gast.ccg_fecha > @Fecha)
		THROW 55130, 'La fecha de la liquidación no puede ser anterior a la de sus gastos.', 1;

	DECLARE @total NUMERIC(12, 2), @iva NUMERIC(12, 2);
	SELECT @total = SUM(gast.ccg_total), @iva = SUM(gast.ccg_iva)
	FROM @lista list INNER JOIN dbo.cch_gasto gast ON gast.ccg_id = list.ccg_id;

	BEGIN TRY
		BEGIN TRANSACTION;
			SELECT @Numero = CONCAT('LCC-', RIGHT(CONCAT('00000', ISNULL(MAX(CAST(SUBSTRING(lcc_numero, 5, 8) AS INT)), 0) + 1), 6))
			FROM dbo.cch_liquidacion WITH (UPDLOCK, HOLDLOCK);
			INSERT INTO dbo.cch_liquidacion (cch_id, lcc_numero, lcc_fecha, lcc_total, lcc_iva, InsUsuario)
			VALUES (@CchId, @Numero, @Fecha, @total, @iva, @UsuId);
			SET @LccId = SCOPE_IDENTITY();

			DECLARE @partida dbo.cont_asiento_det_cc_type, @asi_id INT;
			INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion, IdDepartamento)
			SELECT gast.cta_id, gast.ccg_total - gast.ccg_iva, 0,
				   LEFT(CONCAT(gast.ccg_concepto, ' · ', gast.ccg_proveedor,
							   CASE WHEN gast.ccg_numero IS NOT NULL THEN CONCAT(' ', ISNULL(gast.ccg_serie + '-', ''), gast.ccg_numero) ELSE '' END), 256),
				   gast.IdDepartamento
			FROM @lista list INNER JOIN dbo.cch_gasto gast ON gast.ccg_id = list.ccg_id;
			IF @iva > 0
				INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_iva, @iva, 0, CONCAT('IVA crédito fiscal caja chica ', @Numero));
			INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_fondo, 0, @total, CONCAT('Liquidación ', @Numero, ' de ', @codigo));

			DECLARE @descripcion VARCHAR(256) = LEFT(CONCAT('Liquidación de caja chica ', @Numero, ' · ', @codigo, ' ', @nombre), 256);
			EXEC dbo.paContabilidadAsientoInsertarCc @asi_fecha = @Fecha, @asi_descripcion = @descripcion, @asi_origen = 'CAJA_CHICA',
				@asi_origen_id = @LccId, @usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;

			UPDATE dbo.cch_liquidacion SET asi_id = @asi_id WHERE lcc_id = @LccId;
			UPDATE gast SET ccg_estado = 'L', lcc_id = @LccId, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
			FROM dbo.cch_gasto gast INNER JOIN @lista list ON list.ccg_id = gast.ccg_id;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaChicaLiquidacionConsultar]
	@CchId	INT = NULL,
	@LccId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT liqu.lcc_id AS LccId, liqu.cch_id AS CchId, fond.cch_codigo AS Fondo, fond.cch_nombre AS FondoNombre, fond.cch_responsable AS Responsable,
		   liqu.lcc_numero AS Numero, liqu.lcc_fecha AS Fecha, liqu.lcc_total AS Total, liqu.lcc_iva AS Iva, liqu.asi_id AS AsiId,
		   liqu.lcc_estado AS Estado, liqu.lcc_motivo_anulacion AS MotivoAnulacion,
		   (SELECT COUNT(*) FROM dbo.cch_gasto gast WHERE gast.lcc_id = liqu.lcc_id) AS Gastos,
		   repo.bce_id AS BceIdReposicion, repo.bce_numero_cheque AS ChequeReposicion, repo.bce_fecha_emision AS FechaReposicion,
		   usua.usu_codigo AS Usuario
	FROM dbo.cch_liquidacion liqu
	INNER JOIN dbo.cch_fondo fond ON fond.cch_id = liqu.cch_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = liqu.InsUsuario
	OUTER APPLY (SELECT TOP 1 emit.bce_id, emit.bce_numero_cheque, emit.bce_fecha_emision
				 FROM dbo.cch_fondo_cheque cheq
				 INNER JOIN dbo.bco_cheque_emitido_enc emit ON emit.bce_id = cheq.bce_id AND emit.bce_estado_cheque <> 'A'
				 WHERE cheq.lcc_id = liqu.lcc_id AND cheq.cfc_tipo = 'R') repo
	WHERE (@CchId IS NULL OR liqu.cch_id = @CchId)
	  AND (@LccId IS NULL OR liqu.lcc_id = @LccId)
	ORDER BY liqu.lcc_fecha DESC, liqu.lcc_id DESC;
END;
GO

-- Solo una liquidación sin reposición vigente: anula su póliza y sus gastos
-- vuelven a quedar pendientes.
CREATE OR ALTER PROCEDURE [dbo].[paCajaChicaLiquidacionAnular]
	@LccId	INT,
	@Motivo	VARCHAR(250),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	DECLARE @asi_id INT, @estado CHAR(1);
	SELECT @asi_id = asi_id, @estado = lcc_estado FROM dbo.cch_liquidacion WHERE lcc_id = @LccId;
	IF @estado IS NULL OR @estado <> 'V'
		THROW 55131, 'La liquidación no existe o ya está anulada.', 1;
	IF EXISTS (SELECT 1 FROM dbo.cch_fondo_cheque cheq INNER JOIN dbo.bco_cheque_emitido_enc emit ON emit.bce_id = cheq.bce_id AND emit.bce_estado_cheque <> 'A'
			   WHERE cheq.lcc_id = @LccId AND cheq.cfc_tipo = 'R')
		THROW 55132, 'La liquidación ya se repuso: anule primero el cheque de reposición en Bancos > Cheques.', 1;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 55127, 'Indique el motivo de la anulación (al menos 5 caracteres).', 1;
	BEGIN TRY
		BEGIN TRANSACTION;
			UPDATE dbo.cch_liquidacion
			   SET lcc_estado = 'A', lcc_motivo_anulacion = LTRIM(RTRIM(@Motivo)), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
			 WHERE lcc_id = @LccId;
			UPDATE dbo.cont_asiento_enc
			   SET asi_estado = 'N', asi_motivo_anulacion = LEFT(CONCAT('Liquidación de caja chica anulada: ', LTRIM(RTRIM(@Motivo))), 250),
				   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
			 WHERE asi_id = @asi_id AND asi_estado = 'A';
			UPDATE dbo.cch_gasto SET ccg_estado = 'P', lcc_id = NULL, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE lcc_id = @LccId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 7. Arqueo
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCajaChicaArqueoGrabar]
	@CchId			INT,
	@Efectivo		NUMERIC(12, 2),
	@Observaciones	VARCHAR(250) = NULL,
	@UsuId			INT = NULL,
	@Diferencia		NUMERIC(12, 2) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.cch_fondo WHERE cch_id = @CchId)
		THROW 55107, 'El fondo de caja chica no existe.', 1;
	IF @Efectivo IS NULL OR @Efectivo < 0
		THROW 55133, 'Indique el efectivo contado (cero o más).', 1;
	DECLARE @disponible NUMERIC(12, 2) = (SELECT Constituido - Pendiente - PorReponer FROM dbo.fnCajaChicaSaldo(@CchId));
	INSERT INTO dbo.cch_arqueo (cch_id, cca_fecha, cca_disponible, cca_efectivo, cca_observaciones, InsUsuario)
	VALUES (@CchId, SYSDATETIME(), @disponible, @Efectivo, NULLIF(LTRIM(RTRIM(@Observaciones)), ''), @UsuId);
	SET @Diferencia = @Efectivo - @disponible;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaChicaArqueoConsultar]
	@CchId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT arqu.cca_id AS CcaId, arqu.cca_fecha AS Fecha, arqu.cca_disponible AS Disponible, arqu.cca_efectivo AS Efectivo,
		   arqu.cca_efectivo - arqu.cca_disponible AS Diferencia, arqu.cca_observaciones AS Observaciones, usua.usu_codigo AS Usuario
	FROM dbo.cch_arqueo arqu
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = arqu.InsUsuario
	WHERE arqu.cch_id = @CchId
	ORDER BY arqu.cca_fecha DESC;
END;
GO

------------------------------------------------------------
-- 8. Datos de demostración: un fondo de Q2,000 en la casa matriz, constituido,
-- con gastos, una liquidación repuesta y gastos pendientes.
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.cch_fondo)
   AND EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = 1)
   AND EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE suc_id = 1)
   AND EXISTS (SELECT 1 FROM dbo.cont_asiento_enc WHERE asi_descripcion = 'Pago a proveedor con cheque 1009')
   AND NOT EXISTS (SELECT 1 FROM dbo.cont_periodo_contable WHERE pdo_anio = 2026 AND pdo_mes IN (9, 10) AND pdo_estado = 'C')
BEGIN
	DECLARE @cch_id INT, @bce_id INT, @ccg_id INT, @lcc_id INT, @numero VARCHAR(12), @vacia dbo.id_lista_type;
	DECLARE @papeleria INT = (SELECT TOP 1 cta_id FROM dbo.cont_cuenta_contable WHERE cta_acepta_movimiento = 1 AND cta_tipo = 'G' AND cta_nombre LIKE '%PAPELER%' ORDER BY cta_codigo),
			@combustible INT = (SELECT TOP 1 cta_id FROM dbo.cont_cuenta_contable WHERE cta_acepta_movimiento = 1 AND cta_tipo = 'G' AND cta_nombre LIKE '%COMBUSTIBLE%' ORDER BY cta_codigo),
			@limpieza INT = (SELECT TOP 1 cta_id FROM dbo.cont_cuenta_contable WHERE cta_acepta_movimiento = 1 AND cta_tipo = 'G' AND (cta_nombre LIKE '%LIMPIEZA%' OR cta_nombre LIKE '%VARIOS%') ORDER BY cta_codigo),
			@viaticos INT = (SELECT TOP 1 cta_id FROM dbo.cont_cuenta_contable WHERE cta_acepta_movimiento = 1 AND cta_tipo = 'G' AND (cta_nombre LIKE '%VIATICO%' OR cta_nombre LIKE '%TRANSPORTE%') ORDER BY cta_codigo),
			@generico INT = (SELECT TOP 1 cta_id FROM dbo.cont_cuenta_contable WHERE cta_acepta_movimiento = 1 AND cta_tipo = 'G' AND cta_nombre LIKE '%VARIOS%' ORDER BY cta_codigo);
	SET @generico = ISNULL(@generico, (SELECT TOP 1 cta_id FROM dbo.cont_cuenta_contable WHERE cta_acepta_movimiento = 1 AND cta_tipo = 'G' ORDER BY cta_codigo DESC));
	SET @viaticos = ISNULL(@viaticos, @generico);
	SET @papeleria = ISNULL(@papeleria, @generico);
	SET @combustible = ISNULL(@combustible, @generico);
	SET @limpieza = ISNULL(@limpieza, @generico);

	EXEC dbo.paCajaChicaFondoGuardar @CchId = @cch_id OUTPUT, @Nombre = 'Caja chica administración', @SucId = 1,
		@Responsable = 'Lucía Rodríguez', @MontoAutorizado = 2000, @UsuId = 1;
	EXEC dbo.paCajaChicaFondoCheque @CchId = @cch_id, @Tipo = 'C', @CbcId = 1, @Fecha = '20260915', @UsuId = 1, @BceId = @bce_id OUTPUT;

	SET @ccg_id = NULL;
	EXEC dbo.paCajaChicaGastoGuardar @CcgId = @ccg_id OUTPUT, @CchId = @cch_id, @Fecha = '20260916', @Tipo = 'F', @Nit = '1234567',
		@Proveedor = 'Librería El Estudiante', @Serie = 'A', @Numero = '45821', @Concepto = 'Papel bond y tóner', @CtaId = @papeleria, @Total = 448, @UsuId = 1;
	SET @ccg_id = NULL;
	EXEC dbo.paCajaChicaGastoGuardar @CcgId = @ccg_id OUTPUT, @CchId = @cch_id, @Fecha = '20260918', @Tipo = 'F', @Nit = '9876543',
		@Proveedor = 'Gasolinera La Reforma', @Serie = 'B', @Numero = '10077', @Concepto = 'Combustible mensajería', @CtaId = @combustible, @Total = 350, @UsuId = 1;
	SET @ccg_id = NULL;
	EXEC dbo.paCajaChicaGastoGuardar @CcgId = @ccg_id OUTPUT, @CchId = @cch_id, @Fecha = '20260920', @Tipo = 'V',
		@Proveedor = 'Mensajero (taxi)', @Concepto = 'Taxi para entrega de documentos', @CtaId = @viaticos, @Total = 60, @UsuId = 1;
	EXEC dbo.paCajaChicaLiquidar @CchId = @cch_id, @Fecha = '20260925', @Gastos = @vacia, @UsuId = 1, @LccId = @lcc_id OUTPUT, @Numero = @numero OUTPUT;
	SET @bce_id = NULL;
	EXEC dbo.paCajaChicaFondoCheque @CchId = @cch_id, @Tipo = 'R', @CbcId = 1, @Fecha = '20260926', @LccId = @lcc_id, @UsuId = 1, @BceId = @bce_id OUTPUT;

	SET @ccg_id = NULL;
	EXEC dbo.paCajaChicaGastoGuardar @CcgId = @ccg_id OUTPUT, @CchId = @cch_id, @Fecha = '20260930', @Tipo = 'P', @Nit = '5551112',
		@Proveedor = 'Distribuidora La Limpieza', @Numero = '889', @Concepto = 'Artículos de limpieza', @CtaId = @limpieza, @Total = 185.50, @UsuId = 1;
	SET @ccg_id = NULL;
	EXEC dbo.paCajaChicaGastoGuardar @CcgId = @ccg_id OUTPUT, @CchId = @cch_id, @Fecha = '20261001', @Tipo = 'F', @Nit = '1234567',
		@Proveedor = 'Librería El Estudiante', @Serie = 'A', @Numero = '46102', @Concepto = 'Folders y lapiceros', @CtaId = @papeleria, @Total = 112, @UsuId = 1;
END
GO

PRINT '61_caja_chica.sql aplicado.';
GO
