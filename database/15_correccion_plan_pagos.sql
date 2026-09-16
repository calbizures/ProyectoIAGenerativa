------------------------------------------------------------------------------
-- 15_correccion_plan_pagos.sql
--
-- Corrige una inconsistencia en el cálculo del valor de cada cuota de los
-- planes de pago generados automáticamente al grabar una factura o una
-- compra a crédito:
--
--   * sp_pos_generar_plan_pagos_cliente (Ventas): enc_monto_total ya viene
--     neto de descuento (ver sp_ventas_crear_factura), pero el procedimiento
--     volvía a restar el descuento antes de dividir entre cuotas, dejando el
--     monto financiado por debajo del real.
--
--   * sp_inv_generar_plan_pagos_proveedor (Compras): el enganche se captura
--     y se guarda en enc_monto_enganche, pero nunca se restaba del monto
--     total antes de dividir entre cuotas, así que el enganche no reducía
--     las cuotas del proveedor.
--
-- Ambos procedimientos quedan con la misma fórmula:
--   valor_cuota = (monto_total - monto_enganche) / número_cuotas
--
-- Seguro de correr una sola vez contra una base ya creada con 00-14; usa
-- CREATE OR ALTER y no toca datos existentes (los planes de pago ya
-- generados no se recalculan).
------------------------------------------------------------------------------

USE [erp_db];
GO

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
