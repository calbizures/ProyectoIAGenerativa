// Botón Guardar que queda deshabilitado después de grabar (BotonIcono). Aquí
// se vigila lo que lo vuelve a habilitar sin pasar por Editar:
//   - un cambio en algún campo del mismo formulario (input / change);
//   - un mensaje de error que aparece en la página (la grabación falló y hay
//     que poder corregir y reintentar).
(() => {
    const registrados = new Set();
    const ERRORES = '.mensaje-error, .validation-errors, .validation-message, .aviso-error';

    function desbloquear(registro) {
        registro.ref.invokeMethodAsync('Desbloquear').catch(() => { });
    }

    window.erpGuardar = {
        vigilar(boton, ref) {
            if (!boton) return;
            const contenedor = boton.closest('form, .panel-formulario, .doc-documento, .tarjeta, section, main') || document.body;
            const alCambiar = (e) => {
                if (e.target === boton || boton.contains(e.target)) return;
                desbloquear(registro);
            };
            const registro = { boton, ref, contenedor, alCambiar };
            contenedor.addEventListener('input', alCambiar, true);
            contenedor.addEventListener('change', alCambiar, true);
            registrados.add(registro);
            boton.__erpGuardar = registro;
        },
        olvidar(boton) {
            const registro = boton && boton.__erpGuardar;
            if (!registro) return;
            registro.contenedor.removeEventListener('input', registro.alCambiar, true);
            registro.contenedor.removeEventListener('change', registro.alCambiar, true);
            registrados.delete(registro);
            delete boton.__erpGuardar;
        }
    };

    // Un error nuevo o actualizado en la página habilita los botones bloqueados.
    function dentroDeError(nodo) {
        const elemento = nodo.nodeType === 1 ? nodo : nodo.parentElement;
        return !!(elemento && elemento.closest(ERRORES));
    }

    function contieneError(nodo) {
        return nodo.nodeType === 1 && (nodo.matches(ERRORES) || nodo.querySelector(ERRORES) !== null);
    }

    new MutationObserver(mutaciones => {
        if (registrados.size === 0) return;
        const hayError = mutaciones.some(m => dentroDeError(m.target) || [...m.addedNodes].some(contieneError));
        if (hayError) registrados.forEach(desbloquear);
    }).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
})();
