using System.Xml.Linq;
using Erp.Data.Fel;
using Erp.Web.Fel;

namespace Erp.Tests.Unitarias;

public class FelXmlBuilderTests
{
	private static readonly XNamespace Dte = "http://www.sat.gob.gt/dte/fel/0.2.0";

	private static FelEncabezado Encabezado() => new()
	{
		EncId = 1,
		FechaHoraEmision = new DateTime(2026, 11, 2, 10, 30, 0),
		NitEmisor = "12345678K",
		NombreEmisor = "Empresa de prueba, S.A.",
		NombreComercial = "Prueba",
		IdReceptor = "CF",
		NombreReceptor = "Consumidor final"
	};

	private static FelItem Item(int linea, decimal cantidad, decimal precioNeto, decimal iva = 12, string descripcion = "Producto") => new()
	{
		NumeroLinea = linea,
		Cantidad = cantidad,
		PrecioUnitarioNeto = precioNeto,
		SubTotalNeto = cantidad * precioNeto,
		PorcIva = iva,
		Descripcion = descripcion
	};

	private static XDocument Construir(IReadOnlyList<FelItem> items, IReadOnlyList<FelFraseDocumento>? frases = null,
		FelEncabezado? encabezado = null, FelAdenda? adenda = null, string tipo = "FACT")
	{
		var datos = new FelDocumentoDatos(encabezado ?? Encabezado(), items, frases ?? [], []) { Adenda = adenda };
		return XDocument.Parse(FelXmlBuilder.ConstruirDte(datos, tipo));
	}

	[Fact]
	public void Precio_con_IVA_redondeado_por_unidad()
	{
		// 3 × 10.00 sin IVA: precio unitario con IVA 11.20, precio 33.60, IVA 3.60.
		var linea = FelXmlBuilder.Calcular(Item(1, 3, 10m));

		Assert.Equal(11.20m, linea.PrecioUnitario);
		Assert.Equal(33.60m, linea.Precio);
		Assert.Equal(30.00m, linea.MontoGravable);
		Assert.Equal(3.60m, linea.MontoImpuesto);
		Assert.Equal(linea.Total, linea.MontoGravable + linea.MontoImpuesto);
	}

	[Fact]
	public void Gran_total_es_la_suma_de_las_lineas()
	{
		var xml = Construir([Item(1, 3, 10m), Item(2, 1.5m, 7.33m)]);

		var totales = xml.Descendants(Dte + "Item").Sum(i => decimal.Parse(i.Element(Dte + "Total")!.Value, System.Globalization.CultureInfo.InvariantCulture));
		var granTotal = decimal.Parse(xml.Descendants(Dte + "GranTotal").Single().Value, System.Globalization.CultureInfo.InvariantCulture);
		Assert.Equal(totales, granTotal);
	}

	[Fact]
	public void La_frase_de_exencion_solo_va_con_lineas_exentas()
	{
		FelFraseDocumento[] frases = [new() { TipoFrase = 1, CodigoEscenario = 1 }, new() { TipoFrase = 4, CodigoEscenario = 1 }];

		var sinExentas = Construir([Item(1, 1, 100m)], frases);
		var conExentas = Construir([Item(1, 1, 100m), Item(2, 1, 50m, iva: 0)], frases);

		Assert.DoesNotContain(sinExentas.Descendants(Dte + "Frase"), f => f.Attribute("TipoFrase")!.Value == "4");
		Assert.Contains(conExentas.Descendants(Dte + "Frase"), f => f.Attribute("TipoFrase")!.Value == "4");
		Assert.Equal("2", conExentas.Descendants(Dte + "CodigoUnidadGravable").Last().Value);
	}

	[Fact]
	public void Los_textos_largos_se_recortan_al_largo_de_SAT()
	{
		var encabezado = Encabezado();
		encabezado.NombreReceptor = new string('N', 300);
		encabezado.MunicipioReceptor = new string('M', 150);
		var xml = Construir([Item(1, 1, 10m, descripcion: new string('D', 600))], encabezado: encabezado);

		Assert.Equal(500, xml.Descendants(Dte + "Descripcion").Single().Value.Length);
		Assert.Equal(255, xml.Descendants(Dte + "Receptor").Single().Attribute("NombreReceptor")!.Value.Length);
		Assert.Equal(100, xml.Descendants(Dte + "DireccionReceptor").Single().Element(Dte + "Municipio")!.Value.Length);
	}

	[Fact]
	public void La_adenda_va_dentro_de_SAT_despues_del_DTE()
	{
		var xml = Construir([Item(1, 1, 10m)], adenda: new FelAdenda { NumeroInterno = "A-15", Sucursal = "Central", Usuario = "admin" });

		var sat = xml.Root!.Element(Dte + "SAT")!;
		var hijos = sat.Elements().Select(e => e.Name.LocalName).ToList();
		Assert.Equal(["DTE", "Adenda"], hijos);
		Assert.Contains("A-15", sat.Element(Dte + "Adenda")!.Value);
	}

	[Theory]
	[InlineData("CF", true)]
	[InlineData("c/f", true)]
	[InlineData(" ", true)]
	[InlineData("12345678K", false)]
	public void Consumidor_final(string id, bool esperado)
	{
		Assert.Equal(esperado, FelXmlBuilder.EsConsumidorFinal(id));
	}

	[Fact]
	public void Fecha_con_zona_horaria_de_Guatemala()
	{
		Assert.Equal("2026-11-02T10:30:00-06:00", FelXmlBuilder.FechaHora(new DateTime(2026, 11, 2, 10, 30, 0)));
	}
}
