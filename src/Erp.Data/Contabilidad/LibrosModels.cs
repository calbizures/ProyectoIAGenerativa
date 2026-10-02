namespace Erp.Data.Contabilidad;

// Póliza (asiento contable) con su origen: manual, venta, compra, cheque...
public sealed class Poliza
{
	public int AsiId { get; set; }
	public DateTime Fecha { get; set; }
	public string Descripcion { get; set; } = "";
	public string Origen { get; set; } = "";
	public int? OrigenId { get; set; }
	public string Estado { get; set; } = "A";
	public string? MotivoAnulacion { get; set; }
	public decimal Total { get; set; }
	public int Lineas { get; set; }
	public string? Usuario { get; set; }
	public DateTime? Creada { get; set; }
	public string EstadoPeriodo { get; set; } = "A";
	public string? Documento { get; set; }
	public int? EncId { get; set; }
	public IReadOnlyList<PolizaLinea> Detalle { get; set; } = Array.Empty<PolizaLinea>();

	public bool Anulable => Estado == "A" && Origen is "MANUAL" or "CIERRE_ANUAL";
}

public sealed class PolizaLinea
{
	public int AsdId { get; set; }
	public int CtaId { get; set; }
	public string Codigo { get; set; } = "";
	public string Cuenta { get; set; } = "";
	public decimal Debe { get; set; }
	public decimal Haber { get; set; }
	public string? Descripcion { get; set; }
	public int? IdDepartamento { get; set; }
	public string? Departamento { get; set; }
}

// Línea de una póliza manual en captura.
public sealed class PolizaManualLinea
{
	public int? CtaId { get; set; }
	public decimal? Debe { get; set; }
	public decimal? Haber { get; set; }
	public string? Descripcion { get; set; }
	public int? IdDepartamento { get; set; }
}

public sealed class LibroDiarioLinea
{
	public int AsiId { get; set; }
	public DateTime Fecha { get; set; }
	public string Descripcion { get; set; } = "";
	public string Origen { get; set; } = "";
	public string Codigo { get; set; } = "";
	public string Cuenta { get; set; } = "";
	public decimal Debe { get; set; }
	public decimal Haber { get; set; }
	public string? DescripcionLinea { get; set; }
}

public sealed class MayorCuenta
{
	public int CtaId { get; set; }
	public string Codigo { get; set; } = "";
	public string Cuenta { get; set; } = "";
	public string Naturaleza { get; set; } = "D";
	public decimal SaldoInicial { get; set; }
	public decimal Debe { get; set; }
	public decimal Haber { get; set; }
	public decimal SaldoFinal { get; set; }
	public List<MayorMovimiento> Movimientos { get; set; } = new();
}

public sealed class MayorMovimiento
{
	public int CtaId { get; set; }
	public DateTime Fecha { get; set; }
	public int AsiId { get; set; }
	public string Origen { get; set; } = "";
	public string? Descripcion { get; set; }
	public decimal Debe { get; set; }
	public decimal Haber { get; set; }
	// Saldo corrido con el signo de la naturaleza de la cuenta.
	public decimal Saldo { get; set; }
}

public sealed class BalanzaFila
{
	public int CtaId { get; set; }
	public string Codigo { get; set; } = "";
	public string Cuenta { get; set; } = "";
	public int Nivel { get; set; }
	public string Tipo { get; set; } = "";
	public string Naturaleza { get; set; } = "";
	public decimal InicialDeudor { get; set; }
	public decimal InicialAcreedor { get; set; }
	public decimal Debe { get; set; }
	public decimal Haber { get; set; }
	public decimal FinalDeudor { get; set; }
	public decimal FinalAcreedor { get; set; }
}

// Fila de un estado financiero (cuenta de cualquier nivel).
public sealed class EstadoFila
{
	public int CtaId { get; set; }
	public string Codigo { get; set; } = "";
	public string Cuenta { get; set; } = "";
	public int Nivel { get; set; }
	public string Tipo { get; set; } = "";
	public string? Naturaleza { get; set; }
	public decimal Saldo { get; set; }
	public decimal SaldoComparativo { get; set; }
}

public sealed class BalanceTotales
{
	public decimal Activo { get; set; }
	public decimal Pasivo { get; set; }
	public decimal Capital { get; set; }
	public decimal ResultadoEjercicio { get; set; }
	public decimal ResultadosAnteriores { get; set; }
	public decimal ActivoComparativo { get; set; }
	public decimal PasivoComparativo { get; set; }
	public decimal CapitalComparativo { get; set; }
	public decimal ResultadoEjercicioComparativo { get; set; }
	public decimal ResultadosAnterioresComparativo { get; set; }

	public decimal PasivoCapital => Pasivo + Capital + ResultadoEjercicio + ResultadosAnteriores;
	public decimal PasivoCapitalComparativo => PasivoComparativo + CapitalComparativo + ResultadoEjercicioComparativo + ResultadosAnterioresComparativo;
	public decimal Diferencia => Activo - PasivoCapital;
}

public sealed class BalanceGeneral
{
	public IReadOnlyList<EstadoFila> Filas { get; set; } = Array.Empty<EstadoFila>();
	public BalanceTotales Totales { get; set; } = new();
}

public sealed class ResultadosTotales
{
	public decimal UtilidadBruta { get; set; }
	public decimal Ingresos { get; set; }
	public decimal Costos { get; set; }
	public decimal Gastos { get; set; }
	public decimal UtilidadNeta { get; set; }
}

public sealed class EstadoResultados
{
	public IReadOnlyList<EstadoFila> Filas { get; set; } = Array.Empty<EstadoFila>();
	public ResultadosTotales Totales { get; set; } = new();
	public ResultadosTotales? Comparativo { get; set; }
}

public sealed class PeriodoContable
{
	public int Anio { get; set; }
	public int Mes { get; set; }
	public int? PdoId { get; set; }
	public string Estado { get; set; } = "A";
	public DateTime? FechaCierre { get; set; }
	public string? CerradoPor { get; set; }
	public int Polizas { get; set; }
	public int Anuladas { get; set; }
	public decimal Total { get; set; }
}

public sealed class CierreAnual
{
	public int AsiId { get; set; }
	public DateTime Fecha { get; set; }
	public decimal Total { get; set; }
	public string? Usuario { get; set; }
}

public static class OrigenesPoliza
{
	public static readonly IReadOnlyList<(string Codigo, string Nombre)> Todos = new[]
	{
		("MANUAL", "Manual"), ("APERTURA", "Apertura / saldos iniciales"), ("VENTA", "Venta"), ("COMPRA", "Compra"),
		("NOTA_CREDITO", "Nota de crédito"), ("NOTA_DEBITO", "Nota de débito"), ("PAGO_CLIENTE", "Cobro a cliente"),
		("PAGO_PROVEEDOR", "Pago a proveedor"), ("PAGO_TRANSFERENCIA", "Transferencia"), ("CHEQUE", "Cheque"),
		("DEPOSITO", "Depósito"), ("CIERRE_CAJA", "Cierre de caja"), ("CAJA_CHICA", "Caja chica"), ("NOMINA", "Nómina"),
		("PAGO_NOMINA", "Pago de nómina"), ("AJUSTE_INVENTARIO", "Ajuste de inventario"), ("TRASLADO", "Traslado"),
		("DEPRECIACION", "Depreciación"), ("ACTIVO_FIJO", "Activo fijo"), ("CONCILIACION", "Conciliación bancaria"),
		("CIERRE_ANUAL", "Cierre anual")
	};

	public static string Nombre(string codigo) => Todos.FirstOrDefault(o => o.Codigo == codigo).Nombre ?? codigo;
}
