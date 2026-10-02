namespace Erp.Data.Correo;

// Servidor de correo saliente de la compañía. La contraseña viaja cifrada
// (la cifra y descifra la aplicación); nunca se muestra en pantalla.
public sealed class CorreoConfiguracion
{
	public int CiaId { get; set; }
	public string NombreComercial { get; set; } = "";
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
