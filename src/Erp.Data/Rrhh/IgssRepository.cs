using System.Data;
using Dapper;

namespace Erp.Data.Rrhh;

public sealed class IgssRepository(IDbConnectionFactory connectionFactory) : IIgssRepository
{
	// Los catálogos del IGSS no cambian mientras corre la aplicación.
	private static IgssCatalogos? catalogos;

	public async Task<IgssCatalogos> ConsultarCatalogosAsync()
	{
		if (catalogos is not null) return catalogos;
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paRrhhIgssCatalogosConsultar", commandType: CommandType.StoredProcedure);
		var actividades = (await lector.ReadAsync<Fila>()).Select(a => new IgssCodigo(a.Codigo, a.Descripcion)).ToList();
		var ocupaciones = (await lector.ReadAsync<Fila>()).Select(o => new IgssCodigo(o.Codigo, o.Descripcion)).ToList();
		var departamentos = (await lector.ReadAsync<FilaDepartamento>()).Select(d => new IgssCodigo(d.Departamento, d.Nombre)).ToList();
		var municipios = (await lector.ReadAsync<FilaMunicipio>()).Select(m => new IgssMunicipio(m.Departamento, m.Municipio, m.Nombre)).ToList();
		var tipos = (await lector.ReadAsync<FilaTipoSalario>()).Select(t => new IgssCodigo(t.Codigo.ToString(), t.Descripcion)).ToList();
		catalogos = new IgssCatalogos { Actividades = actividades, Ocupaciones = ocupaciones, Departamentos = departamentos, Municipios = municipios, TiposSalario = tipos };
		return catalogos;
	}

	public async Task<IReadOnlyList<IgssTipoPlanilla>> ConsultarTiposPlanillaAsync(int ciaId)
	{
		using var connection = connectionFactory.CreateConnection();
		return (await connection.QueryAsync<IgssTipoPlanilla>("dbo.paRrhhIgssTipoPlanillaConsultar", new { CiaId = ciaId },
			commandType: CommandType.StoredProcedure)).ToList();
	}

	public async Task<int> GuardarTipoPlanillaAsync(IgssTipoPlanilla tipo, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters(new
		{
			IdTipoPlanilla = tipo.IdTipoPlanilla == 0 ? (int?)null : tipo.IdTipoPlanilla,
			tipo.CiaId,
			tipo.Codigo,
			tipo.Nombre,
			tipo.TipoAfiliado,
			tipo.Periodo,
			tipo.Departamento,
			tipo.Actividad,
			tipo.Clase,
			tipo.TiempoContrato,
			tipo.Estado,
			UsuId = usuarioAccionId
		});
		parametros.Add("@IdResultado", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paRrhhIgssTipoPlanillaGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@IdResultado");
	}

	public async Task<(EmpleadoIgss? Empleado, IReadOnlyList<IgssAusencia> Ausencias)> ConsultarEmpleadoAsync(int idEmpleado)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paRrhhEmpleadoIgssConsultar", new { IdEmpleado = idEmpleado },
			commandType: CommandType.StoredProcedure);
		var empleado = await lector.ReadFirstOrDefaultAsync<EmpleadoIgss>();
		var ausencias = (await lector.ReadAsync<IgssAusencia>()).ToList();
		return (empleado, ausencias);
	}

	public async Task GuardarEmpleadoAsync(EmpleadoIgss empleado, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paRrhhEmpleadoIgssGuardar", new
		{
			empleado.IdEmpleado,
			empleado.IdIgssTipoPlanilla,
			empleado.CondicionLaboral,
			empleado.IgssTipoSalario,
			empleado.HorasDiarias,
			empleado.IgssOcupacion,
			UsuId = usuarioAccionId
		}, commandType: CommandType.StoredProcedure);
	}

	public async Task GuardarAusenciaAsync(IgssAusencia ausencia, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paRrhhIgssAusenciaGuardar", new
		{
			ausencia.IdEmpleado,
			ausencia.Tipo,
			FechaInicio = ausencia.FechaInicio.Date,
			FechaFin = ausencia.FechaFin.Date,
			ausencia.Observacion,
			UsuId = usuarioAccionId
		}, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAusenciaAsync(int idAusencia)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paRrhhIgssAusenciaEliminar", new { IdAusencia = idAusencia }, commandType: CommandType.StoredProcedure);
	}

	public async Task<IgssArchivoDatos> ConsultarArchivoAsync(int ciaId, int anio, int mes)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paRrhhPlanillaIgssArchivoConsultar",
			new { CiaId = ciaId, Anio = anio, Mes = mes }, commandType: CommandType.StoredProcedure);
		return new IgssArchivoDatos
		{
			Patrono = await lector.ReadFirstOrDefaultAsync<IgssArchivoPatrono>(),
			Centros = (await lector.ReadAsync<IgssArchivoCentro>()).ToList(),
			TiposPlanilla = (await lector.ReadAsync<IgssArchivoTipoPlanilla>()).ToList(),
			Liquidaciones = (await lector.ReadAsync<IgssArchivoLiquidacion>()).ToList(),
			Empleados = (await lector.ReadAsync<IgssArchivoEmpleado>()).ToList(),
			Ausencias = (await lector.ReadAsync<IgssArchivoAusencia>()).ToList(),
			Observaciones = (await lector.ReadAsync<FilaObservacion>()).Select(o => new IgssArchivoObservacion(o.Nivel, o.Mensaje)).ToList()
		};
	}

	private sealed class Fila { public string Codigo { get; set; } = ""; public string Descripcion { get; set; } = ""; }
	private sealed class FilaDepartamento { public string Departamento { get; set; } = ""; public string Nombre { get; set; } = ""; }
	private sealed class FilaMunicipio { public string Departamento { get; set; } = ""; public string Municipio { get; set; } = ""; public string Nombre { get; set; } = ""; }
	private sealed class FilaTipoSalario { public byte Codigo { get; set; } public string Descripcion { get; set; } = ""; }
	private sealed class FilaObservacion { public string Nivel { get; set; } = ""; public string Mensaje { get; set; } = ""; }
}
