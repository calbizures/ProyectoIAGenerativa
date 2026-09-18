using System.Data;
using Dapper;

namespace Erp.Data.Inventario;

public sealed class BodegaRepository(IDbConnectionFactory connectionFactory) : IBodegaRepository
{
	public async Task<IReadOnlyList<Bodega>> ConsultarAsync(int? sucId, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { suc_id = sucId, bod_estado = estado };
		var filas = await connection.QueryAsync<Bodega>("dbo.sp_bodega_consultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}
}
