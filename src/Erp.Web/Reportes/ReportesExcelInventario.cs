using ClosedXML.Excel;
using Erp.Data.Inventario;

namespace Erp.Web.Reportes;

// Libro de Excel de rotación del inventario y punto de reorden.
public static partial class ReportesExcel
{
	public static string ClaseRotacion(string clase) => clase switch
	{
		"A" => "Alta",
		"M" => "Media",
		"B" => "Baja",
		_ => "Sin ventas"
	};

	public static byte[] Rotacion(IReadOnlyList<RotacionInventarioFila> filas, string ambito, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add("Rotación y reorden");
		var primera = filas.FirstOrDefault();
		var periodo = primera is null ? "" : $"Del {primera.Desde:dd/MM/yyyy} al {primera.Hasta:dd/MM/yyyy} ({primera.Dias} días) · {ambito}";
		var fila = Encabezado(hoja, compania, "Rotación del inventario y punto de reorden", periodo);
		fila = Titulos(hoja, fila, new List<string>
		{
			"Código", "Producto", "Bodega", "Clase", "Existencia", "En tránsito", "Inv. inicial", "Inv. final", "Inv. promedio",
			"Vendidas", "Costo vendido", "Venta diaria", "Rotación", "Rotación anual", "Días de inventario", "Días de cobertura",
			"Última venta", "Días entrega", "Días seguridad", "Punto de reorden", "Sugerido", "Proveedor", "Valor inventario"
		});
		var inicioDatos = fila;
		foreach (var f in filas)
		{
			hoja.Cell(fila, 1).Value = f.Codigo;
			hoja.Cell(fila, 2).Value = f.Descripcion;
			hoja.Cell(fila, 3).Value = f.Bodega;
			hoja.Cell(fila, 4).Value = ClaseRotacion(f.Clase);
			hoja.Cell(fila, 5).Value = f.Existencia;
			hoja.Cell(fila, 6).Value = f.Transito;
			hoja.Cell(fila, 7).Value = f.ExistenciaInicial;
			hoja.Cell(fila, 8).Value = f.ExistenciaFinal;
			hoja.Cell(fila, 9).Value = f.InventarioPromedio;
			hoja.Cell(fila, 10).Value = f.Vendidas;
			hoja.Cell(fila, 11).Value = f.CostoVendido;
			hoja.Cell(fila, 12).Value = f.VentaDiaria;
			hoja.Cell(fila, 13).Value = f.Rotacion;
			hoja.Cell(fila, 14).Value = f.RotacionAnual;
			hoja.Cell(fila, 15).Value = f.DiasInventario;
			hoja.Cell(fila, 16).Value = f.DiasCobertura;
			hoja.Cell(fila, 17).Value = f.UltimaVenta;
			hoja.Cell(fila, 18).Value = f.DiasEntrega;
			hoja.Cell(fila, 19).Value = f.DiasSeguridad;
			hoja.Cell(fila, 20).Value = f.PuntoReorden;
			hoja.Cell(fila, 21).Value = f.Sugerido;
			hoja.Cell(fila, 22).Value = f.Proveedor ?? "";
			hoja.Cell(fila, 23).Value = f.ValorInventario;
			if (f.BajoReorden) hoja.Range(fila, 1, fila, 23).Style.Fill.BackgroundColor = XLColor.FromHtml("#fff4d6");
			fila++;
		}
		hoja.Range(inicioDatos, 5, fila, 10).Style.NumberFormat.Format = "#,##0.##";
		hoja.Range(inicioDatos, 11, fila, 11).Style.NumberFormat.Format = FormatoMonto;
		hoja.Range(inicioDatos, 12, fila, 16).Style.NumberFormat.Format = "#,##0.00";
		hoja.Range(inicioDatos, 17, fila, 17).Style.DateFormat.Format = "dd/MM/yyyy";
		hoja.Range(inicioDatos, 23, fila, 23).Style.NumberFormat.Format = FormatoMonto;
		if (fila > inicioDatos) hoja.Range(inicioDatos - 1, 1, fila - 1, 23).SetAutoFilter();
		hoja.Columns().AdjustToContents();
		return Guardar(libro);
	}
}
