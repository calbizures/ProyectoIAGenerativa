/*
================================================================================
 instalar_01_al_71.sql
 Corre en orden todos los scripts del 01 al 71 sobre la base erp_db, que debe
 existir ya (créela antes con 00_crear_base_datos.sql).

 Es un script en MODO SQLCMD: incluye cada archivo con :r.

 Uso en SQL Server Management Studio (SSMS):
   1. Abra este archivo.
   2. Menú Consulta (Query) > Modo SQLCMD (SQLCMD Mode).
   3. Cambie la ruta de la línea :setvar RUTA por la carpeta donde están los
      scripts, terminada en barra invertida.
   4. Ejecute (F5).

 Uso desde la línea de comandos (desde la carpeta database, con la ruta ya
 cambiada o con la carpeta actual):
   sqlcmd -S <servidor> -E -f 65001 -i instalar_01_al_71.sql -o instalacion.log
   (-E = autenticación de Windows; con usuario SQL use -U sa -P <clave>.
    -f 65001 lee los archivos como UTF-8 para que los acentos queden bien.)

 Se detiene en el primer error (:on error exit) y muestra el script que lo
 produjo. Cada script se puede volver a correr, así que, corregida la causa,
 basta con ejecutar este archivo de nuevo.

 Importante: incluye los datos de prueba (12, 30, 33, 37, 39, 41, 43 y 46) y el
 12 VACÍA todas las tablas. No lo use sobre una base con datos reales; para
 actualizar una base existente corra solo los scripts nuevos.
================================================================================
*/
:setvar RUTA "C:\ProyectoIAGenerativa\database\"
:on error exit
SET NOCOUNT ON;
GO
IF DB_ID('erp_db') IS NULL
    RAISERROR('La base erp_db no existe: córrala primero con 00_crear_base_datos.sql.', 16, 1);
GO

PRINT '--- 01_tipos_tabla.sql';
GO
:r $(RUTA)01_tipos_tabla.sql
GO

PRINT '--- 02_tablas_generales_seguridad.sql';
GO
:r $(RUTA)02_tablas_generales_seguridad.sql
GO

PRINT '--- 03_tablas_inventario.sql';
GO
:r $(RUTA)03_tablas_inventario.sql
GO

PRINT '--- 04_tablas_pos_bancos.sql';
GO
:r $(RUTA)04_tablas_pos_bancos.sql
GO

PRINT '--- 05_tablas_contabilidad.sql';
GO
:r $(RUTA)05_tablas_contabilidad.sql
GO

PRINT '--- 06_llaves_foraneas.sql';
GO
:r $(RUTA)06_llaves_foraneas.sql
GO

PRINT '--- 07_indices_restricciones.sql';
GO
:r $(RUTA)07_indices_restricciones.sql
GO

PRINT '--- 08_funciones.sql';
GO
:r $(RUTA)08_funciones.sql
GO

PRINT '--- 09_vistas.sql';
GO
:r $(RUTA)09_vistas.sql
GO

PRINT '--- 10_procedimientos_crud.sql';
GO
:r $(RUTA)10_procedimientos_crud.sql
GO

PRINT '--- 11_procedimientos_procesos.sql';
GO
:r $(RUTA)11_procedimientos_procesos.sql
GO

PRINT '--- 12_datos_sinteticos.sql';
GO
:r $(RUTA)12_datos_sinteticos.sql
GO

PRINT '--- 13_correccion_numero_unico.sql';
GO
:r $(RUTA)13_correccion_numero_unico.sql
GO

PRINT '--- 14_procedimientos_vendedor.sql';
GO
:r $(RUTA)14_procedimientos_vendedor.sql
GO

PRINT '--- 15_correccion_plan_pagos.sql';
GO
:r $(RUTA)15_correccion_plan_pagos.sql
GO

PRINT '--- 16_activar_usuario.sql';
GO
:r $(RUTA)16_activar_usuario.sql
GO

PRINT '--- 17_documento_consultar_codigo_cliente.sql';
GO
:r $(RUTA)17_documento_consultar_codigo_cliente.sql
GO

PRINT '--- 18_procedimientos_detalle_producto.sql';
GO
:r $(RUTA)18_procedimientos_detalle_producto.sql
GO

PRINT '--- 19_procedimientos_tipo_caracteristica.sql';
GO
:r $(RUTA)19_procedimientos_tipo_caracteristica.sql
GO

PRINT '--- 20_procedimiento_plan_pagos_consultar.sql';
GO
:r $(RUTA)20_procedimiento_plan_pagos_consultar.sql
GO

PRINT '--- 21_costo_unitario_ppr_id_factura.sql';
GO
:r $(RUTA)21_costo_unitario_ppr_id_factura.sql
GO

PRINT '--- 22_sucursal_caja_formas_pago_tablas.sql';
GO
:r $(RUTA)22_sucursal_caja_formas_pago_tablas.sql
GO

PRINT '--- 23_procedimientos_caja_sucursal.sql';
GO
:r $(RUTA)23_procedimientos_caja_sucursal.sql
GO

PRINT '--- 24_formas_pago_factura_cobro.sql';
GO
:r $(RUTA)24_formas_pago_factura_cobro.sql
GO

PRINT '--- 25_rrhh.sql';
GO
:r $(RUTA)25_rrhh.sql
GO

PRINT '--- 26_parametros_general_caja.sql';
GO
:r $(RUTA)26_parametros_general_caja.sql
GO

PRINT '--- 27_contabilidad_cuentas_parametro.sql';
GO
:r $(RUTA)27_contabilidad_cuentas_parametro.sql
GO

PRINT '--- 28_nomenclatura_contable.sql';
GO
:r $(RUTA)28_nomenclatura_contable.sql
GO

PRINT '--- 29_asientos_deposito_cierre_nomina.sql';
GO
:r $(RUTA)29_asientos_deposito_cierre_nomina.sql
GO

PRINT '--- 30_datos_sinteticos_procesos.sql';
GO
:r $(RUTA)30_datos_sinteticos_procesos.sql
GO

PRINT '--- 31_sucursales_unidades_organigrama.sql';
GO
:r $(RUTA)31_sucursales_unidades_organigrama.sql
GO

PRINT '--- 32_cuentas_por_cobrar_pagar.sql';
GO
:r $(RUTA)32_cuentas_por_cobrar_pagar.sql
GO

PRINT '--- 33_datos_sinteticos_cxc_organigrama.sql';
GO
:r $(RUTA)33_datos_sinteticos_cxc_organigrama.sql
GO

PRINT '--- 34_auditoria_procesos.sql';
GO
:r $(RUTA)34_auditoria_procesos.sql
GO

PRINT '--- 35_costos_fel_tableros.sql';
GO
:r $(RUTA)35_costos_fel_tableros.sql
GO

PRINT '--- 36_bancos_nomina_centro_costo.sql';
GO
:r $(RUTA)36_bancos_nomina_centro_costo.sql
GO

PRINT '--- 37_datos_sinteticos_bancos_nomina.sql';
GO
:r $(RUTA)37_datos_sinteticos_bancos_nomina.sql
GO

PRINT '--- 38_inventario_fisico_cargas_iniciales.sql';
GO
:r $(RUTA)38_inventario_fisico_cargas_iniciales.sql
GO

PRINT '--- 39_datos_sinteticos_inventario_saldos.sql';
GO
:r $(RUTA)39_datos_sinteticos_inventario_saldos.sql
GO

PRINT '--- 40_logo_cuentas_bancarias_productos_proveedor.sql';
GO
:r $(RUTA)40_logo_cuentas_bancarias_productos_proveedor.sql
GO

PRINT '--- 41_datos_sinteticos_productos_proveedor.sql';
GO
:r $(RUTA)41_datos_sinteticos_productos_proveedor.sql
GO

PRINT '--- 42_cxp_cheque_varias_cuotas.sql';
GO
:r $(RUTA)42_cxp_cheque_varias_cuotas.sql
GO

PRINT '--- 43_datos_sinteticos_cxp_pagos.sql';
GO
:r $(RUTA)43_datos_sinteticos_cxp_pagos.sql
GO

PRINT '--- 44_nit_certificadores_seguridad.sql';
GO
:r $(RUTA)44_nit_certificadores_seguridad.sql
GO

PRINT '--- 45_traslados_bodegas.sql';
GO
:r $(RUTA)45_traslados_bodegas.sql
GO

PRINT '--- 46_datos_sinteticos_traslados.sql';
GO
:r $(RUTA)46_datos_sinteticos_traslados.sql
GO

PRINT '--- 47_reparar_opciones_set.sql';
GO
:r $(RUTA)47_reparar_opciones_set.sql
GO

PRINT '--- 48_impresion_factura.sql';
GO
:r $(RUTA)48_impresion_factura.sql
GO

PRINT '--- 49_rrhh_libro_salarios_igss.sql';
GO
:r $(RUTA)49_rrhh_libro_salarios_igss.sql
GO

PRINT '--- 50_auditoria_robustez.sql';
GO
:r $(RUTA)50_auditoria_robustez.sql
GO

PRINT '--- 51_auditoria_saldos.sql';
GO
:r $(RUTA)51_auditoria_saldos.sql
GO

PRINT '--- 52_cotizaciones.sql';
GO
:r $(RUTA)52_cotizaciones.sql
GO

PRINT '--- 53_ordenes_compra.sql';
GO
:r $(RUTA)53_ordenes_compra.sql
GO

PRINT '--- 54_rotacion_reorden.sql';
GO
:r $(RUTA)54_rotacion_reorden.sql
GO

PRINT '--- 55_planilla_igss_archivo.sql';
GO
:r $(RUTA)55_planilla_igss_archivo.sql
GO

PRINT '--- 56_libro_salarios_otros_salarios.sql';
GO
:r $(RUTA)56_libro_salarios_otros_salarios.sql
GO

PRINT '--- 57_orden_compra_firmas.sql';
GO
:r $(RUTA)57_orden_compra_firmas.sql
GO

PRINT '--- 58_contrasenas_pago_transferencias.sql';
GO
:r $(RUTA)58_contrasenas_pago_transferencias.sql
GO

PRINT '--- 59_correo_estado_cuenta.sql';
GO
:r $(RUTA)59_correo_estado_cuenta.sql
GO

PRINT '--- 60_contabilidad_libros_estados.sql';
GO
:r $(RUTA)60_contabilidad_libros_estados.sql
GO

PRINT '--- 61_caja_chica.sql';
GO
:r $(RUTA)61_caja_chica.sql
GO

PRINT '--- 62_activos_fijos.sql';
GO
:r $(RUTA)62_activos_fijos.sql
GO

PRINT '--- 63_flujo_caja.sql';
GO
:r $(RUTA)63_flujo_caja.sql
GO

PRINT '--- 64_conciliacion_bancaria.sql';
GO
:r $(RUTA)64_conciliacion_bancaria.sql
GO

PRINT '--- 65_integridad_fase3.sql';
GO
:r $(RUTA)65_integridad_fase3.sql
GO

PRINT '--- 66_estandarizacion_nombres.sql';
GO
:r $(RUTA)66_estandarizacion_nombres.sql
GO

PRINT '--- 67_antiguedad_vendedor_permisos.sql';
GO
:r $(RUTA)67_antiguedad_vendedor_permisos.sql
GO

PRINT '--- 68_caja_chica_vale_sin_proveedor.sql';
GO
:r $(RUTA)68_caja_chica_vale_sin_proveedor.sql
GO

PRINT '--- 69_kardex_inventario.sql';
GO
:r $(RUTA)69_kardex_inventario.sql
GO

PRINT '--- 70_correo_proveedores.sql';
GO
:r $(RUTA)70_correo_proveedores.sql
GO

PRINT '--- 71_pago_proveedor_transferencia.sql';
GO
:r $(RUTA)71_pago_proveedor_transferencia.sql
GO

PRINT '';
PRINT 'Instalación 01 a 71 terminada. Usuario de prueba: admin / Demo#2024.';
GO
