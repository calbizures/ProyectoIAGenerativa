// Una tabla que en pantallas angostas se desplaza de lado (CSS: overflow-x auto)
// debe poder enfocarse con el teclado para desplazarla con las flechas. Se marca
// con tabindex solo si se desborda y no tiene ya un control enfocable dentro.
(() => {
    const SELECTOR = '.tabla-datos, .doc-tabla';
    let pendiente = false;

    function revisar() {
        pendiente = false;
        document.querySelectorAll(SELECTOR).forEach(tabla => {
            const desborda = tabla.scrollWidth > tabla.clientWidth + 1 && getComputedStyle(tabla).overflowX !== 'visible';
            const tieneEnfocable = tabla.querySelector('a[href], button, input, select, textarea, [tabindex]') !== null;
            if (desborda && !tieneEnfocable) {
                if (!tabla.hasAttribute('tabindex')) {
                    tabla.setAttribute('tabindex', '0');
                    tabla.dataset.tabindexAuto = '1';
                }
            } else if (tabla.dataset.tabindexAuto) {
                tabla.removeAttribute('tabindex');
                delete tabla.dataset.tabindexAuto;
            }
        });
    }

    function programar() {
        if (pendiente) return;
        pendiente = true;
        requestAnimationFrame(revisar);
    }

    new MutationObserver(programar).observe(document.documentElement, { childList: true, subtree: true });
    window.addEventListener('resize', programar);
    programar();
})();
