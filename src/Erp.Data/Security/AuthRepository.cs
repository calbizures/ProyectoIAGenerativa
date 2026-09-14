using System.Data;
using Dapper;

namespace Erp.Data.Security;

public sealed class AuthRepository(IDbConnectionFactory connectionFactory) : IAuthRepository
{
	public async Task<LoginResultado> LoginAsync(string usuario, string password)
	{
		using var connection = connectionFactory.CreateConnection();
		var resultado = await connection.QueryFirstAsync<LoginResultado>(
			"dbo.sp_seguridad_login",
			new { usu_usuario = usuario, usu_password = password },
			commandType: CommandType.StoredProcedure);
		return resultado;
	}

	// Lectura simple (sin lógica de negocio que auditar) para armar los claims
	// de rol/permiso de la cookie de autenticación; no hay un SP dedicado para esto.
	public async Task<UsuarioClaims> ObtenerClaimsAsync(int usuId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var multi = await connection.QueryMultipleAsync(
			"""
			SELECT r.rol_codigo
			FROM dbo.sec_usuario_rol ur
			INNER JOIN dbo.sec_rol r ON r.rol_id = ur.rol_id
			WHERE ur.usu_id = @usu_id AND r.rol_estado = 'A';

			SELECT DISTINCT p.per_codigo
			FROM dbo.sec_usuario_rol ur
			INNER JOIN dbo.sec_rol_permiso rp ON rp.rol_id = ur.rol_id
			INNER JOIN dbo.sec_permiso p ON p.per_id = rp.per_id
			WHERE ur.usu_id = @usu_id AND p.per_estado = 'A';
			""",
			new { usu_id = usuId });

		var roles = (await multi.ReadAsync<string>()).ToList();
		var permisos = (await multi.ReadAsync<string>()).ToList();
		return new UsuarioClaims { Roles = roles, Permisos = permisos };
	}
}
