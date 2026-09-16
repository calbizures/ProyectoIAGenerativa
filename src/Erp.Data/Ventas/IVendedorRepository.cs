namespace Erp.Data.Ventas;

public interface IVendedorRepository
{
	Task<int> InsertarAsync(string codigo, string nombres, string? apellidos, DateTime? fechaIngreso, decimal porcentajeComision, int? usuarioAccionId);
	Task ActualizarAsync(int pveId, string nombres, string? apellidos, DateTime? fechaIngreso, decimal porcentajeComision, int? usuarioAccionId);
	Task EliminarAsync(int pveId, int? usuarioAccionId);
	Task<IReadOnlyList<Vendedor>> ConsultarAsync(string? estado);
	Task<Vendedor?> ConsultarPorIdAsync(int pveId);
}
