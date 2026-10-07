# Demo del producto

Generadores del video de demostración del ERP, de su guion y de la
presentación. Todo se produce a partir de la aplicación real: un navegador
automatizado (Playwright) recorre las pantallas; graba de verdad la factura, el
cobro, la compra, una toma de inventario físico, un cheque a proveedor por
varias facturas, un depósito, un cheque libre y el logotipo de la empresa, y
cada paso lleva un rótulo que explica lo que se ve.

| Archivo | Qué hace |
|---|---|
| `generar.sh` | Corre todo el proceso de principio a fin |
| `grabar.js` | El recorrido: 15 secciones, de la portada al cierre |
| `lib.js` | Motor de grabación: navegador a 1920×1080, captura de cuadros por CDP y codificación con ffmpeg a 30 fps |
| `overlay.js` | Capa que se inyecta en cada página: cursor visible, rótulos, cortinillas con el logo, resaltado y panel de XML |
| `musica.py` | Pista musical original (pad, arpegio, bajo y pulso ligero, 96 BPM); sin derechos de terceros |
| `guion.py` | Guion con los tiempos de cada cortinilla y rótulo, tomado de la grabación |
| `capturas.js` | Capturas limpias para la presentación |
| `deck.js` | Presentación PPTX de 18 diapositivas con notas del orador |
| `logo-empresa-demo.png` | Logotipo de ejemplo de la compañía de prueba, que la demo carga en General › Compañías |
| `guion.md` | Guion de la última versión generada |
| `generar-fase4.sh`, `grabar-fase4.js`, `capturas-fase4.js`, `deck-fase4.js` | Video corto de novedades de la Fase 4, con su guion y su presentación (ver abajo) |

## Requisitos

- La base `erp_db` **recién instalada** (scripts `00` a `43`) en un contenedor
  Docker de SQL Server. La demo graba documentos y carga el logotipo, así que
  cada corrida debe empezar con la base limpia.
- La aplicación corriendo (por defecto en `http://localhost:5273`).
- Node.js 18 o superior, Python 3 con `numpy` y `scipy`, y `ffmpeg`.
- Chromium para Playwright 1.56 (`npx playwright install chromium` si no está).

## Uso

```bash
cd demo
SA_PASSWORD='<clave de sa>' ./generar.sh
```

Variables opcionales:

| Variable | Por defecto | Uso |
|---|---|---|
| `ERP_URL` | `http://localhost:5273` | Dirección de la aplicación |
| `SQL_CONTENEDOR` | `erpsql` | Contenedor de SQL Server (para `docker exec … sqlcmd`) |
| `SALIDA` | `demo/salida` | Carpeta de resultados (ignorada por git) |
| `FFMPEG` | `ffmpeg` | Ejecutable de ffmpeg |

Resultado en `salida/`:

- `Demo ERP - Servicios Informaticos Integrados.mp4`: 1080p, música normalizada a −18 LUFS.
- `Demo ERP - liviano.mp4`: la misma, más liviana, para compartir por correo o chat.
- `guion.md` y `Demo ERP - Servicios Informaticos Integrados.pptx`.
- `tomas/`: un MP4 y una línea de tiempo por sección.

Para regrabar solo algunas secciones: `node grabar.js factura fel` (inicia
sesión fuera de cámara). Las secciones que graban datos (factura, cxc,
compras, inventario, caja, bancos y admin) dependen del estado de la base.

## Video de novedades de la Fase 4

Video corto (≈ 5 min) solo con lo nuevo de la Fase 4, aparte del recorrido
completo: antigüedad de saldos por vendedor (entra el vendedor `jperez`),
mantenimiento de permisos, compra desde una orden de compra aprobada con las
dos firmas, kardex, vale de caja chica sin proveedor, pago a proveedor por
transferencia con autorización y comprobante, y correo saliente por Gmail;
cierra con la estandarización de la base de datos.

```bash
cd demo
SA_PASSWORD='<clave de sa>' ./generar-fase4.sh
```

- Necesita la base **recién instalada con los scripts `00` a `71`**: graba de
  verdad la compra desde la orden de compra, el vale y la transferencia. La
  orden de compra se crea y se aprueba (jefe de bodega y contador general)
  con SQL justo antes de grabar su sección.
- El comprobante de la transferencia es una imagen de ejemplo que genera
  `grabar-fase4.js`; no imita a ningún banco.
- Para regrabar solo algunas secciones: `node grabar-fase4.js kardex correo`.
- Resultado en `salida/fase4/`: `ERP - Novedades Fase 4.mp4` (1080p),
  `ERP - Novedades Fase 4 (liviano).mp4`, `guion.md` (con `python3 guion.py fase4`),
  `ERP - Novedades Fase 4.pptx` (12 diapositivas con notas del orador) y las tomas.

## Notas

- El cliente del cobro y los números del costo promedio se leen de la base al
  grabar, porque los datos sintéticos cambian en cada instalación. La
  presentación toma esos mismos números de `salida/datos_demo.json`.
- La factura de ejemplo usa Q5,200 + Q448 para que el total con IVA sea exacto.
- La factura electrónica se certifica con el simulador (sin validez fiscal).
- El usuario de la demo es `admin` / `Demo#2024`, el de los datos de prueba.
