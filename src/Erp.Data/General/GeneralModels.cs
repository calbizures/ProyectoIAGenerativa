namespace Erp.Data.General;

public sealed class Compania
{
	public int CiaId { get; set; }
	public string CiaNombreComercial { get; set; } = "";
	public string? CiaDireccion { get; set; }
	public string? CiaRepresentanteLegal { get; set; }
	public string? CiaDpiRepresentanteLegal { get; set; }
	public DateTime? CiaFechaNacimientoRepresentanteLegal { get; set; }
	public string? CiaNit { get; set; }
	public string? CiaTelefono { get; set; }
	public string? CiaEmail { get; set; }
	public string CiaEstado { get; set; } = "A";
	public decimal CiaPorcIva { get; set; } = 12m;
	public bool CiaPagaComision { get; set; }
	public decimal CiaToleranciaCierreCaja { get; set; }
	public string CiaPeriodicidadNomina { get; set; } = "M";
}

// Parámetros de uso general de la compañía a la que pertenece una sucursal.
public sealed class ParametrosCompania
{
	public int CiaId { get; set; }
	public string CiaNombreComercial { get; set; } = "";
	public decimal CiaPorcIva { get; set; } = 12m;
	public bool CiaPagaComision { get; set; }
	public decimal CiaToleranciaCierreCaja { get; set; }
	public string CiaPeriodicidadNomina { get; set; } = "M";
}

public sealed class EntidadFinancieraTipo
{
	public int GeftId { get; set; }
	public string GeftDescripcion { get; set; } = "";
	public int CantidadEntidades { get; set; }
}

public sealed class CuentaContable
{
	public int CtaId { get; set; }
	public string CtaCodigo { get; set; } = "";
	public string CtaNombre { get; set; } = "";
	public string CtaTipo { get; set; } = "";
	public string CtaNaturaleza { get; set; } = "";
	public bool CtaAceptaMovimiento { get; set; }
	public int CtaNivel { get; set; }
	public string CtaEstado { get; set; } = "A";
}

// Concepto contable (VENTA_CAJA, VENTA_IVA_DEBITO, ...) y la cuenta a la que
// se envía en las pólizas automáticas.
public sealed class CuentaParametro
{
	public string CcpCodigo { get; set; } = "";
	public string CcpDescripcion { get; set; } = "";
	public string CcpNaturaleza { get; set; } = "";
	public int? CtaId { get; set; }
	public string? CtaCodigo { get; set; }
	public string? CtaNombre { get; set; }
}
