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
	   documento que se está grabando (paInventarioExistenciaDocumentoAjustar).
	   El recálculo completo se conserva como
	   paInventarioExistenciaRecalcular, para usarse solo como
	   utilidad de reconciliación/mantenimiento.

	4) SPR_LOGIN_USUARIO comparaba la contraseña en texto plano. Aquí se
	   compara el hash (ver paUsuarioInsertar/paUsuarioPasswordCambiar
	   en 10_procedimientos_crud.sql) y se bloquea el usuario tras varios
	   intentos fallidos.

	5) No existía ningún procedimiento para anular un documento ya grabado.
	   Se agrega paDocumentoAnular.

	Auditoría: igual que en 10_procedimientos_crud.sql, todo procedimiento que
	inserta o actualiza una fila recibe (o ya recibía, para su propio uso de
	negocio: p.ej. inv_documento_enc.usu_id_creacion) un parámetro @usu_id y
	lo graba en InsUsuario/UpdUsuario junto con InsFechaHora/UpdFechaHora =
	SYSDATETIME(). Los procedimientos internos que antes no necesitaban saber
	quién ejecuta la acción (paInventarioExistenciaDocumentoAjustar,
	paInventarioExistenciaRecalcular,
	paClientePlanPagosGenerar, paProveedorPlanPagosGenerar,
	paContabilidadPeriodoObtenerOCrear) ahora reciben @usu_id también,
	y los procedimientos de más arriba en la cadena de llamadas
	(paVentaFacturaCrear, paCompraDocumentoCrear, paDocumentoAnular,
	paClienteCuotaPagoRegistrar, paBancoChequePagoProveedorEmitir) se lo
	pasan hacia abajo.
*/
USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- Inventario: ajuste incremental y recálculo completo
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paInventarioExistenciaDocumentoAjustar]
	@EncId		INT,
	@Reversar	BIT = 0,	-- 1 = revertir el efecto (usado al anular un documento)
	@UsuId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @naturaleza_signo INT, @reversar_signo INT = CASE WHEN @Reversar = 1 THEN -1 ELSE 1 END;

	SELECT @naturaleza_signo = CASE WHEN tipo.tdo_naturaleza = '+' THEN 1 ELSE -1 END
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @EncId;

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
		deta.pro_id,
		deta.bod_id,
		SUM(deta.det_cantidad) * @naturaleza_signo * @reversar_signo,
		SUM(deta.det_cantidad *
			CASE WHEN @naturaleza_signo = 1
				 THEN deta.det_sub_total / NULLIF(deta.det_cantidad, 0)
				 ELSE prod.pro_costo_unitario
			END
		) * @naturaleza_signo * @reversar_signo
	FROM dbo.inv_documento_det deta
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
	WHERE deta.enc_id = @EncId
	  AND deta.pro_id IS NOT NULL
	  AND prod.pro_maneja_existencia = 1
	GROUP BY deta.pro_id, deta.bod_id;

	MERGE dbo.inv_producto_existencia_bodega AS destino
	USING @movimientos AS origen
		ON destino.pro_id = origen.pro_id AND destino.bod_id = origen.bod_id
	WHEN MATCHED THEN
		UPDATE SET existencia = destino.existencia + origen.cantidad,
				   UpdUsuario = @UsuId,
				   UpdFechaHora = SYSDATETIME()
	WHEN NOT MATCHED THEN
		INSERT (bod_id, pro_id, existencia, InsUsuario, InsFechaHora)
		VALUES (origen.bod_id, origen.pro_id, origen.cantidad, @UsuId, SYSDATETIME());

	;WITH totales AS (
		SELECT pro_id, SUM(cantidad) AS cantidad, SUM(costo) AS costo
		FROM @movimientos
		GROUP BY pro_id
	)
	UPDATE prod2
	   SET prod2.pro_total_cantidad = prod2.pro_total_cantidad + tota.cantidad,
		   prod2.pro_total_costo   = prod2.pro_total_costo + tota.costo,
		   prod2.pro_costo_unitario = CASE WHEN prod2.pro_total_cantidad + tota.cantidad > 0
										THEN (prod2.pro_total_costo + tota.costo) / (prod2.pro_total_cantidad + tota.cantidad)
										ELSE 0 END,
		   prod2.UpdUsuario = @UsuId,
		   prod2.UpdFechaHora = SYSDATETIME()
	FROM dbo.inv_producto prod2
	INNER JOIN totales tota ON tota.pro_id = prod2.pro_id;
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
CREATE OR ALTER PROCEDURE [dbo].[paInventarioExistenciaRecalcular]
	@UsuId INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	UPDATE dbo.inv_producto
	   SET pro_total_cantidad = 0, pro_total_costo = 0, pro_costo_unitario = 0,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE pro_maneja_existencia = 1;

	UPDATE exis
	   SET existencia = 0,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	FROM dbo.inv_producto_existencia_bodega exis
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = exis.pro_id
	WHERE prod.pro_maneja_existencia = 1;

	DECLARE @enc_id INT;

	DECLARE c1 CURSOR LOCAL FAST_FORWARD FOR
		SELECT enca.enc_id
		FROM dbo.inv_documento_enc enca
		WHERE enca.enc_estado = 'G'
		ORDER BY enca.enc_fecha_docto, enca.enc_id;

	OPEN c1;
	FETCH NEXT FROM c1 INTO @enc_id;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		EXEC dbo.paInventarioExistenciaDocumentoAjustar @EncId = @enc_id, @Reversar = 0, @UsuId = @UsuId;
		FETCH NEXT FROM c1 INTO @enc_id;
	END
	CLOSE c1;
	DEALLOCATE c1;
END;
GO

------------------------------------------------------------
-- Planes de pago (cuotas)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paClientePlanPagosGenerar]
	@EncId	INT,
	@UsuId	INT = NULL
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
	WHERE enc_id = @EncId;

	-- enc_monto_total ya viene neto de descuento (ver paVentaFacturaCrear),
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
				(@contador, @fecha_iteracion, @valor_cuota, @valor_cuota, @EncId, @cli_id, 'P',
				 @UsuId, SYSDATETIME());

			SET @contador = @contador + 1;
			SET @fecha_iteracion = DATEADD(MONTH, 1, @fecha_iteracion);
			IF DATEPART(dw, @fecha_iteracion) = 7
				SET @fecha_iteracion = DATEADD(DAY, 1, @fecha_iteracion);
		END

		-- Ajusta la última cuota para que la suma cuadre exactamente con el monto financiado.
		DECLARE @monto_cuotas NUMERIC(12, 2), @monto_restante NUMERIC(12, 2);

		SELECT @monto_cuotas = SUM(cpp_valor_cuota) FROM dbo.pos_cliente_plan_pagos WHERE enc_id = @EncId;
		SET @monto_restante = (ISNULL(@monto_total, 0) - ISNULL(@monto_enganche, 0)) - ISNULL(@monto_cuotas, 0);

		IF @monto_restante <> 0
			UPDATE dbo.pos_cliente_plan_pagos
			   SET cpp_valor_cuota = cpp_valor_cuota + @monto_restante,
				   cpp_saldo_cuota = cpp_saldo_cuota + @monto_restante,
				   UpdUsuario = @UsuId,
				   UpdFechaHora = SYSDATETIME()
			 WHERE enc_id = @EncId
			   AND cpp_nro_cuota = (SELECT MAX(cpp_nro_cuota) FROM dbo.pos_cliente_plan_pagos WHERE enc_id = @EncId);
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProveedorPlanPagosGenerar]
	@EncId	INT,
	@UsuId	INT = NULL
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
	WHERE enc_id = @EncId;

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
				(@contador, @fecha_iteracion, @valor_cuota, @EncId, @prv_id, 'P',
				 @UsuId, SYSDATETIME());

			SET @contador = @contador + 1;
			SET @fecha_iteracion = DATEADD(MONTH, 1, @fecha_iteracion);
			IF DATEPART(dw, @fecha_iteracion) = 7
				SET @fecha_iteracion = DATEADD(DAY, 1, @fecha_iteracion);
		END

		DECLARE @monto_cuotas NUMERIC(12, 2), @monto_restante NUMERIC(12, 2);

		SELECT @monto_cuotas = SUM(ppg_valor_pago) FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @EncId;
		SET @monto_restante = (ISNULL(@monto_total, 0) - ISNULL(@monto_enganche, 0)) - ISNULL(@monto_cuotas, 0);

		IF @monto_restante <> 0
			UPDATE dbo.inv_proveedor_plan_pago
			   SET ppg_valor_pago = ppg_valor_pago + @monto_restante,
				   UpdUsuario = @UsuId,
				   UpdFechaHora = SYSDATETIME()
			 WHERE enc_id = @EncId
			   AND ppg_nro_pago = (SELECT MAX(ppg_nro_pago) FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @EncId);
	END
END;
GO

------------------------------------------------------------
-- Contabilidad: inserción genérica de asientos y generación automática
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paContabilidadPeriodoObtenerOCrear]
	@Fecha	DATE = NULL,
	@UsuId	INT = NULL,
	@PdoId	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));
	DECLARE @anio INT = YEAR(@Fecha), @mes INT = MONTH(@Fecha);

	SELECT @PdoId = pdo_id FROM dbo.cont_periodo_contable WHERE pdo_anio = @anio AND pdo_mes = @mes;

	IF @PdoId IS NULL
	BEGIN
		INSERT INTO dbo.cont_periodo_contable (pdo_anio, pdo_mes, InsUsuario, InsFechaHora)
		VALUES (@anio, @mes, @UsuId, SYSDATETIME());
		SET @PdoId = SCOPE_IDENTITY();
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paContabilidadAsientoInsertar]
	@AsiFecha			DATE,
	@AsiDescripcion	VARCHAR(256) = NULL,
	@AsiOrigen			VARCHAR(20) = 'MANUAL',
	@EncId				INT = NULL,
	@PdoId				INT = NULL,
	@UsuId				INT = NULL,
	@Detalle			dbo.cont_asiento_det_type READONLY,
	@AsiId				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 51301, 'El asiento debe tener al menos una línea.', 1;

	IF (SELECT ISNULL(SUM(asd_debe), 0) FROM @Detalle) <> (SELECT ISNULL(SUM(asd_haber), 0) FROM @Detalle)
		THROW 51302, 'El asiento no está balanceado: la suma del Debe debe ser igual a la suma del Haber.', 1;

	IF @PdoId IS NULL
		EXEC dbo.paContabilidadPeriodoObtenerOCrear @Fecha = @AsiFecha, @UsuId = @UsuId, @PdoId = @PdoId OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.cont_asiento_enc
			(asi_fecha, asi_descripcion, asi_origen, enc_id, pdo_id, usu_id, InsUsuario, InsFechaHora)
		VALUES
			(@AsiFecha, @AsiDescripcion, @AsiOrigen, @EncId, @PdoId, @UsuId, @UsuId, SYSDATETIME());

		SET @AsiId = SCOPE_IDENTITY();

		INSERT INTO dbo.cont_asiento_det (asi_id, cta_id, asd_debe, asd_haber, asd_descripcion, InsUsuario, InsFechaHora)
		SELECT @AsiId, cta_id, asd_debe, asd_haber, asd_descripcion, @UsuId, SYSDATETIME()
		FROM @Detalle;

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
	grabada. Cada línea toma la cuenta del concepto correspondiente en
	cont_cuenta_parametro (VENTA_*, COMPRA_*, INVENTARIO), así funciona con
	cualquier nomenclatura (27 reemplaza esta versión por una que además
	separa lo cobrado al facturar). Es una contabilización simplificada pensada para que el
	modelo sea funcional y fácil de adaptar; no reemplaza un motor fiscal
	certificado.
*/
CREATE OR ALTER PROCEDURE [dbo].[paContabilidadAsientoDocumentoGenerar]
	@EncId	INT,
	@UsuId	INT = NULL,
	@AsiId	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @tdo_naturaleza CHAR(1), @afecta_costo CHAR(1), @fecha DATE, @monto_total NUMERIC(12, 2), @origen VARCHAR(20);

	SELECT @tdo_naturaleza = tipo.tdo_naturaleza, @afecta_costo = tipo.afecta_costo,
		   @fecha = enca.enc_fecha_docto, @monto_total = enca.enc_monto_total,
		   @origen = CASE WHEN tipo.tdo_naturaleza = '+' THEN 'COMPRA' ELSE 'VENTA' END
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @EncId;

	IF @fecha IS NULL
		THROW 51303, 'El documento indicado no existe.', 1;

	-- El precio unitario se maneja sin impuesto incluido: el IVA se calcula
	-- sobre el subtotal neto de descuento y se sube aparte al total del
	-- documento (ver @monto_total en paVentaFacturaCrear / paCompraDocumentoCrear).
	DECLARE @iva NUMERIC(14, 2) =
		(SELECT ISNULL(SUM((det_sub_total - det_valor_descuento) * ISNULL(det_porc_iva, 0) / 100.0), 0) FROM dbo.inv_documento_det WHERE enc_id = @EncId);

	DECLARE @costo_venta NUMERIC(14, 2);
	SELECT @costo_venta = ISNULL(SUM(deta.det_cantidad * prod.pro_costo_unitario), 0)
	FROM dbo.inv_documento_det deta
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
	WHERE deta.enc_id = @EncId AND prod.pro_maneja_existencia = 1;

	DECLARE @pdo_id INT;
	EXEC dbo.paContabilidadPeriodoObtenerOCrear @Fecha = @fecha, @UsuId = @UsuId, @PdoId = @pdo_id OUTPUT;

	DECLARE @detalle dbo.cont_asiento_det_type;

	IF @tdo_naturaleza = '-' -- venta
	BEGIN
		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, @monto_total, 0, 'Cuentas por cobrar - documento ' + CAST(@EncId AS VARCHAR(10))
		FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'VENTA_CLIENTES'
		UNION ALL
		SELECT cta_id, 0, @monto_total - @iva, 'Venta - documento ' + CAST(@EncId AS VARCHAR(10))
		FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'VENTA_INGRESO';

		IF @iva > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			SELECT cta_id, 0, @iva, 'IVA débito fiscal - documento ' + CAST(@EncId AS VARCHAR(10))
			FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'VENTA_IVA_DEBITO';

		IF @costo_venta > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			SELECT cta_id, @costo_venta, 0, 'Costo de venta - documento ' + CAST(@EncId AS VARCHAR(10))
			FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'VENTA_COSTO'
			UNION ALL
			SELECT cta_id, 0, @costo_venta, 'Salida de inventario - documento ' + CAST(@EncId AS VARCHAR(10))
			FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'INVENTARIO';
	END
	ELSE -- compra
	BEGIN
		DECLARE @cuenta_destino VARCHAR(40) = CASE WHEN @afecta_costo = 'S' THEN 'INVENTARIO' ELSE 'COMPRA_GASTO' END;

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, @monto_total - @iva, 0, 'Compra - documento ' + CAST(@EncId AS VARCHAR(10))
		FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = @cuenta_destino;

		IF @iva > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			SELECT cta_id, @iva, 0, 'IVA crédito fiscal - documento ' + CAST(@EncId AS VARCHAR(10))
			FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'COMPRA_IVA_CREDITO';

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, 0, @monto_total, 'Cuentas por pagar - documento ' + CAST(@EncId AS VARCHAR(10))
		FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'COMPRA_PROVEEDORES';
	END

	-- EXEC no acepta una expresión (concatenación, CAST) directamente como
	-- valor de un parámetro con nombre; se calcula antes en una variable.
	DECLARE @asi_descripcion VARCHAR(256) = 'Generado automáticamente desde documento ' + CAST(@EncId AS VARCHAR(10));

	EXEC dbo.paContabilidadAsientoInsertar
		@AsiFecha = @fecha,
		@AsiDescripcion = @asi_descripcion,
		@AsiOrigen = @origen,
		@EncId = @EncId,
		@PdoId = @pdo_id,
		@UsuId = @UsuId,
		@Detalle = @detalle,
		@AsiId = @AsiId OUTPUT;
END;
GO

------------------------------------------------------------
-- Ventas y compras (encabezado + detalle + efectos colaterales)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paVentaFacturaCrear]
	@EncFechaDocto			DATE,
	@EncNumeroAutorizacion	VARCHAR(64) = NULL,
	@EncSerieDocto			VARCHAR(32) = NULL,
	@EncNumeroDocto			VARCHAR(32) = NULL,
	@CliId						INT,
	@EncNombresCliente		VARCHAR(128) = NULL,
	@EncApellidosCliente		VARCHAR(128) = NULL,
	@CliNit					VARCHAR(16) = NULL,
	@TdoId						INT,
	@PveId						INT = NULL,
	@EncFechaPrimerPago		DATE = NULL,
	@EncMontoEnganche			NUMERIC(12, 2) = 0,
	@EncNumeroCuotas			INT = 1,
	@EncValorDescuento		NUMERIC(13, 2) = 0,
	@EncDireccionCliente		VARCHAR(256) = NULL,
	@MonId						INT = NULL,
	@UsuId						INT = NULL,
	@Detalle					dbo.factura_det_type READONLY,
	@PcaId						INT = NULL,				-- apertura de caja activa donde se recibe el pago inicial
	@FormasPago				dbo.pago_forma_type READONLY,	-- pago de contado, o enganche si es a crédito; SQL Server no permite default en un TVP, pasar tabla vacía si no aplica
	@EncId						INT OUTPUT,
	@EncNumeroUnico			VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 51401, 'La factura debe tener al menos una línea de detalle.', 1;

	IF @MonId IS NULL
		SET @MonId = dbo.fnMonedaLocal();

	IF EXISTS (
		SELECT 1
		FROM @Detalle line
		INNER JOIN dbo.inv_producto prod ON prod.pro_id = line.pro_id
		LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = line.pro_id AND exis.bod_id = line.bod_id
		WHERE prod.pro_maneja_existencia = 1
		  AND ISNULL(exis.existencia, 0) < line.det_cantidad
	)
		THROW 51402, 'No hay existencia suficiente para uno o más productos del detalle.', 1;

	-- El monto total del documento es el neto (subtotal - descuento) más el
	-- IVA de cada línea; los precios unitarios se manejan sin impuesto
	-- incluido (ver también paContabilidadAsientoDocumentoGenerar).
	DECLARE @monto_total NUMERIC(12, 2) = (
		SELECT SUM((det_sub_total - det_valor_descuento) * (1 + ISNULL(det_porc_iva, 0) / 100.0))
		FROM @Detalle
	);

	BEGIN TRY
		BEGIN TRANSACTION;

		DECLARE @serie VARCHAR(32), @correlativo NUMERIC(12, 0);

		SELECT @serie = serie, @correlativo = correlativo + 1
		FROM dbo.conf_correlativos WITH (UPDLOCK, ROWLOCK)
		WHERE tdo_id = @TdoId;

		IF @serie IS NULL
			THROW 51403, 'No existe una serie de correlativos configurada para este tipo de documento.', 1;

		UPDATE dbo.conf_correlativos
		   SET correlativo = @correlativo,
			   UpdUsuario = @UsuId,
			   UpdFechaHora = SYSDATETIME()
		 WHERE tdo_id = @TdoId;

		SET @EncNumeroUnico = @serie + '-' + CAST(@correlativo AS VARCHAR(20));

		INSERT INTO dbo.inv_documento_enc
			(enc_fecha_docto, enc_numero_autorizacion, enc_serie_docto, enc_numero_docto,
			 cli_id, enc_nombres_cliente, enc_apellidos_cliente, cli_nit, tdo_id, pve_id,
			 enc_fecha_primer_pago, enc_monto_enganche, enc_numero_cuotas, enc_monto_total,
			 enc_valor_descuento, enc_direccion_cliente, mon_id, usu_id_creacion, enc_numero_unico,
			 InsUsuario, InsFechaHora)
		VALUES
			(@EncFechaDocto, @EncNumeroAutorizacion, @EncSerieDocto, @EncNumeroDocto,
			 @CliId, @EncNombresCliente, @EncApellidosCliente, @CliNit, @TdoId, @PveId,
			 @EncFechaPrimerPago, @EncMontoEnganche, @EncNumeroCuotas, @monto_total,
			 @EncValorDescuento, @EncDireccionCliente, @MonId, @UsuId, @EncNumeroUnico,
			 @UsuId, SYSDATETIME());

		SET @EncId = SCOPE_IDENTITY();

		INSERT INTO dbo.inv_documento_det
			(enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			 det_precio_unitario, det_valor_descuento, det_sub_total, det_costo_unitario, det_porc_iva, bod_id, pro_id, ppr_id,
			 InsUsuario, InsFechaHora)
		SELECT
			@EncId, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			det_precio_unitario, det_valor_descuento, det_sub_total, det_costo_unitario, det_porc_iva, bod_id, pro_id, ppr_id,
			@UsuId, SYSDATETIME()
		FROM @Detalle;

		IF @PcaId IS NOT NULL AND EXISTS (SELECT 1 FROM @FormasPago)
		BEGIN
			DECLARE @ppe_id INT;

			INSERT INTO dbo.pos_pago_enc (cli_id, pca_id, usu_id, InsUsuario, InsFechaHora)
			VALUES (@CliId, @PcaId, @UsuId, @UsuId, SYSDATETIME());

			SET @ppe_id = SCOPE_IDENTITY();

			INSERT INTO dbo.pos_pago_forma
				(gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, ppe_id, pft_id, InsUsuario, InsFechaHora)
			SELECT gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, @ppe_id, pft_id, @UsuId, SYSDATETIME()
			FROM @FormasPago;

			INSERT INTO dbo.pos_pago_det (ppe_id, enc_id, ppd_valor_aplicado, InsUsuario, InsFechaHora)
			SELECT @ppe_id, @EncId, SUM(ppf_monto), @UsuId, SYSDATETIME()
			FROM @FormasPago;
		END

		EXEC dbo.paClientePlanPagosGenerar @EncId = @EncId, @UsuId = @UsuId;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'G',
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId;

		EXEC dbo.paInventarioExistenciaDocumentoAjustar @EncId = @EncId, @UsuId = @UsuId;

		DECLARE @asi_id INT;
		EXEC dbo.paContabilidadAsientoDocumentoGenerar @EncId = @EncId, @UsuId = @UsuId, @AsiId = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompraDocumentoCrear]
	@EncFechaDocto				DATE,
	@EncNumeroAutorizacion		VARCHAR(64) = NULL,
	@EncSerieDocto				VARCHAR(32) = NULL,
	@EncNumeroDocto				VARCHAR(32) = NULL,
	@PrvId							INT,
	@PrvEncNombresProveedor		VARCHAR(128) = NULL,
	@PrvEncApellidosProveedor	VARCHAR(128) = NULL,
	@PrvNit						VARCHAR(16) = NULL,
	@TdoId							INT,
	@EncFechaPrimerPago			DATE = NULL,
	@EncMontoEnganche				NUMERIC(12, 2) = 0,
	@EncNumeroCuotas				INT = 1,
	@EncValorDescuento			NUMERIC(13, 2) = 0,
	@MonId							INT = NULL,
	@UsuId							INT = NULL,
	@Detalle						dbo.compra_det_type READONLY,
	@EncId							INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 51411, 'La compra debe tener al menos una línea de detalle.', 1;

	IF @MonId IS NULL
		SET @MonId = dbo.fnMonedaLocal();

	-- El monto total del documento es el neto (subtotal - descuento) más el
	-- IVA de cada línea; los precios unitarios se manejan sin impuesto
	-- incluido (ver también paContabilidadAsientoDocumentoGenerar).
	DECLARE @monto_total NUMERIC(12, 2) = (
		SELECT SUM((det_sub_total - det_valor_descuento) * (1 + ISNULL(det_porc_iva, 0) / 100.0))
		FROM @Detalle
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
			(@EncFechaDocto, @EncNumeroAutorizacion, @EncSerieDocto, @EncNumeroDocto,
			 @PrvId, @PrvEncNombresProveedor, @PrvEncApellidosProveedor, @PrvNit, @TdoId,
			 @EncFechaPrimerPago, @EncMontoEnganche, @EncNumeroCuotas, @monto_total,
			 @EncValorDescuento, @MonId, @UsuId,
			 @UsuId, SYSDATETIME());

		SET @EncId = SCOPE_IDENTITY();

		INSERT INTO dbo.inv_documento_det
			(enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			 det_precio_unitario, det_valor_descuento, det_sub_total, det_porc_iva, bod_id, pro_id,
			 InsUsuario, InsFechaHora)
		SELECT
			@EncId, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			det_precio_unitario, det_valor_descuento, det_sub_total, det_porc_iva, bod_id, pro_id,
			@UsuId, SYSDATETIME()
		FROM @Detalle;

		EXEC dbo.paProveedorPlanPagosGenerar @EncId = @EncId, @UsuId = @UsuId;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'G',
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId;

		EXEC dbo.paInventarioExistenciaDocumentoAjustar @EncId = @EncId, @UsuId = @UsuId;

		DECLARE @asi_id INT;
		EXEC dbo.paContabilidadAsientoDocumentoGenerar @EncId = @EncId, @UsuId = @UsuId, @AsiId = @asi_id OUTPUT;

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
CREATE OR ALTER PROCEDURE [dbo].[paDocumentoAnular]
	@EncId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado_actual CHAR(1);
	SELECT @estado_actual = enc_estado FROM dbo.inv_documento_enc WHERE enc_id = @EncId;

	IF @estado_actual IS NULL
		THROW 51421, 'El documento indicado no existe.', 1;

	IF @estado_actual <> 'G'
		THROW 51422, 'Solo se pueden anular documentos que estén en estado Grabado.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		EXEC dbo.paInventarioExistenciaDocumentoAjustar @EncId = @EncId, @Reversar = 1, @UsuId = @UsuId;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'A',
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId;

		UPDATE dbo.cont_asiento_enc
		   SET asi_estado = 'N',
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId;

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
CREATE OR ALTER PROCEDURE [dbo].[paClienteCuotaPagoRegistrar]
	@CppId			INT,
	@ValorPago		NUMERIC(12, 2),
	@PcaId			INT,
	@UsuId			INT = NULL,
	@FormasPago	dbo.pago_forma_type READONLY,	-- SQL Server no permite default en un TVP, pasar tabla vacía si no aplica
	@PpeId			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @ValorPago <= 0
		THROW 51501, 'El valor del pago debe ser mayor a cero.', 1;

	DECLARE @cli_id INT, @saldo NUMERIC(12, 2), @estado CHAR(1);
	SELECT @cli_id = cli_id, @saldo = cpp_saldo_cuota, @estado = cpp_estado
	FROM dbo.pos_cliente_plan_pagos WHERE cpp_id = @CppId;

	IF @cli_id IS NULL
		THROW 51502, 'La cuota indicada no existe.', 1;

	IF @estado = 'A'
		THROW 51503, 'La cuota indicada ya está abonada por completo.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.pos_pago_enc (cli_id, pca_id, usu_id, InsUsuario, InsFechaHora)
		VALUES (@cli_id, @PcaId, @UsuId, @UsuId, SYSDATETIME());

		SET @PpeId = SCOPE_IDENTITY();

		INSERT INTO dbo.pos_pago_det (ppe_id, cpp_id, ppd_valor_aplicado, InsUsuario, InsFechaHora)
		VALUES (@PpeId, @CppId, @ValorPago, @UsuId, SYSDATETIME());

		INSERT INTO dbo.pos_pago_forma
			(gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, ppe_id, pft_id, InsUsuario, InsFechaHora)
		SELECT gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, @PpeId, pft_id, @UsuId, SYSDATETIME()
		FROM @FormasPago;

		UPDATE dbo.pos_cliente_plan_pagos
		   SET cpp_saldo_cuota = cpp_saldo_cuota - @ValorPago,
			   cpp_fecha_real_pago = CASE WHEN cpp_saldo_cuota - @ValorPago <= 0 THEN CAST(GETDATE() AS DATE) ELSE cpp_fecha_real_pago END,
			   cpp_estado = CASE WHEN cpp_saldo_cuota - @ValorPago <= 0 THEN 'A' ELSE cpp_estado END,
			   UpdUsuario = @UsuId,
			   UpdFechaHora = SYSDATETIME()
		 WHERE cpp_id = @CppId;

		DECLARE @pdo_id INT, @asi_id INT, @detalle dbo.cont_asiento_det_type, @fecha_hoy DATE = CAST(GETDATE() AS DATE);
		EXEC dbo.paContabilidadPeriodoObtenerOCrear @Fecha = NULL, @UsuId = @UsuId, @PdoId = @pdo_id OUTPUT;

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, @ValorPago, 0, 'Cobro cuota ' + CAST(@CppId AS VARCHAR(10)) FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'COBRO_CAJA'
		UNION ALL
		SELECT cta_id, 0, @ValorPago, 'Cobro cuota ' + CAST(@CppId AS VARCHAR(10)) FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'COBRO_CLIENTES';

		-- EXEC no acepta una expresión directamente como valor de un
		-- parámetro con nombre; @fecha_hoy ya se calculó arriba.
		EXEC dbo.paContabilidadAsientoInsertar
			@AsiFecha = @fecha_hoy, @AsiDescripcion = 'Cobro cuota de cliente',
			@AsiOrigen = 'PAGO_CLIENTE', @UsuId = @UsuId, @Detalle = @detalle, @AsiId = @asi_id OUTPUT;

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
CREATE OR ALTER PROCEDURE [dbo].[paBancoChequePagoProveedorEmitir]
	@PpgId				INT,
	@CbcId				INT,
	@BceNumeroCheque	VARCHAR(16),
	@ValorPago			NUMERIC(12, 2),
	@BmpId				INT = NULL,
	@UsuId				INT = NULL,
	@BceId				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @ValorPago <= 0
		THROW 51601, 'El valor del pago debe ser mayor a cero.', 1;

	DECLARE @enc_id INT, @valor_programado NUMERIC(12, 2), @valor_pagado NUMERIC(12, 2), @estado CHAR(1);
	SELECT @enc_id = enc_id, @valor_programado = ppg_valor_pago, @valor_pagado = ISNULL(ppg_valor_real_pago, 0), @estado = ppg_estado
	FROM dbo.inv_proveedor_plan_pago WHERE ppg_id = @PpgId;

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
			(@CbcId, CAST(GETDATE() AS DATE), @UsuId, @BceNumeroCheque, CAST(@enc_id AS VARCHAR(16)), @ValorPago, @BmpId,
			 @UsuId, SYSDATETIME());

		SET @BceId = SCOPE_IDENTITY();

		INSERT INTO dbo.bco_cheque_emitido_det (bce_id, bmp_id, enc_id, ced_valor, ced_abono_cancelacion, InsUsuario, InsFechaHora)
		VALUES (@BceId, @BmpId, @enc_id, @ValorPago,
				CASE WHEN @valor_pagado + @ValorPago >= @valor_programado THEN 'C' ELSE 'A' END,
				@UsuId, SYSDATETIME());

		UPDATE dbo.inv_proveedor_plan_pago
		   SET ppg_valor_real_pago = @valor_pagado + @ValorPago,
			   ppg_fecha_real_pago = CAST(GETDATE() AS DATE),
			   ppg_numero_cheque = @BceNumeroCheque,
			   ppg_estado = CASE WHEN @valor_pagado + @ValorPago >= @valor_programado THEN 'A' ELSE ppg_estado END,
			   UpdUsuario = @UsuId,
			   UpdFechaHora = SYSDATETIME()
		 WHERE ppg_id = @PpgId;

		DECLARE @pdo_id INT, @asi_id INT, @detalle dbo.cont_asiento_det_type, @fecha_hoy DATE = CAST(GETDATE() AS DATE);
		EXEC dbo.paContabilidadPeriodoObtenerOCrear @Fecha = NULL, @UsuId = @UsuId, @PdoId = @pdo_id OUTPUT;

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, @ValorPago, 0, 'Pago a proveedor - cheque ' + @BceNumeroCheque FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'PAGO_PROVEEDORES'
		UNION ALL
		SELECT cta_id, 0, @ValorPago, 'Pago a proveedor - cheque ' + @BceNumeroCheque FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'PAGO_BANCOS';

		-- EXEC no acepta una expresión directamente como valor de un
		-- parámetro con nombre; se calculan antes en variables.
		DECLARE @asi_descripcion VARCHAR(256) = 'Pago a proveedor con cheque ' + @BceNumeroCheque;

		EXEC dbo.paContabilidadAsientoInsertar
			@AsiFecha = @fecha_hoy, @AsiDescripcion = @asi_descripcion,
			@AsiOrigen = 'PAGO_PROVEEDOR', @EncId = @enc_id, @PdoId = @pdo_id, @UsuId = @UsuId,
			@Detalle = @detalle, @AsiId = @asi_id OUTPUT;

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
CREATE OR ALTER PROCEDURE [dbo].[paCajaAbrir]
	@PcrId			INT,
	@UsuId			INT,
	@PcaId			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pcr_id = @PcrId AND pca_estado = 'A')
		THROW 51701, 'Ya existe una apertura de caja activa para esta caja receptora.', 1;

	INSERT INTO dbo.pos_caja_apertura (pcr_id, usu_id_apertura, InsUsuario, InsFechaHora)
	VALUES (@PcrId, @UsuId, @UsuId, SYSDATETIME());

	SET @PcaId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaCerrar]
	@PcaId	INT,
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @PcaId AND pca_estado = 'A')
		THROW 51702, 'La apertura de caja indicada no existe o ya está cerrada.', 1;

	UPDATE dbo.pos_caja_apertura
	   SET pca_estado = 'C', pca_fecha_cierre = SYSDATETIME(), usu_id_cierre = @UsuId,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE pca_id = @PcaId;
END;
GO

------------------------------------------------------------
-- Seguridad: inicio de sesión
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paSeguridadLogin]
	@UsuUsuario	VARCHAR(128),
	@UsuPassword	VARCHAR(256)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @usu_id INT, @hash VARBINARY(64), @salt UNIQUEIDENTIFIER, @intentos INT, @bloqueado BIT, @estado CHAR(1);

	SELECT @usu_id = usu_id, @hash = usu_password_hash, @salt = usu_password_salt,
		   @intentos = usu_intentos_fallidos, @bloqueado = usu_bloqueado, @estado = usu_estado
	FROM dbo.gen_usuario
	WHERE usu_usuario = @UsuUsuario;

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
	IF HASHBYTES('SHA2_256', CAST(@salt AS VARCHAR(36)) + @UsuPassword) = @hash
	BEGIN
		UPDATE dbo.gen_usuario
		   SET usu_intentos_fallidos = 0, usu_ultimo_login = SYSDATETIME(),
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE usu_id = @usu_id;

		SELECT 'success' AS estado, 'Bienvenido, ' + @UsuUsuario + '.' AS mensaje, @usu_id AS usu_id;
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
