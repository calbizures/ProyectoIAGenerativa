// Capturas limpias (sin rótulos) para la presentación. Se toman a 1920×1080
// y se recorta el menú lateral y la barra de estado para que el contenido se
// lea mejor en la diapositiva. Correr después de grabar.js: usa la factura,
// el cobro y la compra que la demo deja grabados.
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const { chromium } = require('playwright');
const { BASE, SALIDA } = require('./lib');

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
  await p.selectOption('#sucursal', '1'); await p.click('button[type=submit]'); await p.waitForLoadState('networkidle'); await w(800);

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
  await b.close();

  // Menú lateral (338 px) y barra de estado (46 px) fuera.
  for (const f of fs.readdirSync(CRUDAS).filter(f => f.endsWith('.png')))
    await sharp(path.join(CRUDAS, f)).extract({ left: 338, top: 0, width: 1582, height: 1034 }).toFile(path.join(RECORTES, f));
  console.log('capturas:', fs.readdirSync(RECORTES).join(', '));
})();
