namespace Erp.Data.Ventas;

public interface ICotizacionRepository
{
	// estado: V vigentes, X vencidas, F facturadas, A anuladas, null todas.
	Task<IReadOnlyList<CotizacionResumen>> ConsultarAsync(int? sucId, DateTime? desde, DateTime? hasta, string? estado, string? texto);
	Task<(CotizacionEncabezado? Encabezado, IReadOnlyList<CotizacionLinea> Lineas)> ConsultarPorIdAsync(int cotId);
	Task<(int CotId, string Numero)> GuardarAsync(NuevaCotizacion cotizacion, IReadOnlyList<NuevaLineaCotizacion> lineas, int? usuarioAccionId);
	Task AnularAsync(int cotId, string motivo, int? usuarioAccionId);
}
