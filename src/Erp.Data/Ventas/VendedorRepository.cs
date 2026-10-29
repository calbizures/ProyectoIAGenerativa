using System.Data;
using Dapper;

namespace Erp.Data.Ventas;

// Usa los procedimientos pa* (paVendedorInsertar, ...) en vez de sp_<entidad>_<accion>:
// es el único módulo con ese estándar de nomenclatura, a solicitud explícita.
public sealed class VendedorRepository(IDbConnectionFactory connectionFactory) : IVendedorRepository
{
	public async Task<int> InsertarAsync(string codigo, string nombres, string? apellidos, DateTime? fechaIngreso, decimal porcentajeComision, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@pve_codigo", codigo);
		parametros.Add("@pve_nombres", nombres);
		parametros.Add("@pve_apellidos", apellidos);
		parametros.Add("@pve_fecha_ingreso", fechaIngreso);
		parametros.Add("@pve_porc_comision", porcentajeComision);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@pve_id", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.paVendedorInsertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@pve_id");
	}

	public async Task ActualizarAsync(int pveId, string nombres, string? apellidos, DateTime? fechaIngreso, decimal porcentajeComision, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			pve_id = pveId,
			pve_nombres = nombres,
			pve_apellidos = apellidos,
			pve_fecha_ingreso = fechaIngreso,
			pve_porc_comision = porcentajeComision,
			usu_id = usuarioAccionId
		};
		await connection.ExecuteAsync("dbo.paVendedorActualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int pveId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { pve_id = pveId, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paVendedorEliminar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<Vendedor>> ConsultarAsync(string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<Vendedor>(
			"dbo.paVendedorConsultar", new { pve_estado = estado }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<Vendedor?> ConsultarPorIdAsync(int pveId)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QueryFirstOrDefaultAsync<Vendedor>(
			"dbo.paVendedorConsultarPorId", new { pve_id = pveId }, commandType: CommandType.StoredProcedure);
	}

	public async Task<Vendedor?> ConsultarPorUsuarioAsync(int usuId)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QueryFirstOrDefaultAsync<Vendedor>(
			"dbo.paVendedorConsultarPorUsuario", new { UsuId = usuId }, commandType: CommandType.StoredProcedure);
	}

	public async Task<(IReadOnlyList<FacturaVendedor> Facturas, ComisionVendedorResumen Resumen)> ConsultarFacturasAsync(int pveId, DateTime fechaDel, DateTime fechaAl, int? sucId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var multi = await connection.QueryMultipleAsync(
			"dbo.paVendedorFacturasConsultar",
			new { PveId = pveId, FechaDel = fechaDel.Date, FechaAl = fechaAl.Date, SucId = sucId },
			commandType: CommandType.StoredProcedure);
		var facturas = (await multi.ReadAsync<FacturaVendedor>()).ToList();
		var resumen = await multi.ReadFirstOrDefaultAsync<ComisionVendedorResumen>() ?? new ComisionVendedorResumen();
		return (facturas, resumen);
	}
}
