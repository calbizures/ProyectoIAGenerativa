namespace Erp.Data.Compras;

public interface IProveedorRepository
{
	Task<int> InsertarAsync(string codigo, string nombreComercial, string? nit, string? contacto, string? direccion, string? telefonoOficina, string? emailEmpresa, int? usuarioAccionId);
	Task ActualizarAsync(int prvId, string nombreComercial, string? nit, string? contacto, string? direccion, string? telefonoOficina, string? emailEmpresa, int? usuarioAccionId);
	Task EliminarAsync(int prvId, int? usuarioAccionId);
	Task<IReadOnlyList<Proveedor>> ConsultarAsync(string? texto, string? estado);
	Task<Proveedor?> ConsultarPorIdAsync(int prvId);
}
