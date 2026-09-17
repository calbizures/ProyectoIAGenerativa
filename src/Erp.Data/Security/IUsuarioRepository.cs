namespace Erp.Data.Security;

public interface IUsuarioRepository
{
	Task<int> InsertarAsync(string codigo, string usuario, string password, string? email, int? usuarioAccionId);
	Task ActualizarAsync(int usuId, string usuario, string? email, int? usuarioAccionId);
	Task EliminarAsync(int usuId, int? usuarioAccionId);
	Task ActivarAsync(int usuId, int? usuarioAccionId);
	Task CambiarPasswordAsync(int usuId, string passwordActual, string passwordNuevo);
	Task<IReadOnlyList<Usuario>> ConsultarAsync(string? usuario, string? estado, int pagina, int tamanioPagina);
	Task<(Usuario? Usuario, IReadOnlyList<UsuarioRol> Roles)> ConsultarPorIdAsync(int usuId);
	Task AsignarRolAsync(int usuId, int rolId, int? usuarioAccionId);
	Task RevocarRolAsync(int usuId, int rolId);
}
