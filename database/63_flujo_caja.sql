/*
================================================================================
 63_flujo_caja.sql
 Flujo de caja real y proyectado.

   - Cuentas de efectivo: las de caja y bancos (por omisión los grupos 111 CAJA
     y 112 BANCOS y todo lo que cuelga de ellos); se pueden cambiar.
   - Real (método directo): por cada póliza vigente que mueve efectivo, lo que
     entra o sale de las cuentas de efectivo, clasificado en actividades de
     operación, inversión y financiamiento:
       * por el origen de la póliza (ventas y cobros = cobros a clientes;
         compras y pagos = pagos a proveedores; nómina = sueldos...);
       * en las demás (cheques libres, caja chica, pólizas manuales, activos
         fijos...) por la cuenta de contrapartida (12 activo fijo = inversión;
         216 préstamos y 3 capital = financiamiento; gastos = operación...).
     Los traslados entre cuentas de efectivo (depósitos) no son flujo.
   - Proyectado desde hoy: cuotas por cobrar a clientes, cuotas por pagar a
     proveedores (o su contraseña de pago con fecha), nómina promedio con sus
     cuotas patronales y partidas manuales (préstamos, impuestos, alquileres,
     una sola vez o cada mes). Lo vencido se proyecta para hoy.
   - Por semana o por mes, con saldo inicial y final.

 Errores nuevos: 55301 a 55320.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Configuración
------------------------------------------------------------
-- Cuentas de efectivo: una cuenta de cualquier nivel incluye sus subcuentas.
IF OBJECT_ID('dbo.fcj_cuenta_efectivo', 'U') IS NULL
CREATE TABLE dbo.fcj_cuenta_efectivo (
	[cta_id]		INT				NOT NULL CONSTRAINT [PK_fcj_cuenta_efectivo] PRIMARY KEY
									CONSTRAINT [FK_fcj_cuenta_efectivo_cuenta] REFERENCES dbo.cont_cuenta_contable ([cta_id]),
	[InsUsuario]	INT				NULL CONSTRAINT [FK_fcj_cuenta_efectivo_ins] REFERENCES dbo.gen_usuario ([usu_id]),
	[InsFechaHora]	DATETIME2(0)	NOT NULL CONSTRAINT [DF_fcj_cuenta_efectivo_ins] DEFAULT (SYSDATETIME())
);
GO
IF NOT EXISTS (SELECT 1 FROM dbo.fcj_cuenta_efectivo)
	INSERT INTO dbo.fcj_cuenta_efectivo (cta_id) SELECT cta_id FROM dbo.cont_cuenta_contable WHERE cta_codigo IN ('111', '112');
GO

-- Actividad: O operación, I inversión, F financiamiento.
IF OBJECT_ID('dbo.fcj_concepto_origen', 'U') IS NULL
CREATE TABLE dbo.fcj_concepto_origen (
	[asi_origen]	VARCHAR(20)		NOT NULL CONSTRAINT [PK_fcj_concepto_origen] PRIMARY KEY,
	[fco_actividad]	CHAR(1)			NOT NULL CONSTRAINT [CK_fcj_concepto_origen_actividad] CHECK ([fco_actividad] IN ('O', 'I', 'F')),
	[fco_concepto]	VARCHAR(100)	NOT NULL
);
GO
IF OBJECT_ID('dbo.fcj_concepto_cuenta', 'U') IS NULL
CREATE TABLE dbo.fcj_concepto_cuenta (
	[fcc_prefijo]	VARCHAR(20)		NOT NULL CONSTRAINT [PK_fcj_concepto_cuenta] PRIMARY KEY,
	[fcc_actividad]	CHAR(1)			NOT NULL CONSTRAINT [CK_fcj_concepto_cuenta_actividad] CHECK ([fcc_actividad] IN ('O', 'I', 'F')),
	[fcc_concepto]	VARCHAR(100)	NOT NULL
);
GO
INSERT INTO dbo.fcj_concepto_origen (asi_origen, fco_actividad, fco_concepto)
SELECT v.origen, v.actividad, v.concepto
FROM (VALUES
	('VENTA', 'O', 'Cobros a clientes'), ('PAGO_CLIENTE', 'O', 'Cobros a clientes'), ('NOTA_CREDITO', 'O', 'Cobros a clientes'),
	('NOTA_DEBITO', 'O', 'Cobros a clientes'), ('CIERRE_CAJA', 'O', 'Cobros a clientes'),
	('COMPRA', 'O', 'Pagos a proveedores'), ('PAGO_PROVEEDOR', 'O', 'Pagos a proveedores'), ('PAGO_TRANSFERENCIA', 'O', 'Pagos a proveedores'),
	('NOMINA', 'O', 'Sueldos y prestaciones'), ('PAGO_NOMINA', 'O', 'Sueldos y prestaciones'),
	('APERTURA', 'F', 'Saldos de apertura')) v (origen, actividad, concepto)
WHERE NOT EXISTS (SELECT 1 FROM dbo.fcj_concepto_origen conc WHERE conc.asi_origen = v.origen);
-- Por contrapartida: gana el prefijo más largo.
INSERT INTO dbo.fcj_concepto_cuenta (fcc_prefijo, fcc_actividad, fcc_concepto)
SELECT v.prefijo, v.actividad, v.concepto
FROM (VALUES
	('1', 'O', 'Otros movimientos de operación'),
	('114', 'O', 'Cobros a clientes'),
	('116', 'O', 'Pagos a proveedores'),
	('117', 'O', 'Gastos de operación'),
	('12', 'I', 'Compra y venta de activos fijos'),
	('14', 'O', 'Pagos anticipados'),
	('2', 'O', 'Otros pasivos'),
	('211', 'O', 'Impuestos, cuotas IGSS y retenciones'),
	('2110013', 'O', 'Sueldos y prestaciones'),
	('212', 'F', 'Intereses de préstamos'),
	('214', 'O', 'Pagos a proveedores'),
	('216', 'F', 'Préstamos recibidos y pagados'),
	('3', 'F', 'Aportes y retiros de capital'),
	('4', 'O', 'Otros ingresos'),
	('41101', 'O', 'Cobros a clientes'),
	('5', 'O', 'Gastos de operación')) v (prefijo, actividad, concepto)
WHERE NOT EXISTS (SELECT 1 FROM dbo.fcj_concepto_cuenta conc WHERE conc.fcc_prefijo = v.prefijo);
GO

-- Partidas proyectadas a mano (entradas positivas, salidas negativas); con
-- recurrencia M se repiten cada mes hasta la fecha final.
IF OBJECT_ID('dbo.fcj_partida', 'U') IS NULL
CREATE TABLE dbo.fcj_partida (
	[fcp_id]			INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_fcj_partida] PRIMARY KEY,
	[fcp_fecha]			DATE			NOT NULL,
	[fcp_actividad]		CHAR(1)			NOT NULL CONSTRAINT [CK_fcj_partida_actividad] CHECK ([fcp_actividad] IN ('O', 'I', 'F')),
	[fcp_concepto]		VARCHAR(100)	NOT NULL,
	[fcp_monto]			NUMERIC(14, 2)	NOT NULL CONSTRAINT [CK_fcj_partida_monto] CHECK ([fcp_monto] <> 0),
	[fcp_recurrencia]	CHAR(1)			NOT NULL CONSTRAINT [DF_fcj_partida_recurrencia] DEFAULT ('U') CONSTRAINT [CK_fcj_partida_recurrencia] CHECK ([fcp_recurrencia] IN ('U', 'M')),
	[fcp_fecha_fin]		DATE			NULL,
	[fcp_estado]		CHAR(1)			NOT NULL CONSTRAINT [DF_fcj_partida_estado] DEFAULT ('A') CONSTRAINT [CK_fcj_partida_estado] CHECK ([fcp_estado] IN ('A', 'I')),
	[InsUsuario]		INT				NULL CONSTRAINT [FK_fcj_partida_ins] REFERENCES dbo.gen_usuario ([usu_id]),
	[InsFechaHora]		DATETIME2(0)	NOT NULL CONSTRAINT [DF_fcj_partida_ins] DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL CONSTRAINT [FK_fcj_partida_upd] REFERENCES dbo.gen_usuario ([usu_id]),
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [CK_fcj_partida_fin] CHECK ([fcp_fecha_fin] IS NULL OR [fcp_fecha_fin] >= [fcp_fecha])
);
GO

INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT 'BANCOS', 'FLUJO_CAJA', 'Flujo de caja real y proyectado, y partidas proyectadas'
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_codigo = 'FLUJO_CAJA');
INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT rol.rol_id, perm.per_id
FROM dbo.sec_rol rol CROSS JOIN dbo.sec_permiso perm
WHERE rol.rol_codigo IN ('ADMIN', 'CONTADOR', 'CONTADOR_GENERAL') AND perm.per_codigo = 'FLUJO_CAJA'
  AND NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO

------------------------------------------------------------
-- 2. Funciones
------------------------------------------------------------
-- Cuentas de detalle que son efectivo.
CREATE OR ALTER FUNCTION [dbo].[fnFlujoCajaCuentas] ()
RETURNS TABLE
AS
RETURN
	SELECT DISTINCT deta.cta_id
	FROM dbo.fcj_cuenta_efectivo efec
	INNER JOIN dbo.cont_cuenta_contable padr ON padr.cta_id = efec.cta_id
	INNER JOIN dbo.cont_cuenta_contable deta ON deta.cta_codigo LIKE padr.cta_codigo + '%' AND deta.cta_acepta_movimiento = 1;
GO

-- Inicio del período: lunes de la semana (S) o primer día del mes (M).
CREATE OR ALTER FUNCTION [dbo].[fnFlujoCajaPeriodo] (@Fecha DATE, @Agrupar CHAR(1))
RETURNS DATE
AS
BEGIN
	RETURN CASE WHEN @Agrupar = 'S' THEN DATEADD(DAY, -(DATEDIFF(DAY, '19000101', @Fecha) % 7), @Fecha)
				ELSE DATEFROMPARTS(YEAR(@Fecha), MONTH(@Fecha), 1) END;
END;
GO

-- Saldo de efectivo al final de @Fecha.
CREATE OR ALTER FUNCTION [dbo].[fnFlujoCajaSaldo] (@Fecha DATE)
RETURNS NUMERIC(16, 2)
AS
BEGIN
	RETURN (SELECT ISNULL(SUM(deta.asd_debe - deta.asd_haber), 0)
			FROM dbo.cont_asiento_det deta
			INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id AND asie.asi_estado = 'A' AND asie.asi_fecha <= @Fecha
			WHERE deta.cta_id IN (SELECT cta_id FROM dbo.fnFlujoCajaCuentas()));
END;
GO

------------------------------------------------------------
-- 3. Flujo real
------------------------------------------------------------
-- Movimientos de efectivo por concepto. Resultado 1: saldo inicial.
-- Resultado 2: Periodo, Actividad, Concepto, Entradas, Salidas.
-- Resultado 3: pólizas del rango (para revisar de dónde sale cada cifra).
CREATE OR ALTER PROCEDURE [dbo].[paFlujoCajaRealConsultar]
	@Desde		DATE,
	@Hasta		DATE,
	@Agrupar	CHAR(1) = 'M'
AS
BEGIN
	SET NOCOUNT ON;
	IF @Hasta < @Desde
		THROW 55301, 'La fecha final no puede ser anterior a la inicial.', 1;
	SET @Agrupar = IIF(@Agrupar = 'S', 'S', 'M');

	DECLARE @efectivo TABLE (cta_id INT PRIMARY KEY);
	INSERT INTO @efectivo SELECT cta_id FROM dbo.fnFlujoCajaCuentas();

	-- Pólizas con movimiento neto de efectivo.
	DECLARE @polizas TABLE (asi_id INT PRIMARY KEY, fecha DATE, origen VARCHAR(20), descripcion VARCHAR(256), neto NUMERIC(16, 2));
	INSERT INTO @polizas
	SELECT asie.asi_id, asie.asi_fecha, asie.asi_origen, asie.asi_descripcion, SUM(deta.asd_debe - deta.asd_haber)
	FROM dbo.cont_asiento_enc asie
	INNER JOIN dbo.cont_asiento_det deta ON deta.asi_id = asie.asi_id
	INNER JOIN @efectivo efec ON efec.cta_id = deta.cta_id
	WHERE asie.asi_estado = 'A' AND asie.asi_fecha BETWEEN @Desde AND @Hasta
	GROUP BY asie.asi_id, asie.asi_fecha, asie.asi_origen, asie.asi_descripcion
	HAVING SUM(deta.asd_debe - deta.asd_haber) <> 0;

	-- Montos clasificados: por origen, o por cada contrapartida (Haber − Debe
	-- de las líneas que no son efectivo, que suman el neto de la póliza).
	DECLARE @montos TABLE (asi_id INT, fecha DATE, actividad CHAR(1), concepto VARCHAR(100), monto NUMERIC(16, 2));
	INSERT INTO @montos
	SELECT poli.asi_id, poli.fecha, orig.fco_actividad, orig.fco_concepto, poli.neto
	FROM @polizas poli INNER JOIN dbo.fcj_concepto_origen orig ON orig.asi_origen = poli.origen;

	INSERT INTO @montos
	SELECT poli.asi_id, poli.fecha, ISNULL(conc.fcc_actividad, 'O'), ISNULL(conc.fcc_concepto, 'Otros movimientos de operación'), deta.asd_haber - deta.asd_debe
	FROM @polizas poli
	INNER JOIN dbo.cont_asiento_det deta ON deta.asi_id = poli.asi_id
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = deta.cta_id
	OUTER APPLY (SELECT TOP 1 fcc_actividad, fcc_concepto FROM dbo.fcj_concepto_cuenta
				 WHERE cuen.cta_codigo LIKE fcc_prefijo + '%' ORDER BY LEN(fcc_prefijo) DESC) conc
	WHERE NOT EXISTS (SELECT 1 FROM dbo.fcj_concepto_origen orig WHERE orig.asi_origen = poli.origen)
	  AND NOT EXISTS (SELECT 1 FROM @efectivo efec WHERE efec.cta_id = deta.cta_id)
	  AND deta.asd_haber - deta.asd_debe <> 0;

	SELECT dbo.fnFlujoCajaSaldo(DATEADD(DAY, -1, @Desde)) AS SaldoInicial, dbo.fnFlujoCajaSaldo(@Hasta) AS SaldoFinal;

	SELECT dbo.fnFlujoCajaPeriodo(fecha, @Agrupar) AS Periodo, actividad AS Actividad, concepto AS Concepto,
		   SUM(IIF(monto > 0, monto, 0)) AS Entradas, SUM(IIF(monto < 0, -monto, 0)) AS Salidas
	FROM @montos
	GROUP BY dbo.fnFlujoCajaPeriodo(fecha, @Agrupar), actividad, concepto
	ORDER BY Periodo, actividad, concepto;

	SELECT poli.asi_id AS AsiId, poli.fecha AS Fecha, poli.origen AS Origen, poli.descripcion AS Descripcion, poli.neto AS Neto,
		   (SELECT TOP 1 CONCAT(mont.actividad, '|', mont.concepto) FROM @montos mont WHERE mont.asi_id = poli.asi_id ORDER BY ABS(mont.monto) DESC) AS Clasificacion
	FROM @polizas poli
	ORDER BY poli.fecha, poli.asi_id;
END;
GO

------------------------------------------------------------
-- 4. Flujo proyectado
------------------------------------------------------------
-- Desde hoy hasta @Hasta. Resultado 1: saldo de efectivo hoy.
-- Resultado 2: Fecha, Actividad, Concepto, Monto (+ entra, − sale), Detalle, Vencido.
CREATE OR ALTER PROCEDURE [dbo].[paFlujoCajaProyectadoConsultar]
	@Hasta	DATE
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
	IF @Hasta < @hoy
		THROW 55302, 'La proyección va de hoy en adelante: elija una fecha final futura.', 1;

	DECLARE @items TABLE (fecha DATE, actividad CHAR(1), concepto VARCHAR(100), monto NUMERIC(16, 2), detalle VARCHAR(200), vencido BIT);

	-- Cuotas por cobrar.
	INSERT INTO @items
	SELECT IIF(cuot.cpp_fecha_maxima_pago < @hoy, @hoy, cuot.cpp_fecha_maxima_pago), 'O',
		   IIF(cuot.cpp_fecha_maxima_pago < @hoy, 'Cobros a clientes (cuotas vencidas)', 'Cobros a clientes'),
		   cuot.cpp_saldo_cuota,
		   LEFT(CONCAT(LTRIM(CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos)), ' · ', tipo.tdo_codigo, ' ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto, ' cuota ', cuot.cpp_nro_cuota), 200),
		   IIF(cuot.cpp_fecha_maxima_pago < @hoy, 1, 0)
	FROM dbo.pos_cliente_plan_pagos cuot
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	LEFT JOIN dbo.pos_cliente clie ON clie.cli_id = cuot.cli_id
	WHERE cuot.cpp_estado IN ('P', 'V') AND cuot.cpp_saldo_cuota > 0 AND cuot.cpp_fecha_maxima_pago <= @Hasta;

	-- Contraseñas de pago pendientes: se pagan en su fecha.
	INSERT INTO @items
	SELECT IIF(cont.cpa_fecha_pago < @hoy, @hoy, cont.cpa_fecha_pago), 'O', 'Contraseñas de pago a proveedores', -cont.cpa_total,
		   LEFT(CONCAT(cont.cpa_numero, ' · ', prov.prv_nombre_comercial), 200), IIF(cont.cpa_fecha_pago < @hoy, 1, 0)
	FROM dbo.cxp_contrasena_enc cont
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = cont.prv_id
	WHERE cont.cpa_estado = 'E' AND cont.cpa_fecha_pago <= @Hasta;

	-- Cuotas por pagar que no están en una contraseña pendiente.
	INSERT INTO @items
	SELECT IIF(cuot.ppg_fecha_pago < @hoy, @hoy, cuot.ppg_fecha_pago), 'O',
		   IIF(cuot.ppg_fecha_pago < @hoy, 'Pagos a proveedores (cuotas vencidas)', 'Pagos a proveedores'),
		   -(cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0)),
		   LEFT(CONCAT(prov.prv_nombre_comercial, ' · ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto, ' cuota ', cuot.ppg_nro_pago), 200),
		   IIF(cuot.ppg_fecha_pago < @hoy, 1, 0)
	FROM dbo.inv_proveedor_plan_pago cuot
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = docu.prv_id
	WHERE cuot.ppg_estado IN ('P', 'V') AND cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) > 0 AND cuot.ppg_fecha_pago <= @Hasta
	  AND NOT EXISTS (SELECT 1 FROM dbo.cxp_contrasena_det deta INNER JOIN dbo.cxp_contrasena_enc cont ON cont.cpa_id = deta.cpa_id AND cont.cpa_estado = 'E'
					  WHERE deta.ppg_id = cuot.ppg_id);

	-- Nómina: promedio mensual de las nóminas ordinarias de los últimos 3 meses
	-- (o la última): líquido al fin de mes, cuotas y retenciones el 15 del siguiente.
	DECLARE @liquido NUMERIC(16, 2), @cuotas NUMERIC(16, 2), @meses INT;
	SELECT @liquido = SUM(TotalLiquido), @cuotas = SUM(TotalDescuentos + ISNULL(TotalPatronal, 0)),
		   @meses = COUNT(DISTINCT CONCAT(YEAR(FechaPago), '-', MONTH(FechaPago)))
	FROM dbo.rrhhNomina
	WHERE Clase = 'O' AND Estado <> 'N' AND FechaPago >= DATEADD(MONTH, -3, @hoy);
	IF ISNULL(@meses, 0) = 0
		SELECT TOP 1 @liquido = TotalLiquido, @cuotas = TotalDescuentos + ISNULL(TotalPatronal, 0), @meses = 1
		FROM dbo.rrhhNomina WHERE Clase = 'O' AND Estado <> 'N' ORDER BY FechaPago DESC;
	IF ISNULL(@meses, 0) > 0
	BEGIN
		SET @liquido = ROUND(@liquido / @meses, 2);
		SET @cuotas = ROUND(@cuotas / @meses, 2);
		DECLARE @mes DATE = DATEFROMPARTS(YEAR(@hoy), MONTH(@hoy), 1);
		WHILE @mes <= @Hasta
		BEGIN
			-- Si la nómina del mes ya se pagó no se vuelve a proyectar.
			IF EOMONTH(@mes) BETWEEN @hoy AND @Hasta
			   AND NOT EXISTS (SELECT 1 FROM dbo.rrhhNomina WHERE Clase = 'O' AND Estado <> 'N' AND FechaPago BETWEEN @mes AND EOMONTH(@mes)
							   AND EXISTS (SELECT 1 FROM dbo.rrhhNominaEmpleado empl WHERE empl.IdNomina = rrhhNomina.IdNomina AND (empl.bce_id IS NOT NULL OR empl.IdNominaPago IS NOT NULL)))
				INSERT INTO @items VALUES (EOMONTH(@mes), 'O', 'Sueldos (promedio de nóminas)', -@liquido, 'Líquido promedio mensual', 0);
			IF DATEADD(DAY, 14, @mes) BETWEEN @hoy AND @Hasta
				INSERT INTO @items VALUES (DATEADD(DAY, 14, @mes), 'O', 'Cuotas IGSS, IRTRA, INTECAP y retenciones', -@cuotas, 'Del mes anterior (promedio)', 0);
			SET @mes = DATEADD(MONTH, 1, @mes);
		END
	END

	-- Partidas manuales (una vez o cada mes).
	INSERT INTO @items
	SELECT fech.fecha, part.fcp_actividad, part.fcp_concepto, part.fcp_monto, IIF(part.fcp_recurrencia = 'M', 'Mensual', 'Partida proyectada'), 0
	FROM dbo.fcj_partida part
	CROSS APPLY (SELECT DATEADD(MONTH, nume.n, part.fcp_fecha) AS fecha
				 FROM (SELECT TOP (IIF(part.fcp_recurrencia = 'M', 120, 1)) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n FROM sys.all_objects) nume) fech
	WHERE part.fcp_estado = 'A' AND fech.fecha BETWEEN @hoy AND @Hasta
	  AND (part.fcp_fecha_fin IS NULL OR fech.fecha <= part.fcp_fecha_fin);

	SELECT dbo.fnFlujoCajaSaldo(@hoy) AS SaldoInicial;
	SELECT fecha AS Fecha, actividad AS Actividad, concepto AS Concepto, monto AS Monto, detalle AS Detalle, vencido AS Vencido
	FROM @items ORDER BY fecha, actividad, concepto;
END;
GO

------------------------------------------------------------
-- 5. Partidas proyectadas y configuración
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paFlujoCajaPartidaConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT fcp_id AS FcpId, fcp_fecha AS Fecha, fcp_actividad AS Actividad, fcp_concepto AS Concepto, fcp_monto AS Monto,
		   fcp_recurrencia AS Recurrencia, fcp_fecha_fin AS FechaFin, fcp_estado AS Estado
	FROM dbo.fcj_partida
	ORDER BY fcp_estado, fcp_fecha;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFlujoCajaPartidaGuardar]
	@FcpId			INT = NULL OUTPUT,
	@Fecha			DATE,
	@Actividad		CHAR(1),
	@Concepto		VARCHAR(100),
	@Monto			NUMERIC(14, 2),
	@Recurrencia	CHAR(1) = 'U',
	@FechaFin		DATE = NULL,
	@Estado			CHAR(1) = 'A',
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @Concepto = NULLIF(LTRIM(RTRIM(@Concepto)), '');
	IF @Fecha IS NULL OR @Concepto IS NULL
		THROW 55303, 'Indique la fecha y el concepto de la partida.', 1;
	IF ISNULL(@Monto, 0) = 0
		THROW 55304, 'El monto no puede ser cero (positivo si entra dinero, negativo si sale).', 1;
	IF @Actividad NOT IN ('O', 'I', 'F')
		THROW 55305, 'La actividad es O (operación), I (inversión) o F (financiamiento).', 1;
	IF @Recurrencia = 'U' SET @FechaFin = NULL;
	IF @FechaFin IS NOT NULL AND @FechaFin < @Fecha
		THROW 55306, 'La fecha final de la repetición no puede ser anterior a la primera fecha.', 1;
	IF @FcpId IS NULL
	BEGIN
		INSERT INTO dbo.fcj_partida (fcp_fecha, fcp_actividad, fcp_concepto, fcp_monto, fcp_recurrencia, fcp_fecha_fin, fcp_estado, InsUsuario)
		VALUES (@Fecha, @Actividad, @Concepto, @Monto, ISNULL(@Recurrencia, 'U'), @FechaFin, ISNULL(@Estado, 'A'), @UsuId);
		SET @FcpId = SCOPE_IDENTITY();
	END
	ELSE
		UPDATE dbo.fcj_partida
		   SET fcp_fecha = @Fecha, fcp_actividad = @Actividad, fcp_concepto = @Concepto, fcp_monto = @Monto, fcp_recurrencia = ISNULL(@Recurrencia, 'U'),
			   fcp_fecha_fin = @FechaFin, fcp_estado = ISNULL(@Estado, 'A'), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE fcp_id = @FcpId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFlujoCajaCuentaConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cuen.cta_id AS CtaId, cuen.cta_codigo AS Codigo, cuen.cta_nombre AS Nombre,
		   (SELECT COUNT(*) FROM dbo.cont_cuenta_contable deta WHERE deta.cta_codigo LIKE cuen.cta_codigo + '%' AND deta.cta_acepta_movimiento = 1) AS Cuentas
	FROM dbo.fcj_cuenta_efectivo efec
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = efec.cta_id
	ORDER BY cuen.cta_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paFlujoCajaCuentaGuardar]
	@Cuentas	dbo.id_lista_type READONLY,
	@UsuId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF NOT EXISTS (SELECT 1 FROM @Cuentas)
		THROW 55307, 'Elija al menos una cuenta de efectivo (caja o bancos).', 1;
	IF EXISTS (SELECT 1 FROM @Cuentas list LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = list.id WHERE cuen.cta_id IS NULL OR cuen.cta_tipo <> 'A')
		THROW 55308, 'Las cuentas de efectivo deben ser cuentas de activo.', 1;
	BEGIN TRANSACTION;
		DELETE FROM dbo.fcj_cuenta_efectivo WHERE cta_id NOT IN (SELECT id FROM @Cuentas);
		INSERT INTO dbo.fcj_cuenta_efectivo (cta_id, InsUsuario)
		SELECT DISTINCT id, @UsuId FROM @Cuentas WHERE id NOT IN (SELECT cta_id FROM dbo.fcj_cuenta_efectivo);
	COMMIT TRANSACTION;
END;
GO

------------------------------------------------------------
-- 6. Datos de demostración: cuota del préstamo y alquiler mensuales.
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.fcj_partida)
   AND EXISTS (SELECT 1 FROM dbo.cont_asiento_enc WHERE asi_descripcion LIKE 'Desembolso de préstamo bancario%')
BEGIN
	INSERT INTO dbo.fcj_partida (fcp_fecha, fcp_actividad, fcp_concepto, fcp_monto, fcp_recurrencia, fcp_fecha_fin, InsUsuario)
	VALUES ('20261030', 'F', 'Cuota del préstamo bancario (capital e intereses)', -25500, 'M', '20310930', 1),
		   ('20261005', 'O', 'Alquiler de bodega', -6500, 'M', NULL, 1),
		   ('20261115', 'O', 'Pago trimestral de ISR', -12000, 'U', NULL, 1);
END
GO

PRINT '63_flujo_caja.sql aplicado.';
GO
