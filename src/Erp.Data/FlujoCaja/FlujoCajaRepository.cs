using System.Data;
using Dapper;

namespace Erp.Data.FlujoCaja;

public sealed class FlujoCajaRepository(IDbConnectionFactory connectionFactory) : IFlujoCajaRepository
{
	public async Task<FlujoReal> ConsultarRealAsync(DateTime desde, DateTime hasta, string agrupar)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paFlujoCajaRealConsultar",
			new { Desde = desde.Date, Hasta = hasta.Date, Agrupar = agrupar }, commandType: CommandType.StoredProcedure, commandTimeout: 120);
		var saldos = await lector.ReadFirstAsync<FlujoReal>();
		return new FlujoReal
		{
			SaldoInicial = saldos.SaldoInicial,
			SaldoFinal = saldos.SaldoFinal,
			Filas = (await lector.ReadAsync<FlujoRealFila>()).ToList(),
			Polizas = (await lector.ReadAsync<FlujoRealPoliza>()).ToList()
		};
	}

	public async Task<FlujoProyectado> ConsultarProyectadoAsync(DateTime hasta)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paFlujoCajaProyectadoConsultar", new { Hasta = hasta.Date },
			commandType: CommandType.StoredProcedure, commandTimeout: 120);
		return new FlujoProyectado
		{
			SaldoInicial = await lector.ReadFirstAsync<decimal>(),
			Items = (await lector.ReadAsync<FlujoProyectadoItem>()).ToList()
		};
	}

	public async Task<IReadOnlyList<PartidaProyectada>> ConsultarPartidasAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<PartidaProyectada>("dbo.paFlujoCajaPartidaConsultar", commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> GuardarPartidaAsync(PartidaProyectada partida, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters();
		parametros.Add("@FcpId", partida.FcpId == 0 ? null : partida.FcpId, DbType.Int32, ParameterDirection.InputOutput);
		parametros.Add("@Fecha", partida.Fecha.Date, DbType.Date);
		parametros.Add("@Actividad", partida.Actividad);
		parametros.Add("@Concepto", partida.Concepto);
		parametros.Add("@Monto", partida.Monto);
		parametros.Add("@Recurrencia", partida.Recurrencia);
		parametros.Add("@FechaFin", partida.FechaFin?.Date, DbType.Date);
		parametros.Add("@Estado", partida.Estado);
		parametros.Add("@UsuId", usuarioAccionId);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paFlujoCajaPartidaGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@FcpId");
	}

	public async Task<IReadOnlyList<CuentaEfectivo>> ConsultarCuentasAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<CuentaEfectivo>("dbo.paFlujoCajaCuentaConsultar", commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task GuardarCuentasAsync(IReadOnlyList<int> cuentas, int? usuarioAccionId)
	{
		var tabla = new DataTable();
		tabla.Columns.Add("id", typeof(int));
		foreach (var id in cuentas) tabla.Rows.Add(id);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paFlujoCajaCuentaGuardar",
			new { Cuentas = tabla.AsTableValuedParameter("dbo.id_lista_type"), UsuId = usuarioAccionId }, commandType: CommandType.StoredProcedure);
	}
}
