namespace Erp.Web.Reportes;

// Monto en letras para facturas y cheques:
// 4300.50 -> "CUATRO MIL TRESCIENTOS QUETZALES CON 50/100".
public static class NumeroALetras
{
	private static readonly string[] Unidades =
		["", "UN", "DOS", "TRES", "CUATRO", "CINCO", "SEIS", "SIETE", "OCHO", "NUEVE", "DIEZ",
		 "ONCE", "DOCE", "TRECE", "CATORCE", "QUINCE", "DIECISÉIS", "DIECISIETE", "DIECIOCHO", "DIECINUEVE", "VEINTE",
		 "VEINTIÚN", "VEINTIDÓS", "VEINTITRÉS", "VEINTICUATRO", "VEINTICINCO", "VEINTISÉIS", "VEINTISIETE", "VEINTIOCHO", "VEINTINUEVE"];
	private static readonly string[] Decenas = ["", "", "", "TREINTA", "CUARENTA", "CINCUENTA", "SESENTA", "SETENTA", "OCHENTA", "NOVENTA"];
	private static readonly string[] Centenas =
		["", "CIENTO", "DOSCIENTOS", "TRESCIENTOS", "CUATROCIENTOS", "QUINIENTOS", "SEISCIENTOS", "SETECIENTOS", "OCHOCIENTOS", "NOVECIENTOS"];

	public static string Convertir(decimal monto, string monedaSingular = "QUETZAL", string monedaPlural = "QUETZALES")
	{
		monto = Math.Round(Math.Abs(monto), 2);
		var entero = (long)Math.Truncate(monto);
		var centavos = (int)Math.Round((monto - entero) * 100);
		var letras = entero == 0 ? "CERO" : Entero(entero);
		var moneda = entero == 1 ? monedaSingular : monedaPlural;
		// "UN MILLÓN DE QUETZALES", "DOS MILLONES DE QUETZALES".
		if (entero >= 1_000_000 && entero % 1_000_000 == 0) moneda = "DE " + moneda;
		return $"{letras} {moneda} CON {centavos:00}/100";
	}

	private static string Entero(long n)
	{
		if (n >= 1_000_000)
		{
			var millones = n / 1_000_000;
			var resto = n % 1_000_000;
			var texto = millones == 1 ? "UN MILLÓN" : $"{Entero(millones)} MILLONES";
			return resto == 0 ? texto : $"{texto} {Entero(resto)}";
		}
		if (n >= 1000)
		{
			var miles = n / 1000;
			var resto = n % 1000;
			var texto = miles == 1 ? "MIL" : $"{Centena((int)miles)} MIL";
			return resto == 0 ? texto : $"{texto} {Centena((int)resto)}";
		}
		return Centena((int)n);
	}

	private static string Centena(int n)
	{
		if (n == 100) return "CIEN";
		var c = n / 100;
		var resto = n % 100;
		var texto = Centenas[c];
		if (resto == 0) return texto;
		var decenas = resto < 30 ? Unidades[resto] : Decenas[resto / 10] + (resto % 10 == 0 ? "" : " Y " + Unidades[resto % 10]);
		return string.IsNullOrEmpty(texto) ? decenas : $"{texto} {decenas}";
	}
}
