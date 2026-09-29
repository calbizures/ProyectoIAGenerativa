namespace Erp.Data.Contabilidad;

public interface ICentroCostoRepository
{
	Task<IReadOnlyList<CentroCostoFila>> ConsultarAsync(DateTime desde, DateTime hasta, int? idDepartamento);
	Task<IReadOnlyList<CentroCostoLinea>> ConsultarDetalleAsync(DateTime desde, DateTime hasta, int idDepartamento, int? ctaId);
}
