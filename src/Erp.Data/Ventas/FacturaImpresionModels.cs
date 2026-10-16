namespace Erp.Data.Ventas;

// Datos de la representación gráfica de una factura (48_impresion_factura.sql).
public sealed class FacturaImpresionEncabezado
{
	public int EncId { get; set; }
	public string TdoCodigo { get; set; } = "";
	public string TdoDescripcion { get; set; } = "";
	public bool EsNota { get; set; }
	public string? TipoDte { get; set; }
	public string? NumeroUnico { get; set; }
	public string? SerieInterna { get; set; }
	public string? NumeroInterno { get; set; }
	public DateTime FechaEmision { get; set; }
	public string Estado { get; set; } = "G";
	public string? Motivo { get; set; }
	public string Moneda { get; set; } = "GTQ";
	public string Simbolo { get; set; } = "Q";
	public decimal Total { get; set; }
	public decimal Iva { get; set; }
	public decimal Descuento { get; set; }
	public bool EsCredito { get; set; }
	public decimal? Enganche { get; set; }
	public int? NumeroCuotas { get; set; }

	public int CiaId { get; set; }
	public string? NitEmisor { get; set; }
	public string NombreEmisor { get; set; } = "";
	public string NombreComercial { get; set; } = "";
	public string? DireccionEmisor { get; set; }
	public string? MunicipioEmisor { get; set; }
	public string? DepartamentoEmisor { get; set; }
	public string? TelefonoEmisor { get; set; }
	public string? CorreoEmisor { get; set; }
	public string? AfiliacionIva { get; set; }
	public string? Sucursal { get; set; }
	public int? CodigoEstablecimiento { get; set; }
	public bool TieneLogo { get; set; }
	public DateTime? LogoActualizado { get; set; }

	public string NitReceptor { get; set; } = "CF";
	public string NombreReceptor { get; set; } = "";
	public string? DireccionReceptor { get; set; }
	public string? ClienteCodigo { get; set; }

	public string? Vendedor { get; set; }
	public string? Usuario { get; set; }

	public string? FelEstado { get; set; }
	public string? Uuid { get; set; }
	public string? SerieDte { get; set; }
	public string? NumeroDte { get; set; }
	public DateTime? FechaCertificacion { get; set; }
	public string? Certificador { get; set; }
	public string? XmlCertificado { get; set; }
	public DateTime? FechaAnulacionDte { get; set; }

	public string? OrigenNumeroUnico { get; set; }
	public string? OrigenUuid { get; set; }
	public string? OrigenSerie { get; set; }
	public string? OrigenNumero { get; set; }

	// C carta, T térmica.
	public string Impresora { get; set; } = "C";
	public int AnchoTermica { get; set; } = 80;
	public string? Pie { get; set; }
}

public sealed class FacturaImpresionLinea
{
	public int Linea { get; set; }
	public string BienOServicio { get; set; } = "B";
	public decimal Cantidad { get; set; }
	public string Unidad { get; set; } = "UND";
	public string Descripcion { get; set; } = "";
	public string? Codigo { get; set; }
	public decimal PrecioUnitario { get; set; }
	public decimal Descuento { get; set; }
	public decimal Total { get; set; }
}

public sealed class FacturaImpresionFrase
{
	public int TipoFrase { get; set; }
	public int Escenario { get; set; }
	public string? Texto { get; set; }
}

public sealed class FacturaImpresionCuota
{
	public int Cuota { get; set; }
	public DateTime Vencimiento { get; set; }
	public decimal Monto { get; set; }
}

public sealed class FacturaImpresionPago
{
	public string Forma { get; set; } = "";
	public decimal Monto { get; set; }
	public string? Referencia { get; set; }

	// La consulta (48) antepone "Cheque" al número; en una transferencia ese
	// número es el de la operación.
	public string? ReferenciaTexto => Forma == "Transferencia" && Referencia?.StartsWith("Cheque ", StringComparison.Ordinal) == true
		? "Operación " + Referencia["Cheque ".Length..]
		: Referencia;
}

public sealed record FacturaImpresion(FacturaImpresionEncabezado Encabezado, IReadOnlyList<FacturaImpresionLinea> Lineas,
	IReadOnlyList<FacturaImpresionFrase> Frases, IReadOnlyList<FacturaImpresionCuota> Cuotas, IReadOnlyList<FacturaImpresionPago> Pagos);
