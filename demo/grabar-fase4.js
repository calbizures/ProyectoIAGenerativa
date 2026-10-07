// Video corto de las novedades de la Fase 4, una función por sección. Uso:
//   node grabar-fase4.js                    -> todas las secciones
//   node grabar-fase4.js kardex transferencia -> solo esas (inicia sesión fuera de cámara)
// Necesita la base recién instalada (00 a 71): graba una compra desde una orden
// de compra, un vale de caja chica y una transferencia a proveedor.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const { Demo, SALIDA, sql } = require('./lib');
const q2 = n => Number(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const F4 = path.join(SALIDA, 'fase4');
const TOMAS = path.join(F4, 'tomas');
const COMPROBANTE = path.join(F4, 'comprobante-transferencia.png');
const d = new Demo(TOMAS);

async function iniciarSesion(usuario = 'admin') {
  await d.ir('login');
  await d.p.fill('#usuario', usuario); await d.p.fill('#password', 'Demo#2024');
  await d.p.click('button[type=submit]'); await d.p.waitForLoadState('networkidle');
  if (await d.p.$('#sucursal')) { await d.p.selectOption('#sucursal', { index: 1 }); await d.p.click('button[type=submit]'); await d.p.waitForLoadState('networkidle'); }
  await d.espera(600);
}

async function cerrarSesion() {
  await d.p.evaluate(() => { const f = document.querySelector('form[action="logout"]'); if (f) f.submit(); });
  await d.p.waitForURL(u => u.toString().includes('/login'), { timeout: 15000 }).catch(() => {});
  await d.espera(600);
}

// Proveedor con cuenta para transferencia y saldo vencido (el de la demo es PRV04).
function proveedorTransferencia() {
  const [fila] = sql(`SELECT TOP 1 prov.prv_id, prov.prv_codigo FROM dbo.inv_proveedor prov
    JOIN dbo.inv_documento_enc docu ON docu.prv_id = prov.prv_id AND docu.enc_estado = 'G'
    JOIN dbo.inv_proveedor_plan_pago cuot ON cuot.enc_id = docu.enc_id AND cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) > 0
    WHERE prov.prv_gef_id IS NOT NULL AND prov.prv_numero_cuenta IS NOT NULL
    GROUP BY prov.prv_id, prov.prv_codigo ORDER BY CASE WHEN prov.prv_codigo = 'PRV04' THEN 0 ELSE 1 END, COUNT(*) DESC`);
  if (!fila) throw new Error('Ningún proveedor con cuenta para transferencia tiene saldo.');
  return { id: fila[0], codigo: fila[1] };
}

// Orden de compra de la demo: creada y aprobada con las dos firmas (jefe de
// bodega y contador general), lista para recibirse en Compras.
function prepararOrdenCompra() {
  const [[ocp, numero]] = sql(`DECLARE @det dbo.orden_compra_det_type, @id INT = NULL, @num VARCHAR(16), @hoy DATE = CAST(GETDATE() AS DATE),
      @jbod INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'jbodega'), @cgen INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'cgeneral'),
      @prv INT = (SELECT prv_id FROM dbo.inv_proveedor WHERE prv_codigo = 'PRV01'), @bod INT = (SELECT MIN(bod_id) FROM dbo.inv_bodega WHERE bod_estado = 'A');
    INSERT @det SELECT ROW_NUMBER() OVER (ORDER BY pro_codigo), pro_id, pro_descripcion, IIF(pro_codigo = 'LAP-DELL-3520', 6, 4), IIF(pro_codigo = 'LAP-DELL-3520', 4300, 3150)
      FROM dbo.inv_producto WHERE pro_codigo IN ('LAP-DELL-3520', 'LAP-HP-250');
    EXEC dbo.paOrdenCompraGuardar @OcpId = @id OUTPUT, @Fecha = @hoy, @FechaEntrega = @hoy, @PrvId = @prv, @BodId = @bod, @UsuId = 1,
      @Condiciones = 'Entrega en bodega principal', @Detalle = @det, @Numero = @num OUTPUT;
    EXEC dbo.paOrdenCompraAprobarBodega @OcpId = @id, @UsuId = @jbod;
    EXEC dbo.paOrdenCompraAprobar @OcpId = @id, @UsuId = @cgen;
    SELECT @id, @num;`);
  return { ocp, numero };
}

// Comprobante de ejemplo (imagen) para adjuntar a la transferencia; no imita
// a ningún banco real.
async function generarComprobante(autorizacion, monto, cuentaDestino) {
  const nav = await chromium.launch();
  const p = await nav.newPage({ viewport: { width: 760, height: 520 }, deviceScaleFactor: 2 });
  await p.setContent(`<html><body style="margin:0;font-family:Segoe UI,Arial,sans-serif;background:#eef2f7">
    <div style="margin:24px;background:#fff;border-radius:14px;padding:28px 34px;box-shadow:0 4px 18px rgba(13,27,76,.12)">
      <div style="display:flex;justify-content:space-between;align-items:center">
        <div style="font-size:22px;font-weight:700;color:#0d1b4c">Comprobante de transferencia</div>
        <div style="font-size:12px;color:#fff;background:#2e7d32;border-radius:20px;padding:5px 12px">Operación exitosa</div></div>
      <div style="font-size:12px;color:#8a94a6;margin-top:4px">Documento de ejemplo para la demo · sin validez</div>
      <table style="margin-top:22px;width:100%;font-size:15px;border-collapse:collapse">
        ${[['Fecha y hora', new Date().toLocaleDateString('es-GT') + ' 09:42'], ['Número de autorización', autorizacion], ['Cuenta de origen', 'Monetaria 301-0001122-3'],
           ['Cuenta destino', cuentaDestino], ['Beneficiario', 'Proveedor de la demo'], ['Concepto', 'Pago de facturas']]
           .map(([a, b]) => `<tr><td style="padding:8px 0;color:#5f6a7f;border-bottom:1px solid #eef1f5">${a}</td><td style="padding:8px 0;text-align:right;font-weight:600;color:#1c2437;border-bottom:1px solid #eef1f5">${b}</td></tr>`).join('')}
      </table>
      <div style="margin-top:18px;display:flex;justify-content:space-between;align-items:baseline">
        <span style="color:#5f6a7f">Monto transferido</span><span style="font-size:28px;font-weight:700;color:#1565c0">Q ${q2(monto)}</span></div>
    </div></body></html>`);
  await p.screenshot({ path: COMPROBANTE });
  await nav.close();
}

const secciones = {
  async intro() {
    await d.ir('login');
    await d.carta({
      numero: 'Novedades',
      titulo: 'ERP · Fase 4',
      sub: 'Lo nuevo en cartera, compras, inventario, caja, bancos y seguridad.',
      puntos: ['Antigüedad de saldos por vendedor', 'Mantenimiento de permisos', 'Compra desde orden de compra', 'Kardex con costo promedio',
        'Caja chica: vales sin proveedor', 'Pago por transferencia', 'Correo por Gmail', 'Base de datos estandarizada'],
    }, 8000);
  },

  async antiguedad() {
    await d.carta({ numero: '01 · Cuentas por cobrar', titulo: 'Antigüedad de saldos por vendedor', sub: 'Cada vendedor ve su cartera; administración y contabilidad, toda.',
      puntos: ['Clientes a los que el vendedor ha vendido', 'Con todo el saldo del cliente', 'Consulta al elegir el cliente', 'Excel e impresión con el mismo filtro'] }, 4600);
    await d.ir('cxc/antiguedad');
    await d.sinCarta(1000);
    await d.rotulo('01 · Cuentas por cobrar', 'Administrador: todos los clientes',
      'Quien tiene el permiso <b>Antigüedad de todos los clientes</b> (administrador, contador y contador general) ve la cartera completa.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.kpi-fila', 4400); await d.sinResalte();
    await d.rotulo('01 · Cuentas por cobrar', 'Consulta al elegir el cliente',
      'No hace falta pulsar Consultar: al elegir el cliente se muestran sus saldos por rango de días.', { pos: 'abajo-der', espera: false });
    await d.escribir('input[placeholder^="Buscar cliente"]', 'a', 300);
    await d.p.keyboard.press('Enter'); await d.espera(1200);
    await d.clic('.doc-resultado-fila >> nth=1', 1800);
    await d.resaltar('main table', 3600); await d.sinResalte(); await d.sinRotulo();
    // El vendedor entra con su usuario.
    await cerrarSesion();
    await d.rotulo('01 · Cuentas por cobrar', 'Entra un vendedor',
      'Julio Pérez es vendedor (usuario → empleado → vendedor en RRHH).', { pos: 'abajo-izq', espera: false });
    await d.escribir('#usuario', 'jperez');
    await d.escribir('#password', 'Demo#2024', 600);
    await d.clic('button[type=submit]', 1400);
    if (await d.p.$('#sucursal')) { await d.elegir('#sucursal', { index: 1 }, 800); await d.clic('button[type=submit]', 1400); }
    await d.ir('ventas/antiguedad');
    await d.rotulo('01 · Cuentas por cobrar', 'Solo su cartera, con todo el saldo',
      'Ve los clientes a los que <b>él les ha vendido</b>, con el saldo completo de cada uno, aunque parte venga de facturas de otro vendedor. El buscador también se limita a ellos.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.doc-nota', 5600); await d.sinResalte();
    await d.resaltar('main table', 3000); await d.sinResalte(); await d.sinRotulo();
  },

  async permisos() {
    await d.carta({ numero: '02 · Seguridad', titulo: 'Mantenimiento de permisos', sub: 'Cada permiso con dónde se usa, qué roles lo tienen y qué usuarios.',
      puntos: ['Crear, modificar e inactivar', 'Dónde se usa en el menú', 'Asignar o quitar a un rol', 'Usuarios que lo tienen'] }, 4600);
    await cerrarSesion(); await iniciarSesion('admin');
    await d.ir('permisos');
    await d.sinCarta(1000);
    await d.rotulo('02 · Seguridad', 'Permisos',
      'Lista con filtros por texto, módulo y estado, y cuántos roles y usuarios tiene cada uno.', { pos: 'abajo-der', espera: false });
    await d.escribir('.permisos-maestro input[type=search]', 'COMPRAS_ORDEN', 900);
    await d.clic(d.p.locator('.permisos-maestro table').first().locator('tbody tr', { hasText: 'COMPRAS_ORDEN_APROBAR' }).first(), 1400);
    const detalle = d.p.locator('.permisos-maestro > .tarjeta').nth(1);
    const tablas = detalle.locator('table');
    await d.desplazarA(tablas.nth(0), 'center', 1000);
    await d.rotulo('02 · Seguridad', 'Dónde se usa',
      'Las opciones del menú y las acciones dentro de las pantallas que piden este permiso, leídas de la misma aplicación.', { pos: 'abajo-izq', espera: false });
    await d.resaltar(tablas.nth(0), 4600); await d.sinResalte();
    await d.desplazarA(tablas.nth(1), 'center', 1000);
    await d.rotulo('02 · Seguridad', 'Roles y usuarios',
      'Los roles que lo tienen, con <b>Asignar</b> y <b>Quitar</b> desde aquí, y los usuarios que lo reciben por alguno de sus roles.', { pos: 'abajo-izq', espera: false });
    await d.resaltar(tablas.nth(1), 3400);
    await d.resaltar(tablas.nth(2), 3400); await d.sinResalte(); await d.sinRotulo();
  },

  async compraoc() {
    const oc = prepararOrdenCompra();
    await d.carta({ numero: '03 · Compras', titulo: 'Compra desde la orden de compra', sub: 'La orden aprobada por bodega y por el contador general se convierte en compra.',
      puntos: ['Solo órdenes con las dos firmas', 'Lo que llegó con la factura', 'Lo que falta queda pendiente', 'Inventario, cuenta por pagar y póliza'] }, 4600);
    await d.ir('compras/ordenes');
    await d.sinCarta(1000);
    await d.rotulo('03 · Compras', `Orden ${oc.numero} aprobada`,
      'Lleva el <b>visto bueno del jefe de bodega</b> y la <b>aprobación del contador general</b>, dos usuarios distintos.', { pos: 'abajo-der', espera: false });
    await d.resaltar(d.p.locator('main table tbody tr', { hasText: oc.numero }), 4400); await d.sinResalte();
    await d.ir('compras');
    await d.clic('button:has-text("Desde orden de compra")', 1200);
    await d.rotulo('03 · Compras', 'Desde orden de compra',
      'Se elige entre las órdenes aprobadas pendientes de recibir.', { pos: 'arriba-der', espera: false });
    await d.elegir('#compras-desde-orden', String(oc.ocp), 1600);
    await d.escribir('.oc-recepcion input[id^=rec-serie]', 'A', 200);
    await d.escribir('.oc-recepcion input[id^=rec-numero]', '7745', 400);
    const cantidad = d.p.locator('.oc-recepcion input[aria-label^="Cantidad recibida"]').first();
    await d.escribir(cantidad, '4', 300); await cantidad.press('Tab'); await d.espera(600);
    await d.rotulo('03 · Compras', 'Llegó una parte',
      'Se indica lo que llegó con la factura del proveedor: <b>4 de 6</b> laptops Dell. Lo que falta queda pendiente para otra recepción.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.oc-recepcion table', 4800); await d.sinResalte();
    await d.clic('.oc-recepcion button:has-text("Grabar compra")', 2600);
    const err = await d.p.$$eval('.mensaje-error', e => e.map(x => x.textContent.trim()));
    if (err.length) throw new Error('compra desde OC: ' + err.join(' | '));
    await d.rotulo('03 · Compras', 'Compra grabada',
      'Ingreso a bodega con costo promedio, cuenta por pagar y póliza en una sola transacción; la orden queda <b>parcialmente recibida</b>.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.mensaje-ok', 4600); await d.sinResalte(); await d.sinRotulo();
  },

  async kardex() {
    await d.carta({ numero: '04 · Inventario', titulo: 'Kardex', sub: 'Todos los movimientos de un producto, con su costo, para comprobar el costo promedio.',
      puntos: ['Entradas y salidas por documento', 'Costo unitario y costo total', 'Saldo y promedio después de cada línea', 'Comprobado contra lo guardado'] }, 4600);
    await d.ir('existencias');
    await d.sinCarta(1000);
    await d.rotulo('04 · Inventario', 'Existencias por bodega',
      'Cada fila tiene su <b>Kardex</b>; también es una pestaña de la pantalla.', { pos: 'abajo-der', espera: 2600 });
    const fila = d.p.locator('main table tbody tr', { hasText: 'LAP-DELL-3520' }).first();
    await d.clic(fila.locator('button:has-text("Kardex")'), 1800);
    await d.elegir('select[aria-label=Bodega]', '0', 1600);
    await d.rotulo('04 · Inventario', 'Saldo y costo promedio',
      'Entradas, salidas, existencia y costo promedio actual del producto en todas las bodegas.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.kpi-fila', 4000); await d.sinResalte();
    await d.desplazarA('.kardex-tabla', 'start', 1200);
    await d.rotulo('04 · Inventario', 'Movimiento por movimiento',
      'Compra, factura, inventario inicial, ajuste, traslado o devolución: cantidad, <b>costo unitario y costo total</b> de cada línea, y después de ella el saldo, el valor y el promedio. La compra recién recibida aparece al final.', { pos: 'abajo-der', espera: false });
    await d.desplazar(9999, 2600); await d.espera(2600);
    await d.desplazar(0, 1200);
    await d.rotulo('04 · Inventario', 'Comprobado',
      'El cálculo llega a la misma existencia, valor y costo promedio guardados en el producto. Se exporta a <b>Excel</b>.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.doc-nota', 4800); await d.sinResalte(); await d.sinRotulo();
  },

  async cajachica() {
    await d.carta({ numero: '05 · Caja chica', titulo: 'Vales y recibos sin proveedor', sub: 'El proveedor solo se exige en las facturas.',
      puntos: ['Vale: entregado a (opcional)', 'Recibo: emitido por (opcional)', 'Factura con NIT y número', 'Liquidación con su póliza'] }, 4200);
    await d.ir('bancos/caja-chica');
    await d.sinCarta(1000);
    await d.clic('button:has-text("Registrar gasto")', 900);
    await d.elegir('#ccg-tipo', 'V', 900);
    await d.rotulo('05 · Caja chica', 'Vale sin proveedor',
      'En un vale el proveedor pasa a ser <b>Entregado a (opcional)</b>; se puede dejar en blanco.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.campo:has(#ccg-proveedor)', 3800); await d.sinResalte();
    await d.escribir('#ccg-concepto', 'Pasajes de mensajería al centro', 300);
    const viaticos = await d.p.locator('#ccg-cuenta option', { hasText: '5110015' }).first().getAttribute('value');
    await d.elegir('#ccg-cuenta', viaticos, 500);
    await d.escribir('#ccg-total', '35', 500);
    await d.clic('button:has-text("Guardar gasto")', 1600);
    await d.rotulo('05 · Caja chica', 'Registrado',
      'En la lista aparece como <b>Sin proveedor</b> y en la liquidación la línea de la póliza lleva solo el concepto.', { pos: 'abajo-der', espera: false });
    await d.resaltar(d.p.locator('main table tbody tr', { hasText: 'Pasajes de mensajería' }).first(), 4400); await d.sinResalte(); await d.sinRotulo();
  },

  async transferencia() {
    const prv = proveedorTransferencia();
    await d.carta({ numero: '06 · Cuentas por pagar', titulo: 'Pago a proveedores por transferencia', sub: 'Además del cheque: se registra la transferencia ya hecha en la banca electrónica.',
      puntos: ['Número de autorización del banco', 'Comprobante adjunto (PDF o imagen)', 'Póliza Proveedores / Bancos', 'Detalle, comprobante y anulación'] }, 4600);
    await d.ir(`cxp/pagos?prv=${prv.id}`);
    await d.sinCarta(1000);
    const saldos = await d.p.$$eval('table.tabla-cuotas-cobro tbody tr td:nth-child(7)', t => t.map(x => parseFloat(x.textContent.replace(/[^0-9.]/g, ''))));
    const monto = Math.round((saldos[0] + Math.min(1000, (saldos[1] || 0) / 2)) * 100) / 100;
    await d.escribir('#pag-monto', monto.toFixed(2), 500);
    await d.clic('button:has-text("Aplicar a las más antiguas")', 1200);
    await d.desplazarA('#titulo-forma-pago', 'start', 1100);
    await d.rotulo('06 · Cuentas por pagar', 'Cheque o transferencia',
      'Las cuotas se eligen igual que con el cheque; cambia la forma de pago.', { pos: 'arriba-der', espera: 2400 });
    await d.clic('.forma-pago-opciones label:has-text("Transferencia")', 1200);
    await d.rotulo('06 · Cuentas por pagar', 'Cuenta del proveedor propuesta',
      'El banco, el tipo y la cuenta del proveedor se toman de Proveedores; se cambian si se transfirió a otra.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.campo:has(#trf-cuenta-destino)', 3600); await d.sinResalte();
    const autorizacion = '20' + String(Date.now()).slice(-8);
    const cuentaDestino = await d.p.inputValue('#trf-cuenta-destino');
    await generarComprobante(autorizacion, monto, cuentaDestino);
    await d.escribir('#trf-autorizacion', autorizacion, 300);
    await d.escribir('#trf-referencia', 'Banca en línea', 400);
    await d.apuntar('label:has-text("Adjuntar comprobante")'); await d.espera(700);
    await d.p.setInputFiles('#trf-comprobante', COMPROBANTE); await d.espera(1500);
    await d.rotulo('06 · Cuentas por pagar', 'Autorización y comprobante',
      'El número de autorización es obligatorio y <b>no se repite</b> en la misma cuenta. El comprobante del banco (PDF o imagen, hasta 5 MB) queda adjunto; su tipo se comprueba por el contenido.', { pos: 'arriba-der', espera: false });
    await d.resaltar('.formulario-transferencia', 5600); await d.sinResalte();
    await d.clic('button:has-text("Registrar transferencia Q")', 2200);
    const err = await d.p.$$eval('.mensaje-error', e => e.map(x => x.textContent.trim()));
    if (err.length) throw new Error('transferencia: ' + err.join(' | '));
    await d.desplazar(0, 900);
    await d.rotulo('06 · Cuentas por pagar', 'Registrada con su póliza',
      'Correlativo propio <b>TR-</b>; la póliza carga Proveedores (una línea por factura) y abona la cuenta del banco. Entra al estado de cuenta, al flujo de caja y a la conciliación bancaria.', { pos: 'abajo-der', espera: false });
    await d.resaltar('.tarjeta-exito', 5200); await d.sinResalte();
    await d.desplazarA('#titulo-transferencias', 'start', 1200);
    const lista = d.p.locator('.tarjeta:has(#titulo-transferencias)');
    await d.clic(lista.locator('tbody tr >> nth=0 >> button[aria-label="Ver facturas y cuotas pagadas"]'), 1400);
    await d.rotulo('06 · Cuentas por pagar', 'Transferencias registradas',
      'Qué cuotas pagó cada una (abono o cancelación), su comprobante y la anulación con motivo, que devuelve el saldo a las cuotas y anula la póliza.', { pos: 'arriba-der', espera: false });
    await d.resaltar(lista.locator('.tabla-detalle-cheque'), 4400); await d.sinResalte();
    const href = await lista.locator('tbody tr >> nth=0 >> a.boton-icono').getAttribute('href');
    await d.apuntar(lista.locator('tbody tr >> nth=0 >> a.boton-icono')); await d.espera(600);
    await d.ir(href.replace(/^\//, ''));
    await d.p.evaluate(() => { document.body.style.background = '#eef2f7'; const i = document.querySelector('img'); if (i) { i.style.maxHeight = '86vh'; i.style.margin = '4vh auto'; i.style.display = 'block'; } });
    await d.rotulo('06 · Cuentas por pagar', 'El comprobante adjunto',
      'Se abre en el navegador o se descarga; solo con sesión y permiso de cuentas por pagar.', { pos: 'abajo-der', espera: 4000 });
    await d.sinRotulo();
  },

  async correo() {
    await d.carta({ numero: '07 · Correo', titulo: 'Correo saliente por Gmail', sub: 'Por defecto la compañía envía con calbizures@gmail.com.',
      puntos: ['Gmail, Outlook, Microsoft 365, Yahoo', 'Otro servidor SMTP', 'Carpeta para pruebas', 'Contraseña cifrada'] }, 4400);
    await d.ir('general/companias');
    await d.sinCarta(1000);
    await d.clic(d.p.locator('main table tbody tr').first().locator('button[aria-label="Ver detalle"]'), 1400);
    await d.desplazarA('#cia-smtp-proveedor', 'center', 1200);
    await d.rotulo('07 · Correo', 'Gmail por defecto',
      '<b>smtp.gmail.com</b>, puerto 587 con TLS, usuario y remitente calbizures@gmail.com. Gmail pide una <b>contraseña de aplicación</b> (cuenta con verificación en dos pasos).', { pos: 'abajo-der', espera: false });
    await d.resaltar('.campo:has(#cia-smtp-proveedor)', 3000);
    await d.resaltar('.campo:has(#cia-smtp-servidor)', 2400);
    await d.resaltar('.campo:has(#cia-smtp-remitente)', 2600); await d.sinResalte();
    await d.rotulo('07 · Correo', 'Otros tipos de salida',
      'Al cambiar el tipo se llenan servidor y puerto; con <b>Carpeta</b> los correos se guardan como archivos .eml para probar sin enviar.', { pos: 'abajo-der', espera: false });
    await d.elegir('#cia-smtp-proveedor', 'OFFICE365', 1800);
    await d.resaltar('.campo:has(#cia-smtp-servidor)', 2200); await d.sinResalte();
    await d.elegir('#cia-smtp-proveedor', 'GMAIL', 1600);
    await d.sinRotulo();
  },

  async cierre() {
    await d.carta({ numero: 'Fase 4', titulo: 'Base de datos estandarizada',
      sub: 'Los 70 procedimientos y funciones sp_ / fn_ pasaron al estándar pa / fn con PascalCase en nombres, parámetros y alias; las bases anteriores se actualizan con el script 66.',
      puntos: ['Scripts 66 a 71', 'Mismo resultado en base nueva o actualizada', '19 controles de integridad en OK', 'Accesible en computadora y celular'] }, 9000);
  },
};

(async () => {
  const pedidas = process.argv.slice(2);
  const lista = pedidas.length ? pedidas : Object.keys(secciones);
  fs.mkdirSync(TOMAS, { recursive: true });
  await d.iniciar();
  await iniciarSesion('admin');
  await d.p.evaluate(() => sessionStorage.clear());
  let total = 0;
  for (const nombre of lista) {
    const orden = String(Object.keys(secciones).indexOf(nombre)).padStart(2, '0');
    await d.grabar(orden + '_' + nombre);
    try { await secciones[nombre](); }
    catch (e) { console.log('  ERROR en', nombre, e.message.split('\n')[0]); await d.p.screenshot({ path: path.join(TOMAS, 'error_' + nombre + '.png') }); }
    total += await d.parar();
  }
  console.log('total', total.toFixed(1), 's · errores JS:', d.errores.length ? d.errores : 'ninguno');
  await d.cerrar();
})();
