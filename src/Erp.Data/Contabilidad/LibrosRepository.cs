using System.Data;
using Dapper;

namespace Erp.Data.Contabilidad;

public sealed class LibrosRepository(IDbConnectionFactory connectionFactory) : ILibrosRepository
{
	public async Task<IReadOnlyList<Poliza>> ConsultarPolizasAsync(DateTime? desde, DateTime? hasta, string? origen, string? estado, string? texto, int? ctaId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<Poliza>("dbo.paPolizaConsultar",
			new { Desde = desde?.Date, Hasta = hasta?.Date, Origen = Texto(origen), Estado = Texto(estado), Texto = Texto(texto), CtaId = ctaId },
			commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<Poliza?> ConsultarPolizaAsync(int asiId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paPolizaConsultarPorId", new { AsiId = asiId }, commandType: CommandType.StoredProcedure);
		var poliza = await lector.ReadFirstOrDefaultAsync<Poliza>();
		if (poliza is null) return null;
		poliza.Detalle = (await lector.ReadAsync<PolizaLinea>()).ToList();
		poliza.Total = poliza.Detalle.Sum(l => l.Debe);
		poliza.Lineas = poliza.Detalle.Count;
		return poliza;
	}

	public async Task<int> GrabarPolizaManualAsync(DateTime fecha, string descripcion, IReadOnlyList<PolizaManualLinea> lineas, int? usuarioAccionId)
	{
		var tabla = new DataTable();
		tabla.Columns.Add("cta_id", typeof(int));
		tabla.Columns.Add("asd_debe", typeof(decimal));
		tabla.Columns.Add("asd_haber", typeof(decimal));
		tabla.Columns.Add("asd_descripcion", typeof(string));
		tabla.Columns.Add("IdDepartamento", typeof(int));
		foreach (var l in lineas)
			tabla.Rows.Add(l.CtaId ?? 0, l.Debe ?? 0m, l.Haber ?? 0m, (object?)Texto(l.Descripcion) ?? DBNull.Value, (object?)l.IdDepartamento ?? DBNull.Value);

		var parametros = new DynamicParameters();
		parametros.Add("@Fecha", fecha.Date, DbType.Date);
		parametros.Add("@Descripcion", Texto(descripcion));
		parametros.Add("@Lineas", tabla.AsTableValuedParameter("dbo.cont_asiento_det_cc_type"));
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@AsiId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paPolizaManualGrabar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@AsiId");
	}

	public async Task AnularPolizaAsync(int asiId, string motivo, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paPolizaAnular", new { AsiId = asiId, Motivo = motivo, UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<LibroDiarioLinea>> ConsultarLibroDiarioAsync(DateTime desde, DateTime hasta)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<LibroDiarioLinea>("dbo.paLibroDiarioConsultar",
			new { Desde = desde.Date, Hasta = hasta.Date }, commandType: CommandType.StoredProcedure, commandTimeout: 120);
		return filas.ToList();
	}

	public async Task<IReadOnlyList<MayorCuenta>> ConsultarLibroMayorAsync(DateTime desde, DateTime hasta, int? ctaId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paLibroMayorConsultar",
			new { Desde = desde.Date, Hasta = hasta.Date, CtaId = ctaId }, commandType: CommandType.StoredProcedure, commandTimeout: 120);
		var cuentas = (await lector.ReadAsync<MayorCuenta>()).ToList();
		var movimientos = (await lector.ReadAsync<MayorMovimiento>()).ToList();
		var porCuenta = cuentas.ToDictionary(c => c.CtaId);
		foreach (var grupo in movimientos.GroupBy(m => m.CtaId))
		{
			if (!porCuenta.TryGetValue(grupo.Key, out var cuenta)) continue;
			var saldo = cuenta.SaldoInicial;
			foreach (var m in grupo)
			{
				saldo += cuenta.Naturaleza == "D" ? m.Debe - m.Haber : m.Haber - m.Debe;
				m.Saldo = saldo;
				cuenta.Movimientos.Add(m);
			}
		}
		return cuentas;
	}

	public async Task<IReadOnlyList<BalanzaFila>> ConsultarBalanzaAsync(DateTime desde, DateTime hasta, int nivel)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<BalanzaFila>("dbo.paBalanzaComprobacionConsultar",
			new { Desde = desde.Date, Hasta = hasta.Date, Nivel = nivel }, commandType: CommandType.StoredProcedure, commandTimeout: 120);
		return filas.ToList();
	}

	public async Task<BalanceGeneral> ConsultarBalanceGeneralAsync(DateTime fecha, int nivel, DateTime? fechaComparativa)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paBalanceGeneralConsultar",
			new { Fecha = fecha.Date, Nivel = nivel, FechaComparativa = fechaComparativa?.Date }, commandType: CommandType.StoredProcedure, commandTimeout: 120);
		return new BalanceGeneral
		{
			Filas = (await lector.ReadAsync<EstadoFila>()).ToList(),
			Totales = await lector.ReadFirstAsync<BalanceTotales>()
		};
	}

	public async Task<EstadoResultados> ConsultarEstadoResultadosAsync(DateTime desde, DateTime hasta, int nivel, DateTime? desdeComparativo, DateTime? hastaComparativo)
	{
		var comparar = desdeComparativo is not null && hastaComparativo is not null;
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paEstadoResultadosConsultar",
			new
			{
				Desde = desde.Date, Hasta = hasta.Date, Nivel = nivel,
				DesdeComparativo = comparar ? desdeComparativo?.Date : null, HastaComparativo = comparar ? hastaComparativo?.Date : null
			},
			commandType: CommandType.StoredProcedure, commandTimeout: 120);
		var estado = new EstadoResultados
		{
			Filas = (await lector.ReadAsync<EstadoFila>()).ToList(),
			Totales = await lector.ReadFirstAsync<ResultadosTotales>()
		};
		var comparativo = await lector.ReadFirstOrDefaultAsync<ResultadosTotales>();
		estado.Comparativo = comparar ? comparativo : null;
		return estado;
	}

	public async Task<(IReadOnlyList<PeriodoContable> Periodos, CierreAnual? Cierre)> ConsultarPeriodosAsync(int anio)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paPeriodoContableConsultar", new { Anio = anio }, commandType: CommandType.StoredProcedure);
		var periodos = (await lector.ReadAsync<PeriodoContable>()).ToList();
		var cierre = await lector.ReadFirstOrDefaultAsync<CierreAnual>();
		return (periodos, cierre);
	}

	public async Task CambiarEstadoPeriodoAsync(int anio, int mes, string estado, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paPeriodoContableCambiarEstado", new { Anio = anio, Mes = mes, Estado = estado, UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}

	public async Task<int> GenerarCierreAnualAsync(int anio, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters();
		parametros.Add("@Anio", anio);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@AsiId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCierreAnualGenerar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@AsiId");
	}

	private static string? Texto(string? valor) => string.IsNullOrWhiteSpace(valor) ? null : valor.Trim();
}
