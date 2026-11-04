using System.Data;
using Dapper;

namespace Erp.Data.Contabilidad;

// Un control de la revisión de integridad (script 50): Casos = 0 es correcto.
public sealed class ControlIntegridad
{
	public int Orden { get; set; }
	public string? Area { get; set; }
	// "CXC" o "CXP": el control tiene la conciliación de ese submódulo como detalle.
	public string? Detalle { get; set; }
	public string Control { get; set; } = "";
	public int Casos { get; set; }
	public string? Ejemplo { get; set; }
	public string Resultado { get; set; } = "OK";
}

// Cuadre de Cuentas por cobrar o por pagar con su cuenta contable (script 85).
// Diferencia = SaldoCuotas - SaldoContable = Documentos + Pagos + Directas + SinExplicar.
public sealed class CuadreSubmayor
{
	public string Modulo { get; set; } = "";
	public int CtaId { get; set; }
	public string CuentaCodigo { get; set; } = "";
	public string CuentaNombre { get; set; } = "";
	public decimal SaldoCuotas { get; set; }
	public decimal SaldoContable { get; set; }
	public decimal Diferencia { get; set; }
	public decimal Documentos { get; set; }
	public decimal Pagos { get; set; }
	public decimal Directas { get; set; }
	public decimal SinExplicar { get; set; }

	public bool Cuadra => Math.Abs(Diferencia) < 0.01m;
}

// Una partida que explica parte de la diferencia. Grupo: D documento,
// P cobro o pago, O póliza directa en la cuenta.
public sealed class PartidaCuadre
{
	public string Grupo { get; set; } = "";
	public DateTime? Fecha { get; set; }
	public string? Referencia { get; set; }
	public string? Tercero { get; set; }
	public int? TerceroId { get; set; }
	public string? Descripcion { get; set; }
	public decimal Submodulo { get; set; }
	public decimal Contable { get; set; }
	public decimal Efecto { get; set; }
	public int? AsiId { get; set; }
	public int? EncId { get; set; }
	public int? PagoId { get; set; }
	public string? Diagnostico { get; set; }
}

public interface IIntegridadRepository
{
	Task<IReadOnlyList<ControlIntegridad>> ConsultarAsync();
	Task<(CuadreSubmayor? Resumen, IReadOnlyList<PartidaCuadre> Partidas)> ConsultarCuadreAsync(string modulo);
}

public sealed class IntegridadRepository(IDbConnectionFactory connectionFactory) : IIntegridadRepository
{
	public async Task<IReadOnlyList<ControlIntegridad>> ConsultarAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<ControlIntegridad>("dbo.paAuditoriaIntegridadConsultar", commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<(CuadreSubmayor? Resumen, IReadOnlyList<PartidaCuadre> Partidas)> ConsultarCuadreAsync(string modulo)
	{
		using var connection = connectionFactory.CreateConnection();
		using var multi = await connection.QueryMultipleAsync("dbo.paAuditoriaCuadreSubmayorConsultar",
			new { Modulo = modulo }, commandType: CommandType.StoredProcedure);
		var resumen = await multi.ReadFirstOrDefaultAsync<CuadreSubmayor>();
		var partidas = (await multi.ReadAsync<PartidaCuadre>()).ToList();
		return (resumen, partidas);
	}
}
