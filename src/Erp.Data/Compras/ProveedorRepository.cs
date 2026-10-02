using System.Data;
using Dapper;

namespace Erp.Data.Compras;

public sealed class ProveedorRepository(IDbConnectionFactory connectionFactory) : IProveedorRepository
{
	public async Task<int> InsertarAsync(string codigo, string nombreComercial, string? nit, string? contacto, string? direccion, string? telefonoOficina, string? emailEmpresa, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@prv_codigo", codigo);
		parametros.Add("@prv_nombre_comercial", nombreComercial);
		parametros.Add("@prv_nit", nit);
		parametros.Add("@prv_contacto", contacto);
		parametros.Add("@prv_direccion", direccion);
		parametros.Add("@prv_telefono_oficina", telefonoOficina);
		parametros.Add("@prv_email_empresa", emailEmpresa);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@prv_id", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.sp_proveedor_insertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@prv_id");
	}

	public async Task ActualizarAsync(int prvId, string nombreComercial, string? nit, string? contacto, string? direccion, string? telefonoOficina, string? emailEmpresa, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			prv_id = prvId,
			prv_nombre_comercial = nombreComercial,
			prv_nit = nit,
			prv_contacto = contacto,
			prv_direccion = direccion,
			prv_telefono_oficina = telefonoOficina,
			prv_email_empresa = emailEmpresa,
			usu_id = usuarioAccionId
		};
		await connection.ExecuteAsync("dbo.sp_proveedor_actualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int prvId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { prv_id = prvId, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.sp_proveedor_eliminar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<Proveedor>> ConsultarAsync(string? texto, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { texto, prv_estado = estado };
		var filas = await connection.QueryAsync<Proveedor>("dbo.sp_proveedor_consultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<Proveedor?> ConsultarPorIdAsync(int prvId)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QueryFirstOrDefaultAsync<Proveedor>(
			"dbo.sp_proveedor_consultar_por_id", new { prv_id = prvId }, commandType: CommandType.StoredProcedure);
	}
}
