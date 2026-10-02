using System.Data;
using Dapper;

namespace Erp.Data.Correo;

public sealed class CorreoRepository(IDbConnectionFactory connectionFactory) : ICorreoRepository
{
	public async Task<CorreoConfiguracion?> ConsultarConfiguracionAsync(int ciaId)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QueryFirstOrDefaultAsync<CorreoConfiguracion>("dbo.paCompaniaCorreoConsultar", new { CiaId = ciaId },
			commandType: CommandType.StoredProcedure);
	}

	public async Task GuardarConfiguracionAsync(CorreoConfiguracion c, string? claveCifrada, bool borrarClave, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCompaniaCorreoGuardar", new
		{
			c.CiaId,
			c.Servidor,
			c.Puerto,
			c.Ssl,
			c.Usuario,
			ClaveCifrada = claveCifrada,
			BorrarClave = borrarClave,
			c.Remitente,
			c.RemitenteNombre,
			c.Copia,
			UsuId = usuarioAccionId
		}, commandType: CommandType.StoredProcedure);
	}

	public async Task RegistrarAsync(CorreoBitacora e)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCorreoBitacoraRegistrar", new
		{
			e.CiaId,
			e.Tipo,
			e.ReferenciaId,
			e.Destinatario,
			e.Copia,
			e.Asunto,
			e.Adjunto,
			Estado = e.Enviado ? "E" : "F",
			e.Error,
			e.UsuId
		}, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<CorreoEnviado>> ConsultarEnviosAsync(string? tipo, int? referenciaId, int cantidad = 20)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<CorreoEnviado>("dbo.paCorreoBitacoraConsultar",
			new { Tipo = tipo, ReferenciaId = referenciaId, Cantidad = cantidad }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}
}
