using System.Globalization;
using System.Text;
using ClosedXML.Excel;
using Erp.Data.Cargas;

namespace Erp.Web.Reportes;

// Lee la primera hoja de un libro: la fila de encabezados (la primera que
// tenga alguno de los encabezados esperados) y las filas de datos. Los
// encabezados se comparan sin tildes, mayúsculas ni espacios, así que
// "Costo total", "COSTO_TOTAL" y "costototal" son la misma columna.
public sealed class LectorExcel : IDisposable
{
	private static readonly CultureInfo Guatemala = CultureInfo.GetCultureInfo("es-GT");
	private readonly Dictionary<string, int> columnas = new();
	private readonly List<IXLRow> filas = new();
	private XLWorkbook? libro;
	public List<MensajeCarga> Errores { get; } = new();

	private LectorExcel() { }

	public IReadOnlyList<IXLRow> Filas => filas;

	public static LectorExcel Leer(Stream archivo, IEnumerable<string> encabezadosEsperados, string? nombreHoja = null)
	{
		var lector = new LectorExcel();
		var libro = new XLWorkbook(archivo);
		lector.libro = libro;
		var hoja = nombreHoja is not null && libro.Worksheets.TryGetWorksheet(nombreHoja, out var buscada) ? buscada : libro.Worksheets.First();
		var esperados = encabezadosEsperados.Select(Normalizar).ToHashSet();

		IXLRow? encabezado = null;
		foreach (var fila in hoja.RowsUsed().Take(15))
		{
			if (fila.CellsUsed().Count(c => esperados.Contains(Normalizar(c.GetString()))) >= 2)
			{
				encabezado = fila;
				break;
			}
		}
		if (encabezado is null)
		{
			lector.Errores.Add(new MensajeCarga { Fila = 0, Mensaje = $"No se encontró la fila de encabezados. Columnas esperadas: {string.Join(", ", encabezadosEsperados)}." });
			return lector;
		}
		foreach (var celda in encabezado.CellsUsed())
			lector.columnas.TryAdd(Normalizar(celda.GetString()), celda.Address.ColumnNumber);

		foreach (var fila in hoja.RowsUsed().Where(f => f.RowNumber() > encabezado.RowNumber()))
			if (fila.CellsUsed().Any(c => !string.IsNullOrWhiteSpace(c.GetString())))
				lector.filas.Add(fila);
		return lector;
	}

	// El libro queda abierto mientras se leen las filas.
	public void Dispose() => libro?.Dispose();

	public bool TieneColumna(string nombre) => columnas.ContainsKey(Normalizar(nombre));

	public IEnumerable<string> ColumnasFaltantes(IEnumerable<string> obligatorias) =>
		obligatorias.Where(c => !TieneColumna(c));

	private IXLCell? Celda(IXLRow fila, string columna) =>
		columnas.TryGetValue(Normalizar(columna), out var numero) ? fila.Cell(numero) : null;

	public string? Texto(IXLRow fila, string columna)
	{
		var celda = Celda(fila, columna);
		if (celda is null || celda.IsEmpty()) return null;
		var texto = celda.DataType == XLDataType.Number ? celda.GetDouble().ToString(CultureInfo.InvariantCulture) : celda.GetString();
		return string.IsNullOrWhiteSpace(texto) ? null : texto.Trim();
	}

	// Primera letra en mayúscula ("Mensual" → M, "transferencia" → T).
	public string? Letra(IXLRow fila, string columna)
	{
		var texto = Texto(fila, columna);
		var normal = texto is null ? "" : Normalizar(texto);
		return normal.Length == 0 ? null : char.ToUpperInvariant(normal[0]).ToString();
	}

	public decimal? Numero(IXLRow fila, string columna)
	{
		var celda = Celda(fila, columna);
		if (celda is null || celda.IsEmpty()) return null;
		if (celda.DataType == XLDataType.Number) return Math.Round((decimal)celda.GetDouble(), 4);
		var texto = celda.GetString().Trim().Replace("Q", "", StringComparison.OrdinalIgnoreCase).Replace(" ", "");
		if (texto.Length == 0) return null;
		// Acepta 1,234.56 (Guatemala) y 1234,56.
		if (decimal.TryParse(texto, NumberStyles.Number, Guatemala, out var valor)) return valor;
		if (decimal.TryParse(texto, NumberStyles.Number, CultureInfo.GetCultureInfo("es-ES"), out valor)) return valor;
		Errores.Add(new MensajeCarga { Fila = fila.RowNumber(), Mensaje = $"La columna {columna} tiene \"{texto}\", que no es un número." });
		return null;
	}

	public DateTime? Fecha(IXLRow fila, string columna)
	{
		var celda = Celda(fila, columna);
		if (celda is null || celda.IsEmpty()) return null;
		if (celda.DataType == XLDataType.DateTime) return celda.GetDateTime().Date;
		if (celda.DataType == XLDataType.Number) return DateTime.FromOADate(celda.GetDouble()).Date;
		var texto = celda.GetString().Trim();
		if (DateTime.TryParseExact(texto, new[] { "dd/MM/yyyy", "d/M/yyyy", "yyyy-MM-dd", "dd-MM-yyyy" }, Guatemala, DateTimeStyles.None, out var fecha))
			return fecha;
		Errores.Add(new MensajeCarga { Fila = fila.RowNumber(), Mensaje = $"La columna {columna} tiene \"{texto}\", que no es una fecha (use dd/mm/aaaa)." });
		return null;
	}

	public static string Normalizar(string texto)
	{
		var sinTildes = new StringBuilder();
		foreach (var c in texto.Normalize(NormalizationForm.FormD))
			if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark && char.IsLetterOrDigit(c))
				sinTildes.Append(char.ToLowerInvariant(c));
		return sinTildes.ToString();
	}
}
