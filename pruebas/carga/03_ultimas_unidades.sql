-- 03_ultimas_unidades.sql — sobreventa: los 10 usuarios intentan vender a la vez $(CANT) unidades del producto $(PRO) en la bodega 1.
USE erp_db; SET NOCOUNT ON;
DECLARE @u INT = $(U), @t0 DATETIME2(3) = SYSDATETIME(), @enc INT, @num VARCHAR(16);
DECLARE @usu INT = (SELECT usu_id FROM gen_usuario WHERE usu_usuario = CONCAT('prueba', RIGHT(CONCAT('0', @u), 2)));
DECLARE @det factura_det_type, @formas pago_forma_type, @hoy DATE = CAST(GETDATE() AS DATE), @primer DATE = DATEADD(MONTH, 1, CAST(GETDATE() AS DATE));
DECLARE @tdo INT = (SELECT tdo_id FROM inv_documento_tipo WHERE tdo_codigo = 'FCAM');
DECLARE @cli INT = (SELECT cli_id FROM pos_cliente WHERE cli_id = 1 + (@u % 20));
INSERT INTO @det (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total, det_porc_iva, bod_id, pro_id)
SELECT 1, 'B', $(CANT), pro_descripcion, 10, 10 * $(CANT), 12, 1, pro_id FROM inv_producto WHERE pro_id = $(PRO);
-- todos esperan al mismo segundo para arrancar
WAITFOR TIME '$(HORA)';
SET @t0 = SYSDATETIME();
BEGIN TRY
	EXEC paVentaFacturaCrear @EncFechaDocto = @hoy, @CliId = @cli, @TdoId = @tdo, @EncFechaPrimerPago = @primer, @EncNumeroCuotas = 1,
		@UsuId = @usu, @Detalle = @det, @FormasPago = @formas, @EncId = @enc OUTPUT, @EncNumeroUnico = @num OUTPUT;
	INSERT INTO prueba_carga.dbo.resultado (corrida, usuario, rol, operacion, inicio, ms, ok, enc_id) VALUES ('ultima', @u, 'vendedor', 'ultimas_unidades', @t0, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()), 1, @enc);
END TRY
BEGIN CATCH
	INSERT INTO prueba_carga.dbo.resultado (corrida, usuario, rol, operacion, inicio, ms, ok, error_num, error_msg) VALUES ('ultima', @u, 'vendedor', 'ultimas_unidades', @t0, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()), 0, ERROR_NUMBER(), LEFT(ERROR_MESSAGE(), 400));
END CATCH
