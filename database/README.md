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
```

`25`, `26` y `27` se corren siempre (también en una instalación nueva) y se
pueden volver a correr. **Importante:** `11` y `23` todavía contienen la
versión anterior de `sp_pos_caja_cerrar` y `paCorteCajaTeoricoConsultar`
(sin el cuadre obligatorio); si vuelves a correr cualquiera de los dos,
vuelve a correr después `26` y `27`.

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
factura, se cobre o no ese día). La anulación genera la póliza inversa.
Los cobros de cuotas, los depósitos, el cierre de caja (faltantes y
sobrantes) y la nómina ya tienen sus conceptos parametrizados, pero su
póliza se generará cuando se construya el módulo de Contabilidad.

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

- La contabilización automática es una simplificación (una sola tasa de
  IVA por compañía, `cia_porc_iva`, sin múltiples tasas ni exenciones) pensada para demostrar el patrón
  de asiento balanceado, no para cumplimiento fiscal real.
- `sp_documento_anular` no revierte automáticamente las cuotas de plan de
  pago ya generadas.
- No se implementó el flujo de firma/certificación electrónica de facturas
  (FEL) que insinuaba la columna `enc_xml` del script original; la columna
  se conserva por compatibilidad pero ningún procedimiento la llena todavía.
- El costeo de inventario usa costo promedio ponderado (como el script
  original), no PEPS/UEPS.
