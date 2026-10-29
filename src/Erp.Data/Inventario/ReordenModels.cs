namespace Erp.Data.Inventario;

// Una fila del análisis de rotación y punto de reorden (producto en una bodega).
// Clase: A alta rotación (>= 12 al año), M media (>= 4), B baja, S sin ventas.
public sealed class RotacionInventarioFila
{
	public int ProId { get; set; }
	public string Codigo { get; set; } = "";
	public string Descripcion { get; set; } = "";
	public string Unidad { get; set; } = "UND";
	public string? Categoria { get; set; }
	public int BodId { get; set; }
	public string Bodega { get; set; } = "";
	public decimal Existencia { get; set; }
	public decimal Transito { get; set; }
	public decimal ExistenciaInicial { get; set; }
	public decimal ExistenciaFinal { get; set; }
	public decimal InventarioPromedio { get; set; }
	public decimal Vendidas { get; set; }
	public decimal CostoVendido { get; set; }
	public decimal VentaDiaria { get; set; }
	public decimal? Rotacion { get; set; }
	public decimal? RotacionAnual { get; set; }
	public decimal? DiasInventario { get; set; }
	public decimal? DiasCobertura { get; set; }
	public DateTime? UltimaVenta { get; set; }
	public int DiasEntrega { get; set; }
	public int DiasSeguridad { get; set; }
	public int PuntoReorden { get; set; }
	public int Sugerido { get; set; }
	public bool BajoReorden { get; set; }
	public string Clase { get; set; } = "S";
	public decimal ValorInventario { get; set; }
	public int? PrvId { get; set; }
	public string? Proveedor { get; set; }
	public decimal CostoSinIva { get; set; }
	public DateTime Desde { get; set; }
	public DateTime Hasta { get; set; }
	public int Dias { get; set; }
}

public sealed class ReordenParametros
{
	public int CiaId { get; set; }
	public int DiasAnalisis { get; set; } = 90;
	public int DiasEntrega { get; set; } = 7;
	public int DiasSeguridad { get; set; } = 7;
	public int DiasCobertura { get; set; } = 30;
}
