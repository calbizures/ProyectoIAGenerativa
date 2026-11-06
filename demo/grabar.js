// Recorrido completo de la demo, una función por sección. Uso:
//   node grabar.js                 -> todas las secciones
//   node grabar.js ventas fel      -> solo esas (inicia sesión fuera de cámara)
// Necesita la base recién instalada: graba de verdad la cotización y su
// factura, el cobro, la boleta, las compras, la toma de inventario, los pagos
// a proveedores, el depósito, el vale, el cheque libre y el logotipo.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const { Demo, SALIDA, sql } = require('./lib');
const q2 = n => Number(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const TOMAS = path.join(SALIDA, 'tomas');
const IMAGENES = path.join(SALIDA, 'imagenes');
const d = new Demo(TOMAS);
const nuevaFila = '.doc-seccion .doc-buscador-resultados .doc-resultado-fila';

async function iniciarSesion(usuario = 'admin') {
  await d.ir('login');
  await d.p.fill('#usuario', usuario); await d.p.fill('#password', 'Demo#2024');
  await d.p.click('button[type=submit]'); await d.p.waitForLoadState('networkidle');
  if (await d.p.$('#sucursal')) { await d.p.selectOption('#sucursal', { index: 1 }); await d.p.click('button[type=submit]'); await d.p.waitForLoadState('networkidle'); }
  await d.espera(600);
}

async function cerrarSesion() {
  await d.p.evaluate(() => { const f = document.querySelector('form[action="logout"]'); if (f) f.submit(); });
  await d.p.waitForURL(u => u.toString().includes('/login'), { timeout: 15000 }).catch(() => {});
  await d.espera(600);
}

async function sinErrores(que) {
  const err = await d.p.$$eval('.mensaje-error', e => e.map(x => x.textContent.trim()).filter(Boolean));
  if (err.length) throw new Error(que + ': ' + err.join(' | '));
}

// Imagen de ejemplo (comprobante o boleta) para adjuntar; no imita a ningún banco.
async function generarImagen(archivo, titulo, filas, monto) {
  fs.mkdirSync(IMAGENES, { recursive: true });
  const ruta = path.join(IMAGENES, archivo);
  const nav = await chromium.launch();
  const p = await nav.newPage({ viewport: { width: 760, height: 520 }, deviceScaleFactor: 2 });
  await p.setContent(`<html><body style="margin:0;font-family:Segoe UI,Arial,sans-serif;background:#eef2f7">
    <div style="margin:24px;background:#fff;border-radius:14px;padding:28px 34px;box-shadow:0 4px 18px rgba(13,27,76,.12)">
      <div style="display:flex;justify-content:space-between;align-items:center">
        <div style="font-size:22px;font-weight:700;color:#0d1b4c">${titulo}</div>
        <div style="font-size:12px;color:#fff;background:#2e7d32;border-radius:20px;padding:5px 12px">Operación exitosa</div></div>
      <div style="font-size:12px;color:#8a94a6;margin-top:4px">Documento de ejemplo para la demo · sin validez</div>
      <table style="margin-top:22px;width:100%;font-size:15px;border-collapse:collapse">
        ${filas.map(([a, b]) => `<tr><td style="padding:8px 0;color:#5f6a7f;border-bottom:1px solid #eef1f5">${a}</td><td style="padding:8px 0;text-align:right;font-weight:600;color:#1c2437;border-bottom:1px solid #eef1f5">${b}</td></tr>`).join('')}
      </table>
      <div style="margin-top:18px;display:flex;justify-content:space-between;align-items:baseline">
        <span style="color:#5f6a7f">Monto</span><span style="font-size:28px;font-weight:700;color:#1565c0">Q ${q2(monto)}</span></div>
    </div></body></html>`);
  await p.screenshot({ path: ruta });
  await nav.close();
  return ruta;
}
const hoy = () => new Date().toLocaleDateString('es-GT');

// Clientes con más cuotas pendientes (los datos de prueba varían por instalación).
function clientesConCuotas() {
  return sql(`SELECT TOP 3 clie.cli_codigo FROM dbo.pos_cliente_plan_pagos cuot JOIN dbo.pos_cliente clie ON clie.cli_id = cuot.cli_id
    JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G' WHERE cuot.cpp_saldo_cuota > 0
    GROUP BY clie.cli_codigo ORDER BY COUNT(*) DESC, SUM(cuot.cpp_saldo_cuota), clie.cli_codigo`).map(f => f[0]);
}

async function elegirCliente(codigo) {
  const quitar = d.p.locator('.doc-chip button').first();
  if (await quitar.count()) await d.clic(quitar, 900);
  await d.escribir('input[placeholder^="Buscar cliente"]', codigo);
  await d.p.keyboard.press('Enter'); await d.espera(1200);
  await d.clic('.doc-buscador-resultados .doc-resultado-fila', 1600);
}

// Proveedor con cuenta para transferencia y saldo pendiente (de preferencia PRV04).
function proveedorTransferencia() {
  const [fila] = sql(`SELECT TOP 1 prov.prv_id, prov.prv_codigo FROM dbo.inv_proveedor prov
    JOIN dbo.inv_documento_enc docu ON docu.prv_id = prov.prv_id AND docu.enc_estado = 'G'
    JOIN dbo.inv_proveedor_plan_pago cuot ON cuot.enc_id = docu.enc_id AND cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) > 0
    WHERE prov.prv_gef_id IS NOT NULL AND prov.prv_numero_cuenta IS NOT NULL
    GROUP BY prov.prv_id, prov.prv_codigo ORDER BY CASE WHEN prov.prv_codigo = 'PRV04' THEN 0 ELSE 1 END, COUNT(*) DESC`);
  if (!fila) throw new Error('Ningún proveedor con cuenta para transferencia tiene saldo.');
  return { id: fila[0], codigo: fila[1] };
}

// Orden de compra creada y aprobada con las dos firmas (jefe de bodega y
// contador general), lista para recibirse en Compras.
function prepararOrdenCompra() {
  const [[ocp, numero]] = sql(`DECLARE @det dbo.orden_compra_det_type, @id INT = NULL, @num VARCHAR(16), @hoy DATE = CAST(GETDATE() AS DATE),
      @jbod INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'jbodega'), @cgen INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'cgeneral'),
      @prv INT = (SELECT prv_id FROM dbo.inv_proveedor WHERE prv_codigo = 'PRV01'),
      @bod INT = (SELECT MIN(bod_id) FROM dbo.inv_bodega WHERE bod_estado = 'A' AND suc_id = (SELECT MIN(suc_id) FROM dbo.gen_sucursal));
    INSERT @det SELECT ROW_NUMBER() OVER (ORDER BY pro_codigo), pro_id, pro_descripcion, IIF(pro_codigo = 'LAP-DELL-3520', 6, 4), IIF(pro_codigo = 'LAP-DELL-3520', 4300, 3150)
      FROM dbo.inv_producto WHERE pro_codigo IN ('LAP-DELL-3520', 'LAP-HP-250');
    EXEC dbo.paOrdenCompraGuardar @OcpId = @id OUTPUT, @Fecha = @hoy, @FechaEntrega = @hoy, @PrvId = @prv, @BodId = @bod, @UsuId = 1,
      @Condiciones = 'Entrega en bodega principal', @Detalle = @det, @Numero = @num OUTPUT;
    EXEC dbo.paOrdenCompraAprobarBodega @OcpId = @id, @UsuId = @jbod;
    EXEC dbo.paOrdenCompraAprobar @OcpId = @id, @UsuId = @cgen;
    SELECT @id, @num;`);
  return { ocp, numero };
}

const secciones = {
  async intro() {
    await d.ir('login');
    await d.p.evaluate(() => sessionStorage.clear());
    await d.carta({
      titulo: 'ERP · Servicios Informáticos Integrados',
      sub: 'Recorrido por el producto: de la cotización a los estados financieros, en una sola plataforma web.',
      puntos: ['Cotización, factura y FEL', 'Cobros: caja, transferencia o boleta', 'Compras con orden de compra', 'Inventario, kardex y toma física',
        'Proveedores, caja y bancos', 'Contabilidad y estados financieros', 'Nómina, IGSS y RRHH', 'Seguridad y trabajo sin pérdidas'],
    }, 8500);
  },

  async acceso() {
    await d.sinCarta(1100);
    await d.rotulo('01 · Acceso', 'Inicio de sesión seguro',
      'Cada persona entra con su usuario y contraseña. Las contraseñas se guardan con <b>hash seguro</b>, nunca en texto plano.', { pos: 'abajo-izq', espera: 2200 });
    await d.escribir('#usuario', 'admin');
    await d.escribir('#password', 'Demo#2024', 900);
    await d.clic('button[type=submit]', 1400);
    await d.rotulo('01 · Acceso', 'Sucursal de trabajo',
      'Se elige la sucursal en la que se trabajará; solo aparecen las asignadas al usuario. La caja, las bodegas y la factura electrónica toman ese dato.', { pos: 'abajo-izq', espera: 2600 });
    await d.elegir('#sucursal', { index: 1 }, 1200);
    await d.clic('button[type=submit]', 1600);
    await d.rotulo('01 · Acceso', 'Menú según permisos',
      'El menú muestra solo los módulos que el rol del usuario puede usar. La barra inferior indica sucursal, usuario y base de datos.', { pos: 'abajo-der', espera: false });
    await d.resaltar('#menu-principal', 2600);
    await d.resaltar('.barra-estado', 2800);
    await d.sinResalte(); await d.sinRotulo();
  },

  async tableros() {
    await d.carta({ numero: '02 · Tableros', titulo: 'Tableros gerenciales', sub: 'La información para decidir, al día y en una sola pantalla.',
      puntos: ['Ventas y margen bruto', 'Recuperación de cartera', 'Compras y compromisos', 'Filtros por período y sucursal'] }, 4200);
    await d.ir('tableros');
    await d.sinCarta(1000);
    await d.rotulo('02 · Tableros', 'Indicadores del período',
      'Ventas netas sin IVA, margen bruto calculado con el <b>costo real de cada línea</b>, número de facturas y notas de crédito.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.kpi-grilla', 5200); await d.sinResalte();
    const franjas = d.p.locator('.grafico-franja');
    const n = await franjas.count();
    await d.rotulo('02 · Tableros', 'Detalle al pasar el puntero',
      'Cada columna muestra costo, margen y total del mes. Todos los gráficos tienen también una <b>vista de tabla</b>.', { pos: 'abajo-izq', espera: false });
    for (let i = Math.max(0, n - 5); i < n; i++) { await d.apuntar(franjas.nth(i)); await d.espera(1100); }
    await d.rotulo('02 · Tableros', 'Del mes al día',
      'Un clic en un mes muestra sus ventas día por día; «Volver» regresa a la vista mensual.', { pos: 'abajo-izq', espera: false });
    await d.clic(franjas.nth(n - 1), 2600);
    await d.apuntar(d.p.locator('.grafico-franja').nth(3)); await d.espera(1400);
    await d.clic('button:has-text("Volver")', 1600);
    await d.sinRotulo();
    await d.desplazarA('text=Mejores clientes', 'start', 1400);
    await d.rotulo('02 · Tableros', 'Clientes, productos y vendedores',
      'Rankings del período. Un clic en un cliente abre directamente su estado de cuenta.', { pos: 'abajo-der', espera: 3800 });
    await d.desplazar(0, 1000);
    await d.clic('.pestana-boton:has-text("Recuperación")', 1500);
    await d.rotulo('02 · Tableros', 'Recuperación de cartera',
      'Lo que vencía contra lo cobrado, la antigüedad de los saldos y los clientes con mora.', { pos: 'abajo-der', espera: 2600 });
    await d.desplazar(620, 1400); await d.espera(1800);
    await d.desplazar(0, 900);
    await d.clic('.pestana-boton:has-text("Compras")', 1500);
    await d.rotulo('02 · Tableros', 'Compras y compromisos de pago',
      'Compras del período, saldo por pagar y lo que vence en las <b>próximas 12 semanas</b>, para planificar el flujo de caja.', { pos: 'abajo-der', espera: 2800 });
    await d.desplazar(620, 1400); await d.espera(2400);
    await d.sinRotulo();
  },

  async ventas() {
    await d.carta({ numero: '03 · Ventas', titulo: 'De la cotización a la factura', sub: 'Se cotiza, se envía al cliente y se factura con los precios cotizados.',
      puntos: ['Cotización con vigencia', 'Envío por correo al cliente', 'Bienes y servicios juntos', 'Contado, crédito o transferencia'] }, 4400);
    await d.ir('ventas/cotizaciones');
    await d.sinCarta(1000);
    await d.clic('button:has-text("Nueva cotización")', 1200);
    await d.rotulo('03 · Ventas', 'Nueva cotización',
      'Para un cliente o un prospecto (nombre y NIT). Vale <b>15 días</b>: se indica la fecha hasta la que se respetan los precios.', { pos: 'abajo-der', espera: false });
    await d.escribir('input[placeholder^="Buscar cliente"]', 'CLI002');
    await d.p.keyboard.press('Enter'); await d.espera(1200);
    await d.clic('button[aria-label="Elegir el cliente"]', 1200);
    await d.escribir('input[aria-label="Buscar producto por código o descripción"]', 'Dell');
    await d.p.keyboard.press('Enter'); await d.espera(1200);
    await d.clic('button[aria-label="Agregar a la cotización"]', 1200);
    await d.clic('button:has-text("Servicio")', 900);
    await d.escribir('input[aria-label="Descripción del servicio"]', 'Instalación y configuración del equipo', 300);
    await d.escribir(d.p.locator('input[aria-label="Precio con IVA"]').last(), '448', 600);
    await d.p.locator('input[aria-label="Precio con IVA"]').last().press('Tab'); await d.espera(600);
    await d.rotulo('03 · Ventas', 'Bienes y servicios',
      'La laptop con su precio de lista y el servicio de instalación; los precios incluyen IVA y el total se calcula al instante.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.resumen-totales', 3600); await d.sinResalte(); await d.sinRotulo();
    await d.clic('button:has-text("Grabar cotización")', 2200);
    await sinErrores('cotización');
    if (!(await d.p.$('#titulo-cotizacion'))) await d.clic('main table tbody tr >> nth=0 >> button[aria-label="Ver la cotización"]', 1400);
    await d.rotulo('03 · Ventas', 'Cotización grabada',
      'Con su número, la vigencia y la existencia de hoy de cada producto. Se imprime o se envía al cliente.', { pos: 'abajo-der', espera: 3400 });
    await d.clic('button:has-text("Enviar por correo")', 1400);
    await d.rotulo('03 · Ventas', 'Envío por correo',
      'Va al <b>correo registrado del cliente</b>, con la cotización en PDF, desde la cuenta de correo de la compañía (Gmail, Outlook o Microsoft 365): no hace falta servidor de correo propio.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.enviar-correo', 5600); await d.sinResalte();
    await d.clic('.enviar-correo button:has-text("Cerrar")', 800);
    await d.sinRotulo();
    await d.clic('button:has-text("Convertir en factura")', 2400);
    await d.rotulo('03 · Ventas', 'Convertir en factura',
      'La factura se abre con el cliente, las líneas y los <b>precios cotizados</b>. Al grabarla, la cotización queda facturada.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.doc-nota:has-text("Desde la cotización")', 4400); await d.sinResalte();
    await d.desplazarA('table.doc-tabla', 'center', 1100);
    await d.resaltar('table.doc-tabla', 3400); await d.sinResalte(); await d.sinRotulo();
    await d.desplazarA('#facturas-condicionpagofactura', 'center', 1100);
    await d.elegir('#facturas-condicionpagofactura', 'credito', 1200);
    await d.rotulo('03 · Ventas', 'Crédito con límite',
      'Al crédito se muestran límite, saldo y crédito disponible del cliente, y se genera el <b>plan de pagos</b>. Si el monto lo excede, no se puede grabar.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.credito-resumen', 4600); await d.sinResalte();
    await d.elegir('#facturas-condicionpagofactura', 'contado', 1200);
    await d.desplazarA('.tabla-formas-pago', 'center', 1000);
    await d.elegir('.tabla-formas-pago select[aria-label="Forma de pago"]', { label: 'Transferencia' }, 1200);
    await d.rotulo('03 · Ventas', 'Pago por transferencia',
      'El monto se propone con el <b>total de la factura</b>; si el cliente paga una parte con tarjeta, efectivo o cheque, se ajusta.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.tabla-formas-pago input[aria-label="Monto"]', 3600); await d.sinResalte();
    const total = await d.p.inputValue('.tabla-formas-pago input[aria-label="Monto"]');
    const operacion = '7' + String(Date.now()).slice(-7);
    const comprobante = await generarImagen('transferencia-cliente.png', 'Comprobante de transferencia',
      [['Fecha', hoy()], ['Número de operación', operacion], ['Cuenta destino', 'Monetaria 301-0001122-3'], ['Concepto', 'Pago de factura']], Number(total));
    await d.elegir('.tabla-formas-pago select[aria-label="Entidad financiera"]', { index: 1 }, 600);
    await d.escribir('.tabla-formas-pago input[aria-label="No. de operación de la transferencia"]', operacion, 400);
    await d.apuntar('.tabla-formas-pago label:has(#fac-comprobante)'); await d.espera(600);
    await d.p.setInputFiles('#fac-comprobante', comprobante); await d.espera(1400);
    await d.rotulo('03 · Ventas', 'No. de operación y comprobante',
      'El campo de número de cheque o referencia pide el <b>número de operación</b>, y se adjunta el comprobante que mandó el cliente (PDF o imagen).', { pos: 'arriba-der', espera: false });
    await d.resaltar('.tabla-formas-pago', 4600); await d.sinResalte(); await d.sinRotulo();
    await d.clic('.tabla-formas-pago button[aria-label="Agregar forma de pago"]', 1000);
    await d.desplazarA('.doc-card-footer', 'center', 900);
    await d.clic('button:has-text("Grabar factura")', 3400);
    await sinErrores('factura');
    await d.desplazarA('.fel-resumen', 'center', 1000);
    await d.rotulo('03 · Ventas', 'Factura certificada al grabar',
      'Al grabar se envía al certificador y se recibe la <b>autorización (UUID), serie y número</b> de SAT. Si el certificador no responde, queda pendiente y se reintenta sola.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.fel-resumen', 5400); await d.sinResalte();
    const recibidas = d.p.locator('text=Transferencias recibidas').first();
    if (await recibidas.count()) {
      await d.desplazarA(recibidas, 'center', 1000);
      await d.rotulo('03 · Ventas', 'Transferencias recibidas',
        'El detalle de la factura muestra cada operación con su comprobante, que se abre con un clic.', { pos: 'arriba-der', espera: 3400 });
    }
    await d.clic('button:has-text("Enviar por correo")', 1400);
    await d.rotulo('03 · Ventas', 'Factura al correo del cliente',
      'El PDF de la factura y el <b>XML certificado</b> de la FEL, al correo registrado del cliente.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.enviar-correo', 4400); await d.sinResalte();
    await d.clic('.enviar-correo button:has-text("Cerrar")', 800);
    await d.sinRotulo();
    await d.ir('facturas');
    await d.rotulo('03 · Ventas', 'Historial con fecha y hora',
      'Cada factura muestra la fecha del documento y la <b>hora en que se grabó</b>. Búsqueda, filtro de fechas y anulación con motivo.', { pos: 'abajo-der', espera: false });
    await d.resaltar('main table tbody tr:first-child .col-fecha-hora', 4200); await d.sinResalte(); await d.sinRotulo();
  },

  async fel() {
    await d.carta({ numero: '04 · Factura electrónica', titulo: 'FEL parametrizada', sub: 'Cumplimiento con SAT sin depender de un proveedor fijo.',
      puntos: ['INFILE o simulador de pruebas', 'XML armado desde parámetros', 'Reintento automático', 'Anulación ante SAT con motivo'] }, 4200);
    await d.ir('fel/documentos');
    await d.sinCarta(1000);
    await d.rotulo('04 · Factura electrónica', 'Documentos electrónicos',
      'Estado FEL de cada factura y nota, con la fecha y la <b>hora en que se facturó</b>: no enviado, pendiente, rechazado, certificado o anulado ante SAT.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.fel-conteos', 4200); await d.sinResalte();
    await d.rotulo('04 · Factura electrónica', 'Certificación en lote',
      'Los documentos anteriores se envían de una vez, del más antiguo al más reciente; cada nota espera a que su factura de origen esté certificada.', { pos: 'abajo-der', espera: false });
    await d.clic('button:has-text("Enviar pendientes")', 800);
    await d.espera(5200);
    await d.desplazar(0, 600);
    await d.resaltar('.fel-conteos', 2600); await d.sinResalte();
    const fila = d.p.locator('tbody tr:has(.fel-uuid)').first();
    await d.clic(fila.locator('button[aria-label="Ver detalle y bitácora"]'), 1400);
    const encId = await d.p.locator('.fel-detalle a[href*="fel/xml/"]').first().getAttribute('href').then(h => h.split('/')[2]);
    const xml = await d.p.evaluate(async id => (await (await fetch('fel/xml/' + id + '/enviado')).text()), encId);
    await d.rotulo('04 · Factura electrónica', 'XML y bitácora',
      'Se guardan el XML enviado y el certificado, descargables, y cada intento queda en la bitácora con su resultado.', { pos: 'abajo-izq', espera: 2600 });
    const recorte = xml.replace(/></g, '>\n<').split('\n').slice(0, 34).join('\n');
    await d.p.evaluate(([t, x]) => window.__demo.panel(t, x), ['DTE enviado al certificador (GTDocumento 0.1)', recorte]);
    await d.marca({ tipo: 'panel', titulo: 'XML del DTE' });
    await d.espera(6200);
    await d.p.evaluate(() => window.__demo.sinPanel()); await d.espera(500);
    await d.ir('fel/configuracion');
    await d.rotulo('04 · Factura electrónica', 'Todo parametrizado',
      'Certificador, ambiente, emisor, establecimientos, frases, tipos de DTE y unidades. Las llaves del certificador se guardan <b>fuera de la base de datos</b>.', { pos: 'abajo-der', espera: 3400 });
    for (const t of ['Frases', 'Establecimientos', 'Tipos de documento']) await d.clic(`.pestana-boton:has-text("${t}")`, 1700);
    await d.sinRotulo();
  },

  async cxc() {
    await d.carta({ numero: '05 · Cuentas por cobrar', titulo: 'Cartera bajo control', sub: 'Del saldo del cliente al recibo, cobre en caja o en el banco.',
      puntos: ['Estado de cuenta y cartera', 'Varias cuotas en un recibo', 'Transferencia con comprobante', 'Pago con boleta verificado'] }, 4400);
    await d.ir('cxc/estado-cuenta');
    await d.sinCarta(1000);
    await d.rotulo('05 · Cuentas por cobrar', 'Clientes con saldo',
      'La cartera completa al abrir la pantalla; un clic muestra el estado de cuenta del cliente: facturas, cuotas, cobros y notas.', { pos: 'abajo-der', espera: 2800 });
    await d.clic('.cartera-lista tbody tr >> nth=0 >> button.boton-enlace', 2600);
    const [codCobro, codBoleta] = clientesConCuotas();
    await d.ir('cxc/cobros');
    await d.rotulo('05 · Cuentas por cobrar', 'Cobro de cuotas',
      'Se busca al cliente y aparecen sus cuotas pendientes, de todas sus facturas.', { pos: 'abajo-der', espera: false });
    await elegirCliente(codCobro);
    let saldos = await d.p.$$eval('table.tabla-cuotas-cobro tbody tr td:nth-child(6)', t => t.map(x => parseFloat(x.textContent.replace(/[^0-9.]/g, ''))));
    const monto = (saldos[0] + saldos[1] + Math.min(150, Math.floor((saldos[2] || 0) / 2))).toFixed(2);
    await d.escribir('#cob-recibido', monto, 700);
    await d.clic('button:has-text("Aplicar a las más antiguas")', 1200);
    await d.rotulo('05 · Cuentas por cobrar', 'Aplicación automática',
      'El monto recibido se reparte entre las cuotas <b>más antiguas</b>; se puede ajustar a mano cuota por cuota.', { pos: 'arriba-der', espera: false });
    await d.resaltar('table.tabla-cuotas-cobro', 4200); await d.sinResalte();
    await d.desplazarA('#titulo-formas', 'start', 1000);
    await d.elegir('.tabla-formas-pago select[aria-label="Forma de pago"]', { label: 'Transferencia' }, 1200);
    await d.rotulo('05 · Cuentas por cobrar', 'Transferencia del cliente',
      'Se propone <b>lo pendiente de cobrar</b>; se indica el banco, el número de operación y se adjunta el comprobante.', { pos: 'arriba-der', espera: false });
    const operacion = '8' + String(Date.now()).slice(-7);
    const comprobante = await generarImagen('transferencia-cobro.png', 'Comprobante de transferencia',
      [['Fecha', hoy()], ['Número de operación', operacion], ['Cuenta destino', 'Monetaria 301-0001122-3'], ['Concepto', 'Abono a cuotas']], Number(monto));
    await d.elegir('.tabla-formas-pago select[aria-label="Entidad financiera"]', { index: 1 }, 500);
    await d.escribir('.tabla-formas-pago input[aria-label="No. de operación de la transferencia"]', operacion, 300);
    await d.p.setInputFiles('#cob-comprobante', comprobante); await d.espera(1200);
    await d.resaltar('.tabla-formas-pago', 3800); await d.sinResalte();
    await d.clic('.tabla-formas-pago button[aria-label="Agregar forma de pago"]', 900);
    await d.clic('button:has-text("Registrar cobro Q")', 2200);
    await sinErrores('cobro');
    await d.desplazar(0, 900);
    await d.rotulo('05 · Cuentas por cobrar', 'Un recibo, varias cuotas',
      'Un solo recibo con su póliza (Caja / Clientes). Se imprime o se <b>envía por correo</b> al cliente; mientras la caja siga abierta puede anularse, con motivo.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.tarjeta-exito', 4600); await d.sinResalte(); await d.sinRotulo();
    // Pago con boleta: el cliente pagó en el banco y mandó la boleta.
    await d.clic('.tarjeta-exito button:has-text("Otro cobro")', 1200);
    await d.rotulo('05 · Cuentas por cobrar', 'Pagó en el banco',
      'Otro cliente depositó a la cuenta de la empresa y mandó la boleta: se registra igual, eligiendo las cuotas que paga.', { pos: 'abajo-der', espera: false });
    await elegirCliente(codBoleta);
    saldos = await d.p.$$eval('table.tabla-cuotas-cobro tbody tr td:nth-child(6)', t => t.map(x => parseFloat(x.textContent.replace(/[^0-9.]/g, ''))));
    const montoBoleta = saldos[0].toFixed(2);
    await d.escribir('#cob-recibido', montoBoleta, 500);
    await d.clic('button:has-text("Aplicar a las más antiguas")', 1000);
    await d.desplazarA('#titulo-formas', 'start', 1000);
    await d.clic('.forma-pago-opciones label:has-text("Con boleta")', 1200);
    const boleta = '5' + String(Date.now()).slice(-6);
    const imagenBoleta = await generarImagen('boleta-deposito.png', 'Boleta de depósito',
      [['Fecha', hoy()], ['Número de boleta', boleta], ['Cuenta', 'Monetaria 301-0001122-3'], ['Depositante', 'Cliente de la demo']], Number(montoBoleta));
    await d.elegir('#bol-cuenta', { index: 1 }, 500);
    await d.escribir('#bol-referencia', boleta, 300);
    await d.escribir('#bol-observaciones', 'La mandó por WhatsApp', 300);
    await d.p.setInputFiles('#bol-archivo', imagenBoleta); await d.espera(1200);
    await d.rotulo('05 · Cuentas por cobrar', 'Boleta por verificar',
      'Cuenta de la empresa, fecha del depósito, número de boleta y la imagen que mandó el cliente. <b>El saldo no cambia</b> hasta que contabilidad la verifica.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.formulario-boleta', 4600); await d.sinResalte(); await d.sinRotulo();
    await d.clic('button:has-text("Registrar boleta Q")', 2200);
    await sinErrores('boleta');
    await d.desplazarA('#titulo-boletas', 'start', 1200);
    const avisar = d.p.locator('label.casilla-linea input');
    if (await avisar.isChecked()) await d.clic(avisar, 600);
    await d.rotulo('05 · Cuentas por cobrar', 'Verificar contra el banco',
      'Cuando el depósito aparece en el estado de cuenta del banco, quien tiene el permiso la <b>verifica</b>: se graba el recibo y la póliza Bancos / Clientes con la fecha del depósito, y entra a la conciliación bancaria. Si no aparece, se rechaza con motivo. Opcional: avisar al cliente por correo.', { pos: 'arriba-der', espera: false });
    const filaBoleta = d.p.locator('.tarjeta:has(#titulo-boletas) tbody tr', { hasText: boleta }).first();
    await d.resaltar(filaBoleta, 5200); await d.sinResalte();
    await d.clic(filaBoleta.locator('button[aria-label="Verificar: el dinero ya está en el banco"]'), 1200);
    await d.clic('.confirmacion-en-linea button:has-text("Sí")', 2400);
    await sinErrores('verificar boleta');
    await d.elegir('select[aria-label="Estado de las boletas"]', 'V', 1400);
    await d.resaltar(d.p.locator('.tarjeta:has(#titulo-boletas) tbody tr', { hasText: boleta }).first(), 3400); await d.sinResalte(); await d.sinRotulo();
    await d.ir('cxc/antiguedad');
    await d.rotulo('05 · Cuentas por cobrar', 'Antigüedad de saldos',
      'Saldos por rangos de días, por cliente o por factura, con <b>Excel</b> y vista para imprimir. Al elegir un cliente se consulta solo.', { pos: 'abajo-der', espera: 3800 });
    await cerrarSesion();
    await d.rotulo('05 · Cuentas por cobrar', 'Entra un vendedor',
      'Julio Pérez es vendedor (usuario → empleado → vendedor en RRHH).', { pos: 'abajo-izq', espera: false });
    await d.escribir('#usuario', 'jperez');
    await d.escribir('#password', 'Demo#2024', 600);
    await d.clic('button[type=submit]', 1400);
    if (await d.p.$('#sucursal')) { await d.elegir('#sucursal', { index: 1 }, 800); await d.clic('button[type=submit]', 1400); }
    await d.ir('ventas/antiguedad');
    await d.rotulo('05 · Cuentas por cobrar', 'Cada vendedor, su cartera',
      'Ve los clientes a los que <b>él les ha vendido</b>, con el saldo completo de cada uno. Administración y contabilidad ven toda la cartera.', { pos: 'abajo-der', espera: false });
    await d.resaltar('main table', 4400); await d.sinResalte(); await d.sinRotulo();
  },

  async compras() {
    await d.carta({ numero: '06 · Compras', titulo: 'Compras con costo real', sub: 'Cada compra actualiza existencias, costo promedio y el último costo del proveedor.',
      puntos: ['Bodegas de la sucursal', 'Productos por proveedor', 'Costo promedio ponderado', 'Plan de pagos al proveedor'] }, 1000);
    await cerrarSesion(); await iniciarSesion('admin');
    await d.ir('productos');
    await d.espera(2600);
    await d.sinCarta(1000);
    await d.escribir('input[placeholder="Buscar por descripción"]', 'Dell', 300);
    await d.clic('main button:has-text("Buscar")', 1200);
    await d.rotulo('06 · Compras', 'Costo antes de la compra',
      'Cada producto lleva su costo promedio, precios por bodega, características, existencias y proveedores.', { pos: 'abajo-der', espera: false });
    await d.resaltar('main table tbody tr:first-child td.col-monto', 4000); await d.sinResalte();
    const [[costoAntes, cantAntes]] = sql("SELECT CAST(pro_costo_unitario AS DECIMAL(14,2)), CAST(pro_total_cantidad AS INT) FROM dbo.inv_producto WHERE pro_codigo = 'LAP-DELL-3520'");
    await d.ir('compras');
    await d.clic('button:has-text("Nueva compra")', 1200);
    await d.escribir('.campo:has(label:text-is("Serie")) input', 'B', 300);
    await d.escribir('.campo:has(label:text-is("Número")) input', '48213', 300);
    await d.rotulo('06 · Compras', 'Bodegas de la sucursal',
      'Solo aparecen las bodegas de la <b>sucursal con la que se entró</b>, y se propone la primera.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.campo:has(label:has-text("Bodega"))', 3200); await d.sinResalte();
    await d.escribir('input[placeholder^="Buscar proveedor"]', 'PRV02');
    await d.p.keyboard.press('Enter'); await d.espera(1100);
    await d.clic('.doc-buscador-resultados .doc-resultado-fila', 1400);
    await d.rotulo('06 · Compras', 'Los productos del proveedor',
      'Al elegir el proveedor, la búsqueda muestra <b>sus productos</b>, con su código en el catálogo del proveedor y el costo de su última compra.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.doc-seccion:has(.doc-seccion-titulo:has-text("Detalle de productos")) .doc-buscador', 4800); await d.sinResalte();
    await d.escribir('input[aria-label="Buscar producto por código o descripción"]', 'Dell');
    await d.p.keyboard.press('Enter'); await d.espera(1100);
    await d.clic(nuevaFila, 1100);
    const fila = d.p.locator('table.doc-tabla tbody tr').first();
    await d.escribir(fila.locator('input[type=number]').nth(0), '10', 300);
    await d.escribir(fila.locator('input[type=number]').nth(1), '4256', 300);
    await d.escribir(fila.locator('input[type=number]').nth(2), '2240', 300);
    await fila.locator('input[type=number]').nth(2).press('Tab'); await d.espera(700);
    await d.rotulo('06 · Compras', 'Compra con descuento',
      '10 laptops a Q4,256 con IVA y Q2,240 de descuento. El costo que entra al inventario es <b>neto de descuento y sin IVA</b>: Q3,600 por unidad.', { pos: 'arriba-der', espera: false });
    await d.resaltar('table.doc-tabla', 5200); await d.sinResalte();
    await d.desplazarA('.doc-card-footer', 'end', 1000);
    await d.elegir('select:has(option[value=credito])', 'credito', 900);
    await d.escribir('.campo:has(label:has-text("Número de cuotas")) input', '3', 400);
    const primerPago = new Date(Date.now() + 20 * 86400000).toISOString().slice(0, 10);
    await d.clic('.campo:has(label:has-text("primer pago")) input', 300);
    await d.p.locator('.campo:has(label:has-text("primer pago")) input').fill(primerPago); await d.espera(400);
    await d.p.keyboard.press('Tab'); await d.espera(800);
    await d.rotulo('06 · Compras', 'Crédito del proveedor',
      'Las cuotas al proveedor alimentan cuentas por pagar y los compromisos de pago del tablero.', { pos: 'arriba-der', espera: 3200 });
    await d.desplazarA('.doc-card-footer', 'center', 900);
    await d.clic('button:has-text("Grabar compra")', 2600);
    await sinErrores('compra');
    await d.rotulo('06 · Compras', 'Grabada: inventario, costo y póliza',
      'En una sola transacción sube la existencia, se recalcula el costo promedio y se genera la póliza de compra.', { pos: 'arriba-der', espera: 3600 });
    await d.ir('productos');
    await d.escribir('input[placeholder="Buscar por descripción"]', 'Dell', 300);
    await d.clic('main button:has-text("Buscar")', 1200);
    const [[costoDespues]] = sql("SELECT CAST(pro_costo_unitario AS DECIMAL(14,2)) FROM dbo.inv_producto WHERE pro_codigo = 'LAP-DELL-3520'");
    // La presentación usa los mismos números del video.
    fs.writeFileSync(path.join(SALIDA, 'datos_demo.json'), JSON.stringify({ costoAntes: +costoAntes, cantAntes: +cantAntes, costoDespues: +costoDespues }));
    await d.rotulo('06 · Compras', 'Costo promedio actualizado',
      `(Q${q2(costoAntes)} × ${cantAntes} + Q3,600.00 × 10) ÷ ${+cantAntes + 10} = <b>Q${q2(costoDespues)}</b>. La siguiente venta grabará ese costo en su línea y en la póliza de costo de ventas.`, { pos: 'abajo-der', espera: false });
    await d.resaltar('main table tbody tr:first-child td.col-monto', 5800); await d.sinResalte(); await d.sinRotulo();
  },

  async ordencompra() {
    const oc = prepararOrdenCompra();
    await d.carta({ numero: '07 · Órdenes de compra', titulo: 'Compra desde la orden de compra', sub: 'La orden aprobada por bodega y por el contador general se convierte en compra.',
      puntos: ['Dos firmas: bodega y contador general', 'Lo que llegó con la factura', 'Lo que falta queda pendiente', 'Inventario, cuenta por pagar y póliza'] }, 4400);
    await d.ir('compras/ordenes');
    await d.sinCarta(1000);
    await d.rotulo('07 · Órdenes de compra', `Orden ${oc.numero} aprobada`,
      'Lleva el <b>visto bueno del jefe de bodega</b> y la <b>aprobación del contador general</b>, dos usuarios distintos.', { pos: 'abajo-der', espera: false });
    await d.resaltar(d.p.locator('main table tbody tr', { hasText: oc.numero }), 4400); await d.sinResalte();
    await d.ir('compras');
    await d.clic('button:has-text("Desde orden de compra")', 1200);
    await d.rotulo('07 · Órdenes de compra', 'Desde orden de compra',
      'Se elige entre las órdenes aprobadas pendientes de recibir.', { pos: 'arriba-der', espera: false });
    await d.elegir('#compras-desde-orden', String(oc.ocp), 1600);
    await d.escribir('.oc-recepcion input[id^=rec-serie]', 'A', 200);
    await d.escribir('.oc-recepcion input[id^=rec-numero]', '7745', 400);
    const cantidad = d.p.locator('.oc-recepcion input[aria-label^="Cantidad recibida"]').first();
    await d.escribir(cantidad, '4', 300); await cantidad.press('Tab'); await d.espera(600);
    await d.rotulo('07 · Órdenes de compra', 'Llegó una parte',
      'Se indica lo que llegó con la factura del proveedor: <b>4 de 6</b> laptops Dell. Lo que falta queda pendiente para otra recepción.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.oc-recepcion table', 4600); await d.sinResalte();
    await d.clic('.oc-recepcion button:has-text("Grabar compra")', 2600);
    await sinErrores('compra desde OC');
    await d.rotulo('07 · Órdenes de compra', 'Compra grabada',
      'Ingreso a bodega con costo promedio, cuenta por pagar y póliza en una sola transacción; la orden queda <b>parcialmente recibida</b>.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.mensaje-ok', 4400); await d.sinResalte(); await d.sinRotulo();
  },

  async inventario() {
    await d.carta({ numero: '08 · Inventario', titulo: 'Existencias, kardex y toma física', sub: 'Lo que hay en cada bodega, cómo llegó ahí y el conteo contra el sistema.',
      puntos: ['Búsqueda por código o descripción', 'Kardex con costo promedio', 'Conteo en pantalla o con Excel', 'Ajustes con su póliza'] }, 4400);
    await d.ir('existencias');
    await d.sinCarta(1000);
    await d.escribir('input[placeholder="Buscar por código o descripción"]', 'laptop', 900);
    await d.rotulo('08 · Inventario', 'Existencias por bodega',
      'Se filtran por <b>código o descripción</b> mientras se escribe. Cada fila tiene su kardex.', { pos: 'abajo-der', espera: false });
    await d.resaltar('main table', 3800); await d.sinResalte();
    const fila = d.p.locator('main table tbody tr', { hasText: 'LAP-DELL-3520' }).first();
    await d.clic(fila.locator('button:has-text("Kardex")'), 1800);
    await d.elegir('select[aria-label=Bodega]', '0', 1600);
    await d.rotulo('08 · Inventario', 'Kardex',
      'Compra, factura, ajuste o traslado: cantidad, <b>costo unitario y costo total</b> de cada movimiento, con el saldo y el costo promedio después de cada línea. Las compras de hace un momento aparecen al final.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.kpi-fila', 3400); await d.sinResalte();
    await d.desplazarA('.kardex-tabla', 'start', 1200);
    await d.desplazar(9999, 2600); await d.espera(2200);
    await d.desplazar(0, 1200);
    await d.rotulo('08 · Inventario', 'Comprobado',
      'El cálculo llega a la misma existencia, valor y costo promedio guardados en el producto. Se exporta a <b>Excel</b>.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.doc-nota', 4200); await d.sinResalte(); await d.sinRotulo();
    await d.ir('inventario/fisico');
    await d.rotulo('08 · Inventario', 'Toma de inventario físico',
      'Cada toma es de una bodega. La lista muestra cuánto se contó y el valor de los sobrantes y faltantes ajustados.', { pos: 'abajo-der', espera: 3000 });
    await d.clic('button:has-text("Nueva toma")', 1000);
    await d.escribir('#toma-obs', 'Conteo de cierre de mes', 300);
    const soloExistencia = d.p.locator('.panel-formulario label.casilla input');
    if (!(await soloExistencia.isChecked())) await d.clic(soloExistencia, 600); else await d.apuntar(soloExistencia);
    await d.clic('.panel-formulario button:has-text("Abrir toma")', 2200);
    await d.rotulo('08 · Inventario', 'Existencia del sistema junto al conteo',
      'La existencia no se puede modificar; se anota lo contado. También se puede bajar la <b>hoja de conteo en Excel</b>, llenarla en la bodega y subirla.', { pos: 'arriba-der', espera: false });
    const filas = d.p.locator('table.tabla-datos tbody tr');
    const existencia = async i => Number((await filas.nth(i).locator('td').nth(3).textContent()).replace(/[^0-9.]/g, ''));
    const cambios = [0, 2, -1];
    for (let i = 0; i < cambios.length; i++) {
      const entrada = filas.nth(i).locator('input.entrada-numero');
      await d.escribir(entrada, String((await existencia(i)) + cambios[i]), 250);
      await entrada.press('Tab'); await d.espera(500);
    }
    await d.resaltar('table.tabla-datos tbody', 3200); await d.sinResalte();
    await d.clic('button:has-text("Guardar conteo")', 1400);
    await d.clic('label.casilla:has-text("Solo con diferencia") input', 1000);
    await d.rotulo('08 · Inventario', 'Diferencias valoradas',
      'Un sobrante y un faltante, valorados al <b>costo promedio</b> de cada producto.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.resumen-totales', 3600); await d.sinResalte();
    await d.clic('button:has-text("Aplicar ajustes")', 700);
    await d.clic('.confirmacion-en-linea button:has-text("Sí")', 2400);
    await d.desplazar(0, 800);
    await d.rotulo('08 · Inventario', 'Ajuste con póliza',
      'El sobrante va contra ingresos y el faltante contra gastos, cada uno con su póliza. Anular la toma revierte existencias y pólizas.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.mensaje-ok', 4800); await d.sinResalte(); await d.sinRotulo();
  },

  async proveedores() {
    await d.carta({ numero: '09 · Cuentas por pagar', titulo: 'Pagos a proveedores', sub: 'Con cheque o por transferencia, por factura o por todo el saldo.',
      puntos: ['Un cheque para varias facturas', 'Transferencia con autorización', 'Comprobante del banco adjunto', 'Antigüedad de proveedores'] }, 4400);
    const [[prv]] = sql("SELECT prv_id FROM dbo.inv_proveedor WHERE prv_codigo = 'PRV04'");
    await d.ir(`cxp/estado-cuenta?id=${prv}`);
    await d.sinCarta(1000);
    await d.rotulo('09 · Cuentas por pagar', 'Estado de cuenta del proveedor',
      'Compras al crédito con cuotas vencidas. Cada compra se puede pagar desde aquí, o todo el saldo con un solo cheque.', { pos: 'abajo-der', espera: false });
    await d.resaltar('table.tabla-datos', 3400); await d.sinResalte();
    await d.clic('a:has-text("Pagar saldo con cheque")', 2000);
    await d.escribir('#pag-monto', '5000', 500);
    await d.clic('button:has-text("Aplicar a las más antiguas")', 1400);
    await d.rotulo('09 · Cuentas por pagar', 'Un cheque para varias facturas',
      'El monto cancela la cuota más vencida y abona el resto a la siguiente. El concepto se arma con las facturas que paga.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.tabla-cuotas-cobro', 4000); await d.sinResalte(); await d.sinRotulo();
    await d.desplazarA('#titulo-forma-pago', 'start', 1200);
    await d.clic('.forma-pago-opciones label:has-text("Cheque")', 1000);
    await d.clic('button:has-text("Emitir cheque Q")', 2000);
    await sinErrores('cheque');
    await d.desplazar(0, 900);
    await d.rotulo('09 · Cuentas por pagar', 'Cheque emitido con su póliza',
      'La póliza lleva una línea por factura contra la cuenta de abonos del banco. Anularlo devuelve el saldo a cada cuota.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.tarjeta-exito', 3400); await d.sinResalte(); await d.sinRotulo();
    // Transferencia ya hecha en la banca electrónica.
    const prvT = proveedorTransferencia();
    await d.ir(`cxp/pagos?prv=${prvT.id}`);
    const saldos = await d.p.$$eval('table.tabla-cuotas-cobro tbody tr td:nth-child(7)', t => t.map(x => parseFloat(x.textContent.replace(/[^0-9.]/g, ''))));
    const monto = Math.round((saldos[0] + Math.min(1000, (saldos[1] || 0) / 2)) * 100) / 100;
    await d.escribir('#pag-monto', monto.toFixed(2), 500);
    await d.clic('button:has-text("Aplicar a las más antiguas")', 1200);
    await d.desplazarA('#titulo-forma-pago', 'start', 1100);
    await d.clic('.forma-pago-opciones label:has-text("Transferencia")', 1200);
    await d.rotulo('09 · Cuentas por pagar', 'O por transferencia',
      'Se registra la transferencia <b>ya hecha</b> en la banca electrónica. El banco y la cuenta del proveedor se proponen de su ficha.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.campo:has(#trf-cuenta-destino)', 3200); await d.sinResalte();
    const autorizacion = '20' + String(Date.now()).slice(-8);
    const cuentaDestino = await d.p.inputValue('#trf-cuenta-destino');
    const comprobante = await generarImagen('transferencia-proveedor.png', 'Comprobante de transferencia',
      [['Fecha y hora', hoy() + ' 09:42'], ['Número de autorización', autorizacion], ['Cuenta de origen', 'Monetaria 301-0001122-3'], ['Cuenta destino', cuentaDestino], ['Concepto', 'Pago de facturas']], monto);
    await d.escribir('#trf-autorizacion', autorizacion, 300);
    await d.escribir('#trf-referencia', 'Banca en línea', 400);
    await d.p.setInputFiles('#trf-comprobante', comprobante); await d.espera(1400);
    await d.rotulo('09 · Cuentas por pagar', 'Autorización y comprobante',
      'El número de autorización es obligatorio y <b>no se repite</b> en la misma cuenta. El comprobante del banco queda adjunto.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.formulario-transferencia', 4600); await d.sinResalte(); await d.sinRotulo();
    await d.clic('button:has-text("Registrar transferencia Q")', 2200);
    await sinErrores('transferencia');
    await d.desplazar(0, 900);
    await d.rotulo('09 · Cuentas por pagar', 'Registrada con su póliza',
      'Correlativo propio <b>TR-</b>; la póliza carga Proveedores y abona Bancos. Entra al estado de cuenta, al flujo de caja y a la conciliación bancaria.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.tarjeta-exito', 4600); await d.sinResalte(); await d.sinRotulo();
    await d.ir('cxp/antiguedad');
    await d.rotulo('09 · Cuentas por pagar', 'Antigüedad de proveedores',
      'Lo que se debe por rangos de vencimiento, por proveedor o por compra.', { pos: 'abajo-der', espera: 2600 });
    await d.clic('button:has-text("Por compra")', 1800);
    await d.sinRotulo();
  },

  async caja() {
    await d.carta({ numero: '10 · Caja', titulo: 'Caja y caja chica', sub: 'El dinero que entra y sale, cuadrado todos los días.',
      puntos: ['Apertura, corte y cierre', 'Cuadre por forma de pago', 'Depósitos a la cuenta bancaria', 'Caja chica con vales y liquidación'] }, 4400);
    await d.ir('caja');
    await d.sinCarta(1000);
    await d.rotulo('10 · Caja', 'Caja por sucursal',
      'Apertura con monto inicial; no se abre un día nuevo si el anterior quedó sin cerrar.', { pos: 'abajo-der', espera: 3000 });
    await d.clic('.pestana-boton:has-text("Corte")', 1200);
    await d.elegir('.campo:has(label:has-text("Caja abierta")) select', { index: 1 }, 1600);
    await d.rotulo('10 · Caja', 'Corte y cierre con cuadre',
      'El sistema calcula lo esperado por forma de pago (efectivo, cheque, tarjeta y transferencia); el cajero cuenta lo físico y la diferencia genera su póliza.', { pos: 'abajo-der', espera: 4400 });
    await d.desplazar(500, 1200); await d.espera(1200); await d.desplazar(0, 800);
    await d.clic('.pestana-boton:has-text("Depósitos")', 1200);
    await d.elegir('.campo:has(label:has-text("Apertura")) select', { index: 1 }, 1400);
    const cuentaBi = await d.p.locator('.campo:has(label:text-is("Cuenta bancaria")) select option', { hasText: '301-0001122-3' }).first().getAttribute('value');
    await d.elegir('.campo:has(label:text-is("Cuenta bancaria")) select', cuentaBi, 700);
    await d.escribir('.campo:has(label:text-is("Valor")) input', '3500', 300);
    await d.escribir('.campo:has(label:has-text("boleta")) input', 'BOL-20931', 400);
    await d.rotulo('10 · Caja', 'Depósito a una cuenta bancaria',
      'El efectivo se deposita en una <b>cuenta bancaria</b> de la empresa; la póliza carga la cuenta contable de depósitos de esa cuenta.', { pos: 'arriba-der', espera: 3200 });
    await d.clic('button:has-text("Registrar depósito")', 1800);
    await d.desplazarA('text=Depósitos registrados', 'center', 900);
    await d.espera(1400);
    await d.sinRotulo();
    await d.ir('bancos/caja-chica');
    await d.rotulo('10 · Caja', 'Caja chica',
      'Fondo fijo con sus gastos: factura, factura de pequeño contribuyente, vale o recibo. Se liquida con su póliza y se repone.', { pos: 'abajo-der', espera: 3000 });
    await d.clic('button:has-text("Registrar gasto")', 900);
    await d.elegir('#ccg-tipo', 'V', 900);
    await d.rotulo('10 · Caja', 'Vale sin proveedor',
      'En un vale o recibo el proveedor es opcional (<b>Entregado a</b>); solo las facturas lo exigen, con NIT y número.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.campo:has(#ccg-proveedor)', 3200); await d.sinResalte();
    await d.escribir('#ccg-concepto', 'Pasajes de mensajería al centro', 300);
    const viaticos = await d.p.locator('#ccg-cuenta option', { hasText: '5110015' }).first().getAttribute('value');
    await d.elegir('#ccg-cuenta', viaticos, 500);
    await d.escribir('#ccg-total', '35', 500);
    await d.clic('button:has-text("Guardar gasto")', 1600);
    await sinErrores('vale');
    await d.resaltar(d.p.locator('main table tbody tr', { hasText: 'Pasajes de mensajería' }).first(), 3200); await d.sinResalte(); await d.sinRotulo();
  },

  async bancos() {
    await d.carta({ numero: '11 · Bancos', titulo: 'Cuentas, cheques y conciliación', sub: 'Cada movimiento bancario con su cuenta contable, su póliza y su conciliación.',
      puntos: ['Cuenta de depósitos y de cheques', 'Cheques libres con centro de costo', 'Conciliación bancaria', 'Flujo de caja real y proyectado'] }, 4400);
    await d.ir('bancos/cuentas');
    await d.sinCarta(1000);
    await d.rotulo('11 · Bancos', 'Cuentas bancarias',
      'Cada cuenta de la empresa tiene dos cuentas contables: la de <b>cargos</b>, que reciben los depósitos, y la de <b>abonos</b>, que afectan los cheques y pagos. Con sus chequeras y correlativos.', { pos: 'abajo-der', espera: false });
    await d.resaltar('table.tabla-datos', 4600); await d.sinResalte(); await d.sinRotulo();
    await d.ir('bancos/cheques');
    await d.clic('button:has-text("Nuevo cheque")', 1000);
    await d.rotulo('11 · Bancos', 'Cheque libre',
      'Pago que no viene de una compra: beneficiario, motivo, cuenta de gasto y <b>centro de costo</b>. Genera su póliza al emitirlo.', { pos: 'arriba-der', espera: false });
    await d.escribir('#chq-beneficiario', 'Refrigeración Industrial, S.A.', 300);
    await d.escribir('#chq-valor', '1850', 300);
    await d.elegir('#chq-motivo', { label: 'Pago de servicios' }, 500);
    const cuentaGasto = await d.p.locator('#chq-cuenta option', { hasText: '5110012' }).first().getAttribute('value');
    await d.elegir('#chq-cuenta', cuentaGasto, 500);
    await d.elegir('#chq-depto', { label: 'Soporte técnico' }, 500);
    await d.escribir('#chq-obs', 'Mantenimiento de aire acondicionado', 600);
    await d.clic('button:has-text("Emitir cheque")', 2000);
    await sinErrores('cheque libre');
    await d.rotulo('11 · Bancos', 'Todos los cheques',
      'Cheques a proveedores, libres y de nómina en una sola lista. Se marcan como cobrados o se anulan con motivo, lo que anula su póliza.', { pos: 'abajo-der', espera: false });
    await d.desplazarA('#titulo-cheques', 'start', 1000);
    await d.espera(3200);
    await d.ir('bancos/conciliacion');
    await d.rotulo('11 · Bancos', 'Conciliación bancaria',
      'Se importa el estado de cuenta del banco y se concilia automáticamente por documento o por monto y fecha: depósitos, cheques, transferencias y boletas verificadas. Lo que falta se marca a mano o con póliza de ajuste.', { pos: 'abajo-der', espera: false });
    await d.espera(1200);
    const verConc = d.p.locator('main table tbody tr button').first();
    if (await verConc.count()) await d.clic(verConc, 1800);
    await d.espera(3400);
    await d.desplazar(600, 1400); await d.espera(1600); await d.desplazar(0, 900);
    await d.sinRotulo();
    await d.ir('bancos/flujo-caja');
    const consultar = d.p.locator('main button:has-text("Consultar")').first();
    if (await consultar.count()) await d.clic(consultar, 1600);
    await d.rotulo('11 · Bancos', 'Flujo de caja',
      'Lo que entró y salió de caja y bancos según las pólizas, y la proyección con lo que se cobrará y pagará en las próximas semanas.', { pos: 'abajo-der', espera: 4400 });
    await d.desplazar(600, 1400); await d.espera(1600);
    await d.sinRotulo();
  },

  async contabilidad() {
    await d.carta({ numero: '12 · Contabilidad', titulo: 'Contabilidad automática', sub: 'Cada operación genera su póliza de partida doble, siempre cuadrada.',
      puntos: ['Nomenclatura por nodos', 'Pólizas automáticas y manuales', 'Libros y estados financieros', 'Activos fijos y depreciación'] }, 4400);
    await d.ir('contabilidad/nomenclatura');
    await d.sinCarta(1000);
    await d.rotulo('12 · Contabilidad', 'Nomenclatura contable',
      'Catálogo jerárquico: activo, pasivo, capital, ingresos y gastos, mantenido por nodos.', { pos: 'abajo-der', espera: 2400 });
    await d.clic('button:has-text("Expandir todo")', 1400);
    await d.clic('button:has-text("111 CAJA")', 1600);
    await d.ir('general/cuentas-poliza');
    await d.rotulo('12 · Contabilidad', 'Pólizas automáticas',
      'Venta, compra, cobro, boleta, cheque, transferencia, depósito, cierre de caja, nómina y ajustes generan su póliza. Aquí se asigna la cuenta de cada concepto.', { pos: 'abajo-der', espera: 4400 });
    await d.desplazar(700, 1600); await d.espera(1000);
    await d.ir('contabilidad/polizas');
    await d.rotulo('12 · Contabilidad', 'Pólizas',
      'Todas las pólizas, automáticas y manuales, con su origen. Las manuales se capturan, se copian o se revierten.', { pos: 'abajo-der', espera: false });
    await d.resaltar('main table', 3800); await d.sinResalte();
    await d.ir('contabilidad/libros');
    const consLibros = d.p.locator('main button:has-text("Consultar")').first();
    if (await consLibros.count()) await d.clic(consLibros, 1600);
    await d.rotulo('12 · Contabilidad', 'Libros',
      'Libro diario, mayor y balanza de comprobación por período, para imprimir o exportar.', { pos: 'abajo-der', espera: 3600 });
    await d.ir('contabilidad/estados-financieros');
    const consEstados = d.p.locator('main button:has-text("Consultar")').first();
    if (await consEstados.count()) await d.clic(consEstados, 1800);
    await d.rotulo('12 · Contabilidad', 'Estados financieros',
      '<b>Balance General</b> y <b>Estado de Resultados</b> por nodos: se expanden hasta la cuenta de detalle.', { pos: 'abajo-der', espera: false });
    const expandir = d.p.locator('main button:has-text("Expandir todo")').first();
    if (await expandir.count()) await d.clic(expandir, 1600);
    await d.espera(2400);
    await d.desplazar(600, 1400); await d.espera(1200); await d.desplazar(0, 900);
    await d.sinRotulo();
    await d.ir('contabilidad/activos-fijos');
    await d.rotulo('12 · Contabilidad', 'Activos fijos',
      'Alta desde la compra o manual, <b>depreciación mensual</b> con los porcentajes del ISR y bajas o ventas, cada una con su póliza.', { pos: 'abajo-der', espera: 4400 });
    await d.ir('contabilidad/centros-costo');
    await d.clic('button:has-text("Consultar")', 1500);
    await d.rotulo('12 · Contabilidad', 'Gasto por centro de costo',
      'Cada departamento es un centro de costo: la nómina reparte los sueldos y los cheques libres llevan el suyo, como el que se acaba de emitir.', { pos: 'abajo-der', espera: false });
    await d.resaltar('main table', 4400); await d.sinResalte();
    await d.sinRotulo();
  },

  async rrhh() {
    await d.carta({ numero: '13 · Recursos humanos', titulo: 'Personas y nómina', sub: 'Empleados, nómina por período y pago sin efectivo, integrados con contabilidad.',
      puntos: ['Nómina semanal, quincenal o mensual', 'Transferencia o cheque', 'Libro de salarios', 'Planilla del IGSS'] }, 4400);
    await d.ir('rrhh/empleados');
    await d.sinCarta(1000);
    await d.rotulo('13 · Recursos humanos', 'Empleados',
      'Puesto, departamento, tipo de nómina y forma de pago de cada colaborador; puede vincularse a su usuario y a su código de vendedor.', { pos: 'abajo-der', espera: false });
    await d.resaltar('main table', 3800); await d.sinResalte();
    await d.ir('rrhh/nominas');
    await d.clic(d.p.locator('main table tbody tr', { hasText: 'Mensual' }).first().locator('button[aria-label="Ver detalle"]'), 1800);
    await d.rotulo('13 · Recursos humanos', 'Nómina aprobada',
      'Ingresos y descuentos por empleado; al aprobarla se genera la póliza con el gasto por centro de costo.', { pos: 'abajo-der', espera: 3400 });
    await d.desplazarA('#pago-nomina', 'start', 1200);
    await d.rotulo('13 · Recursos humanos', 'Pago de la nómina',
      'Lote de transferencias con el <b>archivo para el banco</b>, o cheques correlativos para quienes cobran con cheque. Cada pago lleva su póliza.', { pos: 'abajo-der', espera: 4400 });
    // Datos del patrono que la demo no trae (número patronal y autorización del libro).
    sql(`UPDATE dbo.gen_compania SET cia_igss_numero_patronal = ISNULL(cia_igss_numero_patronal, '1234567'),
      cia_libro_salarios_autorizacion = ISNULL(cia_libro_salarios_autorizacion, 'DGT-LS-2026-0451');
      UPDATE dbo.rrhhEmpleado SET NumeroAfiliacionIGSS = CONCAT('19', RIGHT(CONCAT('0000000', IdEmpleado), 7)) WHERE NumeroAfiliacionIGSS IS NULL`);
    await d.ir('rrhh/libro-salarios');
    await d.rotulo('13 · Recursos humanos', 'Libro de salarios',
      'Con el formato del Ministerio de Trabajo, por empleado y por año, listo para imprimir.', { pos: 'abajo-der', espera: 3600 });
    await d.ir('rrhh/planilla-igss');
    await d.elegir('select[aria-label="Mes"]', String(new Date().getMonth() + 1), 1600);
    await d.rotulo('13 · Recursos humanos', 'Planilla del IGSS',
      'Cuota laboral y patronal por centro de trabajo, y el <b>archivo para el sistema propio</b> del IGSS (formato 2.2.0).', { pos: 'abajo-der', espera: 3800 });
    await d.ir('rrhh/estructura');
    await d.clic('.pestana-boton:has-text("Organigrama")', 1800);
    await d.rotulo('13 · Recursos humanos', 'Organigrama',
      'Unidades anidadas sin límite de niveles; el organigrama se dibuja solo a partir de la estructura registrada.', { pos: 'abajo-der', espera: 3600 });
    await d.sinRotulo();
  },

  async arranque() {
    await d.carta({ numero: '14 · Puesta en marcha', titulo: 'Arranque desde Excel', sub: 'Los datos iniciales de la empresa se cargan con plantillas de Excel, validadas antes de grabar.',
      puntos: ['Inventario inicial por bodega', 'Saldos iniciales y partida de apertura', 'Carga de empleados', 'Errores señalados por fila'] }, 4200);
    await d.ir('inventario/carga-inicial');
    await d.sinCarta(1000);
    await d.rotulo('14 · Puesta en marcha', 'Tres pasos',
      'Se baja la plantilla (con instrucciones y listas desplegables), se llena y se sube. El archivo se valida completo: <b>si una fila tiene error no se graba nada</b>.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.pasos-carga', 5000); await d.sinResalte();
    await d.ir('contabilidad/saldos-iniciales');
    await d.rotulo('14 · Puesta en marcha', 'Saldos iniciales',
      'La nomenclatura se exporta a Excel, el contador pone el Debe o el Haber de cada cuenta y se genera la <b>partida de apertura</b>, que debe cuadrar.', { pos: 'abajo-der', espera: 4400 });
    await d.ir('rrhh/carga-empleados');
    await d.rotulo('14 · Puesta en marcha', 'Carga de empleados',
      'Alta o actualización por código, con plaza, salario, tipo de nómina y datos de pago.', { pos: 'abajo-der', espera: 3200 });
    await d.sinRotulo();
  },

  async admin() {
    await d.carta({ numero: '15 · Administración', titulo: 'Seguridad y configuración', sub: 'Cada quien ve y hace solo lo que le corresponde, con la imagen de su empresa.',
      puntos: ['Roles y permisos', 'Logotipo de la empresa', 'Correo saliente de la compañía', 'Auditoría de cada registro'] }, 4400);
    await d.ir('roles');
    await d.sinCarta(1000);
    await d.rotulo('15 · Administración', 'Roles',
      'Administrador, contador, vendedor, cajero, jefe de bodega… cada rol agrupa permisos.', { pos: 'abajo-der', espera: 2800 });
    await d.ir('permisos');
    await d.escribir('.permisos-maestro input[type=search]', 'BOLETA', 900);
    await d.clic(d.p.locator('.permisos-maestro table').first().locator('tbody tr').first(), 1400);
    const detalle = d.p.locator('.permisos-maestro > .tarjeta').nth(1);
    const tablas = detalle.locator('table');
    await d.desplazarA(tablas.nth(0), 'center', 1000);
    await d.rotulo('15 · Administración', 'Permisos',
      'Cada permiso con <b>dónde se usa</b> (opciones del menú y acciones), los roles que lo tienen —asignar o quitar desde aquí— y los usuarios que lo reciben.', { pos: 'abajo-izq', espera: false });
    await d.resaltar(tablas.nth(0), 3400);
    await d.resaltar(tablas.nth(1), 3400); await d.sinResalte(); await d.sinRotulo();
    await d.ir('general/companias');
    await d.clic(d.p.locator('main table tbody tr').first().locator('button[aria-label="Ver detalle"]'), 1200);
    await d.desplazarA('h3:has-text("Logotipo")', 'center', 1000);
    await d.rotulo('15 · Administración', 'Logotipo de la empresa',
      'El ERP lleva el logotipo de la empresa que lo usa: aparece en el menú, el inicio de sesión, los documentos impresos, los PDF por correo y los libros de Excel.', { pos: 'abajo-der', espera: false });
    await d.apuntar('label:has-text("logotipo"):has(input[type=file])'); await d.espera(900);
    await d.p.setInputFiles('label:has-text("logotipo"):has(input[type=file]) input[type=file]', path.join(__dirname, 'logo-empresa-demo.png'));
    await d.espera(2200);
    await d.resaltar('.logo-compania-vista', 2600); await d.sinResalte();
    await d.desplazarA('#cia-smtp-proveedor', 'center', 1200);
    await d.rotulo('15 · Administración', 'Correo saliente',
      'La cuenta con la que se envían facturas, recibos, cotizaciones y estados de cuenta: <b>Gmail</b> por defecto, Outlook.com, Microsoft 365, Yahoo u otro servidor. La contraseña queda cifrada.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.campo:has(#cia-smtp-proveedor)', 2600);
    await d.resaltar('.campo:has(#cia-smtp-remitente)', 2600); await d.sinResalte();
    await d.ir('general/companias');
    await d.resaltar('.sidebar-marca', 2400); await d.sinResalte();
    await d.ir('general/sucursales');
    await d.rotulo('15 · Administración', 'Sucursales y bodegas',
      'Multi-sucursal y multi-bodega. Cada registro guarda quién y cuándo lo creó y lo modificó.', { pos: 'abajo-der', espera: 3400 });
    await d.sinRotulo();
  },

  async continuidad() {
    await d.carta({ numero: '16 · Sin perder el trabajo', titulo: 'Cambiar de opción sin perder lo capturado', sub: 'Un documento a medias no se pierde al ir a otra pantalla.',
      puntos: ['Aviso antes de salir', 'Borrador guardado en el navegador', 'Recuperar o descartar', 'Separado por usuario y sucursal'] }, 4400);
    await d.ir('facturas');
    await d.sinCarta(1000);
    await d.clic('button:has-text("Nueva factura")', 1200);
    await d.escribir('input[placeholder^="O busque por código"]', 'CLI003');
    await d.p.keyboard.press('Enter'); await d.espera(1200);
    await d.clic('.doc-buscador-resultados .doc-resultado-fila', 1200);
    await d.escribir('input[placeholder^="Escanee o busque el producto"]', 'HP');
    await d.p.keyboard.press('Enter'); await d.espera(1200);
    await d.clic(nuevaFila, 1400);
    await d.rotulo('16 · Sin perder el trabajo', 'Una factura a medias',
      'Un cliente pide una cotización y hay que ir a otra opción del menú sin haber grabado la factura.', { pos: 'arriba-der', espera: 3000 });
    await d.clic('#menu-principal a[href="ventas/cotizaciones"]', 1400);
    await d.rotulo('16 · Sin perder el trabajo', 'Aviso al salir',
      'La aplicación pregunta antes de salir. Si sale, el documento <b>queda como borrador</b> en este navegador.', { pos: 'arriba-izq', espera: false });
    await d.resaltar('.salir-dialogo', 4200); await d.sinResalte();
    await d.clic('.salir-dialogo button[data-accion="salir"]', 2000);
    await d.sinRotulo();
    await d.espera(1200);
    await d.clic('#menu-principal a[href="facturas"]', 1800);
    await d.rotulo('16 · Sin perder el trabajo', 'Recuperar el borrador',
      'Al volver, un aviso muestra qué quedó sin grabar y a qué hora: <b>Recuperar</b> lo carga tal como estaba y <b>Descartar</b> lo borra. Al grabar el documento, el borrador se borra solo.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.borrador-aviso', 4400); await d.sinResalte();
    await d.clic('.borrador-aviso button:has-text("Recuperar")', 2000);
    await d.desplazarA('table.doc-tabla', 'center', 1000);
    await d.resaltar('table.doc-tabla', 3000); await d.sinResalte(); await d.sinRotulo();
  },

  async cierre() {
    await d.carta({ titulo: 'Servicios Informáticos Integrados',
      sub: 'Un ERP completo en la web: ventas con factura electrónica, cartera, compras e inventario, bancos, contabilidad y RRHH.',
      puntos: ['Pólizas automáticas', 'Costos y márgenes reales', 'Cobros en caja o en el banco', 'Seguridad por roles y sucursal'] }, 9000);
  },
};

(async () => {
  const pedidas = process.argv.slice(2);
  const lista = pedidas.length ? pedidas : Object.keys(secciones);
  fs.mkdirSync(TOMAS, { recursive: true });
  await d.iniciar();
  if (lista[0] !== 'intro' && lista[0] !== 'acceso') await iniciarSesion();
  let total = 0;
  for (const nombre of lista) {
    const orden = String(Object.keys(secciones).indexOf(nombre)).padStart(2, '0');
    if (nombre === 'acceso' && lista[0] === 'acceso') { await d.ir('login'); await d.p.evaluate(() => sessionStorage.clear()); await d.p.evaluate(() => window.__demo.carta({ titulo: 'ERP · Servicios Informáticos Integrados' })); await d.espera(1000); }
    await d.grabar(orden + '_' + nombre);
    try { await secciones[nombre](); }
    catch (e) { console.log('  ERROR en', nombre, e.message.split('\n')[0]); await d.p.screenshot({ path: path.join(TOMAS, 'error_' + nombre + '.png') }); }
    total += await d.parar();
  }
  console.log('total', total.toFixed(1), 's · errores JS:', d.errores.length ? d.errores : 'ninguno');
  await d.cerrar();
})();
