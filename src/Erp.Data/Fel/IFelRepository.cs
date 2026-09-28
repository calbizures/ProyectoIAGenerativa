namespace Erp.Data.Fel;

public interface IFelRepository
{
	Task<FelDocumentoDatos?> ConsultarDatosDocumentoAsync(int encId);
	Task RegistrarResultadoAsync(FelResultado resultado, int? usuarioAccionId);
	Task<IReadOnlyList<FelDocumentoResumen>> ConsultarDocumentosAsync(string? estado, DateTime? desde, DateTime? hasta);
	Task<(FelDocumentoDetalle? Detalle, IReadOnlyList<FelBitacora> Bitacora)> ConsultarDetalleAsync(int encId);

	Task<FelConfiguracion?> ConsultarConfiguracionAsync(int ciaId);
	Task GuardarConfiguracionAsync(FelConfiguracion configuracion, int? usuarioAccionId);
	Task<IReadOnlyList<FelFrase>> ConsultarFrasesAsync(int ciaId);
	Task GuardarFraseAsync(FelFrase frase, int? usuarioAccionId);
	Task EliminarFraseAsync(int ffrId);
	Task<IReadOnlyList<FelEstablecimiento>> ConsultarEstablecimientosAsync(int ciaId);
	Task GuardarEstablecimientoAsync(FelEstablecimiento establecimiento, int? usuarioAccionId);
	Task<IReadOnlyList<FelMunicipio>> ConsultarMunicipiosAsync();
	Task<IReadOnlyList<FelTipoDocumento>> ConsultarTiposDocumentoAsync();
	Task GuardarTipoDocumentoAsync(FelTipoDocumento tipo, int? usuarioAccionId);
	Task<IReadOnlyList<FelUnidadMedida>> ConsultarUnidadesAsync();
	Task GuardarUnidadAsync(int umeId, string felCodigo, int? usuarioAccionId);
}
