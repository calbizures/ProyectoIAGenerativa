using System.Data;
using Dapper;
using Erp.Data.Security;

namespace Erp.Data.Caja;

public sealed class CajaRepository(IDbConnectionFactory connectionFactory) : ICajaRepository
{
	public async Task<IReadOnlyList<Sucursal>> ConsultarSucursalesAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<Sucursal>(
			"SELECT suc_id, suc_codigo, suc_descripcion FROM dbo.gen_sucursal WHERE suc_estado = 'A' ORDER BY suc_descripcion");
		return filas.ToList();
	}

	public async Task<IReadOnlyList<FormaPagoTipo>> ConsultarFormasPagoTipoAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<FormaPagoTipo>(
			"SELECT pft_id, pft_descripcion FROM dbo.pos_pago_forma_tipo WHERE pft_estado = 'A' ORDER BY pft_descripcion");
		return filas.ToList();
	}

	public async Task<IReadOnlyList<EntidadFinanciera>> ConsultarEntidadesFinancierasAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<EntidadFinanciera>(
			"dbo.paEntidadFinancieraConsultar", new { GeftId = (int?)null, SoloActivas = true }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> InsertarCajaReceptoraAsync(string descripcion, int sucId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@pcr_descripcion", descripcion);
		parametros.Add("@suc_id", sucId);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@pcr_id", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.paCajaReceptoraInsertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@pcr_id");
	}

	public async Task ActualizarCajaReceptoraAsync(int pcrId, string descripcion, int sucId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { pcr_id = pcrId, pcr_descripcion = descripcion, suc_id = sucId, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paCajaReceptoraActualizar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task EliminarCajaReceptoraAsync(int pcrId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { pcr_id = pcrId, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paCajaReceptoraEliminar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<CajaReceptora>> ConsultarCajasReceptorasAsync(int? sucId, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { suc_id = sucId, pcr_estado = estado };
		var filas = await connection.QueryAsync<CajaReceptora>(
			"dbo.paCajaReceptoraConsultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<int> AbrirCajaAsync(int pcrId, decimal montoInicial, int? usuarioId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@pcr_id", pcrId);
		parametros.Add("@usu_id", usuarioId);
		parametros.Add("@pca_monto_inicial", montoInicial);
		parametros.Add("@pca_id", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.sp_pos_caja_abrir", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@pca_id");
	}

	public async Task<IReadOnlyList<CajaAperturaActiva>> ConsultarAperturaActivaPorSucursalAsync(int sucId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<CajaAperturaActiva>(
			"dbo.paCajaAperturaConsultarActivaPorSucursal", new { suc_id = sucId }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<IReadOnlyList<CajaApertura>> ConsultarAperturasAsync(int? sucId, string? estado, int pagina, int tamanioPagina)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { suc_id = sucId, pca_estado = estado, pagina, tamanio_pagina = tamanioPagina };
		var filas = await connection.QueryAsync<CajaApertura>(
			"dbo.paCajaAperturaConsultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task CerrarCajaAsync(int pcaId, int? usuarioId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { pca_id = pcaId, usu_id = usuarioId };
		await connection.ExecuteAsync("dbo.sp_pos_caja_cerrar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<FormaPagoTeorico>> ConsultarTeoricoAsync(int pcaId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<FormaPagoTeorico>(
			"dbo.paCorteCajaTeoricoConsultar", new { pca_id = pcaId }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<CuadreCaja?> ConsultarCuadreAsync(int pcaId)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.QueryFirstOrDefaultAsync<CuadreCaja>(
			"dbo.paCorteCajaCuadreConsultar", new { pca_id = pcaId }, commandType: CommandType.StoredProcedure);
	}

	public async Task GuardarDesgloseEfectivoAsync(int pcaId, IReadOnlyList<DenominacionEfectivo> denominaciones, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var tabla = new DataTable();
		tabla.Columns.Add("def_tipo_denominacion", typeof(string));
		tabla.Columns.Add("def_denominacion", typeof(decimal));
		tabla.Columns.Add("def_cantidad", typeof(int));
		foreach (var d in denominaciones)
			tabla.Rows.Add(d.TipoDenominacion, d.Denominacion, d.Cantidad);

		var parametros = new DynamicParameters();
		parametros.Add("@pca_id", pcaId);
		parametros.Add("@denominaciones", tabla.AsTableValuedParameter("dbo.caja_denominacion_type"));
		parametros.Add("@usu_id", usuarioAccionId);

		await connection.ExecuteAsync("dbo.paCajaDesgloseEfectivoGuardar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task GuardarCorteFormaAsync(int pcaId, IReadOnlyList<CorteFormaFisico> formas, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var tabla = new DataTable();
		tabla.Columns.Add("pft_id", typeof(int));
		tabla.Columns.Add("pcf_monto_fisico", typeof(decimal));
		foreach (var f in formas)
			tabla.Rows.Add(f.PftId, f.MontoFisico);

		var parametros = new DynamicParameters();
		parametros.Add("@pca_id", pcaId);
		parametros.Add("@formas", tabla.AsTableValuedParameter("dbo.caja_corte_forma_type"));
		parametros.Add("@usu_id", usuarioAccionId);

		await connection.ExecuteAsync("dbo.paCajaCorteFormaGuardar", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<int> InsertarDepositoAsync(int pcaId, int gefId, DateTime fecha, decimal valor, string? numeroBoleta, string? observaciones, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new DynamicParameters();
		parametros.Add("@pca_id", pcaId);
		parametros.Add("@gef_id", gefId);
		parametros.Add("@pcd_fecha_deposito", fecha);
		parametros.Add("@pcd_valor_deposito", valor);
		parametros.Add("@pcd_numero_boleta", numeroBoleta);
		parametros.Add("@pcd_observaciones", observaciones);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@pcd_id", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.paCajaDepositoInsertar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@pcd_id");
	}

	public async Task<IReadOnlyList<DepositoCaja>> ConsultarDepositosAsync(int? pcaId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<DepositoCaja>(
			"dbo.paCajaDepositoConsultar", new { pca_id = pcaId }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	// Reutilizado por FacturaRepository para armar el TVP dbo.pago_forma_type
	// al grabar el pago inicial de una factura (contado o enganche).
	internal static DataTable ConstruirTablaFormasPago(IReadOnlyList<FormaPagoCaptura> formasPago)
	{
		var tabla = new DataTable();
		tabla.Columns.Add("pft_id", typeof(int));
		tabla.Columns.Add("ppf_monto", typeof(decimal));
		tabla.Columns.Add("gef_id", typeof(int));
		tabla.Columns.Add("ppf_numero_tarjeta_ult4", typeof(string));
		tabla.Columns.Add("ppf_fecha_vencimiento_tarjeta", typeof(string));
		tabla.Columns.Add("ppf_numero_cheque", typeof(string));

		foreach (var f in formasPago)
		{
			tabla.Rows.Add(
				f.PftId,
				f.Monto,
				(object?)f.GefId ?? DBNull.Value,
				(object?)f.NumeroTarjetaUlt4 ?? DBNull.Value,
				(object?)f.FechaVencimientoTarjeta ?? DBNull.Value,
				(object?)f.NumeroCheque ?? DBNull.Value);
		}

		return tabla;
	}
}
