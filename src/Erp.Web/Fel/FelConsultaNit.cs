using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Erp.Data.Fel;
using Erp.Data.General;

namespace Erp.Web.Fel;

// Nombre del contribuyente que devuelve el certificador para un NIT (o CUI).
// Encontrado = false con Mensaje cuando no se pudo consultar o no existe.
public sealed record ConsultaNitResultado(bool Encontrado, string? Nombre, string Mensaje, string Fuente);

// Consulta el NIT con el servicio del certificador de la compañía, según el
// catálogo fel_certificador (44): método, URL con {nit}, cuerpo con {nit}
// {usuario} {llave}, encabezado que lleva la llave y campo del nombre en el
// JSON de respuesta. Así sirve para cualquier certificador que publique su
// servicio sin cambiar código. Las credenciales vienen de la configuración de
// la aplicación (Fel:Credenciales:<NIT emisor>:ConsultaNitUsuario y
// :ConsultaNitLlave; si faltan, el usuario API de la configuración FEL y
// :LlaveApi). El simulador responde sin salir de la aplicación.
public sealed class FelConsultaNitServicio(IFelRepository felRepository, IHttpClientFactory httpClientFactory, IConfiguration configuracion)
{
	public async Task<ConsultaNitResultado> ConsultarAsync(int ciaId, string nit, CancellationToken cancelacion = default)
	{
		var n = NitValidador.Normalizar(nit);
		if (n is null)
			return new ConsultaNitResultado(false, null, "Escriba el NIT.", "");
		if (n == "CF")
			return new ConsultaNitResultado(true, "CONSUMIDOR FINAL", "Consumidor final.", "");
		if (!NitValidador.EsValido(n))
			return new ConsultaNitResultado(false, null, NitValidador.MensajeInvalido(nit), "");

		var conf = await felRepository.ConsultarConsultaNitAsync(ciaId);
		if (conf is null)
			return new ConsultaNitResultado(false, null, "La compañía no tiene configuración FEL.", "");
		var fuente = conf.NombreCertificador ?? conf.Certificador;
		if (!conf.Activa)
			return new ConsultaNitResultado(false, null, "La consulta del NIT al certificador está desactivada en la configuración FEL.", fuente);
		if (conf.Certificador == "SIMULADOR")
			return Simular(n, fuente);
		if (!conf.Implementado || string.IsNullOrWhiteSpace(conf.Url) || string.IsNullOrWhiteSpace(conf.Metodo) || string.IsNullOrWhiteSpace(conf.CampoNombre))
			return new ConsultaNitResultado(false, null,
				$"{fuente} no tiene configurada la consulta de NIT (URL, método y campo del nombre en el catálogo de certificadores).", fuente);

		var clave = $"Fel:Credenciales:{conf.NitEmisor}";
		var usuario = configuracion[$"{clave}:ConsultaNitUsuario"] ?? conf.UsuarioApi ?? "";
		var llave = configuracion[$"{clave}:ConsultaNitLlave"] ?? configuracion[$"{clave}:LlaveApi"] ?? "";
		var usaLlave = (conf.Cuerpo?.Contains("{llave}") ?? false) || !string.IsNullOrWhiteSpace(conf.Encabezado);
		if (usaLlave && string.IsNullOrWhiteSpace(llave))
			return new ConsultaNitResultado(false, null, $"Falta la llave de consulta de NIT: configure {clave}:ConsultaNitLlave en la aplicación.", fuente);

		var url = conf.Url.Replace("{nit}", Uri.EscapeDataString(n));
		using var mensaje = new HttpRequestMessage(conf.Metodo.Equals("POST", StringComparison.OrdinalIgnoreCase) ? HttpMethod.Post : HttpMethod.Get, url);
		if (!string.IsNullOrWhiteSpace(conf.Cuerpo))
		{
			var cuerpo = conf.Cuerpo.Replace("{nit}", Json(n)).Replace("{usuario}", Json(usuario)).Replace("{llave}", Json(llave));
			mensaje.Content = new StringContent(cuerpo, Encoding.UTF8, "application/json");
		}
		if (!string.IsNullOrWhiteSpace(conf.Encabezado))
			mensaje.Headers.TryAddWithoutValidation(conf.Encabezado, llave);
		mensaje.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

		string respuesta;
		try
		{
			var cliente = httpClientFactory.CreateClient("Fel");
			cliente.Timeout = TimeSpan.FromSeconds(Math.Clamp(conf.TimeoutSegundos, 5, 60));
			using var http = await cliente.SendAsync(mensaje, cancelacion);
			respuesta = await http.Content.ReadAsStringAsync(cancelacion);
			if (!http.IsSuccessStatusCode && string.IsNullOrWhiteSpace(respuesta))
				return new ConsultaNitResultado(false, null, $"{fuente} respondió HTTP {(int)http.StatusCode}.", fuente);
		}
		catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
		{
			return new ConsultaNitResultado(false, null, $"No hubo respuesta de {fuente}: {ex.Message}", fuente);
		}

		return Interpretar(respuesta, conf.CampoNombre, fuente);
	}

	// Busca el nombre en la ruta indicada (a.b, sin distinguir mayúsculas; en
	// un arreglo toma el primer elemento).
	internal static ConsultaNitResultado Interpretar(string respuesta, string campo, string fuente)
	{
		try
		{
			using var json = JsonDocument.Parse(respuesta);
			var nombre = Buscar(json.RootElement, campo.Split('.'))?.Trim();
			if (!string.IsNullOrWhiteSpace(nombre))
				return new ConsultaNitResultado(true, nombre, $"Nombre obtenido de {fuente}.", fuente);
			var detalle = Buscar(json.RootElement, ["mensaje"]) ?? Buscar(json.RootElement, ["descripcion"]) ?? Buscar(json.RootElement, ["message"]);
			return new ConsultaNitResultado(false, null, $"{fuente} no devolvió nombre para ese NIT{(string.IsNullOrWhiteSpace(detalle) ? "." : $": {detalle}")}", fuente);
		}
		catch (JsonException)
		{
			return new ConsultaNitResultado(false, null, $"La respuesta de {fuente} no es JSON válido.", fuente);
		}
	}

	private static string? Buscar(JsonElement elemento, string[] ruta)
	{
		foreach (var parte in ruta)
		{
			if (elemento.ValueKind == JsonValueKind.Array)
			{
				if (elemento.GetArrayLength() == 0) return null;
				elemento = elemento[0];
			}
			if (elemento.ValueKind != JsonValueKind.Object) return null;
			var propiedad = elemento.EnumerateObject().FirstOrDefault(p => p.Name.Equals(parte, StringComparison.OrdinalIgnoreCase));
			if (propiedad.Value.ValueKind == JsonValueKind.Undefined) return null;
			elemento = propiedad.Value;
		}
		if (elemento.ValueKind == JsonValueKind.Array && elemento.GetArrayLength() > 0) elemento = elemento[0];
		return elemento.ValueKind is JsonValueKind.String or JsonValueKind.Number ? elemento.ToString() : null;
	}

	private static string Json(string valor) => JsonSerializer.Serialize(valor)[1..^1];

	// Nombre de prueba estable para cada NIT, en el formato de SAT
	// (APELLIDO,APELLIDO,CASADA,NOMBRE,NOMBRE), para ejercitar el registro.
	private static ConsultaNitResultado Simular(string nit, string fuente)
	{
		string[] apellidos = ["LOPEZ", "GARCIA", "MORALES", "HERNANDEZ", "CASTILLO", "RAMIREZ", "PEREZ", "SOTO", "ORELLANA", "CIFUENTES"];
		string[] nombres = ["ANA", "CARLOS", "LUCIA", "JORGE", "MARIA", "ESTUARDO", "SOFIA", "DIEGO", "ANDREA", "JOSE"];
		var semilla = nit.Aggregate(17, (acumulado, c) => unchecked(acumulado * 31 + c)) & int.MaxValue;
		var nombre = $"{apellidos[semilla % 10]},{apellidos[semilla / 10 % 10]},,{nombres[semilla / 100 % 10]},{nombres[semilla / 1000 % 10]}";
		return new ConsultaNitResultado(true, nombre, "Nombre de prueba del simulador (sin validez fiscal).", fuente);
	}
}
