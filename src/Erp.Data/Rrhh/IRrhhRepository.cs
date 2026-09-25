namespace Erp.Data.Rrhh;

public interface IRrhhRepository
{
	// Catálogos simples (el nombre del catálogo lo valida paRrhhCatalogoTabla)
	Task<IReadOnlyList<CatalogoRrhh>> ConsultarCatalogoAsync(string catalogo, bool soloActivos);
	Task<int> GuardarCatalogoAsync(string catalogo, int? id, string descripcion, int? usuarioAccionId);
	Task CambiarEstadoCatalogoAsync(string catalogo, int id, string estado, int? usuarioAccionId);

	// Estructura organizativa
	Task<IReadOnlyList<Departamento>> ConsultarDepartamentosAsync(bool soloActivos);
	Task<int> GuardarDepartamentoAsync(Departamento departamento, int? usuarioAccionId);
	Task<IReadOnlyList<Puesto>> ConsultarPuestosAsync(bool soloActivos);
	Task<int> GuardarPuestoAsync(Puesto puesto, int? usuarioAccionId);
	Task<IReadOnlyList<Plaza>> ConsultarPlazasAsync(bool soloActivos);
	Task<int> GuardarPlazaAsync(Plaza plaza, int? usuarioAccionId);

	// Empleados
	Task<IReadOnlyList<EmpleadoResumen>> ConsultarEmpleadosAsync(string? filtro, string? estado);
	Task<(Empleado? Empleado, IReadOnlyList<HistorialPlaza> Historial)> ConsultarEmpleadoPorIdAsync(int idEmpleado);
	Task<int> GuardarEmpleadoAsync(Empleado empleado, int? usuarioAccionId);
	Task DarBajaEmpleadoAsync(int idEmpleado, DateTime fechaBaja, int? usuarioAccionId);
	Task ReactivarEmpleadoAsync(int idEmpleado, int? usuarioAccionId);
	Task AsignarUsuarioAsync(int idEmpleado, int? usuIdAsignado, int? usuarioAccionId);
	Task AsignarVendedorAsync(int idEmpleado, int? pveId, int? usuarioAccionId);

	// Tipos de movimiento y movimientos manuales
	Task<IReadOnlyList<TipoMovimientoNomina>> ConsultarTiposMovimientoAsync(bool soloActivos);
	Task<int> GuardarTipoMovimientoAsync(TipoMovimientoNomina tipo, int? usuarioAccionId);
	Task<IReadOnlyList<MovimientoNomina>> ConsultarMovimientosAsync(int? idEmpleado, DateTime? fechaDel, DateTime? fechaAl, bool soloPendientes);
	Task<int> GuardarMovimientoAsync(int? idMovimiento, int idEmpleado, int idTipoMovimiento, string? descripcion, decimal monto, DateTime fechaAplicacion, int? usuarioAccionId);
	Task AnularMovimientoAsync(int idMovimiento, int? usuarioAccionId);

	// Nómina
	Task<IReadOnlyList<Nomina>> ConsultarNominasAsync(int? ciaId);
	Task<int> CrearNominaAsync(int ciaId, string descripcion, string tipoPeriodo, DateTime fechaDel, DateTime fechaAl, DateTime? fechaPago, int? usuarioAccionId);
	Task CalcularNominaAsync(int idNomina, int? usuarioAccionId);
	Task AprobarNominaAsync(int idNomina, int? usuarioAccionId);
	Task AnularNominaAsync(int idNomina, int? usuarioAccionId);
	Task<IReadOnlyList<NominaEmpleado>> ConsultarNominaEmpleadosAsync(int idNomina);
	Task<IReadOnlyList<NominaDetalle>> ConsultarNominaDetalleAsync(int idNominaEmpleado);
}
