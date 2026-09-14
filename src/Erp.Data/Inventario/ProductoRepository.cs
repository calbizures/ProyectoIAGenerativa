using System.Data;
using Dapper;

namespace Erp.Data.Inventario;

public sealed class ProductoRepository(IDbConnectionFactory connectionFactory) : IProductoRepository
{
	public async Task<int> InsertarAsync(string codigo, string descripcion, int prtId, string tipoItem, bool manejaExistencia, int? idPadre, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@pro_codigo", codigo);
		parametros.Add("@pro_descripcion", descripcion);
		parametros.Add("@prt_id", prtId);
		parametros.Add("@pro_tipo_item", tipoItem);
		parametros.Add("@pro_maneja_existencia", manejaExistencia);
		parametros.Add("@pro_id_padre", idPadre);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@pro_id", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.sp_producto_insertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@pro_id");
	}

	public async Task ActualizarAsync(int proId, string codigo, string descripcion, int prtId, string tipoItem, bool manejaExistencia, int? idPadre, decimal? porcentajeRentabilidad, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			pro_id = proId,
			pro_codigo = codigo,
			pro_descripcion = descripcion,
			prt_id = prtId,
			pro_tipo_item = tipoItem,
			pro_maneja_existencia = manejaExistencia,
			pro_id_padre = idPadre,
			pro_ptje_rentabilidad = porcentajeRentabilidad,
			usu_id = usuarioAccionId
		};
		await connection.ExecuteAsync("dbo.sp_producto_actualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int proId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { pro_id = proId, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.sp_producto_eliminar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<Producto>> ConsultarAsync(string? codigo, string? descripcion, int? prtId, string? estado, int pagina, int tamanioPagina)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			pro_codigo = codigo,
			pro_descripcion = descripcion,
			prt_id = prtId,
			pro_estado = estado,
			pagina,
			tamanio_pagina = tamanioPagina
		};
		var filas = await connection.QueryAsync<Producto>("dbo.sp_producto_consultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<(Producto? Producto, IReadOnlyList<ProductoExistenciaBodega> Existencias)> ConsultarPorIdAsync(int proId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var multi = await connection.QueryMultipleAsync(
			"dbo.sp_producto_consultar_por_id",
			new { pro_id = proId },
			commandType: CommandType.StoredProcedure);

		var productoEncontrado = await multi.ReadFirstOrDefaultAsync<Producto>();
		var existencias = (await multi.ReadAsync<ProductoExistenciaBodega>()).ToList();
		return (productoEncontrado, existencias);
	}

	// No hay un procedimiento dedicado para esta lectura simple (catálogo sin
	// lógica de negocio que auditar); se consulta la tabla directamente, igual
	// que sp_rol.ConsultarPermisosAsignadosAsync.
	public async Task<IReadOnlyList<ProductoTipo>> ConsultarTiposAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<ProductoTipo>(
			"SELECT prt_id, prt_codigo, prt_descripcion FROM dbo.inv_producto_tipo WHERE prt_estado = 'A' ORDER BY prt_descripcion");
		return filas.ToList();
	}
}
