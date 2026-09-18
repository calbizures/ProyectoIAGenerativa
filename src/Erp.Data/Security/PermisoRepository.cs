using System.Data;
using Dapper;

namespace Erp.Data.Security;

public sealed class PermisoRepository(IDbConnectionFactory connectionFactory) : IPermisoRepository
{
	public async Task<int> InsertarAsync(string modulo, string codigo, string? descripcion, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@per_modulo", modulo);
		parametros.Add("@per_codigo", codigo);
		parametros.Add("@per_descripcion", descripcion);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@per_id", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.sp_permiso_insertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@per_id");
	}

	public async Task<IReadOnlyList<Permiso>> ConsultarAsync(string? modulo, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<Permiso>(
			"dbo.sp_permiso_consultar",
			new { per_modulo = modulo, per_estado = estado },
			commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}
}
