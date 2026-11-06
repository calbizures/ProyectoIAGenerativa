using ClosedXML.Excel;
using Erp.Data.Rrhh;

namespace Erp.Web.Reportes;

// Libros de Excel de RRHH: libro de salarios y planilla mensual del IGSS.
public static partial class ReportesExcel
{
	// Una hoja por folio (trabajador) con sus datos y un renglón por período
	// pagado, más una hoja de resumen con los totales del año por trabajador.
	public static byte[] LibroSalarios(LibroSalarios libro, CompaniaReporte compania)
	{
		using var libroExcel = new XLWorkbook();
		var patrono = libro.Patrono;
		var subtitulo = patrono is null ? "" :
			$"Año {patrono.Anio} · NIT {patrono.Nit}" +
			(string.IsNullOrWhiteSpace(patrono.IgssNumeroPatronal) ? "" : $" · No. patronal IGSS {patrono.IgssNumeroPatronal}") +
			(string.IsNullOrWhiteSpace(patrono.LibroSalariosAutorizacion) ? "" : $" · Autorización {patrono.LibroSalariosAutorizacion}");

		var resumen = libroExcel.Worksheets.Add("Resumen");
		var fila = Encabezado(resumen, compania, "Libro de salarios", subtitulo);
		fila = Titulos(resumen, fila, new List<string> { "Folio", "Código", "Trabajador", "Afiliación IGSS", "Salario total", "IGSS", "Otras deducciones",
			"Bono 14", "Aguinaldo", "Bonificación incentivo", "Otras bonificaciones", "Indemnización", "Líquido" });
		var inicioResumen = fila;
		foreach (var t in libro.Trabajadores)
		{
			var renglones = libro.RenglonesDe(t.IdEmpleado).ToList();
			resumen.Cell(fila, 1).Value = t.Folio;
			resumen.Cell(fila, 2).Value = t.CodigoEmpleado;
			resumen.Cell(fila, 3).Value = t.NombreCompleto;
			resumen.Cell(fila, 4).Value = t.NumeroAfiliacionIGSS;
			resumen.Cell(fila, 5).Value = renglones.Sum(r => r.SalarioTotal);
			resumen.Cell(fila, 6).Value = renglones.Sum(r => r.Igss);
			resumen.Cell(fila, 7).Value = renglones.Sum(r => r.OtrasDeducciones);
			resumen.Cell(fila, 8).Value = renglones.Sum(r => r.Bono14);
			resumen.Cell(fila, 9).Value = renglones.Sum(r => r.Aguinaldo);
			resumen.Cell(fila, 10).Value = renglones.Sum(r => r.Bonificacion);
			resumen.Cell(fila, 11).Value = renglones.Sum(r => r.OtrasBonificaciones);
			resumen.Cell(fila, 12).Value = renglones.Sum(r => r.Indemnizacion);
			resumen.Cell(fila, 13).Value = renglones.Sum(r => r.Liquido);
			fila++;
		}
		resumen.Range(inicioResumen, 4, fila, 4).Style.NumberFormat.Format = "@";
		Totales(resumen, fila, inicioResumen, 5, 13, 3);
		Formato(resumen, inicioResumen, fila, 5, 13);

		foreach (var t in libro.Trabajadores)
		{
			var hoja = libroExcel.Worksheets.Add($"Folio {t.Folio}");
			fila = Encabezado(hoja, compania, $"Libro de salarios · Folio {t.Folio}", subtitulo);
			var datos = new (string Etiqueta, string? Valor)[]
			{
				("Nombre del trabajador", t.NombreCompleto),
				("Edad", t.Edad?.ToString()),
				("Sexo", t.Genero switch { "M" => "Masculino", "F" => "Femenino", _ => null }),
				("Nacionalidad", t.Nacionalidad),
				(t.TipoDocumento ?? "Documento", t.NumeroDocumento),
				("Afiliación IGSS", t.NumeroAfiliacionIGSS),
				("Ocupación", t.Puesto),
				("Jornada", t.NombreJornada + (t.TiempoContrato == "TP" ? ", tiempo parcial" : "")),
				("Fecha de ingreso", t.FechaIngreso.ToString("dd/MM/yyyy")),
				("Fecha de retiro", t.FechaBaja?.ToString("dd/MM/yyyy")),
			};
			foreach (var (etiqueta, valor) in datos)
			{
				hoja.Cell(fila, 1).Value = etiqueta;
				hoja.Cell(fila, 1).Style.Font.Bold = true;
				hoja.Cell(fila, 3).Value = valor ?? "—";
				hoja.Cell(fila, 3).Style.NumberFormat.Format = "@";
				fila++;
			}
			fila++;
			fila = Titulos(hoja, fila, new List<string> { "No.", "Período de trabajo", "Salario base", "Días trabajados", "Horas ordinarias", "Horas extra",
				"Salario ordinario", "Salario extraordinario", "Otros salarios", "Séptimos y asuetos", "Vacaciones", "Salario total", "Cuota laboral IGSS",
				"Otras deducciones", "Total deducciones", "Bono 14", "Aguinaldo", "Bonificación incentivo", "Otras bonificaciones",
				"Indemnización", "Líquido a recibir" });
			var inicioDatos = fila;
			var numero = 0;
			foreach (var r in libro.RenglonesDe(t.IdEmpleado))
			{
				hoja.Cell(fila, 1).Value = ++numero;
				hoja.Cell(fila, 2).Value = r.Periodo;
				hoja.Cell(fila, 3).Value = r.SalarioBase;
				hoja.Cell(fila, 4).Value = r.DiasLaborados;
				hoja.Cell(fila, 5).Value = r.HorasOrdinarias;
				hoja.Cell(fila, 6).Value = r.HorasExtra;
				hoja.Cell(fila, 7).Value = r.Ordinario;
				hoja.Cell(fila, 8).Value = r.Extraordinario;
				hoja.Cell(fila, 9).Value = r.OtrosSalarios;
				hoja.Cell(fila, 10).Value = r.Septimos;
				hoja.Cell(fila, 11).Value = r.Vacaciones;
				hoja.Cell(fila, 12).Value = r.SalarioTotal;
				hoja.Cell(fila, 13).Value = r.Igss;
				hoja.Cell(fila, 14).Value = r.OtrasDeducciones;
				hoja.Cell(fila, 15).Value = r.TotalDeducciones;
				hoja.Cell(fila, 16).Value = r.Bono14;
				hoja.Cell(fila, 17).Value = r.Aguinaldo;
				hoja.Cell(fila, 18).Value = r.Bonificacion;
				hoja.Cell(fila, 19).Value = r.OtrasBonificaciones;
				hoja.Cell(fila, 20).Value = r.Indemnizacion;
				hoja.Cell(fila, 21).Value = r.Liquido;
				fila++;
			}
			Totales(hoja, fila, inicioDatos, 4, 21, 2);
			Formato(hoja, inicioDatos, fila, 7, 21);
			hoja.Range(inicioDatos, 3, fila, 3).Style.NumberFormat.Format = "#,##0.00";
			hoja.Range(inicioDatos, 4, fila, 6).Style.NumberFormat.Format = "#,##0.##";
		}
		return Guardar(libroExcel);
	}

	// Planilla mensual del IGSS: resumen, centros de trabajo y trabajadores con
	// los datos que pide la plantilla del IGSS (afiliación, nombres separados,
	// salario, altas y bajas, centro de trabajo y tiempo de contrato).
	public static byte[] PlanillaIgss(PlanillaIgss planilla, CompaniaReporte compania)
	{
		using var libro = new XLWorkbook();
		var r = planilla.Resumen;
		var mes = r is null ? "" : $"{System.Globalization.CultureInfo.GetCultureInfo("es-GT").DateTimeFormat.GetMonthName(r.Mes)} {r.Anio}";
		var subtitulo = r is null ? "" : $"{mes} · NIT {r.Nit} · No. patronal {r.IgssNumeroPatronal ?? "sin registrar"}";

		var hojaCentros = libro.Worksheets.Add("Centros de trabajo");
		var fila = Encabezado(hojaCentros, compania, "Planilla de seguridad social (IGSS)", subtitulo);
		fila = Titulos(hojaCentros, fila, new List<string> { "Centro de trabajo", "Sucursal", "Tasa IGSS %", "Tasa IRTRA %", "Tasa INTECAP %",
			"Trabajadores", "Salario afecto", "Cuota laboral", "IGSS patronal", "IRTRA", "INTECAP", "Total a pagar" });
		var inicio = fila;
		foreach (var c in planilla.Centros)
		{
			hojaCentros.Cell(fila, 1).Value = c.CentroTrabajo;
			hojaCentros.Cell(fila, 2).Value = c.Descripcion;
			hojaCentros.Cell(fila, 3).Value = c.TasaIgssPatronal;
			hojaCentros.Cell(fila, 4).Value = c.TasaIrtra;
			hojaCentros.Cell(fila, 5).Value = c.TasaIntecap;
			hojaCentros.Cell(fila, 6).Value = c.Empleados;
			hojaCentros.Cell(fila, 7).Value = c.SalarioAfecto;
			hojaCentros.Cell(fila, 8).Value = c.CuotaLaboral;
			hojaCentros.Cell(fila, 9).Value = c.CuotaPatronal;
			hojaCentros.Cell(fila, 10).Value = c.Irtra;
			hojaCentros.Cell(fila, 11).Value = c.Intecap;
			hojaCentros.Cell(fila, 12).Value = c.TotalPagar;
			fila++;
		}
		hojaCentros.Range(inicio, 1, fila, 1).Style.NumberFormat.Format = "@";
		Totales(hojaCentros, fila, inicio, 6, 12, 2);
		Formato(hojaCentros, inicio, fila, 7, 12);

		var hoja = libro.Worksheets.Add("Trabajadores");
		fila = Encabezado(hoja, compania, "Planilla de seguridad social: trabajadores", subtitulo);
		fila = Titulos(hoja, fila, new List<string> { "Número de afiliación", "Primer nombre", "Segundo nombre", "Primer apellido", "Segundo apellido",
			"Apellido de casada", "DPI", "NIT", "Centro de trabajo", "Sucursal", "Puesto", "Tiempo de contrato", "Fecha de alta", "Fecha de baja",
			"Días", "Salario afecto", "Cuota laboral", "IGSS patronal", "IRTRA", "INTECAP", "Total" });
		inicio = fila;
		foreach (var e in planilla.Empleados)
		{
			hoja.Cell(fila, 1).Value = e.NumeroAfiliacionIGSS;
			hoja.Cell(fila, 2).Value = e.PrimerNombre.ToUpperInvariant();
			hoja.Cell(fila, 3).Value = e.SegundoNombre?.ToUpperInvariant();
			hoja.Cell(fila, 4).Value = e.PrimerApellido.ToUpperInvariant();
			hoja.Cell(fila, 5).Value = e.SegundoApellido?.ToUpperInvariant();
			hoja.Cell(fila, 6).Value = e.ApellidoCasada?.ToUpperInvariant();
			hoja.Cell(fila, 7).Value = e.Dpi;
			hoja.Cell(fila, 8).Value = e.Nit;
			hoja.Cell(fila, 9).Value = e.CentroTrabajo;
			hoja.Cell(fila, 10).Value = e.Sucursal;
			hoja.Cell(fila, 11).Value = e.Puesto;
			hoja.Cell(fila, 12).Value = e.TiempoContrato;
			if (e.FechaAlta is DateTime alta) hoja.Cell(fila, 13).Value = alta;
			if (e.FechaBaja is DateTime baja) hoja.Cell(fila, 14).Value = baja;
			hoja.Cell(fila, 15).Value = e.Dias;
			hoja.Cell(fila, 16).Value = e.SalarioAfecto;
			hoja.Cell(fila, 17).Value = e.CuotaLaboral;
			hoja.Cell(fila, 18).Value = e.CuotaPatronal;
			hoja.Cell(fila, 19).Value = e.Irtra;
			hoja.Cell(fila, 20).Value = e.Intecap;
			hoja.Cell(fila, 21).Value = e.Total;
			fila++;
		}
		// Afiliación, DPI, NIT y centro como texto (sin perder ceros).
		foreach (var columna in new[] { 1, 7, 8, 9 })
			hoja.Range(inicio, columna, fila, columna).Style.NumberFormat.Format = "@";
		hoja.Range(inicio, 13, fila, 14).Style.DateFormat.Format = "dd/MM/yyyy";
		Totales(hoja, fila, inicio, 16, 21, 4);
		Formato(hoja, inicio, fila, 16, 21);
		if (fila > inicio) hoja.Range(inicio - 1, 1, fila - 1, 21).SetAutoFilter();
		return Guardar(libro);
	}
}
