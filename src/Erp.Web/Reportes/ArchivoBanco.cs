using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Erp.Data.Pagos;

namespace Erp.Web.Reportes;

// Archivo de transferencias para el banco, según el formato configurado en
// Bancos › Formatos de archivo: delimitado (CSV, punto y coma, barra, TAB) o
// de ancho fijo, con títulos, encabezado y pie opcionales.
//
// Encabezado y pie: texto libre con marcadores {CAMPO} o {CAMPO,ancho}:
//   NUMERO, FECHA, REFERENCIA, DESCRIPCION, TOTAL, CANTIDAD, CUENTA_ORIGEN, MONEDA.
// Con ancho, TOTAL, CANTIDAD y CUENTA_ORIGEN se rellenan con ceros a la
// izquierda; el resto, con espacios a la derecha.
public static partial class ArchivoBanco
{
	public sealed record Resultado(byte[]? Contenido, string NombreArchivo, IReadOnlyList<string> Errores, IReadOnlyList<string> Avisos)
	{
		public bool Valido => Contenido is not null;
	}

	public static readonly IReadOnlyDictionary<string, string> Campos = new Dictionary<string, string>
	{
		["CORRELATIVO"] = "Correlativo (1, 2, 3…)",
		["CODIGO"] = "Código del proveedor o del empleado",
		["BENEFICIARIO"] = "Nombre del beneficiario",
		["IDENTIFICACION"] = "NIT o DPI (sin guion)",
		["BANCO_DESTINO"] = "Código del banco destino",
		["TIPO_CUENTA"] = "Tipo de cuenta destino",
		["CUENTA_DESTINO"] = "Número de cuenta destino",
		["MONTO"] = "Monto",
		["REFERENCIA"] = "Referencia o concepto",
		["CORREO"] = "Correo del beneficiario",
		["FECHA"] = "Fecha del pago",
		["CUENTA_ORIGEN"] = "Cuenta de la empresa",
		["MONEDA"] = "Moneda (GTQ, o el texto de la columna)",
		["FIJO"] = "Texto fijo"
	};

	public static Resultado Generar(FormatoArchivo formato, ArchivoBancoDatos datos)
	{
		var errores = new List<string>();
		var avisos = new List<string>();
		var enc = datos.Encabezado;
		var nombre = $"{Archivo(enc?.Numero ?? "transferencias")}-{Archivo(formato.Nombre)}.{formato.Extension.TrimStart('.')}";
		if (enc is null)
			return new Resultado(null, nombre, ["No se encontró el pago."], avisos);
		if (enc.Estado != "A")
			errores.Add("El pago está anulado.");
		if (datos.Lineas.Count == 0)
			errores.Add("El pago no tiene transferencias.");
		if (formato.Columnas.Count == 0)
			errores.Add("El formato no tiene columnas.");

		var codigos = formato.Bancos.Where(b => !string.IsNullOrWhiteSpace(b.Codigo)).ToDictionary(b => b.GefId, b => b.Codigo.Trim());
		foreach (var l in datos.Lineas)
		{
			if (string.IsNullOrWhiteSpace(l.Cuenta) || l.GefId is null)
				errores.Add($"{l.Beneficiario}: no tiene banco y número de cuenta.");
			else if (formato.Columnas.Any(c => c.Campo == "BANCO_DESTINO") && codigos.Count > 0 && !codigos.ContainsKey(l.GefId.Value))
				errores.Add($"{l.Beneficiario}: el formato no tiene código para el banco {l.Banco}.");
			if (l.Monto <= 0)
				errores.Add($"{l.Beneficiario}: el monto debe ser mayor a cero.");
		}
		if (formato.GefId is int banco && banco != enc.GefIdOrigen)
			avisos.Add($"El formato es del banco {formato.Banco}, pero la cuenta que paga es de {enc.BancoOrigen}.");

		var fin = formato.FinLinea == "LF" ? "\n" : "\r\n";
		var separador = formato.Separador == "TAB" ? "\t" : formato.Separador ?? ",";
		var fijo = formato.Tipo == "F";
		var texto = new StringBuilder();

		if (!string.IsNullOrWhiteSpace(formato.Encabezado))
			texto.Append(Plantilla(formato.Encabezado, formato, enc, errores)).Append(fin);
		if (formato.Titulos)
		{
			var titulos = formato.Columnas.Select(c => c.Titulo ?? (Campos.TryGetValue(c.Campo, out var t) ? t : c.Campo));
			texto.Append(fijo ? string.Concat(formato.Columnas.Zip(titulos, (c, t) => Ajustar(t, c, false, null)))
							  : string.Join(separador, titulos.Select(t => Delimitado(t, formato, separador)))).Append(fin);
		}

		foreach (var l in datos.Lineas)
		{
			var valores = formato.Columnas.Select(c =>
			{
				var (valor, numerico) = Valor(c, l, enc, formato, codigos);
				if (c.Mayusculas) valor = valor.ToUpperInvariant();
				valor = Limpiar(valor);
				if (fijo || c.Longitud is not null)
					valor = Ajustar(valor, c, numerico, errores, l.Beneficiario);
				return fijo ? valor : Delimitado(valor, formato, separador);
			});
			texto.Append(fijo ? string.Concat(valores) : string.Join(separador, valores)).Append(fin);
		}

		if (!string.IsNullOrWhiteSpace(formato.Pie))
			texto.Append(Plantilla(formato.Pie, formato, enc, errores)).Append(fin);

		var suma = datos.Lineas.Sum(l => l.Monto);
		if (suma != enc.Total)
			avisos.Add($"La suma de las líneas (Q{suma:N2}) no coincide con el total del pago (Q{enc.Total:N2}).");

		if (errores.Count > 0)
			return new Resultado(null, nombre, errores.Distinct().ToList(), avisos);
		var codificacion = formato.Codificacion == "UTF-8" ? (Encoding)new UTF8Encoding(false) : Encoding.Latin1;
		return new Resultado(codificacion.GetBytes(texto.ToString()), nombre, errores, avisos);
	}

	private static (string Valor, bool Numerico) Valor(FormatoColumna c, ArchivoBancoLinea l, ArchivoBancoEncabezado enc, FormatoArchivo f,
		IReadOnlyDictionary<int, string> codigos) => c.Campo switch
	{
		"CORRELATIVO" => (l.Correlativo.ToString(CultureInfo.InvariantCulture), true),
		"CODIGO" => (l.Codigo ?? "", false),
		"BENEFICIARIO" => (l.Beneficiario, false),
		"IDENTIFICACION" => (SoloAlfanumerico(l.Identificacion), false),
		"BANCO_DESTINO" => (l.GefId is int g && codigos.TryGetValue(g, out var codigo) ? codigo : l.BancoCodigo ?? "", false),
		"TIPO_CUENTA" => (l.TipoCuenta == "A" ? f.CodigoAhorro : f.CodigoMonetaria, false),
		"CUENTA_DESTINO" => (SoloAlfanumerico(l.Cuenta), true),
		"MONTO" => (Monto(l.Monto, f), true),
		"REFERENCIA" => (l.Referencia ?? enc.Referencia ?? "", false),
		"CORREO" => (l.Correo ?? "", false),
		"FECHA" => (enc.Fecha.ToString(f.FormatoFecha, CultureInfo.InvariantCulture), false),
		"CUENTA_ORIGEN" => (SoloAlfanumerico(enc.CuentaOrigen), true),
		"MONEDA" => (string.IsNullOrEmpty(c.Valor) ? "GTQ" : c.Valor, false),
		"FIJO" => (c.Valor ?? "", false),
		_ => ("", false)
	};

	public static string Monto(decimal monto, FormatoArchivo f)
	{
		var redondeado = Math.Round(monto, f.Decimales, MidpointRounding.AwayFromZero);
		if (f.MontoSinPunto)
			return decimal.Truncate(redondeado * (decimal)Math.Pow(10, f.Decimales)).ToString(CultureInfo.InvariantCulture);
		var texto = redondeado.ToString("F" + f.Decimales, CultureInfo.InvariantCulture);
		return f.SeparadorDecimal == "," ? texto.Replace('.', ',') : texto;
	}

	// Ancho fijo: rellena o recorta. Un número que no cabe no se recorta (cambiaría
	// la cuenta o el monto): es un error del formato.
	private static string Ajustar(string valor, FormatoColumna c, bool numerico, List<string>? errores, string? quien = null)
	{
		if (c.Longitud is not int ancho) return valor;
		if (valor.Length > ancho)
		{
			if (numerico && errores is not null)
			{
				errores.Add($"{quien}: el valor de {c.Campo} ({valor}) no cabe en {ancho} posiciones.");
				return valor;
			}
			return valor[..ancho];
		}
		var relleno = string.IsNullOrEmpty(c.Relleno) ? ' ' : c.Relleno[0];
		return c.Alineacion == "D" ? valor.PadLeft(ancho, relleno) : valor.PadRight(ancho, relleno);
	}

	private static string Delimitado(string valor, FormatoArchivo f, string separador) =>
		f.Comillas ? "\"" + valor.Replace("\"", "\"\"") + "\"" : valor.Replace(separador, " ").Replace("\"", "");

	private static string Plantilla(string plantilla, FormatoArchivo f, ArchivoBancoEncabezado enc, List<string> errores) =>
		Marcador().Replace(plantilla, m =>
		{
			var campo = m.Groups["campo"].Value.ToUpperInvariant();
			var (valor, numerico) = campo switch
			{
				"NUMERO" => (enc.Numero, false),
				"FECHA" => (enc.Fecha.ToString(f.FormatoFecha, CultureInfo.InvariantCulture), false),
				"REFERENCIA" => (enc.Referencia ?? "", false),
				"DESCRIPCION" => (enc.Descripcion ?? "", false),
				"TOTAL" => (Monto(enc.Total, f), true),
				"CANTIDAD" => (enc.Cantidad.ToString(CultureInfo.InvariantCulture), true),
				"CUENTA_ORIGEN" => (SoloAlfanumerico(enc.CuentaOrigen), true),
				"MONEDA" => ("GTQ", false),
				_ => (m.Value, false)
			};
			valor = Limpiar(valor);
			if (!m.Groups["ancho"].Success) return valor;
			var ancho = int.Parse(m.Groups["ancho"].Value, CultureInfo.InvariantCulture);
			if (valor.Length > ancho)
			{
				if (numerico) errores.Add($"El valor de {campo} ({valor}) no cabe en {ancho} posiciones del encabezado o pie.");
				return numerico ? valor : valor[..ancho];
			}
			return numerico ? valor.PadLeft(ancho, '0') : valor.PadRight(ancho);
		});

	// Sin tildes ni saltos de línea: los bancos rechazan caracteres fuera de lo básico.
	private static string Limpiar(string valor)
	{
		var sinTildes = new StringBuilder(valor.Length);
		foreach (var ch in valor.Replace('\r', ' ').Replace('\n', ' ').Replace('\t', ' '))
			sinTildes.Append(ch switch
			{
				'á' => 'a', 'é' => 'e', 'í' => 'i', 'ó' => 'o', 'ú' => 'u', 'ü' => 'u',
				'Á' => 'A', 'É' => 'E', 'Í' => 'I', 'Ó' => 'O', 'Ú' => 'U', 'Ü' => 'U',
				_ => ch
			});
		return sinTildes.ToString().Trim();
	}

	private static string SoloAlfanumerico(string? valor) => valor is null ? "" : NoAlfanumerico().Replace(valor, "");

	private static string Archivo(string valor) => NoArchivo().Replace(Limpiar(valor), "-").Trim('-').ToLowerInvariant();

	[GeneratedRegex(@"\{(?<campo>[A-Za-z_]+)(,(?<ancho>\d{1,3}))?\}")]
	private static partial Regex Marcador();

	[GeneratedRegex(@"[^0-9A-Za-z]")]
	private static partial Regex NoAlfanumerico();

	[GeneratedRegex(@"[^0-9A-Za-z]+")]
	private static partial Regex NoArchivo();
}
