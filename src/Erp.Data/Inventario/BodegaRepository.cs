using System.Data;
using Dapper;

namespace Erp.Data.Inventario;

// Bodegas y unidades de medida (catálogos de inventario).
public sealed class BodegaRepository(IDbConnectionFactory connectionFactory) : IBodegaRepository
{
	public async Task<IReadOnlyList<Bodega>> ConsultarAsync(int? sucId, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { SucId = sucId, BodEstado = estado };
		var filas = await connection.QueryAsync<Bodega>("dbo.paBodegaListar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<IReadOnlyList<BodegaDetalle>> ConsultarDetalleAsync(int? sucId, bool soloActivas)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<BodegaDetalle>("dbo.paBodegaConsultar",
			new { SucId = sucId, SoloActivas = soloActivas }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> GuardarAsync(int? bodId, int sucId, string codigo, string descripcion, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@BodId", bodId);
		parametros.Add("@SucId", sucId);
		parametros.Add("@Codigo", codigo);
		parametros.Add("@Descripcion", descripcion);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@IdResultado", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paBodegaGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@IdResultado");
	}

	public async Task CambiarEstadoAsync(int bodId, string estado, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paBodegaCambiarEstado",
			new { BodId = bodId, Estado = estado, UsuId = usuarioAccionId }, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<UnidadMedida>> ConsultarUnidadesAsync(bool soloActivas)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<UnidadMedida>("dbo.paUnidadMedidaConsultar",
			new { SoloActivas = soloActivas }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> GuardarUnidadAsync(int? umeId, string codigo, string descripcion, string estado, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@UmeId", umeId);
		parametros.Add("@Codigo", codigo);
		parametros.Add("@Descripcion", descripcion);
		parametros.Add("@Estado", estado);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@IdResultado", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paUnidadMedidaGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@IdResultado");
	}

	public async Task EliminarUnidadAsync(int umeId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paUnidadMedidaEliminar", new { UmeId = umeId }, commandType: CommandType.StoredProcedure);
	}
}
