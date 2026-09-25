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
}
