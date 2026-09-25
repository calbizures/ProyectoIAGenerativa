namespace Erp.Data.Contabilidad;

public interface INomenclaturaRepository
{
	Task<IReadOnlyList<NodoCuenta>> ConsultarArbolAsync();
	Task<string> SiguienteCodigoAsync(int? idPadre);
	Task<int> GuardarAsync(int? ctaId, int? idPadre, string codigo, string nombre, string? tipo, string? naturaleza, int? usuarioAccionId);
	Task MoverAsync(int ctaId, int idPadreNuevo, int? usuarioAccionId);
	Task CambiarEstadoAsync(int ctaId, string estado, int? usuarioAccionId);
	Task EliminarAsync(int ctaId);
}
