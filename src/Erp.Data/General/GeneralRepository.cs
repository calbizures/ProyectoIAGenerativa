using System.Data;
using Dapper;
using Erp.Data.Caja;

namespace Erp.Data.General;

public sealed class GeneralRepository(IDbConnectionFactory connectionFactory) : IGeneralRepository
{
	public async Task<IReadOnlyList<NitRevision>> ConsultarNitRevisionAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		return (await connection.QueryAsync<NitRevision>("dbo.paNitRevisionConsultar", commandType: CommandType.StoredProcedure)).ToList();
	}

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
		parametros.Add("@ProvId", compania.ProvId);
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

	public async Task GuardarLogoAsync(int ciaId, byte[]? logo, string? tipo, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@CiaId", ciaId);
		parametros.Add("@Logo", logo, DbType.Binary, size: -1);
		parametros.Add("@Tipo", tipo);
		parametros.Add("@UsuId", usuarioAccionId);
		await connection.ExecuteAsync("dbo.paCompaniaLogoGuardar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<CompaniaLogo?> ConsultarLogoAsync(int? ciaId, int? sucId, bool soloVersion)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QueryFirstOrDefaultAsync<CompaniaLogo>("dbo.paCompaniaLogoConsultar",
			new { CiaId = ciaId, SucId = sucId, SoloVersion = soloVersion }, commandType: CommandType.StoredProcedure);
	}

	public async Task<CatalogoUbicacion> ConsultarUbicacionAsync(bool soloActivos)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paGenUbicacionConsultar",
			new { SoloActivos = soloActivos }, commandType: CommandType.StoredProcedure);
		return new CatalogoUbicacion
		{
			Paises = (await lector.ReadAsync<Pais>()).ToList(),
			Departamentos = (await lector.ReadAsync<DepartamentoGeografico>()).ToList(),
			Municipios = (await lector.ReadAsync<Municipio>()).ToList(),
		};
	}

	public Task<int> GuardarPaisAsync(Pais pais, int? usuarioAccionId) =>
		GuardarConResultadoAsync("dbo.paGenPaisGuardar", new
		{
			PaiId = pais.PaiId == 0 ? (int?)null : pais.PaiId,
			pais.Nombre, pais.CodigoAlfa2, pais.CodigoAlfa3, pais.CodigoNumero, pais.Nacionalidad, pais.Estado,
			UsuId = usuarioAccionId
		});

	public Task<int> GuardarDepartamentoAsync(DepartamentoGeografico departamento, int? usuarioAccionId) =>
		GuardarConResultadoAsync("dbo.paGenDepartamentoGuardar", new
		{
			EstId = departamento.EstId == 0 ? (int?)null : departamento.EstId,
			departamento.PaiId, departamento.Codigo, departamento.Nombre, departamento.Estado,
			UsuId = usuarioAccionId
		});

	public Task<int> GuardarMunicipioAsync(Municipio municipio, int? usuarioAccionId) =>
		GuardarConResultadoAsync("dbo.paGenMunicipioGuardar", new
		{
			ProvId = municipio.ProvId == 0 ? (int?)null : municipio.ProvId,
			municipio.EstId, municipio.Codigo, municipio.Nombre, municipio.Estado,
			UsuId = usuarioAccionId
		});

	private async Task<int> GuardarConResultadoAsync(string procedimiento, object valores)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters(valores);
		parametros.Add("@IdResultado", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync(procedimiento, parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@IdResultado");
	}

	public async Task<IReadOnlyList<SucursalDetalle>> ConsultarSucursalesAsync(int? ciaId, bool soloActivas)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<SucursalDetalle>("dbo.paSucursalConsultar",
			new { CiaId = ciaId, SoloActivas = soloActivas }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> GuardarSucursalAsync(SucursalDetalle sucursal, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@SucId", sucursal.SucId == 0 ? null : sucursal.SucId);
		parametros.Add("@CiaId", sucursal.CiaId);
		parametros.Add("@Codigo", sucursal.SucCodigo);
		parametros.Add("@Descripcion", sucursal.SucDescripcion);
		parametros.Add("@Direccion", sucursal.SucDireccion);
		parametros.Add("@Telefono", sucursal.SucTelefono);
		parametros.Add("@ProvId", sucursal.ProvId);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@IdResultado", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paSucursalGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@IdResultado");
	}

	public async Task CambiarEstadoSucursalAsync(int sucId, string estado, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paSucursalCambiarEstado",
			new { SucId = sucId, Estado = estado, UsuId = usuarioAccionId }, commandType: CommandType.StoredProcedure);
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
			"dbo.paCuentaContableConsultar", new { CtaTipo = (string?)null, CtaEstado = "A" }, commandType: CommandType.StoredProcedure);
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

	public async Task<CompaniaImpresion?> ConsultarImpresionAsync(int ciaId)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QueryFirstOrDefaultAsync<CompaniaImpresion>("dbo.paCompaniaImpresionConsultar", new { CiaId = ciaId },
			commandType: CommandType.StoredProcedure);
	}

	public async Task GuardarImpresionAsync(CompaniaImpresion impresion, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCompaniaImpresionGuardar",
			new { impresion.CiaId, impresion.Impresora, AnchoTermica = (byte)impresion.AnchoTermica, impresion.Pie, impresion.VigenciaCotizacion, UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}
}
