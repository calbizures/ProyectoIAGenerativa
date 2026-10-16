using System.Net;
using System.Net.Mail;
using System.Net.Mime;
using System.Security.Cryptography;
using Erp.Data.Correo;
using Microsoft.AspNetCore.DataProtection;

namespace Erp.Web.Correo;

// Envío de correos con el servidor SMTP de la compañía (STARTTLS en el 587;
// por defecto Gmail) o, con la salida CARPETA, como archivos .eml sin enviar.
// La contraseña se guarda cifrada con Data Protection: si las llaves del
// servidor cambian, hay que volver a escribirla en Compañías.
public sealed class CorreoServicio(ICorreoRepository correos, IDataProtectionProvider proteccion, ILogger<CorreoServicio> bitacora)
{
	private readonly IDataProtector protector = proteccion.CreateProtector("Erp.Correo.Smtp.v1");

	public sealed record Adjunto(string Nombre, byte[] Contenido, string Tipo);

	public sealed record Resultado(bool Enviado, string Mensaje);

	public string Cifrar(string clave) => protector.Protect(clave);

	public Task<Resultado> EnviarAsync(int ciaId, string tipo, int? referenciaId, string para, string? copia, string asunto,
		string html, string texto, Adjunto? adjunto, int? usuId, CancellationToken cancelacion = default) =>
		EnviarConAdjuntosAsync(ciaId, tipo, referenciaId, para, copia, asunto, html, texto, adjunto is null ? Array.Empty<Adjunto>() : new[] { adjunto }, usuId, cancelacion);

	// Con varios adjuntos (por ejemplo, la factura en PDF y su XML certificado).
	public async Task<Resultado> EnviarConAdjuntosAsync(int ciaId, string tipo, int? referenciaId, string para, string? copia, string asunto,
		string html, string texto, IReadOnlyList<Adjunto> adjuntos, int? usuId, CancellationToken cancelacion = default)
	{
		var config = await correos.ConsultarConfiguracionAsync(ciaId);
		if (config is null || !config.Configurado)
			return new Resultado(false, "La compañía no tiene configurado el correo saliente. Configúrelo en General › Compañías › Correo saliente.");

		var destinos = Direcciones(para);
		var copias = Direcciones(string.Join(",", new[] { copia, config.Copia }.Where(c => !string.IsNullOrWhiteSpace(c))));
		if (destinos.Count == 0)
			return new Resultado(false, "Indique al menos un correo de destino válido.");
		var invalido = destinos.Concat(copias).FirstOrDefault(d => !MailAddress.TryCreate(d, out _));
		if (invalido is not null)
			return new Resultado(false, $"El correo «{invalido}» no es válido.");

		string? clave = null;
		if (!string.IsNullOrEmpty(config.ClaveCifrada))
		{
			try { clave = protector.Unprotect(config.ClaveCifrada); }
			catch (CryptographicException)
			{
				return new Resultado(false, "No se pudo leer la contraseña del correo guardada (cambiaron las llaves del servidor). Vuelva a escribirla en Compañías.");
			}
		}

		string? error = null;
		try
		{
			using var mensaje = new MailMessage
			{
				From = new MailAddress(config.Remitente!, config.RemitenteNombre ?? config.NombreComercial),
				Subject = asunto,
				SubjectEncoding = System.Text.Encoding.UTF8,
				BodyEncoding = System.Text.Encoding.UTF8,
				IsBodyHtml = false,
				Body = texto
			};
			mensaje.AlternateViews.Add(AlternateView.CreateAlternateViewFromString(html, System.Text.Encoding.UTF8, MediaTypeNames.Text.Html));
			foreach (var d in destinos) mensaje.To.Add(d);
			foreach (var c in copias.Except(destinos, StringComparer.OrdinalIgnoreCase)) mensaje.CC.Add(c);
			foreach (var adjunto in adjuntos)
				mensaje.Attachments.Add(new Attachment(new MemoryStream(adjunto.Contenido), adjunto.Nombre, adjunto.Tipo));

			if (config.EsCarpeta)
			{
				// Sin envío: el correo queda como archivo .eml en la carpeta.
				Directory.CreateDirectory(config.Servidor!);
				using var carpeta = new SmtpClient { DeliveryMethod = SmtpDeliveryMethod.SpecifiedPickupDirectory, PickupDirectoryLocation = config.Servidor };
				await carpeta.SendMailAsync(mensaje, cancelacion);
			}
			else
			{
				using var cliente = new SmtpClient(config.Servidor, config.Puerto)
				{
					EnableSsl = config.Ssl,
					DeliveryMethod = SmtpDeliveryMethod.Network,
					Timeout = 30000,
					UseDefaultCredentials = false
				};
				if (!string.IsNullOrWhiteSpace(config.Usuario))
					cliente.Credentials = new NetworkCredential(config.Usuario, clave ?? "");
				await cliente.SendMailAsync(mensaje, cancelacion);
			}
		}
		catch (Exception ex) when (ex is SmtpException or InvalidOperationException or IOException or FormatException or UnauthorizedAccessException)
		{
			bitacora.LogWarning(ex, "No se pudo enviar el correo {Tipo} a {Para}", tipo, para);
			error = Traducir(ex);
		}

		await correos.RegistrarAsync(new CorreoBitacora(ciaId, tipo, referenciaId, string.Join(", ", destinos),
			copias.Count == 0 ? null : string.Join(", ", copias), asunto,
			adjuntos.Count == 0 ? null : Recortar(string.Join(", ", adjuntos.Select(a => a.Nombre)), 150), error is null, error, usuId));
		return error is null
			? new Resultado(true, config.EsCarpeta
				? $"Correo para {string.Join(", ", destinos)} guardado en la carpeta {config.Servidor} (no se envió)."
				: $"Correo enviado a {string.Join(", ", destinos)}{(copias.Count == 0 ? "" : $" con copia a {string.Join(", ", copias)}")}.")
			: new Resultado(false, error);
	}

	private static string Recortar(string texto, int largo) => texto.Length <= largo ? texto : texto[..(largo - 1)] + "…";

	private static List<string> Direcciones(string? texto) =>
		(texto ?? "").Split(new[] { ',', ';', ' ' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
			.Distinct(StringComparer.OrdinalIgnoreCase).ToList();

	private static string Traducir(Exception ex)
	{
		var raiz = ex.InnerException?.Message ?? ex.Message;
		return ex switch
		{
			SmtpException { StatusCode: SmtpStatusCode.MustIssueStartTlsFirst } => "El servidor exige conexión segura: active STARTTLS.",
			SmtpException s when s.Message.Contains("authentication", StringComparison.OrdinalIgnoreCase) || (int)s.StatusCode == 535
				=> "El servidor rechazó el usuario o la contraseña del correo. En Gmail use una contraseña de aplicación (no la contraseña normal de la cuenta).",
			UnauthorizedAccessException => $"No se pudo guardar el correo en la carpeta: el servidor no tiene permiso de escritura ({raiz}).",
			SmtpException { StatusCode: SmtpStatusCode.MailboxUnavailable or SmtpStatusCode.MailboxNameNotAllowed }
				=> "El servidor no aceptó el correo de destino.",
			SmtpException s when s.InnerException is System.Net.Sockets.SocketException or IOException
				=> $"No se pudo conectar con el servidor de correo ({raiz}). Revise el servidor, el puerto y STARTTLS.",
			SmtpException s => $"El servidor de correo respondió: {s.Message}",
			_ => $"No se pudo enviar el correo: {raiz}"
		};
	}
}
