namespace Erp.Data.Inventario;

// Kardex de un producto: sus movimientos en el orden en que el sistema los
// procesó, con el saldo y el costo promedio después de cada uno.
public sealed class Kardex
{
	public int ProId { get; set; }
	public string Codigo { get; set; } = "";
	public string Descripcion { get; set; } = "";
	public IReadOnlyList<KardexMovimiento> Movimientos { get; set; } = Array.Empty<KardexMovimiento>();
	public KardexResumen Resumen { get; set; } = new();
}

public sealed class KardexMovimiento
{
	public int Orden { get; set; }
	public DateTime Registrado { get; set; }
	public DateTime Fecha { get; set; }
	public int EncId { get; set; }
	public int BodId { get; set; }
	public string? Bodega { get; set; }
	public string Tipo { get; set; } = "";
	public string TipoNombre { get; set; } = "";
	public string? Documento { get; set; }
	public string? Tercero { get; set; }
	public bool EsReversa { get; set; }
	public decimal Entrada { get; set; }
	public decimal Salida { get; set; }
	public decimal CostoUnitario { get; set; }
	public decimal CostoTotal { get; set; }
	public decimal SaldoCantidad { get; set; }
	public decimal SaldoValor { get; set; }
	public decimal CostoPromedio { get; set; }
	public decimal SaldoBodega { get; set; }
}

// Saldo inicial del período, saldo final calculado y lo guardado en el
// producto y en las bodegas, para comprobar el costo promedio.
public sealed class KardexResumen
{
	public decimal InicialCantidad { get; set; }
	public decimal InicialValor { get; set; }
	public decimal InicialPromedio { get; set; }
	public decimal InicialBodega { get; set; }
	public decimal CalculadoCantidad { get; set; }
	public decimal CalculadoValor { get; set; }
	public decimal CalculadoPromedio { get; set; }
	public decimal GuardadoCantidad { get; set; }
	public decimal GuardadoValor { get; set; }
	public decimal GuardadoPromedio { get; set; }
	public decimal ExistenciaBodegas { get; set; }
	public decimal ExistenciaBodega { get; set; }
	public decimal CalculadoBodega { get; set; }

	public bool CuadraCantidad => Math.Abs(CalculadoCantidad - GuardadoCantidad) < 0.0001m && Math.Abs(CalculadoCantidad - ExistenciaBodegas) < 0.0001m;
	public bool CuadraCosto => Math.Abs(CalculadoPromedio - GuardadoPromedio) < 0.005m && Math.Abs(CalculadoValor - GuardadoValor) < 0.05m;
}
