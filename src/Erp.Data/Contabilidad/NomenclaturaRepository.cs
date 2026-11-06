using System.Data;
using Dapper;

namespace Erp.Data.Contabilidad;

// Todas las reglas de la jerarquía (posiciones del código, padre, movimiento
// solo en subcuentas) las valida la base de datos: procedimientos
// paCuentaContable*, restricciones CHECK y trg_cont_cuenta_contable_jerarquia.
public sealed class NomenclaturaRepository(IDbConnectionFactory connectionFactory) : INomenclaturaRepository
{
	public async Task<IReadOnlyList<NodoCuenta>> ConsultarArbolAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<NodoCuenta>("dbo.paCuentaContableArbolConsultar", commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<string> SiguienteCodigoAsync(int? idPadre)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@IdPadre", idPadre);
		parametros.Add("@Codigo", dbType: DbType.String, size: 20, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paCuentaContableSiguienteCodigo", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<string>("@Codigo");
	}

	public async Task<int> GuardarAsync(int? ctaId, int? idPadre, string codigo, string nombre, string? tipo, string? naturaleza, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@CtaId", ctaId);
		parametros.Add("@IdPadre", idPadre);
		parametros.Add("@Codigo", codigo);
		parametros.Add("@Nombre", nombre);
		parametros.Add("@Tipo", tipo);
		parametros.Add("@Naturaleza", naturaleza);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@IdResultado", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paCuentaContableNodoGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@IdResultado");
	}

	public async Task MoverAsync(int ctaId, int idPadreNuevo, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCuentaContableNodoMover",
			new { CtaId = ctaId, IdPadreNuevo = idPadreNuevo, UsuId = usuarioAccionId }, commandType: CommandType.StoredProcedure);
	}

	public async Task CambiarEstadoAsync(int ctaId, string estado, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCuentaContableNodoCambiarEstado",
			new { CtaId = ctaId, Estado = estado, UsuId = usuarioAccionId }, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int ctaId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCuentaContableNodoEliminar", new { CtaId = ctaId }, commandType: CommandType.StoredProcedure);
	}
}
