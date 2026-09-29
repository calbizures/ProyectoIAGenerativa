// Recorrido de la demo, una función por sección. Uso:
//   node grabar.js                 -> todas las secciones
//   node grabar.js factura fel     -> solo esas (inicia sesión fuera de cámara)
const path = require('path');
const { Demo, BASE, SALIDA, sql } = require('./lib');
const q2 = n => Number(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const TOMAS = path.join(SALIDA, 'tomas');
const d = new Demo(TOMAS);
const nuevaFila = '.doc-seccion .doc-buscador-resultados .doc-resultado-fila';

async function iniciarSesion() {
  await d.ir('login');
  await d.p.fill('#usuario', 'admin'); await d.p.fill('#password', 'Demo#2024');
  await d.p.click('button[type=submit]'); await d.p.waitForLoadState('networkidle');
  if (await d.p.$('#sucursal')) { await d.p.selectOption('#sucursal', '1'); await d.p.click('button[type=submit]'); await d.p.waitForLoadState('networkidle'); }
}

const secciones = {
  async intro() {
    await d.ir('login');
    await d.p.evaluate(() => sessionStorage.clear());
    await d.carta({
      titulo: 'ERP · Servicios Informáticos Integrados',
      sub: 'Recorrido por el producto: de la venta a la contabilidad, en una sola plataforma web.',
      puntos: ['Tableros gerenciales', 'Facturación con FEL', 'Cuentas por cobrar y pagar', 'Compras e inventario', 'Caja y bancos', 'Contabilidad automática', 'Recursos humanos', 'Seguridad por roles'],
    }, 7500);
  },

  async acceso() {
    await d.sinCarta(1100);
    await d.rotulo('01 · Acceso', 'Inicio de sesión seguro',
      'Cada persona entra con su usuario y contraseña. Las contraseñas se guardan con <b>hash seguro</b>, nunca en texto plano.', { pos: 'abajo-izq', espera: 2200 });
    await d.escribir('#usuario', 'admin');
    await d.escribir('#password', 'Demo#2024', 900);
    await d.clic('button[type=submit]', 1400);
    await d.rotulo('01 · Acceso', 'Sucursal de trabajo',
      'Se elige la sucursal en la que se trabajará; solo aparecen las asignadas al usuario. La caja, las bodegas y la factura electrónica toman ese dato.', { pos: 'abajo-izq', espera: 2600 });
    await d.elegir('#sucursal', '1', 1200);
    await d.clic('button[type=submit]', 1600);
    await d.rotulo('01 · Acceso', 'Menú según permisos',
      'El menú muestra solo los módulos que el rol del usuario puede usar. La barra inferior indica sucursal, usuario y base de datos.', { pos: 'abajo-der', espera: false });
    await d.resaltar('#menu-principal', 2600);
    await d.resaltar('.barra-estado', 2800);
    await d.sinResalte(); await d.sinRotulo();
  },

  async tableros() {
    await d.carta({ numero: '02 · Tableros', titulo: 'Tableros gerenciales', sub: 'La información para decidir, al día y en una sola pantalla.',
      puntos: ['Ventas y margen bruto', 'Recuperación de cartera', 'Compras y compromisos', 'Filtros por período y sucursal'] }, 4200);
    await d.ir('tableros');
    await d.sinCarta(1000);
    await d.rotulo('02 · Tableros', 'Indicadores del período',
      'Ventas netas sin IVA, margen bruto calculado con el <b>costo real de cada línea</b>, número de facturas y notas de crédito.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.kpi-grilla', 5200); await d.sinResalte();
    const franjas = d.p.locator('.grafico-franja');
    const n = await franjas.count();
    await d.rotulo('02 · Tableros', 'Detalle al pasar el puntero',
      'Cada columna muestra costo, margen y total del mes. Todos los gráficos tienen también una <b>vista de tabla</b>.', { pos: 'abajo-izq', espera: false });
    for (let i = Math.max(0, n - 5); i < n; i++) { await d.apuntar(franjas.nth(i)); await d.espera(1100); }
    await d.rotulo('02 · Tableros', 'Del mes al día',
      'Un clic en un mes muestra sus ventas día por día; «Volver» regresa a la vista mensual.', { pos: 'abajo-izq', espera: false });
    await d.clic(franjas.nth(n - 1), 2600);
    await d.apuntar(d.p.locator('.grafico-franja').nth(3)); await d.espera(1400);
    await d.clic('button:has-text("Volver")', 1600);
    await d.sinRotulo();
    await d.desplazarA('text=Mejores clientes', 'start', 1400);
    await d.rotulo('02 · Tableros', 'Clientes, productos y vendedores',
      'Rankings del período. Un clic en un cliente abre directamente su estado de cuenta.', { pos: 'abajo-der', espera: 3800 });
    await d.desplazar(0, 1000);
    await d.clic('.pestana-boton:has-text("Recuperación")', 1500);
    await d.rotulo('02 · Tableros', 'Recuperación de cartera',
      'Lo que vencía contra lo cobrado, la antigüedad de los saldos y los clientes con mora.', { pos: 'abajo-der', espera: 2600 });
    await d.desplazar(620, 1400); await d.espera(1800);
    await d.desplazar(0, 900);
    await d.clic('.pestana-boton:has-text("Compras")', 1500);
    await d.rotulo('02 · Tableros', 'Compras y compromisos de pago',
      'Compras del período, saldo por pagar y lo que vence en las <b>próximas 12 semanas</b>, para planificar el flujo de caja.', { pos: 'abajo-der', espera: 2800 });
    await d.desplazar(620, 1400); await d.espera(2400);
    await d.sinRotulo();
  },

  async factura() {
    await d.carta({ numero: '03 · Facturación', titulo: 'Ventas y facturación', sub: 'Una factura completa en pocos pasos, con validaciones en línea.',
      puntos: ['Bienes y servicios juntos', 'Contado o crédito con cuotas', 'Límite de crédito del cliente', 'Certificación FEL al grabar'] }, 4200);
    await d.ir('facturas');
    await d.sinCarta(1000);
    await d.rotulo('03 · Facturación', 'Historial de facturas',
      'Búsqueda por número o cliente, paginación y detalle. Anular exige <b>motivo y confirmación</b>, y revierte inventario y póliza.', { pos: 'abajo-der', espera: 3600 });
    await d.clic('button:has-text("Nueva factura")', 1200);
    await d.rotulo('03 · Facturación', 'Nueva factura',
      'El cliente se busca por código, nombre o NIT; si no existe se da de alta sin salir de la factura.', { pos: 'abajo-der', espera: false });
    await d.escribir('input[placeholder^="Buscar cliente"]', 'Suárez');
    await d.p.keyboard.press('Enter'); await d.espera(1200);
    await d.clic('.doc-buscador-resultados .doc-resultado-fila', 1200);
    await d.elegir('.campo:has(label:has-text("Bodega")) select', { index: 1 }, 900);
    await d.escribir('input[placeholder^="Buscar producto por código"]', 'Dell');
    await d.p.keyboard.press('Enter'); await d.espera(1200);
    await d.clic(nuevaFila, 1200);
    await d.clic('button:has-text("Agregar servicio")', 900);
    await d.escribir('input[placeholder="Describa el servicio"]', 'Instalación y configuración del equipo');
    await d.escribir(d.p.locator('input[aria-label="Precio unitario"]').last(), '448', 800);
    await d.p.locator('input[aria-label="Precio unitario"]').last().press('Tab'); await d.espera(700);
    await d.rotulo('03 · Facturación', 'Bienes y servicios en la misma factura',
      'La columna <b>B/S</b> distingue productos de inventario y servicios. Los precios incluyen IVA y los totales se calculan al instante.', { pos: 'arriba-der', espera: false });
    await d.resaltar('table.doc-tabla', 4800); await d.sinResalte();
    await d.desplazarA('.doc-totales', 'center', 1200);
    await d.elegir('select:has(option[value=credito])', 'credito', 1200);
    await d.escribir('.campo:has(label:has-text("Número de cuotas")) input', '3', 400);
    await d.clic('.campo:has(label:has-text("primer pago")) input', 300);
    await d.p.locator('.campo:has(label:has-text("primer pago")) input').fill('2026-10-28'); await d.espera(400);
    await d.p.keyboard.press('Tab'); await d.espera(900);
    await d.rotulo('03 · Facturación', 'Venta al crédito con límite',
      'Se muestran límite, saldo y crédito disponible del cliente. Si el monto a financiar lo excede, <b>no se puede grabar</b>.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.credito-resumen', 5200); await d.sinResalte();
    await d.clic('.pestana-boton:has-text("Plan de pagos")', 900);
    await d.desplazarA('.doc-card-footer', 'end', 1000);
    await d.rotulo('03 · Facturación', 'Plan de pagos',
      'Las cuotas se generan al grabar y alimentan cuentas por cobrar, la antigüedad de saldos y el tablero de cartera.', { pos: 'arriba-der', espera: 3800 });
    await d.desplazarA('.doc-card-footer', 'center', 900);
    await d.clic('button:has-text("Grabar factura")', 3200);
    await d.desplazarA('.fel-resumen', 'center', 1000);
    await d.rotulo('03 · Facturación', 'Factura certificada al grabar',
      'Al grabar se envía al certificador y se recibe la <b>autorización (UUID), serie y número</b> de SAT. Si el certificador no responde, la factura queda grabada como pendiente y se reintenta sola.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.fel-resumen', 6200); await d.sinResalte(); await d.sinRotulo();
  },

  async fel() {
    await d.carta({ numero: '04 · Factura electrónica', titulo: 'FEL parametrizada', sub: 'Cumplimiento con SAT sin depender de un proveedor fijo.',
      puntos: ['INFILE o simulador de pruebas', 'XML armado desde parámetros', 'Reintento automático', 'Anulación ante SAT con motivo'] }, 4200);
    await d.ir('fel/documentos');
    await d.sinCarta(1000);
    await d.rotulo('04 · Factura electrónica', 'Documentos electrónicos',
      'Estado FEL de cada factura y nota: no enviado, pendiente, rechazado, certificado o anulado ante SAT.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.fel-conteos', 4200); await d.sinResalte();
    await d.rotulo('04 · Factura electrónica', 'Certificación en lote',
      'Los documentos anteriores se envían de una vez, del más antiguo al más reciente; cada nota espera a que su factura de origen esté certificada.', { pos: 'abajo-der', espera: false });
    await d.clic('button:has-text("Enviar pendientes")', 800);
    await d.p.waitForFunction(() => !document.querySelector('button[disabled]:has(.boton-icono-etiqueta)') || true);
    await d.espera(5200);
    await d.desplazar(0, 600);
    await d.resaltar('.fel-conteos', 2600); await d.sinResalte();
    // Detalle del primer documento certificado y su XML
    const fila = d.p.locator('tbody tr:has(.fel-uuid)').first();
    await d.clic(fila.locator('button[aria-label="Ver detalle y bitácora"]'), 1400);
    const encId = await d.p.locator('.fel-detalle a[href*="fel/xml/"]').first().getAttribute('href').then(h => h.split('/')[2]);
    const xml = await d.p.evaluate(async id => (await (await fetch('fel/xml/' + id + '/enviado')).text()), encId);
    await d.rotulo('04 · Factura electrónica', 'XML y bitácora',
      'Se guardan el XML enviado y el certificado, descargables, y cada intento queda en la bitácora con su resultado.', { pos: 'abajo-izq', espera: 2600 });
    const recorte = xml.replace(/></g, '>\n<').split('\n').slice(0, 34).join('\n');
    await d.p.evaluate(([t, x]) => window.__demo.panel(t, x), ['DTE enviado al certificador (GTDocumento 0.1)', recorte]);
    await d.marca({ tipo: 'panel', titulo: 'XML del DTE' });
    await d.espera(6200);
    await d.p.evaluate(() => window.__demo.sinPanel()); await d.espera(500);
    await d.ir('fel/configuracion');
    await d.rotulo('04 · Factura electrónica', 'Todo parametrizado',
      'Certificador, ambiente, emisor, establecimientos, frases, tipos de DTE y unidades. Las llaves del certificador se guardan <b>fuera de la base de datos</b>.', { pos: 'abajo-der', espera: 3400 });
    for (const t of ['Frases', 'Establecimientos', 'Tipos de documento']) await d.clic(`.pestana-boton:has-text("${t}")`, 1700);
    await d.sinRotulo();
  },

  async cxc() {
    await d.carta({ numero: '05 · Cuentas por cobrar', titulo: 'Cartera bajo control', sub: 'Del saldo del cliente al recibo impreso.',
      puntos: ['Estado de cuenta y cartera', 'Varias cuotas en un recibo', 'Recibo imprimible y anulable', 'Antigüedad con Excel'] }, 4200);
    await d.ir('cxc/estado-cuenta');
    await d.sinCarta(1000);
    await d.rotulo('05 · Cuentas por cobrar', 'Clientes con saldo',
      'La cartera completa al abrir la pantalla; un clic muestra el estado de cuenta del cliente.', { pos: 'abajo-der', espera: 2800 });
    await d.clic('.cartera-lista tbody tr >> nth=0 >> button.boton-enlace', 1600);
    await d.rotulo('05 · Cuentas por cobrar', 'Estado de cuenta',
      'Facturas, cuotas, cobros y notas con su saldo, más indicadores de lo vencido. Se puede imprimir.', { pos: 'abajo-der', espera: 3600 });
    await d.ir('cxc/cobros');
    await d.rotulo('05 · Cuentas por cobrar', 'Cobro de cuotas',
      'Se busca al cliente y aparecen sus cuotas pendientes, de todas sus facturas.', { pos: 'abajo-der', espera: false });
    // Cliente con más cuotas pendientes (los datos sintéticos varían por instalación)
    const [[codCobro]] = sql(`SELECT TOP 1 clie.cli_codigo FROM dbo.pos_cliente_plan_pagos cuot JOIN dbo.pos_cliente clie ON clie.cli_id = cuot.cli_id
      JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G' WHERE cuot.cpp_saldo_cuota > 0
      GROUP BY clie.cli_codigo ORDER BY COUNT(*) DESC, SUM(cuot.cpp_saldo_cuota)`);
    await d.escribir('input[placeholder^="Buscar cliente"]', codCobro);
    await d.p.keyboard.press('Enter'); await d.espera(1200);
    await d.clic('.doc-buscador-resultados .doc-resultado-fila', 1600);
    const saldos = await d.p.$$eval('table.tabla-cuotas-cobro tbody tr td:nth-child(6)', t => t.map(x => parseFloat(x.textContent.replace(/[^0-9.]/g, ''))));
    const monto = (saldos[0] + saldos[1] + Math.min(150, Math.floor((saldos[2] || 0) / 2))).toFixed(2);
    await d.escribir('#cob-recibido', monto, 700);
    await d.clic('button:has-text("Aplicar a las más antiguas")', 1200);
    await d.rotulo('05 · Cuentas por cobrar', 'Aplicación automática',
      'El monto recibido se reparte entre las cuotas <b>más antiguas</b>; se puede ajustar a mano cuota por cuota.', { pos: 'arriba-der', espera: false });
    await d.resaltar('table.tabla-cuotas-cobro', 4600); await d.sinResalte();
    await d.clic('button:has-text("Registrar cobro Q")', 2000);
    await d.rotulo('05 · Cuentas por cobrar', 'Un recibo, varias cuotas',
      'Se genera un solo recibo con su póliza contable. Mientras la caja siga abierta puede anularse, con motivo.', { pos: 'arriba-der', espera: 3400 });
    const href = await d.p.getAttribute('.tarjeta-exito a[href*="recibos/imprimir"]', 'href');
    await d.ir(href.replace(/^\//, ''));
    await d.rotulo('05 · Cuentas por cobrar', 'Recibo listo para imprimir',
      'Detalle de cuotas aplicadas y formas de pago.', { pos: 'abajo-der', espera: 3200 });
    await d.ir('cxc/antiguedad');
    await d.rotulo('05 · Cuentas por cobrar', 'Antigüedad de saldos',
      'Saldos por rangos de días, por cliente o por factura, con exportación a <b>Excel</b> y vista para imprimir.', { pos: 'abajo-der', espera: 4200 });
    await d.sinRotulo();
  },

  async compras() {
    await d.carta({ numero: '06 · Compras e inventario', titulo: 'Compras con costo real', sub: 'Cada compra actualiza existencias y costo promedio.',
      puntos: ['Compras con descuento', 'Costo promedio ponderado', 'Existencias por bodega', 'Plan de pagos al proveedor'] }, 4200);
    await d.ir('productos');
    await d.sinCarta(1000);
    await d.escribir('input[placeholder="Buscar por descripción"]', 'Dell', 300);
    await d.clic('main button:has-text("Buscar")', 1200);
    await d.rotulo('06 · Compras e inventario', 'Costo antes de la compra',
      'Cada producto lleva su costo promedio, precios por bodega, características y existencias.', { pos: 'abajo-der', espera: false });
    await d.resaltar('main table tbody tr:first-child td.col-monto', 4000); await d.sinResalte();
    const [[costoAntes, cantAntes]] = sql("SELECT CAST(pro_costo_unitario AS DECIMAL(14,2)), CAST(pro_total_cantidad AS INT) FROM dbo.inv_producto WHERE pro_codigo = 'LAP-DELL-3520'");
    await d.ir('compras');
    await d.clic('button:has-text("Nueva compra")', 1200);
    await d.escribir('.campo:has(label:text-is("Serie")) input', 'B', 300);
    await d.escribir('.campo:has(label:text-is("Número")) input', '48213', 300);
    await d.elegir('.campo:has(label:has-text("Bodega")) select', { index: 1 }, 700);
    await d.escribir('input[placeholder^="Buscar proveedor"]', 'PRV01');
    await d.p.keyboard.press('Enter'); await d.espera(1100);
    await d.clic('.doc-buscador-resultados .doc-resultado-fila', 1100);
    await d.escribir('input[placeholder^="Buscar producto por código"]', 'Dell');
    await d.p.keyboard.press('Enter'); await d.espera(1100);
    await d.clic(nuevaFila, 1100);
    const fila = d.p.locator('table.doc-tabla tbody tr').first();
    await d.escribir(fila.locator('input[type=number]').nth(0), '10', 300);
    await d.escribir(fila.locator('input[type=number]').nth(1), '4256', 300);
    await d.escribir(fila.locator('input[type=number]').nth(2), '2240', 300);
    await fila.locator('input[type=number]').nth(2).press('Tab'); await d.espera(700);
    await d.rotulo('06 · Compras e inventario', 'Compra con descuento',
      '10 laptops a Q4,256 con IVA y Q2,240 de descuento. El costo que entra al inventario es <b>neto de descuento y sin IVA</b>: Q3,600 por unidad.', { pos: 'arriba-der', espera: false });
    await d.resaltar('table.doc-tabla', 5600); await d.sinResalte();
    await d.desplazarA('.doc-card-footer', 'end', 1000);
    await d.elegir('select:has(option[value=credito])', 'credito', 900);
    await d.escribir('.campo:has(label:has-text("Número de cuotas")) input', '3', 400);
    await d.clic('.campo:has(label:has-text("primer pago")) input', 300);
    await d.p.locator('.campo:has(label:has-text("primer pago")) input').fill('2026-10-26'); await d.espera(400);
    await d.p.keyboard.press('Tab'); await d.espera(800);
    await d.rotulo('06 · Compras e inventario', 'Crédito del proveedor',
      'Las cuotas al proveedor alimentan cuentas por pagar y los compromisos de pago del tablero.', { pos: 'arriba-der', espera: 3400 });
    await d.desplazarA('.doc-card-footer', 'center', 900);
    await d.clic('button:has-text("Grabar compra")', 2600);
    const errCompra = await d.p.$$eval('.mensaje-error', e => e.map(x => x.textContent.trim()));
    if (errCompra.length) throw new Error('compra: ' + errCompra.join(' | '));
    await d.rotulo('06 · Compras e inventario', 'Grabada: inventario, costo y póliza',
      'En una sola transacción sube la existencia, se recalcula el costo promedio y se genera la póliza de compra.', { pos: 'arriba-der', espera: 3800 });
    await d.ir('productos');
    await d.escribir('input[placeholder="Buscar por descripción"]', 'Dell', 300);
    await d.clic('main button:has-text("Buscar")', 1200);
    await d.rotulo('06 · Compras e inventario', 'Costo promedio actualizado',
      `(Q${q2(costoAntes)} × ${cantAntes} + Q3,600.00 × 10) ÷ ${+cantAntes + 10} = <b>Q${q2(sql("SELECT CAST(pro_costo_unitario AS DECIMAL(14,2)) FROM dbo.inv_producto WHERE pro_codigo = 'LAP-DELL-3520'")[0][0])}</b>. La siguiente venta grabará ese costo en su línea y en la póliza de costo de ventas.`, { pos: 'abajo-der', espera: false });
    await d.resaltar('main table tbody tr:first-child td.col-monto', 6200); await d.sinResalte(); await d.sinRotulo();
  },

  async bancos() {
    await d.carta({ numero: '07 · Proveedores y bancos', titulo: 'Pagos, caja y bancos', sub: 'El dinero que entra y sale, cuadrado todos los días.',
      puntos: ['Pagos con cheque', 'Antigüedad de proveedores', 'Apertura, corte y cierre de caja', 'Depósitos bancarios'] }, 4200);
    await d.ir('cxp/pagos');
    await d.sinCarta(1000);
    await d.rotulo('07 · Proveedores y bancos', 'Pagos con cheque',
      'Se eligen las cuotas del proveedor y se emite el cheque con su póliza. Se puede anular con motivo mientras no se haya cobrado.', { pos: 'abajo-der', espera: false });
    const idxPrv = await d.p.$$eval('main select >> nth=0', s => [...s[0].options].findIndex(o => o.textContent.includes('Tecno')));
    await d.elegir('main select', { index: Math.max(1, idxPrv) }, 2600);
    await d.espera(1600);
    await d.desplazarA('text=Cheques emitidos', 'start', 1200); await d.espera(1600);
    await d.ir('cxp/antiguedad');
    await d.rotulo('07 · Proveedores y bancos', 'Antigüedad de proveedores',
      'Lo que se debe por rangos de vencimiento, por proveedor o por compra.', { pos: 'abajo-der', espera: 2600 });
    await d.clic('button:has-text("Por compra")', 1800);
    await d.ir('caja');
    await d.rotulo('07 · Proveedores y bancos', 'Caja por sucursal',
      'Apertura con monto inicial; no se abre un día nuevo si el anterior quedó sin cerrar.', { pos: 'abajo-der', espera: 3200 });
    await d.clic('.pestana-boton:has-text("Corte")', 1200);
    await d.elegir('.campo:has(label:has-text("Caja abierta")) select', { index: 1 }, 1600);
    await d.rotulo('07 · Proveedores y bancos', 'Corte y cierre con cuadre',
      'El sistema calcula lo esperado por forma de pago; el cajero cuenta lo físico y la diferencia (faltante o sobrante) genera su póliza.', { pos: 'abajo-der', espera: 4400 });
    await d.desplazar(500, 1200); await d.espera(1200); await d.desplazar(0, 800);
    await d.clic('.pestana-boton:has-text("Depósitos")', 1200);
    await d.elegir('.campo:has(label:has-text("Apertura")) select', { index: 1 }, 1400);
    await d.rotulo('07 · Proveedores y bancos', 'Depósitos',
      'El efectivo se deposita en la cuenta de la entidad financiera, con su póliza de banco.', { pos: 'abajo-der', espera: 3200 });
    await d.sinRotulo();
  },

  async contabilidad() {
    await d.carta({ numero: '08 · Contabilidad', titulo: 'Contabilidad automática', sub: 'Cada operación genera su póliza de partida doble, siempre cuadrada.',
      puntos: ['Nomenclatura por nodos', 'Pólizas automáticas', 'Cuentas por concepto', 'Anulaciones reflejadas'] }, 4200);
    await d.ir('contabilidad/nomenclatura');
    await d.sinCarta(1000);
    await d.rotulo('08 · Contabilidad', 'Nomenclatura contable',
      'Catálogo jerárquico: activo, pasivo, capital, ingresos y gastos, mantenido por nodos.', { pos: 'abajo-der', espera: 2400 });
    await d.clic('button:has-text("Expandir todo")', 1400);
    await d.clic('button:has-text("111 CAJA")', 1600);
    await d.rotulo('08 · Contabilidad', 'Cuentas y subcuentas',
      'Cada nodo muestra su código, nivel y si acepta movimientos; se agregan cuentas sin romper la estructura.', { pos: 'abajo-der', espera: 3600 });
    await d.ir('general/cuentas-poliza');
    await d.rotulo('08 · Contabilidad', 'Pólizas automáticas',
      'Venta, compra, cobro, cheque, depósito, cierre de caja, nómina y notas generan su póliza. Aquí se asigna la cuenta contable de cada concepto.', { pos: 'abajo-der', espera: 4800 });
    await d.desplazar(700, 1600); await d.espera(1400);
    await d.sinRotulo();
  },

  async rrhh() {
    await d.carta({ numero: '09 · Recursos humanos', titulo: 'Personas y nómina', sub: 'Estructura organizativa, empleados y planilla integrados con contabilidad.',
      puntos: ['Empleados y plazas', 'Nómina con póliza', 'Unidades organizativas', 'Organigrama'] }, 4200);
    await d.ir('rrhh/empleados');
    await d.sinCarta(1000);
    await d.rotulo('09 · Recursos humanos', 'Empleados',
      'Datos del colaborador, puesto, plaza y unidad organizativa; puede vincularse a su usuario y a su código de vendedor.', { pos: 'abajo-der', espera: 3600 });
    await d.ir('rrhh/nominas');
    await d.rotulo('09 · Recursos humanos', 'Nómina',
      'Ingresos y descuentos por tipo de movimiento; al aprobarla se genera la póliza de planilla.', { pos: 'abajo-der', espera: false });
    await d.clic('button[aria-label="Ver detalle"]', 1800);
    await d.espera(2600);
    await d.ir('rrhh/estructura');
    await d.rotulo('09 · Recursos humanos', 'Estructura organizativa',
      'Unidades anidadas sin límite de niveles, con departamentos, puestos y plazas.', { pos: 'abajo-der', espera: 3000 });
    await d.clic('.pestana-boton:has-text("Organigrama")', 1800);
    await d.rotulo('09 · Recursos humanos', 'Organigrama',
      'Se dibuja solo a partir de la estructura registrada.', { pos: 'abajo-der', espera: 3600 });
    await d.sinRotulo();
  },

  async admin() {
    await d.carta({ numero: '10 · Administración', titulo: 'Seguridad y configuración', sub: 'Cada quien ve y hace solo lo que le corresponde.',
      puntos: ['Roles y permisos', 'Compañías y sucursales', 'Bodegas y unidades', 'Auditoría de cada registro'] }, 4200);
    await d.ir('roles');
    await d.sinCarta(1000);
    await d.rotulo('10 · Administración', 'Roles',
      'Administrador, contador, vendedor, cajero… cada rol agrupa permisos.', { pos: 'abajo-der', espera: 3000 });
    await d.ir('permisos');
    await d.rotulo('10 · Administración', 'Permisos por pantalla',
      'Cada pantalla exige su permiso y los cambios se aplican a las sesiones abiertas en menos de un minuto.', { pos: 'abajo-der', espera: 3600 });
    await d.ir('general/sucursales');
    await d.rotulo('10 · Administración', 'Sucursales y bodegas',
      'Multi-sucursal y multi-bodega. Cada registro guarda quién y cuándo lo creó y lo modificó.', { pos: 'abajo-der', espera: 3800 });
    await d.sinRotulo();
  },

  async cierre() {
    await d.carta({ titulo: 'Servicios Informáticos Integrados',
      sub: 'Un ERP completo en la web: ventas con factura electrónica, cartera, compras, bancos, contabilidad y RRHH.',
      puntos: ['Pólizas automáticas', 'Costos y márgenes reales', 'Tableros para decidir', 'Seguridad por roles y sucursal'] }, 9000);
  },
};

(async () => {
  const pedidas = process.argv.slice(2);
  const lista = pedidas.length ? pedidas : Object.keys(secciones);
  await d.iniciar();
  if (lista[0] !== 'intro' && lista[0] !== 'acceso') await iniciarSesion();
  let total = 0, i = 0;
  for (const nombre of lista) {
    const orden = String(Object.keys(secciones).indexOf(nombre)).padStart(2, '0');
    if (nombre === 'acceso' && lista[0] === 'acceso') { await d.ir('login'); await d.p.evaluate(() => sessionStorage.clear()); await d.p.evaluate(() => window.__demo.carta({ titulo: 'ERP · Servicios Informáticos Integrados' })); await d.espera(1000); }
    await d.grabar(orden + '_' + nombre);
    try { await secciones[nombre](); }
    catch (e) { console.log('  ERROR en', nombre, e.message.split('\n')[0]); await d.p.screenshot({ path: path.join(TOMAS, 'error_' + nombre + '.png') }); }
    total += await d.parar();
    i++;
  }
  console.log('total', total.toFixed(1), 's · errores JS:', d.errores.length ? d.errores : 'ninguno');
  await d.cerrar();
})();
