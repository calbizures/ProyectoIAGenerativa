using System.Data;
using Dapper;

namespace Erp.Data.Conciliacion;

public sealed class ConciliacionRepository(IDbConnectionFactory connectionFactory) : IConciliacionRepository
{
	public async Task<IReadOnlyList<ConciliacionBancaria>> ConsultarAsync(int? bcbId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<ConciliacionBancaria>("dbo.paConciliacionConsultar", new { BcbId = bcbId }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> CrearAsync(int bcbId, int anio, int mes, decimal? saldoInicialBanco, decimal? saldoBanco, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters();
		parametros.Add("@BcbId", bcbId);
		parametros.Add("@Anio", anio);
		parametros.Add("@Mes", mes);
		parametros.Add("@SaldoInicialBanco", saldoInicialBanco);
		parametros.Add("@SaldoBanco", saldoBanco);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@BcnId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paConciliacionCrear", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@BcnId");
	}

	public Task GuardarSaldosAsync(int bcnId, decimal saldoInicialBanco, decimal saldoBanco, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paConciliacionGuardarSaldos", new { BcnId = bcnId, SaldoInicialBanco = saldoInicialBanco, SaldoBanco = saldoBanco, UsuId = usuarioAccionId });

	public Task EliminarAsync(int bcnId) => EjecutarAsync("dbo.paConciliacionEliminar", new { BcnId = bcnId });

	public async Task<ConciliacionDetalle?> ConsultarDetalleAsync(int bcnId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paConciliacionDetalle", new { BcnId = bcnId }, commandType: CommandType.StoredProcedure, commandTimeout: 120);
		var resumen = await lector.ReadFirstOrDefaultAsync<ConciliacionResumen>();
		if (resumen is null) return null;
		return new ConciliacionDetalle
		{
			Resumen = resumen,
			Extracto = (await lector.ReadAsync<LineaExtracto>()).ToList(),
			Libros = (await lector.ReadAsync<LineaLibro>()).ToList()
		};
	}

	public async Task CargarExtractoAsync(int bcnId, IReadOnlyList<NuevaLineaExtracto> lineas, bool reemplazar, int? usuarioAccionId)
	{
		var tabla = new DataTable();
		tabla.Columns.Add("bex_fecha", typeof(DateTime));
		tabla.Columns.Add("bex_descripcion", typeof(string));
		tabla.Columns.Add("bex_referencia", typeof(string));
		tabla.Columns.Add("bex_debito", typeof(decimal));
		tabla.Columns.Add("bex_credito", typeof(decimal));
		foreach (var l in lineas)
			tabla.Rows.Add(l.Fecha.Date, (object?)Recortar(l.Descripcion, 250) ?? DBNull.Value, (object?)Recortar(l.Referencia, 50) ?? DBNull.Value, l.Debito, l.Credito);
		await EjecutarAsync("dbo.paConciliacionExtractoCargar",
			new { BcnId = bcnId, Lineas = tabla.AsTableValuedParameter("dbo.bco_extracto_type"), Reemplazar = reemplazar, UsuId = usuarioAccionId });
	}

	public Task EliminarLineaExtractoAsync(int bexId) => EjecutarAsync("dbo.paConciliacionExtractoEliminar", new { BexId = bexId });

	public async Task<int> ConciliarAutomaticoAsync(int bcnId)
	{
		var parametros = new DynamicParameters();
		parametros.Add("@BcnId", bcnId);
		parametros.Add("@Emparejadas", dbType: DbType.Int32, direction: ParameterDirection.Output);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paConciliacionAutomatica", parametros, commandType: CommandType.StoredProcedure, commandTimeout: 120);
		return parametros.Get<int>("@Emparejadas");
	}

	public Task EmparejarAsync(int bcnId, int bexId, int asdId) =>
		EjecutarAsync("dbo.paConciliacionEmparejar", new { BcnId = bcnId, BexId = bexId, AsdId = asdId, Forma = "M" });

	public Task DesemparejarAsync(int bcnId, int? bexId, int? asdId) =>
		EjecutarAsync("dbo.paConciliacionDesemparejar", new { BcnId = bcnId, BexId = bexId, AsdId = asdId });

	public Task MarcarLibroAsync(int bcnId, int asdId, bool marcar) =>
		EjecutarAsync("dbo.paConciliacionMarcarLibro", new { BcnId = bcnId, AsdId = asdId, Marcar = marcar });

	public async Task<int> GrabarAjusteAsync(int bcnId, int bexId, int? ctaId, string? descripcion, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters();
		parametros.Add("@BcnId", bcnId);
		parametros.Add("@BexId", bexId);
		parametros.Add("@CtaId", ctaId);
		parametros.Add("@Descripcion", string.IsNullOrWhiteSpace(descripcion) ? null : descripcion.Trim());
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@AsiId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paConciliacionAjuste", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@AsiId");
	}

	public Task CerrarAsync(int bcnId, int? usuarioAccionId) => EjecutarAsync("dbo.paConciliacionCerrar", new { BcnId = bcnId, UsuId = usuarioAccionId });

	public Task ReabrirAsync(int bcnId, int? usuarioAccionId) => EjecutarAsync("dbo.paConciliacionReabrir", new { BcnId = bcnId, UsuId = usuarioAccionId });

	private async Task EjecutarAsync(string procedimiento, object parametros)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync(procedimiento, parametros, commandType: CommandType.StoredProcedure, commandTimeout: 120);
	}

	private static string? Recortar(string? texto, int largo) =>
		string.IsNullOrWhiteSpace(texto) ? null : texto.Trim().Length > largo ? texto.Trim()[..largo] : texto.Trim();
}
