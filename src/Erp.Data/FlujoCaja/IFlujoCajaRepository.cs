namespace Erp.Data.FlujoCaja;

public interface IFlujoCajaRepository
{
	// Agrupar: S semana, M mes.
	Task<FlujoReal> ConsultarRealAsync(DateTime desde, DateTime hasta, string agrupar);
	Task<FlujoProyectado> ConsultarProyectadoAsync(DateTime hasta);
	Task<IReadOnlyList<PartidaProyectada>> ConsultarPartidasAsync();
	Task<int> GuardarPartidaAsync(PartidaProyectada partida, int? usuarioAccionId);
	Task<IReadOnlyList<CuentaEfectivo>> ConsultarCuentasAsync();
	Task GuardarCuentasAsync(IReadOnlyList<int> cuentas, int? usuarioAccionId);
}
