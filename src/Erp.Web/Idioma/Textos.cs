using System.Collections.Frozen;
using System.Globalization;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Erp.Web.Idioma;

// Textos de la interfaz en el idioma del usuario. La aplicación está escrita
// en español y el texto en español es la llave: L("Guardar") devuelve "Save"
// en inglés y "Guardar" en español (o si falta la traducción). Las
// traducciones están en Idioma/en/*.json, un archivo por módulo.
//
// Solo cambia el idioma de la interfaz (CurrentUICulture); el formato de
// números y fechas sigue siendo el de la aplicación.
public static partial class Textos
{
	public const string CookieIdioma = "erp-idioma";
	public const string CookieTema = "erp-tema";

	private static FrozenDictionary<string, string> ingles = FrozenDictionary<string, string>.Empty;
	private static (Regex Patron, string Plantilla)[] patrones = [];

	public static bool EsIngles => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "en";

	// Código del idioma actual para <html lang> y para los nombres de archivo.
	public static string CodigoIdioma => EsIngles ? "en" : "es";

	// Texto fijo de la interfaz.
	public static string L(string? texto)
	{
		if (string.IsNullOrEmpty(texto) || !EsIngles) return texto ?? "";
		return ingles.TryGetValue(texto, out var traduccion) ? traduccion : texto;
	}

	// Texto con valores: L("Factura {0} grabada.", numero). Los valores se
	// formatean con la cultura de la aplicación, igual que en español.
	public static string L(string texto, params object?[] valores) =>
		string.Format(CultureInfo.CurrentCulture, L(texto), valores);

	// Mensaje ya armado que puede traer valores (errores de la base de datos o
	// de la aplicación): primero se busca tal cual y, si no está, se compara
	// contra las plantillas con {0}, {1}... y se pasan los valores al inglés.
	public static string Mensaje(string? texto)
	{
		if (string.IsNullOrEmpty(texto) || !EsIngles) return texto ?? "";
		if (ingles.TryGetValue(texto, out var traduccion)) return traduccion;
		foreach (var (patron, plantilla) in patrones)
		{
			var m = patron.Match(texto);
			if (!m.Success) continue;
			return Marcador().Replace(plantilla, x => m.Groups["v" + x.Groups[1].Value].Value);
		}
		// Varias oraciones: se traduce cada una por separado.
		var partes = Oraciones().Split(texto);
		if (partes.Length > 1)
		{
			var traducidas = partes.Select(p => p.Length == 0 ? p : Mensaje(p)).ToArray();
			if (!traducidas.SequenceEqual(partes)) return string.Join(" ", traducidas.Where(p => p.Length > 0));
		}
		return texto;
	}

	// Carga las traducciones incrustadas en el ensamblado (Idioma/en/*.json).
	public static void Cargar()
	{
		var ensamblado = Assembly.GetExecutingAssembly();
		var todo = new Dictionary<string, string>(StringComparer.Ordinal);
		foreach (var recurso in ensamblado.GetManifestResourceNames().Where(r => r.StartsWith("idioma:en/", StringComparison.Ordinal)).Order())
		{
			using var flujo = ensamblado.GetManifestResourceStream(recurso)!;
			var archivo = JsonSerializer.Deserialize<Dictionary<string, string>>(flujo) ?? new();
			foreach (var (es, en) in archivo)
			{
				if (!string.IsNullOrEmpty(en)) todo[es] = en;
			}
		}
		ingles = todo.ToFrozenDictionary(StringComparer.Ordinal);

		// Plantillas con valores; las más largas primero para que la más
		// específica gane.
		patrones = todo.Where(p => Marcador().IsMatch(p.Key))
			.OrderByDescending(p => p.Key.Length)
			.Select(p => (new Regex("^" + Marcador().Replace(Regex.Escape(p.Key).Replace(@"\{", "{"), x => $"(?<v{x.Groups[1].Value}>.+?)") + "$",
				RegexOptions.Singleline | RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(50)), Marcador().Replace(p.Value, "{$1}")))
			.ToArray();
	}

	// Cantidad de textos traducidos (para la prueba de carga).
	public static int CantidadTextos => ingles.Count;

	[GeneratedRegex(@"\{(\d+)(?::[^}]*)?\}")]
	private static partial Regex Marcador();

	[GeneratedRegex(@"(?<=[.:;])\s+(?=[A-ZÁÉÍÓÚÑ¿¡(])")]
	private static partial Regex Oraciones();
}
