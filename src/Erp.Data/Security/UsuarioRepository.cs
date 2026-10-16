using System.Data;
using Dapper;

namespace Erp.Data.Security;

public sealed class UsuarioRepository(IDbConnectionFactory connectionFactory) : IUsuarioRepository
{
	public async Task<int> InsertarAsync(string codigo, string usuario, string password, string? email, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@UsuCodigo", codigo);
		parametros.Add("@UsuUsuario", usuario);
		parametros.Add("@UsuPassword", password);
		parametros.Add("@UsuEmail", email);
		parametros.Add("@UsuIdAccion", usuarioAccionId);
		parametros.Add("@UsuId", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.paUsuarioInsertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@UsuId");
	}

	public async Task ActualizarAsync(int usuId, string usuario, string? email, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			UsuId = usuId,
			UsuUsuario = usuario,
			UsuEmail = email,
			UsuIdAccion = usuarioAccionId
		};
		await connection.ExecuteAsync("dbo.paUsuarioActualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int usuId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { UsuId = usuId, UsuIdAccion = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paUsuarioEliminar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task ActivarAsync(int usuId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { usu_id = usuId, usu_id_accion = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paUsuarioActivar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task CambiarPasswordAsync(int usuId, string passwordActual, string passwordNuevo)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			UsuId = usuId,
			PasswordActual = passwordActual,
			PasswordNuevo = passwordNuevo
		};
		await connection.ExecuteAsync("dbo.paUsuarioPasswordCambiar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<Usuario>> ConsultarAsync(string? usuario, string? estado, int pagina, int tamanioPagina)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			UsuUsuario = usuario,
			UsuEstado = estado,
			Pagina = pagina,
			TamanioPagina = tamanioPagina
		};
		var filas = await connection.QueryAsync<Usuario>("dbo.paUsuarioConsultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<(Usuario? Usuario, IReadOnlyList<UsuarioRol> Roles)> ConsultarPorIdAsync(int usuId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var multi = await connection.QueryMultipleAsync(
			"dbo.paUsuarioConsultarPorId",
			new { UsuId = usuId },
			commandType: CommandType.StoredProcedure);

		var usuarioEncontrado = await multi.ReadFirstOrDefaultAsync<Usuario>();
		var roles = (await multi.ReadAsync<UsuarioRol>()).ToList();
		return (usuarioEncontrado, roles);
	}

	public async Task AsignarRolAsync(int usuId, int rolId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { UsuId = usuId, RolId = rolId, UsuIdAccion = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paUsuarioRolAsignar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task RevocarRolAsync(int usuId, int rolId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { UsuId = usuId, RolId = rolId };
		await connection.ExecuteAsync("dbo.paUsuarioRolRevocar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<Sucursal>> ConsultarSucursalesAsignadasAsync(int usuId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<Sucursal>(
			"dbo.paUsuarioSucursalConsultar", new { usu_id = usuId }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task AsignarSucursalAsync(int usuId, int sucId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { usu_id = usuId, suc_id = sucId, usu_id_accion = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paUsuarioSucursalAsignar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task RevocarSucursalAsync(int usuId, int sucId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { usu_id = usuId, suc_id = sucId };
		await connection.ExecuteAsync("dbo.paUsuarioSucursalRevocar", parametros, commandType: CommandType.StoredProcedure);
	}
}
