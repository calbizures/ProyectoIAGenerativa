using System.Globalization;
using System.Xml.Linq;
using Erp.Data.Fel;

namespace Erp.Web.Fel;

// Arma el XML del DTE (GTDocumento) y el de su anulación (GTAnulacionDocumento)
// según el esquema FEL de SAT, con los parámetros de la base (emisor por
// sucursal, frases, tipo de DTE, unidad de medida, receptor por defecto...).
// Reemplaza a spr_sel_pos_factura_xml: XDocument escapa el texto (un "&" o
// "<" en una descripción ya no rompe el XML) y los montos salen de las
// líneas grabadas, no de un 12 % fijo.
public static class FelXmlBuilder
{
	private static readonly XNamespace Ds = "http://www.w3.org/2000/09/xmldsig#";
	private static readonly XNamespace Xsi = "http://www.w3.org/2001/XMLSchema-instance";
	private static readonly XNamespace Cfc = "http://www.sat.gob.gt/dte/fel/CompCambiaria/0.1.0";
	private static readonly XNamespace Cno = "http://www.sat.gob.gt/face2/ComplementoReferenciaNota/0.1.0";
	private static readonly XNamespace DteAnulacion = "http://www.sat.gob.gt/dte/fel/0.1.0";
	public const string ZonaHoraria = "-06:00";

	public static string Monto(decimal valor) => valor.ToString("0.00", CultureInfo.InvariantCulture);
	private static string Cantidad(decimal valor) => valor.ToString("0.####", CultureInfo.InvariantCulture);
	private static string Precio(decimal valor) => valor.ToString("0.######", CultureInfo.InvariantCulture);
	public static string FechaHora(DateTime valor) => valor.ToString("yyyy-MM-dd'T'HH:mm:ss", CultureInfo.InvariantCulture) + ZonaHoraria;
	private static string Fecha(DateTime valor) => valor.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

	// Montos de una línea como los pide SAT: precios con IVA incluido.
	public sealed record LineaFel(FelItem Item, decimal PrecioUnitario, decimal Precio, decimal Descuento, decimal Total,
		decimal MontoGravable, decimal MontoImpuesto, bool Exenta);

	public static LineaFel Calcular(FelItem item)
	{
		// La factura guarda los montos sin IVA; el precio con IVA se redondea
		// por unidad para que Cantidad × PrecioUnitario = Precio (SAT lo valida).
		var factor = 1 + item.PorcIva / 100m;
		var precioUnitario = Math.Round(item.PrecioUnitarioNeto * factor, 2);
		var precio = Math.Round(precioUnitario * item.Cantidad, 2);
		var descuento = Math.Round(item.DescuentoNeto * factor, 2);
		var total = precio - descuento;
		var exenta = item.PorcIva <= 0;
		var gravable = exenta ? total : Math.Round(total / factor, 2);
		return new LineaFel(item, precioUnitario, precio, descuento, total, gravable, exenta ? 0 : total - gravable, exenta);
	}

	public static string ConstruirDte(FelDocumentoDatos datos, string tipoDte)
	{
		var e = datos.Encabezado;
		XNamespace dte = e.XmlnsDte;
		var lineas = datos.Items.Select(Calcular).ToList();
		var esNota = tipoDte is "NCRE" or "NDEB";

		var emisor = new XElement(dte + "Emisor",
			new XAttribute("AfiliacionIVA", e.AfiliacionIva),
			new XAttribute("CodigoEstablecimiento", e.CodigoEstablecimiento ?? 1),
			string.IsNullOrWhiteSpace(e.CorreoEmisor) ? null : new XAttribute("CorreoEmisor", e.CorreoEmisor),
			new XAttribute("NITEmisor", e.NitEmisor),
			new XAttribute("NombreComercial", e.NombreComercial),
			new XAttribute("NombreEmisor", e.NombreEmisor),
			Direccion(dte, "DireccionEmisor", e.DireccionEmisor ?? "Ciudad", e.CodigoPostalEmisor, e.MunicipioEmisor ?? "Guatemala",
				e.DepartamentoEmisor ?? "Guatemala", e.PaisEmisor));

		var receptor = new XElement(dte + "Receptor",
			string.IsNullOrWhiteSpace(e.CorreoReceptor) ? null : new XAttribute("CorreoReceptor", e.CorreoReceptor),
			new XAttribute("IDReceptor", e.IdReceptor),
			new XAttribute("NombreReceptor", string.IsNullOrWhiteSpace(e.NombreReceptor) ? "Consumidor final" : e.NombreReceptor),
			string.IsNullOrEmpty(e.TipoEspecial) ? null : new XAttribute("TipoEspecial", e.TipoEspecial),
			Direccion(dte, "DireccionReceptor", e.DireccionReceptor, e.CodigoPostalReceptor, e.MunicipioReceptor, e.DepartamentoReceptor, e.PaisReceptor));

		var frases = datos.Frases.Where(f => !esNota || f.AplicaNotas).ToList();

		var items = new XElement(dte + "Items", lineas.Select(l => new XElement(dte + "Item",
			new XAttribute("BienOServicio", l.Item.BienOServicio),
			new XAttribute("NumeroLinea", l.Item.NumeroLinea),
			new XElement(dte + "Cantidad", Cantidad(l.Item.Cantidad)),
			new XElement(dte + "UnidadMedida", l.Item.UnidadMedida),
			new XElement(dte + "Descripcion", l.Item.Descripcion),
			new XElement(dte + "PrecioUnitario", Precio(l.PrecioUnitario)),
			new XElement(dte + "Precio", Monto(l.Precio)),
			new XElement(dte + "Descuento", Monto(l.Descuento)),
			new XElement(dte + "Impuestos", new XElement(dte + "Impuesto",
				new XElement(dte + "NombreCorto", "IVA"),
				new XElement(dte + "CodigoUnidadGravable", l.Exenta ? 2 : 1),
				new XElement(dte + "MontoGravable", Monto(l.MontoGravable)),
				new XElement(dte + "MontoImpuesto", Monto(l.MontoImpuesto)))),
			new XElement(dte + "Total", Monto(l.Total)))));

		var totales = new XElement(dte + "Totales",
			new XElement(dte + "TotalImpuestos", new XElement(dte + "TotalImpuesto",
				new XAttribute("NombreCorto", "IVA"),
				new XAttribute("TotalMontoImpuesto", Monto(lineas.Sum(l => l.MontoImpuesto))))),
			new XElement(dte + "GranTotal", Monto(lineas.Sum(l => l.Total))));

		XElement? complementos = null;
		if (tipoDte == "FCAM" && datos.Abonos.Count > 0)
		{
			complementos = new XElement(dte + "Complementos", new XElement(dte + "Complemento",
				new XAttribute("IDComplemento", "Cambiaria"),
				new XAttribute("NombreComplemento", "Cambiaria"),
				new XAttribute("URIComplemento", "http://www.sat.gob.gt/fel/cambiaria.xsd"),
				new XElement(Cfc + "AbonosFacturaCambiaria",
					new XAttribute(XNamespace.Xmlns + "cfc", Cfc),
					new XAttribute("Version", "1"),
					datos.Abonos.Select(a => new XElement(Cfc + "Abono",
						new XElement(Cfc + "NumeroAbono", a.NumeroAbono),
						new XElement(Cfc + "FechaVencimiento", Fecha(a.FechaVencimiento)),
						new XElement(Cfc + "MontoAbono", Monto(a.MontoAbono)))))));
		}
		else if (esNota)
		{
			complementos = new XElement(dte + "Complementos", new XElement(dte + "Complemento",
				new XAttribute("IDComplemento", "ReferenciasNota"),
				new XAttribute("NombreComplemento", "ReferenciasNota"),
				new XAttribute("URIComplemento", Cno.NamespaceName),
				new XElement(Cno + "ReferenciasNota",
					new XAttribute(XNamespace.Xmlns + "cno", Cno),
					new XAttribute("FechaEmisionDocumentoOrigen", Fecha(e.OrigenFechaEmision ?? e.FechaHoraEmision)),
					new XAttribute("MotivoAjuste", e.MotivoAjuste ?? "Ajuste"),
					new XAttribute("NumeroAutorizacionDocumentoOrigen", e.OrigenUuid ?? ""),
					string.IsNullOrEmpty(e.OrigenSerie) ? null : new XAttribute("SerieDocumentoOrigen", e.OrigenSerie),
					string.IsNullOrEmpty(e.OrigenNumero) ? null : new XAttribute("NumeroDocumentoOrigen", e.OrigenNumero),
					new XAttribute("Version", "0.0"))));
		}

		var documento = new XDocument(new XDeclaration("1.0", "UTF-8", null),
			new XElement(dte + "GTDocumento",
				new XAttribute(XNamespace.Xmlns + "ds", Ds),
				new XAttribute(XNamespace.Xmlns + "dte", dte),
				new XAttribute(XNamespace.Xmlns + "xsi", Xsi),
				new XAttribute("Version", e.VersionDte),
				new XAttribute(Xsi + "schemaLocation", dte.NamespaceName),
				new XElement(dte + "SAT", new XAttribute("ClaseDocumento", "dte"),
					new XElement(dte + "DTE", new XAttribute("ID", "DatosCertificados"),
						new XElement(dte + "DatosEmision", new XAttribute("ID", "DatosEmision"),
							new XElement(dte + "DatosGenerales",
								new XAttribute("CodigoMoneda", e.CodigoMoneda),
								new XAttribute("FechaHoraEmision", FechaHora(e.FechaHoraEmision)),
								new XAttribute("Tipo", tipoDte)),
							emisor,
							receptor,
							frases.Count == 0 ? null : new XElement(dte + "Frases", frases.Select(f => new XElement(dte + "Frase",
								new XAttribute("CodigoEscenario", f.CodigoEscenario),
								new XAttribute("TipoFrase", f.TipoFrase)))),
							items,
							totales,
							complementos)))));

		return Serializar(documento);
	}

	public static string ConstruirAnulacion(FelEncabezado e, DateTime fechaEmisionOriginal, string uuid, string motivo, DateTime fechaAnulacion)
	{
		XNamespace dte = DteAnulacion;
		var documento = new XDocument(new XDeclaration("1.0", "UTF-8", null),
			new XElement(dte + "GTAnulacionDocumento",
				new XAttribute(XNamespace.Xmlns + "ds", Ds),
				new XAttribute(XNamespace.Xmlns + "dte", dte),
				new XAttribute(XNamespace.Xmlns + "xsi", Xsi),
				new XAttribute("Version", "0.1"),
				new XElement(dte + "SAT",
					new XElement(dte + "AnulacionDTE", new XAttribute("ID", "DatosCertificados"),
						new XElement(dte + "DatosGenerales",
							new XAttribute("FechaEmisionDocumentoAnular", FechaHora(fechaEmisionOriginal)),
							new XAttribute("FechaHoraAnulacion", FechaHora(fechaAnulacion)),
							new XAttribute("ID", "DatosAnulacion"),
							new XAttribute("IDReceptor", e.IdReceptor),
							new XAttribute("MotivoAnulacion", motivo),
							new XAttribute("NITEmisor", e.NitEmisor),
							new XAttribute("NumeroDocumentoAAnular", uuid))))));
		return Serializar(documento);
	}

	private static XElement Direccion(XNamespace dte, string nombre, string direccion, string codigoPostal, string municipio, string departamento, string pais) =>
		new(dte + nombre,
			new XElement(dte + "Direccion", direccion),
			new XElement(dte + "CodigoPostal", codigoPostal),
			new XElement(dte + "Municipio", municipio),
			new XElement(dte + "Departamento", departamento),
			new XElement(dte + "Pais", pais));

	private static string Serializar(XDocument documento)
	{
		using var escritor = new Utf8StringWriter();
		documento.Save(escritor, SaveOptions.DisableFormatting);
		return escritor.ToString();
	}

	private sealed class Utf8StringWriter : StringWriter
	{
		public override System.Text.Encoding Encoding => new System.Text.UTF8Encoding(false);
	}
}
