/*
================================================================================
 50_auditoria_robustez.sql
 Correcciones de la auditoría de los scripts 34 a 49 (procesos, contabilidad
 y robustez).

   1. Operaciones aplicadas dos veces. Varias anulaciones y recepciones
      validan el estado antes de abrir la transacción: si dos usuarios (o
      un doble clic) las ejecutan al mismo tiempo, las dos pasan la
      validación y el efecto se aplica dos veces (existencia devuelta dos
      veces al anular una factura, saldo devuelto dos veces a una cuota al
      anular un recibo o un cheque, mercadería sumada dos veces al recibir
      un traslado, dos pólizas al aprobar una nómina, ajuste de una toma
      física aplicado dos veces). Triggers de transición de estado rechazan
      el segundo cambio y revierten toda su transacción:
          inv_documento_enc   un documento anulado no cambia de estado
          pos_pago_enc        un recibo anulado no cambia de estado
          bco_cheque_emitido  un cheque anulado o cobrado no cambia de estado
          rrhhNomina          una nómina anulada no cambia; una aprobada solo
                              pasa a anulada
          inv_traslado        solo un traslado en tránsito cambia de estado
          inv_toma_fisica     una toma anulada no cambia; una aplicada solo
                              pasa a anulada
          rrhhNominaEmpleado  un empleado ya pagado no se paga en otro lote

   2. Existencia negativa. La venta valida la existencia antes de la
      transacción, y anular una compra o una carga inicial cuya mercadería
      ya se vendió dejaba la bodega en negativo. CHECK existencia >= 0 en
      inv_producto_existencia_bodega (solo si hoy no hay negativos; si los
      hay, se listan para corregirlos y se agrega al volver a correr).

   3. Pago de nómina por transferencia: el monto se calculaba fuera de la
      transacción; dos pagos simultáneos generaban un segundo lote vacío con
      póliza por el mismo monto. Ahora bloquea la nómina y calcula adentro.

   4. Períodos contables cerrados: ninguna póliza se graba ni se anula en un
      período con pdo_estado = 'C'.

   5. Índices para llaves foráneas que usan los procesos (cheques, notas,
      traslados, nómina) y para las pólizas por fecha.

   6. paAuditoriaIntegridadConsultar: revisión de integridad que se puede
      correr en cualquier momento (pólizas cuadradas, saldos de CxC y CxP
      contra sus pagos, existencias, pagos de nómina, pólizas faltantes).

 Requiere 34 a 49. Errores 54201-54210. Se puede volver a correr.
================================================================================
*/
USE [erp_db];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Transiciones de estado
------------------------------------------------------------
CREATE OR ALTER TRIGGER [dbo].[trg_inv_documento_enc_estado]
ON [dbo].[inv_documento_enc]
AFTER UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT UPDATE(enc_estado) RETURN;
	IF EXISTS (SELECT 1 FROM inserted nuev INNER JOIN deleted ante ON ante.enc_id = nuev.enc_id WHERE ante.enc_estado = 'A')
		THROW 54201, 'El documento ya fue anulado (quizá por otro usuario al mismo tiempo); no se aplicó ningún cambio. Actualice la pantalla.', 1;
END;
GO

CREATE OR ALTER TRIGGER [dbo].[trg_pos_pago_enc_estado]
ON [dbo].[pos_pago_enc]
AFTER UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT UPDATE(ppe_estado) RETURN;
	IF EXISTS (SELECT 1 FROM inserted nuev INNER JOIN deleted ante ON ante.ppe_id = nuev.ppe_id WHERE ante.ppe_estado = 'N')
		THROW 54202, 'El recibo ya fue anulado (quizá por otro usuario al mismo tiempo); no se aplicó ningún cambio. Actualice la pantalla.', 1;
END;
GO

CREATE OR ALTER TRIGGER [dbo].[trg_bco_cheque_emitido_enc_estado]
ON [dbo].[bco_cheque_emitido_enc]
AFTER UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT UPDATE(bce_estado_cheque) RETURN;
	-- Anulado: definitivo. Cobrado: no se anula (marcarlo cobrado otra vez no cambia nada).
	IF EXISTS (SELECT 1 FROM inserted nuev INNER JOIN deleted ante ON ante.bce_id = nuev.bce_id
			   WHERE ante.bce_estado_cheque = 'A' OR (ante.bce_estado_cheque = 'C' AND nuev.bce_estado_cheque <> 'C'))
		THROW 54203, 'El cheque ya fue anulado o cobrado (quizá por otro usuario al mismo tiempo); no se aplicó ningún cambio. Actualice la pantalla.', 1;
END;
GO

CREATE OR ALTER TRIGGER [dbo].[trg_rrhhNomina_estado]
ON [dbo].[rrhhNomina]
AFTER UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT UPDATE(Estado) RETURN;
	IF EXISTS (SELECT 1 FROM inserted nuev INNER JOIN deleted ante ON ante.IdNomina = nuev.IdNomina
			   WHERE ante.Estado = 'N' OR (ante.Estado = 'A' AND nuev.Estado <> 'N'))
		THROW 54204, 'La nómina ya fue aprobada o anulada (quizá por otro usuario al mismo tiempo); no se aplicó ningún cambio. Actualice la pantalla.', 1;
END;
GO

CREATE OR ALTER TRIGGER [dbo].[trg_inv_traslado_estado]
ON [dbo].[inv_traslado]
AFTER UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT UPDATE(tra_estado) RETURN;
	IF EXISTS (SELECT 1 FROM inserted nuev INNER JOIN deleted ante ON ante.tra_id = nuev.tra_id WHERE ante.tra_estado <> 'E')
		THROW 54205, 'El traslado ya fue recibido, rechazado o cancelado (quizá por otro usuario al mismo tiempo); no se aplicó ningún cambio. Actualice la pantalla.', 1;
END;
GO

CREATE OR ALTER TRIGGER [dbo].[trg_inv_toma_fisica_estado]
ON [dbo].[inv_toma_fisica]
AFTER UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT UPDATE(tfi_estado) RETURN;
	IF EXISTS (SELECT 1 FROM inserted nuev INNER JOIN deleted ante ON ante.tfi_id = nuev.tfi_id
			   WHERE ante.tfi_estado = 'N' OR (ante.tfi_estado = 'A' AND nuev.tfi_estado <> 'N'))
		THROW 54206, 'La toma ya fue aplicada o anulada (quizá por otro usuario al mismo tiempo); no se aplicó ningún cambio. Actualice la pantalla.', 1;
END;
GO

CREATE OR ALTER TRIGGER [dbo].[trg_rrhhNominaEmpleado_pago]
ON [dbo].[rrhhNominaEmpleado]
AFTER UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT UPDATE(IdNominaPago) RETURN;
	IF EXISTS (SELECT 1 FROM inserted nuev INNER JOIN deleted ante ON ante.IdNominaEmpleado = nuev.IdNominaEmpleado
			   WHERE ante.IdNominaPago IS NOT NULL AND nuev.IdNominaPago IS NOT NULL AND nuev.IdNominaPago <> ante.IdNominaPago)
		THROW 54207, 'Uno de los empleados ya se pagó en otro lote (quizá por otro usuario al mismo tiempo); no se aplicó ningún cambio. Actualice la pantalla.', 1;
END;
GO

------------------------------------------------------------
-- 2. Existencia nunca negativa
------------------------------------------------------------
IF OBJECT_ID('dbo.CK_inv_existencia_no_negativa', 'C') IS NULL
BEGIN
	IF EXISTS (SELECT 1 FROM dbo.inv_producto_existencia_bodega WHERE existencia < 0)
	BEGIN
		PRINT 'AVISO: hay existencias negativas; corríjalas (toma física) y vuelva a correr este script para activar la regla:';
		SELECT bode.bod_codigo AS Bodega, prod.pro_codigo AS Producto, prod.pro_descripcion AS Descripcion, exis.existencia AS Existencia
		FROM dbo.inv_producto_existencia_bodega exis
		INNER JOIN dbo.inv_bodega bode ON bode.bod_id = exis.bod_id
		INNER JOIN dbo.inv_producto prod ON prod.pro_id = exis.pro_id
		WHERE exis.existencia < 0;
	END
	ELSE
		ALTER TABLE dbo.inv_producto_existencia_bodega ADD CONSTRAINT [CK_inv_existencia_no_negativa] CHECK ([existencia] >= 0);
END
GO

------------------------------------------------------------
-- 3. Pago de nómina por transferencia (monto calculado con la nómina
--    bloqueada, dentro de la transacción)
------------------------------------------------------------
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

	BEGIN TRY
		BEGIN TRANSACTION;

		-- Un pago a la vez por nómina: el segundo espera y luego ya no
		-- encuentra empleados pendientes.
		DECLARE @descripcion_nomina VARCHAR(100);
		SELECT @descripcion_nomina = Descripcion FROM dbo.rrhhNomina WITH (UPDLOCK, HOLDLOCK) WHERE IdNomina = @IdNomina;

		DECLARE @monto NUMERIC(14, 2), @empleados INT;
		SELECT @monto = SUM(Liquido), @empleados = COUNT(*)
		FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina AND FormaPago = 'T' AND Liquido > 0 AND IdNominaPago IS NULL;
		IF ISNULL(@empleados, 0) = 0
			THROW 53430, 'No hay empleados pendientes de pago por transferencia en esta nómina (quizá otro usuario ya los pagó).', 1;

		INSERT INTO dbo.rrhhNominaPago (IdNomina, Tipo, bcb_id, FechaPago, Monto, Empleados, Referencia, InsUsuario)
		VALUES (@IdNomina, 'T', @BcbId, @Fecha, @monto, @empleados, NULLIF(LTRIM(RTRIM(@Referencia)), ''), @UsuId);
		SET @IdNominaPago = SCOPE_IDENTITY();

		UPDATE dbo.rrhhNominaEmpleado SET IdNominaPago = @IdNominaPago
		 WHERE IdNomina = @IdNomina AND FormaPago = 'T' AND Liquido > 0 AND IdNominaPago IS NULL;
		IF @@ROWCOUNT <> @empleados
			THROW 54208, 'Los empleados pendientes cambiaron mientras se registraba el pago; vuelva a intentarlo.', 1;

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

------------------------------------------------------------
-- 4. Períodos contables cerrados
------------------------------------------------------------
CREATE OR ALTER TRIGGER [dbo].[trg_cont_asiento_enc_periodo]
ON [dbo].[cont_asiento_enc]
AFTER INSERT, UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	-- Al anular se cambia el estado; una póliza nueva entra con su período.
	IF EXISTS (SELECT 1 FROM deleted) AND NOT UPDATE(asi_estado) AND NOT UPDATE(pdo_id) RETURN;
	DECLARE @periodo VARCHAR(10) = (
		SELECT TOP 1 CONCAT(peri.pdo_mes, '/', peri.pdo_anio)
		FROM inserted nuev
		INNER JOIN dbo.cont_periodo_contable peri ON peri.pdo_id = nuev.pdo_id
		LEFT JOIN deleted ante ON ante.asi_id = nuev.asi_id
		WHERE peri.pdo_estado = 'C' AND (ante.asi_id IS NULL OR ante.asi_estado <> nuev.asi_estado OR ante.pdo_id <> nuev.pdo_id));
	IF @periodo IS NOT NULL
	BEGIN
		DECLARE @mensaje NVARCHAR(300) = CONCAT(N'El período contable ', @periodo,
			N' está cerrado: no se graban ni se anulan pólizas en él. Registre el ajuste en un período abierto (p. ej. con una nota de crédito o débito).');
		THROW 54209, @mensaje, 1;
	END
END;
GO

------------------------------------------------------------
-- 5. Índices
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bco_cheque_det_ppg_id')
	CREATE INDEX [IX_bco_cheque_det_ppg_id] ON dbo.bco_cheque_emitido_det ([ppg_id]) WHERE [ppg_id] IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bco_cheque_enc_nomina_empleado')
	CREATE INDEX [IX_bco_cheque_enc_nomina_empleado] ON dbo.bco_cheque_emitido_enc ([IdNominaEmpleado]) WHERE [IdNominaEmpleado] IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_inv_proveedor_nota_aplicacion_ppg')
	CREATE INDEX [IX_inv_proveedor_nota_aplicacion_ppg] ON dbo.inv_proveedor_nota_aplicacion ([ppg_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_pos_cliente_nota_aplicacion_cpp')
	CREATE INDEX [IX_pos_cliente_nota_aplicacion_cpp] ON dbo.pos_cliente_nota_aplicacion ([cpp_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_inv_traslado_origen')
	CREATE INDEX [IX_inv_traslado_origen] ON dbo.inv_traslado ([bod_id_origen], [tra_estado]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_inv_documento_det_origen')
	CREATE INDEX [IX_inv_documento_det_origen] ON dbo.inv_documento_det ([det_id_origen]) WHERE [det_id_origen] IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cont_asiento_enc_fecha')
	CREATE INDEX [IX_cont_asiento_enc_fecha] ON dbo.cont_asiento_enc ([asi_fecha]) INCLUDE ([asi_estado], [asi_origen]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rrhhNomina_Compania')
	CREATE INDEX [IX_rrhhNomina_Compania] ON dbo.rrhhNomina ([cia_id], [Clase], [FechaAl]) INCLUDE ([Estado], [TipoPeriodo], [FechaPago]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rrhhNominaEmpleado_Empleado')
	CREATE INDEX [IX_rrhhNominaEmpleado_Empleado] ON dbo.rrhhNominaEmpleado ([IdEmpleado]) INCLUDE ([IdNomina], [DiasLaborados]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rrhhNominaEmpleado_Pago')
	CREATE INDEX [IX_rrhhNominaEmpleado_Pago] ON dbo.rrhhNominaEmpleado ([IdNominaPago]) WHERE [IdNominaPago] IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rrhhNominaEmpleado_Cheque')
	CREATE INDEX [IX_rrhhNominaEmpleado_Cheque] ON dbo.rrhhNominaEmpleado ([bce_id]) WHERE [bce_id] IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rrhhNominaPago_Nomina')
	CREATE INDEX [IX_rrhhNominaPago_Nomina] ON dbo.rrhhNominaPago ([IdNomina]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rrhhMovimientoNomina_Nomina')
	CREATE INDEX [IX_rrhhMovimientoNomina_Nomina] ON dbo.rrhhMovimientoNomina ([IdNomina]) WHERE [IdNomina] IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rrhhNominaDetalle_Movimiento')
	CREATE INDEX [IX_rrhhNominaDetalle_Movimiento] ON dbo.rrhhNominaDetalle ([IdMovimientoNomina]) WHERE [IdMovimientoNomina] IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rrhhHistorialPlaza_Empleado')
	CREATE INDEX [IX_rrhhHistorialPlaza_Empleado] ON dbo.rrhhHistorialPlaza ([IdEmpleado], [FechaAl]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rrhhEmpleado_Plaza')
	CREATE INDEX [IX_rrhhEmpleado_Plaza] ON dbo.rrhhEmpleado ([IdPlaza]) WHERE [IdPlaza] IS NOT NULL;
GO

------------------------------------------------------------
-- 6. Revisión de integridad
--
-- Una fila por control con la cantidad de casos y un ejemplo. Cantidad 0 =
-- todo bien. Los documentos internos de inventario inicial (INVI) no llevan
-- póliza y no se cuentan.
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paAuditoriaIntegridadConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @r TABLE (Orden INT, Control VARCHAR(120), Casos INT, Ejemplo VARCHAR(200));

	INSERT INTO @r
	SELECT 1, 'Pólizas descuadradas (Debe distinto del Haber)', COUNT(*), MIN(CAST(asi_id AS VARCHAR(20)))
	FROM (SELECT asi_id FROM dbo.cont_asiento_det GROUP BY asi_id HAVING SUM(asd_debe) <> SUM(asd_haber)) desc_;

	INSERT INTO @r
	SELECT 2, 'Líneas de póliza en cuentas de agrupación', COUNT(*), MIN(CONCAT('póliza ', deta.asi_id, ' cuenta ', cuen.cta_codigo))
	FROM dbo.cont_asiento_det deta INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = deta.cta_id
	WHERE cuen.cta_acepta_movimiento = 0;

	INSERT INTO @r
	SELECT 3, 'Documentos vigentes sin póliza vigente', COUNT(*), MIN(CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_numero_unico, docu.enc_numero_docto)))
	FROM dbo.inv_documento_enc docu
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	WHERE docu.enc_estado = 'G' AND tipo.tdo_codigo <> 'INVI'
	  AND NOT EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.enc_id = docu.enc_id AND asie.asi_estado = 'A')
	  AND NOT EXISTS (SELECT 1 FROM dbo.inv_traslado tras WHERE docu.enc_id IN (tras.enc_id_salida, tras.enc_id_ingreso, tras.enc_id_devolucion));

	INSERT INTO @r
	SELECT 4, 'Documentos anulados con póliza vigente', COUNT(*), MIN(CAST(docu.enc_id AS VARCHAR(20)))
	FROM dbo.inv_documento_enc docu
	WHERE docu.enc_estado = 'A' AND EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.enc_id = docu.enc_id AND asie.asi_estado = 'A'
											 AND asie.asi_origen NOT IN ('PAGO_CLIENTE', 'PAGO_PROVEEDOR'));

	INSERT INTO @r
	-- La nota de crédito rebaja el saldo de la cuota; la de débito crea una
	-- cuota nueva por su monto (no se resta).
	SELECT 5, 'Cuotas de clientes: saldo distinto de valor - cobros vigentes - notas de crédito', COUNT(*), MIN(CAST(cuot.cpp_id AS VARCHAR(20)))
	FROM dbo.pos_cliente_plan_pagos cuot
	CROSS APPLY (SELECT ISNULL(SUM(deta.ppd_valor_aplicado), 0) AS Cobrado
				 FROM dbo.pos_pago_det deta INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id
				 WHERE deta.cpp_id = cuot.cpp_id AND pago.ppe_estado = 'A') cobr
	CROSS APPLY (SELECT ISNULL(SUM(apli.cna_monto), 0) AS Notas
				 FROM dbo.pos_cliente_nota_aplicacion apli
				 INNER JOIN dbo.inv_documento_enc nota ON nota.enc_id = apli.enc_id_nota
				 INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = nota.tdo_id
				 WHERE apli.cpp_id = cuot.cpp_id AND tipo.tdo_codigo = 'NCC') nota
	WHERE ABS(cuot.cpp_valor_cuota - cobr.Cobrado - nota.Notas - cuot.cpp_saldo_cuota) > 0.01;

	INSERT INTO @r
	-- Las notas a proveedores cambian el valor de la cuota (o crean una), no lo pagado.
	SELECT 6, 'Cuotas de proveedores: pagado distinto de los cheques vigentes', COUNT(*), MIN(CAST(cuot.ppg_id AS VARCHAR(20)))
	FROM dbo.inv_proveedor_plan_pago cuot
	CROSS APPLY (SELECT ISNULL(SUM(deta.ced_valor), 0) AS Pagado
				 FROM dbo.bco_cheque_emitido_det deta INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = deta.bce_id
				 WHERE deta.ppg_id = cuot.ppg_id AND cheq.bce_estado_cheque <> 'A') cheq
	WHERE ABS(ISNULL(cuot.ppg_valor_real_pago, 0) - cheq.Pagado) > 0.01
	   OR ISNULL(cuot.ppg_valor_real_pago, 0) > cuot.ppg_valor_pago + 0.01;

	INSERT INTO @r
	SELECT 7, 'Existencias negativas', COUNT(*), MIN(CONCAT('producto ', pro_id, ' bodega ', bod_id))
	FROM dbo.inv_producto_existencia_bodega WHERE existencia < 0;

	INSERT INTO @r
	SELECT 8, 'Nóminas aprobadas sin póliza vigente', COUNT(*), MIN(nomi.Descripcion)
	FROM dbo.rrhhNomina nomi
	WHERE nomi.Estado = 'A' AND NOT EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.asi_origen = 'NOMINA' AND asie.asi_origen_id = nomi.IdNomina AND asie.asi_estado = 'A');

	INSERT INTO @r
	SELECT 9, 'Pagos de nómina vigentes que no suman el líquido de sus empleados', COUNT(*), MIN(CAST(pago.IdNominaPago AS VARCHAR(20)))
	FROM dbo.rrhhNominaPago pago
	CROSS APPLY (SELECT ISNULL(SUM(nemp.Liquido), 0) AS Liquido FROM dbo.rrhhNominaEmpleado nemp WHERE nemp.IdNominaPago = pago.IdNominaPago) suma
	WHERE pago.Estado = 'A' AND pago.Monto <> suma.Liquido;

	INSERT INTO @r
	SELECT 10, 'Empleados pagados en una nómina no aprobada', COUNT(*), MIN(CAST(nemp.IdNominaEmpleado AS VARCHAR(20)))
	FROM dbo.rrhhNominaEmpleado nemp INNER JOIN dbo.rrhhNomina nomi ON nomi.IdNomina = nemp.IdNomina
	WHERE nemp.IdNominaPago IS NOT NULL AND nomi.Estado <> 'A';

	INSERT INTO @r
	SELECT 11, 'Traslados en tránsito sin salida de inventario', COUNT(*), MIN(CAST(tras.tra_numero AS VARCHAR(20)))
	FROM dbo.inv_traslado tras
	WHERE tras.tra_estado = 'E' AND (tras.enc_id_salida IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.inv_documento_enc docu WHERE docu.enc_id = tras.enc_id_salida AND docu.enc_estado = 'G'));

	INSERT INTO @r
	SELECT 12, 'Recibos vigentes sin póliza vigente', COUNT(*), MIN(CAST(pago.ppe_id AS VARCHAR(20)))
	FROM dbo.pos_pago_enc pago
	WHERE pago.ppe_estado = 'A'
	  AND NOT EXISTS (SELECT 1 FROM dbo.pos_pago_det deta WHERE deta.ppe_id = pago.ppe_id AND deta.enc_id IS NOT NULL)
	  AND NOT EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.asi_origen = 'PAGO_CLIENTE' AND asie.asi_origen_id = pago.ppe_id AND asie.asi_estado = 'A');

	SELECT Orden, Control, Casos, CASE WHEN Casos = 0 THEN NULL ELSE Ejemplo END AS Ejemplo,
		   CASE WHEN Casos = 0 THEN 'OK' ELSE 'REVISAR' END AS Resultado
	FROM @r ORDER BY Orden;
END;
GO

EXEC dbo.paAuditoriaIntegridadConsultar;
GO
PRINT '50: auditoría de procesos aplicada.';
GO
