using System.Data;
using Dapper;

namespace Erp.Data.CajaChica;

public sealed class CajaChicaRepository(IDbConnectionFactory connectionFactory) : ICajaChicaRepository
{
	public async Task<IReadOnlyList<FondoCajaChica>> ConsultarFondosAsync(int? cchId, bool soloActivos)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<FondoCajaChica>("dbo.paCajaChicaFondoConsultar", new { CchId = cchId, SoloActivos = soloActivos },
			commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> GuardarFondoAsync(FondoCajaChica fondo, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters();
		parametros.Add("@CchId", fondo.CchId == 0 ? null : fondo.CchId, DbType.Int32, ParameterDirection.InputOutput);
		parametros.Add("@Nombre", fondo.Nombre);
		parametros.Add("@SucId", fondo.SucId);
		parametros.Add("@Responsable", fondo.Responsable);
		parametros.Add("@MontoAutorizado", fondo.MontoAutorizado);
		parametros.Add("@CtaId", fondo.CtaId == 0 ? null : fondo.CtaId);
		parametros.Add("@Estado", fondo.Estado);
		parametros.Add("@UsuId", usuarioAccionId);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCajaChicaFondoGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@CchId");
	}

	public async Task<int> EmitirChequeAsync(int cchId, string tipo, int cbcId, string? numero, DateTime fecha, decimal? monto, int? lccId, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters();
		parametros.Add("@CchId", cchId);
		parametros.Add("@Tipo", tipo);
		parametros.Add("@CbcId", cbcId);
		parametros.Add("@Numero", string.IsNullOrWhiteSpace(numero) ? null : numero.Trim());
		parametros.Add("@Fecha", fecha.Date, DbType.Date);
		parametros.Add("@Monto", monto);
		parametros.Add("@LccId", lccId);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@BceId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCajaChicaFondoCheque", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@BceId");
	}

	public async Task<IReadOnlyList<ChequeCajaChica>> ConsultarChequesAsync(int cchId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<ChequeCajaChica>("dbo.paCajaChicaChequesConsultar", new { CchId = cchId }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<IReadOnlyList<GastoCajaChica>> ConsultarGastosAsync(int cchId, string? estado, int? lccId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<GastoCajaChica>("dbo.paCajaChicaGastoConsultar",
			new { CchId = cchId, Estado = string.IsNullOrEmpty(estado) ? null : estado, LccId = lccId }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> GuardarGastoAsync(GastoCajaChica gasto, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters();
		parametros.Add("@CcgId", gasto.CcgId, DbType.Int32, ParameterDirection.InputOutput);
		parametros.Add("@CchId", gasto.CchId);
		parametros.Add("@Fecha", gasto.Fecha.Date, DbType.Date);
		parametros.Add("@Tipo", gasto.Tipo);
		parametros.Add("@PrvId", gasto.PrvId);
		parametros.Add("@Nit", gasto.Nit);
		parametros.Add("@Proveedor", gasto.Proveedor);
		parametros.Add("@Serie", gasto.Serie);
		parametros.Add("@Numero", gasto.Numero);
		parametros.Add("@Concepto", gasto.Concepto);
		parametros.Add("@CtaId", gasto.CtaId);
		parametros.Add("@IdDepartamento", gasto.IdDepartamento);
		parametros.Add("@Total", gasto.Total);
		parametros.Add("@UsuId", usuarioAccionId);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCajaChicaGastoGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@CcgId");
	}

	public async Task AnularGastoAsync(int ccgId, string motivo, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCajaChicaGastoAnular", new { CcgId = ccgId, Motivo = motivo, UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}

	public async Task<(int LccId, string Numero)> LiquidarAsync(int cchId, DateTime fecha, IReadOnlyList<int> gastos, int? usuarioAccionId)
	{
		var tabla = new DataTable();
		tabla.Columns.Add("id", typeof(int));
		foreach (var id in gastos) tabla.Rows.Add(id);
		var parametros = new DynamicParameters();
		parametros.Add("@CchId", cchId);
		parametros.Add("@Fecha", fecha.Date, DbType.Date);
		parametros.Add("@Gastos", tabla.AsTableValuedParameter("dbo.id_lista_type"));
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@LccId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		parametros.Add("@Numero", dbType: DbType.String, direction: ParameterDirection.Output, size: 12);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCajaChicaLiquidar", parametros, commandType: CommandType.StoredProcedure);
		return (parametros.Get<int>("@LccId"), parametros.Get<string>("@Numero"));
	}

	public async Task<IReadOnlyList<LiquidacionCajaChica>> ConsultarLiquidacionesAsync(int? cchId, int? lccId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<LiquidacionCajaChica>("dbo.paCajaChicaLiquidacionConsultar", new { CchId = cchId, LccId = lccId },
			commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task AnularLiquidacionAsync(int lccId, string motivo, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCajaChicaLiquidacionAnular", new { LccId = lccId, Motivo = motivo, UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}

	public async Task<decimal> GrabarArqueoAsync(int cchId, decimal efectivo, string? observaciones, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters();
		parametros.Add("@CchId", cchId);
		parametros.Add("@Efectivo", efectivo);
		parametros.Add("@Observaciones", observaciones);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@Diferencia", dbType: DbType.Decimal, direction: ParameterDirection.Output, precision: 12, scale: 2);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCajaChicaArqueoGrabar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<decimal>("@Diferencia");
	}

	public async Task<IReadOnlyList<ArqueoCajaChica>> ConsultarArqueosAsync(int cchId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<ArqueoCajaChica>("dbo.paCajaChicaArqueoConsultar", new { CchId = cchId }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}
}
