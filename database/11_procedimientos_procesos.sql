/*
	Script 11: Procesos de negocio.

	Aquí se corrigen los errores más importantes que tenía el script original:

	1) spr_guarda_compra / spr_guarda_factura hacían
	       UPDATE inv_documento_enc SET enc_estado = 'G'
	   SIN WHERE, por lo que cada factura o compra grabada dejaba en estado
	   "Grabado" a TODOS los documentos de la tabla. Aquí todo UPDATE lleva
	   su WHERE enc_id = @enc_id.

	2) spr_guarda_factura hacía
	       UPDATE conf_correlativos SET correlatio = (SELECT correlatio + 1 FROM conf_correlativos c)
	   también sin WHERE (y con una subconsulta ambigua si hay más de una
	   serie). Aquí el correlativo se toma con UPDLOCK/ROWLOCK filtrando por
	   tipo de documento, evitando además condiciones de carrera entre dos
	   facturas grabándose al mismo tiempo.

	3) SPR_ACTUALIZA_EXISTENCIAS recalculaba TODO el historial de documentos
	   con un cursor cada vez que se grababa una sola factura o compra
	   (costo O(n) por transacción). Aquí las existencias y el costo
	   promedio se ajustan de forma incremental, solo con las líneas del
	   documento que se está grabando (sp_inventario_ajustar_existencia_documento).
	   El recálculo completo se conserva como
	   sp_inventario_recalcular_existencias_completo, para usarse solo como
	   utilidad de reconciliación/mantenimiento.

	4) SPR_LOGIN_USUARIO comparaba la contraseña en texto plano. Aquí se
	   compara el hash (ver sp_usuario_insertar/sp_usuario_cambiar_password
	   en 10_procedimientos_crud.sql) y se bloquea el usuario tras varios
	   intentos fallidos.

	5) No existía ningún procedimiento para anular un documento ya grabado.
	   Se agrega sp_documento_anular.

	Auditoría: igual que en 10_procedimientos_crud.sql, todo procedimiento que
	inserta o actualiza una fila recibe (o ya recibía, para su propio uso de
	negocio: p.ej. inv_documento_enc.usu_id_creacion) un parámetro @usu_id y
	lo graba en InsUsuario/UpdUsuario junto con InsFechaHora/UpdFechaHora =
	SYSDATETIME(). Los procedimientos internos que antes no necesitaban saber
	quién ejecuta la acción (sp_inventario_ajustar_existencia_documento,
	sp_inventario_recalcular_existencias_completo,
	sp_pos_generar_plan_pagos_cliente, sp_inv_generar_plan_pagos_proveedor,
	sp_contabilidad_obtener_o_crear_periodo) ahora reciben @usu_id también,
	y los procedimientos de más arriba en la cadena de llamadas
	(sp_ventas_crear_factura, sp_compras_crear_documento, sp_documento_anular,
	sp_pos_registrar_pago_cuota, sp_bancos_emitir_cheque_pago_proveedor) se lo
	pasan hacia abajo.
*/
USE [erp_db];
GO

------------------------------------------------------------
-- Inventario: ajuste incremental y recálculo completo
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_inventario_ajustar_existencia_documento]
	@enc_id		INT,
	@reversar	BIT = 0,	-- 1 = revertir el efecto (usado al anular un documento)
	@usu_id		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @naturaleza_signo INT, @reversar_signo INT = CASE WHEN @reversar = 1 THEN -1 ELSE 1 END;

	SELECT @naturaleza_signo = CASE WHEN tdo.tdo_naturaleza = '+' THEN 1 ELSE -1 END
	FROM dbo.inv_documento_enc enc
	INNER JOIN dbo.inv_documento_tipo tdo ON tdo.tdo_id = enc.tdo_id
	WHERE enc.enc_id = @enc_id;

	IF @naturaleza_signo IS NULL
		THROW 51201, 'El documento indicado no existe.', 1;

	-- Movimientos agregados por producto/bodega (solo bienes con control de existencia).
	-- Para ingresos (compras) el costo es el precio pagado; para egresos (ventas) el
	-- costo es el costo promedio actual del producto, NO el precio de venta.
	DECLARE @movimientos TABLE (
		[pro_id]	INT				NOT NULL,
		[bod_id]	INT				NOT NULL,
		[cantidad]	NUMERIC(12, 4)	NOT NULL,
		[costo]		NUMERIC(14, 2)	NOT NULL,
		PRIMARY KEY ([pro_id], [bod_id])
	);

	INSERT INTO @movimientos ([pro_id], [bod_id], [cantidad], [costo])
	SELECT
		det.pro_id,
		det.bod_id,
		SUM(det.det_cantidad) * @naturaleza_signo * @reversar_signo,
		SUM(det.det_cantidad *
			CASE WHEN @naturaleza_signo = 1
				 THEN det.det_sub_total / NULLIF(det.det_cantidad, 0)
				 ELSE pro.pro_costo_unitario
			END
		) * @naturaleza_signo * @reversar_signo
	FROM dbo.inv_documento_det det
	INNER JOIN dbo.inv_producto pro ON pro.pro_id = det.pro_id
	WHERE det.enc_id = @enc_id
	  AND det.pro_id IS NOT NULL
	  AND pro.pro_maneja_existencia = 1
	GROUP BY det.pro_id, det.bod_id;

	MERGE dbo.inv_producto_existencia_bodega AS destino
	USING @movimientos AS origen
		ON destino.pro_id = origen.pro_id AND destino.bod_id = origen.bod_id
	WHEN MATCHED THEN
		UPDATE SET existencia = destino.existencia + origen.cantidad,
				   UpdUsuario = @usu_id,
				   UpdFechaHora = SYSDATETIME()
	WHEN NOT MATCHED THEN
		INSERT (bod_id, pro_id, existencia, InsUsuario, InsFechaHora)
		VALUES (origen.bod_id, origen.pro_id, origen.cantidad, @usu_id, SYSDATETIME());

	;WITH totales AS (
		SELECT pro_id, SUM(cantidad) AS cantidad, SUM(costo) AS costo
		FROM @movimientos
		GROUP BY pro_id
	)
	UPDATE p
	   SET p.pro_total_cantidad = p.pro_total_cantidad + t.cantidad,
		   p.pro_total_costo   = p.pro_total_costo + t.costo,
		   p.pro_costo_unitario = CASE WHEN p.pro_total_cantidad + t.cantidad > 0
										THEN (p.pro_total_costo + t.costo) / (p.pro_total_cantidad + t.cantidad)
										ELSE 0 END,
		   p.UpdUsuario = @usu_id,
		   p.UpdFechaHora = SYSDATETIME()
	FROM dbo.inv_producto p
	INNER JOIN totales t ON t.pro_id = p.pro_id;
END;
GO

/*
	Recálculo completo desde cero de existencias y costo promedio, recorriendo
	TODO el historial de documentos grabados en orden cronológico. Es la
	versión corregida de SPR_ACTUALIZA_EXISTENCIAS del script original: úsese
	solo como utilidad de mantenimiento/reconciliación (por ejemplo tras una
	migración de datos), nunca como parte del flujo normal de grabar una
	factura o una compra.
*/
CREATE OR ALTER PROCEDURE [dbo].[sp_inventario_recalcular_existencias_completo]
	@usu_id INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	UPDATE dbo.inv_producto
	   SET pro_total_cantidad = 0, pro_total_costo = 0, pro_costo_unitario = 0,
		   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
	 WHERE pro_maneja_existencia = 1;

	UPDATE peb
	   SET existencia = 0,
		   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
	FROM dbo.inv_producto_existencia_bodega peb
	INNER JOIN dbo.inv_producto pro ON pro.pro_id = peb.pro_id
	WHERE pro.pro_maneja_existencia = 1;

	DECLARE @enc_id INT;

	DECLARE c1 CURSOR LOCAL FAST_FORWARD FOR
		SELECT enc.enc_id
		FROM dbo.inv_documento_enc enc
		WHERE enc.enc_estado = 'G'
		ORDER BY enc.enc_fecha_docto, enc.enc_id;

	OPEN c1;
	FETCH NEXT FROM c1 INTO @enc_id;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		EXEC dbo.sp_inventario_ajustar_existencia_documento @enc_id = @enc_id, @reversar = 0, @usu_id = @usu_id;
		FETCH NEXT FROM c1 INTO @enc_id;
	END
	CLOSE c1;
	DEALLOCATE c1;
END;
GO

------------------------------------------------------------
-- Planes de pago (cuotas)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_pos_generar_plan_pagos_cliente]
	@enc_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @contador INT, @fecha_iteracion DATE, @valor_cuota NUMERIC(13, 2),
			@cli_id INT, @numero_cuotas INT, @fecha_primer_pago DATE,
			@monto_enganche NUMERIC(13, 2), @monto_total NUMERIC(13, 2);

	SELECT @cli_id = cli_id, @numero_cuotas = enc_numero_cuotas,
		   @fecha_primer_pago = enc_fecha_primer_pago, @monto_total = enc_monto_total,
		   @monto_enganche = enc_monto_enganche
	FROM dbo.inv_documento_enc
	WHERE enc_id = @enc_id;

	-- enc_monto_total ya viene neto de descuento (ver sp_ventas_crear_factura),
	-- así que aquí sólo se resta el enganche; restar también el descuento
	-- duplicaba la resta y dejaba el monto financiado por debajo del real.
	IF @fecha_primer_pago IS NOT NULL AND @monto_total IS NOT NULL AND @numero_cuotas IS NOT NULL AND @numero_cuotas > 0
	BEGIN
		SET @contador = 1;
		SET @valor_cuota = (ISNULL(@monto_total, 0) - ISNULL(@monto_enganche, 0)) / @numero_cuotas;
		SET @fecha_iteracion = @fecha_primer_pago;

		WHILE @contador <= @numero_cuotas
		BEGIN
			INSERT INTO dbo.pos_cliente_plan_pagos
				(cpp_nro_cuota, cpp_fecha_maxima_pago, cpp_valor_cuota, cpp_saldo_cuota, enc_id, cli_id, cpp_estado,
				 InsUsuario, InsFechaHora)
			VALUES
				(@contador, @fecha_iteracion, @valor_cuota, @valor_cuota, @enc_id, @cli_id, 'P',
				 @usu_id, SYSDATETIME());

			SET @contador = @contador + 1;
			SET @fecha_iteracion = DATEADD(MONTH, 1, @fecha_iteracion);
			IF DATEPART(dw, @fecha_iteracion) = 7
				SET @fecha_iteracion = DATEADD(DAY, 1, @fecha_iteracion);
		END

		-- Ajusta la última cuota para que la suma cuadre exactamente con el monto financiado.
		DECLARE @monto_cuotas NUMERIC(12, 2), @monto_restante NUMERIC(12, 2);

		SELECT @monto_cuotas = SUM(cpp_valor_cuota) FROM dbo.pos_cliente_plan_pagos WHERE enc_id = @enc_id;
		SET @monto_restante = (ISNULL(@monto_total, 0) - ISNULL(@monto_enganche, 0)) - ISNULL(@monto_cuotas, 0);

		IF @monto_restante <> 0
			UPDATE dbo.pos_cliente_plan_pagos
			   SET cpp_valor_cuota = cpp_valor_cuota + @monto_restante,
				   cpp_saldo_cuota = cpp_saldo_cuota + @monto_restante,
				   UpdUsuario = @usu_id,
				   UpdFechaHora = SYSDATETIME()
			 WHERE enc_id = @enc_id
			   AND cpp_nro_cuota = (SELECT MAX(cpp_nro_cuota) FROM dbo.pos_cliente_plan_pagos WHERE enc_id = @enc_id);
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_inv_generar_plan_pagos_proveedor]
	@enc_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @contador INT, @fecha_iteracion DATE, @valor_cuota NUMERIC(13, 2),
			@prv_id INT, @numero_cuotas INT, @fecha_primer_pago DATE,
			@monto_total NUMERIC(13, 2), @monto_enganche NUMERIC(13, 2);

	SELECT @prv_id = prv_id, @numero_cuotas = enc_numero_cuotas,
		   @fecha_primer_pago = enc_fecha_primer_pago, @monto_total = enc_monto_total,
		   @monto_enganche = enc_monto_enganche
	FROM dbo.inv_documento_enc
	WHERE enc_id = @enc_id;

	IF @fecha_primer_pago IS NOT NULL AND @monto_total IS NOT NULL AND @numero_cuotas IS NOT NULL AND @numero_cuotas > 0
	BEGIN
		SET @contador = 1;
		SET @valor_cuota = (ISNULL(@monto_total, 0) - ISNULL(@monto_enganche, 0)) / @numero_cuotas;
		SET @fecha_iteracion = @fecha_primer_pago;

		WHILE @contador <= @numero_cuotas
		BEGIN
			INSERT INTO dbo.inv_proveedor_plan_pago
				(ppg_nro_pago, ppg_fecha_pago, ppg_valor_pago, enc_id, prv_id, ppg_estado,
				 InsUsuario, InsFechaHora)
			VALUES
				(@contador, @fecha_iteracion, @valor_cuota, @enc_id, @prv_id, 'P',
				 @usu_id, SYSDATETIME());

			SET @contador = @contador + 1;
			SET @fecha_iteracion = DATEADD(MONTH, 1, @fecha_iteracion);
			IF DATEPART(dw, @fecha_iteracion) = 7
				SET @fecha_iteracion = DATEADD(DAY, 1, @fecha_iteracion);
		END

		DECLARE @monto_cuotas NUMERIC(12, 2), @monto_restante NUMERIC(12, 2);

		SELECT @monto_cuotas = SUM(ppg_valor_pago) FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @enc_id;
		SET @monto_restante = (ISNULL(@monto_total, 0) - ISNULL(@monto_enganche, 0)) - ISNULL(@monto_cuotas, 0);

		IF @monto_restante <> 0
			UPDATE dbo.inv_proveedor_plan_pago
			   SET ppg_valor_pago = ppg_valor_pago + @monto_restante,
				   UpdUsuario = @usu_id,
				   UpdFechaHora = SYSDATETIME()
			 WHERE enc_id = @enc_id
			   AND ppg_nro_pago = (SELECT MAX(ppg_nro_pago) FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @enc_id);
	END
END;
GO

------------------------------------------------------------
-- Contabilidad: inserción genérica de asientos y generación automática
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_contabilidad_obtener_o_crear_periodo]
	@fecha	DATE = NULL,
	@usu_id	INT = NULL,
	@pdo_id	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	SET @fecha = ISNULL(@fecha, CAST(GETDATE() AS DATE));
	DECLARE @anio INT = YEAR(@fecha), @mes INT = MONTH(@fecha);

	SELECT @pdo_id = pdo_id FROM dbo.cont_periodo_contable WHERE pdo_anio = @anio AND pdo_mes = @mes;

	IF @pdo_id IS NULL
	BEGIN
		INSERT INTO dbo.cont_periodo_contable (pdo_anio, pdo_mes, InsUsuario, InsFechaHora)
		VALUES (@anio, @mes, @usu_id, SYSDATETIME());
		SET @pdo_id = SCOPE_IDENTITY();
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_contabilidad_insertar_asiento]
	@asi_fecha			DATE,
	@asi_descripcion	VARCHAR(256) = NULL,
	@asi_origen			VARCHAR(20) = 'MANUAL',
	@enc_id				INT = NULL,
	@pdo_id				INT = NULL,
	@usu_id				INT = NULL,
	@detalle			dbo.cont_asiento_det_type READONLY,
	@asi_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @detalle)
		THROW 51301, 'El asiento debe tener al menos una línea.', 1;

	IF (SELECT ISNULL(SUM(asd_debe), 0) FROM @detalle) <> (SELECT ISNULL(SUM(asd_haber), 0) FROM @detalle)
		THROW 51302, 'El asiento no está balanceado: la suma del Debe debe ser igual a la suma del Haber.', 1;

	IF @pdo_id IS NULL
		EXEC dbo.sp_contabilidad_obtener_o_crear_periodo @fecha = @asi_fecha, @usu_id = @usu_id, @pdo_id = @pdo_id OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.cont_asiento_enc
			(asi_fecha, asi_descripcion, asi_origen, enc_id, pdo_id, usu_id, InsUsuario, InsFechaHora)
		VALUES
			(@asi_fecha, @asi_descripcion, @asi_origen, @enc_id, @pdo_id, @usu_id, @usu_id, SYSDATETIME());

		SET @asi_id = SCOPE_IDENTITY();

		INSERT INTO dbo.cont_asiento_det (asi_id, cta_id, asd_debe, asd_haber, asd_descripcion, InsUsuario, InsFechaHora)
		SELECT @asi_id, cta_id, asd_debe, asd_haber, asd_descripcion, @usu_id, SYSDATETIME()
		FROM @detalle;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

/*
	Genera automáticamente el asiento contable de una venta o una compra ya
	grabada, usando un catálogo de cuentas por código (ver 12_datos_sinteticos.sql
	para los códigos sembrados: 1105 Caja, 1110 Bancos, 1150 IVA crédito,
	1205 Clientes, 1310 Inventarios, 2105 Proveedores, 2205 IVA débito,
	4105 Ventas, 5105 Costo de ventas, 5205 Gastos/compras que no son
	inventariables). Es una contabilización simplificada pensada para que el
	modelo sea funcional y fácil de adaptar; no reemplaza un motor fiscal
	certificado.
*/
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

	IF @tdo_naturaleza = '-' -- venta
	BEGIN
		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, @monto_total, 0, 'Cuentas por cobrar - documento ' + CAST(@enc_id AS VARCHAR(10))
		FROM dbo.cont_cuenta_contable WHERE cta_codigo = '1205'
		UNION ALL
		SELECT cta_id, 0, @monto_total - @iva, 'Venta - documento ' + CAST(@enc_id AS VARCHAR(10))
		FROM dbo.cont_cuenta_contable WHERE cta_codigo = '4105';

		IF @iva > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			SELECT cta_id, 0, @iva, 'IVA débito fiscal - documento ' + CAST(@enc_id AS VARCHAR(10))
			FROM dbo.cont_cuenta_contable WHERE cta_codigo = '2205';

		IF @costo_venta > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			SELECT cta_id, @costo_venta, 0, 'Costo de venta - documento ' + CAST(@enc_id AS VARCHAR(10))
			FROM dbo.cont_cuenta_contable WHERE cta_codigo = '5105'
			UNION ALL
			SELECT cta_id, 0, @costo_venta, 'Salida de inventario - documento ' + CAST(@enc_id AS VARCHAR(10))
			FROM dbo.cont_cuenta_contable WHERE cta_codigo = '1310';
	END
	ELSE -- compra
	BEGIN
		DECLARE @cuenta_destino VARCHAR(20) = CASE WHEN @afecta_costo = 'S' THEN '1310' ELSE '5205' END;

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, @monto_total - @iva, 0, 'Compra - documento ' + CAST(@enc_id AS VARCHAR(10))
		FROM dbo.cont_cuenta_contable WHERE cta_codigo = @cuenta_destino;

		IF @iva > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			SELECT cta_id, @iva, 0, 'IVA crédito fiscal - documento ' + CAST(@enc_id AS VARCHAR(10))
			FROM dbo.cont_cuenta_contable WHERE cta_codigo = '1150';

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, 0, @monto_total, 'Cuentas por pagar - documento ' + CAST(@enc_id AS VARCHAR(10))
		FROM dbo.cont_cuenta_contable WHERE cta_codigo = '2105';
	END

	-- EXEC no acepta una expresión (concatenación, CAST) directamente como
	-- valor de un parámetro con nombre; se calcula antes en una variable.
	DECLARE @asi_descripcion VARCHAR(256) = 'Generado automáticamente desde documento ' + CAST(@enc_id AS VARCHAR(10));

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

------------------------------------------------------------
-- Ventas y compras (encabezado + detalle + efectos colaterales)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_ventas_crear_factura]
	@enc_fecha_docto			DATE,
	@enc_numero_autorizacion	VARCHAR(64) = NULL,
	@enc_serie_docto			VARCHAR(32) = NULL,
	@enc_numero_docto			VARCHAR(32) = NULL,
	@cli_id						INT,
	@enc_nombres_cliente		VARCHAR(128) = NULL,
	@enc_apellidos_cliente		VARCHAR(128) = NULL,
	@cli_nit					VARCHAR(16) = NULL,
	@tdo_id						INT,
	@pve_id						INT = NULL,
	@enc_fecha_primer_pago		DATE = NULL,
	@enc_monto_enganche			NUMERIC(12, 2) = 0,
	@enc_numero_cuotas			INT = 1,
	@enc_valor_descuento		NUMERIC(13, 2) = 0,
	@enc_direccion_cliente		VARCHAR(256) = NULL,
	@mon_id						INT = NULL,
	@usu_id						INT = NULL,
	@detalle					dbo.factura_det_type READONLY,
	@pca_id						INT = NULL,				-- apertura de caja activa donde se recibe el pago inicial
	@formas_pago				dbo.pago_forma_type READONLY = NULL,	-- pago de contado, o enganche si es a crédito
	@enc_id						INT OUTPUT,
	@enc_numero_unico			VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @detalle)
		THROW 51401, 'La factura debe tener al menos una línea de detalle.', 1;

	IF @mon_id IS NULL
		SET @mon_id = dbo.fn_moneda_local();

	IF EXISTS (
		SELECT 1
		FROM @detalle d
		INNER JOIN dbo.inv_producto p ON p.pro_id = d.pro_id
		LEFT JOIN dbo.inv_producto_existencia_bodega e ON e.pro_id = d.pro_id AND e.bod_id = d.bod_id
		WHERE p.pro_maneja_existencia = 1
		  AND ISNULL(e.existencia, 0) < d.det_cantidad
	)
		THROW 51402, 'No hay existencia suficiente para uno o más productos del detalle.', 1;

	-- El monto total del documento es el neto (subtotal - descuento) más el
	-- IVA de cada línea; los precios unitarios se manejan sin impuesto
	-- incluido (ver también sp_contabilidad_generar_asiento_documento).
	DECLARE @monto_total NUMERIC(12, 2) = (
		SELECT SUM((det_sub_total - det_valor_descuento) * (1 + ISNULL(det_porc_iva, 0) / 100.0))
		FROM @detalle
	);

	BEGIN TRY
		BEGIN TRANSACTION;

		DECLARE @serie VARCHAR(32), @correlativo NUMERIC(12, 0);

		SELECT @serie = serie, @correlativo = correlativo + 1
		FROM dbo.conf_correlativos WITH (UPDLOCK, ROWLOCK)
		WHERE tdo_id = @tdo_id;

		IF @serie IS NULL
			THROW 51403, 'No existe una serie de correlativos configurada para este tipo de documento.', 1;

		UPDATE dbo.conf_correlativos
		   SET correlativo = @correlativo,
			   UpdUsuario = @usu_id,
			   UpdFechaHora = SYSDATETIME()
		 WHERE tdo_id = @tdo_id;

		SET @enc_numero_unico = @serie + '-' + CAST(@correlativo AS VARCHAR(20));

		INSERT INTO dbo.inv_documento_enc
			(enc_fecha_docto, enc_numero_autorizacion, enc_serie_docto, enc_numero_docto,
			 cli_id, enc_nombres_cliente, enc_apellidos_cliente, cli_nit, tdo_id, pve_id,
			 enc_fecha_primer_pago, enc_monto_enganche, enc_numero_cuotas, enc_monto_total,
			 enc_valor_descuento, enc_direccion_cliente, mon_id, usu_id_creacion, enc_numero_unico,
			 InsUsuario, InsFechaHora)
		VALUES
			(@enc_fecha_docto, @enc_numero_autorizacion, @enc_serie_docto, @enc_numero_docto,
			 @cli_id, @enc_nombres_cliente, @enc_apellidos_cliente, @cli_nit, @tdo_id, @pve_id,
			 @enc_fecha_primer_pago, @enc_monto_enganche, @enc_numero_cuotas, @monto_total,
			 @enc_valor_descuento, @enc_direccion_cliente, @mon_id, @usu_id, @enc_numero_unico,
			 @usu_id, SYSDATETIME());

		SET @enc_id = SCOPE_IDENTITY();

		INSERT INTO dbo.inv_documento_det
			(enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			 det_precio_unitario, det_valor_descuento, det_sub_total, det_costo_unitario, det_porc_iva, bod_id, pro_id, ppr_id,
			 InsUsuario, InsFechaHora)
		SELECT
			@enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			det_precio_unitario, det_valor_descuento, det_sub_total, det_costo_unitario, det_porc_iva, bod_id, pro_id, ppr_id,
			@usu_id, SYSDATETIME()
		FROM @detalle;

		IF @pca_id IS NOT NULL AND EXISTS (SELECT 1 FROM @formas_pago)
		BEGIN
			DECLARE @ppe_id INT;

			INSERT INTO dbo.pos_pago_enc (cli_id, pca_id, usu_id, InsUsuario, InsFechaHora)
			VALUES (@cli_id, @pca_id, @usu_id, @usu_id, SYSDATETIME());

			SET @ppe_id = SCOPE_IDENTITY();

			INSERT INTO dbo.pos_pago_forma
				(gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, ppe_id, pft_id, InsUsuario, InsFechaHora)
			SELECT gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, @ppe_id, pft_id, @usu_id, SYSDATETIME()
			FROM @formas_pago;

			INSERT INTO dbo.pos_pago_det (ppe_id, enc_id, ppd_valor_aplicado, InsUsuario, InsFechaHora)
			SELECT @ppe_id, @enc_id, SUM(ppf_monto), @usu_id, SYSDATETIME()
			FROM @formas_pago;
		END

		EXEC dbo.sp_pos_generar_plan_pagos_cliente @enc_id = @enc_id, @usu_id = @usu_id;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'G',
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @enc_id;

		EXEC dbo.sp_inventario_ajustar_existencia_documento @enc_id = @enc_id, @usu_id = @usu_id;

		DECLARE @asi_id INT;
		EXEC dbo.sp_contabilidad_generar_asiento_documento @enc_id = @enc_id, @usu_id = @usu_id, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_compras_crear_documento]
	@enc_fecha_docto				DATE,
	@enc_numero_autorizacion		VARCHAR(64) = NULL,
	@enc_serie_docto				VARCHAR(32) = NULL,
	@enc_numero_docto				VARCHAR(32) = NULL,
	@prv_id							INT,
	@prv_enc_nombres_proveedor		VARCHAR(128) = NULL,
	@prv_enc_apellidos_proveedor	VARCHAR(128) = NULL,
	@prv_nit						VARCHAR(16) = NULL,
	@tdo_id							INT,
	@enc_fecha_primer_pago			DATE = NULL,
	@enc_monto_enganche				NUMERIC(12, 2) = 0,
	@enc_numero_cuotas				INT = 1,
	@enc_valor_descuento			NUMERIC(13, 2) = 0,
	@mon_id							INT = NULL,
	@usu_id							INT = NULL,
	@detalle						dbo.compra_det_type READONLY,
	@enc_id							INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @detalle)
		THROW 51411, 'La compra debe tener al menos una línea de detalle.', 1;

	IF @mon_id IS NULL
		SET @mon_id = dbo.fn_moneda_local();

	-- El monto total del documento es el neto (subtotal - descuento) más el
	-- IVA de cada línea; los precios unitarios se manejan sin impuesto
	-- incluido (ver también sp_contabilidad_generar_asiento_documento).
	DECLARE @monto_total NUMERIC(12, 2) = (
		SELECT SUM((det_sub_total - det_valor_descuento) * (1 + ISNULL(det_porc_iva, 0) / 100.0))
		FROM @detalle
	);

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.inv_documento_enc
			(enc_fecha_docto, enc_numero_autorizacion, enc_serie_docto, enc_numero_docto,
			 prv_id, prv_enc_nombres_proveedor, prv_enc_apellidos_proveedor, prv_nit, tdo_id,
			 enc_fecha_primer_pago, enc_monto_enganche, enc_numero_cuotas, enc_monto_total,
			 enc_valor_descuento, mon_id, usu_id_creacion,
			 InsUsuario, InsFechaHora)
		VALUES
			(@enc_fecha_docto, @enc_numero_autorizacion, @enc_serie_docto, @enc_numero_docto,
			 @prv_id, @prv_enc_nombres_proveedor, @prv_enc_apellidos_proveedor, @prv_nit, @tdo_id,
			 @enc_fecha_primer_pago, @enc_monto_enganche, @enc_numero_cuotas, @monto_total,
			 @enc_valor_descuento, @mon_id, @usu_id,
			 @usu_id, SYSDATETIME());

		SET @enc_id = SCOPE_IDENTITY();

		INSERT INTO dbo.inv_documento_det
			(enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			 det_precio_unitario, det_valor_descuento, det_sub_total, det_porc_iva, bod_id, pro_id,
			 InsUsuario, InsFechaHora)
		SELECT
			@enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			det_precio_unitario, det_valor_descuento, det_sub_total, det_porc_iva, bod_id, pro_id,
			@usu_id, SYSDATETIME()
		FROM @detalle;

		EXEC dbo.sp_inv_generar_plan_pagos_proveedor @enc_id = @enc_id, @usu_id = @usu_id;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'G',
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @enc_id;

		EXEC dbo.sp_inventario_ajustar_existencia_documento @enc_id = @enc_id, @usu_id = @usu_id;

		DECLARE @asi_id INT;
		EXEC dbo.sp_contabilidad_generar_asiento_documento @enc_id = @enc_id, @usu_id = @usu_id, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

/*
	Anula un documento ya grabado: revierte su efecto en existencias y anula
	su asiento contable. No revierte automáticamente las cuotas de plan de
	pago ya generadas (pos_cliente_plan_pagos / inv_proveedor_plan_pago);
	si aplica, se gestionan aparte porque cancelar un documento no implica
	necesariamente cancelar un compromiso de pago ya acordado con el cliente.
*/
CREATE OR ALTER PROCEDURE [dbo].[sp_documento_anular]
	@enc_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado_actual CHAR(1);
	SELECT @estado_actual = enc_estado FROM dbo.inv_documento_enc WHERE enc_id = @enc_id;

	IF @estado_actual IS NULL
		THROW 51421, 'El documento indicado no existe.', 1;

	IF @estado_actual <> 'G'
		THROW 51422, 'Solo se pueden anular documentos que estén en estado Grabado.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		EXEC dbo.sp_inventario_ajustar_existencia_documento @enc_id = @enc_id, @reversar = 1, @usu_id = @usu_id;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'A',
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @enc_id;

		UPDATE dbo.cont_asiento_enc
		   SET asi_estado = 'N',
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @enc_id;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- Cobros a clientes (abono a una cuota del plan de pagos)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_pos_registrar_pago_cuota]
	@cpp_id			INT,
	@valor_pago		NUMERIC(12, 2),
	@pca_id			INT,
	@usu_id			INT = NULL,
	@formas_pago	dbo.pago_forma_type READONLY = NULL,
	@ppe_id			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @valor_pago <= 0
		THROW 51501, 'El valor del pago debe ser mayor a cero.', 1;

	DECLARE @cli_id INT, @saldo NUMERIC(12, 2), @estado CHAR(1);
	SELECT @cli_id = cli_id, @saldo = cpp_saldo_cuota, @estado = cpp_estado
	FROM dbo.pos_cliente_plan_pagos WHERE cpp_id = @cpp_id;

	IF @cli_id IS NULL
		THROW 51502, 'La cuota indicada no existe.', 1;

	IF @estado = 'A'
		THROW 51503, 'La cuota indicada ya está abonada por completo.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.pos_pago_enc (cli_id, pca_id, usu_id, InsUsuario, InsFechaHora)
		VALUES (@cli_id, @pca_id, @usu_id, @usu_id, SYSDATETIME());

		SET @ppe_id = SCOPE_IDENTITY();

		INSERT INTO dbo.pos_pago_det (ppe_id, cpp_id, ppd_valor_aplicado, InsUsuario, InsFechaHora)
		VALUES (@ppe_id, @cpp_id, @valor_pago, @usu_id, SYSDATETIME());

		INSERT INTO dbo.pos_pago_forma
			(gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, ppe_id, pft_id, InsUsuario, InsFechaHora)
		SELECT gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, @ppe_id, pft_id, @usu_id, SYSDATETIME()
		FROM @formas_pago;

		UPDATE dbo.pos_cliente_plan_pagos
		   SET cpp_saldo_cuota = cpp_saldo_cuota - @valor_pago,
			   cpp_fecha_real_pago = CASE WHEN cpp_saldo_cuota - @valor_pago <= 0 THEN CAST(GETDATE() AS DATE) ELSE cpp_fecha_real_pago END,
			   cpp_estado = CASE WHEN cpp_saldo_cuota - @valor_pago <= 0 THEN 'A' ELSE cpp_estado END,
			   UpdUsuario = @usu_id,
			   UpdFechaHora = SYSDATETIME()
		 WHERE cpp_id = @cpp_id;

		DECLARE @pdo_id INT, @asi_id INT, @detalle dbo.cont_asiento_det_type, @fecha_hoy DATE = CAST(GETDATE() AS DATE);
		EXEC dbo.sp_contabilidad_obtener_o_crear_periodo @fecha = NULL, @usu_id = @usu_id, @pdo_id = @pdo_id OUTPUT;

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, @valor_pago, 0, 'Cobro cuota ' + CAST(@cpp_id AS VARCHAR(10)) FROM dbo.cont_cuenta_contable WHERE cta_codigo = '1105'
		UNION ALL
		SELECT cta_id, 0, @valor_pago, 'Cobro cuota ' + CAST(@cpp_id AS VARCHAR(10)) FROM dbo.cont_cuenta_contable WHERE cta_codigo = '1205';

		-- EXEC no acepta una expresión directamente como valor de un
		-- parámetro con nombre; @fecha_hoy ya se calculó arriba.
		EXEC dbo.sp_contabilidad_insertar_asiento
			@asi_fecha = @fecha_hoy, @asi_descripcion = 'Cobro cuota de cliente',
			@asi_origen = 'PAGO_CLIENTE', @usu_id = @usu_id, @detalle = @detalle, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- Pagos a proveedores mediante cheque
------------------------------------------------------------
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

	IF @estado = 'A'
		THROW 51603, 'La cuota de proveedor indicada ya está pagada por completo.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.bco_cheque_emitido_enc
			(cbc_id, bce_fecha_emision, usu_id, bce_numero_cheque, bce_documento_ref, bce_valor, bmp_id,
			 InsUsuario, InsFechaHora)
		VALUES
			(@cbc_id, CAST(GETDATE() AS DATE), @usu_id, @bce_numero_cheque, CAST(@enc_id AS VARCHAR(16)), @valor_pago, @bmp_id,
			 @usu_id, SYSDATETIME());

		SET @bce_id = SCOPE_IDENTITY();

		INSERT INTO dbo.bco_cheque_emitido_det (bce_id, bmp_id, enc_id, ced_valor, ced_abono_cancelacion, InsUsuario, InsFechaHora)
		VALUES (@bce_id, @bmp_id, @enc_id, @valor_pago,
				CASE WHEN @valor_pagado + @valor_pago >= @valor_programado THEN 'C' ELSE 'A' END,
				@usu_id, SYSDATETIME());

		UPDATE dbo.inv_proveedor_plan_pago
		   SET ppg_valor_real_pago = @valor_pagado + @valor_pago,
			   ppg_fecha_real_pago = CAST(GETDATE() AS DATE),
			   ppg_numero_cheque = @bce_numero_cheque,
			   ppg_estado = CASE WHEN @valor_pagado + @valor_pago >= @valor_programado THEN 'A' ELSE ppg_estado END,
			   UpdUsuario = @usu_id,
			   UpdFechaHora = SYSDATETIME()
		 WHERE ppg_id = @ppg_id;

		DECLARE @pdo_id INT, @asi_id INT, @detalle dbo.cont_asiento_det_type, @fecha_hoy DATE = CAST(GETDATE() AS DATE);
		EXEC dbo.sp_contabilidad_obtener_o_crear_periodo @fecha = NULL, @usu_id = @usu_id, @pdo_id = @pdo_id OUTPUT;

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, @valor_pago, 0, 'Pago a proveedor - cheque ' + @bce_numero_cheque FROM dbo.cont_cuenta_contable WHERE cta_codigo = '2105'
		UNION ALL
		SELECT cta_id, 0, @valor_pago, 'Pago a proveedor - cheque ' + @bce_numero_cheque FROM dbo.cont_cuenta_contable WHERE cta_codigo = '1110';

		-- EXEC no acepta una expresión directamente como valor de un
		-- parámetro con nombre; se calculan antes en variables.
		DECLARE @asi_descripcion VARCHAR(256) = 'Pago a proveedor con cheque ' + @bce_numero_cheque;

		EXEC dbo.sp_contabilidad_insertar_asiento
			@asi_fecha = @fecha_hoy, @asi_descripcion = @asi_descripcion,
			@asi_origen = 'PAGO_PROVEEDOR', @enc_id = @enc_id, @pdo_id = @pdo_id, @usu_id = @usu_id,
			@detalle = @detalle, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- Punto de venta: apertura y cierre de caja
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_pos_caja_abrir]
	@pcr_id			INT,
	@usu_id			INT,
	@pca_id			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pcr_id = @pcr_id AND pca_estado = 'A')
		THROW 51701, 'Ya existe una apertura de caja activa para esta caja receptora.', 1;

	INSERT INTO dbo.pos_caja_apertura (pcr_id, usu_id_apertura, InsUsuario, InsFechaHora)
	VALUES (@pcr_id, @usu_id, @usu_id, SYSDATETIME());

	SET @pca_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_pos_caja_cerrar]
	@pca_id	INT,
	@usu_id	INT
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id AND pca_estado = 'A')
		THROW 51702, 'La apertura de caja indicada no existe o ya está cerrada.', 1;

	UPDATE dbo.pos_caja_apertura
	   SET pca_estado = 'C', pca_fecha_cierre = SYSDATETIME(), usu_id_cierre = @usu_id,
		   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
	 WHERE pca_id = @pca_id;
END;
GO

------------------------------------------------------------
-- Seguridad: inicio de sesión
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_seguridad_login]
	@usu_usuario	VARCHAR(128),
	@usu_password	VARCHAR(256)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @usu_id INT, @hash VARBINARY(64), @salt UNIQUEIDENTIFIER, @intentos INT, @bloqueado BIT, @estado CHAR(1);

	SELECT @usu_id = usu_id, @hash = usu_password_hash, @salt = usu_password_salt,
		   @intentos = usu_intentos_fallidos, @bloqueado = usu_bloqueado, @estado = usu_estado
	FROM dbo.gen_usuario
	WHERE usu_usuario = @usu_usuario;

	IF @usu_id IS NULL
	BEGIN
		SELECT 'error' AS estado, 'Usuario o contraseña no son válidos.' AS mensaje;
		RETURN;
	END

	IF @estado = 'I' OR @bloqueado = 1
	BEGIN
		SELECT 'error' AS estado, 'El usuario está inactivo o bloqueado. Contacte al administrador.' AS mensaje;
		RETURN;
	END

	-- Es el propio usuario quien produce el cambio (éxito o intento fallido):
	-- UpdUsuario queda como el mismo @usu_id encontrado arriba.
	IF HASHBYTES('SHA2_256', CAST(@salt AS VARCHAR(36)) + @usu_password) = @hash
	BEGIN
		UPDATE dbo.gen_usuario
		   SET usu_intentos_fallidos = 0, usu_ultimo_login = SYSDATETIME(),
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE usu_id = @usu_id;

		SELECT 'success' AS estado, 'Bienvenido, ' + @usu_usuario + '.' AS mensaje, @usu_id AS usu_id;
	END
	ELSE
	BEGIN
		UPDATE dbo.gen_usuario
		   SET usu_intentos_fallidos = usu_intentos_fallidos + 1,
			   usu_bloqueado = CASE WHEN usu_intentos_fallidos + 1 >= 5 THEN 1 ELSE 0 END,
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE usu_id = @usu_id;

		SELECT 'error' AS estado, 'Usuario o contraseña no son válidos.' AS mensaje;
	END
END;
GO
