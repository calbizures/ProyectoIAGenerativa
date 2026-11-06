------------------------------------------------------------------------------
-- datos-pinturas.sql
--
-- Convierte una base de demostración recién instalada (01 al 86) en la de una
-- tienda de pinturas ficticia, "Pinturas del Valle, S.A.", para grabar el
-- video de ventas (generar-pinturas.sh). NO se usa en producción ni en la base
-- de trabajo: solo en un contenedor desechable.
--
--   1. Compañía, tiendas (sucursales), bodegas y cajas con nombres de la tienda.
--   2. Tipos de producto y unidades de pintura (galón, cubeta).
--   3. Los productos de cómputo de los datos de prueba quedan inactivos y se
--      carga el inventario inicial de pinturas, brochas y rodillos en cada
--      tienda (con su costo, precio de venta y póliza), con el procedimiento
--      de cargas iniciales.
--   4. Proveedores de pintura y dos clientes contratistas (los dos clientes
--      con más cuotas pendientes, para que tengan cartera y antigüedad).
--
-- Los nombres, marcas y NIT son inventados. Se puede volver a correr.
------------------------------------------------------------------------------
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');

------------------------------------------------------------
-- 1. Compañía, tiendas, bodegas y cajas
------------------------------------------------------------
UPDATE dbo.gen_compania
   SET cia_nombre_comercial = 'Pinturas del Valle, S.A.',
	   cia_fel_nombre_emisor = 'Pinturas del Valle, S.A.',
	   cia_direccion = '6a. Avenida 12-40 Zona 1, Ciudad de Guatemala',
	   cia_nit = '8765432-6',
	   cia_telefono = '24561200',
	   cia_email = 'ventas@pinturasdelvalle.example',
	   cia_fel_correo_emisor = 'ventas@pinturasdelvalle.example',
	   cia_representante_legal = 'Ana Lucía Morales Herrera'
 WHERE cia_id = (SELECT MIN(cia_id) FROM dbo.gen_compania);

UPDATE dbo.gen_sucursal SET suc_descripcion = 'Tienda Central Zona 1', suc_fel_nombre_comercial = 'Pinturas del Valle - Central',
	suc_direccion = '6a. Avenida 12-40 Zona 1, Ciudad de Guatemala' WHERE suc_codigo = 'SUC01';
UPDATE dbo.gen_sucursal SET suc_descripcion = 'Tienda Mixco', suc_fel_nombre_comercial = 'Pinturas del Valle - Mixco',
	suc_direccion = 'Calzada San Juan 15-20 Zona 4 de Mixco' WHERE suc_codigo = 'SUC02';

UPDATE dbo.inv_bodega SET bod_descripcion = 'Bodega Tienda Central' WHERE bod_codigo = 'BOD01';
UPDATE dbo.inv_bodega SET bod_descripcion = 'Bodega Tienda Mixco' WHERE bod_codigo = 'BOD02';
UPDATE dbo.inv_bodega SET bod_descripcion = 'Bodega de reserva Central' WHERE bod_codigo = 'BOD03';

UPDATE caja SET pcr_descripcion = CONCAT('Caja ', caja.pcr_id, ' - ', REPLACE(sucu.suc_descripcion, ' Zona 1', '')), pcr_calcula_vuelto = 1
  FROM dbo.pos_caja_receptora caja JOIN dbo.gen_sucursal sucu ON sucu.suc_id = caja.suc_id;

-- En mostrador se imprime en ticket (térmica de 80 mm) y el NIT de un
-- cliente nuevo se consulta al certificador al facturar.
UPDATE dbo.gen_compania SET cia_factura_impresora = 'T', cia_factura_ancho_termica = 80;
UPDATE dbo.fel_configuracion SET fco_consulta_nit_activa = 1;

-- Serie de las facturas con las iniciales de la tienda.
UPDATE dbo.conf_correlativos SET serie = 'PDV-A' WHERE serie = 'SIQ-A';
UPDATE dbo.inv_documento_enc SET enc_numero_unico = STUFF(enc_numero_unico, 1, 3, 'PDV') WHERE enc_numero_unico LIKE 'SIQ-%';

------------------------------------------------------------
-- 2. Tipos de producto y unidades
------------------------------------------------------------
MERGE dbo.inv_producto_tipo AS dest
USING (VALUES ('PINT', 'Pinturas'), ('IMPE', 'Impermeabilizantes y selladores'), ('HERR', 'Brochas, rodillos y herramientas'), ('SOLV', 'Solventes'))
	AS orig (codigo, descripcion) ON dest.prt_codigo = orig.codigo
WHEN NOT MATCHED THEN INSERT (prt_codigo, prt_descripcion, prt_estado, InsUsuario, InsFechaHora) VALUES (orig.codigo, orig.descripcion, 'A', @usu, SYSDATETIME());

MERGE dbo.inv_unidad_medida AS dest
USING (VALUES ('GAL', 'Galón'), ('CUB', 'Cubeta de 5 galones'), ('CUA', 'Cuarto de galón'), ('ROL', 'Rollo'))
	AS orig (codigo, descripcion) ON dest.ume_codigo = orig.codigo
WHEN NOT MATCHED THEN INSERT (ume_codigo, ume_descripcion, ume_estado, ume_fel_codigo, InsUsuario, InsFechaHora) VALUES (orig.codigo, orig.descripcion, 'A', orig.codigo, @usu, SYSDATETIME());

------------------------------------------------------------
-- 3. Productos: los de cómputo se inactivan; inventario inicial de pinturas
------------------------------------------------------------
UPDATE dbo.inv_producto SET pro_estado = 'I'
 WHERE pro_codigo NOT LIKE 'PDV-%' AND pro_estado = 'A';

IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_codigo LIKE 'PDV-%')
BEGIN
	DECLARE @prod TABLE (codigo VARCHAR(64), descripcion VARCHAR(256), tipo VARCHAR(16), unidad VARCHAR(16), costo NUMERIC(12, 2), precio NUMERIC(12, 2),
		central NUMERIC(12, 2), mixco NUMERIC(12, 2), reserva NUMERIC(12, 2));
	INSERT INTO @prod VALUES
		('PDV-LAT-BLA-GAL', 'Pintura látex interior blanco mate (galón)',          'PINT', 'GAL',  92.00,  165.00, 120, 48,   0),
		('PDV-LAT-BLA-CUB', 'Pintura látex interior blanco mate (cubeta 5 gal)',   'PINT', 'CUB', 415.00,  725.00,  36, 10,  40),
		('PDV-LAT-EXT-GAL', 'Pintura látex exterior colores (galón)',              'PINT', 'GAL', 118.00,  205.00,  85, 30,   0),
		('PDV-LAT-EXT-CUB', 'Pintura látex exterior colores (cubeta 5 gal)',       'PINT', 'CUB', 530.00,  925.00,  28,  8,  30),
		('PDV-ESM-BRI-GAL', 'Esmalte brillante (galón)',                           'PINT', 'GAL', 138.00,  245.00,  40, 18,   0),
		('PDV-ESM-BRI-CUA', 'Esmalte brillante (cuarto de galón)',                 'PINT', 'CUA',  41.00,   75.00,  60, 24,   0),
		('PDV-IMP-ACR-CUB', 'Impermeabilizante acrílico para techos (cubeta 5 gal)', 'IMPE', 'CUB', 598.00, 1050.00, 32,  3,  40),
		('PDV-IMP-ACR-GAL', 'Impermeabilizante acrílico para techos (galón)',      'IMPE', 'GAL', 132.00,  235.00,  45, 15,   0),
		('PDV-SEL-ACR-GAL', 'Sellador acrílico para paredes (galón)',              'IMPE', 'GAL',  68.00,  125.00,  50, 20,   0),
		('PDV-BRO-3P',      'Brocha de 3 pulgadas',                                'HERR', 'UND',  17.00,   35.00, 140, 60,   0),
		('PDV-BRO-4P',      'Brocha de 4 pulgadas',                                'HERR', 'UND',  23.00,   45.00, 110, 40,   0),
		('PDV-ROD-9P',      'Rodillo de 9 pulgadas con felpa',                     'HERR', 'UND',  36.00,   69.00,  90, 35,   0),
		('PDV-BAN-PIN',     'Bandeja plástica para pintar',                        'HERR', 'UND',  14.00,   29.00,  70, 25,   0),
		('PDV-CIN-MAS',     'Cinta de enmascarar 2 pulgadas',                      'HERR', 'ROL',  11.00,   22.00, 150, 60,   0),
		('PDV-LIJ-120',     'Lija para pared grano 120 (pliego)',                  'HERR', 'UND',   3.00,    6.00, 400, 150,  0),
		('PDV-SOL-THI-GAL', 'Solvente thinner (galón)',                            'SOLV', 'GAL',  52.00,   95.00,  60, 20,   0);

	DECLARE @filas dbo.inv_carga_inicial_type;
	INSERT INTO @filas (Fila, Sucursal, Bodega, Producto, Descripcion, Tipo, Unidad, Cantidad, CostoTotal, PrecioVenta)
	SELECT ROW_NUMBER() OVER (ORDER BY bode.orden, prod.codigo) + 1, bode.sucursal, bode.bodega, prod.codigo, prod.descripcion, prod.tipo, prod.unidad,
		   bode.cantidad, bode.cantidad * prod.costo, prod.precio
	  FROM @prod prod
	 CROSS APPLY (VALUES (1, 'SUC01', 'BOD01', prod.central), (2, 'SUC02', 'BOD02', prod.mixco), (3, 'SUC01', 'BOD03', prod.reserva))
		AS bode (orden, sucursal, bodega, cantidad)
	 WHERE bode.cantidad > 0;

	DECLARE @fecha DATE = DATEADD(DAY, -45, CAST(GETDATE() AS DATE));
	EXEC dbo.paInvCargaInicialProcesar @Fecha = @fecha, @Filas = @filas, @SoloValidar = 0, @UsuId = @usu;

	-- La reserva también tiene precio de venta (lo usa el traslado y la venta desde esa bodega).
	INSERT INTO dbo.inv_producto_precio (ppr_precio_unitario_venta, ppr_descripcion, ppr_vigencia_desde, pro_id, bod_id, mon_id, ppr_estado, InsUsuario, InsFechaHora)
	SELECT prod.precio, 'Precio de lista', @fecha, prod2.pro_id, bode.bod_id, (SELECT MIN(mon_id) FROM dbo.inv_producto_precio), 'A', @usu, SYSDATETIME()
	  FROM @prod prod
	  JOIN dbo.inv_producto prod2 ON prod2.pro_codigo = prod.codigo
	 CROSS JOIN dbo.inv_bodega bode
	 WHERE NOT EXISTS (SELECT 1 FROM dbo.inv_producto_precio prec WHERE prec.pro_id = prod2.pro_id AND prec.bod_id = bode.bod_id AND prec.ppr_estado = 'A');
END

------------------------------------------------------------
-- 4. Proveedores y clientes contratistas
------------------------------------------------------------
UPDATE dbo.inv_proveedor SET prv_nombre_comercial = CASE prv_codigo
		WHEN 'PRV01' THEN 'Distribuidora Centroamericana de Pinturas'
		WHEN 'PRV02' THEN 'Recubrimientos Industriales del Sur'
		WHEN 'PRV03' THEN 'Brochas y Rodillos de Guatemala'
		WHEN 'PRV04' THEN 'Solventes y Químicos de Occidente'
		WHEN 'PRV05' THEN 'Suministros de Ferretería El Pilar'
		ELSE prv_nombre_comercial END;

IF NOT EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_codigo = 'CONT01')
BEGIN
	DECLARE @contratistas TABLE (orden INT IDENTITY, cli_id INT);
	INSERT INTO @contratistas (cli_id)
	SELECT TOP 2 cuot.cli_id
	  FROM dbo.pos_cliente_plan_pagos cuot
	  JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
	 WHERE cuot.cpp_saldo_cuota > 0
	 GROUP BY cuot.cli_id
	 ORDER BY SUM(IIF(cuot.cpp_fecha_maxima_pago < CAST(GETDATE() AS DATE), 1, 0)) DESC, COUNT(*) DESC, cuot.cli_id;

	UPDATE clie SET
		cli_codigo = IIF(cont.orden = 1, 'CONT01', 'CONT02'),
		cli_nombres = IIF(cont.orden = 1, 'Constructora Altamira, S.A.', 'Remodelaciones y Acabados Pérez'),
		cli_apellidos = NULL,
		cli_email = IIF(cont.orden = 1, 'compras@altamira.example', 'acabados.perez@correo.example'),
		cli_limite_credito = IIF(cont.orden = 1, 60000, 25000)
	  FROM dbo.pos_cliente clie JOIN @contratistas cont ON cont.cli_id = clie.cli_id;
END

SELECT cli_codigo, cli_nombres, cli_limite_credito FROM dbo.pos_cliente WHERE cli_codigo LIKE 'CONT%';
SELECT COUNT(*) AS productos_pintura FROM dbo.inv_producto WHERE pro_codigo LIKE 'PDV-%';
