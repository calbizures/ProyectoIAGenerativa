using Erp.Data.Caja;

namespace Erp.Data.General;

public interface IGeneralRepository
{
	Task<IReadOnlyList<NitRevision>> ConsultarNitRevisionAsync();
	// Compañía y parámetros de uso general
	Task<IReadOnlyList<Compania>> ConsultarCompaniasAsync(bool soloActivas);
	Task<int> GuardarCompaniaAsync(Compania compania, int? usuarioAccionId);
	Task CambiarEstadoCompaniaAsync(int ciaId, string estado, int? usuarioAccionId);
	Task<ParametrosCompania> ConsultarParametrosAsync(int? sucId);
	Task GuardarLogoAsync(int ciaId, byte[]? logo, string? tipo, int? usuarioAccionId);
	// Sin ciaId: la compañía de la sucursal o la primera activa.
	Task<CompaniaLogo?> ConsultarLogoAsync(int? ciaId, int? sucId, bool soloVersion);

	Task<IReadOnlyList<SucursalDetalle>> ConsultarSucursalesAsync(int? ciaId, bool soloActivas);
	Task<int> GuardarSucursalAsync(SucursalDetalle sucursal, int? usuarioAccionId);
	Task CambiarEstadoSucursalAsync(int sucId, string estado, int? usuarioAccionId);

	// Entidades financieras (maestro: tipo, detalle: entidad)
	Task<IReadOnlyList<EntidadFinancieraTipo>> ConsultarTiposEntidadAsync();
	Task<int> GuardarTipoEntidadAsync(int? geftId, string descripcion, int? usuarioAccionId);
	Task EliminarTipoEntidadAsync(int geftId);
	Task<IReadOnlyList<EntidadFinanciera>> ConsultarEntidadesAsync(int? geftId, bool soloActivas);
	Task<int> GuardarEntidadAsync(int? gefId, int geftId, string codigo, string descripcion, string estado, int? usuarioAccionId);
	Task EliminarEntidadAsync(int gefId);

	// Cuentas contables y conceptos de póliza automática
	Task<IReadOnlyList<CuentaContable>> ConsultarCuentasContablesAsync();
	Task<IReadOnlyList<CuentaParametro>> ConsultarCuentasParametroAsync();
	Task GuardarCuentaParametroAsync(string codigo, int ctaId, int? usuarioAccionId);
}
