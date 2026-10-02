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
	public bool CiaTieneLogo { get; set; }
	public DateTime? CiaLogoActualizado { get; set; }
}

// Cómo se imprime la factura de la compañía.
public sealed class CompaniaImpresion
{
	public int CiaId { get; set; }
	public string Impresora { get; set; } = "C";
	public int AnchoTermica { get; set; } = 80;
	public string? Pie { get; set; }
	// Días que vale una cotización (script 52).
	public int VigenciaCotizacion { get; set; } = 15;
}

// Logotipo de una compañía (Logo es null cuando solo se pidió la versión).
public sealed class CompaniaLogo
{
	public int CiaId { get; set; }
	public string Nombre { get; set; } = "";
	public byte[]? Logo { get; set; }
	public string? Tipo { get; set; }
	public DateTime? Actualizado { get; set; }
	public bool TieneLogo => Tipo is not null;
	// Dirección de la imagen; la versión cambia al cambiar el logotipo.
	public string Url => $"compania/logo?cia={CiaId}&v={Actualizado?.Ticks ?? 0}";
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

public sealed class SucursalDetalle
{
	public int SucId { get; set; }
	public string SucCodigo { get; set; } = "";
	public string SucDescripcion { get; set; } = "";
	public string? SucDireccion { get; set; }
	public string? SucTelefono { get; set; }
	public int CiaId { get; set; }
	public string CiaNombreComercial { get; set; } = "";
	public string SucEstado { get; set; } = "A";
	public int CantidadBodegas { get; set; }
}

// NIT o DPI grabado que no pasa la validación (para corregirlo).
public sealed class NitRevision
{
	public string Tipo { get; set; } = "";
	public int Id { get; set; }
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public string Dato { get; set; } = "";
	public string? Valor { get; set; }
	public string Pantalla { get; set; } = "";
}
