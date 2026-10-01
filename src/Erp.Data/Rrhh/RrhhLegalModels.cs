namespace Erp.Data.Rrhh;

// Cumplimiento laboral (script 49): datos del patrono, centros de trabajo del
// IGSS, libro de salarios y planilla mensual del IGSS.

public sealed class CompaniaRrhh
{
	public int CiaId { get; set; }
	public string? IgssNumeroPatronal { get; set; }
	public string? LibroSalariosAutorizacion { get; set; }
}

// Sucursal como centro de trabajo del IGSS. TasaIgssLaboral nula = la del
// tipo de movimiento IGSS_LABORAL.
public sealed class SucursalIgss
{
	public int SucId { get; set; }
	public int CiaId { get; set; }
	public string Codigo { get; set; } = "";
	public string Descripcion { get; set; } = "";
	public string? CentroTrabajo { get; set; }
	public decimal TasaIgssPatronal { get; set; } = 10.67m;
	public decimal? TasaIgssLaboral { get; set; }
	public decimal TasaIrtra { get; set; } = 1m;
	public decimal TasaIntecap { get; set; } = 1m;
	public string Estado { get; set; } = "A";
}

public sealed class LibroSalariosPatrono
{
	public int CiaId { get; set; }
	public string NombreComercial { get; set; } = "";
	public string Nit { get; set; } = "";
	public string? Direccion { get; set; }
	public string? RepresentanteLegal { get; set; }
	public string? IgssNumeroPatronal { get; set; }
	public string? LibroSalariosAutorizacion { get; set; }
	public int Anio { get; set; }
}

public sealed class LibroSalariosTrabajador
{
	public int IdEmpleado { get; set; }
	public int Folio { get; set; }
	public string CodigoEmpleado { get; set; } = "";
	public string NombreCompleto { get; set; } = "";
	public int? Edad { get; set; }
	public string? Genero { get; set; }
	public string Nacionalidad { get; set; } = "";
	public string? TipoDocumento { get; set; }
	public string? NumeroDocumento { get; set; }
	public string? NumeroAfiliacionIGSS { get; set; }
	public string? Nit { get; set; }
	public string? Puesto { get; set; }
	public DateTime FechaIngreso { get; set; }
	public DateTime? FechaBaja { get; set; }
	public string Jornada { get; set; } = "D";
	public string TiempoContrato { get; set; } = "TC";
	public decimal SalarioBase { get; set; }
	public string NombreJornada => Jornada switch { "M" => "Mixta", "N" => "Nocturna", _ => "Diurna" };
}

// Un renglón del libro: una nómina aprobada del trabajador.
public sealed class LibroSalariosRenglon
{
	public int IdEmpleado { get; set; }
	public int IdNomina { get; set; }
	public string Nomina { get; set; } = "";
	public string Clase { get; set; } = "O";
	public string TipoPeriodo { get; set; } = "M";
	public DateTime FechaDel { get; set; }
	public DateTime FechaAl { get; set; }
	public DateTime? FechaPago { get; set; }
	public decimal SalarioBase { get; set; }
	public decimal DiasLaborados { get; set; }
	public int HorasOrdinarias { get; set; }
	public decimal HorasExtra { get; set; }
	public decimal Ordinario { get; set; }
	public decimal Extraordinario { get; set; }
	public decimal Septimos { get; set; }
	public decimal Vacaciones { get; set; }
	public decimal SalarioTotal { get; set; }
	public decimal Igss { get; set; }
	public decimal OtrasDeducciones { get; set; }
	public decimal TotalDeducciones { get; set; }
	public decimal Bono14 { get; set; }
	public decimal Aguinaldo { get; set; }
	public decimal Bonificacion { get; set; }
	public decimal OtrasBonificaciones { get; set; }
	public decimal Indemnizacion { get; set; }
	public decimal Liquido { get; set; }
	public string Periodo => Clase switch
	{
		"A" => $"Aguinaldo {FechaDel:dd/MM/yyyy} al {FechaAl:dd/MM/yyyy}",
		"B" => $"Bono 14 {FechaDel:dd/MM/yyyy} al {FechaAl:dd/MM/yyyy}",
		_ => $"{FechaDel:dd/MM/yyyy} al {FechaAl:dd/MM/yyyy}"
	};
}

public sealed record LibroSalarios(
	LibroSalariosPatrono? Patrono,
	IReadOnlyList<LibroSalariosTrabajador> Trabajadores,
	IReadOnlyList<LibroSalariosRenglon> Renglones)
{
	public IEnumerable<LibroSalariosRenglon> RenglonesDe(int idEmpleado) => Renglones.Where(r => r.IdEmpleado == idEmpleado);
}

public sealed class PlanillaIgssResumen
{
	public int CiaId { get; set; }
	public string NombreComercial { get; set; } = "";
	public string Nit { get; set; } = "";
	public string? Email { get; set; }
	public string? IgssNumeroPatronal { get; set; }
	public int Anio { get; set; }
	public int Mes { get; set; }
	public int Empleados { get; set; }
	public decimal SalarioAfecto { get; set; }
	public decimal CuotaLaboral { get; set; }
	public decimal CuotaPatronal { get; set; }
	public decimal Irtra { get; set; }
	public decimal Intecap { get; set; }
	public decimal TotalPagar { get; set; }
	public int NominasPendientes { get; set; }
}

public sealed class PlanillaIgssCentro
{
	public int? SucId { get; set; }
	public string? Codigo { get; set; }
	public string? Descripcion { get; set; }
	public string? CentroTrabajo { get; set; }
	public decimal? TasaIgssPatronal { get; set; }
	public decimal? TasaIrtra { get; set; }
	public decimal? TasaIntecap { get; set; }
	public int Empleados { get; set; }
	public decimal SalarioAfecto { get; set; }
	public decimal CuotaLaboral { get; set; }
	public decimal CuotaPatronal { get; set; }
	public decimal Irtra { get; set; }
	public decimal Intecap { get; set; }
	public decimal TotalPagar { get; set; }
}

public sealed class PlanillaIgssEmpleado
{
	public int IdEmpleado { get; set; }
	public string CodigoEmpleado { get; set; } = "";
	public string? NumeroAfiliacionIGSS { get; set; }
	public string? Dpi { get; set; }
	public string? Nit { get; set; }
	public string PrimerNombre { get; set; } = "";
	public string? SegundoNombre { get; set; }
	public string PrimerApellido { get; set; } = "";
	public string? SegundoApellido { get; set; }
	public string? ApellidoCasada { get; set; }
	public string? CentroTrabajo { get; set; }
	public string? Sucursal { get; set; }
	public string? Puesto { get; set; }
	public string TiempoContrato { get; set; } = "TC";
	public DateTime? FechaAlta { get; set; }
	public DateTime? FechaBaja { get; set; }
	public decimal Dias { get; set; }
	public decimal SalarioAfecto { get; set; }
	public decimal CuotaLaboral { get; set; }
	public decimal CuotaPatronal { get; set; }
	public decimal Irtra { get; set; }
	public decimal Intecap { get; set; }
	public decimal Total { get; set; }
	public int Nominas { get; set; }
	public string Nombre => string.Join(" ", new[] { PrimerNombre, SegundoNombre, PrimerApellido, SegundoApellido }
		.Where(p => !string.IsNullOrWhiteSpace(p))) + (string.IsNullOrWhiteSpace(ApellidoCasada) ? "" : $" de {ApellidoCasada}");
}

public sealed record PlanillaIgss(
	PlanillaIgssResumen? Resumen,
	IReadOnlyList<PlanillaIgssCentro> Centros,
	IReadOnlyList<PlanillaIgssEmpleado> Empleados);

// Etiquetas de las columnas del libro de salarios para los tipos de movimiento.
public static class ColumnasLibroSalarios
{
	public static readonly IReadOnlyList<(string Codigo, string Nombre, string Naturaleza)> Todas =
	[
		("ORDINARIO", "Salario ordinario", "I"),
		("EXTRAORDINARIO", "Salario extraordinario (horas extra)", "I"),
		("SEPTIMOS", "Séptimos y asuetos", "I"),
		("VACACIONES", "Vacaciones", "I"),
		("BONIFICACION", "Bonificación incentivo (Decreto 37-2001)", "I"),
		("AGUINALDO", "Aguinaldo", "I"),
		("BONO14", "Bono 14", "I"),
		("OTRAS_BONIF", "Otras bonificaciones", "I"),
		("INDEMNIZACION", "Indemnización", "I"),
		("IGSS", "Cuota laboral IGSS", "D"),
		("OTRAS_DEDUCCIONES", "Otras deducciones", "D"),
	];

	public static string Nombre(string? codigo) =>
		Todas.FirstOrDefault(c => c.Codigo == codigo).Nombre ?? "—";
}
