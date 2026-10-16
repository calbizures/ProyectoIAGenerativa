using System.Data;
using Dapper;

namespace Erp.Data.Inventario;

public sealed class ProductoCaracteristicaRepository(IDbConnectionFactory connectionFactory) : IProductoCaracteristicaRepository
{
	public async Task<int> InsertarAsync(int proId, int ptcId, string valor, string? descripcion, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@pro_id", proId);
		parametros.Add("@ptc_id", ptcId);
		parametros.Add("@pca_valor", valor);
		parametros.Add("@pca_descripcion", descripcion);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@pca_id", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.paProductoCaracteristicaInsertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@pca_id");
	}

	public async Task ActualizarAsync(int pcaId, string valor, string? descripcion, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { pca_id = pcaId, pca_valor = valor, pca_descripcion = descripcion, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paProductoCaracteristicaActualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int pcaId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paProductoCaracteristicaEliminar", new { pca_id = pcaId }, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<ProductoCaracteristica>> ConsultarAsync(int? proId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<ProductoCaracteristica>(
			"dbo.paProductoCaracteristicaConsultar", new { pro_id = proId }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<IReadOnlyList<ProductoTipoCaracteristica>> ConsultarTiposAsync(string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<ProductoTipoCaracteristica>(
			"dbo.paProductoTipoCaracteristicaConsultar", new { ptc_estado = estado }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> InsertarTipoAsync(string codigo, string descripcion, int orden, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@ptc_codigo", codigo);
		parametros.Add("@ptc_descripcion", descripcion);
		parametros.Add("@ptc_orden", orden);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@ptc_id", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.paProductoTipoCaracteristicaInsertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@ptc_id");
	}

	public async Task ActualizarTipoAsync(int ptcId, string codigo, string descripcion, int orden, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { ptc_id = ptcId, ptc_codigo = codigo, ptc_descripcion = descripcion, ptc_orden = orden, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paProductoTipoCaracteristicaActualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarTipoAsync(int ptcId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { ptc_id = ptcId, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paProductoTipoCaracteristicaEliminar", parametros, commandType: CommandType.StoredProcedure);
	}
}
