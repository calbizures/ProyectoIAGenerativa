/*
================================================================================
 57_orden_compra_firmas.sql
 Órdenes de compra con dos firmas: visto bueno del jefe de bodega y
 aprobación del contador general.

   - La orden la elabora el bodeguero (permiso COMPRAS_ORDEN) en borrador (B).
   - Primera firma: el jefe de bodega da el visto bueno (permiso
     COMPRAS_ORDEN_APROBAR_BODEGA); la orden pasa a V y ya no se edita.
   - Segunda firma: el contador general la aprueba (permiso
     COMPRAS_ORDEN_APROBAR); pasa a A y ya se puede recibir mercadería. Debe
     ser un usuario distinto del que dio el visto bueno.
   - Cualquiera de los dos puede devolverla a borrador con un motivo, para
     que el bodeguero la corrija; se borra el visto bueno.
   - Roles nuevos: Bodeguero, Jefe de bodega y Contador general.
   - Lo pendiente de órdenes con visto bueno cuenta como "en tránsito" en la
     rotación del inventario (no se vuelve a sugerir).
   - Datos de prueba: usuarios bodega01 (Bodeguero), jbodega (Jefe de
     bodega) y cgeneral (Contador general), contraseña Demo#2024.

 Errores nuevos: 54523 a 54527.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Columnas y estados
------------------------------------------------------------
IF COL_LENGTH('dbo.cmp_orden_compra_enc', 'usu_id_visto_bueno') IS NULL
	ALTER TABLE dbo.cmp_orden_compra_enc ADD
		[usu_id_visto_bueno]		INT				NULL
			CONSTRAINT [FK_cmp_orden_compra_enc_visto_bueno] FOREIGN KEY REFERENCES dbo.gen_usuario ([usu_id]),
		[ocp_fecha_visto_bueno]		DATETIME2(0)	NULL,
		[ocp_motivo_devolucion]		VARCHAR(256)	NULL;
GO

-- V = con visto bueno del jefe de bodega, pendiente del contador general.
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_cmp_orden_compra_enc_estado' AND definition NOT LIKE '%''V''%')
	ALTER TABLE dbo.cmp_orden_compra_enc DROP CONSTRAINT [CK_cmp_orden_compra_enc_estado];
IF OBJECT_ID('dbo.CK_cmp_orden_compra_enc_estado', 'C') IS NULL
	ALTER TABLE dbo.cmp_orden_compra_enc ADD CONSTRAINT [CK_cmp_orden_compra_enc_estado] CHECK ([ocp_estado] IN ('B', 'V', 'A', 'C', 'N'));
GO
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_cmp_orden_compra_enc_aprobacion' AND definition NOT LIKE '%visto_bueno%')
	ALTER TABLE dbo.cmp_orden_compra_enc DROP CONSTRAINT [CK_cmp_orden_compra_enc_aprobacion];
IF OBJECT_ID('dbo.CK_cmp_orden_compra_enc_aprobacion', 'C') IS NULL
	ALTER TABLE dbo.cmp_orden_compra_enc ADD CONSTRAINT [CK_cmp_orden_compra_enc_aprobacion]
		CHECK ([ocp_estado] IN ('B', 'N')
			OR ([ocp_estado] = 'V' AND [ocp_fecha_visto_bueno] IS NOT NULL)
			OR ([ocp_estado] IN ('A', 'C') AND [ocp_fecha_aprobacion] IS NOT NULL));
GO

------------------------------------------------------------
-- 2. Firmas
------------------------------------------------------------
-- Primera firma: visto bueno del jefe de bodega (B -> V).
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraAprobarBodega]
	@OcpId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	UPDATE dbo.cmp_orden_compra_enc
	   SET ocp_estado = 'V', usu_id_visto_bueno = @UsuId, ocp_fecha_visto_bueno = SYSDATETIME(), ocp_motivo_devolucion = NULL,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE ocp_id = @OcpId AND ocp_estado = 'B';
	IF @@ROWCOUNT = 0
		THROW 54523, 'Solo se da el visto bueno de bodega a una orden en borrador.', 1;
END;
GO

-- Segunda firma: aprobación del contador general (V -> A), otro usuario.
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraAprobar]
	@OcpId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	BEGIN TRANSACTION;
	DECLARE @estado CHAR(1), @vobo INT;
	SELECT @estado = ocp_estado, @vobo = usu_id_visto_bueno
	FROM dbo.cmp_orden_compra_enc WITH (UPDLOCK, HOLDLOCK)
	WHERE ocp_id = @OcpId;
	IF @estado = 'B'
		THROW 54525, 'Falta el visto bueno del jefe de bodega: la orden debe tener las dos firmas.', 1;
	IF @estado IS NULL OR @estado <> 'V'
		THROW 54509, 'Solo se aprueba una orden con el visto bueno del jefe de bodega.', 1;
	IF @UsuId IS NOT NULL AND @UsuId = @vobo
		THROW 54524, 'La aprobación del contador general debe darla un usuario distinto del que dio el visto bueno de bodega.', 1;
	UPDATE dbo.cmp_orden_compra_enc
	   SET ocp_estado = 'A', usu_id_aprobacion = @UsuId, ocp_fecha_aprobacion = SYSDATETIME(),
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE ocp_id = @OcpId;
	COMMIT;
END;
GO

-- Devolver a borrador (V -> B) para corregir; se borra el visto bueno.
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraDevolver]
	@OcpId	INT,
	@Motivo	VARCHAR(256),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(LTRIM(RTRIM(@Motivo)), '') = ''
		THROW 54526, 'Indique por qué se devuelve la orden.', 1;
	UPDATE dbo.cmp_orden_compra_enc
	   SET ocp_estado = 'B', usu_id_visto_bueno = NULL, ocp_fecha_visto_bueno = NULL,
		   ocp_motivo_devolucion = LTRIM(RTRIM(@Motivo)), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE ocp_id = @OcpId AND ocp_estado = 'V';
	IF @@ROWCOUNT = 0
		THROW 54527, 'Solo se devuelve a borrador una orden con visto bueno y sin aprobar.', 1;
END;
GO

-- Anular: en borrador, con visto bueno o aprobada sin nada recibido en compras vigentes.
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraAnular]
	@OcpId	INT,
	@Motivo	VARCHAR(256),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF ISNULL(LTRIM(RTRIM(@Motivo)), '') = ''
		THROW 54510, 'Indique el motivo.', 1;

	BEGIN TRANSACTION;
	DECLARE @estado CHAR(1) = (SELECT ocp_estado FROM dbo.cmp_orden_compra_enc WITH (UPDLOCK, HOLDLOCK) WHERE ocp_id = @OcpId);
	IF @estado IS NULL OR @estado NOT IN ('B', 'V', 'A')
		THROW 54511, 'Solo se anula una orden en borrador, con visto bueno o aprobada.', 1;
	IF EXISTS (SELECT 1 FROM dbo.fnOrdenCompraRecibido(@OcpId) WHERE recibido > 0)
		THROW 54512, 'La orden ya tiene mercadería recibida: ciérrela para cancelar lo pendiente.', 1;
	UPDATE dbo.cmp_orden_compra_enc
	   SET ocp_estado = 'N', ocp_motivo_cierre = LTRIM(RTRIM(@Motivo)), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE ocp_id = @OcpId;
	COMMIT;
END;
GO

------------------------------------------------------------
-- 3. Consultas (incluyen las firmas)
------------------------------------------------------------
-- Estado efectivo: B borrador, V visto bueno de bodega, A aprobada (nada
-- recibido), P parcial, R recibida (todo), C cerrada, N anulada.
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraConsultar]
	@Estado	CHAR(1) = NULL,
	@PrvId	INT = NULL,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL,
	@Texto	VARCHAR(100) = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @Texto = NULLIF(LTRIM(RTRIM(@Texto)), '');

	WITH ordenes AS (
		SELECT orde.ocp_id, orde.ocp_numero, orde.ocp_fecha, orde.ocp_fecha_entrega, orde.prv_id, orde.ocp_total,
			   orde.mon_id, orde.bod_id, orde.ocp_estado, cant.ordenado, cant.recibido,
			   CASE WHEN orde.ocp_estado <> 'A' THEN orde.ocp_estado
					WHEN cant.recibido >= cant.ordenado THEN 'R'
					WHEN cant.recibido > 0 THEN 'P'
					ELSE 'A' END AS estado
		FROM dbo.cmp_orden_compra_enc orde
		CROSS APPLY (SELECT SUM(deta.ocd_cantidad) AS ordenado, SUM(reci.recibido) AS recibido
					 FROM dbo.cmp_orden_compra_det deta
					 INNER JOIN dbo.fnOrdenCompraRecibido(orde.ocp_id) reci ON reci.ocd_id = deta.ocd_id) cant
		WHERE (@PrvId IS NULL OR orde.prv_id = @PrvId)
		  AND (@Desde IS NULL OR orde.ocp_fecha >= @Desde)
		  AND (@Hasta IS NULL OR orde.ocp_fecha <= @Hasta)
	)
	SELECT orde.ocp_id AS OcpId, orde.ocp_numero AS Numero, orde.ocp_fecha AS Fecha, orde.ocp_fecha_entrega AS FechaEntrega,
		   orde.prv_id AS PrvId, prov.prv_nombre_comercial AS Proveedor, prov.prv_nit AS Nit,
		   bode.bod_descripcion AS Bodega, ISNULL(mone.mon_simbolo, 'Q') AS Simbolo, orde.ocp_total AS Total,
		   orde.ordenado AS Ordenado, orde.recibido AS Recibido, orde.estado AS Estado,
		   CAST(CASE WHEN orde.estado IN ('A', 'P') AND orde.ocp_fecha_entrega < CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END AS BIT) AS Atrasada
	FROM ordenes orde
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = orde.prv_id
	INNER JOIN dbo.inv_bodega bode ON bode.bod_id = orde.bod_id
	LEFT JOIN dbo.gen_moneda mone ON mone.mon_id = orde.mon_id
	WHERE (@Estado IS NULL OR orde.estado = @Estado OR (@Estado = 'X' AND orde.estado IN ('A', 'P')) OR (@Estado = 'F' AND orde.estado IN ('B', 'V')))
	  AND (@Texto IS NULL OR orde.ocp_numero LIKE '%' + @Texto + '%' OR prov.prv_nombre_comercial LIKE '%' + @Texto + '%'
		   OR prov.prv_nit LIKE '%' + @Texto + '%' OR prov.prv_codigo LIKE '%' + @Texto + '%')
	ORDER BY orde.ocp_fecha DESC, orde.ocp_id DESC;
END;
GO

-- Una orden: encabezado (con emisor, proveedor y firmas), líneas con lo recibido
-- y lo pendiente, y las recepciones (compras) que la atendieron.
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraConsultarPorId]
	@OcpId	INT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @ordenado INT, @recibido INT;
	SELECT @ordenado = SUM(deta.ocd_cantidad), @recibido = SUM(reci.recibido)
	FROM dbo.cmp_orden_compra_det deta
	INNER JOIN dbo.fnOrdenCompraRecibido(@OcpId) reci ON reci.ocd_id = deta.ocd_id;

	SELECT orde.ocp_id AS OcpId, orde.ocp_numero AS Numero, orde.ocp_fecha AS Fecha, orde.ocp_fecha_entrega AS FechaEntrega,
		   CASE WHEN orde.ocp_estado <> 'A' THEN orde.ocp_estado
				WHEN @recibido >= @ordenado THEN 'R'
				WHEN @recibido > 0 THEN 'P'
				ELSE 'A' END AS Estado,
		   orde.prv_id AS PrvId, prov.prv_codigo AS ProveedorCodigo, prov.prv_nombre_comercial AS Proveedor, prov.prv_nit AS Nit,
		   prov.prv_direccion AS ProveedorDireccion, prov.prv_contacto AS ProveedorContacto,
		   COALESCE(prov.prv_telefono_oficina, prov.prv_celular) AS ProveedorTelefono,
		   COALESCE(prov.prv_email_contacto, prov.prv_email_empresa) AS ProveedorCorreo,
		   orde.suc_id AS SucId, orde.bod_id AS BodId, bode.bod_descripcion AS Bodega, orde.mon_id AS MonId,
		   ISNULL(mone.mon_codigo, 'GTQ') AS Moneda, ISNULL(mone.mon_simbolo, 'Q') AS Simbolo,
		   orde.ocp_porc_iva AS PorcentajeIva, orde.ocp_total AS Total,
		   CAST(ROUND(orde.ocp_total * orde.ocp_porc_iva / (100 + orde.ocp_porc_iva), 2) AS NUMERIC(14, 2)) AS IvaIncluido,
		   orde.ocp_condiciones AS Condiciones, orde.ocp_observaciones AS Observaciones, orde.ocp_motivo_cierre AS MotivoCierre,
		   usua.usu_codigo AS Usuario, apro.usu_codigo AS Aprobo, orde.ocp_fecha_aprobacion AS FechaAprobacion,
		   vobo.usu_codigo AS VistoBueno, orde.ocp_fecha_visto_bueno AS FechaVistoBueno, orde.ocp_motivo_devolucion AS MotivoDevolucion,
		   ISNULL(@ordenado, 0) AS Ordenado, ISNULL(@recibido, 0) AS Recibido,
		   -- Emisor y lugar de entrega
		   comp.cia_id AS CiaId, comp.cia_nit AS NitEmisor, ISNULL(comp.cia_fel_nombre_emisor, comp.cia_nombre_comercial) AS NombreEmisor,
		   ISNULL(sucu.suc_fel_nombre_comercial, comp.cia_nombre_comercial) AS NombreComercial,
		   ISNULL(sucu.suc_direccion, comp.cia_direccion) AS DireccionEmisor, ISNULL(sucu.suc_telefono, comp.cia_telefono) AS TelefonoEmisor,
		   ISNULL(comp.cia_fel_correo_emisor, comp.cia_email) AS CorreoEmisor, sucu.suc_descripcion AS Sucursal,
		   CAST(CASE WHEN comp.cia_logo IS NULL THEN 0 ELSE 1 END AS BIT) AS TieneLogo, comp.cia_logo_actualizado AS LogoActualizado
	FROM dbo.cmp_orden_compra_enc orde
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = orde.prv_id
	INNER JOIN dbo.inv_bodega bode ON bode.bod_id = orde.bod_id
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = orde.suc_id
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	LEFT JOIN dbo.gen_moneda mone ON mone.mon_id = orde.mon_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = orde.usu_id
	LEFT JOIN dbo.gen_usuario apro ON apro.usu_id = orde.usu_id_aprobacion
	LEFT JOIN dbo.gen_usuario vobo ON vobo.usu_id = orde.usu_id_visto_bueno
	WHERE orde.ocp_id = @OcpId;

	SELECT deta.ocd_id AS OcdId, deta.ocd_item AS Item, deta.pro_id AS ProId, prod.pro_codigo AS Codigo,
		   rela.ppp_codigo_proveedor AS CodigoProveedor, deta.ocd_descripcion AS Descripcion,
		   ISNULL(unid.ume_codigo, 'UND') AS Unidad, deta.ocd_cantidad AS Cantidad, reci.recibido AS Recibido,
		   IIF(deta.ocd_cantidad > reci.recibido, deta.ocd_cantidad - reci.recibido, 0) AS Pendiente,
		   deta.ocd_costo_unitario AS CostoUnitario, deta.ocd_total AS Total, exis.existencia AS Existencia
	FROM dbo.cmp_orden_compra_det deta
	INNER JOIN dbo.cmp_orden_compra_enc orde ON orde.ocp_id = deta.ocp_id
	INNER JOIN dbo.fnOrdenCompraRecibido(@OcpId) reci ON reci.ocd_id = deta.ocd_id
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = deta.ume_id
	LEFT JOIN dbo.inv_producto_proveedor rela ON rela.pro_id = deta.pro_id AND rela.prv_id = orde.prv_id
	LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = deta.pro_id AND exis.bod_id = orde.bod_id
	WHERE deta.ocp_id = @OcpId
	ORDER BY deta.ocd_item;

	SELECT rece.ocr_id AS OcrId, rece.enc_id AS EncId, rece.ocr_fecha AS Fecha,
		   CONCAT(comp.enc_serie_docto, IIF(comp.enc_serie_docto IS NULL, '', '-'), comp.enc_numero_docto) AS Documento,
		   comp.enc_monto_total AS Total, comp.enc_estado AS EstadoCompra, usua.usu_codigo AS Usuario,
		   (SELECT SUM(rdet.ord_cantidad) FROM dbo.cmp_orden_compra_recepcion_det rdet WHERE rdet.ocr_id = rece.ocr_id) AS Unidades
	FROM dbo.cmp_orden_compra_recepcion rece
	INNER JOIN dbo.inv_documento_enc comp ON comp.enc_id = rece.enc_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = rece.usu_id
	WHERE rece.ocp_id = @OcpId
	ORDER BY rece.ocr_fecha, rece.ocr_id;
END;
GO


------------------------------------------------------------
-- 4. Rotación: lo pedido en órdenes con visto bueno también está en tránsito
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
		WHERE orde.ocp_estado IN ('B', 'V', 'A') AND orde.bod_id IN (SELECT bod_id FROM @bodegas) AND deta.ocd_cantidad > reci.recibido
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
-- 5. Permisos y roles
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT v.modulo, v.codigo, v.descripcion
FROM (VALUES ('COMPRAS', 'COMPRAS_ORDEN_APROBAR_BODEGA', 'Órdenes de compra: visto bueno del jefe de bodega (primera firma)')) v (modulo, codigo, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso perm WHERE perm.per_codigo = v.codigo);
UPDATE dbo.sec_permiso SET per_descripcion = 'Órdenes de compra: aprobación del contador general (segunda firma)'
 WHERE per_codigo = 'COMPRAS_ORDEN_APROBAR';
GO

INSERT INTO dbo.sec_rol (rol_codigo, rol_nombre, rol_estado, InsFechaHora)
SELECT v.codigo, v.nombre, 'A', SYSDATETIME()
FROM (VALUES ('BODEGUERO', 'Bodeguero'), ('JEFE_BODEGA', 'Jefe de bodega'), ('CONTADOR_GENERAL', 'Contador general')) v (codigo, nombre)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_rol rol WHERE rol.rol_codigo = v.codigo OR rol.rol_nombre = v.nombre);
GO

-- El bodeguero elabora y recibe; el jefe de bodega además da el visto bueno;
-- el contador general aprueba y tiene lo del contador. El administrador
-- puede dar ambas firmas, pero no a la misma orden.
INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT rol.rol_id, perm.per_id
FROM (VALUES
	('BODEGUERO', 'COMPRAS_ORDEN'), ('BODEGUERO', 'COMPRAS_ORDEN_RECIBIR'), ('BODEGUERO', 'INVENTARIO_TRASLADO_ENVIAR'),
	('BODEGUERO', 'INVENTARIO_TRASLADO_RECIBIR'), ('BODEGUERO', 'INVENTARIO_FISICO'),
	('JEFE_BODEGA', 'COMPRAS_ORDEN'), ('JEFE_BODEGA', 'COMPRAS_ORDEN_APROBAR_BODEGA'), ('JEFE_BODEGA', 'COMPRAS_ORDEN_RECIBIR'),
	('JEFE_BODEGA', 'INVENTARIO_REORDEN'), ('JEFE_BODEGA', 'INVENTARIO_TRASLADO_ENVIAR'), ('JEFE_BODEGA', 'INVENTARIO_TRASLADO_RECIBIR'),
	('JEFE_BODEGA', 'INVENTARIO_FISICO'),
	('CONTADOR_GENERAL', 'COMPRAS_ORDEN_APROBAR'),
	('ADMIN', 'COMPRAS_ORDEN_APROBAR_BODEGA')) v (rol, permiso)
INNER JOIN dbo.sec_rol rol ON rol.rol_codigo = v.rol
INNER JOIN dbo.sec_permiso perm ON perm.per_codigo = v.permiso
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT gene.rol_id, rope.per_id
FROM dbo.sec_rol gene
INNER JOIN dbo.sec_rol cont ON cont.rol_codigo = 'CONTADOR'
INNER JOIN dbo.sec_rol_permiso rope ON rope.rol_id = cont.rol_id
WHERE gene.rol_codigo = 'CONTADOR_GENERAL'
  AND NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso otro WHERE otro.rol_id = gene.rol_id AND otro.per_id = rope.per_id);
GO

------------------------------------------------------------
-- 6. Usuarios de prueba (solo con los datos sintéticos)
------------------------------------------------------------
IF EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_codigo = 'ADMIN') AND EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_nit = '1234567-9')
BEGIN
	DECLARE @usuarios TABLE (codigo VARCHAR(20), usuario VARCHAR(50), correo VARCHAR(100), rol VARCHAR(30));
	INSERT INTO @usuarios VALUES ('BOD01', 'bodega01', 'bodega01@siq.com.gt', 'BODEGUERO'),
								 ('JBOD01', 'jbodega', 'jbodega@siq.com.gt', 'JEFE_BODEGA'),
								 ('CGEN01', 'cgeneral', 'cgeneral@siq.com.gt', 'CONTADOR_GENERAL');
	DECLARE @codigo VARCHAR(20), @usuario VARCHAR(50), @correo VARCHAR(100), @usu INT;
	DECLARE cursor_usuarios CURSOR LOCAL FAST_FORWARD FOR
		SELECT codigo, usuario, correo FROM @usuarios u WHERE NOT EXISTS (SELECT 1 FROM dbo.gen_usuario g WHERE g.usu_codigo = u.codigo OR g.usu_usuario = u.usuario);
	OPEN cursor_usuarios;
	FETCH NEXT FROM cursor_usuarios INTO @codigo, @usuario, @correo;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		EXEC dbo.sp_usuario_insertar @usu_codigo = @codigo, @usu_usuario = @usuario, @usu_password = 'Demo#2024', @usu_email = @correo, @usu_id = @usu OUTPUT;
		FETCH NEXT FROM cursor_usuarios INTO @codigo, @usuario, @correo;
	END
	CLOSE cursor_usuarios;
	DEALLOCATE cursor_usuarios;

	INSERT INTO dbo.sec_usuario_rol (usu_id, rol_id)
	SELECT usua.usu_id, rol.rol_id
	FROM @usuarios u
	INNER JOIN dbo.gen_usuario usua ON usua.usu_codigo = u.codigo
	INNER JOIN dbo.sec_rol rol ON rol.rol_codigo = u.rol
	WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_usuario_rol ur WHERE ur.usu_id = usua.usu_id AND ur.rol_id = rol.rol_id);

	INSERT INTO dbo.sec_usuario_sucursal (usu_id, suc_id, InsFechaHora)
	SELECT usua.usu_id, sucu.suc_id, SYSDATETIME()
	FROM @usuarios u
	INNER JOIN dbo.gen_usuario usua ON usua.usu_codigo = u.codigo
	CROSS JOIN dbo.gen_sucursal sucu
	WHERE sucu.suc_estado = 'A'
	  AND NOT EXISTS (SELECT 1 FROM dbo.sec_usuario_sucursal us WHERE us.usu_id = usua.usu_id AND us.suc_id = sucu.suc_id);
END
GO

PRINT '57_orden_compra_firmas.sql aplicado.';
GO
