using System.Globalization;
using System.Text;
using ClosedXML.Excel;
using Erp.Data.Conciliacion;

namespace Erp.Web.Reportes;

// Lee el estado de cuenta que descarga la banca en línea (Excel o CSV). Busca
// la fila de títulos entre las primeras 30 (la que tiene Fecha y Débito/
// Crédito o Monto) y reconoce los nombres más comunes de cada columna; los
// montos pueden venir como 1,234.56, 1.234,56, (45.00) o -45.
public static class ExtractoBancario
{
	public sealed record Resultado(IReadOnlyList<NuevaLineaExtracto> Lineas, IReadOnlyList<string> Errores, decimal? SaldoFinal, decimal? SaldoInicial);

	private static readonly string[] Fechas = { "fecha", "fechaoperacion", "fechamovimiento", "fechacontable", "fechavalor", "date" };
	private static readonly string[] Descripciones = { "descripcion", "concepto", "detalle", "movimiento", "transaccion", "description" };
	private static readonly string[] Referencias = { "referencia", "documento", "nodocumento", "numerodocumento", "numero", "nodoc", "cheque", "ref" };
	private static readonly string[] Debitos = { "debito", "debitos", "cargo", "cargos", "retiro", "retiros", "debe", "egreso", "egresos" };
	private static readonly string[] Creditos = { "credito", "creditos", "abono", "abonos", "deposito", "depositos", "haber", "ingreso", "ingresos" };
	private static readonly string[] Montos = { "monto", "importe", "valor", "amount" };
	private static readonly string[] Saldos = { "saldo", "saldodisponible", "saldocontable", "balance" };

	public static readonly string[] ColumnasPlantilla = { "Fecha", "Descripción", "Referencia", "Débito", "Crédito", "Saldo" };

	public static Resultado Leer(Stream archivo, string nombre)
	{
		var filas = nombre.EndsWith(".csv", StringComparison.OrdinalIgnoreCase) || nombre.EndsWith(".txt", StringComparison.OrdinalIgnoreCase)
			? LeerCsv(archivo)
			: LeerExcel(archivo);
		return Interpretar(filas);
	}

	private static List<List<object?>> LeerExcel(Stream archivo)
	{
		using var libro = new XLWorkbook(archivo);
		var hoja = libro.Worksheets.First();
		var filas = new List<List<object?>>();
		var ultima = hoja.LastColumnUsed()?.ColumnNumber() ?? 0;
		foreach (var fila in hoja.RowsUsed())
		{
			var valores = new List<object?>();
			for (var c = 1; c <= ultima; c++)
			{
				var celda = fila.Cell(c);
				valores.Add(celda.IsEmpty() ? null
					: celda.DataType switch
					{
						XLDataType.DateTime => celda.GetDateTime(),
						XLDataType.Number => (object)(decimal)celda.GetDouble(),
						_ => celda.GetString()
					});
			}
			filas.Add(valores);
		}
		return filas;
	}

	private static List<List<object?>> LeerCsv(Stream archivo)
	{
		using var memoria = new MemoryStream();
		archivo.CopyTo(memoria);
		var bytes = memoria.ToArray();
		string texto;
		try { texto = new UTF8Encoding(false, true).GetString(bytes); }
		catch (DecoderFallbackException) { texto = Encoding.Latin1.GetString(bytes); }
		var lineas = texto.Replace("\r\n", "\n").Split('\n').Where(l => l.Trim().Length > 0).ToList();
		var muestra = lineas.Take(30).ToList();
		var separador = new[] { ';', ',', '\t', '|' }.OrderByDescending(s => muestra.Max(l => l.Count(c => c == s))).First();
		return lineas.Select(l => Dividir(l, separador).Select(v => (object?)(string.IsNullOrWhiteSpace(v) ? null : v.Trim())).ToList()).ToList();
	}

	// Separa una línea CSV respetando comillas.
	private static List<string> Dividir(string linea, char separador)
	{
		var campos = new List<string>();
		var actual = new StringBuilder();
		var comillas = false;
		for (var i = 0; i < linea.Length; i++)
		{
			var c = linea[i];
			if (c == '"')
			{
				if (comillas && i + 1 < linea.Length && linea[i + 1] == '"') { actual.Append('"'); i++; }
				else comillas = !comillas;
			}
			else if (c == separador && !comillas) { campos.Add(actual.ToString()); actual.Clear(); }
			else actual.Append(c);
		}
		campos.Add(actual.ToString());
		return campos;
	}

	private static int Columna(List<object?> titulos, string[] alias) =>
		titulos.FindIndex(t => t is string s && alias.Contains(LectorExcel.Normalizar(s)));

	private static Resultado Interpretar(List<List<object?>> filas)
	{
		var errores = new List<string>();
		var lineas = new List<NuevaLineaExtracto>();
		var inicio = filas.Take(30).ToList().FindIndex(f => Columna(f, Fechas) >= 0
			&& (Columna(f, Debitos) >= 0 || Columna(f, Creditos) >= 0 || Columna(f, Montos) >= 0));
		if (inicio < 0)
		{
			errores.Add("No se encontró la fila de títulos: el archivo necesita una columna Fecha y las columnas Débito y Crédito (o una columna Monto con signo). Descargue la plantilla para ver el formato.");
			return new Resultado(lineas, errores, null, null);
		}
		var titulos = filas[inicio];
		int cFecha = Columna(titulos, Fechas), cDesc = Columna(titulos, Descripciones), cRef = Columna(titulos, Referencias),
			cDeb = Columna(titulos, Debitos), cCred = Columna(titulos, Creditos), cMonto = Columna(titulos, Montos), cSaldo = Columna(titulos, Saldos);
		decimal? saldoInicial = null, saldoFinal = null;

		for (var i = inicio + 1; i < filas.Count; i++)
		{
			var fila = filas[i];
			object? Valor(int c) => c >= 0 && c < fila.Count ? fila[c] : null;
			var numeroFila = i + 1;
			if (fila.All(v => v is null)) continue;
			var fecha = Fecha(Valor(cFecha));
			if (fecha is null)
			{
				// Filas de totales o saldos al pie: se ignoran.
				if (Valor(cFecha) is not null && lineas.Count == 0) errores.Add($"Fila {numeroFila}: \"{Valor(cFecha)}\" no es una fecha (use dd/mm/aaaa).");
				continue;
			}
			decimal debito = 0, credito = 0;
			if (cDeb >= 0 || cCred >= 0)
			{
				debito = Math.Abs(Monto(Valor(cDeb)) ?? 0);
				credito = Math.Abs(Monto(Valor(cCred)) ?? 0);
			}
			else
			{
				var monto = Monto(Valor(cMonto)) ?? 0;
				if (monto < 0) debito = -monto; else credito = monto;
			}
			if (debito == 0 && credito == 0) continue;
			if (debito > 0 && credito > 0)
			{
				errores.Add($"Fila {numeroFila}: tiene débito y crédito; deje solo uno.");
				continue;
			}
			var saldo = Monto(Valor(cSaldo));
			if (saldo is not null)
			{
				saldoInicial ??= saldo - credito + debito;
				saldoFinal = saldo;
			}
			lineas.Add(new NuevaLineaExtracto
			{
				Fecha = fecha.Value,
				Descripcion = Valor(cDesc)?.ToString(),
				Referencia = Valor(cRef) switch { decimal d => d.ToString("0", CultureInfo.InvariantCulture), var v => v?.ToString() },
				Debito = Math.Round(debito, 2),
				Credito = Math.Round(credito, 2)
			});
		}
		if (lineas.Count == 0 && errores.Count == 0) errores.Add("El archivo no tiene movimientos con fecha y monto.");
		return new Resultado(lineas, errores, saldoFinal, saldoInicial);
	}

	private static DateTime? Fecha(object? valor)
	{
		switch (valor)
		{
			case DateTime fecha: return fecha.Date;
			case decimal numero when numero > 20000 && numero < 80000: return DateTime.FromOADate((double)numero).Date;
			case string texto:
				var formatos = new[] { "dd/MM/yyyy", "d/M/yyyy", "dd/MM/yy", "d/M/yy", "yyyy-MM-dd", "dd-MM-yyyy", "d-M-yyyy", "dd.MM.yyyy", "dd/MM/yyyy HH:mm:ss", "yyyy-MM-ddTHH:mm:ss" };
				return DateTime.TryParseExact(texto.Trim(), formatos, CultureInfo.InvariantCulture, DateTimeStyles.None, out var leida) ? leida.Date : null;
			default: return null;
		}
	}

	private static decimal? Monto(object? valor)
	{
		switch (valor)
		{
			case decimal numero: return numero;
			case string texto:
				var limpio = texto.Trim().Replace("Q", "", StringComparison.OrdinalIgnoreCase).Replace("GTQ", "", StringComparison.OrdinalIgnoreCase).Replace(" ", "");
				if (limpio.Length == 0 || limpio == "-") return null;
				var negativo = limpio.StartsWith('(') && limpio.EndsWith(')') || limpio.EndsWith('-');
				limpio = limpio.Trim('(', ')').TrimEnd('-');
				// 1.234,56 → coma decimal; 1,234.56 → punto decimal.
				if (limpio.Contains(',') && (!limpio.Contains('.') || limpio.LastIndexOf(',') > limpio.LastIndexOf('.')))
					limpio = limpio.Replace(".", "").Replace(',', '.');
				else
					limpio = limpio.Replace(",", "");
				if (!decimal.TryParse(limpio, NumberStyles.Number, CultureInfo.InvariantCulture, out var monto)) return null;
				return negativo ? -monto : monto;
			default: return null;
		}
	}
}
