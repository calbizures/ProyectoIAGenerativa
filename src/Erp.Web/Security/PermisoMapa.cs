using System.Reflection;
using System.Text.RegularExpressions;

namespace Erp.Web.Security;

// Dónde usa la aplicación cada permiso: las pantallas que lo piden para
// entrar y los botones o secciones que muestra solo a quien lo tiene. Se arma
// una vez a partir de los .razor incrustados en el ensamblado (ver
// Erp.Web.csproj), con el nombre de cada opción tal como sale en el menú.
public sealed partial class PermisoMapa
{
	public sealed record Uso(string Ruta, string Opcion, bool EsAccion);

	private readonly Dictionary<string, List<Uso>> usos = new(StringComparer.OrdinalIgnoreCase);

	public PermisoMapa()
	{
		var ensamblado = typeof(PermisoMapa).Assembly;
		var archivos = ensamblado.GetManifestResourceNames()
			.Where(n => n.StartsWith("razor:", StringComparison.Ordinal))
			.ToDictionary(n => Path.GetFileNameWithoutExtension(n["razor:".Length..]), n => Leer(ensamblado, n));

		var menu = archivos.TryGetValue("NavMenu", out var nav) ? OpcionesMenu(nav) : new Dictionary<string, string>();
		string Nombre(IEnumerable<string> rutas) =>
			rutas.Select(r => menu.TryGetValue(r, out var n) ? n : null).FirstOrDefault(n => n is not null) ?? "/" + rutas.First();

		// Páginas: rutas y nombre en el menú.
		// Las pantallas con parámetros en la ruta (impresiones, detalles) no se listan.
		var paginas = archivos.Where(a => RutaPagina().IsMatch(a.Value))
			.ToDictionary(a => a.Key, a => RutaPagina().Matches(a.Value).Select(m => m.Groups[1].Value.Trim('/')).ToList())
			.Where(p => p.Value.Any(r => !r.Contains('{')))
			.ToDictionary(p => p.Key, p => p.Value.Where(r => !r.Contains('{')).ToList());

		foreach (var (archivo, texto) in archivos)
		{
			if (archivo == "NavMenu") continue;
			// Componentes sin @page: se atribuyen a las páginas que los usan.
			var destinos = paginas.TryGetValue(archivo, out var propias)
				? new List<List<string>> { propias }
				: paginas.Where(p => archivos[p.Key].Contains("<" + archivo + " ") || archivos[p.Key].Contains("<" + archivo + ">") || archivos[p.Key].Contains("<" + archivo + "\n"))
					.Select(p => p.Value).ToList();
			if (destinos.Count == 0) continue;

			var entrada = PoliticaPagina().Match(texto);
			var acciones = PoliticaVista().Matches(texto).SelectMany(m => Codigos(m.Groups[1].Value)).Distinct().ToList();
			foreach (var rutas in destinos)
			{
				var uso = rutas.FirstOrDefault(r => menu.ContainsKey(r)) ?? rutas[0];
				if (entrada.Success && paginas.ContainsKey(archivo))
					foreach (var codigo in Codigos(entrada.Groups[1].Value)) Agregar(codigo, new Uso(uso, Nombre(rutas), false));
				foreach (var codigo in acciones) Agregar(codigo, new Uso(uso, Nombre(rutas), true));
			}
		}
		foreach (var lista in usos.Values) lista.Sort((a, b) => (a.EsAccion, a.Opcion).CompareTo((b.EsAccion, b.Opcion)));
	}

	public IReadOnlyList<Uso> Consultar(string codigo) => usos.TryGetValue(codigo, out var lista) ? lista : Array.Empty<Uso>();

	public bool SeUsa(string codigo) => usos.ContainsKey(codigo);

	private void Agregar(string codigo, Uso uso)
	{
		if (!usos.TryGetValue(codigo, out var lista)) usos[codigo] = lista = new();
		if (!lista.Any(u => u.Ruta == uso.Ruta && u.EsAccion == uso.EsAccion)) lista.Add(uso);
	}

	private static IEnumerable<string> Codigos(string politica) =>
		politica.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

	private static string Leer(Assembly ensamblado, string recurso)
	{
		using var flujo = ensamblado.GetManifestResourceStream(recurso)!;
		using var lector = new StreamReader(flujo);
		return lector.ReadToEnd();
	}

	// Ruta -> "Grupo › Opción" según el menú lateral.
	private static Dictionary<string, string> OpcionesMenu(string nav)
	{
		var grupos = Nodo().Matches(nav).Select(m => (Inicio: m.Index, Fin: nav.IndexOf("</SidebarNodo>", m.Index, StringComparison.Ordinal), Titulo: m.Groups[1].Value)).ToList();
		var resultado = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
		foreach (Match enlace in Enlace().Matches(nav))
		{
			var texto = Etiquetas().Replace(enlace.Groups[2].Value, " ").Trim();
			texto = Espacios().Replace(texto, " ");
			var grupo = grupos.LastOrDefault(g => g.Inicio < enlace.Index && g.Fin > enlace.Index).Titulo;
			resultado.TryAdd(enlace.Groups[1].Value.Trim('/'), grupo is null ? texto : $"{grupo} › {texto}");
		}
		return resultado;
	}

	[GeneratedRegex("""@page\s+"([^"]*)" """, RegexOptions.IgnorePatternWhitespace)]
	private static partial Regex RutaPagina();
	[GeneratedRegex("""@attribute\s+\[Authorize\(Policy\s*=\s*"Permiso:([^"]+)"\)\]""")]
	private static partial Regex PoliticaPagina();
	[GeneratedRegex("""AuthorizeView\s+Policy="Permiso:([^"]+)" """, RegexOptions.IgnorePatternWhitespace)]
	private static partial Regex PoliticaVista();
	[GeneratedRegex("""<SidebarNodo\s+Titulo="([^"]+)" """, RegexOptions.IgnorePatternWhitespace)]
	private static partial Regex Nodo();
	[GeneratedRegex("""<NavLink\s+href="([^"]*)"[^>]*>(.*?)</NavLink>""", RegexOptions.Singleline)]
	private static partial Regex Enlace();
	[GeneratedRegex("<[^>]+>")]
	private static partial Regex Etiquetas();
	[GeneratedRegex(@"\s+")]
	private static partial Regex Espacios();
}
