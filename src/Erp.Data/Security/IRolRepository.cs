namespace Erp.Data.Security;

public interface IRolRepository
{
	Task<int> InsertarAsync(string codigo, string nombre, int? usuarioAccionId);
	Task ActualizarAsync(int rolId, string nombre, int? usuarioAccionId);
	Task EliminarAsync(int rolId, int? usuarioAccionId);
	Task<IReadOnlyList<Rol>> ConsultarAsync(string? estado);
	Task AsignarPermisoAsync(int rolId, int perId, int? usuarioAccionId);
	Task RevocarPermisoAsync(int rolId, int perId);
	Task<IReadOnlyList<int>> ConsultarPermisosAsignadosAsync(int rolId);
}
