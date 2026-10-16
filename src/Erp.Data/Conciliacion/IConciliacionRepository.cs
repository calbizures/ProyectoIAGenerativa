namespace Erp.Data.Conciliacion;

public interface IConciliacionRepository
{
	Task<IReadOnlyList<ConciliacionBancaria>> ConsultarAsync(int? bcbId);
	Task<int> CrearAsync(int bcbId, int anio, int mes, decimal? saldoInicialBanco, decimal? saldoBanco, int? usuarioAccionId);
	Task GuardarSaldosAsync(int bcnId, decimal saldoInicialBanco, decimal saldoBanco, int? usuarioAccionId);
	Task EliminarAsync(int bcnId);
	Task<ConciliacionDetalle?> ConsultarDetalleAsync(int bcnId);
	Task CargarExtractoAsync(int bcnId, IReadOnlyList<NuevaLineaExtracto> lineas, bool reemplazar, int? usuarioAccionId);
	Task EliminarLineaExtractoAsync(int bexId);
	Task<int> ConciliarAutomaticoAsync(int bcnId);
	Task EmparejarAsync(int bcnId, int bexId, int asdId);
	Task DesemparejarAsync(int bcnId, int? bexId, int? asdId);
	Task MarcarLibroAsync(int bcnId, int asdId, bool marcar);
	Task<int> GrabarAjusteAsync(int bcnId, int bexId, int? ctaId, string? descripcion, int? usuarioAccionId);
	Task CerrarAsync(int bcnId, int? usuarioAccionId);
	Task ReabrirAsync(int bcnId, int? usuarioAccionId);
}
