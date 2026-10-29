// node web.js <usuarios> <vueltas> <etiqueta>   (ERP_URL=http://servidor:puerto si no es localhost:5273)
// Cada usuario virtual (un contexto de navegador = una sesión/circuito de Blazor) inicia sesión como
// pruebaNN y, en cada vuelta, abre pantallas de uso diario y graba una factura de contado desde la UI.
const { chromium } = require('playwright');
const fs = require('fs');
const [usuariosTxt, vueltasTxt, etiqueta] = process.argv.slice(2);
const USUARIOS = +usuariosTxt, VUELTAS = +vueltasTxt;
const base = process.env.ERP_URL || 'http://localhost:5273';
const clave = process.env.CLAVE_PRUEBA || 'Demo#2024';
const PANTALLAS = ['tableros', 'facturas', 'existencias', 'clientes', 'cxc/antiguedad', 'contabilidad/libros', 'cxc/cobros'];
const medidas = [];   // { usuario, accion, ms, ok, detalle }

async function medir(usuario, accion, fn) {
  const t0 = Date.now();
  try { const detalle = await fn(); medidas.push({ usuario, accion, ms: Date.now() - t0, ok: true, detalle }); }
  catch (e) { medidas.push({ usuario, accion, ms: Date.now() - t0, ok: false, detalle: String(e.message).split('\n')[0].slice(0, 200) }); }
}

async function facturar(p) {
  await p.goto(base + '/facturas'); await p.waitForLoadState('networkidle');
  await p.click('button:has-text("Nueva factura")');
  await p.click('button:has-text("C/F")');
  const buscar = p.locator('input[aria-label="Buscar producto por código o descripción"]');
  await buscar.fill('MON'); await buscar.press('Enter');
  await p.locator('.doc-buscador-resultados .doc-resultado-fila').first().click();
  await p.selectOption('#facturas-condicionpagofactura', 'contado');
  await p.waitForTimeout(300);
  const t0 = Date.now();
  await p.click('button:has-text("Grabar factura")');
  // éxito: aparece el aviso de factura grabada; error: un aviso de error
  const aviso = p.locator('.aviso, [role=status], [role=alert]').filter({ hasText: /grabad|Factura|error|No hay|suficiente/i }).first();
  await aviso.waitFor({ timeout: 30000 });
  const texto = (await aviso.innerText()).replace(/\s+/g, ' ').slice(0, 160);
  if (!/grabad/i.test(texto)) throw new Error('Respuesta: ' + texto);
  return `${Date.now() - t0} ms al grabar · ${texto}`;
}

async function usuarioVirtual(b, n) {
  const login = 'prueba' + String(n).padStart(2, '0');
  const ctx = await b.newContext({ viewport: { width: 1366, height: 900 } });
  const p = await ctx.newPage();
  const errores = [];
  p.on('pageerror', e => errores.push(e.message));
  await medir(n, 'login', async () => {
    await p.goto(base + '/login');
    await p.fill('#usuario', login); await p.fill('#password', clave);
    await p.click('button[type=submit]'); await p.waitForLoadState('networkidle');
    if (await p.$('#sucursal')) { await p.selectOption('#sucursal', { index: 1 }); await p.click('button[type=submit]'); await p.waitForLoadState('networkidle'); }
  });
  for (let v = 0; v < VUELTAS; v++) {
    for (const ruta of PANTALLAS)
      await medir(n, 'pantalla ' + ruta, async () => {
        await p.goto(base + '/' + ruta); await p.waitForLoadState('networkidle');
        if (await p.locator('#blazor-error-ui').isVisible()) throw new Error('blazor-error-ui');
      });
    await medir(n, 'grabar factura (UI)', () => facturar(p));
  }
  if (errores.length) medidas.push({ usuario: n, accion: 'errores JS', ms: 0, ok: false, detalle: errores.slice(0, 3).join(' | ') });
  await ctx.close();
}

(async () => {
  const b = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
  const t0 = Date.now();
  await Promise.all(Array.from({ length: USUARIOS }, (_, i) => usuarioVirtual(b, i + 1)));
  const total = Date.now() - t0;
  await b.close();
  fs.writeFileSync(`${__dirname}/web-${etiqueta}.json`, JSON.stringify({ usuarios: USUARIOS, vueltas: VUELTAS, totalMs: total, medidas }, null, 1));
  // resumen por acción
  const grupos = {};
  for (const m of medidas) (grupos[m.accion] ??= []).push(m);
  const pct = (a, q) => a[Math.min(a.length - 1, Math.floor(q * a.length))];
  console.log(`${etiqueta}: ${USUARIOS} usuarios × ${VUELTAS} vueltas, ${(total / 1000).toFixed(1)} s`);
  for (const [accion, ms] of Object.entries(grupos)) {
    const ok = ms.filter(m => m.ok).map(m => m.ms).sort((a, b) => a - b);
    console.log(`${accion.padEnd(30)} n=${String(ms.length).padStart(3)} ok=${String(ok.length).padStart(3)}  prom=${ok.length ? Math.round(ok.reduce((s, x) => s + x, 0) / ok.length) : '-'} ms  p95=${ok.length ? pct(ok, 0.95) : '-'} ms  max=${ok.length ? ok[ok.length - 1] : '-'} ms`);
  }
  for (const m of medidas.filter(m => !m.ok).slice(0, 8)) console.log('  FALLA', m.usuario, m.accion, m.detalle);
})();
