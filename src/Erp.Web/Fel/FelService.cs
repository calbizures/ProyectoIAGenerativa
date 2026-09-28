using Erp.Data.Fel;

namespace Erp.Web.Fel;

// Resultado que ve el usuario después de grabar, reintentar o anular.
public sealed record FelEnvio(bool Aplica, bool Exito, string Estado, string Mensaje, string? Uuid = null)
{
	public static FelEnvio NoAplica(string mensaje) => new(false, true, "N", mensaje);
}

// Orquesta la certificación: reúne los datos (paFelDocumentoDatosConsultar),
// arma el XML, lo envía al certificador configurado para la compañía y
// guarda el resultado. Nunca lanza excepción por una falla del certificador:
// el documento ya está grabado y queda Pendiente o Rechazado para reintentar.
public sealed class FelService(IFelRepository repositorio, IEnumerable<IFelCertificador> certificadores, IConfiguration configuracion,
	ILogger<FelService> log)
{
	public static string EstadoTexto(string? estado) => estado switch
	{
		"C" => "Certificado",
		"P" => "Pendiente",
		"R" => "Rechazado",
		"A" => "Anulado en SAT",
		"X" => "Anulación pendiente",
		_ => "No enviado"
	};

	private IFelCertificador? Certificador(string? nombre) =>
		certificadores.FirstOrDefault(c => c.Nombre.Equals(nombre ?? "", StringComparison.OrdinalIgnoreCase));

	private FelSolicitud Solicitud(FelEncabezado e, string xml, string identificador, string? url) => new(
		xml, identificador, e.NitEmisor, e.CorreoCopia, url, e.UsuarioFirma,
		configuracion[$"Fel:Credenciales:{e.NitEmisor}:LlaveFirma"], e.UsuarioApi,
		configuracion[$"Fel:Credenciales:{e.NitEmisor}:LlaveApi"], e.TimeoutSegundos);

	public async Task<FelEnvio> CertificarAsync(int encId, int? usuId, CancellationToken cancelacion = default)
	{
		FelDocumentoDatos? datos;
		try { datos = await repositorio.ConsultarDatosDocumentoAsync(encId); }
		catch (Exception ex)
		{
			log.LogError(ex, "No se pudieron leer los datos FEL del documento {EncId}", encId);
			return new FelEnvio(true, false, "P", "No se pudieron leer los datos para la factura electrónica: " + ex.Message);
		}
		if (datos is null) return FelEnvio.NoAplica("El documento no existe.");

		var e = datos.Encabezado;
		if (!e.Certifica || string.IsNullOrEmpty(e.TipoDte)) return FelEnvio.NoAplica("Este tipo de documento no se certifica.");
		if (!e.Activo) return FelEnvio.NoAplica("La factura electrónica está desactivada para la compañía.");
		if (e.FelEstado is "C" or "A" or "X") return new FelEnvio(true, true, e.FelEstado, $"Ya está {EstadoTexto(e.FelEstado).ToLowerInvariant()}.", e.FelUuid);
		if (e.EstadoDocumento != "G") return FelEnvio.NoAplica("El documento está anulado en el sistema; no se certifica.");

		// Una nota refiere la autorización de su factura: si la factura aún no
		// está certificada, se certifica primero.
		if (e.TipoDte is "NCRE" or "NDEB" && string.IsNullOrEmpty(e.OrigenUuid) && e.OrigenEncId is int origen && origen != encId)
		{
			var previa = await CertificarAsync(origen, usuId, cancelacion);
			if (previa.Exito)
			{
				datos = await repositorio.ConsultarDatosDocumentoAsync(encId) ?? datos;
				e = datos.Encabezado;
			}
		}

		var certificador = Certificador(e.Certificador);
		var tipoDte = e.TipoDte!;

		// Validaciones previas: sin estos datos el certificador lo rechazaría.
		string? problema = null;
		if (certificador is null) problema = $"Certificador '{e.Certificador}' no reconocido.";
		else if (string.IsNullOrWhiteSpace(e.NitEmisor)) problema = "La compañía no tiene NIT.";
		else if (e.CodigoEstablecimiento is null) problema = "La sucursal no tiene código de establecimiento FEL.";
		else if (datos.Items.Count == 0) problema = "El documento no tiene líneas.";
		else if (tipoDte is "NCRE" or "NDEB" && string.IsNullOrEmpty(e.OrigenUuid))
			problema = "La factura de origen de esta nota no está certificada; certifíquela primero.";

		string? xml = null;
		if (problema is null)
		{
			try { xml = FelXmlBuilder.ConstruirDte(datos, tipoDte); }
			catch (Exception ex) { problema = "No se pudo armar el XML: " + ex.Message; }
		}

		var resultado = new FelResultado
		{
			EncId = encId, Operacion = "CERTIFICAR", TipoDte = tipoDte, Certificador = e.Certificador ?? "", XmlEnviado = xml
		};

		if (problema is not null)
		{
			resultado.Exito = false;
			resultado.Estado = "R";
			resultado.Mensaje = problema;
		}
		else
		{
			var identificador = e.NumeroUnico ?? $"DOC-{encId}";
			FelRespuesta respuesta;
			try { respuesta = await certificador!.CertificarAsync(Solicitud(e, xml!, identificador, e.UrlCertificacion), cancelacion); }
			catch (Exception ex) when (ex is not OperationCanceledException)
			{
				log.LogError(ex, "Error inesperado del certificador para el documento {EncId}", encId);
				respuesta = new FelRespuesta(false, false, null, null, null, null, null, "Error al comunicarse con el certificador: " + ex.Message, null);
			}
			resultado.Exito = respuesta.Exito;
			resultado.Estado = respuesta.Exito ? "C" : respuesta.Rechazado ? "R" : "P";
			resultado.Uuid = respuesta.Uuid;
			resultado.Serie = respuesta.Serie;
			resultado.Numero = respuesta.Numero;
			resultado.FechaCertificacion = respuesta.Fecha;
			resultado.XmlCertificado = respuesta.XmlCertificado;
			resultado.Mensaje = respuesta.Mensaje;
			resultado.Respuesta = respuesta.Respuesta;
		}

		try { await repositorio.RegistrarResultadoAsync(resultado, usuId); }
		catch (Exception ex)
		{
			log.LogError(ex, "No se pudo guardar el resultado FEL del documento {EncId}", encId);
			return new FelEnvio(true, resultado.Exito, resultado.Estado, "Se obtuvo respuesta del certificador pero no se pudo guardar: " + ex.Message, resultado.Uuid);
		}

		return new FelEnvio(true, resultado.Exito, resultado.Estado,
			resultado.Exito ? $"Certificada: autorización {resultado.Uuid}." : $"{EstadoTexto(resultado.Estado)}: {resultado.Mensaje}", resultado.Uuid);
	}

	// Se llama después de anular el documento en el sistema. Si falla, queda
	// como anulación pendiente para reintentarla.
	public async Task<FelEnvio> AnularAsync(int encId, string motivo, int? usuId, CancellationToken cancelacion = default)
	{
		var datos = await repositorio.ConsultarDatosDocumentoAsync(encId);
		if (datos is null) return FelEnvio.NoAplica("El documento no existe.");
		var e = datos.Encabezado;
		if (e.FelEstado is not ("C" or "X") || string.IsNullOrEmpty(e.FelUuid))
			return FelEnvio.NoAplica("El documento no estaba certificado; no hay nada que anular ante SAT.");

		var certificador = Certificador(e.Certificador);
		var motivoFinal = string.IsNullOrWhiteSpace(motivo) ? "Anulación del documento" : motivo.Trim();
		var xml = FelXmlBuilder.ConstruirAnulacion(e, e.FechaHoraEmision, e.FelUuid, motivoFinal, DateTime.Now);
		var resultado = new FelResultado
		{
			EncId = encId, Operacion = "ANULAR", TipoDte = e.FelTipoDte ?? e.TipoDte ?? "", Certificador = e.Certificador ?? "",
			XmlEnviado = xml, MotivoAnulacion = motivoFinal
		};

		if (certificador is null)
		{
			resultado.Estado = "X";
			resultado.Mensaje = $"Certificador '{e.Certificador}' no reconocido.";
		}
		else
		{
			FelRespuesta respuesta;
			try { respuesta = await certificador.AnularAsync(Solicitud(e, xml, $"ANU-{e.NumeroUnico ?? encId.ToString()}", e.UrlAnulacion), cancelacion); }
			catch (Exception ex) when (ex is not OperationCanceledException)
			{
				log.LogError(ex, "Error inesperado del certificador al anular el documento {EncId}", encId);
				respuesta = new FelRespuesta(false, false, null, null, null, null, null, "Error al comunicarse con el certificador: " + ex.Message, null);
			}
			resultado.Exito = respuesta.Exito;
			resultado.Estado = respuesta.Exito ? "A" : "X";
			resultado.FechaCertificacion = respuesta.Fecha;
			resultado.Mensaje = respuesta.Mensaje;
			resultado.Respuesta = respuesta.Respuesta;
		}

		await repositorio.RegistrarResultadoAsync(resultado, usuId);
		return new FelEnvio(true, resultado.Exito, resultado.Estado,
			resultado.Exito ? "Anulada también ante SAT." : $"La anulación ante SAT quedó pendiente: {resultado.Mensaje}");
	}
}

// Reintenta cada cierto tiempo lo que quedó Pendiente por falla de
// comunicación y las anulaciones pendientes. Fel:ReintentoMinutos = 0 lo apaga.
public sealed class FelReintentoServicio(IServiceScopeFactory scopeFactory, IConfiguration configuracion, ILogger<FelReintentoServicio> log)
	: BackgroundService
{
	protected override async Task ExecuteAsync(CancellationToken cancelacion)
	{
		var minutos = configuracion.GetValue("Fel:ReintentoMinutos", 10);
		if (minutos <= 0) return;
		using var reloj = new PeriodicTimer(TimeSpan.FromMinutes(minutos));
		while (await reloj.WaitForNextTickAsync(cancelacion))
		{
			try
			{
				using var scope = scopeFactory.CreateScope();
				var repositorio = scope.ServiceProvider.GetRequiredService<IFelRepository>();
				var servicio = scope.ServiceProvider.GetRequiredService<FelService>();
				foreach (var doc in (await repositorio.ConsultarDocumentosAsync("P", null, null)).Where(d => d.Intentos < 20).OrderBy(d => d.EncId))
					await servicio.CertificarAsync(doc.EncId, null, cancelacion);
				foreach (var doc in await repositorio.ConsultarDocumentosAsync("X", null, null))
				{
					var (detalle, _) = await repositorio.ConsultarDetalleAsync(doc.EncId);
					await servicio.AnularAsync(doc.EncId, detalle?.MotivoAnulacion ?? "", null, cancelacion);
				}
			}
			catch (Exception ex) when (ex is not OperationCanceledException)
			{
				log.LogWarning(ex, "Falló el reintento automático de factura electrónica");
			}
		}
	}
}
