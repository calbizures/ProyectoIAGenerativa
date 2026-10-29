/*
================================================================================
 69_kardex_inventario.sql
 Fase 4, punto 5: kardex de un producto (Inventario › Existencias, pestaña
 Kardex).

 Cada movimiento de inventario del producto, en el orden en que el sistema
 lo procesó (fecha y hora de registro), con la cantidad que entra o sale, su
 costo unitario y su costo total, y después de cada línea el saldo del
 producto (cantidad, valor y costo unitario promedio) y la existencia de la
 bodega del movimiento:
   - compras, facturas, inventario inicial, ajustes de inventario físico,
     traslados (salida e ingreso) y devoluciones de notas de crédito;
   - un documento anulado aparece dos veces: su movimiento y, en la fecha de
     la anulación, la reversa al mismo costo (así lo procesa el sistema).
 El costo promedio se recalcula como lo hace paInventarioExistenciaDocumento
 Ajustar: (valor acumulado + costo del movimiento) / (cantidad acumulada +
 cantidad del movimiento); si el saldo queda en cero o negativo el valor
 vuelve a cero y se conserva el último promedio.
 El resultado 3 compara el saldo calculado con lo guardado en el producto
 (pro_total_cantidad, pro_total_costo, pro_costo_unitario) y con las
 existencias por bodega, para comprobar el costo promedio.

 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Resultado 1: el producto. 2: los movimientos (filtrados por bodega y
-- fechas; el saldo y el promedio siempre son del producto completo). 3: la
-- comprobación contra lo guardado.
CREATE OR ALTER PROCEDURE [dbo].[paInventarioKardexConsultar]
	@ProId	INT,
	@BodId	INT = NULL,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_id = @ProId)
		THROW 55601, 'El producto no existe.', 1;
	IF @Hasta < @Desde
		THROW 55602, 'La fecha final no puede ser anterior a la inicial.', 1;

	CREATE TABLE #mov (
		orden			INT IDENTITY(1,1) PRIMARY KEY,
		momento			DATETIME2(0),
		fecha			DATE,
		enc_id			INT,
		det_id			INT,
		bod_id			INT,
		tipo			VARCHAR(10),
		tipo_nombre		VARCHAR(100),
		documento		VARCHAR(60),
		tercero			VARCHAR(250),
		es_reversa		BIT,
		cantidad		NUMERIC(14, 4),		-- + entra, - sale
		costo_unitario	NUMERIC(14, 4),
		costo_total		NUMERIC(16, 2),		-- con el signo del movimiento
		saldo_cantidad	NUMERIC(14, 4),
		saldo_valor		NUMERIC(16, 2),
		promedio		NUMERIC(14, 4),
		saldo_bodega	NUMERIC(14, 4)
	);

	;WITH lineas AS (
		SELECT enca.enc_id, deta.det_id, deta.bod_id, tipo.tdo_codigo, tipo.tdo_descripcion, enca.enc_estado,
			   ISNULL(enca.enc_numero_unico, CONCAT(enca.enc_serie_docto, IIF(enca.enc_serie_docto IS NULL, '', '-'), enca.enc_numero_docto)) AS documento,
			   COALESCE(NULLIF(LTRIM(CONCAT(enca.enc_nombres_cliente, ' ', enca.enc_apellidos_cliente)), ''), prov.prv_nombre_comercial, enca.enc_motivo) AS tercero,
			   enca.enc_fecha_docto, enca.InsFechaHora, enca.UpdFechaHora,
			   IIF(tipo.tdo_naturaleza = '+', 1, -1) * deta.det_cantidad AS cantidad,
			   COALESCE(deta.det_costo_unitario, 0) AS costo_unitario
		FROM dbo.inv_documento_det deta
		INNER JOIN dbo.inv_documento_enc enca ON enca.enc_id = deta.enc_id
		INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
		INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id AND prod.pro_maneja_existencia = 1
		LEFT JOIN dbo.inv_proveedor prov ON prov.prv_id = enca.prv_id
		WHERE deta.pro_id = @ProId AND deta.det_cantidad > 0 AND deta.bod_id IS NOT NULL
		  -- Las notas solo mueven inventario en las líneas de devolución.
		  AND (tipo.tdo_codigo NOT IN ('NCC', 'NCP', 'NDC', 'NDP') OR deta.det_id_origen IS NOT NULL)
	), eventos AS (
		SELECT InsFechaHora AS momento, enc_fecha_docto AS fecha, enc_id, det_id, bod_id, tdo_codigo, tdo_descripcion, documento, tercero,
			   CAST(0 AS BIT) AS es_reversa, cantidad, costo_unitario
		FROM lineas
		UNION ALL
		SELECT UpdFechaHora, CAST(UpdFechaHora AS DATE), enc_id, det_id, bod_id, tdo_codigo, tdo_descripcion, documento, tercero,
			   CAST(1 AS BIT), -cantidad, costo_unitario
		FROM lineas WHERE enc_estado = 'A'
	)
	INSERT INTO #mov (momento, fecha, enc_id, det_id, bod_id, tipo, tipo_nombre, documento, tercero, es_reversa, cantidad, costo_unitario, costo_total)
	SELECT momento, fecha, enc_id, det_id, bod_id, tdo_codigo, tdo_descripcion, documento, tercero, es_reversa, cantidad, costo_unitario,
		   CAST(cantidad * costo_unitario AS NUMERIC(16, 2))
	FROM eventos
	ORDER BY momento, es_reversa, enc_id, det_id;

	-- Saldos, en el orden del sistema.
	DECLARE @orden INT = 1, @maximo INT = (SELECT MAX(orden) FROM #mov), @cantidad NUMERIC(14, 4) = 0, @valor NUMERIC(16, 2) = 0,
			@promedio NUMERIC(14, 4) = 0, @mov_cantidad NUMERIC(14, 4), @mov_costo NUMERIC(16, 2), @bod INT;
	DECLARE @bodegas TABLE (bod_id INT PRIMARY KEY, saldo NUMERIC(14, 4));
	WHILE @orden <= @maximo
	BEGIN
		SELECT @mov_cantidad = cantidad, @mov_costo = costo_total, @bod = bod_id FROM #mov WHERE orden = @orden;
		IF @cantidad + @mov_cantidad > 0
		BEGIN
			SET @valor = @valor + @mov_costo;
			SET @promedio = @valor / (@cantidad + @mov_cantidad);
		END
		ELSE SET @valor = 0;
		SET @cantidad = @cantidad + @mov_cantidad;
		IF NOT EXISTS (SELECT 1 FROM @bodegas WHERE bod_id = @bod) INSERT INTO @bodegas VALUES (@bod, 0);
		UPDATE @bodegas SET saldo = saldo + @mov_cantidad WHERE bod_id = @bod;
		UPDATE #mov SET saldo_cantidad = @cantidad, saldo_valor = @valor, promedio = @promedio,
						saldo_bodega = (SELECT saldo FROM @bodegas WHERE bod_id = @bod)
		WHERE orden = @orden;
		SET @orden += 1;
	END

	SELECT prod.pro_id AS ProId, prod.pro_codigo AS Codigo, prod.pro_descripcion AS Descripcion, prod.pro_maneja_existencia AS ManejaExistencia
	FROM dbo.inv_producto prod WHERE prod.pro_id = @ProId;

	-- Saldo anterior al período (o al primer movimiento de la bodega).
	SELECT movi.orden AS Orden, movi.momento AS Registrado, movi.fecha AS Fecha, movi.enc_id AS EncId, movi.bod_id AS BodId,
		   bode.bod_descripcion AS Bodega, movi.tipo AS Tipo, movi.tipo_nombre AS TipoNombre, movi.documento AS Documento,
		   movi.tercero AS Tercero, movi.es_reversa AS EsReversa,
		   IIF(movi.cantidad > 0, movi.cantidad, 0) AS Entrada, IIF(movi.cantidad < 0, -movi.cantidad, 0) AS Salida,
		   movi.costo_unitario AS CostoUnitario, movi.costo_total AS CostoTotal,
		   movi.saldo_cantidad AS SaldoCantidad, movi.saldo_valor AS SaldoValor, movi.promedio AS CostoPromedio,
		   movi.saldo_bodega AS SaldoBodega
	FROM #mov movi
	LEFT JOIN dbo.inv_bodega bode ON bode.bod_id = movi.bod_id
	WHERE (@BodId IS NULL OR movi.bod_id = @BodId)
	  AND (@Desde IS NULL OR movi.fecha >= @Desde)
	  AND (@Hasta IS NULL OR movi.fecha <= @Hasta)
	ORDER BY movi.orden;

	SELECT
		-- Saldo al inicio del período (último movimiento antes de @Desde).
		ISNULL((SELECT TOP 1 saldo_cantidad FROM #mov WHERE @Desde IS NOT NULL AND fecha < @Desde ORDER BY orden DESC), 0) AS InicialCantidad,
		ISNULL((SELECT TOP 1 saldo_valor FROM #mov WHERE @Desde IS NOT NULL AND fecha < @Desde ORDER BY orden DESC), 0) AS InicialValor,
		ISNULL((SELECT TOP 1 promedio FROM #mov WHERE @Desde IS NOT NULL AND fecha < @Desde ORDER BY orden DESC), 0) AS InicialPromedio,
		ISNULL((SELECT SUM(cantidad) FROM #mov WHERE @BodId IS NOT NULL AND bod_id = @BodId AND @Desde IS NOT NULL AND fecha < @Desde), 0) AS InicialBodega,
		-- Saldo final calculado con todos los movimientos.
		@cantidad AS CalculadoCantidad, @valor AS CalculadoValor, @promedio AS CalculadoPromedio,
		-- Lo guardado.
		prod.pro_total_cantidad AS GuardadoCantidad, prod.pro_total_costo AS GuardadoValor, prod.pro_costo_unitario AS GuardadoPromedio,
		ISNULL((SELECT SUM(exis.existencia) FROM dbo.inv_producto_existencia_bodega exis WHERE exis.pro_id = @ProId), 0) AS ExistenciaBodegas,
		ISNULL((SELECT SUM(exis.existencia) FROM dbo.inv_producto_existencia_bodega exis WHERE exis.pro_id = @ProId AND exis.bod_id = @BodId), 0) AS ExistenciaBodega,
		ISNULL((SELECT SUM(cantidad) FROM #mov WHERE bod_id = @BodId), 0) AS CalculadoBodega
	FROM dbo.inv_producto prod WHERE prod.pro_id = @ProId;
END;
GO

PRINT '69_kardex_inventario.sql aplicado.';
GO
