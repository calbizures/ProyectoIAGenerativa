namespace Erp.Data.Inventario;

public interface IReordenRepository
{
	Task<IReadOnlyList<RotacionInventarioFila>> ConsultarRotacionAsync(int? bodId, int? sucId, int? dias, DateTime? hasta);
	Task<ReordenParametros?> ConsultarParametrosAsync(int ciaId);
	Task GuardarParametrosAsync(ReordenParametros parametros, int? usuarioAccionId);
	Task GuardarDiasEntregaAsync(int pppId, int? dias, int? usuarioAccionId);
}
