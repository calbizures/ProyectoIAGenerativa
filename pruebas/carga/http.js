// node http.js <usuarios> <vueltas> <etiqueta>   (ERP_URL=http://servidor:puerto si no es localhost:5273)
// Mide el tiempo del servidor sin el costo del navegador: cada usuario inicia sesión (cookie propia) y
// pide las pantallas con GET. Blazor las prerenderiza en el servidor, así que la respuesta incluye
// las consultas a la base y el armado del HTML.
const { chromium } = require('playwright');
const [usuariosTxt, vueltasTxt, etiqueta] = process.argv.slice(2);
const USUARIOS = +usuariosTxt, VUELTAS = +vueltasTxt;
const base = process.env.ERP_URL || 'http://localhost:5273';
const clave = process.env.CLAVE_PRUEBA || 'Demo#2024';
const PANTALLAS = ['tableros', 'facturas', 'existencias', 'clientes', 'cxc/antiguedad', 'contabilidad/libros', 'cxc/cobros', 'contabilidad/estados-financieros', 'productos'];

async function cookieDe(b, login) {
  const ctx = await b.newContext();
  const p = await ctx.newPage();
  await p.goto(base + '/login');
  await p.fill('#usuario', login); await p.fill('#password', clave);
  await p.click('button[type=submit]'); await p.waitForLoadState('networkidle');
  if (await p.$('#sucursal')) { await p.selectOption('#sucursal', { index: 1 }); await p.click('button[type=submit]'); await p.waitForLoadState('networkidle'); }
  const c = (await ctx.cookies()).map(x => `${x.name}=${x.value}`).join('; ');
  await ctx.close();
  return c;
}

(async () => {
  const b = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
  const cookies = [];
  for (let i = 1; i <= USUARIOS; i++) cookies.push(await cookieDe(b, 'prueba' + String(i).padStart(2, '0')));
  await b.close();
  const medidas = {};
  const t0 = Date.now();
  await Promise.all(cookies.map(async (cookie) => {
    for (let v = 0; v < VUELTAS; v++)
      for (const ruta of PANTALLAS) {
        const t = Date.now();
        const r = await fetch(`${base}/${ruta}`, { headers: { cookie }, redirect: 'manual' });
        const cuerpo = await r.text();
        const ms = Date.now() - t;
        (medidas[ruta] ??= []).push({ ms, status: r.status, kb: Math.round(cuerpo.length / 1024), login: /login/.test(r.headers.get('location') || '') });
      }
  }));
  const total = Date.now() - t0;
  console.log(`${etiqueta}: ${USUARIOS} usuarios × ${VUELTAS} vueltas × ${PANTALLAS.length} pantallas, ${(total / 1000).toFixed(1)} s, ${Math.round(USUARIOS * VUELTAS * PANTALLAS.length / (total / 1000))} páginas/s`);
  for (const [ruta, m] of Object.entries(medidas)) {
    const ms = m.map(x => x.ms).sort((a, b) => a - b);
    const malos = m.filter(x => x.status !== 200).length;
    console.log(`${ruta.padEnd(34)} prom=${String(Math.round(ms.reduce((s, x) => s + x, 0) / ms.length)).padStart(5)} ms  p95=${String(ms[Math.min(ms.length - 1, Math.floor(0.95 * ms.length))]).padStart(5)} ms  max=${String(ms[ms.length - 1]).padStart(5)} ms  ${m[0].kb} KB${malos ? `  NO-200: ${malos}` : ''}`);
  }
})();
