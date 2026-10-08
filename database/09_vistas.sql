/*
	Script 09: Vistas de selección de producto.

	Cambios vs. el script original:
	- vw_sel_producto tenía "and exb.bod_id = 1" quemado en el código, es
	  decir que solo funcionaba para la bodega con id 1. Se cambia a un
	  LEFT JOIN por bodega del precio, para que sirva con cualquier bodega
	  y quien la consuma filtre por bod_id si lo necesita.
	- Ambas vistas ahora filtran productos y precios inactivos.
*/
USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[vw_sel_producto]
AS
-- select * from vw_sel_producto where bod_id = 1
SELECT
	 pro.pro_id
	,pro.pro_codigo							AS Codigo
	,pro.pro_descripcion						AS Nombre
	,ppr.ppr_id
	,ppr.ppr_precio_unitario_venta				AS Precio
	,ppr.ppr_vigencia_desde						AS Desde
	,ppr.ppr_vigencia_hasta						AS Hasta
	,ppr.bod_id
	,ISNULL(exb.existencia, 0)					AS Existencia
FROM dbo.inv_producto pro
INNER JOIN dbo.inv_producto_precio ppr
	ON ppr.pro_id = pro.pro_id
	AND ppr.ppr_estado = 'A'
LEFT JOIN dbo.inv_producto_existencia_bodega exb
	ON exb.pro_id = pro.pro_id
	AND exb.bod_id = ppr.bod_id
WHERE pro.pro_estado = 'A';
GO

CREATE OR ALTER VIEW [dbo].[vw_sel_producto_compra]
AS
-- select * from vw_sel_producto_compra
SELECT
	 pro.pro_id
	,pro.pro_codigo				AS Codigo
	,pro.pro_descripcion			AS Nombre
	,pro.pro_costo_unitario		AS UltimoCosto
	,pro.pro_tipo_item
FROM dbo.inv_producto pro
WHERE pro.pro_estado = 'A';
GO
