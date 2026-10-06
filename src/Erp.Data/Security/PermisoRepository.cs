using System.Data;
using Dapper;

namespace Erp.Data.Security;

public sealed class PermisoRepository(IDbConnectionFactory connectionFactory) : IPermisoRepository
{
	public async Task<int> InsertarAsync(string modulo, string codigo, string? descripcion, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@PerModulo", modulo);
		parametros.Add("@PerCodigo", codigo);
		parametros.Add("@PerDescripcion", descripcion);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@PerId", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.paPermisoInsertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@PerId");
	}

	public async Task<IReadOnlyList<Permiso>> ConsultarAsync(string? modulo, string? estado, string? texto = null)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<Permiso>(
			"dbo.paPermisoConsultar",
			new { PerModulo = modulo, PerEstado = estado, Texto = texto },
			commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task ActualizarAsync(int perId, string modulo, string? descripcion, string estado, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paPermisoActualizar",
			new { PerId = perId, PerModulo = modulo, PerDescripcion = descripcion, PerEstado = estado, UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarAsync(int perId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paPermisoEliminar", new { PerId = perId }, commandType: CommandType.StoredProcedure);
	}

	public async Task<PermisoDetalle?> ConsultarDetalleAsync(int perId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var multi = await connection.QueryMultipleAsync("dbo.paPermisoDetalleConsultar", new { PerId = perId }, commandType: CommandType.StoredProcedure);
		var cabecera = await multi.ReadFirstOrDefaultAsync<PermisoCabecera>();
		if (cabecera is null) return null;
		return new PermisoDetalle
		{
			Permiso = new Permiso { PerId = cabecera.PerId, PerModulo = cabecera.PerModulo, PerCodigo = cabecera.PerCodigo, PerDescripcion = cabecera.PerDescripcion, PerEstado = cabecera.PerEstado },
			Creado = cabecera.Creado,
			CreadoPor = cabecera.CreadoPor,
			Modificado = cabecera.Modificado,
			Roles = (await multi.ReadAsync<PermisoRol>()).ToList(),
			Usuarios = (await multi.ReadAsync<PermisoUsuario>()).ToList()
		};
	}

	private sealed class PermisoCabecera
	{
		public int PerId { get; set; }
		public string PerModulo { get; set; } = "";
		public string PerCodigo { get; set; } = "";
		public string? PerDescripcion { get; set; }
		public string PerEstado { get; set; } = "A";
		public DateTime? Creado { get; set; }
		public string? CreadoPor { get; set; }
		public DateTime? Modificado { get; set; }
	}
}
