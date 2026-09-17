namespace Erp.Data.Compras;

public sealed class Proveedor
{
	public int PrvId { get; set; }
	public string PrvCodigo { get; set; } = "";
	public string PrvNombreComercial { get; set; } = "";
	public string? PrvNit { get; set; }
	public string? PrvContacto { get; set; }
	public string? PrvTelefonoOficina { get; set; }
	public string? PrvEmailEmpresa { get; set; }
	public string PrvEstado { get; set; } = "A";
}

public sealed class DocumentoTipoCompra
{
	public int TdoId { get; set; }
	public string TdoCodigo { get; set; } = "";
	public string TdoDescripcion { get; set; } = "";
}

public sealed class Moneda
{
	public int MonId { get; set; }
	public string MonCodigo { get; set; } = "";
	public string MonNombre { get; set; } = "";
	public string? MonSimbolo { get; set; }
	public bool MonEsLocal { get; set; }
}

public sealed class CompraEncabezado
{
	public int EncId { get; set; }
	public DateTime EncFechaDocto { get; set; }
	public string? EncSerieDocto { get; set; }
	public string? EncNumeroDocto { get; set; }
	public string TdoCodigo { get; set; } = "";
	public string TdoDescripcion { get; set; } = "";
	public int? PrvId { get; set; }
	public string? PrvNombreComercial { get; set; }
	public decimal EncMontoTotal { get; set; }
	public string EncEstado { get; set; } = "";
}

public sealed class CompraEncabezadoDetalle
{
	public int EncId { get; set; }
	public DateTime EncFechaDocto { get; set; }
	public string? EncSerieDocto { get; set; }
	public string? EncNumeroDocto { get; set; }
	public int? PrvId { get; set; }
	public string? PrvEncNombresProveedor { get; set; }
	public string? PrvNit { get; set; }
	public string TdoDescripcion { get; set; } = "";
	public decimal EncMontoTotal { get; set; }
	public decimal EncValorDescuento { get; set; }
	public int? MonId { get; set; }
	public string EncEstado { get; set; } = "";
}

public sealed class CompraDetalleLinea
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

public sealed class NuevaCompraEncabezado
{
	public DateTime FechaDocumento { get; set; } = DateTime.Today;
	public string? NumeroAutorizacion { get; set; }
	public string? SerieDocumento { get; set; }
	public string? NumeroDocumento { get; set; }
	public int PrvId { get; set; }
	public string? NombreProveedor { get; set; }
	public string? Nit { get; set; }
	public int TdoId { get; set; }
	public DateTime? FechaPrimerPago { get; set; }
	public decimal MontoEnganche { get; set; }
	public int NumeroCuotas { get; set; } = 1;
	public decimal ValorDescuento { get; set; }
	public int? MonId { get; set; }
}

public sealed class NuevaLineaCompra
{
	public int? ProId { get; set; }
	public string BienOServicio { get; set; } = "B";
	public int Cantidad { get; set; }
	public string Descripcion { get; set; } = "";
	public decimal PrecioUnitario { get; set; }
	public decimal ValorDescuento { get; set; }
	public decimal SubTotal { get; set; }
	public decimal? PorcentajeIva { get; set; }
	public int BodId { get; set; }
}
