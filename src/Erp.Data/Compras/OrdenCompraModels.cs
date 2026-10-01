namespace Erp.Data.Compras;

// Estados de una orden de compra: B borrador, A aprobada (nada recibido),
// P parcial, R recibida, C cerrada (se canceló el saldo), N anulada.
// P y R se calculan de lo recibido en compras vigentes.
public sealed class OrdenCompraResumen
{
	public int OcpId { get; set; }
	public string Numero { get; set; } = "";
	public DateTime Fecha { get; set; }
	public DateTime? FechaEntrega { get; set; }
	public int PrvId { get; set; }
	public string Proveedor { get; set; } = "";
	public string? Nit { get; set; }
	public string? Bodega { get; set; }
	public string Simbolo { get; set; } = "Q";
	public decimal Total { get; set; }
	public int Ordenado { get; set; }
	public int Recibido { get; set; }
	public string Estado { get; set; } = "B";
	public bool Atrasada { get; set; }
}

public sealed class OrdenCompraEncabezado
{
	public int OcpId { get; set; }
	public string Numero { get; set; } = "";
	public DateTime Fecha { get; set; }
	public DateTime? FechaEntrega { get; set; }
	public string Estado { get; set; } = "B";
	public int PrvId { get; set; }
	public string? ProveedorCodigo { get; set; }
	public string Proveedor { get; set; } = "";
	public string? Nit { get; set; }
	public string? ProveedorDireccion { get; set; }
	public string? ProveedorContacto { get; set; }
	public string? ProveedorTelefono { get; set; }
	public string? ProveedorCorreo { get; set; }
	public int SucId { get; set; }
	public int BodId { get; set; }
	public string? Bodega { get; set; }
	public int MonId { get; set; }
	public string Moneda { get; set; } = "GTQ";
	public string Simbolo { get; set; } = "Q";
	public decimal PorcentajeIva { get; set; }
	public decimal Total { get; set; }
	public decimal IvaIncluido { get; set; }
	public string? Condiciones { get; set; }
	public string? Observaciones { get; set; }
	public string? MotivoCierre { get; set; }
	public string? Usuario { get; set; }
	public string? Aprobo { get; set; }
	public DateTime? FechaAprobacion { get; set; }
	public int Ordenado { get; set; }
	public int Recibido { get; set; }
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

	public bool PorRecibir => Estado is "A" or "P";
}

public sealed class OrdenCompraLinea
{
	public int OcdId { get; set; }
	public int Item { get; set; }
	public int ProId { get; set; }
	public string Codigo { get; set; } = "";
	public string? CodigoProveedor { get; set; }
	public string Descripcion { get; set; } = "";
	public string Unidad { get; set; } = "UND";
	public int Cantidad { get; set; }
	public int Recibido { get; set; }
	public int Pendiente { get; set; }
	public decimal CostoUnitario { get; set; }	// con IVA
	public decimal Total { get; set; }
	public decimal? Existencia { get; set; }
}

public sealed class OrdenCompraRecepcion
{
	public int OcrId { get; set; }
	public int EncId { get; set; }
	public DateTime Fecha { get; set; }
	public string? Documento { get; set; }
	public decimal Total { get; set; }
	public string EstadoCompra { get; set; } = "G";
	public string? Usuario { get; set; }
	public int Unidades { get; set; }
}

public sealed class NuevaOrdenCompra
{
	public int? OcpId { get; set; }		// con valor: reemplaza una orden en borrador
	public DateTime Fecha { get; set; } = DateTime.Today;
	public DateTime? FechaEntrega { get; set; }
	public int PrvId { get; set; }
	public int BodId { get; set; }
	public int? MonId { get; set; }
	public string? Condiciones { get; set; }
	public string? Observaciones { get; set; }
}

public sealed class NuevaLineaOrdenCompra
{
	public int ProId { get; set; }
	public string? Descripcion { get; set; }
	public int Cantidad { get; set; }
	public decimal CostoUnitario { get; set; }	// con IVA
}

// Factura del proveedor con la que se recibe (todo o parte de) la orden.
public sealed class RecepcionOrdenCompra
{
	public DateTime Fecha { get; set; } = DateTime.Today;
	public string? Serie { get; set; }
	public string NumeroDocumento { get; set; } = "";
	public string? Autorizacion { get; set; }
	public DateTime? FechaPrimerPago { get; set; }	// NULL: contado
	public int NumeroCuotas { get; set; } = 1;
	public decimal Enganche { get; set; }
}

public sealed class LineaRecepcionOrdenCompra
{
	public int OcdId { get; set; }
	public int Cantidad { get; set; }
	public decimal CostoUnitario { get; set; }	// con IVA
}
