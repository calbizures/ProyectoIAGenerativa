namespace Erp.Data.Ventas;

public sealed class Cliente
{
	public int CliId { get; set; }
	public string CliCodigo { get; set; } = "";
	public string CliNombres { get; set; } = "";
	public string? CliApellidos { get; set; }
	public string? CliNit { get; set; }
	public string? CliDireccion { get; set; }
	public string? CliTelefonoCelular { get; set; }
	public decimal CliLimiteCredito { get; set; }
	public string CliEstado { get; set; } = "A";

	public string NombreCompleto => string.IsNullOrWhiteSpace(CliApellidos) ? CliNombres : $"{CliNombres} {CliApellidos}";
}

public sealed class Vendedor
{
	public int PveId { get; set; }
	public string PveCodigo { get; set; } = "";
	public string PveNombres { get; set; } = "";
	public string? PveApellidos { get; set; }
	public DateTime? PveFechaIngreso { get; set; }
	public decimal PvePorcComision { get; set; }
	public string PveEstado { get; set; } = "A";
}

public sealed class Moneda
{
	public int MonId { get; set; }
	public string MonCodigo { get; set; } = "";
	public string MonNombre { get; set; } = "";
	public string? MonSimbolo { get; set; }
	public bool MonEsLocal { get; set; }
}

public sealed class DocumentoTipoVenta
{
	public int TdoId { get; set; }
	public string TdoCodigo { get; set; } = "";
	public string TdoDescripcion { get; set; } = "";
}

public sealed class FacturaEncabezado
{
	public int EncId { get; set; }
	public DateTime EncFechaDocto { get; set; }
	public string? EncSerieDocto { get; set; }
	public string? EncNumeroDocto { get; set; }
	public string TdoCodigo { get; set; } = "";
	public string TdoDescripcion { get; set; } = "";
	public int? CliId { get; set; }
	public string? CliNombres { get; set; }
	public string? CliApellidos { get; set; }
	public decimal EncMontoTotal { get; set; }
	public string EncEstado { get; set; } = "";
	public string NombreCliente => $"{CliNombres} {CliApellidos}".Trim();
}

public sealed class FacturaEncabezadoDetalle
{
	public int EncId { get; set; }
	public DateTime EncFechaDocto { get; set; }
	public string? EncSerieDocto { get; set; }
	public string? EncNumeroDocto { get; set; }
	public string? EncNumeroUnico { get; set; }
	public int? CliId { get; set; }
	public string? EncNombresCliente { get; set; }
	public string? EncApellidosCliente { get; set; }
	public string? CliNit { get; set; }
	public string? EncDireccionCliente { get; set; }
	public string TdoDescripcion { get; set; } = "";
	public int? PveId { get; set; }
	public decimal EncMontoTotal { get; set; }
	public decimal EncValorDescuento { get; set; }
	public int? MonId { get; set; }
	public string EncEstado { get; set; } = "";
}

public sealed class FacturaDetalleLinea
{
	public int DetId { get; set; }
	public int DetItem { get; set; }
	public string DetBienOServicio { get; set; } = "B";
	public int DetCantidad { get; set; }
	public string DetDescripcion { get; set; } = "";
	public decimal DetPrecioUnitario { get; set; }
	public decimal DetValorDescuento { get; set; }
	public decimal DetSubTotal { get; set; }
	public decimal? DetPorcIva { get; set; }
	public int BodId { get; set; }
	public int? ProId { get; set; }
}

public sealed class NuevaFacturaEncabezado
{
	public DateTime FechaDocumento { get; set; } = DateTime.Today;
	public string? NumeroAutorizacion { get; set; }
	public string? SerieDocumento { get; set; }
	public string? NumeroDocumento { get; set; }
	public int CliId { get; set; }
	public string? NombresCliente { get; set; }
	public string? ApellidosCliente { get; set; }
	public string? Nit { get; set; }
	public int TdoId { get; set; }
	public int? PveId { get; set; }
	public DateTime? FechaPrimerPago { get; set; }
	public decimal MontoEnganche { get; set; }
	public int NumeroCuotas { get; set; } = 1;
	public decimal ValorDescuento { get; set; }
	public string? DireccionCliente { get; set; }
	public int? MonId { get; set; }
}

public sealed class NuevaLineaFactura
{
	public int ProId { get; set; }
	public string BienOServicio { get; set; } = "B";
	public int Cantidad { get; set; }
	public string Descripcion { get; set; } = "";
	public decimal PrecioUnitario { get; set; }
	public decimal ValorDescuento { get; set; }
	public decimal SubTotal { get; set; }
	public decimal? PorcentajeIva { get; set; }
	public int BodId { get; set; }
}
