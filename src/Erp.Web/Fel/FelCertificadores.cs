using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Xml.Linq;

namespace Erp.Web.Fel;

// Lo que se envía al certificador. Las llaves vienen de la configuración de
// la aplicación (Fel:Credenciales:<NIT>), nunca de la base.
public sealed record FelSolicitud(string Xml, string Identificador, string NitEmisor, string? CorreoCopia,
	string? Url, string? UsuarioFirma, string? LlaveFirma, string? UsuarioApi, string? LlaveApi, int TimeoutSegundos);

// Rechazado = el certificador respondió con errores (hay que corregir datos);
// si no hubo respuesta (Exito y Rechazado en false) se puede reintentar tal cual.
public sealed record FelRespuesta(bool Exito, bool Rechazado, string? Uuid, string? Serie, string? Numero, DateTime? Fecha,
	string? XmlCertificado, string Mensaje, string? Respuesta);

public interface IFelCertificador
{
	string Nombre { get; }
	Task<FelRespuesta> CertificarAsync(FelSolicitud solicitud, CancellationToken cancelacion = default);
	Task<FelRespuesta> AnularAsync(FelSolicitud solicitud, CancellationToken cancelacion = default);
}

// INFILE, proceso unificado (firma + certificación en una llamada): el XML va
// en el cuerpo y las credenciales en los encabezados. El mismo servicio recibe
// la anulación. Las URLs se configuran por compañía; confírmelas con INFILE
// para el ambiente de pruebas o producción.
public sealed class InfileCertificador(IHttpClientFactory httpClientFactory) : IFelCertificador
{
	public string Nombre => "INFILE";

	public Task<FelRespuesta> CertificarAsync(FelSolicitud solicitud, CancellationToken cancelacion = default) => EnviarAsync(solicitud, cancelacion);
	public Task<FelRespuesta> AnularAsync(FelSolicitud solicitud, CancellationToken cancelacion = default) => EnviarAsync(solicitud, cancelacion);

	private async Task<FelRespuesta> EnviarAsync(FelSolicitud s, CancellationToken cancelacion)
	{
		if (string.IsNullOrWhiteSpace(s.Url) || string.IsNullOrWhiteSpace(s.UsuarioFirma) || string.IsNullOrWhiteSpace(s.UsuarioApi))
			return new FelRespuesta(false, true, null, null, null, null, null, "Falta la URL o los usuarios de INFILE en la configuración FEL de la compañía.", null);
		if (string.IsNullOrWhiteSpace(s.LlaveFirma) || string.IsNullOrWhiteSpace(s.LlaveApi))
			return new FelRespuesta(false, true, null, null, null, null, null,
				$"Faltan las llaves de INFILE: configure Fel:Credenciales:{s.NitEmisor}:LlaveFirma y :LlaveApi en la aplicación.", null);

		var cliente = httpClientFactory.CreateClient("Fel");
		cliente.Timeout = TimeSpan.FromSeconds(s.TimeoutSegundos);
		using var mensaje = new HttpRequestMessage(HttpMethod.Post, s.Url)
		{
			Content = new StringContent(s.Xml, Encoding.UTF8, "application/xml")
		};
		mensaje.Headers.Add("UsuarioFirma", s.UsuarioFirma);
		mensaje.Headers.Add("LlaveFirma", s.LlaveFirma);
		mensaje.Headers.Add("UsuarioApi", s.UsuarioApi);
		mensaje.Headers.Add("LlaveApi", s.LlaveApi);
		mensaje.Headers.Add("Identificador", s.Identificador);
		if (!string.IsNullOrWhiteSpace(s.CorreoCopia)) mensaje.Headers.Add("CorreoCopia", s.CorreoCopia);
		mensaje.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

		string cuerpo;
		try
		{
			using var respuesta = await cliente.SendAsync(mensaje, cancelacion);
			cuerpo = await respuesta.Content.ReadAsStringAsync(cancelacion);
			if (!respuesta.IsSuccessStatusCode && string.IsNullOrWhiteSpace(cuerpo))
				return new FelRespuesta(false, (int)respuesta.StatusCode is >= 400 and < 500, null, null, null, null, null,
					$"INFILE respondió HTTP {(int)respuesta.StatusCode}.", null);
		}
		catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
		{
			return new FelRespuesta(false, false, null, null, null, null, null, $"No hubo respuesta de INFILE: {ex.Message}", null);
		}

		return Interpretar(cuerpo);
	}

	// Respuesta JSON de INFILE: resultado, descripcion, uuid, serie, numero,
	// fecha, xml_certificado (base64) y descripcion_errores[].mensaje_error.
	internal static FelRespuesta Interpretar(string cuerpo)
	{
		try
		{
			using var json = JsonDocument.Parse(cuerpo);
			var raiz = json.RootElement;
			string? Texto(string nombre) => raiz.TryGetProperty(nombre, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
			var resultado = raiz.TryGetProperty("resultado", out var r) && r.ValueKind == JsonValueKind.True;
			if (resultado)
			{
				var xml = Texto("xml_certificado");
				if (!string.IsNullOrEmpty(xml) && !xml.TrimStart().StartsWith('<'))
					xml = Encoding.UTF8.GetString(Convert.FromBase64String(xml));
				DateTime? fecha = DateTime.TryParse(Texto("fecha"), CultureInfo.InvariantCulture, DateTimeStyles.None, out var f) ? f : null;
				return new FelRespuesta(true, false, Texto("uuid"), Texto("serie"), Texto("numero"), fecha, xml, Texto("descripcion") ?? "Certificado.", cuerpo);
			}

			var errores = new List<string>();
			if (raiz.TryGetProperty("descripcion_errores", out var lista) && lista.ValueKind == JsonValueKind.Array)
				foreach (var error in lista.EnumerateArray())
					if (error.TryGetProperty("mensaje_error", out var m) && m.GetString() is { Length: > 0 } texto)
						errores.Add(texto);
			var descripcion = Texto("descripcion");
			var mensaje = errores.Count > 0 ? string.Join(" | ", errores) : descripcion ?? "El certificador rechazó el documento.";
			return new FelRespuesta(false, true, null, null, null, null, null, mensaje, cuerpo);
		}
		catch (JsonException)
		{
			return new FelRespuesta(false, false, null, null, null, null, null, "La respuesta del certificador no es JSON válido.", cuerpo);
		}
	}
}

// Certificador de pruebas: valida el XML y devuelve una autorización con el
// formato de SAT (UUID, serie de 8 caracteres y número) y el XML con el nodo
// de certificación, sin salir de la aplicación.
public sealed class SimuladorCertificador : IFelCertificador
{
	public string Nombre => "SIMULADOR";

	public Task<FelRespuesta> CertificarAsync(FelSolicitud solicitud, CancellationToken cancelacion = default)
	{
		XDocument documento;
		try { documento = XDocument.Parse(solicitud.Xml); }
		catch (Exception ex) { return Task.FromResult(Rechazo($"XML no válido: {ex.Message}")); }

		var dte = documento.Root!.Name.Namespace;
		var emision = documento.Descendants(dte + "DatosEmision").FirstOrDefault();
		if (emision is null) return Task.FromResult(Rechazo("El XML no tiene DatosEmision."));

		var granTotal = decimal.Parse(emision.Descendants(dte + "GranTotal").First().Value, CultureInfo.InvariantCulture);
		var sumaItems = emision.Descendants(dte + "Item").Sum(i => decimal.Parse(i.Element(dte + "Total")!.Value, CultureInfo.InvariantCulture));
		if (granTotal != sumaItems) return Task.FromResult(Rechazo($"El GranTotal ({granTotal}) no es la suma de los ítems ({sumaItems})."));
		if (!emision.Descendants(dte + "Item").Any()) return Task.FromResult(Rechazo("El documento no tiene ítems."));

		var tipo = emision.Element(dte + "DatosGenerales")?.Attribute("Tipo")?.Value;
		if (tipo is "NCRE" or "NDEB")
		{
			var referencia = documento.Descendants().FirstOrDefault(x => x.Name.LocalName == "ReferenciasNota");
			if (string.IsNullOrEmpty(referencia?.Attribute("NumeroAutorizacionDocumentoOrigen")?.Value))
				return Task.FromResult(Rechazo("La nota debe referir la autorización (UUID) del documento de origen."));
		}

		var uuid = Guid.NewGuid().ToString().ToUpperInvariant();
		var serie = uuid[..8];
		var numero = Convert.ToUInt32(uuid.Substring(9, 4) + uuid.Substring(14, 4), 16).ToString(CultureInfo.InvariantCulture);
		var fecha = DateTime.Now;

		var datosCertificados = documento.Descendants(dte + "DTE").First();
		datosCertificados.Add(new XElement(dte + "Certificacion",
			new XElement(dte + "NITCertificador", "12521337"),
			new XElement(dte + "NombreCertificador", "SIMULADOR FEL (sin validez fiscal)"),
			new XElement(dte + "NumeroAutorizacion", new XAttribute("Numero", numero), new XAttribute("Serie", serie), uuid),
			new XElement(dte + "FechaHoraCertificacion", FelXmlBuilder.FechaHora(fecha))));

		return Task.FromResult(new FelRespuesta(true, false, uuid, serie, numero, fecha, documento.Declaration + documento.ToString(SaveOptions.DisableFormatting),
			"Certificado por el simulador (sin validez fiscal).", null));
	}

	public Task<FelRespuesta> AnularAsync(FelSolicitud solicitud, CancellationToken cancelacion = default)
	{
		try { XDocument.Parse(solicitud.Xml); }
		catch (Exception ex) { return Task.FromResult(Rechazo($"XML no válido: {ex.Message}")); }
		return Task.FromResult(new FelRespuesta(true, false, null, null, null, DateTime.Now, null, "Anulado por el simulador (sin validez fiscal).", null));
	}

	private static FelRespuesta Rechazo(string mensaje) => new(false, true, null, null, null, null, null, mensaje, null);
}
