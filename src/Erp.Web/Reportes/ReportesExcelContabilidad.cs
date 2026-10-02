using ClosedXML.Excel;
using Erp.Data.Contabilidad;

namespace Erp.Web.Reportes;

// Libros de Excel de contabilidad: libro diario, mayor, balanza y estados financieros.
public static partial class ReportesExcel
{
	public static byte[] LibroDiario(IReadOnlyList<LibroDiarioLinea> lineas, ReporteContable reporte, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add("Libro diario");
		var fila = Encabezado(hoja, compania, reporte.Titulo, reporte.Rango);
		fila = Titulos(hoja, fila, new List<string> { "Fecha", "Póliza", "Origen", "Concepto", "Cuenta", "Nombre", "Descripción", "Debe", "Haber" });
		var inicioDatos = fila;
		foreach (var l in lineas)
		{
			hoja.Cell(fila, 1).Value = l.Fecha;
			hoja.Cell(fila, 1).Style.DateFormat.Format = "dd/MM/yyyy";
			hoja.Cell(fila, 2).Value = l.AsiId;
			hoja.Cell(fila, 3).Value = OrigenesPoliza.Nombre(l.Origen);
			hoja.Cell(fila, 4).Value = l.Descripcion;
			hoja.Cell(fila, 5).Value = l.Codigo;
			hoja.Cell(fila, 6).Value = l.Cuenta;
			hoja.Cell(fila, 7).Value = l.DescripcionLinea;
			hoja.Cell(fila, 8).Value = l.Debe;
			hoja.Cell(fila, 9).Value = l.Haber;
			fila++;
		}
		Totales(hoja, fila, inicioDatos, 8, 9, 6);
		Formato(hoja, inicioDatos, fila, 8, 9);
		if (fila > inicioDatos) hoja.Range(inicioDatos - 1, 1, fila - 1, 9).SetAutoFilter();
		return Guardar(libro);
	}

	public static byte[] LibroMayor(IReadOnlyList<MayorCuenta> cuentas, ReporteContable reporte, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add("Libro mayor");
		var fila = Encabezado(hoja, compania, reporte.Titulo, reporte.Rango);
		fila = Titulos(hoja, fila, new List<string> { "Cuenta", "Nombre", "Fecha", "Póliza", "Concepto", "Debe", "Haber", "Saldo" });
		var inicioDatos = fila;
		foreach (var c in cuentas)
		{
			hoja.Cell(fila, 1).Value = c.Codigo;
			hoja.Cell(fila, 2).Value = c.Cuenta;
			hoja.Cell(fila, 5).Value = "Saldo inicial";
			hoja.Cell(fila, 8).Value = c.SaldoInicial;
			hoja.Range(fila, 1, fila, 8).Style.Font.Bold = true;
			fila++;
			foreach (var m in c.Movimientos)
			{
				hoja.Cell(fila, 1).Value = c.Codigo;
				hoja.Cell(fila, 3).Value = m.Fecha;
				hoja.Cell(fila, 3).Style.DateFormat.Format = "dd/MM/yyyy";
				hoja.Cell(fila, 4).Value = m.AsiId;
				hoja.Cell(fila, 5).Value = m.Descripcion;
				hoja.Cell(fila, 6).Value = m.Debe;
				hoja.Cell(fila, 7).Value = m.Haber;
				hoja.Cell(fila, 8).Value = m.Saldo;
				fila++;
			}
			hoja.Cell(fila, 1).Value = c.Codigo;
			hoja.Cell(fila, 5).Value = "Saldo final";
			hoja.Cell(fila, 6).Value = c.Debe;
			hoja.Cell(fila, 7).Value = c.Haber;
			hoja.Cell(fila, 8).Value = c.SaldoFinal;
			var total = hoja.Range(fila, 1, fila, 8);
			total.Style.Font.Bold = true;
			total.Style.Border.TopBorder = XLBorderStyleValues.Thin;
			fila += 2;
		}
		Formato(hoja, inicioDatos, fila, 6, 8);
		return Guardar(libro);
	}

	public static byte[] Balanza(IReadOnlyList<BalanzaFila> filas, ReporteContable reporte, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add("Balanza");
		var fila = Encabezado(hoja, compania, reporte.Titulo, reporte.Rango);
		fila = Titulos(hoja, fila, new List<string> { "Cuenta", "Nombre", "Nivel", "Inicial deudor", "Inicial acreedor", "Debe", "Haber", "Final deudor", "Final acreedor" });
		var inicioDatos = fila;
		var maximo = filas.Count == 0 ? 0 : filas.Max(f => f.Nivel);
		var minimo = filas.Count == 0 ? 0 : filas.Min(f => f.Nivel);
		foreach (var f in filas)
		{
			hoja.Cell(fila, 1).Value = f.Codigo;
			hoja.Cell(fila, 2).Value = new string(' ', (f.Nivel - 1) * 2) + f.Cuenta;
			hoja.Cell(fila, 3).Value = f.Nivel;
			hoja.Cell(fila, 4).Value = f.InicialDeudor;
			hoja.Cell(fila, 5).Value = f.InicialAcreedor;
			hoja.Cell(fila, 6).Value = f.Debe;
			hoja.Cell(fila, 7).Value = f.Haber;
			hoja.Cell(fila, 8).Value = f.FinalDeudor;
			hoja.Cell(fila, 9).Value = f.FinalAcreedor;
			if (f.Nivel < maximo) hoja.Range(fila, 1, fila, 9).Style.Font.Bold = true;
			fila++;
		}
		// Sumas iguales: solo las cuentas del primer nivel mostrado (las demás ya están dentro).
		hoja.Cell(fila, 2).Value = "Sumas iguales";
		for (var c = 4; c <= 9; c++)
		{
			var letra = XLHelper.GetColumnLetterFromNumber(c);
			hoja.Cell(fila, c).FormulaA1 = fila > inicioDatos ? $"SUMIF(C{inicioDatos}:C{fila - 1},{minimo},{letra}{inicioDatos}:{letra}{fila - 1})" : "0";
		}
		var total = hoja.Range(fila, 1, fila, 9);
		total.Style.Font.Bold = true;
		total.Style.Border.TopBorder = XLBorderStyleValues.Thin;
		Formato(hoja, inicioDatos, fila, 4, 9);
		return Guardar(libro);
	}

	public static byte[] BalanceGeneral(BalanceGeneral balance, ReporteContable reporte, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add("Balance General");
		var fila = Encabezado(hoja, compania, reporte.Titulo, reporte.Rango);
		var columnas = new List<string> { "Cuenta", "Nombre", reporte.EtiquetaActual };
		if (reporte.Comparar) columnas.AddRange(new[] { reporte.EtiquetaComparativa, "Variación" });
		fila = Titulos(hoja, fila, columnas);
		var inicioDatos = fila;
		var t = balance.Totales;
		var maximo = balance.Filas.Count == 0 ? 0 : balance.Filas.Max(f => f.Nivel);

		void Fila(string codigo, string nombre, decimal actual, decimal comparativo, bool negrita)
		{
			hoja.Cell(fila, 1).Value = codigo;
			hoja.Cell(fila, 2).Value = nombre;
			hoja.Cell(fila, 3).Value = actual;
			if (reporte.Comparar)
			{
				hoja.Cell(fila, 4).Value = comparativo;
				hoja.Cell(fila, 5).Value = actual - comparativo;
			}
			if (negrita) hoja.Range(fila, 1, fila, columnas.Count).Style.Font.Bold = true;
			fila++;
		}

		foreach (var (tipo, titulo) in new[] { ("A", "ACTIVO"), ("P", "PASIVO"), ("K", "CAPITAL") })
		{
			var filas = balance.Filas.Where(f => f.Tipo == tipo).ToList();
			if (filas.Count == 0) Fila("", titulo, 0, 0, true);
			foreach (var f in filas) Fila(f.Codigo, new string(' ', (f.Nivel - 1) * 2) + f.Cuenta, f.Saldo, f.SaldoComparativo, f.Nivel < maximo);
			switch (tipo)
			{
				case "A":
					Fila("", "TOTAL ACTIVO", t.Activo, t.ActivoComparativo, true);
					fila++;
					break;
				case "P":
					Fila("", "Total pasivo", t.Pasivo, t.PasivoComparativo, true);
					break;
				default:
					if (t.ResultadosAnteriores != 0 || t.ResultadosAnterioresComparativo != 0)
						Fila("", "  Resultados de ejercicios anteriores (sin partida de cierre)", t.ResultadosAnteriores, t.ResultadosAnterioresComparativo, false);
					Fila("", $"  {(t.ResultadoEjercicio >= 0 ? "Utilidad" : "Pérdida")} del ejercicio", t.ResultadoEjercicio, t.ResultadoEjercicioComparativo, false);
					Fila("", "Total capital", t.Capital + t.ResultadoEjercicio + t.ResultadosAnteriores,
						t.CapitalComparativo + t.ResultadoEjercicioComparativo + t.ResultadosAnterioresComparativo, true);
					Fila("", "TOTAL PASIVO Y CAPITAL", t.PasivoCapital, t.PasivoCapitalComparativo, true);
					break;
			}
		}
		Formato(hoja, inicioDatos, fila, 3, columnas.Count);
		return Guardar(libro);
	}

	public static byte[] EstadoResultados(EstadoResultados estado, ReporteContable reporte, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add("Estado de Resultados");
		var fila = Encabezado(hoja, compania, reporte.Titulo, reporte.Rango);
		var columnas = new List<string> { "Cuenta", "Nombre", reporte.EtiquetaActual };
		if (reporte.Comparar) columnas.AddRange(new[] { reporte.EtiquetaComparativa, "Variación" });
		fila = Titulos(hoja, fila, columnas);
		var inicioDatos = fila;
		var t = estado.Totales;
		var c = estado.Comparativo ?? new ResultadosTotales();
		var maximo = estado.Filas.Count == 0 ? 0 : estado.Filas.Max(f => f.Nivel);

		void Fila(string codigo, string nombre, decimal actual, decimal comparativo, bool negrita)
		{
			hoja.Cell(fila, 1).Value = codigo;
			hoja.Cell(fila, 2).Value = nombre;
			hoja.Cell(fila, 3).Value = actual;
			if (reporte.Comparar)
			{
				hoja.Cell(fila, 4).Value = comparativo;
				hoja.Cell(fila, 5).Value = actual - comparativo;
			}
			if (negrita) hoja.Range(fila, 1, fila, columnas.Count).Style.Font.Bold = true;
			fila++;
		}

		foreach (var f in estado.Filas.Where(f => f.Tipo == "I"))
			Fila(f.Codigo, new string(' ', (f.Nivel - 1) * 2) + (f.Naturaleza == "D" ? "(−) " : "") + f.Cuenta, f.Saldo, f.SaldoComparativo, f.Nivel < maximo);
		Fila("", "Ventas e ingresos", t.Ingresos, c.Ingresos, false);
		Fila("", "(−) Costo de ventas", t.Costos, c.Costos, false);
		Fila("", "UTILIDAD BRUTA", t.UtilidadBruta, c.UtilidadBruta, true);
		fila++;
		foreach (var f in estado.Filas.Where(f => f.Tipo == "G"))
			Fila(f.Codigo, new string(' ', (f.Nivel - 1) * 2) + f.Cuenta, f.Saldo, f.SaldoComparativo, f.Nivel < maximo);
		Fila("", "(−) Total gastos de operación", t.Gastos, c.Gastos, false);
		Fila("", $"{(t.UtilidadNeta >= 0 ? "UTILIDAD" : "PÉRDIDA")} NETA DEL PERÍODO", t.UtilidadNeta, c.UtilidadNeta, true);
		Formato(hoja, inicioDatos, fila, 3, columnas.Count);
		return Guardar(libro);
	}
}
