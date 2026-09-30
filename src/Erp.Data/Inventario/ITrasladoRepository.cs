namespace Erp.Data.Inventario;

public interface ITrasladoRepository
{
	Task<IReadOnlyList<Traslado>> ConsultarAsync(int? sucId, string? estado, DateTime? desde, DateTime? hasta);
	Task<IReadOnlyList<TrasladoLinea>> ConsultarLineasAsync(int traId);
	Task<IReadOnlyList<ProductoTrasladable>> ConsultarProductosAsync(int bodId, string? texto);
	Task<int> EnviarAsync(int bodIdOrigen, int bodIdDestino, string? observaciones, IReadOnlyList<(int ProId, decimal Cantidad)> lineas, int? usuarioAccionId);
	// Recibidas: cantidad por producto (las que no se indican llegan completas);
	// diferencia D = devolver a origen, P = pérdida.
	Task RecibirAsync(int traId, IReadOnlyList<(int ProId, decimal Cantidad)> recibidas, string diferencia, string? nota, int? usuarioAccionId);
	Task DevolverAsync(int traId, string motivo, bool esCancelacion, int? usuarioAccionId);
}
