# Prueba de carga: 10 usuarios simultáneos

Verifica que el sistema soporte 10 usuarios trabajando a la vez **sin colisiones
transaccionales** (números repetidos, existencias o saldos inconsistentes,
bloqueos mutuos) y mide **cuánto se degrada el tiempo de respuesta**.

> **Solo en una base de prueba.** Crea los usuarios `prueba01` a `prueba10`
> (con la misma contraseña que `admin`), abre la caja 2 y graba documentos
> reales: facturas, cobros y compras. Úsala sobre una copia de la base o sobre
> una instalación con los datos de demostración, nunca en producción.

## Qué hace cada usuario

| Usuarios | Perfil | Qué hace |
|---|---|---|
| 1–4 | Vendedor | Facturas a crédito con los mismos 5 productos (compiten por la existencia y el correlativo) |
| 5–6 | Cajero | Facturas de contado en efectivo (caja 1 y caja 2) |
| 7–8 | Cobrador | Cobros de cuotas tomadas del mismo grupo (a propósito intentan cobrar la misma cuota a la vez) |
| 9 | Compras | Compras de esos 5 productos (suben la existencia que bajan los vendedores) |
| 10 | Contador | Balanza, libro diario, antigüedad de saldos, tablero de ventas y existencias |

Además, la prueba de **sobreventa** pone a los 10 usuarios a pedir, en el
mismo segundo, las últimas unidades de un producto: solo pueden pasar las que
alcanzan y ninguna bodega puede quedar en negativo.

## 1. Prueba transaccional (base de datos)

Requiere `sqlcmd`. Desde esta carpeta:

```powershell
# Windows, usuario de SQL
.\correr.ps1 -Servidor localhost -Usuario sa -Clave 'su_clave'
# Windows, autenticación de Windows
.\correr.ps1 -Servidor localhost
```

```bash
# Linux o macOS
SERVIDOR=localhost USUARIO=sa CLAVE='su_clave' ./correr.sh
```

Corre en orden:

1. `01_preparar.sql`: crea la base `prueba_carga` (resultados), los 10
   usuarios y la apertura de la caja 2, y toma la foto de existencias.
2. Línea base: cada perfil solo, uno tras otro (30 operaciones).
3. Los 10 usuarios al mismo tiempo (100 operaciones cada uno; se cambia con
   `-Operaciones` o con el primer argumento de `correr.sh`).
4. `03_ultimas_unidades.sql`: la prueba de sobreventa.
5. `04_verificar.sql`: deja el resultado en `resultado.txt`.

### Cómo leer `resultado.txt`

- **1. Tiempos**: promedio, máximo y percentil 95 por operación, solo y con
  10 usuarios.
- **2. Rechazadas**: deben ser solo reglas de negocio. Son normales:
  - *El saldo de una de las cuotas cambió…* (53211) y *supera su saldo*
    (53206): dos cobradores sobre la misma cuota; el segundo se rechaza.
  - *Excede el límite de crédito* (53226): los vendedores llenan el crédito de
    los clientes; aparece más cada vez que se repite la prueba.
  - Error 547 `CK_inv_existencia_no_negativa` en la sobreventa: la base
    rechazó la venta que dejaría la bodega en negativo. En la aplicación el
    usuario ve *"No hay existencia suficiente… otro usuario vendió al mismo
    tiempo"*.
- **3. Bloqueos mutuos y esperas vencidas**: deben ser **0**.
- **4. Consistencia**: todo en **0**.
- **5. Existencias**: todas las filas en **OK** (existencia inicial + compras
  − ventas de la prueba = existencia actual).
- **6. Controles de integridad**: los 19 en **OK**.

Al terminar, `05_limpiar.sql` borra la base `prueba_carga` e inactiva los
usuarios de prueba (los documentos grabados quedan en la base).

## 2. Prueba de la aplicación web

Con la aplicación corriendo y después de `01_preparar.sql` (para que existan
los usuarios), desde esta carpeta:

```bash
npm install
npx playwright install chromium     # la primera vez
node http.js 1 5 solo               # tiempos del servidor con un usuario
node http.js 10 5 simultaneo        # ... con 10 usuarios a la vez
node web.js 10 3 simultaneo         # 10 navegadores reales
```

Si la aplicación no está en `http://localhost:5273`, defina `ERP_URL`
(por ejemplo `ERP_URL=https://servidor:7138`).

- `http.js` pide las pantallas con la sesión de cada usuario, sin dibujarlas:
  mide el tiempo del servidor (consultas y armado de la página) y las páginas
  por segundo.
- `web.js` abre un navegador por usuario: inicia sesión, recorre pantallas de
  uso diario y graba una factura de contado desde la pantalla en cada vuelta.
  Mide el tiempo completo que vería el usuario. Correr 10 navegadores en la
  misma computadora la satura; para medir lo que verá cada usuario, reparta
  los navegadores entre varias computadoras o use `http.js`.

## Resultado de referencia

En una máquina de 4 núcleos (aplicación, SQL Server y navegadores juntos), con
los datos de demostración:

- 0 bloqueos mutuos, 0 números duplicados, existencias exactas y los 19
  controles de integridad en OK.
- Grabar una factura en la base: 6 ms promedio con un usuario y 50 ms con 10
  (p95 160 ms).
- Pantallas generadas por el servidor: p95 de hasta 335 ms con 10 usuarios sin
  pausas entre operaciones.
- Contabilidad › Libros envía unos 1,8 MB de HTML y tarda unos 4,5 s en el
  navegador aun con un solo usuario: conviene paginarla.
