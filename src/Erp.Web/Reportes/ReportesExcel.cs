using ClosedXML.Excel;
using Erp.Data.Cuentas;
using Erp.Web.Components.Pages.Cuentas;

namespace Erp.Web.Reportes;

// Compañía que encabeza los libros de Excel: nombre y logotipo.
public sealed record CompaniaReporte(string Nombre, byte[]? Logo = null);

// Libros de Excel de cuentas por cobrar y por pagar.
public static partial class ReportesExcel
{
	private const string FormatoMonto = "#,##0.00;[Red]-#,##0.00";

	public static byte[] Antiguedad(IReadOnlyList<AntiguedadFila> filas, bool esCliente, DateTime fechaCorte, CompaniaReporte compania)
	{
		var tercero = esCliente ? "Cliente" : "Proveedor";
		var documento = esCliente ? "Factura" : "Compra";
		var grupos = AntiguedadGrupo.Agrupar(filas);
		using var libro = new XLWorkbook();

		// Hoja 1: resumen por tercero.
		var hoja = libro.Worksheets.Add($"Por {tercero.ToLowerInvariant()}");
		var fila = Encabezado(hoja, compania, $"Antigüedad de saldos de {(esCliente ? "clientes" : "proveedores")}", $"Fecha de corte: {fechaCorte:dd/MM/yyyy}");
		var columnas = new List<string> { "Código", tercero, "Documentos" };
		columnas.AddRange(RangosAntiguedad.Etiquetas);
		columnas.Add("Total");
		fila = Titulos(hoja, fila, columnas);
		var inicioDatos = fila;
		foreach (var g in grupos)
		{
			hoja.Cell(fila, 1).Value = g.Codigo;
			hoja.Cell(fila, 2).Value = g.Nombre;
			hoja.Cell(fila, 3).Value = g.Documentos.Count;
			for (var i = 0; i < 5; i++) hoja.Cell(fila, 4 + i).Value = g.Rangos[i];
			hoja.Cell(fila, 9).FormulaA1 = $"SUM(D{fila}:H{fila})";
			fila++;
		}
		Totales(hoja, fila, inicioDatos, 4, 9, 3);
		Formato(hoja, inicioDatos, fila, 4, 9);

		// Hoja 2: por documento.
		var hojaDocs = libro.Worksheets.Add($"Por {documento.ToLowerInvariant()}");
		fila = Encabezado(hojaDocs, compania, $"Antigüedad de saldos por {documento.ToLowerInvariant()}", $"Fecha de corte: {fechaCorte:dd/MM/yyyy}");
		columnas = new List<string> { "Código", tercero, documento, "Fecha", "Vence", "Días" };
		columnas.AddRange(RangosAntiguedad.Etiquetas);
		columnas.Add("Total");
		fila = Titulos(hojaDocs, fila, columnas);
		inicioDatos = fila;
		foreach (var g in grupos)
			foreach (var d in g.Documentos)
			{
				hojaDocs.Cell(fila, 1).Value = g.Codigo;
				hojaDocs.Cell(fila, 2).Value = g.Nombre;
				hojaDocs.Cell(fila, 3).Value = d.Documento;
				hojaDocs.Cell(fila, 4).Value = d.FechaDocumento;
				hojaDocs.Cell(fila, 5).Value = d.VencimientoMasAntiguo;
				hojaDocs.Cell(fila, 6).Value = Math.Max(d.DiasMaximos, 0);
				for (var i = 0; i < 5; i++) hojaDocs.Cell(fila, 7 + i).Value = d.Rangos[i];
				hojaDocs.Cell(fila, 12).FormulaA1 = $"SUM(G{fila}:K{fila})";
				fila++;
			}
		Totales(hojaDocs, fila, inicioDatos, 7, 12, 6);
		Formato(hojaDocs, inicioDatos, fila, 7, 12);
		hojaDocs.Range(inicioDatos, 4, fila, 5).Style.DateFormat.Format = "dd/MM/yyyy";

		// Hoja 3: cada cuota (para filtrar o armar tablas dinámicas).
		var hojaCuotas = libro.Worksheets.Add("Cuotas");
		fila = Titulos(hojaCuotas, 1, new List<string> { "Código", tercero, documento, "Fecha", "Cuota", "Vencimiento", "Días", "Rango", "Saldo" });
		inicioDatos = fila;
		foreach (var f in filas)
		{
			hojaCuotas.Cell(fila, 1).Value = f.Codigo;
			hojaCuotas.Cell(fila, 2).Value = f.Nombre;
			hojaCuotas.Cell(fila, 3).Value = f.Documento;
			hojaCuotas.Cell(fila, 4).Value = f.FechaDocumento;
			hojaCuotas.Cell(fila, 5).Value = f.Cuota;
			hojaCuotas.Cell(fila, 6).Value = f.Vencimiento;
			hojaCuotas.Cell(fila, 7).Value = f.Dias;
			hojaCuotas.Cell(fila, 8).Value = RangosAntiguedad.Etiquetas[Array.FindIndex(RangosAntiguedad.De(f), m => m != 0) is var i and >= 0 ? i : 0];
			hojaCuotas.Cell(fila, 9).Value = f.Saldo;
			fila++;
		}
		hojaCuotas.Range(inicioDatos, 4, fila, 4).Style.DateFormat.Format = "dd/MM/yyyy";
		hojaCuotas.Range(inicioDatos, 6, fila, 6).Style.DateFormat.Format = "dd/MM/yyyy";
		hojaCuotas.Range(inicioDatos, 9, fila, 9).Style.NumberFormat.Format = FormatoMonto;
		if (fila > inicioDatos) hojaCuotas.Range(inicioDatos - 1, 1, fila - 1, 9).SetAutoFilter();
		hojaCuotas.Columns().AdjustToContents();

		return Guardar(libro);
	}

	public static byte[] EstadoCuenta(IReadOnlyList<MovimientoEstadoCuenta> movimientos, IReadOnlyList<DocumentoSaldo> documentos, bool esCliente,
		string tercero, DateTime? desde, DateTime? hasta, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add("Estado de cuenta");
		var rango = $"{(desde is null ? "Desde el inicio" : $"Del {desde:dd/MM/yyyy}")} al {(hasta ?? DateTime.Today):dd/MM/yyyy}";
		var fila = Encabezado(hoja, compania, $"Estado de cuenta · {tercero}", rango);
		var saldoInicial = movimientos.FirstOrDefault()?.SaldoInicial ?? 0;
		hoja.Cell(fila, 1).Value = "Saldo inicial";
		hoja.Cell(fila, 7).Value = saldoInicial;
		hoja.Cell(fila, 7).Style.NumberFormat.Format = FormatoMonto;
		fila += 2;
		fila = Titulos(hoja, fila, new List<string> { "Fecha", "Tipo", "Documento", "Referencia", "Cargo", "Abono", "Saldo" });
		var inicioDatos = fila;
		foreach (var m in movimientos)
		{
			hoja.Cell(fila, 1).Value = m.Fecha;
			hoja.Cell(fila, 2).Value = m.Tipo;
			hoja.Cell(fila, 3).Value = m.Documento;
			hoja.Cell(fila, 4).Value = m.Referencia;
			hoja.Cell(fila, 5).Value = m.Cargo;
			hoja.Cell(fila, 6).Value = m.Abono;
			hoja.Cell(fila, 7).Value = m.Saldo;
			fila++;
		}
		hoja.Range(inicioDatos, 1, fila, 1).Style.DateFormat.Format = "dd/MM/yyyy";
		hoja.Range(inicioDatos, 5, fila, 7).Style.NumberFormat.Format = FormatoMonto;
		hoja.Cell(fila, 4).Value = "Totales";
		hoja.Cell(fila, 5).FormulaA1 = $"SUM(E{inicioDatos}:E{fila - 1})";
		hoja.Cell(fila, 6).FormulaA1 = $"SUM(F{inicioDatos}:F{fila - 1})";
		hoja.Range(fila, 1, fila, 7).Style.Font.Bold = true;
		hoja.Columns().AdjustToContents();

		var hojaDocs = libro.Worksheets.Add("Documentos con saldo");
		fila = Titulos(hojaDocs, 1, new List<string> { esCliente ? "Factura" : "Compra", "Fecha", "Total", "Pagado", "Notas de crédito", "Notas de débito", "Saldo", "Próximo vencimiento" });
		inicioDatos = fila;
		foreach (var d in documentos)
		{
			hojaDocs.Cell(fila, 1).Value = d.Documento;
			hojaDocs.Cell(fila, 2).Value = d.EncFechaDocto;
			hojaDocs.Cell(fila, 3).Value = d.EncMontoTotal;
			hojaDocs.Cell(fila, 4).Value = d.Pagado;
			hojaDocs.Cell(fila, 5).Value = d.NotasCredito;
			hojaDocs.Cell(fila, 6).Value = d.NotasDebito;
			hojaDocs.Cell(fila, 7).Value = d.Saldo;
			if (d.ProximoVencimiento is not null) hojaDocs.Cell(fila, 8).Value = d.ProximoVencimiento.Value;
			fila++;
		}
		hojaDocs.Range(inicioDatos, 2, fila, 2).Style.DateFormat.Format = "dd/MM/yyyy";
		hojaDocs.Range(inicioDatos, 8, fila, 8).Style.DateFormat.Format = "dd/MM/yyyy";
		hojaDocs.Range(inicioDatos, 3, fila, 7).Style.NumberFormat.Format = FormatoMonto;
		hojaDocs.Columns().AdjustToContents();

		return Guardar(libro);
	}

	// Logotipo (si la compañía lo tiene) en las filas 1 a 4 y debajo el nombre
	// de la compañía, el título, el subtítulo y la fecha. Devuelve la primera
	// fila libre.
	private static int Encabezado(IXLWorksheet hoja, CompaniaReporte compania, string titulo, string subtitulo)
	{
		var fila = 1;
		if (compania.Logo is { Length: > 0 } logo)
		{
			try
			{
				using var imagen = new MemoryStream(logo);
				var foto = hoja.AddPicture(imagen, "Logotipo").MoveTo(hoja.Cell(1, 1), 4, 4);
				foto.Scale(Math.Min(56.0 / foto.OriginalHeight, 220.0 / foto.OriginalWidth));
				fila = 5;
			}
			catch (Exception)
			{
				// Un formato que Excel no admite (p. ej. WEBP) deja el libro sin logotipo.
			}
		}
		hoja.Cell(fila, 1).Value = compania.Nombre;
		hoja.Cell(fila, 1).Style.Font.Bold = true;
		hoja.Cell(fila + 1, 1).Value = titulo;
		hoja.Cell(fila + 1, 1).Style.Font.Bold = true;
		hoja.Cell(fila + 1, 1).Style.Font.FontSize = 14;
		hoja.Cell(fila + 2, 1).Value = subtitulo;
		hoja.Cell(fila + 3, 1).Value = $"Generado el {DateTime.Now:dd/MM/yyyy HH:mm}";
		hoja.Cell(fila + 3, 1).Style.Font.FontColor = XLColor.Gray;
		return fila + 5;
	}

	// Listado de transferencias de un lote de nómina: resumen por banco y una
	// hoja por banco destino, lista para enviar o cargar en cada banco.
	public static byte[] TransferenciasNomina(IReadOnlyList<Erp.Data.Rrhh.TransferenciaNomina> filas, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var primera = filas.FirstOrDefault();
		var subtitulo = primera is null ? "Sin transferencias"
			: $"{primera.Nomina} · pagado el {primera.FechaPago:dd/MM/yyyy} desde {primera.CuentaOrigen}{(string.IsNullOrWhiteSpace(primera.Referencia) ? "" : $" · referencia {primera.Referencia}")}";
		var bancos = filas.GroupBy(f => f.Banco ?? "(sin banco)").OrderBy(g => g.Key).ToList();

		var hoja = libro.Worksheets.Add("Resumen");
		var fila = Encabezado(hoja, compania, "Transferencias de nómina por banco", subtitulo);
		fila = Titulos(hoja, fila, new List<string> { "Banco", "Empleados", "Monto" });
		var inicioDatos = fila;
		foreach (var g in bancos)
		{
			hoja.Cell(fila, 1).Value = g.Key;
			hoja.Cell(fila, 2).Value = g.Count();
			hoja.Cell(fila, 3).Value = g.Sum(f => f.Monto);
			fila++;
		}
		Totales(hoja, fila, inicioDatos, 2, 3, 1);
		Formato(hoja, inicioDatos, fila, 3, 3);

		foreach (var g in bancos)
		{
			var nombreHoja = new string(g.Key.Where(c => !"[]*?/\\:".Contains(c)).ToArray());
			var hojaBanco = libro.Worksheets.Add(nombreHoja.Length > 31 ? nombreHoja[..31] : nombreHoja);
			fila = Encabezado(hojaBanco, compania, $"Transferencias a {g.Key}", subtitulo);
			fila = Titulos(hojaBanco, fila, new List<string> { "Tipo de cuenta", "Número de cuenta", "Código", "Empleado", "Documento", "Monto" });
			inicioDatos = fila;
			foreach (var f in g)
			{
				hojaBanco.Cell(fila, 1).Value = f.TipoCuenta;
				hojaBanco.Cell(fila, 2).Value = f.NumeroCuenta;
				hojaBanco.Cell(fila, 3).Value = f.CodigoEmpleado;
				hojaBanco.Cell(fila, 4).Value = f.Empleado;
				hojaBanco.Cell(fila, 5).Value = f.NumeroDocumento;
				hojaBanco.Cell(fila, 6).Value = f.Monto;
				fila++;
			}
			// Números de cuenta y documento como texto (no perder ceros ni guiones).
			hojaBanco.Range(inicioDatos, 2, fila, 2).Style.NumberFormat.Format = "@";
			hojaBanco.Range(inicioDatos, 5, fila, 5).Style.NumberFormat.Format = "@";
			Totales(hojaBanco, fila, inicioDatos, 6, 6, 4);
			Formato(hojaBanco, inicioDatos, fila, 6, 6);
		}
		return Guardar(libro);
	}

	// Gasto por centro de costo (departamento) y cuenta.
	public static byte[] CentrosCosto(IReadOnlyList<Erp.Data.Contabilidad.CentroCostoFila> filas, DateTime desde, DateTime hasta, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add("Centros de costo");
		var fila = Encabezado(hoja, compania, "Gasto por centro de costo", $"Del {desde:dd/MM/yyyy} al {hasta:dd/MM/yyyy}");
		fila = Titulos(hoja, fila, new List<string> { "Centro de costo", "Cuenta", "Nombre", "Pólizas", "Debe", "Haber", "Saldo" });
		var inicioDatos = fila;
		foreach (var f in filas)
		{
			hoja.Cell(fila, 1).Value = f.Departamento;
			hoja.Cell(fila, 2).Value = f.CuentaCodigo;
			hoja.Cell(fila, 3).Value = f.CuentaNombre;
			hoja.Cell(fila, 4).Value = f.Partidas;
			hoja.Cell(fila, 5).Value = f.Debe;
			hoja.Cell(fila, 6).Value = f.Haber;
			hoja.Cell(fila, 7).Value = f.Saldo;
			fila++;
		}
		Totales(hoja, fila, inicioDatos, 5, 7, 3);
		Formato(hoja, inicioDatos, fila, 5, 7);
		if (fila > inicioDatos) hoja.Range(inicioDatos - 1, 1, fila - 1, 7).SetAutoFilter();
		return Guardar(libro);
	}

	private static int Titulos(IXLWorksheet hoja, int fila, IList<string> columnas)
	{
		for (var i = 0; i < columnas.Count; i++) hoja.Cell(fila, i + 1).Value = columnas[i];
		var rango = hoja.Range(fila, 1, fila, columnas.Count);
		rango.Style.Font.Bold = true;
		rango.Style.Font.FontColor = XLColor.White;
		rango.Style.Fill.BackgroundColor = XLColor.FromHtml("#142d6e");
		hoja.SheetView.FreezeRows(fila);
		return fila + 1;
	}

	private static void Totales(IXLWorksheet hoja, int fila, int inicioDatos, int primeraColumna, int ultimaColumna, int columnaEtiqueta)
	{
		hoja.Cell(fila, columnaEtiqueta).Value = "Total general";
		for (var c = primeraColumna; c <= ultimaColumna; c++)
		{
			var letra = XLHelper.GetColumnLetterFromNumber(c);
			hoja.Cell(fila, c).FormulaA1 = fila > inicioDatos ? $"SUM({letra}{inicioDatos}:{letra}{fila - 1})" : "0";
		}
		var total = hoja.Range(fila, 1, fila, ultimaColumna);
		total.Style.Font.Bold = true;
		total.Style.Border.TopBorder = XLBorderStyleValues.Thin;
	}

	private static void Formato(IXLWorksheet hoja, int inicioDatos, int filaTotales, int primeraColumna, int ultimaColumna)
	{
		hoja.Range(inicioDatos, primeraColumna, filaTotales, ultimaColumna).Style.NumberFormat.Format = FormatoMonto;
		hoja.Columns().AdjustToContents();
	}

	private static byte[] Guardar(XLWorkbook libro)
	{
		using var memoria = new MemoryStream();
		libro.SaveAs(memoria);
		return memoria.ToArray();
	}
}
