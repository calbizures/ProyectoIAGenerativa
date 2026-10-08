using System.Data;
using Dapper;

namespace Erp.Data.Compras;

public sealed class ProductoProveedorRepository(IDbConnectionFactory connectionFactory) : IProductoProveedorRepository
{
	public async Task<IReadOnlyList<ProductoProveedor>> ConsultarAsync(int? prvId, int? proId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<ProductoProveedor>("dbo.paProductoProveedorConsultar",
			new { PrvId = prvId, ProId = proId }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> GuardarAsync(int? pppId, int prvId, int proId, bool preferido, string? codigoProveedor, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters(new
		{
			PppId = pppId,
			PrvId = prvId,
			ProId = proId,
			Preferido = preferido,
			CodigoProveedor = codigoProveedor,
			UsuId = usuarioAccionId
		});
		parametros.Add("@IdResultado", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paProductoProveedorGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@IdResultado");
	}

	public async Task EliminarAsync(int pppId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paProductoProveedorEliminar",
			new { PppId = pppId, UsuId = usuarioAccionId }, commandType: CommandType.StoredProcedure);
	}

	public async Task<int> RegistrarCompraAsync(int encId, bool relacionar, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QuerySingleAsync<int>("dbo.paProductoProveedorRegistrarCompra",
			new { EncId = encId, Relacionar = relacionar, UsuId = usuarioAccionId }, commandType: CommandType.StoredProcedure);
	}
}
