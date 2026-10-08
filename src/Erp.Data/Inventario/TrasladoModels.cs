namespace Erp.Data.Inventario;

// Traslado entre bodegas: E enviado (en tránsito), R recibido, P recibido con
// diferencias, X rechazado por el destino, N cancelado por el origen.
public sealed class Traslado
{
	public int TraId { get; set; }
	public string Numero { get; set; } = "";
	public DateTime Fecha { get; set; }
	public string Estado { get; set; } = "E";
	public int BodIdOrigen { get; set; }
	public string BodegaOrigen { get; set; } = "";
	public int SucIdOrigen { get; set; }
	public string SucursalOrigen { get; set; } = "";
	public int BodIdDestino { get; set; }
	public string BodegaDestino { get; set; } = "";
	public int SucIdDestino { get; set; }
	public string SucursalDestino { get; set; } = "";
	public decimal Valor { get; set; }
	public string? Observaciones { get; set; }
	public string? Envia { get; set; }
	public string? Recibe { get; set; }
	public DateTime? FechaRecepcion { get; set; }
	public string? NotaRecepcion { get; set; }
	public string? Diferencia { get; set; }
	public int Lineas { get; set; }
	public decimal Unidades { get; set; }

	public string EstadoTexto => Estado switch
	{
		"E" => "En tránsito",
		"R" => "Recibido",
		"P" => Diferencia == "P" ? "Recibido con pérdida" : "Recibido con devolución",
		"X" => "Rechazado",
		"N" => "Cancelado",
		_ => Estado
	};
}

public sealed class TrasladoLinea
{
	public int TrdId { get; set; }
	public int ProId { get; set; }
	public string Codigo { get; set; } = "";
	public string Descripcion { get; set; } = "";
	public string? Unidad { get; set; }
	public decimal Cantidad { get; set; }
	public decimal CostoUnitario { get; set; }
	public decimal Valor { get; set; }
	public decimal? CantidadRecibida { get; set; }
}

// Producto con existencia en la bodega origen.
public sealed class ProductoTrasladable
{
	public int ProId { get; set; }
	public string Codigo { get; set; } = "";
	public string Descripcion { get; set; } = "";
	public decimal Existencia { get; set; }
	public decimal CostoUnitario { get; set; }
	public string? Unidad { get; set; }
}
