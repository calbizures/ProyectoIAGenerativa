using System.Data;
using Dapper;
using Erp.Data.Contabilidad;

namespace Erp.Tests.Integracion;

// paAuditoriaCuadreSubmayorConsultar (script 85): cuando CxC o CxP no cuadran
// con su cuenta, las partidas explican toda la diferencia y dicen por qué.
// Cada prueba provoca un descuadre real dentro de una transacción revertida.
public class ConciliacionSubmayorTests
{
	private static async Task<(CuadreSubmayor Resumen, List<PartidaCuadre> Partidas)> ConciliarAsync(IDbConnection conexion, IDbTransaction? transaccion, string modulo)
	{
		using var multi = await conexion.QueryMultipleAsync("dbo.paAuditoriaCuadreSubmayorConsultar", new { Modulo = modulo },
			transaccion, commandType: CommandType.StoredProcedure);
		var resumen = await multi.ReadFirstAsync<CuadreSubmayor>();
		return (resumen, (await multi.ReadAsync<PartidaCuadre>()).ToList());
	}

	private static Task<int> CasosAsync(IDbConnection conexion, IDbTransaction transaccion, int orden) =>
		conexion.QueryAsync<ControlIntegridad>("dbo.paAuditoriaIntegridadConsultar", transaction: transaccion, commandType: CommandType.StoredProcedure)
			.ContinueWith(t => t.Result.Single(c => c.Orden == orden).Casos);

	// La diferencia queda explicada por completo: nada "sin explicar".
	private static void AssertExplicada(CuadreSubmayor resumen, IReadOnlyList<PartidaCuadre> partidas)
	{
		Assert.Equal(resumen.SaldoCuotas - resumen.SaldoContable, resumen.Diferencia);
		Assert.Equal(0m, resumen.SinExplicar);
		Assert.Equal(resumen.Diferencia, partidas.Sum(p => p.Efecto));
		Assert.Equal(resumen.Documentos + resumen.Pagos + resumen.Directas, resumen.Diferencia);
	}

	[FactBaseDatos]
	public async Task Con_los_datos_instalados_no_hay_partidas_que_explicar()
	{
		using var conexion = BaseDatos.Abrir();
		foreach (var modulo in new[] { "CXC", "CXP" })
		{
			var (resumen, partidas) = await ConciliarAsync(conexion, null, modulo);
			Assert.True(resumen.Cuadra, $"{modulo}: diferencia {resumen.Diferencia}");
			Assert.Empty(partidas);
		}
	}

	[FactBaseDatos]
	public async Task Una_poliza_manual_en_clientes_sale_como_poliza_directa()
	{
		using var conexion = BaseDatos.Abrir();
		using var transaccion = conexion.BeginTransaction();
		var asiId = await conexion.ExecuteScalarAsync<int>("""
			DECLARE @cli INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'VENTA_CLIENTES');
			DECLARE @ingreso INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'VENTA_INGRESO');
			INSERT INTO dbo.cont_asiento_enc (asi_fecha, asi_descripcion, asi_origen, asi_estado, asi_fecha_creacion, pdo_id)
			SELECT TOP (1) CAST(GETDATE() AS DATE), 'Prueba: ajuste manual', 'MANUAL', 'A', SYSDATETIME(), pdo_id
			FROM dbo.cont_asiento_enc ORDER BY asi_id DESC;
			DECLARE @asi INT = SCOPE_IDENTITY();
			INSERT INTO dbo.cont_asiento_det (asi_id, cta_id, asd_debe, asd_haber) VALUES (@asi, @cli, 500, 0), (@asi, ISNULL(@ingreso, @cli), 0, 500);
			SELECT @asi;
			""", transaction: transaccion);

		var (resumen, partidas) = await ConciliarAsync(conexion, transaccion, "CXC");

		Assert.Equal(-500m, resumen.Diferencia);
		AssertExplicada(resumen, partidas);
		var partida = Assert.Single(partidas);
		Assert.Equal("O", partida.Grupo);
		Assert.Equal(asiId, partida.AsiId);
		Assert.Contains("manual", partida.Diagnostico);
		Assert.Equal(1, await CasosAsync(conexion, transaccion, 20));
		transaccion.Rollback();
	}

	[FactBaseDatos]
	public async Task Un_cobro_vigente_de_una_factura_anulada_sale_como_cobro()
	{
		using var conexion = BaseDatos.Abrir();
		using var transaccion = conexion.BeginTransaction();
		// Se anula "por fuera" una factura cobrada, como lo hacía una versión
		// anterior de la anulación: el cobro queda vigente.
		var (encId, cobrado) = await conexion.QueryFirstAsync<(int, decimal)>("""
			SELECT TOP (1) cuot.enc_id, SUM(deta.ppd_valor_aplicado)
			FROM dbo.pos_pago_det deta
			INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
			INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = deta.cpp_id
			INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
			WHERE NOT EXISTS (SELECT 1 FROM dbo.inv_documento_enc nota WHERE nota.enc_id_referencia = docu.enc_id)
			GROUP BY cuot.enc_id ORDER BY cuot.enc_id
			""", transaction: transaccion);
		await conexion.ExecuteAsync("""
			UPDATE dbo.inv_documento_enc SET enc_estado = 'A' WHERE enc_id = @encId;
			UPDATE dbo.cont_asiento_enc SET asi_estado = 'N' WHERE enc_id = @encId;
			""", new { encId }, transaccion);

		var (resumen, partidas) = await ConciliarAsync(conexion, transaccion, "CXC");

		Assert.Equal(cobrado, resumen.Diferencia);
		AssertExplicada(resumen, partidas);
		Assert.All(partidas, p => Assert.Equal("P", p.Grupo));
		Assert.Equal(cobrado, partidas.Sum(p => p.Efecto));
		Assert.True(await CasosAsync(conexion, transaccion, 22) >= 1);
		transaccion.Rollback();
	}

	[FactBaseDatos]
	public async Task Una_compra_sin_plan_de_pagos_sale_como_documento()
	{
		using var conexion = BaseDatos.Abrir();
		using var transaccion = conexion.BeginTransaction();
		var (encId, total) = await conexion.QueryFirstAsync<(int, decimal)>("""
			SELECT TOP (1) docu.enc_id, docu.enc_monto_total
			FROM dbo.inv_documento_enc docu
			INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id AND tipo.tdo_codigo = 'COMP'
			WHERE docu.enc_estado = 'G'
			  AND NOT EXISTS (SELECT 1 FROM dbo.inv_documento_enc nota WHERE nota.enc_id_referencia = docu.enc_id)
			  AND NOT EXISTS (
				SELECT 1 FROM dbo.inv_proveedor_plan_pago cuot
				WHERE cuot.enc_id = docu.enc_id
				  AND (ISNULL(cuot.ppg_valor_real_pago, 0) > 0
					OR EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_det x WHERE x.ppg_id = cuot.ppg_id)
					OR EXISTS (SELECT 1 FROM dbo.bco_lote_transferencia_cuota x WHERE x.ppg_id = cuot.ppg_id)
					OR EXISTS (SELECT 1 FROM dbo.inv_proveedor_nota_aplicacion x WHERE x.ppg_id = cuot.ppg_id)
					OR EXISTS (SELECT 1 FROM dbo.cxp_contrasena_det x WHERE x.ppg_id = cuot.ppg_id)))
			ORDER BY docu.enc_id
			""", transaction: transaccion);
		await conexion.ExecuteAsync("DELETE FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @encId", new { encId }, transaccion);

		var (resumen, partidas) = await ConciliarAsync(conexion, transaccion, "CXP");

		Assert.Equal(-total, resumen.Diferencia);
		AssertExplicada(resumen, partidas);
		var partida = Assert.Single(partidas);
		Assert.Equal("D", partida.Grupo);
		Assert.Equal(encId, partida.EncId);
		Assert.Contains("no tiene cuotas", partida.Diagnostico);
		Assert.Equal(1, await CasosAsync(conexion, transaccion, 21));
		Assert.Equal(1, await CasosAsync(conexion, transaccion, 24));
		transaccion.Rollback();
	}

	[FactBaseDatos]
	public async Task Un_modulo_desconocido_se_rechaza()
	{
		using var conexion = BaseDatos.Abrir();
		var error = await Assert.ThrowsAsync<Microsoft.Data.SqlClient.SqlException>(() => ConciliarAsync(conexion, null, "XXX"));
		Assert.Equal(55980, error.Number);
	}
}
