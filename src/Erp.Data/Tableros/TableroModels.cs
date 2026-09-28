namespace Erp.Data.Tableros;

public sealed class VentasKpi
{
	public decimal Ventas { get; set; }
	public int Facturas { get; set; }
	public decimal Costo { get; set; }
	public decimal VentasCredito { get; set; }
	public decimal VentasConIva { get; set; }
	public decimal NotasCredito { get; set; }
	public decimal VentasAnterior { get; set; }
	public int FacturasAnterior { get; set; }
	public decimal CostoAnterior { get; set; }
	public int Clientes { get; set; }
	public string Agrupacion { get; set; } = "M";	// D por día, M por mes
	public decimal Margen => Ventas - Costo;
	public decimal MargenAnterior => VentasAnterior - CostoAnterior;
}

public sealed class VentasPeriodo
{
	public DateTime Periodo { get; set; }
	public decimal Ventas { get; set; }
	public decimal Costo { get; set; }
	public int Facturas { get; set; }
	public decimal Margen => Ventas - Costo;
}

public sealed class RankingFila
{
	public int Id { get; set; }
	public string? Codigo { get; set; }
	public string? Tipo { get; set; }
	public string Nombre { get; set; } = "";
	public decimal Ventas { get; set; }
	public decimal Costo { get; set; }
	public decimal Cantidad { get; set; }
	public int Facturas { get; set; }
}

public sealed record TableroVentas(VentasKpi Kpi, IReadOnlyList<VentasPeriodo> Periodos, IReadOnlyList<RankingFila> Clientes,
	IReadOnlyList<RankingFila> Productos, IReadOnlyList<RankingFila> Vendedores);

public sealed class CarteraKpi
{
	public decimal Cartera { get; set; }
	public decimal Vencida { get; set; }
	public decimal Cobrado { get; set; }
	public int Recibos { get; set; }
	public decimal Vencia { get; set; }
	public decimal CobradoDeLoQueVencia { get; set; }
	public int ClientesMorosos { get; set; }
	public string Agrupacion { get; set; } = "M";
}

public sealed class CarteraPeriodo
{
	public DateTime Periodo { get; set; }
	public decimal Vencia { get; set; }
	public decimal Cobrado { get; set; }
}

public sealed class AntiguedadRango
{
	public int Orden { get; set; }
	public string Rango { get; set; } = "";
	public decimal Saldo { get; set; }
	public int Cuotas { get; set; }
}

public sealed class Deudor
{
	public int Id { get; set; }
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public decimal Vencido { get; set; }
	public decimal Saldo { get; set; }
	public int? DiasMaximo { get; set; }
}

public sealed class MontoPorNombre
{
	public string Forma { get; set; } = "";
	public decimal Monto { get; set; }
}

public sealed record TableroCartera(CarteraKpi Kpi, IReadOnlyList<CarteraPeriodo> Periodos, IReadOnlyList<AntiguedadRango> Antiguedad,
	IReadOnlyList<Deudor> Deudores, IReadOnlyList<MontoPorNombre> Formas);

public sealed class ComprasKpi
{
	public decimal Compras { get; set; }
	public int Documentos { get; set; }
	public decimal ComprasAnterior { get; set; }
	public decimal PorPagar { get; set; }
	public decimal Vencido { get; set; }
	public decimal Proximos30 { get; set; }
	public decimal Pagado { get; set; }
	public int Cheques { get; set; }
	public string Agrupacion { get; set; } = "M";
}

public sealed class ComprasPeriodo
{
	public DateTime Periodo { get; set; }
	public decimal Compras { get; set; }
	public decimal Pagado { get; set; }
}

public sealed class ProveedorRanking
{
	public int Id { get; set; }
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public decimal Compras { get; set; }
	public decimal Saldo { get; set; }
}

public sealed class CompromisoSemana
{
	public int Orden { get; set; }
	public DateTime? Desde { get; set; }
	public DateTime Hasta { get; set; }
	public decimal Monto { get; set; }
	public int Cuotas { get; set; }
}

public sealed class CuotaPorPagar
{
	public int PrvId { get; set; }
	public string Proveedor { get; set; } = "";
	public string Documento { get; set; } = "";
	public int Cuota { get; set; }
	public DateTime Vence { get; set; }
	public decimal Saldo { get; set; }
	public int Dias { get; set; }
}

public sealed record TableroCompras(ComprasKpi Kpi, IReadOnlyList<ComprasPeriodo> Periodos, IReadOnlyList<ProveedorRanking> Proveedores,
	IReadOnlyList<CompromisoSemana> Compromisos, IReadOnlyList<CuotaPorPagar> Proximas);
