using System.Data;
using Dapper;

namespace Erp.Data.Security;

public sealed class RolRepository(IDbConnectionFactory connectionFactory) : IRolRepository
{
	public async Task<int> InsertarAsync(string codigo, string nombre, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@RolCodigo", codigo);
		parametros.Add("@RolNombre", nombre);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@RolId", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.paRolInsertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@RolId");
	}

	public async Task ActualizarAsync(int rolId, string nombre, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { RolId = rolId, RolNombre = nombre, UsuId = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paRolActualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int rolId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { RolId = rolId, UsuId = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paRolEliminar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<Rol>> ConsultarAsync(string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<Rol>(
			"dbo.paRolConsultar", new { RolEstado = estado }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task AsignarPermisoAsync(int rolId, int perId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { RolId = rolId, PerId = perId, UsuId = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paRolPermisoAsignar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task RevocarPermisoAsync(int rolId, int perId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { RolId = rolId, PerId = perId };
		await connection.ExecuteAsync("dbo.paRolPermisoRevocar", parametros, commandType: CommandType.StoredProcedure);
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
