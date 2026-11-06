// Capturas limpias (sin rótulos) para la presentación. Se toman a 1920×1080
// y se recorta el menú lateral y la barra de estado para que el contenido se
// lea mejor en la diapositiva (menos en «inicio_logo», que muestra el menú con
// el logotipo). Correr después de grabar.js: usa la cotización, la factura,
// el cobro, la boleta, las compras, la toma de inventario, los pagos y el
// logotipo que la demo deja grabados.
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const { chromium } = require('playwright');
const { BASE, SALIDA, sql } = require('./lib');

const CRUDAS = path.join(SALIDA, 'capturas');
const RECORTES = path.join(SALIDA, 'recortes');

(async () => {
  fs.mkdirSync(CRUDAS, { recursive: true }); fs.mkdirSync(RECORTES, { recursive: true });
  const b = await chromium.launch({ args: ['--force-device-scale-factor=1.25', '--window-size=1536,864', '--lang=es-GT'] });
  const p = await (await b.newContext({ viewport: null })).newPage();
  const w = ms => p.waitForTimeout(ms);
  const ir = async r => { await p.goto(BASE + r, { waitUntil: 'networkidle' }); await w(1000); };
  const foto = n => p.screenshot({ path: path.join(CRUDAS, n + '.png') });

  await ir('login');
  await p.fill('#usuario', 'admin'); await p.fill('#password', 'Demo#2024'); await p.click('button[type=submit]'); await p.waitForLoadState('networkidle');
  await p.selectOption('#sucursal', { index: 1 }); await p.click('button[type=submit]'); await p.waitForLoadState('networkidle'); await w(800);

  await ir('tableros'); await p.mouse.move(5, 500); await w(500); await foto('tablero_ventas');
  await ir('facturas'); await p.click('tbody tr >> nth=0 >> button[aria-label="Ver detalle"]'); await w(1500);
  await p.locator('.fel-resumen').first().evaluate(e => e.scrollIntoView({ block: 'center' })).catch(() => {}); await w(600); await foto('factura_detalle');
  await ir('cxc/antiguedad'); await foto('cxc_antiguedad');
  await ir('productos');
  await p.fill('input[placeholder="Buscar por descripción"]', 'Laptop'); await p.click('main button:has-text("Buscar")'); await w(1200); await foto('productos');
  await ir('caja'); await p.click('.pestana-boton:has-text("Corte")'); await w(800);
  await p.locator('.campo:has(label:has-text("Caja abierta")) select').selectOption({ index: 1 }); await w(1500); await foto('caja_corte');
  await ir('contabilidad/nomenclatura'); await p.click('button:has-text("Expandir todo")'); await w(800); await p.click('button:has-text("111 CAJA")'); await w(1000); await foto('nomenclatura');
  await ir('rrhh/estructura'); await p.click('.pestana-boton:has-text("Organigrama")'); await w(1800); await foto('organigrama');
  await ir('permisos'); await foto('permisos');

  const [[prv]] = sql("SELECT prv_id FROM dbo.inv_proveedor WHERE prv_codigo = 'PRV02'");
  await ir(`compras/productos-proveedor?prv=${prv}`); await foto('productos_proveedor');
  await ir('inventario/fisico'); await p.locator('main table tbody tr').first().locator('button').first().click(); await w(1500);
  await p.check('label.casilla:has-text("Solo con diferencia") input'); await w(800); await foto('toma_fisica');
  await ir('bancos/cuentas'); await p.locator('main table.tabla-datos tbody tr').first().locator('td').first().click(); await w(1200); await foto('cuentas_bancarias');
  await ir('rrhh/nominas'); await p.locator('main table tbody tr', { hasText: 'Mensual' }).first().locator('button[aria-label="Ver detalle"]').click(); await w(1500);
  await p.locator('#pago-nomina').evaluate(e => e.scrollIntoView({ block: 'start' })); await w(800); await foto('nomina_pago');
  await ir('contabilidad/saldos-iniciales'); await foto('saldos_iniciales');
  await ir('ventas/cotizaciones'); await p.click('main table tbody tr >> nth=0 >> button[aria-label="Ver la cotización"]'); await w(1500); await foto('cotizacion');
  await ir('facturas'); await p.click('tbody tr >> nth=0 >> button[aria-label="Ver detalle"]'); await w(1500);
  await p.click('button:has-text("Enviar por correo")'); await w(1500);
  await p.locator('.enviar-correo').evaluate(e => e.scrollIntoView({ block: 'center' })); await w(600); await foto('factura_correo');
  await ir('cxc/cobros'); await p.selectOption('select[aria-label="Estado de las boletas"]', ''); await w(1500);
  await p.locator('#titulo-boletas').evaluate(e => e.scrollIntoView({ block: 'start' })); await w(600); await foto('cobros_boletas');
  await ir('compras/ordenes'); await foto('ordenes_compra');
  await ir('existencias'); await p.locator('main table tbody tr', { hasText: 'LAP-DELL-3520' }).first().locator('button:has-text("Kardex")').click(); await w(1500);
  await p.selectOption('select[aria-label=Bodega]', '0'); await w(1800); await foto('kardex');
  const [[prvT]] = sql("SELECT TOP 1 deta.prv_id FROM dbo.bco_lote_transferencia_det deta JOIN dbo.bco_transferencia_comprobante comp ON comp.blt_id = deta.blt_id WHERE deta.prv_id IS NOT NULL ORDER BY deta.blt_id DESC");
  await ir(`cxp/pagos?prv=${prvT}`); await p.locator('#titulo-transferencias').evaluate(e => e.scrollIntoView({ block: 'start' })); await w(800); await foto('pagos_transferencia');
  await ir('bancos/conciliacion'); await p.locator('main table tbody tr button').first().click().catch(() => {}); await w(1800); await foto('conciliacion');
  await ir('contabilidad/estados-financieros'); await p.click('main button:has-text("Consultar")').catch(() => {}); await w(1800); await foto('estados_financieros');
  await ir('rrhh/planilla-igss'); await p.selectOption('select[aria-label="Mes"]', String(new Date().getMonth() + 1)); await w(1800); await foto('planilla_igss');
  await ir(''); await p.mouse.move(1500, 700); await w(800); await foto('inicio_logo');
  await b.close();

  // Menú lateral (338 px) y barra de estado (46 px) fuera.
  for (const f of fs.readdirSync(CRUDAS).filter(f => f.endsWith('.png') && f !== 'inicio_logo.png'))
    await sharp(path.join(CRUDAS, f)).extract({ left: 338, top: 0, width: 1582, height: 1034 }).toFile(path.join(RECORTES, f));
  await sharp(path.join(CRUDAS, 'inicio_logo.png')).toFile(path.join(RECORTES, 'inicio_logo.png'));
  console.log('capturas:', fs.readdirSync(RECORTES).join(', '));
})();
