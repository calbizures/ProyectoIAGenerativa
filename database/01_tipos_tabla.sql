/*
	Script 01: Tipos de tabla (Table-Valued Parameters).
	Se usan para enviar el detalle de compras y facturas en una sola
	llamada a los procedimientos de negocio (ver 11_procedimientos_procesos.sql).

	Cambio vs. script original: se quita la columna [enc_id] de ambos tipos.
	En el script original siempre viajaba en NULL porque el encabezado
	(inv_documento_enc) todavía no existía al momento de armar el detalle;
	el procedimiento lo asignaba después con SCOPE_IDENTITY(). Mantenerla
	en el tipo solo generaba confusión.
*/
USE [erp_db];
GO

IF TYPE_ID(N'dbo.compra_det_type') IS NOT NULL
	DROP TYPE [dbo].[compra_det_type];
GO
CREATE TYPE [dbo].[compra_det_type] AS TABLE
(
	[det_item]				INT				NOT NULL,
	[det_bien_o_servicio]	CHAR(1)			NOT NULL,
	[det_cantidad]			INT				NOT NULL,
	[det_descripcion]		VARCHAR(256)	NOT NULL,
	[det_precio_unitario]	NUMERIC(12, 2)	NOT NULL,	-- costo unitario de compra
	[det_valor_descuento]	NUMERIC(12, 2)	NOT NULL DEFAULT (0),
	[det_sub_total]			NUMERIC(12, 2)	NOT NULL,
	[det_porc_iva]			NUMERIC(8, 2)	NULL,
	[bod_id]				INT				NOT NULL,
	[pro_id]				INT				NULL
);
GO

IF TYPE_ID(N'dbo.factura_det_type') IS NOT NULL
	DROP TYPE [dbo].[factura_det_type];
GO
CREATE TYPE [dbo].[factura_det_type] AS TABLE
(
	[det_item]				INT				NOT NULL,
	[det_bien_o_servicio]	CHAR(1)			NOT NULL,
	[det_cantidad]			INT				NOT NULL,
	[det_descripcion]		VARCHAR(256)	NOT NULL,
	[det_precio_unitario]	NUMERIC(12, 2)	NOT NULL,	-- precio unitario de venta
	[det_valor_descuento]	NUMERIC(12, 2)	NOT NULL DEFAULT (0),
	[det_sub_total]			NUMERIC(12, 2)	NOT NULL,
	[det_costo_unitario]	NUMERIC(12, 5)	NULL,		-- costo unitario del producto al momento de la venta
	[det_porc_iva]			NUMERIC(8, 2)	NULL,
	[bod_id]				INT				NOT NULL,
	[pro_id]				INT				NULL,
	[ppr_id]				INT				NULL		-- inv_producto_precio.ppr_id con el que se vendió
);
GO

IF TYPE_ID(N'dbo.cont_asiento_det_type') IS NOT NULL
	DROP TYPE [dbo].[cont_asiento_det_type];
GO
CREATE TYPE [dbo].[cont_asiento_det_type] AS TABLE
(
	[cta_id]			INT				NOT NULL,
	[asd_debe]			DECIMAL(14, 2)	NOT NULL DEFAULT (0),
	[asd_haber]			DECIMAL(14, 2)	NOT NULL DEFAULT (0),
	[asd_descripcion]	VARCHAR(256)	NULL
);
GO

IF TYPE_ID(N'dbo.caja_denominacion_type') IS NOT NULL
	DROP TYPE [dbo].[caja_denominacion_type];
GO
CREATE TYPE [dbo].[caja_denominacion_type] AS TABLE
(
	[def_tipo_denominacion]	CHAR(1)			NOT NULL,	-- B=Billete, M=Moneda
	[def_denominacion]		NUMERIC(12, 2)	NOT NULL,
	[def_cantidad]			NUMERIC(8, 0)	NOT NULL
);
GO

IF TYPE_ID(N'dbo.caja_corte_forma_type') IS NOT NULL
	DROP TYPE [dbo].[caja_corte_forma_type];
GO
CREATE TYPE [dbo].[caja_corte_forma_type] AS TABLE
(
	[pft_id]			INT				NOT NULL,
	[pcf_monto_fisico]	NUMERIC(12, 2)	NOT NULL
);
GO

-- Forma(s) de pago del monto pagado al momento de facturar (de contado, o
-- el enganche si es a crédito) y del cobro de una cuota. Un mismo pago
-- puede dividirse en varias formas (p.ej. parte efectivo, parte cheque).
IF TYPE_ID(N'dbo.pago_forma_type') IS NOT NULL
	DROP TYPE [dbo].[pago_forma_type];
GO
CREATE TYPE [dbo].[pago_forma_type] AS TABLE
(
	[pft_id]							INT				NOT NULL,
	[ppf_monto]							NUMERIC(12, 2)	NOT NULL,
	[gef_id]							INT				NULL,
	[ppf_numero_tarjeta_ult4]			VARCHAR(4)		NULL,
	[ppf_fecha_vencimiento_tarjeta]	VARCHAR(4)		NULL,
	[ppf_numero_cheque]					VARCHAR(16)		NULL
);
GO
