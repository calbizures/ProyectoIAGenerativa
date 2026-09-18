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
```

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
  automáticamente el asiento de cada venta/compra usando el catálogo de
  cuentas sembrado en `12_datos_sinteticos.sql` (1105 Caja, 1110 Bancos, 1150
  IVA crédito, 1205 Clientes, 1310 Inventarios, 2105 Proveedores, 2205 IVA
  débito, 4105 Ventas, 5105 Costo de ventas, 5205 Gastos generales). Es una
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
3. ~35 facturas de venta a clientes aleatorios (algunas de contado, otras a
   crédito con 2-6 cuotas), validando que haya existencia suficiente antes de
   grabar.
4. Cobro de hasta 15 cuotas de clientes.
5. Pago con cheque de hasta 10 cuotas de proveedores.
6. Anulación de 1-2 facturas, para probar `sp_documento_anular`.

Las contraseñas de los usuarios de ejemplo (`admin`, `jperez`, `mgarcia`,
`lrodriguez`) son todas `Demo#2024` — solo para este juego de datos de
prueba.

## Limitaciones conocidas / decisiones de alcance

- La contabilización automática es una simplificación (un IVA único del
  12%, sin múltiples tasas ni exenciones) pensada para demostrar el patrón
  de asiento balanceado, no para cumplimiento fiscal real.
- `sp_documento_anular` no revierte automáticamente las cuotas de plan de
  pago ya generadas.
- No se implementó el flujo de firma/certificación electrónica de facturas
  (FEL) que insinuaba la columna `enc_xml` del script original; la columna
  se conserva por compatibilidad pero ningún procedimiento la llena todavía.
- El costeo de inventario usa costo promedio ponderado (como el script
  original), no PEPS/UEPS.
