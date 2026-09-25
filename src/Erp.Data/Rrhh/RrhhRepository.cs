using System.Data;
using Dapper;

namespace Erp.Data.Rrhh;

public sealed class RrhhRepository(IDbConnectionFactory connectionFactory) : IRrhhRepository
{
	private async Task<int> GuardarConResultadoAsync(string procedimiento, DynamicParameters parametros)
	{
		parametros.Add("@IdResultado", dbType: DbType.Int32, direction: ParameterDirection.Output);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync(procedimiento, parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@IdResultado");
	}

	private async Task EjecutarAsync(string procedimiento, object parametros)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync(procedimiento, parametros, commandType: CommandType.StoredProcedure);
	}

	private async Task<IReadOnlyList<T>> ConsultarAsync<T>(string procedimiento, object? parametros = null)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<T>(procedimiento, parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	private static int? SinCero(int id) => id == 0 ? null : id;

	public Task<IReadOnlyList<CatalogoRrhh>> ConsultarCatalogoAsync(string catalogo, bool soloActivos) =>
		ConsultarAsync<CatalogoRrhh>("dbo.paRrhhCatalogoConsultar", new { Catalogo = catalogo, SoloActivos = soloActivos });

	public Task<int> GuardarCatalogoAsync(string catalogo, int? id, string descripcion, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters(new { Catalogo = catalogo, Id = id, Descripcion = descripcion, UsuId = usuarioAccionId });
		return GuardarConResultadoAsync("dbo.paRrhhCatalogoGuardar", parametros);
	}

	public Task CambiarEstadoCatalogoAsync(string catalogo, int id, string estado, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paRrhhCatalogoCambiarEstado", new { Catalogo = catalogo, Id = id, Estado = estado, UsuId = usuarioAccionId });

	public Task<IReadOnlyList<Departamento>> ConsultarDepartamentosAsync(bool soloActivos) =>
		ConsultarAsync<Departamento>("dbo.paRrhhDepartamentoConsultar", new { SoloActivos = soloActivos });

	public Task<int> GuardarDepartamentoAsync(Departamento departamento, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters(new
		{
			IdDepartamento = SinCero(departamento.IdDepartamento),
			departamento.Descripcion,
			departamento.IdUnidadOrganizativa,
			departamento.SucId,
			departamento.Estado,
			UsuId = usuarioAccionId
		});
		return GuardarConResultadoAsync("dbo.paRrhhDepartamentoGuardar", parametros);
	}

	public Task<IReadOnlyList<Puesto>> ConsultarPuestosAsync(bool soloActivos) =>
		ConsultarAsync<Puesto>("dbo.paRrhhPuestoConsultar", new { SoloActivos = soloActivos });

	public Task<int> GuardarPuestoAsync(Puesto puesto, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters(new
		{
			IdPuesto = SinCero(puesto.IdPuesto),
			puesto.Descripcion,
			puesto.SalarioMinimo,
			puesto.SalarioMaximo,
			puesto.Estado,
			UsuId = usuarioAccionId
		});
		return GuardarConResultadoAsync("dbo.paRrhhPuestoGuardar", parametros);
	}

	public Task<IReadOnlyList<Plaza>> ConsultarPlazasAsync(bool soloActivos) =>
		ConsultarAsync<Plaza>("dbo.paRrhhPlazaConsultar", new { SoloActivos = soloActivos });

	public Task<int> GuardarPlazaAsync(Plaza plaza, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters(new
		{
			IdPlaza = SinCero(plaza.IdPlaza),
			plaza.Descripcion,
			plaza.IdDepartamento,
			plaza.IdPuesto,
			plaza.Estado,
			UsuId = usuarioAccionId
		});
		return GuardarConResultadoAsync("dbo.paRrhhPlazaGuardar", parametros);
	}

	public Task<IReadOnlyList<EmpleadoResumen>> ConsultarEmpleadosAsync(string? filtro, string? estado) =>
		ConsultarAsync<EmpleadoResumen>("dbo.paRrhhEmpleadoConsultar", new { Filtro = filtro, Estado = estado });

	public async Task<(Empleado? Empleado, IReadOnlyList<HistorialPlaza> Historial)> ConsultarEmpleadoPorIdAsync(int idEmpleado)
	{
		using var connection = connectionFactory.CreateConnection();
		using var multi = await connection.QueryMultipleAsync(
			"dbo.paRrhhEmpleadoConsultarPorId", new { IdEmpleado = idEmpleado }, commandType: CommandType.StoredProcedure);
		var empleado = await multi.ReadFirstOrDefaultAsync<Empleado>();
		var historial = (await multi.ReadAsync<HistorialPlaza>()).ToList();
		return (empleado, historial);
	}

	public Task<int> GuardarEmpleadoAsync(Empleado empleado, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters(new
		{
			IdEmpleado = SinCero(empleado.IdEmpleado),
			empleado.CodigoEmpleado,
			empleado.CiaId,
			empleado.PrimerNombre,
			empleado.SegundoNombre,
			empleado.PrimerApellido,
			empleado.SegundoApellido,
			empleado.ApellidoCasada,
			empleado.Genero,
			empleado.FechaNacimiento,
			empleado.FechaIngreso,
			empleado.Direccion,
			empleado.IdTipoDocumentoIdentificacion,
			empleado.NumeroDocumento,
			empleado.NumeroAfiliacionIGSS,
			empleado.Nit,
			empleado.Email,
			empleado.IdPlaza,
			empleado.SalarioBase,
			UsuId = usuarioAccionId
		});
		return GuardarConResultadoAsync("dbo.paRrhhEmpleadoGuardar", parametros);
	}

	public Task DarBajaEmpleadoAsync(int idEmpleado, DateTime fechaBaja, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paRrhhEmpleadoDarBaja", new { IdEmpleado = idEmpleado, FechaBaja = fechaBaja.Date, UsuId = usuarioAccionId });

	public Task ReactivarEmpleadoAsync(int idEmpleado, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paRrhhEmpleadoReactivar", new { IdEmpleado = idEmpleado, UsuId = usuarioAccionId });

	public Task AsignarUsuarioAsync(int idEmpleado, int? usuIdAsignado, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paRrhhEmpleadoAsignarUsuario", new { IdEmpleado = idEmpleado, UsuIdAsignado = usuIdAsignado, UsuId = usuarioAccionId });

	public Task AsignarVendedorAsync(int idEmpleado, int? pveId, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paRrhhEmpleadoAsignarVendedor", new { IdEmpleado = idEmpleado, PveId = pveId, UsuId = usuarioAccionId });

	public Task<IReadOnlyList<TipoMovimientoNomina>> ConsultarTiposMovimientoAsync(bool soloActivos) =>
		ConsultarAsync<TipoMovimientoNomina>("dbo.paRrhhTipoMovimientoNominaConsultar", new { SoloActivos = soloActivos });

	public Task<int> GuardarTipoMovimientoAsync(TipoMovimientoNomina tipo, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters(new
		{
			IdTipoMovimientoNomina = SinCero(tipo.IdTipoMovimientoNomina),
			tipo.Codigo,
			tipo.Descripcion,
			tipo.Naturaleza,
			tipo.FormaCalculo,
			tipo.Valor,
			tipo.EsAutomatico,
			tipo.EsBaseCalculo,
			tipo.Orden,
			tipo.CtaId,
			tipo.Estado,
			UsuId = usuarioAccionId
		});
		return GuardarConResultadoAsync("dbo.paRrhhTipoMovimientoNominaGuardar", parametros);
	}

	public Task<IReadOnlyList<MovimientoNomina>> ConsultarMovimientosAsync(int? idEmpleado, DateTime? fechaDel, DateTime? fechaAl, bool soloPendientes) =>
		ConsultarAsync<MovimientoNomina>("dbo.paRrhhMovimientoNominaConsultar",
			new { IdEmpleado = idEmpleado, FechaDel = fechaDel?.Date, FechaAl = fechaAl?.Date, SoloPendientes = soloPendientes });

	public Task<int> GuardarMovimientoAsync(int? idMovimiento, int idEmpleado, int idTipoMovimiento, string? descripcion, decimal monto, DateTime fechaAplicacion, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters(new
		{
			IdMovimientoNomina = idMovimiento,
			IdEmpleado = idEmpleado,
			IdTipoMovimientoNomina = idTipoMovimiento,
			Descripcion = descripcion,
			Monto = monto,
			FechaAplicacion = fechaAplicacion.Date,
			UsuId = usuarioAccionId
		});
		return GuardarConResultadoAsync("dbo.paRrhhMovimientoNominaGuardar", parametros);
	}

	public Task AnularMovimientoAsync(int idMovimiento, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paRrhhMovimientoNominaAnular", new { IdMovimientoNomina = idMovimiento, UsuId = usuarioAccionId });

	public Task<IReadOnlyList<Nomina>> ConsultarNominasAsync(int? ciaId) =>
		ConsultarAsync<Nomina>("dbo.paRrhhNominaConsultar", new { CiaId = ciaId });

	public Task<int> CrearNominaAsync(int ciaId, string descripcion, string tipoPeriodo, DateTime fechaDel, DateTime fechaAl, DateTime? fechaPago, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters(new
		{
			CiaId = ciaId,
			Descripcion = descripcion,
			TipoPeriodo = tipoPeriodo,
			FechaDel = fechaDel.Date,
			FechaAl = fechaAl.Date,
			FechaPago = fechaPago?.Date,
			UsuId = usuarioAccionId
		});
		return GuardarConResultadoAsync("dbo.paRrhhNominaCrear", parametros);
	}

	public Task CalcularNominaAsync(int idNomina, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paRrhhNominaCalcular", new { IdNomina = idNomina, UsuId = usuarioAccionId });

	public Task AprobarNominaAsync(int idNomina, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paRrhhNominaAprobar", new { IdNomina = idNomina, UsuId = usuarioAccionId });

	public Task AnularNominaAsync(int idNomina, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paRrhhNominaAnular", new { IdNomina = idNomina, UsuId = usuarioAccionId });

	public Task<IReadOnlyList<NominaEmpleado>> ConsultarNominaEmpleadosAsync(int idNomina) =>
		ConsultarAsync<NominaEmpleado>("dbo.paRrhhNominaEmpleadoConsultar", new { IdNomina = idNomina });

	public Task<IReadOnlyList<NominaDetalle>> ConsultarNominaDetalleAsync(int idNominaEmpleado) =>
		ConsultarAsync<NominaDetalle>("dbo.paRrhhNominaDetalleConsultar", new { IdNominaEmpleado = idNominaEmpleado });
}
