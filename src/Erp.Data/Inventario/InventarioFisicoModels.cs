namespace Erp.Data.Inventario;

// Toma de inventario físico de una bodega. Estado B = en conteo, A = aplicada, N = anulada.
public sealed class TomaFisica
{
	public int TfiId { get; set; }
	public int BodId { get; set; }
	public string Bodega { get; set; } = "";
	public int SucId { get; set; }
	public string Sucursal { get; set; } = "";
	public DateTime Fecha { get; set; }
	public string? Observaciones { get; set; }
	public string Estado { get; set; } = "B";
	public DateTime? FechaAplicacion { get; set; }
	public string? MotivoAnulacion { get; set; }
	public int Productos { get; set; }
	public int Contados { get; set; }
	public decimal ValorSobrante { get; set; }
	public decimal ValorFaltante { get; set; }
	public string? Usuario { get; set; }
	// Conteo: al abrir la toma se toma la foto de existencias y la bodega queda
	// bloqueada hasta terminar el conteo (ConteoFin).
	public DateTime ConteoInicio { get; set; }
	public DateTime? ConteoFin { get; set; }
	public string? ConteoTerminadoPor { get; set; }
	public bool UsaFoto { get; set; } = true;
	public bool BodegaBloqueada { get; set; }
}

public sealed class TomaFisicaLinea
{
	public int TfdId { get; set; }
	public int ProId { get; set; }
	public string Codigo { get; set; } = "";
	public string Descripcion { get; set; } = "";
	public string? Unidad { get; set; }
	public string? TipoProducto { get; set; }
	public decimal Existencia { get; set; }
	public decimal? Conteo { get; set; }
	public decimal? CostoUnitario { get; set; }
	public decimal ExistenciaActual { get; set; }
	public decimal? Diferencia => Conteo is null ? null : Conteo - Existencia;
	public decimal ValorDiferencia => Math.Round((Diferencia ?? 0) * (CostoUnitario ?? 0), 2);
}
