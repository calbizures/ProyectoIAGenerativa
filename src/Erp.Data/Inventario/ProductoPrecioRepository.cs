using System.Data;
using Dapper;

namespace Erp.Data.Inventario;

public sealed class ProductoPrecioRepository(IDbConnectionFactory connectionFactory) : IProductoPrecioRepository
{
	public async Task<int> InsertarAsync(int proId, int bodId, int monId, decimal precioUnitarioVenta, string? descripcion,
		DateTime vigenciaDesde, DateTime? vigenciaHasta, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@pro_id", proId);
		parametros.Add("@bod_id", bodId);
		parametros.Add("@mon_id", monId);
		parametros.Add("@ppr_precio_unitario_venta", precioUnitarioVenta);
		parametros.Add("@ppr_descripcion", descripcion);
		parametros.Add("@ppr_vigencia_desde", vigenciaDesde);
		parametros.Add("@ppr_vigencia_hasta", vigenciaHasta);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@ppr_id", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.sp_producto_precio_insertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@ppr_id");
	}

	public async Task ActualizarAsync(int pprId, int bodId, int monId, decimal precioUnitarioVenta, string? descripcion,
		DateTime vigenciaDesde, DateTime? vigenciaHasta, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			ppr_id = pprId,
			bod_id = bodId,
			mon_id = monId,
			ppr_precio_unitario_venta = precioUnitarioVenta,
			ppr_descripcion = descripcion,
			ppr_vigencia_desde = vigenciaDesde,
			ppr_vigencia_hasta = vigenciaHasta,
			usu_id = usuarioAccionId
		};
		await connection.ExecuteAsync("dbo.sp_producto_precio_actualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int pprId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { ppr_id = pprId, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.sp_producto_precio_eliminar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<ProductoPrecio>> ConsultarAsync(int? proId, int? bodId, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { pro_id = proId, bod_id = bodId, ppr_estado = estado };
		var filas = await connection.QueryAsync<ProductoPrecio>(
			"dbo.sp_producto_precio_consultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}
}
