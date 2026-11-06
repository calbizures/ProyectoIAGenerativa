using System.Data;
using Dapper;
using Erp.Data.Cargas;
using Erp.Data.Contabilidad;

namespace Erp.Tests.Integracion;

// Carga de facturas y compras pendientes al arrancar (script 86), siempre
// dentro de una transacción revertida.
public class DocumentosPendientesTests
{
	private static DataTable Filas(params (string Codigo, string? Nombre, string? Nit, string? Serie, string Numero, DateTime Fecha, int? Cuota, DateTime Vence, decimal Saldo, string? Uuid)[] filas)
	{
		var tabla = new DataTable();
		foreach (var (nombre, tipo) in new[] { ("Fila", typeof(int)), ("Codigo", typeof(string)), ("Nombre", typeof(string)), ("Nit", typeof(string)),
			("Sucursal", typeof(string)), ("Serie", typeof(string)), ("Numero", typeof(string)), ("FechaDocumento", typeof(DateTime)), ("Cuota", typeof(int)),
			("Vencimiento", typeof(DateTime)), ("Saldo", typeof(decimal)), ("FelSerie", typeof(string)), ("FelNumero", typeof(string)), ("FelUuid", typeof(string)) })
			tabla.Columns.Add(nombre, tipo);
		var n = 2;
		foreach (var f in filas)
			tabla.Rows.Add(n++, f.Codigo, (object?)f.Nombre ?? DBNull.Value, (object?)f.Nit ?? DBNull.Value, DBNull.Value, (object?)f.Serie ?? DBNull.Value,
				f.Numero, f.Fecha, (object?)f.Cuota ?? DBNull.Value, f.Vence, f.Saldo, DBNull.Value, DBNull.Value, (object?)f.Uuid ?? DBNull.Value);
		return tabla;
	}

	private static async Task<(List<MensajeCarga> Mensajes, ResumenDocumentosPendientes Resumen)> ProcesarAsync(
		IDbConnection conexion, IDbTransaction transaccion, string modulo, DataTable filas, bool soloValidar)
	{
		var usuId = await conexion.ExecuteScalarAsync<int>("SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin'", transaction: transaccion);
		using var multi = await conexion.QueryMultipleAsync("dbo.paCxSaldoInicialProcesar", new
		{
			Modulo = modulo, Fecha = new DateTime(2026, 10, 31), Filas = filas.AsTableValuedParameter("dbo.cxs_carga_type"),
			Archivo = "prueba.xlsx", SoloValidar = soloValidar, UsuId = usuId
		}, transaccion, commandType: CommandType.StoredProcedure);
		return ((await multi.ReadAsync<MensajeCarga>()).ToList(), await multi.ReadSingleAsync<ResumenDocumentosPendientes>());
	}

	private static async Task<CuadreSubmayor> CuadreAsync(IDbConnection conexion, IDbTransaction transaccion, string modulo)
	{
		using var multi = await conexion.QueryMultipleAsync("dbo.paAuditoriaCuadreSubmayorConsultar", new { Modulo = modulo }, transaccion, commandType: CommandType.StoredProcedure);
		return await multi.ReadFirstAsync<CuadreSubmayor>();
	}

	// Un NIT válido que ningún cliente o proveedor tiene.
	private static Task<string> NitLibreAsync(IDbConnection conexion, IDbTransaction transaccion) =>
		conexion.ExecuteScalarAsync<string>("""
			SELECT TOP (1) CONCAT(base.n, '-', digito.d)
			FROM (SELECT CAST(7700000 + v.number AS VARCHAR(10)) AS n FROM master.dbo.spt_values v WHERE v.type = 'P' AND v.number < 500) base
			CROSS JOIN (VALUES ('0'),('1'),('2'),('3'),('4'),('5'),('6'),('7'),('8'),('9'),('K')) digito(d)
			WHERE dbo.fnNitValido(CONCAT(base.n, digito.d)) = 1
			  AND NOT EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE dbo.fnNitNormalizar(cli_nit) = CONCAT(base.n, digito.d))
			  AND NOT EXISTS (SELECT 1 FROM dbo.inv_proveedor WHERE dbo.fnNitNormalizar(prv_nit) = CONCAT(base.n, digito.d))
			ORDER BY base.n
			""", transaction: transaccion)!;

	// Asiento de apertura por el monto indicado en la cuenta del módulo (contra capital).
	private static Task AperturaAsync(IDbConnection conexion, IDbTransaction transaccion, string modulo, decimal monto) =>
		conexion.ExecuteAsync("""
			DECLARE @cta INT = (SELECT CtaId FROM dbo.fnAuditoriaSubmayorSaldos(@modulo));
			DECLARE @capital INT = (SELECT TOP (1) cta_id FROM dbo.cont_cuenta_contable WHERE cta_acepta_movimiento = 1 AND cta_tipo = 'K' ORDER BY cta_id);
			INSERT INTO dbo.cont_asiento_enc (asi_fecha, asi_descripcion, asi_origen, asi_estado, asi_fecha_creacion, pdo_id)
			SELECT TOP (1) '2026-10-31', 'Prueba: apertura', 'APERTURA', 'A', SYSDATETIME(), pdo_id FROM dbo.cont_asiento_enc ORDER BY asi_id DESC;
			DECLARE @asi INT = SCOPE_IDENTITY();
			IF @modulo = 'CXC'
				INSERT INTO dbo.cont_asiento_det (asi_id, cta_id, asd_debe, asd_haber) VALUES (@asi, @cta, @monto, 0), (@asi, @capital, 0, @monto);
			ELSE
				INSERT INTO dbo.cont_asiento_det (asi_id, cta_id, asd_debe, asd_haber) VALUES (@asi, @capital, @monto, 0), (@asi, @cta, 0, @monto);
			""", new { modulo, monto }, transaccion);

	[FactBaseDatos]
	public async Task Las_filas_con_errores_se_reportan_y_no_se_graba_nada()
	{
		using var conexion = BaseDatos.Abrir();
		using var transaccion = conexion.BeginTransaction();
		var cliente = await conexion.ExecuteScalarAsync<string>("SELECT TOP (1) cli_codigo FROM dbo.pos_cliente ORDER BY cli_id", transaction: transaccion);
		var filas = Filas(
			("NUEVO-X", "Sin NIT válido", "1234567-1", null, "1", new DateTime(2026, 9, 1), null, new DateTime(2026, 10, 1), 10m, null),
			(cliente!, null, null, null, "2", new DateTime(2026, 9, 1), null, new DateTime(2026, 8, 1), 10m, null),
			(cliente!, null, null, null, "3", new DateTime(2026, 11, 15), null, new DateTime(2026, 12, 1), 10m, null),
			(cliente!, null, null, null, "4", new DateTime(2026, 9, 1), null, new DateTime(2026, 10, 1), 0m, null),
			(cliente!, null, null, null, "5", new DateTime(2026, 9, 1), null, new DateTime(2026, 10, 1), 10m, "no-es-uuid"));

		var (mensajes, resumen) = await ProcesarAsync(conexion, transaccion, "CXC", filas, soloValidar: false);

		Assert.False(resumen.Grabado);
		Assert.Equal(new[] { 2, 3, 4, 5, 6 }, mensajes.Where(m => m.EsError).Select(m => m.Fila));
		Assert.Contains(mensajes, m => m.Mensaje.Contains("dígito verificador"));
		Assert.Contains(mensajes, m => m.Mensaje.Contains("posterior a la fecha de los saldos iniciales"));
		Assert.Equal(0, await conexion.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM dbo.cxs_carga", transaction: transaccion));
		transaccion.Rollback();
	}

	[FactBaseDatos]
	public async Task Las_facturas_cargadas_cuadran_con_la_apertura_y_se_ven_en_la_antiguedad()
	{
		using var conexion = BaseDatos.Abrir();
		using var transaccion = conexion.BeginTransaction();
		var cliente = await conexion.ExecuteScalarAsync<string>("SELECT TOP (1) cli_codigo FROM dbo.pos_cliente ORDER BY cli_id", transaction: transaccion);
		var nit = await NitLibreAsync(conexion, transaccion);
		var antes = await CuadreAsync(conexion, transaccion, "CXC");
		var filas = Filas(
			(cliente!, null, null, "PRB", "9001", new DateTime(2026, 9, 15), 1, new DateTime(2026, 10, 15), 1500m, null),
			(cliente!, null, null, "PRB", "9001", new DateTime(2026, 9, 15), 2, new DateTime(2026, 11, 15), 1500m, null),
			("PRUEBA-NUEVO", "Cliente de prueba", nit, "FACE", "77", new DateTime(2026, 8, 1), null, new DateTime(2026, 9, 1), 800m, "1a2b3c4d-1a2b-1a2b-1a2b-1a2b3c4d5e6f"));

		var (mensajes, resumen) = await ProcesarAsync(conexion, transaccion, "CXC", filas, soloValidar: false);

		Assert.DoesNotContain(mensajes, m => m.EsError);
		Assert.True(resumen.Grabado);
		Assert.Equal((2, 1, 3800m), (resumen.Documentos, resumen.TercerosNuevos, resumen.Total));
		// Sin apertura en la cuenta, la conciliación lo dice; con ella, cuadra.
		var sinApertura = await CuadreAsync(conexion, transaccion, "CXC");
		Assert.Equal(antes.Diferencia + 3800m, sinApertura.Diferencia);
		Assert.Equal(antes.Directas + 3800m, sinApertura.Directas);
		await AperturaAsync(conexion, transaccion, "CXC", 3800m);
		var conApertura = await CuadreAsync(conexion, transaccion, "CXC");
		Assert.Equal(antes.Diferencia, conApertura.Diferencia);
		Assert.Equal(0m, conApertura.SinExplicar);
		// La antigüedad y la factura electrónica de origen.
		var antiguedad = (await conexion.QueryAsync("dbo.paCxcAntiguedadConsultar", transaction: transaccion, commandType: CommandType.StoredProcedure)).ToList();
		Assert.Equal(3, antiguedad.Count(f => ((string)f.Documento).StartsWith("PRB-9001") || ((string)f.Documento).StartsWith("FACE-77")));
		var uuid = await conexion.ExecuteScalarAsync<string>("""
			SELECT felo.fdo_uuid FROM dbo.fel_documento felo
			INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = felo.enc_id AND docu.enc_numero_docto = '77' AND docu.enc_serie_docto = 'FACE'
			""", transaction: transaccion);
		Assert.Equal("1A2B3C4D-1A2B-1A2B-1A2B-1A2B3C4D5E6F", uuid);
		// Volver a cargar el mismo documento se rechaza.
		var (otraVez, _) = await ProcesarAsync(conexion, transaccion, "CXC", filas, soloValidar: true);
		Assert.All(otraVez.Where(m => m.Fila > 0), m => Assert.Contains("ya existe en el sistema", m.Mensaje));
		// Los documentos iniciales no tienen póliza propia y no son un caso de integridad.
		var controles = (await conexion.QueryAsync<ControlIntegridad>("dbo.paAuditoriaIntegridadConsultar", transaction: transaccion, commandType: CommandType.StoredProcedure)).ToList();
		Assert.Equal(0, controles.Single(c => c.Orden == 3).Casos);
		transaccion.Rollback();
	}

	[FactBaseDatos]
	public async Task Una_nota_de_credito_sobre_una_factura_inicial_rebaja_la_cuota_y_bloquea_la_anulacion()
	{
		using var conexion = BaseDatos.Abrir();
		using var transaccion = conexion.BeginTransaction();
		var cliente = await conexion.ExecuteScalarAsync<string>("SELECT TOP (1) cli_codigo FROM dbo.pos_cliente ORDER BY cli_id", transaction: transaccion);
		var (_, resumen) = await ProcesarAsync(conexion, transaccion, "CXC",
			Filas((cliente!, null, null, "PRB", "9002", new DateTime(2026, 9, 15), null, new DateTime(2026, 10, 15), 1120m, null)), soloValidar: false);
		var encId = await conexion.ExecuteScalarAsync<int>("SELECT enc_id FROM dbo.cxs_carga_documento WHERE csc_id = @csc", new { csc = resumen.CscId }, transaccion);
		await AperturaAsync(conexion, transaccion, "CXC", 1120m);
		var antes = await CuadreAsync(conexion, transaccion, "CXC");

		var detalle = new DataTable();
		foreach (var (nombre, tipo) in new[] { ("det_item", typeof(int)), ("det_descripcion", typeof(string)), ("det_cantidad", typeof(decimal)),
			("det_precio_unitario", typeof(decimal)), ("det_porc_iva", typeof(decimal)), ("ume_id", typeof(int)), ("det_id_origen", typeof(int)) })
			detalle.Columns.Add(nombre, tipo);
		detalle.Rows.Add(1, "Rebaja por pronto pago", 1m, 100m, 12m, DBNull.Value, DBNull.Value);
		var parametros = new DynamicParameters(new
		{
			TipoNota = "NCC", EncIdReferencia = encId, Fecha = new DateTime(2026, 11, 2), Motivo = "Rebaja por pronto pago",
			Detalle = detalle.AsTableValuedParameter("dbo.nota_det_type")
		});
		parametros.Add("EncId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		parametros.Add("NumeroUnico", dbType: DbType.String, size: 16, direction: ParameterDirection.Output);
		await conexion.ExecuteAsync("dbo.paNotaCrear", parametros, transaccion, commandType: CommandType.StoredProcedure);

		var saldo = await conexion.ExecuteScalarAsync<decimal>("SELECT SUM(cpp_saldo_cuota) FROM dbo.pos_cliente_plan_pagos WHERE enc_id = @encId", new { encId }, transaccion);
		Assert.Equal(1008m, saldo);
		var despues = await CuadreAsync(conexion, transaccion, "CXC");
		Assert.Equal(antes.Diferencia, despues.Diferencia);
		Assert.Equal(0m, despues.SinExplicar);
		var error = await Assert.ThrowsAsync<Microsoft.Data.SqlClient.SqlException>(() => conexion.ExecuteAsync("dbo.paCxSaldoInicialAnular",
			new { CscId = resumen.CscId, Motivo = "Prueba de anulación", UsuId = (int?)null }, transaccion, commandType: CommandType.StoredProcedure));
		Assert.Equal(55993, error.Number);
		transaccion.Rollback();
	}

	[FactBaseDatos]
	public async Task Las_compras_cargadas_se_pueden_anular_mientras_no_tengan_pagos()
	{
		using var conexion = BaseDatos.Abrir();
		using var transaccion = conexion.BeginTransaction();
		var proveedor = await conexion.ExecuteScalarAsync<string>("SELECT TOP (1) prv_codigo FROM dbo.inv_proveedor ORDER BY prv_id", transaction: transaccion);
		var antes = await CuadreAsync(conexion, transaccion, "CXP");
		var (mensajes, resumen) = await ProcesarAsync(conexion, transaccion, "CXP",
			Filas((proveedor!, null, null, "F", "PRB-7001", new DateTime(2026, 10, 1), null, new DateTime(2026, 10, 31), 2000m, null)), soloValidar: false);
		Assert.True(resumen.Grabado, string.Join(" | ", mensajes.Select(m => m.Mensaje)));
		Assert.Equal(antes.SaldoCuotas + 2000m, (await CuadreAsync(conexion, transaccion, "CXP")).SaldoCuotas);

		await conexion.ExecuteAsync("dbo.paCxSaldoInicialAnular", new { CscId = resumen.CscId, Motivo = "Se cargó con fecha equivocada", UsuId = (int?)null },
			transaccion, commandType: CommandType.StoredProcedure);

		Assert.Equal("A", await conexion.ExecuteScalarAsync<string>("SELECT csc_estado FROM dbo.cxs_carga WHERE csc_id = @id", new { id = resumen.CscId }, transaccion));
		var despues = await CuadreAsync(conexion, transaccion, "CXP");
		Assert.Equal(antes.SaldoCuotas, despues.SaldoCuotas);
		Assert.Equal(antes.Diferencia, despues.Diferencia);
		transaccion.Rollback();
	}
}
