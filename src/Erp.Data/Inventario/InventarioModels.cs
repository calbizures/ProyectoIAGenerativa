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
	public int PebId { get; set; }
	public int ProId { get; set; }
	public string ProCodigo { get; set; } = "";
	public string ProDescripcion { get; set; } = "";
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

public sealed class ProductoTipoCaracteristica
{
	public int PtcId { get; set; }
	public string PtcCodigo { get; set; } = "";
	public string PtcDescripcion { get; set; } = "";
	public int PtcOrden { get; set; }
	public string PtcEstado { get; set; } = "A";
}

public sealed class ProductoCaracteristica
{
	public int PcaId { get; set; }
	public string PcaValor { get; set; } = "";
	public string? PcaDescripcion { get; set; }
	public int ProId { get; set; }
	public string ProCodigo { get; set; } = "";
	public string ProDescripcion { get; set; } = "";
	public int PtcId { get; set; }
	public string PtcCodigo { get; set; } = "";
	public string PtcDescripcion { get; set; } = "";
}

public sealed class ProductoPrecio
{
	public int PprId { get; set; }
	public int ProId { get; set; }
	public string ProCodigo { get; set; } = "";
	public string ProDescripcion { get; set; } = "";
	public int BodId { get; set; }
	public string BodDescripcion { get; set; } = "";
	public int MonId { get; set; }
	public string MonCodigo { get; set; } = "";
	public decimal PprPrecioUnitarioVenta { get; set; }
	public string? PprDescripcion { get; set; }
	public DateTime PprVigenciaDesde { get; set; }
	public DateTime? PprVigenciaHasta { get; set; }
	public string PprEstado { get; set; } = "A";
}
