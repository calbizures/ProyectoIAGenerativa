// Video comercial de 3 minutos para una tienda de pinturas (para enviar por
// WhatsApp). Empresa ficticia "Pinturas del Valle, S.A." con los datos de
// datos-pinturas.sql. Una función por sección:
//   node pinturas/grabar-pinturas.js                 -> todas
//   node pinturas/grabar-pinturas.js mostrador       -> solo esa (inicia sesión fuera de cámara)
// Graba una factura de contado, un traslado entre tiendas, una cotización con
// su factura al crédito y un cobro: use una base recién preparada.
const fs = require('fs');
const path = require('path');
const { Demo, SALIDA, sql } = require('../lib');

const DIR = path.join(SALIDA, 'pinturas');
const TOMAS = path.join(DIR, 'tomas');
const d = new Demo(TOMAS);
const T = 'Pinturas del Valle';

async function iniciarSesion() {
  await d.ir('login');
  await d.p.fill('#usuario', 'admin'); await d.p.fill('#password', 'Demo#2024');
  await d.p.click('button[type=submit]'); await d.p.waitForLoadState('networkidle');
  if (await d.p.$('#sucursal')) { await d.p.selectOption('#sucursal', { label: 'Tienda Central Zona 1' }); await d.p.click('button[type=submit]'); await d.p.waitForLoadState('networkidle'); }
  await d.espera(600);
}

async function sinErrores(que) {
  const err = await d.p.$$eval('.mensaje-error', e => e.map(x => x.textContent.trim()).filter(Boolean));
  if (err.length) throw new Error(que + ': ' + err.join(' | '));
}

// Busca un producto en el detalle del documento y lo agrega con la cantidad
// indicada. En la factura el resultado es una fila que se toca; en la
// cotización, una tabla con el botón de agregar.
async function agregarProducto(busqueda, descripcion, cantidad, boton) {
  const campo = 'main input[aria-label="Buscar producto por código o descripción"]';
  await d.escribir(campo, busqueda, 200);
  await d.p.keyboard.press('Enter'); await d.espera(900);
  // Se centra el resultado: la barra de estado fija del pie taparía el botón.
  const fila = boton ? d.p.locator('table.tabla-compacta tbody tr', { hasText: descripcion }).first()
    : d.p.locator('.doc-buscador-resultados .doc-resultado-fila', { hasText: descripcion }).first();
  await d.desplazarA(fila, 'center', 500);
  await d.clic(boton ? fila.locator(boton) : fila, 900);
  if (cantidad > 1) {
    const entrada = d.p.locator('main input[aria-label="Cantidad"]').last();  // la línea recién agregada
    await llenar(entrada, cantidad, 500);
  }
}

// Campos numéricos que recalculan en cada tecla: se llenan de una vez.
async function llenar(sel, valor, despues = 600) {
  const l = d.loc(sel);
  await d.clic(l, 200); await l.fill(String(valor)); await d.espera(300);
  await l.press('Tab'); await d.espera(despues);
}

const secciones = {
  async portada() {
    await d.ir('');
    await d.carta({
      numero: 'Para tiendas de pinturas',
      titulo: 'Su tienda, en orden',
      sub: 'Ventas en mostrador con factura electrónica, crédito a contratistas e inventario por tienda. En la web, desde cualquier computadora o celular.',
      puntos: ['Factura FEL en segundos', 'Vuelto calculado en caja', 'Crédito con límite y cuotas', 'Existencias de cada tienda'],
    }, 6400);
  },

  async mostrador() {
    await d.carta({ numero: '01 · Venta en tienda', titulo: 'Mostrador y caja', sub: 'Un cliente lleva pintura para su casa y paga en efectivo.',
      puntos: ['Búsqueda por nombre o código', 'Consumidor final con un clic', 'Vuelto calculado', 'FEL certificada al grabar'] }, 3400);
    await d.ir('facturas');
    await d.sinCarta(900);
    await d.clic('button:has-text("Nueva factura")', 1000);
    await d.rotulo('01 · Venta en tienda', 'Nueva factura',
      'Se escribe parte del nombre o se <b>escanea el código</b>; el precio de la tienda sale solo.', { pos: 'arriba-der', espera: false });
    await agregarProducto('látex', 'interior blanco mate (galón)', 2);
    await agregarProducto('brocha', 'Brocha de 3 pulgadas', 1);
    await d.sinRotulo(200);
    await d.desplazarA('button:has-text("C/F")', 'center', 700);
    await d.clic('button:has-text("C/F")', 900);
    await d.rotulo('01 · Venta en tienda', 'Consumidor final',
      'Con un clic, o con el NIT del cliente: si no está registrado, se consulta a SAT y se registra solo.', { pos: 'arriba-der', espera: 3400 });
    await d.desplazarA('.calculo-vuelto', 'center', 900);
    await llenar('#facturas-efectivo-recibido', 500, 900);
    await d.rotulo('01 · Venta en tienda', 'Vuelto calculado',
      'El cajero anota cuánto le dieron (o toca el billete) y el sistema le dice <b>cuánto devolver</b>.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.calculo-vuelto', 3600); await d.sinResalte(); await d.sinRotulo();
    await d.desplazarA('button:has-text("Grabar factura")', 'center', 600);
    await d.clic('button:has-text("Grabar factura")', 3200);
    await sinErrores('factura de contado');
    await d.desplazarA('.fel-resumen', 'center', 900);
    await d.rotulo('01 · Venta en tienda', 'Factura electrónica lista',
      'Certificada ante SAT al grabar: <b>serie, número y autorización</b>. Se imprime en ticket o se envía por correo; el inventario y la caja se actualizan solos.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.fel-resumen', 5200); await d.sinResalte(); await d.sinRotulo();
  },

  async inventario() {
    await d.carta({ numero: '02 · Inventario por tienda', titulo: 'Cada tienda con su existencia', sub: 'Lo que hay en la tienda Central, en Mixco y en la bodega de reserva.',
      puntos: ['Existencias por bodega', 'Kardex con costo promedio', 'Traslados entre tiendas', 'Conteo físico con ajuste'] }, 3400);
    await d.ir('existencias');
    await d.sinCarta(900);
    await d.escribir('input[placeholder="Buscar por código o descripción"]', 'Impermeabilizante', 400);
    await d.espera(800);
    await d.rotulo('02 · Inventario por tienda', 'Existencias por tienda',
      'En <b>Mixco quedan solo 3 cubetas</b> de impermeabilizante; en la bodega de reserva hay 40.', { pos: 'abajo-der', espera: false });
    await d.resaltar(d.p.locator('main table tbody tr', { hasText: 'Bodega Tienda Mixco' }).filter({ hasText: 'cubeta' }).first(), 4200); await d.sinResalte(); await d.sinRotulo();
    await d.ir('inventario/traslados');
    await d.clic('button:has-text("Nuevo traslado")', 1000);
    await d.elegir('#tra-origen', { label: 'Tienda Central Zona 1 · Bodega de reserva Central' }, 700);
    await d.elegir('#tra-destino', { label: 'Tienda Mixco · Bodega Tienda Mixco' }, 700);
    await d.escribir('#tra-obs', 'Reposición para Mixco', 300);
    await d.escribir('#tra-buscar', 'Impermeabilizante', 200);
    await d.p.keyboard.press('Enter'); await d.espera(1000);
    await d.clic(d.p.locator('table.tabla-compacta tbody tr', { hasText: 'cubeta' }).first().locator('button[aria-label="Agregar al traslado"]'), 900);
    const cant = d.p.locator('input[aria-label="Cantidad de PDV-IMP-ACR-CUB"]');
    await llenar(cant, 15, 500);
    await d.rotulo('02 · Inventario por tienda', 'Traslado entre tiendas',
      'Sale de la reserva y queda <b>en tránsito</b> hasta que Mixco confirma lo que recibió; lo que falte se devuelve o se registra como pérdida.', { pos: 'arriba-der', espera: 4600 });
    await d.clic('button:has-text("Enviar traslado")', 2000);
    await sinErrores('traslado');
    await d.resaltar(d.p.locator('main table tbody tr').first(), 3000); await d.sinResalte(); await d.sinRotulo();
  },

  async contratista() {
    await d.carta({ numero: '03 · Crédito a contratistas', titulo: 'Cotice, facture y cobre', sub: 'Una constructora pide material para impermeabilizar y pintar un edificio.',
      puntos: ['Cotización con vigencia', 'Factura al crédito con cuotas', 'Límite de crédito controlado', 'Antigüedad y cobros'] }, 3400);
    await d.ir('ventas/cotizaciones');
    await d.sinCarta(900);
    await d.clic('button:has-text("Nueva cotización")', 1000);
    await d.escribir('input[placeholder^="Buscar cliente"]', 'Altamira');
    await d.p.keyboard.press('Enter'); await d.espera(1000);
    await d.clic('button[aria-label="Elegir el cliente"]', 1000);
    await d.rotulo('03 · Crédito a contratistas', 'Cotización para la constructora',
      'Con los precios de lista y la vigencia de la oferta. Se imprime o se envía por correo en PDF.', { pos: 'arriba-der', espera: false });
    await agregarProducto('Impermeabilizante', 'techos (cubeta 5 gal)', 12, 'button[aria-label="Agregar a la cotización"]');
    await agregarProducto('exterior', 'exterior colores (cubeta 5 gal)', 8, 'button[aria-label="Agregar a la cotización"]');
    await d.resaltar('.resumen-totales', 2600); await d.sinResalte(); await d.sinRotulo();
    await d.clic('button:has-text("Grabar cotización")', 2000);
    await sinErrores('cotización');
    await d.clic('button:has-text("Convertir en factura")', 2200);
    await d.desplazarA('#facturas-condicionpagofactura', 'center', 900);
    await d.elegir('#facturas-condicionpagofactura', 'credito', 1000);
    await d.escribir('#facturas-factura-numerocuotas', '3', 300);
    await d.p.press('#facturas-factura-numerocuotas', 'Tab'); await d.espera(400);
    const primerPago = new Date(Date.now() + 30 * 864e5).toISOString().slice(0, 10);
    await d.apuntar('#facturas-factura-fechaprimerpago');
    await d.p.fill('#facturas-factura-fechaprimerpago', primerPago); await d.p.press('#facturas-factura-fechaprimerpago', 'Tab'); await d.espera(600);
    await d.rotulo('03 · Crédito a contratistas', 'Al crédito, en 3 cuotas',
      'Se ven el <b>límite, el saldo y el crédito disponible</b>; si la venta lo excede, no se puede grabar.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.credito-resumen', 4400); await d.sinResalte(); await d.sinRotulo();
    await d.desplazarA('button:has-text("Grabar factura")', 'center', 600);
    await d.clic('button:has-text("Grabar factura")', 3000);
    await sinErrores('factura al crédito');
    await d.ir('cxc/antiguedad');
    await d.rotulo('03 · Crédito a contratistas', 'Antigüedad de saldos',
      'La factura ya está en la cartera de la constructora, con lo que debe por días de atraso. En Excel o impreso.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.kpi-fila', 2400);
    await d.resaltar(d.p.locator('main table tbody tr', { hasText: 'Altamira' }).first(), 3600); await d.sinResalte(); await d.sinRotulo();
    await d.ir('cxc/cobros');
    await d.escribir('input[placeholder^="Buscar cliente"]', 'Altamira');
    await d.p.keyboard.press('Enter'); await d.espera(1000);
    await d.clic('.doc-buscador-resultados .doc-resultado-fila', 1400);
    const saldos = await d.p.$$eval('table.tabla-cuotas-cobro tbody tr td:nth-child(6)', t => t.map(x => parseFloat(x.textContent.replace(/[^0-9.]/g, ''))));
    const monto = (saldos[0] + (saldos[1] || 0)).toFixed(2);
    await llenar('#cob-recibido', monto, 500);
    await d.clic('button:has-text("Aplicar a las más antiguas")', 1000);
    await d.rotulo('03 · Crédito a contratistas', 'Cobro de cuotas',
      'El abono se aplica a las cuotas <b>más antiguas</b>; un solo recibo, en efectivo, cheque, tarjeta o transferencia.', { pos: 'arriba-der', espera: false });
    await d.resaltar('table.tabla-cuotas-cobro', 3000); await d.sinResalte();
    await d.desplazarA('#titulo-formas', 'start', 800);
    await d.clic('button:has-text("Registrar cobro Q")', 2000);
    await sinErrores('cobro');
    await d.desplazar(0, 700);
    await d.resaltar('.tarjeta-exito', 2400); await d.sinResalte(); await d.sinRotulo();
  },

  async cierre() {
    await d.carta({ titulo: 'Pruébelo en su tienda',
      sub: 'Ventas, caja, crédito, inventario, compras, bancos y contabilidad en un solo sistema, en la nube o en su propio servidor.',
      puntos: ['Factura electrónica FEL', 'Una o varias tiendas', 'Acceso por usuario y permisos', 'Soporte en Guatemala'] }, 8000);
  },
};

(async () => {
  const pedidas = process.argv.slice(2);
  const nombres = Object.keys(secciones);
  const lista = pedidas.length ? pedidas : nombres;
  fs.mkdirSync(TOMAS, { recursive: true });
  await d.iniciar();
  await iniciarSesion();
  await d.p.evaluate(() => sessionStorage.removeItem('demo-carta'));
  let total = 0;
  for (const nombre of lista) {
    const orden = String(nombres.indexOf(nombre)).padStart(2, '0');
    await d.grabar(orden + '_' + nombre);
    try { await secciones[nombre](); }
    catch (e) { console.log('  ERROR en', nombre, e.message.split('\n')[0]); await d.p.screenshot({ path: path.join(TOMAS, 'error_' + nombre + '.png') }); }
    total += await d.parar();
  }
  console.log('total', total.toFixed(1), 's · errores JS:', d.errores.length ? d.errores : 'ninguno');
  await d.cerrar();
})();
