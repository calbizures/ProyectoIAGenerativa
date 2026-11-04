using System.Data;
using Dapper;
using Erp.Data.Security;

namespace Erp.Tests.Integracion;

// Inicio de sesión del script 83: intentos fallidos, bloqueo y hash guardado.
public class SeguridadTests
{
	private static async Task<int> UsuarioAsync(IDbConnection conexion, IDbTransaction transaccion, string password)
	{
		var hash = ContrasenaHash.Calcular(password);
		var parametros = new DynamicParameters(new
		{
			UsuCodigo = "PRUEBA-XUNIT",
			UsuUsuario = "prueba.xunit." + Guid.NewGuid().ToString("N")[..8],
			UsuPasswordHash = hash.Hash,
			UsuPasswordSalt = hash.Salt,
			UsuPasswordIteraciones = hash.Iteraciones
		});
		parametros.Add("UsuId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await conexion.ExecuteAsync("dbo.paUsuarioInsertar", parametros, transaccion, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("UsuId");
	}

	private static Task<LoginResultado> RegistrarAsync(IDbConnection conexion, IDbTransaction transaccion, int usuId, bool exito) =>
		conexion.QueryFirstAsync<LoginResultado>("dbo.paSeguridadLoginRegistrar", new { UsuId = usuId, Exito = exito },
			transaccion, commandType: CommandType.StoredProcedure);

	[FactBaseDatos]
	public async Task El_hash_guardado_se_verifica_en_la_aplicacion()
	{
		using var conexion = BaseDatos.Abrir();
		using var transaccion = conexion.BeginTransaction();
		var usuId = await UsuarioAsync(conexion, transaccion, "Inicial#2026");

		var datos = await conexion.QueryFirstAsync<(int UsuId, string Estado, bool Bloqueado, bool CambiarPassword, byte[] Hash, Guid Salt, int? Iteraciones)>(
			"dbo.paSeguridadLoginDatos", new { UsuId = usuId }, transaccion, commandType: CommandType.StoredProcedure);

		Assert.Equal(ContrasenaHash.Iteraciones, datos.Iteraciones);
		Assert.True(ContrasenaHash.Verificar("Inicial#2026", datos.Hash, datos.Salt, datos.Iteraciones!.Value));
		Assert.False(ContrasenaHash.Verificar("Otra#2026", datos.Hash, datos.Salt, datos.Iteraciones!.Value));
		transaccion.Rollback();
	}

	[FactBaseDatos]
	public async Task Cinco_intentos_fallidos_bloquean_el_usuario()
	{
		using var conexion = BaseDatos.Abrir();
		using var transaccion = conexion.BeginTransaction();
		var usuId = await UsuarioAsync(conexion, transaccion, "Inicial#2026");

		for (var i = 0; i < 5; i++)
			Assert.False((await RegistrarAsync(conexion, transaccion, usuId, exito: false)).EsExitoso);

		// Bloqueado: ni la contraseña correcta lo deja entrar.
		var resultado = await RegistrarAsync(conexion, transaccion, usuId, exito: true);
		Assert.False(resultado.EsExitoso);
		Assert.Contains("bloqueado", resultado.Mensaje);
		transaccion.Rollback();
	}

	[FactBaseDatos]
	public async Task Un_acierto_reinicia_los_intentos_fallidos()
	{
		using var conexion = BaseDatos.Abrir();
		using var transaccion = conexion.BeginTransaction();
		var usuId = await UsuarioAsync(conexion, transaccion, "Inicial#2026");

		for (var i = 0; i < 4; i++)
			await RegistrarAsync(conexion, transaccion, usuId, exito: false);
		Assert.True((await RegistrarAsync(conexion, transaccion, usuId, exito: true)).EsExitoso);

		var intentos = await conexion.ExecuteScalarAsync<int>("SELECT usu_intentos_fallidos FROM dbo.gen_usuario WHERE usu_id = @usuId",
			new { usuId }, transaccion);
		Assert.Equal(0, intentos);
		transaccion.Rollback();
	}

	[FactBaseDatos]
	public async Task La_base_rechaza_un_hash_debil()
	{
		using var conexion = BaseDatos.Abrir();
		using var transaccion = conexion.BeginTransaction();
		var usuId = await UsuarioAsync(conexion, transaccion, "Inicial#2026");

		var error = await Assert.ThrowsAsync<Microsoft.Data.SqlClient.SqlException>(() => conexion.ExecuteAsync("dbo.paUsuarioPasswordGuardar",
			new { UsuId = usuId, Hash = new byte[32], Salt = Guid.NewGuid(), Iteraciones = 1000 }, transaccion, commandType: CommandType.StoredProcedure));
		Assert.Equal(55970, error.Number);
		transaccion.Rollback();
	}
}
