------------------------------------------------------------------------------
-- 39_datos_sinteticos_inventario_saldos.sql
--
-- Datos de prueba de la fase B (script 38), grabados con sus procedimientos:
--
--   1. Inventario inicial de la bodega de Mixco: tres productos nuevos de
--      accesorios con su costo y precio de venta.
--   2. Inventario físico de la bodega principal: se cuentan los productos con
--      existencia; uno tiene 1 unidad de más y otro 1 de menos. Al aplicarlo
--      se generan el sobrante, el faltante y sus partidas.
--   3. Partida de apertura al 1 de enero: caja, banco, inventario (igual al
--      inventario inicial cargado) y capital.
--
-- Requiere 38. Se puede volver a correr: cada sección se omite si sus datos
-- ya existen.
------------------------------------------------------------------------------

USE [erp_db];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Inventario inicial de la bodega de Mixco
------------------------------------------------------------
DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
DECLARE @inicio_anio DATE = DATEFROMPARTS(YEAR(GETDATE()), 1, 1);
DECLARE @filas dbo.inv_carga_inicial_type;

IF EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_codigo = 'INI-ACC-001')
	PRINT 'Inventario inicial: ya se cargó, se omite la sección.';
ELSE
BEGIN
	INSERT INTO @filas (Fila, Sucursal, Bodega, Producto, Descripcion, Tipo, Unidad, Cantidad, CostoTotal, PrecioVenta)
	VALUES (2, 'SUC02', 'BOD02', 'INI-ACC-001', 'Mouse inalámbrico ergonómico', 'ACC', 'UND', 25, 2125.00, 149.00),
		   (3, 'SUC02', 'BOD02', 'INI-ACC-002', 'Cable HDMI 2 metros', 'ACC', 'UND', 40, 1400.00, 99.00),
		   (4, 'SUC02', 'BOD02', 'INI-ACC-003', 'Base refrigerante para laptop', 'ACC', 'UND', 12, 1620.00, 229.00);
	EXEC dbo.paInvCargaInicialProcesar @Fecha = @inicio_anio, @Filas = @filas, @SoloValidar = 0, @UsuId = @usu;
	PRINT 'Inventario inicial: 3 productos cargados en la bodega de Mixco.';
END
GO

------------------------------------------------------------
-- 2. Inventario físico de la bodega principal
------------------------------------------------------------
DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
DECLARE @bod INT = (SELECT bod_id FROM dbo.inv_bodega WHERE bod_codigo = 'BOD01');
DECLARE @toma INT, @conteos dbo.inv_toma_conteo_type;

IF EXISTS (SELECT 1 FROM dbo.inv_toma_fisica WHERE bod_id = @bod AND tfi_estado <> 'N')
	PRINT 'Inventario físico: la bodega principal ya tiene una toma, se omite la sección.';
ELSE
BEGIN
	DECLARE @fecha DATE = DATEADD(DAY, -1, CAST(GETDATE() AS DATE));
	EXEC dbo.paInvTomaCrear @BodId = @bod, @Fecha = @fecha, @Observaciones = 'Conteo de fin de mes', @SoloConExistencia = 1,
		@UsuId = @usu, @IdResultado = @toma OUTPUT;

	-- Todo cuadra salvo dos productos: el primero sobra 1 y el último falta 1.
	INSERT INTO @conteos (pro_id, conteo)
	SELECT deta.pro_id,
		   deta.tfd_existencia + CASE WHEN deta.pro_id = (SELECT MIN(pro_id) FROM dbo.inv_toma_fisica_det WHERE tfi_id = @toma) THEN 1
									  WHEN deta.pro_id = (SELECT MAX(pro_id) FROM dbo.inv_toma_fisica_det WHERE tfi_id = @toma AND tfd_existencia >= 1) THEN -1
									  ELSE 0 END
	FROM dbo.inv_toma_fisica_det deta WHERE deta.tfi_id = @toma;
	EXEC dbo.paInvTomaConteoGuardar @TfiId = @toma, @Conteos = @conteos, @UsuId = @usu;
	EXEC dbo.paInvTomaAplicar @TfiId = @toma, @UsuId = @usu;
	PRINT 'Inventario físico: toma de la bodega principal aplicada (un sobrante y un faltante).';
END
GO

------------------------------------------------------------
-- 3. Partida de apertura
------------------------------------------------------------
DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
DECLARE @inicio_anio DATE = DATEFROMPARTS(YEAR(GETDATE()), 1, 1);
DECLARE @saldos dbo.cont_saldo_inicial_type;
DECLARE @inventario DECIMAL(14, 2) = (SELECT ISNULL(SUM(enca.enc_monto_total), 0) FROM dbo.inv_documento_enc enca
									  INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_codigo = 'INVI'
									  WHERE enca.enc_estado = 'G');
DECLARE @cta_inventario VARCHAR(20) = (SELECT cuen.cta_codigo FROM dbo.cont_cuenta_parametro para
									   INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = para.cta_id WHERE para.ccp_codigo = 'INVENTARIO');

IF EXISTS (SELECT 1 FROM dbo.cont_asiento_enc WHERE asi_origen = 'APERTURA' AND asi_estado = 'A')
	PRINT 'Saldos iniciales: ya hay partida de apertura, se omite la sección.';
ELSE
BEGIN
	INSERT INTO @saldos (Fila, Codigo, Debe, Haber)
	VALUES (2, '1110006', 5000.00, NULL),
		   (3, '1120014', 150000.00, NULL),
		   (4, @cta_inventario, @inventario, NULL),
		   (5, '3410001', NULL, 155000.00 + @inventario);
	EXEC dbo.paContabilidadSaldosInicialesProcesar @Fecha = @inicio_anio, @Filas = @saldos, @SoloValidar = 0, @Reemplazar = 0, @UsuId = @usu;
	PRINT 'Saldos iniciales: partida de apertura grabada.';
END
GO
