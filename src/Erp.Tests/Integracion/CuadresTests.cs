using System.Data;
using Dapper;

namespace Erp.Tests.Integracion;

// Lo que un auditor revisaría: cada submódulo cuadra con su cuenta contable
// y los controles de integridad no encuentran casos.
public class CuadresTests
{
	[FactBaseDatos]
	public async Task Los_controles_de_integridad_no_encuentran_casos()
	{
		using var conexion = BaseDatos.Abrir();
		var controles = (await conexion.QueryAsync<Erp.Data.Contabilidad.ControlIntegridad>(
			"dbo.paAuditoriaIntegridadConsultar", commandType: CommandType.StoredProcedure)).ToList();

		Assert.Equal(Enumerable.Range(1, 24), controles.Select(c => c.Orden));
		Assert.All(controles, c => Assert.False(string.IsNullOrEmpty(c.Area), $"El control {c.Orden} no tiene área."));
		var conCasos = controles.Where(c => c.Casos > 0).Select(c => $"{c.Orden}. {c.Control}: {c.Casos} (p. ej. {c.Ejemplo})").ToList();
		Assert.True(conCasos.Count == 0, string.Join(Environment.NewLine, conCasos));
	}

	[FactBaseDatos]
	public async Task Cuentas_por_pagar_cuadran_con_la_cuenta_de_proveedores()
	{
		using var conexion = BaseDatos.Abrir();
		var cuotas = (await conexion.QueryAsync("dbo.paCxpAntiguedadConsultar", commandType: CommandType.StoredProcedure))
			.Sum(f => (decimal)f.Saldo);
		var contable = -await BaseDatos.SaldoCuentaAsync(conexion, "COMPRA_PROVEEDORES");

		Assert.Equal(contable, cuotas);
	}

	[FactBaseDatos]
	public async Task Cuentas_por_cobrar_cuadran_con_la_cuenta_de_clientes()
	{
		using var conexion = BaseDatos.Abrir();
		var cuotas = (await conexion.QueryAsync("dbo.paCxcAntiguedadConsultar", commandType: CommandType.StoredProcedure))
			.Sum(f => (decimal)f.Saldo);
		var contable = await BaseDatos.SaldoCuentaAsync(conexion, "VENTA_CLIENTES");

		Assert.Equal(contable, cuotas);
	}
}
