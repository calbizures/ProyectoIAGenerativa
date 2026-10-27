using System.Net;
using System.Security.Cryptography;
using Erp.Data.General;

namespace Erp.Web.Correo;

// Contraseña temporal de un usuario: la genera y la envía por correo con el
// servidor SMTP de la compañía. El usuario debe cambiarla al iniciar sesión.
// La bitácora de correos guarda el asunto, nunca el cuerpo con la contraseña.
public sealed class ContrasenaCorreo(IGeneralRepository general, CorreoServicio correo)
{
	public const string Tipo = "CONTRASENA";

	// Sin letras ni números que se confundan al leerlos (0/O, 1/l/I).
	private const string Letras = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ";
	private const string Numeros = "23456789";

	// 10 caracteres con al menos una letra y un número (la política de la base
	// pide 8 o más, con letras y números).
	public static string Generar()
	{
		var todos = Letras + Numeros;
		var caracteres = new char[10];
		caracteres[0] = Letras[RandomNumberGenerator.GetInt32(Letras.Length)];
		caracteres[1] = Numeros[RandomNumberGenerator.GetInt32(Numeros.Length)];
		for (var i = 2; i < caracteres.Length; i++)
			caracteres[i] = todos[RandomNumberGenerator.GetInt32(todos.Length)];
		RandomNumberGenerator.Shuffle(caracteres.AsSpan());
		return new string(caracteres);
	}

	public async Task<CorreoServicio.Resultado> EnviarAsync(int usuId, string usuario, string para, string password, bool esNuevo,
		string urlSistema, int? sucId, int? usuIdAccion)
	{
		var parametros = await general.ConsultarParametrosAsync(sucId);
		var compania = parametros.CiaNombreComercial;
		var asunto = esNuevo ? $"Su usuario del sistema ERP - {compania}" : $"Su nueva contraseña del sistema ERP - {compania}";
		var intro = esNuevo
			? "Se creó su usuario para ingresar al sistema ERP."
			: "El administrador del sistema restableció su contraseña del sistema ERP.";
		const string aviso = "Es una contraseña temporal: al ingresar, el sistema le pedirá cambiarla por una que solo usted conozca "
			+ "(al menos 8 caracteres, con letras y números). Si usted no solicitó este cambio, avise al administrador.";
		string H(string s) => WebUtility.HtmlEncode(s);
		var html = $"""
			<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#1a1f2e;max-width:600px">
			  <p>{H(intro)}</p>
			  <table style="border-collapse:collapse;margin:12px 0;min-width:320px">
			    <tr><td style="padding:6px 12px;background:#e8edf7;color:#34405a">Usuario</td><td style="padding:6px 12px;font-weight:bold;color:#0d1b4c">{H(usuario)}</td></tr>
			    <tr><td style="padding:6px 12px;background:#e8edf7;color:#34405a">Contraseña temporal</td><td style="padding:6px 12px;font-weight:bold;color:#0d1b4c;font-family:Consolas,monospace">{H(password)}</td></tr>
			    <tr><td style="padding:6px 12px;background:#e8edf7;color:#34405a">Dirección</td><td style="padding:6px 12px"><a href="{H(urlSistema)}">{H(urlSistema)}</a></td></tr>
			  </table>
			  <p>{H(aviso)}</p>
			  <p>Atentamente,<br><strong>{H(compania)}</strong></p>
			</div>
			""";
		var texto = string.Join("\n", intro, "", $"Usuario: {usuario}", $"Contraseña temporal: {password}", $"Dirección: {urlSistema}", "",
			aviso, "", "Atentamente,", compania);
		return await correo.EnviarAsync(parametros.CiaId, Tipo, usuId, para, null, asunto, html, texto, null, usuIdAccion);
	}
}
