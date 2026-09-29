namespace Erp.Data.Bancos;

public sealed class CuentaBancaria
{
	public int BcbId { get; set; }
	public string NumeroCuenta { get; set; } = "";
	public string? Descripcion { get; set; }
	public int GefId { get; set; }
	public string Banco { get; set; } = "";
	// M = monetaria, A = ahorro
	public string Tipo { get; set; } = "M";
	public int? CtaId { get; set; }
	public string? CuentaCodigo { get; set; }
	public string? CuentaNombre { get; set; }
	public string Estado { get; set; } = "A";
	public int ChequerasActivas { get; set; }
	public string Nombre => $"{Banco} {NumeroCuenta}";
}

public sealed class Chequera
{
	public int CbcId { get; set; }
	public int BcbId { get; set; }
	public string Cuenta { get; set; } = "";
	public int ChequeDel { get; set; }
	public int ChequeAl { get; set; }
	public DateTime? FechaRecepcion { get; set; }
	public string Estado { get; set; } = "A";
	public int Emitidos { get; set; }
	public int? Siguiente { get; set; }
	public int Disponibles { get; set; }
	public string Nombre => $"{Cuenta} · {ChequeDel}-{ChequeAl}";
}

public sealed class MotivoPago
{
	public int BmpId { get; set; }
	public string Descripcion { get; set; } = "";
	public string Estado { get; set; } = "A";
	public int Cheques { get; set; }
}

public sealed class Cheque
{
	public int BceId { get; set; }
	// P = proveedor, L = libre, N = nómina
	public string Tipo { get; set; } = "L";
	public DateTime Fecha { get; set; }
	public string Numero { get; set; } = "";
	public int BcbId { get; set; }
	public string Cuenta { get; set; } = "";
	public string? Beneficiario { get; set; }
	public string? Motivo { get; set; }
	public string? CuentaCodigo { get; set; }
	public string? CuentaNombre { get; set; }
	public string? Departamento { get; set; }
	public decimal Valor { get; set; }
	// E = emitido, C = cobrado, A = anulado
	public string EstadoCheque { get; set; } = "E";
	public DateTime? FechaCobro { get; set; }
	public string? Observaciones { get; set; }
	public string? Usuario { get; set; }
	public string? Nomina { get; set; }
}

public sealed class ChequeLibre
{
	public int CbcId { get; set; }
	public string? Numero { get; set; }
	public DateTime Fecha { get; set; } = DateTime.Today;
	public string Beneficiario { get; set; } = "";
	public int BmpId { get; set; }
	public int CtaId { get; set; }
	public int? IdDepartamento { get; set; }
	public decimal Valor { get; set; }
	public string? Observaciones { get; set; }
}
