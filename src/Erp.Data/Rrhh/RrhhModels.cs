namespace Erp.Data.Rrhh;

// Catálogo simple (Id, Descripción, Estado) de RRHH: unidades organizativas,
// tipos de requisito, documento, teléfono, escolaridad, evaluación y cursos.
public sealed class CatalogoRrhh
{
	public int Id { get; set; }
	public string Descripcion { get; set; } = "";
	public string Estado { get; set; } = "A";
}

public sealed class Departamento
{
	public int IdDepartamento { get; set; }
	public string Descripcion { get; set; } = "";
	public int? IdUnidadOrganizativa { get; set; }
	public string? UnidadOrganizativa { get; set; }
	public int? SucId { get; set; }
	public string? SucDescripcion { get; set; }
	public string Estado { get; set; } = "A";
}

public sealed class Puesto
{
	public int IdPuesto { get; set; }
	public string Descripcion { get; set; } = "";
	public decimal? SalarioMinimo { get; set; }
	public decimal? SalarioMaximo { get; set; }
	public string Estado { get; set; } = "A";
	// Ocupación CIUO-88 del puesto para la planilla del IGSS.
	public string? IgssOcupacion { get; set; }
	public string? IgssOcupacionDescripcion { get; set; }
}

public sealed class Plaza
{
	public int IdPlaza { get; set; }
	public string Descripcion { get; set; } = "";
	public string Estado { get; set; } = "A";
	public int IdDepartamento { get; set; }
	public string Departamento { get; set; } = "";
	public int IdPuesto { get; set; }
	public string Puesto { get; set; } = "";
	public int? IdEmpleadoOcupante { get; set; }
	public string? EmpleadoOcupante { get; set; }
}

public sealed class EmpleadoResumen
{
	public int IdEmpleado { get; set; }
	public string CodigoEmpleado { get; set; } = "";
	public string Nombres { get; set; } = "";
	public string Apellidos { get; set; } = "";
	public DateTime FechaIngreso { get; set; }
	public DateTime? FechaBaja { get; set; }
	public decimal SalarioBase { get; set; }
	public string Estado { get; set; } = "A";
	public string? Plaza { get; set; }
	public string? Puesto { get; set; }
	public string? Departamento { get; set; }
	public string TipoNomina { get; set; } = "M";
	public string? FormaPago { get; set; }
	public string? Banco { get; set; }
	public string NombreCompleto => $"{Nombres} {Apellidos}".Trim();
}

public sealed class Empleado
{
	public int IdEmpleado { get; set; }
	public string CodigoEmpleado { get; set; } = "";
	public int CiaId { get; set; }
	public string PrimerNombre { get; set; } = "";
	public string? SegundoNombre { get; set; }
	public string PrimerApellido { get; set; } = "";
	public string? SegundoApellido { get; set; }
	public string? ApellidoCasada { get; set; }
	public string? Genero { get; set; }
	public DateTime? FechaNacimiento { get; set; }
	public DateTime FechaIngreso { get; set; } = DateTime.Today;
	public DateTime? FechaBaja { get; set; }
	public string? Direccion { get; set; }
	// Ubicación (script 73): municipio; departamento y país se derivan.
	public int? ProvId { get; set; }
	public int? EstId { get; set; }
	public int? PaiId { get; set; }
	public string? Municipio { get; set; }
	public string? Departamento { get; set; }
	public string? Pais { get; set; }
	public string? DireccionCompleta { get; set; }
	public int? IdTipoDocumentoIdentificacion { get; set; }
	public string? NumeroDocumento { get; set; }
	public string? NumeroAfiliacionIGSS { get; set; }
	public string? Nit { get; set; }
	public string? Email { get; set; }
	public int? IdPlaza { get; set; }
	public decimal SalarioBase { get; set; }
	public string Estado { get; set; } = "A";
	public int? UsuId { get; set; }
	public int? PveId { get; set; }
	// Pago de nómina: S = semanal, Q = quincenal, M = mensual; T = transferencia, C = cheque.
	public string TipoNomina { get; set; } = "M";
	public string? FormaPago { get; set; }
	public int? GefId { get; set; }
	public string? TipoCuenta { get; set; }
	public string? NumeroCuenta { get; set; }
	// Datos laborales para el IGSS y el libro de salarios (script 49).
	// SucId = centro de trabajo; Jornada D/M/N; TiempoContrato TC/TP.
	public int? SucId { get; set; }
	public string? Nacionalidad { get; set; }
	public string Jornada { get; set; } = "D";
	public string TiempoContrato { get; set; } = "TC";
	public int? FolioLibroSalarios { get; set; }
	public string NombreCompleto => string.Join(" ", new[] { PrimerNombre, SegundoNombre, PrimerApellido, SegundoApellido }.Where(p => !string.IsNullOrWhiteSpace(p)));
}

public sealed class HistorialPlaza
{
	public int IdHistorialPlaza { get; set; }
	public int IdPlaza { get; set; }
	public string Plaza { get; set; } = "";
	public DateTime FechaDel { get; set; }
	public DateTime? FechaAl { get; set; }
	public decimal Salario { get; set; }
}

public sealed class TipoMovimientoNomina
{
	public int IdTipoMovimientoNomina { get; set; }
	public string Codigo { get; set; } = "";
	public string Descripcion { get; set; } = "";
	// I = ingreso (suma), D = descuento (resta)
	public string Naturaleza { get; set; } = "I";
	// S = salario base prorrateado, F = monto fijo, P = porcentaje de la base, M = manual
	public string FormaCalculo { get; set; } = "M";
	public decimal Valor { get; set; }
	public bool EsAutomatico { get; set; }
	public bool EsBaseCalculo { get; set; }
	public short Orden { get; set; } = 100;
	public int? CtaId { get; set; }
	public string? CtaCodigo { get; set; }
	public string? CtaNombre { get; set; }
	public string Estado { get; set; } = "A";
	// Columna del libro de salarios (ORDINARIO, EXTRAORDINARIO, IGSS...).
	public string? ColumnaLibro { get; set; }
}

public sealed class MovimientoNomina
{
	public int IdMovimientoNomina { get; set; }
	public int IdEmpleado { get; set; }
	public string CodigoEmpleado { get; set; } = "";
	public string Empleado { get; set; } = "";
	public int IdTipoMovimientoNomina { get; set; }
	public string TipoMovimiento { get; set; } = "";
	public string Naturaleza { get; set; } = "I";
	public string? Descripcion { get; set; }
	public decimal Monto { get; set; }
	public DateTime FechaAplicacion { get; set; }
	public int? IdNomina { get; set; }
	public string? Nomina { get; set; }
	public string Estado { get; set; } = "A";
	public decimal? Horas { get; set; }
}

public sealed class Nomina
{
	public int IdNomina { get; set; }
	public int CiaId { get; set; }
	public string CiaNombreComercial { get; set; } = "";
	public string Descripcion { get; set; } = "";
	// S = semanal, Q = quincenal, M = mensual
	public string TipoPeriodo { get; set; } = "M";
	// O = ordinaria, A = aguinaldo, B = bono 14
	public string Clase { get; set; } = "O";
	public DateTime FechaDel { get; set; }
	public DateTime FechaAl { get; set; }
	public DateTime? FechaPago { get; set; }
	public decimal TotalIngresos { get; set; }
	public decimal TotalDescuentos { get; set; }
	public decimal TotalLiquido { get; set; }
	// IGSS patronal + IRTRA + INTECAP
	public decimal TotalPatronal { get; set; }
	// B = borrador, C = calculada, A = aprobada, N = anulada
	public string Estado { get; set; } = "B";
	public DateTime? FechaCalculo { get; set; }
	public DateTime? FechaAprobacion { get; set; }
	public int CantidadEmpleados { get; set; }
	public decimal TotalPagado { get; set; }
	public int PendientesPago { get; set; }
}

public sealed class NominaEmpleado
{
	public int IdNominaEmpleado { get; set; }
	public int IdEmpleado { get; set; }
	public string CodigoEmpleado { get; set; } = "";
	public string Empleado { get; set; } = "";
	public decimal SalarioBase { get; set; }
	public decimal DiasLaborados { get; set; }
	public decimal TotalIngresos { get; set; }
	public decimal TotalDescuentos { get; set; }
	public decimal Liquido { get; set; }
	public string? Departamento { get; set; }
	public string? FormaPago { get; set; }
	public string? Banco { get; set; }
	public string? TipoCuenta { get; set; }
	public string? NumeroCuenta { get; set; }
	public int? IdNominaPago { get; set; }
	public string? NumeroCheque { get; set; }
	public string? TipoPago { get; set; }
	public DateTime? FechaPago { get; set; }
	public string? CentroTrabajo { get; set; }
	public decimal BaseIgss { get; set; }
	public decimal IgssPatronal { get; set; }
	public decimal Irtra { get; set; }
	public decimal Intecap { get; set; }
	public decimal ProvAguinaldo { get; set; }
	public decimal ProvBono14 { get; set; }
}

public sealed class PeriodoSugerido
{
	public DateTime FechaDel { get; set; }
	public DateTime FechaAl { get; set; }
	public DateTime FechaPago { get; set; }
	public string Descripcion { get; set; } = "";
}

// Lote de pago de una nómina: T = transferencias, C = cheques.
public sealed class NominaPago
{
	public int IdNominaPago { get; set; }
	public string Tipo { get; set; } = "T";
	public DateTime FechaPago { get; set; }
	public decimal Monto { get; set; }
	public int Empleados { get; set; }
	public string? Referencia { get; set; }
	public string Estado { get; set; } = "A";
	public string? MotivoAnulacion { get; set; }
	public string Cuenta { get; set; } = "";
	public string? Usuario { get; set; }
}

public sealed class TransferenciaNomina
{
	public string? BancoCodigo { get; set; }
	public string? Banco { get; set; }
	public string TipoCuenta { get; set; } = "";
	public string? NumeroCuenta { get; set; }
	public string CodigoEmpleado { get; set; } = "";
	public string Empleado { get; set; } = "";
	public string? NumeroDocumento { get; set; }
	public decimal Monto { get; set; }
	public string Nomina { get; set; } = "";
	public DateTime FechaPago { get; set; }
	public string? Referencia { get; set; }
	public string CuentaOrigen { get; set; } = "";
}

public sealed class NominaDetalle
{
	public int IdNominaDetalle { get; set; }
	public int IdTipoMovimientoNomina { get; set; }
	public string Codigo { get; set; } = "";
	public string Naturaleza { get; set; } = "I";
	public string? Descripcion { get; set; }
	public decimal Monto { get; set; }
	public decimal? Horas { get; set; }
}

public sealed class UnidadOrganizativaNodo
{
	public int IdUnidadOrganizativa { get; set; }
	public int? IdUnidadPadre { get; set; }
	public string Descripcion { get; set; } = "";
	public string Estado { get; set; } = "A";
	public short Orden { get; set; }
	public int Nivel { get; set; }
	public int CantidadHijos { get; set; }
	public int CantidadDepartamentos { get; set; }
}

// Nodo del organigrama: U = unidad, D = departamento, P = plaza.
public sealed class OrganigramaNodo
{
	public string Clave { get; set; } = "";
	public string? ClavePadre { get; set; }
	public string Tipo { get; set; } = "U";
	public string Descripcion { get; set; } = "";
	public string? Detalle { get; set; }
	public short Orden { get; set; }
	public string Estado { get; set; } = "A";
}
