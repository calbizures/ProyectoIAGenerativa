using Erp.Data.Caja;
using Erp.Data.Ventas;

namespace Erp.Data.Cuentas;

public interface ICuentasRepository
{
	// Cuentas por cobrar
	Task<IReadOnlyList<DocumentoSaldo>> ConsultarDocumentosCxcAsync(int? cliId, bool soloPendientes);
	Task<IReadOnlyList<MovimientoEstadoCuenta>> ConsultarEstadoCuentaClienteAsync(int cliId, DateTime? desde, DateTime? hasta);
	// usuId: solo los clientes que ese usuario puede ver (vendedor); null = todos.
	Task<IReadOnlyList<AntiguedadFila>> ConsultarAntiguedadClientesAsync(DateTime fechaCorte, int? cliId, int? usuId = null);
	Task<AntiguedadAlcance> ConsultarAntiguedadAlcanceAsync(int usuId);
	Task<IReadOnlyList<CuotaPlanPago>> ConsultarCuotasClienteAsync(int encId);
	Task<int> RegistrarCobroAsync(int cppId, decimal valor, int pcaId, IReadOnlyList<FormaPagoCaptura> formasPago, int? usuarioAccionId);
	Task<IReadOnlyList<CuotaPendiente>> ConsultarCuotasPendientesClienteAsync(int cliId);
	Task<int> RegistrarCobroCuotasAsync(int cliId, int pcaId, IReadOnlyList<CuotaCobro> cuotas, IReadOnlyList<FormaPagoCaptura> formasPago, int? usuarioAccionId);
	Task<IReadOnlyList<ReciboResumen>> ConsultarRecibosAsync(int? pcaId, int? cliId, DateTime? desde, DateTime? hasta);
	Task<ReciboDetalle?> ConsultarReciboAsync(int ppeId);
	Task AnularReciboAsync(int ppeId, string motivo, int? usuarioAccionId);
	Task<CreditoCliente?> ConsultarCreditoClienteAsync(int cliId);
	// Encabezado del estado de cuenta: contacto, límite, saldo, vencido y crédito disponible.
	Task<ClienteEstadoCuenta?> ConsultarDatosEstadoCuentaClienteAsync(int cliId);

	// Cuentas por pagar
	Task<IReadOnlyList<DocumentoSaldo>> ConsultarDocumentosCxpAsync(int? prvId, bool soloPendientes);
	Task<IReadOnlyList<MovimientoEstadoCuenta>> ConsultarEstadoCuentaProveedorAsync(int prvId, DateTime? desde, DateTime? hasta);
	Task<IReadOnlyList<AntiguedadFila>> ConsultarAntiguedadProveedoresAsync(DateTime fechaCorte, int? prvId);
	Task<IReadOnlyList<CuotaProveedor>> ConsultarCuotasProveedorAsync(int encId);
	Task<IReadOnlyList<Chequera>> ConsultarChequerasAsync();
	Task<IReadOnlyList<MotivoPago>> ConsultarMotivosPagoAsync();
	Task<IReadOnlyList<CuotaPendienteProveedor>> ConsultarCuotasPendientesProveedorAsync(int prvId, int? encId);
	Task<(int BceId, string Numero)> EmitirChequeAsync(int prvId, int cbcId, string? numeroCheque, int? bmpId, string? concepto,
		IReadOnlyList<CuotaPagoProveedor> cuotas, int? usuarioAccionId);
	Task<IReadOnlyList<ChequeDetalleLinea>> ConsultarChequeDetalleAsync(int bceId);
	Task<IReadOnlyList<ProveedorConSaldo>> ConsultarProveedoresConSaldoAsync();
	Task<IReadOnlyList<ChequeResumen>> ConsultarChequesAsync(int? prvId, DateTime? desde, DateTime? hasta);
	Task AnularChequeAsync(int bceId, string motivo, int? usuarioAccionId);
	// Transferencias ya hechas en el banco (con comprobante y autorización).
	Task<(int BltId, string Numero)> RegistrarTransferenciaAsync(TransferenciaProveedorCaptura transferencia, IReadOnlyList<CuotaPagoProveedor> cuotas,
		int? usuarioAccionId);
	Task<IReadOnlyList<TransferenciaResumen>> ConsultarTransferenciasAsync(int? prvId, DateTime? desde, DateTime? hasta);
	Task<IReadOnlyList<ChequeDetalleLinea>> ConsultarTransferenciaDetalleAsync(int bltId);
	Task<ComprobanteTransferencia?> ConsultarComprobanteTransferenciaAsync(int bltId);
	Task AnularTransferenciaAsync(int bltId, string motivo, int? usuarioAccionId);

	// Transferencias recibidas en caja (factura o cobro) y su comprobante.
	Task<IReadOnlyList<TransferenciaRecibida>> ConsultarTransferenciasPagoAsync(int? ppeId, int? encId);
	Task<ArchivoAdjunto?> ConsultarComprobantePagoAsync(int ppfId);

	// Pago con boleta: por verificar, verificar (recibo sin caja), rechazar o anular.
	Task<int> RegistrarBoletaAsync(BoletaCaptura boleta, IReadOnlyList<CuotaCobro> cuotas, int? usuarioAccionId);
	Task<int> VerificarBoletaAsync(int cboId, int? usuarioAccionId);
	Task RechazarBoletaAsync(int cboId, string motivo, int? usuarioAccionId);
	Task AnularBoletaAsync(int cboId, string motivo, int? usuarioAccionId);
	Task<IReadOnlyList<BoletaResumen>> ConsultarBoletasAsync(string? estado, int? cliId, DateTime? desde, DateTime? hasta);
	Task<IReadOnlyList<BoletaCuota>> ConsultarBoletaDetalleAsync(int cboId);
	Task<ArchivoAdjunto?> ConsultarComprobanteBoletaAsync(int cboId);

	// Notas de crédito y débito (NCC, NDC, NCP, NDP)
	Task<IReadOnlyList<NotaResumen>> ConsultarNotasAsync(bool esCliente, int? cliId, int? prvId, int? encIdReferencia);
	Task<IReadOnlyList<LineaDevolucion>> ConsultarLineasDevolucionAsync(int encId);
	Task<(int EncId, string? Numero)> CrearNotaAsync(string tipoNota, int encIdReferencia, DateTime fecha, string? numeroDocto, string motivo,
		DateTime? fechaVencimiento, IReadOnlyList<NuevaLineaNota> lineas, int? usuarioAccionId);
}
