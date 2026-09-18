namespace Erp.Data.Inventario;

public interface IProductoCaracteristicaRepository
{
	Task<int> InsertarAsync(int proId, int ptcId, string valor, string? descripcion, int? usuarioAccionId);
	Task ActualizarAsync(int pcaId, string valor, string? descripcion, int? usuarioAccionId);
	Task EliminarAsync(int pcaId);
	Task<IReadOnlyList<ProductoCaracteristica>> ConsultarAsync(int? proId);
	Task<IReadOnlyList<ProductoTipoCaracteristica>> ConsultarTiposAsync(string? estado);
}
