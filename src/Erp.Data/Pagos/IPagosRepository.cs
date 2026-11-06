namespace Erp.Data.Pagos;

// Contraseñas de pago, pago programado (cheque o transferencia), lotes de
// transferencias y formatos del archivo de cada banco.
public interface IPagosRepository
{
	Task<ProveedorPago?> ConsultarProveedorPagoAsync(int prvId);
	Task GuardarProveedorPagoAsync(ProveedorPago pago, int? usuarioAccionId);
	Task<int?> ConsultarDiaPagoAsync(int ciaId);
	Task<int?> ConsultarDiaPagoSucursalAsync(int sucId);
	Task GuardarDiaPagoAsync(int ciaId, int? diaPago, int? usuarioAccionId);

	Task<IReadOnlyList<ContrasenaCuotaDisponible>> ConsultarCuotasDisponiblesAsync(int prvId);
	Task<IReadOnlyList<ContrasenaResumen>> ConsultarContrasenasAsync(string? estado, int? prvId, DateTime? desde, DateTime? hasta, DateTime? pagoHasta, string? formaPago);
	Task<Contrasena?> ConsultarContrasenaAsync(int cpaId);
	Task<(int CpaId, string Numero)> EmitirContrasenaAsync(int prvId, int sucId, DateTime? fechaPago, string? formaPago, string? observaciones,
		IReadOnlyList<ContrasenaCuota> cuotas, int? usuarioAccionId);
	Task AnularContrasenaAsync(int cpaId, string motivo, int? usuarioAccionId);
	Task<int> PagarContrasenaChequeAsync(int cpaId, int cbcId, string? numero, int? usuarioAccionId);
	Task<(int BltId, string Numero)> PagarTransferenciaAsync(int bcbId, DateTime fecha, string? referencia, IReadOnlyList<int> contrasenas, int? usuarioAccionId);

	Task<IReadOnlyList<LoteTransferencia>> ConsultarLotesAsync(DateTime? desde, DateTime? hasta);
	Task AnularLoteAsync(int bltId, string motivo, int? usuarioAccionId);
	Task<ArchivoBancoDatos> ConsultarArchivoLoteAsync(int bltId);
	Task<ArchivoBancoDatos> ConsultarArchivoNominaAsync(int idNominaPago);

	Task<IReadOnlyList<FormatoArchivo>> ConsultarFormatosAsync(int? bfaId, bool soloActivos);
	Task<int> GuardarFormatoAsync(FormatoArchivo formato, int? usuarioAccionId);
}
