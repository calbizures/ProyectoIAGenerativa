namespace Erp.Data.Ventas;

public interface IFacturaRepository
{
	Task<IReadOnlyList<Cliente>> ConsultarClientesAsync(string? texto, string? estado);
	Task<IReadOnlyList<Vendedor>> ConsultarVendedoresAsync();
	Task<IReadOnlyList<Moneda>> ConsultarMonedasAsync();
	Task<IReadOnlyList<DocumentoTipoVenta>> ConsultarTiposDocumentoAsync();
	Task<(int EncId, string NumeroUnico)> CrearAsync(NuevaFacturaEncabezado encabezado, IReadOnlyList<NuevaLineaFactura> detalle, int? usuarioAccionId);
	Task AnularAsync(int encId, int? usuarioAccionId);
	Task<IReadOnlyList<FacturaEncabezado>> ConsultarAsync(int tdoId, int? cliId, DateTime? fechaDesde, DateTime? fechaHasta, string? estado, int pagina, int tamanioPagina);
	Task<(FacturaEncabezadoDetalle? Encabezado, IReadOnlyList<FacturaDetalleLinea> Detalle)> ConsultarPorIdAsync(int encId);
}
