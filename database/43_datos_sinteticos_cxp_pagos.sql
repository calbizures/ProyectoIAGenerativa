------------------------------------------------------------------------------
-- 43_datos_sinteticos_cxp_pagos.sql
--
-- Datos de prueba del script 42 (cheque por factura o por saldo), grabados
-- con sus procedimientos:
--
--   Tres compras al crédito de "Redes y Conectividad GT" (PRV04) con varias
--   cuotas, unas vencidas y otras por vencer, y un cheque que paga en una
--   sola emisión la primera cuota de la factura A-2201 y abona a la primera
--   de la A-2245. Quedan cuotas pendientes para pagar desde Cuentas por
--   pagar > Pagos por factura o por el saldo.
--
-- Requiere 42. Se puede volver a correr: las compras y el cheque se crean
-- una sola vez.
------------------------------------------------------------------------------

USE [erp_db];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- Compras al crédito con varias cuotas
------------------------------------------------------------
DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
DECLARE @prv INT = (SELECT prv_id FROM dbo.inv_proveedor WHERE prv_codigo = 'PRV04');
DECLARE @bod INT = (SELECT TOP 1 bode.bod_id FROM dbo.inv_bodega bode INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
				   WHERE bode.bod_codigo = 'BOD01' ORDER BY CASE sucu.suc_codigo WHEN 'SUC01' THEN 0 ELSE 1 END, sucu.cia_id, bode.bod_id);
DECLARE @tdo INT = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo = 'COMP');
DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
DECLARE @monitor INT = (SELECT pro_id FROM dbo.inv_producto WHERE pro_descripcion LIKE 'Monitor LG%');
DECLARE @disco INT = (SELECT pro_id FROM dbo.inv_producto WHERE pro_descripcion LIKE 'Disco duro externo%');
DECLARE @cable INT = (SELECT pro_id FROM dbo.inv_producto WHERE pro_descripcion LIKE 'Cable UTP%');

DECLARE @compras TABLE (orden INT PRIMARY KEY, numero VARCHAR(32), dias_atras INT, cuotas INT, primer_pago INT);
INSERT INTO @compras VALUES
	(1, '2201', 95, 3, 30),		-- las tres cuotas ya vencieron
	(2, '2245', 50, 2, 30),		-- una vencida y una por vencer
	(3, '2290', 12, 2, 30);		-- por vencer

DECLARE @orden INT = 1, @numero VARCHAR(32), @dias INT, @cuotas INT, @primer INT;
DECLARE @fecha DATE, @fecha_primer_pago DATE, @enc_id INT;
DECLARE @det dbo.compra_det_type;
DECLARE @relacionados TABLE (Relacionados INT);

IF @prv IS NULL OR @bod IS NULL OR @monitor IS NULL OR @disco IS NULL OR @cable IS NULL
	PRINT 'Compras de prueba omitidas: falta el proveedor PRV04, la bodega BOD01 o sus productos.';
ELSE
WHILE @orden <= 3
BEGIN
	SELECT @numero = numero, @dias = dias_atras, @cuotas = cuotas, @primer = primer_pago FROM @compras WHERE orden = @orden;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE prv_id = @prv AND tdo_id = @tdo AND enc_serie_docto = 'A' AND enc_numero_docto = @numero)
	BEGIN
		SET @fecha = DATEADD(DAY, -@dias, @hoy);
		SET @fecha_primer_pago = DATEADD(DAY, @primer, @fecha);
		DELETE FROM @det;
		INSERT INTO @det (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total, det_porc_iva, bod_id, pro_id)
		SELECT line.item, 'B', line.cantidad, prod.pro_descripcion, line.precio, line.precio * line.cantidad, 12, @bod, prod.pro_id
		FROM (VALUES (1, @monitor, 4 + @orden * 2, 589.00),
					 (2, @disco, 3 * @orden, 412.50),
					 (3, @cable, 2 + @orden, 895.00)) line (item, pro_id, cantidad, precio)
		INNER JOIN dbo.inv_producto prod ON prod.pro_id = line.pro_id;

		EXEC dbo.sp_compras_crear_documento
			@enc_fecha_docto = @fecha, @enc_serie_docto = 'A', @enc_numero_docto = @numero,
			@prv_id = @prv, @tdo_id = @tdo,
			@enc_fecha_primer_pago = @fecha_primer_pago, @enc_numero_cuotas = @cuotas,
			@usu_id = @usu, @detalle = @det, @enc_id = @enc_id OUTPUT;

		INSERT INTO @relacionados EXEC dbo.paProductoProveedorRegistrarCompra @EncId = @enc_id, @Relacionar = 1, @UsuId = @usu;
		PRINT CONCAT('Compra A-', @numero, ' de PRV04 creada con ', @cuotas, ' cuotas.');
	END
	SET @orden += 1;
END
GO

------------------------------------------------------------
-- Un cheque que paga cuotas de dos facturas
------------------------------------------------------------
DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
DECLARE @prv INT = (SELECT prv_id FROM dbo.inv_proveedor WHERE prv_codigo = 'PRV04');
DECLARE @cbc INT = (SELECT TOP 1 cheq.cbc_id FROM dbo.bco_cuenta_bancaria_chequera cheq
					INNER JOIN dbo.bco_cuenta_bancaria cuen ON cuen.bcb_id = cheq.bcb_id AND cuen.bcb_estado = 'A'
					WHERE cheq.cbc_estado = 'A' ORDER BY cheq.cbc_id);
DECLARE @bmp INT = (SELECT TOP 1 bmp_id FROM dbo.bco_motivo_pago WHERE bmp_descripcion = 'Pago a proveedores');
DECLARE @cuota_2201 INT = (SELECT cuot.ppg_id FROM dbo.inv_proveedor_plan_pago cuot
						   INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
						   WHERE docu.prv_id = @prv AND docu.enc_serie_docto = 'A' AND docu.enc_numero_docto = '2201' AND cuot.ppg_nro_pago = 1);
DECLARE @cuota_2245 INT = (SELECT cuot.ppg_id FROM dbo.inv_proveedor_plan_pago cuot
						   INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
						   WHERE docu.prv_id = @prv AND docu.enc_serie_docto = 'A' AND docu.enc_numero_docto = '2245' AND cuot.ppg_nro_pago = 1);

IF @cbc IS NULL OR @cuota_2201 IS NULL OR @cuota_2245 IS NULL
	PRINT 'Cheque de prueba omitido: falta una chequera activa o las compras de PRV04.';
ELSE IF EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_det WHERE ppg_id IN (@cuota_2201, @cuota_2245))
	PRINT 'El cheque de prueba de PRV04 ya existe.';
ELSE
BEGIN
	DECLARE @pago dbo.cxp_pago_cuota_type, @bce_id INT, @numero VARCHAR(16) = NULL;
	INSERT INTO @pago (ppg_id, monto)
	SELECT ppg_id, ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0) FROM dbo.inv_proveedor_plan_pago WHERE ppg_id = @cuota_2201
	UNION ALL
	SELECT @cuota_2245, 1000.00;

	EXEC dbo.paCxpChequeEmitir
		@PrvId = @prv, @CbcId = @cbc, @Numero = @numero, @BmpId = @bmp, @Concepto = NULL,
		@Cuotas = @pago, @UsuId = @usu, @BceId = @bce_id OUTPUT;

	DECLARE @resumen VARCHAR(300);
	SELECT @resumen = CONCAT('Cheque ', bce_numero_cheque, ' por Q', FORMAT(bce_valor, 'N2'), ': ', bce_observaciones)
	FROM dbo.bco_cheque_emitido_enc WHERE bce_id = @bce_id;
	PRINT @resumen;
END
GO
