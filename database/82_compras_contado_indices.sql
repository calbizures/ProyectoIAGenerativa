/*
================================================================================
 82_compras_contado_indices.sql
 Hallazgos de la auditoría del 02/11/2026.

   1. Compras al contado y enganche sin cuota por pagar.
      El asiento de una compra abona Proveedores (COMPRA_PROVEEDORES) por el
      total, pero paProveedorPlanPagosGenerar solo creaba cuotas cuando la
      compra traía fecha del primer pago (crédito), y aun así por el total
      menos el enganche. Una compra al contado, o el enganche de una compra
      al crédito, quedaba en la cuenta contable sin cuota: no se podía pagar
      desde Cuentas por pagar y el saldo de CxP no cuadraba con contabilidad.
      Ahora:
        - Contado: una cuota por el total que vence la fecha de la compra.
        - Enganche: la cuota 1 es el enganche, con vencimiento la fecha de la
          compra; las cuotas del crédito siguen desde la 2.
        - Si la compra ya tiene plan de pagos, no se genera otro.
      Las compras grabadas sin plan (al contado) reciben su cuota pendiente
      aquí, una sola vez.

   2. Índices para llaves foráneas que se consultan seguido:
        inv_documento_det.afc_id, inv_documento_det.ume_id,
        pos_pago_enc.bcb_id, pos_pago_enc.usu_id_anulacion.

 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProveedorPlanPagosGenerar]
	@EncId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @contador INT, @nro INT, @fecha_iteracion DATE, @valor_cuota NUMERIC(13, 2),
			@prv_id INT, @numero_cuotas INT, @fecha_primer_pago DATE, @fecha_docto DATE,
			@monto_total NUMERIC(13, 2), @monto_enganche NUMERIC(13, 2);

	-- Un documento tiene un solo plan de pagos.
	IF EXISTS (SELECT 1 FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @EncId)
		RETURN;

	SELECT @prv_id = prv_id, @numero_cuotas = enc_numero_cuotas,
		   @fecha_primer_pago = enc_fecha_primer_pago, @fecha_docto = enc_fecha_docto,
		   @monto_total = enc_monto_total, @monto_enganche = ISNULL(enc_monto_enganche, 0)
	FROM dbo.inv_documento_enc
	WHERE enc_id = @EncId;

	IF @prv_id IS NULL OR ISNULL(@monto_total, 0) <= 0
		RETURN;

	-- Contado: una sola cuota por el total, vence el día de la compra.
	IF @fecha_primer_pago IS NULL OR ISNULL(@numero_cuotas, 0) <= 0
	BEGIN
		INSERT INTO dbo.inv_proveedor_plan_pago
			(ppg_nro_pago, ppg_fecha_pago, ppg_valor_pago, enc_id, prv_id, ppg_estado,
			 InsUsuario, InsFechaHora)
		VALUES
			(1, ISNULL(@fecha_docto, CAST(GETDATE() AS DATE)), @monto_total, @EncId, @prv_id, 'P',
			 @UsuId, SYSDATETIME());
		RETURN;
	END

	-- Crédito: el enganche (si hay) es la cuota 1, vence el día de la compra.
	SET @nro = 0;
	IF @monto_enganche > 0
	BEGIN
		SET @nro = 1;
		INSERT INTO dbo.inv_proveedor_plan_pago
			(ppg_nro_pago, ppg_fecha_pago, ppg_valor_pago, enc_id, prv_id, ppg_estado,
			 InsUsuario, InsFechaHora)
		VALUES
			(1, ISNULL(@fecha_docto, @fecha_primer_pago), @monto_enganche, @EncId, @prv_id, 'P',
			 @UsuId, SYSDATETIME());
	END

	SET @contador = 1;
	SET @valor_cuota = (@monto_total - @monto_enganche) / @numero_cuotas;
	SET @fecha_iteracion = @fecha_primer_pago;

	WHILE @contador <= @numero_cuotas
	BEGIN
		INSERT INTO dbo.inv_proveedor_plan_pago
			(ppg_nro_pago, ppg_fecha_pago, ppg_valor_pago, enc_id, prv_id, ppg_estado,
			 InsUsuario, InsFechaHora)
		VALUES
			(@nro + @contador, @fecha_iteracion, @valor_cuota, @EncId, @prv_id, 'P',
			 @UsuId, SYSDATETIME());

		SET @contador = @contador + 1;
		SET @fecha_iteracion = DATEADD(MONTH, 1, @fecha_iteracion);
		IF DATEPART(dw, @fecha_iteracion) = 7
			SET @fecha_iteracion = DATEADD(DAY, 1, @fecha_iteracion);
	END

	-- Los centavos del redondeo van a la última cuota: el plan suma el total.
	DECLARE @monto_restante NUMERIC(13, 2) = @monto_total
		- ISNULL((SELECT SUM(ppg_valor_pago) FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @EncId), 0);

	IF @monto_restante <> 0
		UPDATE dbo.inv_proveedor_plan_pago
		   SET ppg_valor_pago = ppg_valor_pago + @monto_restante,
			   UpdUsuario = @UsuId,
			   UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId
		   AND ppg_nro_pago = (SELECT MAX(ppg_nro_pago) FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @EncId);
END;
GO

-- Compras ya grabadas sin plan de pagos (al contado): su cuota pendiente.
DECLARE @enc_id INT;
DECLARE compras CURSOR LOCAL FAST_FORWARD FOR
	SELECT docu.enc_id
	FROM dbo.inv_documento_enc docu
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	WHERE tipo.tdo_codigo IN ('COMP', 'GAST')
	  AND docu.enc_estado = 'G'
	  AND docu.prv_id IS NOT NULL
	  AND docu.enc_monto_total > 0
	  AND NOT EXISTS (SELECT 1 FROM dbo.inv_proveedor_plan_pago ppag WHERE ppag.enc_id = docu.enc_id);
OPEN compras;
FETCH NEXT FROM compras INTO @enc_id;
WHILE @@FETCH_STATUS = 0
BEGIN
	EXEC dbo.paProveedorPlanPagosGenerar @EncId = @enc_id;
	FETCH NEXT FROM compras INTO @enc_id;
END
CLOSE compras;
DEALLOCATE compras;
GO

-- Índices normales (no filtrados): un índice filtrado exige QUOTED_IDENTIFIER ON
-- en todo INSERT/UPDATE de la tabla, y hay procedimientos antiguos sin él.
DECLARE @indices TABLE (tabla SYSNAME, columna SYSNAME, nombre SYSNAME);
INSERT INTO @indices VALUES
	('inv_documento_det', 'afc_id', 'IX_inv_documento_det_afc_id'),
	('inv_documento_det', 'ume_id', 'IX_inv_documento_det_ume_id'),
	('pos_pago_enc', 'bcb_id', 'IX_pos_pago_enc_bcb_id'),
	('pos_pago_enc', 'usu_id_anulacion', 'IX_pos_pago_enc_usu_id_anulacion');
DECLARE @tabla SYSNAME, @columna SYSNAME, @nombre SYSNAME, @sql NVARCHAR(MAX);
DECLARE indices CURSOR LOCAL FAST_FORWARD FOR SELECT tabla, columna, nombre FROM @indices;
OPEN indices;
FETCH NEXT FROM indices INTO @tabla, @columna, @nombre;
WHILE @@FETCH_STATUS = 0
BEGIN
	IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = @nombre AND has_filter = 1)
	BEGIN
		SET @sql = N'DROP INDEX ' + QUOTENAME(@nombre) + N' ON dbo.' + QUOTENAME(@tabla) + N';';
		EXEC sys.sp_executesql @sql;
	END
	IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = @nombre)
	BEGIN
		SET @sql = N'CREATE INDEX ' + QUOTENAME(@nombre) + N' ON dbo.' + QUOTENAME(@tabla) + N' (' + QUOTENAME(@columna) + N');';
		EXEC sys.sp_executesql @sql;
	END
	FETCH NEXT FROM indices INTO @tabla, @columna, @nombre;
END
CLOSE indices;
DEALLOCATE indices;
GO
