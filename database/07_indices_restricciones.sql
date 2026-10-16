/*
	Script 07: Índices de apoyo para llaves foráneas.

	El script original prácticamente no tenía índices no clusterizados: solo
	existía el índice implícito de cada PRIMARY KEY. Toda consulta que
	filtrara o hiciera JOIN por una columna de llave foránea forzaba un
	escaneo completo de la tabla. Aquí se agrega un índice para cada columna
	de llave foránea que no quede ya cubierta como columna líder de un
	UNIQUE/PRIMARY KEY existente.
*/
USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_gen_entidad_financiera_geft_id' AND object_id = OBJECT_ID(N'dbo.gen_entidad_financiera'))
CREATE INDEX [IX_gen_entidad_financiera_geft_id] ON [dbo].[gen_entidad_financiera]([geft_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_gen_auditoria_usu_id' AND object_id = OBJECT_ID(N'dbo.gen_auditoria'))
CREATE INDEX [IX_gen_auditoria_usu_id] ON [dbo].[gen_auditoria]([usu_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_conf_correlativos_tdo_id' AND object_id = OBJECT_ID(N'dbo.conf_correlativos'))
CREATE INDEX [IX_conf_correlativos_tdo_id] ON [dbo].[conf_correlativos]([tdo_id]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sec_rol_permiso_per_id' AND object_id = OBJECT_ID(N'dbo.sec_rol_permiso'))
CREATE INDEX [IX_sec_rol_permiso_per_id] ON [dbo].[sec_rol_permiso]([per_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sec_usuario_rol_rol_id' AND object_id = OBJECT_ID(N'dbo.sec_usuario_rol'))
CREATE INDEX [IX_sec_usuario_rol_rol_id] ON [dbo].[sec_usuario_rol]([rol_id]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_producto_prt_id' AND object_id = OBJECT_ID(N'dbo.inv_producto'))
CREATE INDEX [IX_inv_producto_prt_id] ON [dbo].[inv_producto]([prt_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_producto_pro_id_padre' AND object_id = OBJECT_ID(N'dbo.inv_producto'))
CREATE INDEX [IX_inv_producto_pro_id_padre] ON [dbo].[inv_producto]([pro_id_padre]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_producto_caracteristica_ptc_id' AND object_id = OBJECT_ID(N'dbo.inv_producto_caracteristica'))
CREATE INDEX [IX_inv_producto_caracteristica_ptc_id] ON [dbo].[inv_producto_caracteristica]([ptc_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_producto_precio_pro_id' AND object_id = OBJECT_ID(N'dbo.inv_producto_precio'))
CREATE INDEX [IX_inv_producto_precio_pro_id] ON [dbo].[inv_producto_precio]([pro_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_producto_precio_bod_id' AND object_id = OBJECT_ID(N'dbo.inv_producto_precio'))
CREATE INDEX [IX_inv_producto_precio_bod_id] ON [dbo].[inv_producto_precio]([bod_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_producto_precio_mon_id' AND object_id = OBJECT_ID(N'dbo.inv_producto_precio'))
CREATE INDEX [IX_inv_producto_precio_mon_id] ON [dbo].[inv_producto_precio]([mon_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_producto_existencia_bodega_pro_id' AND object_id = OBJECT_ID(N'dbo.inv_producto_existencia_bodega'))
CREATE INDEX [IX_inv_producto_existencia_bodega_pro_id] ON [dbo].[inv_producto_existencia_bodega]([pro_id]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_proveedor_plan_pago_enc_id' AND object_id = OBJECT_ID(N'dbo.inv_proveedor_plan_pago'))
CREATE INDEX [IX_inv_proveedor_plan_pago_enc_id] ON [dbo].[inv_proveedor_plan_pago]([enc_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_proveedor_plan_pago_prv_id' AND object_id = OBJECT_ID(N'dbo.inv_proveedor_plan_pago'))
CREATE INDEX [IX_inv_proveedor_plan_pago_prv_id] ON [dbo].[inv_proveedor_plan_pago]([prv_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_proveedor_plan_pago_cbc_id' AND object_id = OBJECT_ID(N'dbo.inv_proveedor_plan_pago'))
CREATE INDEX [IX_inv_proveedor_plan_pago_cbc_id] ON [dbo].[inv_proveedor_plan_pago]([cbc_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_producto_proveedor_pro_id' AND object_id = OBJECT_ID(N'dbo.inv_producto_proveedor'))
CREATE INDEX [IX_inv_producto_proveedor_pro_id] ON [dbo].[inv_producto_proveedor]([pro_id]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_documento_enc_cli_id' AND object_id = OBJECT_ID(N'dbo.inv_documento_enc'))
CREATE INDEX [IX_inv_documento_enc_cli_id] ON [dbo].[inv_documento_enc]([cli_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_documento_enc_prv_id' AND object_id = OBJECT_ID(N'dbo.inv_documento_enc'))
CREATE INDEX [IX_inv_documento_enc_prv_id] ON [dbo].[inv_documento_enc]([prv_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_documento_enc_tdo_id' AND object_id = OBJECT_ID(N'dbo.inv_documento_enc'))
CREATE INDEX [IX_inv_documento_enc_tdo_id] ON [dbo].[inv_documento_enc]([tdo_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_documento_enc_pve_id' AND object_id = OBJECT_ID(N'dbo.inv_documento_enc'))
CREATE INDEX [IX_inv_documento_enc_pve_id] ON [dbo].[inv_documento_enc]([pve_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_documento_enc_gef_id' AND object_id = OBJECT_ID(N'dbo.inv_documento_enc'))
CREATE INDEX [IX_inv_documento_enc_gef_id] ON [dbo].[inv_documento_enc]([gef_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_documento_enc_mon_id' AND object_id = OBJECT_ID(N'dbo.inv_documento_enc'))
CREATE INDEX [IX_inv_documento_enc_mon_id] ON [dbo].[inv_documento_enc]([mon_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_documento_enc_usu_id_creacion' AND object_id = OBJECT_ID(N'dbo.inv_documento_enc'))
CREATE INDEX [IX_inv_documento_enc_usu_id_creacion] ON [dbo].[inv_documento_enc]([usu_id_creacion]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_documento_enc_enc_id_referencia' AND object_id = OBJECT_ID(N'dbo.inv_documento_enc'))
CREATE INDEX [IX_inv_documento_enc_enc_id_referencia] ON [dbo].[inv_documento_enc]([enc_id_referencia]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_documento_enc_fecha_docto' AND object_id = OBJECT_ID(N'dbo.inv_documento_enc'))
CREATE INDEX [IX_inv_documento_enc_fecha_docto] ON [dbo].[inv_documento_enc]([enc_fecha_docto]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_documento_det_bod_id' AND object_id = OBJECT_ID(N'dbo.inv_documento_det'))
CREATE INDEX [IX_inv_documento_det_bod_id] ON [dbo].[inv_documento_det]([bod_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_documento_det_pro_id' AND object_id = OBJECT_ID(N'dbo.inv_documento_det'))
CREATE INDEX [IX_inv_documento_det_pro_id] ON [dbo].[inv_documento_det]([pro_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inv_documento_det_ppr_id' AND object_id = OBJECT_ID(N'dbo.inv_documento_det'))
CREATE INDEX [IX_inv_documento_det_ppr_id] ON [dbo].[inv_documento_det]([ppr_id]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_bco_cuenta_bancaria_gef_id' AND object_id = OBJECT_ID(N'dbo.bco_cuenta_bancaria'))
CREATE INDEX [IX_bco_cuenta_bancaria_gef_id] ON [dbo].[bco_cuenta_bancaria]([gef_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_bco_chequera_bcb_id' AND object_id = OBJECT_ID(N'dbo.bco_cuenta_bancaria_chequera'))
CREATE INDEX [IX_bco_chequera_bcb_id] ON [dbo].[bco_cuenta_bancaria_chequera]([bcb_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_bco_cheque_enc_usu_id' AND object_id = OBJECT_ID(N'dbo.bco_cheque_emitido_enc'))
CREATE INDEX [IX_bco_cheque_enc_usu_id] ON [dbo].[bco_cheque_emitido_enc]([usu_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_bco_cheque_enc_bmp_id' AND object_id = OBJECT_ID(N'dbo.bco_cheque_emitido_enc'))
CREATE INDEX [IX_bco_cheque_enc_bmp_id] ON [dbo].[bco_cheque_emitido_enc]([bmp_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_bco_cheque_det_bce_id' AND object_id = OBJECT_ID(N'dbo.bco_cheque_emitido_det'))
CREATE INDEX [IX_bco_cheque_det_bce_id] ON [dbo].[bco_cheque_emitido_det]([bce_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_bco_cheque_det_bmp_id' AND object_id = OBJECT_ID(N'dbo.bco_cheque_emitido_det'))
CREATE INDEX [IX_bco_cheque_det_bmp_id] ON [dbo].[bco_cheque_emitido_det]([bmp_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_bco_cheque_det_enc_id' AND object_id = OBJECT_ID(N'dbo.bco_cheque_emitido_det'))
CREATE INDEX [IX_bco_cheque_det_enc_id] ON [dbo].[bco_cheque_emitido_det]([enc_id]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_caja_apertura_pcr_id' AND object_id = OBJECT_ID(N'dbo.pos_caja_apertura'))
CREATE INDEX [IX_pos_caja_apertura_pcr_id] ON [dbo].[pos_caja_apertura]([pcr_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_caja_apertura_usu_id_apertura' AND object_id = OBJECT_ID(N'dbo.pos_caja_apertura'))
CREATE INDEX [IX_pos_caja_apertura_usu_id_apertura] ON [dbo].[pos_caja_apertura]([usu_id_apertura]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_caja_apertura_usu_id_cierre' AND object_id = OBJECT_ID(N'dbo.pos_caja_apertura'))
CREATE INDEX [IX_pos_caja_apertura_usu_id_cierre] ON [dbo].[pos_caja_apertura]([usu_id_cierre]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_caja_desglose_efectivo_pca_id' AND object_id = OBJECT_ID(N'dbo.pos_caja_desglose_efectivo'))
CREATE INDEX [IX_pos_caja_desglose_efectivo_pca_id] ON [dbo].[pos_caja_desglose_efectivo]([pca_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_caja_deposito_pca_id' AND object_id = OBJECT_ID(N'dbo.pos_caja_deposito'))
CREATE INDEX [IX_pos_caja_deposito_pca_id] ON [dbo].[pos_caja_deposito]([pca_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_caja_deposito_gef_id' AND object_id = OBJECT_ID(N'dbo.pos_caja_deposito'))
CREATE INDEX [IX_pos_caja_deposito_gef_id] ON [dbo].[pos_caja_deposito]([gef_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_caja_receptora_suc_id' AND object_id = OBJECT_ID(N'dbo.pos_caja_receptora'))
CREATE INDEX [IX_pos_caja_receptora_suc_id] ON [dbo].[pos_caja_receptora]([suc_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_caja_corte_forma_pca_id' AND object_id = OBJECT_ID(N'dbo.pos_caja_corte_forma'))
CREATE INDEX [IX_pos_caja_corte_forma_pca_id] ON [dbo].[pos_caja_corte_forma]([pca_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_sec_usuario_sucursal_suc_id' AND object_id = OBJECT_ID(N'dbo.sec_usuario_sucursal'))
CREATE INDEX [IX_sec_usuario_sucursal_suc_id] ON [dbo].[sec_usuario_sucursal]([suc_id]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_cliente_dir_pais' AND object_id = OBJECT_ID(N'dbo.pos_cliente'))
CREATE INDEX [IX_pos_cliente_dir_pais] ON [dbo].[pos_cliente]([cli_direccion_pais]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_cliente_dir_estado' AND object_id = OBJECT_ID(N'dbo.pos_cliente'))
CREATE INDEX [IX_pos_cliente_dir_estado] ON [dbo].[pos_cliente]([cli_direccion_estado]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_cliente_dir_provincia' AND object_id = OBJECT_ID(N'dbo.pos_cliente'))
CREATE INDEX [IX_pos_cliente_dir_provincia] ON [dbo].[pos_cliente]([cli_direccion_provincia]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_cliente_nacionalidad' AND object_id = OBJECT_ID(N'dbo.pos_cliente'))
CREATE INDEX [IX_pos_cliente_nacionalidad] ON [dbo].[pos_cliente]([cli_nacionalidad]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_cliente_profesion' AND object_id = OBJECT_ID(N'dbo.pos_cliente'))
CREATE INDEX [IX_pos_cliente_profesion] ON [dbo].[pos_cliente]([cli_profesion]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_cliente_dpi_pais' AND object_id = OBJECT_ID(N'dbo.pos_cliente'))
CREATE INDEX [IX_pos_cliente_dpi_pais] ON [dbo].[pos_cliente]([cli_DPI_extendido_pais]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_cliente_dpi_estado' AND object_id = OBJECT_ID(N'dbo.pos_cliente'))
CREATE INDEX [IX_pos_cliente_dpi_estado] ON [dbo].[pos_cliente]([cli_DPI_extendido_estado]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_cliente_dpi_provincia' AND object_id = OBJECT_ID(N'dbo.pos_cliente'))
CREATE INDEX [IX_pos_cliente_dpi_provincia] ON [dbo].[pos_cliente]([cli_DPI_extendido_provincia]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_cliente_plan_pagos_cli_id' AND object_id = OBJECT_ID(N'dbo.pos_cliente_plan_pagos'))
CREATE INDEX [IX_pos_cliente_plan_pagos_cli_id] ON [dbo].[pos_cliente_plan_pagos]([cli_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_cliente_plan_pagos_tpa_id' AND object_id = OBJECT_ID(N'dbo.pos_cliente_plan_pagos'))
CREATE INDEX [IX_pos_cliente_plan_pagos_tpa_id] ON [dbo].[pos_cliente_plan_pagos]([tpa_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_pago_enc_cli_id' AND object_id = OBJECT_ID(N'dbo.pos_pago_enc'))
CREATE INDEX [IX_pos_pago_enc_cli_id] ON [dbo].[pos_pago_enc]([cli_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_pago_enc_pca_id' AND object_id = OBJECT_ID(N'dbo.pos_pago_enc'))
CREATE INDEX [IX_pos_pago_enc_pca_id] ON [dbo].[pos_pago_enc]([pca_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_pago_enc_usu_id' AND object_id = OBJECT_ID(N'dbo.pos_pago_enc'))
CREATE INDEX [IX_pos_pago_enc_usu_id] ON [dbo].[pos_pago_enc]([usu_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_pago_forma_gef_id' AND object_id = OBJECT_ID(N'dbo.pos_pago_forma'))
CREATE INDEX [IX_pos_pago_forma_gef_id] ON [dbo].[pos_pago_forma]([gef_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_pago_forma_pft_id' AND object_id = OBJECT_ID(N'dbo.pos_pago_forma'))
CREATE INDEX [IX_pos_pago_forma_pft_id] ON [dbo].[pos_pago_forma]([pft_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_pago_forma_ppe_id' AND object_id = OBJECT_ID(N'dbo.pos_pago_forma'))
CREATE INDEX [IX_pos_pago_forma_ppe_id] ON [dbo].[pos_pago_forma]([ppe_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_pago_det_cpp_id' AND object_id = OBJECT_ID(N'dbo.pos_pago_det'))
CREATE INDEX [IX_pos_pago_det_cpp_id] ON [dbo].[pos_pago_det]([cpp_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_pago_det_ppe_id' AND object_id = OBJECT_ID(N'dbo.pos_pago_det'))
CREATE INDEX [IX_pos_pago_det_ppe_id] ON [dbo].[pos_pago_det]([ppe_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pos_pago_det_enc_id' AND object_id = OBJECT_ID(N'dbo.pos_pago_det'))
CREATE INDEX [IX_pos_pago_det_enc_id] ON [dbo].[pos_pago_det]([enc_id]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cont_cuenta_contable_padre' AND object_id = OBJECT_ID(N'dbo.cont_cuenta_contable'))
CREATE INDEX [IX_cont_cuenta_contable_padre] ON [dbo].[cont_cuenta_contable]([cta_id_padre]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cont_asiento_enc_enc_id' AND object_id = OBJECT_ID(N'dbo.cont_asiento_enc'))
CREATE INDEX [IX_cont_asiento_enc_enc_id] ON [dbo].[cont_asiento_enc]([enc_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cont_asiento_enc_pdo_id' AND object_id = OBJECT_ID(N'dbo.cont_asiento_enc'))
CREATE INDEX [IX_cont_asiento_enc_pdo_id] ON [dbo].[cont_asiento_enc]([pdo_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cont_asiento_enc_usu_id' AND object_id = OBJECT_ID(N'dbo.cont_asiento_enc'))
CREATE INDEX [IX_cont_asiento_enc_usu_id] ON [dbo].[cont_asiento_enc]([usu_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cont_asiento_det_cta_id' AND object_id = OBJECT_ID(N'dbo.cont_asiento_det'))
CREATE INDEX [IX_cont_asiento_det_cta_id] ON [dbo].[cont_asiento_det]([cta_id]);
GO
