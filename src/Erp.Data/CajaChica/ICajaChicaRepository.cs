namespace Erp.Data.CajaChica;

public interface ICajaChicaRepository
{
	Task<IReadOnlyList<FondoCajaChica>> ConsultarFondosAsync(int? cchId, bool soloActivos);
	Task<int> GuardarFondoAsync(FondoCajaChica fondo, int? usuarioAccionId);
	// Tipo: C constitución, A aumento (con monto), R reposición (de una liquidación).
	Task<int> EmitirChequeAsync(int cchId, string tipo, int cbcId, string? numero, DateTime fecha, decimal? monto, int? lccId, int? usuarioAccionId);
	Task<IReadOnlyList<ChequeCajaChica>> ConsultarChequesAsync(int cchId);

	Task<IReadOnlyList<GastoCajaChica>> ConsultarGastosAsync(int cchId, string? estado, int? lccId);
	Task<int> GuardarGastoAsync(GastoCajaChica gasto, int? usuarioAccionId);
	Task AnularGastoAsync(int ccgId, string motivo, int? usuarioAccionId);

	Task<(int LccId, string Numero)> LiquidarAsync(int cchId, DateTime fecha, IReadOnlyList<int> gastos, int? usuarioAccionId);
	Task<IReadOnlyList<LiquidacionCajaChica>> ConsultarLiquidacionesAsync(int? cchId, int? lccId);
	Task AnularLiquidacionAsync(int lccId, string motivo, int? usuarioAccionId);

	Task<decimal> GrabarArqueoAsync(int cchId, decimal efectivo, string? observaciones, int? usuarioAccionId);
	Task<IReadOnlyList<ArqueoCajaChica>> ConsultarArqueosAsync(int cchId);
}
