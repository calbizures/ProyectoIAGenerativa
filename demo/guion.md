# Guion de la demo — ERP · Servicios Informáticos Integrados

Video de 11:50 min, 1920×1080, 30 fps. Sin locución: la explicación va en rótulos en pantalla y el fondo es música instrumental original (generada por `musica.py`, libre de derechos). Los tiempos son del video final.

| Tiempo | Sección |
|---|---|
| 0:00 | Portada |
| 0:09 | 01 · Acceso |
| 0:34 | 02 · Tableros gerenciales |
| 1:32 | 03 · Ventas y facturación |
| 2:56 | 04 · Factura electrónica (FEL) |
| 3:44 | 05 · Cuentas por cobrar |
| 4:34 | 06 · Compras e inventario |
| 6:09 | 07 · Inventario físico |
| 7:02 | 08 · Proveedores y caja |
| 8:02 | 09 · Bancos |
| 8:57 | 10 · Contabilidad |
| 9:34 | 11 · Recursos humanos |
| 10:30 | 12 · Puesta en marcha (cargas desde Excel) |
| 11:00 | 13 · Administración y seguridad |
| 11:40 | Cierre |
| 11:50 | Fin |

## 0:00 · Portada

- `0:01` **Cortinilla:** *ERP · Servicios Informáticos Integrados*. Recorrido por el producto: de la venta a la contabilidad, en una sola plataforma web. Puntos: Tableros gerenciales; Facturación con FEL; Cuentas por cobrar y pagar; Compras e inventario físico; Caja, bancos y cheques; Contabilidad automática; Nómina y RRHH; Arranque desde Excel.

## 0:09 · 01 · Acceso

- `0:10` **Inicio de sesión seguro.** Cada persona entra con su usuario y contraseña. Las contraseñas se guardan con hash seguro, nunca en texto plano.
- `0:19` **Sucursal de trabajo.** Se elige la sucursal en la que se trabajará; solo aparecen las asignadas al usuario. La caja, las bodegas y la factura electrónica toman ese dato.
- `0:27` **Menú según permisos.** El menú muestra solo los módulos que el rol del usuario puede usar. La barra inferior indica sucursal, usuario y base de datos.

## 0:34 · 02 · Tableros gerenciales

- `0:34` **Cortinilla:** 02 · Tableros — *Tableros gerenciales*. La información para decidir, al día y en una sola pantalla. Puntos: Ventas y margen bruto; Recuperación de cartera; Compras y compromisos; Filtros por período y sucursal.
- `0:41` **Indicadores del período.** Ventas netas sin IVA, margen bruto calculado con el costo real de cada línea, número de facturas y notas de crédito.
- `0:46` **Detalle al pasar el puntero.** Cada columna muestra costo, margen y total del mes. Todos los gráficos tienen también una vista de tabla.
- `0:56` **Del mes al día.** Un clic en un mes muestra sus ventas día por día; «Volver» regresa a la vista mensual.
- `1:08` **Clientes, productos y vendedores.** Rankings del período. Un clic en un cliente abre directamente su estado de cuenta.
- `1:16` **Recuperación de cartera.** Lo que vencía contra lo cobrado, la antigüedad de los saldos y los clientes con mora.
- `1:25` **Compras y compromisos de pago.** Compras del período, saldo por pagar y lo que vence en las próximas 12 semanas, para planificar el flujo de caja.

## 1:32 · 03 · Ventas y facturación

- `1:33` **Cortinilla:** 03 · Facturación — *Ventas y facturación*. Una factura completa en pocos pasos, con validaciones en línea. Puntos: Bienes y servicios juntos; Contado o crédito con cuotas; Límite de crédito del cliente; Certificación FEL al grabar.
- `1:39` **Historial de facturas.** Búsqueda por número o cliente, paginación y detalle. Anular exige motivo y confirmación, y revierte inventario y póliza.
- `1:46` **Vendedor del usuario.** Si quien factura es vendedor, la factura lo propone solo. El usuario de la demo no lo es, así que el sistema indica dónde vincularlo.
- `1:51` **Nueva factura.** El cliente se busca por código, nombre o NIT; si no existe se da de alta sin salir de la factura.
- `2:15` **Bienes y servicios en la misma factura.** La columna B/S distingue productos de inventario y servicios. Los precios incluyen IVA y los totales se calculan al instante.
- `2:28` **Venta al crédito con límite.** Se muestran límite, saldo y crédito disponible del cliente. Si el monto a financiar lo excede, no se puede grabar.
- `2:37` **Plan de pagos.** Las cuotas se generan al grabar y alimentan cuentas por cobrar, la antigüedad de saldos y el tablero de cartera.
- `2:48` **Factura certificada al grabar.** Al grabar se envía al certificador y se recibe la autorización (UUID), serie y número de SAT. Si el certificador no responde, la factura queda grabada como pendiente y se reintenta sola.

## 2:56 · 04 · Factura electrónica (FEL)

- `2:56` **Cortinilla:** 04 · Factura electrónica — *FEL parametrizada*. Cumplimiento con SAT sin depender de un proveedor fijo. Puntos: INFILE o simulador de pruebas; XML armado desde parámetros; Reintento automático; Anulación ante SAT con motivo.
- `3:02` **Documentos electrónicos.** Estado FEL de cada factura y nota: no enviado, pendiente, rechazado, certificado o anulado ante SAT.
- `3:07` **Certificación en lote.** Los documentos anteriores se envían de una vez, del más antiguo al más reciente; cada nota espera a que su factura de origen esté certificada.
- `3:21` **XML y bitácora.** Se guardan el XML enviado y el certificado, descargables, y cada intento queda en la bitácora con su resultado.
- `3:23` **Panel:** fragmento real del XML del DTE (GTDocumento 0.1) enviado al certificador.
- `3:31` **Todo parametrizado.** Certificador, ambiente, emisor, establecimientos, frases, tipos de DTE y unidades. Las llaves del certificador se guardan fuera de la base de datos.

## 3:44 · 05 · Cuentas por cobrar

- `3:44` **Cortinilla:** 05 · Cuentas por cobrar — *Cartera bajo control*. Del saldo del cliente al recibo impreso. Puntos: Estado de cuenta y cartera; Varias cuotas en un recibo; Recibo imprimible y anulable; Antigüedad con Excel.
- `3:51` **Clientes con saldo.** La cartera completa al abrir la pantalla; un clic muestra el estado de cuenta del cliente.
- `3:56` **Estado de cuenta.** Facturas, cuotas, cobros y notas con su saldo, más indicadores de lo vencido. Se puede imprimir.
- `4:01` **Cobro de cuotas.** Se busca al cliente y aparecen sus cuotas pendientes, de todas sus facturas.
- `4:11` **Aplicación automática.** El monto recibido se reparte entre las cuotas más antiguas; se puede ajustar a mano cuota por cuota.
- `4:19` **Un recibo, varias cuotas.** Se genera un solo recibo con su póliza contable. Mientras la caja siga abierta puede anularse, con motivo.
- `4:24` **Recibo listo para imprimir.** Detalle de cuotas aplicadas y formas de pago.
- `4:29` **Antigüedad de saldos.** Saldos por rangos de días, por cliente o por factura, con exportación a Excel y vista para imprimir.

## 4:34 · 06 · Compras e inventario

- `4:34` **Cortinilla:** 06 · Compras e inventario — *Compras con costo real*. Cada compra actualiza existencias, costo promedio y el último costo del proveedor. Puntos: Productos por proveedor; Compras con descuento; Costo promedio ponderado; Plan de pagos al proveedor.
- `4:45` **Costo antes de la compra.** Cada producto lleva su costo promedio, precios por bodega, características, existencias y proveedores.
- `5:05` **Los productos del proveedor.** Al elegir el proveedor, la búsqueda muestra sus productos, con su código en el catálogo del proveedor y el costo de su última compra. Si se compra algo que aún no le corresponde, se marca y se relaciona en el momento.
- `5:22` **Compra con descuento.** 10 laptops a Q4,256 con IVA y Q2,240 de descuento. El costo que entra al inventario es neto de descuento y sin IVA: Q3,600 por unidad.
- `5:36` **Crédito del proveedor.** Las cuotas al proveedor alimentan cuentas por pagar y los compromisos de pago del tablero.
- `5:44` **Grabada: inventario, costo y póliza.** En una sola transacción sube la existencia, se recalcula el costo promedio y se genera la póliza de compra.
- `5:53` **Costo promedio actualizado.** (Q3,224.00 × 119 + Q3,600.00 × 10) ÷ 129 = Q3,253.15. La siguiente venta grabará ese costo en su línea y en la póliza de costo de ventas.
- `6:02` **Productos por proveedor.** Lo que vende cada proveedor: código en su catálogo, proveedor preferido y último costo, que la compra recién grabada dejó en Q3,600 sin IVA. También se mantiene desde cada producto.

## 6:09 · 07 · Inventario físico

- `6:10` **Cortinilla:** 07 · Inventario físico — *Inventario físico*. El conteo de cada bodega contra el sistema, con su ajuste y su póliza. Puntos: Toma por sucursal y bodega; Conteo en pantalla o con Excel; Sobrante contra ingresos; Faltante contra gastos.
- `6:16` **Tomas de inventario.** Cada toma es de una bodega. La lista muestra cuánto se contó y el valor de los sobrantes y faltantes ajustados.
- `6:29` **Existencia del sistema junto al conteo.** La existencia no se puede modificar; se anota lo contado. También se puede bajar la hoja de conteo en Excel, llenarla en la bodega y subirla.
- `6:45` **Diferencias valoradas.** Un sobrante y un faltante, valorados al costo promedio de cada producto.
- `6:55` **Ajuste con póliza.** Se generan el documento de sobrante (contra ingresos) y el de faltante (contra gastos), cada uno con su póliza. Anular la toma revierte existencias y pólizas.

## 7:02 · 08 · Proveedores y caja

- `7:02` **Cortinilla:** 08 · Proveedores y caja — *Pagos y caja*. El dinero que entra y sale, cuadrado todos los días. Puntos: Pagos con cheque; Antigüedad de proveedores; Apertura, corte y cierre de caja; Depósitos a la cuenta bancaria.
- `7:09` **Pagos con cheque.** Se eligen las cuotas del proveedor y se emite el cheque con su póliza. Se puede anular con motivo mientras no se haya cobrado.
- `7:19` **Antigüedad de proveedores.** Lo que se debe por rangos de vencimiento, por proveedor o por compra.
- `7:25` **Caja por sucursal.** Apertura con monto inicial; no se abre un día nuevo si el anterior quedó sin cerrar.
- `7:33` **Corte y cierre con cuadre.** El sistema calcula lo esperado por forma de pago; el cajero cuenta lo físico y la diferencia (faltante o sobrante) genera su póliza.
- `7:52` **Depósito a una cuenta bancaria.** El efectivo se deposita en una cuenta bancaria de la empresa; la póliza carga la cuenta contable de depósitos de esa cuenta.

## 8:02 · 09 · Bancos

- `8:02` **Cortinilla:** 09 · Bancos — *Cuentas, chequeras y cheques*. Cada movimiento bancario con su cuenta contable y su póliza. Puntos: Cuenta de depósitos y de cheques; Chequeras con correlativo; Cheques libres con centro de costo; Cobrados y anulados con motivo.
- `8:09` **Cuentas bancarias.** Cada cuenta de la empresa tiene dos cuentas contables: la de cargos, que reciben los depósitos, y la de abonos, que afectan los cheques y pagos.
- `8:26` **Chequeras.** Rangos de cheques por cuenta sin traslapes; el sistema propone siempre el siguiente número disponible.
- `8:33` **Cheque libre.** Pago que no viene de una compra: beneficiario, motivo, cuenta de gasto y centro de costo. Genera su póliza al emitirlo.
- `8:51` **Todos los cheques.** Cheques a proveedores, libres y de nómina en una sola lista. Se marcan como cobrados o se anulan con motivo, lo que anula su póliza.

## 8:57 · 10 · Contabilidad

- `8:57` **Cortinilla:** 10 · Contabilidad — *Contabilidad automática*. Cada operación genera su póliza de partida doble, siempre cuadrada. Puntos: Nomenclatura por nodos; Pólizas automáticas; Centros de costo; Anulaciones reflejadas.
- `9:04` **Nomenclatura contable.** Catálogo jerárquico: activo, pasivo, capital, ingresos y gastos, mantenido por nodos.
- `9:11` **Cuentas y subcuentas.** Cada nodo muestra su código, nivel y si acepta movimientos; se agregan cuentas sin romper la estructura.
- `9:16` **Pólizas automáticas.** Venta, compra, cobro, cheque, depósito, cierre de caja, nómina, notas y ajustes de inventario generan su póliza. Aquí se asigna la cuenta contable de cada concepto.
- `9:28` **Gasto por centro de costo.** Cada departamento es un centro de costo: la nómina reparte los sueldos por departamento y los cheques libres llevan el suyo, como el que se acaba de emitir. Se exporta a Excel.

## 9:34 · 11 · Recursos humanos

- `9:35` **Cortinilla:** 11 · Recursos humanos — *Personas y nómina*. Empleados, nómina por período y pago sin efectivo, integrados con contabilidad. Puntos: Nómina semanal, quincenal o mensual; Transferencia o cheque; Centro de costo por departamento; Organigrama.
- `9:41` **Empleados.** Puesto, departamento, tipo de nómina y forma de pago de cada colaborador; puede vincularse a su usuario y a su código de vendedor.
- `9:50` **Datos de pago.** No se paga en efectivo: transferencia a su cuenta (banco, tipo y número) o cheque. Su departamento es el centro de costo de su sueldo.
- `10:00` **Período sugerido.** Al elegir semanal, quincenal o mensual se propone el período que sigue a la última nómina de ese tipo; las fechas se pueden cambiar.
- `10:11` **Nómina aprobada.** Ingresos y descuentos por empleado; al aprobarla se genera la póliza con el gasto por centro de costo.
- `10:15` **Pago de la nómina.** Lote de transferencias con su listado por banco en Excel, o cheques correlativos para quienes cobran con cheque. Cada pago lleva su póliza.
- `10:25` **Organigrama.** Unidades anidadas sin límite de niveles; el organigrama se dibuja solo a partir de la estructura registrada.

## 10:30 · 12 · Puesta en marcha (cargas desde Excel)

- `10:30` **Cortinilla:** 12 · Puesta en marcha — *Arranque desde Excel*. Los datos iniciales de la empresa se cargan con plantillas de Excel, validadas antes de grabar. Puntos: Inventario inicial por bodega; Saldos iniciales y partida de apertura; Carga de empleados; Errores señalados por fila.
- `10:36` **Tres pasos.** Se baja la plantilla (con instrucciones y los códigos válidos), se llena y se sube. El archivo se valida completo: si una fila tiene error no se graba nada.
- `10:43` **Inventario inicial.** Por sucursal, bodega y producto: crea los productos que faltan, sus existencias, el costo promedio (costo total ÷ cantidad) y el precio de venta con IVA.
- `10:49` **Saldos iniciales.** La nomenclatura se exporta a Excel, el contador pone el Debe o el Haber de cada cuenta y se genera la partida de apertura. Debe cuadrar y avisa si el inventario no coincide con el cargado.
- `10:55` **Carga de empleados.** Alta o actualización por código, con plaza, salario, tipo de nómina y datos de pago.

## 11:00 · 13 · Administración y seguridad

- `11:00` **Cortinilla:** 13 · Administración — *Seguridad y configuración*. Cada quien ve y hace solo lo que le corresponde, con la imagen de su empresa. Puntos: Roles y permisos; Logotipo de la empresa; Compañías y sucursales; Auditoría de cada registro.
- `11:07` **Roles.** Administrador, contador, vendedor, cajero… cada rol agrupa permisos.
- `11:11` **Permisos por pantalla.** Cada pantalla exige su permiso y los cambios se aplican a las sesiones abiertas en menos de un minuto.
- `11:19` **Logotipo de la empresa.** El ERP lleva el logotipo de la empresa que lo usa, cargado en la compañía (PNG, JPG, GIF o WEBP).
- `11:29` **En todo el sistema.** El logotipo aparece en el menú, en el inicio de sesión, en los recibos y reportes impresos y en el encabezado de los libros de Excel.
- `11:35` **Sucursales y bodegas.** Multi-sucursal y multi-bodega. Cada registro guarda quién y cuándo lo creó y lo modificó.

## 11:40 · Cierre

- `11:40` **Cortinilla:** *Servicios Informáticos Integrados*. Un ERP completo en la web: ventas con factura electrónica, cartera, compras e inventario, bancos, contabilidad y RRHH. Puntos: Pólizas automáticas; Costos y márgenes reales; Arranque desde Excel; Seguridad por roles y sucursal.

## Qué se ve en pantalla

- Todo es la aplicación real corriendo contra SQL Server con los datos de prueba (scripts 00 a 41): la factura, el cobro, la compra, la toma de inventario, el depósito, el cheque y el logotipo se graban de verdad durante la grabación.
- La factura electrónica usa el **simulador** de certificación (UUID, serie y número de prueba, sin validez fiscal). Con INFILE el flujo es el mismo.
- Usuario de la demo: `admin`, sucursal *Casa matriz Zona 10*.

## Si se quiere agregar voz

Cada rótulo de arriba sirve como texto de locución, en el tiempo indicado. Una voz grabada puede mezclarse sobre la música bajándola unos 10 dB mientras se habla.
