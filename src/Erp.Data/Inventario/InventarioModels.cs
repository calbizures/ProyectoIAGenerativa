namespace Erp.Data.Inventario;

public sealed class Producto
{
	public int ProId { get; set; }
	public string ProCodigo { get; set; } = "";
	public string ProDescripcion { get; set; } = "";
	public string ProTipoItem { get; set; } = "B";
	public bool ProManejaExistencia { get; set; }
	public decimal ProTotalCantidad { get; set; }
	public decimal ProCostoUnitario { get; set; }
	public int PrtId { get; set; }
	public string PrtDescripcion { get; set; } = "";
	public string ProEstado { get; set; } = "A";
}

public sealed class ProductoExistenciaBodega
{
	public int BodId { get; set; }
	public string BodDescripcion { get; set; } = "";
	public decimal Existencia { get; set; }
}

public sealed class ProductoTipo
{
	public int PrtId { get; set; }
	public string PrtCodigo { get; set; } = "";
	public string PrtDescripcion { get; set; } = "";
}
