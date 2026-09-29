using System.Data;
using Dapper;

namespace Erp.Data.Bancos;

public sealed class BancosRepository(IDbConnectionFactory connectionFactory) : IBancosRepository
{
	private async Task<IReadOnlyList<T>> ConsultarAsync<T>(string procedimiento, object? parametros = null)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<T>(procedimiento, parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	private async Task EjecutarAsync(string procedimiento, object parametros)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync(procedimiento, parametros, commandType: CommandType.StoredProcedure);
	}

	private async Task<int> GuardarAsync(string procedimiento, DynamicParameters parametros, string salida = "@IdResultado")
	{
		parametros.Add(salida, dbType: DbType.Int32, direction: ParameterDirection.Output);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync(procedimiento, parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>(salida);
	}

	public Task<IReadOnlyList<CuentaBancaria>> ConsultarCuentasAsync(bool soloActivas) =>
		ConsultarAsync<CuentaBancaria>("dbo.paBcoCuentaBancariaConsultar", new { SoloActivas = soloActivas });

	public Task<int> GuardarCuentaAsync(CuentaBancaria cuenta, int? usuarioAccionId) =>
		GuardarAsync("dbo.paBcoCuentaBancariaGuardar", new DynamicParameters(new
		{
			BcbId = cuenta.BcbId == 0 ? (int?)null : cuenta.BcbId,
			cuenta.NumeroCuenta,
			cuenta.Descripcion,
			cuenta.GefId,
			cuenta.Tipo,
			cuenta.CtaId,
			cuenta.Estado,
			UsuId = usuarioAccionId
		}));

	public Task<IReadOnlyList<Chequera>> ConsultarChequerasAsync(int? bcbId, bool soloActivas) =>
		ConsultarAsync<Chequera>("dbo.paBcoChequeraConsultar", new { BcbId = bcbId, SoloActivas = soloActivas });

	public Task<int> GuardarChequeraAsync(Chequera chequera, int? usuarioAccionId) =>
		GuardarAsync("dbo.paBcoChequeraGuardar", new DynamicParameters(new
		{
			CbcId = chequera.CbcId == 0 ? (int?)null : chequera.CbcId,
			chequera.BcbId,
			chequera.ChequeDel,
			chequera.ChequeAl,
			FechaRecepcion = chequera.FechaRecepcion?.Date,
			chequera.Estado,
			UsuId = usuarioAccionId
		}));

	public Task<IReadOnlyList<MotivoPago>> ConsultarMotivosAsync(bool soloActivos) =>
		ConsultarAsync<MotivoPago>("dbo.paBcoMotivoPagoConsultar", new { SoloActivos = soloActivos });

	public Task<int> GuardarMotivoAsync(int? bmpId, string descripcion, string estado, int? usuarioAccionId) =>
		GuardarAsync("dbo.paBcoMotivoPagoGuardar", new DynamicParameters(new { BmpId = bmpId, Descripcion = descripcion, Estado = estado, UsuId = usuarioAccionId }));

	public Task<IReadOnlyList<Cheque>> ConsultarChequesAsync(int? bcbId, string? tipo, string? estado, DateTime? desde, DateTime? hasta) =>
		ConsultarAsync<Cheque>("dbo.paBcoChequesConsultar", new { BcbId = bcbId, Tipo = tipo, Estado = estado, Desde = desde?.Date, Hasta = hasta?.Date });

	public Task<int> EmitirChequeLibreAsync(ChequeLibre cheque, int? usuarioAccionId) =>
		GuardarAsync("dbo.paBcoChequeEmitirLibre", new DynamicParameters(new
		{
			cheque.CbcId,
			Numero = string.IsNullOrWhiteSpace(cheque.Numero) ? null : cheque.Numero.Trim(),
			Fecha = cheque.Fecha.Date,
			cheque.Beneficiario,
			cheque.BmpId,
			cheque.CtaId,
			cheque.IdDepartamento,
			cheque.Valor,
			cheque.Observaciones,
			UsuId = usuarioAccionId
		}), "@BceId");

	public Task AnularChequeAsync(int bceId, string motivo, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paBcoChequeAnular", new { BceId = bceId, Motivo = motivo, UsuId = usuarioAccionId });

	public Task CobrarChequeAsync(int bceId, DateTime? fecha, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paBcoChequeCobrar", new { BceId = bceId, Fecha = fecha?.Date, UsuId = usuarioAccionId });
}
