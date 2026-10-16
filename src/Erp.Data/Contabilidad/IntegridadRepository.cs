using System.Data;
using Dapper;

namespace Erp.Data.Contabilidad;

// Un control de la revisión de integridad (script 50): Casos = 0 es correcto.
public sealed class ControlIntegridad
{
	public int Orden { get; set; }
	public string Control { get; set; } = "";
	public int Casos { get; set; }
	public string? Ejemplo { get; set; }
	public string Resultado { get; set; } = "OK";
}

public interface IIntegridadRepository
{
	Task<IReadOnlyList<ControlIntegridad>> ConsultarAsync();
}

public sealed class IntegridadRepository(IDbConnectionFactory connectionFactory) : IIntegridadRepository
{
	public async Task<IReadOnlyList<ControlIntegridad>> ConsultarAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<ControlIntegridad>("dbo.paAuditoriaIntegridadConsultar", commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}
}
