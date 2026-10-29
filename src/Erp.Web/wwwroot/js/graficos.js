// Ancho real del contenedor de un gráfico para dibujarlo a escala 1:1 (el
// texto de los ejes conserva su tamaño en escritorio y en celular).
window.erpGraficos = {
    observar(elemento, componente) {
        if (!elemento) return 0;
        let pendiente = null;
        const observador = new ResizeObserver(entradas => {
            const ancho = Math.round(entradas[0].contentRect.width);
            clearTimeout(pendiente);
            pendiente = setTimeout(() => componente.invokeMethodAsync('AjustarAncho', ancho).catch(() => { }), 120);
        });
        observador.observe(elemento);
        elemento._erpObservador = observador;
        return Math.round(elemento.getBoundingClientRect().width);
    },
    dejar(elemento) {
        if (elemento && elemento._erpObservador) elemento._erpObservador.disconnect();
    }
};
