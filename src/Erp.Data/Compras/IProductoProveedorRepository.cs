namespace Erp.Data.Compras;

public interface IProductoProveedorRepository
{
	// Por proveedor (sus productos) o por producto (sus proveedores).
	Task<IReadOnlyList<ProductoProveedor>> ConsultarAsync(int? prvId, int? proId);
	Task<int> GuardarAsync(int? pppId, int prvId, int proId, bool preferido, string? codigoProveedor, int? usuarioAccionId);
	Task EliminarAsync(int pppId, int? usuarioAccionId);
	// Después de grabar una compra: último costo y, si se pide, relaciona los productos nuevos.
	Task<int> RegistrarCompraAsync(int encId, bool relacionar, int? usuarioAccionId);
}
