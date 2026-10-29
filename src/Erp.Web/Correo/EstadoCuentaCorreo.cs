using System.Globalization;
using System.Net;
using Erp.Data.Cuentas;
using Erp.Data.General;
using Erp.Web.Reportes;

namespace Erp.Web.Correo;

// Arma el estado de cuenta del cliente (PDF y texto del correo) y lo envía.
public sealed class EstadoCuentaCorreo(ICuentasRepository cuentas, IGeneralRepository general, CorreoServicio correo)
{
	public const string Tipo = "ESTADO_CUENTA";
	private static readonly CultureInfo Es = CultureInfo.GetCultureInfo("es-GT");

	public sealed record Documento(EstadoCuentaPdf.Datos Datos, byte[] Pdf, string NombreArchivo, int CiaId);

	public async Task<Documento?> GenerarAsync(int cliId, DateTime? desde, DateTime? hasta, int? sucId)
	{
		var cliente = await cuentas.ConsultarDatosEstadoCuentaClienteAsync(cliId);
		if (cliente is null) return null;
		var corte = (hasta ?? DateTime.Today).Date;
		var parametros = await general.ConsultarParametrosAsync(sucId);
		var compania = (await general.ConsultarCompaniasAsync(soloActivas: false)).FirstOrDefault(c => c.CiaId == parametros.CiaId);
		var logo = parametros.CiaId == 0 ? null : await general.ConsultarLogoAsync(parametros.CiaId, null, soloVersion: false);
		var emisor = new EstadoCuentaPdf.Emisor(compania?.CiaNombreComercial ?? parametros.CiaNombreComercial, compania?.CiaNit, compania?.CiaDireccion,
			compania?.CiaTelefono, compania?.CiaEmail, logo?.Logo);
		var datos = new EstadoCuentaPdf.Datos(emisor, cliente,
			await cuentas.ConsultarAntiguedadClientesAsync(DateTime.Today, cliId),
			await cuentas.ConsultarDocumentosCxcAsync(cliId, soloPendientes: true),
			await cuentas.ConsultarEstadoCuentaClienteAsync(cliId, desde, corte),
			desde, corte, DateTime.Now);
		return new Documento(datos, EstadoCuentaPdf.Generar(datos), EstadoCuentaPdf.NombreArchivo(cliente, corte), parametros.CiaId);
	}

	public static string Asunto(Documento d) => $"Estado de cuenta al {d.Datos.Hasta:dd/MM/yyyy} - {d.Datos.Compania.NombreComercial}";

	public async Task<CorreoServicio.Resultado> EnviarAsync(Documento d, string para, string? copia, string asunto, string? mensaje, int? usuId)
	{
		var (html, texto) = Cuerpo(d, mensaje);
		return await correo.EnviarAsync(d.CiaId, Tipo, d.Datos.Cliente.CliId, para, copia, asunto, html, texto,
			new CorreoServicio.Adjunto(d.NombreArchivo, d.Pdf, "application/pdf"), usuId);
	}

	// Resumen en el cuerpo; el detalle completo va en el PDF adjunto.
	public static (string Html, string Texto) Cuerpo(Documento d, string? mensaje)
	{
		var c = d.Datos.Cliente;
		var e = d.Datos.Compania;
		string M(decimal v) => "Q" + v.ToString("N2", CultureInfo.InvariantCulture);
		var filas = new List<(string, string, bool)>
		{
			("Saldo actual", M(c.Saldo), false),
			("Vencido", M(c.Vencido), c.Vencido > 0),
			("Límite de crédito", c.Limite > 0 ? M(c.Limite) : "Sin límite", false),
			("Crédito disponible", c.Disponible is decimal disp ? M(disp) : "—", false),
			("Documentos pendientes", d.Datos.Documentos.Count.ToString(Es), false)
		};
		var proxima = d.Datos.Cuotas.Where(x => x.Dias <= 0).OrderBy(x => x.Vencimiento).FirstOrDefault();
		if (proxima is not null) filas.Add(("Próximo vencimiento", $"{proxima.Vencimiento:dd/MM/yyyy} · {M(proxima.Saldo)}", false));

		var saludo = $"Estimado(a) {c.Nombre}:";
		var intro = $"Le enviamos su estado de cuenta con {e.NombreComercial} al {d.Datos.Hasta.ToString("dd 'de' MMMM 'de' yyyy", Es)}. "
			+ "En el archivo PDF adjunto encontrará el detalle de sus documentos, cuotas pendientes y movimientos.";
		var cierre = "Si ya realizó su pago, por favor ignore los montos correspondientes. Para cualquier consulta, responda a este correo"
			+ (string.IsNullOrWhiteSpace(e.Telefono) ? "." : $" o llámenos al {e.Telefono}.");

		string H(string s) => WebUtility.HtmlEncode(s);
		var html = $"""
			<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#1a1f2e;max-width:600px">
			  <p>{H(saludo)}</p>
			  <p>{H(intro)}</p>
			  {(string.IsNullOrWhiteSpace(mensaje) ? "" : $"<p>{H(mensaje.Trim()).Replace("\n", "<br>")}</p>")}
			  <table style="border-collapse:collapse;margin:12px 0;min-width:320px">
			    {string.Concat(filas.Select(f => $"<tr><td style=\"padding:6px 12px;background:#e8edf7;color:#34405a\">{H(f.Item1)}</td><td style=\"padding:6px 12px;text-align:right;font-weight:bold;color:{(f.Item3 ? "#b02020" : "#0d1b4c")}\">{H(f.Item2)}</td></tr>"))}
			  </table>
			  <p>{H(cierre)}</p>
			  <p>Atentamente,<br><strong>{H(e.NombreComercial)}</strong></p>
			</div>
			""";
		var texto = string.Join("\n", new[]
		{
			saludo, "", intro, string.IsNullOrWhiteSpace(mensaje) ? null : "\n" + mensaje.Trim(), "",
			string.Join("\n", filas.Select(f => $"{f.Item1}: {f.Item2}")), "", cierre, "", "Atentamente,", e.NombreComercial
		}.Where(l => l is not null));
		return (html, texto);
	}
}
