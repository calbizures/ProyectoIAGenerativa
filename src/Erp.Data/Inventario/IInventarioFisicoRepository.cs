namespace Erp.Data.Inventario;

public interface IInventarioFisicoRepository
{
	Task<IReadOnlyList<TomaFisica>> ConsultarAsync(int? sucId, int? bodId, string? estado);
	Task<int> CrearAsync(int bodId, DateTime fecha, string? observaciones, bool soloConExistencia, int? usuarioAccionId);
	Task<IReadOnlyList<TomaFisicaLinea>> ConsultarLineasAsync(int tfiId);
	Task GuardarConteoAsync(int tfiId, IReadOnlyList<(int ProId, decimal? Conteo)> conteos, int? usuarioAccionId);
	Task AplicarAsync(int tfiId, int? usuarioAccionId);
	Task AnularAsync(int tfiId, string motivo, int? usuarioAccionId);
}
