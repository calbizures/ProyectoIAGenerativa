using System.Data;
using Dapper;

namespace Erp.Data.Security;

public sealed class RolRepository(IDbConnectionFactory connectionFactory) : IRolRepository
{
	public async Task<int> InsertarAsync(string codigo, string nombre, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@rol_codigo", codigo);
		parametros.Add("@rol_nombre", nombre);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@rol_id", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.sp_rol_insertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@rol_id");
	}

	public async Task ActualizarAsync(int rolId, string nombre, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { rol_id = rolId, rol_nombre = nombre, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.sp_rol_actualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int rolId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { rol_id = rolId, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.sp_rol_eliminar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<Rol>> ConsultarAsync(string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<Rol>(
			"dbo.sp_rol_consultar", new { rol_estado = estado }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task AsignarPermisoAsync(int rolId, int perId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { rol_id = rolId, per_id = perId, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.sp_rol_asignar_permiso", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task RevocarPermisoAsync(int rolId, int perId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { rol_id = rolId, per_id = perId };
		await connection.ExecuteAsync("dbo.sp_rol_revocar_permiso", parametros, commandType: CommandType.StoredProcedure);
	}

	// No hay un procedimiento dedicado para esta lectura simple (sin lógica de
	// negocio que auditar); se consulta la tabla de asignación directamente.
	public async Task<IReadOnlyList<int>> ConsultarPermisosAsignadosAsync(int rolId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<int>(
			"SELECT per_id FROM dbo.sec_rol_permiso WHERE rol_id = @rol_id", new { rol_id = rolId });
		return filas.ToList();
	}
}
