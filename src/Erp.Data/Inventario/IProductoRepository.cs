namespace Erp.Data.Inventario;

public interface IProductoRepository
{
	Task<int> InsertarAsync(string codigo, string descripcion, int prtId, string tipoItem, bool manejaExistencia, int? idPadre, int? usuarioAccionId, int? umeId = null);
	Task ActualizarAsync(int proId, string codigo, string descripcion, int prtId, string tipoItem, bool manejaExistencia, int? idPadre, decimal? porcentajeRentabilidad, int? usuarioAccionId, int? umeId = null);
	Task EliminarAsync(int proId, int? usuarioAccionId);
	Task<IReadOnlyList<Producto>> ConsultarAsync(string? codigo, string? descripcion, int? prtId, string? estado, int pagina, int tamanioPagina);
	Task<(Producto? Producto, IReadOnlyList<ProductoExistenciaBodega> Existencias)> ConsultarPorIdAsync(int proId);
	Task<IReadOnlyList<ProductoTipo>> ConsultarTiposAsync();
	Task<IReadOnlyList<ProductoExistenciaBodega>> ConsultarExistenciasAsync(int? proId, int? bodId);
	Task<Kardex?> ConsultarKardexAsync(int proId, int? bodId, DateTime? desde, DateTime? hasta);
}
