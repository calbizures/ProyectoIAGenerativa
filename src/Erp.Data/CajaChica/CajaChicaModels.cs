namespace Erp.Data.CajaChica;

public sealed class FondoCajaChica
{
	public int CchId { get; set; }
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public int SucId { get; set; }
	public string Sucursal { get; set; } = "";
	public string Responsable { get; set; } = "";
	public decimal MontoAutorizado { get; set; }
	public int CtaId { get; set; }
	public string CuentaCodigo { get; set; } = "";
	public string CuentaNombre { get; set; } = "";
	public string Estado { get; set; } = "A";
	public decimal Constituido { get; set; }
	public decimal Pendiente { get; set; }
	public int GastosPendientes { get; set; }
	public decimal PorReponer { get; set; }
	public decimal Disponible { get; set; }
	public DateTime? UltimoArqueo { get; set; }

	public bool EstaConstituido => Constituido > 0;
}

// Tipo: F factura (IVA crédito), P factura de pequeño contribuyente, R recibo, V vale.
public sealed class GastoCajaChica
{
	public int? CcgId { get; set; }
	public int CchId { get; set; }
	public DateTime Fecha { get; set; } = DateTime.Today;
	public string Tipo { get; set; } = "F";
	public int? PrvId { get; set; }
	public string? Nit { get; set; }
	public string Proveedor { get; set; } = "";
	public string? Serie { get; set; }
	public string? Numero { get; set; }
	public string Concepto { get; set; } = "";
	public int CtaId { get; set; }
	public string? CuentaCodigo { get; set; }
	public string? CuentaNombre { get; set; }
	public int? IdDepartamento { get; set; }
	public string? Departamento { get; set; }
	public decimal Total { get; set; }
	public decimal Iva { get; set; }
	public string Estado { get; set; } = "P";
	public int? LccId { get; set; }
	public string? Liquidacion { get; set; }
	public string? MotivoAnulacion { get; set; }

	public static string NombreTipo(string tipo) => tipo switch
	{
		"F" => "Factura",
		"P" => "Factura peq. contribuyente",
		"R" => "Recibo",
		_ => "Vale"
	};
}

public sealed class LiquidacionCajaChica
{
	public int LccId { get; set; }
	public int CchId { get; set; }
	public string Fondo { get; set; } = "";
	public string FondoNombre { get; set; } = "";
	public string Responsable { get; set; } = "";
	public string Numero { get; set; } = "";
	public DateTime Fecha { get; set; }
	public decimal Total { get; set; }
	public decimal Iva { get; set; }
	public int? AsiId { get; set; }
	public string Estado { get; set; } = "V";
	public string? MotivoAnulacion { get; set; }
	public int Gastos { get; set; }
	public int? BceIdReposicion { get; set; }
	public string? ChequeReposicion { get; set; }
	public DateTime? FechaReposicion { get; set; }
	public string? Usuario { get; set; }

	public bool Repuesta => BceIdReposicion is not null;
}

public sealed class ChequeCajaChica
{
	public int CfcId { get; set; }
	public string Tipo { get; set; } = "C";
	public int BceId { get; set; }
	public string Numero { get; set; } = "";
	public DateTime Fecha { get; set; }
	public decimal Monto { get; set; }
	public string EstadoCheque { get; set; } = "E";
	public string? Liquidacion { get; set; }
	public string? Cuenta { get; set; }

	public string NombreTipo => Tipo switch { "C" => "Constitución", "A" => "Aumento", _ => "Reposición" };
}

public sealed class ArqueoCajaChica
{
	public int CcaId { get; set; }
	public DateTime Fecha { get; set; }
	public decimal Disponible { get; set; }
	public decimal Efectivo { get; set; }
	public decimal Diferencia { get; set; }
	public string? Observaciones { get; set; }
	public string? Usuario { get; set; }
}
