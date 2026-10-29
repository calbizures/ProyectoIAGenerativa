// Capa de presentación que se inyecta en cada página de la demo: cursor
// visible, rótulos descriptivos, cortinillas de sección y resaltado. El
// estado (cortinilla visible, posición del cursor) sobrevive a la navegación
// mediante sessionStorage. La constante LOGO recibe el SVG del logotipo.
(() => {
  if (window.__demo) return;
  const LOGO = `__LOGO__`;
  const CSS = `
  #demo-capa{position:fixed;inset:0;pointer-events:none;z-index:2147483646;font-family:'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif}
  #demo-cursor{position:fixed;left:0;top:0;width:26px;height:26px;z-index:2147483647;pointer-events:none;transform:translate(-3px,-2px);filter:drop-shadow(0 2px 3px rgba(0,0,0,.35));transition:opacity .2s}
  .demo-onda{position:fixed;width:16px;height:16px;margin:-8px 0 0 -8px;border-radius:50%;border:3px solid #29b6f6;background:rgba(41,182,246,.25);animation:demoOnda .6s ease-out forwards;z-index:2147483646}
  @keyframes demoOnda{from{transform:scale(.6);opacity:1}to{transform:scale(3.4);opacity:0}}
  #demo-rotulo{position:fixed;max-width:640px;background:rgba(13,27,76,.94);color:#fff;border-radius:16px;padding:18px 22px 20px;box-shadow:0 18px 40px rgba(6,14,40,.35);opacity:0;transform:translateY(18px);transition:opacity .45s ease,transform .45s ease;backdrop-filter:blur(4px)}
  #demo-rotulo.visible{opacity:1;transform:none}
  #demo-rotulo.abajo-izq{left:28px;bottom:58px} #demo-rotulo.abajo-der{right:28px;bottom:58px} #demo-rotulo.arriba-der{right:28px;top:22px} #demo-rotulo.arriba-izq{left:300px;top:22px} #demo-rotulo.centro-abajo{left:50%;bottom:58px;transform:translate(-50%,18px)} #demo-rotulo.centro-abajo.visible{transform:translate(-50%,0)}
  #demo-rotulo .demo-seccion{display:inline-flex;gap:8px;align-items:center;font-size:12.5px;font-weight:700;letter-spacing:.09em;text-transform:uppercase;color:#7ee0fb;margin-bottom:8px}
  #demo-rotulo .demo-seccion i{display:inline-block;width:8px;height:8px;border-radius:50%;background:#29b6f6;box-shadow:0 0 0 4px rgba(41,182,246,.25)}
  #demo-rotulo h3{margin:0 0 6px;font-size:23px;line-height:1.25;font-weight:700;color:#fff}
  #demo-rotulo p{margin:0;font-size:17px;line-height:1.5;color:#d5e6ff}
  #demo-rotulo p b{color:#fff}
  #demo-resalte{position:fixed;border:3px solid #29b6f6;border-radius:12px;box-shadow:0 0 0 6px rgba(41,182,246,.22),0 0 26px rgba(41,182,246,.55);opacity:0;transition:opacity .3s,left .35s,top .35s,width .35s,height .35s;animation:demoPulso 1.6s ease-in-out infinite}
  #demo-resalte.visible{opacity:1}
  @keyframes demoPulso{50%{box-shadow:0 0 0 10px rgba(41,182,246,.12),0 0 34px rgba(41,182,246,.7)}}
  #demo-carta{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;background:radial-gradient(120% 120% at 0% 0%,#0d1b4c 0%,#142d6e 38%,#1565c0 78%,#1e88e5 100%);opacity:0;transition:opacity .7s ease;pointer-events:none;overflow:hidden}
  #demo-carta.visible{opacity:1}
  #demo-carta .demo-orbe{position:absolute;border-radius:50%;background:radial-gradient(circle,rgba(126,224,251,.28),rgba(126,224,251,0) 70%);animation:demoFlota 9s ease-in-out infinite alternate}
  @keyframes demoFlota{to{transform:translate(40px,-30px) scale(1.12)}}
  #demo-carta .demo-cuadros{position:absolute;right:9%;top:16%;display:grid;grid-template-columns:repeat(3,22px);gap:12px;opacity:.55}
  #demo-carta .demo-cuadros span{width:22px;height:22px;background:#7ee0fb;border-radius:4px;animation:demoParpadeo 2.4s ease-in-out infinite}
  @keyframes demoParpadeo{50%{opacity:.25}}
  #demo-carta .demo-contenido{position:relative;display:flex;gap:64px;align-items:center;max-width:1240px;padding:0 60px;color:#fff}
  #demo-carta .demo-logo{flex:none;width:250px;height:236px;background:#fff;border-radius:28px;display:flex;align-items:center;justify-content:center;box-shadow:0 30px 60px rgba(4,10,35,.45)}
  #demo-carta .demo-logo svg{width:210px;height:auto}
  #demo-carta .demo-num{font-size:20px;font-weight:700;letter-spacing:.2em;color:#7ee0fb;text-transform:uppercase;margin-bottom:12px}
  #demo-carta h1{margin:0;color:#fff;font-size:64px;line-height:1.05;font-weight:800;letter-spacing:-.01em}
  #demo-carta .demo-sub{margin:18px 0 0;font-size:25px;line-height:1.45;color:#d5e6ff;max-width:760px}
  #demo-carta ul{margin:26px 0 0;padding:0;list-style:none;display:grid;grid-template-columns:1fr 1fr;gap:12px 34px;max-width:800px}
  #demo-carta li{font-size:19px;color:#eaf4ff;display:flex;gap:12px;align-items:baseline}
  #demo-carta li::before{content:'';flex:none;width:9px;height:9px;border-radius:2px;background:#29b6f6;transform:translateY(-2px)}
  #demo-carta .demo-anim{opacity:0;transform:translateY(22px);transition:opacity .7s ease,transform .7s ease}
  #demo-carta.visible .demo-anim{opacity:1;transform:none}
  #demo-carta.visible .demo-anim.d1{transition-delay:.15s} #demo-carta.visible .demo-anim.d2{transition-delay:.35s} #demo-carta.visible .demo-anim.d3{transition-delay:.55s} #demo-carta.visible .demo-anim.d4{transition-delay:.75s}
  #demo-panel{position:fixed;right:28px;top:26px;width:760px;max-height:calc(100vh - 230px);overflow:hidden;background:#0b1433;border-radius:16px;box-shadow:0 22px 50px rgba(4,10,35,.5);opacity:0;transform:translateX(30px);transition:opacity .45s,transform .45s}
  #demo-panel.visible{opacity:1;transform:none}
  #demo-panel header{display:flex;gap:10px;align-items:center;padding:12px 18px;background:#142d6e;color:#d5e6ff;font-size:14px;font-weight:600;letter-spacing:.04em}
  #demo-panel header i{width:11px;height:11px;border-radius:50%;background:#29b6f6;display:inline-block}
  #demo-panel pre{margin:0;padding:16px 18px;font:13.5px/1.55 'DejaVu Sans Mono',Menlo,monospace;color:#cfe3ff;white-space:pre-wrap;word-break:break-all}
  #demo-panel .xt{color:#7ee0fb} #demo-panel .xa{color:#ffcf70} #demo-panel .xv{color:#a8e6a1}
  #demo-carta .demo-pie{position:absolute;left:60px;bottom:44px;font-size:15px;letter-spacing:.14em;text-transform:uppercase;color:rgba(213,230,255,.8)}
  `;
  const S = sessionStorage;
  let capa, cursor, rotulo, resalte, carta;

  function esc(t) { return String(t ?? ''); }

  function asegurar() {
    const host = document.documentElement;
    if (!host) return false;
    if (!document.getElementById('demo-estilo')) {
      const st = document.createElement('style'); st.id = 'demo-estilo'; st.textContent = CSS; (document.head || host).appendChild(st);
    }
    capa = document.getElementById('demo-capa');
    if (!capa) {
      capa = document.createElement('div'); capa.id = 'demo-capa';
      capa.innerHTML = '<div id="demo-resalte"></div><div id="demo-panel"></div><div id="demo-rotulo"></div><div id="demo-carta"></div>' +
        '<svg id="demo-cursor" viewBox="0 0 26 26"><path d="M3 2 L3 21 L8.2 16.4 L11.6 24 L15 22.5 L11.7 15 L19 15 Z" fill="#fff" stroke="#0d1b4c" stroke-width="1.6" stroke-linejoin="round"/></svg>';
      host.appendChild(capa);
    }
    cursor = document.getElementById('demo-cursor'); rotulo = document.getElementById('demo-rotulo');
    resalte = document.getElementById('demo-resalte'); carta = document.getElementById('demo-carta');
    return true;
  }

  function moverCursor(x, y) {
    if (!asegurar()) return;
    cursor.style.left = x + 'px'; cursor.style.top = y + 'px';
    S.setItem('demo-cursor', JSON.stringify([x, y]));
  }

  function pintarCarta(d) {
    const lista = (d.puntos || []).map(p => `<li>${esc(p)}</li>`).join('');
    carta.innerHTML = `
      <div class="demo-orbe" style="width:720px;height:720px;left:-180px;top:-240px"></div>
      <div class="demo-orbe" style="width:560px;height:560px;right:-140px;bottom:-200px;animation-delay:-4s"></div>
      <div class="demo-cuadros"><span></span><span style="animation-delay:.4s"></span><span style="animation-delay:.8s"></span><span style="animation-delay:1.2s"></span><span></span><span style="animation-delay:1.6s"></span></div>
      <div class="demo-contenido">
        ${d.logo === false ? '' : `<div class="demo-logo demo-anim">${LOGO}</div>`}
        <div>
          ${d.numero ? `<div class="demo-num demo-anim d1">${esc(d.numero)}</div>` : ''}
          <h1 class="demo-anim d1">${esc(d.titulo)}</h1>
          ${d.sub ? `<p class="demo-sub demo-anim d2">${esc(d.sub)}</p>` : ''}
          ${lista ? `<ul class="demo-anim d3">${lista}</ul>` : ''}
        </div>
      </div>
      <div class="demo-pie demo-anim d4">Servicios Informáticos Integrados · ERP</div>`;
  }

  window.__demo = {
    cursor: moverCursor,
    onda(x, y) { if (!asegurar()) return; const o = document.createElement('div'); o.className = 'demo-onda'; o.style.left = x + 'px'; o.style.top = y + 'px'; capa.appendChild(o); setTimeout(() => o.remove(), 700); },
    rotulo(d) {
      if (!asegurar()) return;
      const pintar = () => {
        rotulo.className = d.pos || 'abajo-izq';
        rotulo.innerHTML = `${d.seccion ? `<div class="demo-seccion"><i></i>${esc(d.seccion)}</div>` : ''}<h3>${esc(d.titulo)}</h3>${d.texto ? `<p>${d.texto}</p>` : ''}`;
        requestAnimationFrame(() => requestAnimationFrame(() => rotulo.classList.add('visible')));
      };
      if (rotulo.classList.contains('visible')) { rotulo.classList.remove('visible'); setTimeout(pintar, 380); } else pintar();
    },
    ocultarRotulo() { if (asegurar()) rotulo.classList.remove('visible'); },
    carta(d) {
      if (!asegurar()) return;
      S.setItem('demo-carta', JSON.stringify(d)); pintarCarta(d);
      requestAnimationFrame(() => requestAnimationFrame(() => carta.classList.add('visible')));
    },
    ocultarCarta() { S.removeItem('demo-carta'); if (asegurar()) carta.classList.remove('visible'); },
    resaltar(r) {
      if (!asegurar()) return;
      const m = 8; Object.assign(resalte.style, { left: (r.x - m) + 'px', top: (r.y - m) + 'px', width: (r.width + 2 * m) + 'px', height: (r.height + 2 * m) + 'px' });
      resalte.classList.add('visible');
    },
    quitarResalte() { if (asegurar()) resalte.classList.remove('visible'); },
    panel(titulo, xml) {
      if (!asegurar()) return;
      const p = document.getElementById('demo-panel');
      const h = xml.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/(&lt;\/?)([\w:.-]+)|([\w:.-]+)="([^"]*)"/g, (m, a, t, n, v) =>
          a !== undefined ? a + '<span class="xt">' + t + '</span>' : '<span class="xa">' + n + '</span>=<span class="xv">"' + v + '"</span>');
      p.innerHTML = `<header><i></i>${esc(titulo)}</header><pre>${h}</pre>`;
      requestAnimationFrame(() => requestAnimationFrame(() => p.classList.add('visible')));
    },
    sinPanel() { if (asegurar()) document.getElementById('demo-panel').classList.remove('visible'); },
  };

  // Al cargar un documento nuevo: restaurar cursor y, si había una cortinilla
  // en pantalla, pintarla ya visible (sin animación) para que no se vea el
  // parpadeo de la navegación.
  const iniciar = () => {
    if (!asegurar()) { requestAnimationFrame(iniciar); return; }
    const c = JSON.parse(S.getItem('demo-cursor') || '[960,540]'); moverCursor(c[0], c[1]);
    const d = S.getItem('demo-carta');
    if (d) { pintarCarta(JSON.parse(d)); carta.style.transition = 'none'; carta.classList.add('visible'); carta.offsetHeight; carta.style.transition = ''; }
  };
  iniciar();
  addEventListener('mousemove', e => moverCursor(e.clientX, e.clientY), true);
  addEventListener('mousedown', e => window.__demo.onda(e.clientX, e.clientY), true);
  // Blazor puede reemplazar partes del documento: si la capa desaparece, se repone.
  new MutationObserver(() => { if (!document.getElementById('demo-capa')) { asegurar(); const c = JSON.parse(S.getItem('demo-cursor') || '[960,540]'); moverCursor(c[0], c[1]); } })
    .observe(document, { childList: true, subtree: true });
})();
