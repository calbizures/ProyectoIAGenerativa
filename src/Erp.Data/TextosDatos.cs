namespace Erp.Data;

// Etiquetas de los modelos (estados, tipos) en el idioma del usuario. La
// aplicación web conecta aquí su traductor al arrancar (Erp.Web/Idioma);
// sin él, los textos quedan en español.
public static class TextosDatos
{
	public static Func<string, string> Traductor { get; set; } = texto => texto;

	public static string L(string texto) => Traductor(texto);

	public static string L(string texto, params object?[] valores) =>
		string.Format(System.Globalization.CultureInfo.CurrentCulture, Traductor(texto), valores);
}
