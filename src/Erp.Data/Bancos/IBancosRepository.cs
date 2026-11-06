namespace Erp.Data.Bancos;

public interface IBancosRepository
{
	Task<IReadOnlyList<CuentaBancaria>> ConsultarCuentasAsync(bool soloActivas);
	Task<int> GuardarCuentaAsync(CuentaBancaria cuenta, int? usuarioAccionId);

	Task<IReadOnlyList<Chequera>> ConsultarChequerasAsync(int? bcbId, bool soloActivas);
	Task<int> GuardarChequeraAsync(Chequera chequera, int? usuarioAccionId);

	Task<IReadOnlyList<MotivoPago>> ConsultarMotivosAsync(bool soloActivos);
	Task<int> GuardarMotivoAsync(int? bmpId, string descripcion, string estado, int? usuarioAccionId);

	Task<IReadOnlyList<Cheque>> ConsultarChequesAsync(int? bcbId, string? tipo, string? estado, DateTime? desde, DateTime? hasta);
	Task<int> EmitirChequeLibreAsync(ChequeLibre cheque, int? usuarioAccionId);
	Task AnularChequeAsync(int bceId, string motivo, int? usuarioAccionId);
	Task CobrarChequeAsync(int bceId, DateTime? fecha, int? usuarioAccionId);
}
