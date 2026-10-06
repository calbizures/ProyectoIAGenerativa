using System.Data;
using Dapper;

namespace Erp.Data.Inventario;

public sealed class ProductoRepository(IDbConnectionFactory connectionFactory) : IProductoRepository
{
	public async Task<int> InsertarAsync(string codigo, string descripcion, int prtId, string tipoItem, bool manejaExistencia, int? idPadre, int? usuarioAccionId, int? umeId = null)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@ProCodigo", codigo);
		parametros.Add("@ProDescripcion", descripcion);
		parametros.Add("@PrtId", prtId);
		parametros.Add("@ProTipoItem", tipoItem);
		parametros.Add("@ProManejaExistencia", manejaExistencia);
		parametros.Add("@ProIdPadre", idPadre);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@ProId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		parametros.Add("@UmeId", umeId);

		await connection.ExecuteAsync("dbo.paProductoInsertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@ProId");
	}

	public async Task ActualizarAsync(int proId, string codigo, string descripcion, int prtId, string tipoItem, bool manejaExistencia, int? idPadre, decimal? porcentajeRentabilidad, int? usuarioAccionId, int? umeId = null)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			ProId = proId,
			ProCodigo = codigo,
			ProDescripcion = descripcion,
			PrtId = prtId,
			ProTipoItem = tipoItem,
			ProManejaExistencia = manejaExistencia,
			ProIdPadre = idPadre,
			ProPtjeRentabilidad = porcentajeRentabilidad,
			UsuId = usuarioAccionId,
			UmeId = umeId
		};
		await connection.ExecuteAsync("dbo.paProductoActualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int proId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { ProId = proId, UsuId = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paProductoEliminar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<Producto>> ConsultarAsync(string? codigo, string? descripcion, int? prtId, string? estado, int pagina, int tamanioPagina)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			ProCodigo = codigo,
			ProDescripcion = descripcion,
			PrtId = prtId,
			ProEstado = estado,
			Pagina = pagina,
			TamanioPagina = tamanioPagina
		};
		var filas = await connection.QueryAsync<Producto>("dbo.paProductoConsultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<(Producto? Producto, IReadOnlyList<ProductoExistenciaBodega> Existencias)> ConsultarPorIdAsync(int proId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var multi = await connection.QueryMultipleAsync(
			"dbo.paProductoConsultarPorId",
			new { ProId = proId },
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

	public async Task<IReadOnlyList<ProductoExistenciaBodega>> ConsultarExistenciasAsync(int? proId, int? bodId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { pro_id = proId, bod_id = bodId };
		var filas = await connection.QueryAsync<ProductoExistenciaBodega>(
			"dbo.paProductoExistenciaConsultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}
}
