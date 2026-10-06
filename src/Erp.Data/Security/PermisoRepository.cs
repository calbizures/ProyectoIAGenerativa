using System.Data;
using Dapper;

namespace Erp.Data.Security;

public sealed class PermisoRepository(IDbConnectionFactory connectionFactory) : IPermisoRepository
{
	public async Task<int> InsertarAsync(string modulo, string codigo, string? descripcion, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@PerModulo", modulo);
		parametros.Add("@PerCodigo", codigo);
		parametros.Add("@PerDescripcion", descripcion);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@PerId", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.paPermisoInsertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@PerId");
	}

	public async Task<IReadOnlyList<Permiso>> ConsultarAsync(string? modulo, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<Permiso>(
			"dbo.paPermisoConsultar",
			new { PerModulo = modulo, PerEstado = estado },
			commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}
}
