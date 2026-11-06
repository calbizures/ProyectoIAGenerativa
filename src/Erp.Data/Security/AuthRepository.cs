using System.Data;
using Dapper;

namespace Erp.Data.Security;

public sealed class AuthRepository(IDbConnectionFactory connectionFactory) : IAuthRepository
{
	// El hash se verifica aquí (PBKDF2, script 83): la contraseña no llega a la
	// base. Un hash anterior (SHA-256) se verifica en la base una última vez y
	// se reemplaza por PBKDF2; uno con menos iteraciones que las actuales, también.
	public async Task<LoginResultado> LoginAsync(string usuario, string password)
	{
		using var connection = connectionFactory.CreateConnection();
		var datos = await connection.QueryFirstOrDefaultAsync<DatosLogin>(
			"dbo.paSeguridadLoginDatos", new { UsuUsuario = usuario }, commandType: CommandType.StoredProcedure);

		if (datos is null)
		{
			ContrasenaHash.CalcularFicticio(password);
			return new LoginResultado { Estado = "error", Mensaje = "Usuario o contraseña no son válidos." };
		}

		// Inactivo o bloqueado: no se verifica la contraseña ni se suman intentos.
		var valido = false;
		if (datos.Estado == "A" && !datos.Bloqueado)
		{
			if (datos.Iteraciones is int iteraciones)
				valido = ContrasenaHash.Verificar(password, datos.Hash, datos.Salt, iteraciones);
			else
				valido = await connection.ExecuteScalarAsync<bool>(
					"dbo.paSeguridadPasswordLegadoVerificar", new { datos.UsuId, Password = password },
					commandType: CommandType.StoredProcedure);

			if (valido && (datos.Iteraciones ?? 0) < ContrasenaHash.Iteraciones)
				await GuardarHashAsync(connection, datos.UsuId, password, cambiarPassword: null, desbloquear: false, usuIdAccion: datos.UsuId);
		}

		return await connection.QueryFirstAsync<LoginResultado>(
			"dbo.paSeguridadLoginRegistrar", new { datos.UsuId, Exito = valido },
			commandType: CommandType.StoredProcedure);
	}

	internal static async Task GuardarHashAsync(IDbConnection connection, int usuId, string password,
		bool? cambiarPassword, bool desbloquear, int? usuIdAccion)
	{
		var hash = ContrasenaHash.Calcular(password);
		await connection.ExecuteAsync("dbo.paUsuarioPasswordGuardar", new
		{
			UsuId = usuId,
			hash.Hash,
			hash.Salt,
			hash.Iteraciones,
			CambiarPassword = cambiarPassword,
			Desbloquear = desbloquear,
			UsuIdAccion = usuIdAccion
		}, commandType: CommandType.StoredProcedure);
	}

	internal sealed class DatosLogin
	{
		public int UsuId { get; set; }
		public string Estado { get; set; } = "";
		public bool Bloqueado { get; set; }
		public byte[] Hash { get; set; } = [];
		public Guid Salt { get; set; }
		public int? Iteraciones { get; set; }
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
			INNER JOIN dbo.sec_rol r ON r.rol_id = ur.rol_id AND r.rol_estado = 'A'
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
