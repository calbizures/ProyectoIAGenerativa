using System.Globalization;
using MigraDoc.DocumentObjectModel;
using MigraDoc.DocumentObjectModel.Tables;
using MigraDoc.Rendering;

namespace Erp.Web.Reportes;

// Documento para el cliente en PDF (carta) con el mismo estilo del estado de
// cuenta: factura, recibo de cobro o cotización. Encabezado con el logo y los
// datos de la compañía, el título del documento, los datos del cliente, una
// tabla de líneas, los totales y notas al pie.
public static class DocumentoPdf
{
	public sealed record Columna(string Titulo, double AnchoCm, bool Numerica = false);

	public sealed record Datos(
		EstadoCuentaPdf.Emisor Compania,
		string Titulo,
		string Subtitulo,
		IReadOnlyList<(string Etiqueta, string? Valor)> Encabezado,
		IReadOnlyList<Columna> Columnas,
		IReadOnlyList<string[]> Filas,
		IReadOnlyList<(string Etiqueta, string Valor, bool Destacado)> Totales,
		IReadOnlyList<(string Titulo, IReadOnlyList<string> Lineas)> Secciones,
		IReadOnlyList<string> Notas,
		string Pie,
		string? Marca = null);

	private static readonly CultureInfo Es = CultureInfo.GetCultureInfo("es-GT");
	private static readonly Color Azul = new(13, 27, 76);
	private static readonly Color AzulClaro = new(232, 237, 247);
	private static readonly Color Gris = new(90, 99, 120);
	private static readonly Color Rojo = new(176, 32, 32);
	private const double AnchoUtilCm = 21.59 - 3.0;

	public static byte[] Generar(Datos d)
	{
		FuentesPdf.Registrar();
		var doc = new Document();
		doc.Info.Title = $"{d.Titulo} {d.Subtitulo}";
		doc.Info.Author = d.Compania.NombreComercial;
		var normal = doc.Styles[StyleNames.Normal]!;
		normal.Font.Name = FuentesPdf.Familia;
		normal.Font.Size = 8.5;
		normal.Font.Color = new Color(26, 31, 46);

		var sec = doc.AddSection();
		sec.PageSetup = doc.DefaultPageSetup.Clone();
		sec.PageSetup.PageWidth = Unit.FromInch(8.5);
		sec.PageSetup.PageHeight = Unit.FromInch(11);
		sec.PageSetup.TopMargin = Unit.FromCentimeter(1.4);
		sec.PageSetup.BottomMargin = Unit.FromCentimeter(1.6);
		sec.PageSetup.LeftMargin = sec.PageSetup.RightMargin = Unit.FromCentimeter(1.5);
		var ancho = Unit.FromCentimeter(AnchoUtilCm);

		var pie = sec.Footers.Primary.AddParagraph();
		pie.Format.Font.Size = 7;
		pie.Format.Font.Color = Gris;
		pie.AddText($"{d.Pie} · página ");
		pie.AddPageField();
		pie.AddText(" de ");
		pie.AddNumPagesField();

		Encabezado(sec, d, ancho);
		if (d.Marca is not null)
		{
			var marca = sec.AddParagraph(d.Marca);
			marca.Format.Font.Size = 12;
			marca.Format.Font.Bold = true;
			marca.Format.Font.Color = Rojo;
			marca.Format.Alignment = ParagraphAlignment.Center;
			marca.Format.SpaceAfter = Unit.FromPoint(6);
		}
		Datos2Columnas(sec, d.Encabezado, ancho);

		if (d.Columnas.Count > 0)
		{
			var t = sec.AddTable();
			t.Borders.Visible = false;
			t.LeftPadding = t.RightPadding = Unit.FromPoint(4);
			t.TopPadding = t.BottomPadding = Unit.FromPoint(2);
			var escala = AnchoUtilCm / d.Columnas.Sum(c => c.AnchoCm);
			foreach (var c in d.Columnas)
				t.AddColumn(Unit.FromCentimeter(c.AnchoCm * escala)).Format.Alignment = c.Numerica ? ParagraphAlignment.Right : ParagraphAlignment.Left;
			var enc = t.AddRow();
			enc.HeadingFormat = true;
			enc.Shading.Color = AzulClaro;
			enc.Format.Font.Bold = true;
			enc.Format.Font.Size = 7.5;
			enc.Format.Font.Color = Azul;
			enc.Borders.Bottom.Width = 0.75;
			enc.Borders.Bottom.Color = Azul;
			for (var i = 0; i < d.Columnas.Count; i++) enc.Cells[i].AddParagraph(d.Columnas[i].Titulo.ToUpper(Es));
			foreach (var valores in d.Filas)
			{
				var r = t.AddRow();
				r.Borders.Bottom.Width = 0.25;
				r.Borders.Bottom.Color = new Color(220, 224, 232);
				for (var i = 0; i < valores.Length && i < d.Columnas.Count; i++) r.Cells[i].AddParagraph(valores[i]);
			}
			foreach (var (etiqueta, valor, destacado) in d.Totales)
			{
				var r = t.AddRow();
				r.Format.Font.Bold = destacado;
				if (destacado) { r.Borders.Top.Width = 0.75; r.Borders.Top.Color = Azul; r.Format.Font.Color = Azul; }
				r.Cells[0].MergeRight = d.Columnas.Count - 2;
				r.Cells[0].Format.Alignment = ParagraphAlignment.Right;
				r.Cells[0].AddParagraph(etiqueta);
				r.Cells[d.Columnas.Count - 1].AddParagraph(valor);
			}
		}

		foreach (var (titulo, lineas) in d.Secciones.Where(s => s.Lineas.Count > 0))
		{
			var p = sec.AddParagraph(titulo);
			p.Format.Font.Size = 10;
			p.Format.Font.Bold = true;
			p.Format.Font.Color = Azul;
			p.Format.SpaceBefore = Unit.FromCentimeter(0.45);
			p.Format.SpaceAfter = Unit.FromPoint(3);
			p.Format.KeepWithNext = true;
			foreach (var l in lineas) sec.AddParagraph(l);
		}

		foreach (var nota in d.Notas.Where(n => !string.IsNullOrWhiteSpace(n)))
		{
			var p = sec.AddParagraph(nota);
			p.Format.SpaceBefore = Unit.FromCentimeter(0.35);
			p.Format.Font.Color = Gris;
		}

		var renderer = new PdfDocumentRenderer { Document = doc };
		renderer.RenderDocument();
		using var salida = new MemoryStream();
		renderer.PdfDocument.Save(salida, false);
		return salida.ToArray();
	}

	private static void Encabezado(Section sec, Datos d, Unit ancho)
	{
		var t = sec.AddTable();
		t.Borders.Visible = false;
		t.AddColumn(ancho - Unit.FromCentimeter(6.2));
		t.AddColumn(Unit.FromCentimeter(6.2));
		var fila = t.AddRow();
		var emisor = fila.Cells[0];
		if (d.Compania.Logo is { Length: > 0 } logo && EsImagen(logo))
		{
			var imagen = emisor.AddImage("base64:" + Convert.ToBase64String(logo));
			imagen.Height = Unit.FromCentimeter(1.5);
			imagen.LockAspectRatio = true;
		}
		var nombre = emisor.AddParagraph(d.Compania.NombreComercial);
		nombre.Format.Font.Size = 13;
		nombre.Format.Font.Bold = true;
		nombre.Format.Font.Color = Azul;
		foreach (var linea in new[] { d.Compania.Nit is null ? null : $"NIT {d.Compania.Nit}", d.Compania.Direccion,
					 string.Join(" · ", new[] { d.Compania.Telefono is null ? null : $"Tel. {d.Compania.Telefono}", d.Compania.Correo }.Where(x => !string.IsNullOrWhiteSpace(x))) }
				 .Where(x => !string.IsNullOrWhiteSpace(x)))
			emisor.AddParagraph(linea!).Format.Font.Color = Gris;

		var caja = fila.Cells[1];
		caja.Shading.Color = Azul;
		caja.Format.Alignment = ParagraphAlignment.Center;
		caja.VerticalAlignment = VerticalAlignment.Center;
		var titulo = caja.AddParagraph(d.Titulo.ToUpper(Es));
		titulo.Format.Font.Size = 13;
		titulo.Format.Font.Bold = true;
		titulo.Format.Font.Color = Colors.White;
		titulo.Format.SpaceBefore = Unit.FromPoint(6);
		var sub = caja.AddParagraph(d.Subtitulo);
		sub.Format.Font.Color = Colors.White;
		sub.Format.SpaceAfter = Unit.FromPoint(6);

		var linea2 = sec.AddParagraph();
		linea2.Format.Borders.Bottom.Width = 1.5;
		linea2.Format.Borders.Bottom.Color = Azul;
		linea2.Format.SpaceAfter = Unit.FromCentimeter(0.3);
	}

	// Pares etiqueta/valor en dos columnas.
	private static void Datos2Columnas(Section sec, IReadOnlyList<(string Etiqueta, string? Valor)> pares, Unit ancho)
	{
		if (pares.Count == 0) return;
		var t = sec.AddTable();
		t.Borders.Color = new Color(210, 216, 228);
		t.Borders.Width = 0.5;
		t.LeftPadding = t.RightPadding = Unit.FromPoint(5);
		t.TopPadding = t.BottomPadding = Unit.FromPoint(2.5);
		var mitad = ancho / 2;
		t.AddColumn(Unit.FromCentimeter(2.6)); t.AddColumn(mitad - Unit.FromCentimeter(2.6));
		t.AddColumn(Unit.FromCentimeter(2.6)); t.AddColumn(mitad - Unit.FromCentimeter(2.6));
		for (var i = 0; i < pares.Count; i += 2)
		{
			var r = t.AddRow();
			for (var j = 0; j < 2 && i + j < pares.Count; j++)
			{
				r.Cells[j * 2].AddParagraph(pares[i + j].Etiqueta).Format.Font.Color = Gris;
				r.Cells[j * 2 + 1].AddParagraph(string.IsNullOrWhiteSpace(pares[i + j].Valor) ? "—" : pares[i + j].Valor!);
			}
		}
		sec.AddParagraph().Format.SpaceAfter = Unit.FromCentimeter(0.2);
	}

	// PNG, JPEG, GIF o BMP: MigraDoc no dibuja SVG ni WebP.
	private static bool EsImagen(byte[] b) =>
		b.Length > 4 && ((b[0] == 0x89 && b[1] == 0x50) || (b[0] == 0xFF && b[1] == 0xD8) || (b[0] == 0x47 && b[1] == 0x49) || (b[0] == 0x42 && b[1] == 0x4D));
}
