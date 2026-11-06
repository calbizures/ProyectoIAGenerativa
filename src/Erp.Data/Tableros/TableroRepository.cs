using System.Data;
using Dapper;

namespace Erp.Data.Tableros;

public interface ITableroRepository
{
	Task<TableroVentas> ConsultarVentasAsync(DateTime desde, DateTime hasta, int? sucId);
	Task<TableroCartera> ConsultarCarteraAsync(DateTime desde, DateTime hasta, int? sucId);
	Task<TableroCompras> ConsultarComprasAsync(DateTime desde, DateTime hasta, int? sucId);
}

public sealed class TableroRepository(IDbConnectionFactory connectionFactory) : ITableroRepository
{
	private static object Parametros(DateTime desde, DateTime hasta, int? sucId) => new { Desde = desde.Date, Hasta = hasta.Date, SucId = sucId };

	public async Task<TableroVentas> ConsultarVentasAsync(DateTime desde, DateTime hasta, int? sucId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paTableroVentas", Parametros(desde, hasta, sucId), commandType: CommandType.StoredProcedure);
		var kpi = await lector.ReadSingleAsync<VentasKpi>();
		var periodos = (await lector.ReadAsync<VentasPeriodo>()).ToList();
		var clientes = (await lector.ReadAsync<RankingFila>()).ToList();
		var productos = (await lector.ReadAsync<RankingFila>()).ToList();
		var vendedores = (await lector.ReadAsync<RankingFila>()).ToList();
		return new TableroVentas(kpi, periodos, clientes, productos, vendedores);
	}

	public async Task<TableroCartera> ConsultarCarteraAsync(DateTime desde, DateTime hasta, int? sucId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paTableroCartera", Parametros(desde, hasta, sucId), commandType: CommandType.StoredProcedure);
		var kpi = await lector.ReadSingleAsync<CarteraKpi>();
		var periodos = (await lector.ReadAsync<CarteraPeriodo>()).ToList();
		var antiguedad = (await lector.ReadAsync<AntiguedadRango>()).ToList();
		var deudores = (await lector.ReadAsync<Deudor>()).ToList();
		var formas = (await lector.ReadAsync<MontoPorNombre>()).ToList();
		return new TableroCartera(kpi, periodos, antiguedad, deudores, formas);
	}

	public async Task<TableroCompras> ConsultarComprasAsync(DateTime desde, DateTime hasta, int? sucId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paTableroCompras", Parametros(desde, hasta, sucId), commandType: CommandType.StoredProcedure);
		var kpi = await lector.ReadSingleAsync<ComprasKpi>();
		var periodos = (await lector.ReadAsync<ComprasPeriodo>()).ToList();
		var proveedores = (await lector.ReadAsync<ProveedorRanking>()).ToList();
		var compromisos = (await lector.ReadAsync<CompromisoSemana>()).ToList();
		var proximas = (await lector.ReadAsync<CuotaPorPagar>()).ToList();
		return new TableroCompras(kpi, periodos, proveedores, compromisos, proximas);
	}
}
