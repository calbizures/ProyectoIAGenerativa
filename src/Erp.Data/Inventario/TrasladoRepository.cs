using System.Data;
using Dapper;

namespace Erp.Data.Inventario;

public sealed class TrasladoRepository(IDbConnectionFactory connectionFactory) : ITrasladoRepository
{
	public async Task<IReadOnlyList<Traslado>> ConsultarAsync(int? sucId, string? estado, DateTime? desde, DateTime? hasta)
	{
		using var connection = connectionFactory.CreateConnection();
		return (await connection.QueryAsync<Traslado>("dbo.paInvTrasladoConsultar",
			new { SucId = sucId, Estado = estado, Desde = desde?.Date, Hasta = hasta?.Date }, commandType: CommandType.StoredProcedure)).ToList();
	}

	public async Task<IReadOnlyList<TrasladoLinea>> ConsultarLineasAsync(int traId)
	{
		using var connection = connectionFactory.CreateConnection();
		return (await connection.QueryAsync<TrasladoLinea>("dbo.paInvTrasladoDetalleConsultar", new { TraId = traId },
			commandType: CommandType.StoredProcedure)).ToList();
	}

	public async Task<IReadOnlyList<ProductoTrasladable>> ConsultarProductosAsync(int bodId, string? texto)
	{
		using var connection = connectionFactory.CreateConnection();
		return (await connection.QueryAsync<ProductoTrasladable>("dbo.paInvTrasladoProductosConsultar",
			new { BodId = bodId, Texto = string.IsNullOrWhiteSpace(texto) ? null : texto.Trim() }, commandType: CommandType.StoredProcedure)).ToList();
	}

	public async Task<int> EnviarAsync(int bodIdOrigen, int bodIdDestino, string? observaciones, IReadOnlyList<(int ProId, decimal Cantidad)> lineas, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters(new { BodIdOrigen = bodIdOrigen, BodIdDestino = bodIdDestino, Observaciones = observaciones, UsuId = usuarioAccionId });
		parametros.Add("@Lineas", TablaLineas(lineas).AsTableValuedParameter("dbo.inv_traslado_linea_type"));
		parametros.Add("@TraId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paInvTrasladoEnviar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@TraId");
	}

	public async Task RecibirAsync(int traId, IReadOnlyList<(int ProId, decimal Cantidad)> recibidas, string diferencia, string? nota, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters(new { TraId = traId, Diferencia = diferencia, Nota = nota, UsuId = usuarioAccionId });
		parametros.Add("@Lineas", TablaLineas(recibidas).AsTableValuedParameter("dbo.inv_traslado_linea_type"));
		await connection.ExecuteAsync("dbo.paInvTrasladoRecibir", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task DevolverAsync(int traId, string motivo, bool esCancelacion, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paInvTrasladoDevolver",
			new { TraId = traId, Motivo = motivo, EsCancelacion = esCancelacion, UsuId = usuarioAccionId }, commandType: CommandType.StoredProcedure);
	}

	// Mismo orden de columnas que dbo.inv_traslado_linea_type (45_traslados_bodegas.sql).
	private static DataTable TablaLineas(IReadOnlyList<(int ProId, decimal Cantidad)> lineas)
	{
		var tabla = new DataTable();
		tabla.Columns.Add("pro_id", typeof(int));
		tabla.Columns.Add("cantidad", typeof(decimal));
		foreach (var (proId, cantidad) in lineas) tabla.Rows.Add(proId, cantidad);
		return tabla;
	}
}
