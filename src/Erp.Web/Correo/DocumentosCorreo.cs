using System.Globalization;
using System.Net;
using Erp.Data.Cuentas;
using Erp.Data.General;
using Erp.Data.Ventas;
using Erp.Web.Reportes;

namespace Erp.Web.Correo;

// Documentos que se envían al correo del cliente con la cuenta de correo de
// la compañía (General › Compañías › Correo saliente): la factura (PDF y, si
// está certificada, el XML de FEL), el recibo de cobro, la cotización y el
// aviso de un pago con boleta verificado o rechazado.
public sealed class DocumentosCorreo(IFacturaRepository facturas, ICotizacionRepository cotizaciones, ICuentasRepository cuentas,
	IGeneralRepository general, CorreoServicio correo)
{
	public const string TipoFactura = "FACTURA";
	public const string TipoRecibo = "RECIBO";
	public const string TipoCotizacion = "COTIZACION";
	public const string TipoBoleta = "BOLETA";

	private static readonly CultureInfo Es = CultureInfo.GetCultureInfo("es-GT");

	// Lo que se envía: destinatario propuesto, asunto, el resumen del cuerpo y los adjuntos.
	public sealed record Documento(string Tipo, int ReferenciaId, int CiaId, string Nombre, string? Para, string Asunto, string Destinatario,
		string Intro, IReadOnlyList<(string Etiqueta, string Valor)> Resumen, IReadOnlyList<CorreoServicio.Adjunto> Adjuntos,
		string Compania, string? Telefono);

	public async Task<Documento?> FacturaAsync(int encId)
	{
		var impresion = await facturas.ConsultarImpresionAsync(encId);
		if (impresion is null) return null;
		var e = impresion.Encabezado;
		var simbolo = e.Simbolo;
		string M(decimal v) => $"{simbolo} {v.ToString("N2", CultureInfo.InvariantCulture)}";
		var emisor = await EmisorAsync(e.CiaId);
		var (cabecera, _) = await facturas.ConsultarPorIdAsync(encId);
		var correoCliente = cabecera?.CliId is int cliId ? (await cuentas.ConsultarDatosEstadoCuentaClienteAsync(cliId))?.Correo : null;
		var numero = e.Uuid is not null && e.SerieDte is not null ? $"{e.SerieDte}-{e.NumeroDte}" : e.NumeroUnico ?? e.NumeroInterno ?? encId.ToString(Es);

		var encabezado = new List<(string, string?)>
		{
			("Cliente", e.NombreReceptor), ("NIT", e.NitReceptor),
			("Dirección", e.DireccionReceptor), ("Fecha de emisión", e.FechaEmision.ToString("dd/MM/yyyy HH:mm", Es)),
			("Condición", e.EsCredito ? $"Crédito{(e.NumeroCuotas is int n ? $", {n} cuota{(n == 1 ? "" : "s")}" : "")}" : "Contado"), ("Moneda", e.Moneda),
			("Vendedor", e.Vendedor), ("Documento interno", e.NumeroUnico)
		};
		if (e.Uuid is not null)
		{
			encabezado.Add(("Autorización", e.Uuid));
			encabezado.Add(("Serie y número", $"{e.SerieDte} · {e.NumeroDte}"));
			encabezado.Add(("Certificación", e.FechaCertificacion?.ToString("dd/MM/yyyy HH:mm:ss", Es)));
			encabezado.Add(("Certificador", e.Certificador));
		}
		var filas = impresion.Lineas.Select(l => new[]
		{
			l.Cantidad.ToString("0.##", Es), l.Unidad, l.Codigo is null ? l.Descripcion : $"{l.Codigo} · {l.Descripcion}",
			M(l.PrecioUnitario), l.Descuento == 0 ? "" : M(l.Descuento), M(l.Total)
		}).ToList();
		var totales = new List<(string, string, bool)>();
		if (e.Descuento > 0) totales.Add(("Descuento", M(e.Descuento), false));
		totales.Add(("IVA incluido", M(e.Iva), false));
		totales.Add(("Total", M(e.Total), true));
		var secciones = new List<(string, IReadOnlyList<string>)>
		{
			("Plan de pagos", impresion.Cuotas.Select(c => $"Cuota {c.Cuota}: {M(c.Monto)}, vence el {c.Vencimiento:dd/MM/yyyy}").ToList()),
			("Pagos recibidos", impresion.Pagos.Select(p => $"{p.Forma}: {M(p.Monto)}{(string.IsNullOrWhiteSpace(p.ReferenciaTexto) ? "" : $" ({p.ReferenciaTexto})")}").ToList())
		};
		var notas = impresion.Frases.Select(f => f.Texto).Where(t => !string.IsNullOrWhiteSpace(t)).Select(t => t!).ToList();
		if (e.Uuid is null) notas.Add("Documento todavía sin certificar ante SAT.");
		if (!string.IsNullOrWhiteSpace(e.Pie)) notas.Add(e.Pie!);

		var titulo = string.IsNullOrWhiteSpace(e.TdoDescripcion) ? "Factura" : e.TdoDescripcion;
		var pdf = DocumentoPdf.Generar(new DocumentoPdf.Datos(emisor, titulo, $"No. {numero}", encabezado,
			[new("Cant.", 1.4, true), new("Unidad", 1.6), new("Descripción", 8.0), new("Precio unit.", 2.5, true), new("Descuento", 2.2, true), new("Total", 2.9, true)],
			filas, totales, secciones, notas, $"{emisor.NombreComercial} · {titulo} {numero}",
			e.Estado == "A" ? "DOCUMENTO ANULADO" : null));

		var adjuntos = new List<CorreoServicio.Adjunto> { new($"{Archivo(titulo)}-{Archivo(numero)}.pdf", pdf, "application/pdf") };
		if (!string.IsNullOrWhiteSpace(e.XmlCertificado))
			adjuntos.Add(new($"{Archivo(titulo)}-{Archivo(numero)}.xml", System.Text.Encoding.UTF8.GetBytes(e.XmlCertificado), "application/xml"));
		var intro = $"Le enviamos su {titulo.ToLower(Es)} No. {numero} del {e.FechaEmision.ToString("dd 'de' MMMM 'de' yyyy", Es)}."
			+ (e.Uuid is null ? "" : " Se adjunta el PDF y el archivo XML certificado ante SAT.");
		return new Documento(TipoFactura, encId, e.CiaId, $"{titulo} {numero}", correoCliente,
			$"{titulo} {numero} - {emisor.NombreComercial}", e.NombreReceptor, intro,
			[("Documento", $"{titulo} {numero}"), ("Fecha", e.FechaEmision.ToString("dd/MM/yyyy", Es)), ("Total", M(e.Total)),
			 ("Condición", e.EsCredito ? "Crédito" : "Contado")],
			adjuntos, emisor.NombreComercial, emisor.Telefono);
	}

	public async Task<Documento?> ReciboAsync(int ppeId)
	{
		var recibo = await cuentas.ConsultarReciboAsync(ppeId);
		if (recibo is null) return null;
		var e = recibo.Encabezado;
		var emisor = await EmisorAsync(e.CiaId);
		var total = recibo.Aplicaciones.Sum(a => a.Monto);
		var encabezado = new List<(string, string?)>
		{
			("Cliente", e.Cliente), ("Código", e.ClienteCodigo), ("NIT", e.ClienteNit), ("Fecha", e.Fecha.ToString("dd/MM/yyyy HH:mm", Es)),
			("Recibido en", $"{e.Sucursal} · {e.Caja}"), ("Atendió", e.Usuario)
		};
		var filas = recibo.Aplicaciones.Select(a => new[]
		{
			a.Documento, a.Cuota?.ToString(Es) ?? "Pago inicial", a.Vencimiento?.ToString("dd/MM/yyyy", Es) ?? "", M(a.Monto),
			a.SaldoCuota is decimal s ? M(s) : ""
		}).ToList();
		var formas = recibo.Formas.Select(f => $"{f.Forma}: {M(f.Monto)}{(f.Entidad is null ? "" : $" · {f.Entidad}")}{(string.IsNullOrWhiteSpace(f.Referencia) ? "" : $" · ref. {f.Referencia}")}").ToList();
		var pdf = DocumentoPdf.Generar(new DocumentoPdf.Datos(emisor, "Recibo de pago", $"No. {e.PpeId}", encabezado,
			[new("Documento", 5.0), new("Cuota", 2.0, true), new("Vence", 2.6), new("Pagado", 3.0, true), new("Saldo de la cuota", 3.0, true)],
			filas, [("Total recibido", M(total), true)], [("Forma de pago", formas)],
			["Gracias por su pago."], $"{emisor.NombreComercial} · Recibo {e.PpeId}",
			e.Estado == "N" ? $"RECIBO ANULADO{(string.IsNullOrWhiteSpace(e.MotivoAnulacion) ? "" : $": {e.MotivoAnulacion}")}" : null));
		return new Documento(TipoRecibo, ppeId, e.CiaId, $"Recibo {ppeId}", e.ClienteCorreo,
			$"Recibo de pago No. {ppeId} - {emisor.NombreComercial}", e.Cliente,
			$"Le confirmamos que recibimos su pago por {M(total)} el {e.Fecha.ToString("dd 'de' MMMM 'de' yyyy", Es)}. Se adjunta el recibo.",
			[("Recibo", ppeId.ToString(Es)), ("Fecha", e.Fecha.ToString("dd/MM/yyyy", Es)), ("Monto", M(total)),
			 ("Documentos", string.Join(", ", recibo.Aplicaciones.Select(a => a.Cuota is null ? a.Documento : $"{a.Documento} #{a.Cuota}")))],
			[new($"recibo-{ppeId}.pdf", pdf, "application/pdf")], emisor.NombreComercial, emisor.Telefono);
	}

	public async Task<Documento?> CotizacionAsync(int cotId)
	{
		var (c, lineas) = await cotizaciones.ConsultarPorIdAsync(cotId);
		if (c is null) return null;
		var parametros = await general.ConsultarParametrosAsync(c.SucId);
		var emisor = await EmisorAsync(parametros.CiaId);
		string Mo(decimal v) => $"{c.Simbolo} {v.ToString("N2", CultureInfo.InvariantCulture)}";
		var correoCliente = c.Correo;
		if (string.IsNullOrWhiteSpace(correoCliente) && c.CliId is int cliId)
			correoCliente = (await cuentas.ConsultarDatosEstadoCuentaClienteAsync(cliId))?.Correo;
		var encabezado = new List<(string, string?)>
		{
			("Cliente", c.Cliente), ("NIT", c.Nit), ("Dirección", c.Direccion), ("Teléfono", c.Telefono),
			("Fecha", c.Fecha.ToString("dd/MM/yyyy", Es)), ("Válida hasta", c.Vence.ToString("dd/MM/yyyy", Es)),
			("Vendedor", c.Vendedor), ("Moneda", c.Moneda)
		};
		var filas = lineas.Select(l => new[]
		{
			l.Cantidad.ToString("0.##", Es), l.Unidad, l.Codigo is null ? l.Descripcion : $"{l.Codigo} · {l.Descripcion}",
			Mo(l.PrecioUnitario), l.Descuento == 0 ? "" : Mo(l.Descuento), Mo(l.Total)
		}).ToList();
		var totales = new List<(string, string, bool)>();
		if (c.Descuento > 0) totales.Add(("Descuento", Mo(c.Descuento), false));
		totales.Add(("IVA incluido", Mo(c.IvaIncluido), false));
		totales.Add(("Total", Mo(c.Total), true));
		var notas = new List<string> { $"Precios con IVA incluido. Cotización válida por {c.VigenciaDias} días, hasta el {c.Vence:dd/MM/yyyy}; sujeta a existencias." };
		if (!string.IsNullOrWhiteSpace(c.Observaciones)) notas.Insert(0, c.Observaciones!);
		var pdf = DocumentoPdf.Generar(new DocumentoPdf.Datos(emisor, "Cotización", $"No. {c.Numero}", encabezado,
			[new("Cant.", 1.4, true), new("Unidad", 1.6), new("Descripción", 8.0), new("Precio unit.", 2.5, true), new("Descuento", 2.2, true), new("Total", 2.9, true)],
			filas, totales, Array.Empty<(string, IReadOnlyList<string>)>(), notas, $"{emisor.NombreComercial} · Cotización {c.Numero}",
			c.Estado switch { "A" => "COTIZACIÓN ANULADA", "X" => "COTIZACIÓN VENCIDA", _ => null }));
		return new Documento(TipoCotizacion, cotId, parametros.CiaId, $"Cotización {c.Numero}", correoCliente,
			$"Cotización {c.Numero} - {emisor.NombreComercial}", c.Cliente,
			$"Le enviamos la cotización No. {c.Numero} que nos solicitó, válida hasta el {c.Vence.ToString("dd 'de' MMMM 'de' yyyy", Es)}.",
			[("Cotización", c.Numero), ("Total", Mo(c.Total)), ("Válida hasta", c.Vence.ToString("dd/MM/yyyy", Es))],
			[new($"cotizacion-{Archivo(c.Numero)}.pdf", pdf, "application/pdf")], emisor.NombreComercial, emisor.Telefono);
	}

	// Aviso al cliente de su pago con boleta: verificado (con el recibo adjunto) o rechazado.
	public async Task<CorreoServicio.Resultado> AvisarBoletaAsync(BoletaResumen b, bool verificada, int? ppeId, string? motivo, int? usuId, int? sucId)
	{
		if (string.IsNullOrWhiteSpace(b.ClienteCorreo))
			return new CorreoServicio.Resultado(false, "el cliente no tiene correo registrado");
		var adjuntos = new List<CorreoServicio.Adjunto>();
		var ciaId = (await general.ConsultarParametrosAsync(sucId)).CiaId;
		var resumen = new List<(string, string)> { ("Boleta", b.Referencia), ("Fecha del pago", b.Fecha.ToString("dd/MM/yyyy", Es)), ("Monto", M(b.Monto)), ("Cuenta", b.Cuenta) };
		if (verificada && ppeId is int recibo && await ReciboAsync(recibo) is { } doc)
		{
			adjuntos.AddRange(doc.Adjuntos);
			ciaId = doc.CiaId;
			resumen.Add(("Recibo", recibo.ToString(Es)));
		}
		var emisor = await EmisorAsync(ciaId);
		var intro = verificada
			? $"Confirmamos su pago con la boleta {b.Referencia} por {M(b.Monto)}: ya está aplicado a su cuenta" + (adjuntos.Count > 0 ? " y le adjuntamos el recibo." : ".")
			: $"No pudimos confirmar su pago con la boleta {b.Referencia} por {M(b.Monto)}"
				+ (string.IsNullOrWhiteSpace(motivo) ? "." : $": {motivo.Trim()}.") + " Por favor comuníquese con nosotros.";
		var d = new Documento(TipoBoleta, b.CboId, ciaId, $"Boleta {b.Referencia}", b.ClienteCorreo,
			verificada ? $"Pago recibido - boleta {b.Referencia} - {emisor.NombreComercial}" : $"Pago no confirmado - boleta {b.Referencia} - {emisor.NombreComercial}",
			b.Cliente, intro, resumen, adjuntos, emisor.NombreComercial, emisor.Telefono);
		return await EnviarAsync(d, b.ClienteCorreo!, null, d.Asunto, null, usuId);
	}

	public Task<CorreoServicio.Resultado> EnviarAsync(Documento d, string para, string? copia, string asunto, string? mensaje, int? usuId)
	{
		var (html, texto) = Cuerpo(d, mensaje);
		return correo.EnviarConAdjuntosAsync(d.CiaId, d.Tipo, d.ReferenciaId, para, copia, asunto, html, texto, d.Adjuntos, usuId);
	}

	public static (string Html, string Texto) Cuerpo(Documento d, string? mensaje)
	{
		var saludo = $"Estimado(a) {d.Destinatario}:";
		var cierre = "Para cualquier consulta, responda a este correo" + (string.IsNullOrWhiteSpace(d.Telefono) ? "." : $" o llámenos al {d.Telefono}.");
		string H(string s) => WebUtility.HtmlEncode(s);
		var html = $"""
			<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#1a1f2e;max-width:600px">
			  <p>{H(saludo)}</p>
			  <p>{H(d.Intro)}</p>
			  {(string.IsNullOrWhiteSpace(mensaje) ? "" : $"<p>{H(mensaje.Trim()).Replace("\n", "<br>")}</p>")}
			  <table style="border-collapse:collapse;margin:12px 0;min-width:320px">
			    {string.Concat(d.Resumen.Select(f => $"<tr><td style=\"padding:6px 12px;background:#e8edf7;color:#34405a\">{H(f.Etiqueta)}</td><td style=\"padding:6px 12px;text-align:right;font-weight:bold;color:#0d1b4c\">{H(f.Valor)}</td></tr>"))}
			  </table>
			  <p>{H(cierre)}</p>
			  <p>Atentamente,<br><strong>{H(d.Compania)}</strong></p>
			</div>
			""";
		var texto = string.Join("\n", new[]
		{
			saludo, "", d.Intro, string.IsNullOrWhiteSpace(mensaje) ? null : "\n" + mensaje.Trim(), "",
			string.Join("\n", d.Resumen.Select(f => $"{f.Etiqueta}: {f.Valor}")), "", cierre, "", "Atentamente,", d.Compania
		}.Where(l => l is not null));
		return (html, texto);
	}

	private async Task<EstadoCuentaPdf.Emisor> EmisorAsync(int ciaId)
	{
		var compania = (await general.ConsultarCompaniasAsync(soloActivas: false)).FirstOrDefault(c => c.CiaId == ciaId)
			?? (await general.ConsultarCompaniasAsync(soloActivas: false)).FirstOrDefault();
		var logo = compania is null ? null : await general.ConsultarLogoAsync(compania.CiaId, null, soloVersion: false);
		return new EstadoCuentaPdf.Emisor(compania?.CiaNombreComercial ?? "", compania?.CiaNit, compania?.CiaDireccion,
			compania?.CiaTelefono, compania?.CiaEmail, logo?.Logo);
	}

	private static string M(decimal v) => "Q" + v.ToString("N2", CultureInfo.InvariantCulture);

	private static string Archivo(string texto) =>
		new string(texto.ToLowerInvariant().Select(ch => char.IsLetterOrDigit(ch) ? ch : '-').ToArray()).Trim('-');
}
