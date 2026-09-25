/*
	Script 12: Datos sintéticos para pruebas.

	Volumen "ligero": catálogos con 20-50 filas y unas ~80-120 transacciones
	de negocio (compras, ventas, cobros y pagos con cheque), generadas a
	través de los procedimientos de 10_procedimientos_crud.sql y
	11_procedimientos_procesos.sql -- así esta misma carga de datos sirve
	como prueba de humo de todo el paquete (incluida la corrección de los
	bugs del script original: correlativos, existencias, asientos).

	Los montos, nombres y NIT/DPI son ficticios.

	Este script se puede correr las veces que se quiera: el primer bloque
	deja todas las tablas en cero antes de volver a sembrar datos, así que
	nunca queda nada duplicado ni a medias por una corrida anterior que
	haya fallado.
*/
USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
GO

------------------------------------------------------------
-- Limpieza: deja todas las tablas en cero antes de sembrar datos, para
-- que este script se pueda volver a correr sin duplicar nada.
--
-- No se usa TRUNCATE TABLE porque SQL Server no permite truncar una tabla
-- referenciada por una FOREIGN KEY, y en este modelo casi todas lo son.
-- En su lugar: se desactivan todas las llaves foráneas, se borra el
-- contenido de cada tabla con DELETE (con las FK desactivadas ya no
-- importa el orden), se reinicia el contador IDENTITY de cada tabla a 0
-- (el mismo efecto que tendría un TRUNCATE) y al final se vuelven a
-- activar y revalidar todas las llaves foráneas.
------------------------------------------------------------
DECLARE @sql NVARCHAR(MAX);

SET @sql = N'';
SELECT @sql = @sql + N'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name)
	+ N' NOCHECK CONSTRAINT ALL;' + CHAR(10)
FROM sys.tables t
WHERE EXISTS (SELECT 1 FROM sys.foreign_keys fk WHERE fk.parent_object_id = t.object_id);
EXEC sp_executesql @sql;

SET @sql = N'';
SELECT @sql = @sql + N'DELETE FROM ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N';' + CHAR(10)
FROM sys.tables t
WHERE SCHEMA_NAME(t.schema_id) = N'dbo';
EXEC sp_executesql @sql;

-- Solo se reinician las tablas que ya tuvieron filas: en una tabla recién
-- creada (last_value NULL), RESEED 0 hace que la primera fila reciba el id 0
-- en lugar de 1, y la aplicación usa 0 como "Seleccione..." en los combos.
SET @sql = N'';
SELECT @sql = @sql + N'DBCC CHECKIDENT (''dbo.' + t.name + N''', RESEED, 0);' + CHAR(10)
FROM sys.tables t
WHERE SCHEMA_NAME(t.schema_id) = N'dbo'
  AND EXISTS (SELECT 1 FROM sys.identity_columns ic WHERE ic.object_id = t.object_id AND ic.last_value IS NOT NULL);
EXEC sp_executesql @sql;

SET @sql = N'';
SELECT @sql = @sql + N'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name)
	+ N' WITH CHECK CHECK CONSTRAINT ALL;' + CHAR(10)
FROM sys.tables t
WHERE EXISTS (SELECT 1 FROM sys.foreign_keys fk WHERE fk.parent_object_id = t.object_id);
EXEC sp_executesql @sql;
GO

------------------------------------------------------------
-- Geografía
------------------------------------------------------------
INSERT INTO dbo.gen_pais (pai_nombre, pai_codigo_alfa2, pai_codigo_alfa3, pai_codigo_numero, pai_nacionalidad) VALUES
('Guatemala', 'GT', 'GTM', '320', 'Guatemalteca'),
('México', 'MX', 'MEX', '484', 'Mexicana'),
('El Salvador', 'SV', 'SLV', '222', 'Salvadoreña'),
('Honduras', 'HN', 'HND', '340', 'Hondureña'),
('Estados Unidos', 'US', 'USA', '840', 'Estadounidense');
GO

DECLARE @gt INT = (SELECT pai_id FROM dbo.gen_pais WHERE pai_codigo_alfa2 = 'GT');

INSERT INTO dbo.gen_estado (est_codigo, pai_id, est_nombre) VALUES
('GU', @gt, 'Guatemala'),
('SA', @gt, 'Sacatepéquez'),
('QZ', @gt, 'Quetzaltenango'),
('ES', @gt, 'Escuintla'),
('AV', @gt, 'Alta Verapaz'),
('CH', @gt, 'Chimaltenango');
GO

INSERT INTO dbo.gen_provincia (prov_codigo, est_id, prov_nombre)
SELECT v.prov_codigo, e.est_id, v.prov_nombre
FROM (VALUES
	('01', 'GU', 'Ciudad de Guatemala'), ('02', 'GU', 'Mixco'), ('03', 'GU', 'Villa Nueva'),
	('01', 'SA', 'Antigua Guatemala'), ('02', 'SA', 'Jocotenango'),
	('01', 'QZ', 'Quetzaltenango'), ('02', 'QZ', 'Salcajá'),
	('01', 'ES', 'Escuintla'), ('02', 'ES', 'Puerto San José'),
	('01', 'AV', 'Cobán'),
	('01', 'CH', 'Chimaltenango')
) v(prov_codigo, est_codigo, prov_nombre)
INNER JOIN dbo.gen_estado e ON e.est_codigo = v.est_codigo;
GO

INSERT INTO dbo.gen_profesion (prf_descripcion) VALUES
('Ingeniero en Sistemas'), ('Administrador de Empresas'), ('Contador General'),
('Técnico en Redes'), ('Abogado'), ('Médico'), ('Arquitecto'), ('Diseñador Gráfico'),
('Estudiante'), ('Comerciante');
GO

------------------------------------------------------------
-- Moneda
------------------------------------------------------------
INSERT INTO dbo.gen_moneda (mon_codigo, mon_nombre, mon_simbolo, mon_es_local) VALUES
('GTQ', 'Quetzal', 'Q', 1),
('USD', 'Dólar estadounidense', '$', 0);
GO

INSERT INTO dbo.gen_tipo_cambio (mon_id, tpc_fecha, tpc_valor)
SELECT mon_id, d, 7.75 + (CHECKSUM(NEWID()) % 20) / 100.0
FROM dbo.gen_moneda
CROSS APPLY (VALUES (CAST(DATEADD(MONTH, -2, GETDATE()) AS DATE)), (CAST(DATEADD(MONTH, -1, GETDATE()) AS DATE)), (CAST(GETDATE() AS DATE))) AS f(d)
WHERE mon_codigo = 'USD';
GO

------------------------------------------------------------
-- Compañía / sucursales / bancos
------------------------------------------------------------
INSERT INTO dbo.gen_compania (cia_nombre_comercial, cia_direccion, cia_representante_legal, cia_nit, cia_telefono, cia_email) VALUES
('Servicios Informáticos Quetzal, S.A.', '5a. Avenida 10-25 Zona 10, Ciudad de Guatemala', 'María Fernanda López Castillo', '1234567-8', '22334455', 'contacto@siq.com.gt');
GO

DECLARE @cia INT = (SELECT cia_id FROM dbo.gen_compania);

INSERT INTO dbo.gen_sucursal (suc_codigo, suc_descripcion, suc_direccion, suc_telefono, cia_id) VALUES
('SUC01', 'Casa matriz Zona 10', '5a. Avenida 10-25 Zona 10', '22334455', @cia),
('SUC02', 'Sucursal Zona 4 Mixco', 'Centro Comercial Utz Ulew, local 12', '22336677', @cia);
GO

INSERT INTO dbo.gen_entidad_financiera_tipo (geft_descripcion) VALUES ('Banco'), ('Tarjeta de crédito/débito');
GO

INSERT INTO dbo.gen_entidad_financiera (geft_id, gef_codigo, gef_descripcion)
SELECT (SELECT geft_id FROM dbo.gen_entidad_financiera_tipo WHERE geft_descripcion = 'Banco'), v.codigo, v.nombre
FROM (VALUES ('BI', 'Banco Industrial'), ('BAM', 'Banco Agromercantil'), ('GYT', 'Banco G&T Continental'),
			 ('BANRURAL', 'Banrural')) v(codigo, nombre);

INSERT INTO dbo.gen_entidad_financiera (geft_id, gef_codigo, gef_descripcion)
SELECT (SELECT geft_id FROM dbo.gen_entidad_financiera_tipo WHERE geft_descripcion = 'Tarjeta de crédito/débito'), v.codigo, v.nombre
FROM (VALUES ('VISA', 'Visa'), ('MC', 'Mastercard')) v(codigo, nombre);
GO

INSERT INTO dbo.bco_motivo_pago (bmp_descripcion) VALUES
('Pago a proveedores'), ('Pago de servicios'), ('Gastos varios'), ('Devolución a cliente');
GO

-- EXEC no acepta una subconsulta ni ninguna otra expresión directamente
-- como valor de un parámetro con nombre: solo constantes o variables. Por
-- eso en todo este script cada (SELECT ...) que antes iba pegado al
-- parámetro ahora se resuelve primero en una variable.
DECLARE @bcb_id INT;
DECLARE @gef_bi_id INT = (SELECT gef_id FROM dbo.gen_entidad_financiera WHERE gef_codigo = 'BI');
EXEC dbo.sp_cuenta_bancaria_insertar
	@bcb_numero_cuenta = '301-0001122-3', @bcb_descripcion = 'Cuenta monetaria BI',
	@gef_id = @gef_bi_id, @bcb_id = @bcb_id OUTPUT;

INSERT INTO dbo.bco_cuenta_bancaria_chequera (cbc_cheque_del, cbc_cheque_al, cbc_fecha_recepcion_chequera, bcb_id)
VALUES (1001, 1100, DATEADD(MONTH, -3, GETDATE()), @bcb_id);
GO

------------------------------------------------------------
-- Contabilidad: catálogo de cuentas y periodo inicial
------------------------------------------------------------
INSERT INTO dbo.cont_cuenta_contable (cta_codigo, cta_nombre, cta_tipo, cta_naturaleza, cta_acepta_movimiento, cta_id_padre, cta_nivel) VALUES
('1000', 'ACTIVO', 'A', 'D', 0, NULL, 1),
('2000', 'PASIVO', 'P', 'H', 0, NULL, 1),
('4000', 'INGRESOS', 'I', 'H', 0, NULL, 1),
('5000', 'GASTOS Y COSTOS', 'G', 'D', 0, NULL, 1);

INSERT INTO dbo.cont_cuenta_contable (cta_codigo, cta_nombre, cta_tipo, cta_naturaleza, cta_acepta_movimiento, cta_id_padre, cta_nivel)
SELECT v.codigo, v.nombre, v.tipo, v.naturaleza, 1, p.cta_id, 2
FROM (VALUES
	('1105', 'Caja General', 'A', 'D', '1000'),
	('1110', 'Bancos', 'A', 'D', '1000'),
	('1150', 'IVA Crédito Fiscal', 'A', 'D', '1000'),
	('1205', 'Clientes', 'A', 'D', '1000'),
	('1310', 'Inventarios', 'A', 'D', '1000'),
	('2105', 'Proveedores', 'P', 'H', '2000'),
	('2205', 'IVA Débito Fiscal', 'P', 'H', '2000'),
	('4105', 'Ventas', 'I', 'H', '4000'),
	('5105', 'Costo de Ventas', 'G', 'D', '5000'),
	('5205', 'Gastos Generales', 'G', 'D', '5000')
) v(codigo, nombre, tipo, naturaleza, padre)
INNER JOIN dbo.cont_cuenta_contable p ON p.cta_codigo = v.padre;
GO

-- Si ya se corrió 27_contabilidad_cuentas_parametro.sql, la partida
-- automática busca sus cuentas en cont_cuenta_parametro (que el DELETE de
-- arriba vació): se vuelven a asignar las que usan ventas y compras. El
-- resto de conceptos los repone 27 al volver a correrlo.
IF OBJECT_ID('dbo.cont_cuenta_parametro', 'U') IS NOT NULL
	INSERT INTO dbo.cont_cuenta_parametro (ccp_codigo, ccp_descripcion, ccp_naturaleza, cta_id)
	SELECT v.codigo, v.descripcion, v.naturaleza, cuen.cta_id
	FROM (VALUES
		('VENTA_CAJA',         'Venta: lo cobrado al facturar (contado o enganche)', 'D', '1105'),
		('VENTA_CLIENTES',     'Venta: saldo a crédito del cliente',                 'D', '1205'),
		('VENTA_INGRESO',      'Venta: ingreso por ventas (sin IVA)',                'H', '4105'),
		('VENTA_IVA_DEBITO',   'Venta: IVA débito fiscal',                           'H', '2205'),
		('VENTA_COSTO',        'Venta: costo de lo vendido',                         'D', '5105'),
		('INVENTARIO',         'Inventario de mercadería',                           'H', '1310'),
		('COMPRA_GASTO',       'Compra que no afecta inventario (gasto)',            'D', '5205'),
		('COMPRA_IVA_CREDITO', 'Compra: IVA crédito fiscal',                         'D', '1150'),
		('COMPRA_PROVEEDORES', 'Compra: cuentas por pagar a proveedores',            'H', '2105')
	) v(codigo, descripcion, naturaleza, cuenta)
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_codigo = v.cuenta;
GO

------------------------------------------------------------
-- Seguridad: roles, permisos y usuarios
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion) VALUES
('INVENTARIO', 'INVENTARIO_PRODUCTO_CREAR', 'Crear productos'),
('INVENTARIO', 'INVENTARIO_PRODUCTO_EDITAR', 'Editar productos'),
('VENTAS', 'VENTAS_FACTURA_CREAR', 'Grabar facturas'),
('VENTAS', 'VENTAS_FACTURA_ANULAR', 'Anular facturas'),
('COMPRAS', 'COMPRAS_DOCUMENTO_CREAR', 'Grabar compras'),
('BANCOS', 'BANCOS_CHEQUE_EMITIR', 'Emitir cheques'),
('BANCOS', 'BANCOS_CAJA_ADMIN', 'Administrar caja (apertura, corte, cierre, depósitos)'),
('CONTABILIDAD', 'CONTABILIDAD_ASIENTO_MANUAL', 'Registrar asientos manuales'),
('SEGURIDAD', 'SEGURIDAD_USUARIO_ADMIN', 'Administrar usuarios y roles'),
-- Módulos General y RRHH (26_parametros_general_caja.sql también los crea si
-- faltan; se incluyen aquí para que volver a correr este script no se los
-- quite al rol ADMIN).
('GENERAL', 'GENERAL_CONFIG_ADMIN', 'Administrar compañía, parámetros y entidades financieras'),
('RRHH', 'RRHH_ADMIN', 'Administrar recursos humanos y nómina');
GO

DECLARE @rol_admin INT, @rol_vendedor INT, @rol_cajero INT, @rol_contador INT;
EXEC dbo.sp_rol_insertar @rol_codigo = 'ADMIN', @rol_nombre = 'Administrador', @rol_id = @rol_admin OUTPUT;
EXEC dbo.sp_rol_insertar @rol_codigo = 'VENDEDOR', @rol_nombre = 'Vendedor', @rol_id = @rol_vendedor OUTPUT;
EXEC dbo.sp_rol_insertar @rol_codigo = 'CAJERO', @rol_nombre = 'Cajero', @rol_id = @rol_cajero OUTPUT;
EXEC dbo.sp_rol_insertar @rol_codigo = 'CONTADOR', @rol_nombre = 'Contador', @rol_id = @rol_contador OUTPUT;

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT @rol_admin, per_id FROM dbo.sec_permiso;

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT @rol_vendedor, per_id FROM dbo.sec_permiso WHERE per_codigo IN ('VENTAS_FACTURA_CREAR');

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT @rol_contador, per_id FROM dbo.sec_permiso WHERE per_modulo = 'CONTABILIDAD';

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT @rol_cajero, per_id FROM dbo.sec_permiso WHERE per_codigo IN ('BANCOS_CAJA_ADMIN', 'VENTAS_FACTURA_CREAR');

DECLARE @usu_admin INT, @usu_vendedor INT, @usu_cajero INT, @usu_contador INT;
EXEC dbo.sp_usuario_insertar @usu_codigo = 'ADMIN', @usu_usuario = 'admin', @usu_password = 'Demo#2024', @usu_email = 'admin@siq.com.gt', @usu_id = @usu_admin OUTPUT;
EXEC dbo.sp_usuario_insertar @usu_codigo = 'VEND01', @usu_usuario = 'jperez', @usu_password = 'Demo#2024', @usu_email = 'jperez@siq.com.gt', @usu_id = @usu_vendedor OUTPUT;
EXEC dbo.sp_usuario_insertar @usu_codigo = 'CAJA01', @usu_usuario = 'mgarcia', @usu_password = 'Demo#2024', @usu_email = 'mgarcia@siq.com.gt', @usu_id = @usu_cajero OUTPUT;
EXEC dbo.sp_usuario_insertar @usu_codigo = 'CONT01', @usu_usuario = 'lrodriguez', @usu_password = 'Demo#2024', @usu_email = 'lrodriguez@siq.com.gt', @usu_id = @usu_contador OUTPUT;

INSERT INTO dbo.sec_usuario_rol (usu_id, rol_id) VALUES
(@usu_admin, @rol_admin), (@usu_vendedor, @rol_vendedor), (@usu_cajero, @rol_cajero), (@usu_contador, @rol_contador);
GO
-- Nota: las contraseñas de ejemplo ('Demo#2024') son solo para este juego de
-- datos de prueba; en un ambiente real cada usuario debe definir la suya.

------------------------------------------------------------
-- Bodegas y vendedores
------------------------------------------------------------
DECLARE @bod1 INT, @bod2 INT;
DECLARE @suc1_id INT = (SELECT suc_id FROM dbo.gen_sucursal WHERE suc_codigo = 'SUC01');
DECLARE @suc2_id INT = (SELECT suc_id FROM dbo.gen_sucursal WHERE suc_codigo = 'SUC02');
EXEC dbo.sp_bodega_insertar @bod_codigo = 'BOD01', @bod_descripcion = 'Bodega principal Zona 10',
	@suc_id = @suc1_id, @bod_id = @bod1 OUTPUT;
EXEC dbo.sp_bodega_insertar @bod_codigo = 'BOD02', @bod_descripcion = 'Bodega sucursal Mixco',
	@suc_id = @suc2_id, @bod_id = @bod2 OUTPUT;
GO

INSERT INTO dbo.pos_vendedor (pve_codigo, pve_nombres, pve_apellidos, pve_fecha_ingreso, pve_porc_comision) VALUES
('VEN01', 'Julio', 'Pérez Ramírez', '2021-03-01', 5.0),
('VEN02', 'Ana Lucía', 'Morales Gómez', '2022-01-15', 5.0),
('VEN03', 'Carlos', 'Estrada Solís', '2023-06-10', 4.5);
GO

DECLARE @suc1_caja_id INT = (SELECT suc_id FROM dbo.gen_sucursal WHERE suc_codigo = 'SUC01');
DECLARE @suc2_caja_id INT = (SELECT suc_id FROM dbo.gen_sucursal WHERE suc_codigo = 'SUC02');
INSERT INTO dbo.pos_caja_receptora (pcr_descripcion, suc_id) VALUES ('Caja 1 - Zona 10', @suc1_caja_id), ('Caja 2 - Mixco', @suc2_caja_id);
GO

INSERT INTO dbo.pos_pago_forma_tipo (pft_descripcion) VALUES ('Efectivo'), ('Tarjeta'), ('Cheque'), ('Transferencia');
GO

INSERT INTO dbo.pos_cliente_tipo_pago (tpa_codigo, tpa_descripcion) VALUES ('CON', 'Contado'), ('CRE', 'Crédito');
GO

------------------------------------------------------------
-- Tipos y características de producto
------------------------------------------------------------
INSERT INTO dbo.inv_producto_tipo (prt_codigo, prt_descripcion) VALUES
('HW', 'Hardware'), ('SW', 'Software y licencias'), ('SERV', 'Servicios de soporte'),
('CONS', 'Consultoría'), ('ACC', 'Accesorios'), ('RED', 'Redes y conectividad');
GO

INSERT INTO dbo.inv_producto_tipo_caracteristica (ptc_codigo, ptc_descripcion, ptc_orden) VALUES
('MARCA', 'Marca', 1), ('MODELO', 'Modelo', 2), ('GARANTIA', 'Garantía', 3), ('CAPACIDAD', 'Capacidad', 4);
GO

------------------------------------------------------------
-- Tipos de documento y correlativos
------------------------------------------------------------
INSERT INTO dbo.inv_documento_tipo (tdo_codigo, tdo_descripcion, tdo_naturaleza, afecta_costo) VALUES
('FCAM', 'Factura cambiaria', '-', 'S'),
('COMP', 'Compra inventariable', '+', 'S'),
('GAST', 'Compra no inventariable', '+', 'N');
GO

INSERT INTO dbo.conf_correlativos (tdo_id, serie, correlativo)
SELECT tdo_id, 'SIQ-A', 0 FROM dbo.inv_documento_tipo WHERE tdo_codigo = 'FCAM';
GO

------------------------------------------------------------
-- Proveedores
------------------------------------------------------------
DECLARE @p1 INT, @p2 INT, @p3 INT, @p4 INT, @p5 INT, @p6 INT;
EXEC dbo.sp_proveedor_insertar @prv_codigo='PRV01', @prv_nombre_comercial='TecnoDistribuciones, S.A.', @prv_nit='1122334-5', @prv_contacto='Roberto Aguilar', @prv_telefono_oficina='23456789', @prv_id=@p1 OUTPUT;
EXEC dbo.sp_proveedor_insertar @prv_codigo='PRV02', @prv_nombre_comercial='Importadora de Cómputo Maya', @prv_nit='2233445-6', @prv_contacto='Sofía Ramírez', @prv_telefono_oficina='23456790', @prv_id=@p2 OUTPUT;
EXEC dbo.sp_proveedor_insertar @prv_codigo='PRV03', @prv_nombre_comercial='Software Licencias Centroamérica', @prv_nit='3344556-7', @prv_contacto='Diego Herrera', @prv_telefono_oficina='23456791', @prv_id=@p3 OUTPUT;
EXEC dbo.sp_proveedor_insertar @prv_codigo='PRV04', @prv_nombre_comercial='Redes y Conectividad GT', @prv_nit='4455667-8', @prv_contacto='Paola Castillo', @prv_telefono_oficina='23456792', @prv_id=@p4 OUTPUT;
EXEC dbo.sp_proveedor_insertar @prv_codigo='PRV05', @prv_nombre_comercial='Suministros de Oficina El Pilar', @prv_nit='5566778-9', @prv_contacto='Manuel Ordóñez', @prv_telefono_oficina='23456793', @prv_id=@p5 OUTPUT;
EXEC dbo.sp_proveedor_insertar @prv_codigo='PRV06', @prv_nombre_comercial='Servicios de Internet Fibra Óptica', @prv_nit='6677889-0', @prv_contacto='Karla Vásquez', @prv_telefono_oficina='23456794', @prv_id=@p6 OUTPUT;
GO

------------------------------------------------------------
-- Productos (bienes y servicios) + precio en cada bodega
------------------------------------------------------------
CREATE TABLE #producto_precio (pro_id INT, precio NUMERIC(12,2));
GO

DECLARE @pro_id INT, @bod1 INT = (SELECT bod_id FROM dbo.inv_bodega WHERE bod_codigo='BOD01'), @bod2 INT = (SELECT bod_id FROM dbo.inv_bodega WHERE bod_codigo='BOD02');
DECLARE @mon_local INT = dbo.fn_moneda_local();

-- Cada bloque: inserta el producto y su precio de venta en ambas bodegas.
DECLARE @codigo VARCHAR(64), @desc VARCHAR(256), @prt VARCHAR(8), @tipo CHAR(1), @maneja BIT, @precio NUMERIC(12,2);

DECLARE productos_cur CURSOR LOCAL FAST_FORWARD FOR
SELECT * FROM (VALUES
	('LAP-DELL-3520', 'Laptop Dell Latitude 3520 i5/8GB/256SSD', 'HW', 'B', 1, 5200.00),
	('LAP-HP-250', 'Laptop HP 250 G9 i3/8GB/512SSD', 'HW', 'B', 1, 4300.00),
	('MON-LG-24', 'Monitor LG 24" Full HD', 'HW', 'B', 1, 950.00),
	('MON-SAM-27', 'Monitor Samsung 27" Full HD', 'HW', 'B', 1, 1250.00),
	('IMP-EPSON-L3250', 'Impresora multifuncional Epson L3250', 'HW', 'B', 1, 1450.00),
	('TEC-LOG-K380', 'Teclado inalámbrico Logitech K380', 'ACC', 'B', 1, 280.00),
	('MOU-LOG-M170', 'Mouse inalámbrico Logitech M170', 'ACC', 'B', 1, 120.00),
	('UPS-APC-750', 'UPS APC 750VA', 'ACC', 'B', 1, 620.00),
	('DD-EXT-1TB', 'Disco duro externo 1TB', 'ACC', 'B', 1, 380.00),
	('SW-WIN11-PRO', 'Licencia Windows 11 Pro', 'SW', 'B', 0, 950.00),
	('SW-OFFICE365', 'Licencia Microsoft 365 Business (anual)', 'SW', 'B', 0, 1100.00),
	('SW-ANTIVIRUS', 'Licencia antivirus corporativo (anual)', 'SW', 'B', 0, 480.00),
	('RED-SWITCH-8P', 'Switch de red 8 puertos', 'RED', 'B', 1, 540.00),
	('RED-ROUTER-AC', 'Router inalámbrico AC1200', 'RED', 'B', 1, 610.00),
	('RED-CABLE-UTP', 'Cable UTP Cat6 (rollo 100m)', 'RED', 'B', 1, 430.00),
	('SERV-SOPORTE-HR', 'Soporte técnico por hora', 'SERV', 'S', 0, 175.00),
	('SERV-MANTENIMIENTO', 'Mantenimiento preventivo de equipo', 'SERV', 'S', 0, 250.00),
	('SERV-INSTALACION-RED', 'Instalación de red de oficina', 'SERV', 'S', 0, 950.00),
	('SERV-HOSTING-ANUAL', 'Hosting compartido (anual)', 'SERV', 'S', 0, 650.00),
	('SERV-DOMINIO-ANUAL', 'Registro de dominio (anual)', 'SERV', 'S', 0, 180.00),
	('CONS-INFRA', 'Consultoría de infraestructura TI', 'CONS', 'S', 0, 1800.00),
	('CONS-CIBERSEG', 'Consultoría de ciberseguridad', 'CONS', 'S', 0, 2200.00)
) v(pro_codigo, pro_descripcion, prt_codigo, pro_tipo_item, pro_maneja_existencia, precio);

OPEN productos_cur;
FETCH NEXT FROM productos_cur INTO @codigo, @desc, @prt, @tipo, @maneja, @precio;
WHILE @@FETCH_STATUS = 0
BEGIN
	DECLARE @prt_id_sel INT;
	SELECT @prt_id_sel = prt_id FROM dbo.inv_producto_tipo WHERE prt_codigo = @prt;

	EXEC dbo.sp_producto_insertar
		@pro_codigo = @codigo, @pro_descripcion = @desc,
		@prt_id = @prt_id_sel,
		@pro_tipo_item = @tipo, @pro_maneja_existencia = @maneja, @pro_id = @pro_id OUTPUT;

	INSERT INTO dbo.inv_producto_precio (ppr_precio_unitario_venta, ppr_descripcion, ppr_vigencia_desde, pro_id, bod_id, mon_id)
	VALUES (@precio, 'Precio de lista', DATEADD(MONTH, -6, GETDATE()), @pro_id, @bod1, @mon_local);
	INSERT INTO dbo.inv_producto_precio (ppr_precio_unitario_venta, ppr_descripcion, ppr_vigencia_desde, pro_id, bod_id, mon_id)
	VALUES (@precio, 'Precio de lista', DATEADD(MONTH, -6, GETDATE()), @pro_id, @bod2, @mon_local);

	INSERT INTO #producto_precio (pro_id, precio) VALUES (@pro_id, @precio);

	FETCH NEXT FROM productos_cur INTO @codigo, @desc, @prt, @tipo, @maneja, @precio;
END
CLOSE productos_cur;
DEALLOCATE productos_cur;
GO

-- Proveedor preferido por producto (asignación simple round-robin entre los proveedores).
INSERT INTO dbo.inv_producto_proveedor (prv_id, pro_id, ppp_preferencia)
SELECT prv.prv_id, pp.pro_id, 'S'
FROM #producto_precio pp
CROSS APPLY (
	SELECT prv_id
	FROM (SELECT prv_id, ROW_NUMBER() OVER (ORDER BY prv_id) AS rn, COUNT(*) OVER () AS total FROM dbo.inv_proveedor) x
	WHERE x.rn = (pp.pro_id % x.total) + 1
) prv;
GO

------------------------------------------------------------
-- Clientes
------------------------------------------------------------
CREATE TABLE #cliente (cli_id INT);
GO
DECLARE @cli_id INT, @gt_pais INT = (SELECT pai_id FROM dbo.gen_pais WHERE pai_codigo_alfa2='GT');
DECLARE @codigo VARCHAR(32), @nombres VARCHAR(64), @apellidos VARCHAR(64), @nit VARCHAR(16);

DECLARE clientes_cur CURSOR LOCAL FAST_FORWARD FOR
SELECT * FROM (VALUES
	('CLI001','Carlos','Méndez López','1000011-2'), ('CLI002','María José','Suárez Pineda','1000022-3'),
	('CLI003','Luis Fernando','García Mazariegos','1000033-4'), ('CLI004','Ana Gabriela','Ordóñez Ruiz','1000044-5'),
	('CLI005','José Miguel','Barrios Cifuentes','1000055-6'), ('CLI006','Silvia Patricia','Reyes Monterroso','1000066-7'),
	('CLI007','Édgar Rolando','Chacón Paredes','1000077-8'), ('CLI008','Claudia Verónica','Solórzano Guzmán','1000088-9'),
	('CLI009','Byron Estuardo','Marroquín Ical','1000099-0'), ('CLI010','Wendy Carolina','Tzul Xico','1000100-1'),
	('CLI011','Óscar Danilo','Pérez Castañeda','1000111-2'), ('CLI012','Heidy Lorena','Aguilar Ramírez','1000122-3'),
	('CLI013','Jorge Mario','Velásquez Girón','1000133-4'), ('CLI014','Brenda Suceli','López Hernández','1000144-5'),
	('CLI015','Fredy Armando','Chávez Morán','1000155-6'), ('CLI016','Gabriela Alejandra','Contreras Soto','1000166-7'),
	('CLI017','Rudy Alfonso','Ixcot Batz','1000177-8'), ('CLI018','Cindy Marisol','Poou Caal','1000188-9'),
	('CLI019','Estuardo José','Tojín Sactic','1000199-0'), ('CLI020','Paola Nineth','Recinos Cabrera','1000200-1'),
	('CLI021','Mynor Vinicio','Salazar Pineda','1000211-2'), ('CLI022','Dora Lidia','Cabrera Estrada','1000222-3'),
	('CLI023','Selvin Otoniel','Coy Chiquito','1000233-4'), ('CLI024','Ingrid Yesenia','Morán Batres','1000244-5'),
	('CLI025','Alejandro','Villatoro Dubón','1000255-6')
) v(cli_codigo, cli_nombres, cli_apellidos, cli_nit);

OPEN clientes_cur;
FETCH NEXT FROM clientes_cur INTO @codigo, @nombres, @apellidos, @nit;
WHILE @@FETCH_STATUS = 0
BEGIN
	EXEC dbo.sp_cliente_insertar
		@cli_codigo = @codigo, @cli_nombres = @nombres, @cli_apellidos = @apellidos, @cli_nit = @nit,
		@cli_limite_credito = 15000.00, @cli_direccion_pais = @gt_pais, @cli_id = @cli_id OUTPUT;
	INSERT INTO #cliente VALUES (@cli_id);
	FETCH NEXT FROM clientes_cur INTO @codigo, @nombres, @apellidos, @nit;
END
CLOSE clientes_cur; DEALLOCATE clientes_cur;
GO

------------------------------------------------------------
-- Apertura de caja para poder registrar cobros
------------------------------------------------------------
DECLARE @pca_id INT;
DECLARE @pcr1_id INT = (SELECT TOP 1 pcr_id FROM dbo.pos_caja_receptora ORDER BY pcr_id);
DECLARE @usu_cajero_id INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'mgarcia');
EXEC dbo.sp_pos_caja_abrir
	@pcr_id = @pcr1_id,
	@usu_id = @usu_cajero_id,
	@pca_id = @pca_id OUTPUT;
GO

------------------------------------------------------------
-- Compra inicial de apertura de inventario (stock para poder vender)
------------------------------------------------------------
DECLARE @det dbo.compra_det_type;
DECLARE @bod1 INT = (SELECT bod_id FROM dbo.inv_bodega WHERE bod_codigo='BOD01');
DECLARE @fecha_compra DATE = DATEADD(MONTH, -5, CAST(GETDATE() AS DATE));

INSERT INTO @det (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total, det_porc_iva, bod_id, pro_id)
SELECT ROW_NUMBER() OVER (ORDER BY pp.pro_id), pro.pro_tipo_item, 100, pro.pro_descripcion,
	   pp.precio * 0.62, (pp.precio * 0.62) * 100, 12, @bod1, pp.pro_id
FROM #producto_precio pp
INNER JOIN dbo.inv_producto pro ON pro.pro_id = pp.pro_id
WHERE pro.pro_maneja_existencia = 1;

DECLARE @enc_compra_inicial INT;
DECLARE @prv1_id INT = (SELECT TOP 1 prv_id FROM dbo.inv_proveedor ORDER BY prv_id);
DECLARE @tdo_comp_id INT = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo='COMP');
EXEC dbo.sp_compras_crear_documento
	@enc_fecha_docto = @fecha_compra, @enc_numero_docto = 'INV-INICIAL-001',
	@prv_id = @prv1_id,
	@tdo_id = @tdo_comp_id,
	@enc_numero_cuotas = 1, @detalle = @det, @enc_id = @enc_compra_inicial OUTPUT;
GO

------------------------------------------------------------
-- Compras adicionales de reabastecimiento (variedad de fechas/proveedores)
------------------------------------------------------------
DECLARE @i INT = 1;
DECLARE @bod1 INT = (SELECT bod_id FROM dbo.inv_bodega WHERE bod_codigo='BOD01');
DECLARE @tdo_comp INT = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo='COMP');

WHILE @i <= 10
BEGIN
	BEGIN TRY
		DECLARE @det2 dbo.compra_det_type;
		DECLARE @pro_sel INT, @precio_sel NUMERIC(12,2), @cant_sel INT = 10 + (ABS(CHECKSUM(NEWID())) % 30);
		DECLARE @prv_sel INT;
		-- EXEC no acepta una expresión directamente como valor de un
		-- parámetro con nombre; se calculan antes en variables.
		DECLARE @fecha_compra_i DATE = DATEADD(DAY, -1 * (ABS(CHECKSUM(NEWID())) % 120), CAST(GETDATE() AS DATE));
		DECLARE @numero_docto_compra VARCHAR(32) = CONCAT('REST-', @i);

		SELECT TOP 1 @pro_sel = pp.pro_id, @precio_sel = pp.precio
		FROM #producto_precio pp
		INNER JOIN dbo.inv_producto pro ON pro.pro_id = pp.pro_id
		WHERE pro.pro_maneja_existencia = 1
		ORDER BY NEWID();

		SELECT @prv_sel = prv_id FROM dbo.inv_producto_proveedor WHERE pro_id = @pro_sel;

		INSERT INTO @det2 (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total, det_porc_iva, bod_id, pro_id)
		SELECT 1, 'B', @cant_sel, pro_descripcion, @precio_sel * 0.62, (@precio_sel * 0.62) * @cant_sel, 12, @bod1, @pro_sel
		FROM dbo.inv_producto WHERE pro_id = @pro_sel;

		DECLARE @enc_compra INT;
		EXEC dbo.sp_compras_crear_documento
			@enc_fecha_docto = @fecha_compra_i,
			@enc_numero_docto = @numero_docto_compra,
			@prv_id = @prv_sel, @tdo_id = @tdo_comp, @enc_numero_cuotas = 1,
			@detalle = @det2, @enc_id = @enc_compra OUTPUT;
	END TRY
	BEGIN CATCH
		PRINT 'Compra de reabastecimiento #' + CAST(@i AS VARCHAR) + ' omitida: ' + ERROR_MESSAGE();
	END CATCH

	SET @i = @i + 1;
END
GO

------------------------------------------------------------
-- Ventas (facturas a clientes): algunas de contado, otras a crédito
------------------------------------------------------------
DECLARE @i INT = 1;
DECLARE @bod1 INT = (SELECT bod_id FROM dbo.inv_bodega WHERE bod_codigo='BOD01');
DECLARE @tdo_fcam INT = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo='FCAM');
DECLARE @usu_vend_id INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'jperez');

WHILE @i <= 35
BEGIN
	BEGIN TRY
		DECLARE @det3 dbo.factura_det_type;
		DECLARE @cli_sel INT, @vend_sel INT, @cuotas INT, @fecha_venta DATE, @fecha_primer_pago DATE;

		SELECT TOP 1 @cli_sel = cli_id FROM #cliente ORDER BY NEWID();
		SELECT TOP 1 @vend_sel = pve_id FROM dbo.pos_vendedor ORDER BY NEWID();
		SET @fecha_venta = DATEADD(DAY, -1 * (ABS(CHECKSUM(NEWID())) % 150), CAST(GETDATE() AS DATE));
		SET @cuotas = CASE WHEN @i % 3 = 0 THEN 1 + (ABS(CHECKSUM(NEWID())) % 6) ELSE 1 END;
		SET @fecha_primer_pago = DATEADD(MONTH, 1, @fecha_venta);

		;WITH lineas AS (
			SELECT TOP (1 + (ABS(CHECKSUM(NEWID())) % 2))
				   pp.pro_id, pro.pro_tipo_item, pro.pro_maneja_existencia, pp.precio,
				   1 + (ABS(CHECKSUM(NEWID())) % 2) AS cantidad
			FROM #producto_precio pp
			INNER JOIN dbo.inv_producto pro ON pro.pro_id = pp.pro_id
			LEFT JOIN dbo.inv_producto_existencia_bodega peb ON peb.pro_id = pp.pro_id AND peb.bod_id = @bod1
			WHERE pro.pro_maneja_existencia = 0 OR ISNULL(peb.existencia, 0) >= 2
			ORDER BY NEWID()
		)
		INSERT INTO @det3 (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total, det_porc_iva, bod_id, pro_id)
		SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), pro_tipo_item, cantidad,
			   (SELECT pro_descripcion FROM dbo.inv_producto WHERE pro_id = lineas.pro_id),
			   precio, precio * cantidad, 12, @bod1, pro_id
		FROM lineas;

		IF EXISTS (SELECT 1 FROM @det3)
		BEGIN
			DECLARE @enc_venta INT, @numero_unico VARCHAR(16), @numero_docto_venta VARCHAR(32) = CONCAT('FAC-', @i);
			DECLARE @formas_vacio_venta dbo.pago_forma_type;
			EXEC dbo.sp_ventas_crear_factura
				@enc_fecha_docto = @fecha_venta, @enc_numero_docto = @numero_docto_venta,
				@cli_id = @cli_sel, @tdo_id = @tdo_fcam, @pve_id = @vend_sel,
				@enc_fecha_primer_pago = @fecha_primer_pago, @enc_numero_cuotas = @cuotas,
				@usu_id = @usu_vend_id,
				@detalle = @det3, @formas_pago = @formas_vacio_venta,
				@enc_id = @enc_venta OUTPUT, @enc_numero_unico = @numero_unico OUTPUT;
		END
	END TRY
	BEGIN CATCH
		PRINT 'Factura #' + CAST(@i AS VARCHAR) + ' omitida: ' + ERROR_MESSAGE();
	END CATCH

	SET @i = @i + 1;
END
GO

------------------------------------------------------------
-- Cobros de cuotas a clientes
------------------------------------------------------------
DECLARE @pca_id INT = (SELECT TOP 1 pca_id FROM dbo.pos_caja_apertura WHERE pca_estado = 'A' ORDER BY pca_id);
DECLARE @usu_cajero INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'mgarcia');
DECLARE @cpp_id INT, @saldo NUMERIC(12,2), @ppe_id INT;
DECLARE @formas_vacio_cuota dbo.pago_forma_type;

DECLARE cuotas_cur CURSOR LOCAL FAST_FORWARD FOR
	SELECT TOP 15 cpp_id, cpp_saldo_cuota
	FROM dbo.pos_cliente_plan_pagos
	WHERE cpp_estado = 'P'
	ORDER BY NEWID();

OPEN cuotas_cur;
FETCH NEXT FROM cuotas_cur INTO @cpp_id, @saldo;
WHILE @@FETCH_STATUS = 0
BEGIN
	BEGIN TRY
		EXEC dbo.sp_pos_registrar_pago_cuota @cpp_id = @cpp_id, @valor_pago = @saldo, @pca_id = @pca_id, @usu_id = @usu_cajero, @formas_pago = @formas_vacio_cuota, @ppe_id = @ppe_id OUTPUT;
	END TRY
	BEGIN CATCH
		PRINT 'Cobro de cuota ' + CAST(@cpp_id AS VARCHAR) + ' omitido: ' + ERROR_MESSAGE();
	END CATCH
	FETCH NEXT FROM cuotas_cur INTO @cpp_id, @saldo;
END
CLOSE cuotas_cur; DEALLOCATE cuotas_cur;
GO

------------------------------------------------------------
-- Pagos a proveedores mediante cheque
------------------------------------------------------------
DECLARE @cbc_id INT = (SELECT TOP 1 cbc_id FROM dbo.bco_cuenta_bancaria_chequera ORDER BY cbc_id);
DECLARE @usu_admin INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
DECLARE @bmp_pago_id INT = (SELECT TOP 1 bmp_id FROM dbo.bco_motivo_pago WHERE bmp_descripcion = 'Pago a proveedores');
DECLARE @ppg_id INT, @valor_pend NUMERIC(12,2), @bce_id INT, @numero_cheque_base INT = 1001, @contador INT = 0;

DECLARE pagos_cur CURSOR LOCAL FAST_FORWARD FOR
	SELECT TOP 10 ppg_id, ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0)
	FROM dbo.inv_proveedor_plan_pago
	WHERE ppg_estado = 'P'
	ORDER BY NEWID();

OPEN pagos_cur;
FETCH NEXT FROM pagos_cur INTO @ppg_id, @valor_pend;
WHILE @@FETCH_STATUS = 0
BEGIN
	BEGIN TRY
		-- EXEC no acepta una expresión directamente como valor de un
		-- parámetro con nombre; el número de cheque se calcula antes.
		DECLARE @numero_cheque VARCHAR(16) = CAST(@numero_cheque_base + @contador AS VARCHAR(16));

		EXEC dbo.sp_bancos_emitir_cheque_pago_proveedor
			@ppg_id = @ppg_id, @cbc_id = @cbc_id,
			@bce_numero_cheque = @numero_cheque,
			@valor_pago = @valor_pend,
			@bmp_id = @bmp_pago_id,
			@usu_id = @usu_admin, @bce_id = @bce_id OUTPUT;
	END TRY
	BEGIN CATCH
		PRINT 'Pago a proveedor (cuota ' + CAST(@ppg_id AS VARCHAR) + ') omitido: ' + ERROR_MESSAGE();
	END CATCH
	SET @contador = @contador + 1;
	FETCH NEXT FROM pagos_cur INTO @ppg_id, @valor_pend;
END
CLOSE pagos_cur; DEALLOCATE pagos_cur;
GO

------------------------------------------------------------
-- Anulación de un par de documentos (demuestra sp_documento_anular)
------------------------------------------------------------
DECLARE @enc_a INT, @enc_b INT;
DECLARE @usu_admin_id INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario='admin');
SELECT TOP 1 @enc_a = enc_id FROM dbo.inv_documento_enc WHERE enc_estado = 'G' AND tdo_id = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo='FCAM') ORDER BY enc_id DESC;
IF @enc_a IS NOT NULL EXEC dbo.sp_documento_anular @enc_id = @enc_a, @usu_id = @usu_admin_id;

SELECT TOP 1 @enc_b = enc_id FROM dbo.inv_documento_enc WHERE enc_estado = 'G' AND tdo_id = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo='FCAM') ORDER BY enc_id ASC;
IF @enc_b IS NOT NULL AND @enc_b <> @enc_a EXEC dbo.sp_documento_anular @enc_id = @enc_b, @usu_id = @usu_admin_id;
GO

------------------------------------------------------------
-- Limpieza de tablas temporales de este script
------------------------------------------------------------
DROP TABLE IF EXISTS #producto_precio;
DROP TABLE IF EXISTS #cliente;
GO

------------------------------------------------------------
-- Resumen rápido de verificación
------------------------------------------------------------
SELECT 'productos' AS entidad, COUNT(*) AS filas FROM dbo.inv_producto
UNION ALL SELECT 'clientes', COUNT(*) FROM dbo.pos_cliente
UNION ALL SELECT 'proveedores', COUNT(*) FROM dbo.inv_proveedor
UNION ALL SELECT 'documentos_grabados', COUNT(*) FROM dbo.inv_documento_enc WHERE enc_estado = 'G'
UNION ALL SELECT 'documentos_anulados', COUNT(*) FROM dbo.inv_documento_enc WHERE enc_estado = 'A'
UNION ALL SELECT 'asientos_contables', COUNT(*) FROM dbo.cont_asiento_enc
UNION ALL SELECT 'cuotas_cliente_pendientes', COUNT(*) FROM dbo.pos_cliente_plan_pagos WHERE cpp_estado = 'P'
UNION ALL SELECT 'cheques_emitidos', COUNT(*) FROM dbo.bco_cheque_emitido_enc;
GO
