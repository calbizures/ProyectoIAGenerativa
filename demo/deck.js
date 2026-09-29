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

  const fondo = await fondoDegradado();
  const logo = await logoPng();
  const ic = {};
  for (const [k, C] of Object.entries({ grafico: Fi.FiTrendingUp, factura: Fi.FiFileText, fel: Fi.FiShield, cobrar: Fi.FiCreditCard,
    compras: Fi.FiShoppingCart, banco: Fi.FiBriefcase, conta: Fi.FiBookOpen, rrhh: Fi.FiUsers, seguridad: Fi.FiLock, check: Fi.FiCheck,
    reloj: Fi.FiRefreshCw, llave: Fi.FiKey, anular: Fi.FiXCircle, db: Fi.FiDatabase, web: Fi.FiMonitor, capas: Fi.FiLayers, flecha: Fi.FiArrowRight,
    filtro: Fi.FiFilter, clic: Fi.FiMousePointer, calendario: Fi.FiCalendar, caja: Fi.FiDollarSign, sucursal: Fi.FiMapPin, auditoria: Fi.FiEye, excel: Fi.FiDownload })) {
    ic[k] = await icono(C, BLANCO);
    ic[k + 'Azul'] = await icono(C, BLUE);
  }

  // --- ayudantes -----------------------------------------------------------
  const titulo = (s, texto, sub) => {
    s.addText(texto, { x: 0.5, y: 0.32, w: 9, h: 0.6, fontFace: H, fontSize: 30, bold: true, color: NAVY, margin: 0, isTextBox: true });
    if (sub) s.addText(sub, { x: 0.5, y: 0.9, w: 9, h: 0.35, fontFace: T, fontSize: 14, color: TENUE, margin: 0, isTextBox: true });
  };
  const etiqueta = (s, texto) => s.addText(texto.toUpperCase(), { x: 0.5, y: 0.12, w: 6, h: 0.22, fontFace: T, fontSize: 10, bold: true, color: BLUE, charSpacing: 2, margin: 0, isTextBox: true });
  const captura = (s, archivo, x, y, w) => {
    const h = w * 1034 / 1582;
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
  s.addText('De la venta a la contabilidad, en una sola plataforma web: facturación con FEL, cartera, compras, bancos, contabilidad automática y RRHH.',
    { x: 3.75, y: 3.2, w: 5.6, h: 0.85, fontFace: T, fontSize: 14, color: ICE, margin: 0, valign: 'top', isTextBox: true });
  s.addText('Acompaña al video de la demo (8 min)', { x: 0.75, y: 4.95, w: 6, h: 0.3, fontFace: T, fontSize: 11, color: 'A9C6F0', margin: 0, isTextBox: true });
  s.addNotes('Presentación del ERP de Servicios Informáticos Integrados. El recorrido sigue el mismo orden del video: acceso, tableros, facturación y FEL, cartera, compras, caja y bancos, contabilidad, RRHH y administración.');

  // 2. Módulos ----------------------------------------------------------------
  s = claro(); etiqueta(s, 'Visión general'); titulo(s, 'Una plataforma, toda la operación', 'Ocho módulos integrados sobre la misma base de datos: cada operación alimenta a las demás.');
  const mods = [['grafico', 'Tableros', 'Ventas, cartera, compras y compromisos'], ['factura', 'Ventas y FEL', 'Factura con bienes y servicios, certificada al grabar'],
    ['cobrar', 'Cartera (CxC)', 'Estado de cuenta, cobros y antigüedad'], ['compras', 'Compras', 'Inventario por bodega y costo promedio'],
    ['banco', 'Caja y bancos', 'Apertura, corte con cuadre y depósitos'], ['conta', 'Contabilidad', 'Pólizas automáticas de partida doble'],
    ['rrhh', 'RRHH', 'Empleados, nómina y organigrama'], ['seguridad', 'Administración', 'Roles, permisos, sucursales y auditoría']];
  mods.forEach(([k, cab, txt], i) => {
    const x = 0.5 + (i % 4) * 2.3, y = 1.55 + Math.floor(i / 4) * 1.85;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 2.1, h: 1.6, rectRadius: 0.1, fill: { color: BLANCO }, line: { color: 'E8EDF4', width: 0.75 },
      shadow: { type: 'outer', color: '0D1B4C', opacity: 0.08, blur: 8, offset: 2, angle: 90 } });
    s.addShape(pres.shapes.OVAL, { x: x + 0.2, y: y + 0.2, w: 0.5, h: 0.5, fill: { color: i % 2 ? BLUE5 : BLUE } });
    s.addImage({ data: ic[k], x: x + 0.32, y: y + 0.32, w: 0.26, h: 0.26 });
    s.addText(cab, { x: x + 0.2, y: y + 0.78, w: 1.8, h: 0.3, fontFace: H, fontSize: 13, bold: true, color: NAVY, margin: 0, isTextBox: true });
    s.addText(txt, { x: x + 0.2, y: y + 1.08, w: 1.8, h: 0.45, fontFace: T, fontSize: 10, color: TENUE, margin: 0, valign: 'top', isTextBox: true });
  });
  s.addNotes('Todos los módulos comparten la misma base de datos: una factura mueve inventario, cartera, FEL, tableros y contabilidad en una sola transacción.');

  // 3. Tableros ---------------------------------------------------------------
  s = claro(); etiqueta(s, '02 · Tableros'); titulo(s, 'Tableros gerenciales', 'La información para decidir, al día y en una sola pantalla.');
  filaIcono(s, 0.5, 1.55, 3.3, ic.grafico, 'Ventas y margen real', 'Margen bruto calculado con el costo grabado en cada línea.');
  filaIcono(s, 0.5, 2.45, 3.3, ic.clic, 'Interactivos', 'Detalle al pasar el puntero; un clic en un mes lo abre por día.');
  filaIcono(s, 0.5, 3.35, 3.3, ic.calendario, 'Compromisos de pago', 'Lo que vence con proveedores en las próximas 12 semanas.');
  filaIcono(s, 0.5, 4.25, 3.3, ic.filtro, 'Filtros', 'Por período y por sucursal; cada gráfico tiene vista de tabla.');
  captura(s, 'tablero_ventas.png', 4.1, 1.45, 5.45);
  s.addNotes('Tres tableros: ventas, recuperación de cartera y compras con compromisos de pago. El margen usa el costo real grabado en cada línea de factura. Un clic en un mes lo abre por día y un clic en un cliente lleva a su estado de cuenta.');

  // 4. Facturación ------------------------------------------------------------
  s = claro(); etiqueta(s, '03 · Ventas'); titulo(s, 'Facturación completa en pocos pasos', 'Validaciones en línea y certificación FEL al grabar.');
  captura(s, 'factura_detalle.png', 0.45, 1.45, 5.45);
  filaIcono(s, 6.2, 1.55, 3.4, ic.factura, 'Bienes y servicios', 'La columna B/S mezcla productos de inventario y servicios.');
  filaIcono(s, 6.2, 2.45, 3.4, ic.cobrar, 'Contado o crédito', 'Plan de cuotas y validación del límite de crédito del cliente.');
  filaIcono(s, 6.2, 3.35, 3.4, ic.fel, 'Certificada al grabar', 'UUID, serie y número de SAT en el mismo momento.');
  filaIcono(s, 6.2, 4.25, 3.4, ic.anular, 'Anulación controlada', 'Con motivo y confirmación; revierte inventario y anula la póliza.');
  s.addNotes('Factura de ejemplo: una laptop y un servicio de instalación, a crédito en tres cuotas. El sistema muestra límite, saldo y crédito disponible; si el monto a financiar lo excede, no permite grabar. Al grabar se certifica ante el certificador FEL.');

  // 5. FEL --------------------------------------------------------------------
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
  filaIcono(s, 0.5, 3.3, 2.9, ic.reloj, 'Reintento automático', 'Si no hay conexión, la factura queda grabada como pendiente y se reenvía sola.');
  filaIcono(s, 3.55, 3.3, 2.9, ic.anular, 'Anulación ante SAT', 'Con motivo; queda registrada con su XML de anulación.');
  filaIcono(s, 6.6, 3.3, 2.9, ic.llave, 'Llaves protegidas', 'Las credenciales del certificador van fuera de la base de datos.');
  s.addText('Parámetros: certificador, ambiente, emisor, establecimientos, frases, tipos de DTE (FACT, FCAM con abonos, NCRE, NDEB) y unidades de medida. Cada intento queda en bitácora con el XML enviado y el certificado.',
    { x: 0.5, y: 4.45, w: 9, h: 0.6, fontFace: T, fontSize: 11.5, color: TEXTO, margin: 0, valign: 'top', isTextBox: true });
  s.addNotes('El XML del DTE se arma con datos parametrizados (emisor, establecimiento, frases, tipo de DTE, unidades), se envía al certificador y se guarda la autorización. En la demo se usó el simulador; con INFILE el flujo es el mismo. Los documentos anteriores se certifican en lote, y cada nota espera a su factura de origen.');

  // 6. Cuentas por cobrar -----------------------------------------------------
  s = claro(); etiqueta(s, '05 · Cuentas por cobrar'); titulo(s, 'Cartera bajo control', 'Del saldo del cliente al recibo impreso.');
  filaIcono(s, 0.5, 1.55, 3.3, ic.cobrar, 'Varias cuotas, un recibo', 'El monto recibido se aplica a las cuotas más antiguas.');
  filaIcono(s, 0.5, 2.45, 3.3, ic.factura, 'Recibo imprimible', 'Anulable con motivo mientras la caja siga abierta.');
  filaIcono(s, 0.5, 3.35, 3.3, ic.auditoria, 'Estado de cuenta', 'Facturas, cuotas, cobros y notas con su saldo.');
  filaIcono(s, 0.5, 4.25, 3.3, ic.excel, 'Antigüedad de saldos', 'Por rangos de días, exportable a Excel.');
  captura(s, 'cxc_antiguedad.png', 4.1, 1.45, 5.45);
  s.addNotes('Cobro de varias cuotas con un solo recibo y su póliza. La antigüedad de saldos se consulta por cliente o por factura y se exporta a Excel.');

  // 7. Costo promedio ---------------------------------------------------------
  s = claro(); etiqueta(s, '06 · Compras e inventario'); titulo(s, 'Cada compra actualiza el costo real', 'Costo neto de descuento y sin IVA, promediado con la existencia.');
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 0.5, y: 1.5, w: 4.2, h: 3.55, rectRadius: 0.12, fill: { color: NAVY } });
  s.addText('EJEMPLO DE LA DEMO', { x: 0.8, y: 1.72, w: 3.7, h: 0.25, fontFace: T, fontSize: 10, bold: true, color: '7EE0FB', charSpacing: 2, margin: 0, isTextBox: true });
  s.addText('10 laptops a Q4,256 con IVA y Q2,240 de descuento', { x: 0.8, y: 2.0, w: 3.7, h: 0.5, fontFace: T, fontSize: 12.5, color: ICE, margin: 0, valign: 'top', isTextBox: true });
  s.addText('Q3,600', { x: 0.8, y: 2.5, w: 3.7, h: 0.7, fontFace: H, fontSize: 40, bold: true, color: BLANCO, margin: 0, isTextBox: true });
  s.addText('costo por unidad que entra al inventario', { x: 0.8, y: 3.15, w: 3.7, h: 0.3, fontFace: T, fontSize: 11.5, color: ICE, margin: 0, isTextBox: true });
  s.addText([{ text: '(Q3,224 × 95 + Q3,600 × 10) ÷ 105 = ', options: { color: ICE } }, { text: 'Q3,259.81', options: { color: BLANCO, bold: true } }],
    { x: 0.8, y: 3.62, w: 3.75, h: 0.35, fontFace: T, fontSize: 11.5, margin: 0, isTextBox: true });
  s.addText('Nuevo costo promedio. La siguiente venta lo graba en su línea y en la póliza de costo de ventas.', { x: 0.8, y: 4.08, w: 3.7, h: 0.7, fontFace: T, fontSize: 11, color: ICE, margin: 0, valign: 'top', isTextBox: true });
  captura(s, 'productos.png', 5.0, 1.5, 4.55);
  s.addText('Existencia, costo unitario y estado de cada producto.', { x: 5.0, y: 4.62, w: 4.55, h: 0.3, fontFace: T, fontSize: 10.5, italic: true, color: TENUE, margin: 0, isTextBox: true });
  s.addNotes('Al grabar la compra, en una sola transacción, sube la existencia, se recalcula el costo promedio ponderado y se genera la póliza de compra. La venta toma el costo en ese momento, por eso el margen de los tableros es real.');

  // 8. Caja y bancos ----------------------------------------------------------
  s = claro(); etiqueta(s, '07 · Proveedores, caja y bancos'); titulo(s, 'Caja cuadrada todos los días', 'Pagos con cheque, corte con conteo físico y depósitos.');
  captura(s, 'caja_corte.png', 0.45, 1.45, 5.45);
  filaIcono(s, 6.2, 1.55, 3.4, ic.caja, 'Apertura por sucursal', 'Con monto inicial; no se abre un día nuevo sin cerrar el anterior.');
  filaIcono(s, 6.2, 2.45, 3.4, ic.check, 'Corte con cuadre', 'Esperado por forma de pago contra lo contado; la diferencia genera póliza.');
  filaIcono(s, 6.2, 3.35, 3.4, ic.banco, 'Depósitos', 'A la cuenta de la entidad financiera, con póliza de banco.');
  filaIcono(s, 6.2, 4.25, 3.4, ic.factura, 'Pagos con cheque', 'Por cuotas del proveedor; anulables con motivo.');
  s.addNotes('Caja por sucursal: apertura, corte con conteo físico por denominación y forma de pago, cierre con faltante o sobrante contabilizado, y depósitos al banco.');

  // 9. Contabilidad -----------------------------------------------------------
  s = claro(); etiqueta(s, '08 · Contabilidad'); titulo(s, 'Contabilidad automática', 'Cada operación genera su póliza de partida doble, siempre cuadrada.');
  const ops = ['Venta', 'Compra', 'Cobro', 'Cheque', 'Depósito', 'Cierre de caja', 'Nómina', 'Nota de crédito', 'Nota de débito'];
  ops.forEach((o, i) => {
    const x = 0.5 + (i % 3) * 1.4, y = 1.55 + Math.floor(i / 3) * 0.72;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 1.28, h: 0.56, rectRadius: 0.08, fill: { color: i === 0 ? BLUE : BLANCO }, line: { color: i === 0 ? BLUE : 'D7DEE8', width: 0.75 } });
    s.addText(o, { x, y, w: 1.28, h: 0.56, fontFace: T, fontSize: 11.5, bold: true, color: i === 0 ? BLANCO : NAVY, align: 'center', valign: 'middle', margin: 0, isTextBox: true });
  });
  s.addText('Las cuentas de cada concepto se configuran en «Cuentas de pólizas automáticas». La nomenclatura es jerárquica y se mantiene por nodos.',
    { x: 0.5, y: 3.8, w: 4.1, h: 0.9, fontFace: T, fontSize: 12, color: TEXTO, margin: 0, valign: 'top', isTextBox: true });
  captura(s, 'nomenclatura.png', 4.85, 1.45, 4.7);
  s.addNotes('Nueve tipos de operación generan póliza automáticamente. Un trigger valida que cada póliza cuadre. Al anular un documento, su póliza queda anulada.');

  // 10. RRHH ------------------------------------------------------------------
  s = claro(); etiqueta(s, '09 · Recursos humanos'); titulo(s, 'Personas y nómina', 'Estructura organizativa, empleados y planilla integrados con contabilidad.');
  captura(s, 'organigrama.png', 0.45, 1.45, 5.45);
  filaIcono(s, 6.2, 1.55, 3.4, ic.rrhh, 'Empleados', 'Puesto, plaza y unidad; vinculables a su usuario y código de vendedor.');
  filaIcono(s, 6.2, 2.45, 3.4, ic.caja, 'Nómina', 'Ingresos y descuentos por tipo; al aprobarla genera su póliza.');
  filaIcono(s, 6.2, 3.35, 3.4, ic.capas, 'Estructura sin límite', 'Unidades anidadas, departamentos, puestos y plazas.');
  filaIcono(s, 6.2, 4.25, 3.4, ic.grafico, 'Organigrama', 'Se dibuja solo a partir de la estructura registrada.');
  s.addNotes('RRHH: empleados, nómina con póliza contable y estructura organizativa recursiva, con organigrama generado automáticamente.');

  // 11. Administración --------------------------------------------------------
  s = claro(); etiqueta(s, '10 · Administración'); titulo(s, 'Seguridad y configuración', 'Cada quien ve y hace solo lo que le corresponde.');
  filaIcono(s, 0.5, 1.55, 3.3, ic.seguridad, 'Roles y permisos', 'Cada pantalla exige su permiso; los cambios aplican en menos de un minuto.');
  filaIcono(s, 0.5, 2.45, 3.3, ic.llave, 'Contraseñas seguras', 'Guardadas con hash, nunca en texto plano.');
  filaIcono(s, 0.5, 3.35, 3.3, ic.sucursal, 'Multi-sucursal', 'Sucursales, bodegas y cajas; la sesión trabaja en una sucursal.');
  filaIcono(s, 0.5, 4.25, 3.3, ic.auditoria, 'Auditoría', 'Cada registro guarda quién y cuándo lo creó y lo modificó.');
  captura(s, 'permisos.png', 4.1, 1.45, 5.45);
  s.addNotes('Seguridad por roles y permisos por pantalla, con refresco de permisos en las sesiones abiertas. Auditoría por registro en todas las tablas de negocio.');

  // 12. Tecnología ------------------------------------------------------------
  s = claro(); etiqueta(s, 'Tecnología'); titulo(s, 'Construido para durar', 'Base de datos sólida y aplicación web moderna.');
  const stats = [['SQL Server', 'Base de datos con reglas de negocio en procedimientos almacenados'], ['.NET 8', 'Aplicación web Blazor Server, responsive'], ['36', 'Scripts de instalación re-ejecutables'], ['42', 'Pantallas verificadas en escritorio y celular']];
  stats.forEach(([n, t], i) => {
    const x = 0.5 + i * 2.3;
    s.addText(n, { x, y: 1.6, w: 2.1, h: 0.75, fontFace: H, fontSize: n.length > 4 ? 26 : 44, bold: true, color: BLUE, margin: 0, valign: 'bottom', isTextBox: true });
    s.addText(t, { x, y: 2.42, w: 2.05, h: 0.65, fontFace: T, fontSize: 11.5, color: TENUE, margin: 0, valign: 'top', isTextBox: true });
  });
  filaIcono(s, 0.5, 3.45, 4.3, ic.db, 'Transacciones completas', 'Documento, inventario, cartera y póliza se graban juntos o no se graba nada.');
  filaIcono(s, 5.2, 3.45, 4.3, ic.web, 'Accesible', 'Contraste AA, foco visible con teclado y uso en celular.');
  s.addNotes('SQL Server con la lógica de negocio en procedimientos almacenados y una aplicación Blazor Server sobre .NET 8. La instalación son 36 scripts re-ejecutables.');

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
