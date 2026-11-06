/*
 04_verificar.sql — Resultado de la prueba de carga: tiempos, errores y consistencia.
 Correr después de las corridas (correr.ps1 o correr.sh).
*/
USE erp_db;
SET NOCOUNT ON;

PRINT '1. Tiempos por operación (ms)';
SELECT r.corrida, r.operacion, COUNT(*) AS operaciones, SUM(CAST(r.ok AS INT)) AS correctas,
	   AVG(r.ms) AS promedio_ms, MAX(r.ms) AS maximo_ms,
	   MAX(p.p95) AS p95_ms
FROM prueba_carga.dbo.resultado r
CROSS APPLY (SELECT DISTINCT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY r2.ms) OVER () AS p95
			 FROM prueba_carga.dbo.resultado r2 WHERE r2.corrida = r.corrida AND r2.operacion = r.operacion) p
GROUP BY r.corrida, r.operacion
ORDER BY r.operacion, r.corrida;

PRINT '2. Operaciones rechazadas (los choques esperados aparecen con mensaje de negocio)';
SELECT corrida, operacion, error_num, COUNT(*) AS veces, MIN(error_msg) AS ejemplo
FROM prueba_carga.dbo.resultado WHERE ok = 0
GROUP BY corrida, operacion, error_num ORDER BY corrida, operacion;

PRINT '3. Bloqueos mutuos (1205) y esperas vencidas (1222): deben ser 0';
SELECT COUNT(*) AS bloqueos FROM prueba_carga.dbo.resultado WHERE error_num IN (1205, 1222);

PRINT '4. Consistencia';
SELECT 'Números únicos duplicados' AS chequeo, COUNT(*) AS casos
FROM (SELECT tdo_id, enc_serie_docto, enc_numero_unico FROM dbo.inv_documento_enc
	  WHERE enc_numero_unico IS NOT NULL GROUP BY tdo_id, enc_serie_docto, enc_numero_unico HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'Operaciones correctas sin su documento grabado', COUNT(*)
FROM prueba_carga.dbo.resultado r
WHERE r.ok = 1 AND r.enc_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.inv_documento_enc e WHERE e.enc_id = r.enc_id AND e.enc_estado = 'G')
UNION ALL
SELECT 'Cuotas con saldo negativo o mayor que su valor', COUNT(*)
FROM dbo.pos_cliente_plan_pagos WHERE cpp_saldo_cuota < 0 OR cpp_saldo_cuota > cpp_valor_cuota
UNION ALL
SELECT 'Existencias negativas', COUNT(*) FROM dbo.inv_producto_existencia_bodega WHERE existencia < 0;

PRINT '5. Existencias: inicial + compras - ventas de la prueba = existencia actual';
WITH mov AS (
	SELECT deta.pro_id, deta.bod_id,
		   SUM(CASE tipo.tdo_naturaleza WHEN '+' THEN deta.det_cantidad ELSE -deta.det_cantidad END) AS movimientos
	FROM dbo.inv_documento_det deta
	INNER JOIN dbo.inv_documento_enc enca ON enca.enc_id = deta.enc_id
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id > (SELECT enc_max FROM prueba_carga.dbo.antes_max)
	  AND enca.enc_estado = 'G' AND deta.pro_id IS NOT NULL
	GROUP BY deta.pro_id, deta.bod_id)
SELECT mov.pro_id, mov.bod_id, ante.existencia AS antes, mov.movimientos, ante.existencia + mov.movimientos AS esperado,
	   exis.existencia AS actual,
	   CASE WHEN ante.existencia + mov.movimientos = exis.existencia THEN 'OK' ELSE 'DIFERENCIA' END AS resultado
FROM mov
INNER JOIN prueba_carga.dbo.antes_exis ante ON ante.pro_id = mov.pro_id AND ante.bod_id = mov.bod_id
INNER JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = mov.pro_id AND exis.bod_id = mov.bod_id
ORDER BY mov.pro_id;

PRINT '6. Controles de integridad del sistema (todos deben decir OK)';
EXEC dbo.paAuditoriaIntegridadConsultar;
