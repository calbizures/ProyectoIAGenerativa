using Erp.Data.Security;

namespace Erp.Data.Caja;

public interface ICajaRepository
{
	// Catálogos
	Task<IReadOnlyList<Sucursal>> ConsultarSucursalesAsync();
	Task<IReadOnlyList<FormaPagoTipo>> ConsultarFormasPagoTipoAsync();
	Task<IReadOnlyList<EntidadFinanciera>> ConsultarEntidadesFinancierasAsync();

	// Cajas receptoras
	Task<int> InsertarCajaReceptoraAsync(string descripcion, int sucId, int? usuarioAccionId, bool calculaVuelto = false);
	Task ActualizarCajaReceptoraAsync(int pcrId, string descripcion, int sucId, int? usuarioAccionId, bool? calculaVuelto = null);
	Task RegistrarEfectivoRecibidoAsync(int? ppeId, int? encId, decimal recibido, int? usuarioAccionId);
	Task<EfectivoRecibido?> ConsultarEfectivoRecibidoAsync(int? ppeId, int? encId);
	Task EliminarCajaReceptoraAsync(int pcrId, int? usuarioAccionId);
	Task<IReadOnlyList<CajaReceptora>> ConsultarCajasReceptorasAsync(int? sucId, string? estado);

	// Apertura / cierre
	Task<int> AbrirCajaAsync(int pcrId, decimal montoInicial, int? usuarioId);
	Task<IReadOnlyList<CajaAperturaActiva>> ConsultarAperturaActivaPorSucursalAsync(int sucId);
	Task<IReadOnlyList<CajaApertura>> ConsultarAperturasAsync(int? sucId, string? estado, int pagina, int tamanioPagina);
	Task CerrarCajaAsync(int pcaId, int? usuarioId);

	// Corte de caja
	Task<IReadOnlyList<FormaPagoTeorico>> ConsultarTeoricoAsync(int pcaId);
	Task<CuadreCaja?> ConsultarCuadreAsync(int pcaId);
	Task GuardarDesgloseEfectivoAsync(int pcaId, IReadOnlyList<DenominacionEfectivo> denominaciones, int? usuarioAccionId);
	Task GuardarCorteFormaAsync(int pcaId, IReadOnlyList<CorteFormaFisico> formas, int? usuarioAccionId);

	// Depósitos
	Task<int> InsertarDepositoAsync(int pcaId, int bcbId, DateTime fecha, decimal valor, string? numeroBoleta, string? observaciones, int? usuarioAccionId);
	Task<IReadOnlyList<DepositoCaja>> ConsultarDepositosAsync(int? pcaId);
}
