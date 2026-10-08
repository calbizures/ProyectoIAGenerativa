namespace Erp.Data.Contabilidad;

public interface ILibrosRepository
{
	Task<IReadOnlyList<Poliza>> ConsultarPolizasAsync(DateTime? desde, DateTime? hasta, string? origen, string? estado, string? texto, int? ctaId);
	Task<Poliza?> ConsultarPolizaAsync(int asiId);
	Task<int> GrabarPolizaManualAsync(DateTime fecha, string descripcion, IReadOnlyList<PolizaManualLinea> lineas, int? usuarioAccionId);
	Task AnularPolizaAsync(int asiId, string motivo, int? usuarioAccionId);

	Task<IReadOnlyList<LibroDiarioLinea>> ConsultarLibroDiarioAsync(DateTime desde, DateTime hasta);
	Task<IReadOnlyList<MayorCuenta>> ConsultarLibroMayorAsync(DateTime desde, DateTime hasta, int? ctaId);
	Task<IReadOnlyList<BalanzaFila>> ConsultarBalanzaAsync(DateTime desde, DateTime hasta, int nivel);

	Task<BalanceGeneral> ConsultarBalanceGeneralAsync(DateTime fecha, int nivel, DateTime? fechaComparativa);
	Task<EstadoResultados> ConsultarEstadoResultadosAsync(DateTime desde, DateTime hasta, int nivel, DateTime? desdeComparativo, DateTime? hastaComparativo);

	Task<(IReadOnlyList<PeriodoContable> Periodos, CierreAnual? Cierre)> ConsultarPeriodosAsync(int anio);
	Task CambiarEstadoPeriodoAsync(int anio, int mes, string estado, int? usuarioAccionId);
	Task<int> GenerarCierreAnualAsync(int anio, int? usuarioAccionId);
}
