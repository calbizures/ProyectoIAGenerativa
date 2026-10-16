using System.Data;
using Dapper;

namespace Erp.Data.Inventario;

public sealed class InventarioFisicoRepository(IDbConnectionFactory connectionFactory) : IInventarioFisicoRepository
{
	public async Task<IReadOnlyList<TomaFisica>> ConsultarAsync(int? sucId, int? bodId, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		return (await connection.QueryAsync<TomaFisica>("dbo.paInvTomaConsultar", new { SucId = sucId, BodId = bodId, Estado = estado },
			commandType: CommandType.StoredProcedure)).ToList();
	}

	public async Task<int> CrearAsync(int bodId, DateTime fecha, string? observaciones, bool soloConExistencia, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters(new
		{
			BodId = bodId,
			Fecha = fecha.Date,
			Observaciones = observaciones,
			SoloConExistencia = soloConExistencia,
			UsuId = usuarioAccionId
		});
		parametros.Add("@IdResultado", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paInvTomaCrear", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@IdResultado");
	}

	public async Task<IReadOnlyList<TomaFisicaLinea>> ConsultarLineasAsync(int tfiId)
	{
		using var connection = connectionFactory.CreateConnection();
		return (await connection.QueryAsync<TomaFisicaLinea>("dbo.paInvTomaDetalleConsultar", new { TfiId = tfiId },
			commandType: CommandType.StoredProcedure)).ToList();
	}

	public async Task GuardarConteoAsync(int tfiId, IReadOnlyList<(int ProId, decimal? Conteo)> conteos, int? usuarioAccionId)
	{
		var tabla = new DataTable();
		tabla.Columns.Add("pro_id", typeof(int));
		tabla.Columns.Add("conteo", typeof(decimal));
		foreach (var (proId, conteo) in conteos) tabla.Rows.Add(proId, conteo is null ? DBNull.Value : conteo.Value);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paInvTomaConteoGuardar",
			new { TfiId = tfiId, Conteos = tabla.AsTableValuedParameter("dbo.inv_toma_conteo_type"), UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}

	public async Task AplicarAsync(int tfiId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paInvTomaAplicar", new { TfiId = tfiId, UsuId = usuarioAccionId }, commandType: CommandType.StoredProcedure);
	}

	public async Task AnularAsync(int tfiId, string motivo, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paInvTomaAnular", new { TfiId = tfiId, Motivo = motivo, UsuId = usuarioAccionId }, commandType: CommandType.StoredProcedure);
	}
}
