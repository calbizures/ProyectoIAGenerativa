namespace Erp.Data.Ventas;

// Estados de una cotización: V vigente, X vencida (vigente con la fecha pasada),
// F facturada, A anulada.
public sealed class CotizacionResumen
{
	public int CotId { get; set; }
	public string Numero { get; set; } = "";
	public DateTime Fecha { get; set; }
	public DateTime Vence { get; set; }
	public int VigenciaDias { get; set; }
	public string Estado { get; set; } = "V";
	public int? DiasRestantes { get; set; }
	public int? CliId { get; set; }
	public string Cliente { get; set; } = "";
	public string? Nit { get; set; }
	public string? Vendedor { get; set; }
	public string Simbolo { get; set; } = "Q";
	public decimal Total { get; set; }
	public int? EncId { get; set; }
	public string? Factura { get; set; }
	public string? Sucursal { get; set; }
}

public sealed class CotizacionEncabezado
{
	public int CotId { get; set; }
	public string Numero { get; set; } = "";
	public DateTime Fecha { get; set; }
	public DateTime Vence { get; set; }
	public int VigenciaDias { get; set; }
	public string Estado { get; set; } = "V";
	public int? DiasRestantes { get; set; }
	public int SucId { get; set; }
	public int BodId { get; set; }
	public int MonId { get; set; }
	public int? PveId { get; set; }
	public int? CliId { get; set; }
	public string? Nit { get; set; }
	public string Cliente { get; set; } = "";
	public string? Direccion { get; set; }
	public string? Telefono { get; set; }
	public string? Correo { get; set; }
	public string? ClienteCodigo { get; set; }
	public string? Vendedor { get; set; }
	public decimal PorcentajeIva { get; set; }
	public decimal Descuento { get; set; }
	public decimal Total { get; set; }
	public decimal IvaIncluido { get; set; }
	public string? Observaciones { get; set; }
	public string? MotivoAnulacion { get; set; }
	public int? EncId { get; set; }
	public string? Factura { get; set; }
	public string Moneda { get; set; } = "GTQ";
	public string Simbolo { get; set; } = "Q";
	public string? Bodega { get; set; }
	public string? Usuario { get; set; }
	public int CiaId { get; set; }
	public string? NitEmisor { get; set; }
	public string? NombreEmisor { get; set; }
	public string? NombreComercial { get; set; }
	public string? DireccionEmisor { get; set; }
	public string? TelefonoEmisor { get; set; }
	public string? CorreoEmisor { get; set; }
	public string? Sucursal { get; set; }
	public bool TieneLogo { get; set; }
	public DateTime? LogoActualizado { get; set; }

	public bool PuedeFacturarse => Estado == "V";
}

public sealed class CotizacionLinea
{
	public int Item { get; set; }
	public string BienOServicio { get; set; } = "B";
	public int? ProId { get; set; }
	public int? PprId { get; set; }
	public int? UmeId { get; set; }
	public string Unidad { get; set; } = "UND";
	public string? Codigo { get; set; }
	public string Descripcion { get; set; } = "";
	public decimal Cantidad { get; set; }
	public decimal PrecioUnitario { get; set; }	// con IVA
	public decimal Descuento { get; set; }
	public decimal Total { get; set; }
	public bool ManejaExistencia { get; set; }
	public decimal? CostoUnitario { get; set; }
	public decimal? Existencia { get; set; }
}

public sealed class NuevaCotizacion
{
	public DateTime Fecha { get; set; } = DateTime.Today;
	public int BodId { get; set; }
	public int? MonId { get; set; }
	public int? CliId { get; set; }
	public string? Nit { get; set; }
	public string? Nombre { get; set; }
	public string? Direccion { get; set; }
	public string? Telefono { get; set; }
	public string? Correo { get; set; }
	public int? PveId { get; set; }
	public string? Observaciones { get; set; }
}

public sealed class NuevaLineaCotizacion
{
	public string BienOServicio { get; set; } = "B";
	public int? ProId { get; set; }
	public int? PprId { get; set; }
	public int? UmeId { get; set; }
	public string Descripcion { get; set; } = "";
	public decimal Cantidad { get; set; }
	public decimal PrecioUnitario { get; set; }	// con IVA
	public decimal Descuento { get; set; }
}
