namespace Erp.Data.Compras;

// Producto que vende un proveedor (inv_producto_proveedor).
public sealed class ProductoProveedor
{
	public int PppId { get; set; }
	public int PrvId { get; set; }
	public string PrvCodigo { get; set; } = "";
	public string Proveedor { get; set; } = "";
	public int ProId { get; set; }
	public string ProCodigo { get; set; } = "";
	public string ProDescripcion { get; set; } = "";
	public string ProTipoItem { get; set; } = "B";
	public string? UmeCodigo { get; set; }
	public decimal ProCostoUnitario { get; set; }
	public string ProEstado { get; set; } = "A";
	public bool Preferido { get; set; }
	// Código del producto en el catálogo del proveedor.
	public string? CodigoProveedor { get; set; }
	// Costo unitario sin IVA de la última compra a este proveedor.
	public decimal? UltimoCosto { get; set; }
	public DateTime? FechaUltimaCompra { get; set; }
	// Días que tarda en entregar (NULL: los de la compañía, para el punto de reorden).
	public int? DiasEntrega { get; set; }
}
