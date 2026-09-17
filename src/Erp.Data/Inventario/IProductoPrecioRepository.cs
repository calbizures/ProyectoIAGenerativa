namespace Erp.Data.Inventario;

public interface IProductoPrecioRepository
{
	Task<int> InsertarAsync(int proId, int bodId, int monId, decimal precioUnitarioVenta, string? descripcion,
		DateTime vigenciaDesde, DateTime? vigenciaHasta, int? usuarioAccionId);
	Task ActualizarAsync(int pprId, int bodId, int monId, decimal precioUnitarioVenta, string? descripcion,
		DateTime vigenciaDesde, DateTime? vigenciaHasta, int? usuarioAccionId);
	Task EliminarAsync(int pprId, int? usuarioAccionId);
	Task<IReadOnlyList<ProductoPrecio>> ConsultarAsync(int? proId, int? bodId, string? estado);
}
