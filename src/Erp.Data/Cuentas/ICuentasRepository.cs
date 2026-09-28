using Erp.Data.Caja;
using Erp.Data.Ventas;

namespace Erp.Data.Cuentas;

public interface ICuentasRepository
{
	// Cuentas por cobrar
	Task<IReadOnlyList<DocumentoSaldo>> ConsultarDocumentosCxcAsync(int? cliId, bool soloPendientes);
	Task<IReadOnlyList<MovimientoEstadoCuenta>> ConsultarEstadoCuentaClienteAsync(int cliId, DateTime? desde, DateTime? hasta);
	Task<IReadOnlyList<AntiguedadFila>> ConsultarAntiguedadClientesAsync(DateTime fechaCorte, int? cliId);
	Task<IReadOnlyList<CuotaPlanPago>> ConsultarCuotasClienteAsync(int encId);
	Task<int> RegistrarCobroAsync(int cppId, decimal valor, int pcaId, IReadOnlyList<FormaPagoCaptura> formasPago, int? usuarioAccionId);

	// Cuentas por pagar
	Task<IReadOnlyList<DocumentoSaldo>> ConsultarDocumentosCxpAsync(int? prvId, bool soloPendientes);
	Task<IReadOnlyList<MovimientoEstadoCuenta>> ConsultarEstadoCuentaProveedorAsync(int prvId, DateTime? desde, DateTime? hasta);
	Task<IReadOnlyList<AntiguedadFila>> ConsultarAntiguedadProveedoresAsync(DateTime fechaCorte, int? prvId);
	Task<IReadOnlyList<CuotaProveedor>> ConsultarCuotasProveedorAsync(int encId);
	Task<IReadOnlyList<Chequera>> ConsultarChequerasAsync();
	Task<IReadOnlyList<MotivoPago>> ConsultarMotivosPagoAsync();
	Task<int> EmitirChequeAsync(int ppgId, int cbcId, string numeroCheque, decimal valor, int? bmpId, int? usuarioAccionId);

	// Notas de crédito y débito (NCC, NDC, NCP, NDP)
	Task<IReadOnlyList<NotaResumen>> ConsultarNotasAsync(bool esCliente, int? cliId, int? prvId, int? encIdReferencia);
	Task<IReadOnlyList<LineaDevolucion>> ConsultarLineasDevolucionAsync(int encId);
	Task<(int EncId, string? Numero)> CrearNotaAsync(string tipoNota, int encIdReferencia, DateTime fecha, string? numeroDocto, string motivo,
		DateTime? fechaVencimiento, IReadOnlyList<NuevaLineaNota> lineas, int? usuarioAccionId);
}
