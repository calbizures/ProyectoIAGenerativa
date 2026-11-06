namespace Erp.Data.Cargas;

public interface ICargasRepository
{
	Task<ResultadoCarga<ResumenInventarioInicial>> ProcesarInventarioInicialAsync(DateTime fecha, IReadOnlyList<FilaInventarioInicial> filas, bool soloValidar, int? usuarioAccionId);
	Task<IReadOnlyList<CargaInventarioInicial>> ConsultarInventarioInicialAsync();
	Task AnularInventarioInicialAsync(int encId, int? usuarioAccionId);

	Task<IReadOnlyList<CuentaSaldoInicial>> ConsultarPlantillaSaldosAsync();
	Task<ResultadoCarga<ResumenSaldosIniciales>> ProcesarSaldosInicialesAsync(DateTime fecha, IReadOnlyList<FilaSaldoInicial> filas, bool soloValidar, bool reemplazar, int? usuarioAccionId);
	Task<(PartidaApertura? Partida, IReadOnlyList<LineaApertura> Lineas)> ConsultarAperturaAsync();

	Task<ResultadoCarga<ResumenEmpleados>> ProcesarEmpleadosAsync(int ciaId, IReadOnlyList<FilaEmpleado> filas, bool soloValidar, int? usuarioAccionId);

	// Documentos pendientes iniciales: modulo "CXC" o "CXP".
	Task<ResultadoCarga<ResumenDocumentosPendientes>> ProcesarDocumentosPendientesAsync(string modulo, DateTime fecha, IReadOnlyList<FilaDocumentoPendiente> filas,
		string? archivo, bool soloValidar, int? usuarioAccionId);
	Task<(IReadOnlyList<CargaDocumentosPendientes> Cargas, IReadOnlyList<DocumentoPendienteCargado> Documentos)> ConsultarDocumentosPendientesAsync(string modulo);
	Task AnularDocumentosPendientesAsync(int cscId, string motivo, int? usuarioAccionId);
}
