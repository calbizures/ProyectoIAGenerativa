using System.Data;
using Dapper;
using Erp.Data.Caja;
using Erp.Data.Ventas;

namespace Erp.Data.Cuentas;

public sealed class CuentasRepository(IDbConnectionFactory connectionFactory) : ICuentasRepository
{
	private async Task<IReadOnlyList<T>> ConsultarAsync<T>(string procedimiento, object? parametros = null)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<T>(procedimiento, parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public Task<IReadOnlyList<DocumentoSaldo>> ConsultarDocumentosCxcAsync(int? cliId, bool soloPendientes) =>
		ConsultarAsync<DocumentoSaldo>("dbo.paCxcDocumentosConsultar", new { CliId = cliId, SoloPendientes = soloPendientes });

	public Task<IReadOnlyList<MovimientoEstadoCuenta>> ConsultarEstadoCuentaClienteAsync(int cliId, DateTime? desde, DateTime? hasta) =>
		ConsultarAsync<MovimientoEstadoCuenta>("dbo.paCxcEstadoCuentaConsultar", new { CliId = cliId, Desde = desde?.Date, Hasta = hasta?.Date });

	public Task<IReadOnlyList<AntiguedadFila>> ConsultarAntiguedadClientesAsync(DateTime fechaCorte, int? cliId) =>
		ConsultarAsync<AntiguedadFila>("dbo.paCxcAntiguedadConsultar", new { FechaCorte = fechaCorte.Date, CliId = cliId });

	public Task<IReadOnlyList<CuotaPlanPago>> ConsultarCuotasClienteAsync(int encId) =>
		ConsultarAsync<CuotaPlanPago>("dbo.paClientePlanPagosConsultar", new { enc_id = encId });

	public async Task<int> RegistrarCobroAsync(int cppId, decimal valor, int pcaId, IReadOnlyList<FormaPagoCaptura> formasPago, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@cpp_id", cppId);
		parametros.Add("@valor_pago", valor);
		parametros.Add("@pca_id", pcaId);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@formas_pago", CajaRepository.ConstruirTablaFormasPago(formasPago).AsTableValuedParameter("dbo.pago_forma_type"));
		parametros.Add("@ppe_id", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.sp_pos_registrar_pago_cuota", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@ppe_id");
	}

	public Task<IReadOnlyList<CuotaPendiente>> ConsultarCuotasPendientesClienteAsync(int cliId) =>
		ConsultarAsync<CuotaPendiente>("dbo.paCxcCuotasPendientesConsultar", new { CliId = cliId });

	public async Task<int> RegistrarCobroCuotasAsync(int cliId, int pcaId, IReadOnlyList<CuotaCobro> cuotas, IReadOnlyList<FormaPagoCaptura> formasPago, int? usuarioAccionId)
	{
		var tablaCuotas = new DataTable();
		tablaCuotas.Columns.Add("cpp_id", typeof(int));
		tablaCuotas.Columns.Add("monto", typeof(decimal));
		foreach (var c in cuotas) tablaCuotas.Rows.Add(c.CppId, c.Monto);

		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@CliId", cliId);
		parametros.Add("@PcaId", pcaId);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@Cuotas", tablaCuotas.AsTableValuedParameter("dbo.cobro_cuota_type"));
		parametros.Add("@Formas", CajaRepository.ConstruirTablaFormasPago(formasPago).AsTableValuedParameter("dbo.pago_forma_type"));
		parametros.Add("@PpeId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paCxcCobroRegistrar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@PpeId");
	}

	public Task<IReadOnlyList<ReciboResumen>> ConsultarRecibosAsync(int? pcaId, int? cliId, DateTime? desde, DateTime? hasta) =>
		ConsultarAsync<ReciboResumen>("dbo.paCxcRecibosConsultar", new { PcaId = pcaId, CliId = cliId, Desde = desde?.Date, Hasta = hasta?.Date });

	public async Task<ReciboDetalle?> ConsultarReciboAsync(int ppeId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paCxcReciboDetalleConsultar", new { PpeId = ppeId }, commandType: CommandType.StoredProcedure);
		var encabezado = await lector.ReadSingleOrDefaultAsync<ReciboEncabezado>();
		if (encabezado is null) return null;
		var aplicaciones = (await lector.ReadAsync<ReciboAplicacion>()).ToList();
		var formas = (await lector.ReadAsync<ReciboForma>()).ToList();
		return new ReciboDetalle(encabezado, aplicaciones, formas);
	}

	public async Task AnularReciboAsync(int ppeId, string motivo, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCxcReciboAnular", new { PpeId = ppeId, Motivo = motivo, UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}

	public async Task<CreditoCliente?> ConsultarCreditoClienteAsync(int cliId)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QuerySingleOrDefaultAsync<CreditoCliente>("dbo.paClienteCreditoConsultar", new { CliId = cliId },
			commandType: CommandType.StoredProcedure);
	}

	public Task<IReadOnlyList<ChequeResumen>> ConsultarChequesAsync(int? prvId, DateTime? desde, DateTime? hasta) =>
		ConsultarAsync<ChequeResumen>("dbo.paCxpChequesConsultar", new { PrvId = prvId, Desde = desde?.Date, Hasta = hasta?.Date });

	public async Task AnularChequeAsync(int bceId, string motivo, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCxpChequeAnular", new { BceId = bceId, Motivo = motivo, UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}

	public Task<IReadOnlyList<DocumentoSaldo>> ConsultarDocumentosCxpAsync(int? prvId, bool soloPendientes) =>
		ConsultarAsync<DocumentoSaldo>("dbo.paCxpDocumentosConsultar", new { PrvId = prvId, SoloPendientes = soloPendientes });

	public Task<IReadOnlyList<MovimientoEstadoCuenta>> ConsultarEstadoCuentaProveedorAsync(int prvId, DateTime? desde, DateTime? hasta) =>
		ConsultarAsync<MovimientoEstadoCuenta>("dbo.paCxpEstadoCuentaConsultar", new { PrvId = prvId, Desde = desde?.Date, Hasta = hasta?.Date });

	public Task<IReadOnlyList<AntiguedadFila>> ConsultarAntiguedadProveedoresAsync(DateTime fechaCorte, int? prvId) =>
		ConsultarAsync<AntiguedadFila>("dbo.paCxpAntiguedadConsultar", new { FechaCorte = fechaCorte.Date, PrvId = prvId });

	public Task<IReadOnlyList<CuotaProveedor>> ConsultarCuotasProveedorAsync(int encId) =>
		ConsultarAsync<CuotaProveedor>("dbo.paProveedorPlanPagosConsultar", new { EncId = encId });

	public async Task<IReadOnlyList<Chequera>> ConsultarChequerasAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		// El siguiente número es el mayor emitido + 1, dentro del rango de la chequera.
		var filas = await connection.QueryAsync<Chequera>("""
			SELECT cheq.cbc_id, CONCAT(enti.gef_descripcion, ' ', cuen.bcb_numero_cuenta, ' (', cheq.cbc_cheque_del, '-', cheq.cbc_cheque_al, ')') AS Descripcion,
				   cheq.cbc_cheque_del, cheq.cbc_cheque_al,
				   CASE WHEN ISNULL(ulti.Ultimo, cheq.cbc_cheque_del - 1) + 1 <= cheq.cbc_cheque_al
						THEN ISNULL(ulti.Ultimo, cheq.cbc_cheque_del - 1) + 1 END AS SiguienteNumero
			FROM dbo.bco_cuenta_bancaria_chequera cheq
			INNER JOIN dbo.bco_cuenta_bancaria cuen ON cuen.bcb_id = cheq.bcb_id
			INNER JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuen.gef_id
			OUTER APPLY (SELECT MAX(TRY_CAST(emit.bce_numero_cheque AS INT)) AS Ultimo FROM dbo.bco_cheque_emitido_enc emit WHERE emit.cbc_id = cheq.cbc_id) ulti
			WHERE cheq.cbc_estado = 'A' AND cuen.bcb_estado = 'A'
			ORDER BY Descripcion
			""");
		return filas.ToList();
	}

	public async Task<IReadOnlyList<MotivoPago>> ConsultarMotivosPagoAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<MotivoPago>(
			"SELECT bmp_id, bmp_descripcion FROM dbo.bco_motivo_pago WHERE bmp_estado = 'A' ORDER BY bmp_descripcion");
		return filas.ToList();
	}

	public async Task<int> EmitirChequeAsync(int ppgId, int cbcId, string numeroCheque, decimal valor, int? bmpId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@ppg_id", ppgId);
		parametros.Add("@cbc_id", cbcId);
		parametros.Add("@bce_numero_cheque", numeroCheque);
		parametros.Add("@valor_pago", valor);
		parametros.Add("@bmp_id", bmpId);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@bce_id", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.sp_bancos_emitir_cheque_pago_proveedor", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@bce_id");
	}

	public Task<IReadOnlyList<NotaResumen>> ConsultarNotasAsync(bool esCliente, int? cliId, int? prvId, int? encIdReferencia) =>
		ConsultarAsync<NotaResumen>("dbo.paNotaConsultar", new { EsCliente = esCliente, CliId = cliId, PrvId = prvId, EncIdReferencia = encIdReferencia });

	public Task<IReadOnlyList<LineaDevolucion>> ConsultarLineasDevolucionAsync(int encId) =>
		ConsultarAsync<LineaDevolucion>("dbo.paDocumentoLineasDevolucionConsultar", new { EncId = encId });

	public async Task<(int EncId, string? Numero)> CrearNotaAsync(string tipoNota, int encIdReferencia, DateTime fecha, string? numeroDocto, string motivo,
		DateTime? fechaVencimiento, IReadOnlyList<NuevaLineaNota> lineas, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@TipoNota", tipoNota);
		parametros.Add("@EncIdReferencia", encIdReferencia);
		parametros.Add("@Fecha", fecha.Date);
		parametros.Add("@NumeroDocto", numeroDocto);
		parametros.Add("@Motivo", motivo);
		parametros.Add("@FechaVencimiento", fechaVencimiento?.Date);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@Detalle", ConstruirTablaNota(lineas).AsTableValuedParameter("dbo.nota_det_type"));
		parametros.Add("@EncId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		parametros.Add("@NumeroUnico", dbType: DbType.String, size: 16, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paNotaCrear", parametros, commandType: CommandType.StoredProcedure);
		return (parametros.Get<int>("@EncId"), parametros.Get<string?>("@NumeroUnico") ?? numeroDocto);
	}

	// Mismo orden de columnas que CREATE TYPE dbo.nota_det_type (32_cuentas_por_cobrar_pagar.sql).
	private static DataTable ConstruirTablaNota(IReadOnlyList<NuevaLineaNota> lineas)
	{
		var tabla = new DataTable();
		tabla.Columns.Add("det_item", typeof(int));
		tabla.Columns.Add("det_descripcion", typeof(string));
		tabla.Columns.Add("det_cantidad", typeof(decimal));
		tabla.Columns.Add("det_precio_unitario", typeof(decimal));
		tabla.Columns.Add("det_porc_iva", typeof(decimal));
		tabla.Columns.Add("ume_id", typeof(int));
		tabla.Columns.Add("det_id_origen", typeof(int));

		var item = 1;
		foreach (var linea in lineas)
		{
			tabla.Rows.Add(item++, linea.Descripcion, linea.Cantidad, linea.PrecioUnitario,
				(object?)linea.PorcentajeIva ?? DBNull.Value, (object?)linea.UmeId ?? DBNull.Value, (object?)linea.DetIdOrigen ?? DBNull.Value);
		}
		return tabla;
	}
}
