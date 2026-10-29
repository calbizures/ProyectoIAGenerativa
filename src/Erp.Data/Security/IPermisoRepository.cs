namespace Erp.Data.Security;

public interface IPermisoRepository
{
	Task<int> InsertarAsync(string modulo, string codigo, string? descripcion, int? usuarioAccionId);
	Task<IReadOnlyList<Permiso>> ConsultarAsync(string? modulo, string? estado, string? texto = null);
	Task ActualizarAsync(int perId, string modulo, string? descripcion, string estado, int? usuarioAccionId);
	Task EliminarAsync(int perId);
	Task<PermisoDetalle?> ConsultarDetalleAsync(int perId);
}
