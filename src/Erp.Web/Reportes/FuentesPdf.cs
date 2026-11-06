using PdfSharp.Fonts;

namespace Erp.Web.Reportes;

// Fuente de los PDF (PDFsharp no trae fuentes propias). Busca una fuente sans
// del sistema: Arial en Windows; Liberation Sans, DejaVu Sans o FreeSans en
// Linux. Todos los PDF usan la familia lógica "ErpSans".
public sealed class FuentesPdf : IFontResolver
{
	public const string Familia = "ErpSans";

	private static readonly string[] Carpetas =
	[
		Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Fonts"),
		"/usr/share/fonts/truetype/liberation", "/usr/share/fonts/truetype/liberation2", "/usr/share/fonts/liberation",
		"/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/dejavu", "/usr/share/fonts/truetype/freefont",
		"/Library/Fonts", "/System/Library/Fonts/Supplemental"
	];

	// Por estilo: normal, negrita, cursiva, negrita cursiva.
	private static readonly string[][] Archivos =
	[
		["arial.ttf", "LiberationSans-Regular.ttf", "DejaVuSans.ttf", "FreeSans.ttf", "Arial.ttf"],
		["arialbd.ttf", "LiberationSans-Bold.ttf", "DejaVuSans-Bold.ttf", "FreeSansBold.ttf", "Arial Bold.ttf"],
		["ariali.ttf", "LiberationSans-Italic.ttf", "DejaVuSans-Oblique.ttf", "FreeSansOblique.ttf", "Arial Italic.ttf"],
		["arialbi.ttf", "LiberationSans-BoldItalic.ttf", "DejaVuSans-BoldOblique.ttf", "FreeSansBoldOblique.ttf", "Arial Bold Italic.ttf"]
	];

	private static readonly Lazy<string?[]> Rutas = new(() => Archivos.Select(Buscar).ToArray());
	private static readonly object Candado = new();
	private static bool registrado;

	public static void Registrar()
	{
		lock (Candado)
		{
			if (registrado) return;
			if (Rutas.Value[0] is null)
				throw new InvalidOperationException("No se encontró una fuente para generar el PDF (Arial, Liberation Sans o DejaVu Sans). Instale una en el servidor.");
			GlobalFontSettings.FontResolver = new FuentesPdf();
			registrado = true;
		}
	}

	private static string? Buscar(string[] nombres) =>
		nombres.SelectMany(n => Carpetas.Select(c => Path.Combine(c, n))).FirstOrDefault(File.Exists);

	public FontResolverInfo? ResolveTypeface(string familyName, bool isBold, bool isItalic)
	{
		var estilo = (isBold ? 1 : 0) + (isItalic ? 2 : 0);
		// Sin la variante, la normal con negrita o cursiva simuladas.
		if (Rutas.Value[estilo] is not null) return new FontResolverInfo($"{Familia}#{estilo}");
		return new FontResolverInfo($"{Familia}#0", isBold, isItalic);
	}

	public byte[]? GetFont(string faceName)
	{
		var estilo = int.TryParse(faceName.Split('#').LastOrDefault(), out var e) ? e : 0;
		var ruta = Rutas.Value[estilo] ?? Rutas.Value[0];
		return ruta is null ? null : File.ReadAllBytes(ruta);
	}
}
