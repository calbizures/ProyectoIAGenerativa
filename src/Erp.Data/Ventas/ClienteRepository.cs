using System.Data;
using Dapper;

namespace Erp.Data.Ventas;

public sealed class ClienteRepository(IDbConnectionFactory connectionFactory) : IClienteRepository
{
	public async Task<int> InsertarAsync(string codigo, string nombres, string? apellidos, string? direccion, string? telefonoCelular, string? nit, string? email, decimal limiteCredito, int? usuarioAccionId, int? provId = null)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@CliCodigo", codigo);
		parametros.Add("@CliNombres", nombres);
		parametros.Add("@CliApellidos", apellidos);
		parametros.Add("@CliDireccion", direccion);
		parametros.Add("@CliTelefonoCelular", telefonoCelular);
		parametros.Add("@CliNit", nit);
		parametros.Add("@CliEmail", email);
		parametros.Add("@CliLimiteCredito", limiteCredito);
		parametros.Add("@CliDireccionProvincia", provId);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@CliId", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.paClienteInsertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@CliId");
	}

	public async Task ActualizarAsync(int cliId, string nombres, string? apellidos, string? direccion, string? telefonoCelular, string? nit, string? email, decimal limiteCredito, int? usuarioAccionId, int? provId = IClienteRepository.ClienteSinCambioUbicacion)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			CliId = cliId,
			CliNombres = nombres,
			CliApellidos = apellidos,
			CliDireccion = direccion,
			CliTelefonoCelular = telefonoCelular,
			CliNit = nit,
			CliEmail = email,
			CliLimiteCredito = limiteCredito,
			CliDireccionProvincia = provId,
			UsuId = usuarioAccionId
		};
		await connection.ExecuteAsync("dbo.paClienteActualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int cliId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { CliId = cliId, UsuId = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paClienteEliminar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<Cliente>> ConsultarAsync(string? texto, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { Texto = texto, CliEstado = estado };
		var filas = await connection.QueryAsync<Cliente>("dbo.paClienteConsultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<Cliente?> ConsultarPorIdAsync(int cliId)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QueryFirstOrDefaultAsync<Cliente>(
			"dbo.paClienteConsultarPorId", new { CliId = cliId }, commandType: CommandType.StoredProcedure);
	}

	public async Task<Cliente?> BuscarPorNitAsync(string nit)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QueryFirstOrDefaultAsync<Cliente>(
			"dbo.paClienteBuscarPorNit", new { Nit = nit }, commandType: CommandType.StoredProcedure);
	}

	public async Task<(int CliId, bool Nuevo)> RegistrarPorNitAsync(string nit, string? nombre, string? direccion, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters(new { Nit = nit, Nombre = nombre, Direccion = direccion, UsuId = usuarioAccionId });
		parametros.Add("@CliId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		parametros.Add("@Nuevo", dbType: DbType.Boolean, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paClienteRegistrarPorNit", parametros, commandType: CommandType.StoredProcedure);
		return (parametros.Get<int>("@CliId"), parametros.Get<bool>("@Nuevo"));
	}

	public async Task<IReadOnlyList<FacturaCliente>> ConsultarFacturasAsync(int cliId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<FacturaCliente>(
			"dbo.paClienteFacturasConsultar", new { CliId = cliId }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}
}
