using ClosedXML.Excel;
using Erp.Data.Caja;
using Erp.Data.Cargas;
using Erp.Data.Inventario;
using Erp.Data.Rrhh;

namespace Erp.Web.Reportes;

// Plantillas y hojas de trabajo de las cargas desde Excel. Cada una trae la
// hoja de datos (la que se vuelve a subir) y hojas de consulta con los
// códigos válidos.
public static partial class ReportesExcel
{
	public static readonly string[] ColumnasInventarioInicial =
		{ "Sucursal", "Bodega", "Producto", "Descripción", "Tipo", "Unidad", "Cantidad", "Costo total", "Precio venta" };

	public static readonly string[] ColumnasEmpleados =
	{
		"Código", "Primer nombre", "Segundo nombre", "Primer apellido", "Segundo apellido", "Género", "Fecha nacimiento", "Fecha ingreso",
		"Tipo documento", "Número documento", "Afiliación IGSS", "NIT", "Email", "Dirección", "Plaza", "Salario base", "Tipo nómina",
		"Forma pago", "Banco", "Tipo cuenta", "Número cuenta"
	};

	public static readonly string[] ColumnasSaldosIniciales = { "Código", "Cuenta", "Debe", "Haber" };

	public static readonly string[] ColumnasConteo = { "Código", "Descripción", "Conteo" };

	private static readonly XLColor Captura = XLColor.FromHtml("#fff8e1");
	private static readonly XLColor Agrupacion = XLColor.FromHtml("#eef1f6");

	public static byte[] PlantillaInventarioInicial(IReadOnlyList<BodegaDetalle> bodegas, IReadOnlyList<ProductoTipo> tipos,
		IReadOnlyList<UnidadMedida> unidades, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add("Inventario inicial");
		var fila = Encabezado(hoja, compania, "Inventario inicial por sucursal y bodega",
			"Una fila por producto y bodega. El costo total es el de todas las unidades; el precio de venta es unitario e incluye IVA.");
		fila = Titulos(hoja, fila, ColumnasInventarioInicial);
		hoja.Range(fila, 1, fila + 500, 6).Style.NumberFormat.Format = "@";
		hoja.Range(fila, 7, fila + 500, 7).Style.NumberFormat.Format = "#,##0.####";
		hoja.Range(fila, 8, fila + 500, 9).Style.NumberFormat.Format = "#,##0.00";
		hoja.Range(fila, 1, fila + 500, 9).Style.Fill.BackgroundColor = Captura;
		hoja.Column(4).Width = 40;
		foreach (var c in new[] { 1, 2, 3, 5, 6 }) hoja.Column(c).Width = 14;
		foreach (var c in new[] { 7, 8, 9 }) hoja.Column(c).Width = 14;

		var ayuda = libro.Worksheets.Add("Instrucciones");
		var textos = new[]
		{
			"Cómo llenar la hoja \"Inventario inicial\"",
			"• Sucursal, Bodega, Tipo y Unidad se eligen de listas desplegables con los datos de la base; no se aceptan otros valores.",
			"• Bodega: elija primero la sucursal; la lista muestra solo las bodegas de esa sucursal.",
			"• Producto: código del producto. Si no existe se crea con la Descripción, el Tipo y la Unidad que indique.",
			"• Si el producto ya existe, Descripción y Tipo se ignoran; la Unidad, si viene, debe ser la misma del producto.",
			"• Cantidad: unidades en la bodega. Costo total: costo de todas esas unidades (el costo unitario = costo total / cantidad).",
			"• Precio venta: precio unitario de venta con IVA para esa bodega (opcional).",
			"• El mismo producto no puede repetirse en la misma bodega. Si una fila tiene error, no se graba ninguna.",
			"• La carga no genera partida: su valor debe entrar en la partida de saldos iniciales (cuenta de inventario)."
		};
		for (var i = 0; i < textos.Length; i++) ayuda.Cell(i + 1, 1).Value = textos[i];
		ayuda.Cell(1, 1).Style.Font.Bold = true;
		ayuda.Column(1).Width = 110;

		// Las bodegas van ordenadas por sucursal: la lista de la columna Bodega
		// toma solo las de la sucursal elegida en la misma fila.
		var activas = bodegas.Where(b => b.BodEstado == "A").OrderBy(b => b.SucCodigo).ThenBy(b => b.BodCodigo).ToList();
		var sucursales = activas.GroupBy(b => b.SucCodigo).Select(g => g.First()).ToList();
		var nSucursales = Catalogo(libro, "Sucursales", new[] { "Sucursal", "Nombre de la sucursal" },
			sucursales.Select(b => new object[] { b.SucCodigo, b.SucDescripcion }));
		Catalogo(libro, "Bodegas", new[] { "Sucursal", "Nombre de la sucursal", "Bodega", "Nombre de la bodega" },
			activas.Select(b => new object[] { b.SucCodigo, b.SucDescripcion, b.BodCodigo, b.BodDescripcion }));
		var nTipos = Catalogo(libro, "Tipos", new[] { "Tipo", "Descripción" }, tipos.Select(t => new object[] { t.PrtCodigo, t.PrtDescripcion }));
		var nUnidades = Catalogo(libro, "Unidades", new[] { "Unidad", "Descripción" },
			unidades.Where(u => u.UmeEstado == "A").Select(u => new object[] { u.UmeCodigo, u.UmeDescripcion }));

		var ultima = fila + 500;
		Lista(hoja.Range(fila, 1, ultima, 1), Columna("Sucursales", "A", nSucursales), "Sucursal",
			"Elija la sucursal de la lista (hoja Sucursales).");
		Lista(hoja.Range(fila, 2, ultima, 2),
			$"OFFSET(Bodegas!$C$1,MATCH($A{fila},Bodegas!$A:$A,0)-1,0,MAX(1,COUNTIF(Bodegas!$A:$A,$A{fila})),1)", "Bodega",
			"Elija primero la sucursal; la lista muestra solo sus bodegas (hoja Bodegas).");
		Lista(hoja.Range(fila, 5, ultima, 5), Columna("Tipos", "A", nTipos), "Tipo",
			"Elija el tipo de la lista (hoja Tipos). Solo se usa si el producto es nuevo.");
		Lista(hoja.Range(fila, 6, ultima, 6), Columna("Unidades", "A", nUnidades), "Unidad",
			"Elija la unidad de la lista (hoja Unidades).");
		hoja.SetTabActive();
		return Guardar(libro);
	}

	// Rango de una columna de una hoja de catálogo (títulos en la fila 1).
	private static string Columna(string hoja, string columna, int filas) =>
		$"'{hoja}'!${columna}$2:${columna}${Math.Max(2, filas + 1)}";

	// Lista desplegable que solo admite los valores del catálogo.
	private static void Lista(IXLRange rango, string formula, string titulo, string mensaje)
	{
		var validacion = rango.CreateDataValidation();
		validacion.List(formula, true);
		validacion.IgnoreBlanks = true;
		validacion.ShowErrorMessage = true;
		validacion.ErrorStyle = XLErrorStyle.Stop;
		validacion.ErrorTitle = titulo;
		validacion.ErrorMessage = "El valor no existe en la base de datos. " + mensaje;
		validacion.ShowInputMessage = true;
		validacion.InputTitle = titulo;
		validacion.InputMessage = mensaje;
	}

	public static byte[] PlantillaEmpleados(IReadOnlyList<Plaza> plazas, IReadOnlyList<EntidadFinanciera> bancos,
		IReadOnlyList<CatalogoRrhh> tiposDocumento, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add("Empleados");
		var fila = Encabezado(hoja, compania, "Carga de empleados",
			"Una fila por empleado. Si el código ya existe, se actualizan sus datos (los opcionales vacíos conservan lo que tenía).");
		fila = Titulos(hoja, fila, ColumnasEmpleados);
		hoja.Range(fila, 1, fila + 500, ColumnasEmpleados.Length).Style.NumberFormat.Format = "@";
		hoja.Range(fila, 7, fila + 500, 8).Style.NumberFormat.Format = "dd/mm/yyyy";
		hoja.Range(fila, 16, fila + 500, 16).Style.NumberFormat.Format = "#,##0.00";
		hoja.Range(fila, 1, fila + 500, ColumnasEmpleados.Length).Style.Fill.BackgroundColor = Captura;
		hoja.Columns(1, ColumnasEmpleados.Length).Width = 16;

		var ayuda = libro.Worksheets.Add("Instrucciones");
		var textos = new[]
		{
			"Cómo llenar la hoja \"Empleados\"",
			"• Obligatorios: Código, Primer nombre, Primer apellido, Fecha ingreso (si es nuevo), Salario base (mensual) y Forma pago.",
			"• Género: M o F. Fechas: dd/mm/aaaa.",
			"• Tipo documento: como en la hoja Tipos de documento (DPI, Pasaporte).",
			"• Plaza: nombre exacto de la hoja Plazas; una plaza solo puede tener un empleado activo. El departamento de la plaza es su centro de costo.",
			"• Tipo nómina: S (semanal), Q (quincenal) o M (mensual); vacío = la periodicidad de la compañía.",
			"• Forma pago: T (transferencia) o C (cheque). No se paga en efectivo.",
			"• Para transferencia: Banco (código de la hoja Bancos), Tipo cuenta (M monetaria / A ahorro) y Número cuenta.",
			"• Si una fila tiene error, no se graba ninguna."
		};
		for (var i = 0; i < textos.Length; i++) ayuda.Cell(i + 1, 1).Value = textos[i];
		ayuda.Cell(1, 1).Style.Font.Bold = true;
		ayuda.Column(1).Width = 120;

		var nPlazas = Catalogo(libro, "Plazas", new[] { "Plaza", "Puesto", "Departamento (centro de costo)", "Ocupada por" },
			plazas.Where(p => p.Estado == "A").Select(p => new object[] { p.Descripcion, p.Puesto, p.Departamento, p.EmpleadoOcupante ?? "" }));
		var nBancos = Catalogo(libro, "Bancos", new[] { "Banco", "Nombre" }, bancos.Select(b => new object[] { b.GefCodigo, b.GefDescripcion }));
		var nDocumentos = Catalogo(libro, "Tipos de documento", new[] { "Tipo documento" }, tiposDocumento.Select(t => new object[] { t.Descripcion }));

		var ultima = fila + 500;
		Lista(hoja.Range(fila, 6, ultima, 6), "\"M,F\"", "Género", "M (masculino) o F (femenino).");
		Lista(hoja.Range(fila, 9, ultima, 9), Columna("Tipos de documento", "A", nDocumentos), "Tipo documento",
			"Elija el tipo de la lista (hoja Tipos de documento).");
		Lista(hoja.Range(fila, 15, ultima, 15), Columna("Plazas", "A", nPlazas), "Plaza", "Elija la plaza de la lista (hoja Plazas).");
		Lista(hoja.Range(fila, 17, ultima, 17), "\"S,Q,M\"", "Tipo nómina", "S semanal, Q quincenal o M mensual.");
		Lista(hoja.Range(fila, 18, ultima, 18), "\"T,C\"", "Forma pago", "T transferencia o C cheque.");
		Lista(hoja.Range(fila, 19, ultima, 19), Columna("Bancos", "A", nBancos), "Banco", "Elija el banco de la lista (hoja Bancos).");
		Lista(hoja.Range(fila, 20, ultima, 20), "\"M,A\"", "Tipo cuenta", "M monetaria o A ahorro.");
		hoja.SetTabActive();
		return Guardar(libro);
	}

	// Nomenclatura para que el contador ponga los saldos iniciales. Las cuentas
	// de agrupación van en gris (no llevan saldo) y abajo están los totales.
	public static byte[] SaldosIniciales(IReadOnlyList<CuentaSaldoInicial> cuentas, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add("Saldos iniciales");
		var fila = Encabezado(hoja, compania, "Saldos iniciales (partida de apertura)",
			"Ponga el saldo de cada cuenta de movimiento en Debe (deudor) o en Haber (acreedor). Las filas grises son de agrupación.");
		fila = Titulos(hoja, fila, new[] { "Código", "Cuenta", "Naturaleza", "Debe", "Haber" });
		var inicio = fila;
		foreach (var c in cuentas)
		{
			hoja.Cell(fila, 1).SetValue(c.Codigo);
			hoja.Cell(fila, 2).Value = new string(' ', Math.Max(0, (c.Nivel - 1) * 3)) + c.Nombre;
			hoja.Cell(fila, 3).Value = c.Naturaleza == "D" ? "Deudora" : c.Naturaleza == "H" ? "Acreedora" : "";
			if (c.AceptaMovimiento)
			{
				if (c.Debe is not null) hoja.Cell(fila, 4).Value = c.Debe.Value;
				if (c.Haber is not null) hoja.Cell(fila, 5).Value = c.Haber.Value;
				hoja.Range(fila, 4, fila, 5).Style.Fill.BackgroundColor = Captura;
			}
			else
			{
				var grupo = hoja.Range(fila, 1, fila, 5);
				grupo.Style.Fill.BackgroundColor = Agrupacion;
				grupo.Style.Font.Bold = true;
			}
			fila++;
		}
		hoja.Range(inicio, 1, fila, 1).Style.NumberFormat.Format = "@";
		hoja.Range(inicio, 4, fila + 2, 5).Style.NumberFormat.Format = FormatoMonto;
		hoja.Cell(fila, 2).Value = "Totales";
		hoja.Cell(fila, 4).FormulaA1 = $"SUM(D{inicio}:D{fila - 1})";
		hoja.Cell(fila, 5).FormulaA1 = $"SUM(E{inicio}:E{fila - 1})";
		hoja.Cell(fila + 1, 2).Value = "Diferencia (debe quedar en cero)";
		hoja.Cell(fila + 1, 4).FormulaA1 = $"D{fila}-E{fila}";
		hoja.Range(fila, 1, fila + 1, 5).Style.Font.Bold = true;
		hoja.Range(fila, 1, fila, 5).Style.Border.TopBorder = XLBorderStyleValues.Thin;
		hoja.Column(1).Width = 14;
		hoja.Column(2).Width = 60;
		hoja.Column(3).Width = 12;
		hoja.Columns(4, 5).Width = 16;
		return Guardar(libro);
	}

	// Hoja para contar: se imprime o se llena la columna Conteo y se sube a la toma.
	public static byte[] HojaConteo(TomaFisica toma, IReadOnlyList<TomaFisicaLinea> lineas, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var hoja = libro.Worksheets.Add("Conteo");
		var fila = Encabezado(hoja, compania, $"Inventario físico #{toma.TfiId} · {toma.Bodega}",
			$"{toma.Sucursal} · {toma.Fecha:dd/MM/yyyy}. Anote en Conteo las unidades contadas; deje vacío lo que no se contó.");
		fila = Titulos(hoja, fila, new[] { "Código", "Descripción", "Tipo", "Unidad", "Existencia", "Conteo" });
		var inicio = fila;
		foreach (var l in lineas)
		{
			hoja.Cell(fila, 1).SetValue(l.Codigo);
			hoja.Cell(fila, 2).Value = l.Descripcion;
			hoja.Cell(fila, 3).Value = l.TipoProducto;
			hoja.Cell(fila, 4).Value = l.Unidad;
			hoja.Cell(fila, 5).Value = l.Existencia;
			if (l.Conteo is not null) hoja.Cell(fila, 6).Value = l.Conteo.Value;
			fila++;
		}
		hoja.Range(inicio, 5, fila, 6).Style.NumberFormat.Format = "#,##0.####";
		hoja.Range(inicio, 6, Math.Max(inicio, fila - 1), 6).Style.Fill.BackgroundColor = Captura;
		hoja.Column(1).Width = 16;
		hoja.Column(2).Width = 50;
		hoja.Columns(3, 6).Width = 14;
		return Guardar(libro);
	}

	// Hoja de consulta con títulos en la fila 1; devuelve cuántas filas de datos tiene.
	private static int Catalogo(XLWorkbook libro, string nombre, IList<string> columnas, IEnumerable<object[]> filas)
	{
		var hoja = libro.Worksheets.Add(nombre);
		var fila = Titulos(hoja, 1, columnas);
		foreach (var valores in filas)
		{
			for (var i = 0; i < valores.Length; i++) hoja.Cell(fila, i + 1).SetValue(XLCellValue.FromObject(valores[i]));
			fila++;
		}
		hoja.Columns().AdjustToContents();
		return fila - 2;
	}
}
