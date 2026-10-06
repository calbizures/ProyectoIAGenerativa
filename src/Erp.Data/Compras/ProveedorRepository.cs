using System.Data;
using Dapper;

namespace Erp.Data.Compras;

public sealed class ProveedorRepository(IDbConnectionFactory connectionFactory) : IProveedorRepository
{
	public async Task<int> InsertarAsync(string codigo, string nombreComercial, string? nit, string? contacto, string? direccion, string? telefonoOficina, string? emailEmpresa, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@PrvCodigo", codigo);
		parametros.Add("@PrvNombreComercial", nombreComercial);
		parametros.Add("@PrvNit", nit);
		parametros.Add("@PrvContacto", contacto);
		parametros.Add("@PrvDireccion", direccion);
		parametros.Add("@PrvTelefonoOficina", telefonoOficina);
		parametros.Add("@PrvEmailEmpresa", emailEmpresa);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@PrvId", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.paProveedorInsertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@PrvId");
	}

	public async Task ActualizarAsync(int prvId, string nombreComercial, string? nit, string? contacto, string? direccion, string? telefonoOficina, string? emailEmpresa, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			PrvId = prvId,
			PrvNombreComercial = nombreComercial,
			PrvNit = nit,
			PrvContacto = contacto,
			PrvDireccion = direccion,
			PrvTelefonoOficina = telefonoOficina,
			PrvEmailEmpresa = emailEmpresa,
			UsuId = usuarioAccionId
		};
		await connection.ExecuteAsync("dbo.paProveedorActualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int prvId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { PrvId = prvId, UsuId = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paProveedorEliminar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<Proveedor>> ConsultarAsync(string? texto, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { Texto = texto, PrvEstado = estado };
		var filas = await connection.QueryAsync<Proveedor>("dbo.paProveedorConsultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<Proveedor?> ConsultarPorIdAsync(int prvId)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QueryFirstOrDefaultAsync<Proveedor>(
			"dbo.paProveedorConsultarPorId", new { PrvId = prvId }, commandType: CommandType.StoredProcedure);
	}
}
