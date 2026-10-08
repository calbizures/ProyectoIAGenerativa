------------------------------------------------------------------------------
-- 33_datos_sinteticos_cxc_organigrama.sql
--
-- Datos de prueba de lo agregado en 31 y 32, generados con los propios
-- procedimientos:
--   1. Organigrama de ejemplo: Junta Directiva (n1) > Gerencias de
--      Operaciones, IT, Financiera y RRHH (n2.1 a n2.4) > departamentos.
--      Los departamentos del 25 (Ventas, Caja, Contabilidad) pasan a su
--      gerencia y las unidades de prueba anteriores se eliminan si quedan
--      vacías.
--   2. Una factura a crédito con un producto y dos líneas de servicio (sin
--      producto, en horas y como servicio).
--   3. Una nota de cada tipo: crédito a cliente con devolución, débito a
--      cliente, crédito de proveedor (rebaja) y débito de proveedor.
--
-- Requiere 12 a 32. Se puede volver a correr: cada sección se omite si ya
-- existen sus datos.
------------------------------------------------------------------------------

USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Organigrama
------------------------------------------------------------
IF EXISTS (SELECT 1 FROM dbo.rrhhUnidadOrganizativa WHERE Descripcion = 'Junta Directiva')
	PRINT 'Organigrama: ya existe, se omite la sección.';
ELSE
BEGIN
	DECLARE @admin INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
	DECLARE @suc INT = (SELECT MIN(suc_id) FROM dbo.gen_sucursal WHERE suc_estado = 'A');
	DECLARE @junta INT, @operaciones INT, @it INT, @financiera INT, @rrhh INT;

	EXEC dbo.paRrhhUnidadGuardar @IdUnidad = NULL, @IdPadre = NULL, @Descripcion = 'Junta Directiva', @Orden = 1, @UsuId = @admin, @IdResultado = @junta OUTPUT;
	EXEC dbo.paRrhhUnidadGuardar @IdUnidad = NULL, @IdPadre = @junta, @Descripcion = 'Gerencia de Operaciones', @Orden = 1, @UsuId = @admin, @IdResultado = @operaciones OUTPUT;
	EXEC dbo.paRrhhUnidadGuardar @IdUnidad = NULL, @IdPadre = @junta, @Descripcion = 'Gerencia IT', @Orden = 2, @UsuId = @admin, @IdResultado = @it OUTPUT;
	EXEC dbo.paRrhhUnidadGuardar @IdUnidad = NULL, @IdPadre = @junta, @Descripcion = 'Gerencia Financiera', @Orden = 3, @UsuId = @admin, @IdResultado = @financiera OUTPUT;
	EXEC dbo.paRrhhUnidadGuardar @IdUnidad = NULL, @IdPadre = @junta, @Descripcion = 'Gerencia de RRHH', @Orden = 4, @UsuId = @admin, @IdResultado = @rrhh OUTPUT;

	-- Departamentos existentes a su gerencia.
	UPDATE dbo.rrhhDepartamento SET IdUnidadOrganizativa = @operaciones WHERE Descripcion = 'Ventas';
	UPDATE dbo.rrhhDepartamento SET IdUnidadOrganizativa = @financiera WHERE Descripcion IN ('Caja', 'Contabilidad');

	-- Departamentos nuevos.
	INSERT INTO dbo.rrhhDepartamento (Descripcion, IdUnidadOrganizativa, suc_id, InsUsuario)
	SELECT v.d, v.u, @suc, @admin
	FROM (VALUES ('Logística y bodega', @operaciones),
				 ('Soporte técnico', @it), ('Desarrollo', @it), ('Redes', @it),
				 ('Tesorería', @financiera), ('Auditoría', @financiera),
				 ('Reclutamiento y selección', @rrhh), ('Nómina y compensaciones', @rrhh)) v(d, u)
	WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhDepartamento depa WHERE depa.Descripcion = v.d);

	-- Plazas vacantes de ejemplo en IT.
	INSERT INTO dbo.rrhhPuesto (Descripcion, SalarioMinimo, SalarioMaximo)
	SELECT v.d, v.mi, v.ma FROM (VALUES ('Técnico de soporte', 4500, 7000), ('Desarrollador', 8000, 15000)) v(d, mi, ma)
	WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhPuesto pues WHERE pues.Descripcion = v.d);

	INSERT INTO dbo.rrhhDepartamentoPuesto (IdDepartamento, IdPuesto)
	SELECT depa.IdDepartamento, pues.IdPuesto
	FROM (VALUES ('Soporte técnico', 'Técnico de soporte'), ('Desarrollo', 'Desarrollador')) v(d, p)
	INNER JOIN dbo.rrhhDepartamento depa ON depa.Descripcion = v.d
	INNER JOIN dbo.rrhhPuesto pues ON pues.Descripcion = v.p
	WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhDepartamentoPuesto x WHERE x.IdDepartamento = depa.IdDepartamento AND x.IdPuesto = pues.IdPuesto);

	INSERT INTO dbo.rrhhPlaza (Descripcion, IdDepartamentoPuesto)
	SELECT v.plaza, depu.IdDepartamentoPuesto
	FROM (VALUES ('Técnico de soporte 1', 'Soporte técnico', 'Técnico de soporte'), ('Desarrollador 1', 'Desarrollo', 'Desarrollador')) v(plaza, d, p)
	INNER JOIN dbo.rrhhDepartamento depa ON depa.Descripcion = v.d
	INNER JOIN dbo.rrhhPuesto pues ON pues.Descripcion = v.p
	INNER JOIN dbo.rrhhDepartamentoPuesto depu ON depu.IdDepartamento = depa.IdDepartamento AND depu.IdPuesto = pues.IdPuesto
	WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhPlaza plaz WHERE plaz.Descripcion = v.plaza);

	-- Unidades de prueba del 25 que quedaron vacías.
	DELETE unid FROM dbo.rrhhUnidadOrganizativa unid
	WHERE unid.Descripcion IN ('Operaciones', 'Administración')
	  AND NOT EXISTS (SELECT 1 FROM dbo.rrhhDepartamento depa WHERE depa.IdUnidadOrganizativa = unid.IdUnidadOrganizativa)
	  AND NOT EXISTS (SELECT 1 FROM dbo.rrhhUnidadOrganizativa hijo WHERE hijo.IdUnidadPadre = unid.IdUnidadOrganizativa);
END
GO

------------------------------------------------------------
-- 2. Factura con líneas de servicio
------------------------------------------------------------
IF EXISTS (SELECT 1 FROM dbo.inv_documento_det WHERE det_bien_o_servicio = 'S' AND pro_id IS NULL AND det_id_origen IS NULL)
	PRINT 'Factura con servicios: ya existe, se omite la sección.';
ELSE
BEGIN
	DECLARE @usu_vendedor INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'jperez');
	DECLARE @bod INT = (SELECT TOP 1 bode.bod_id FROM dbo.inv_bodega bode INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
				   WHERE bode.bod_codigo = 'BOD01' ORDER BY CASE sucu.suc_codigo WHEN 'SUC01' THEN 0 ELSE 1 END, sucu.cia_id, bode.bod_id);
	DECLARE @tdo INT = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo = 'FCAM');
	DECLARE @cli INT = (SELECT TOP 1 cli_id FROM dbo.pos_cliente WHERE cli_estado = 'A' ORDER BY cli_id);
	DECLARE @vend INT = (SELECT TOP 1 pve_id FROM dbo.pos_vendedor ORDER BY pve_id);
	DECLARE @hr INT = (SELECT ume_id FROM dbo.inv_unidad_medida WHERE ume_codigo = 'HR');
	DECLARE @srv INT = (SELECT ume_id FROM dbo.inv_unidad_medida WHERE ume_codigo = 'SRV');
	DECLARE @iva NUMERIC(8, 2) = ISNULL((SELECT TOP 1 cia_porc_iva FROM dbo.gen_compania ORDER BY cia_id), 12);
	DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
	DECLARE @primer_pago DATE = DATEADD(MONTH, 1, @hoy);

	-- Un producto con existencia y precio vigente.
	DECLARE @pro INT, @precio NUMERIC(12, 2), @ppr INT, @costo NUMERIC(12, 5);
	SELECT TOP 1 @pro = prod.pro_id, @precio = prec.ppr_precio_unitario_venta, @ppr = prec.ppr_id, @costo = prod.pro_costo_unitario
	FROM dbo.inv_producto prod
	INNER JOIN dbo.inv_producto_precio prec ON prec.pro_id = prod.pro_id AND prec.bod_id = @bod AND prec.ppr_estado = 'A'
	INNER JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = prod.pro_id AND exis.bod_id = @bod AND exis.existencia >= 2
	WHERE prod.pro_maneja_existencia = 1
	ORDER BY prod.pro_id;

	DECLARE @det dbo.factura_det_type, @formas dbo.pago_forma_type, @enc INT, @numero VARCHAR(16);
	INSERT INTO @det (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total, det_costo_unitario, det_porc_iva, bod_id, pro_id, ppr_id, ume_id)
	SELECT 1, 'B', 2, pro_descripcion, ROUND(@precio / (1 + @iva / 100), 2), ROUND(@precio / (1 + @iva / 100), 2) * 2, @costo, @iva, @bod, @pro, @ppr, NULL
	FROM dbo.inv_producto WHERE pro_id = @pro;
	INSERT INTO @det (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total, det_porc_iva, bod_id, pro_id, ume_id)
	VALUES (2, 'S', 3.5, 'Instalación y configuración del equipo en sitio', 200.00, 700.00, @iva, @bod, NULL, @hr),
		   (3, 'S', 1, 'Capacitación básica de uso (grupo de 5 personas)', 450.00, 450.00, @iva, @bod, NULL, @srv);

	EXEC dbo.paVentaFacturaCrear
		@EncFechaDocto = @hoy, @EncNumeroDocto = 'FAC-SERV-1', @CliId = @cli, @TdoId = @tdo, @PveId = @vend,
		@EncFechaPrimerPago = @primer_pago, @EncNumeroCuotas = 2, @UsuId = @usu_vendedor,
		@Detalle = @det, @FormasPago = @formas, @EncId = @enc OUTPUT, @EncNumeroUnico = @numero OUTPUT;
	PRINT CONCAT('Factura con servicios: ', @numero);
END
GO

------------------------------------------------------------
-- 3. Notas de crédito y débito
------------------------------------------------------------
IF EXISTS (SELECT 1 FROM dbo.inv_documento_enc enca INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id WHERE tipo.tdo_es_nota = 1)
	PRINT 'Notas: ya existen, se omite la sección.';
ELSE
BEGIN
	DECLARE @admin INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
	DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
	DECLARE @vence DATE = DATEADD(DAY, 30, @hoy);
	DECLARE @iva NUMERIC(8, 2) = ISNULL((SELECT TOP 1 cia_porc_iva FROM dbo.gen_compania ORDER BY cia_id), 12);
	DECLARE @lineas dbo.nota_det_type, @nota INT, @numero VARCHAR(16);

	-- Crédito a cliente: devuelve 1 unidad de una factura con saldo suficiente
	-- y rebaja Q50 por atraso en la entrega.
	DECLARE @fac INT, @det_fac INT, @precio_fac NUMERIC(12, 2), @iva_fac NUMERIC(8, 2);
	SELECT TOP 1 @fac = enca.enc_id, @det_fac = deta.det_id, @precio_fac = deta.det_precio_unitario, @iva_fac = deta.det_porc_iva
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_codigo = 'FCAM'
	INNER JOIN dbo.inv_documento_det deta ON deta.enc_id = enca.enc_id
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id AND prod.pro_maneja_existencia = 1
	WHERE enca.enc_estado = 'G'
	  AND (SELECT SUM(cpp_saldo_cuota) FROM dbo.pos_cliente_plan_pagos WHERE enc_id = enca.enc_id) > deta.det_precio_unitario * (1 + ISNULL(deta.det_porc_iva, 0) / 100) + 60
	ORDER BY enca.enc_fecha_docto, enca.enc_id;
	IF @fac IS NOT NULL
	BEGIN
		INSERT INTO @lineas (det_item, det_descripcion, det_cantidad, det_precio_unitario, det_porc_iva, det_id_origen)
		VALUES (1, 'Devolución: producto con falla de fábrica', 1, @precio_fac, @iva_fac, @det_fac),
			   (2, 'Rebaja por atraso en la entrega', 1, ROUND(50 / (1 + @iva / 100), 2), @iva, NULL);
		EXEC dbo.paNotaCrear @TipoNota = 'NCC', @EncIdReferencia = @fac, @Fecha = @hoy, @Motivo = 'Devolución por falla y rebaja por atraso',
			@UsuId = @admin, @Detalle = @lineas, @EncId = @nota OUTPUT, @NumeroUnico = @numero OUTPUT;
		PRINT CONCAT('Nota de crédito a cliente: ', @numero);

		-- Débito al mismo cliente: intereses por mora.
		DELETE FROM @lineas;
		INSERT INTO @lineas (det_item, det_descripcion, det_cantidad, det_precio_unitario, det_porc_iva)
		VALUES (1, 'Intereses por mora', 1, ROUND(75 / (1 + @iva / 100), 2), @iva);
		EXEC dbo.paNotaCrear @TipoNota = 'NDC', @EncIdReferencia = @fac, @Fecha = @hoy, @Motivo = 'Intereses por pago atrasado',
			@FechaVencimiento = @vence, @UsuId = @admin, @Detalle = @lineas, @EncId = @nota OUTPUT, @NumeroUnico = @numero OUTPUT;
		PRINT CONCAT('Nota de débito a cliente: ', @numero);
	END

	-- Proveedor: rebaja por monto y cargo por flete sobre una compra con saldo.
	DECLARE @com INT = (SELECT TOP 1 enca.enc_id FROM dbo.inv_documento_enc enca
		INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_codigo = 'COMP'
		WHERE enca.enc_estado = 'G'
		  AND (SELECT SUM(ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0)) FROM dbo.inv_proveedor_plan_pago WHERE enc_id = enca.enc_id) > 500
		ORDER BY enca.enc_id);
	IF @com IS NOT NULL
	BEGIN
		DELETE FROM @lineas;
		INSERT INTO @lineas (det_item, det_descripcion, det_cantidad, det_precio_unitario, det_porc_iva)
		VALUES (1, 'Descuento por volumen de compra', 1, ROUND(300 / (1 + @iva / 100), 2), @iva);
		EXEC dbo.paNotaCrear @TipoNota = 'NCP', @EncIdReferencia = @com, @Fecha = @hoy, @NumeroDocto = 'NC-PRV-0001', @Motivo = 'Descuento por volumen',
			@UsuId = @admin, @Detalle = @lineas, @EncId = @nota OUTPUT, @NumeroUnico = @numero OUTPUT;

		DELETE FROM @lineas;
		INSERT INTO @lineas (det_item, det_descripcion, det_cantidad, det_precio_unitario, det_porc_iva)
		VALUES (1, 'Flete de entrega', 1, ROUND(112 / (1 + @iva / 100), 2), @iva);
		EXEC dbo.paNotaCrear @TipoNota = 'NDP', @EncIdReferencia = @com, @Fecha = @hoy, @NumeroDocto = 'ND-PRV-0001', @Motivo = 'Flete no incluido en la factura',
			@FechaVencimiento = @vence, @UsuId = @admin, @Detalle = @lineas, @EncId = @nota OUTPUT, @NumeroUnico = @numero OUTPUT;
		PRINT 'Notas de proveedor: NC-PRV-0001 y ND-PRV-0001';
	END
END
GO

------------------------------------------------------------
-- Resumen
------------------------------------------------------------
SELECT asie.asi_origen, COUNT(*) AS partidas,
	   SUM(CASE WHEN tota.Debe <> tota.Haber THEN 1 ELSE 0 END) AS descuadradas
FROM dbo.cont_asiento_enc asie
CROSS APPLY (SELECT SUM(asd_debe) AS Debe, SUM(asd_haber) AS Haber FROM dbo.cont_asiento_det WHERE asi_id = asie.asi_id) tota
GROUP BY asie.asi_origen
ORDER BY asie.asi_origen;
GO
