namespace Erp.Data.Compras;

public interface IOrdenCompraRepository
{
	Task<IReadOnlyList<OrdenCompraResumen>> ConsultarAsync(string? estado, int? prvId, DateTime? desde, DateTime? hasta, string? texto);
	Task<(OrdenCompraEncabezado? Encabezado, IReadOnlyList<OrdenCompraLinea> Lineas, IReadOnlyList<OrdenCompraRecepcion> Recepciones)> ConsultarPorIdAsync(int ocpId);
	Task<(int OcpId, string Numero)> GuardarAsync(NuevaOrdenCompra orden, IReadOnlyList<NuevaLineaOrdenCompra> lineas, int? usuarioAccionId);
	Task AprobarBodegaAsync(int ocpId, int? usuarioAccionId);
	Task AprobarAsync(int ocpId, int? usuarioAccionId);
	Task DevolverAsync(int ocpId, string motivo, int? usuarioAccionId);
	Task AnularAsync(int ocpId, string motivo, int? usuarioAccionId);
	Task CerrarAsync(int ocpId, string motivo, int? usuarioAccionId);
	Task<int> RecibirAsync(int ocpId, RecepcionOrdenCompra recepcion, IReadOnlyList<LineaRecepcionOrdenCompra> lineas, int? usuarioAccionId);
}
