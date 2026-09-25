using System.Data;
using Dapper;
using Erp.Data.Caja;

namespace Erp.Data.General;

public sealed class GeneralRepository(IDbConnectionFactory connectionFactory) : IGeneralRepository
{
	public async Task<IReadOnlyList<Compania>> ConsultarCompaniasAsync(bool soloActivas)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<Compania>(
			"dbo.paCompaniaConsultar", new { SoloActivas = soloActivas }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> GuardarCompaniaAsync(Compania compania, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@CiaId", compania.CiaId == 0 ? null : compania.CiaId);
		parametros.Add("@NombreComercial", compania.CiaNombreComercial);
		parametros.Add("@Direccion", compania.CiaDireccion);
		parametros.Add("@RepresentanteLegal", compania.CiaRepresentanteLegal);
		parametros.Add("@DpiRepresentanteLegal", compania.CiaDpiRepresentanteLegal);
		parametros.Add("@FechaNacimientoRepresentanteLegal", compania.CiaFechaNacimientoRepresentanteLegal);
		parametros.Add("@Nit", compania.CiaNit);
		parametros.Add("@Telefono", compania.CiaTelefono);
		parametros.Add("@Email", compania.CiaEmail);
		parametros.Add("@PorcIva", compania.CiaPorcIva);
		parametros.Add("@PagaComision", compania.CiaPagaComision);
		parametros.Add("@ToleranciaCierreCaja", compania.CiaToleranciaCierreCaja);
		parametros.Add("@PeriodicidadNomina", compania.CiaPeriodicidadNomina);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@IdResultado", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paCompaniaGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@IdResultado");
	}

	public async Task CambiarEstadoCompaniaAsync(int ciaId, string estado, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCompaniaCambiarEstado",
			new { CiaId = ciaId, Estado = estado, UsuId = usuarioAccionId }, commandType: CommandType.StoredProcedure);
	}

	public async Task<ParametrosCompania> ConsultarParametrosAsync(int? sucId)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QueryFirstOrDefaultAsync<ParametrosCompania>(
			"dbo.paCompaniaParametrosConsultar", new { SucId = sucId }, commandType: CommandType.StoredProcedure)
			?? new ParametrosCompania();
	}

	public async Task<IReadOnlyList<EntidadFinancieraTipo>> ConsultarTiposEntidadAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<EntidadFinancieraTipo>(
			"dbo.paEntidadFinancieraTipoConsultar", commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> GuardarTipoEntidadAsync(int? geftId, string descripcion, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@GeftId", geftId);
		parametros.Add("@Descripcion", descripcion);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@IdResultado", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paEntidadFinancieraTipoGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@IdResultado");
	}

	public async Task EliminarTipoEntidadAsync(int geftId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paEntidadFinancieraTipoEliminar", new { GeftId = geftId }, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<EntidadFinanciera>> ConsultarEntidadesAsync(int? geftId, bool soloActivas)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<EntidadFinanciera>(
			"dbo.paEntidadFinancieraConsultar", new { GeftId = geftId, SoloActivas = soloActivas }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> GuardarEntidadAsync(int? gefId, int geftId, string codigo, string descripcion, string estado, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@GefId", gefId);
		parametros.Add("@GeftId", geftId);
		parametros.Add("@Codigo", codigo);
		parametros.Add("@Descripcion", descripcion);
		parametros.Add("@Estado", estado);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@IdResultado", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paEntidadFinancieraGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@IdResultado");
	}

	public async Task EliminarEntidadAsync(int gefId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paEntidadFinancieraEliminar", new { GefId = gefId }, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<CuentaContable>> ConsultarCuentasContablesAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<CuentaContable>(
			"dbo.sp_cuenta_contable_consultar", new { cta_tipo = (string?)null, cta_estado = "A" }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<IReadOnlyList<CuentaParametro>> ConsultarCuentasParametroAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<CuentaParametro>(
			"dbo.paCuentaParametroConsultar", commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task GuardarCuentaParametroAsync(string codigo, int ctaId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCuentaParametroGuardar",
			new { Codigo = codigo, CtaId = ctaId, UsuId = usuarioAccionId }, commandType: CommandType.StoredProcedure);
	}
}
