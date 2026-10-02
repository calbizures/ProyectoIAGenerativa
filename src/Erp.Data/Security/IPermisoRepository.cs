namespace Erp.Data.Security;

public interface IPermisoRepository
{
	Task<int> InsertarAsync(string modulo, string codigo, string? descripcion, int? usuarioAccionId);
	Task<IReadOnlyList<Permiso>> ConsultarAsync(string? modulo, string? estado);
}
