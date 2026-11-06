// Tema de la pantalla: "claro", "oscuro" o "sistema" (sigue al sistema
// operativo). Se guarda en la cookie erp-tema para que el servidor pinte
// la página ya con el tema elegido, sin parpadeo.
window.erpTema = {
    actual: function () {
        var m = document.cookie.match(/(?:^|; )erp-tema=([^;]*)/);
        return m && (m[1] === 'claro' || m[1] === 'oscuro') ? m[1] : 'sistema';
    },
    aplicar: function (valor) {
        if (valor !== 'claro' && valor !== 'oscuro') valor = 'sistema';
        document.cookie = 'erp-tema=' + valor + '; path=/; max-age=31536000; samesite=lax';
        var html = document.documentElement;
        if (valor === 'sistema') html.removeAttribute('data-theme');
        else html.setAttribute('data-theme', valor === 'oscuro' ? 'dark' : 'light');
    },
    // Enlace de idioma: vuelve a la pantalla actual después de cambiarlo.
    idioma: function (enlace) {
        var codigo = enlace.classList.contains('idioma-en') ? 'en' : 'es';
        enlace.href = '/idioma/' + codigo + '?volver=' + encodeURIComponent(location.pathname + location.search);
    }
};
