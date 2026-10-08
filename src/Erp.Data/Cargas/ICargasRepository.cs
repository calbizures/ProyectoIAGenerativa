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
}
