/*
	Script 03: Inventario, productos, proveedores y documentos (facturas/compras).

	Cambios relevantes vs. el script original:
	- [inv_producto] no tenía columna de estado ni de tipo de ítem: se agregan
	  [pro_estado] y [pro_tipo_item] ('B'=Bien, 'S'=Servicio) para saber desde
	  el catálogo si un producto requiere control de existencias.
	- [inv_producto_existencia_bodega] no tenía UNIQUE(bod_id, pro_id), lo que
	  permitía existencias duplicadas por producto/bodega; se agrega.
	- inv_proveedor_plan_pago usaba el prefijo "ppr_", igual que
	  inv_producto_precio (precio de producto). Se renombra a "ppg_" (plan de
	  pago) para eliminar la ambigüedad entre ambos conceptos.
	- [inv_documento_enc] no registraba qué usuario grabó el documento; se
	  agrega [usu_id_creacion]. También se agrega soporte de moneda
	  ([mon_id], [enc_tipo_cambio]) para el nuevo módulo multi-moneda.
	- Se agregan CHECK constraints para los indicadores de una sola letra
	  (naturaleza de documento, bien/servicio, estado del documento, etc.).

	Todas las tablas agregan además [InsUsuario]/[InsFechaHora]/[UpdUsuario]/
	[UpdFechaHora] (ver el comentario de cabecera de 02_tablas_generales_seguridad.sql
	para la convención completa). En [inv_documento_enc] esto es adicional a
	[usu_id_creacion]/[enc_fecha_grabado], que ya existían con el mismo fin y
	se conservan por compatibilidad.
*/
USE [erp_db];
GO

------------------------------------------------------------
-- Tipos y características de producto
------------------------------------------------------------
CREATE TABLE [dbo].[inv_producto_tipo](
	[prt_id]			INT				IDENTITY(1,1)	NOT NULL,
	[prt_codigo]		VARCHAR(8)		NOT NULL,
	[prt_descripcion]	VARCHAR(64)		NOT NULL,
	[prt_estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_producto_tipo] PRIMARY KEY CLUSTERED ([prt_id] ASC),
	CONSTRAINT [UQ_inv_producto_tipo_codigo] UNIQUE ([prt_codigo]),
	CONSTRAINT [CK_inv_producto_tipo_estado] CHECK ([prt_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[inv_producto_tipo_caracteristica](
	[ptc_id]			INT				IDENTITY(1,1)	NOT NULL,
	[ptc_codigo]		VARCHAR(16)		NOT NULL,
	[ptc_descripcion]	VARCHAR(64)		NOT NULL,
	[ptc_orden]			INT				NOT NULL DEFAULT (0),	-- antes CHAR(1); un orden de despliegue no debe limitarse a un dígito
	[ptc_estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_producto_tipo_caracteristica] PRIMARY KEY CLUSTERED ([ptc_id] ASC),
	CONSTRAINT [UQ_inv_producto_tipo_caracteristica_codigo] UNIQUE ([ptc_codigo]),
	CONSTRAINT [CK_inv_producto_tipo_caracteristica_estado] CHECK ([ptc_estado] IN ('A','I'))
);
GO

------------------------------------------------------------
-- Producto
------------------------------------------------------------
CREATE TABLE [dbo].[inv_producto](
	[pro_id]					INT				IDENTITY(1,1)	NOT NULL,
	[pro_codigo]				VARCHAR(64)		NOT NULL,
	[pro_descripcion]			VARCHAR(256)	NOT NULL,
	[pro_tipo_item]				CHAR(1)			NOT NULL DEFAULT ('B'),		-- B=Bien, S=Servicio
	[pro_maneja_existencia]		BIT				NOT NULL DEFAULT (1),
	[pro_total_cantidad]		NUMERIC(12, 4)	NOT NULL DEFAULT (0),
	[pro_total_costo]			NUMERIC(14, 2)	NOT NULL DEFAULT (0),
	[pro_costo_unitario]		NUMERIC(14, 5)	NOT NULL DEFAULT (0),
	[pro_ptje_rentabilidad]		NUMERIC(8, 2)	NULL,
	[pro_id_padre]				INT				NULL,
	[prt_id]					INT				NOT NULL,
	[pro_estado]				CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]				INT				NULL,
	[InsFechaHora]				DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]				INT				NULL,
	[UpdFechaHora]				DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_producto] PRIMARY KEY CLUSTERED ([pro_id] ASC),
	CONSTRAINT [UQ_inv_producto_codigo] UNIQUE ([pro_codigo]),
	CONSTRAINT [CK_inv_producto_tipo_item] CHECK ([pro_tipo_item] IN ('B','S')),
	CONSTRAINT [CK_inv_producto_estado] CHECK ([pro_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[inv_producto_caracteristica](
	[pca_id]			INT				IDENTITY(1,1)	NOT NULL,
	[pca_valor]			VARCHAR(64)		NOT NULL,
	[pca_descripcion]	VARCHAR(64)		NULL,
	[pro_id]			INT				NOT NULL,
	[ptc_id]			INT				NOT NULL,
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_producto_caracteristica] PRIMARY KEY CLUSTERED ([pca_id] ASC),
	CONSTRAINT [UQ_inv_producto_caracteristica] UNIQUE ([pro_id], [ptc_id])
);
GO

CREATE TABLE [dbo].[inv_producto_precio](
	[ppr_id]							INT				IDENTITY(1,1)	NOT NULL,
	[ppr_precio_unitario_venta]			NUMERIC(12, 2)	NOT NULL,
	[ppr_descripcion]					VARCHAR(128)	NULL,
	[ppr_vigencia_desde]				DATE			NOT NULL,
	[ppr_vigencia_hasta]				DATE			NULL,
	[pro_id]							INT				NOT NULL,
	[bod_id]							INT				NOT NULL,
	[mon_id]							INT				NOT NULL,
	[ppr_estado]						CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]						INT				NULL,
	[InsFechaHora]						DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]						INT				NULL,
	[UpdFechaHora]						DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_producto_precio] PRIMARY KEY CLUSTERED ([ppr_id] ASC),
	CONSTRAINT [CK_inv_producto_precio_vigencia] CHECK ([ppr_vigencia_hasta] IS NULL OR [ppr_vigencia_hasta] >= [ppr_vigencia_desde]),
	CONSTRAINT [CK_inv_producto_precio_valor] CHECK ([ppr_precio_unitario_venta] >= 0),
	CONSTRAINT [CK_inv_producto_precio_estado] CHECK ([ppr_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[inv_producto_existencia_bodega](
	[peb_id]		INT				IDENTITY(1,1)	NOT NULL,
	[bod_id]		INT				NOT NULL,
	[pro_id]		INT				NOT NULL,
	[existencia]	NUMERIC(12, 4)	NOT NULL DEFAULT (0),
	[InsUsuario]	INT				NULL,
	[InsFechaHora]	DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]	INT				NULL,
	[UpdFechaHora]	DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_producto_existencia_bodega] PRIMARY KEY CLUSTERED ([peb_id] ASC),
	CONSTRAINT [UQ_inv_producto_existencia_bodega] UNIQUE ([bod_id], [pro_id])
);
GO

------------------------------------------------------------
-- Bodegas
------------------------------------------------------------
CREATE TABLE [dbo].[inv_bodega](
	[bod_id]			INT				IDENTITY(1,1)	NOT NULL,
	[bod_codigo]		VARCHAR(8)		NOT NULL,
	[bod_descripcion]	VARCHAR(128)	NOT NULL,
	[suc_id]			INT				NOT NULL,
	[bod_estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_bodega] PRIMARY KEY CLUSTERED ([bod_id] ASC),
	CONSTRAINT [UQ_inv_bodega_suc_codigo] UNIQUE ([suc_id], [bod_codigo]),
	CONSTRAINT [CK_inv_bodega_estado] CHECK ([bod_estado] IN ('A','I'))
);
GO

------------------------------------------------------------
-- Proveedores
------------------------------------------------------------
CREATE TABLE [dbo].[inv_proveedor](
	[prv_id]				INT				IDENTITY(1,1)	NOT NULL,
	[prv_codigo]			VARCHAR(16)		NOT NULL,
	[prv_nombre_comercial]	VARCHAR(128)	NOT NULL,
	[prv_nit]				VARCHAR(16)		NULL,
	[prv_contacto]			VARCHAR(128)	NULL,
	[prv_direccion]			VARCHAR(128)	NULL,
	[prv_telefono_oficina]	VARCHAR(16)		NULL,
	[prv_celular]			VARCHAR(16)		NULL,
	[prv_email_empresa]		VARCHAR(64)		NULL,
	[prv_email_contacto]	VARCHAR(64)		NULL,
	[prv_estado]			CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_proveedor] PRIMARY KEY CLUSTERED ([prv_id] ASC),
	CONSTRAINT [UQ_inv_proveedor_codigo] UNIQUE ([prv_codigo]),
	CONSTRAINT [CK_inv_proveedor_estado] CHECK ([prv_estado] IN ('A','I'))
);
GO
-- NIT único solo cuando viene informado (permite varios proveedores sin NIT registrado).
CREATE UNIQUE INDEX [UX_inv_proveedor_nit] ON [dbo].[inv_proveedor]([prv_nit]) WHERE [prv_nit] IS NOT NULL;
GO

CREATE TABLE [dbo].[inv_proveedor_plan_pago](
	[ppg_id]				INT				IDENTITY(1,1)	NOT NULL,
	[ppg_nro_pago]			INT				NOT NULL,
	[ppg_fecha_pago]		DATE			NOT NULL,
	[ppg_fecha_real_pago]	DATE			NULL,
	[ppg_valor_pago]		NUMERIC(12, 2)	NOT NULL,
	[ppg_valor_real_pago]	NUMERIC(12, 2)	NULL,
	[ppg_numero_cheque]		VARCHAR(16)		NULL,
	[enc_id]				INT				NOT NULL,
	[prv_id]				INT				NOT NULL,
	[cbc_id]				INT				NULL,
	[ppg_estado]			CHAR(1)			NOT NULL DEFAULT ('P'),	-- P=Pendiente, A=Abonado/pagado, V=Vencido
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_proveedor_plan_pago] PRIMARY KEY CLUSTERED ([ppg_id] ASC),
	CONSTRAINT [CK_inv_proveedor_plan_pago_estado] CHECK ([ppg_estado] IN ('P','A','V'))
);
GO

CREATE TABLE [dbo].[inv_producto_proveedor](
	[ppp_id]			INT				IDENTITY(1,1)	NOT NULL,
	[prv_id]			INT				NOT NULL,
	[pro_id]			INT				NOT NULL,
	[ppp_preferencia]	CHAR(1)			NOT NULL DEFAULT ('N'),	-- S=proveedor preferido, N=alterno
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_producto_proveedor] PRIMARY KEY CLUSTERED ([ppp_id] ASC),
	CONSTRAINT [UQ_inv_producto_proveedor] UNIQUE ([prv_id], [pro_id]),
	CONSTRAINT [CK_inv_producto_proveedor_pref] CHECK ([ppp_preferencia] IN ('S','N'))
);
GO

------------------------------------------------------------
-- Documentos de inventario (compras / ventas)
------------------------------------------------------------
CREATE TABLE [dbo].[inv_documento_tipo](
	[tdo_id]			INT				IDENTITY(1,1)	NOT NULL,
	[tdo_codigo]		VARCHAR(8)		NOT NULL,
	[tdo_descripcion]	VARCHAR(32)		NOT NULL,
	[tdo_naturaleza]	CHAR(1)			NOT NULL,		-- +=ingresa existencia, -=egresa existencia
	[afecta_costo]		CHAR(1)			NOT NULL DEFAULT ('S'),
	[tdo_estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_documento_tipo] PRIMARY KEY CLUSTERED ([tdo_id] ASC),
	CONSTRAINT [UQ_inv_documento_tipo_codigo] UNIQUE ([tdo_codigo]),
	CONSTRAINT [CK_inv_documento_tipo_naturaleza] CHECK ([tdo_naturaleza] IN ('+','-')),
	CONSTRAINT [CK_inv_documento_tipo_afecta_costo] CHECK ([afecta_costo] IN ('S','N')),
	CONSTRAINT [CK_inv_documento_tipo_estado] CHECK ([tdo_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[inv_documento_enc](
	[enc_id]						INT				IDENTITY(1,1)	NOT NULL,
	[enc_fecha_grabado]				DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[enc_fecha_docto]				DATE			NOT NULL,
	[enc_numero_autorizacion]		VARCHAR(64)		NULL,
	[enc_serie_docto]				VARCHAR(32)		NULL,
	[enc_numero_docto]				VARCHAR(32)		NULL,
	[cli_id]						INT				NULL,
	[enc_nombres_cliente]			VARCHAR(128)	NULL,
	[enc_apellidos_cliente]			VARCHAR(128)	NULL,
	[cli_nit]						VARCHAR(16)		NULL,
	[prv_id]						INT				NULL,
	[prv_enc_nombres_proveedor]		VARCHAR(128)	NULL,
	[prv_enc_apellidos_proveedor]	VARCHAR(128)	NULL,
	[prv_nit]						VARCHAR(16)		NULL,
	[tdo_id]						INT				NOT NULL,
	[pve_id]						INT				NULL,
	[enc_fecha_primer_pago]			DATE			NULL,
	[enc_monto_enganche]			NUMERIC(12, 2)	NOT NULL DEFAULT (0),
	[enc_numero_cuotas]				INT				NOT NULL DEFAULT (1),
	[enc_ptje_interes]				NUMERIC(8, 2)	NOT NULL DEFAULT (0),
	[enc_monto_total]				NUMERIC(12, 2)	NOT NULL,
	[enc_id_referencia]				INT				NULL,
	[enc_numero_cheque]				VARCHAR(16)		NULL,
	[gef_id]						INT				NULL,
	[enc_valor_descuento]			NUMERIC(13, 2)	NOT NULL DEFAULT (0),
	[enc_direccion_cliente]			VARCHAR(256)	NULL,
	[mon_id]						INT				NOT NULL,
	[enc_tipo_cambio]				DECIMAL(12, 6)	NOT NULL DEFAULT (1),
	[enc_xml]						XML				NULL,
	[enc_numero_unico]				VARCHAR(16)		NULL,
	[usu_id_creacion]				INT				NULL,
	[enc_estado]					CHAR(1)			NOT NULL DEFAULT ('P'),	-- P=Pendiente, G=Grabado, A=Anulado
	[InsUsuario]					INT				NULL,
	[InsFechaHora]					DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]					INT				NULL,
	[UpdFechaHora]					DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_documento_enc] PRIMARY KEY CLUSTERED ([enc_id] ASC),
	CONSTRAINT [CK_inv_documento_enc_estado] CHECK ([enc_estado] IN ('P','G','A'))
);
GO

-- Índice único FILTRADO (no una UNIQUE constraint corriente): las compras
-- (sp_compras_crear_documento) nunca llenan enc_numero_unico a propósito, así
-- que con una UNIQUE constraint normal (que en SQL Server solo permite UN
-- NULL en toda la tabla) apenas la primera compra de la vida del sistema
-- podía insertarse; cualquier compra o factura siguiente chocaba contra ese
-- primer NULL. Filtrando el índice por "IS NOT NULL" se preserva la
-- unicidad real (dos facturas no pueden compartir número) sin limitar
-- cuántos documentos pueden dejarlo en NULL.
CREATE UNIQUE INDEX [UQ_inv_documento_enc_numero_unico]
	ON [dbo].[inv_documento_enc] ([enc_numero_unico])
	WHERE [enc_numero_unico] IS NOT NULL;
GO

CREATE TABLE [dbo].[inv_documento_det](
	[det_id]				INT				IDENTITY(1,1)	NOT NULL,
	[enc_id]				INT				NOT NULL,
	[det_item]				INT				NOT NULL,
	[det_bien_o_servicio]	CHAR(1)			NOT NULL,
	[det_cantidad]			NUMERIC(12, 4)	NOT NULL,
	[det_descripcion]		VARCHAR(512)	NOT NULL,
	[det_precio_unitario]	NUMERIC(12, 2)	NOT NULL,
	[det_valor_descuento]	NUMERIC(12, 2)	NOT NULL DEFAULT (0),
	[det_sub_total]			NUMERIC(12, 2)	NOT NULL,
	[det_costo_unitario]	NUMERIC(12, 5)	NULL,
	[det_porc_iva]			NUMERIC(8, 2)	NULL,
	[bod_id]				INT				NOT NULL,
	[pro_id]				INT				NULL,
	[ppr_id]				INT				NULL,
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_inv_documento_det] PRIMARY KEY CLUSTERED ([det_id] ASC),
	CONSTRAINT [UQ_inv_documento_det_item] UNIQUE ([enc_id], [det_item]),
	CONSTRAINT [CK_inv_documento_det_bs] CHECK ([det_bien_o_servicio] IN ('B','S')),
	CONSTRAINT [CK_inv_documento_det_cantidad] CHECK ([det_cantidad] > 0),
	CONSTRAINT [CK_inv_documento_det_precio] CHECK ([det_precio_unitario] >= 0)
);
GO
