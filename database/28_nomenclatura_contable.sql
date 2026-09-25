------------------------------------------------------------------------------
-- 28_nomenclatura_contable.sql
--
-- Nomenclatura contable definitiva, tomada de tbl_Nomenclatura_Contable
-- (DMOSOFT) y corregida para que la jerarquía la determinen las posiciones
-- del código:
--
--     Nivel 1  Grupo      1 posición    1
--     Nivel 2  Subgrupo   2 posiciones  11
--     Nivel 3  Cuenta     3 posiciones  111
--     Nivel 4  Subcuenta  7 posiciones  1110002   (cuenta + correlativo de 4)
--
-- Reglas que se validan en la base de datos (no solo en la pantalla):
--   * El código es numérico y su longitud define el nivel.
--   * El padre es el nodo cuyo código es el prefijo del nivel anterior.
--   * Solo la subcuenta (nivel 4) acepta movimiento; un grupo, subgrupo o
--     cuenta nunca recibe partidas.
--
-- Correcciones al archivo original (ver README, punto 26): se crean el
-- subgrupo 34 y la cuenta 140 que faltaban; 2160002 pasa a 216; se quitan los
-- niveles sobrantes 1161, 1221 y 1222; no se carga la rama 521/529 (sus
-- subcuentas sin equivalente pasan a 511 como 5110057-5110070); se agregan
-- 5110071 Faltantes de caja y 4110027 Sobrantes de caja. No se migran saldos.
--
-- Si la base tiene el catálogo de prueba anterior (1105, 1205...), sus
-- partidas, pólizas automáticas y tipos de movimiento de nómina se reasignan a
-- la cuenta equivalente y el catálogo de prueba se elimina.
--
-- Requiere 27_contabilidad_cuentas_parametro.sql. Se puede volver a correr.
------------------------------------------------------------------------------

USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Carga de la nomenclatura base
------------------------------------------------------------
-- Procedimiento para que 12_datos_sinteticos.sql también pueda sembrarla
-- después de vaciar las tablas. Solo carga si la nomenclatura no existe
-- (no hay grupo '1'); no pisa cambios hechos desde el mantenimiento.
CREATE OR ALTER PROCEDURE [dbo].[paNomenclaturaBaseCargar]
	@UsuId INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_codigo = '1')
		RETURN;

	DECLARE @base TABLE (
		Codigo		VARCHAR(20)		NOT NULL PRIMARY KEY,
		Nombre		NVARCHAR(128)	NOT NULL,
		Tipo		CHAR(1)			NOT NULL,
		Naturaleza	CHAR(1)			NOT NULL,
		FechaAlta	DATETIME2(0)	NULL
	);

	INSERT INTO @base (Codigo, Nombre, Tipo, Naturaleza, FechaAlta) VALUES
		('1', N'ACTIVO', 'A', 'D', '2005-01-01 00:00:00'),
		('11', N'CIRCULANTE', 'A', 'D', '2005-01-01 00:00:00'),
		('111', N'CAJA', 'A', 'D', '2005-01-01 00:00:00'),
		('1110002', N'CAJA CHICA', 'A', 'D', '2005-01-01 00:00:00'),
		('1110006', N'CAJA GENERAL', 'A', 'D', '2005-01-01 00:00:00'),
		('1110007', N'CAJA DOLAR', 'A', 'D', '2005-01-01 00:00:00'),
		('1110057', N'DIFERENCIAL CAJA DOLARES', 'A', 'D', '2005-01-01 00:00:00'),
		('1110099', N'CAJA MONEDA EXTRANJERA (DEPOSITOS)', 'A', 'D', '2005-01-01 00:00:00'),
		('112', N'BANCOS', 'A', 'D', '2005-01-01 00:00:00'),
		('1120014', N'BANCO INDUSTRIAL 198-009460-9', 'A', 'D', '2007-01-10 10:36:21'),
		('1120017', N'BANRURAL 3206001363-DEMOSOFT/RRR', 'A', 'D', '2018-02-20 09:45:59'),
		('1120018', N'BANCO INDUSTRIAL RRR 149-009783-7', 'A', 'D', '2018-03-21 16:45:32'),
		('1120019', N'Banco Industrial-Dolar - 149-017690-4', 'A', 'D', '2018-06-19 17:06:51'),
		('1120020', N'Diferencial cambiario Banco Industrial-Dolar - 149-017690-4', 'A', 'D', '2018-06-19 17:15:42'),
		('1120021', N'BANCO INDUSTRIAL PRUEBA - 123456789-0', 'A', 'D', '2020-11-26 17:12:46'),
		('1120022', N'CENTRO EDUCATIVO DEMOSOFT', 'A', 'D', '2026-05-06 07:00:59'),
		('113', N'CUENTAS POR COBRAR EMPLEADOS', 'A', 'D', '2005-01-01 00:00:00'),
		('1130001', N'CUENTAS POR COBRAR A EMPLEADOS', 'A', 'D', '2005-01-01 00:00:00'),
		('1130002', N'DESCUENTO A EMPLEADOS POR PRESTAMO', 'A', 'D', '2005-01-01 00:00:00'),
		('114', N'CUENTAS POR COBRAR', 'A', 'D', '2005-01-01 00:00:00'),
		('1140001', N'CLIENTES', 'A', 'D', '2006-03-22 17:31:54'),
		('116', N'INVENTARIO', 'A', 'D', '2005-02-17 21:22:53'),
		('1161001', N'INVENTARIO VALORIZADO', 'A', 'D', '2005-01-01 00:00:00'),
		('117', N'IVA POR COBRAR', 'A', 'D', '2005-01-01 00:00:00'),
		('1170001', N'IVA POR COBRAR', 'A', 'D', '2005-01-01 00:00:00'),
		('12', N'FIJO', 'A', 'D', '2005-01-01 00:00:00'),
		('121', N'VEHICULOS', 'A', 'D', '2005-01-01 00:00:00'),
		('1210001', N'VEHICULOS', 'A', 'D', '2005-01-01 00:00:00'),
		('122', N'MOBILIARIO Y EQUIPO', 'A', 'D', '2005-01-01 00:00:00'),
		('1221001', N'1221001 - MOBILIARIO Y EQUIPO', 'A', 'D', '2005-01-01 00:00:00'),
		('1221002', N'PLANTA TELEFONICA', 'A', 'D', '2005-01-01 00:00:00'),
		('1221003', N'ROTULOS', 'A', 'D', '2005-01-01 00:00:00'),
		('1222001', N'MOBILIARIO Y EQUIPO', 'A', 'H', '2005-01-01 00:00:00'),
		('1222002', N'PLANTA TELEFONICA', 'A', 'H', '2005-01-01 00:00:00'),
		('1222003', N'ROTULOS', 'A', 'H', '2005-01-01 00:00:00'),
		('123', N'TERRENOS', 'A', 'D', '2005-01-01 00:00:00'),
		('1230001', N'TERRENOS', 'A', 'D', '2005-01-01 00:00:00'),
		('124', N'EDIFICIOS', 'A', 'D', '2005-01-01 00:00:00'),
		('1240001', N'EDIFICIOS', 'A', 'D', '2005-01-01 00:00:00'),
		('1240002', N'INVERSIONES', 'A', 'D', '2006-07-18 17:17:23'),
		('125', N'EQUIPO DE COMPUTACIÓN', 'A', 'D', '2018-02-27 17:19:58'),
		('1250001', N'EQUIPO DE COMPUTACION', 'A', 'D', '2018-02-27 17:20:54'),
		('14', N'DIFERIDO', 'A', 'D', '2005-01-01 00:00:00'),
		('140', N'DIFERIDO', 'A', 'D', NULL),
		('1400001', N'PAGOS TRIMESTRALES ISR', 'A', 'D', '2005-01-01 00:00:00'),
		('1400002', N'PAGOS CUOTAS EMPRESAS MERCANTILES', 'A', 'D', '2005-01-01 00:00:00'),
		('1400003', N'MERMAS MENSUALES', 'A', 'D', '2005-03-03 13:04:54'),
		('1400005', N'OTROS ACTIVOS AMORTIZABLES', 'A', 'D', '2008-07-16 10:47:19'),
		('1400006', N'IVA RETENIDO POR ACREDITAR', 'A', 'D', '2018-05-31 12:43:52'),
		('1400007', N'GASTOS ANTICIPADOS', 'A', 'D', '2019-05-13 15:20:47'),
		('2', N'PASIVO', 'P', 'H', '2005-01-01 00:00:00'),
		('21', N'A CORTO PLAZO', 'P', 'H', '2005-01-01 00:00:00'),
		('211', N'CUENTAS POR PAGAR', 'P', 'H', '2005-01-01 00:00:00'),
		('2110001', N'IGSS CUOTAS LABORALES', 'P', 'H', '2005-01-01 00:00:00'),
		('2110002', N'IVA FACTURAS ESPECIALES', 'P', 'H', '2005-01-01 00:00:00'),
		('2110003', N'IMPUESTO SOBRE LA RENTA POR PAGAR', 'P', 'H', '2005-01-01 00:00:00'),
		('2110004', N'RETENCIONES ISR POR PAGAR', 'P', 'H', '2005-01-01 00:00:00'),
		('2110006', N'IVA RETENIDO', 'P', 'H', '2005-01-01 00:00:00'),
		('2110007', N'FONDO DE PENSIONES', 'P', 'H', '2005-01-01 00:00:00'),
		('2110008', N'MULTAS POR PAGAR', 'P', 'H', '2005-01-01 00:00:00'),
		('2110010', N'PRESTACIONES LABORALES POR PAGAR', 'P', 'H', '2005-01-01 00:00:00'),
		('2110011', N'GASTOS DE ALIMENTACION POR PAGAR', 'P', 'H', '2005-01-01 00:00:00'),
		('2110012', N'IVA POR PAGAR', 'P', 'H', '2018-04-18 15:59:21'),
		('2110013', N'SUELDOS POR PAGAR', 'P', 'H', '2019-04-02 10:23:54'),
		('2110014', N'CUENTAS POR PAGAR', 'P', 'H', '2021-08-30 17:28:27'),
		('2110015', N'CUENTAS POR PAGAR COLEGIO', 'P', 'H', '2005-06-09 09:27:57'),
		('212', N'INTERESES BANCARIOS', 'P', 'H', '2005-01-01 00:00:00'),
		('2120001', N'INTERESES BANCARIOS', 'P', 'H', '2005-01-01 00:00:00'),
		('214', N'PROVEEDORES', 'P', 'H', '2005-01-01 00:00:00'),
		('2140001', N'PROVEEDORES LOCALES', 'P', 'H', '2005-02-17 21:30:04'),
		('2140002', N'CUENTAS POR PAGAR', 'P', 'H', '2018-03-15 14:12:51'),
		('216', N'PRESTAMOS', 'P', 'H', '2005-01-01 00:00:00'),
		('2160001', N'PRESTAMOS BANCARIOS', 'P', 'H', '2005-01-01 00:00:00'),
		('2160003', N'PRÉSTAMOS DEMOSOFT S.A.', 'P', 'H', '2025-01-10 10:34:05'),
		('3', N'CAPITAL Y RESERVAS', 'K', 'H', '2005-01-01 00:00:00'),
		('34', N'CAPITAL Y RESERVAS', 'K', 'H', NULL),
		('341', N'CAPITAL Y RESERVAS', 'K', 'H', '2005-01-01 00:00:00'),
		('3410001', N'CAPITAL', 'K', 'H', '2005-01-01 00:00:00'),
		('3410002', N'UTILIDADES DEL EJERCICIO', 'K', 'H', '2005-01-01 00:00:00'),
		('3410003', N'UTILIDADES NO DISTRIBUIDAS', 'K', 'H', '2005-01-01 00:00:00'),
		('3410004', N'PERDIDAS DEL EJERCICIO', 'K', 'D', '2005-01-01 00:00:00'),
		('3410005', N'PERDIDAS DE EJERCICIOS ANTERIORES', 'K', 'D', '2005-01-01 00:00:00'),
		('3410006', N'Cuenta Puente Balance', 'K', 'H', '2018-08-07 16:55:30'),
		('4', N'INGRESOS', 'I', 'H', '2005-01-01 00:00:00'),
		('41', N'INGRESOS NETOS', 'I', 'H', '2005-01-01 00:00:00'),
		('411', N'INGRESOS BRUTOS', 'I', 'H', '2005-01-01 00:00:00'),
		('4110001', N'VENTAS', 'I', 'H', '2008-06-11 09:01:08'),
		('4110002', N'SERVICIOS', 'I', 'H', '2018-04-18 15:55:28'),
		('4110024', N'VENTA COMBUSTIBLE', 'I', 'H', '2005-01-01 00:00:00'),
		('4110025', N'Cuenta Puente Resultados', 'I', 'H', '2018-08-07 17:00:41'),
		('4110026', N'Otros ingresos', 'I', 'H', '2025-04-22 07:15:29'),
		('4110027', N'SOBRANTES DE CAJA', 'I', 'H', NULL),
		('412', N'COSTO DE VENTAS', 'I', 'D', '2005-01-01 00:00:00'),
		('4120111', N'COSTO DE HARDWARE', 'I', 'D', '2005-01-01 00:00:00'),
		('4120112', N'COSTO DE SOFTWARE', 'I', 'D', '2005-01-01 00:00:00'),
		('4120113', N'COSTO DE SERVICIOS', 'I', 'D', '2005-01-01 00:00:00'),
		('4120114', N'COSTO DE MERCADERIA', 'I', 'D', '2005-01-01 00:00:00'),
		('4120115', N'PARTICIPACIÓN EN FERIAS Y EVENTOS', 'I', 'D', '2025-01-10 10:27:20'),
		('5', N'GASTOS DE ADMINISTRACION Y OPERACION', 'G', 'D', '2005-01-01 00:00:00'),
		('51', N'GASTOS DE ADMINISTRACION Y OPERACION', 'G', 'D', '2005-01-01 00:00:00'),
		('511', N'GASTOS DE ADMINISTRACION', 'G', 'D', '2005-01-01 00:00:00'),
		('5110001', N'SUELDOS Y SALARIOS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110002', N'HORAS EXTRAS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110003', N'BONIFICACION INCENTIVO', 'G', 'D', '2005-01-01 00:00:00'),
		('5110004', N'BONO 14', 'G', 'D', '2005-01-01 00:00:00'),
		('5110005', N'AGUINALDO', 'G', 'D', '2005-01-01 00:00:00'),
		('5110006', N'VACACIONES', 'G', 'D', '2005-01-01 00:00:00'),
		('5110007', N'INDEMNIZACION', 'G', 'D', '2005-01-01 00:00:00'),
		('5110008', N'CUOTA PATRONAL IGSS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110009', N'BONIFICACION DECRETO 78-89', 'G', 'D', '2005-01-01 00:00:00'),
		('5110010', N'PAPELERIA Y UTILES', 'G', 'D', '2005-01-01 00:00:00'),
		('5110011', N'GASTOS DE REPRESENTACION', 'G', 'D', '2005-01-01 00:00:00'),
		('5110012', N'GASTOS DE MANTENIMIENTO', 'G', 'D', '2018-02-28 10:57:32'),
		('5110013', N'PARQUEOS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110014', N'TELEFONO CORREOS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110015', N'VIATICOS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110016', N'INTERNET', 'G', 'D', '2005-01-01 00:00:00'),
		('5110017', N'MANTENIMIENTO Y LIMPIEZA', 'G', 'D', '2005-01-01 00:00:00'),
		('5110018', N'VARIOS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110020', N'CAPACITACION Y EDUCACION', 'G', 'D', '2005-01-01 00:00:00'),
		('5110021', N'BENEFICIO A EMPLEADOS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110022', N'MATERIAL PROMOCIONAL', 'G', 'D', '2005-01-01 00:00:00'),
		('5110023', N'PUBLICIDAD Y PROPAGANDA', 'G', 'D', '2005-01-01 00:00:00'),
		('5110024', N'IMPUESTOS, CONTRIBUCIONES Y TASAS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110025', N'SEGUROS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110026', N'HONORARIOS PROFESIONALES', 'G', 'D', '2005-01-01 00:00:00'),
		('5110027', N'DEPRECIACIONES', 'G', 'D', '2005-01-01 00:00:00'),
		('5110028', N'REPUESTOS Y MANTENIMIENTO DE EQUIPO DE C', 'G', 'D', '2005-01-01 00:00:00'),
		('5110029', N'MANTENIMIENTO Y REPARACIÓN DE EDIFICIO', 'G', 'D', '2005-01-01 00:00:00'),
		('5110030', N'ALIMENTACION DEL PERSONAL', 'G', 'D', '2005-01-01 00:00:00'),
		('5110031', N'UNIFORMES', 'G', 'D', '2005-01-01 00:00:00'),
		('5110032', N'MATERIALES Y SUMINISTROS', 'G', 'D', '2018-04-29 12:44:54'),
		('5110033', N'GASTOS ADMINISTRATIVOS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110034', N'ASISTENCIA MEDICA Y MEDICINAS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110035', N'PAGO POR KILOMETRAJE', 'G', 'D', '2005-01-01 00:00:00'),
		('5110037', N'COMBUSTIBLES Y LUBRICANTES', 'G', 'D', '2005-01-01 00:00:00'),
		('5110038', N'REPUESTOS Y REPARACIONES DE VEHICULOS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110039', N'REPARACIONES VARIAS ADMINISTRACION', 'G', 'D', '2005-01-01 00:00:00'),
		('5110040', N'SUSCRIPCIONES', 'G', 'D', '2005-01-01 00:00:00'),
		('5110041', N'Reembolso', 'G', 'D', '2005-01-01 00:00:00'),
		('5110042', N'TRAMITES', 'G', 'D', '2005-01-01 00:00:00'),
		('5110049', N'ELECTRICIDAD', 'G', 'D', '2008-07-16 11:24:01'),
		('5110051', N'HOSPEDAJE', 'G', 'D', '2008-07-15 11:05:11'),
		('5110053', N'SERVICIOS DE IMPLEMENTACION', 'G', 'D', '2018-05-14 10:32:38'),
		('5110054', N'GASTOS NO DEDUCIBLES', 'G', 'D', '2019-05-13 14:31:33'),
		('5110055', N'GASTOS ANTICIPADOS', 'G', 'D', '2019-05-13 14:43:40'),
		('5110056', N'Anticipo sueldo', 'G', 'D', '2025-02-07 07:05:31'),
		('5110057', N'GASTOS RICARDO RANGEL R', 'G', 'D', '2005-01-01 00:00:00'),
		('5110058', N'GASTOS VEHICULOS DEMOSOFT.', 'G', 'D', '2005-01-01 00:00:00'),
		('5110059', N'SERVICIOS GPS', 'G', 'D', '2018-05-14 11:02:22'),
		('5110060', N'PAQUETERIA Y COURIER', 'G', 'D', '2005-01-01 00:00:00'),
		('5110061', N'CONTRATO FUNERARIO', 'G', 'D', '2005-01-01 00:00:00'),
		('5110062', N'GASTOS TARJETAS DE PRESENTACION', 'G', 'D', '2005-01-01 00:00:00'),
		('5110063', N'MULTAS VARIAS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110064', N'COMISIONES BANCARIAS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110065', N'PASAJES EMPLEADOS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110066', N'MANTENIMIENTO DE SOFTWARE', 'G', 'D', '2005-01-01 00:00:00'),
		('5110067', N'HERRAMIENTAS', 'G', 'D', '2005-01-01 00:00:00'),
		('5110068', N'UTENCILIOS DE LIMPIEZA/COCINA', 'G', 'D', '2005-01-01 00:00:00'),
		('5110069', N'AGUA POTABLE', 'G', 'D', '2018-04-26 16:02:10'),
		('5110070', N'ARRENDAMIENTO DE INMUEBLES Y OTROS', 'G', 'D', '2019-07-02 12:49:28'),
		('5110071', N'FALTANTES DE CAJA', 'G', 'D', NULL);

	-- Se inserta nivel por nivel para que cada nodo encuentre a su padre.
	DECLARE @longitud INT;
	DECLARE niveles CURSOR LOCAL FAST_FORWARD FOR SELECT v.l FROM (VALUES (1), (2), (3), (7)) v(l) ORDER BY v.l;
	OPEN niveles;
	FETCH NEXT FROM niveles INTO @longitud;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		INSERT INTO dbo.cont_cuenta_contable
			(cta_codigo, cta_nombre, cta_tipo, cta_naturaleza, cta_acepta_movimiento, cta_id_padre, cta_nivel, cta_estado, InsUsuario, InsFechaHora)
		SELECT base.Codigo, base.Nombre, base.Tipo, base.Naturaleza,
			   CASE WHEN @longitud = 7 THEN 1 ELSE 0 END,
			   padr.cta_id,
			   CASE @longitud WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 3 THEN 3 ELSE 4 END,
			   'A', @UsuId, ISNULL(base.FechaAlta, SYSDATETIME())
		FROM @base base
		LEFT JOIN dbo.cont_cuenta_contable padr
			ON padr.cta_codigo = LEFT(base.Codigo, CASE @longitud WHEN 2 THEN 1 WHEN 3 THEN 2 WHEN 7 THEN 3 END)
		WHERE LEN(base.Codigo) = @longitud
		  AND NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable cuen WHERE cuen.cta_codigo = base.Codigo);
		FETCH NEXT FROM niveles INTO @longitud;
	END
	CLOSE niveles;
	DEALLOCATE niveles;
END;
GO

------------------------------------------------------------
-- 2. Conceptos de pólizas automáticas
------------------------------------------------------------
-- Todos los conceptos y la subcuenta que usan con la nomenclatura. 12 lo
-- llama al regenerar los datos de prueba; aquí actualiza también los que ya
-- apuntaban a una cuenta del catálogo de prueba. La cuenta de bancos
-- (1120014) es provisional y se cambia en General > Cuentas de pólizas.
CREATE OR ALTER PROCEDURE [dbo].[paCuentaParametroCargarBase]
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @conceptos TABLE (Codigo VARCHAR(40) PRIMARY KEY, Descripcion VARCHAR(150), Naturaleza CHAR(1), Cuenta VARCHAR(20));
	INSERT INTO @conceptos VALUES
		('VENTA_CAJA',              'Venta: lo cobrado al facturar (contado o enganche)', 'D', '1110006'),
		('VENTA_CLIENTES',          'Venta: saldo a crédito del cliente',                 'D', '1140001'),
		('VENTA_INGRESO',           'Venta: ingreso por ventas (sin IVA)',                'H', '4110001'),
		('VENTA_IVA_DEBITO',        'Venta: IVA débito fiscal',                           'H', '2110012'),
		('VENTA_COSTO',             'Venta: costo de lo vendido',                         'D', '4120114'),
		('INVENTARIO',              'Inventario de mercadería',                           'H', '1161001'),
		('COMPRA_GASTO',            'Compra que no afecta inventario (gasto)',            'D', '5110033'),
		('COMPRA_IVA_CREDITO',      'Compra: IVA crédito fiscal',                         'D', '1170001'),
		('COMPRA_PROVEEDORES',      'Compra: cuentas por pagar a proveedores',            'H', '2140001'),
		('COBRO_CAJA',              'Cobro de cuota: ingreso a caja',                     'D', '1110006'),
		('COBRO_CLIENTES',          'Cobro de cuota: rebaja de la cuenta del cliente',    'H', '1140001'),
		('PAGO_PROVEEDORES',        'Pago con cheque: rebaja de la cuenta del proveedor', 'D', '2140001'),
		('PAGO_BANCOS',             'Pago con cheque: salida del banco',                  'H', '1120014'),
		('DEPOSITO_BANCOS',         'Depósito: ingreso al banco',                         'D', '1120014'),
		('DEPOSITO_CAJA',           'Depósito: salida de caja',                           'H', '1110006'),
		('CAJA_FALTANTE',           'Cierre de caja: faltante',                           'D', '5110071'),
		('CAJA_SOBRANTE',           'Cierre de caja: sobrante',                           'H', '4110027'),
		('NOMINA_SUELDOS_GASTO',    'Nómina: gasto de sueldos (ingresos del empleado)',   'D', '5110001'),
		('NOMINA_BONIFICACION',     'Nómina: gasto de bonificación incentivo',            'D', '5110003'),
		('NOMINA_IGSS_POR_PAGAR',   'Nómina: IGSS retenido por pagar',                    'H', '2110001'),
		('NOMINA_SUELDOS_POR_PAGAR','Nómina: líquido a pagar a empleados',                'H', '2110013');

	INSERT INTO dbo.cont_cuenta_parametro (ccp_codigo, ccp_descripcion, ccp_naturaleza, cta_id)
	SELECT conc.Codigo, conc.Descripcion, conc.Naturaleza, cuen.cta_id
	FROM @conceptos conc
	LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_codigo = conc.Cuenta
	WHERE NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_parametro para WHERE para.ccp_codigo = conc.Codigo);

	-- Conceptos sin cuenta o todavía en una cuenta que no es subcuenta
	-- (catálogo de prueba): se asigna la de la nomenclatura.
	UPDATE para SET cta_id = cuen.cta_id, UpdFechaHora = SYSDATETIME()
	FROM dbo.cont_cuenta_parametro para
	INNER JOIN @conceptos conc ON conc.Codigo = para.ccp_codigo
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_codigo = conc.Cuenta
	LEFT JOIN dbo.cont_cuenta_contable actu ON actu.cta_id = para.cta_id
	WHERE para.cta_id IS NULL OR LEN(actu.cta_codigo) <> 7;

	-- Tipos de movimiento de nómina: ingresos a sueldos, bonificación e IGSS a su cuenta.
	IF OBJECT_ID('dbo.rrhhTipoMovimientoNomina', 'U') IS NOT NULL
		UPDATE tipo SET cta_id = cuen.cta_id
		FROM dbo.rrhhTipoMovimientoNomina tipo
		INNER JOIN (VALUES ('SUELDO', '5110001'), ('HORAS_EXTRA', '5110002'), ('COMISION', '5110001'), ('OTRO_INGRESO', '5110001'),
						   ('BONIF_INCENTIVO', '5110003'), ('IGSS_LABORAL', '2110001')) v(tipo, cuenta) ON v.tipo = tipo.Codigo
		INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_codigo = v.cuenta
		LEFT JOIN dbo.cont_cuenta_contable actu ON actu.cta_id = tipo.cta_id
		WHERE tipo.cta_id IS NULL OR LEN(actu.cta_codigo) <> 7;
END;
GO

------------------------------------------------------------
-- 3. Migración desde el catálogo de prueba
------------------------------------------------------------
-- Antes de agregar las validaciones: el catálogo de prueba tiene códigos de
-- 4 posiciones que no las cumplen.
IF OBJECT_ID('dbo.trg_cont_cuenta_contable_jerarquia', 'TR') IS NOT NULL
	DROP TRIGGER dbo.trg_cont_cuenta_contable_jerarquia;
GO

EXEC dbo.paNomenclaturaBaseCargar;
GO

BEGIN TRANSACTION;

DECLARE @equivalencia TABLE (Anterior VARCHAR(20) PRIMARY KEY, Nueva VARCHAR(20) NOT NULL);
INSERT INTO @equivalencia VALUES
	('1105', '1110006'), ('1110', '1120014'), ('1150', '1170001'), ('1205', '1140001'), ('1310', '1161001'),
	('2105', '2140001'), ('2205', '2110012'), ('2305', '2110001'), ('2310', '2110013'),
	('4105', '4110001'), ('4205', '4110027'), ('5105', '4120114'), ('5205', '5110033'),
	('5210', '5110001'), ('5215', '5110003'), ('5220', '5110071');

DECLARE @mapa TABLE (IdAnterior INT PRIMARY KEY, IdNuevo INT NOT NULL);
INSERT INTO @mapa (IdAnterior, IdNuevo)
SELECT ante.cta_id, nuev.cta_id
FROM @equivalencia equi
INNER JOIN dbo.cont_cuenta_contable ante ON ante.cta_codigo = equi.Anterior
INNER JOIN dbo.cont_cuenta_contable nuev ON nuev.cta_codigo = equi.Nueva;

-- Cambiar la cuenta de una línea no altera los totales de la partida, así
-- que el trigger de balance de cont_asiento_det sigue satisfecho.
UPDATE deta SET cta_id = mapa.IdNuevo
FROM dbo.cont_asiento_det deta INNER JOIN @mapa mapa ON mapa.IdAnterior = deta.cta_id;

UPDATE para SET cta_id = mapa.IdNuevo
FROM dbo.cont_cuenta_parametro para INNER JOIN @mapa mapa ON mapa.IdAnterior = para.cta_id;

IF OBJECT_ID('dbo.rrhhTipoMovimientoNomina', 'U') IS NOT NULL
	UPDATE tipo SET cta_id = mapa.IdNuevo
	FROM dbo.rrhhTipoMovimientoNomina tipo INNER JOIN @mapa mapa ON mapa.IdAnterior = tipo.cta_id;

-- Catálogo de prueba: todo código que no cumple las posiciones. Primero las
-- hojas y luego sus agrupadores.
DELETE FROM dbo.cont_cuenta_contable
WHERE LEN(cta_codigo) NOT IN (1, 2, 3, 7) AND cta_acepta_movimiento = 1;
DELETE FROM dbo.cont_cuenta_contable
WHERE LEN(cta_codigo) NOT IN (1, 2, 3, 7);

COMMIT TRANSACTION;
GO

EXEC dbo.paCuentaParametroCargarBase;
GO

------------------------------------------------------------
-- 4. Validaciones de la jerarquía
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_cont_cuenta_contable_codigo_posiciones')
	ALTER TABLE dbo.cont_cuenta_contable WITH CHECK ADD CONSTRAINT [CK_cont_cuenta_contable_codigo_posiciones]
		CHECK (cta_codigo NOT LIKE '%[^0-9]%' AND LEN(cta_codigo) IN (1, 2, 3, 7));
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_cont_cuenta_contable_nivel_posiciones')
	ALTER TABLE dbo.cont_cuenta_contable WITH CHECK ADD CONSTRAINT [CK_cont_cuenta_contable_nivel_posiciones]
		CHECK (cta_nivel = CASE LEN(cta_codigo) WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 3 THEN 3 WHEN 7 THEN 4 END);
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_cont_cuenta_contable_movimiento_subcuenta')
	ALTER TABLE dbo.cont_cuenta_contable WITH CHECK ADD CONSTRAINT [CK_cont_cuenta_contable_movimiento_subcuenta]
		CHECK (cta_acepta_movimiento = CASE WHEN cta_nivel = 4 THEN 1 ELSE 0 END);
GO

-- El padre no se puede validar con un CHECK (depende de otra fila): el
-- trigger revisa, al final de cada sentencia, que cada nodo tocado y los
-- hijos de los nodos tocados cuelguen del nodo cuyo código es su prefijo.
CREATE OR ALTER TRIGGER [dbo].[trg_cont_cuenta_contable_jerarquia]
ON [dbo].[cont_cuenta_contable]
AFTER INSERT, UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

	IF EXISTS (
		SELECT 1
		FROM dbo.cont_cuenta_contable nodo
		LEFT JOIN dbo.cont_cuenta_contable padr ON padr.cta_id = nodo.cta_id_padre
		WHERE (nodo.cta_id IN (SELECT cta_id FROM inserted) OR nodo.cta_id_padre IN (SELECT cta_id FROM inserted))
		  AND NOT (
				(nodo.cta_nivel = 1 AND nodo.cta_id_padre IS NULL)
			 OR (nodo.cta_nivel > 1 AND padr.cta_nivel = nodo.cta_nivel - 1
				 AND LEFT(nodo.cta_codigo, LEN(padr.cta_codigo)) = padr.cta_codigo))
	)
		THROW 52400, 'El código de la cuenta no corresponde a su padre: debe empezar con el código del padre y estar en el nivel siguiente (grupo 1, subgrupo 2, cuenta 3 y subcuenta 7 posiciones).', 1;
END;
GO

------------------------------------------------------------
-- 5. Mantenimiento por nodos
------------------------------------------------------------
-- Árbol completo. El orden alfabético del código es el orden del árbol,
-- porque cada código empieza con el de su padre.
CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableArbolConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cuen.cta_id, cuen.cta_codigo, cuen.cta_nombre, cuen.cta_tipo, cuen.cta_naturaleza, cuen.cta_acepta_movimiento,
		   cuen.cta_id_padre, cuen.cta_nivel, cuen.cta_estado,
		   (SELECT COUNT(*) FROM dbo.cont_cuenta_contable hijo WHERE hijo.cta_id_padre = cuen.cta_id) AS CantidadHijos,
		   (SELECT COUNT(*) FROM dbo.cont_asiento_det deta WHERE deta.cta_id = cuen.cta_id) AS CantidadPartidas,
		   (SELECT COUNT(*) FROM dbo.cont_cuenta_parametro para WHERE para.cta_id = cuen.cta_id)
		   + (SELECT COUNT(*) FROM dbo.rrhhTipoMovimientoNomina tipo WHERE tipo.cta_id = cuen.cta_id) AS CantidadAsignaciones
	FROM dbo.cont_cuenta_contable cuen
	ORDER BY cuen.cta_codigo;
END;
GO

-- Siguiente código libre para un hijo de @IdPadre (NULL = nuevo grupo).
CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableSiguienteCodigo]
	@IdPadre	INT = NULL,
	@Codigo		VARCHAR(20) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @codigoPadre VARCHAR(20) = '', @nivelPadre INT = 0, @posiciones INT, @maximo INT;

	IF @IdPadre IS NOT NULL
	BEGIN
		SELECT @codigoPadre = cta_codigo, @nivelPadre = cta_nivel FROM dbo.cont_cuenta_contable WHERE cta_id = @IdPadre;
		IF @@ROWCOUNT = 0
			THROW 52401, 'La cuenta padre no existe.', 1;
		IF @nivelPadre = 4
			THROW 52402, 'Una subcuenta no puede tener cuentas debajo: es el último nivel de la nomenclatura.', 1;
	END

	-- Posiciones que agrega cada nivel: grupo 1, subgrupo 1, cuenta 1, subcuenta 4.
	SET @posiciones = CASE WHEN @nivelPadre = 3 THEN 4 ELSE 1 END;

	SELECT @maximo = MAX(CAST(SUBSTRING(cta_codigo, LEN(@codigoPadre) + 1, @posiciones) AS INT))
	FROM dbo.cont_cuenta_contable
	WHERE ISNULL(cta_id_padre, 0) = ISNULL(@IdPadre, 0);

	SET @maximo = ISNULL(@maximo, 0) + 1;
	IF @maximo > POWER(10, @posiciones) - 1
		THROW 52403, 'No quedan códigos libres en este nivel para la cuenta padre seleccionada.', 1;

	SET @Codigo = @codigoPadre + RIGHT(REPLICATE('0', @posiciones) + CAST(@maximo AS VARCHAR(10)), @posiciones);
END;
GO

-- Alta o edición de un nodo. En un alta el nivel, el tipo y el movimiento
-- salen del padre; @Tipo solo se usa al crear un grupo.
CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableNodoGuardar]
	@CtaId			INT = NULL,
	@IdPadre		INT = NULL,
	@Codigo			VARCHAR(20),
	@Nombre			VARCHAR(128),
	@Tipo			CHAR(1) = NULL,
	@Naturaleza		CHAR(1) = NULL,
	@UsuId			INT = NULL,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET @Codigo = LTRIM(RTRIM(@Codigo));
	SET @Nombre = LTRIM(RTRIM(@Nombre));
	IF @Nombre = '' OR @Codigo = ''
		THROW 52404, 'El código y el nombre son obligatorios.', 1;
	IF @Naturaleza IS NOT NULL AND @Naturaleza NOT IN ('D', 'H')
		THROW 52405, 'La naturaleza debe ser deudora (D) o acreedora (H).', 1;
	IF EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_codigo = @Codigo AND cta_id <> ISNULL(@CtaId, 0))
		THROW 52406, 'Ya existe una cuenta con ese código.', 1;

	IF @CtaId IS NULL
	BEGIN
		DECLARE @nivelPadre INT = 0, @codigoPadre VARCHAR(20) = '', @tipoPadre CHAR(1), @naturalezaPadre CHAR(1), @estadoPadre CHAR(1);
		IF @IdPadre IS NOT NULL
		BEGIN
			SELECT @nivelPadre = cta_nivel, @codigoPadre = cta_codigo, @tipoPadre = cta_tipo, @naturalezaPadre = cta_naturaleza, @estadoPadre = cta_estado
			FROM dbo.cont_cuenta_contable WHERE cta_id = @IdPadre;
			IF @@ROWCOUNT = 0
				THROW 52401, 'La cuenta padre no existe.', 1;
			IF @nivelPadre = 4
				THROW 52402, 'Una subcuenta no puede tener cuentas debajo: es el último nivel de la nomenclatura.', 1;
			IF @estadoPadre <> 'A'
				THROW 52407, 'No se pueden agregar cuentas debajo de una cuenta inactiva.', 1;
		END
		ELSE IF @Tipo IS NULL OR @Tipo NOT IN ('A', 'P', 'K', 'I', 'G')
			THROW 52408, 'Indique el tipo del grupo: Activo, Pasivo, Capital, Ingreso o Gasto.', 1;

		DECLARE @longitudEsperada INT = CASE @nivelPadre WHEN 0 THEN 1 WHEN 1 THEN 2 WHEN 2 THEN 3 ELSE 7 END;
		IF @Codigo LIKE '%[^0-9]%' OR LEN(@Codigo) <> @longitudEsperada OR LEFT(@Codigo, LEN(@codigoPadre)) <> @codigoPadre
		BEGIN
			DECLARE @mensaje NVARCHAR(300) = CONCAT(N'El código debe tener ', @longitudEsperada, N' posiciones numéricas',
				CASE WHEN @codigoPadre <> '' THEN CONCAT(N' y empezar con ', @codigoPadre) ELSE N'' END, N'.');
			THROW 52409, @mensaje, 1;
		END

		INSERT INTO dbo.cont_cuenta_contable
			(cta_codigo, cta_nombre, cta_tipo, cta_naturaleza, cta_acepta_movimiento, cta_id_padre, cta_nivel, cta_estado, InsUsuario, InsFechaHora)
		VALUES (@Codigo, @Nombre, ISNULL(@tipoPadre, @Tipo),
				COALESCE(@Naturaleza, @naturalezaPadre, CASE WHEN @Tipo IN ('A', 'G') THEN 'D' ELSE 'H' END),
				CASE WHEN @nivelPadre = 3 THEN 1 ELSE 0 END, @IdPadre, @nivelPadre + 1, 'A', @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
		RETURN;
	END

	DECLARE @codigoActual VARCHAR(20), @nivel INT;
	SELECT @codigoActual = cta_codigo, @nivel = cta_nivel FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId;
	IF @@ROWCOUNT = 0
		THROW 52410, 'La cuenta no existe.', 1;

	IF @Codigo <> @codigoActual
	BEGIN
		IF EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id_padre = @CtaId)
			THROW 52411, 'No se puede cambiar el código de una cuenta que tiene cuentas debajo; muévalas o elimínelas primero.', 1;
		IF EXISTS (SELECT 1 FROM dbo.cont_asiento_det WHERE cta_id = @CtaId)
			THROW 52412, 'No se puede cambiar el código de una cuenta que ya tiene partidas.', 1;
	END

	-- El tipo solo cambia en un grupo, y se propaga a toda su rama.
	UPDATE dbo.cont_cuenta_contable
	   SET cta_codigo = @Codigo, cta_nombre = @Nombre,
		   cta_naturaleza = ISNULL(@Naturaleza, cta_naturaleza),
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cta_id = @CtaId;

	IF @nivel = 1 AND @Tipo IS NOT NULL
		UPDATE dbo.cont_cuenta_contable SET cta_tipo = @Tipo WHERE LEFT(cta_codigo, 1) = LEFT(@Codigo, 1);

	SET @IdResultado = @CtaId;
END;
GO

-- Mueve un nodo (con toda su rama) debajo de otro nodo del nivel superior.
-- Como el código depende del padre, el nodo recibe el siguiente código libre
-- del nuevo padre y su rama se recodifica con el mismo prefijo.
CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableNodoMover]
	@CtaId			INT,
	@IdPadreNuevo	INT,
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @codigo VARCHAR(20), @nivel INT, @padreActual INT, @nivelPadre INT, @estadoPadre CHAR(1), @tipoNuevo CHAR(1);
	SELECT @codigo = cta_codigo, @nivel = cta_nivel, @padreActual = cta_id_padre FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId;
	IF @@ROWCOUNT = 0
		THROW 52410, 'La cuenta no existe.', 1;
	IF @nivel = 1
		THROW 52413, 'Un grupo no se puede mover: es el primer nivel de la nomenclatura.', 1;
	IF @padreActual = @IdPadreNuevo
		THROW 52414, 'La cuenta ya está debajo de ese padre.', 1;

	SELECT @nivelPadre = cta_nivel, @estadoPadre = cta_estado, @tipoNuevo = cta_tipo FROM dbo.cont_cuenta_contable WHERE cta_id = @IdPadreNuevo;
	IF @@ROWCOUNT = 0
		THROW 52401, 'La cuenta padre no existe.', 1;
	IF @nivelPadre <> @nivel - 1
		THROW 52415, 'El nuevo padre debe estar en el nivel inmediato superior (una subcuenta va debajo de una cuenta, una cuenta debajo de un subgrupo y un subgrupo debajo de un grupo).', 1;
	IF @estadoPadre <> 'A'
		THROW 52407, 'No se pueden agregar cuentas debajo de una cuenta inactiva.', 1;
	IF EXISTS (SELECT 1 FROM dbo.cont_asiento_det deta
			   INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = deta.cta_id
			   WHERE cuen.cta_codigo LIKE @codigo + '%')
		THROW 52416, 'No se puede mover: la cuenta o alguna de sus subcuentas ya tiene partidas y su código cambiaría.', 1;

	DECLARE @codigoNuevo VARCHAR(20);
	EXEC dbo.paCuentaContableSiguienteCodigo @IdPadre = @IdPadreNuevo, @Codigo = @codigoNuevo OUTPUT;

	-- Una sola sentencia: el trigger valida la rama completa ya recodificada.
	UPDATE dbo.cont_cuenta_contable
	   SET cta_codigo = @codigoNuevo + SUBSTRING(cta_codigo, LEN(@codigo) + 1, 20),
		   cta_id_padre = CASE WHEN cta_id = @CtaId THEN @IdPadreNuevo ELSE cta_id_padre END,
		   cta_tipo = @tipoNuevo,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cta_codigo LIKE @codigo + '%' AND LEN(cta_codigo) >= LEN(@codigo);
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableNodoCambiarEstado]
	@CtaId	INT,
	@Estado	CHAR(1),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @Estado NOT IN ('A', 'I')
		THROW 52417, 'El estado debe ser A (activa) o I (inactiva).', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId)
		THROW 52410, 'La cuenta no existe.', 1;
	IF @Estado = 'I' AND EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id_padre = @CtaId AND cta_estado = 'A')
		THROW 52418, 'Primero inactive las cuentas que están debajo de esta.', 1;
	IF @Estado = 'I' AND EXISTS (SELECT 1 FROM dbo.cont_cuenta_parametro WHERE cta_id = @CtaId)
		THROW 52419, 'La cuenta está asignada a una póliza automática (General > Cuentas de pólizas); asigne otra antes de inactivarla.', 1;
	IF @Estado = 'A' AND EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable hijo
								 INNER JOIN dbo.cont_cuenta_contable padr ON padr.cta_id = hijo.cta_id_padre
								 WHERE hijo.cta_id = @CtaId AND padr.cta_estado <> 'A')
		THROW 52420, 'Primero active la cuenta de la que depende.', 1;

	UPDATE dbo.cont_cuenta_contable SET cta_estado = @Estado, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE cta_id = @CtaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableNodoEliminar]
	@CtaId INT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId)
		THROW 52410, 'La cuenta no existe.', 1;
	IF EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id_padre = @CtaId)
		THROW 52421, 'No se puede eliminar: tiene cuentas debajo.', 1;
	IF EXISTS (SELECT 1 FROM dbo.cont_asiento_det WHERE cta_id = @CtaId)
		THROW 52422, 'No se puede eliminar: la cuenta tiene partidas. Puede inactivarla.', 1;
	IF EXISTS (SELECT 1 FROM dbo.cont_cuenta_parametro WHERE cta_id = @CtaId)
	   OR EXISTS (SELECT 1 FROM dbo.rrhhTipoMovimientoNomina WHERE cta_id = @CtaId)
		THROW 52423, 'No se puede eliminar: la cuenta está asignada a una póliza automática o a un tipo de movimiento de nómina.', 1;

	DELETE FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId;
END;
GO

------------------------------------------------------------
-- 6. Permiso del mantenimiento: Contador general y Administrador
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT 'CONTABILIDAD', 'CONTABILIDAD_NOMENCLATURA_ADMIN', 'Mantenimiento de la nomenclatura contable'
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_codigo = 'CONTABILIDAD_NOMENCLATURA_ADMIN');

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id, InsFechaHora)
SELECT rol.rol_id, perm.per_id, SYSDATETIME()
FROM dbo.sec_rol rol
CROSS JOIN dbo.sec_permiso perm
WHERE rol.rol_codigo IN ('ADMIN', 'CONTADOR')
  AND perm.per_codigo = 'CONTABILIDAD_NOMENCLATURA_ADMIN'
  AND NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO
