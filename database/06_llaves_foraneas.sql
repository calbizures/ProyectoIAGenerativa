/*
	Script 06: Llaves foráneas.

	Se agrupan todas al final (igual que en el script original) para no
	depender del orden de creación de las tablas. Todas quedan en
	NO ACTION (comportamiento por defecto): los borrados de catálogos con
	movimientos deben resolverse a nivel de aplicación desactivando el
	registro (estado='I') en vez de borrarlo físicamente.
*/
USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- gen_*
IF OBJECT_ID(N'dbo.FK_gen_estado_gen_pais', N'F') IS NULL
ALTER TABLE [dbo].[gen_estado]  ADD CONSTRAINT [FK_gen_estado_gen_pais] FOREIGN KEY([pai_id]) REFERENCES [dbo].[gen_pais]([pai_id]);
IF OBJECT_ID(N'dbo.FK_gen_provincia_gen_estado', N'F') IS NULL
ALTER TABLE [dbo].[gen_provincia]  ADD CONSTRAINT [FK_gen_provincia_gen_estado] FOREIGN KEY([est_id]) REFERENCES [dbo].[gen_estado]([est_id]);
IF OBJECT_ID(N'dbo.FK_gen_sucursal_gen_compania', N'F') IS NULL
ALTER TABLE [dbo].[gen_sucursal]  ADD CONSTRAINT [FK_gen_sucursal_gen_compania] FOREIGN KEY([cia_id]) REFERENCES [dbo].[gen_compania]([cia_id]);
IF OBJECT_ID(N'dbo.FK_gen_entidad_financiera_tipo', N'F') IS NULL
ALTER TABLE [dbo].[gen_entidad_financiera]  ADD CONSTRAINT [FK_gen_entidad_financiera_tipo] FOREIGN KEY([geft_id]) REFERENCES [dbo].[gen_entidad_financiera_tipo]([geft_id]);
IF OBJECT_ID(N'dbo.FK_gen_tipo_cambio_gen_moneda', N'F') IS NULL
ALTER TABLE [dbo].[gen_tipo_cambio]  ADD CONSTRAINT [FK_gen_tipo_cambio_gen_moneda] FOREIGN KEY([mon_id]) REFERENCES [dbo].[gen_moneda]([mon_id]);
IF OBJECT_ID(N'dbo.FK_gen_auditoria_gen_usuario', N'F') IS NULL
ALTER TABLE [dbo].[gen_auditoria]  ADD CONSTRAINT [FK_gen_auditoria_gen_usuario] FOREIGN KEY([usu_id]) REFERENCES [dbo].[gen_usuario]([usu_id]);
IF OBJECT_ID(N'dbo.FK_conf_correlativos_tipo_docto', N'F') IS NULL
ALTER TABLE [dbo].[conf_correlativos]  ADD CONSTRAINT [FK_conf_correlativos_tipo_docto] FOREIGN KEY([tdo_id]) REFERENCES [dbo].[inv_documento_tipo]([tdo_id]);
GO

-- sec_*
IF OBJECT_ID(N'dbo.FK_sec_rol_permiso_rol', N'F') IS NULL
ALTER TABLE [dbo].[sec_rol_permiso]  ADD CONSTRAINT [FK_sec_rol_permiso_rol] FOREIGN KEY([rol_id]) REFERENCES [dbo].[sec_rol]([rol_id]);
IF OBJECT_ID(N'dbo.FK_sec_rol_permiso_permiso', N'F') IS NULL
ALTER TABLE [dbo].[sec_rol_permiso]  ADD CONSTRAINT [FK_sec_rol_permiso_permiso] FOREIGN KEY([per_id]) REFERENCES [dbo].[sec_permiso]([per_id]);
IF OBJECT_ID(N'dbo.FK_sec_usuario_rol_usuario', N'F') IS NULL
ALTER TABLE [dbo].[sec_usuario_rol]  ADD CONSTRAINT [FK_sec_usuario_rol_usuario] FOREIGN KEY([usu_id]) REFERENCES [dbo].[gen_usuario]([usu_id]);
IF OBJECT_ID(N'dbo.FK_sec_usuario_rol_rol', N'F') IS NULL
ALTER TABLE [dbo].[sec_usuario_rol]  ADD CONSTRAINT [FK_sec_usuario_rol_rol] FOREIGN KEY([rol_id]) REFERENCES [dbo].[sec_rol]([rol_id]);
GO

-- inv_* (catálogo de producto)
IF OBJECT_ID(N'dbo.FK_inv_producto_tipo', N'F') IS NULL
ALTER TABLE [dbo].[inv_producto]  ADD CONSTRAINT [FK_inv_producto_tipo] FOREIGN KEY([prt_id]) REFERENCES [dbo].[inv_producto_tipo]([prt_id]);
IF OBJECT_ID(N'dbo.FK_inv_producto_padre', N'F') IS NULL
ALTER TABLE [dbo].[inv_producto]  ADD CONSTRAINT [FK_inv_producto_padre] FOREIGN KEY([pro_id_padre]) REFERENCES [dbo].[inv_producto]([pro_id]);
IF OBJECT_ID(N'dbo.FK_inv_producto_caracteristica_producto', N'F') IS NULL
ALTER TABLE [dbo].[inv_producto_caracteristica]  ADD CONSTRAINT [FK_inv_producto_caracteristica_producto] FOREIGN KEY([pro_id]) REFERENCES [dbo].[inv_producto]([pro_id]);
IF OBJECT_ID(N'dbo.FK_inv_producto_caracteristica_tipo', N'F') IS NULL
ALTER TABLE [dbo].[inv_producto_caracteristica]  ADD CONSTRAINT [FK_inv_producto_caracteristica_tipo] FOREIGN KEY([ptc_id]) REFERENCES [dbo].[inv_producto_tipo_caracteristica]([ptc_id]);
IF OBJECT_ID(N'dbo.FK_inv_producto_precio_producto', N'F') IS NULL
ALTER TABLE [dbo].[inv_producto_precio]  ADD CONSTRAINT [FK_inv_producto_precio_producto] FOREIGN KEY([pro_id]) REFERENCES [dbo].[inv_producto]([pro_id]);
IF OBJECT_ID(N'dbo.FK_inv_producto_precio_bodega', N'F') IS NULL
ALTER TABLE [dbo].[inv_producto_precio]  ADD CONSTRAINT [FK_inv_producto_precio_bodega] FOREIGN KEY([bod_id]) REFERENCES [dbo].[inv_bodega]([bod_id]);
IF OBJECT_ID(N'dbo.FK_inv_producto_precio_moneda', N'F') IS NULL
ALTER TABLE [dbo].[inv_producto_precio]  ADD CONSTRAINT [FK_inv_producto_precio_moneda] FOREIGN KEY([mon_id]) REFERENCES [dbo].[gen_moneda]([mon_id]);
IF OBJECT_ID(N'dbo.FK_inv_prod_exist_bodega', N'F') IS NULL
ALTER TABLE [dbo].[inv_producto_existencia_bodega]  ADD CONSTRAINT [FK_inv_prod_exist_bodega] FOREIGN KEY([bod_id]) REFERENCES [dbo].[inv_bodega]([bod_id]);
IF OBJECT_ID(N'dbo.FK_inv_prod_exist_producto', N'F') IS NULL
ALTER TABLE [dbo].[inv_producto_existencia_bodega]  ADD CONSTRAINT [FK_inv_prod_exist_producto] FOREIGN KEY([pro_id]) REFERENCES [dbo].[inv_producto]([pro_id]);
IF OBJECT_ID(N'dbo.FK_inv_bodega_sucursal', N'F') IS NULL
ALTER TABLE [dbo].[inv_bodega]  ADD CONSTRAINT [FK_inv_bodega_sucursal] FOREIGN KEY([suc_id]) REFERENCES [dbo].[gen_sucursal]([suc_id]);
GO

-- inv_* (proveedores)
IF OBJECT_ID(N'dbo.FK_inv_proveedor_plan_pago_documento', N'F') IS NULL
ALTER TABLE [dbo].[inv_proveedor_plan_pago]  ADD CONSTRAINT [FK_inv_proveedor_plan_pago_documento] FOREIGN KEY([enc_id]) REFERENCES [dbo].[inv_documento_enc]([enc_id]);
IF OBJECT_ID(N'dbo.FK_inv_proveedor_plan_pago_proveedor', N'F') IS NULL
ALTER TABLE [dbo].[inv_proveedor_plan_pago]  ADD CONSTRAINT [FK_inv_proveedor_plan_pago_proveedor] FOREIGN KEY([prv_id]) REFERENCES [dbo].[inv_proveedor]([prv_id]);
IF OBJECT_ID(N'dbo.FK_inv_proveedor_plan_pago_chequera', N'F') IS NULL
ALTER TABLE [dbo].[inv_proveedor_plan_pago]  ADD CONSTRAINT [FK_inv_proveedor_plan_pago_chequera] FOREIGN KEY([cbc_id]) REFERENCES [dbo].[bco_cuenta_bancaria_chequera]([cbc_id]);
IF OBJECT_ID(N'dbo.FK_inv_producto_proveedor_producto', N'F') IS NULL
ALTER TABLE [dbo].[inv_producto_proveedor]  ADD CONSTRAINT [FK_inv_producto_proveedor_producto] FOREIGN KEY([pro_id]) REFERENCES [dbo].[inv_producto]([pro_id]);
IF OBJECT_ID(N'dbo.FK_inv_producto_proveedor_proveedor', N'F') IS NULL
ALTER TABLE [dbo].[inv_producto_proveedor]  ADD CONSTRAINT [FK_inv_producto_proveedor_proveedor] FOREIGN KEY([prv_id]) REFERENCES [dbo].[inv_proveedor]([prv_id]);
GO

-- inv_documento_enc / inv_documento_det
IF OBJECT_ID(N'dbo.FK_inv_documento_enc_cliente', N'F') IS NULL
ALTER TABLE [dbo].[inv_documento_enc]  ADD CONSTRAINT [FK_inv_documento_enc_cliente] FOREIGN KEY([cli_id]) REFERENCES [dbo].[pos_cliente]([cli_id]);
IF OBJECT_ID(N'dbo.FK_inv_documento_enc_proveedor', N'F') IS NULL
ALTER TABLE [dbo].[inv_documento_enc]  ADD CONSTRAINT [FK_inv_documento_enc_proveedor] FOREIGN KEY([prv_id]) REFERENCES [dbo].[inv_proveedor]([prv_id]);
IF OBJECT_ID(N'dbo.FK_inv_documento_enc_tipo', N'F') IS NULL
ALTER TABLE [dbo].[inv_documento_enc]  ADD CONSTRAINT [FK_inv_documento_enc_tipo] FOREIGN KEY([tdo_id]) REFERENCES [dbo].[inv_documento_tipo]([tdo_id]);
IF OBJECT_ID(N'dbo.FK_inv_documento_enc_vendedor', N'F') IS NULL
ALTER TABLE [dbo].[inv_documento_enc]  ADD CONSTRAINT [FK_inv_documento_enc_vendedor] FOREIGN KEY([pve_id]) REFERENCES [dbo].[pos_vendedor]([pve_id]);
IF OBJECT_ID(N'dbo.FK_inv_documento_enc_entidad_financiera', N'F') IS NULL
ALTER TABLE [dbo].[inv_documento_enc]  ADD CONSTRAINT [FK_inv_documento_enc_entidad_financiera] FOREIGN KEY([gef_id]) REFERENCES [dbo].[gen_entidad_financiera]([gef_id]);
IF OBJECT_ID(N'dbo.FK_inv_documento_enc_moneda', N'F') IS NULL
ALTER TABLE [dbo].[inv_documento_enc]  ADD CONSTRAINT [FK_inv_documento_enc_moneda] FOREIGN KEY([mon_id]) REFERENCES [dbo].[gen_moneda]([mon_id]);
IF OBJECT_ID(N'dbo.FK_inv_documento_enc_usuario', N'F') IS NULL
ALTER TABLE [dbo].[inv_documento_enc]  ADD CONSTRAINT [FK_inv_documento_enc_usuario] FOREIGN KEY([usu_id_creacion]) REFERENCES [dbo].[gen_usuario]([usu_id]);
IF OBJECT_ID(N'dbo.FK_inv_documento_enc_referencia', N'F') IS NULL
ALTER TABLE [dbo].[inv_documento_enc]  ADD CONSTRAINT [FK_inv_documento_enc_referencia] FOREIGN KEY([enc_id_referencia]) REFERENCES [dbo].[inv_documento_enc]([enc_id]);
IF OBJECT_ID(N'dbo.FK_inv_documento_det_encabezado', N'F') IS NULL
ALTER TABLE [dbo].[inv_documento_det]  ADD CONSTRAINT [FK_inv_documento_det_encabezado] FOREIGN KEY([enc_id]) REFERENCES [dbo].[inv_documento_enc]([enc_id]);
IF OBJECT_ID(N'dbo.FK_inv_documento_det_bodega', N'F') IS NULL
ALTER TABLE [dbo].[inv_documento_det]  ADD CONSTRAINT [FK_inv_documento_det_bodega] FOREIGN KEY([bod_id]) REFERENCES [dbo].[inv_bodega]([bod_id]);
IF OBJECT_ID(N'dbo.FK_inv_documento_det_producto', N'F') IS NULL
ALTER TABLE [dbo].[inv_documento_det]  ADD CONSTRAINT [FK_inv_documento_det_producto] FOREIGN KEY([pro_id]) REFERENCES [dbo].[inv_producto]([pro_id]);
IF OBJECT_ID(N'dbo.FK_inv_documento_det_precio', N'F') IS NULL
ALTER TABLE [dbo].[inv_documento_det]  ADD CONSTRAINT [FK_inv_documento_det_precio] FOREIGN KEY([ppr_id]) REFERENCES [dbo].[inv_producto_precio]([ppr_id]);
GO

-- bco_*
IF OBJECT_ID(N'dbo.FK_bco_cuenta_bancaria_entidad', N'F') IS NULL
ALTER TABLE [dbo].[bco_cuenta_bancaria]  ADD CONSTRAINT [FK_bco_cuenta_bancaria_entidad] FOREIGN KEY([gef_id]) REFERENCES [dbo].[gen_entidad_financiera]([gef_id]);
IF OBJECT_ID(N'dbo.FK_bco_chequera_cuenta', N'F') IS NULL
ALTER TABLE [dbo].[bco_cuenta_bancaria_chequera]  ADD CONSTRAINT [FK_bco_chequera_cuenta] FOREIGN KEY([bcb_id]) REFERENCES [dbo].[bco_cuenta_bancaria]([bcb_id]);
IF OBJECT_ID(N'dbo.FK_bco_cheque_enc_chequera', N'F') IS NULL
ALTER TABLE [dbo].[bco_cheque_emitido_enc]  ADD CONSTRAINT [FK_bco_cheque_enc_chequera] FOREIGN KEY([cbc_id]) REFERENCES [dbo].[bco_cuenta_bancaria_chequera]([cbc_id]);
IF OBJECT_ID(N'dbo.FK_bco_cheque_enc_usuario', N'F') IS NULL
ALTER TABLE [dbo].[bco_cheque_emitido_enc]  ADD CONSTRAINT [FK_bco_cheque_enc_usuario] FOREIGN KEY([usu_id]) REFERENCES [dbo].[gen_usuario]([usu_id]);
IF OBJECT_ID(N'dbo.FK_bco_cheque_enc_motivo', N'F') IS NULL
ALTER TABLE [dbo].[bco_cheque_emitido_enc]  ADD CONSTRAINT [FK_bco_cheque_enc_motivo] FOREIGN KEY([bmp_id]) REFERENCES [dbo].[bco_motivo_pago]([bmp_id]);
IF OBJECT_ID(N'dbo.FK_bco_cheque_det_encabezado', N'F') IS NULL
ALTER TABLE [dbo].[bco_cheque_emitido_det]  ADD CONSTRAINT [FK_bco_cheque_det_encabezado] FOREIGN KEY([bce_id]) REFERENCES [dbo].[bco_cheque_emitido_enc]([bce_id]);
IF OBJECT_ID(N'dbo.FK_bco_cheque_det_motivo', N'F') IS NULL
ALTER TABLE [dbo].[bco_cheque_emitido_det]  ADD CONSTRAINT [FK_bco_cheque_det_motivo] FOREIGN KEY([bmp_id]) REFERENCES [dbo].[bco_motivo_pago]([bmp_id]);
IF OBJECT_ID(N'dbo.FK_bco_cheque_det_documento', N'F') IS NULL
ALTER TABLE [dbo].[bco_cheque_emitido_det]  ADD CONSTRAINT [FK_bco_cheque_det_documento] FOREIGN KEY([enc_id]) REFERENCES [dbo].[inv_documento_enc]([enc_id]);
GO

-- pos_* (caja)
IF OBJECT_ID(N'dbo.FK_pos_caja_receptora_sucursal', N'F') IS NULL
ALTER TABLE [dbo].[pos_caja_receptora]  ADD CONSTRAINT [FK_pos_caja_receptora_sucursal] FOREIGN KEY([suc_id]) REFERENCES [dbo].[gen_sucursal]([suc_id]);
IF OBJECT_ID(N'dbo.FK_pos_caja_apertura_receptora', N'F') IS NULL
ALTER TABLE [dbo].[pos_caja_apertura]  ADD CONSTRAINT [FK_pos_caja_apertura_receptora] FOREIGN KEY([pcr_id]) REFERENCES [dbo].[pos_caja_receptora]([pcr_id]);
IF OBJECT_ID(N'dbo.FK_pos_caja_apertura_usu_apertura', N'F') IS NULL
ALTER TABLE [dbo].[pos_caja_apertura]  ADD CONSTRAINT [FK_pos_caja_apertura_usu_apertura] FOREIGN KEY([usu_id_apertura]) REFERENCES [dbo].[gen_usuario]([usu_id]);
IF OBJECT_ID(N'dbo.FK_pos_caja_apertura_usu_cierre', N'F') IS NULL
ALTER TABLE [dbo].[pos_caja_apertura]  ADD CONSTRAINT [FK_pos_caja_apertura_usu_cierre] FOREIGN KEY([usu_id_cierre]) REFERENCES [dbo].[gen_usuario]([usu_id]);
IF OBJECT_ID(N'dbo.FK_pos_desglose_caja', N'F') IS NULL
ALTER TABLE [dbo].[pos_caja_desglose_efectivo]  ADD CONSTRAINT [FK_pos_desglose_caja] FOREIGN KEY([pca_id]) REFERENCES [dbo].[pos_caja_apertura]([pca_id]);
IF OBJECT_ID(N'dbo.FK_pos_deposito_caja', N'F') IS NULL
ALTER TABLE [dbo].[pos_caja_deposito]  ADD CONSTRAINT [FK_pos_deposito_caja] FOREIGN KEY([pca_id]) REFERENCES [dbo].[pos_caja_apertura]([pca_id]);
IF OBJECT_ID(N'dbo.FK_pos_caja_deposito_entidad', N'F') IS NULL
ALTER TABLE [dbo].[pos_caja_deposito]  ADD CONSTRAINT [FK_pos_caja_deposito_entidad] FOREIGN KEY([gef_id]) REFERENCES [dbo].[gen_entidad_financiera]([gef_id]);
IF OBJECT_ID(N'dbo.FK_pos_caja_corte_forma_apertura', N'F') IS NULL
ALTER TABLE [dbo].[pos_caja_corte_forma]  ADD CONSTRAINT [FK_pos_caja_corte_forma_apertura] FOREIGN KEY([pca_id]) REFERENCES [dbo].[pos_caja_apertura]([pca_id]);
IF OBJECT_ID(N'dbo.FK_pos_caja_corte_forma_tipo', N'F') IS NULL
ALTER TABLE [dbo].[pos_caja_corte_forma]  ADD CONSTRAINT [FK_pos_caja_corte_forma_tipo] FOREIGN KEY([pft_id]) REFERENCES [dbo].[pos_pago_forma_tipo]([pft_id]);
GO

-- sec_usuario_sucursal
IF OBJECT_ID(N'dbo.FK_sec_usuario_sucursal_usuario', N'F') IS NULL
ALTER TABLE [dbo].[sec_usuario_sucursal]  ADD CONSTRAINT [FK_sec_usuario_sucursal_usuario] FOREIGN KEY([usu_id]) REFERENCES [dbo].[gen_usuario]([usu_id]);
IF OBJECT_ID(N'dbo.FK_sec_usuario_sucursal_sucursal', N'F') IS NULL
ALTER TABLE [dbo].[sec_usuario_sucursal]  ADD CONSTRAINT [FK_sec_usuario_sucursal_sucursal] FOREIGN KEY([suc_id]) REFERENCES [dbo].[gen_sucursal]([suc_id]);
GO

-- pos_cliente (geografía)
IF OBJECT_ID(N'dbo.FK_pos_cliente_dir_pais', N'F') IS NULL
ALTER TABLE [dbo].[pos_cliente]  ADD CONSTRAINT [FK_pos_cliente_dir_pais] FOREIGN KEY([cli_direccion_pais]) REFERENCES [dbo].[gen_pais]([pai_id]);
IF OBJECT_ID(N'dbo.FK_pos_cliente_dir_estado', N'F') IS NULL
ALTER TABLE [dbo].[pos_cliente]  ADD CONSTRAINT [FK_pos_cliente_dir_estado] FOREIGN KEY([cli_direccion_estado]) REFERENCES [dbo].[gen_estado]([est_id]);
IF OBJECT_ID(N'dbo.FK_pos_cliente_dir_provincia', N'F') IS NULL
ALTER TABLE [dbo].[pos_cliente]  ADD CONSTRAINT [FK_pos_cliente_dir_provincia] FOREIGN KEY([cli_direccion_provincia]) REFERENCES [dbo].[gen_provincia]([prov_id]);
IF OBJECT_ID(N'dbo.FK_pos_cliente_nacionalidad', N'F') IS NULL
ALTER TABLE [dbo].[pos_cliente]  ADD CONSTRAINT [FK_pos_cliente_nacionalidad] FOREIGN KEY([cli_nacionalidad]) REFERENCES [dbo].[gen_pais]([pai_id]);
IF OBJECT_ID(N'dbo.FK_pos_cliente_profesion', N'F') IS NULL
ALTER TABLE [dbo].[pos_cliente]  ADD CONSTRAINT [FK_pos_cliente_profesion] FOREIGN KEY([cli_profesion]) REFERENCES [dbo].[gen_profesion]([prf_id]);
IF OBJECT_ID(N'dbo.FK_pos_cliente_dpi_pais', N'F') IS NULL
ALTER TABLE [dbo].[pos_cliente]  ADD CONSTRAINT [FK_pos_cliente_dpi_pais] FOREIGN KEY([cli_DPI_extendido_pais]) REFERENCES [dbo].[gen_pais]([pai_id]);
IF OBJECT_ID(N'dbo.FK_pos_cliente_dpi_estado', N'F') IS NULL
ALTER TABLE [dbo].[pos_cliente]  ADD CONSTRAINT [FK_pos_cliente_dpi_estado] FOREIGN KEY([cli_DPI_extendido_estado]) REFERENCES [dbo].[gen_estado]([est_id]);
IF OBJECT_ID(N'dbo.FK_pos_cliente_dpi_provincia', N'F') IS NULL
ALTER TABLE [dbo].[pos_cliente]  ADD CONSTRAINT [FK_pos_cliente_dpi_provincia] FOREIGN KEY([cli_DPI_extendido_provincia]) REFERENCES [dbo].[gen_provincia]([prov_id]);
GO

-- pos_* (planes de pago / pagos)
IF OBJECT_ID(N'dbo.FK_pos_cliente_plan_pagos_cliente', N'F') IS NULL
ALTER TABLE [dbo].[pos_cliente_plan_pagos]  ADD CONSTRAINT [FK_pos_cliente_plan_pagos_cliente] FOREIGN KEY([cli_id]) REFERENCES [dbo].[pos_cliente]([cli_id]);
IF OBJECT_ID(N'dbo.FK_pos_cliente_plan_pagos_documento', N'F') IS NULL
ALTER TABLE [dbo].[pos_cliente_plan_pagos]  ADD CONSTRAINT [FK_pos_cliente_plan_pagos_documento] FOREIGN KEY([enc_id]) REFERENCES [dbo].[inv_documento_enc]([enc_id]);
IF OBJECT_ID(N'dbo.FK_pos_cliente_plan_pagos_tipo', N'F') IS NULL
ALTER TABLE [dbo].[pos_cliente_plan_pagos]  ADD CONSTRAINT [FK_pos_cliente_plan_pagos_tipo] FOREIGN KEY([tpa_id]) REFERENCES [dbo].[pos_cliente_tipo_pago]([tpa_id]);
IF OBJECT_ID(N'dbo.FK_pos_pago_enc_cliente', N'F') IS NULL
ALTER TABLE [dbo].[pos_pago_enc]  ADD CONSTRAINT [FK_pos_pago_enc_cliente] FOREIGN KEY([cli_id]) REFERENCES [dbo].[pos_cliente]([cli_id]);
IF OBJECT_ID(N'dbo.FK_pos_pago_enc_caja', N'F') IS NULL
ALTER TABLE [dbo].[pos_pago_enc]  ADD CONSTRAINT [FK_pos_pago_enc_caja] FOREIGN KEY([pca_id]) REFERENCES [dbo].[pos_caja_apertura]([pca_id]);
IF OBJECT_ID(N'dbo.FK_pos_pago_enc_usuario', N'F') IS NULL
ALTER TABLE [dbo].[pos_pago_enc]  ADD CONSTRAINT [FK_pos_pago_enc_usuario] FOREIGN KEY([usu_id]) REFERENCES [dbo].[gen_usuario]([usu_id]);
IF OBJECT_ID(N'dbo.FK_pos_pago_forma_entidad', N'F') IS NULL
ALTER TABLE [dbo].[pos_pago_forma]  ADD CONSTRAINT [FK_pos_pago_forma_entidad] FOREIGN KEY([gef_id]) REFERENCES [dbo].[gen_entidad_financiera]([gef_id]);
IF OBJECT_ID(N'dbo.FK_pos_pago_forma_tipo', N'F') IS NULL
ALTER TABLE [dbo].[pos_pago_forma]  ADD CONSTRAINT [FK_pos_pago_forma_tipo] FOREIGN KEY([pft_id]) REFERENCES [dbo].[pos_pago_forma_tipo]([pft_id]);
IF OBJECT_ID(N'dbo.FK_pos_pago_forma_pago_enc', N'F') IS NULL
ALTER TABLE [dbo].[pos_pago_forma]  ADD CONSTRAINT [FK_pos_pago_forma_pago_enc] FOREIGN KEY([ppe_id]) REFERENCES [dbo].[pos_pago_enc]([ppe_id]);
IF OBJECT_ID(N'dbo.FK_pos_pago_det_cuota', N'F') IS NULL
ALTER TABLE [dbo].[pos_pago_det]  ADD CONSTRAINT [FK_pos_pago_det_cuota] FOREIGN KEY([cpp_id]) REFERENCES [dbo].[pos_cliente_plan_pagos]([cpp_id]);
IF OBJECT_ID(N'dbo.FK_pos_pago_det_pago_enc', N'F') IS NULL
ALTER TABLE [dbo].[pos_pago_det]  ADD CONSTRAINT [FK_pos_pago_det_pago_enc] FOREIGN KEY([ppe_id]) REFERENCES [dbo].[pos_pago_enc]([ppe_id]);
IF OBJECT_ID(N'dbo.FK_pos_pago_det_documento', N'F') IS NULL
ALTER TABLE [dbo].[pos_pago_det]  ADD CONSTRAINT [FK_pos_pago_det_documento] FOREIGN KEY([enc_id]) REFERENCES [dbo].[inv_documento_enc]([enc_id]);
GO

-- cont_*
IF OBJECT_ID(N'dbo.FK_cont_asiento_enc_documento', N'F') IS NULL
ALTER TABLE [dbo].[cont_asiento_enc]  ADD CONSTRAINT [FK_cont_asiento_enc_documento] FOREIGN KEY([enc_id]) REFERENCES [dbo].[inv_documento_enc]([enc_id]);
IF OBJECT_ID(N'dbo.FK_cont_asiento_enc_periodo', N'F') IS NULL
ALTER TABLE [dbo].[cont_asiento_enc]  ADD CONSTRAINT [FK_cont_asiento_enc_periodo] FOREIGN KEY([pdo_id]) REFERENCES [dbo].[cont_periodo_contable]([pdo_id]);
IF OBJECT_ID(N'dbo.FK_cont_asiento_enc_usuario', N'F') IS NULL
ALTER TABLE [dbo].[cont_asiento_enc]  ADD CONSTRAINT [FK_cont_asiento_enc_usuario] FOREIGN KEY([usu_id]) REFERENCES [dbo].[gen_usuario]([usu_id]);
IF OBJECT_ID(N'dbo.FK_cont_asiento_det_encabezado', N'F') IS NULL
ALTER TABLE [dbo].[cont_asiento_det]  ADD CONSTRAINT [FK_cont_asiento_det_encabezado] FOREIGN KEY([asi_id]) REFERENCES [dbo].[cont_asiento_enc]([asi_id]);
IF OBJECT_ID(N'dbo.FK_cont_asiento_det_cuenta', N'F') IS NULL
ALTER TABLE [dbo].[cont_asiento_det]  ADD CONSTRAINT [FK_cont_asiento_det_cuenta] FOREIGN KEY([cta_id]) REFERENCES [dbo].[cont_cuenta_contable]([cta_id]);
GO

------------------------------------------------------------
-- Auditoría: InsUsuario / UpdUsuario -> gen_usuario
--
-- Todas las tablas de 02-05 (excepto [gen_auditoria], que no lleva estas
-- columnas: ver su comentario en 02_tablas_generales_seguridad.sql) tienen
-- [InsUsuario] y [UpdUsuario]. En vez de repetir a mano más de cien
-- ALTER TABLE, se generan por SQL dinámico recorriendo el catálogo del
-- sistema: para cada columna llamada InsUsuario/UpdUsuario que todavía no
-- tenga llave foránea, crea una hacia [gen_usuario]([usu_id]).
------------------------------------------------------------
DECLARE @sql_auditoria NVARCHAR(MAX) = N'';

SELECT @sql_auditoria = @sql_auditoria + N'
ALTER TABLE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name)
	+ N' ADD CONSTRAINT ' + QUOTENAME(N'FK_' + t.name + N'_' + c.name)
	+ N' FOREIGN KEY (' + QUOTENAME(c.name) + N') REFERENCES [dbo].[gen_usuario]([usu_id]);'
FROM sys.columns c
INNER JOIN sys.tables t ON t.object_id = c.object_id
INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = N'dbo'
  AND c.name IN (N'InsUsuario', N'UpdUsuario')
  AND NOT EXISTS (
		SELECT 1
		FROM sys.foreign_key_columns fkc
		WHERE fkc.parent_object_id = c.object_id
		  AND fkc.parent_column_id = c.column_id
	  );

EXEC sp_executesql @sql_auditoria;
GO
