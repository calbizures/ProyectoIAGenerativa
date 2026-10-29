using System.Data;
using Dapper;

namespace Erp.Data.Inventario;

public sealed class ReordenRepository(IDbConnectionFactory connectionFactory) : IReordenRepository
{
	public async Task<IReadOnlyList<RotacionInventarioFila>> ConsultarRotacionAsync(int? bodId, int? sucId, int? dias, DateTime? hasta)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<RotacionInventarioFila>("dbo.paInventarioRotacionConsultar",
			new { BodId = bodId, SucId = sucId, Dias = dias, Hasta = hasta }, commandType: CommandType.StoredProcedure, commandTimeout: 120);
		return filas.ToList();
	}

	public async Task<ReordenParametros?> ConsultarParametrosAsync(int ciaId)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QueryFirstOrDefaultAsync<ReordenParametros>("dbo.paReordenParametrosConsultar",
			new { CiaId = ciaId }, commandType: CommandType.StoredProcedure);
	}

	public async Task GuardarParametrosAsync(ReordenParametros parametros, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paReordenParametrosGuardar", new
		{
			parametros.CiaId,
			parametros.DiasAnalisis,
			parametros.DiasEntrega,
			parametros.DiasSeguridad,
			parametros.DiasCobertura,
			UsuId = usuarioAccionId
		}, commandType: CommandType.StoredProcedure);
	}

	public async Task GuardarDiasEntregaAsync(int pppId, int? dias, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paProductoProveedorDiasEntregaGuardar",
			new { PppId = pppId, Dias = dias, UsuId = usuarioAccionId }, commandType: CommandType.StoredProcedure);
	}
}
