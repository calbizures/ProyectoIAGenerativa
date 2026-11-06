// Presentación de las novedades de la Fase 4 (acompaña al video corto de
// grabar-fase4.js). Mismo estilo que deck.js; usa las capturas de
// capturas-fase4.js.
const fs = require('fs');
const path = require('path');
const pptxgen = require('pptxgenjs');
const sharp = require('sharp');
const React = require('react');
const { renderToStaticMarkup } = require('react-dom/server');
const Fi = require('react-icons/fi');

const SALIDA = process.env.SALIDA || path.join(__dirname, 'salida');
const F4 = path.join(SALIDA, 'fase4');
const R = path.join(F4, 'recortes');
const NAVY = '0D1B4C', BLUE = '1565C0', BLUE5 = '1E88E5', ICE = 'D5E6FF';
const FONDO = 'F4F7FB', TEXTO = '1C2437', TENUE = '5F6A7F', BLANCO = 'FFFFFF';
const H = 'Calibri', T = 'Calibri';

async function icono(Comp, color, px = 256) {
  const svg = renderToStaticMarkup(React.createElement(Comp, { color: '#' + color, size: px, strokeWidth: 2 }));
  const png = await sharp(Buffer.from(svg)).resize(px, px).png().toBuffer();
  return 'image/png;base64,' + png.toString('base64');
}

async function fondoDegradado() {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080">
    <defs><radialGradient id="g" cx="0" cy="0" r="1.45" gradientUnits="objectBoundingBox">
      <stop offset="0" stop-color="#0d1b4c"/><stop offset="0.38" stop-color="#142d6e"/><stop offset="0.78" stop-color="#1565c0"/><stop offset="1" stop-color="#1e88e5"/></radialGradient>
      <radialGradient id="o" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#7ee0fb" stop-opacity="0.26"/><stop offset="1" stop-color="#7ee0fb" stop-opacity="0"/></radialGradient></defs>
    <rect width="1920" height="1080" fill="url(#g)"/>
    <circle cx="160" cy="120" r="420" fill="url(#o)"/><circle cx="1800" cy="1000" r="360" fill="url(#o)"/>
    <g fill="#7ee0fb" opacity="0.5"><rect x="1640" y="160" width="26" height="26" rx="5"/><rect x="1680" y="160" width="26" height="26" rx="5" opacity=".5"/><rect x="1720" y="160" width="26" height="26" rx="5"/>
    <rect x="1640" y="200" width="26" height="26" rx="5" opacity=".5"/><rect x="1680" y="200" width="26" height="26" rx="5"/><rect x="1720" y="200" width="26" height="26" rx="5" opacity=".6"/></g></svg>`;
  return 'image/png;base64,' + (await sharp(Buffer.from(svg)).png().toBuffer()).toString('base64');
}

async function logoPng() {
  const svg = fs.readFileSync(path.join(__dirname, '..', 'src', 'Erp.Web', 'wwwroot', 'images', 'logo-si.svg'));
  return 'image/png;base64,' + (await sharp(svg, { density: 300 }).resize(920).png().toBuffer()).toString('base64');
}

(async () => {
  const pres = new pptxgen();
  pres.layout = 'LAYOUT_16x9';   // 10 × 5.625 in
  pres.title = 'ERP · Novedades de la Fase 4';
  pres.company = 'Servicios Informáticos Integrados';

  const fondo = await fondoDegradado();
  const logo = await logoPng();
  const ic = {};
  for (const [k, C] of Object.entries({ cartera: Fi.FiCreditCard, vendedor: Fi.FiUserCheck, clic: Fi.FiMousePointer, excel: Fi.FiDownload,
    seguridad: Fi.FiLock, mapa: Fi.FiMap, roles: Fi.FiUsers, editar: Fi.FiEdit3, compras: Fi.FiShoppingCart, firma: Fi.FiCheckSquare,
    parcial: Fi.FiPieChart, poliza: Fi.FiBookOpen, kardex: Fi.FiList, costo: Fi.FiDollarSign, check: Fi.FiCheck, caja: Fi.FiInbox,
    vale: Fi.FiFileText, banco: Fi.FiBriefcase, clave: Fi.FiKey, adjunto: Fi.FiPaperclip, anular: Fi.FiXCircle, correo: Fi.FiMail,
    carpeta: Fi.FiFolder, db: Fi.FiDatabase, flecha: Fi.FiArrowRight, capas: Fi.FiLayers, ojo: Fi.FiEye })) {
    ic[k] = await icono(C, BLANCO);
    ic[k + 'Azul'] = await icono(C, BLUE);
  }

  // --- ayudantes (iguales a deck.js) ----------------------------------------
  const titulo = (s, texto, sub) => {
    s.addText(texto, { x: 0.5, y: 0.32, w: 9, h: 0.6, fontFace: H, fontSize: 30, bold: true, color: NAVY, margin: 0, isTextBox: true });
    if (sub) s.addText(sub, { x: 0.5, y: 0.9, w: 9, h: 0.35, fontFace: T, fontSize: 14, color: TENUE, margin: 0, isTextBox: true });
  };
  const etiqueta = (s, texto) => s.addText(texto.toUpperCase(), { x: 0.5, y: 0.12, w: 6, h: 0.22, fontFace: T, fontSize: 10, bold: true, color: BLUE, charSpacing: 2, margin: 0, isTextBox: true });
  const captura = (s, archivo, x, y, w, proporcion = 1034 / 1582) => {
    const h = w * proporcion;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h, rectRadius: 0.08, fill: { color: BLANCO }, line: { color: 'D7DEE8', width: 0.75 },
      shadow: { type: 'outer', color: '0D1B4C', opacity: 0.18, blur: 12, offset: 3, angle: 90 } });
    s.addImage({ path: path.join(R, archivo), x: x + 0.05, y: y + 0.05, w: w - 0.1, h: h - 0.1, rounding: false });
    return h;
  };
  const filaIcono = (s, x, y, w, icn, cab, texto) => {
    s.addShape(pres.shapes.OVAL, { x, y, w: 0.42, h: 0.42, fill: { color: BLUE } });
    s.addImage({ data: icn, x: x + 0.1, y: y + 0.1, w: 0.22, h: 0.22 });
    s.addText(cab, { x: x + 0.56, y: y - 0.02, w: w - 0.56, h: 0.26, fontFace: H, fontSize: 13.5, bold: true, color: NAVY, margin: 0, isTextBox: true });
    s.addText(texto, { x: x + 0.56, y: y + 0.24, w: w - 0.56, h: 0.5, fontFace: T, fontSize: 11, color: TENUE, margin: 0, valign: 'top', isTextBox: true });
  };
  const claro = () => { const s = pres.addSlide(); s.background = { color: FONDO }; return s; };
  const oscuro = () => { const s = pres.addSlide(); s.background = { data: fondo }; return s; };
  // Pasos en fila: [icono, cabecera, texto]; el último va resaltado.
  const pasos = (s, lista, x0, y, ancho, alto, separacion) => lista.forEach(([k, cab, txt], i) => {
    const x = x0 + i * separacion, ult = i === lista.length - 1;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: ancho, h: alto, rectRadius: 0.1, fill: { color: ult ? BLUE : BLANCO }, line: { color: ult ? BLUE : 'D7DEE8', width: 0.75 } });
    s.addImage({ data: ult ? ic[k] : ic[k + 'Azul'], x: x + 0.16, y: y + 0.15, w: 0.3, h: 0.3 });
    s.addText(cab, { x: x + 0.16, y: y + 0.52, w: ancho - 0.25, h: 0.3, fontFace: H, fontSize: 12.5, bold: true, color: ult ? BLANCO : NAVY, margin: 0, isTextBox: true });
    s.addText(txt, { x: x + 0.16, y: y + 0.82, w: ancho - 0.25, h: alto - 0.9, fontFace: T, fontSize: 9.5, color: ult ? ICE : TENUE, margin: 0, valign: 'top', isTextBox: true });
    if (!ult) s.addImage({ data: ic.flechaAzul, x: x + ancho + (separacion - ancho - 0.22) / 2, y: y + alto / 2 - 0.11, w: 0.22, h: 0.22 });
  });

  // 1. Portada ------------------------------------------------------------------
  let s = oscuro();
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 0.75, y: 1.55, w: 2.55, h: 2.4, rectRadius: 0.22, fill: { color: BLANCO },
    shadow: { type: 'outer', color: '040A23', opacity: 0.4, blur: 20, offset: 6, angle: 90 } });
  s.addImage({ data: logo, x: 0.92, y: 1.68, w: 2.2, h: 2.2 * 430 / 460 });
  s.addText('NOVEDADES DEL PRODUCTO', { x: 3.75, y: 1.55, w: 5.8, h: 0.3, fontFace: T, fontSize: 12, bold: true, color: '7EE0FB', charSpacing: 3, margin: 0, isTextBox: true });
  s.addText('ERP · Fase 4', { x: 3.75, y: 1.88, w: 5.8, h: 0.8, fontFace: H, fontSize: 36, bold: true, color: BLANCO, margin: 0, valign: 'top', isTextBox: true });
  s.addText('Cartera por vendedor, permisos, compra desde la orden de compra, kardex, caja chica, pago por transferencia, correo por Gmail y una base de datos estandarizada.',
    { x: 3.75, y: 2.75, w: 5.6, h: 1.1, fontFace: T, fontSize: 14, color: ICE, margin: 0, valign: 'top', isTextBox: true });
  s.addText('Acompaña al video de novedades (≈ 5 min)', { x: 0.75, y: 4.95, w: 6, h: 0.3, fontFace: T, fontSize: 11, color: 'A9C6F0', margin: 0, isTextBox: true });
  s.addNotes('Novedades de la Fase 4 del ERP de Servicios Informáticos Integrados. Sigue el mismo orden del video corto: antigüedad por vendedor, permisos, compra desde orden de compra, kardex, caja chica, pago por transferencia y correo; al final, la estandarización de la base de datos.');

  // 2. Resumen ------------------------------------------------------------------
  s = claro(); etiqueta(s, 'Fase 4'); titulo(s, 'Ocho novedades', 'Pedidas por el negocio y probadas sobre la aplicación real.');
  const nov = [['vendedor', 'Cartera por vendedor', 'Antigüedad de saldos con todo el saldo del cliente'], ['seguridad', 'Permisos', 'Mantenimiento con dónde se usa, roles y usuarios'],
    ['compras', 'Compra desde OC', 'La orden con dos firmas se vuelve compra'], ['kardex', 'Kardex', 'Costo unitario, total y promedio por movimiento'],
    ['vale', 'Caja chica', 'Vales y recibos sin proveedor'], ['banco', 'Transferencias', 'Pago a proveedores con autorización y comprobante'],
    ['correo', 'Correo por Gmail', 'Por defecto, con otros tipos de salida'], ['db', 'Base estandarizada', '70 objetos al estándar pa / fn']];
  nov.forEach(([k, cab, txt], i) => {
    const x = 0.5 + (i % 4) * 2.3, y = 1.5 + Math.floor(i / 4) * 1.75;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 2.1, h: 1.55, rectRadius: 0.1, fill: { color: BLANCO }, line: { color: 'E8EDF4', width: 0.75 },
      shadow: { type: 'outer', color: '0D1B4C', opacity: 0.08, blur: 8, offset: 2, angle: 90 } });
    s.addShape(pres.shapes.OVAL, { x: x + 0.16, y: y + 0.18, w: 0.46, h: 0.46, fill: { color: i % 2 ? BLUE5 : BLUE } });
    s.addImage({ data: ic[k], x: x + 0.27, y: y + 0.29, w: 0.24, h: 0.24 });
    s.addText(cab, { x: x + 0.16, y: y + 0.75, w: 1.85, h: 0.3, fontFace: H, fontSize: 13, bold: true, color: NAVY, margin: 0, isTextBox: true });
    s.addText(txt, { x: x + 0.16, y: y + 1.05, w: 1.85, h: 0.45, fontFace: T, fontSize: 9.5, color: TENUE, margin: 0, valign: 'top', isTextBox: true });
  });
  s.addNotes('Siete novedades funcionales y una técnica (la estandarización de la base de datos). Cada una tiene su script (66 a 71) o es un cambio de la aplicación.');

  // 3. Antigüedad por vendedor ---------------------------------------------------
  s = claro(); etiqueta(s, '01 · Cuentas por cobrar'); titulo(s, 'Antigüedad de saldos por vendedor', 'Cada vendedor ve su cartera; administración y contabilidad, toda.');
  filaIcono(s, 0.5, 1.55, 3.3, ic.vendedor, 'Su cartera', 'Clientes a los que el vendedor les ha vendido (usuario → empleado → vendedor).');
  filaIcono(s, 0.5, 2.45, 3.3, ic.cartera, 'Todo el saldo', 'Del cliente completo, aunque parte venga de facturas de otro vendedor.');
  filaIcono(s, 0.5, 3.35, 3.3, ic.seguridad, 'Todos los clientes', 'Con el permiso CXC_ANTIGUEDAD_TODOS: administrador, contador y contador general.');
  filaIcono(s, 0.5, 4.25, 3.3, ic.clic, 'Al elegir el cliente', 'La consulta corre sola; Excel e impresión con el mismo filtro.');
  captura(s, 'antiguedad_vendedor.png', 4.1, 1.45, 5.45);
  s.addNotes('Vista del vendedor jperez: solo sus clientes, con el saldo completo de cada uno. Un usuario sin vendedor asociado no ve clientes y la pantalla le explica por qué. El rol CAJERO no tiene el permiso de ver todos; se le puede asignar en Seguridad › Permisos si se necesita.');

  // 4. Permisos --------------------------------------------------------------------
  s = claro(); etiqueta(s, '02 · Seguridad'); titulo(s, 'Mantenimiento de permisos', 'Cada permiso con dónde se usa, qué roles lo tienen y qué usuarios.');
  captura(s, 'permisos_detalle.png', 0.45, 1.45, 5.45);
  filaIcono(s, 6.2, 1.55, 3.4, ic.editar, 'Crear y modificar', 'Módulo, descripción y estado; se elimina solo si nadie lo usa.');
  filaIcono(s, 6.2, 2.45, 3.4, ic.mapa, 'Dónde se usa', 'Opciones del menú y acciones dentro de las pantallas, leídas de la aplicación.');
  filaIcono(s, 6.2, 3.35, 3.4, ic.roles, 'Roles', 'Asignar o quitar el permiso a un rol desde el detalle.');
  filaIcono(s, 6.2, 4.25, 3.4, ic.ojo, 'Usuarios', 'Quién lo tiene, por qué rol y su último ingreso.');
  s.addNotes('El detalle del permiso COMPRAS_ORDEN_APROBAR: se usa en Compras › Órdenes de compra, lo tienen ADMIN y CONTADOR_GENERAL, y los usuarios admin y cgeneral. Los permisos de un rol inactivo ya no cuentan.');

  // 5. Compra desde OC -------------------------------------------------------------
  s = claro(); etiqueta(s, '03 · Compras'); titulo(s, 'Compra desde la orden de compra', 'La orden aprobada se recibe como compra, completa o por partes.');
  pasos(s, [['compras', 'Orden', 'Proveedor, bodega y productos'], ['firma', 'Visto bueno', 'Jefe de bodega'], ['firma', 'Aprobación', 'Contador general'],
    ['poliza', 'Compra', 'Inventario, cuenta por pagar y póliza']], 0.5, 1.5, 1.95, 1.4, 2.33);
  captura(s, 'compra_desde_oc.png', 0.5, 3.1, 3.3);
  filaIcono(s, 4.2, 3.2, 5.3, ic.parcial, 'Recepciones parciales', 'Se indica lo que llegó con la factura; lo que falta queda pendiente para otra recepción.');
  filaIcono(s, 4.2, 4.1, 5.3, ic.compras, 'Desde Compras', 'Botón «Desde orden de compra» (permiso COMPRAS_ORDEN_RECIBIR), además de Órdenes de compra.');
  s.addNotes('En la demo la orden OC-000001 pide 6 laptops Dell y 4 HP; llegaron 4 Dell y 4 HP con la factura A-7745. Se grabó la compra y la orden quedó parcialmente recibida, con 2 Dell pendientes (es lo que muestra la captura).');

  // 6. Kardex ------------------------------------------------------------------------
  s = claro(); etiqueta(s, '04 · Inventario'); titulo(s, 'Kardex', 'Todos los movimientos de un producto, para comprobar el costo promedio.');
  filaIcono(s, 0.5, 1.55, 3.3, ic.kardex, 'Cada movimiento', 'Compras, facturas, ajustes, traslados, devoluciones y anulaciones.');
  filaIcono(s, 0.5, 2.45, 3.3, ic.costo, 'Costo por línea', 'Cantidad, costo unitario y costo total de cada movimiento.');
  filaIcono(s, 0.5, 3.35, 3.3, ic.capas, 'Saldo y promedio', 'Después de cada línea: existencia, valor y costo promedio.');
  filaIcono(s, 0.5, 4.25, 3.3, ic.check, 'Comprobado', 'Llega a lo guardado en el producto; se exporta a Excel.');
  captura(s, 'kardex.png', 4.1, 1.45, 5.45);
  s.addNotes('El promedio se recalcula como lo hace el sistema al grabar cada documento. En los 15 productos de prueba el kardex llega exactamente a la existencia, el valor y el costo promedio guardados.');

  // 7. Caja chica ----------------------------------------------------------------------
  s = claro(); etiqueta(s, '05 · Caja chica'); titulo(s, 'Vales y recibos sin proveedor', 'El proveedor solo se exige en las facturas.');
  captura(s, 'caja_chica.png', 0.45, 1.45, 5.45);
  filaIcono(s, 6.2, 1.55, 3.4, ic.vale, 'Vale', '«Entregado a» es opcional.');
  filaIcono(s, 6.2, 2.45, 3.4, ic.vale, 'Recibo', '«Emitido por» es opcional.');
  filaIcono(s, 6.2, 3.35, 3.4, ic.caja, 'Facturas', 'Con proveedor, NIT y número, como antes.');
  filaIcono(s, 6.2, 4.25, 3.4, ic.poliza, 'Liquidación', 'La línea de la póliza de un gasto sin proveedor lleva solo el concepto.');
  s.addNotes('El vale de la demo (pasajes de mensajería, Q35.00 a viáticos) aparece como «Sin proveedor» en los gastos sin liquidar.');

  // 8. Transferencia: registro ----------------------------------------------------------
  s = claro(); etiqueta(s, '06 · Cuentas por pagar'); titulo(s, 'Pago a proveedores por transferencia', 'Además del cheque: se registra la transferencia ya hecha en el banco.');
  captura(s, 'transferencia_formulario.png', 0.45, 1.45, 5.45);
  filaIcono(s, 6.2, 1.55, 3.4, ic.banco, 'Cuentas', 'La de la empresa de la que salió y la del proveedor (propuesta desde Proveedores).');
  filaIcono(s, 6.2, 2.45, 3.4, ic.clave, 'Autorización', 'Obligatoria; no se repite en la misma cuenta mientras esté vigente.');
  filaIcono(s, 6.2, 3.35, 3.4, ic.adjunto, 'Comprobante', 'PDF o imagen de hasta 5 MB; el tipo se comprueba por el contenido.');
  filaIcono(s, 6.2, 4.25, 3.4, ic.cartera, 'Mismas cuotas', 'A las más antiguas, factura completa, todo el saldo o lo vencido.');
  s.addNotes('La fecha no puede ser futura ni anterior a las compras que paga. Si el proveedor tiene como forma de pago transferencia, la pantalla la propone sola.');

  // 9. Transferencia: póliza y seguimiento -----------------------------------------------
  s = claro(); etiqueta(s, '06 · Cuentas por pagar'); titulo(s, 'Registrada, contabilizada y trazable', 'Correlativo TR-, póliza automática y anulación con motivo.');
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 0.5, y: 1.5, w: 3.6, h: 3.5, rectRadius: 0.12, fill: { color: NAVY } });
  s.addText('PÓLIZA PAGO_TRANSFERENCIA', { x: 0.8, y: 1.72, w: 3.1, h: 0.25, fontFace: T, fontSize: 10, bold: true, color: '7EE0FB', charSpacing: 2, margin: 0, isTextBox: true });
  s.addText([{ text: 'Debe', options: { bold: true, color: BLANCO, breakLine: true } }, { text: 'Proveedores — una línea por factura', options: { color: ICE, breakLine: true } },
    { text: ' ', options: { breakLine: true } }, { text: 'Haber', options: { bold: true, color: BLANCO, breakLine: true } }, { text: 'Cuenta contable del banco', options: { color: ICE } }],
    { x: 0.8, y: 2.1, w: 3.1, h: 1.5, fontFace: T, fontSize: 13, margin: 0, valign: 'top', isTextBox: true });
  s.addText('Entra al estado de cuenta del proveedor, al flujo de caja, a la conciliación bancaria y al control 6 de integridad.', { x: 0.8, y: 3.75, w: 3.1, h: 1.0, fontFace: T, fontSize: 11, color: ICE, margin: 0, valign: 'top', isTextBox: true });
  captura(s, 'transferencias.png', 4.35, 1.45, 5.2);
  s.addText('Detalle de cuotas (abono o cancelación), comprobante y anulación.', { x: 4.35, y: 4.95, w: 5.2, h: 0.3, fontFace: T, fontSize: 10.5, italic: true, color: TENUE, margin: 0, isTextBox: true });
  s.addNotes('Anular devuelve el saldo a las cuotas y anula la póliza; el comprobante se conserva. Anular solo deshace el registro: la devolución del dinero se gestiona con el banco o el proveedor. El comprobante del video es una imagen de ejemplo.');

  // 10. Correo ------------------------------------------------------------------------------
  s = claro(); etiqueta(s, '07 · Correo'); titulo(s, 'Correo saliente por Gmail', 'Por defecto la compañía envía con calbizures@gmail.com.');
  filaIcono(s, 0.5, 1.55, 3.3, ic.correo, 'Gmail por defecto', 'smtp.gmail.com, puerto 587 con TLS.');
  filaIcono(s, 0.5, 2.45, 3.3, ic.clave, 'Contraseña de aplicación', 'Gmail la exige (verificación en dos pasos); se guarda cifrada.');
  filaIcono(s, 0.5, 3.35, 3.3, ic.capas, 'Otros tipos', 'Outlook.com, Microsoft 365, Yahoo u otro servidor SMTP.');
  filaIcono(s, 0.5, 4.25, 3.3, ic.carpeta, 'Carpeta', 'Guarda los correos como .eml para probar sin enviar.');
  captura(s, 'correo.png', 4.1, 1.45, 5.45);
  s.addNotes('El correo se usa para enviar los estados de cuenta. Las compañías que ya tenían otro servidor configurado lo conservan. Para que Gmail acepte los envíos hay que escribir la contraseña de aplicación en General › Compañías › Correo saliente.');

  // 11. Base de datos estandarizada -------------------------------------------------------------
  s = claro(); etiqueta(s, 'Base de datos'); titulo(s, 'Base de datos estandarizada', 'Procedimientos y funciones con un solo estándar de nombres.');
  const stats = [['70', 'Procedimientos sp_ y funciones fn_ renombrados'], ['6', 'Scripts nuevos (66 a 71), re-ejecutables'], ['449', 'Procedimientos y funciones idénticos en base nueva o actualizada'], ['19', 'Controles de integridad en OK']];
  stats.forEach(([n, t], i) => {
    const x = 0.5 + i * 2.3;
    s.addText(n, { x, y: 1.45, w: 2.1, h: 0.75, fontFace: H, fontSize: 44, bold: true, color: BLUE, margin: 0, valign: 'bottom', isTextBox: true });
    s.addText(t, { x, y: 2.27, w: 2.05, h: 0.65, fontFace: T, fontSize: 11.5, color: TENUE, margin: 0, valign: 'top', isTextBox: true });
  });
  const filas = [['Antes', 'Ahora'], ['sp_ventas_crear_factura', 'paVentaFacturaCrear'], ['sp_compras_crear_documento', 'paCompraDocumentoCrear'], ['fn_moneda_local', 'fnMonedaLocal'], ['@enc_id, alias  p', '@EncId, alias  prod']];
  s.addTable(filas.map((f, i) => f.map(c => ({ text: c, options: { bold: i === 0, color: i === 0 ? BLANCO : TEXTO, fill: { color: i === 0 ? NAVY : (i % 2 ? BLANCO : 'EEF3FA') }, fontFace: i === 0 ? T : 'Consolas' } }))),
    { x: 0.5, y: 3.15, w: 5.4, colW: [2.7, 2.7], fontSize: 11, border: { type: 'solid', color: 'D7DEE8', pt: 0.75 }, rowH: 0.34 });
  filaIcono(s, 6.25, 3.2, 3.3, ic.db, 'Prefijo pa / fn + PascalCase', 'Nombres, parámetros (@PascalCase) y alias de al menos 4 caracteres.');
  filaIcono(s, 6.25, 4.15, 3.3, ic.check, 'Actualización segura', 'El script 66 migra una base existente; se actualizan base y aplicación juntas.');
  s.addNotes('La estandarización se hizo con la opción B elegida: nombres, parámetros y alias. Se probó sobre una copia de la base anterior: después de correr 66 a 71 queda igual que una instalación nueva.');

  // 12. Cierre ------------------------------------------------------------------------------------
  s = oscuro();
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 3.95, y: 0.7, w: 2.1, h: 1.98, rectRadius: 0.2, fill: { color: BLANCO },
    shadow: { type: 'outer', color: '040A23', opacity: 0.4, blur: 20, offset: 6, angle: 90 } });
  s.addImage({ data: logo, x: 4.07, y: 0.8, w: 1.86, h: 1.86 * 430 / 460 });
  s.addText('Gracias', { x: 1, y: 2.95, w: 8, h: 0.8, fontFace: H, fontSize: 40, bold: true, color: BLANCO, align: 'center', margin: 0, isTextBox: true });
  s.addText('Fase 4 lista: scripts 66 a 71 y la aplicación actualizada.', { x: 1, y: 3.75, w: 8, h: 0.4, fontFace: T, fontSize: 16, color: ICE, align: 'center', margin: 0, isTextBox: true });
  s.addText('Servicios Informáticos Integrados', { x: 1, y: 4.8, w: 8, h: 0.3, fontFace: T, fontSize: 11, color: 'A9C6F0', align: 'center', charSpacing: 2, margin: 0, isTextBox: true });
  s.addNotes('Cierre. Espacio para preguntas y para mostrar en vivo cualquiera de las novedades.');

  await pres.writeFile({ fileName: path.join(F4, 'ERP - Novedades Fase 4.pptx') });
  console.log('ok');
})();
