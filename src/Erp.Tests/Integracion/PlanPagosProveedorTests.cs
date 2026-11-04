using Dapper;

namespace Erp.Tests.Integracion;

// paProveedorPlanPagosGenerar (script 82): el plan de pagos siempre suma el
// total de la compra, que es lo que el asiento abona a Proveedores.
public class PlanPagosProveedorTests
{
	private sealed record Cuota(int Nro, DateTime Fecha, decimal Valor);

	private static async Task<(int EncId, decimal Total, DateTime Fecha)> CompraAsync(System.Data.IDbConnection conexion, System.Data.IDbTransaction transaccion) =>
		await conexion.QueryFirstAsync<(int, decimal, DateTime)>("""
			SELECT TOP (1) docu.enc_id, docu.enc_monto_total, docu.enc_fecha_docto
			FROM dbo.inv_documento_enc docu
			INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id AND tipo.tdo_codigo = 'COMP'
			WHERE docu.enc_estado = 'G' AND docu.enc_monto_total > 100
			  -- Sin pagos, notas ni contraseñas de pago: su plan se puede rehacer.
			  AND NOT EXISTS (
				SELECT 1 FROM dbo.inv_proveedor_plan_pago cuot
				WHERE cuot.enc_id = docu.enc_id
				  AND (EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_det x WHERE x.ppg_id = cuot.ppg_id)
					OR EXISTS (SELECT 1 FROM dbo.bco_lote_transferencia_cuota x WHERE x.ppg_id = cuot.ppg_id)
					OR EXISTS (SELECT 1 FROM dbo.inv_proveedor_nota_aplicacion x WHERE x.ppg_id = cuot.ppg_id)
					OR EXISTS (SELECT 1 FROM dbo.cxp_contrasena_det x WHERE x.ppg_id = cuot.ppg_id)))
			ORDER BY docu.enc_id
			""", transaction: transaccion);

	private static async Task<List<Cuota>> RegenerarAsync(System.Data.IDbConnection conexion, System.Data.IDbTransaction transaccion,
		int encId, DateTime? primerPago, int cuotas, decimal enganche)
	{
		await conexion.ExecuteAsync("""
			DELETE FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @encId;
			UPDATE dbo.inv_documento_enc
			   SET enc_fecha_primer_pago = @primerPago, enc_numero_cuotas = @cuotas, enc_monto_enganche = @enganche
			 WHERE enc_id = @encId;
			EXEC dbo.paProveedorPlanPagosGenerar @EncId = @encId;
			EXEC dbo.paProveedorPlanPagosGenerar @EncId = @encId;	-- la segunda no debe duplicar
			""", new { encId, primerPago, cuotas, enganche }, transaccion);
		return (await conexion.QueryAsync<Cuota>(
			"SELECT ppg_nro_pago AS Nro, ppg_fecha_pago AS Fecha, ppg_valor_pago AS Valor FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @encId ORDER BY ppg_nro_pago",
			new { encId }, transaccion)).ToList();
	}

	[FactBaseDatos]
	public async Task Contado_una_cuota_por_el_total_que_vence_el_dia_de_la_compra()
	{
		using var conexion = BaseDatos.Abrir();
		using var transaccion = conexion.BeginTransaction();
		var (encId, total, fecha) = await CompraAsync(conexion, transaccion);

		var plan = await RegenerarAsync(conexion, transaccion, encId, null, 1, 0);

		var cuota = Assert.Single(plan);
		Assert.Equal(total, cuota.Valor);
		Assert.Equal(fecha.Date, cuota.Fecha.Date);
		transaccion.Rollback();
	}

	[FactBaseDatos]
	public async Task Credito_con_enganche_la_cuota_1_es_el_enganche_y_el_plan_suma_el_total()
	{
		using var conexion = BaseDatos.Abrir();
		using var transaccion = conexion.BeginTransaction();
		var (encId, total, fecha) = await CompraAsync(conexion, transaccion);

		var plan = await RegenerarAsync(conexion, transaccion, encId, fecha.AddMonths(1), 3, 50m);

		Assert.Equal(4, plan.Count);
		Assert.Equal(50m, plan[0].Valor);
		Assert.Equal(fecha.Date, plan[0].Fecha.Date);
		Assert.Equal([1, 2, 3, 4], plan.Select(c => c.Nro));
		Assert.Equal(total, plan.Sum(c => c.Valor));
		transaccion.Rollback();
	}

	[FactBaseDatos]
	public async Task Credito_sin_enganche_reparte_los_centavos_en_la_ultima_cuota()
	{
		using var conexion = BaseDatos.Abrir();
		using var transaccion = conexion.BeginTransaction();
		var (encId, total, fecha) = await CompraAsync(conexion, transaccion);

		var plan = await RegenerarAsync(conexion, transaccion, encId, fecha.AddMonths(1), 7, 0);

		Assert.Equal(7, plan.Count);
		Assert.Equal(total, plan.Sum(c => c.Valor));
		Assert.All(plan.Take(6), c => Assert.Equal(plan[0].Valor, c.Valor));
		transaccion.Rollback();
	}
}
