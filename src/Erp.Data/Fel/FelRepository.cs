using System.Data;
using Dapper;

namespace Erp.Data.Fel;

public sealed class FelRepository(IDbConnectionFactory connectionFactory) : IFelRepository
{
	private async Task<IReadOnlyList<T>> ConsultarAsync<T>(string procedimiento, object? parametros = null)
	{
		using var connection = connectionFactory.CreateConnection();
		return (await connection.QueryAsync<T>(procedimiento, parametros, commandType: CommandType.StoredProcedure)).ToList();
	}

	private async Task EjecutarAsync(string procedimiento, object parametros)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync(procedimiento, parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<FelDocumentoDatos?> ConsultarDatosDocumentoAsync(int encId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paFelDocumentoDatosConsultar", new { EncId = encId }, commandType: CommandType.StoredProcedure);
		var encabezado = await lector.ReadSingleOrDefaultAsync<FelEncabezado>();
		if (encabezado is null) return null;
		var items = (await lector.ReadAsync<FelItem>()).ToList();
		var frases = (await lector.ReadAsync<FelFraseDocumento>()).ToList();
		var abonos = (await lector.ReadAsync<FelAbono>()).ToList();
		return new FelDocumentoDatos(encabezado, items, frases, abonos);
	}

	public Task RegistrarResultadoAsync(FelResultado r, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paFelResultadoRegistrar", new
		{
			r.EncId, r.Operacion, r.Exito, r.Estado, r.TipoDte, r.Certificador, r.Uuid, r.Serie, r.Numero, r.FechaCertificacion,
			Mensaje = Recortar(r.Mensaje, 2000), r.XmlEnviado, r.XmlCertificado, r.Respuesta,
			MotivoAnulacion = Recortar(r.MotivoAnulacion, 256), UsuId = usuarioAccionId
		});

	private static string? Recortar(string? texto, int largo) => texto is null || texto.Length <= largo ? texto : texto[..largo];

	public Task<IReadOnlyList<FelDocumentoResumen>> ConsultarDocumentosAsync(string? estado, DateTime? desde, DateTime? hasta) =>
		ConsultarAsync<FelDocumentoResumen>("dbo.paFelDocumentosConsultar", new { Estado = estado, Desde = desde?.Date, Hasta = hasta?.Date });

	public async Task<(FelDocumentoDetalle? Detalle, IReadOnlyList<FelBitacora> Bitacora)> ConsultarDetalleAsync(int encId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paFelDocumentoDetalleConsultar", new { EncId = encId }, commandType: CommandType.StoredProcedure);
		var detalle = await lector.ReadSingleOrDefaultAsync<FelDocumentoDetalle>();
		var bitacora = (await lector.ReadAsync<FelBitacora>()).ToList();
		return (detalle, bitacora);
	}

	public async Task<FelConfiguracion?> ConsultarConfiguracionAsync(int ciaId) =>
		(await ConsultarAsync<FelConfiguracion>("dbo.paFelConfiguracionConsultar", new { CiaId = ciaId })).FirstOrDefault();

	public Task GuardarConfiguracionAsync(FelConfiguracion c, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paFelConfiguracionGuardar", new
		{
			c.CiaId, c.AfiliacionIva, c.NombreEmisor, c.CorreoEmisor, c.Certificador, c.Activo, c.Ambiente, c.UrlCertificacion, c.UrlAnulacion,
			c.UsuarioFirma, c.UsuarioApi, c.CorreoCopia, c.TimeoutSegundos, c.XmlnsDte, c.VersionDte, c.ReceptorDireccion,
			c.ReceptorCodigoPostal, c.ReceptorMunicipio, c.ReceptorDepartamento, c.ReceptorPais, UsuId = usuarioAccionId
		});

	public Task<IReadOnlyList<FelFrase>> ConsultarFrasesAsync(int ciaId) =>
		ConsultarAsync<FelFrase>("dbo.paFelFraseConsultar", new { CiaId = ciaId });

	public Task GuardarFraseAsync(FelFrase f, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paFelFraseGuardar", new
		{
			FfrId = f.FfrId == 0 ? (int?)null : f.FfrId, f.CiaId, f.TipoFrase, f.CodigoEscenario, f.Descripcion, f.AplicaNotas, f.Estado,
			UsuId = usuarioAccionId
		});

	public Task EliminarFraseAsync(int ffrId) => EjecutarAsync("dbo.paFelFraseEliminar", new { FfrId = ffrId });

	public Task<IReadOnlyList<FelEstablecimiento>> ConsultarEstablecimientosAsync(int ciaId) =>
		ConsultarAsync<FelEstablecimiento>("dbo.paFelEstablecimientoConsultar", new { CiaId = ciaId });

	public Task GuardarEstablecimientoAsync(FelEstablecimiento e, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paFelEstablecimientoGuardar", new
		{
			e.SucId, CodigoEstablecimiento = e.CodigoEstablecimiento ?? 0, e.NombreComercial, e.CodigoPostal, ProvId = e.ProvId ?? 0,
			UsuId = usuarioAccionId
		});

	public Task<IReadOnlyList<FelMunicipio>> ConsultarMunicipiosAsync() => ConsultarAsync<FelMunicipio>("dbo.paFelMunicipiosConsultar");

	public Task<IReadOnlyList<FelTipoDocumento>> ConsultarTiposDocumentoAsync() => ConsultarAsync<FelTipoDocumento>("dbo.paFelTipoDocumentoConsultar");

	public Task GuardarTipoDocumentoAsync(FelTipoDocumento t, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paFelTipoDocumentoGuardar", new { t.TdoId, t.TipoDte, t.TipoDteContado, t.Certifica, UsuId = usuarioAccionId });

	public Task<IReadOnlyList<FelUnidadMedida>> ConsultarUnidadesAsync() => ConsultarAsync<FelUnidadMedida>("dbo.paFelUnidadMedidaConsultar");

	public Task GuardarUnidadAsync(int umeId, string felCodigo, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paFelUnidadMedidaGuardar", new { UmeId = umeId, FelCodigo = felCodigo, UsuId = usuarioAccionId });
}
