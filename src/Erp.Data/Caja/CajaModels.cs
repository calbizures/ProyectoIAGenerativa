namespace Erp.Data.Caja;

public sealed class CajaReceptora
{
	public int PcrId { get; set; }
	public string PcrDescripcion { get; set; } = "";
	public int SucId { get; set; }
	public string SucCodigo { get; set; } = "";
	public string SucDescripcion { get; set; } = "";
	public string PcrEstado { get; set; } = "A";
}

public sealed class CajaApertura
{
	public int PcaId { get; set; }
	public DateTime PcaFechaApertura { get; set; }
	public DateTime? PcaFechaCierre { get; set; }
	public string PcaEstado { get; set; } = "A";
	public decimal PcaMontoInicial { get; set; }
	public decimal? PcaMontoTeoricoTotal { get; set; }
	public decimal? PcaMontoFisicoTotal { get; set; }
	public decimal? PcaDiferencia { get; set; }
	public int PcrId { get; set; }
	public string PcrDescripcion { get; set; } = "";
	public int SucId { get; set; }
	public string SucDescripcion { get; set; } = "";
	public string? UsuarioApertura { get; set; }
	public string? UsuarioCierre { get; set; }
}

public sealed class CajaAperturaActiva
{
	public int PcaId { get; set; }
	public DateTime PcaFechaApertura { get; set; }
	public decimal PcaMontoInicial { get; set; }
	public int PcrId { get; set; }
	public string PcrDescripcion { get; set; } = "";
	public string? UsuarioApertura { get; set; }
}

public sealed class FormaPagoTipo
{
	public int PftId { get; set; }
	public string PftDescripcion { get; set; } = "";
}

public sealed class FormaPagoTeorico
{
	public int PftId { get; set; }
	public string PftDescripcion { get; set; } = "";
	public decimal MontoTeorico { get; set; }
}

public sealed class EntidadFinanciera
{
	public int GefId { get; set; }
	public string GefCodigo { get; set; } = "";
	public string GefDescripcion { get; set; } = "";
	public int GeftId { get; set; }
	public string GeftDescripcion { get; set; } = "";
}

public sealed class DepositoCaja
{
	public int PcdId { get; set; }
	public DateTime PcdFechaDeposito { get; set; }
	public decimal PcdValorDeposito { get; set; }
	public string? PcdNumeroBoleta { get; set; }
	public string? PcdObservaciones { get; set; }
	public int PcaId { get; set; }
	public int? GefId { get; set; }
	public string? GefCodigo { get; set; }
	public string? GefDescripcion { get; set; }
}

// Captura de una forma de pago (efectivo/cheque/tarjeta) usada al pagar de
// contado, el enganche de una factura a crédito, o el abono a una cuota.
public sealed class FormaPagoCaptura
{
	public int PftId { get; set; }
	public decimal Monto { get; set; }
	public int? GefId { get; set; }
	public string? NumeroTarjetaUlt4 { get; set; }
	public string? FechaVencimientoTarjeta { get; set; }
	public string? NumeroCheque { get; set; }
}

// Conteo físico de efectivo por denominación al hacer el corte de caja.
public sealed class DenominacionEfectivo
{
	public string TipoDenominacion { get; set; } = "B"; // B=Billete, M=Moneda
	public decimal Denominacion { get; set; }
	public int Cantidad { get; set; }
}

// Conteo físico de una forma de pago distinta a efectivo, al corte de caja.
public sealed class CorteFormaFisico
{
	public int PftId { get; set; }
	public decimal MontoFisico { get; set; }
}
