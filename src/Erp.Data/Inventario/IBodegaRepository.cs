namespace Erp.Data.Inventario;

public sealed class Bodega
{
	public int BodId { get; set; }
	public string BodCodigo { get; set; } = "";
	public string BodDescripcion { get; set; } = "";
	public int SucId { get; set; }
	public string SucDescripcion { get; set; } = "";
	public string BodEstado { get; set; } = "A";
}

public interface IBodegaRepository
{
	Task<IReadOnlyList<Bodega>> ConsultarAsync(int? sucId, string? estado);
	Task<IReadOnlyList<BodegaDetalle>> ConsultarDetalleAsync(int? sucId, bool soloActivas);
	Task<int> GuardarAsync(int? bodId, int sucId, string codigo, string descripcion, int? usuarioAccionId);
	Task CambiarEstadoAsync(int bodId, string estado, int? usuarioAccionId);
	Task<IReadOnlyList<UnidadMedida>> ConsultarUnidadesAsync(bool soloActivas);
	Task<int> GuardarUnidadAsync(int? umeId, string codigo, string descripcion, string estado, int? usuarioAccionId);
	Task EliminarUnidadAsync(int umeId);
}
