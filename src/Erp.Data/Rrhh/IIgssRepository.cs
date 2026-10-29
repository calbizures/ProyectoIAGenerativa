namespace Erp.Data.Rrhh;

public interface IIgssRepository
{
	Task<IgssCatalogos> ConsultarCatalogosAsync();
	Task<IReadOnlyList<IgssTipoPlanilla>> ConsultarTiposPlanillaAsync(int ciaId);
	Task<int> GuardarTipoPlanillaAsync(IgssTipoPlanilla tipo, int? usuarioAccionId);
	Task<(EmpleadoIgss? Empleado, IReadOnlyList<IgssAusencia> Ausencias)> ConsultarEmpleadoAsync(int idEmpleado);
	Task GuardarEmpleadoAsync(EmpleadoIgss empleado, int? usuarioAccionId);
	Task GuardarAusenciaAsync(IgssAusencia ausencia, int? usuarioAccionId);
	Task EliminarAusenciaAsync(int idAusencia);
	Task<IgssArchivoDatos> ConsultarArchivoAsync(int ciaId, int anio, int mes);
}
