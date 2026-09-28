namespace Erp.Data.Cuentas;

// Documento (factura o compra) con su saldo. Cliente o Proveedor según el módulo.
public sealed class DocumentoSaldo
{
	public int EncId { get; set; }
	public int? CliId { get; set; }
	public int? PrvId { get; set; }
	public string? Cliente { get; set; }
	public string? Proveedor { get; set; }
	public string Documento { get; set; } = "";
	public DateTime EncFechaDocto { get; set; }
	public decimal EncMontoTotal { get; set; }
	public decimal Pagado { get; set; }
	public decimal NotasCredito { get; set; }
	public decimal NotasDebito { get; set; }
	public decimal Saldo { get; set; }
	public DateTime? ProximoVencimiento { get; set; }
	public int? CuotasPendientes { get; set; }
	public string Tercero => Cliente ?? Proveedor ?? "";
}

public sealed class MovimientoEstadoCuenta
{
	public DateTime Fecha { get; set; }
	public string Tipo { get; set; } = "";
	public string? Documento { get; set; }
	public string? Referencia { get; set; }
	public decimal Cargo { get; set; }
	public decimal Abono { get; set; }
	public decimal Saldo { get; set; }
	public decimal SaldoInicial { get; set; }
}

// Una cuota pendiente con su rango de antigüedad a la fecha de corte.
public sealed class AntiguedadFila
{
	public int Id { get; set; }
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public int EncId { get; set; }
	public string Documento { get; set; } = "";
	public DateTime FechaDocumento { get; set; }
	public int Cuota { get; set; }
	public DateTime Vencimiento { get; set; }
	public int Dias { get; set; }
	public decimal Saldo { get; set; }
	public decimal NoVencido { get; set; }
	public decimal De1a30 { get; set; }
	public decimal De31a60 { get; set; }
	public decimal De61a90 { get; set; }
	public decimal Mas90 { get; set; }
}

public sealed class CuotaProveedor
{
	public int PpgId { get; set; }
	public int PpgNroPago { get; set; }
	public DateTime PpgFechaPago { get; set; }
	public decimal PpgValorPago { get; set; }
	public decimal PpgValorRealPago { get; set; }
	public decimal Saldo { get; set; }
	public DateTime? PpgFechaRealPago { get; set; }
	public string? PpgNumeroCheque { get; set; }
	public string PpgEstado { get; set; } = "P";
	public int EncId { get; set; }
}

public sealed class Chequera
{
	public int CbcId { get; set; }
	public string Descripcion { get; set; } = "";
	public int CbcChequeDel { get; set; }
	public int CbcChequeAl { get; set; }
	public int? SiguienteNumero { get; set; }
}

public sealed class MotivoPago
{
	public int BmpId { get; set; }
	public string BmpDescripcion { get; set; } = "";
}

public sealed class NotaResumen
{
	public int EncId { get; set; }
	public string TdoCodigo { get; set; } = "";
	public string TdoDescripcion { get; set; } = "";
	public DateTime EncFechaDocto { get; set; }
	public string? Numero { get; set; }
	public string? EncMotivo { get; set; }
	public decimal EncMontoTotal { get; set; }
	public int EncIdReferencia { get; set; }
	public string? DocumentoReferencia { get; set; }
	public string? Tercero { get; set; }
	public int LineasDevolucion { get; set; }
	public bool EsCredito => TdoCodigo is "NCC" or "NCP";
}

// Línea de un documento que se puede devolver en una nota de crédito.
public sealed class LineaDevolucion
{
	public int DetId { get; set; }
	public int DetItem { get; set; }
	public int ProId { get; set; }
	public string ProCodigo { get; set; } = "";
	public string DetDescripcion { get; set; } = "";
	public decimal DetCantidad { get; set; }
	public decimal Devuelto { get; set; }
	public decimal Disponible { get; set; }
	public decimal DetPrecioUnitario { get; set; }
	public decimal? DetPorcIva { get; set; }
	public int? UmeId { get; set; }
	public string? UmeCodigo { get; set; }
}

public sealed class NuevaLineaNota
{
	public string Descripcion { get; set; } = "";
	public decimal Cantidad { get; set; } = 1;
	public decimal PrecioUnitario { get; set; }		// sin IVA
	public decimal? PorcentajeIva { get; set; }
	public int? UmeId { get; set; }
	public int? DetIdOrigen { get; set; }			// devolución de esa línea; null = rebaja o cargo por monto
}
