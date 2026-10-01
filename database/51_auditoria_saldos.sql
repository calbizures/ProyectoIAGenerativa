/*
================================================================================
 51_auditoria_saldos.sql
 Correcciones de la auditoría completa (scripts 00 a 50).

   1. Saldos de cuotas. Las notas de crédito, los cobros y los cheques a
      proveedores validan el saldo pendiente y luego lo rebajan cuota por
      cuota. Con READ_COMMITTED_SNAPSHOT la validación lee la versión
      confirmada: si dos usuarios aplican al mismo documento al mismo
      tiempo, los dos pasan la validación y la segunda rebaja deja la cuota
      con saldo negativo (o un cheque deja la cuota pagada de más). Las
      reglas CHECK rechazan esa segunda operación y revierten toda su
      transacción:
          pos_cliente_plan_pagos   0 <= saldo <= valor de la cuota
          inv_proveedor_plan_pago  0 <= pagado <= valor de la cuota
      Igual que en el script 50, si hoy hay filas que no cumplen se listan
      y la regla se agrega al volver a correr el script ya corregidas.

   2. Montos que nunca son negativos: formas de pago de un recibo,
      descuento y subtotal de una línea, total, enganche y descuento de un
      documento, horas de un movimiento de nómina.

   3. Baja de empleado: la marca del empleado y el cierre de su historial
      de plaza van en una sola transacción, y un empleado que ya está de
      baja no se vuelve a dar de baja (antes cambiaba su fecha de baja sin
      aviso).

   4. Nota de crédito simultánea a un cobro u otra nota del mismo documento:
      las dos pasaban la validación del saldo; la segunda se grababa por su
      total pero solo rebajaba lo que quedaba en las cuotas (póliza mayor
      que lo aplicado). Ahora se rechaza si no alcanza a aplicarse completa.
      El cheque de una sola cuota (sp_bancos_emitir_cheque_pago_proveedor,
      lo usan los datos de prueba) sobrescribía el pago de otro cheque
      simultáneo; ahora lo detecta y se rechaza. Control 13 en la pantalla
      Contabilidad > Integridad: notas ya grabadas con este defecto.

   5. Caja: dos aperturas simultáneas de la misma caja quedaban las dos
      activas, y dos cierres simultáneos grababan dos pólizas de diferencia.
      La apertura bloquea la caja dentro de la transacción y el cierre solo
      cierra una apertura que sigue activa.

 Errores nuevos: 54301 a 54303.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Saldos de cuotas de clientes y de proveedores
------------------------------------------------------------
IF OBJECT_ID('dbo.CK_pos_cliente_plan_pagos_saldo', 'C') IS NULL
BEGIN
	IF EXISTS (SELECT 1 FROM dbo.pos_cliente_plan_pagos
			   WHERE cpp_valor_cuota < 0 OR cpp_saldo_cuota < 0 OR cpp_saldo_cuota > cpp_valor_cuota)
	BEGIN
		PRINT 'AVISO: hay cuotas de clientes con saldo negativo o mayor que su valor; corríjalas y vuelva a correr este script para activar la regla:';
		SELECT cuot.cpp_id AS Cuota, cuot.enc_id AS Documento, cuot.cpp_nro_cuota AS Numero, cuot.cpp_valor_cuota AS Valor, cuot.cpp_saldo_cuota AS Saldo
		FROM dbo.pos_cliente_plan_pagos cuot
		WHERE cuot.cpp_valor_cuota < 0 OR cuot.cpp_saldo_cuota < 0 OR cuot.cpp_saldo_cuota > cuot.cpp_valor_cuota;
	END
	ELSE
		ALTER TABLE dbo.pos_cliente_plan_pagos ADD CONSTRAINT [CK_pos_cliente_plan_pagos_saldo]
			CHECK ([cpp_valor_cuota] >= 0 AND [cpp_saldo_cuota] >= 0 AND [cpp_saldo_cuota] <= [cpp_valor_cuota]);
END
GO

IF OBJECT_ID('dbo.CK_inv_proveedor_plan_pago_saldo', 'C') IS NULL
BEGIN
	IF EXISTS (SELECT 1 FROM dbo.inv_proveedor_plan_pago
			   WHERE ppg_valor_pago < 0 OR ISNULL(ppg_valor_real_pago, 0) < 0 OR ISNULL(ppg_valor_real_pago, 0) > ppg_valor_pago)
	BEGIN
		PRINT 'AVISO: hay cuotas de proveedores con pago negativo o mayor que su valor; corríjalas y vuelva a correr este script para activar la regla:';
		SELECT cuot.ppg_id AS Cuota, cuot.enc_id AS Documento, cuot.ppg_nro_pago AS Numero, cuot.ppg_valor_pago AS Valor, cuot.ppg_valor_real_pago AS Pagado
		FROM dbo.inv_proveedor_plan_pago cuot
		WHERE cuot.ppg_valor_pago < 0 OR ISNULL(cuot.ppg_valor_real_pago, 0) < 0 OR ISNULL(cuot.ppg_valor_real_pago, 0) > cuot.ppg_valor_pago;
	END
	ELSE
		ALTER TABLE dbo.inv_proveedor_plan_pago ADD CONSTRAINT [CK_inv_proveedor_plan_pago_saldo]
			CHECK ([ppg_valor_pago] >= 0 AND ISNULL([ppg_valor_real_pago], 0) >= 0 AND ISNULL([ppg_valor_real_pago], 0) <= [ppg_valor_pago]);
END
GO

------------------------------------------------------------
-- 2. Montos que nunca son negativos
------------------------------------------------------------
IF OBJECT_ID('dbo.CK_pos_pago_forma_monto', 'C') IS NULL
	AND NOT EXISTS (SELECT 1 FROM dbo.pos_pago_forma WHERE ppf_monto <= 0)
	ALTER TABLE dbo.pos_pago_forma ADD CONSTRAINT [CK_pos_pago_forma_monto] CHECK ([ppf_monto] > 0);
GO

IF OBJECT_ID('dbo.CK_inv_documento_det_montos', 'C') IS NULL
	AND NOT EXISTS (SELECT 1 FROM dbo.inv_documento_det WHERE ISNULL(det_valor_descuento, 0) < 0 OR det_sub_total < 0)
	ALTER TABLE dbo.inv_documento_det ADD CONSTRAINT [CK_inv_documento_det_montos]
		CHECK (ISNULL([det_valor_descuento], 0) >= 0 AND [det_sub_total] >= 0);
GO

IF OBJECT_ID('dbo.CK_inv_documento_enc_montos', 'C') IS NULL
	AND NOT EXISTS (SELECT 1 FROM dbo.inv_documento_enc
					WHERE enc_monto_total < 0 OR ISNULL(enc_monto_enganche, 0) < 0 OR ISNULL(enc_valor_descuento, 0) < 0)
	ALTER TABLE dbo.inv_documento_enc ADD CONSTRAINT [CK_inv_documento_enc_montos]
		CHECK ([enc_monto_total] >= 0 AND ISNULL([enc_monto_enganche], 0) >= 0 AND ISNULL([enc_valor_descuento], 0) >= 0);
GO

IF OBJECT_ID('dbo.CK_rrhhMovimientoNomina_Horas', 'C') IS NULL
	AND NOT EXISTS (SELECT 1 FROM dbo.rrhhMovimientoNomina WHERE Horas < 0)
	ALTER TABLE dbo.rrhhMovimientoNomina ADD CONSTRAINT [CK_rrhhMovimientoNomina_Horas] CHECK ([Horas] IS NULL OR [Horas] >= 0);
GO

------------------------------------------------------------
-- 3. Baja de empleado en una sola transacción
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoDarBaja]
	@IdEmpleado	INT,
	@FechaBaja	DATE,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF EXISTS (SELECT 1 FROM dbo.rrhhEmpleado WHERE IdEmpleado = @IdEmpleado AND FechaIngreso > @FechaBaja)
		THROW 52044, 'La fecha de baja no puede ser anterior a la fecha de ingreso.', 1;

	BEGIN TRANSACTION;
	-- Solo un empleado activo pasa a baja; el bloqueo evita que dos bajas
	-- simultáneas cambien dos veces la fecha.
	UPDATE dbo.rrhhEmpleado WITH (UPDLOCK, HOLDLOCK)
	   SET Estado = 'B', FechaBaja = @FechaBaja, IdPlaza = NULL, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdEmpleado = @IdEmpleado AND Estado = 'A';
	IF @@ROWCOUNT = 0
		THROW 54301, 'El empleado ya está de baja o no existe.', 1;

	UPDATE dbo.rrhhHistorialPlaza SET FechaAl = @FechaBaja WHERE IdEmpleado = @IdEmpleado AND FechaAl IS NULL;
	COMMIT;
END;
GO

------------------------------------------------------------
-- 4. Nota de crédito y cheque a una cuota con el saldo cambiado
--    por otro usuario al mismo tiempo
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paNotaCrear]
	@TipoNota			CHAR(3),			-- NCC, NDC, NCP, NDP
	@EncIdReferencia	INT,
	@Fecha				DATE,
	@NumeroDocto		VARCHAR(32) = NULL,	-- número del proveedor (NCP/NDP)
	@Motivo				VARCHAR(256),
	@FechaVencimiento	DATE = NULL,		-- nota de débito: vencimiento de la cuota nueva
	@UsuId				INT = NULL,
	@Detalle			dbo.nota_det_type READONLY,
	@EncId				INT OUTPUT,
	@NumeroUnico		VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- Los parámetros OUTPUT también llegan con el valor que traiga quien llama.
	SELECT @EncId = NULL, @NumeroUnico = NULL;

	DECLARE @es_cliente BIT = CASE WHEN @TipoNota IN ('NCC', 'NDC') THEN 1 ELSE 0 END,
			@es_credito BIT = CASE WHEN @TipoNota IN ('NCC', 'NCP') THEN 1 ELSE 0 END;

	IF @TipoNota NOT IN ('NCC', 'NDC', 'NCP', 'NDP')
		THROW 53101, 'El tipo de nota debe ser NCC, NDC, NCP o NDP.', 1;
	IF ISNULL(LTRIM(RTRIM(@Motivo)), '') = ''
		THROW 53102, 'Ingrese el motivo de la nota.', 1;
	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 53103, 'La nota debe tener al menos una línea.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE det_cantidad <= 0 OR det_precio_unitario < 0 OR LTRIM(RTRIM(det_descripcion)) = '')
		THROW 53104, 'Cada línea necesita descripción, cantidad mayor a cero y precio no negativo.', 1;
	IF @es_credito = 0 AND EXISTS (SELECT 1 FROM @Detalle WHERE det_id_origen IS NOT NULL)
		THROW 53105, 'Una nota de débito no lleva devoluciones de producto.', 1;
	IF @es_credito = 0 AND @FechaVencimiento IS NULL
		THROW 53106, 'Indique la fecha de vencimiento del cargo de la nota de débito.', 1;
	IF @es_cliente = 0 AND ISNULL(LTRIM(RTRIM(@NumeroDocto)), '') = ''
		THROW 53107, 'Ingrese el número de la nota del proveedor.', 1;

	-- Documento de referencia: factura (cliente) o compra (proveedor) grabada.
	DECLARE @ref_cli INT, @ref_prv INT, @ref_estado CHAR(1), @ref_es_nota BIT, @ref_naturaleza CHAR(1), @ref_afecta_costo CHAR(1),
			@ref_mon INT, @ref_bod INT;
	SELECT @ref_cli = enca.cli_id, @ref_prv = enca.prv_id, @ref_estado = enca.enc_estado, @ref_es_nota = tipo.tdo_es_nota,
		   @ref_naturaleza = tipo.tdo_naturaleza, @ref_afecta_costo = tipo.afecta_costo, @ref_mon = enca.mon_id,
		   @ref_bod = (SELECT TOP 1 bod_id FROM dbo.inv_documento_det WHERE enc_id = enca.enc_id ORDER BY det_item)
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @EncIdReferencia;

	IF @ref_estado IS NULL OR @ref_es_nota = 1
		THROW 53108, 'El documento de referencia no existe o es otra nota.', 1;
	IF @ref_estado <> 'G'
		THROW 53109, 'El documento de referencia debe estar grabado (no anulado).', 1;
	IF @es_cliente = 1 AND (@ref_cli IS NULL OR @ref_naturaleza <> '-')
		THROW 53110, 'Una nota a cliente debe referirse a una factura.', 1;
	IF @es_cliente = 0 AND (@ref_prv IS NULL OR @ref_naturaleza <> '+')
		THROW 53111, 'Una nota de proveedor debe referirse a una compra.', 1;

	-- Líneas con los datos que faltan tomados de la línea original.
	DECLARE @lineas TABLE (det_item INT PRIMARY KEY, det_descripcion VARCHAR(256), det_cantidad NUMERIC(12, 4), det_precio_unitario NUMERIC(12, 2),
		det_sub_total NUMERIC(12, 2), det_porc_iva NUMERIC(8, 2), ume_id INT, det_id_origen INT, pro_id INT, bod_id INT, maneja_existencia BIT,
		costo_unitario NUMERIC(14, 5));
	INSERT INTO @lineas
	SELECT deta.det_item, deta.det_descripcion, deta.det_cantidad, deta.det_precio_unitario,
		   ROUND(deta.det_cantidad * deta.det_precio_unitario, 2), ISNULL(deta.det_porc_iva, orig.det_porc_iva),
		   COALESCE(orig.ume_id, deta.ume_id), deta.det_id_origen, orig.pro_id, ISNULL(orig.bod_id, @ref_bod),
		   ISNULL(prod.pro_maneja_existencia, 0),
		   -- costo con que vuelve (o sale) la mercadería: el costo de la venta
		   -- original; en compras, el costo de compra de la línea.
		   CASE WHEN @es_cliente = 1 THEN COALESCE(orig.det_costo_unitario, prod.pro_costo_unitario, 0)
				ELSE deta.det_precio_unitario END
	FROM @Detalle deta
	LEFT JOIN dbo.inv_documento_det orig ON orig.det_id = deta.det_id_origen
	LEFT JOIN dbo.inv_producto prod ON prod.pro_id = orig.pro_id;

	IF EXISTS (SELECT 1 FROM @lineas lin LEFT JOIN dbo.inv_documento_det orig ON orig.det_id = lin.det_id_origen
			   WHERE lin.det_id_origen IS NOT NULL AND (orig.enc_id IS NULL OR orig.enc_id <> @EncIdReferencia OR orig.pro_id IS NULL))
		THROW 53112, 'Una línea de devolución no corresponde a un producto del documento de referencia.', 1;

	-- No se puede devolver más de lo vendido/comprado menos lo ya devuelto.
	IF EXISTS (
		SELECT 1
		FROM (SELECT det_id_origen, SUM(det_cantidad) AS cantidad FROM @lineas WHERE det_id_origen IS NOT NULL GROUP BY det_id_origen) dev
		INNER JOIN dbo.inv_documento_det orig ON orig.det_id = dev.det_id_origen
		CROSS APPLY (SELECT ISNULL(SUM(prev.det_cantidad), 0) AS devuelto
					 FROM dbo.inv_documento_det prev
					 INNER JOIN dbo.inv_documento_enc nota ON nota.enc_id = prev.enc_id AND nota.enc_estado = 'G'
					 WHERE prev.det_id_origen = orig.det_id) ante
		WHERE dev.cantidad > orig.det_cantidad - ante.devuelto)
		THROW 53113, 'La cantidad devuelta supera lo que queda por devolver de esa línea.', 1;

	IF EXISTS (SELECT 1 FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1 AND det_cantidad <> ROUND(det_cantidad, 0))
		THROW 53114, 'Los productos con existencia se devuelven en cantidades enteras.', 1;

	-- Devolución al proveedor: la mercadería debe estar en la bodega.
	IF @es_cliente = 0 AND @es_credito = 1 AND EXISTS (
		SELECT 1
		FROM (SELECT pro_id, bod_id, SUM(det_cantidad) AS cantidad FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1 GROUP BY pro_id, bod_id) dev
		LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = dev.pro_id AND exis.bod_id = dev.bod_id
		WHERE ISNULL(exis.existencia, 0) < dev.cantidad)
		THROW 53115, 'No hay existencia suficiente en la bodega para devolver esa mercadería al proveedor.', 1;

	DECLARE @neto NUMERIC(14, 2) = (SELECT SUM(det_sub_total) FROM @lineas),
			@neto_devolucion NUMERIC(14, 2) = (SELECT ISNULL(SUM(det_sub_total), 0) FROM @lineas WHERE det_id_origen IS NOT NULL),
			@costo_devolucion NUMERIC(14, 2) = (SELECT ISNULL(SUM(ROUND(det_cantidad * costo_unitario, 2)), 0) FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1),
			@total NUMERIC(14, 2) = (SELECT ROUND(SUM(det_sub_total * (1 + ISNULL(det_porc_iva, 0) / 100.0)), 2) FROM @lineas);
	DECLARE @iva NUMERIC(14, 2) = @total - @neto;

	IF @total <= 0
		THROW 53116, 'El total de la nota debe ser mayor a cero.', 1;

	-- Una nota de crédito no puede dejar el documento con saldo negativo.
	DECLARE @pendiente NUMERIC(14, 2) = CASE WHEN @es_cliente = 1
		THEN (SELECT ISNULL(SUM(cpp_saldo_cuota), 0) FROM dbo.pos_cliente_plan_pagos WHERE enc_id = @EncIdReferencia AND cpp_saldo_cuota > 0)
		ELSE (SELECT ISNULL(SUM(ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0)), 0) FROM dbo.inv_proveedor_plan_pago
			  WHERE enc_id = @EncIdReferencia AND ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0) > 0) END;
	IF @es_credito = 1 AND @total > @pendiente
	BEGIN
		DECLARE @msg_saldo NVARCHAR(300) = CONCAT(N'La nota de crédito (Q', FORMAT(@total, 'N2'), N') supera el saldo pendiente del documento (Q',
			FORMAT(@pendiente, 'N2'), N').');
		THROW 53117, @msg_saldo, 1;
	END

	-- Cuentas de la póliza (se validan antes de grabar nada).
	DECLARE @cta_clientes INT, @cta_iva_debito INT, @cta_inventario INT, @cta_costo INT, @cta_proveedores INT, @cta_iva_credito INT,
			@cta_gasto_compra INT, @cta_contrapartida INT;
	IF @es_cliente = 1
	BEGIN
		EXEC dbo.paCuentaParametroObtener @Codigo = 'VENTA_CLIENTES', @CtaId = @cta_clientes OUTPUT;
		EXEC dbo.paCuentaParametroObtener @Codigo = 'VENTA_IVA_DEBITO', @CtaId = @cta_iva_debito OUTPUT;
		IF @es_credito = 1
		BEGIN
			EXEC dbo.paCuentaParametroObtener @Codigo = 'NC_CLIENTE_REBAJA', @CtaId = @cta_contrapartida OUTPUT;
			IF @costo_devolucion > 0
			BEGIN
				EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO', @CtaId = @cta_inventario OUTPUT;
				EXEC dbo.paCuentaParametroObtener @Codigo = 'VENTA_COSTO', @CtaId = @cta_costo OUTPUT;
			END
		END
		ELSE
			EXEC dbo.paCuentaParametroObtener @Codigo = 'ND_CLIENTE_INGRESO', @CtaId = @cta_contrapartida OUTPUT;
	END
	ELSE
	BEGIN
		EXEC dbo.paCuentaParametroObtener @Codigo = 'COMPRA_PROVEEDORES', @CtaId = @cta_proveedores OUTPUT;
		EXEC dbo.paCuentaParametroObtener @Codigo = 'COMPRA_IVA_CREDITO', @CtaId = @cta_iva_credito OUTPUT;
		IF @es_credito = 1
		BEGIN
			IF @neto - @neto_devolucion > 0
				EXEC dbo.paCuentaParametroObtener @Codigo = 'NC_PROVEEDOR_REBAJA', @CtaId = @cta_contrapartida OUTPUT;
			IF @neto_devolucion > 0
			BEGIN
				-- EXEC no acepta una expresión como valor de un parámetro.
				DECLARE @concepto_devolucion VARCHAR(40) = CASE WHEN @ref_afecta_costo = 'S' THEN 'INVENTARIO' ELSE 'COMPRA_GASTO' END;
				EXEC dbo.paCuentaParametroObtener @Codigo = @concepto_devolucion, @CtaId = @cta_inventario OUTPUT;
			END
		END
		ELSE
			EXEC dbo.paCuentaParametroObtener @Codigo = 'ND_PROVEEDOR_GASTO', @CtaId = @cta_contrapartida OUTPUT;
	END

	DECLARE @tdo_id INT = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo = @TipoNota);
	DECLARE @referencia VARCHAR(40);

	BEGIN TRANSACTION;

	-- Correlativo (solo notas a clientes).
	IF @es_cliente = 1
	BEGIN
		DECLARE @serie VARCHAR(32), @correlativo NUMERIC(12, 0);
		SELECT @serie = serie, @correlativo = correlativo + 1 FROM dbo.conf_correlativos WITH (UPDLOCK, ROWLOCK) WHERE tdo_id = @tdo_id;
		IF @serie IS NULL
			THROW 51403, 'No existe una serie de correlativos configurada para este tipo de documento.', 1;
		UPDATE dbo.conf_correlativos SET correlativo = @correlativo, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE tdo_id = @tdo_id;
		SET @NumeroUnico = @serie + '-' + CAST(@correlativo AS VARCHAR(20));
	END

	INSERT INTO dbo.inv_documento_enc
		(enc_fecha_docto, enc_numero_docto, cli_id, enc_nombres_cliente, enc_apellidos_cliente, cli_nit,
		 prv_id, prv_enc_nombres_proveedor, prv_enc_apellidos_proveedor, prv_nit, tdo_id, enc_monto_total, enc_id_referencia,
		 mon_id, enc_numero_unico, enc_motivo, usu_id_creacion, enc_estado, InsUsuario, InsFechaHora)
	SELECT @Fecha, @NumeroDocto, refe.cli_id, refe.enc_nombres_cliente, refe.enc_apellidos_cliente, refe.cli_nit,
		   refe.prv_id, refe.prv_enc_nombres_proveedor, refe.prv_enc_apellidos_proveedor, refe.prv_nit, @tdo_id, @total, @EncIdReferencia,
		   @ref_mon, @NumeroUnico, LTRIM(RTRIM(@Motivo)), @UsuId, 'G', @UsuId, SYSDATETIME()
	FROM dbo.inv_documento_enc refe WHERE refe.enc_id = @EncIdReferencia;
	SET @EncId = SCOPE_IDENTITY();
	SET @referencia = CONCAT(@TipoNota, ' ', ISNULL(@NumeroUnico, @NumeroDocto));

	INSERT INTO dbo.inv_documento_det
		(enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total, det_costo_unitario,
		 det_porc_iva, bod_id, pro_id, ume_id, det_id_origen, InsUsuario, InsFechaHora)
	SELECT @EncId, det_item, CASE WHEN pro_id IS NULL THEN 'S' ELSE 'B' END, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total,
		   CASE WHEN maneja_existencia = 1 THEN costo_unitario END, det_porc_iva, bod_id, pro_id, ume_id, det_id_origen, @UsuId, SYSDATETIME()
	FROM @lineas;

	-- Inventario de las devoluciones: entra (cliente) o sale (proveedor) al
	-- costo de la línea, y se recalcula el costo promedio.
	IF EXISTS (SELECT 1 FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1)
	BEGIN
		DECLARE @signo INT = CASE WHEN @es_cliente = 1 THEN 1 ELSE -1 END;
		DECLARE @movimientos TABLE (pro_id INT, bod_id INT, cantidad NUMERIC(14, 4), costo NUMERIC(14, 2), PRIMARY KEY (pro_id, bod_id));
		INSERT INTO @movimientos
		SELECT pro_id, bod_id, SUM(det_cantidad) * @signo, SUM(ROUND(det_cantidad * costo_unitario, 2)) * @signo
		FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1
		GROUP BY pro_id, bod_id;

		MERGE dbo.inv_producto_existencia_bodega AS destino
		USING @movimientos AS origen ON destino.pro_id = origen.pro_id AND destino.bod_id = origen.bod_id
		WHEN MATCHED THEN UPDATE SET existencia = destino.existencia + origen.cantidad, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		WHEN NOT MATCHED THEN INSERT (bod_id, pro_id, existencia, InsUsuario, InsFechaHora) VALUES (origen.bod_id, origen.pro_id, origen.cantidad, @UsuId, SYSDATETIME());

		;WITH totales AS (SELECT pro_id, SUM(cantidad) AS cantidad, SUM(costo) AS costo FROM @movimientos GROUP BY pro_id)
		UPDATE prod
		   SET prod.pro_total_cantidad = prod.pro_total_cantidad + tota.cantidad,
			   prod.pro_total_costo = prod.pro_total_costo + tota.costo,
			   prod.pro_costo_unitario = CASE WHEN prod.pro_total_cantidad + tota.cantidad > 0
											  THEN (prod.pro_total_costo + tota.costo) / (prod.pro_total_cantidad + tota.cantidad) ELSE 0 END,
			   prod.UpdUsuario = @UsuId, prod.UpdFechaHora = SYSDATETIME()
		FROM dbo.inv_producto prod INNER JOIN totales tota ON tota.pro_id = prod.pro_id;
	END

	-- Plan de pagos.
	IF @es_credito = 1
	BEGIN
		-- Rebaja desde la última cuota hacia atrás.
		DECLARE @restante NUMERIC(14, 2) = @total, @cuota INT, @saldo_cuota NUMERIC(14, 2), @aplicado NUMERIC(14, 2);
		IF @es_cliente = 1
		BEGIN
			DECLARE cuotas_cur CURSOR LOCAL FAST_FORWARD FOR
				SELECT cpp_id, cpp_saldo_cuota FROM dbo.pos_cliente_plan_pagos
				WHERE enc_id = @EncIdReferencia AND cpp_saldo_cuota > 0 ORDER BY cpp_nro_cuota DESC;
			OPEN cuotas_cur;
			FETCH NEXT FROM cuotas_cur INTO @cuota, @saldo_cuota;
			WHILE @@FETCH_STATUS = 0 AND @restante > 0
			BEGIN
				SET @aplicado = CASE WHEN @saldo_cuota < @restante THEN @saldo_cuota ELSE @restante END;
				UPDATE dbo.pos_cliente_plan_pagos
				   SET cpp_saldo_cuota = cpp_saldo_cuota - @aplicado,
					   cpp_estado = CASE WHEN cpp_saldo_cuota - @aplicado <= 0 THEN 'A' ELSE cpp_estado END,
					   cpp_fecha_real_pago = CASE WHEN cpp_saldo_cuota - @aplicado <= 0 THEN @Fecha ELSE cpp_fecha_real_pago END,
					   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
				 WHERE cpp_id = @cuota;
				INSERT INTO dbo.pos_cliente_nota_aplicacion (enc_id_nota, cpp_id, cna_monto, InsUsuario) VALUES (@EncId, @cuota, @aplicado, @UsuId);
				SET @restante = @restante - @aplicado;
				FETCH NEXT FROM cuotas_cur INTO @cuota, @saldo_cuota;
			END
			CLOSE cuotas_cur; DEALLOCATE cuotas_cur;
		END
		ELSE
		BEGIN
			DECLARE pagos_cur CURSOR LOCAL FAST_FORWARD FOR
				SELECT ppg_id, ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0) FROM dbo.inv_proveedor_plan_pago
				WHERE enc_id = @EncIdReferencia AND ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0) > 0 ORDER BY ppg_nro_pago DESC;
			OPEN pagos_cur;
			FETCH NEXT FROM pagos_cur INTO @cuota, @saldo_cuota;
			WHILE @@FETCH_STATUS = 0 AND @restante > 0
			BEGIN
				SET @aplicado = CASE WHEN @saldo_cuota < @restante THEN @saldo_cuota ELSE @restante END;
				UPDATE dbo.inv_proveedor_plan_pago
				   SET ppg_valor_pago = ppg_valor_pago - @aplicado,
					   ppg_estado = CASE WHEN ppg_valor_pago - @aplicado <= ISNULL(ppg_valor_real_pago, 0) THEN 'A' ELSE ppg_estado END,
					   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
				 WHERE ppg_id = @cuota;
				INSERT INTO dbo.inv_proveedor_nota_aplicacion (enc_id_nota, ppg_id, pna_monto, InsUsuario) VALUES (@EncId, @cuota, @aplicado, @UsuId);
				SET @restante = @restante - @aplicado;
				FETCH NEXT FROM pagos_cur INTO @cuota, @saldo_cuota;
			END
			CLOSE pagos_cur; DEALLOCATE pagos_cur;
		END
		-- La validación del saldo (antes de la transacción) lee la versión
		-- confirmada: si otro usuario aplicó un cobro, un pago o una nota al
		-- mismo documento al mismo tiempo, aquí el saldo ya no alcanza y la
		-- nota no se graba (antes se grababa por el total y solo rebajaba lo
		-- que quedaba, y la póliza no cuadraba con las cuotas).
		IF @restante > 0
			THROW 54302, 'El saldo del documento cambió mientras se grababa la nota (otro usuario aplicó un cobro, pago o nota al mismo tiempo). Vuelva a consultarlo e intente de nuevo.', 1;
	END
	ELSE
	BEGIN
		-- Nota de débito: cuota nueva al final del plan del documento.
		DECLARE @nueva_cuota INT;
		IF @es_cliente = 1
		BEGIN
			INSERT INTO dbo.pos_cliente_plan_pagos
				(cpp_nro_cuota, cpp_fecha_maxima_pago, cpp_valor_cuota, cpp_saldo_cuota, enc_id, cli_id, cpp_estado, InsUsuario, InsFechaHora)
			SELECT ISNULL(MAX(cpp_nro_cuota), 0) + 1, @FechaVencimiento, @total, @total, @EncIdReferencia, @ref_cli, 'P', @UsuId, SYSDATETIME()
			FROM dbo.pos_cliente_plan_pagos WHERE enc_id = @EncIdReferencia;
			SET @nueva_cuota = SCOPE_IDENTITY();
			INSERT INTO dbo.pos_cliente_nota_aplicacion (enc_id_nota, cpp_id, cna_monto, InsUsuario) VALUES (@EncId, @nueva_cuota, @total, @UsuId);
		END
		ELSE
		BEGIN
			INSERT INTO dbo.inv_proveedor_plan_pago (ppg_nro_pago, ppg_fecha_pago, ppg_valor_pago, enc_id, prv_id, ppg_estado, InsUsuario, InsFechaHora)
			SELECT ISNULL(MAX(ppg_nro_pago), 0) + 1, @FechaVencimiento, @total, @EncIdReferencia, @ref_prv, 'P', @UsuId, SYSDATETIME()
			FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @EncIdReferencia;
			SET @nueva_cuota = SCOPE_IDENTITY();
			INSERT INTO dbo.inv_proveedor_nota_aplicacion (enc_id_nota, ppg_id, pna_monto, InsUsuario) VALUES (@EncId, @nueva_cuota, @total, @UsuId);
		END
	END

	-- Póliza.
	DECLARE @partida dbo.cont_asiento_det_type, @asi_id INT;
	IF @TipoNota = 'NCC'
	BEGIN
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_contrapartida, @neto, 0, @referencia);
		IF @iva > 0 INSERT INTO @partida VALUES (@cta_iva_debito, @iva, 0, @referencia);
		INSERT INTO @partida VALUES (@cta_clientes, 0, @total, @referencia);
		IF @costo_devolucion > 0
			INSERT INTO @partida VALUES (@cta_inventario, @costo_devolucion, 0, CONCAT(@referencia, ' - reingreso')),
										(@cta_costo, 0, @costo_devolucion, CONCAT(@referencia, ' - reingreso'));
	END
	ELSE IF @TipoNota = 'NDC'
	BEGIN
		INSERT INTO @partida VALUES (@cta_clientes, @total, 0, @referencia), (@cta_contrapartida, 0, @neto, @referencia);
		IF @iva > 0 INSERT INTO @partida VALUES (@cta_iva_debito, 0, @iva, @referencia);
	END
	ELSE IF @TipoNota = 'NCP'
	BEGIN
		INSERT INTO @partida VALUES (@cta_proveedores, @total, 0, @referencia);
		IF @neto_devolucion > 0 INSERT INTO @partida VALUES (@cta_inventario, 0, @neto_devolucion, CONCAT(@referencia, ' - devolución'));
		IF @neto - @neto_devolucion > 0 INSERT INTO @partida VALUES (@cta_contrapartida, 0, @neto - @neto_devolucion, @referencia);
		IF @iva > 0 INSERT INTO @partida VALUES (@cta_iva_credito, 0, @iva, @referencia);
	END
	ELSE
	BEGIN
		INSERT INTO @partida VALUES (@cta_contrapartida, @neto, 0, @referencia);
		IF @iva > 0 INSERT INTO @partida VALUES (@cta_iva_credito, @iva, 0, @referencia);
		INSERT INTO @partida VALUES (@cta_proveedores, 0, @total, @referencia);
	END

	DECLARE @origen VARCHAR(20) = CASE WHEN @es_credito = 1 THEN 'NOTA_CREDITO' ELSE 'NOTA_DEBITO' END;
	DECLARE @descripcion VARCHAR(256) = CONCAT(@referencia, ' - ', LTRIM(RTRIM(@Motivo)));
	EXEC dbo.sp_contabilidad_insertar_asiento
		@asi_fecha = @Fecha, @asi_descripcion = @descripcion, @asi_origen = @origen, @asi_origen_id = @EncId, @enc_id = @EncId,
		@usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;

	COMMIT TRANSACTION;
END;
GO

-- Cheque a proveedor por una sola cuota (lo usan los datos de prueba).
CREATE OR ALTER PROCEDURE [dbo].[sp_bancos_emitir_cheque_pago_proveedor]
	@ppg_id				INT,
	@cbc_id				INT,
	@bce_numero_cheque	VARCHAR(16),
	@valor_pago			NUMERIC(12, 2),
	@bmp_id				INT = NULL,
	@usu_id				INT = NULL,
	@bce_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @valor_pago <= 0
		THROW 51601, 'El valor del pago debe ser mayor a cero.', 1;

	DECLARE @enc_id INT, @valor_programado NUMERIC(12, 2), @valor_pagado NUMERIC(12, 2), @estado CHAR(1);
	SELECT @enc_id = enc_id, @valor_programado = ppg_valor_pago, @valor_pagado = ISNULL(ppg_valor_real_pago, 0), @estado = ppg_estado
	FROM dbo.inv_proveedor_plan_pago WHERE ppg_id = @ppg_id;

	IF @enc_id IS NULL
		THROW 51602, 'La cuota de proveedor indicada no existe.', 1;
	IF @estado = 'A' OR @valor_programado - @valor_pagado <= 0
		THROW 51603, 'La cuota de proveedor indicada ya está pagada por completo.', 1;
	IF @valor_pago > @valor_programado - @valor_pagado
	BEGIN
		DECLARE @msg NVARCHAR(200) = CONCAT(N'El pago (Q', FORMAT(@valor_pago, 'N2'), N') supera el saldo de la cuota (Q',
			FORMAT(@valor_programado - @valor_pagado, 'N2'), N').');
		THROW 51604, @msg, 1;
	END
	IF EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_id = @enc_id AND enc_estado <> 'G')
		THROW 53217, 'La compra de esa cuota está anulada.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @cbc_id)
		THROW 51606, 'La chequera indicada no existe.', 1;
	-- Chequera activa, número dentro del rango y sin repetir (vacío = siguiente).
	EXEC dbo.paBcoChequeValidarNumero @CbcId = @cbc_id, @Numero = @bce_numero_cheque OUTPUT;

	DECLARE @cta_proveedores INT, @cta_bancos INT = dbo.fnBcoCuentaContable((SELECT bcb_id FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @cbc_id));
	EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_PROVEEDORES', @CtaId = @cta_proveedores OUTPUT;
	IF @cta_bancos IS NULL
		EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_bancos OUTPUT;

	DECLARE @beneficiario VARCHAR(150) = (SELECT prov.prv_nombre_comercial FROM dbo.inv_documento_enc docu
										  INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = docu.prv_id WHERE docu.enc_id = @enc_id);

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.bco_cheque_emitido_enc
			(cbc_id, bce_fecha_emision, usu_id, bce_numero_cheque, bce_documento_ref, bce_valor, bmp_id, bce_tipo, bce_beneficiario, InsUsuario, InsFechaHora)
		VALUES
			(@cbc_id, CAST(GETDATE() AS DATE), @usu_id, @bce_numero_cheque, CAST(@enc_id AS VARCHAR(16)), @valor_pago, @bmp_id, 'P', @beneficiario, @usu_id, SYSDATETIME());

		SET @bce_id = SCOPE_IDENTITY();

		INSERT INTO dbo.bco_cheque_emitido_det (bce_id, bmp_id, enc_id, ppg_id, ced_valor, ced_abono_cancelacion, InsUsuario, InsFechaHora)
		VALUES (@bce_id, @bmp_id, @enc_id, @ppg_id, @valor_pago,
				CASE WHEN @valor_pagado + @valor_pago >= @valor_programado THEN 'C' ELSE 'A' END,
				@usu_id, SYSDATETIME());

		UPDATE dbo.inv_proveedor_plan_pago
		   SET ppg_valor_real_pago = @valor_pagado + @valor_pago,
			   ppg_fecha_real_pago = CAST(GETDATE() AS DATE),
			   ppg_numero_cheque = @bce_numero_cheque,
			   cbc_id = @cbc_id,
			   ppg_estado = CASE WHEN @valor_pagado + @valor_pago >= @valor_programado THEN 'A' ELSE ppg_estado END,
			   UpdUsuario = @usu_id,
			   UpdFechaHora = SYSDATETIME()
		 WHERE ppg_id = @ppg_id
		   AND ISNULL(ppg_valor_real_pago, 0) = @valor_pagado;
		-- El pagado se leyó antes de la transacción: si otro cheque pagó la
		-- misma cuota mientras tanto, no se sobrescribe su pago.
		IF @@ROWCOUNT = 0
			THROW 54303, 'Otro usuario pagó la misma cuota mientras se emitía el cheque. Vuelva a consultarla e intente de nuevo.', 1;

		DECLARE @asi_id INT, @partida dbo.cont_asiento_det_type, @fecha_hoy DATE = CAST(GETDATE() AS DATE);
		DECLARE @referencia VARCHAR(64) = 'Pago a proveedor - cheque ' + @bce_numero_cheque;
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_proveedores, @valor_pago, 0, @referencia), (@cta_bancos, 0, @valor_pago, @referencia);

		DECLARE @asi_descripcion VARCHAR(256) = 'Pago a proveedor con cheque ' + @bce_numero_cheque;
		EXEC dbo.sp_contabilidad_insertar_asiento
			@asi_fecha = @fecha_hoy, @asi_descripcion = @asi_descripcion,
			@asi_origen = 'PAGO_PROVEEDOR', @asi_origen_id = @bce_id, @enc_id = @enc_id,
			@usu_id = @usu_id, @detalle = @partida, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 5. Control 13 de integridad: notas aplicadas por menos de su total
--    (las que se grabaron con el defecto del punto 4)
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

	INSERT INTO @r
	-- Script 51: una nota se aplica completa a las cuotas o no se graba.
	SELECT 13, 'Notas vigentes cuyo total no coincide con lo aplicado a las cuotas', COUNT(*), MIN(CONCAT(tipo.tdo_codigo, ' ', ISNULL(nota.enc_numero_unico, nota.enc_numero_docto)))
	FROM dbo.inv_documento_enc nota
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = nota.tdo_id
	CROSS APPLY (SELECT ISNULL((SELECT SUM(apli.cna_monto) FROM dbo.pos_cliente_nota_aplicacion apli WHERE apli.enc_id_nota = nota.enc_id), 0)
					  + ISNULL((SELECT SUM(apli.pna_monto) FROM dbo.inv_proveedor_nota_aplicacion apli WHERE apli.enc_id_nota = nota.enc_id), 0) AS Aplicado) apli
	WHERE tipo.tdo_es_nota = 1 AND nota.enc_estado = 'G'
	  AND (EXISTS (SELECT 1 FROM dbo.pos_cliente_nota_aplicacion x WHERE x.enc_id_nota = nota.enc_id)
		   OR EXISTS (SELECT 1 FROM dbo.inv_proveedor_nota_aplicacion x WHERE x.enc_id_nota = nota.enc_id))
	  AND ABS(nota.enc_monto_total - apli.Aplicado) > 0.01;

	SELECT Orden, Control, Casos, CASE WHEN Casos = 0 THEN NULL ELSE Ejemplo END AS Ejemplo,
		   CASE WHEN Casos = 0 THEN 'OK' ELSE 'REVISAR' END AS Resultado
	FROM @r ORDER BY Orden;
END;
GO

------------------------------------------------------------
-- 6. Apertura y cierre de caja simultáneos
------------------------------------------------------------
-- Apertura de caja: monto inicial libre.
CREATE OR ALTER PROCEDURE [dbo].[sp_pos_caja_abrir]
	@pcr_id				INT,
	@usu_id				INT,
	@pca_monto_inicial	NUMERIC(12, 2) = 0,
	@pca_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	BEGIN TRANSACTION;
	-- El bloqueo de rango (UPDLOCK, HOLDLOCK) hace que una segunda apertura
	-- simultánea de la misma caja espere a la primera y luego la encuentre.
	IF EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WITH (UPDLOCK, HOLDLOCK) WHERE pcr_id = @pcr_id AND pca_estado = 'A')
		THROW 51701, 'Ya existe una apertura de caja activa para esta caja receptora. Debe cerrarse antes de abrir una nueva.', 1;

	INSERT INTO dbo.pos_caja_apertura (pcr_id, usu_id_apertura, pca_monto_inicial, InsUsuario, InsFechaHora)
	VALUES (@pcr_id, @usu_id, ISNULL(@pca_monto_inicial, 0), @usu_id, SYSDATETIME());

	SET @pca_id = SCOPE_IDENTITY();
	COMMIT TRANSACTION;
END;
GO

-- Cierre de caja: faltante o sobrante dentro de la tolerancia.
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
	 WHERE pca_id = @pca_id AND pca_estado = 'A';
	-- Dos cierres simultáneos pasan la validación de arriba; solo el primero
	-- cierra y graba la póliza de la diferencia.
	IF @@ROWCOUNT = 0
		THROW 51702, 'La apertura de caja indicada no existe o ya está cerrada.', 1;

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

PRINT '51_auditoria_saldos.sql aplicado.';
GO
