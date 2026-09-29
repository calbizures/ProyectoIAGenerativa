// Motor de grabación de la demo: navegador con la capa de presentación,
// captura de cuadros por CDP (screencast) y codificación a MP4 a 30 fps
// constantes con ffmpeg, un archivo por sección, más una línea de tiempo de
// rótulos para el guion.
const fs = require('fs');
const path = require('path');
const { spawn, execFileSync } = require('child_process');
const { chromium } = require('playwright');

const FFMPEG = process.env.FFMPEG || 'ffmpeg';
const FPS = 30;
const BASE = (process.env.ERP_URL || 'http://localhost:5273').replace(/\/?$/, '/');
const SALIDA = process.env.SALIDA || path.join(__dirname, 'salida');

class Demo {
  constructor(salida) {
    this.salida = salida; fs.mkdirSync(salida, { recursive: true });
    this.pos = [960, 540];
    this.linea = [];
  }

  async iniciar() {
    const logo = fs.readFileSync(path.join(__dirname, '..', 'src', 'Erp.Web', 'wwwroot', 'images', 'logo-si.svg'), 'utf8')
      .replace(/<\?xml[^>]*>/, '').replace(/`/g, '');
    const capa = fs.readFileSync(path.join(__dirname, 'overlay.js'), 'utf8').replace('__LOGO__', logo);
    // El escalado forzado (no emulado) hace que el screencast entregue
    // cuadros de 1920×1080 con la interfaz al 125 %.
    this.nav = await chromium.launch({ args: ['--force-device-scale-factor=1.25', '--window-size=1536,864', '--lang=es-GT'] });
    this.ctx = await this.nav.newContext({ viewport: null, locale: 'es-GT' });
    await this.ctx.addInitScript({ content: capa });
    this.p = await this.ctx.newPage();
    this.errores = [];
    this.p.on('pageerror', e => this.errores.push(e.message));
    this.cdp = await this.ctx.newCDPSession(this.p);
    this.cdp.on('Page.screencastFrame', f => this.cuadro(f));
  }

  // ---- captura -------------------------------------------------------------
  cuadro(f) {
    this.cdp.send('Page.screencastFrameAck', { sessionId: f.sessionId }).catch(() => {});
    if (!this.ff) return;
    const buf = Buffer.from(f.data, 'base64');
    const ts = f.metadata.timestamp;
    if (this.t0 === null) { this.t0 = ts; this.ultimo = buf; return; }
    this.volcar(ts);
    this.ultimo = buf;
  }
  volcar(ts) {
    const hasta = Math.floor((ts - this.t0) * FPS);
    while (this.escritos < hasta) { this.ff.stdin.write(this.ultimo); this.escritos++; }
  }
  async grabar(nombre) {
    this.archivo = path.join(this.salida, nombre + '.mp4');
    this.ff = spawn(FFMPEG, ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '18', '-pix_fmt', 'yuv420p', '-r', String(FPS), this.archivo]);
    this.ff.stderr.on('data', d => process.stderr.write('[ffmpeg] ' + d));
    this.t0 = null; this.escritos = 0; this.ultimo = null; this.nombre = nombre;
    this.inicioReloj = Date.now() / 1000;
    await this.cdp.send('Page.startScreencast', { format: 'jpeg', quality: 92, maxWidth: 1920, maxHeight: 1080, everyNthFrame: 1 });
    await this.mover(this.pos[0] + 1, this.pos[1], 2);  // fuerza un primer cuadro
    await this.p.waitForTimeout(150);
  }
  async parar() {
    await this.p.waitForTimeout(300);
    await this.cdp.send('Page.stopScreencast');
    if (this.t0 !== null) this.volcar(this.t0 + (Date.now() / 1000 - this.inicioReloj) + 0.2);
    const ff = this.ff; this.ff = null;
    await new Promise(r => { ff.on('close', r); ff.stdin.end(); });
    const seg = this.escritos / FPS;
    console.log(`  ${this.nombre}: ${seg.toFixed(1)} s`);
    fs.writeFileSync(path.join(this.salida, this.nombre + '.json'), JSON.stringify({ duracion: seg, eventos: this.linea }, null, 1));
    this.linea = [];
    return seg;
  }
  marca(e) { this.linea.push({ t: +(Date.now() / 1000 - this.inicioReloj).toFixed(2), ...e }); }

  // ---- utilidades ------------------------------------------------------------
  espera(ms) { return this.p.waitForTimeout(ms); }
  async ir(ruta) {
    await this.p.goto(BASE + ruta, { waitUntil: 'networkidle' });
    await this.espera(700);
  }
  async mover(x, y, pasos) {
    const [x0, y0] = this.pos;
    const d = Math.hypot(x - x0, y - y0);
    const n = pasos ?? Math.max(8, Math.min(38, Math.round(d / 22)));
    for (let i = 1; i <= n; i++) {
      const k = i / n; const e = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
      await this.p.mouse.move(x0 + (x - x0) * e, y0 + (y - y0) * e);
      await this.p.waitForTimeout(14);
    }
    this.pos = [x, y];
  }
  loc(sel) { return typeof sel === 'string' ? this.p.locator(sel).first() : sel; }
  async centro(sel) {
    const l = this.loc(sel);
    await l.scrollIntoViewIfNeeded(); await this.espera(150);
    const b = await l.boundingBox();
    if (!b) throw new Error('Sin caja para ' + sel);
    return [b.x + b.width / 2, b.y + b.height / 2, b];
  }
  async apuntar(sel) { const [x, y] = await this.centro(sel); await this.mover(x, y); await this.espera(250); }
  async clic(sel, despues = 900) {
    const [x, y] = await this.centro(sel);
    await this.mover(x, y); await this.espera(220);
    await this.p.mouse.down(); await this.espera(70); await this.p.mouse.up();
    await this.espera(despues);
  }
  async escribir(sel, texto, despues = 400) {
    await this.clic(sel, 250);
    await this.loc(sel).fill('');
    await this.loc(sel).pressSequentially(String(texto), { delay: 65 });
    await this.espera(despues);
  }
  async elegir(sel, valor, despues = 900) {
    await this.clic(sel, 250);
    const l = this.loc(sel);
    if (typeof valor === 'object') await l.selectOption(valor); else await l.selectOption(valor);
    await this.espera(despues);
  }
  async desplazar(y, ms = 1100) {
    await this.p.evaluate(v => window.scrollTo({ top: v, behavior: 'smooth' }), y);
    await this.espera(ms);
  }
  async desplazarA(sel, bloque = 'center', ms = 1100) {
    await this.loc(sel).evaluate((el, b) => el.scrollIntoView({ behavior: 'smooth', block: b }), bloque);
    await this.espera(ms);
  }

  // ---- presentación --------------------------------------------------------
  tiempoLectura(titulo, texto) {
    const palabras = (titulo + ' ' + (texto || '').replace(/<[^>]+>/g, '')).split(/\s+/).filter(Boolean).length;
    return Math.round(Math.max(3200, 1500 + palabras * 290));
  }
  async rotulo(seccion, titulo, texto, o = {}) {
    await this.p.evaluate(d => window.__demo.rotulo(d), { seccion, titulo, texto, pos: o.pos });
    this.marca({ tipo: 'rotulo', seccion, titulo, texto: (texto || '').replace(/<[^>]+>/g, '') });
    if (o.espera !== false) await this.espera(o.espera ?? this.tiempoLectura(titulo, texto));
  }
  async sinRotulo(ms = 450) { await this.p.evaluate(() => window.__demo.ocultarRotulo()); await this.espera(ms); }
  async carta(d, ms = 3800) {
    await this.p.evaluate(x => window.__demo.carta(x), d);
    this.marca({ tipo: 'carta', ...d });
    await this.espera(ms);
  }
  async sinCarta(ms = 900) { await this.p.evaluate(() => window.__demo.ocultarCarta()); await this.espera(ms); }
  async resaltar(sel, ms) {
    const [, , b] = await this.centro(sel);
    await this.p.evaluate(r => window.__demo.resaltar(r), { x: b.x, y: b.y, width: b.width, height: b.height });
    if (ms) await this.espera(ms);
  }
  async sinResalte() { await this.p.evaluate(() => window.__demo.quitarResalte()); await this.espera(250); }

  async cerrar() { await this.nav.close(); }
}

// Consulta a la base (filas como arreglos de texto). Usa sqlcmd dentro del
// contenedor de SQL Server (SQL_CONTENEDOR) con la clave de SA_PASSWORD.
function sql(q) {
  if (!process.env.SA_PASSWORD) throw new Error('Defina SA_PASSWORD con la clave de sa del contenedor de SQL Server.');
  const out = execFileSync('docker', ['exec', process.env.SQL_CONTENEDOR || 'erpsql', '/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-U', 'sa', '-P', process.env.SA_PASSWORD, '-C',
    '-d', 'erp_db', '-h', '-1', '-W', '-s', '|', '-Q', 'SET NOCOUNT ON; ' + q], { encoding: 'utf8' });
  return out.split('\n').map(x => x.trim()).filter(Boolean).map(x => x.split('|'));
}

module.exports = { Demo, BASE, SALIDA, sql };
