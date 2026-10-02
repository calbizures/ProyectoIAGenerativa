namespace Erp.Data.General;

// Validación del NIT y del CUI de Guatemala, igual que dbo.fnNitValido y
// dbo.fnCuiValido (44_nit_certificadores_seguridad.sql): la pantalla avisa
// antes de grabar y la base lo exige en toda escritura.
public static class NitValidador
{
	// Municipios por departamento (01 Guatemala ... 22 Jutiapa).
	private static readonly int[] MunicipiosPorDepartamento =
		[17, 8, 16, 16, 14, 14, 19, 8, 24, 21, 9, 30, 33, 21, 8, 17, 14, 5, 11, 11, 7, 17];

	// Sin espacios, guiones, puntos ni diagonales y en mayúsculas ("c/f" -> "CF").
	public static string? Normalizar(string? nit)
	{
		if (string.IsNullOrWhiteSpace(nit)) return null;
		var limpio = new string(nit.Where(c => !char.IsWhiteSpace(c) && c is not '-' and not '/' and not '.').ToArray()).ToUpperInvariant();
		return limpio.Length == 0 ? null : limpio;
	}

	public static bool EsConsumidorFinal(string? nit) => Normalizar(nit) == "CF";

	// Vacío o C/F son válidos (el dato es opcional o es consumidor final).
	public static bool EsValido(string? nit)
	{
		var n = Normalizar(nit);
		if (n is null || n == "CF") return true;
		if (n.Length == 13 && n.All(char.IsAsciiDigit)) return EsCuiValido(n);

		var cuerpo = n[..^1];
		var verificador = n[^1];
		if (n.Length < 2 || !cuerpo.All(char.IsAsciiDigit) || !(char.IsAsciiDigit(verificador) || verificador == 'K'))
			return false;

		var suma = 0;
		for (int i = cuerpo.Length - 1, peso = 2; i >= 0; i--, peso++)
			suma += (cuerpo[i] - '0') * peso;
		var resultado = (11 - suma % 11) % 11;
		if (verificador == (resultado == 10 ? 'K' : (char)('0' + resultado)))
			return true;
		// NIT de 9 dígitos asignado con el CUI (inscritos desde 2023).
		return n.Length == 9 && CorrelativoCuiValido(n);
	}

	// CUI/DPI: correlativo (8) + verificador (1) + departamento (2) + municipio (2).
	public static bool EsCuiValido(string? cui)
	{
		var c = Normalizar(cui);
		if (c is null || c.Length != 13 || !c.All(char.IsAsciiDigit)) return false;
		var departamento = int.Parse(c.Substring(9, 2));
		var municipio = int.Parse(c.Substring(11, 2));
		if (departamento is < 1 or > 22 || municipio < 1 || municipio > MunicipiosPorDepartamento[departamento - 1])
			return false;
		return CorrelativoCuiValido(c);
	}

	public static bool EsCui(string? nit)
	{
		var n = Normalizar(nit);
		return n is { Length: 13 } && n.All(char.IsAsciiDigit);
	}

	// Como se guarda: "1234567-9", "CF" o el CUI sin espacios.
	public static string? Formatear(string? nit)
	{
		var n = Normalizar(nit);
		if (n is null || n == "CF" || EsCui(n) || n.Length < 2) return n;
		return $"{n[..^1]}-{n[^1]}";
	}

	public static string MensajeInvalido(string? nit, string dato = "NIT") =>
		$"El {dato} {nit} no es válido: revise el dígito verificador (o use C/F o el CUI de 13 dígitos).";

	private static bool CorrelativoCuiValido(string digitos)
	{
		var suma = 0;
		for (var i = 0; i < 8; i++)
			suma += (digitos[i] - '0') * (i + 2);
		return suma % 11 == digitos[8] - '0';
	}
}
