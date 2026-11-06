/*
================================================================================
 54_rotacion_reorden.sql
 Rotación del inventario y punto de reorden, con sugerencia de órdenes de compra.

   Por producto (bien que maneja existencia) y bodega, en un período de N días
   que termina en una fecha:
     - Unidades vendidas: facturas menos devoluciones (notas de crédito con
       producto), solo documentos vigentes.
     - Costo de lo vendido y existencia inicial / final del período (la final
       se reconstruye desde la existencia de hoy restando los movimientos
       posteriores; la inicial, restando los del período).
     - Inventario promedio = (inicial + final) / 2.
     - Rotación del período = vendidas / inventario promedio; anualizada
       = rotación × 365 / días. Días de inventario = 365 / rotación anual.
     - Venta diaria = vendidas / días. Cobertura = existencia hoy / venta diaria.
     - Punto de reorden = venta diaria × (días de entrega + días de seguridad),
       redondeado hacia arriba. Días de entrega: los del proveedor preferido
       del producto (inv_producto_proveedor.ppp_dias_entrega) o, si no tiene,
       los de la compañía. Días de seguridad: los de la compañía.
     - En tránsito: lo pendiente de órdenes de compra en borrador o aprobadas
       para la bodega (así no se vuelve a sugerir lo que ya se pidió).
     - Sugerido: si existencia + tránsito <= punto de reorden, lo que falta
       para llegar a venta diaria × (entrega + seguridad + cobertura).
   Clasificación por rotación anual: A alta (>= 12), M media (>= 4),
   B baja (> 0), S sin ventas en el período.

   Parámetros por compañía (gen_compania): días de análisis (90), de entrega
   (7), de seguridad (7) y de cobertura (30).
   Permiso INVENTARIO_REORDEN. Las órdenes sugeridas se crean en borrador
   (script 53) agrupadas por proveedor preferido.

 Errores nuevos: 54601 a 54603.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Parámetros
------------------------------------------------------------
IF COL_LENGTH('dbo.gen_compania', 'cia_reorden_dias_analisis') IS NULL
	ALTER TABLE dbo.gen_compania ADD
		[cia_reorden_dias_analisis]		INT NOT NULL CONSTRAINT [DF_gen_compania_reorden_analisis] DEFAULT (90),
		[cia_reorden_dias_entrega]		INT NOT NULL CONSTRAINT [DF_gen_compania_reorden_entrega] DEFAULT (7),
		[cia_reorden_dias_seguridad]	INT NOT NULL CONSTRAINT [DF_gen_compania_reorden_seguridad] DEFAULT (7),
		[cia_reorden_dias_cobertura]	INT NOT NULL CONSTRAINT [DF_gen_compania_reorden_cobertura] DEFAULT (30);
GO
IF OBJECT_ID('dbo.CK_gen_compania_reorden', 'C') IS NULL
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [CK_gen_compania_reorden]
		CHECK ([cia_reorden_dias_analisis] BETWEEN 7 AND 730 AND [cia_reorden_dias_entrega] BETWEEN 0 AND 365
			   AND [cia_reorden_dias_seguridad] BETWEEN 0 AND 365 AND [cia_reorden_dias_cobertura] BETWEEN 1 AND 365);
GO

-- Días que tarda este proveedor en entregar este producto (NULL: los de la compañía).
IF COL_LENGTH('dbo.inv_producto_proveedor', 'ppp_dias_entrega') IS NULL
	ALTER TABLE dbo.inv_producto_proveedor ADD [ppp_dias_entrega] INT NULL;
GO
IF OBJECT_ID('dbo.CK_inv_producto_proveedor_dias_entrega', 'C') IS NULL
	ALTER TABLE dbo.inv_producto_proveedor ADD CONSTRAINT [CK_inv_producto_proveedor_dias_entrega]
		CHECK ([ppp_dias_entrega] IS NULL OR [ppp_dias_entrega] BETWEEN 0 AND 365);
GO

CREATE OR ALTER PROCEDURE [dbo].[paReordenParametrosConsultar]
	@CiaId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cia_id AS CiaId, cia_reorden_dias_analisis AS DiasAnalisis, cia_reorden_dias_entrega AS DiasEntrega,
		   cia_reorden_dias_seguridad AS DiasSeguridad, cia_reorden_dias_cobertura AS DiasCobertura
	FROM dbo.gen_compania WHERE cia_id = @CiaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paReordenParametrosGuardar]
	@CiaId			INT,
	@DiasAnalisis	INT,
	@DiasEntrega	INT,
	@DiasSeguridad	INT,
	@DiasCobertura	INT,
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @DiasAnalisis NOT BETWEEN 7 AND 730 OR @DiasEntrega NOT BETWEEN 0 AND 365
	   OR @DiasSeguridad NOT BETWEEN 0 AND 365 OR @DiasCobertura NOT BETWEEN 1 AND 365
		THROW 54601, 'Días de análisis de 7 a 730; de entrega y de seguridad de 0 a 365; de cobertura de 1 a 365.', 1;
	UPDATE dbo.gen_compania
	   SET cia_reorden_dias_analisis = @DiasAnalisis, cia_reorden_dias_entrega = @DiasEntrega,
		   cia_reorden_dias_seguridad = @DiasSeguridad, cia_reorden_dias_cobertura = @DiasCobertura,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cia_id = @CiaId;
	IF @@ROWCOUNT = 0
		THROW 54602, 'La compañía no existe.', 1;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoProveedorDiasEntregaGuardar]
	@PppId	INT,
	@Dias	INT = NULL,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @Dias IS NOT NULL AND @Dias NOT BETWEEN 0 AND 365
		THROW 54603, 'Los días de entrega van de 0 a 365 (vacío: los de la compañía).', 1;
	UPDATE dbo.inv_producto_proveedor SET ppp_dias_entrega = @Dias, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE ppp_id = @PppId;
END;
GO

------------------------------------------------------------
-- 2. Análisis
------------------------------------------------------------
-- @BodId NULL: todas las bodegas activas de @SucId (o de todas si también es NULL).
-- @Dias NULL: los de la compañía. @Hasta NULL: hoy.
CREATE OR ALTER PROCEDURE [dbo].[paInventarioRotacionConsultar]
	@BodId	INT = NULL,
	@SucId	INT = NULL,
	@Dias	INT = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @Hasta = ISNULL(@Hasta, CAST(GETDATE() AS DATE));

	DECLARE @bodegas TABLE (bod_id INT PRIMARY KEY, cia_id INT, dias_entrega INT, dias_seguridad INT, dias_cobertura INT, dias_analisis INT);
	INSERT INTO @bodegas
	SELECT bode.bod_id, comp.cia_id, comp.cia_reorden_dias_entrega, comp.cia_reorden_dias_seguridad,
		   comp.cia_reorden_dias_cobertura, comp.cia_reorden_dias_analisis
	FROM dbo.inv_bodega bode
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	WHERE bode.bod_estado = 'A'
	  AND (@BodId IS NULL OR bode.bod_id = @BodId)
	  AND (@SucId IS NULL OR bode.suc_id = @SucId);

	SET @Dias = ISNULL(@Dias, (SELECT MAX(dias_analisis) FROM @bodegas));
	SET @Dias = ISNULL(@Dias, 90);
	DECLARE @desde DATE = DATEADD(DAY, 1 - @Dias, @Hasta);

	-- Movimientos de inventario (documentos vigentes que afectan existencias).
	WITH movimientos AS (
		SELECT deta.pro_id, deta.bod_id,
			   SUM(CASE WHEN enca.enc_fecha_docto > @Hasta
						THEN deta.det_cantidad * IIF(tipo.tdo_naturaleza = '+', 1, -1) ELSE 0 END) AS neto_posterior,
			   SUM(CASE WHEN enca.enc_fecha_docto BETWEEN @desde AND @Hasta
						THEN deta.det_cantidad * IIF(tipo.tdo_naturaleza = '+', 1, -1) ELSE 0 END) AS neto_periodo,
			   SUM(CASE WHEN enca.enc_fecha_docto BETWEEN @desde AND @Hasta AND tipo.tdo_codigo = 'FCAM' THEN deta.det_cantidad
						WHEN enca.enc_fecha_docto BETWEEN @desde AND @Hasta AND tipo.tdo_codigo = 'NCC' THEN -deta.det_cantidad
						ELSE 0 END) AS vendidas,
			   SUM(CASE WHEN enca.enc_fecha_docto BETWEEN @desde AND @Hasta AND tipo.tdo_codigo = 'FCAM' THEN deta.det_cantidad * ISNULL(deta.det_costo_unitario, 0)
						WHEN enca.enc_fecha_docto BETWEEN @desde AND @Hasta AND tipo.tdo_codigo = 'NCC' THEN -deta.det_cantidad * ISNULL(deta.det_costo_unitario, 0)
						ELSE 0 END) AS costo_vendido,
			   MAX(CASE WHEN tipo.tdo_codigo = 'FCAM' AND enca.enc_fecha_docto <= @Hasta THEN enca.enc_fecha_docto END) AS ultima_venta
		FROM dbo.inv_documento_det deta
		INNER JOIN dbo.inv_documento_enc enca ON enca.enc_id = deta.enc_id AND enca.enc_estado = 'G'
		INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.afecta_costo = 'S'
		WHERE deta.pro_id IS NOT NULL
		  AND deta.bod_id IN (SELECT bod_id FROM @bodegas)
		  AND enca.enc_fecha_docto >= @desde
		GROUP BY deta.pro_id, deta.bod_id
	),
	transito AS (
		SELECT orde.bod_id, deta.pro_id, SUM(deta.ocd_cantidad - reci.recibido) AS pendiente
		FROM dbo.cmp_orden_compra_enc orde
		INNER JOIN dbo.cmp_orden_compra_det deta ON deta.ocp_id = orde.ocp_id
		CROSS APPLY (SELECT ISNULL(SUM(rdet.ord_cantidad), 0) AS recibido
					 FROM dbo.cmp_orden_compra_recepcion_det rdet
					 INNER JOIN dbo.cmp_orden_compra_recepcion rece ON rece.ocr_id = rdet.ocr_id
					 INNER JOIN dbo.inv_documento_enc comp ON comp.enc_id = rece.enc_id AND comp.enc_estado = 'G'
					 WHERE rdet.ocd_id = deta.ocd_id) reci
		WHERE orde.ocp_estado IN ('B', 'A') AND orde.bod_id IN (SELECT bod_id FROM @bodegas) AND deta.ocd_cantidad > reci.recibido
		GROUP BY orde.bod_id, deta.pro_id
	),
	base AS (
		SELECT prod.pro_id, bode.bod_id, bode.dias_seguridad, bode.dias_cobertura,
			   ISNULL(exis.existencia, 0) AS existencia,
			   ISNULL(exis.existencia, 0) - ISNULL(movi.neto_posterior, 0) AS final_periodo,
			   ISNULL(exis.existencia, 0) - ISNULL(movi.neto_posterior, 0) - ISNULL(movi.neto_periodo, 0) AS inicial_periodo,
			   IIF(ISNULL(movi.vendidas, 0) > 0, movi.vendidas, 0) AS vendidas,
			   IIF(ISNULL(movi.costo_vendido, 0) > 0, movi.costo_vendido, 0) AS costo_vendido,
			   movi.ultima_venta,
			   ISNULL(tras.pendiente, 0) AS transito,
			   pref.prv_id, pref.ppp_ultimo_costo, ISNULL(pref.ppp_dias_entrega, bode.dias_entrega) AS dias_entrega
		FROM dbo.inv_producto prod
		CROSS JOIN @bodegas bode
		LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = prod.pro_id AND exis.bod_id = bode.bod_id
		LEFT JOIN movimientos movi ON movi.pro_id = prod.pro_id AND movi.bod_id = bode.bod_id
		LEFT JOIN transito tras ON tras.pro_id = prod.pro_id AND tras.bod_id = bode.bod_id
		OUTER APPLY (SELECT TOP 1 rela.prv_id, rela.ppp_ultimo_costo, rela.ppp_dias_entrega
					 FROM dbo.inv_producto_proveedor rela
					 INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = rela.prv_id AND prov.prv_estado = 'A'
					 WHERE rela.pro_id = prod.pro_id
					 ORDER BY IIF(rela.ppp_preferencia = 'S', 0, 1), rela.ppp_fecha_ultima_compra DESC) pref
		WHERE prod.pro_estado = 'A' AND prod.pro_tipo_item = 'B' AND prod.pro_maneja_existencia = 1
		  -- Solo lo que se maneja en la bodega: con existencia, movimiento, tránsito o precio en ella.
		  AND (exis.pro_id IS NOT NULL OR movi.pro_id IS NOT NULL OR tras.pro_id IS NOT NULL
			   OR EXISTS (SELECT 1 FROM dbo.inv_producto_precio prec WHERE prec.pro_id = prod.pro_id AND prec.bod_id = bode.bod_id AND prec.ppr_estado = 'A'))
	),
	calculo AS (
		SELECT base.*,
			   CAST(base.vendidas AS DECIMAL(18, 6)) / @Dias AS venta_diaria,
			   (IIF(base.inicial_periodo > 0, base.inicial_periodo, 0) + IIF(base.final_periodo > 0, base.final_periodo, 0)) / 2.0 AS promedio
		FROM base
	),
	reorden AS (
		SELECT calculo.*,
			   CEILING(calculo.venta_diaria * (calculo.dias_entrega + calculo.dias_seguridad)) AS punto_reorden,
			   CEILING(calculo.venta_diaria * (calculo.dias_entrega + calculo.dias_seguridad + calculo.dias_cobertura)) AS maximo,
			   CASE WHEN calculo.promedio > 0 THEN calculo.vendidas / calculo.promedio END AS rotacion
		FROM calculo
	)
	SELECT reor.pro_id AS ProId, prod.pro_codigo AS Codigo, prod.pro_descripcion AS Descripcion,
		   ISNULL(unid.ume_codigo, 'UND') AS Unidad, tipo.prt_descripcion AS Categoria,
		   reor.bod_id AS BodId, bode.bod_descripcion AS Bodega,
		   CAST(reor.existencia AS DECIMAL(14, 2)) AS Existencia, CAST(reor.transito AS DECIMAL(14, 2)) AS Transito,
		   CAST(reor.inicial_periodo AS DECIMAL(14, 2)) AS ExistenciaInicial, CAST(reor.final_periodo AS DECIMAL(14, 2)) AS ExistenciaFinal,
		   CAST(reor.promedio AS DECIMAL(14, 2)) AS InventarioPromedio,
		   CAST(reor.vendidas AS DECIMAL(14, 2)) AS Vendidas, CAST(reor.costo_vendido AS DECIMAL(14, 2)) AS CostoVendido,
		   CAST(reor.venta_diaria AS DECIMAL(14, 4)) AS VentaDiaria,
		   CAST(reor.rotacion AS DECIMAL(14, 2)) AS Rotacion,
		   CAST(reor.rotacion * 365.0 / @Dias AS DECIMAL(14, 2)) AS RotacionAnual,
		   CAST(CASE WHEN reor.rotacion > 0 THEN @Dias / reor.rotacion END AS DECIMAL(14, 1)) AS DiasInventario,
		   CAST(CASE WHEN reor.venta_diaria > 0 THEN reor.existencia / reor.venta_diaria END AS DECIMAL(14, 1)) AS DiasCobertura,
		   reor.ultima_venta AS UltimaVenta,
		   reor.dias_entrega AS DiasEntrega, reor.dias_seguridad AS DiasSeguridad,
		   CAST(reor.punto_reorden AS INT) AS PuntoReorden,
		   CAST(CASE WHEN reor.vendidas > 0 AND reor.existencia + reor.transito <= reor.punto_reorden
					 THEN reor.maximo - (reor.existencia + reor.transito) ELSE 0 END AS INT) AS Sugerido,
		   CAST(CASE WHEN reor.vendidas > 0 AND reor.existencia + reor.transito <= reor.punto_reorden THEN 1 ELSE 0 END AS BIT) AS BajoReorden,
		   CASE WHEN reor.vendidas = 0 THEN 'S'
				WHEN reor.rotacion * 365.0 / @Dias >= 12 OR reor.rotacion IS NULL THEN 'A'
				WHEN reor.rotacion * 365.0 / @Dias >= 4 THEN 'M'
				ELSE 'B' END AS Clase,
		   CAST(reor.existencia * prod.pro_costo_unitario AS DECIMAL(14, 2)) AS ValorInventario,
		   reor.prv_id AS PrvId, prov.prv_nombre_comercial AS Proveedor,
		   CAST(COALESCE(reor.ppp_ultimo_costo, prod.pro_costo_unitario) AS DECIMAL(14, 4)) AS CostoSinIva,
		   @desde AS Desde, @Hasta AS Hasta, @Dias AS Dias
	FROM reorden reor
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = reor.pro_id
	INNER JOIN dbo.inv_bodega bode ON bode.bod_id = reor.bod_id
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = prod.ume_id
	LEFT JOIN dbo.inv_producto_tipo tipo ON tipo.prt_id = prod.prt_id
	LEFT JOIN dbo.inv_proveedor prov ON prov.prv_id = reor.prv_id
	ORDER BY CASE WHEN reor.vendidas > 0 AND reor.existencia + reor.transito <= reor.punto_reorden THEN 0 ELSE 1 END,
			 reor.venta_diaria DESC, prod.pro_codigo;
END;
GO

------------------------------------------------------------
-- 3. Productos por proveedor con los días de entrega (amplía el 40)
------------------------------------------------------------
-- Relaciones de un proveedor (sus productos) o de un producto (sus proveedores).
CREATE OR ALTER PROCEDURE [dbo].[paProductoProveedorConsultar]
	@PrvId	INT = NULL,
	@ProId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT rela.ppp_id AS PppId, rela.prv_id AS PrvId, prov.prv_codigo AS PrvCodigo, prov.prv_nombre_comercial AS Proveedor,
		   rela.pro_id AS ProId, prod.pro_codigo AS ProCodigo, prod.pro_descripcion AS ProDescripcion, prod.pro_tipo_item AS ProTipoItem,
		   unid.ume_codigo AS UmeCodigo, prod.pro_costo_unitario AS ProCostoUnitario, prod.pro_estado AS ProEstado,
		   CAST(CASE WHEN rela.ppp_preferencia = 'S' THEN 1 ELSE 0 END AS BIT) AS Preferido,
		   rela.ppp_codigo_proveedor AS CodigoProveedor, rela.ppp_ultimo_costo AS UltimoCosto,
		   rela.ppp_fecha_ultima_compra AS FechaUltimaCompra, rela.ppp_dias_entrega AS DiasEntrega
	FROM dbo.inv_producto_proveedor rela
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = rela.prv_id
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = rela.pro_id
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = prod.ume_id
	WHERE (@PrvId IS NULL OR rela.prv_id = @PrvId)
	  AND (@ProId IS NULL OR rela.pro_id = @ProId)
	ORDER BY CASE WHEN @PrvId IS NULL THEN prov.prv_nombre_comercial ELSE prod.pro_descripcion END;
END;
GO

------------------------------------------------------------
-- 4. Permiso
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT v.modulo, v.codigo, v.descripcion
FROM (VALUES ('INVENTARIO', 'INVENTARIO_REORDEN', 'Rotación del inventario y punto de reorden: consultar, parametrizar y sugerir órdenes de compra')) v (modulo, codigo, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso perm WHERE perm.per_codigo = v.codigo);
GO

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT rol.rol_id, perm.per_id
FROM (VALUES ('Administrador', 'INVENTARIO_REORDEN'), ('Contador', 'INVENTARIO_REORDEN')) v (rol, permiso)
INNER JOIN dbo.sec_rol rol ON rol.rol_nombre = v.rol
INNER JOIN dbo.sec_permiso perm ON perm.per_codigo = v.permiso
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO

PRINT '54_rotacion_reorden.sql aplicado.';
GO
