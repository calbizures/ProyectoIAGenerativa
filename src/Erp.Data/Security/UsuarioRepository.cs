using System.Data;
using Dapper;

namespace Erp.Data.Security;

public sealed class UsuarioRepository(IDbConnectionFactory connectionFactory) : IUsuarioRepository
{
	public async Task<int> InsertarAsync(string codigo, string usuario, string password, string? email, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@usu_codigo", codigo);
		parametros.Add("@usu_usuario", usuario);
		parametros.Add("@usu_password", password);
		parametros.Add("@usu_email", email);
		parametros.Add("@usu_id_accion", usuarioAccionId);
		parametros.Add("@usu_id", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.sp_usuario_insertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@usu_id");
	}

	public async Task ActualizarAsync(int usuId, string usuario, string? email, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			usu_id = usuId,
			usu_usuario = usuario,
			usu_email = email,
			usu_id_accion = usuarioAccionId
		};
		await connection.ExecuteAsync("dbo.sp_usuario_actualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int usuId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { usu_id = usuId, usu_id_accion = usuarioAccionId };
		await connection.ExecuteAsync("dbo.sp_usuario_eliminar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task CambiarPasswordAsync(int usuId, string passwordActual, string passwordNuevo)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			usu_id = usuId,
			password_actual = passwordActual,
			password_nuevo = passwordNuevo
		};
		await connection.ExecuteAsync("dbo.sp_usuario_cambiar_password", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<Usuario>> ConsultarAsync(string? usuario, string? estado, int pagina, int tamanioPagina)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			usu_usuario = usuario,
			usu_estado = estado,
			pagina,
			tamanio_pagina = tamanioPagina
		};
		var filas = await connection.QueryAsync<Usuario>("dbo.sp_usuario_consultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<(Usuario? Usuario, IReadOnlyList<UsuarioRol> Roles)> ConsultarPorIdAsync(int usuId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var multi = await connection.QueryMultipleAsync(
			"dbo.sp_usuario_consultar_por_id",
			new { usu_id = usuId },
			commandType: CommandType.StoredProcedure);

		var usuarioEncontrado = await multi.ReadFirstOrDefaultAsync<Usuario>();
		var roles = (await multi.ReadAsync<UsuarioRol>()).ToList();
		return (usuarioEncontrado, roles);
	}

	public async Task AsignarRolAsync(int usuId, int rolId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { usu_id = usuId, rol_id = rolId, usu_id_accion = usuarioAccionId };
		await connection.ExecuteAsync("dbo.sp_usuario_asignar_rol", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task RevocarRolAsync(int usuId, int rolId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { usu_id = usuId, rol_id = rolId };
		await connection.ExecuteAsync("dbo.sp_usuario_revocar_rol", parametros, commandType: CommandType.StoredProcedure);
	}
}
