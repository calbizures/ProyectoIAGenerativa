namespace Erp.Data.ActivosFijos;

public interface IActivosFijosRepository
{
	Task<IReadOnlyList<CategoriaActivo>> ConsultarCategoriasAsync(bool soloActivas);
	Task<int> GuardarCategoriaAsync(CategoriaActivo categoria, int? usuarioAccionId);

	Task<IReadOnlyList<ActivoFijo>> ConsultarAsync(int? afaId, int? afcId, int? sucId, string? estado, string? texto);
	Task<int> GuardarAsync(ActivoFijo activo, int? usuarioAccionId);
	Task<IReadOnlyList<DepreciacionMes>> ConsultarHistorialAsync(int afaId);
	// Tipo: B baja, V venta (con precio y cuenta de cobro).
	Task DarDeBajaAsync(int afaId, string tipo, DateTime fecha, string motivo, decimal? precioVenta, int? ctaIdCobro, int? usuarioAccionId);

	Task<IReadOnlyList<DepreciacionPrevia>> ConsultarDepreciacionPreviaAsync(int anio, int mes);
	Task<IReadOnlyList<DepreciacionCorrida>> ConsultarCorridasAsync();
	Task<int> DepreciarAsync(int anio, int mes, int? usuarioAccionId);
	Task AnularCorridaAsync(int adcId, int? usuarioAccionId);
}
