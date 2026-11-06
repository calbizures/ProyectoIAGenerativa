// Capturas limpias (sin rótulos) para la presentación de la Fase 4. Correr
// después de grabar-fase4.js: usa la compra desde la orden de compra, el vale
// de caja chica y la transferencia que la grabación deja registrados. Igual
// que capturas.js, se recorta el menú lateral y la barra de estado.
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const { chromium } = require('playwright');
const { BASE, SALIDA, sql } = require('./lib');

const F4 = path.join(SALIDA, 'fase4');
const CRUDAS = path.join(F4, 'capturas');
const RECORTES = path.join(F4, 'recortes');

(async () => {
  fs.mkdirSync(CRUDAS, { recursive: true }); fs.mkdirSync(RECORTES, { recursive: true });
  const b = await chromium.launch({ args: ['--force-device-scale-factor=1.25', '--window-size=1536,864', '--lang=es-GT'] });
  const ctx = await b.newContext({ viewport: null });
  let p = await ctx.newPage();
  const w = ms => p.waitForTimeout(ms);
  const ir = async r => { await p.goto(BASE + r, { waitUntil: 'networkidle' }); await w(1000); };
  const foto = n => p.screenshot({ path: path.join(CRUDAS, n + '.png') });
  const entrar = async usuario => {
    await ir('login');
    await p.fill('#usuario', usuario); await p.fill('#password', 'Demo#2024'); await p.click('button[type=submit]'); await p.waitForLoadState('networkidle');
    if (await p.$('#sucursal')) { await p.selectOption('#sucursal', { index: 1 }); await p.click('button[type=submit]'); await p.waitForLoadState('networkidle'); }
    await w(800);
  };
  const centrar = async sel => { await p.locator(sel).first().evaluate(e => e.scrollIntoView({ block: 'center' })); await w(700); };

  // Antigüedad vista por el vendedor.
  await entrar('jperez');
  await ir('ventas/antiguedad'); await p.mouse.move(5, 500); await foto('antiguedad_vendedor');
  await p.close();
  await ctx.clearCookies();
  p = await ctx.newPage();
  await entrar('admin');

  await ir('permisos');
  await p.fill('main input[type=search]', 'COMPRAS_ORDEN'); await w(900);
  await p.locator('.permisos-maestro table').first().locator('tbody tr', { hasText: 'COMPRAS_ORDEN_APROBAR' }).first().click(); await w(1200);
  await foto('permisos_detalle');

  // La orden de la demo quedó con lo pendiente de recibir.
  await ir('compras'); await p.click('button:has-text("Desde orden de compra")'); await w(900);
  await p.selectOption('#compras-desde-orden', { index: 1 }); await w(1500);
  await p.locator('.oc-recepcion').evaluate(e => e.scrollIntoView({ block: 'start' })); await w(700); await foto('compra_desde_oc');

  await ir('existencias');
  await p.locator('main table tbody tr', { hasText: 'LAP-DELL-3520' }).first().locator('button:has-text("Kardex")').click(); await w(1500);
  await p.selectOption('select[aria-label=Bodega]', '0'); await w(1500);
  await p.mouse.move(5, 500); await foto('kardex');

  await ir('bancos/caja-chica'); await centrar('main table'); await foto('caja_chica');

  const [[prv]] = sql("SELECT TOP 1 line.prv_id FROM dbo.bco_lote_transferencia lote JOIN dbo.bco_lote_transferencia_det line ON line.blt_id = lote.blt_id WHERE lote.blt_tipo = 'D' ORDER BY lote.blt_id DESC");
  await ir(`cxp/pagos?prv=${prv}`);
  await p.locator('#titulo-transferencias').evaluate(e => e.scrollIntoView({ block: 'start' })); await w(600);
  await p.locator('.tarjeta:has(#titulo-transferencias) tbody tr >> nth=0 >> button[aria-label="Ver facturas y cuotas pagadas"]').click(); await w(1200);
  await p.locator('#titulo-transferencias').evaluate(e => e.scrollIntoView({ block: 'start' })); await w(600);
  await p.mouse.move(5, 500); await foto('transferencias');
  // Formulario de transferencia con las cuotas más antiguas marcadas.
  await ir(`cxp/pagos?prv=${prv}`);
  await p.click('button:has-text("Todo lo vencido")'); await w(800);
  await p.click('.forma-pago-opciones label:has-text("Transferencia")'); await w(800);
  await p.locator('#titulo-forma-pago').evaluate(e => e.scrollIntoView({ block: 'start' })); await w(600);
  await p.mouse.move(5, 500); await foto('transferencia_formulario');

  await ir('general/companias');
  await p.locator('main table tbody tr').first().locator('button[aria-label="Ver detalle"]').click(); await w(1200);
  await p.locator('h3:has-text("Correo saliente")').evaluate(e => e.scrollIntoView({ block: 'start' })); await w(700); await p.mouse.move(5, 500); await foto('correo');
  await b.close();

  for (const f of fs.readdirSync(CRUDAS).filter(f => f.endsWith('.png')))
    await sharp(path.join(CRUDAS, f)).extract({ left: 338, top: 0, width: 1582, height: 1034 }).toFile(path.join(RECORTES, f));
  console.log('capturas:', fs.readdirSync(RECORTES).join(', '));
})();
