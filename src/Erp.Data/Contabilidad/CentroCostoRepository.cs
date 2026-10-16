using System.Data;
using Dapper;

namespace Erp.Data.Contabilidad;

public sealed class CentroCostoRepository(IDbConnectionFactory connectionFactory) : ICentroCostoRepository
{
	public async Task<IReadOnlyList<CentroCostoFila>> ConsultarAsync(DateTime desde, DateTime hasta, int? idDepartamento)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<CentroCostoFila>("dbo.paContabilidadCentroCostoConsultar",
			new { Desde = desde.Date, Hasta = hasta.Date, IdDepartamento = idDepartamento }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<IReadOnlyList<CentroCostoLinea>> ConsultarDetalleAsync(DateTime desde, DateTime hasta, int idDepartamento, int? ctaId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<CentroCostoLinea>("dbo.paContabilidadCentroCostoDetalle",
			new { Desde = desde.Date, Hasta = hasta.Date, IdDepartamento = idDepartamento, CtaId = ctaId }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}
}
