namespace Erp.Web.Components.Shared;

// Cantidades y montos capturados en pantalla: a lo más dos decimales y sin
// ceros de sobra (la base guarda las cantidades con escala 4, y 1.0000 se
// mostraría así en el campo).
public static class Montos
{
	public static decimal DosDecimales(decimal valor) =>
		Math.Round(valor, 2, MidpointRounding.AwayFromZero) / 1.000000000000000000000000000000000m;
}
