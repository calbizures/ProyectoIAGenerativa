// Aviso al salir de una pantalla con cambios sin grabar. Se carga antes que
// blazor.web.js: así su escucha del botón Atrás (popstate) corre primero y puede
// detener la navegación mejorada de Blazor.
//
// Qué cuenta como "cambios sin grabar":
//   - Un documento con borrador (BorradorDocumento) que informa que tiene datos
//     capturados. En esas pantallas manda el documento: el aviso dice que quedó
//     guardado como borrador y que se recupera al volver.
//   - En las demás pantallas, un campo que cambió dentro del formulario de un
//     botón Guardar visible (guardado.js registra la zona de cada botón). Grabar
//     con éxito, Editar, Nuevo o Cancelar dejan la zona limpia. Los filtros,
//     búsquedas y paginadores no cuentan.
//
// Qué se intercepta: los enlaces internos (menú lateral, tableros), el botón
// Atrás/Adelante del navegador y el formulario de Cerrar sesión, con un diálogo
// propio (Quedarme / Salir). Recargar o cerrar la pestaña muestra el aviso
// nativo del navegador. Ctrl+clic abre otra pestaña sin preguntar: la pantalla
// actual no se pierde.
(() => {
    const EXCLUIDOS = '.barra-herramientas, .barra-filtros, .filtro-campo, .filtro-tercero, .grupo-rango, .paginador, [data-sin-cambios], input[type=search]';
    const zonas = new Set();
    const documentos = new Map();
    let urlActual = location.href;
    let saliendo = false;
    let preguntando = false;

    // ---- zonas de los botones Guardar (guardado.js) --------------------------
    function registrarZona(boton, contenedor) {
        const zona = { boton, contenedor, sucio: false, guardadoEn: 0 };
        zona.alCambiar = (e) => {
            const t = e.target;
            if (!(t instanceof Element) || t.closest(EXCLUIDOS) || t.closest('button')) return;
            zona.sucio = true;
        };
        contenedor.addEventListener('input', zona.alCambiar, true);
        contenedor.addEventListener('change', zona.alCambiar, true);
        zonas.add(zona);
        return zona;
    }

    function quitarZona(zona) {
        if (!zona) return;
        zona.contenedor.removeEventListener('input', zona.alCambiar, true);
        zona.contenedor.removeEventListener('change', zona.alCambiar, true);
        zonas.delete(zona);
    }

    function zonaGuardada(zona) {
        if (!zona) return;
        zona.guardadoEn = zona.sucio ? Date.now() : 0;
        zona.sucio = false;
    }

    // Un error que aparece poco después de grabar: la grabación falló y lo
    // capturado sigue sin grabar.
    function zonaFallo(zona) {
        if (!zona || !zona.guardadoEn) return;
        if (Date.now() - zona.guardadoEn < 15000) zona.sucio = true;
        zona.guardadoEn = 0;
    }

    function limpiarZonas() {
        zonas.forEach(z => { z.sucio = false; z.guardadoEn = 0; });
    }

    // ---- documentos con borrador (BorradorDocumento) ------------------------
    function documento(id, texto, ref) {
        documentos.set(id, { texto: texto || null, ref });
    }

    function quitarDocumento(id) {
        documentos.delete(id);
    }

    function pendiente() {
        if (documentos.size > 0) {
            const textos = [...documentos.values()].map(d => d.texto).filter(Boolean);
            return textos.length ? { borrador: true, textos } : null;
        }
        // Un Guardar deshabilitado (pantalla en modo consulta) no cuenta.
        const sucia = [...zonas].some(z => z.sucio && z.boton.isConnected && !z.boton.disabled);
        return sucia ? { borrador: false, textos: [] } : null;
    }

    async function guardarBorradores() {
        const tareas = [...documentos.values()].filter(d => d.texto && d.ref)
            .map(d => d.ref.invokeMethodAsync('GuardarAhora').catch(() => { }));
        // Si el servidor no responde, no se detiene la salida.
        await Promise.race([Promise.all(tareas), new Promise(r => setTimeout(r, 2000))]);
    }

    // ---- diálogo --------------------------------------------------------------
    let fondo, titulo, mensaje, botonQuedar, botonSalir;

    function crearDialogo() {
        fondo = document.createElement('div');
        fondo.className = 'salir-fondo';
        fondo.hidden = true;
        fondo.innerHTML =
            '<div class="salir-dialogo" role="alertdialog" aria-modal="true" aria-labelledby="salir-titulo" aria-describedby="salir-mensaje">' +
            '<h2 id="salir-titulo"></h2><div id="salir-mensaje"></div>' +
            '<div class="salir-acciones">' +
            '<button type="button" class="boton-icono boton-icono-neutral boton-icono-con-etiqueta" data-accion="quedar"><span class="boton-icono-etiqueta">Quedarme</span></button>' +
            '<button type="button" class="boton-icono boton-icono-primario boton-icono-con-etiqueta" data-accion="salir"><span class="boton-icono-etiqueta">Salir</span></button>' +
            '</div></div>';
        document.body.appendChild(fondo);
        titulo = fondo.querySelector('#salir-titulo');
        mensaje = fondo.querySelector('#salir-mensaje');
        botonQuedar = fondo.querySelector('[data-accion=quedar]');
        botonSalir = fondo.querySelector('[data-accion=salir]');
    }

    function confirmarSalida(estado) {
        if (!fondo) crearDialogo();
        preguntando = true;
        const previo = document.activeElement;
        mensaje.replaceChildren();
        if (estado.borrador) {
            titulo.textContent = 'Documento sin grabar';
            const p = document.createElement('p');
            p.textContent = estado.textos.length === 1
                ? 'Tiene sin grabar: ' + estado.textos[0] + '.'
                : 'Tiene sin grabar:';
            mensaje.appendChild(p);
            if (estado.textos.length > 1) {
                const ul = document.createElement('ul');
                estado.textos.forEach(t => { const li = document.createElement('li'); li.textContent = t; ul.appendChild(li); });
                mensaje.appendChild(ul);
            }
            const p2 = document.createElement('p');
            p2.textContent = 'Si sale, queda guardado como borrador en este navegador y podrá recuperarlo al volver a esta opción.';
            mensaje.appendChild(p2);
            botonSalir.querySelector('span').textContent = 'Salir y guardar borrador';
        } else {
            titulo.textContent = 'Cambios sin grabar';
            const p = document.createElement('p');
            p.textContent = 'Hay cambios en esta pantalla que no se han grabado. Si sale, se perderán.';
            mensaje.appendChild(p);
            botonSalir.querySelector('span').textContent = 'Salir sin grabar';
        }
        fondo.hidden = false;
        botonQuedar.focus();
        return new Promise(resolver => {
            const cerrar = (salir) => {
                fondo.hidden = true;
                fondo.removeEventListener('click', alClic);
                fondo.removeEventListener('keydown', alTecla);
                preguntando = false;
                if (!salir && previo && previo.isConnected && previo.focus) previo.focus();
                resolver(salir);
            };
            const alClic = (e) => {
                const accion = e.target.closest('[data-accion]')?.dataset.accion;
                if (accion) cerrar(accion === 'salir');
                else if (e.target === fondo) cerrar(false);
            };
            const alTecla = (e) => {
                if (e.key === 'Escape') { e.preventDefault(); cerrar(false); }
                else if (e.key === 'Tab') {
                    e.preventDefault();
                    (document.activeElement === botonQuedar ? botonSalir : botonQuedar).focus();
                }
            };
            fondo.addEventListener('click', alClic);
            fondo.addEventListener('keydown', alTecla);
        });
    }

    // Pregunta y, si el usuario decide salir, guarda borradores y deja todo
    // limpio para que la navegación siguiente no vuelva a preguntar.
    async function preguntarYSalir(estado, salir) {
        if (preguntando) return;
        if (!(await confirmarSalida(estado))) return;
        await guardarBorradores();
        limpiarZonas();
        documentos.clear();
        salir();
    }

    function navegar(url) {
        if (window.Blazor && typeof window.Blazor.navigateTo === 'function') window.Blazor.navigateTo(url);
        else location.assign(url);
    }

    // ---- enlaces internos -----------------------------------------------------
    window.addEventListener('click', (e) => {
        if (e.defaultPrevented || e.button !== 0 || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return;
        const a = e.target instanceof Element ? e.target.closest('a[href]') : null;
        if (!a || a.closest('#blazor-error-ui') || a.hasAttribute('download')) return;
        if (a.target && a.target !== '_self') return;
        const url = new URL(a.href, document.baseURI);
        if (url.origin !== location.origin) return;
        if (url.pathname === location.pathname && url.search === location.search) return;
        const estado = pendiente();
        if (!estado) return;
        e.preventDefault();
        e.stopPropagation();
        preguntarYSalir(estado, () => navegar(url.href));
    }, true);

    // ---- Cerrar sesión y otros formularios fuera de la pantalla ---------------
    window.addEventListener('submit', (e) => {
        const form = e.target;
        if (!(form instanceof HTMLFormElement) || form.closest('main') || saliendo) return;
        const estado = pendiente();
        if (!estado) return;
        e.preventDefault();
        e.stopPropagation();
        preguntarYSalir(estado, () => { saliendo = true; form.submit(); });
    }, true);

    // ---- Atrás / Adelante -----------------------------------------------------
    window.addEventListener('popstate', (e) => {
        const estado = pendiente();
        if (preguntando) {
            // El diálogo sigue abierto: se ignora y se vuelve a la pantalla.
            e.stopImmediatePropagation();
            history.pushState(null, '', urlActual);
            return;
        }
        if (!estado) { urlActual = location.href; return; }
        e.stopImmediatePropagation();
        const destino = location.href;
        history.pushState(null, '', urlActual);
        preguntarYSalir(estado, () => navegar(destino));
    });

    // La URL de la pantalla actual, para volver a ella si el usuario se queda.
    for (const metodo of ['pushState', 'replaceState']) {
        const original = history[metodo];
        history[metodo] = function (...args) {
            const r = original.apply(this, args);
            urlActual = location.href;
            return r;
        };
    }

    // ---- Recargar o cerrar la pestaña ----------------------------------------
    window.addEventListener('beforeunload', (e) => {
        if (saliendo || !pendiente()) return;
        e.preventDefault();
        e.returnValue = '';
    });

    window.erpCambios = {
        registrarZona, quitarZona, zonaGuardada, zonaFallo, limpiarZonas,
        documento, quitarDocumento,
        hayCambios: () => pendiente() !== null
    };
})();
