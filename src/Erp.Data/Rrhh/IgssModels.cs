namespace Erp.Data.Rrhh;

// Planilla del IGSS para "sistema propio", formato 2.2.0 (script 55).

public sealed record IgssCodigo(string Codigo, string Descripcion)
{
	public string Texto => $"{Codigo} · {Descripcion}";
}

public sealed record IgssMunicipio(string Departamento, string Municipio, string Nombre);

public sealed class IgssCatalogos
{
	public IReadOnlyList<IgssCodigo> Actividades { get; init; } = Array.Empty<IgssCodigo>();
	public IReadOnlyList<IgssCodigo> Ocupaciones { get; init; } = Array.Empty<IgssCodigo>();
	public IReadOnlyList<IgssCodigo> Departamentos { get; init; } = Array.Empty<IgssCodigo>();
	public IReadOnlyList<IgssMunicipio> Municipios { get; init; } = Array.Empty<IgssMunicipio>();
	public IReadOnlyList<IgssCodigo> TiposSalario { get; init; } = Array.Empty<IgssCodigo>();
}

// Tipo de planilla: afiliado C con IVS / S sin IVS; período M mensual, C catorcenal,
// S semanal; clase N normal / V sin movimiento; tiempo de contrato TC / TP.
public sealed class IgssTipoPlanilla
{
	public int IdTipoPlanilla { get; set; }
	public int CiaId { get; set; }
	public int Codigo { get; set; }
	public string Nombre { get; set; } = "";
	public string TipoAfiliado { get; set; } = "C";
	public string Periodo { get; set; } = "M";
	public string Departamento { get; set; } = "01";
	public string Actividad { get; set; } = "";
	public string Clase { get; set; } = "N";
	public string TiempoContrato { get; set; } = "TC";
	public string Estado { get; set; } = "A";
	public int Empleados { get; set; }
}

public sealed class EmpleadoIgss
{
	public int IdEmpleado { get; set; }
	public int? IdIgssTipoPlanilla { get; set; }
	public string CondicionLaboral { get; set; } = "P";
	public byte IgssTipoSalario { get; set; } = 1;
	public decimal? HorasDiarias { get; set; }
	public string? IgssOcupacion { get; set; }
	public string? OcupacionPuesto { get; set; }
	public string? OcupacionPuestoDescripcion { get; set; }
}

// Suspensión del IGSS (S) o licencia sin goce de salario (L).
public sealed class IgssAusencia
{
	public int IdAusencia { get; set; }
	public int IdEmpleado { get; set; }
	public string Tipo { get; set; } = "S";
	public DateTime FechaInicio { get; set; }
	public DateTime FechaFin { get; set; }
	public string? Observacion { get; set; }
}

// Bloques del archivo de un mes (paRrhhPlanillaIgssArchivoConsultar).
public sealed class IgssArchivoPatrono
{
	public string? NumeroPatronal { get; set; }
	public string NombreComercial { get; set; } = "";
	public string? Nit { get; set; }
	public string? Correo { get; set; }
	public int Anio { get; set; }
	public int Mes { get; set; }
}

public sealed class IgssArchivoCentro
{
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public string? Direccion { get; set; }
	public byte? Zona { get; set; }
	public string? Telefono { get; set; }
	public string? Fax { get; set; }
	public string? Contacto { get; set; }
	public string? Email { get; set; }
	public string? Departamento { get; set; }
	public string? Municipio { get; set; }
	public string? Actividad { get; set; }
}

public sealed class IgssArchivoTipoPlanilla
{
	public int Codigo { get; set; }
	public string Nombre { get; set; } = "";
	public string TipoAfiliado { get; set; } = "C";
	public string Periodo { get; set; } = "M";
	public string Departamento { get; set; } = "";
	public string Actividad { get; set; } = "";
	public string Clase { get; set; } = "N";
	public string TiempoContrato { get; set; } = "TC";
}

public sealed class IgssArchivoLiquidacion
{
	public int Numero { get; set; }
	public int TipoPlanilla { get; set; }
	public DateTime FechaInicio { get; set; }
	public DateTime FechaFin { get; set; }
}

public sealed class IgssArchivoEmpleado
{
	public int Liquidacion { get; set; }
	public string CodigoEmpleado { get; set; } = "";
	public string? Afiliacion { get; set; }
	public string PrimerNombre { get; set; } = "";
	public string? SegundoNombre { get; set; }
	public string PrimerApellido { get; set; } = "";
	public string? SegundoApellido { get; set; }
	public string? ApellidoCasada { get; set; }
	public decimal Sueldo { get; set; }
	public DateTime? FechaAlta { get; set; }
	public DateTime? FechaBaja { get; set; }
	public string? Centro { get; set; }
	public string? Nit { get; set; }
	public string? Ocupacion { get; set; }
	public string Condicion { get; set; } = "P";
	public byte TipoSalario { get; set; } = 1;
	public decimal? Horas { get; set; }
	public string TiempoContrato { get; set; } = "TC";
	public decimal Dias { get; set; }
}

public sealed class IgssArchivoAusencia
{
	public string Tipo { get; set; } = "S";
	public int Liquidacion { get; set; }
	public string? Afiliacion { get; set; }
	public string PrimerNombre { get; set; } = "";
	public string? SegundoNombre { get; set; }
	public string PrimerApellido { get; set; } = "";
	public string? SegundoApellido { get; set; }
	public string? ApellidoCasada { get; set; }
	public DateTime FechaInicio { get; set; }
	public DateTime FechaFin { get; set; }
}

// Nivel E: impide generar el archivo; A: aviso.
public sealed record IgssArchivoObservacion(string Nivel, string Mensaje);

public sealed class IgssArchivoDatos
{
	public IgssArchivoPatrono? Patrono { get; init; }
	public IReadOnlyList<IgssArchivoCentro> Centros { get; init; } = Array.Empty<IgssArchivoCentro>();
	public IReadOnlyList<IgssArchivoTipoPlanilla> TiposPlanilla { get; init; } = Array.Empty<IgssArchivoTipoPlanilla>();
	public IReadOnlyList<IgssArchivoLiquidacion> Liquidaciones { get; init; } = Array.Empty<IgssArchivoLiquidacion>();
	public IReadOnlyList<IgssArchivoEmpleado> Empleados { get; init; } = Array.Empty<IgssArchivoEmpleado>();
	public IReadOnlyList<IgssArchivoAusencia> Ausencias { get; init; } = Array.Empty<IgssArchivoAusencia>();
	public IReadOnlyList<IgssArchivoObservacion> Observaciones { get; init; } = Array.Empty<IgssArchivoObservacion>();
	public bool TieneErrores => Observaciones.Any(o => o.Nivel == "E");
}
