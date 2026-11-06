namespace Erp.Data.Pagos;

// Datos de pago del proveedor: C = cheque, T = transferencia.
public sealed class ProveedorPago
{
	public int PrvId { get; set; }
	public string FormaPago { get; set; } = "C";
	public int? GefId { get; set; }
	public string? Banco { get; set; }
	// M = monetaria, A = ahorro
	public string? TipoCuenta { get; set; }
	public string? NumeroCuenta { get; set; }
	public string? Titular { get; set; }
}

public sealed class ContrasenaCuotaDisponible
{
	public int PpgId { get; set; }
	public int EncId { get; set; }
	public string Documento { get; set; } = "";
	public DateTime FechaDocumento { get; set; }
	public int Cuota { get; set; }
	public DateTime Vencimiento { get; set; }
	public decimal ValorCuota { get; set; }
	public decimal Pagado { get; set; }
	public decimal Saldo { get; set; }
}

public sealed class ContrasenaCuota
{
	public int PpgId { get; set; }
	public decimal Monto { get; set; }
}

public sealed class ContrasenaResumen
{
	public int CpaId { get; set; }
	public string Numero { get; set; } = "";
	public DateTime Fecha { get; set; }
	public DateTime FechaPago { get; set; }
	public string FormaPago { get; set; } = "C";
	public decimal Total { get; set; }
	// E = pendiente, P = pagada, A = anulada
	public string Estado { get; set; } = "E";
	public int PrvId { get; set; }
	public string ProveedorCodigo { get; set; } = "";
	public string Proveedor { get; set; } = "";
	public string? Nit { get; set; }
	public bool TieneCuenta { get; set; }
	public string? Banco { get; set; }
	public string? CuentaProveedor { get; set; }
	public int Facturas { get; set; }
	public string? Cheque { get; set; }
	public string? Lote { get; set; }
}

public sealed class Contrasena
{
	public int CpaId { get; set; }
	public string Numero { get; set; } = "";
	public DateTime Fecha { get; set; }
	public DateTime FechaPago { get; set; }
	public string FormaPago { get; set; } = "C";
	public decimal Total { get; set; }
	public string? Observaciones { get; set; }
	public string Estado { get; set; } = "E";
	public string? MotivoAnulacion { get; set; }
	public int? BceId { get; set; }
	public string? Cheque { get; set; }
	public int? BltId { get; set; }
	public string? Lote { get; set; }
	public string? Usuario { get; set; }
	public int PrvId { get; set; }
	public string ProveedorCodigo { get; set; } = "";
	public string Proveedor { get; set; } = "";
	public string? Nit { get; set; }
	public string? ProveedorDireccion { get; set; }
	public string? Banco { get; set; }
	public string? TipoCuenta { get; set; }
	public string? CuentaProveedor { get; set; }
	public int CiaId { get; set; }
	public string? NitEmisor { get; set; }
	public string? NombreEmisor { get; set; }
	public string? NombreComercial { get; set; }
	public string? DireccionEmisor { get; set; }
	public string? TelefonoEmisor { get; set; }
	public bool TieneLogo { get; set; }
	public DateTime? LogoActualizado { get; set; }
	public List<ContrasenaLinea> Lineas { get; set; } = [];
}

public sealed class ContrasenaLinea
{
	public int PpgId { get; set; }
	public int EncId { get; set; }
	public string Documento { get; set; } = "";
	public DateTime FechaDocumento { get; set; }
	public int Cuota { get; set; }
	public DateTime Vencimiento { get; set; }
	public decimal Monto { get; set; }
	public decimal SaldoActual { get; set; }
}

public sealed class LoteTransferencia
{
	public int BltId { get; set; }
	public string Numero { get; set; } = "";
	public DateTime Fecha { get; set; }
	public string? Referencia { get; set; }
	public decimal Total { get; set; }
	public int Cantidad { get; set; }
	// A = vigente, N = anulado
	public string Estado { get; set; } = "A";
	public string? MotivoAnulacion { get; set; }
	public int BcbId { get; set; }
	public string CuentaOrigen { get; set; } = "";
	public int GefIdOrigen { get; set; }
	public string? Usuario { get; set; }
}

// Lo que va en el archivo del banco: un encabezado y una fila por transferencia.
public sealed class ArchivoBancoEncabezado
{
	public string Numero { get; set; } = "";
	public DateTime Fecha { get; set; }
	public string? Referencia { get; set; }
	public decimal Total { get; set; }
	public int Cantidad { get; set; }
	public string CuentaOrigen { get; set; } = "";
	public int GefIdOrigen { get; set; }
	public string BancoOrigen { get; set; } = "";
	public string Estado { get; set; } = "A";
	public string? Descripcion { get; set; }
}

public sealed class ArchivoBancoLinea
{
	public int Correlativo { get; set; }
	public string? Codigo { get; set; }
	public string Beneficiario { get; set; } = "";
	public string? Identificacion { get; set; }
	public int? GefId { get; set; }
	public string? BancoCodigo { get; set; }
	public string? Banco { get; set; }
	public string TipoCuenta { get; set; } = "M";
	public string? Cuenta { get; set; }
	public decimal Monto { get; set; }
	public string? Referencia { get; set; }
	public string? Correo { get; set; }
	public string? Documento { get; set; }
}

public sealed class ArchivoBancoDatos
{
	public ArchivoBancoEncabezado? Encabezado { get; set; }
	public List<ArchivoBancoLinea> Lineas { get; set; } = [];
}

public sealed class FormatoArchivo
{
	public int BfaId { get; set; }
	public string Nombre { get; set; } = "";
	public int? GefId { get; set; }
	public string? Banco { get; set; }
	// P = proveedores, N = planilla, A = ambos
	public string Uso { get; set; } = "A";
	// D = delimitado, F = ancho fijo
	public string Tipo { get; set; } = "D";
	public string? Separador { get; set; } = ",";
	public bool Titulos { get; set; }
	public bool Comillas { get; set; }
	public string? Encabezado { get; set; }
	public string? Pie { get; set; }
	public string Extension { get; set; } = "txt";
	public string Codificacion { get; set; } = "ANSI";
	public string FinLinea { get; set; } = "CRLF";
	public string FormatoFecha { get; set; } = "yyyyMMdd";
	public byte Decimales { get; set; } = 2;
	public string SeparadorDecimal { get; set; } = ".";
	public bool MontoSinPunto { get; set; }
	public string CodigoMonetaria { get; set; } = "M";
	public string CodigoAhorro { get; set; } = "A";
	public string Estado { get; set; } = "A";
	public List<FormatoColumna> Columnas { get; set; } = [];
	public List<FormatoBanco> Bancos { get; set; } = [];
}

public sealed class FormatoColumna
{
	public int BfaId { get; set; }
	public int Orden { get; set; }
	public string Campo { get; set; } = "BENEFICIARIO";
	public string? Titulo { get; set; }
	public int? Longitud { get; set; }
	public string? Relleno { get; set; }
	// I = izquierda, D = derecha
	public string Alineacion { get; set; } = "I";
	public string? Valor { get; set; }
	public bool Mayusculas { get; set; }
}

public sealed class FormatoBanco
{
	public int BfaId { get; set; }
	public int GefId { get; set; }
	public string? Banco { get; set; }
	public string Codigo { get; set; } = "";
}
