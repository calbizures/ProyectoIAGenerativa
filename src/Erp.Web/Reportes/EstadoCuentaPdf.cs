using System.Globalization;
using Erp.Data.Cuentas;
using MigraDoc.DocumentObjectModel;
using MigraDoc.DocumentObjectModel.Tables;
using MigraDoc.Rendering;

namespace Erp.Web.Reportes;

// Estado de cuenta del cliente en PDF (carta), para enviarlo por correo o
// descargarlo: datos del cliente, crédito, antigüedad, cuotas y documentos
// pendientes y los movimientos del período con su saldo corrido.
public static class EstadoCuentaPdf
{
	public sealed record Emisor(string NombreComercial, string? Nit, string? Direccion, string? Telefono, string? Correo, byte[]? Logo);

	public sealed record Datos(Emisor Compania, ClienteEstadoCuenta Cliente, IReadOnlyList<AntiguedadFila> Cuotas,
		IReadOnlyList<DocumentoSaldo> Documentos, IReadOnlyList<MovimientoEstadoCuenta> Movimientos, DateTime? Desde, DateTime Hasta, DateTime Generado);

	private static readonly CultureInfo Es = CultureInfo.GetCultureInfo("es-GT");
	private static readonly Color Azul = new(13, 27, 76);
	private static readonly Color AzulClaro = new(232, 237, 247);
	private static readonly Color Gris = new(90, 99, 120);
	private static readonly Color Rojo = new(176, 32, 32);

	public static string NombreArchivo(ClienteEstadoCuenta cliente, DateTime corte) => $"estado-cuenta-{cliente.Codigo}-{corte:yyyyMMdd}.pdf".ToLowerInvariant();

	public static byte[] Generar(Datos d)
	{
		FuentesPdf.Registrar();
		var doc = new Document();
		doc.Info.Title = $"Estado de cuenta {d.Cliente.Codigo}";
		doc.Info.Author = d.Compania.NombreComercial;
		var normal = doc.Styles[StyleNames.Normal]!;
		normal.Font.Name = FuentesPdf.Familia;
		normal.Font.Size = 8.5;
		normal.Font.Color = new Color(26, 31, 46);

		var sec = doc.AddSection();
		sec.PageSetup = doc.DefaultPageSetup.Clone();
		// Carta: con la configuración clonada, PageFormat no cambia las medidas (vienen de A4).
		sec.PageSetup.PageWidth = Unit.FromInch(8.5);
		sec.PageSetup.PageHeight = Unit.FromInch(11);
		sec.PageSetup.TopMargin = Unit.FromCentimeter(1.4);
		sec.PageSetup.BottomMargin = Unit.FromCentimeter(1.6);
		sec.PageSetup.LeftMargin = sec.PageSetup.RightMargin = Unit.FromCentimeter(1.5);
		var ancho = Unit.FromCentimeter(21.59 - 3.0);

		Pie(sec, d);
		Encabezado(sec, d, ancho);
		Cliente(sec, d, ancho);
		Resumen(sec, d, ancho);

		Titulo(sec, "Cuotas pendientes");
		if (d.Cuotas.Count == 0) Texto(sec, "El cliente no tiene cuotas pendientes.");
		else
		{
			var t = Tabla(sec, ["Documento", "Fecha", "Cuota", "Vence", "Situación", "Saldo"], [4.6, 2.2, 1.4, 2.2, 5.0, 3.19], [false, false, true, false, false, true]);
			foreach (var c in d.Cuotas.OrderBy(c => c.Vencimiento).ThenBy(c => c.Documento))
			{
				var situacion = c.Dias > 0 ? $"Vencida hace {c.Dias} día{(c.Dias == 1 ? "" : "s")}" : c.Dias == 0 ? "Vence hoy" : $"Vence en {-c.Dias} día{(c.Dias == -1 ? "" : "s")}";
				var fila = Fila(t, c.Documento, F(c.FechaDocumento), c.Cuota.ToString(Es), F(c.Vencimiento), situacion, M(c.Saldo));
				if (c.Dias > 0) fila.Cells[4].Format.Font.Color = Rojo;
			}
			Total(t, "Total pendiente", M(d.Cuotas.Sum(c => c.Saldo)));
		}

		Titulo(sec, "Documentos con saldo");
		if (d.Documentos.Count == 0) Texto(sec, "No hay documentos con saldo.");
		else
		{
			var t = Tabla(sec, ["Documento", "Fecha", "Total", "Pagado", "Notas", "Saldo"], [4.6, 2.2, 2.95, 2.95, 2.95, 2.94], [false, false, true, true, true, true]);
			foreach (var x in d.Documentos.OrderBy(x => x.EncFechaDocto))
				Fila(t, x.Documento, F(x.EncFechaDocto), M(x.EncMontoTotal), M(x.Pagado), M(x.NotasDebito - x.NotasCredito), M(x.Saldo));
			Total(t, "Saldo total", M(d.Documentos.Sum(x => x.Saldo)));
		}

		Titulo(sec, $"Movimientos {(d.Desde is null ? "" : $"del {F(d.Desde.Value)} ")}al {F(d.Hasta)}");
		if (d.Movimientos.Count == 0) Texto(sec, "No hay movimientos en el período.");
		else
		{
			var t = Tabla(sec, ["Fecha", "Movimiento", "Documento", "Referencia", "Cargo", "Abono", "Saldo"], [1.9, 2.3, 3.0, 4.6, 2.25, 2.25, 2.29],
				[false, false, false, false, true, true, true]);
			var inicial = d.Movimientos[0].SaldoInicial;
			if (d.Desde is not null) Fila(t, F(d.Desde.Value), "Saldo inicial", "", "", "", "", M(inicial)).Format.Font.Italic = true;
			foreach (var m in d.Movimientos)
				Fila(t, F(m.Fecha), m.Tipo, m.Documento ?? "", m.Referencia ?? "", m.Cargo == 0 ? "" : M(m.Cargo), m.Abono == 0 ? "" : M(m.Abono), M(m.Saldo));
		}

		var nota = sec.AddParagraph("Si ya realizó su pago, por favor ignore los montos correspondientes. Para cualquier consulta sobre este estado de cuenta "
			+ $"comuníquese con {d.Compania.NombreComercial}{(string.IsNullOrWhiteSpace(d.Compania.Telefono) ? "" : $" al {d.Compania.Telefono}")}"
			+ $"{(string.IsNullOrWhiteSpace(d.Compania.Correo) ? "" : $" o a {d.Compania.Correo}")}.");
		nota.Format.SpaceBefore = Unit.FromCentimeter(0.6);
		nota.Format.Font.Color = Gris;

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
		var titulo = caja.AddParagraph("ESTADO DE CUENTA");
		titulo.Format.Font.Size = 13;
		titulo.Format.Font.Bold = true;
		titulo.Format.Font.Color = Colors.White;
		titulo.Format.SpaceBefore = Unit.FromPoint(6);
		var corte = caja.AddParagraph($"Al {d.Hasta.ToString("dd 'de' MMMM 'de' yyyy", Es)}");
		corte.Format.Font.Color = Colors.White;
		corte.Format.SpaceAfter = Unit.FromPoint(6);

		var linea2 = sec.AddParagraph();
		linea2.Format.Borders.Bottom.Width = 1.5;
		linea2.Format.Borders.Bottom.Color = Azul;
		linea2.Format.SpaceAfter = Unit.FromCentimeter(0.3);
	}

	private static void Cliente(Section sec, Datos d, Unit ancho)
	{
		var c = d.Cliente;
		var t = sec.AddTable();
		t.Borders.Color = new Color(210, 216, 228);
		t.Borders.Width = 0.5;
		t.LeftPadding = t.RightPadding = Unit.FromPoint(5);
		t.TopPadding = t.BottomPadding = Unit.FromPoint(2.5);
		var mitad = ancho / 2;
		t.AddColumn(Unit.FromCentimeter(2.2)); t.AddColumn(mitad - Unit.FromCentimeter(2.2));
		t.AddColumn(Unit.FromCentimeter(2.2)); t.AddColumn(mitad - Unit.FromCentimeter(2.2));
		void Par(Row r, int i, string etiqueta, string? valor, bool negrita = false)
		{
			r.Cells[i].AddParagraph(etiqueta).Format.Font.Color = Gris;
			var p = r.Cells[i + 1].AddParagraph(string.IsNullOrWhiteSpace(valor) ? "—" : valor);
			p.Format.Font.Bold = negrita;
		}
		var f1 = t.AddRow(); Par(f1, 0, "Cliente", c.Nombre, true); Par(f1, 2, "Código", c.Codigo);
		var f2 = t.AddRow(); Par(f2, 0, "NIT", c.Nit); Par(f2, 2, "Teléfono", c.Telefono);
		var f3 = t.AddRow(); Par(f3, 0, "Dirección", c.Direccion); Par(f3, 2, "Correo", c.Correo);
		sec.AddParagraph().Format.SpaceAfter = Unit.FromCentimeter(0.2);
	}

	private static void Resumen(Section sec, Datos d, Unit ancho)
	{
		var c = d.Cliente;
		var bloques = new List<(string Etiqueta, string Valor, bool Alerta)>
		{
			("Límite de crédito", c.Limite > 0 ? M(c.Limite) : "Sin límite", false),
			("Saldo actual", M(c.Saldo), false),
			("Vencido", M(c.Vencido), c.Vencido > 0),
			("Crédito disponible", c.Disponible is decimal disp ? M(disp) : "—", c.Disponible is <= 0 && c.Limite > 0)
		};
		var t = sec.AddTable();
		t.Borders.Visible = false;
		foreach (var _ in bloques) t.AddColumn(ancho / bloques.Count);
		var r1 = t.AddRow();
		var r2 = t.AddRow();
		for (var i = 0; i < bloques.Count; i++)
		{
			foreach (var r in new[] { r1, r2 }) { r.Cells[i].Shading.Color = AzulClaro; r.Cells[i].Format.Alignment = ParagraphAlignment.Center; }
			var e = r1.Cells[i].AddParagraph(bloques[i].Etiqueta);
			e.Format.Font.Color = Gris;
			e.Format.SpaceBefore = Unit.FromPoint(4);
			var v = r2.Cells[i].AddParagraph(bloques[i].Valor);
			v.Format.Font.Size = 12;
			v.Format.Font.Bold = true;
			v.Format.Font.Color = bloques[i].Alerta ? Rojo : Azul;
			v.Format.SpaceAfter = Unit.FromPoint(4);
		}
		// Antigüedad del saldo.
		var rangos = new (string, decimal)[]
		{
			("No vencido", d.Cuotas.Sum(x => x.NoVencido)), ("1 a 30 días", d.Cuotas.Sum(x => x.De1a30)), ("31 a 60 días", d.Cuotas.Sum(x => x.De31a60)),
			("61 a 90 días", d.Cuotas.Sum(x => x.De61a90)), ("Más de 90 días", d.Cuotas.Sum(x => x.Mas90))
		};
		Titulo(sec, "Antigüedad del saldo");
		var a = Tabla(sec, rangos.Select(r => r.Item1).ToArray(), rangos.Select(_ => 18.59 / rangos.Length).ToArray(), rangos.Select(_ => true).ToArray());
		Fila(a, rangos.Select(r => M(r.Item2)).ToArray());
		var ultima = sec.AddParagraph(string.Join("   ·   ", new[]
		{
			c.UltimaCompra is DateTime u ? $"Última compra: {F(u)}" : null,
			c.UltimoPago is DateTime p ? $"Último pago: {F(p)}" : null
		}.Where(x => x is not null)));
		ultima.Format.Font.Color = Gris;
		ultima.Format.SpaceBefore = Unit.FromPoint(3);
	}

	private static void Pie(Section sec, Datos d)
	{
		var p = sec.Footers.Primary.AddParagraph();
		p.Format.Font.Size = 7;
		p.Format.Font.Color = Gris;
		p.AddText($"{d.Compania.NombreComercial} · Estado de cuenta de {d.Cliente.Codigo} · generado el {d.Generado:dd/MM/yyyy HH:mm} · página ");
		p.AddPageField();
		p.AddText(" de ");
		p.AddNumPagesField();
	}

	private static void Titulo(Section sec, string texto)
	{
		var p = sec.AddParagraph(texto);
		p.Format.Font.Size = 10;
		p.Format.Font.Bold = true;
		p.Format.Font.Color = Azul;
		p.Format.SpaceBefore = Unit.FromCentimeter(0.45);
		p.Format.SpaceAfter = Unit.FromPoint(3);
		p.Format.KeepWithNext = true;
	}

	private static void Texto(Section sec, string texto) => sec.AddParagraph(texto).Format.Font.Color = Gris;

	private static Table Tabla(Section sec, string[] titulos, double[] anchosCm, bool[] numericas)
	{
		var t = sec.AddTable();
		t.Borders.Visible = false;
		t.LeftPadding = t.RightPadding = Unit.FromPoint(4);
		t.TopPadding = t.BottomPadding = Unit.FromPoint(2);
		for (var i = 0; i < titulos.Length; i++)
		{
			var col = t.AddColumn(Unit.FromCentimeter(anchosCm[i]));
			col.Format.Alignment = numericas[i] ? ParagraphAlignment.Right : ParagraphAlignment.Left;
		}
		var enc = t.AddRow();
		enc.HeadingFormat = true;
		enc.Shading.Color = AzulClaro;
		enc.Format.Font.Bold = true;
		enc.Format.Font.Size = 7.5;
		enc.Format.Font.Color = Azul;
		enc.Borders.Bottom.Width = 0.75;
		enc.Borders.Bottom.Color = Azul;
		for (var i = 0; i < titulos.Length; i++) enc.Cells[i].AddParagraph(titulos[i].ToUpper(Es));
		return t;
	}

	private static Row Fila(Table t, params string[] valores)
	{
		var r = t.AddRow();
		r.Borders.Bottom.Width = 0.25;
		r.Borders.Bottom.Color = new Color(220, 224, 232);
		for (var i = 0; i < valores.Length; i++) r.Cells[i].AddParagraph(valores[i]);
		return r;
	}

	private static void Total(Table t, string etiqueta, string valor)
	{
		var r = t.AddRow();
		r.Format.Font.Bold = true;
		r.Cells[0].MergeRight = t.Columns.Count - 2;
		r.Cells[0].AddParagraph(etiqueta);
		r.Cells[t.Columns.Count - 1].AddParagraph(valor);
		r.Borders.Top.Width = 0.75;
		r.Borders.Top.Color = Azul;
	}

	// PNG, JPEG, GIF o BMP: MigraDoc no dibuja SVG ni WebP.
	private static bool EsImagen(byte[] b) =>
		b.Length > 4 && ((b[0] == 0x89 && b[1] == 0x50) || (b[0] == 0xFF && b[1] == 0xD8) || (b[0] == 0x47 && b[1] == 0x49) || (b[0] == 0x42 && b[1] == 0x4D));

	private static string F(DateTime f) => f.ToString("dd/MM/yyyy", Es);
	private static string M(decimal m) => "Q" + m.ToString("N2", CultureInfo.InvariantCulture);
}
