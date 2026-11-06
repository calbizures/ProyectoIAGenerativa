using ClosedXML.Excel;
using Erp.Data.General;

namespace Erp.Web.Reportes;

// Plantilla de las facturas (clientes) o compras (proveedores) pendientes al
// arrancar el sistema (script 86): una fila por cuota pendiente.
public static partial class ReportesExcel
{
	public static readonly string[] ColumnasDocumentosPendientesClientes =
		{ "Código", "Nombre", "NIT", "Sucursal", "Serie", "Número", "Fecha documento", "Cuota", "Vencimiento", "Saldo", "Serie FEL", "Número FEL", "UUID FEL" };

	public static readonly string[] ColumnasDocumentosPendientesProveedores =
		{ "Código", "Nombre", "NIT", "Sucursal", "Serie", "Número", "Fecha documento", "Cuota", "Vencimiento", "Saldo" };

	public static string[] ColumnasDocumentosPendientes(bool esCliente) =>
		esCliente ? ColumnasDocumentosPendientesClientes : ColumnasDocumentosPendientesProveedores;

	public static byte[] PlantillaDocumentosPendientes(bool esCliente, IReadOnlyList<SucursalDetalle> sucursales,
		IEnumerable<(string Codigo, string Nombre, string? Nit)> terceros, CompaniaReporte compania)
	{
		var columnas = ColumnasDocumentosPendientes(esCliente);
		var tercero = esCliente ? "cliente" : "proveedor";
		var documento = esCliente ? "factura" : "compra";
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add(esCliente ? "Facturas pendientes" : "Compras pendientes");
		var fila = Encabezado(hoja, compania, esCliente ? "Facturas pendientes de cobro al arrancar" : "Compras pendientes de pago al arrancar",
			$"Una fila por cada cuota pendiente de cada {documento}. Una {documento} con varias cuotas pendientes va en varias filas.");
		fila = Titulos(hoja, fila, columnas);
		var ultima = fila + 1000;
		hoja.Range(fila, 1, ultima, 6).Style.NumberFormat.Format = "@";
		hoja.Range(fila, 7, ultima, 7).Style.NumberFormat.Format = "dd/mm/yyyy";
		hoja.Range(fila, 8, ultima, 8).Style.NumberFormat.Format = "0";
		hoja.Range(fila, 9, ultima, 9).Style.NumberFormat.Format = "dd/mm/yyyy";
		hoja.Range(fila, 10, ultima, 10).Style.NumberFormat.Format = "#,##0.00";
		if (esCliente) hoja.Range(fila, 11, ultima, 13).Style.NumberFormat.Format = "@";
		hoja.Range(fila, 1, ultima, columnas.Length).Style.Fill.BackgroundColor = Captura;
		hoja.Column(1).Width = 14;
		hoja.Column(2).Width = 34;
		foreach (var c in new[] { 3, 4, 5, 6 }) hoja.Column(c).Width = 12;
		foreach (var c in new[] { 7, 9 }) hoja.Column(c).Width = 15;
		hoja.Column(8).Width = 8;
		hoja.Column(10).Width = 14;
		if (esCliente) { hoja.Column(11).Width = 12; hoja.Column(12).Width = 14; hoja.Column(13).Width = 40; }

		// Validaciones que ayudan a llenar bien desde Excel.
		var fechas = hoja.Range(fila, 7, ultima, 7).CreateDataValidation();
		fechas.Date.GreaterThan(new DateTime(1990, 1, 1));
		fechas.ErrorTitle = "Fecha";
		fechas.ErrorMessage = "Escriba una fecha válida (dd/mm/aaaa).";
		var vencimientos = hoja.Range(fila, 9, ultima, 9).CreateDataValidation();
		vencimientos.Date.GreaterThan(new DateTime(1990, 1, 1));
		vencimientos.ErrorTitle = "Vencimiento";
		vencimientos.ErrorMessage = "Escriba una fecha válida (dd/mm/aaaa).";
		var saldos = hoja.Range(fila, 10, ultima, 10).CreateDataValidation();
		saldos.Decimal.GreaterThan(0);
		saldos.ErrorTitle = "Saldo";
		saldos.ErrorMessage = "El saldo pendiente debe ser mayor a cero.";

		var ayuda = libro.Worksheets.Add("Instrucciones");
		var textos = new List<string>
		{
			$"Cómo llenar la hoja \"{hoja.Name}\"",
			$"• Una fila por cada cuota pendiente. Una {documento} al crédito con tres cuotas por {(esCliente ? "cobrar" : "pagar")} va en tres filas, con el mismo Código, Serie, Número y Fecha documento.",
			$"• Código: el del {tercero} en el sistema (hoja {(esCliente ? "Clientes" : "Proveedores")}). Si no existe, se crea con el Nombre y el NIT de la fila.",
			$"• NIT: con o sin guion (1234567-8), C/F o el CUI de 13 dígitos. Se valida el dígito verificador. Para un {tercero} que ya existe, Nombre y NIT se ignoran.",
			"• Sucursal: opcional; elija de la lista. Vacía = la casa matriz.",
			$"• Serie y Número: los de la {documento} original. No se puede cargar dos veces el mismo documento del mismo {tercero}.",
			"• Fecha documento: la de la factura original; no puede ser posterior a la fecha de los saldos iniciales que indique en el sistema.",
			"• Cuota: opcional. Si la deja vacía, las cuotas de cada documento se numeran por fecha de vencimiento. Si numera, numere todas las del documento.",
			"• Vencimiento: fecha en que vence la cuota (define la antigüedad del saldo).",
			"• Saldo: lo que todavía se debe de esa cuota, con IVA, en quetzales.",
		};
		if (esCliente)
			textos.Add("• Serie FEL, Número FEL y UUID FEL: opcionales, los de la factura electrónica certificada por SAT. Con ellos podrá emitir después una nota de crédito electrónica sobre esa factura.");
		textos.AddRange(new[]
		{
			"• Al subir el archivo se valida completo: si alguna fila tiene error no se graba nada.",
			$"• La carga no genera póliza: su total debe ser igual a lo que la partida de saldos iniciales lleva a la cuenta de {(esCliente ? "clientes" : "proveedores")}. El sistema le avisa si no coincide.",
			"• Mientras ningún documento tenga cobros, pagos o notas, la carga se puede anular y volver a subir."
		});
		for (var i = 0; i < textos.Count; i++) ayuda.Cell(i + 1, 1).Value = textos[i];
		ayuda.Cell(1, 1).Style.Font.Bold = true;
		ayuda.Column(1).Width = 130;

		var activas = sucursales.Where(s => s.SucEstado == "A").OrderBy(s => s.SucCodigo).ToList();
		var nSucursales = Catalogo(libro, "Sucursales", new[] { "Sucursal", "Nombre de la sucursal" },
			activas.Select(s => new object[] { s.SucCodigo, s.SucDescripcion }));
		Catalogo(libro, esCliente ? "Clientes" : "Proveedores", new[] { "Código", "Nombre", "NIT" },
			terceros.OrderBy(t => t.Codigo).Select(t => new object[] { t.Codigo, t.Nombre, t.Nit ?? "" }));
		Lista(hoja.Range(fila, 4, ultima, 4), Columna("Sucursales", "A", nSucursales), "Sucursal",
			"Opcional: elija la sucursal de la lista (hoja Sucursales). Vacía = casa matriz.");

		hoja.SheetView.FreezeRows(fila - 1);
		hoja.SetTabActive();
		return Guardar(libro);
	}
}
