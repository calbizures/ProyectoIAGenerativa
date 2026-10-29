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
	// Si esta factura es el flete de otra compra: esa compra.
	public int? EncIdCompraFlete { get; set; }
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
	public bool DetEsFlete { get; set; }
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
	// Flete sin IVA incluido en esta factura: se reparte al costo de los productos.
	public decimal Flete { get; set; }
	// Esta factura es el flete de otra compra (transportista o factura aparte).
	public int? EncIdCompraFlete { get; set; }
}

// Compra de mercadería a la que se le puede cargar una factura de flete.
public sealed class CompraParaFlete
{
	public int EncId { get; set; }
	public DateTime Fecha { get; set; }
	public string Documento { get; set; } = "";
	public string? Proveedor { get; set; }
	public decimal Total { get; set; }
	public int? BodId { get; set; }
	public decimal FleteSinIva { get; set; }
}

// Factura de flete vinculada a una compra (o la compra de un flete).
public sealed class CompraFleteDocumento
{
	public int EncId { get; set; }
	public DateTime Fecha { get; set; }
	public string Documento { get; set; } = "";
	public string? Proveedor { get; set; }
	public decimal Total { get; set; }
	public string Estado { get; set; } = "";
	public bool EsFleteDeEsta { get; set; }
}

// Costo de una línea de la compra con su parte del flete (sin IVA).
public sealed class CompraFleteLinea
{
	public int DetId { get; set; }
	public decimal NetoSinFlete { get; set; }
	public decimal FleteMismaFactura { get; set; }
	public decimal FleteOtrasFacturas { get; set; }
	public decimal CostoConFlete => NetoSinFlete + FleteMismaFactura + FleteOtrasFacturas;
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
	// Línea de activo fijo: categoría (sin producto) y centro de costo.
	public int? AfcId { get; set; }
	public int? IdDepartamento { get; set; }
}
