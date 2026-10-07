namespace Erp.Web.Components.Shared;

// Comprobante o boleta adjunto en pantalla, antes de grabarlo: PDF o imagen
// de hasta 5 MB. El tipo se toma del contenido del archivo, no de lo que
// dice el navegador.
public sealed record ArchivoCargado(string Nombre, string Tipo, byte[] Contenido)
{
	public const long TamanoMaximo = 5 * 1024 * 1024;
	public const string TiposAceptados = "application/pdf,image/png,image/jpeg,image/webp,image/gif";

	public static string? TipoDesdeContenido(byte[] datos)
	{
		bool Empieza(params byte[] firma) => datos.Length >= firma.Length && datos.AsSpan(0, firma.Length).SequenceEqual(firma);
		if (Empieza(0x25, 0x50, 0x44, 0x46)) return "application/pdf";
		if (Empieza(0x89, 0x50, 0x4E, 0x47)) return "image/png";
		if (Empieza(0xFF, 0xD8, 0xFF)) return "image/jpeg";
		if (Empieza(0x47, 0x49, 0x46, 0x38)) return "image/gif";
		if (datos.Length >= 12 && Empieza(0x52, 0x49, 0x46, 0x46) && datos.AsSpan(8, 4).SequenceEqual("WEBP"u8)) return "image/webp";
		return null;
	}

	public static string TamanoTexto(long bytes) =>
		bytes < 1024 * 1024 ? $"{Math.Max(1, bytes / 1024)} KB" : $"{bytes / (1024d * 1024):N1} MB";
}
