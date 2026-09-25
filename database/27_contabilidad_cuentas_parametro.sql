------------------------------------------------------------------------------
-- 27_contabilidad_cuentas_parametro.sql
--
-- Cuentas contables parametrizadas para las partidas automáticas.
--
-- Antes, sp_contabilidad_generar_asiento_documento buscaba las cuentas por
-- código fijo en el procedimiento ('1205', '4105'...): cambiar el catálogo de
-- cuentas obligaba a editar el SQL. Ahora cada concepto contable apunta a
-- una cuenta en cont_cuenta_parametro y el módulo de contabilidad solo tiene
-- que editar esa tabla.
--
-- Cuándo se genera cada partida (ver README, punto 22):
--   * Venta: al grabar la factura, en la misma transacción. Es el momento en
--     que nace la obligación (devengo), no cuando se cobra. Lo cobrado al
--     facturar (contado o enganche) va a Caja; el resto, a Clientes.
--   * Compra: al grabar el documento de compra.
--   * Anulación: sp_documento_anular anula la partida del documento.
--   * Cobro de cuota, depósito, diferencia de cierre de caja y nómina
--     aprobada: sus conceptos quedan configurados aquí (COBRO_*, DEPOSITO_*,
--     CAJA_*, NOMINA_*) para cuando se construya el módulo contable; todavía
--     no generan partida.
--
-- Se puede volver a correr.
------------------------------------------------------------------------------

USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.cont_cuenta_parametro', 'U') IS NULL
CREATE TABLE [dbo].[cont_cuenta_parametro](
	[ccp_codigo]		VARCHAR(40)		NOT NULL,
	[ccp_descripcion]	VARCHAR(150)	NOT NULL,
	[ccp_naturaleza]	CHAR(1)			NOT NULL,	-- D = se carga (Debe), H = se abona (Haber) en la partida típica
	[cta_id]			INT				NULL,
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_cont_cuenta_parametro] PRIMARY KEY CLUSTERED ([ccp_codigo]),
	CONSTRAINT [CK_cont_cuenta_parametro_naturaleza] CHECK ([ccp_naturaleza] IN ('D','H')),
	CONSTRAINT [FK_cont_cuenta_parametro_cuenta] FOREIGN KEY ([cta_id]) REFERENCES [dbo].[cont_cuenta_contable]([cta_id])
);
GO

-- Cuentas que faltaban en el catálogo de ejemplo para nómina y cierre de caja.
INSERT INTO dbo.cont_cuenta_contable (cta_codigo, cta_nombre, cta_tipo, cta_naturaleza, cta_acepta_movimiento, cta_id_padre, cta_nivel)
SELECT v.codigo, v.nombre, v.tipo, v.naturaleza, 1, padr.cta_id, 2
FROM (VALUES
	('2305', 'IGSS por pagar',          'P', 'H', '2000'),
	('2310', 'Sueldos por pagar',       'P', 'H', '2000'),
	('4205', 'Sobrantes de caja',       'I', 'H', '4000'),
	('5210', 'Sueldos y salarios',      'G', 'D', '5000'),
	('5215', 'Bonificación incentivo',  'G', 'D', '5000'),
	('5220', 'Faltantes de caja',       'G', 'D', '5000')
) v(codigo, nombre, tipo, naturaleza, padre)
INNER JOIN dbo.cont_cuenta_contable padr ON padr.cta_codigo = v.padre
WHERE NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable cuen WHERE cuen.cta_codigo = v.codigo);
GO

INSERT INTO dbo.cont_cuenta_parametro (ccp_codigo, ccp_descripcion, ccp_naturaleza, cta_id)
SELECT v.codigo, v.descripcion, v.naturaleza, cuen.cta_id
FROM (VALUES
	('VENTA_CAJA',              'Venta: lo cobrado al facturar (contado o enganche)', 'D', '1105'),
	('VENTA_CLIENTES',          'Venta: saldo a crédito del cliente',                 'D', '1205'),
	('VENTA_INGRESO',           'Venta: ingreso por ventas (sin IVA)',                'H', '4105'),
	('VENTA_IVA_DEBITO',        'Venta: IVA débito fiscal',                           'H', '2205'),
	('VENTA_COSTO',             'Venta: costo de lo vendido',                         'D', '5105'),
	('INVENTARIO',              'Inventario de mercadería',                           'H', '1310'),
	('COMPRA_GASTO',            'Compra que no afecta inventario (gasto)',            'D', '5205'),
	('COMPRA_IVA_CREDITO',      'Compra: IVA crédito fiscal',                         'D', '1150'),
	('COMPRA_PROVEEDORES',      'Compra: cuentas por pagar a proveedores',            'H', '2105'),
	('COBRO_CAJA',              'Cobro de cuota: ingreso a caja',                     'D', '1105'),
	('COBRO_CLIENTES',          'Cobro de cuota: rebaja de la cuenta del cliente',    'H', '1205'),
	('DEPOSITO_BANCOS',         'Depósito: ingreso al banco',                         'D', '1110'),
	('DEPOSITO_CAJA',           'Depósito: salida de caja',                           'H', '1105'),
	('CAJA_FALTANTE',           'Cierre de caja: faltante',                           'D', '5220'),
	('CAJA_SOBRANTE',           'Cierre de caja: sobrante',                           'H', '4205'),
	('NOMINA_SUELDOS_GASTO',    'Nómina: gasto de sueldos (ingresos del empleado)',   'D', '5210'),
	('NOMINA_BONIFICACION',     'Nómina: gasto de bonificación incentivo',            'D', '5215'),
	('NOMINA_IGSS_POR_PAGAR',   'Nómina: IGSS retenido por pagar',                    'H', '2305'),
	('NOMINA_SUELDOS_POR_PAGAR','Nómina: líquido a pagar a empleados',                'H', '2310')
) v(codigo, descripcion, naturaleza, cuenta)
LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_codigo = v.cuenta
WHERE NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_parametro para WHERE para.ccp_codigo = v.codigo);
GO

-- Cada tipo de movimiento de nómina sabe a qué cuenta va en la partida de
-- nómina: ingresos a gasto, IGSS a su pasivo; los demás descuentos quedan sin
-- cuenta hasta que contabilidad los defina.
UPDATE tipo SET cta_id = cuen.cta_id
FROM dbo.rrhhTipoMovimientoNomina tipo
INNER JOIN (VALUES ('SUELDO', '5210'), ('HORAS_EXTRA', '5210'), ('COMISION', '5210'), ('OTRO_INGRESO', '5210'),
				   ('BONIF_INCENTIVO', '5215'), ('IGSS_LABORAL', '2305')) v(tipo, cuenta) ON v.tipo = tipo.Codigo
INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_codigo = v.cuenta
WHERE tipo.cta_id IS NULL;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaParametroConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT para.ccp_codigo, para.ccp_descripcion, para.ccp_naturaleza, para.cta_id, cuen.cta_codigo, cuen.cta_nombre
	FROM dbo.cont_cuenta_parametro para
	LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = para.cta_id
	ORDER BY para.ccp_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaParametroGuardar]
	@Codigo	VARCHAR(40),
	@CtaId	INT,
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId AND cta_acepta_movimiento = 1 AND cta_estado = 'A')
		THROW 52300, 'La cuenta debe existir, estar activa y aceptar movimientos (no puede ser de agrupación).', 1;
	UPDATE dbo.cont_cuenta_parametro SET cta_id = @CtaId, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE ccp_codigo = @Codigo;
	IF @@ROWCOUNT = 0
		THROW 52301, 'El concepto contable indicado no existe.', 1;
END;
GO

------------------------------------------------------------
-- Partida automática de ventas y compras, ahora con cuentas parametrizadas.
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_contabilidad_generar_asiento_documento]
	@enc_id	INT,
	@usu_id	INT = NULL,
	@asi_id	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @tdo_naturaleza CHAR(1), @afecta_costo CHAR(1), @fecha DATE, @monto_total NUMERIC(12, 2), @origen VARCHAR(20);

	SELECT @tdo_naturaleza = tdo.tdo_naturaleza, @afecta_costo = tdo.afecta_costo,
		   @fecha = enc.enc_fecha_docto, @monto_total = enc.enc_monto_total,
		   @origen = CASE WHEN tdo.tdo_naturaleza = '+' THEN 'COMPRA' ELSE 'VENTA' END
	FROM dbo.inv_documento_enc enc
	INNER JOIN dbo.inv_documento_tipo tdo ON tdo.tdo_id = enc.tdo_id
	WHERE enc.enc_id = @enc_id;

	IF @fecha IS NULL
		THROW 51303, 'El documento indicado no existe.', 1;

	-- Conceptos que usa este procedimiento; si alguno no tiene cuenta, se
	-- detiene con un mensaje claro en lugar de dejar una partida incompleta.
	DECLARE @cuentas TABLE (ccp_codigo VARCHAR(40) PRIMARY KEY, cta_id INT);
	INSERT INTO @cuentas SELECT ccp_codigo, cta_id FROM dbo.cont_cuenta_parametro
	WHERE ccp_codigo IN ('VENTA_CAJA','VENTA_CLIENTES','VENTA_INGRESO','VENTA_IVA_DEBITO','VENTA_COSTO','INVENTARIO',
						 'COMPRA_GASTO','COMPRA_IVA_CREDITO','COMPRA_PROVEEDORES');

	DECLARE @faltante VARCHAR(40) = (SELECT TOP 1 v.c FROM (VALUES ('VENTA_CAJA'),('VENTA_CLIENTES'),('VENTA_INGRESO'),('VENTA_IVA_DEBITO'),
		('VENTA_COSTO'),('INVENTARIO'),('COMPRA_GASTO'),('COMPRA_IVA_CREDITO'),('COMPRA_PROVEEDORES')) v(c)
		LEFT JOIN @cuentas cuen ON cuen.ccp_codigo = v.c WHERE cuen.cta_id IS NULL);
	IF @faltante IS NOT NULL
	BEGIN
		DECLARE @msg_faltante NVARCHAR(200) = CONCAT(N'El concepto contable ', @faltante, N' no tiene cuenta asignada; configúrelo en cont_cuenta_parametro.');
		THROW 51304, @msg_faltante, 1;
	END

	DECLARE @cta_caja INT, @cta_clientes INT, @cta_ingreso INT, @cta_iva_debito INT, @cta_costo INT, @cta_inventario INT,
			@cta_gasto INT, @cta_iva_credito INT, @cta_proveedores INT;
	SELECT @cta_caja = MAX(CASE ccp_codigo WHEN 'VENTA_CAJA' THEN cta_id END),
		   @cta_clientes = MAX(CASE ccp_codigo WHEN 'VENTA_CLIENTES' THEN cta_id END),
		   @cta_ingreso = MAX(CASE ccp_codigo WHEN 'VENTA_INGRESO' THEN cta_id END),
		   @cta_iva_debito = MAX(CASE ccp_codigo WHEN 'VENTA_IVA_DEBITO' THEN cta_id END),
		   @cta_costo = MAX(CASE ccp_codigo WHEN 'VENTA_COSTO' THEN cta_id END),
		   @cta_inventario = MAX(CASE ccp_codigo WHEN 'INVENTARIO' THEN cta_id END),
		   @cta_gasto = MAX(CASE ccp_codigo WHEN 'COMPRA_GASTO' THEN cta_id END),
		   @cta_iva_credito = MAX(CASE ccp_codigo WHEN 'COMPRA_IVA_CREDITO' THEN cta_id END),
		   @cta_proveedores = MAX(CASE ccp_codigo WHEN 'COMPRA_PROVEEDORES' THEN cta_id END)
	FROM @cuentas;

	-- El precio unitario se maneja sin impuesto incluido: el IVA se calcula
	-- sobre el subtotal neto de descuento y se sube aparte al total del
	-- documento (ver @monto_total en sp_ventas_crear_factura / sp_compras_crear_documento).
	DECLARE @iva NUMERIC(14, 2) =
		(SELECT ISNULL(SUM((det_sub_total - det_valor_descuento) * ISNULL(det_porc_iva, 0) / 100.0), 0) FROM dbo.inv_documento_det WHERE enc_id = @enc_id);

	DECLARE @costo_venta NUMERIC(14, 2);
	SELECT @costo_venta = ISNULL(SUM(det.det_cantidad * pro.pro_costo_unitario), 0)
	FROM dbo.inv_documento_det det
	INNER JOIN dbo.inv_producto pro ON pro.pro_id = det.pro_id
	WHERE det.enc_id = @enc_id AND pro.pro_maneja_existencia = 1;

	DECLARE @pdo_id INT;
	EXEC dbo.sp_contabilidad_obtener_o_crear_periodo @fecha = @fecha, @usu_id = @usu_id, @pdo_id = @pdo_id OUTPUT;

	DECLARE @detalle dbo.cont_asiento_det_type;
	DECLARE @ref VARCHAR(10) = CAST(@enc_id AS VARCHAR(10));

	IF @tdo_naturaleza = '-' -- venta
	BEGIN
		-- Lo cobrado al momento de facturar (sp_ventas_crear_factura registra
		-- el pago antes de llamar a este procedimiento) entra a Caja; el resto
		-- queda como cuenta por cobrar al cliente.
		DECLARE @cobrado NUMERIC(12, 2) = (SELECT ISNULL(SUM(ppd_valor_aplicado), 0) FROM dbo.pos_pago_det WHERE enc_id = @enc_id);
		IF @cobrado > @monto_total SET @cobrado = @monto_total;

		IF @cobrado > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_caja, @cobrado, 0, 'Cobro al facturar - documento ' + @ref);
		IF @monto_total - @cobrado > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_clientes, @monto_total - @cobrado, 0, 'Cuentas por cobrar - documento ' + @ref);

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_ingreso, 0, @monto_total - @iva, 'Venta - documento ' + @ref);

		IF @iva > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_iva_debito, 0, @iva, 'IVA débito fiscal - documento ' + @ref);

		IF @costo_venta > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			VALUES (@cta_costo, @costo_venta, 0, 'Costo de venta - documento ' + @ref),
				   (@cta_inventario, 0, @costo_venta, 'Salida de inventario - documento ' + @ref);
	END
	ELSE -- compra
	BEGIN
		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (CASE WHEN @afecta_costo = 'S' THEN @cta_inventario ELSE @cta_gasto END, @monto_total - @iva, 0, 'Compra - documento ' + @ref);

		IF @iva > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_iva_credito, @iva, 0, 'IVA crédito fiscal - documento ' + @ref);

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_proveedores, 0, @monto_total, 'Cuentas por pagar - documento ' + @ref);
	END

	-- EXEC no acepta una expresión (concatenación, CAST) directamente como
	-- valor de un parámetro con nombre; se calcula antes en una variable.
	DECLARE @asi_descripcion VARCHAR(256) = 'Generado automáticamente desde documento ' + @ref;

	EXEC dbo.sp_contabilidad_insertar_asiento
		@asi_fecha = @fecha,
		@asi_descripcion = @asi_descripcion,
		@asi_origen = @origen,
		@enc_id = @enc_id,
		@pdo_id = @pdo_id,
		@usu_id = @usu_id,
		@detalle = @detalle,
		@asi_id = @asi_id OUTPUT;
END;
GO
