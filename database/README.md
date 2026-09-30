# ERP de Servicios Informáticos — Base de datos

Rediseño del script SQL Server original (`texasdb`) para un ERP de servicios
informáticos (punto de venta, inventario, cuentas por cobrar/pagar, bancos),
ampliado con módulos de **seguridad (roles/permisos)**, **multi-moneda** y
**contabilidad (libro de asientos)**, más datos sintéticos y procedimientos
almacenados de CRUD y de procesos de negocio.

## Cómo ejecutar

Correr los scripts **en orden**, con SQLCMD, Azure Data Studio o SSMS
(requiere SQL Server 2019 o superior por el uso de `STRING_AGG`-like syntax,
`THROW`, `TRIM`... en realidad el mínimo real es SQL Server 2016, pero el
script fija `COMPATIBILITY_LEVEL = 150`):

```
00_crear_base_datos.sql
01_tipos_tabla.sql
02_tablas_generales_seguridad.sql
03_tablas_inventario.sql
04_tablas_pos_bancos.sql
05_tablas_contabilidad.sql
06_llaves_foraneas.sql
07_indices_restricciones.sql
08_funciones.sql
09_vistas.sql
10_procedimientos_crud.sql
11_procedimientos_procesos.sql
12_datos_sinteticos.sql   -- opcional, solo para ambientes de prueba
13_correccion_numero_unico.sql   -- solo si ya corriste 00-12 antes de esta fecha
14_procedimientos_vendedor.sql   -- solo si ya corriste 00-12 antes de esta fecha
15_correccion_plan_pagos.sql     -- solo si ya corriste 00-14 antes de esta fecha
16_activar_usuario.sql                        -- solo si ya corriste 00-15 antes de esta fecha
17_documento_consultar_codigo_cliente.sql     -- solo si ya corriste 00-16 antes de esta fecha
18_procedimientos_detalle_producto.sql        -- solo si ya corriste 00-17 antes de esta fecha
19_procedimientos_tipo_caracteristica.sql     -- solo si ya corriste 00-18 antes de esta fecha
20_procedimiento_plan_pagos_consultar.sql     -- solo si ya corriste 00-19 antes de esta fecha
21_costo_unitario_ppr_id_factura.sql          -- solo si ya corriste 00-20 antes de esta fecha
22_sucursal_caja_formas_pago_tablas.sql       -- solo si ya corriste 00-21 antes de esta fecha
23_procedimientos_caja_sucursal.sql           -- solo si ya corriste 00-22 antes de esta fecha
24_formas_pago_factura_cobro.sql              -- solo si ya corriste 00-23 antes de esta fecha
25_rrhh.sql                                   -- módulo de RRHH y nómina
26_parametros_general_caja.sql                -- parámetros de compañía, módulo General, cuadre de caja
27_contabilidad_cuentas_parametro.sql         -- cuentas de las pólizas automáticas
28_nomenclatura_contable.sql                  -- nomenclatura contable definitiva y su mantenimiento
29_asientos_deposito_cierre_nomina.sql        -- partidas de depósito, cierre de caja y nómina
30_datos_sinteticos_procesos.sql              -- opcional: datos de prueba de caja y nómina
31_sucursales_unidades_organigrama.sql        -- sucursales, bodegas, unidades de medida, factura con servicios, organigrama
32_cuentas_por_cobrar_pagar.sql               -- cuentas por cobrar y por pagar, notas de crédito y débito
33_datos_sinteticos_cxc_organigrama.sql       -- opcional: organigrama de ejemplo, factura con servicios y notas
34_auditoria_procesos.sql                     -- recibos y cheques anulables, cobro de varias cuotas, límite de crédito
35_costos_fel_tableros.sql                    -- costo unitario por línea, factura electrónica (FEL) parametrizada, tableros
36_bancos_nomina_centro_costo.sql             -- bancos (cuentas, chequeras, motivos, cheques), nómina por período, pago a empleados, centro de costo
37_datos_sinteticos_bancos_nomina.sql         -- opcional: datos de prueba de bancos y pago de nómina
38_inventario_fisico_cargas_iniciales.sql     -- inventario físico, inventario inicial, saldos iniciales y carga de empleados desde Excel
39_datos_sinteticos_inventario_saldos.sql     -- opcional: datos de prueba de inventario físico, inventario inicial y apertura
40_logo_cuentas_bancarias_productos_proveedor.sql -- nomenclatura sin datos confidenciales, cuentas de cargos/abonos, logotipo, productos por proveedor
41_datos_sinteticos_productos_proveedor.sql   -- opcional: productos por proveedor a partir de las compras
42_cxp_cheque_varias_cuotas.sql               -- pago a proveedores: un cheque por una factura completa o por el saldo de varias
43_datos_sinteticos_cxp_pagos.sql             -- opcional: compras al crédito con varias cuotas y un cheque de varias facturas
44_nit_certificadores_seguridad.sql           -- validación de NIT/CUI, consulta de NIT por certificador FEL, clientes por NIT, permisos
45_traslados_bodegas.sql                      -- traslados entre bodegas: salida, tránsito e ingreso al recibir
46_datos_sinteticos_traslados.sql             -- opcional: tercera bodega y dos traslados de prueba
47_reparar_opciones_set.sql                   -- repara objetos creados con QUOTED_IDENTIFIER/ANSI_NULLS en OFF y prueba grabar una factura
48_impresion_factura.sql                      -- impresión de la factura en carta o en impresora térmica
```

**Todos los scripts se pueden volver a correr.** Correr del `00` al `48` en
orden funciona igual sobre una base nueva que sobre una existente: los
scripts `01`-`07` solo crean los tipos, tablas, llaves e índices que falten, y
los demás usan `CREATE OR ALTER` o verifican antes de insertar. Ojo: el `12`
borra y regenera todos los datos de prueba; si la base tiene datos reales,
no lo incluyas (ni el `30`, el `33`, el `37`, el `39`, el `41`, el `43` ni el `46`).

`25` a `29`, `31`, `32`, `34` a `36`, `38`, `40`, `42`, `44`, `45`, `47` y `48` se corren siempre (también en una instalación
nueva) y se pueden volver a correr. **Importante:** `11` y `23` todavía contienen la
versión anterior de `sp_pos_caja_cerrar` y `paCorteCajaTeoricoConsultar`
(sin el cuadre obligatorio ni la partida del cierre); si vuelves a correr
cualquiera de los dos, vuelve a correr después `26` a `48`. Si vuelves a
correr `12`, corre después `22` a `48` (el `12` vacía todas las tablas). Lo
mismo con `25`, `26`, `27`, `29`, `31`, `32`, `34` y `35`: redefinen
procedimientos que los scripts posteriores corrigen, así que después de
cualquiera de ellos corre de nuevo el `34`, `35`, `36`, `38`, `40` y `42`. Si
vuelves a correr `23`, `29` o `36`, corre después el `40` (redefine el
depósito de caja y el mantenimiento de cuentas bancarias). Si vuelves a
correr `34` o `38`, corre después el `42` (redefine la consulta de cheques a
proveedores y el tablero de compras). Si vuelves a correr `10` o `38`,
corre después el `44` (redefine la consulta de usuarios y la carga de
empleados con la validación del NIT y el DPI).

Todos los scripts fijan `SET QUOTED_IDENTIFIER ON` y `SET ANSI_NULLS ON` al
inicio, porque los índices filtrados (`enc_numero_unico`, `IdEmpleado`) los
exigen y `sqlcmd` los apaga por defecto; ya no hace falta pasar `-I`.

**¿No aparecen los menús General o RRHH?** Se muestran con los permisos
`GENERAL_CONFIG_ADMIN` y `RRHH_ADMIN`, que `26` asigna al rol `ADMIN` (y
`12` también los incluye, para que volver a correrlo no se los quite).
Verifícalo con:

```sql
SELECT pe.per_codigo, r.rol_codigo
FROM sec_permiso pe
JOIN sec_rol_permiso rp ON rp.per_id = pe.per_id
JOIN sec_rol r ON r.rol_id = rp.rol_id
WHERE pe.per_codigo IN ('GENERAL_CONFIG_ADMIN', 'RRHH_ADMIN');
```

Si la consulta no devuelve filas, corre `26_parametros_general_caja.sql`.
La aplicación vuelve a leer los permisos de la sesión cada minuto, así que
el menú aparece al recargar la página sin cerrar sesión.

## Estándares de nomenclatura (a partir de este punto)

A solicitud explícita, todo procedimiento almacenado **nuevo** y todo alias
de tabla **nuevo** en el SQL que se agregue de aquí en adelante debe seguir:

- **Procedimientos almacenados:** prefijo `pa` + PascalCase, sin guiones
  bajos (ej. `paProductoInsertar`, `paClienteConsultarPorId`).
- **Alias de tabla en consultas:** mínimo 4 caracteres (ej. `prod` en vez de
  `pro`, `enca` en vez de `enc`).

Esto **no aplica retroactivamente**: los ~90 procedimientos `sp_<entidad>_
<accion>` y los alias de 3 caracteres (`pro`, `cli`, `enc`, `bod`, `mon`,
`tdo`, `prv`, `ppr`, `pca`, `ptc`, `peb`...) que ya están desplegados se
dejan como están para no romper llamadas existentes desde `Erp.Data`. Si
en algún momento se pide migrar los objetos existentes a este estándar,
es un cambio aparte y coordinado (afecta la capa de datos del frontend a
la vez), no algo para hacer de forma incremental sin avisar.

Cada archivo empieza con `USE [erp_db];` y usa `CREATE OR ALTER` en objetos
programables, así que se pueden volver a correr sin borrar la base primero
(excepto `00` y las tablas, que fallan si ya existen — están pensadas para
una carga inicial única).

Si tu base ya existía **antes** de que se agregara `13_correccion_numero_unico.sql`,
corre ese script una sola vez (ver la sección "Correcciones posteriores" más
abajo); una instalación nueva desde cero ya no lo necesita porque `03` y `11`
quedaron corregidos directamente.

## Qué se mantuvo del script original

El modelo de negocio original se conservó casi intacto: catálogos generales
(país/departamento/municipio, compañía/sucursal), inventario y productos,
proveedores, documentos de inventario (encabezado/detalle, usado tanto para
compras como ventas), clientes y sus planes de pago, punto de venta (caja,
formas de pago) y bancos (cuentas, chequeras, cheques emitidos). Las
funciones de negocio (nombres/direcciones completas, número a letras, último
movimiento/costo de un producto) y la idea de guardar factura/compra con un
parámetro de tabla (TVP) para el detalle también se mantuvieron.

## Cambios generales

- La base de datos se renombra de `texasdb` a `erp_db`: el nombre original
  correspondía a un cliente/proyecto específico; uno genérico permite
  reutilizar el modelo en otro giro de negocio sin que el nombre de la base
  quede desalineado con el negocio real.
- Se eliminan las tablas `temp_pagoProveedor`, `temp_pagoProveedorDiciembre`,
  `tmp_producto` y `tmp_producto_tipo`: eran tablas de staging para una
  migración puntual (nombres en camelCase o sin prefijo, sin llaves,
  claramente ajenas a la convención `prefijo_columna` del resto del modelo),
  no parte del modelo de negocio.
- Convención de nombres consistente: se corrigen columnas con acentos mal
  codificados (`cbc_fecha_recepciòn_chequera`) y una tabla con dos errores de
  tecleo (`bco_cuenta_bacaria_chequera` → `bco_cuenta_bancaria_chequera`,
  `correlatio` → `correlativo`).
- Se corrige una colisión de nombres: `inv_proveedor_plan_pago` usaba el
  mismo prefijo de columna (`ppr_`) que `inv_producto_precio`. Ahora usa
  `ppg_` (plan de pago) para que ambos conceptos no se confundan.
- Todas las columnas de una sola letra (`_estado`, `_naturaleza`,
  `_bien_o_servicio`, etc.) quedan con `CHECK` explícito de los valores
  permitidos; antes no había ninguna validación a nivel de base de datos.
- Se agregan `UNIQUE` en llaves de negocio (códigos, NIT, números de cuenta,
  etc.) y un índice no clusterizado por cada columna de llave foránea que no
  quedaba ya cubierta por un `UNIQUE`/`PRIMARY KEY` — el script original
  prácticamente no tenía más índices que el de la llave primaria.

## Auditoría por fila (`InsUsuario` / `InsFechaHora` / `UpdUsuario` / `UpdFechaHora`)

Todas las tablas de `02_tablas_generales_seguridad.sql`, `03_tablas_inventario.sql`,
`04_tablas_pos_bancos.sql` y `05_tablas_contabilidad.sql` — 50 en total —
agregan cuatro columnas al final:

| Columna | Tipo | Se llena... |
|---|---|---|
| `InsUsuario` | `INT NULL` | con el usuario que creó la fila |
| `InsFechaHora` | `DATETIME2(0) NOT NULL DEFAULT (SYSDATETIME())` | sola, al insertar |
| `UpdUsuario` | `INT NULL` | con el usuario de la última actualización |
| `UpdFechaHora` | `DATETIME2(0) NULL` | con la fecha/hora de la última actualización |

Se dejan en **PascalCase**, a propósito distinto de la convención
`<prefijo>_columna` del resto del modelo, para que se identifiquen de un
vistazo como metadatos de auditoría y no como columnas de negocio.

Decisiones de diseño:

- `InsUsuario`/`UpdUsuario` son `INT NULL` con llave foránea hacia
  `gen_usuario([usu_id])`. Se generan al final de `06_llaves_foraneas.sql`
  con un bloque de SQL dinámico que recorre `sys.columns`/`sys.tables` (en
  vez de escribir a mano más de cien `ALTER TABLE`), así que ese script
  ahora también debe volver a correrse.
- Se dejan nulas — a diferencia de `InsFechaHora`, que sí es obligatoria —
  para que quien llame a un procedimiento sin indicar `@usu_id` (por
  ejemplo `12_datos_sinteticos.sql`, que hace `INSERT` directos sin pasar
  por los procedimientos) no rompa nada; simplemente esas columnas quedan
  en `NULL`.
- Única excepción: `gen_auditoria` no las lleva, porque esa tabla **es** la
  bitácora de auditoría (ya tiene sus propias columnas `usu_id`/`aud_fecha`
  equivalentes) y sus filas nunca se actualizan, solo se insertan.
- En `inv_documento_enc` y `cont_asiento_enc`, que ya traían columnas
  equivalentes (`usu_id_creacion`/`enc_fecha_grabado` y
  `usu_id`/`asi_fecha_creacion` respectivamente), las nuevas columnas se
  agregan de todas formas para que las 50 tablas sean consistentes; las
  columnas anteriores se conservan por compatibilidad.
- No se agregaron índices sobre `InsUsuario`/`UpdUsuario` (ver
  `07_indices_restricciones.sql`): son columnas de "quién", poco usadas para
  filtrar/unir en el uso normal del ERP, y sumar ~100 índices más solo por
  simetría habría sido puro costo de escritura sin beneficio real.

**Estado de la conexión con los procedimientos:**

- `10_procedimientos_crud.sql` ya está conectado: cada
  `sp_<entidad>_insertar`/`_actualizar`/`_eliminar` recibe un parámetro
  `@usu_id` (opcional, `NULL` por defecto) y lo graba en
  `InsUsuario`/`UpdUsuario`, junto con `InsFechaHora`/`UpdFechaHora` =
  `SYSDATETIME()`. En los procedimientos de `gen_usuario`, donde `@usu_id`
  ya identificaba la fila objetivo, el usuario que ejecuta la acción se
  recibe como `@usu_id_accion` para no chocar con ese nombre.
  `sp_usuario_cambiar_password` graba `UpdUsuario = @usu_id` (el mismo
  usuario, porque es un cambio que uno hace sobre su propia cuenta).
  `sp_rol_asignar_permiso`/`sp_usuario_asignar_rol` también graban
  `InsUsuario`/`InsFechaHora` al insertar en las tablas de asignación;
  los procedimientos `_revocar_*` (`DELETE`) no aplican, porque la fila
  desaparece.
- `11_procedimientos_procesos.sql` también está conectado: `@usu_id` se
  graba en todas las filas que tocan `sp_ventas_crear_factura`,
  `sp_compras_crear_documento` (encabezado y detalle del documento, el plan
  de cuotas que generan, el ajuste de existencias y el asiento contable
  automático), `sp_documento_anular` (reversa de existencias y anulación del
  asiento), `sp_pos_registrar_pago_cuota` (el pago y la cuota abonada),
  `sp_bancos_emitir_cheque_pago_proveedor` (el cheque y la cuota pagada),
  `sp_pos_caja_abrir`/`sp_pos_caja_cerrar` y `sp_seguridad_login` (que se
  graba a sí mismo como `UpdUsuario`, tanto en un login exitoso como en uno
  fallido). Los procedimientos internos que antes no necesitaban saber quién
  ejecuta la acción (`sp_inventario_ajustar_existencia_documento`,
  `sp_inventario_recalcular_existencias_completo`,
  `sp_pos_generar_plan_pagos_cliente`, `sp_inv_generar_plan_pagos_proveedor`,
  `sp_contabilidad_obtener_o_crear_periodo`) ahora reciben `@usu_id` también,
  para poder pasarlo hacia abajo en la cadena de llamadas.
  `12_datos_sinteticos.sql` no necesitó cambios: todos los parámetros nuevos
  son opcionales y las llamadas existentes ya usaban argumentos con nombre.

## Errores corregidos (no eran solo de estilo)

1. **`UPDATE` sin `WHERE`.** `spr_guarda_compra` y `spr_guarda_factura`
   hacían `UPDATE inv_documento_enc SET enc_estado = 'G'` sin filtrar por
   `enc_id`: cada factura o compra grabada marcaba **todos** los documentos
   de la tabla como "Grabado". Ahora todo `UPDATE` de estado lleva su
   `WHERE enc_id = @enc_id` (`sp_ventas_crear_factura`,
   `sp_compras_crear_documento`, `sp_documento_anular`).
2. **Correlativo de facturación compartido y sin bloqueo.** `spr_guarda_factura`
   actualizaba `conf_correlativos` con una subconsulta a la misma tabla, sin
   `WHERE` y sin distinguir series por tipo de documento — con más de una
   serie el valor quedaba indeterminado, y dos facturas grabándose al mismo
   tiempo podían repetir número. Ahora `conf_correlativos` tiene una fila por
   `tdo_id` y se lee con `UPDLOCK, ROWLOCK` dentro de la transacción antes de
   incrementarla (`sp_ventas_crear_factura`).
3. **Recalcular todo el inventario en cada venta.** `SPR_ACTUALIZA_EXISTENCIAS`
   recorría con un cursor **todo** el historial de documentos cada vez que se
   grababa una sola factura o compra. Se reemplaza por un ajuste incremental
   (`sp_inventario_ajustar_existencia_documento`) que solo toca las líneas del
   documento que se está grabando; el recálculo completo se conserva como
   `sp_inventario_recalcular_existencias_completo`, para usarse solo como
   utilidad de mantenimiento/reconciliación.
4. **Contraseñas en texto plano.** `gen_usuario.usu_contrasenia` era
   `varchar(8)` y `SPR_LOGIN_USUARIO` comparaba el valor tal cual. Se
   reemplaza por `usu_password_hash` (`SHA2_256` + sal por usuario) y
   `sp_seguridad_login` compara el hash, además de bloquear la cuenta tras 5
   intentos fallidos.
5. **Datos de tarjeta en texto plano.** `pos_pago_forma` guardaba el número
   completo de tarjeta y el código de verificación (CVV), lo cual viola
   PCI-DSS. Se elimina el CVV por completo y el número de tarjeta se reduce a
   los últimos 4 dígitos.
6. **`pos_caja_deposito.pcd_valor_deposito` tipado como `DATETIME`** a pesar
   de ser un monto en dinero: se corrige a `DECIMAL(14,2)`.
7. **`pos_pago_det` no tenía monto.** No se podía saber cuánto de un pago se
   aplicó a cada cuota. Se agrega `ppd_valor_aplicado`.
8. **No existía forma de anular un documento** ya grabado. Se agrega
   `sp_documento_anular`, que revierte el efecto en existencias y anula el
   asiento contable asociado (no revierte automáticamente cuotas de plan de
   pago ya generadas: cancelar un documento no implica necesariamente
   cancelar un compromiso de pago ya acordado con el cliente/proveedor).

## Correcciones posteriores (encontradas al construir el frontend)

9. **`enc_numero_unico` con una `UNIQUE` constraint normal sobre columna
   nullable.** En SQL Server ese tipo de restricción solo permite **un**
   valor `NULL` en toda la tabla (a diferencia de PostgreSQL/Oracle). Como
   `sp_compras_crear_documento` nunca llena esa columna (las compras no usan
   ese correlativo), la primera compra de la vida del sistema la deja en
   `NULL`, y cualquier documento posterior que también intentara insertarse
   con `NULL` en ese instante (toda factura nueva, porque el `INSERT`
   original de `sp_ventas_crear_factura` la dejaba en `NULL` momentáneamente
   antes de un `UPDATE` posterior) chocaba contra ese primer `NULL` y fallaba
   con `Violation of UNIQUE KEY constraint ... duplicate key value is
   (<NULL>)`. Se cambia por un **índice único filtrado**
   (`WHERE enc_numero_unico IS NOT NULL`, ver `03_tablas_inventario.sql`) y
   `sp_ventas_crear_factura` ahora graba `enc_numero_unico` directo en el
   `INSERT` en vez de en un `UPDATE` posterior (`11_procedimientos_procesos.sql`).
   Quien ya haya corrido `00`-`12` antes de este cambio debe correr
   `13_correccion_numero_unico.sql` una sola vez contra su base existente.
10. **`pos_vendedor` sin procedimientos.** Existía la tabla (sembrada por
    `12_datos_sinteticos.sql`) pero no había alta/baja/edición/consulta. Se
    agregan en `10_procedimientos_crud.sql`. A solicitud explícita, estos
    procedimientos usan el estándar de nomenclatura **`pa` + PascalCase**
    (`paVendedorInsertar`, `paVendedorActualizar`, `paVendedorEliminar`,
    `paVendedorConsultar`, `paVendedorConsultarPorId`) en vez de
    `sp_<entidad>_<accion>`. En ese momento fue el único módulo con ese
    estándar; desde la sección "Estándares de nomenclatura" arriba, es el
    estándar para todo procedimiento nuevo — los ~90 procedimientos
    `sp_<entidad>_<accion>` existentes no se renombraron para no romper
    llamadas ya desplegadas. Quien ya haya corrido `00`-`12` debe correr
    `14_procedimientos_vendedor.sql` una sola vez.
11. **Plan de pagos con el enganche/descuento mal aplicado.** Al exponer en
    el frontend los campos de crédito (enganche, cuotas, fecha del primer
    pago) se encontró que `sp_pos_generar_plan_pagos_cliente` restaba el
    descuento dos veces (una porque `enc_monto_total` ya viene neto de
    descuento, y otra porque el procedimiento lo volvía a restar), y que
    `sp_inv_generar_plan_pagos_proveedor` nunca restaba el enganche aunque
    sí se captura y se guarda. Ambos quedan con la misma fórmula
    `valor_cuota = (monto_total - monto_enganche) / número_cuotas`
    (`11_procedimientos_procesos.sql`). Quien ya haya corrido `00`-`14` debe
    correr `15_correccion_plan_pagos.sql` una sola vez; no recalcula planes
    de pago ya generados.
12. **Reactivar usuario.** `sp_usuario_eliminar` (baja lógica) no tenía
    contraparte para reactivar. Se agrega `paUsuarioActivar`
    (`10_procedimientos_crud.sql`). Quien ya haya corrido `00`-`15` debe
    correr `16_activar_usuario.sql` una sola vez.
13. **Listado de documentos sin código de tipo ni nombre de cliente/
    proveedor.** El listado de Facturas/Compras mostraba la descripción
    completa del tipo de documento y no traía el nombre del cliente o
    proveedor. Se agrega `tdo_codigo`, `cli_nombres`/`cli_apellidos` y
    `prv_nombre_comercial` al resultado, y de paso se renombra
    `sp_documento_consultar` a **`paDocumentoConsultar`**
    (`10_procedimientos_crud.sql`). Quien ya haya corrido `00`-`16` debe
    correr `17_documento_consultar_codigo_cliente.sql` una sola vez (borra
    el procedimiento viejo y crea el nuevo).
14. **Detalle de producto sin CRUD.** Existían las tablas
    `inv_producto_caracteristica`, `inv_producto_tipo_caracteristica`,
    `inv_producto_existencia_bodega` e `inv_producto_precio`, pero solo se
    podían leer (nunca dar de alta/editar/eliminar) desde el frontend. Se
    agregan `paProductoTipoCaracteristicaConsultar`,
    `paProductoCaracteristicaInsertar/Actualizar/Eliminar/Consultar`,
    `paProductoExistenciaConsultar` (solo consulta — la existencia la
    mantienen los procesos de negocio) y
    `paProductoPrecioInsertar/Actualizar/Eliminar/Consultar/ConsultarPorId`
    (`10_procedimientos_crud.sql`). Quien ya haya corrido `00`-`17` debe
    correr `18_procedimientos_detalle_producto.sql` una sola vez.
15. **CRUD de tipo de característica.** `inv_producto_tipo_caracteristica`
    (el catálogo de tipos de característica: Marca, Modelo, Garantía,
    Capacidad...) solo tenía consulta. Se agregan
    `paProductoTipoCaracteristicaInsertar/Actualizar/Eliminar` (baja lógica
    con `ptc_estado`) para poder mantenerlo desde un módulo propio en
    Inventario (`10_procedimientos_crud.sql`). Quien ya haya corrido
    `00`-`18` debe correr `19_procedimientos_tipo_caracteristica.sql` una
    sola vez.
16. **Consulta del plan de pagos.** `pos_cliente_plan_pagos` (las cuotas
    de una factura a crédito) se generaba al grabar pero no tenía
    procedimiento de consulta. Se agrega `paClientePlanPagosConsultar`
    (`10_procedimientos_crud.sql`) para poder mostrar el plan de pagos
    como detalle informativo justo al grabar una factura a crédito. Quien
    ya haya corrido `00`-`19` debe correr
    `20_procedimiento_plan_pagos_consultar.sql` una sola vez.
17. **Costo unitario y precio de lista sin registrar en el detalle de
    factura.** `inv_documento_det` ya tenía las columnas
    `det_costo_unitario` y `ppr_id`, pero `sp_ventas_crear_factura` nunca
    las llenaba (quedaban `NULL`). Ahora `det_costo_unitario` guarda el
    costo unitario del producto al momento de la venta y `ppr_id` guarda
    el `inv_producto_precio.ppr_id` de la lista de precios con el que se
    vendió (`det_precio_unitario` sigue siendo el precio de venta, y
    `det_bien_o_servicio` ya se llenaba bien desde el tipo de producto).
    Como `dbo.factura_det_type` es un parámetro con tipo de tabla, no se
    puede alterar in-place: el script quita temporalmente
    `sp_ventas_crear_factura`, recrea el tipo con la columna nueva y
    vuelve a crear el procedimiento. Quien ya haya corrido `00`-`20` debe
    correr `21_costo_unitario_ppr_id_factura.sql` una sola vez.
18. **Login por sucursal, apertura de caja con fondo inicial, depósitos y
    formas de pago (efectivo/cheque/tarjeta).** A solicitud explícita se
    agrega:
    - `pos_caja_receptora` ahora se relaciona con `gen_sucursal` (una
      sucursal puede tener varias cajas). Tabla nueva
      `sec_usuario_sucursal`: qué sucursales tiene autorizadas cada
      usuario (el login pide la sucursal y valida contra esta tabla). Se
      apadrina a todos los usuarios activos en todas las sucursales
      activas para no romper accesos existentes; un administrador ajusta
      después los accesos reales desde Usuarios.
    - `pos_caja_apertura` agrega el monto inicial (fondo de caja, libre)
      y los totales de corte (teórico/físico/diferencia). `sp_pos_caja_abrir`
      ya validaba que no hubiera otra apertura activa para la misma caja
      receptora (esa es la regla de "no abrir si no se cerró el día
      anterior"); solo se le agregó el monto inicial. `sp_pos_caja_cerrar`
      ahora calcula el corte (teórico desde `pos_pago_forma`, físico desde
      `pos_caja_desglose_efectivo` + la nueva `pos_caja_corte_forma`)
      antes de cerrar.
    - `pos_caja_deposito` ahora se relaciona con `gen_entidad_financiera`.
    - `pos_pago_forma` agrega el monto de esa forma de pago (antes no se
      podía saber cuánto correspondía a cada forma), y `pos_pago_det`
      ahora puede referenciar directamente una factura además de una
      cuota, para poder registrar el pago de contado o el enganche de
      crédito (que antes no generaban cuota propia, así que no se podían
      pagar). `sp_ventas_crear_factura` y `sp_pos_registrar_pago_cuota`
      reciben las formas de pago usadas.
    - CRUD nuevo de cajas receptoras (`paCajaReceptora*`, antes solo se
      podían insertar a mano) y de sucursales por usuario
      (`paUsuarioSucursal*`).

    Scripts: `22_sucursal_caja_formas_pago_tablas.sql` (tablas),
    `23_procedimientos_caja_sucursal.sql` (sucursal/caja/corte) y
    `24_formas_pago_factura_cobro.sql` (formas de pago en factura y
    cobro). Quien ya haya corrido `00`-`21` debe correr los tres, en
    orden, una sola vez.

    En el frontend (`Erp.Web`): el login ahora pide la sucursal en un
    segundo paso (se salta si el usuario solo tiene una autorizada) y la
    guarda como claim; si el usuario no tiene ninguna sucursal asignada,
    no puede iniciar sesión — **excepto** quien tenga el permiso
    `SEGURIDAD_USUARIO_ADMIN` (mantenimiento de usuarios), que nunca se
    bloquea por esto (si no, nadie podría entrar a asignarle una sucursal
    a nadie); ese usuario entra sin sucursal seleccionada y puede elegir
    cualquiera desde "Bancos > Caja" al hacer mantenimiento. La barra de
    estado muestra una advertencia
    (no bloqueante, según lo pedido) cuando la sucursal actual no tiene
    ninguna caja abierta. El menú "Bancos > Caja" agrupa apertura,
    corte/cierre con conteo físico por denominación, depósitos y el CRUD
    de cajas receptoras. En "Usuarios" se agregó una sección de
    sucursales asignadas (mismo patrón que roles asignados). En
    "Facturas" se agregó la captura de forma(s) de pago (efectivo,
    cheque, tarjeta, transferencia) del monto pagado al momento de
    facturar (de contado, o el enganche si es a crédito), enlazada a la
    caja abierta de la sucursal del usuario; si no hay caja abierta, la
    factura se graba igual pero sin registrar el pago en caja. **No** se
    construyó una pantalla de cobro de cuotas con formas de pago (el
    procedimiento `sp_pos_registrar_pago_cuota` ya las acepta a nivel de
    base de datos, pero no hay UI todavía).
19. **Corrección: un parámetro de tabla (TVP) no puede tener valor por
    defecto en SQL Server.** `@formas_pago dbo.pago_forma_type READONLY
    = NULL` en `sp_ventas_crear_factura` y `sp_pos_registrar_pago_cuota`
    (punto 18) no es sintaxis válida — SQL Server la rechaza con "Incorrect
    syntax near '='" al crear el procedimiento, y como el `CREATE
    PROCEDURE` completo falla, arrastra errores de "must declare the
    scalar variable" en el resto de parámetros. Se quitó el `= NULL` de
    ambos procedimientos (ahora `@formas_pago` es obligatorio, como
    `@detalle` en las demás; sigue aceptando una tabla vacía cuando no
    aplica). `12_datos_sinteticos.sql` se ajustó para pasar una tabla
    vacía en sus dos llamadas a estos procedimientos. Si ya corriste
    `22`-`24` con la versión anterior, vuelve a correr `24_formas_pago_factura_cobro.sql`
    (o `11_procedimientos_procesos.sql` si empezaste desde cero) para
    quedar con los procedimientos corregidos.
20. **Corrección: en una instalación nueva, la primera fila de cada tabla
    recibía el id 0.** `12_datos_sinteticos.sql` reinicia los contadores
    con `DBCC CHECKIDENT (..., RESEED, 0)`; en una tabla que nunca tuvo
    filas, SQL Server entrega ese mismo valor (0) a la siguiente fila en
    lugar de 0 + 1. Así quedaban con id 0 el usuario `admin`, la sucursal
    "Casa matriz", la primera bodega, la moneda, etc. (43 tablas), y la
    aplicación usa 0 como "Seleccione..." en los combos: por ejemplo, nadie
    podía iniciar sesión en "Casa matriz". Ahora solo se reinician las
    tablas que ya tuvieron filas (`last_value IS NOT NULL`), y en ambos
    casos (instalación nueva o re-ejecución) los ids empiezan en 1.
    **Si tu base se creó desde cero con la versión anterior**, revisa con
    `SELECT suc_id, suc_descripcion FROM gen_sucursal;`: si ves un
    `suc_id = 0`, vuelve a correr `12_datos_sinteticos.sql` y después
    `22`, `23` y `24` (el 12 borra y regenera todos los datos de ejemplo).
21. **Corrección: `22` y `23` no se podían volver a correr.** `22` fallaba
    incluso en una instalación nueva porque `07` ya había creado el índice
    `IX_pos_caja_receptora_suc_id`, y `23` fallaba al re-ejecutarse porque
    intentaba borrar sus tipos de tabla mientras los procedimientos los
    seguían usando. Ahora ambos verifican lo que ya existe antes de
    crearlo. Se comprobó la instalación completa `00`-`24` contra SQL
    Server 2022 sin errores, y la re-ejecución de `12` + `22`-`24` sobre
    una base ya poblada.

## Parámetros generales, RRHH y pólizas automáticas (`25`-`27`)

### Parámetros de uso general en `gen_compania` (`26`)

Se evaluaron los valores que hoy estaban fijos en el código o que cada
módulo necesitaría repetir, y se dejaron en la compañía (mantenimiento en
**General > Compañías**, solo para el rol ADMIN mediante el permiso
`GENERAL_CONFIG_ADMIN`):

| Columna | Default | Uso |
|---|---|---|
| `cia_porc_iva` | 12.00 | % de IVA con el que Facturas y Compras separan el neto del precio con IVA incluido (antes estaba fijo en el código). |
| `cia_paga_comision` | 0 | Si es 1, la pestaña *Facturas y comisiones* del vendedor calcula la comisión (`pve_porc_comision` sobre la venta **sin IVA**, solo facturas grabadas). |
| `cia_tolerancia_cierre_caja` | 0.00 | Diferencia máxima (en quetzales) permitida entre el teórico y lo contado para cerrar una caja. |
| `cia_periodicidad_nomina` | `M` | Periodicidad sugerida al crear nóminas: mensual (`M`) o quincenal (`Q`). |

Se consideraron y **no** se agregaron: la moneda base (ya la define
`gen_moneda.mon_es_local`), las tasas de IGSS/bonificación (son tipos de
movimiento de nómina configurables, ver abajo) y un indicador de "precios
incluyen IVA" (en Guatemala siempre es así y el sistema ya lo asume).
`paCompaniaParametrosConsultar(@SucId)` devuelve los parámetros de la
compañía de una sucursal para que cualquier pantalla los use.

El mismo script agrega el CRUD de compañías y el maestro-detalle de
`gen_entidad_financiera_tipo` → `gen_entidad_financiera` (procedimientos
`paCompania*`, `paEntidadFinancieraTipo*`, `paEntidadFinanciera*`).

### Cuadre obligatorio del cierre de caja (`26`)

`paCorteCajaCuadreConsultar(@pca_id)` desglosa el teórico:

```
teórico = monto inicial + ventas/cobros en efectivo − depósitos al banco
          + cheques + tarjetas + otras formas (transferencias)
```

y lo compara con lo contado (desglose de efectivo + conteo de otras
formas). `sp_pos_caja_cerrar` rechaza el cierre (error 51703, con el
teórico, lo contado y la diferencia en el mensaje) cuando
`|contado − teórico| > cia_tolerancia_cierre_caja`. La pantalla de Caja
muestra el mismo desglose y deshabilita **Cerrar caja** mientras no cuadre.

### Usuario ↔ vendedor ↔ empleado (`25`)

Sí conviene relacionarlos, pero no directamente usuario con vendedor: con
el módulo de RRHH, **usuario y vendedor son roles de una persona, el
empleado**. Por eso se agregó `IdEmpleado` (nullable, único cuando tiene
valor) en `gen_usuario` y en `pos_vendedor`, en lugar de una FK
usuario→vendedor. Así:

- un empleado puede ser usuario, vendedor, ambos o ninguno (un vendedor
  por comisión sin acceso al sistema no necesita usuario);
- al facturar, `paVendedorConsultarPorUsuario` propone como vendedor el del
  empleado que inició sesión;
- la baja del empleado queda en un solo lugar.

La asignación se hace desde **RRHH > Empleados > Vínculos con el sistema**.

### Módulo de RRHH (`25`)

Tablas con el estándar `rrhh` + PascalCase, tomadas del diagrama
`ERD_RRHH`: estructura organizativa (`rrhhUnidadOrganizativa`,
`rrhhDepartamento`, `rrhhPuesto`, `rrhhDepartamentoPuesto`, `rrhhPlaza`,
`rrhhRequisitoPuesto`), personas (`rrhhCandidato`, `rrhhEmpleado`,
`rrhhHistorialPlaza`, `rrhhTelefono`, `rrhhReferencia`, `rrhhEscolaridad`),
desarrollo (`rrhhCurso`, `rrhhHistorialCapacitacion`,
`rrhhEvaluacionDesempenio`) y catálogos (`rrhhTipo*`).

**Nómina.** `TipoIngreso` y `TipoDescuento` del diagrama se unificaron en
`rrhhTipoMovimientoNomina`, con `Naturaleza` (`I` suma / `D` resta) y
`FormaCalculo`:

| Forma | Cálculo |
|---|---|
| `S` | Salario base × días laborados / 30 (quincena = 15 días; se prorratea el ingreso o la baja dentro del período). |
| `F` | Monto fijo mensual, prorrateado a los días laborados (p. ej. bonificación incentivo Q250). |
| `P` | Porcentaje sobre la suma de los ingresos marcados `EsBaseCalculo` (p. ej. IGSS laboral 4.83 %; la bonificación incentivo no es base). |
| `M` | Manual: se captura por empleado en `rrhhMovimientoNomina` (horas extra, comisiones, ISR, anticipos, préstamos). |

Flujo: `paRrhhNominaCrear` (borrador, valida traslapes) →
`paRrhhNominaCalcular` (llena `rrhhNominaEmpleado` y `rrhhNominaDetalle`;
se puede recalcular) → `paRrhhNominaAprobar` (marca los movimientos
manuales como aplicados a esa nómina) o `paRrhhNominaAnular` (los libera).
El ISR queda como movimiento manual porque depende de la proyección anual
de cada empleado. Los tipos de movimiento tienen `cta_id` para la futura
póliza de nómina.

### Partida de ventas y cuentas afectadas (`27`)

**Cuándo:** la póliza de venta se genera automáticamente al **grabar la
factura** (criterio de devengo: el ingreso y el IVA débito nacen con la
factura, se cobre o no ese día). Al anular la factura su póliza queda
anulada (`asi_estado = 'N'`). Los cobros de cuotas y los pagos con cheque
generan su póliza con los conceptos `COBRO_*` y `PAGO_*`; los depósitos, el
cierre de caja y la nómina, desde el `29` (ver «Partidas de depósito, cierre
de caja y nómina»).

**Qué cuentas** (factura de Q950 de contado, IVA 12 %):

| Concepto | Cuenta | Debe | Haber |
|---|---|---:|---:|
| `VENTA_CAJA` (lo cobrado al facturar) | 1105 Caja general | 950.00 | |
| `VENTA_CLIENTES` (saldo al crédito) | 1205 Clientes | — | |
| `VENTA_INGRESO` (total sin IVA) | 4105 Ventas | | 848.21 |
| `VENTA_IVA_DEBITO` | 2205 IVA débito fiscal | | 101.79 |
| `VENTA_COSTO` / `INVENTARIO` | 5105 Costo de ventas / 1310 Inventarios | 589.00 | 589.00 |

Las cuentas no están fijas en el procedimiento: la tabla
`cont_cuenta_parametro` relaciona cada concepto con una cuenta y se mantiene
en **General > Cuentas de pólizas**. `sp_contabilidad_generar_asiento_documento`
rechaza el documento (error 51304) si falta la cuenta de algún concepto.

### Nomenclatura contable (`28`)

Se carga la nomenclatura de `tbl_Nomenclatura_Contable` (sistema anterior) en
`cont_cuenta_contable`, reemplazando el catálogo mínimo de prueba. La
jerarquía la definen las posiciones del código:

| Nivel | Nodo | Posiciones | Ejemplo | Acepta movimiento |
|---|---|---|---|---|
| 1 | Grupo | 1 | `1` Activo | No |
| 2 | Subgrupo | 2 | `11` Circulante | No |
| 3 | Cuenta | 3 | `111` Caja | No |
| 4 | Subcuenta | 7 (cuenta + correlativo de 4) | `1110002` Caja chica | Sí |

Quedan 162 nodos: 5 grupos, 7 subgrupos, 20 cuentas y 130 subcuentas. El
nivel y el padre se recalcularon a partir del código, porque el archivo traía
errores de jerarquía:

- Se crearon el subgrupo `34` Capital y reservas y la cuenta `140` Diferido, que faltaban.
- `2160002` Préstamos pasó a ser la cuenta `216`.
- Se quitaron los niveles sobrantes `1161`, `1221` y `1222`; sus subcuentas cuelgan de `116` y `122`.
- `1130002`, `2110014` y `5110049` se cargaron como subcuentas (tenían 7 posiciones pero venían marcadas como agrupadoras).
- No se cargaron `521` Gastos de operación ni `529` Pago de impuestos. De sus 35
  subcuentas, 21 ya tenían equivalente en `511` y 14 pasaron a `511` como
  `5110057`-`5110070`.
- Se agregaron `5110071` Faltantes de caja y `4110027` Sobrantes de caja.
- Todas se cargaron activas. No se migraron los saldos (no cuadraban) ni los
  campos `Tipo_Resta`, `Clasificacion_Nomenclatura`, flujo de efectivo y demás.

La base de datos valida la jerarquía: restricciones `CHECK` (código numérico
de 1, 2, 3 o 7 posiciones; nivel según la longitud; movimiento solo en
subcuentas) y el trigger `trg_cont_cuenta_contable_jerarquia` (el código
empieza con el del padre y el padre está en el nivel anterior).

El catálogo de prueba anterior (`1105`, `1205`...) se migra solo: sus
partidas, conceptos de póliza y tipos de movimiento de nómina pasan a la
subcuenta equivalente. Los procedimientos de cobro de cuota y pago con cheque
ya no usan códigos fijos: toman la cuenta de los conceptos `COBRO_*` y
`PAGO_*` (nuevos `PAGO_PROVEEDORES` y `PAGO_BANCOS`). La tabla de conceptos
`cont_cuenta_parametro` ahora se crea en `05`. La cuenta de bancos
(`1120014` Banco Industrial) es provisional y se cambia en **Cuentas de pólizas**.

**Mantenimiento por nodos** (**Contabilidad › Nomenclatura**, permiso nuevo
`CONTABILIDAD_NOMENCLATURA_ADMIN`, asignado a los roles Administrador y
Contador): árbol a la izquierda y nodo seleccionado a la derecha, con estas
acciones (procedimientos `paCuentaContable*`):

- **Agregar** grupo, subgrupo, cuenta o subcuenta; se propone el siguiente código libre.
- **Editar** nombre y naturaleza. El código solo cambia sin hijos ni partidas.
- **Mover** a otro padre del nivel superior; el nodo y su rama se recodifican.
  No se permite si alguno tiene partidas.
- **Activar o inactivar**. Una cuenta asignada a una póliza automática no se puede inactivar.
- **Eliminar**, solo sin hijos, partidas ni asignaciones.

### Partidas de depósito, cierre de caja y nómina (`29`)

Hasta el `28` estos procesos tenían sus conceptos configurados pero no
generaban póliza. Desde el `29` la generan en la misma transacción: si la
póliza no se puede armar (por ejemplo, un concepto sin cuenta), el depósito,
el cierre o la aprobación tampoco se graban y se muestra el motivo.

| Proceso | Debe | Haber |
|---|---|---|
| Depósito de caja al banco | `DEPOSITO_BANCOS` 1120014 Banco | `DEPOSITO_CAJA` 1110006 Caja general |
| Cierre con faltante | `CAJA_FALTANTE` 5110071 Faltantes de caja | `COBRO_CAJA` 1110006 Caja general |
| Cierre con sobrante | `COBRO_CAJA` 1110006 Caja general | `CAJA_SOBRANTE` 4110027 Sobrantes de caja |
| Nómina aprobada | cada ingreso, a la cuenta de su tipo de movimiento | cada descuento, a la cuenta de su tipo; el líquido a `NOMINA_SUELDOS_POR_PAGAR` 2110013 |

- El cierre solo genera póliza si hay diferencia; como el cierre exige
  cuadrar, la diferencia nunca pasa de la tolerancia de la compañía.
- Cuentas de los tipos de movimiento de nómina (se cambian en **RRHH › Tipos
  de movimiento**):

  | Tipo | Cuenta |
  |---|---|
  | Sueldo, comisiones, otros ingresos | 5110001 Sueldos y salarios |
  | Horas extra | 5110002 Horas extras |
  | Bonificación incentivo | 5110003 Bonificación incentivo |
  | IGSS laboral | 2110001 IGSS cuotas laborales |
  | ISR | 2110004 Retenciones ISR por pagar |
  | Anticipo, otros descuentos | 1130001 Cuentas por cobrar a empleados |
  | Préstamo | 1130002 Descuento a empleados por préstamo |

  Un ingreso sin cuenta usa `NOMINA_SUELDOS_GASTO` (o `NOMINA_BONIFICACION` /
  `NOMINA_IGSS_POR_PAGAR` para esos dos tipos). Un descuento sin cuenta
  detiene la aprobación (error 52502).
- Anular una nómina aprobada anula su póliza.
- La nómina no calcula la cuota patronal del IGSS, IRTRA, INTECAP ni las
  provisiones de prestaciones (aguinaldo, bono 14, indemnización,
  vacaciones), así que su póliza tampoco las incluye.
- Cada póliza guarda en `cont_asiento_enc.asi_origen_id` el registro que la
  originó (`pcd_id`, `pca_id` o `IdNomina`); `asi_origen` admite ahora
  `DEPOSITO`, `CIERRE_CAJA` y `NOMINA`.

### Sucursales, bodegas y unidades de medida (`31`)

- **General › Sucursales y bodegas**: sucursales (maestro) y sus bodegas
  (detalle). Una sucursal tiene una o más bodegas. **Inventario › Bodegas**
  lista todas las bodegas con filtro por sucursal. Una sucursal no se
  inactiva con bodegas activas o caja abierta; una bodega no se inactiva ni
  cambia de sucursal si tiene existencias. No se eliminan: se inactivan.
- **Inventario › Unidades de medida** (`inv_unidad_medida`): unidad, hora,
  día, mes, servicio, licencia, caja, paquete, metro, kit. El producto tiene
  su unidad por defecto (`inv_producto.ume_id`) y cada línea de documento
  guarda la suya (`inv_documento_det.ume_id`). Una unidad en uso no se
  elimina.

### Factura con bienes y servicios (`31`)

Cada línea del detalle tiene su casilla **B/S**. Un bien (**B**) toma el
producto del inventario (buscador general o dentro de la línea); un
servicio (**S**) se describe en la misma línea sin producto. En ambos se
captura cantidad (con decimales en servicios, p. ej. 2.5 horas), unidad de
medida, precio con IVA incluido y descuento, y se calcula el subtotal.
`factura_det_type` ahora lleva `det_cantidad` decimal y `ume_id`. El
historial del cliente y el plan de pagos pasaron al final de la captura,
debajo de la forma de pago.

### Unidades organizativas y organigrama (`31`)

`rrhhUnidadOrganizativa` es recursiva (`IdUnidadPadre`, `Orden`). En **RRHH ›
Estructura organizativa** la pestaña **Unidades organizativas** mantiene el
árbol por nodos (agregar raíz o subunidad, editar, mover con su rama,
activar o inactivar, eliminar sin hijos ni departamentos; no se permiten
ciclos) y la pestaña **Organigrama** dibuja unidades › departamentos ›
plazas con el empleado que las ocupa (o *Vacante*). Cada nodo lleva su
código de posición: `n<nivel>.<posición>` para unidades (`n1` Junta
Directiva, `n2.1`…`n2.4` gerencias), `.d<n>` para departamentos
(`n2.2.d1`) y `.p<n>` para plazas.

### Cuentas por cobrar y por pagar (`32`)

Menús **Cuentas por cobrar** (permiso `CXC_ADMIN`: roles Administrador,
Contador y Cajero) y **Cuentas por pagar** (`CXP_ADMIN`: Administrador y
Contador):

- **Estado de cuenta**: documentos con saldo (con sus cuotas) y movimientos
  con saldo corrido (facturas o compras, pagos o cheques y notas), con
  saldo inicial según la fecha *Desde*.
- **Cobros** (CxC): el monto recibido se aplica a las cuotas del cliente de
  la más antigua a la más reciente (o a las que se marquen), en un solo
  recibo imprimible, con formas de pago, en la caja abierta de la sucursal;
  los recibos de la caja se pueden anular mientras siga abierta (`34`).
  **Pagos a proveedores** (CxP): cheque de una chequera activa (propone el
  siguiente número); los cheques emitidos se pueden anular (`34`). Ambos
  aceptan abonos parciales y rechazan pagar más que el saldo de la cuota.
- **Notas de crédito y débito** (`NCC`/`NDC` a clientes, `NCP`/`NDP` de
  proveedores), ligadas al documento que afectan (`enc_id_referencia`):
  - La nota de crédito rebaja el saldo desde la última cuota hacia atrás
    (`pos_cliente_nota_aplicacion` / `inv_proveedor_nota_aplicacion`
    registran qué cuota rebajó) y no puede pasar del saldo pendiente. Puede
    devolver mercadería (líneas del documento original, sin pasar de lo que
    queda por devolver): la del cliente reingresa al costo de la venta; la
    que se devuelve al proveedor sale al costo de compra.
  - La nota de débito agrega una cuota nueva al plan del documento con su
    propio vencimiento.
  - Una nota no se anula (se corrige con la nota contraria) y un documento
    con notas tampoco se puede anular.
- **Antigüedad de saldos** (también en **Ventas › Antigüedad de saldos**):
  saldo de cada cuota por días desde su vencimiento a la fecha de corte:
  No vencido, 1-30, 31-60, 61-90 y más de 90 días; por cliente/proveedor o
  por documento, con totales y porcentajes. **Excel** (hojas por tercero,
  por documento y por cuota) y **vista imprimible** (se imprime o se guarda
  como PDF desde el navegador). El estado de cuenta también se exporta e
  imprime.

Pólizas de las notas (conceptos configurables en **Cuentas de pólizas**):

| Nota | Debe | Haber |
|---|---|---|
| Crédito a cliente | `NC_CLIENTE_REBAJA` 4110028 Devoluciones y rebajas sobre ventas (neto) + IVA débito | `VENTA_CLIENTES` (total) |
| … si devuelve mercadería | `INVENTARIO` (costo) | `VENTA_COSTO` (costo) |
| Débito a cliente | `VENTA_CLIENTES` (total) | `ND_CLIENTE_INGRESO` 4110026 Otros ingresos (neto) + IVA débito |
| Crédito de proveedor | `COMPRA_PROVEEDORES` (total) | `INVENTARIO` (devolución) / `NC_PROVEEDOR_REBAJA` 4110026 (rebaja) + IVA crédito |
| Débito de proveedor | `ND_PROVEEDOR_GASTO` 5110033 (neto) + IVA crédito | `COMPRA_PROVEEDORES` (total) |

La subcuenta 4110028 se crea en el `32`. El cobro de cuota y el pago con
cheque ahora guardan en `asi_origen_id` el recibo o el cheque y en `enc_id`
el documento pagado.

### Segunda auditoría de procesos (`34`)

- **Recibos de cobro con estado** (`pos_pago_enc.ppe_estado` A/N, motivo,
  fecha y usuario de anulación). Los recibos que se grabaron sin forma de
  pago no entraban al cuadre de caja: el `30` los completa como Efectivo
  antes de cerrar su caja y el `34` hace lo mismo con los de cajas abiertas
  (no toca cajas ya cerradas).
- **Cobro de varias cuotas en un recibo** (`paCxcCobroRegistrar`, TVP
  `cobro_cuota_type`): una sola póliza por el total. El saldo de cada cuota
  se vuelve a comprobar al rebajarlo, por si otro cajero la cobró al mismo
  tiempo. `sp_pos_registrar_pago_cuota` queda como atajo de una cuota; sin
  formas de pago toma el monto como Efectivo.
- **Anulación de recibos** (`paCxcReciboAnular`): solo mientras la caja donde
  se cobró siga abierta y con motivo de al menos 5 caracteres. Devuelve el
  saldo a las cuotas, anula la póliza y el monto sale del cuadre de la caja.
  El pago de contado o enganche de una factura se anula con la factura.
- **Anulación de cheques** (`paCxpChequeAnular`): en cualquier momento, salvo
  que el cheque ya esté cobrado. Devuelve el saldo a la cuota y anula la
  póliza; el número de cheque queda usado. `bco_cheque_emitido_det.ppg_id`
  guarda ahora la cuota que paga cada cheque (el `34` la completa en los ya
  emitidos) y las pólizas de pagos anteriores al `29` se ligan a su recibo o
  cheque.
- **Anular una factura o compra con pagos:** la factura se bloquea si tiene
  cobros de cuotas vigentes (se anulan antes los recibos); su pago de
  contado o enganche se anula con ella si la caja sigue abierta y, si ya
  cerró, se bloquea (corresponde una nota de crédito). La compra se bloquea
  si tiene cheques vigentes.
- **Factura:** el límite de crédito del cliente (`cli_limite_credito`, 0 =
  sin límite) se valida contra el saldo pendiente más lo financiado; las
  formas de pago deben sumar el total (contado) o el enganche (crédito) y
  requieren una caja abierta. `paClienteCreditoConsultar` alimenta el
  resumen de crédito disponible en la pantalla.
- El corte y cuadre de caja, los saldos de documentos y los estados de
  cuenta ignoran recibos y cheques anulados.

Errores `53201`-`53229`.

### Costo unitario, factura electrónica y tableros (`35`)

**Costo unitario.**
- **Ventas:** cada línea con producto guarda en `det_costo_unitario` el costo
  promedio del producto en el momento de grabar. Lo pone la base (ya no lo
  manda la pantalla) y la póliza de la venta usa ese costo.
- **Compras:** cada línea guarda `(subtotal - descuento) / cantidad`, sin IVA.
  El costo promedio ponderado del producto se recalcula con ese neto (antes no
  restaba el descuento). Si la existencia llega a cero, el producto conserva
  su último costo.
- Las líneas ya grabadas sin costo se completan: las de compra con su neto;
  las de venta con el costo actual del producto, porque no hay historial.

**Factura electrónica (FEL).** Todo lo que va en el XML sale de parámetros
que se mantienen en **General › Factura electrónica**:

| Dónde | Qué |
|---|---|
| `fel_configuracion` (por compañía) | certificador (`SIMULADOR` o `INFILE`), activo, ambiente, URLs de certificación y anulación, usuario de firma y de la API, correo de copia, tiempo de espera, espacio de nombres y versión del DTE, receptor por defecto (dirección, código postal, municipio, departamento, país) |
| `gen_compania` | afiliación IVA (`GEN`, `PEQ`...), nombre del emisor (razón social), correo |
| `gen_sucursal` | código de establecimiento, nombre comercial, código postal y municipio (departamento y país salen de `gen_provincia` / `gen_estado` / `gen_pais`) |
| `inv_documento_tipo` | tipo de DTE, tipo para la venta de contado (FCAM a crédito, FACT de contado) y si se certifica |
| `inv_unidad_medida` | código FEL de la unidad (3 caracteres) |
| `pos_cliente` | código postal y tipo de receptor (`CUI` o `EXT`; vacío = NIT o CF) |
| `fel_frase` | frases por compañía (tipo y escenario; opcionalmente también en notas) |
| `fel_documento` / `fel_bitacora` | estado FEL de cada documento (P pendiente, R rechazado, C certificado, A anulado, X anulación pendiente), UUID, serie, número, XML enviado, certificado y de anulación, y cada intento |

- **Llaves fuera de la base.** Las llaves de firma y de la API no se guardan
  en la base. Van en la configuración de la aplicación como
  `Fel:Credenciales:<NIT sin guion>:LlaveFirma` y `:LlaveApi`, en
  appsettings, variables de entorno o secretos del servidor.
- **Qué se certifica.** Facturas (FACT/FCAM con el complemento de abonos),
  notas de crédito y débito a clientes (NCRE/NDEB con referencia a la factura)
  y la anulación de un documento certificado.
- **Cuándo.** El envío ocurre en la aplicación justo después de grabar. La
  factura queda grabada aunque el certificador falle:
  - Sin respuesta, queda **Pendiente** y se reintenta sola cada
    `Fel:ReintentoMinutos` (10 por defecto).
  - Si el certificador la rechaza, queda **Rechazada** con el motivo, para
    corregir y reenviar desde **Ventas › Documentos electrónicos**.
  - Una nota cuya factura no está certificada certifica primero la factura.
- `paFelDocumentoDatosConsultar` reemplaza a `spr_sel_pos_factura_xml`: arma
  los datos y la aplicación genera el XML. En el script original se corrigió
  lo siguiente:
  - Las etiquetas `cfc:NumeroAbono`, `cfc:FechaVencimiento` y `cfc:MontoAbono`
    se cerraban como `dte:...` y el XML quedaba inválido.
  - El texto no se escapaba: un `&` o un `<` en una descripción rompía el XML.
  - El IVA era un 12 % fijo (`/1.12`) y todo documento salía como `FCAM`.
  - El nombre comercial, la dirección, el municipio y el código postal del
    emisor estaban escritos en el código.
  - La frase era siempre la misma, el código postal del receptor era `0` y el
    `xsi:schemaLocation` apuntaba a una ruta local del disco.
  - Los montos ahora se calculan con el IVA de cada línea: precio unitario con
    IVA redondeado por unidad, `Precio = Cantidad × PrecioUnitario`, y
    `MontoGravable + MontoImpuesto = Total`. Una línea con IVA 0 va como exenta.
- **Simulador y fechas.** El certificador **SIMULADOR** valida el XML y
  devuelve una autorización con el formato de SAT (sin validez fiscal). Sirve
  para probar sin credenciales. SAT solo acepta documentos con pocos días de
  antigüedad, así que las facturas viejas de los datos de prueba solo se
  certifican con el simulador.
- **URLs de INFILE.** Las URLs por defecto son las del proceso unificado de
  INFILE (firma y certificación en una llamada). Confírmelas con INFILE para
  su ambiente.

**Tableros** (menú **Tableros**, permiso `TABLERO_GERENCIAL`):
`paTableroVentas`, `paTableroCartera` y `paTableroCompras` reciben rango de
fechas y sucursal (la de la bodega del documento). Agrupan por día si el
rango es de hasta 62 días y por mes si es mayor. Devuelven:
- **Ventas:** indicadores contra el período anterior, venta y costo por
  período, mejores clientes, productos y vendedores.
- **Cartera:** saldo y vencido a hoy, cobrado, recuperación (de lo que vencía
  en el período, cuánto se cobró), antigüedad, clientes con más vencido y
  formas de pago.
- **Compras:** compras y pagos por período, por pagar y vencido,
  compromisos de las próximas 12 semanas y próximas cuotas.

Errores `53301`-`53314`. Permisos `TABLERO_GERENCIAL` (Administrador) y
`FEL_ADMIN` (Administrador y Contador).

### Bancos, nómina por período, pago a empleados y centro de costo (`36`)

Menú **Caja y bancos** (permiso `BANCOS_ADMIN`, solo Administrador y Contador):

| Pantalla | Qué hace |
|---|---|
| **Cuentas y chequeras** | Cuentas bancarias de la empresa (`bco_cuenta_bancaria`): banco, número, tipo (`bcb_tipo` M monetaria / A ahorro) y su cuenta contable (`cta_id`; si falta se usa el concepto `PAGO_BANCOS`). Cada cuenta con sus chequeras: rangos sin traslape, siguiente número y cheques disponibles. |
| **Motivos de pago** | Catálogo `bco_motivo_pago`. |
| **Cheques** | Todos los cheques (`bce_tipo` P proveedor, L libre, N nómina) con filtros. Emite el **cheque libre**: beneficiario, motivo, cuenta de gasto y centro de costo; póliza Debe cuenta elegida / Haber banco (origen `CHEQUE`). Marca un cheque como cobrado y anula con motivo: se anula su póliza; el de proveedor devuelve el saldo a la cuota y el de nómina deja al empleado pendiente de pago. |

- El número de cheque se valida contra la chequera (activa, dentro del rango,
  sin repetir); vacío toma el siguiente. Aplica también al cheque a
  proveedor, que ahora usa la cuenta contable de su banco y guarda el
  beneficiario.

**Nómina por período.** `rrhhNomina.TipoPeriodo` acepta `S` semanal, `Q`
quincenal y `M` mensual; cada empleado tiene su `TipoNomina` y solo entra en
las nóminas de su tipo. Al abrir una nómina, `paRrhhNominaPeriodoSugerido`
propone el período que sigue a la última del mismo tipo (semana de lunes a
domingo, quincena 1-15 / 16-fin de mes, mes completo); si no hay ninguna, el
que contiene la fecha de hoy. El traslape solo se valida entre nóminas del
mismo tipo. La semana usa 7 días base y el sueldo semanal es el mensual × 12 / 52.

**Pago a empleados (no se paga en efectivo).** En **RRHH › Empleados ›
Pago de nómina**: forma de pago (`T` transferencia / `C` cheque), banco,
tipo y número de cuenta (obligatorios para transferencia). La nómina guarda
una foto de esos datos y del departamento al calcular y al aprobar; aprobar
exige que todos los empleados con líquido tengan forma de pago. Ya aprobada,
la pestaña de la nómina muestra la sección **Pago** (permiso `BANCOS_ADMIN`):

- **Transferencias:** un lote (`rrhhNominaPago` tipo T) con todos los
  pendientes que cobran por transferencia. Póliza Debe
  `NOMINA_SUELDOS_POR_PAGAR` / Haber banco (origen `PAGO_NOMINA`). Se
  descarga el **listado en Excel**: resumen por banco y una hoja por banco
  destino.
- **Cheques:** uno por empleado con números correlativos de la chequera, cada
  uno con su póliza (origen `CHEQUE`).
- Un pago se anula con motivo (su póliza también). Una nómina con pagos
  vigentes no se puede anular.

**Centro de costo = departamento.** `cont_asiento_det.IdDepartamento` guarda
el centro de costo de cada línea de póliza (nuevo tipo
`cont_asiento_det_cc_type` y `paContabilidadAsientoInsertarCc`; el tipo y el
procedimiento anteriores no cambian). La nómina aprobada desglosa cada
ingreso por el departamento de la plaza del empleado (descuentos y líquido
van sin centro de costo) y el cheque libre lleva el que se elija. Reporte en
**Contabilidad › Centros de costo** (permiso `CONTABILIDAD_CENTRO_COSTO`):
saldo por departamento y cuenta, pólizas de cada línea y exportación a Excel.

También: la periodicidad de la compañía acepta semanal y el `24` ya no falla
al volver a correrlo (no intenta borrar `pago_forma_type`, que usan
procedimientos posteriores).

Datos de prueba (`37`): cuenta de nómina en Banrural con chequera 5001-5050,
datos de pago de los empleados (tres por transferencia, uno con cheque), un
técnico de soporte en nómina semanal, pago de la nómina mensual (lote de
transferencias y cheque), la nómina semanal de la semana pasada aprobada y
pagada, y dos cheques libres con centro de costo.

Errores `53401`-`53439`.

### Inventario físico, inventario inicial, saldos iniciales y carga de empleados (`38`)

**Documentos internos de inventario.** `inv_documento_tipo.tdo_es_interno`
marca los tipos que no son ventas ni compras: `INVI` inventario inicial (+),
`AJIS` sobrante de inventario físico (+) y `AJIF` faltante (-). No aparecen en
Facturas, Compras, cuentas por cobrar/pagar ni en los tableros (el `38`
redefine `paTableroVentas` y `paTableroCompras` con ese filtro).
`paInvDocumentoInternoCrear` los graba y mueve existencias y costo promedio.

**Inventario físico** (**Inventario › Inventario físico**, permiso
`INVENTARIO_FISICO`, administrador y contador):
- Se abre una toma por bodega (`inv_toma_fisica`) con los productos que
  manejan existencia; una toma abierta por bodega.
- La pantalla muestra la existencia del sistema (no editable) y el conteo de
  cada producto. El conteo también se puede llenar en la hoja de Excel de la
  toma y subirla.
- Al aplicar, la diferencia se calcula contra la existencia de ese momento y
  se valora al costo promedio. Los productos sin conteo no se ajustan.
- Sobrante: documento `AJIS` y póliza Debe `INVENTARIO` / Haber
  `INVENTARIO_SOBRANTE`. Faltante: documento `AJIF` y póliza Debe
  `INVENTARIO_FALTANTE` / Haber `INVENTARIO` (origen `AJUSTE_INVENTARIO`).
- Si la nomenclatura no las tiene, el `38` crea las cuentas SOBRANTES DE
  INVENTARIO (bajo 411) y FALTANTES DE INVENTARIO (bajo 511); se pueden
  cambiar en Cuentas de pólizas.
- Anular una toma aplicada anula sus documentos (revierte existencias) y sus
  pólizas.

**Cargas desde Excel.** Todas bajan una plantilla (con instrucciones y los
códigos válidos), validan el archivo completo y solo graban si ninguna fila
tiene error. Muestran cada error o advertencia con su fila.

| Carga | Dónde | Qué hace |
|---|---|---|
| Inventario inicial | **Inventario › Inventario inicial** (`INVENTARIO_CARGA_INICIAL`) | Por sucursal, bodega y producto + unidad: cantidad, costo total y precio de venta con IVA. Crea los productos que no existen, un documento `INVI` por bodega (costo unitario = costo total / cantidad) y el precio de venta en la bodega. No genera póliza. Se puede anular. |
| Saldos iniciales | **Contabilidad › Saldos iniciales** (`CONTABILIDAD_SALDOS_INICIALES`) | Exporta la nomenclatura; el contador pone el Debe o el Haber de cada cuenta de movimiento; al subirla se genera la partida de apertura (origen `APERTURA`). Debe cuadrar; avisa si una cuenta queda con saldo contrario a su naturaleza y si la cuenta del concepto `INVENTARIO` no coincide con el inventario inicial cargado. Una nueva reemplaza (anula) a la vigente solo si se marca Reemplazar. |
| Empleados | **RRHH › Carga de empleados** (`RRHH_ADMIN`) | Alta o actualización por código con plaza, salario, tipo de nómina y datos de pago; los datos opcionales vacíos conservan lo que ya tenía el empleado. |

Datos de prueba (`39`): inventario inicial de tres accesorios en la bodega de
Mixco, una toma aplicada en la bodega principal (un sobrante y un faltante) y
la partida de apertura al 1 de enero con el inventario igual al cargado.

Errores `53501`-`53510`.

### Nomenclatura sin datos confidenciales, cuentas de cargos y abonos, logotipo y productos por proveedor (`40`)

**Nomenclatura.** Las cuentas de bancos migradas del sistema anterior traían
números de cuenta y nombres reales (`1120014`-`1120022`, `2160003` y
`5110058`). `28` ya las carga con nombres sintéticos y `40` renombra las de
una base existente. Solo cambia las que conservan el nombre original: las
reconoce por su huella SHA-256, así el texto original no queda escrito en el
script. Un nombre ya cambiado desde la nomenclatura se respeta.

**Cuentas bancarias: cargos y abonos.** Cada cuenta bancaria
(`bco_cuenta_bancaria`) tiene dos cuentas contables:

| Columna | Movimiento | Se afecta en |
|---|---|---|
| `cta_id_cargo` | Depósitos a la cuenta | Debe |
| `cta_id` | Cheques y pagos desde la cuenta | Haber |

Pueden ser la misma cuenta contable; las cuentas que ya existían quedan con
la misma en ambas. El depósito de caja ahora se hace a una **cuenta
bancaria** (`pos_caja_deposito.bcb_id`, en **Caja › Depósitos**) y su
partida carga la cuenta de cargos de esa cuenta (`fnBcoCuentaContableCargo`;
sin cuenta de cargos usa el concepto `DEPOSITO_BANCOS`). Los cheques siguen
abonando `cta_id` (`fnBcoCuentaContable`). Los depósitos anteriores quedan
en la cuenta de su banco cuando ese banco tiene una sola cuenta. Se
configuran en **Caja y bancos › Cuentas bancarias**.

**Logotipo.** `gen_compania` guarda el logotipo (`cia_logo`,
`cia_logo_tipo`, `cia_logo_actualizado`): PNG, JPG, GIF o WEBP de hasta
1 MB, cargado en **General › Compañías** (detalle). Se muestra en el menú,
la pantalla de inicio de sesión, los documentos impresos (recibos, estados
de cuenta, antigüedad) y el encabezado de los libros de Excel (Excel no
admite WEBP). Sin logotipo se usa el del sistema. La aplicación lo sirve en
`/compania/logo`, que es público porque lo usa la pantalla de inicio de
sesión.

**Productos por proveedor.** `inv_producto_proveedor` suma el código del
producto en el catálogo del proveedor, el último costo de compra (sin IVA),
su fecha y la compra; un producto tiene un solo proveedor preferido (índice
único filtrado). Se mantiene en **Compras › Productos por proveedor** (por
proveedor), en la pestaña **Proveedores** de cada producto y desde
**Proveedores** (botón de productos del proveedor). En **Compras**, al elegir
el proveedor la búsqueda se limita a sus productos (se puede quitar la
marca para buscar en todo el catálogo) y el costo propuesto es el de su
última compra. Los productos que el proveedor todavía no tiene se marcan en
la línea y se relacionan con **Relacionar ahora** o, al grabar, con la
casilla *Relacionar con el proveedor los productos que aún no lo están*.
`paProductoProveedorRegistrarCompra` actualiza el último costo al grabar.

**Vendedor por defecto al facturar.** Ya lo proponía
`paVendedorConsultarPorUsuario` (`25`): usuario → empleado → vendedor.
**Facturas** ahora indica cuándo el vendedor es el del usuario y, si el
usuario no tiene vendedor, dónde vincularlo (**RRHH › Empleados › Vínculos
con el sistema**).

Datos de prueba (`41`): cada compra vigente actualiza el último costo y
relaciona sus productos con el proveedor; las relaciones reciben un código
del proveedor de ejemplo.

Errores `53601`-`53611`.

## Pago a proveedores por factura o por saldo (`42`)

Un solo cheque puede pagar una factura completa, varias cuotas de distintas
compras o todo el saldo del proveedor (antes, un cheque pagaba una sola
cuota).

- `paCxpCuotasPendientesConsultar @PrvId, @EncId`: cuotas con saldo del
  proveedor (todas sus compras o una), de la más antigua a la más reciente.
- `paCxpChequeEmitir`: recibe las cuotas y el monto de cada una en
  `dbo.cxp_pago_cuota_type`. Valida que sean del proveedor, que la compra
  esté vigente y que ningún monto pase del saldo de su cuota; bloquea las
  cuotas mientras las paga. Graba un encabezado por el total (beneficiario =
  proveedor, concepto en `bce_observaciones`), una línea de detalle por
  cuota (`A` abono / `C` cancelación) y una sola póliza: Debe
  `PAGO_PROVEEDORES` con una línea por factura, Haber la cuenta de abonos de
  la cuenta bancaria (o `PAGO_BANCOS`). Sin concepto, lo arma con las
  facturas: *Pago facturas A-2201, A-2245*.
- `paCxpChequeDetalleConsultar`: facturas y cuotas que pagó un cheque.
- `paCxpChequesConsultar` devuelve una fila por cheque con los documentos
  agrupados (*COMP A-2201 #2; COMP A-2245 #1*).
- `paTableroCompras` (tablero de compras) devuelve la compra de cada
  próximo pago.
- La anulación sigue siendo `paCxpChequeAnular` (`36`): devuelve el saldo a
  cada cuota del cheque y anula su póliza.

En la aplicación, **Cuentas por pagar › Pagos a proveedores** funciona como
los cobros a clientes: se elige pagar todo el saldo o una sola factura, se
indica el monto del cheque y **Aplicar a las más antiguas** lo reparte (o
**Todo el saldo** / **Factura completa**, **Todo lo vencido**, o se marcan
las cuotas y se ajusta cada monto). El concepto se arma solo y se puede
editar. Se llega con la compra o el proveedor ya elegidos desde el **Estado
de cuenta** (por compra y *Pagar saldo con cheque*), la **Antigüedad de
saldos** (por proveedor y por compra), el historial de **Compras** y los
**Próximos pagos** del tablero de compras
(`/cxp/pagos?prv=…&enc=…` o `&todo=1`).

Datos de prueba (`43`): tres compras al crédito de *Redes y Conectividad
GT* (PRV04) con cuotas vencidas y por vencer, y un cheque que paga la
primera cuota de A-2201 y abona a la primera de A-2245.

Errores `53701`-`53707`.

## Validación de NIT, consulta al certificador y clientes por NIT (`44`)

**Validación.** `fnNitValido` aplica el algoritmo de SAT (módulo 11): los
dígitos del cuerpo se multiplican de derecha a izquierda por 2, 3, 4…; el
verificador es `(11 − suma mod 11) mod 11` y 10 se escribe `K`
(`42932-5`, `1009-K`). También acepta `C/F`, el CUI de 13 dígitos (válido
como NIT desde 2025) y el NIT de 9 dígitos asignado con el CUI.
`fnCuiValido` valida el DPI: correlativo de 8 dígitos con su verificador
(pesos 2 a 9, módulo 11), departamento 01-22 y municipio dentro de los del
departamento. `fnNitNormalizar` quita espacios, guiones, puntos y diagonales.

Triggers en clientes, proveedores, compañías, empleados y documentos
rechazan un NIT o DPI **nuevo o cambiado** que no sea válido (errores
`53801`-`53807`). Los datos que ya estaban grabados se siguen pudiendo usar;
`paNitRevisionConsultar` los lista y la pantalla **General › Revisión de
NIT** lleva a corregirlos. Los clientes del extranjero (`EXT`) no se validan.
La aplicación valida igual antes de grabar (`NitValidador`).

**Consulta del NIT al certificador.** `fel_certificador` es el catálogo de
certificadores autorizados con su servicio de consulta de NIT: método, URL de
pruebas y de producción (con `{nit}`), cuerpo (`{nit}`, `{usuario}`,
`{llave}`), encabezado que lleva la llave y campo del nombre en la
respuesta. Vienen configurados **INFILE** (*Consulta de Receptores*, POST a
`consultareceptores.feel.com.gt/rest/action`, campo `nombre`) y **DIGIFACT**
(*RTU*, GET `api/RTU?NIT={nit}` con encabezado `Authorization`, campo
`NOMBRE`); G4S, COFIDI, MEGAPRINT, AINNOVA, CCG, CARI y EDICOM quedan
registrados para completar cuando entreguen su documentación, sin cambiar
código. `fel_configuracion` suma `fco_consulta_nit_activa` y
`fco_url_consulta_nit` (URL propia opcional); se cambian con
`paFelConsultaNitGuardar` o en **Factura electrónica › Consulta de NIT**, que
también permite probar un NIT. Las credenciales van en la configuración de la
aplicación: `Fel:Credenciales:<NIT emisor>:ConsultaNitUsuario` y
`:ConsultaNitLlave`.

**Clientes por NIT.** Columna `pos_cliente.cli_nit_normalizado` con índice,
que mantiene el trigger del cliente (una versión anterior la hacía columna
calculada; el 44 la convierte). `paClienteBuscarPorNit` encuentra el cliente sin importar cómo se
escribió el NIT; `paClienteRegistrarPorNit` graba el que no existe con el
nombre que devolvió el certificador (formato de SAT
`APELLIDO,APELLIDO,CASADA,NOMBRE,NOMBRE`) o el que escribió el cajero, con el
siguiente código `CLI###`. En **Facturas** se escanea o busca el producto;
tras el primero el foco pasa al NIT: Enter busca en la base, si no está
consulta al certificador y registra al cliente (errores `53808`-`53810`).

**Otros cambios.**

- `paCxpProveedoresConSaldoConsultar`: solo proveedores con saldo, con lo
  vencido y el número de facturas (lista de **Pagos a proveedores**).
- `sp_usuario_consultar` devuelve el empleado (nombre completo) y el código
  de vendedor. El nombre del vendedor vinculado a un empleado se toma del
  empleado (triggers), para no tenerlo escrito dos veces.
- Permisos nuevos: `COMPRAS_DOCUMENTO_ANULAR`, `VENTAS_VENDEDOR_ADMIN`,
  `INVENTARIO_TRASLADO_ENVIAR`, `INVENTARIO_TRASLADO_RECIBIR` y
  `GENERAL_NIT_REVISION` (el administrador los tiene todos; el contador anula
  compras, revisa NIT y recibe traslados; el cajero recibe traslados).
- La carga de empleados (`paRrhhEmpleadoCargaProcesar`) marca en su fila el
  NIT o el DPI inválido.

## Traslados entre bodegas (`45`)

Entre bodegas de la misma sucursal o de otra. Buenas prácticas aplicadas:
el origen no pierde el control de la mercadería hasta que el destino la
recibe, y la contabilidad la muestra en tránsito.

1. **Envío** (`paInvTrasladoEnviar`, permiso `INVENTARIO_TRASLADO_ENVIAR`):
   genera la **salida por traslado** (`TRS`) en la bodega de origen al costo
   promedio, deja el traslado *En tránsito* y la póliza Debe
   `INVENTARIO EN TRANSITO` / Haber inventario.
2. **Recepción** (`paInvTrasladoRecibir`, permiso
   `INVENTARIO_TRASLADO_RECIBIR`, usuario asignado a la sucursal destino): se
   confirma lo que llegó por línea. Genera el **ingreso por traslado**
   (`TRE`) en la bodega destino al mismo costo y la póliza Debe inventario /
   Haber tránsito. Si falta algo, lo que no llegó se **devuelve a origen**
   (`D`, ingreso de devolución) o se registra como **pérdida** (`P`, a la cuenta de faltantes de inventario).
3. **Rechazo o cancelación** (`paInvTrasladoDevolver`): el destino rechaza
   todo o el origen cancela mientras siga en tránsito; la mercadería regresa
   a la bodega de origen.

El costo promedio no cambia (sale y entra al mismo costo unitario). Estados:
`E` en tránsito, `R` recibido, `P` recibido con diferencias, `X`
rechazado, `N` cancelado. Consultas: `paInvTrasladoConsultar`,
`paInvTrasladoDetalleConsultar`, `paInvTrasladoProductosConsultar` y
`paInvTransitoConsultar` (saldo en tránsito, que cuadra con la cuenta).
Errores `53901`-`53914`. En la aplicación: **Inventario › Traslados entre
bodegas**, con los pendientes de recibir de la sucursal resaltados.

Datos de prueba (`46`): bodega `BOD03` en la casa matriz, un traslado
BOD01 → BOD03 recibido y uno BOD01 → BOD02 (Mixco) en tránsito.

## Error "Ocurrió un error en la base de datos" al grabar facturas (`47`)

Causa: el error SQL **1934**. Un procedimiento creado con
`QUOTED_IDENTIFIER OFF` (un script corrido con `sqlcmd` sin `-I` o desde una
herramienta con esa opción apagada) no puede escribir en tablas con índices
filtrados (`pos_cliente`, `inv_documento_enc`) ni con índice sobre columna
calculada. SQL Server guarda esa opción en cada procedimiento al crearlo.

- `47_reparar_opciones_set.sql` lista los procedimientos, funciones,
  triggers y vistas con `QUOTED_IDENTIFIER` o `ANSI_NULLS` en OFF, los recrea
  con `CREATE OR ALTER` y las opciones en ON (sin cambiar su código ni sus
  permisos) y muestra lo que quede pendiente.
- `paDiagnosticoFacturaProbar` (el 47 lo ejecuta al final) graba una factura
  al crédito de prueba y registra un cliente por NIT dentro de una
  transacción que **siempre se revierte**: no queda factura, cliente, póliza
  ni correlativo. Devuelve `OK` o el error real con su número, procedimiento
  y línea. Se puede volver a ejecutar: `EXEC dbo.paDiagnosticoFacturaProbar @SucId = 1;`.
- El 44 convierte `cli_nit_normalizado` en una columna normal, para que la
  tabla de clientes no exija opciones SET a quien escriba en ella.
- La aplicación muestra ahora el número de error SQL, el procedimiento y la
  línea (y para el 1934 indica correr el 47). Si la factura ya se grabó y
  falla un paso posterior (certificación o pantalla), avisa que **sí quedó
  grabada** para que no se vuelva a grabar.

## Impresión de la factura (`48`)

Representación gráfica del DTE en dos formatos, según la compañía
(**General › Compañías › Impresión de facturas**):

- `cia_factura_impresora`: `C` carta (tinta o láser, p. ej. Epson L3250) o
  `T` térmica de rollo; `cia_factura_ancho_termica` 80 o 58 mm;
  `cia_factura_pie` texto al pie. Se leen y guardan con
  `paCompaniaImpresionConsultar` / `paCompaniaImpresionGuardar`
  (errores `54001`-`54003`).
- `paFacturaImpresionConsultar @EncId` devuelve encabezado (emisor y
  establecimiento, receptor, condición, vendedor, cajero, datos FEL y
  formato), detalle con precios con IVA, frases, cuotas y formas de pago.

La impresión (`/facturas/{id}/imprimir`, botón **Imprimir** en el historial
y en el detalle) lleva: tipo de DTE, serie, número y número de autorización,
fechas de emisión y certificación, emisor (nombre comercial, razón social,
NIT, dirección del establecimiento), receptor, detalle, IVA incluido, total
en letras, frases, abonos de la factura cambiaria, forma de pago, nombre y NIT
del certificador (tomados del XML certificado) y un código QR con el número
de autorización para verificarla en el portal de la SAT. Si el documento
está anulado o no se ha certificado, lo indica con un aviso y una marca de
agua. En térmica, el largo del papel se ajusta al contenido.

## Módulos nuevos

- **Seguridad (`sec_*`)**: roles, permisos y las tablas de asignación
  `sec_rol_permiso` / `sec_usuario_rol`, más `gen_auditoria` (bitácora
  genérica pensada para poblarse con triggers `FOR JSON` sobre las tablas que
  se necesite auditar).
- **Multi-moneda (`gen_moneda`, `gen_tipo_cambio`)**: cada documento
  (`inv_documento_enc`) y cada precio de producto (`inv_producto_precio`)
  quedan ligados a una moneda; `fn_moneda_local()` resuelve la moneda
  funcional de la compañía para usarla como valor por defecto.
- **Contabilidad (`cont_*`)**: catálogo de cuentas, períodos contables y un
  libro de asientos de partida doble. Un trigger (`trg_cont_asiento_det_valida_balance`)
  impide que quede grabado un asiento donde Debe ≠ Haber — por eso el detalle
  de un asiento siempre se inserta en una sola sentencia (`sp_contabilidad_insertar_asiento`),
  nunca línea por línea. `sp_contabilidad_generar_asiento_documento` genera
  automáticamente el asiento de cada venta/compra con las subcuentas que
  cada concepto tiene asignadas en `cont_cuenta_parametro` (ver
  «Nomenclatura contable»). Es una
  contabilización **simplificada**, pensada para que el modelo sea funcional
  y fácil de adaptar; no reemplaza un motor fiscal certificado.

## Procedimientos almacenados

- **CRUD** (`10_procedimientos_crud.sql`) para las entidades principales:
  producto, cliente, proveedor, usuario (con manejo seguro de contraseña),
  bodega, cuenta bancaria, cuenta contable, rol/permiso, y consulta de
  documentos. Los catálogos simples (país, tipo de documento, etc.) se
  mantienen con `INSERT`/`UPDATE` directos, sin un procedimiento dedicado por
  cada uno.
- **Procesos de negocio** (`11_procedimientos_procesos.sql`): crear factura
  (`sp_ventas_crear_factura`) y compra (`sp_compras_crear_documento`) con
  ajuste de inventario, generación de plan de pagos y asiento contable
  automático, todo dentro de una sola transacción (`TRY/CATCH` +
  `XACT_ABORT`); anular documento; registrar cobro de cuota
  (`sp_pos_registrar_pago_cuota`); emitir cheque a proveedor
  (`sp_bancos_emitir_cheque_pago_proveedor`); apertura/cierre de caja; login
  seguro.

## Datos sintéticos (`12_datos_sinteticos.sql`)

Volumen ligero: catálogos con 20-50 filas (países, departamentos, productos,
clientes, proveedores, etc.) y un flujo de transacciones generado **a través
de los mismos procedimientos** (no con `INSERT` directo), para que la carga
de datos sirva también como prueba de humo de todo el paquete:

1. Compra inicial que abastece el inventario de todos los productos que
   controlan existencia.
2. ~10 compras de reabastecimiento adicionales, en fechas aleatorias.
3. ~35 facturas de venta a clientes aleatorios, todas a crédito (1 a 6
   cuotas), validando que haya existencia suficiente antes de grabar. La
   factura de contado se prueba desde la pantalla de Facturas.
4. Cobro de hasta 15 cuotas de clientes.
5. Pago con cheque de hasta 10 cuotas de proveedores.
6. Anulación de 1-2 facturas, para probar `sp_documento_anular`.

Las compras se graban con fecha de primer pago, para que generen su plan de
pagos al proveedor y haya cuotas que pagar con cheque.

**Corrección:** hasta esta versión, el `12` (y el reintento del `13`) solo
grababa la primera factura y la primera compra de reabastecimiento; las
demás fallaban en silencio. Una variable de tabla declarada dentro de un
`WHILE` no se vacía en cada vuelta, así que desde la segunda vuelta repetía
las líneas anteriores y chocaba con la llave única de `det_item`. Los errores
quedaban atrapados por `TRY/CATCH` y solo se imprimían. Ahora se vacía al
inicio de cada vuelta, y el `13` ya no reintenta si las compras existen.

`33_datos_sinteticos_cxc_organigrama.sql` arma el organigrama de ejemplo
(Junta Directiva › Gerencias de Operaciones, IT, Financiera y RRHH ›
departamentos, con dos plazas vacantes en IT), graba una factura a crédito
con un producto y dos líneas de servicio (3.5 horas de instalación y una
capacitación) y registra una nota de cada tipo.

`30_datos_sinteticos_procesos.sql` agrega lo que el `12` no puede generar
porque sus procedimientos se crean después: tres cobros en efectivo, un
depósito, el cierre de la caja con un faltante de Q2.00 (sube la tolerancia
de la compañía a Q5.00 si era 0) y la apertura de una caja nueva, y la
nómina del mes en curso calculada y aprobada. Al terminar muestra las pólizas
por origen y cuántas no cuadran (deben ser 0).

Las contraseñas de los usuarios de ejemplo (`admin`, `jperez`, `mgarcia`,
`lrodriguez`) son todas `Demo#2024` — solo para este juego de datos de
prueba.

## Limitaciones conocidas / decisiones de alcance

- La contabilización automática es una simplificación (una sola tasa de
  IVA por compañía, `cia_porc_iva`, sin múltiples tasas ni exenciones) pensada para demostrar el patrón
  de asiento balanceado, no para cumplimiento fiscal real.
- Anular una factura no cambia sus cuotas (quedan fuera de los saldos porque
  todas las consultas toman solo documentos vigentes).
- La anulación de pólizas marca la póliza como anulada (`asi_estado = 'N'`);
  no genera una póliza de reversión con fecha de la anulación.
- Una nota de crédito solo se aplica a un documento con saldo pendiente: la
  devolución de una factura de contado ya pagada (que implicaría reembolso)
  no está cubierta.
- La antigüedad de saldos usa el saldo actual de cada cuota; con una fecha
  de corte pasada no descuenta los pagos hechos después de esa fecha.
- La factura electrónica guarda el XML en `fel_documento`; la columna
  `enc_xml` del script original se conserva pero no se usa (el UUID queda en
  `enc_numero_autorizacion`). La integración con INFILE está hecha según su
  proceso unificado pero no se probó contra INFILE (no hay credenciales en
  este ambiente); se probó con el simulador y los casos de falla.
- El costeo de inventario usa costo promedio ponderado (como el script
  original), no PEPS/UEPS.
