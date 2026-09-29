# Guion de la demo — ERP · Servicios Informáticos Integrados

Video de 8:10 min, 1920×1080, 30 fps. Sin locución: la explicación va en rótulos en pantalla y el fondo es música instrumental original (generada por `musica.py`, libre de derechos). Los tiempos son del video final.

| Tiempo | Sección |
|---|---|
| 0:00 | Portada |
| 0:09 | 01 · Acceso |
| 0:34 | 02 · Tableros gerenciales |
| 1:33 | 03 · Ventas y facturación |
| 2:53 | 04 · Factura electrónica (FEL) |
| 3:41 | 05 · Cuentas por cobrar |
| 4:32 | 06 · Compras e inventario |
| 5:53 | 07 · Proveedores, caja y bancos |
| 6:42 | 08 · Contabilidad |
| 7:10 | 09 · Recursos humanos |
| 7:40 | 10 · Administración y seguridad |
| 8:01 | Cierre |
| 8:10 | Fin |

## 0:00 · Portada

- `0:01` **Cortinilla:** *ERP · Servicios Informáticos Integrados*. Recorrido por el producto: de la venta a la contabilidad, en una sola plataforma web. Puntos: Tableros gerenciales; Facturación con FEL; Cuentas por cobrar y pagar; Compras e inventario; Caja y bancos; Contabilidad automática; Recursos humanos; Seguridad por roles.

## 0:09 · 01 · Acceso

- `0:10` **Inicio de sesión seguro.** Cada persona entra con su usuario y contraseña. Las contraseñas se guardan con hash seguro, nunca en texto plano.
- `0:19` **Sucursal de trabajo.** Se elige la sucursal en la que se trabajará; solo aparecen las asignadas al usuario. La caja, las bodegas y la factura electrónica toman ese dato.
- `0:27` **Menú según permisos.** El menú muestra solo los módulos que el rol del usuario puede usar. La barra inferior indica sucursal, usuario y base de datos.

## 0:34 · 02 · Tableros gerenciales

- `0:34` **Cortinilla:** 02 · Tableros — *Tableros gerenciales*. La información para decidir, al día y en una sola pantalla. Puntos: Ventas y margen bruto; Recuperación de cartera; Compras y compromisos; Filtros por período y sucursal.
- `0:41` **Indicadores del período.** Ventas netas sin IVA, margen bruto calculado con el costo real de cada línea, número de facturas y notas de crédito.
- `0:47` **Detalle al pasar el puntero.** Cada columna muestra costo, margen y total del mes. Todos los gráficos tienen también una vista de tabla.
- `0:57` **Del mes al día.** Un clic en un mes muestra sus ventas día por día; «Volver» regresa a la vista mensual.
- `1:08` **Clientes, productos y vendedores.** Rankings del período. Un clic en un cliente abre directamente su estado de cuenta.
- `1:17` **Recuperación de cartera.** Lo que vencía contra lo cobrado, la antigüedad de los saldos y los clientes con mora.
- `1:26` **Compras y compromisos de pago.** Compras del período, saldo por pagar y lo que vence en las próximas 12 semanas, para planificar el flujo de caja.

## 1:33 · 03 · Ventas y facturación

- `1:33` **Cortinilla:** 03 · Facturación — *Ventas y facturación*. Una factura completa en pocos pasos, con validaciones en línea. Puntos: Bienes y servicios juntos; Contado o crédito con cuotas; Límite de crédito del cliente; Certificación FEL al grabar.
- `1:40` **Historial de facturas.** Búsqueda por número o cliente, paginación y detalle. Anular exige motivo y confirmación, y revierte inventario y póliza.
- `1:47` **Nueva factura.** El cliente se busca por código, nombre o NIT; si no existe se da de alta sin salir de la factura.
- `2:11` **Bienes y servicios en la misma factura.** La columna B/S distingue productos de inventario y servicios. Los precios incluyen IVA y los totales se calculan al instante.
- `2:25` **Venta al crédito con límite.** Se muestran límite, saldo y crédito disponible del cliente. Si el monto a financiar lo excede, no se puede grabar.
- `2:34` **Plan de pagos.** Las cuotas se generan al grabar y alimentan cuentas por cobrar, la antigüedad de saldos y el tablero de cartera.
- `2:45` **Factura certificada al grabar.** Al grabar se envía al certificador y se recibe la autorización (UUID), serie y número de SAT. Si el certificador no responde, la factura queda grabada como pendiente y se reintenta sola.

## 2:53 · 04 · Factura electrónica (FEL)

- `2:53` **Cortinilla:** 04 · Factura electrónica — *FEL parametrizada*. Cumplimiento con SAT sin depender de un proveedor fijo. Puntos: INFILE o simulador de pruebas; XML armado desde parámetros; Reintento automático; Anulación ante SAT con motivo.
- `2:59` **Documentos electrónicos.** Estado FEL de cada factura y nota: no enviado, pendiente, rechazado, certificado o anulado ante SAT.
- `3:04` **Certificación en lote.** Los documentos anteriores se envían de una vez, del más antiguo al más reciente; cada nota espera a que su factura de origen esté certificada.
- `3:18` **XML y bitácora.** Se guardan el XML enviado y el certificado, descargables, y cada intento queda en la bitácora con su resultado.
- `3:20` **Panel:** fragmento real del XML del DTE (GTDocumento 0.1) enviado al certificador.
- `3:28` **Todo parametrizado.** Certificador, ambiente, emisor, establecimientos, frases, tipos de DTE y unidades. Las llaves del certificador se guardan fuera de la base de datos.

## 3:41 · 05 · Cuentas por cobrar

- `3:41` **Cortinilla:** 05 · Cuentas por cobrar — *Cartera bajo control*. Del saldo del cliente al recibo impreso. Puntos: Estado de cuenta y cartera; Varias cuotas en un recibo; Recibo imprimible y anulable; Antigüedad con Excel.
- `3:48` **Clientes con saldo.** La cartera completa al abrir la pantalla; un clic muestra el estado de cuenta del cliente.
- `3:54` **Estado de cuenta.** Facturas, cuotas, cobros y notas con su saldo, más indicadores de lo vencido. Se puede imprimir.
- `3:59` **Cobro de cuotas.** Se busca al cliente y aparecen sus cuotas pendientes, de todas sus facturas.
- `4:09` **Aplicación automática.** El monto recibido se reparte entre las cuotas más antiguas; se puede ajustar a mano cuota por cuota.
- `4:17` **Un recibo, varias cuotas.** Se genera un solo recibo con su póliza contable. Mientras la caja siga abierta puede anularse, con motivo.
- `4:22` **Recibo listo para imprimir.** Detalle de cuotas aplicadas y formas de pago.
- `4:27` **Antigüedad de saldos.** Saldos por rangos de días, por cliente o por factura, con exportación a Excel y vista para imprimir.

## 4:32 · 06 · Compras e inventario

- `4:32` **Cortinilla:** 06 · Compras e inventario — *Compras con costo real*. Cada compra actualiza existencias y costo promedio. Puntos: Compras con descuento; Costo promedio ponderado; Existencias por bodega; Plan de pagos al proveedor.
- `4:43` **Costo antes de la compra.** Cada producto lleva su costo promedio, precios por bodega, características y existencias.
- `5:14` **Compra con descuento.** 10 laptops a Q4,256 con IVA y Q2,240 de descuento. El costo que entra al inventario es neto de descuento y sin IVA: Q3,600 por unidad.
- `5:27` **Crédito del proveedor.** Las cuotas al proveedor alimentan cuentas por pagar y los compromisos de pago del tablero.
- `5:35` **Grabada: inventario, costo y póliza.** En una sola transacción sube la existencia, se recalcula el costo promedio y se genera la póliza de compra.
- `5:45` **Costo promedio actualizado.** (Q3,224.00 × 110 + Q3,600.00 × 10) ÷ 120 = Q3,255.33. La siguiente venta grabará ese costo en su línea y en la póliza de costo de ventas.

## 5:53 · 07 · Proveedores, caja y bancos

- `5:53` **Cortinilla:** 07 · Proveedores y bancos — *Pagos, caja y bancos*. El dinero que entra y sale, cuadrado todos los días. Puntos: Pagos con cheque; Antigüedad de proveedores; Apertura, corte y cierre de caja; Depósitos bancarios.
- `6:00` **Pagos con cheque.** Se eligen las cuotas del proveedor y se emite el cheque con su póliza. Se puede anular con motivo mientras no se haya cobrado.
- `6:10` **Antigüedad de proveedores.** Lo que se debe por rangos de vencimiento, por proveedor o por compra.
- `6:16` **Caja por sucursal.** Apertura con monto inicial; no se abre un día nuevo si el anterior quedó sin cerrar.
- `6:25` **Corte y cierre con cuadre.** El sistema calcula lo esperado por forma de pago; el cajero cuenta lo físico y la diferencia (faltante o sobrante) genera su póliza.
- `6:37` **Depósitos.** El efectivo se deposita en la cuenta de la entidad financiera, con su póliza de banco.

## 6:42 · 08 · Contabilidad

- `6:42` **Cortinilla:** 08 · Contabilidad — *Contabilidad automática*. Cada operación genera su póliza de partida doble, siempre cuadrada. Puntos: Nomenclatura por nodos; Pólizas automáticas; Cuentas por concepto; Anulaciones reflejadas.
- `6:48` **Nomenclatura contable.** Catálogo jerárquico: activo, pasivo, capital, ingresos y gastos, mantenido por nodos.
- `6:56` **Cuentas y subcuentas.** Cada nodo muestra su código, nivel y si acepta movimientos; se agregan cuentas sin romper la estructura.
- `7:01` **Pólizas automáticas.** Venta, compra, cobro, cheque, depósito, cierre de caja, nómina y notas generan su póliza. Aquí se asigna la cuenta contable de cada concepto.

## 7:10 · 09 · Recursos humanos

- `7:10` **Cortinilla:** 09 · Recursos humanos — *Personas y nómina*. Estructura organizativa, empleados y planilla integrados con contabilidad. Puntos: Empleados y plazas; Nómina con póliza; Unidades organizativas; Organigrama.
- `7:16` **Empleados.** Datos del colaborador, puesto, plaza y unidad organizativa; puede vincularse a su usuario y a su código de vendedor.
- `7:21` **Nómina.** Ingresos y descuentos por tipo de movimiento; al aprobarla se genera la póliza de planilla.
- `7:29` **Estructura organizativa.** Unidades anidadas sin límite de niveles, con departamentos, puestos y plazas.
- `7:35` **Organigrama.** Se dibuja solo a partir de la estructura registrada.

## 7:40 · 10 · Administración y seguridad

- `7:40` **Cortinilla:** 10 · Administración — *Seguridad y configuración*. Cada quien ve y hace solo lo que le corresponde. Puntos: Roles y permisos; Compañías y sucursales; Bodegas y unidades; Auditoría de cada registro.
- `7:47` **Roles.** Administrador, contador, vendedor, cajero… cada rol agrupa permisos.
- `7:51` **Permisos por pantalla.** Cada pantalla exige su permiso y los cambios se aplican a las sesiones abiertas en menos de un minuto.
- `7:56` **Sucursales y bodegas.** Multi-sucursal y multi-bodega. Cada registro guarda quién y cuándo lo creó y lo modificó.

## 8:01 · Cierre

- `8:01` **Cortinilla:** *Servicios Informáticos Integrados*. Un ERP completo en la web: ventas con factura electrónica, cartera, compras, bancos, contabilidad y RRHH. Puntos: Pólizas automáticas; Costos y márgenes reales; Tableros para decidir; Seguridad por roles y sucursal.

## Qué se ve en pantalla

- Todo es la aplicación real corriendo contra SQL Server con los datos de prueba (scripts 00 a 35): la factura, el cobro y la compra se graban de verdad durante la grabación.
- La factura electrónica usa el **simulador** de certificación (UUID, serie y número de prueba, sin validez fiscal). Con INFILE el flujo es el mismo.
- Usuario de la demo: `admin`, sucursal *Casa matriz Zona 10*.

## Si se quiere agregar voz

Cada rótulo de arriba sirve como texto de locución, en el tiempo indicado. Una voz grabada puede mezclarse sobre la música bajándola unos 10 dB mientras se habla.
