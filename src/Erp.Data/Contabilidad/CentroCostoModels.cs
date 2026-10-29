namespace Erp.Data.Contabilidad;

// Saldo de una cuenta en un centro de costo (departamento) para un rango.
public sealed class CentroCostoFila
{
	public int IdDepartamento { get; set; }
	public string Departamento { get; set; } = "";
	public int CtaId { get; set; }
	public string CuentaCodigo { get; set; } = "";
	public string CuentaNombre { get; set; } = "";
	public decimal Debe { get; set; }
	public decimal Haber { get; set; }
	public decimal Saldo { get; set; }
	public int Partidas { get; set; }
}

public sealed class CentroCostoLinea
{
	public int AsiId { get; set; }
	public DateTime Fecha { get; set; }
	public string Origen { get; set; } = "";
	public string? Partida { get; set; }
	public string CuentaCodigo { get; set; } = "";
	public string CuentaNombre { get; set; } = "";
	public string? Descripcion { get; set; }
	public decimal Debe { get; set; }
	public decimal Haber { get; set; }
}
