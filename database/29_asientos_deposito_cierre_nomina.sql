------------------------------------------------------------------------------
-- 29_asientos_deposito_cierre_nomina.sql
--
-- Partidas automáticas que faltaban. Hasta el 28, sus conceptos contables
-- estaban configurados en cont_cuenta_parametro pero ningún proceso los usaba:
--
--   * Depósito de caja a banco (paCajaDepositoInsertar):
--         Debe  DEPOSITO_BANCOS   valor depositado
--         Haber DEPOSITO_CAJA     valor depositado
--   * Cierre de caja con diferencia dentro de la tolerancia (sp_pos_caja_cerrar).
--     Si cuadra exacto no hay partida.
--         Faltante: Debe CAJA_FALTANTE / Haber COBRO_CAJA
--         Sobrante: Debe COBRO_CAJA    / Haber CAJA_SOBRANTE
--   * Nómina aprobada (paRrhhNominaAprobar):
--         Debe  cada ingreso a la cuenta de su tipo de movimiento
--         Haber cada descuento a la cuenta de su tipo de movimiento
--         Haber NOMINA_SUELDOS_POR_PAGAR   total líquido
--     Si un tipo no tiene cuenta se usa NOMINA_BONIFICACION (bonificación
--     incentivo), NOMINA_IGSS_POR_PAGAR (IGSS laboral) o NOMINA_SUELDOS_GASTO
--     (demás ingresos). Un descuento sin cuenta detiene la aprobación con un
--     mensaje: no hay forma segura de adivinar a quién se le debe.
--     Anular una nómina aprobada anula su partida.
--
-- Cada partida guarda en asi_origen_id el registro que la originó (pcd_id,
-- pca_id o IdNomina) para poder encontrarla y anularla.
--
-- Todo ocurre en la misma transacción que el proceso: si la partida no se
-- puede generar (p. ej. un concepto sin cuenta), el depósito, cierre o
-- aprobación tampoco se graba.
--
-- Requiere 23, 25, 26 y 28. Se puede volver a correr.
------------------------------------------------------------------------------

USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Origen de la partida
------------------------------------------------------------
IF COL_LENGTH('dbo.cont_asiento_enc', 'asi_origen_id') IS NULL
	ALTER TABLE dbo.cont_asiento_enc ADD [asi_origen_id] INT NULL;	-- pcd_id, pca_id o IdNomina según asi_origen
GO

IF OBJECT_ID('dbo.CK_cont_asiento_enc_origen', 'C') IS NOT NULL
	ALTER TABLE dbo.cont_asiento_enc DROP CONSTRAINT [CK_cont_asiento_enc_origen];
ALTER TABLE dbo.cont_asiento_enc ADD CONSTRAINT [CK_cont_asiento_enc_origen]
	CHECK ([asi_origen] IN ('MANUAL','VENTA','COMPRA','PAGO_CLIENTE','PAGO_PROVEEDOR','DEPOSITO','CIERRE_CAJA','NOMINA',
							'NOTA_CREDITO','NOTA_DEBITO',		-- 32
							'CHEQUE','PAGO_NOMINA',				-- 36
							'AJUSTE_INVENTARIO','APERTURA',		-- 38
							'TRASLADO'));						-- 45
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cont_asiento_enc_origen_id' AND object_id = OBJECT_ID('dbo.cont_asiento_enc'))
	CREATE INDEX [IX_cont_asiento_enc_origen_id] ON dbo.cont_asiento_enc ([asi_origen], [asi_origen_id]) WHERE [asi_origen_id] IS NOT NULL;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_contabilidad_insertar_asiento]
	@asi_fecha			DATE,
	@asi_descripcion	VARCHAR(256) = NULL,
	@asi_origen			VARCHAR(20) = 'MANUAL',
	@enc_id				INT = NULL,
	@pdo_id				INT = NULL,
	@usu_id				INT = NULL,
	@detalle			dbo.cont_asiento_det_type READONLY,
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

	IF @pdo_id IS NULL
		EXEC dbo.sp_contabilidad_obtener_o_crear_periodo @fecha = @asi_fecha, @usu_id = @usu_id, @pdo_id = @pdo_id OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.cont_asiento_enc
			(asi_fecha, asi_descripcion, asi_origen, asi_origen_id, enc_id, pdo_id, usu_id, InsUsuario, InsFechaHora)
		VALUES
			(@asi_fecha, @asi_descripcion, @asi_origen, @asi_origen_id, @enc_id, @pdo_id, @usu_id, @usu_id, SYSDATETIME());

		SET @asi_id = SCOPE_IDENTITY();

		INSERT INTO dbo.cont_asiento_det (asi_id, cta_id, asd_debe, asd_haber, asd_descripcion, InsUsuario, InsFechaHora)
		SELECT @asi_id, cta_id, asd_debe, asd_haber, asd_descripcion, @usu_id, SYSDATETIME()
		FROM @detalle;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Cuenta asignada a un concepto; detiene el proceso con un mensaje claro si
-- el concepto no existe o no tiene cuenta.
CREATE OR ALTER PROCEDURE [dbo].[paCuentaParametroObtener]
	@Codigo	VARCHAR(40),
	@CtaId	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET @CtaId = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = @Codigo);
	IF @CtaId IS NULL
	BEGIN
		DECLARE @mensaje NVARCHAR(200) = CONCAT(N'El concepto contable ', @Codigo, N' no tiene cuenta asignada; configúrelo en Contabilidad > Cuentas de pólizas.');
		THROW 52500, @mensaje, 1;
	END
END;
GO

------------------------------------------------------------
-- 2. Depósito de caja a banco
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCajaDepositoInsertar]
	@pca_id				INT,
	@gef_id				INT,
	@pcd_fecha_deposito	DATE,
	@pcd_valor_deposito	DECIMAL(14, 2),
	@pcd_numero_boleta	VARCHAR(32) = NULL,
	@pcd_observaciones	VARCHAR(128) = NULL,
	@usu_id				INT = NULL,
	@pcd_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id)
		THROW 51904, 'La apertura de caja indicada no existe.', 1;
	IF ISNULL(@pcd_valor_deposito, 0) <= 0
		THROW 52501, 'El valor del depósito debe ser mayor a cero.', 1;

	DECLARE @cta_banco INT, @cta_caja INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'DEPOSITO_BANCOS', @CtaId = @cta_banco OUTPUT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'DEPOSITO_CAJA', @CtaId = @cta_caja OUTPUT;

	BEGIN TRANSACTION;

	INSERT INTO dbo.pos_caja_deposito
		(pcd_fecha_deposito, pcd_valor_deposito, pcd_numero_boleta, pcd_observaciones, pca_id, gef_id, InsUsuario, InsFechaHora)
	VALUES
		(@pcd_fecha_deposito, @pcd_valor_deposito, @pcd_numero_boleta, @pcd_observaciones, @pca_id, @gef_id, @usu_id, SYSDATETIME());

	SET @pcd_id = SCOPE_IDENTITY();

	DECLARE @referencia VARCHAR(64) = CONCAT('Depósito boleta ', ISNULL(@pcd_numero_boleta, 's/n'), ' - apertura ', @pca_id);
	DECLARE @detalle dbo.cont_asiento_det_type, @asi_id INT;
	INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
	VALUES (@cta_banco, @pcd_valor_deposito, 0, @referencia),
		   (@cta_caja, 0, @pcd_valor_deposito, @referencia);

	EXEC dbo.sp_contabilidad_insertar_asiento
		@asi_fecha = @pcd_fecha_deposito, @asi_descripcion = @referencia, @asi_origen = 'DEPOSITO', @asi_origen_id = @pcd_id,
		@usu_id = @usu_id, @detalle = @detalle, @asi_id = @asi_id OUTPUT;

	COMMIT TRANSACTION;
END;
GO

------------------------------------------------------------
-- 3. Cierre de caja: faltante o sobrante dentro de la tolerancia
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_pos_caja_cerrar]
	@pca_id	INT,
	@usu_id	INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id AND pca_estado = 'A')
		THROW 51702, 'La apertura de caja indicada no existe o ya está cerrada.', 1;

	DECLARE @cuadre TABLE (MontoInicial NUMERIC(12, 2), EfectivoCobrado NUMERIC(12, 2), Depositos NUMERIC(12, 2), Cheques NUMERIC(12, 2),
		Tarjetas NUMERIC(12, 2), OtrasFormas NUMERIC(12, 2), TeoricoTotal NUMERIC(12, 2), FisicoEfectivo NUMERIC(12, 2),
		FisicoOtrasFormas NUMERIC(12, 2), FisicoTotal NUMERIC(12, 2), Diferencia NUMERIC(12, 2), Tolerancia NUMERIC(12, 2), Cuadra BIT);
	INSERT INTO @cuadre EXEC dbo.paCorteCajaCuadreConsultar @pca_id = @pca_id;

	DECLARE @teorico NUMERIC(12, 2), @fisico NUMERIC(12, 2), @diferencia NUMERIC(12, 2), @tolerancia NUMERIC(12, 2), @cuadra BIT;
	SELECT @teorico = TeoricoTotal, @fisico = FisicoTotal, @diferencia = Diferencia, @tolerancia = Tolerancia, @cuadra = Cuadra FROM @cuadre;

	IF @cuadra = 0
	BEGIN
		DECLARE @mensaje NVARCHAR(400) = CONCAT(N'La caja no cuadra: teórico Q', FORMAT(@teorico, 'N2'), N', contado Q', FORMAT(@fisico, 'N2'),
			N', diferencia Q', FORMAT(@diferencia, 'N2'), N' (tolerancia permitida Q', FORMAT(@tolerancia, 'N2'),
			N'). Revise el conteo y los depósitos antes de cerrar.');
		THROW 51703, @mensaje, 1;
	END

	-- La caja absorbe la diferencia contra faltantes (gasto) o sobrantes
	-- (ingreso). La cuenta de caja es la misma donde entran los cobros.
	DECLARE @detalle dbo.cont_asiento_det_type, @asi_id INT, @cta_caja INT, @cta_diferencia INT;
	IF @diferencia <> 0
	BEGIN
		EXEC dbo.paCuentaParametroObtener @Codigo = 'COBRO_CAJA', @CtaId = @cta_caja OUTPUT;
		IF @diferencia < 0
		BEGIN
			EXEC dbo.paCuentaParametroObtener @Codigo = 'CAJA_FALTANTE', @CtaId = @cta_diferencia OUTPUT;
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			VALUES (@cta_diferencia, -@diferencia, 0, CONCAT('Faltante al cerrar la apertura ', @pca_id)),
				   (@cta_caja, 0, -@diferencia, CONCAT('Faltante al cerrar la apertura ', @pca_id));
		END
		ELSE
		BEGIN
			EXEC dbo.paCuentaParametroObtener @Codigo = 'CAJA_SOBRANTE', @CtaId = @cta_diferencia OUTPUT;
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			VALUES (@cta_caja, @diferencia, 0, CONCAT('Sobrante al cerrar la apertura ', @pca_id)),
				   (@cta_diferencia, 0, @diferencia, CONCAT('Sobrante al cerrar la apertura ', @pca_id));
		END
	END

	BEGIN TRANSACTION;

	UPDATE dbo.pos_caja_apertura
	   SET pca_estado = 'C',
		   pca_fecha_corte = SYSDATETIME(),
		   pca_fecha_cierre = SYSDATETIME(),
		   usu_id_cierre = @usu_id,
		   pca_monto_teorico_total = @teorico,
		   pca_monto_fisico_total = @fisico,
		   pca_diferencia = @diferencia,
		   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
	 WHERE pca_id = @pca_id;

	IF EXISTS (SELECT 1 FROM @detalle)
	BEGIN
		DECLARE @fecha DATE = CAST(GETDATE() AS DATE);
		DECLARE @descripcion VARCHAR(256) = CONCAT('Diferencia en el cierre de caja, apertura ', @pca_id);
		EXEC dbo.sp_contabilidad_insertar_asiento
			@asi_fecha = @fecha, @asi_descripcion = @descripcion, @asi_origen = 'CIERRE_CAJA', @asi_origen_id = @pca_id,
			@usu_id = @usu_id, @detalle = @detalle, @asi_id = @asi_id OUTPUT;
	END

	COMMIT TRANSACTION;
END;
GO

------------------------------------------------------------
-- 4. Nómina aprobada y anulada
------------------------------------------------------------
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
		THROW 52091, 'La nómina no tiene empleados; revise las fechas y los empleados activos.', 1;

	-- Una línea de partida por tipo de movimiento.
	DECLARE @cta_sueldos INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'NOMINA_SUELDOS_GASTO'),
			@cta_bonificacion INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'NOMINA_BONIFICACION'),
			@cta_igss INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'NOMINA_IGSS_POR_PAGAR'),
			@cta_liquido INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'NOMINA_SUELDOS_POR_PAGAR', @CtaId = @cta_liquido OUTPUT;

	DECLARE @lineas TABLE (cta_id INT NULL, Codigo VARCHAR(20) NOT NULL, Descripcion VARCHAR(100) NOT NULL, Naturaleza CHAR(1) NOT NULL, Monto NUMERIC(14, 2) NOT NULL);
	INSERT INTO @lineas (cta_id, Codigo, Descripcion, Naturaleza, Monto)
	SELECT COALESCE(tipo.cta_id,
					CASE WHEN tipo.Codigo = 'BONIF_INCENTIVO' THEN @cta_bonificacion
						 WHEN tipo.Codigo = 'IGSS_LABORAL' THEN @cta_igss
						 WHEN deta.Naturaleza = 'I' THEN @cta_sueldos END),
		   tipo.Codigo, tipo.Descripcion, deta.Naturaleza, SUM(deta.Monto)
	FROM dbo.rrhhNominaDetalle deta
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = deta.IdNominaEmpleado
	INNER JOIN dbo.rrhhTipoMovimientoNomina tipo ON tipo.IdTipoMovimientoNomina = deta.IdTipoMovimientoNomina
	WHERE nemp.IdNomina = @IdNomina
	GROUP BY tipo.IdTipoMovimientoNomina, tipo.cta_id, tipo.Codigo, tipo.Descripcion, deta.Naturaleza;

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

	DECLARE @detalle dbo.cont_asiento_det_type, @asi_id INT;
	INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
	SELECT cta_id,
		   CASE WHEN Naturaleza = 'I' THEN Monto ELSE 0 END,
		   CASE WHEN Naturaleza = 'D' THEN Monto ELSE 0 END,
		   Descripcion
	FROM @lineas;
	-- El líquido es ingresos menos descuentos, así que esta línea cuadra la partida.
	IF @liquido <> 0
		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_liquido, CASE WHEN @liquido < 0 THEN -@liquido ELSE 0 END, CASE WHEN @liquido > 0 THEN @liquido ELSE 0 END, 'Líquido a pagar a empleados');

	BEGIN TRANSACTION;

	-- Los movimientos manuales quedan ligados a esta nómina y ya no entran
	-- en ninguna otra.
	UPDATE movi SET IdNomina = @IdNomina, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	FROM dbo.rrhhMovimientoNomina movi
	INNER JOIN dbo.rrhhNominaDetalle deta ON deta.IdMovimientoNomina = movi.IdMovimientoNomina
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = deta.IdNominaEmpleado
	WHERE nemp.IdNomina = @IdNomina;

	UPDATE dbo.rrhhNomina
	   SET Estado = 'A', UsuarioAprobo = @UsuId, FechaAprobacion = SYSDATETIME(), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdNomina = @IdNomina;

	DECLARE @descripcion VARCHAR(256) = CONCAT('Nómina ', @descripcion_nomina);
	EXEC dbo.sp_contabilidad_insertar_asiento
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

	BEGIN TRANSACTION;
	-- Libera los movimientos manuales para que entren en otra nómina.
	UPDATE dbo.rrhhMovimientoNomina SET IdNomina = NULL, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE IdNomina = @IdNomina;
	UPDATE dbo.rrhhNomina SET Estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE IdNomina = @IdNomina;
	-- Si estaba aprobada, su partida también se anula.
	UPDATE dbo.cont_asiento_enc SET asi_estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE asi_origen = 'NOMINA' AND asi_origen_id = @IdNomina AND asi_estado = 'A';
	COMMIT TRANSACTION;
END;
GO
