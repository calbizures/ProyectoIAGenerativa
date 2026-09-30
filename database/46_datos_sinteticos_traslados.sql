------------------------------------------------------------------------------
-- 46_datos_sinteticos_traslados.sql
--
-- Datos de prueba del script 45, grabados con sus procedimientos:
--
--   * Bodega BOD03 "Bodega de repuestos Zona 10" en la casa matriz, para
--     trasladar dentro de la misma sucursal.
--   * TR: BOD01 -> BOD03 (misma sucursal), ya recibido completo.
--   * TR: BOD01 -> BOD02 (Mixco), EN TRÁNSITO: queda pendiente de recibir
--     en la sucursal de Mixco.
--
-- Requiere 45. Se puede volver a correr: solo crea lo que falta.
------------------------------------------------------------------------------

USE [erp_db];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
-- El código de bodega es único por sucursal (UQ_inv_bodega_suc_codigo): BOD01 se
-- busca en la casa matriz (SUC01), BOD02 en Mixco (SUC02) y BOD03 en la misma
-- sucursal que BOD01.
DECLARE @bod1 INT = (SELECT TOP 1 bode.bod_id FROM dbo.inv_bodega bode INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
				   WHERE bode.bod_codigo = 'BOD01' ORDER BY CASE sucu.suc_codigo WHEN 'SUC01' THEN 0 ELSE 1 END, sucu.cia_id, bode.bod_id);
DECLARE @suc1 INT = (SELECT suc_id FROM dbo.inv_bodega WHERE bod_id = @bod1);
DECLARE @bod2 INT = (SELECT TOP 1 bode.bod_id FROM dbo.inv_bodega bode INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
				   WHERE bode.bod_codigo = 'BOD02' AND bode.suc_id <> @suc1
				   ORDER BY CASE sucu.suc_codigo WHEN 'SUC02' THEN 0 ELSE 1 END, sucu.cia_id, bode.bod_id);
DECLARE @bod3 INT = (SELECT bod_id FROM dbo.inv_bodega WHERE bod_codigo = 'BOD03' AND suc_id = @suc1);

IF @bod3 IS NULL AND @suc1 IS NOT NULL
	EXEC dbo.paBodegaGuardar @SucId = @suc1, @Codigo = 'BOD03', @Descripcion = 'Bodega de repuestos Zona 10', @UsuId = @usu, @IdResultado = @bod3 OUTPUT;

DECLARE @lineas dbo.inv_traslado_linea_type, @tra INT, @numero VARCHAR(16);

-- Traslado dentro de la casa matriz, recibido completo.
IF @bod1 IS NOT NULL AND @bod3 IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM dbo.inv_traslado WHERE bod_id_origen = @bod1 AND bod_id_destino = @bod3)
BEGIN
	INSERT INTO @lineas (pro_id, cantidad)
	SELECT TOP 2 exis.pro_id, 3 FROM dbo.inv_producto_existencia_bodega exis
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = exis.pro_id AND prod.pro_maneja_existencia = 1
	WHERE exis.bod_id = @bod1 AND exis.existencia >= 10 ORDER BY prod.pro_codigo;
	IF EXISTS (SELECT 1 FROM @lineas)
	BEGIN
		EXEC dbo.paInvTrasladoEnviar @BodIdOrigen = @bod1, @BodIdDestino = @bod3, @Observaciones = 'Repuestos para el taller',
			@Lineas = @lineas, @UsuId = @usu, @TraId = @tra OUTPUT;
		DELETE FROM @lineas;
		EXEC dbo.paInvTrasladoRecibir @TraId = @tra, @Lineas = @lineas, @Diferencia = 'D', @Nota = 'Recibido completo', @UsuId = @usu;
		SET @numero = (SELECT tra_numero FROM dbo.inv_traslado WHERE tra_id = @tra);
		PRINT CONCAT('Traslado ', @numero, ' BOD01 -> BOD03 recibido.');
	END
END

-- Traslado a Mixco, en tránsito.
DELETE FROM @lineas;
IF @bod1 IS NOT NULL AND @bod2 IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM dbo.inv_traslado WHERE bod_id_origen = @bod1 AND bod_id_destino = @bod2)
BEGIN
	INSERT INTO @lineas (pro_id, cantidad)
	SELECT TOP 3 exis.pro_id, 5 FROM dbo.inv_producto_existencia_bodega exis
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = exis.pro_id AND prod.pro_maneja_existencia = 1
	WHERE exis.bod_id = @bod1 AND exis.existencia >= 20 ORDER BY prod.pro_codigo DESC;
	IF EXISTS (SELECT 1 FROM @lineas)
	BEGIN
		EXEC dbo.paInvTrasladoEnviar @BodIdOrigen = @bod1, @BodIdDestino = @bod2, @Observaciones = 'Reposición de la sucursal Mixco',
			@Lineas = @lineas, @UsuId = @usu, @TraId = @tra OUTPUT;
		SET @numero = (SELECT tra_numero FROM dbo.inv_traslado WHERE tra_id = @tra);
		PRINT CONCAT('Traslado ', @numero, ' BOD01 -> BOD02 en tránsito.');
	END
END
GO
