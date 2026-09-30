namespace Erp.Data.Ventas;

public interface IClienteRepository
{
	Task<int> InsertarAsync(string codigo, string nombres, string? apellidos, string? direccion, string? telefonoCelular, string? nit, string? email, decimal limiteCredito, int? usuarioAccionId);
	Task ActualizarAsync(int cliId, string nombres, string? apellidos, string? direccion, string? telefonoCelular, string? nit, string? email, decimal limiteCredito, int? usuarioAccionId);
	Task EliminarAsync(int cliId, int? usuarioAccionId);
	Task<IReadOnlyList<Cliente>> ConsultarAsync(string? texto, string? estado);
	Task<Cliente?> ConsultarPorIdAsync(int cliId);
	Task<IReadOnlyList<FacturaCliente>> ConsultarFacturasAsync(int cliId);
	// Cliente por NIT (normalizado: sin guiones ni espacios; C/F = CF).
	Task<Cliente?> BuscarPorNitAsync(string nit);
	// Devuelve el cliente con ese NIT o lo registra con el nombre dado.
	Task<(int CliId, bool Nuevo)> RegistrarPorNitAsync(string nit, string? nombre, string? direccion, int? usuarioAccionId);
}
