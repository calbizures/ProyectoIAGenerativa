using System.Data;
using Dapper;

namespace Erp.Data.ActivosFijos;

public sealed class ActivosFijosRepository(IDbConnectionFactory connectionFactory) : IActivosFijosRepository
{
	public async Task<IReadOnlyList<CategoriaActivo>> ConsultarCategoriasAsync(bool soloActivas)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<CategoriaActivo>("dbo.paActivoFijoCategoriaConsultar", new { SoloActivas = soloActivas },
			commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> GuardarCategoriaAsync(CategoriaActivo categoria, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters();
		parametros.Add("@AfcId", categoria.AfcId == 0 ? null : categoria.AfcId, DbType.Int32, ParameterDirection.InputOutput);
		parametros.Add("@Codigo", categoria.Codigo);
		parametros.Add("@Nombre", categoria.Nombre);
		parametros.Add("@Porcentaje", categoria.Porcentaje);
		parametros.Add("@CtaIdActivo", categoria.CtaIdActivo);
		parametros.Add("@CtaIdDepreciacion", categoria.CtaIdDepreciacion);
		parametros.Add("@CtaIdGasto", categoria.CtaIdGasto);
		parametros.Add("@Estado", categoria.Estado);
		parametros.Add("@UsuId", usuarioAccionId);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paActivoFijoCategoriaGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@AfcId");
	}

	public async Task<IReadOnlyList<ActivoFijo>> ConsultarAsync(int? afaId, int? afcId, int? sucId, string? estado, string? texto)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<ActivoFijo>("dbo.paActivoFijoConsultar",
			new { AfaId = afaId, AfcId = afcId, SucId = sucId, Estado = string.IsNullOrEmpty(estado) ? null : estado, Texto = string.IsNullOrWhiteSpace(texto) ? null : texto.Trim() },
			commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> GuardarAsync(ActivoFijo activo, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters();
		parametros.Add("@AfaId", activo.AfaId == 0 ? null : activo.AfaId, DbType.Int32, ParameterDirection.InputOutput);
		parametros.Add("@Descripcion", activo.Descripcion);
		parametros.Add("@AfcId", activo.AfcId);
		parametros.Add("@SucId", activo.SucId);
		parametros.Add("@IdDepartamento", activo.IdDepartamento);
		parametros.Add("@Responsable", activo.Responsable);
		parametros.Add("@Serie", activo.Serie);
		parametros.Add("@Ubicacion", activo.Ubicacion);
		parametros.Add("@FechaAdquisicion", activo.FechaAdquisicion.Date, DbType.Date);
		parametros.Add("@Costo", activo.Costo);
		parametros.Add("@ValorResidual", activo.ValorResidual);
		parametros.Add("@Porcentaje", activo.Porcentaje);
		parametros.Add("@DepreciacionInicial", activo.DepreciacionInicial);
		parametros.Add("@Documento", activo.Documento);
		parametros.Add("@CtaIdContrapartida", activo.CtaIdContrapartida);
		parametros.Add("@UsuId", usuarioAccionId);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paActivoFijoGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@AfaId");
	}

	public async Task<IReadOnlyList<DepreciacionMes>> ConsultarHistorialAsync(int afaId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<DepreciacionMes>("dbo.paActivoFijoDepreciacionHistorial", new { AfaId = afaId },
			commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task DarDeBajaAsync(int afaId, string tipo, DateTime fecha, string motivo, decimal? precioVenta, int? ctaIdCobro, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paActivoFijoBaja",
			new { AfaId = afaId, Tipo = tipo, Fecha = fecha.Date, Motivo = motivo, PrecioVenta = precioVenta, CtaIdCobro = ctaIdCobro, UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<DepreciacionPrevia>> ConsultarDepreciacionPreviaAsync(int anio, int mes)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<DepreciacionPrevia>("dbo.paActivoFijoDepreciacionPrevia", new { Anio = anio, Mes = mes },
			commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<IReadOnlyList<DepreciacionCorrida>> ConsultarCorridasAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<DepreciacionCorrida>("dbo.paActivoFijoDepreciacionCorridaConsultar", commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> DepreciarAsync(int anio, int mes, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters();
		parametros.Add("@Anio", anio);
		parametros.Add("@Mes", mes);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@AdcId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paActivoFijoDepreciar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@AdcId");
	}

	public async Task AnularCorridaAsync(int adcId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paActivoFijoDepreciacionAnular", new { AdcId = adcId, UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}
}
