using System.Data;
using Dapper;

namespace Erp.Data.Ventas;

public sealed class ClienteRepository(IDbConnectionFactory connectionFactory) : IClienteRepository
{
	public async Task<int> InsertarAsync(string codigo, string nombres, string? apellidos, string? direccion, string? telefonoCelular, string? nit, string? email, decimal limiteCredito, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@cli_codigo", codigo);
		parametros.Add("@cli_nombres", nombres);
		parametros.Add("@cli_apellidos", apellidos);
		parametros.Add("@cli_direccion", direccion);
		parametros.Add("@cli_telefono_celular", telefonoCelular);
		parametros.Add("@cli_nit", nit);
		parametros.Add("@cli_email", email);
		parametros.Add("@cli_limite_credito", limiteCredito);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@cli_id", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.sp_cliente_insertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@cli_id");
	}

	public async Task ActualizarAsync(int cliId, string nombres, string? apellidos, string? direccion, string? telefonoCelular, string? nit, string? email, decimal limiteCredito, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			cli_id = cliId,
			cli_nombres = nombres,
			cli_apellidos = apellidos,
			cli_direccion = direccion,
			cli_telefono_celular = telefonoCelular,
			cli_nit = nit,
			cli_email = email,
			cli_limite_credito = limiteCredito,
			usu_id = usuarioAccionId
		};
		await connection.ExecuteAsync("dbo.sp_cliente_actualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int cliId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { cli_id = cliId, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.sp_cliente_eliminar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<Cliente>> ConsultarAsync(string? texto, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { texto, cli_estado = estado };
		var filas = await connection.QueryAsync<Cliente>("dbo.sp_cliente_consultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<Cliente?> ConsultarPorIdAsync(int cliId)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QueryFirstOrDefaultAsync<Cliente>(
			"dbo.sp_cliente_consultar_por_id", new { cli_id = cliId }, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<FacturaCliente>> ConsultarFacturasAsync(int cliId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<FacturaCliente>(
			"dbo.paClienteFacturasConsultar", new { CliId = cliId }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}
}
