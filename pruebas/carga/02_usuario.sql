-- 02_usuario.sql — un usuario de la prueba de carga (se corre 10 veces en paralelo). Variables: $(CORRIDA), $(U) (1..10), $(N) operaciones.
--   1-4  vendedor: facturas a crédito con los mismos 5 productos (compiten por existencia y correlativo)
--   5-6  cajero: facturas de contado en efectivo (caja 1 y caja 2)
--   7-8  cobrador: cobros de cuotas tomadas del mismo grupo (compiten por la misma cuota)
--   9    compras: compras de los mismos 5 productos (suben la existencia que bajan los vendedores)
--   10   contador: balanza, libro diario, antigüedad de saldos, tablero de ventas y existencias
USE erp_db;
SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @u INT = $(U), @n INT = $(N), @corrida VARCHAR(20) = '$(CORRIDA)';
DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = CONCAT('prueba', RIGHT(CONCAT('0', @u), 2)));
DECLARE @rol VARCHAR(20) = CASE WHEN @u <= 4 THEN 'vendedor' WHEN @u <= 6 THEN 'cajero' WHEN @u <= 8 THEN 'cobrador' WHEN @u = 9 THEN 'compras' ELSE 'contador' END;
DECLARE @pca INT = (SELECT TOP 1 pca_id FROM dbo.pos_caja_apertura WHERE pca_estado = 'A' AND pcr_id = CASE WHEN @u IN (5, 7) THEN 1 ELSE 2 END);
DECLARE @tdo_fcam INT = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo = 'FCAM');
DECLARE @tdo_comp INT = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo = 'COMP');
DECLARE @bod INT = (SELECT bod_id FROM dbo.inv_bodega WHERE bod_codigo = 'BOD01');
DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
DECLARE @k INT = 1, @t0 DATETIME2(3), @op VARCHAR(40), @enc INT, @num VARCHAR(16), @ppe INT, @total NUMERIC(12, 2);
DECLARE @det dbo.factura_det_type, @detc dbo.compra_det_type, @formas dbo.pago_forma_type, @activos dbo.compra_activo_type;
DECLARE @hot TABLE (n INT IDENTITY, pro_id INT, precio NUMERIC(12, 2));
INSERT INTO @hot (pro_id, precio)
SELECT TOP 5 prod.pro_id, 100 + prod.pro_id FROM dbo.inv_producto prod
INNER JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = prod.pro_id AND exis.bod_id = @bod
WHERE prod.pro_maneja_existencia = 1 ORDER BY exis.existencia DESC, prod.pro_id;

WHILE @k <= @n
BEGIN
	DELETE FROM @det; DELETE FROM @detc; DELETE FROM @formas;
	SET @enc = NULL; SET @op = NULL;
	SET @t0 = SYSDATETIME();
	BEGIN TRY
		IF @rol IN ('vendedor', 'cajero')
		BEGIN
			-- 1 a 3 líneas con productos distintos del grupo, 1 a 3 unidades cada una
			INSERT INTO @det (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total, det_porc_iva, bod_id, pro_id)
			SELECT ROW_NUMBER() OVER (ORDER BY h.n), 'B', q.cant, prod.pro_descripcion, h.precio, h.precio * q.cant, 12, @bod, h.pro_id
			FROM (SELECT TOP (1 + ABS(CHECKSUM(NEWID())) % 3) * FROM @hot ORDER BY NEWID()) h
			CROSS APPLY (SELECT 1 + ABS(CHECKSUM(NEWID())) % 3 AS cant) q
			INNER JOIN dbo.inv_producto prod ON prod.pro_id = h.pro_id;
			DECLARE @cli INT = (SELECT TOP 1 cli_id FROM dbo.pos_cliente WHERE cli_estado = 'A' ORDER BY NEWID());
			DECLARE @pve INT = (SELECT TOP 1 pve_id FROM dbo.pos_vendedor ORDER BY NEWID());
			IF @rol = 'vendedor'
			BEGIN
				SET @op = 'factura_credito';
				DECLARE @cuotas INT = 1 + ABS(CHECKSUM(NEWID())) % 3, @primer DATE = DATEADD(MONTH, 1, @hoy);
				EXEC dbo.paVentaFacturaCrear @EncFechaDocto = @hoy, @CliId = @cli, @TdoId = @tdo_fcam, @PveId = @pve,
					@EncFechaPrimerPago = @primer, @EncNumeroCuotas = @cuotas, @UsuId = @usu,
					@Detalle = @det, @FormasPago = @formas, @EncId = @enc OUTPUT, @EncNumeroUnico = @num OUTPUT;
			END
			ELSE
			BEGIN
				SET @op = 'factura_contado';
				SET @total = (SELECT SUM(ROUND(det_sub_total * (1 + det_porc_iva / 100), 2)) FROM @det);
				INSERT INTO @formas (pft_id, ppf_monto) VALUES (1, @total);
				EXEC dbo.paVentaFacturaCrear @EncFechaDocto = @hoy, @CliId = @cli, @TdoId = @tdo_fcam, @PveId = @pve,
					@EncNumeroCuotas = 1, @UsuId = @usu, @PcaId = @pca,
					@Detalle = @det, @FormasPago = @formas, @EncId = @enc OUTPUT, @EncNumeroUnico = @num OUTPUT;
			END
		END
		ELSE IF @rol = 'cobrador'
		BEGIN
			-- Los dos cobradores toman cuotas del mismo grupo (las 15 pendientes más antiguas):
			-- es frecuente que intenten cobrar la misma cuota a la vez.
			SET @op = 'cobro_cuota';
			DECLARE @cpp INT, @saldo NUMERIC(12, 2);
			SELECT TOP 1 @cpp = cpp_id, @saldo = cpp_saldo_cuota
			FROM (SELECT TOP 15 cuot.cpp_id, cuot.cpp_saldo_cuota
				  FROM dbo.pos_cliente_plan_pagos cuot
				  INNER JOIN dbo.inv_documento_enc enca ON enca.enc_id = cuot.enc_id AND enca.enc_estado = 'G'
				  WHERE cuot.cpp_estado = 'P' AND cuot.cpp_saldo_cuota > 0 ORDER BY cuot.cpp_id) c
			ORDER BY NEWID();
			IF @cpp IS NULL
				SET @op = 'cobro_sin_cuotas';
			ELSE
			BEGIN
				-- abono parcial (la mitad) o pago completo
				DECLARE @valor NUMERIC(12, 2) = CASE WHEN ABS(CHECKSUM(NEWID())) % 2 = 0 THEN @saldo ELSE ROUND(@saldo / 2, 2) END;
				EXEC dbo.paClienteCuotaPagoRegistrar @CppId = @cpp, @ValorPago = @valor, @PcaId = @pca, @UsuId = @usu,
					@FormasPago = @formas, @PpeId = @ppe OUTPUT;
			END
		END
		ELSE IF @rol = 'compras'
		BEGIN
			SET @op = 'compra';
			INSERT INTO @detc (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total, det_porc_iva, bod_id, pro_id)
			SELECT h.n, 'B', 5, prod.pro_descripcion, ROUND(h.precio * 0.6, 2), ROUND(h.precio * 0.6, 2) * 5, 12, @bod, h.pro_id
			FROM @hot h INNER JOIN dbo.inv_producto prod ON prod.pro_id = h.pro_id;
			DECLARE @prv INT = (SELECT TOP 1 prv_id FROM dbo.inv_proveedor ORDER BY NEWID());
			DECLARE @numc VARCHAR(32) = CONCAT('PC-', @corrida, '-', @k), @pp DATE = DATEADD(MONTH, 1, @hoy);
			EXEC dbo.paCompraDocumentoCrear @EncFechaDocto = @hoy, @EncNumeroDocto = @numc, @PrvId = @prv, @TdoId = @tdo_comp,
				@EncFechaPrimerPago = @pp, @EncNumeroCuotas = 1, @UsuId = @usu, @Detalle = @detc, @EncId = @enc OUTPUT, @Activos = @activos;
		END
		ELSE
		BEGIN
			DECLARE @desde DATE = DATEFROMPARTS(YEAR(@hoy), 1, 1);
			DECLARE @r INT = @k % 5;
			SET @op = CHOOSE(@r + 1, 'balanza', 'libro_diario', 'antiguedad_cxc', 'tablero_ventas', 'existencias');
			IF @r = 0 EXEC dbo.paBalanzaComprobacionConsultar @Desde = @desde, @Hasta = @hoy, @Nivel = 5;
			IF @r = 1 EXEC dbo.paLibroDiarioConsultar @Desde = @desde, @Hasta = @hoy;
			IF @r = 2 EXEC dbo.paCxcAntiguedadConsultar @FechaCorte = @hoy, @CliId = NULL, @UsuId = 1;
			IF @r = 3 EXEC dbo.paTableroVentas @Desde = @desde, @Hasta = @hoy, @SucId = NULL;
			IF @r = 4 EXEC dbo.paProductoExistenciaConsultar @pro_id = NULL, @bod_id = NULL;
		END
		INSERT INTO prueba_carga.dbo.resultado (corrida, usuario, rol, operacion, inicio, ms, ok, enc_id)
		VALUES (@corrida, @u, @rol, @op, @t0, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()), 1, @enc);
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;
		INSERT INTO prueba_carga.dbo.resultado (corrida, usuario, rol, operacion, inicio, ms, ok, error_num, error_msg)
		VALUES (@corrida, @u, @rol, ISNULL(@op, '?'), @t0, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()), 0, ERROR_NUMBER(), LEFT(ERROR_MESSAGE(), 400));
	END CATCH
	SET @k += 1;
END
