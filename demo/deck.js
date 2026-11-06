// Presentación de la demo del ERP (Servicios Informáticos Integrados).
const fs = require('fs');
const path = require('path');
const pptxgen = require('pptxgenjs');
const sharp = require('sharp');
const React = require('react');
const { renderToStaticMarkup } = require('react-dom/server');
const Fi = require('react-icons/fi');

const SALIDA = process.env.SALIDA || path.join(__dirname, 'salida');
const R = path.join(SALIDA, 'recortes');
const NAVY = '0D1B4C', NAVY2 = '142D6E', BLUE = '1565C0', BLUE5 = '1E88E5', CYAN = '29B6F6', ICE = 'D5E6FF';
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
  pres.title = 'Demo ERP · Servicios Informáticos Integrados';
  pres.company = 'Servicios Informáticos Integrados';

  // Números de la compra grabada en el video (grabar.js); si no están, los de una instalación limpia.
  const archivoDatos = path.join(SALIDA, 'datos_demo.json');
  const datos = fs.existsSync(archivoDatos) ? JSON.parse(fs.readFileSync(archivoDatos, 'utf8')) : { costoAntes: 3224, cantAntes: 97, costoDespues: 3259.14 };
  const q = n => 'Q' + Number(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const fondo = await fondoDegradado();
  const logo = await logoPng();
  const ic = {};
  for (const [k, C] of Object.entries({ grafico: Fi.FiTrendingUp, factura: Fi.FiFileText, fel: Fi.FiShield, cobrar: Fi.FiCreditCard,
    compras: Fi.FiShoppingCart, banco: Fi.FiBriefcase, conta: Fi.FiBookOpen, rrhh: Fi.FiUsers, seguridad: Fi.FiLock, check: Fi.FiCheck,
    reloj: Fi.FiRefreshCw, llave: Fi.FiKey, anular: Fi.FiXCircle, db: Fi.FiDatabase, web: Fi.FiMonitor, capas: Fi.FiLayers, flecha: Fi.FiArrowRight,
    filtro: Fi.FiFilter, clic: Fi.FiMousePointer, calendario: Fi.FiCalendar, caja: Fi.FiDollarSign, sucursal: Fi.FiMapPin, auditoria: Fi.FiEye, excel: Fi.FiDownload,
    inventario: Fi.FiPackage, correo: Fi.FiMail, conteo: Fi.FiClipboard, subir: Fi.FiUpload, imagen: Fi.FiImage, vinculo: Fi.FiLink, usuario: Fi.FiUserCheck, arranque: Fi.FiPlayCircle })) {
    ic[k] = await icono(C, BLANCO);
    ic[k + 'Azul'] = await icono(C, BLUE);
  }

  // --- ayudantes -----------------------------------------------------------
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

  // 1. Portada -----------------------------------------------------------------
  let s = oscuro();
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 0.75, y: 1.55, w: 2.55, h: 2.4, rectRadius: 0.22, fill: { color: BLANCO },
    shadow: { type: 'outer', color: '040A23', opacity: 0.4, blur: 20, offset: 6, angle: 90 } });
  s.addImage({ data: logo, x: 0.92, y: 1.68, w: 2.2, h: 2.2 * 430 / 460 });
  s.addText('DEMO DEL PRODUCTO', { x: 3.75, y: 1.55, w: 5.8, h: 0.3, fontFace: T, fontSize: 12, bold: true, color: '7EE0FB', charSpacing: 3, margin: 0, isTextBox: true });
  s.addText('ERP · Servicios Informáticos Integrados', { x: 3.75, y: 1.88, w: 5.8, h: 1.25, fontFace: H, fontSize: 32, bold: true, color: BLANCO, margin: 0, valign: 'top', isTextBox: true });
  s.addText('De la cotización a los estados financieros, en una sola plataforma web: ventas con FEL, cartera, compras e inventario, bancos, contabilidad automática y RRHH.',
    { x: 3.75, y: 3.2, w: 5.6, h: 0.85, fontFace: T, fontSize: 14, color: ICE, margin: 0, valign: 'top', isTextBox: true });
  s.addText('Acompaña al video de la demo', { x: 0.75, y: 4.95, w: 6, h: 0.3, fontFace: T, fontSize: 11, color: 'A9C6F0', margin: 0, isTextBox: true });
  s.addNotes('Presentación del ERP de Servicios Informáticos Integrados. El recorrido sigue el mismo orden del video: acceso, tableros, ventas y FEL, cartera, compras y órdenes de compra, inventario, proveedores, caja, bancos, contabilidad, RRHH, puesta en marcha, administración y trabajo sin pérdidas.');

  // 2. Módulos ----------------------------------------------------------------
  s = claro(); etiqueta(s, 'Visión general'); titulo(s, 'Una plataforma, toda la operación', 'Doce áreas integradas sobre la misma base de datos: cada operación alimenta a las demás.');
  const mods = [['grafico', 'Tableros', 'Ventas, cartera, compras y compromisos'], ['factura', 'Ventas y FEL', 'De la cotización a la factura certificada'],
    ['cobrar', 'Cartera (CxC)', 'Cobro en caja, transferencia o boleta'], ['compras', 'Compras', 'Orden de compra con dos firmas'],
    ['inventario', 'Inventario', 'Kardex, costo promedio y toma física'], ['caja', 'Proveedores y caja', 'Cheque o transferencia; corte con cuadre'],
    ['banco', 'Bancos', 'Cheques, conciliación y flujo de caja'], ['conta', 'Contabilidad', 'Pólizas automáticas y estados financieros'],
    ['rrhh', 'RRHH', 'Nómina, libro de salarios e IGSS'], ['subir', 'Puesta en marcha', 'Inventario, saldos y empleados desde Excel'],
    ['seguridad', 'Administración', 'Roles, permisos, logotipo y correo'], ['reloj', 'Sin perder el trabajo', 'Aviso al salir y borrador']];
  mods.forEach(([k, cab, txt], i) => {
    const x = 0.5 + (i % 4) * 2.3, y = 1.45 + Math.floor(i / 4) * 1.3;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 2.1, h: 1.15, rectRadius: 0.1, fill: { color: BLANCO }, line: { color: 'E8EDF4', width: 0.75 },
      shadow: { type: 'outer', color: '0D1B4C', opacity: 0.08, blur: 8, offset: 2, angle: 90 } });
    s.addShape(pres.shapes.OVAL, { x: x + 0.16, y: y + 0.16, w: 0.42, h: 0.42, fill: { color: i % 2 ? BLUE5 : BLUE } });
    s.addImage({ data: ic[k], x: x + 0.26, y: y + 0.26, w: 0.22, h: 0.22 });
    s.addText(cab, { x: x + 0.68, y: y + 0.2, w: 1.35, h: 0.34, fontFace: H, fontSize: 12.5, bold: true, color: NAVY, margin: 0, valign: 'middle', isTextBox: true });
    s.addText(txt, { x: x + 0.16, y: y + 0.66, w: 1.85, h: 0.42, fontFace: T, fontSize: 9.5, color: TENUE, margin: 0, valign: 'top', isTextBox: true });
  });
  s.addNotes('Todos los módulos comparten la misma base de datos: una factura mueve inventario, cartera, FEL, tableros y contabilidad en una sola transacción. El orden de las diapositivas sigue al video.');

  // Tableros ------------------------------------------------------------------
  s = claro(); etiqueta(s, '02 · Tableros'); titulo(s, 'Tableros gerenciales', 'La información para decidir, al día y en una sola pantalla.');
  filaIcono(s, 0.5, 1.55, 3.3, ic.grafico, 'Ventas y margen real', 'Margen bruto calculado con el costo grabado en cada línea.');
  filaIcono(s, 0.5, 2.45, 3.3, ic.clic, 'Interactivos', 'Detalle al pasar el puntero; un clic en un mes lo abre por día.');
  filaIcono(s, 0.5, 3.35, 3.3, ic.calendario, 'Compromisos de pago', 'Lo que vence con proveedores en las próximas 12 semanas.');
  filaIcono(s, 0.5, 4.25, 3.3, ic.filtro, 'Filtros', 'Por período y por sucursal; cada gráfico tiene vista de tabla.');
  captura(s, 'tablero_ventas.png', 4.1, 1.45, 5.45);
  s.addNotes('Tres tableros: ventas, recuperación de cartera y compras con compromisos de pago. El margen usa el costo real grabado en cada línea de factura.');

  // Cotización ----------------------------------------------------------------
  s = claro(); etiqueta(s, '03 · Ventas'); titulo(s, 'De la cotización a la factura', 'Se cotiza, se envía al cliente y se factura con los precios cotizados.');
  captura(s, 'cotizacion.png', 0.45, 1.45, 5.45);
  filaIcono(s, 6.2, 1.55, 3.4, ic.calendario, 'Vigencia de 15 días', 'Para clientes o prospectos; muestra la existencia de hoy.');
  filaIcono(s, 6.2, 2.45, 3.4, ic.correo, 'Por correo al cliente', 'En PDF, con la cuenta de correo de la compañía.');
  filaIcono(s, 6.2, 3.35, 3.4, ic.factura, 'Convertir en factura', 'Con el cliente, las líneas y los precios cotizados.');
  filaIcono(s, 6.2, 4.25, 3.4, ic.check, 'Queda facturada', 'Al grabar la factura, la cotización se marca facturada.');
  s.addNotes('En el video se cotiza una laptop y su instalación para un cliente, se muestra el envío por correo y se convierte en factura.');

  // Factura -------------------------------------------------------------------
  s = claro(); etiqueta(s, '03 · Ventas'); titulo(s, 'Factura certificada y enviada al cliente', 'Contado, crédito o transferencia, con FEL al grabar.');
  filaIcono(s, 0.5, 1.55, 3.3, ic.cobrar, 'Crédito con límite', 'Plan de cuotas y validación del crédito disponible.');
  filaIcono(s, 0.5, 2.45, 3.3, ic.banco, 'Transferencia', 'Monto propuesto, número de operación y comprobante adjunto.');
  filaIcono(s, 0.5, 3.35, 3.3, ic.fel, 'Certificada al grabar', 'UUID, serie y número de SAT; anulación con motivo.');
  filaIcono(s, 0.5, 4.25, 3.3, ic.correo, 'PDF y XML por correo', 'Al correo registrado del cliente; la lista muestra la hora en que se grabó.');
  captura(s, 'factura_correo.png', 4.1, 1.45, 5.45);
  s.addNotes('La factura se paga por transferencia: el monto se propone con el total, se indica el número de operación y se adjunta el comprobante. En el detalle se ven las transferencias recibidas y el envío por correo del PDF y el XML certificado.');

  // FEL -----------------------------------------------------------------------
  s = claro(); etiqueta(s, '04 · Factura electrónica'); titulo(s, 'FEL parametrizada', 'Cumplimiento con SAT sin depender de un proveedor fijo.');
  const pasos = [['factura', 'Grabar', 'Factura o nota en el ERP'], ['capas', 'XML del DTE', 'Armado desde parámetros'], ['fel', 'Certificador', 'INFILE o simulador'], ['check', 'Autorización', 'UUID, serie y número']];
  pasos.forEach(([k, cab, txt], i) => {
    const x = 0.5 + i * 2.33;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 1.5, w: 1.95, h: 1.35, rectRadius: 0.1, fill: { color: i === 3 ? BLUE : BLANCO }, line: { color: i === 3 ? BLUE : 'D7DEE8', width: 0.75 } });
    s.addImage({ data: i === 3 ? ic[k] : ic[k + 'Azul'], x: x + 0.2, y: 1.68, w: 0.34, h: 0.34 });
    s.addText(cab, { x: x + 0.2, y: 2.1, w: 1.65, h: 0.3, fontFace: H, fontSize: 14, bold: true, color: i === 3 ? BLANCO : NAVY, margin: 0, isTextBox: true });
    s.addText(txt, { x: x + 0.2, y: 2.4, w: 1.65, h: 0.35, fontFace: T, fontSize: 10.5, color: i === 3 ? ICE : TENUE, margin: 0, isTextBox: true });
    if (i < 3) s.addImage({ data: ic.flechaAzul, x: x + 2.02, y: 2.02, w: 0.26, h: 0.26 });
  });
  filaIcono(s, 0.5, 3.3, 2.9, ic.reloj, 'Reintento automático', 'Si no hay conexión, la factura queda pendiente y se reenvía sola.');
  filaIcono(s, 3.55, 3.3, 2.9, ic.anular, 'Anulación ante SAT', 'Con motivo; queda registrada con su XML de anulación.');
  filaIcono(s, 6.6, 3.3, 2.9, ic.llave, 'Llaves protegidas', 'Las credenciales del certificador van fuera de la base de datos.');
  s.addText('Parámetros: certificador, ambiente, emisor, establecimientos, frases, tipos de DTE (FACT, FCAM con abonos, NCRE, NDEB) y unidades de medida. Cada documento muestra la fecha y la hora en que se facturó.',
    { x: 0.5, y: 4.45, w: 9, h: 0.6, fontFace: T, fontSize: 11.5, color: TEXTO, margin: 0, valign: 'top', isTextBox: true });
  s.addNotes('En la demo se usó el simulador de certificación; con INFILE el flujo es el mismo. Los documentos anteriores se certifican en lote.');

  // Cuentas por cobrar ---------------------------------------------------------
  s = claro(); etiqueta(s, '05 · Cuentas por cobrar'); titulo(s, 'Cobros en caja o en el banco', 'Transferencia con comprobante o boleta verificada contra el banco.');
  captura(s, 'cobros_boletas.png', 0.45, 1.45, 5.45);
  filaIcono(s, 6.2, 1.55, 3.4, ic.cobrar, 'Varias cuotas, un recibo', 'El monto se aplica a las cuotas más antiguas.');
  filaIcono(s, 6.2, 2.45, 3.4, ic.banco, 'Transferencia', 'Se propone lo pendiente; No. de operación y comprobante.');
  filaIcono(s, 6.2, 3.35, 3.4, ic.imagen, 'Pago con boleta', 'El cliente pagó en el banco: queda por verificar.');
  filaIcono(s, 6.2, 4.25, 3.4, ic.check, 'Verificada contra el banco', 'Recibo sin caja y póliza Bancos / Clientes; aviso al cliente.');
  s.addNotes('La boleta no rebaja el saldo hasta que contabilidad la verifica contra el estado de cuenta del banco (permiso Verificar boletas). Entonces se graba el recibo y la póliza con la fecha del depósito, y entra en la conciliación bancaria. También se puede rechazar o anular.');

  s = claro(); etiqueta(s, '05 · Cuentas por cobrar'); titulo(s, 'Cartera bajo control', 'Estado de cuenta y antigüedad, por cliente y por vendedor.');
  filaIcono(s, 0.5, 1.55, 3.3, ic.auditoria, 'Estado de cuenta', 'Facturas, cuotas, cobros y notas con su saldo.');
  filaIcono(s, 0.5, 2.45, 3.3, ic.excel, 'Antigüedad de saldos', 'Por rangos de días, con Excel e impresión.');
  filaIcono(s, 0.5, 3.35, 3.3, ic.usuario, 'Por vendedor', 'Cada vendedor ve los clientes a los que les ha vendido.');
  filaIcono(s, 0.5, 4.25, 3.3, ic.correo, 'Por correo', 'Estado de cuenta y recibos al correo del cliente.');
  captura(s, 'cxc_antiguedad.png', 4.1, 1.45, 5.45);
  s.addNotes('Administración y contabilidad ven toda la cartera; el vendedor, la de sus clientes con todo su saldo.');

  // Costo promedio ---------------------------------------------------------
  s = claro(); etiqueta(s, '06 · Compras'); titulo(s, 'Cada compra actualiza el costo real', 'Costo neto de descuento y sin IVA, promediado con la existencia.');
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 0.5, y: 1.5, w: 4.2, h: 3.55, rectRadius: 0.12, fill: { color: NAVY } });
  s.addText('EJEMPLO DE LA DEMO', { x: 0.8, y: 1.72, w: 3.7, h: 0.25, fontFace: T, fontSize: 10, bold: true, color: '7EE0FB', charSpacing: 2, margin: 0, isTextBox: true });
  s.addText('10 laptops a Q4,256 con IVA y Q2,240 de descuento', { x: 0.8, y: 2.0, w: 3.7, h: 0.5, fontFace: T, fontSize: 12.5, color: ICE, margin: 0, valign: 'top', isTextBox: true });
  s.addText('Q3,600', { x: 0.8, y: 2.5, w: 3.7, h: 0.7, fontFace: H, fontSize: 40, bold: true, color: BLANCO, margin: 0, isTextBox: true });
  s.addText('costo por unidad que entra al inventario', { x: 0.8, y: 3.15, w: 3.7, h: 0.3, fontFace: T, fontSize: 11.5, color: ICE, margin: 0, isTextBox: true });
  s.addText([{ text: `(${q(datos.costoAntes)} × ${datos.cantAntes} + Q3,600 × 10) ÷ ${datos.cantAntes + 10} = `, options: { color: ICE } }, { text: q(datos.costoDespues), options: { color: BLANCO, bold: true } }],
    { x: 0.8, y: 3.62, w: 3.75, h: 0.35, fontFace: T, fontSize: 11.5, margin: 0, isTextBox: true });
  s.addText('Nuevo costo promedio. La siguiente venta lo graba en su línea y en la póliza de costo de ventas.', { x: 0.8, y: 4.08, w: 3.7, h: 0.7, fontFace: T, fontSize: 11, color: ICE, margin: 0, valign: 'top', isTextBox: true });
  captura(s, 'productos.png', 5.0, 1.5, 4.55);
  s.addText('Solo las bodegas de la sucursal de la sesión; productos y último costo del proveedor.', { x: 5.0, y: 4.62, w: 4.55, h: 0.4, fontFace: T, fontSize: 10.5, italic: true, color: TENUE, margin: 0, isTextBox: true });
  s.addNotes('Al grabar la compra, en una sola transacción, sube la existencia, se recalcula el costo promedio ponderado y se genera la póliza de compra.');

  // Órdenes de compra --------------------------------------------------------
  s = claro(); etiqueta(s, '07 · Órdenes de compra'); titulo(s, 'Compra desde la orden de compra', 'Aprobada por bodega y por el contador general, recibida completa o por partes.');
  captura(s, 'ordenes_compra.png', 0.45, 1.45, 5.45);
  filaIcono(s, 6.2, 1.55, 3.4, ic.usuario, 'Dos firmas', 'Visto bueno del jefe de bodega y aprobación del contador general.');
  filaIcono(s, 6.2, 2.45, 3.4, ic.inventario, 'Recepción parcial', 'Lo que llegó con la factura; lo demás queda pendiente.');
  filaIcono(s, 6.2, 3.35, 3.4, ic.conta, 'Todo junto', 'Inventario, cuenta por pagar y póliza en una transacción.');
  filaIcono(s, 6.2, 4.25, 3.4, ic.compras, 'Productos por proveedor', 'Código del proveedor, preferido y último costo.');
  s.addNotes('Solo las órdenes con las dos firmas se pueden recibir. En el video llegan 4 de 6 laptops y la orden queda recibida en parte.');

  // Kardex --------------------------------------------------------------------
  s = claro(); etiqueta(s, '08 · Inventario'); titulo(s, 'Kardex con costo promedio', 'Cómo llegó cada producto a su existencia y a su costo.');
  filaIcono(s, 0.5, 1.55, 3.3, ic.filtro, 'Búsqueda', 'Existencias y precios por código o descripción.');
  filaIcono(s, 0.5, 2.45, 3.3, ic.inventario, 'Cada movimiento', 'Cantidad, costo unitario y total; saldo y promedio después de cada línea.');
  filaIcono(s, 0.5, 3.35, 3.3, ic.check, 'Comprobado', 'Llega a la misma existencia y costo guardados en el producto.');
  filaIcono(s, 0.5, 4.25, 3.3, ic.excel, 'Excel', 'El kardex completo se exporta.');
  captura(s, 'kardex.png', 4.1, 1.45, 5.45);
  s.addNotes('El kardex está en Inventario › Existencias, por bodega o de todas.');

  // Inventario físico ---------------------------------------------------------
  s = claro(); etiqueta(s, '08 · Inventario'); titulo(s, 'Inventario físico con ajuste', 'El conteo de cada bodega contra el sistema, con su documento y su póliza.');
  filaIcono(s, 0.5, 1.55, 3.3, ic.conteo, 'Toma por bodega', 'Existencia del sistema (no modificable) junto al conteo.');
  filaIcono(s, 0.5, 2.45, 3.3, ic.excel, 'En pantalla o con Excel', 'Hoja de conteo para llenar en la bodega y subir.');
  filaIcono(s, 0.5, 3.35, 3.3, ic.inventario, 'Ajuste valorado', 'Sobrante contra ingresos, faltante contra gastos, al costo promedio.');
  filaIcono(s, 0.5, 4.25, 3.3, ic.anular, 'Anulación', 'Revierte existencias y pólizas de los ajustes.');
  captura(s, 'toma_fisica.png', 4.1, 1.45, 5.45);
  s.addNotes('Al aplicar la toma, las diferencias generan los documentos de sobrante y faltante con sus pólizas.');

  // Pagos a proveedores --------------------------------------------------------
  s = claro(); etiqueta(s, '09 · Cuentas por pagar'); titulo(s, 'Pagos a proveedores', 'Con cheque o por transferencia, por factura o por todo el saldo.');
  captura(s, 'pagos_transferencia.png', 0.45, 1.45, 5.45);
  filaIcono(s, 6.2, 1.55, 3.4, ic.factura, 'Un cheque, varias facturas', 'Aplicado a las cuotas más antiguas, con concepto automático.');
  filaIcono(s, 6.2, 2.45, 3.4, ic.banco, 'Transferencia', 'La ya hecha en la banca electrónica, con su número de autorización.');
  filaIcono(s, 6.2, 3.35, 3.4, ic.imagen, 'Comprobante adjunto', 'PDF o imagen del banco, abierto desde la lista.');
  filaIcono(s, 6.2, 4.25, 3.4, ic.anular, 'Anulación', 'Devuelve el saldo a las cuotas y anula la póliza.');
  s.addNotes('La póliza carga Proveedores (una línea por factura) y abona la cuenta del banco. Las transferencias entran al estado de cuenta, al flujo de caja y a la conciliación bancaria.');

  // Caja ------------------------------------------------------------------
  s = claro(); etiqueta(s, '10 · Caja'); titulo(s, 'Caja cuadrada todos los días', 'Corte con conteo físico, depósitos y caja chica.');
  captura(s, 'caja_corte.png', 0.45, 1.45, 5.45);
  filaIcono(s, 6.2, 1.55, 3.4, ic.caja, 'Apertura por sucursal', 'Con monto inicial; no se abre un día nuevo sin cerrar el anterior.');
  filaIcono(s, 6.2, 2.45, 3.4, ic.check, 'Corte con cuadre', 'Esperado por forma de pago contra lo contado; la diferencia genera póliza.');
  filaIcono(s, 6.2, 3.35, 3.4, ic.banco, 'Depósitos', 'A una cuenta bancaria; la póliza carga su cuenta de depósitos.');
  filaIcono(s, 6.2, 4.25, 3.4, ic.factura, 'Caja chica', 'Facturas, vales y recibos; liquidación y reposición con póliza.');
  s.addNotes('Caja por sucursal con apertura, corte por forma de pago (efectivo, cheque, tarjeta y transferencia), cierre y depósitos. En caja chica el proveedor solo se exige en las facturas.');

  // Bancos ----------------------------------------------------------------
  s = claro(); etiqueta(s, '11 · Bancos'); titulo(s, 'Cuentas, cheques y conciliación', 'Cada movimiento bancario con su cuenta contable, su póliza y su conciliación.');
  filaIcono(s, 0.5, 1.55, 3.3, ic.banco, 'Cargos y abonos', 'Cada cuenta define la cuenta contable de depósitos y la de pagos.');
  filaIcono(s, 0.5, 2.45, 3.3, ic.caja, 'Cheques libres', 'Beneficiario, motivo, cuenta de gasto y centro de costo.');
  filaIcono(s, 0.5, 3.35, 3.3, ic.check, 'Conciliación bancaria', 'Estado de cuenta importado y conciliado automáticamente.');
  filaIcono(s, 0.5, 4.25, 3.3, ic.grafico, 'Flujo de caja', 'Real según las pólizas y proyectado con cobros y pagos.');
  captura(s, 'conciliacion.png', 4.1, 1.45, 5.45);
  s.addNotes('La conciliación empareja por documento o por monto y fecha: depósitos, cheques, transferencias y boletas verificadas. Lo que falta se marca a mano o con póliza de ajuste, y se cierra solo si cuadra.');

  // Contabilidad -----------------------------------------------------------
  s = claro(); etiqueta(s, '12 · Contabilidad'); titulo(s, 'Contabilidad automática', 'Cada operación genera su póliza de partida doble, siempre cuadrada.');
  const ops = ['Venta', 'Compra', 'Cobro', 'Boleta', 'Cheque', 'Transferencia', 'Depósito', 'Cierre de caja', 'Nómina', 'Notas', 'Ajuste de inventario', 'Depreciación'];
  ops.forEach((o, i) => {
    const x = 0.5 + (i % 3) * 1.4, y = 1.5 + Math.floor(i / 3) * 0.62;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 1.28, h: 0.5, rectRadius: 0.08, fill: { color: i === 0 ? BLUE : BLANCO }, line: { color: i === 0 ? BLUE : 'D7DEE8', width: 0.75 } });
    s.addText(o, { x, y, w: 1.28, h: 0.5, fontFace: T, fontSize: 10.5, bold: true, color: i === 0 ? BLANCO : NAVY, align: 'center', valign: 'middle', margin: 0, isTextBox: true });
  });
  s.addText('Las cuentas de cada concepto se configuran en «Cuentas de pólizas automáticas». También pólizas manuales, libros diario y mayor, balanza y centros de costo.',
    { x: 0.5, y: 4.08, w: 4.1, h: 0.9, fontFace: T, fontSize: 11.5, color: TEXTO, margin: 0, valign: 'top', isTextBox: true });
  captura(s, 'nomenclatura.png', 4.85, 1.45, 4.7);
  s.addNotes('Las operaciones generan póliza automáticamente y cada póliza debe cuadrar. Al anular un documento, su póliza queda anulada.');

  s = claro(); etiqueta(s, '12 · Contabilidad'); titulo(s, 'Estados financieros', 'Balance General y Estado de Resultados por nodos, al día.');
  captura(s, 'estados_financieros.png', 0.45, 1.45, 5.45);
  filaIcono(s, 6.2, 1.55, 3.4, ic.capas, 'Por nodos', 'Se abren hasta la cuenta de detalle y su libro mayor.');
  filaIcono(s, 6.2, 2.45, 3.4, ic.calendario, 'Comparativos', 'Contra otra fecha o período.');
  filaIcono(s, 6.2, 3.35, 3.4, ic.inventario, 'Activos fijos', 'Depreciación mensual con los porcentajes del ISR.');
  filaIcono(s, 6.2, 4.25, 3.4, ic.excel, 'Imprimir o Excel', 'Con el logotipo de la empresa.');
  s.addNotes('Los estados financieros se calculan con las pólizas vigentes. Los cierres de período y de ejercicio se hacen desde Contabilidad › Períodos.');

  // RRHH -------------------------------------------------------------------
  s = claro(); etiqueta(s, '13 · Recursos humanos'); titulo(s, 'Personas y nómina', 'Nómina por período y pago sin efectivo, integrados con contabilidad.');
  captura(s, 'nomina_pago.png', 0.45, 1.45, 5.45);
  filaIcono(s, 6.2, 1.55, 3.4, ic.calendario, 'Semanal, quincenal o mensual', 'Cada empleado tiene su tipo; se sugiere el siguiente período.');
  filaIcono(s, 6.2, 2.45, 3.4, ic.banco, 'Pago sin efectivo', 'Transferencias con archivo para el banco, o cheques.');
  filaIcono(s, 6.2, 3.35, 3.4, ic.conta, 'Centro de costo', 'El sueldo va al departamento de la plaza del empleado.');
  filaIcono(s, 6.2, 4.25, 3.4, ic.capas, 'Estructura y organigrama', 'Unidades anidadas sin límite; el organigrama se dibuja solo.');
  s.addNotes('Empleados con sus datos de pago, nómina con póliza por centro de costo al aprobarla y pago por transferencia o cheque.');

  s = claro(); etiqueta(s, '13 · Recursos humanos'); titulo(s, 'Libro de salarios y planilla del IGSS', 'Lo que piden el Ministerio de Trabajo y el IGSS, desde la nómina.');
  filaIcono(s, 0.5, 1.55, 3.3, ic.factura, 'Libro de salarios', 'Formato del Ministerio de Trabajo, por empleado y año.');
  filaIcono(s, 0.5, 2.45, 3.3, ic.caja, 'Cuotas', 'Laboral y patronal, IRTRA e INTECAP por centro de trabajo.');
  filaIcono(s, 0.5, 3.35, 3.3, ic.subir, 'Archivo para el IGSS', 'Sistema propio, formato 2.2.0.');
  filaIcono(s, 0.5, 4.25, 3.3, ic.calendario, 'Prestaciones', 'Aguinaldo y bono 14 con su provisión.');
  captura(s, 'planilla_igss.png', 4.1, 1.45, 5.45);
  s.addNotes('La planilla del mes se arma con las nóminas aprobadas cuyo período termina en ese mes.');

  // Puesta en marcha ----------------------------------------------------------
  s = claro(); etiqueta(s, '14 · Puesta en marcha'); titulo(s, 'Arranque desde Excel', 'Los datos iniciales se cargan con plantillas, validadas antes de grabar.');
  const pasosCarga = [['excel', '1. Plantilla', 'Con instrucciones y listas desplegables'], ['subir', '2. Subir', 'El archivo lleno, tal cual'], ['check', '3. Grabar', 'Si una fila tiene error, no se graba nada']];
  pasosCarga.forEach(([k, cab, txt], i) => {
    const x = 0.5 + i * 1.42, y = 1.5;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 1.3, h: 1.45, rectRadius: 0.1, fill: { color: i === 2 ? BLUE : BLANCO }, line: { color: i === 2 ? BLUE : 'D7DEE8', width: 0.75 } });
    s.addImage({ data: i === 2 ? ic[k] : ic[k + 'Azul'], x: x + 0.14, y: y + 0.16, w: 0.3, h: 0.3 });
    s.addText(cab, { x: x + 0.14, y: y + 0.54, w: 1.1, h: 0.3, fontFace: H, fontSize: 12, bold: true, color: i === 2 ? BLANCO : NAVY, margin: 0, isTextBox: true });
    s.addText(txt, { x: x + 0.14, y: y + 0.84, w: 1.1, h: 0.55, fontFace: T, fontSize: 9.5, color: i === 2 ? ICE : TENUE, margin: 0, valign: 'top', isTextBox: true });
  });
  filaIcono(s, 0.5, 3.2, 4.1, ic.inventario, 'Inventario inicial', 'Productos, existencias, costo y precio de venta por bodega.');
  filaIcono(s, 0.5, 3.85, 4.1, ic.conta, 'Saldos iniciales', 'Debe y Haber por cuenta; se genera la partida de apertura.');
  filaIcono(s, 0.5, 4.5, 4.1, ic.rrhh, 'Empleados', 'Alta o actualización con plaza, salario y datos de pago.');
  captura(s, 'saldos_iniciales.png', 4.85, 1.45, 4.7);
  s.addNotes('Tres cargas desde Excel para arrancar: inventario inicial, saldos iniciales con su partida de apertura y empleados.');

  // Administración --------------------------------------------------------
  s = claro(); etiqueta(s, '15 · Administración'); titulo(s, 'Seguridad y configuración', 'Cada quien ve y hace solo lo que le corresponde.');
  filaIcono(s, 0.5, 1.55, 3.3, ic.seguridad, 'Roles y permisos', 'Cada permiso con dónde se usa, sus roles y sus usuarios.');
  filaIcono(s, 0.5, 2.45, 3.3, ic.llave, 'Contraseñas seguras', 'Guardadas con hash, nunca en texto plano.');
  filaIcono(s, 0.5, 3.35, 3.3, ic.sucursal, 'Multi-sucursal', 'Sucursales, bodegas y cajas; la sesión trabaja en una sucursal.');
  filaIcono(s, 0.5, 4.25, 3.3, ic.auditoria, 'Auditoría', 'Cada registro guarda quién y cuándo lo creó y lo modificó.');
  captura(s, 'permisos.png', 4.1, 1.45, 5.45);
  s.addNotes('Seguridad por roles y permisos por pantalla y por acción, con refresco de permisos en las sesiones abiertas.');

  s = claro(); etiqueta(s, '15 · Administración'); titulo(s, 'Con la imagen de su empresa', 'Su logotipo y su cuenta de correo, en todo el sistema.');
  captura(s, 'inicio_logo.png', 0.45, 1.45, 5.45, 1080 / 1920);
  filaIcono(s, 6.2, 1.55, 3.4, ic.imagen, 'Logotipo', 'En el menú, el inicio de sesión, los impresos y los libros de Excel.');
  filaIcono(s, 6.2, 2.45, 3.4, ic.correo, 'Correo saliente', 'Gmail por defecto, Outlook.com, Microsoft 365 u otro servidor.');
  filaIcono(s, 6.2, 3.35, 3.4, ic.factura, 'Documentos al cliente', 'Facturas, recibos, cotizaciones y estados de cuenta en PDF.');
  filaIcono(s, 6.2, 4.25, 3.4, ic.llave, 'Contraseña cifrada', 'Gmail usa una contraseña de aplicación.');
  s.addNotes('No hace falta un servidor de correo propio: se usa la cuenta de la compañía. Microsoft está retirando el SMTP con contraseña en cuentas personales de Outlook/Hotmail; en ese caso conviene Gmail o Microsoft 365.');

  // Sin perder el trabajo -------------------------------------------------
  s = claro(); etiqueta(s, '16 · Sin perder el trabajo'); titulo(s, 'Cambiar de opción sin perder lo capturado', 'Un documento a medias no se pierde al ir a otra pantalla.');
  const flujo = [['factura', 'A medias', 'Una factura sin grabar'], ['anular', 'Aviso al salir', 'Quedarme o salir y guardar borrador'], ['reloj', 'Borrador', 'En este navegador, por usuario y sucursal'], ['check', 'Recuperar', 'Tal como estaba, al volver']];
  flujo.forEach(([k, cab, txt], i) => {
    const x = 0.5 + i * 2.33;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 1.6, w: 1.95, h: 1.5, rectRadius: 0.1, fill: { color: i === 3 ? BLUE : BLANCO }, line: { color: i === 3 ? BLUE : 'D7DEE8', width: 0.75 } });
    s.addImage({ data: i === 3 ? ic[k] : ic[k + 'Azul'], x: x + 0.2, y: 1.78, w: 0.34, h: 0.34 });
    s.addText(cab, { x: x + 0.2, y: 2.2, w: 1.65, h: 0.3, fontFace: H, fontSize: 14, bold: true, color: i === 3 ? BLANCO : NAVY, margin: 0, isTextBox: true });
    s.addText(txt, { x: x + 0.2, y: 2.5, w: 1.65, h: 0.5, fontFace: T, fontSize: 10.5, color: i === 3 ? ICE : TENUE, margin: 0, valign: 'top', isTextBox: true });
    if (i < 3) s.addImage({ data: ic.flechaAzul, x: x + 2.02, y: 2.2, w: 0.26, h: 0.26 });
  });
  s.addText('Funciona en facturas, cotizaciones, compras, órdenes de compra, cobros, pagos a proveedores, notas, pólizas manuales, inventario físico y caja chica. En los catálogos solo hay aviso. Con Ctrl+clic en el menú se abre otra opción en una pestaña nueva.',
    { x: 0.5, y: 3.5, w: 9, h: 0.9, fontFace: T, fontSize: 12, color: TEXTO, margin: 0, valign: 'top', isTextBox: true });
  s.addNotes('El borrador queda cifrado en el navegador y separado por usuario, sucursal y pantalla. Al grabar el documento se borra.');

  // Por qué ---------------------------------------------------------------
  s = claro(); etiqueta(s, 'En resumen'); titulo(s, 'Construido para la operación diaria', 'Una sola plataforma web, segura y en español.');
  const stats = [['Web', 'Desde cualquier navegador, también en el celular'], ['FEL', 'Factura electrónica certificada al grabar'], ['Pólizas', 'Automáticas en cada operación'], ['Excel', 'Reportes y cargas iniciales']];
  stats.forEach(([n, t], i) => {
    const x = 0.5 + i * 2.3;
    s.addText(n, { x, y: 1.6, w: 2.1, h: 0.75, fontFace: H, fontSize: 36, bold: true, color: BLUE, margin: 0, valign: 'bottom', isTextBox: true });
    s.addText(t, { x, y: 2.42, w: 2.05, h: 0.65, fontFace: T, fontSize: 11.5, color: TENUE, margin: 0, valign: 'top', isTextBox: true });
  });
  filaIcono(s, 0.5, 3.45, 4.3, ic.db, 'Transacciones completas', 'Documento, inventario, cartera y póliza se graban juntos o no se graba nada.');
  filaIcono(s, 5.2, 3.45, 4.3, ic.web, 'Accesible', 'Contraste AA, foco visible con teclado y uso en celular.');
  s.addNotes('Resumen para cerrar: plataforma web, factura electrónica, contabilidad automática y reportes en Excel.');

  // 13. Cierre ----------------------------------------------------------------
  s = oscuro();
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 3.95, y: 0.7, w: 2.1, h: 1.98, rectRadius: 0.2, fill: { color: BLANCO },
    shadow: { type: 'outer', color: '040A23', opacity: 0.4, blur: 20, offset: 6, angle: 90 } });
  s.addImage({ data: logo, x: 4.07, y: 0.8, w: 1.86, h: 1.86 * 430 / 460 });
  s.addText('Gracias', { x: 1, y: 2.95, w: 8, h: 0.8, fontFace: H, fontSize: 40, bold: true, color: BLANCO, align: 'center', margin: 0, isTextBox: true });
  s.addText('Un ERP completo en la web, listo para crecer con su empresa.', { x: 1, y: 3.75, w: 8, h: 0.4, fontFace: T, fontSize: 16, color: ICE, align: 'center', margin: 0, isTextBox: true });
  s.addText('Servicios Informáticos Integrados', { x: 1, y: 4.8, w: 8, h: 0.3, fontFace: T, fontSize: 11, color: 'A9C6F0', align: 'center', charSpacing: 2, margin: 0, isTextBox: true });
  s.addNotes('Cierre. Espacio para preguntas y para mostrar en vivo cualquier módulo.');

  await pres.writeFile({ fileName: path.join(SALIDA, 'Demo ERP - Servicios Informaticos Integrados.pptx') });
  console.log('ok');
})();
