------------------------------------------------------------------------------
-- 30_datos_sinteticos_procesos.sql
--
-- Datos de prueba de los procesos que el 12 no puede generar porque sus
-- procedimientos se crean después (caja en 23/26, RRHH en 25, partidas en
-- 29). Igual que el 12, todo pasa por los procedimientos de la aplicación,
-- así que también sirve de prueba de humo de sus partidas contables:
--
--   1. Caja: tres cobros de cuota en efectivo, un depósito al banco, conteo
--      con un faltante de Q2.00 (dentro de la tolerancia) y cierre. Después
--      se abre una caja nueva para que el cajero de prueba pueda seguir
--      cobrando.
--   2. Nómina del mes en curso: se crea, se calcula y se aprueba.
--
-- Para que el cierre con faltante sea posible, si la compañía tiene
-- tolerancia de cierre 0 se sube a Q5.00.
--
-- Requiere 12 a 29. Se puede volver a correr: cada sección se omite si ya
-- hay depósitos o si ya existe la nómina del mes.
------------------------------------------------------------------------------

USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Caja: cobros en efectivo, depósito y cierre con faltante
------------------------------------------------------------
DECLARE @pca_id INT = (SELECT TOP 1 pca_id FROM dbo.pos_caja_apertura WHERE pca_estado = 'A' ORDER BY pca_id);

IF EXISTS (SELECT 1 FROM dbo.pos_caja_deposito)
	PRINT 'Caja: ya hay depósitos, se omite la sección.';
ELSE IF @pca_id IS NULL
	PRINT 'Caja: no hay una apertura activa, se omite la sección.';
ELSE
BEGIN
	DECLARE @pcr_id INT = (SELECT pcr_id FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id);
	DECLARE @usu_cajero INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'mgarcia');
	DECLARE @pft_efectivo INT = (SELECT pft_id FROM dbo.pos_pago_forma_tipo WHERE pft_descripcion = 'Efectivo');
	DECLARE @gef_banco INT = (SELECT gef_id FROM dbo.gen_entidad_financiera WHERE gef_codigo = 'BI');
	DECLARE @hoy DATE = CAST(GETDATE() AS DATE);

	-- Los cobros del 12 se grabaron antes de que existieran las formas de pago
	-- (24): se completan como Efectivo para que entren al cuadre de esta caja.
	INSERT INTO dbo.pos_pago_forma (pft_id, ppf_monto, ppe_id, InsUsuario, InsFechaHora)
	SELECT @pft_efectivo, apli.Monto, pago.ppe_id, pago.usu_id, SYSDATETIME()
	FROM dbo.pos_pago_enc pago
	CROSS APPLY (SELECT SUM(deta.ppd_valor_aplicado) AS Monto FROM dbo.pos_pago_det deta WHERE deta.ppe_id = pago.ppe_id) apli
	WHERE pago.pca_id = @pca_id AND apli.Monto > 0
	  AND NOT EXISTS (SELECT 1 FROM dbo.pos_pago_forma form WHERE form.ppe_id = pago.ppe_id);

	-- Tres cuotas pendientes cobradas en efectivo.
	DECLARE @cpp_id INT, @saldo NUMERIC(12, 2), @ppe_id INT;
	DECLARE @formas dbo.pago_forma_type;
	DECLARE cobros_cur CURSOR LOCAL FAST_FORWARD FOR
		SELECT TOP 3 cpp_id, cpp_saldo_cuota FROM dbo.pos_cliente_plan_pagos WHERE cpp_estado = 'P' ORDER BY cpp_fecha_maxima_pago, cpp_id;
	OPEN cobros_cur;
	FETCH NEXT FROM cobros_cur INTO @cpp_id, @saldo;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		DELETE FROM @formas;
		INSERT INTO @formas (pft_id, ppf_monto) VALUES (@pft_efectivo, @saldo);
		EXEC dbo.sp_pos_registrar_pago_cuota @cpp_id = @cpp_id, @valor_pago = @saldo, @pca_id = @pca_id, @usu_id = @usu_cajero,
			@formas_pago = @formas, @ppe_id = @ppe_id OUTPUT;
		FETCH NEXT FROM cobros_cur INTO @cpp_id, @saldo;
	END
	CLOSE cobros_cur; DEALLOCATE cobros_cur;

	-- La mitad del efectivo cobrado (en quetzales enteros) se deposita al banco.
	DECLARE @efectivo NUMERIC(12, 2) = (SELECT ISNULL(SUM(forma.ppf_monto), 0) FROM dbo.pos_pago_forma forma
		INNER JOIN dbo.pos_pago_enc penc ON penc.ppe_id = forma.ppe_id WHERE penc.pca_id = @pca_id AND forma.pft_id = @pft_efectivo);
	DECLARE @deposito NUMERIC(14, 2) = FLOOR(@efectivo / 2), @pcd_id INT;
	IF @deposito > 0
		EXEC dbo.paCajaDepositoInsertar @pca_id = @pca_id, @gef_id = @gef_banco, @pcd_fecha_deposito = @hoy,
			@pcd_valor_deposito = @deposito, @pcd_numero_boleta = 'BOL-0001', @pcd_observaciones = 'Depósito de prueba',
			@usu_id = @usu_cajero, @pcd_id = @pcd_id OUTPUT;

	UPDATE comp SET cia_tolerancia_cierre_caja = 5.00, UpdFechaHora = SYSDATETIME()
	FROM dbo.gen_compania comp
	INNER JOIN dbo.gen_sucursal sucu ON sucu.cia_id = comp.cia_id
	INNER JOIN dbo.pos_caja_receptora caja ON caja.suc_id = sucu.suc_id
	WHERE caja.pcr_id = @pcr_id AND ISNULL(comp.cia_tolerancia_cierre_caja, 0) = 0;

	-- Conteo del efectivo: Q2.00 menos que el teórico, en billetes de Q1 y
	-- monedas de Q0.01 para no depender de los montos generados.
	DECLARE @teorico_efectivo NUMERIC(12, 2) = (SELECT pca_monto_inicial FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id) + @efectivo - @deposito;
	DECLARE @contado NUMERIC(12, 2) = @teorico_efectivo - 2.00;
	DECLARE @denominaciones dbo.caja_denominacion_type;
	INSERT INTO @denominaciones (def_tipo_denominacion, def_denominacion, def_cantidad)
	VALUES ('B', 1.00, FLOOR(@contado)),
		   ('M', 0.01, (@contado - FLOOR(@contado)) * 100);
	EXEC dbo.paCajaDesgloseEfectivoGuardar @pca_id = @pca_id, @denominaciones = @denominaciones, @usu_id = @usu_cajero;

	EXEC dbo.sp_pos_caja_cerrar @pca_id = @pca_id, @usu_id = @usu_cajero;

	DECLARE @pca_nueva INT;
	EXEC dbo.sp_pos_caja_abrir @pcr_id = @pcr_id, @usu_id = @usu_cajero, @pca_monto_inicial = 0, @pca_id = @pca_nueva OUTPUT;
END
GO

------------------------------------------------------------
-- 2. Nómina del mes en curso
------------------------------------------------------------
DECLARE @inicio_mes DATE = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
DECLARE @fin_mes DATE = EOMONTH(@inicio_mes);
DECLARE @cia INT = (SELECT TOP 1 cia_id FROM dbo.rrhhEmpleado ORDER BY cia_id);
DECLARE @usu_admin INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');

IF @cia IS NULL
	PRINT 'Nómina: no hay empleados, se omite la sección.';
ELSE IF EXISTS (SELECT 1 FROM dbo.rrhhNomina WHERE cia_id = @cia AND FechaDel = @inicio_mes AND Estado <> 'N')
	PRINT 'Nómina: la del mes ya existe, se omite la sección.';
ELSE
BEGIN
	DECLARE @descripcion VARCHAR(100) = CONCAT('Nómina ', FORMAT(@inicio_mes, 'MMMM yyyy', 'es-GT'));
	DECLARE @id_nomina INT;
	EXEC dbo.paRrhhNominaCrear @CiaId = @cia, @Descripcion = @descripcion, @TipoPeriodo = 'M',
		@FechaDel = @inicio_mes, @FechaAl = @fin_mes, @FechaPago = @fin_mes, @UsuId = @usu_admin, @IdResultado = @id_nomina OUTPUT;
	EXEC dbo.paRrhhNominaCalcular @IdNomina = @id_nomina, @UsuId = @usu_admin;
	EXEC dbo.paRrhhNominaAprobar @IdNomina = @id_nomina, @UsuId = @usu_admin;
END
GO

------------------------------------------------------------
-- Resumen: partidas por origen y verificación de cuadre
------------------------------------------------------------
SELECT asie.asi_origen, COUNT(*) AS partidas,
	   SUM(CASE WHEN tota.Debe <> tota.Haber THEN 1 ELSE 0 END) AS descuadradas
FROM dbo.cont_asiento_enc asie
CROSS APPLY (SELECT SUM(asd_debe) AS Debe, SUM(asd_haber) AS Haber FROM dbo.cont_asiento_det WHERE asi_id = asie.asi_id) tota
GROUP BY asie.asi_origen
ORDER BY asie.asi_origen;
GO
