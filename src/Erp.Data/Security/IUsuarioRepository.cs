namespace Erp.Data.Security;

public interface IUsuarioRepository
{
	Task<int> InsertarAsync(string codigo, string usuario, string password, string? email, int? usuarioAccionId, bool cambiarPassword = false);
	Task ActualizarAsync(int usuId, string usuario, string? email, int? usuarioAccionId);
	Task EliminarAsync(int usuId, int? usuarioAccionId);
	Task ActivarAsync(int usuId, int? usuarioAccionId);
	Task CambiarPasswordAsync(int usuId, string passwordActual, string passwordNuevo);
	Task RestablecerPasswordAsync(int usuId, string passwordNuevo, int? usuarioAccionId);
	Task DesbloquearAsync(int usuId, int? usuarioAccionId);
	Task<IReadOnlyList<Usuario>> ConsultarAsync(string? usuario, string? estado, int pagina, int tamanioPagina);
	Task<(Usuario? Usuario, IReadOnlyList<UsuarioRol> Roles)> ConsultarPorIdAsync(int usuId);
	Task AsignarRolAsync(int usuId, int rolId, int? usuarioAccionId);
	Task RevocarRolAsync(int usuId, int rolId, int? usuarioAccionId);
	Task<IReadOnlyList<Sucursal>> ConsultarSucursalesAsignadasAsync(int usuId);
	Task AsignarSucursalAsync(int usuId, int sucId, int? usuarioAccionId);
	Task RevocarSucursalAsync(int usuId, int sucId);
}
