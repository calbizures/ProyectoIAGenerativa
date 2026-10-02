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

// Cuota con saldo de un proveedor, para pagarla con cheque (sola o con otras).
public sealed class CuotaPendienteProveedor
{
	public int PpgId { get; set; }
	public int EncId { get; set; }
	public string Documento { get; set; } = "";
	public string NumeroDocumento { get; set; } = "";
	public DateTime FechaDocumento { get; set; }
	public int Cuota { get; set; }
	public DateTime Vencimiento { get; set; }
	public int Dias { get; set; }
	public decimal ValorCuota { get; set; }
	public decimal Pagado { get; set; }
	public decimal Saldo { get; set; }
}

public sealed record CuotaPagoProveedor(int PpgId, decimal Monto);

// Proveedor con cuotas pendientes (lista de Pagos a proveedores).
public sealed class ProveedorConSaldo
{
	public int PrvId { get; set; }
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public decimal Saldo { get; set; }
	public decimal Vencido { get; set; }
	public int Facturas { get; set; }
}

// Factura y cuota que pagó una línea de un cheque.
public sealed class ChequeDetalleLinea
{
	public int CedId { get; set; }
	public int EncId { get; set; }
	public string Documento { get; set; } = "";
	public DateTime FechaDocumento { get; set; }
	public int? Cuota { get; set; }
	public DateTime? Vencimiento { get; set; }
	public decimal? ValorCuota { get; set; }
	public decimal Monto { get; set; }
	public string Aplicacion { get; set; } = "";
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

// Cuota con saldo de un cliente (para aplicar un cobro de la más antigua a la más reciente).
public sealed class CuotaPendiente
{
	public int CppId { get; set; }
	public int EncId { get; set; }
	public string Documento { get; set; } = "";
	public DateTime FechaDocumento { get; set; }
	public int Cuota { get; set; }
	public DateTime Vencimiento { get; set; }
	public int Dias { get; set; }
	public decimal ValorCuota { get; set; }
	public decimal Saldo { get; set; }
}

public sealed record CuotaCobro(int CppId, decimal Monto);

public sealed class ReciboResumen
{
	public int PpeId { get; set; }
	public DateTime Fecha { get; set; }
	public int CliId { get; set; }
	public string Cliente { get; set; } = "";
	public decimal Total { get; set; }
	public string? Documentos { get; set; }
	public string? Formas { get; set; }
	public string Estado { get; set; } = "A";
	public string? MotivoAnulacion { get; set; }
	public int? PcaId { get; set; }
	public string? Caja { get; set; }
	public string? Usuario { get; set; }
	public bool CajaAbierta { get; set; }
	public bool EsPagoFactura { get; set; }
	public bool Anulado => Estado == "N";
	// Se anula aquí solo un cobro de cuotas vigente cuya caja siga abierta.
	public bool SePuedeAnular => !Anulado && CajaAbierta && !EsPagoFactura;
}

public sealed class ReciboEncabezado
{
	public int PpeId { get; set; }
	public DateTime Fecha { get; set; }
	public string Estado { get; set; } = "A";
	public string? MotivoAnulacion { get; set; }
	public string? ClienteCodigo { get; set; }
	public string Cliente { get; set; } = "";
	public string? ClienteNit { get; set; }
	public string? Compania { get; set; }
	public string? CompaniaNit { get; set; }
	public string? CompaniaDireccion { get; set; }
	public string? Sucursal { get; set; }
	public string? Caja { get; set; }
	public string? Usuario { get; set; }
}

public sealed class ReciboAplicacion
{
	public string Documento { get; set; } = "";
	public int? Cuota { get; set; }
	public DateTime? Vencimiento { get; set; }
	public decimal Monto { get; set; }
	public decimal? SaldoCuota { get; set; }
}

public sealed class ReciboForma
{
	public string Forma { get; set; } = "";
	public decimal Monto { get; set; }
	public string? Entidad { get; set; }
	public string? Referencia { get; set; }
}

public sealed record ReciboDetalle(ReciboEncabezado Encabezado, IReadOnlyList<ReciboAplicacion> Aplicaciones, IReadOnlyList<ReciboForma> Formas);

public sealed class ChequeResumen
{
	public int BceId { get; set; }
	public DateTime Fecha { get; set; }
	public string Numero { get; set; } = "";
	public string? Cuenta { get; set; }
	public int PrvId { get; set; }
	public string Proveedor { get; set; } = "";
	public string Documento { get; set; } = "";
	public int Cuotas { get; set; }
	public decimal Valor { get; set; }
	public string EstadoCheque { get; set; } = "E";	// E emitido, C cobrado, A anulado
	public string? Observaciones { get; set; }
	public string? Usuario { get; set; }
	public string EstadoTexto => EstadoCheque switch { "A" => "Anulado", "C" => "Cobrado", _ => "Emitido" };
}

// Límite 0 = sin límite (Disponible null).
public sealed class CreditoCliente
{
	public int CliId { get; set; }
	public decimal Limite { get; set; }
	public decimal Saldo { get; set; }
	public decimal? Disponible { get; set; }
}

public sealed class ClienteEstadoCuenta
{
	public int CliId { get; set; }
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public string? Nit { get; set; }
	public string? Direccion { get; set; }
	public string? Correo { get; set; }
	public string? Telefono { get; set; }
	public decimal Limite { get; set; }
	public decimal Saldo { get; set; }
	public decimal? Disponible { get; set; }
	public decimal Vencido { get; set; }
	public DateTime? UltimaCompra { get; set; }
	public DateTime? UltimoPago { get; set; }
}
