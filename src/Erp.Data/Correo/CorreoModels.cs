namespace Erp.Data.Correo;

// Servidor de correo saliente de la compañía. La contraseña viaja cifrada
// (la cifra y descifra la aplicación); nunca se muestra en pantalla.
public sealed class CorreoConfiguracion
{
	public int CiaId { get; set; }
	public string NombreComercial { get; set; } = "";
	// GMAIL, OUTLOOK, OFFICE365, YAHOO, SMTP (otro servidor) o CARPETA (guarda
	// el correo como .eml en la carpeta indicada en Servidor, sin enviarlo).
	public string Proveedor { get; set; } = "GMAIL";
	public string? Servidor { get; set; }
	public int Puerto { get; set; } = 587;
	public bool Ssl { get; set; } = true;
	public string? Usuario { get; set; }
	public string? ClaveCifrada { get; set; }
	public string? Remitente { get; set; }
	public string? RemitenteNombre { get; set; }
	public string? Copia { get; set; }
	public string? Telefono { get; set; }
	public bool Configurado => !string.IsNullOrWhiteSpace(Servidor) && !string.IsNullOrWhiteSpace(Remitente);
	public bool EsCarpeta => Proveedor == "CARPETA";

	// Datos de conexión de cada proveedor conocido (servidor, puerto, STARTTLS).
	public static readonly IReadOnlyList<(string Codigo, string Nombre, string? Servidor, int Puerto, bool Ssl)> Proveedores = new[]
	{
		("GMAIL", "Gmail", "smtp.gmail.com", 587, true),
		("OUTLOOK", "Outlook.com / Hotmail", "smtp-mail.outlook.com", 587, true),
		("OFFICE365", "Microsoft 365 (correo de la empresa)", "smtp.office365.com", 587, true),
		("YAHOO", "Yahoo", "smtp.mail.yahoo.com", 587, true),
		("SMTP", "Otro servidor SMTP", (string?)null, 587, true),
		("CARPETA", "Guardar en una carpeta (no envía)", (string?)null, 0, false)
	};
}

public sealed class CorreoEnviado
{
	public int GcbId { get; set; }
	public string Tipo { get; set; } = "";
	public int? ReferenciaId { get; set; }
	public string Destinatario { get; set; } = "";
	public string? Copia { get; set; }
	public string Asunto { get; set; } = "";
	public string? Adjunto { get; set; }
	// E = el servidor lo aceptó, F = falló
	public string Estado { get; set; } = "E";
	public string? Error { get; set; }
	public DateTime Fecha { get; set; }
	public string? Usuario { get; set; }
}

public sealed record CorreoBitacora(int CiaId, string Tipo, int? ReferenciaId, string Destinatario, string? Copia, string Asunto, string? Adjunto,
	bool Enviado, string? Error, int? UsuId);
