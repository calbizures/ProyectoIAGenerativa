using System.Globalization;

namespace Erp.Web.Components.Shared.Graficos;

// Serie de un gráfico de columnas. Slot = posición fija en la paleta
// categórica (el color sigue a la serie, no a su orden en pantalla).
public sealed record SerieGrafico(string Nombre, IReadOnlyList<decimal> Valores, int Slot = 1);

// Fila de un ranking de barras horizontales.
public sealed record BarraFila(int Id, string Etiqueta, decimal Valor, string? Detalle = null);

// Parte de un total (barra 100 %).
public sealed record ParteTotal(string Nombre, decimal Valor, int Slot);

public static class PaletaGraficos
{
	// Paleta categórica validada (orden fijo) contra el fondo blanco de las tarjetas.
	private static readonly string[] Categorica = { "#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948" };

	public static string Color(int slot) => Categorica[Math.Clamp(slot, 1, Categorica.Length) - 1];

	private static readonly CultureInfo Cultura = CultureInfo.GetCultureInfo("es-GT");

	public static string Moneda(decimal valor) => "Q" + valor.ToString("N2", CultureInfo.InvariantCulture);

	// Cifras compactas para ejes y mosaicos: Q950, Q12.4 mil, Q1.2 M.
	public static string MonedaCompacta(decimal valor)
	{
		var abs = Math.Abs(valor);
		var signo = valor < 0 ? "-" : "";
		if (abs >= 1_000_000m) return $"{signo}Q{(abs / 1_000_000m).ToString("0.#", CultureInfo.InvariantCulture)} M";
		if (abs >= 1_000m) return $"{signo}Q{(abs / 1_000m).ToString("0.#", CultureInfo.InvariantCulture)} mil";
		return $"{signo}Q{abs.ToString("#,0", CultureInfo.InvariantCulture)}";
	}

	public static string Porcentaje(decimal valor) => valor.ToString("0.0", CultureInfo.InvariantCulture) + " %";

	public static string Mes(DateTime fecha) => Cultura.TextInfo.ToTitleCase(fecha.ToString("MMM yyyy", Cultura).Replace(".", ""));
	public static string Dia(DateTime fecha) => fecha.ToString("dd/MM", CultureInfo.InvariantCulture);

	// Tope "redondo" del eje: 1, 2, 2.5 o 5 por potencia de 10.
	public static decimal TopeEje(decimal maximo, int divisiones = 4)
	{
		if (maximo <= 0) return divisiones;
		var paso = (double)maximo / divisiones;
		var potencia = Math.Pow(10, Math.Floor(Math.Log10(paso)));
		foreach (var m in new[] { 1, 2, 2.5, 5, 10 })
			if (m * potencia >= paso) return (decimal)(m * potencia * divisiones);
		return (decimal)(10 * potencia * divisiones);
	}
}
