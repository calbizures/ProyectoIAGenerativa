namespace Erp.Data.Compras;

public interface ICompraRepository
{
	Task<IReadOnlyList<Proveedor>> ConsultarProveedoresAsync(string? texto, string? estado);
	Task<IReadOnlyList<DocumentoTipoCompra>> ConsultarTiposDocumentoAsync();
	Task<IReadOnlyList<Moneda>> ConsultarMonedasAsync();
	Task<int> CrearAsync(NuevaCompraEncabezado encabezado, IReadOnlyList<NuevaLineaCompra> detalle, int? usuarioAccionId);
	Task AnularAsync(int encId, int? usuarioAccionId);
	Task<IReadOnlyList<CompraEncabezado>> ConsultarAsync(IReadOnlyList<int> tiposDocumento, int? prvId, DateTime? fechaDesde, DateTime? fechaHasta, string? estado, int pagina, int tamanioPagina);
	Task<(CompraEncabezadoDetalle? Encabezado, IReadOnlyList<CompraDetalleLinea> Detalle)> ConsultarPorIdAsync(int encId);
}
