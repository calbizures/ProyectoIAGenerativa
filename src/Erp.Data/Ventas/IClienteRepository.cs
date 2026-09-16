namespace Erp.Data.Ventas;

public interface IClienteRepository
{
	Task<int> InsertarAsync(string codigo, string nombres, string? apellidos, string? direccion, string? telefonoCelular, string? nit, string? email, decimal limiteCredito, int? usuarioAccionId);
	Task ActualizarAsync(int cliId, string nombres, string? apellidos, string? direccion, string? telefonoCelular, string? nit, string? email, decimal limiteCredito, int? usuarioAccionId);
	Task EliminarAsync(int cliId, int? usuarioAccionId);
	Task<IReadOnlyList<Cliente>> ConsultarAsync(string? texto, string? estado);
	Task<Cliente?> ConsultarPorIdAsync(int cliId);
}
