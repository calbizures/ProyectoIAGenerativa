using ClosedXML.Excel;
using Erp.Data.FlujoCaja;

namespace Erp.Web.Reportes;

public static partial class ReportesExcel
{
	// Flujo de caja en columnas por período, como en la pantalla.
	public static byte[] FlujoCaja(FlujoCajaPivote pivote, string titulo, string subtitulo, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add("Flujo de caja");
		var fila = Encabezado(hoja, compania, titulo, subtitulo);
		var columnas = new List<string> { "Concepto" };
		columnas.AddRange(pivote.Periodos.Select(pivote.Etiqueta));
		columnas.Add("Total");
		fila = Titulos(hoja, fila, columnas);
		var inicioDatos = fila;
		var ultima = columnas.Count;

		void Fila(string concepto, Func<DateTime, decimal> monto, decimal total, bool negrita)
		{
			hoja.Cell(fila, 1).Value = concepto;
			for (var i = 0; i < pivote.Periodos.Count; i++) hoja.Cell(fila, i + 2).Value = monto(pivote.Periodos[i]);
			hoja.Cell(fila, ultima).Value = total;
			if (negrita) hoja.Range(fila, 1, fila, ultima).Style.Font.Bold = true;
			fila++;
		}

		Fila("Saldo inicial de efectivo", pivote.SaldoInicialDe, pivote.SaldoInicial, true);
		foreach (var (actividad, nombre) in ActividadesFlujo.Todas)
		{
			var filas = pivote.Filas.Where(f => f.Actividad == actividad).ToList();
			if (filas.Count == 0) continue;
			hoja.Cell(fila, 1).Value = nombre.ToUpperInvariant();
			hoja.Cell(fila, 1).Style.Font.Bold = true;
			fila++;
			foreach (var f in filas) Fila("   " + f.Concepto, p => f.Montos.GetValueOrDefault(p), f.Total, false);
			Fila($"Flujo neto de {nombre.Replace("Actividades de ", "")}", p => pivote.Neto(p, actividad), filas.Sum(f => f.Total), true);
		}
		Fila("Flujo neto del período", pivote.Neto, pivote.Periodos.Sum(pivote.Neto), true);
		Fila("Saldo final de efectivo", pivote.SaldoFinalDe, pivote.SaldoFinal, true);
		hoja.Range(fila - 1, 1, fila - 1, ultima).Style.Border.TopBorder = XLBorderStyleValues.Thin;
		Formato(hoja, inicioDatos, fila, 2, ultima);
		return Guardar(libro);
	}

	// Plantilla del estado de cuenta para la conciliación bancaria.
	public static byte[] PlantillaEstadoCuenta(CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add("Estado de cuenta");
		var fila = Encabezado(hoja, compania, "Estado de cuenta bancario", "Una fila por movimiento; débito = sale del banco, crédito = entra. La columna Saldo es opcional.");
		fila = Titulos(hoja, fila, ExtractoBancario.ColumnasPlantilla);
		var ejemplos = new (DateTime Fecha, string Descripcion, string Referencia, decimal Debito, decimal Credito, decimal Saldo)[]
		{
			(new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1), "DEPOSITO EN EFECTIVO", "458712", 0, 15980, 165980),
			(new DateTime(DateTime.Today.Year, DateTime.Today.Month, 2), "CHEQUE PAGADO", "1012", 850, 0, 165130),
			(new DateTime(DateTime.Today.Year, DateTime.Today.Month, 3), "COMISION MANEJO DE CUENTA", "", 45, 0, 165085)
		};
		var inicio = fila;
		foreach (var e in ejemplos)
		{
			hoja.Cell(fila, 1).Value = e.Fecha;
			hoja.Cell(fila, 1).Style.DateFormat.Format = "dd/MM/yyyy";
			hoja.Cell(fila, 2).Value = e.Descripcion;
			hoja.Cell(fila, 3).Value = e.Referencia;
			if (e.Debito > 0) hoja.Cell(fila, 4).Value = e.Debito;
			if (e.Credito > 0) hoja.Cell(fila, 5).Value = e.Credito;
			hoja.Cell(fila, 6).Value = e.Saldo;
			fila++;
		}
		hoja.Range(inicio, 4, fila, 6).Style.NumberFormat.Format = "#,##0.00";
		hoja.Columns().AdjustToContents();
		return Guardar(libro);
	}
}
