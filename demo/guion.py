"""Arma el guion (tiempos, cortinillas y rótulos) a partir de las líneas de
tiempo que grabar.js deja en salida/tomas/*.json. Uso: python3 guion.py"""
import glob
import json
import os

SALIDA = os.environ.get('SALIDA', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'salida'))
SECCIONES = {
    '00_intro': 'Portada', '01_acceso': '01 · Acceso', '02_tableros': '02 · Tableros gerenciales',
    '03_factura': '03 · Ventas y facturación', '04_fel': '04 · Factura electrónica (FEL)', '05_cxc': '05 · Cuentas por cobrar',
    '06_compras': '06 · Compras e inventario', '07_inventario': '07 · Inventario físico', '08_caja': '08 · Proveedores y caja',
    '09_bancos': '09 · Bancos', '10_contabilidad': '10 · Contabilidad', '11_rrhh': '11 · Recursos humanos',
    '12_arranque': '12 · Puesta en marcha (cargas desde Excel)', '13_admin': '13 · Administración y seguridad', '14_cierre': 'Cierre',
}


def mmss(t):
    return f"{int(t // 60)}:{int(t % 60):02d}"


tomas = []
inicio = 0.0
for f in sorted(glob.glob(os.path.join(SALIDA, 'tomas', '*.json'))):
    nombre = os.path.basename(f)[:-5]
    datos = json.load(open(f, encoding='utf-8'))
    tomas.append((nombre, inicio, datos))
    inicio += datos['duracion']

L = ["# Guion de la demo — ERP · Servicios Informáticos Integrados", "",
     f"Video de {mmss(inicio)} min, 1920×1080, 30 fps. Sin locución: la explicación va en rótulos en pantalla y el fondo es "
     "música instrumental original (generada por `musica.py`, libre de derechos). Los tiempos son del video final.", "",
     "| Tiempo | Sección |", "|---|---|"]
L += [f"| {mmss(t)} | {SECCIONES.get(n, n)} |" for n, t, _ in tomas] + [f"| {mmss(inicio)} | Fin |", ""]
for nombre, t0, datos in tomas:
    L += [f"## {mmss(t0)} · {SECCIONES.get(nombre, nombre)}", ""]
    for e in datos['eventos']:
        t = mmss(t0 + e['t'])
        if e['tipo'] == 'carta':
            txt = f"**Cortinilla:** {e['numero'] + ' — ' if e.get('numero') else ''}*{e['titulo']}*"
            if e.get('sub'):
                txt += f". {e['sub']}"
            if e.get('puntos'):
                txt += " Puntos: " + "; ".join(e['puntos']) + "."
            L.append(f"- `{t}` {txt}")
        elif e['tipo'] == 'rotulo':
            L.append(f"- `{t}` **{e['titulo']}.** {e['texto']}")
        elif e['tipo'] == 'panel':
            L.append(f"- `{t}` **Panel:** fragmento real del XML del DTE (GTDocumento 0.1) enviado al certificador.")
    L.append("")
L += ["## Qué se ve en pantalla", "",
      "- Todo es la aplicación real corriendo contra SQL Server con los datos de prueba (scripts 00 a 43): la factura, el cobro, la compra, la toma de inventario, el depósito, el cheque a proveedor por varias facturas, el cheque libre y el logotipo se graban de verdad durante la grabación.",
      "- La factura electrónica usa el **simulador** de certificación (UUID, serie y número de prueba, sin validez fiscal). Con INFILE el flujo es el mismo.",
      "- Usuario de la demo: `admin`, sucursal *Casa matriz Zona 10*.", "",
      "## Si se quiere agregar voz", "",
      "Cada rótulo de arriba sirve como texto de locución, en el tiempo indicado. Una voz grabada puede mezclarse sobre la música bajándola unos 10 dB mientras se habla."]
open(os.path.join(SALIDA, 'guion.md'), 'w', encoding='utf-8').write("\n".join(L) + "\n")
print('guion:', os.path.join(SALIDA, 'guion.md'))
