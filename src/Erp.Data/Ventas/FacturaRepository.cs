using System.Data;
using Dapper;
using Erp.Data.Caja;

namespace Erp.Data.Ventas;

public sealed class FacturaRepository(IDbConnectionFactory connectionFactory) : IFacturaRepository
{
	public async Task<IReadOnlyList<Cliente>> ConsultarClientesAsync(string? texto, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { Texto = texto, CliEstado = estado };
		var filas = await connection.QueryAsync<Cliente>("dbo.paClienteConsultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	// Sin procedimiento CRUD todavía (no hay pantalla de Vendedores/Monedas/
	// Tipos de documento aún); son catálogos de solo lectura para los combos
	// de la factura, mismo criterio que otras lecturas simples del proyecto.
	public async Task<IReadOnlyList<Vendedor>> ConsultarVendedoresAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<Vendedor>(
			"SELECT pve_id, pve_codigo, pve_nombres, pve_apellidos FROM dbo.pos_vendedor WHERE pve_estado = 'A' ORDER BY pve_nombres");
		return filas.ToList();
	}

	public async Task<IReadOnlyList<Moneda>> ConsultarMonedasAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<Moneda>(
			"SELECT mon_id, mon_codigo, mon_nombre, mon_simbolo, mon_es_local FROM dbo.gen_moneda WHERE mon_estado = 'A' ORDER BY mon_es_local DESC, mon_codigo");
		return filas.ToList();
	}

	public async Task<IReadOnlyList<DocumentoTipoVenta>> ConsultarTiposDocumentoAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<DocumentoTipoVenta>(
			"SELECT tdo_id, tdo_codigo, tdo_descripcion FROM dbo.inv_documento_tipo WHERE tdo_naturaleza = '-' AND tdo_estado = 'A' AND tdo_es_nota = 0 AND tdo_es_interno = 0 ORDER BY tdo_descripcion");
		return filas.ToList();
	}

	public async Task<(int EncId, string NumeroUnico)> CrearAsync(
		NuevaFacturaEncabezado encabezado, IReadOnlyList<NuevaLineaFactura> detalle, int? usuarioAccionId,
		int? pcaId = null, IReadOnlyList<FormaPagoCaptura>? formasPago = null)
	{
		using var connection = connectionFactory.CreateConnection();
		var tablaDetalle = ConstruirTablaDetalle(detalle);
		var tablaFormasPago = CajaRepository.ConstruirTablaFormasPago(formasPago ?? Array.Empty<FormaPagoCaptura>());

		var parametros = new DynamicParameters();
		parametros.Add("@EncFechaDocto", encabezado.FechaDocumento);
		parametros.Add("@EncNumeroAutorizacion", encabezado.NumeroAutorizacion);
		parametros.Add("@EncSerieDocto", encabezado.SerieDocumento);
		parametros.Add("@EncNumeroDocto", encabezado.NumeroDocumento);
		parametros.Add("@CliId", encabezado.CliId);
		parametros.Add("@EncNombresCliente", encabezado.NombresCliente);
		parametros.Add("@EncApellidosCliente", encabezado.ApellidosCliente);
		parametros.Add("@CliNit", encabezado.Nit);
		parametros.Add("@TdoId", encabezado.TdoId);
		parametros.Add("@PveId", encabezado.PveId);
		parametros.Add("@EncFechaPrimerPago", encabezado.FechaPrimerPago);
		parametros.Add("@EncMontoEnganche", encabezado.MontoEnganche);
		parametros.Add("@EncNumeroCuotas", encabezado.NumeroCuotas);
		parametros.Add("@EncValorDescuento", encabezado.ValorDescuento);
		parametros.Add("@EncDireccionCliente", encabezado.DireccionCliente);
		parametros.Add("@MonId", encabezado.MonId);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@CotId", encabezado.CotId);
		parametros.Add("@Detalle", tablaDetalle.AsTableValuedParameter("dbo.factura_det_type"));
		parametros.Add("@PcaId", pcaId);
		parametros.Add("@FormasPago", tablaFormasPago.AsTableValuedParameter("dbo.pago_forma_type"));
		parametros.Add("@EncId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		parametros.Add("@EncNumeroUnico", dbType: DbType.String, size: 16, direction: ParameterDirection.Output);

		// Con comprobantes de transferencias, la factura y sus comprobantes se graban juntos.
		if (!ComprobantesFormaPago.HayComprobantes(formasPago))
		{
			await connection.ExecuteAsync("dbo.paVentaFacturaCrear", parametros, commandType: CommandType.StoredProcedure);
			return (parametros.Get<int>("@EncId"), parametros.Get<string>("@EncNumeroUnico"));
		}
		connection.Open();
		using var transaccion = connection.BeginTransaction();
		await connection.ExecuteAsync("dbo.paVentaFacturaCrear", parametros, transaccion, commandType: CommandType.StoredProcedure);
		var encId = parametros.Get<int>("@EncId");
		await ComprobantesFormaPago.GuardarAsync(connection, transaccion, null, encId, formasPago!, usuarioAccionId);
		transaccion.Commit();
		return (encId, parametros.Get<string>("@EncNumeroUnico"));
	}

	public async Task AnularAsync(int encId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { EncId = encId, UsuId = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paDocumentoAnular", parametros, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<FacturaEncabezado>> ConsultarAsync(int tdoId, int? cliId, DateTime? fechaDesde, DateTime? fechaHasta, string? estado, int pagina, int tamanioPagina)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new
		{
			tdo_id = tdoId,
			cli_id = cliId,
			fecha_desde = fechaDesde,
			fecha_hasta = fechaHasta,
			enc_estado = estado,
			pagina,
			tamanio_pagina = tamanioPagina
		};
		var filas = await connection.QueryAsync<FacturaEncabezado>("dbo.paDocumentoConsultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<(FacturaEncabezadoDetalle? Encabezado, IReadOnlyList<FacturaDetalleLinea> Detalle)> ConsultarPorIdAsync(int encId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var multi = await connection.QueryMultipleAsync(
			"dbo.paDocumentoConsultarPorId",
			new { EncId = encId },
			commandType: CommandType.StoredProcedure);

		var encabezado = await multi.ReadFirstOrDefaultAsync<FacturaEncabezadoDetalle>();
		var detalle = (await multi.ReadAsync<FacturaDetalleLinea>()).ToList();
		return (encabezado, detalle);
	}

	public async Task<IReadOnlyList<CuotaPlanPago>> ConsultarPlanPagosAsync(int encId)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<CuotaPlanPago>(
			"dbo.paClientePlanPagosConsultar", new { enc_id = encId }, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	// El orden de las columnas debe coincidir exactamente con CREATE TYPE
	// dbo.factura_det_type (31_sucursales_unidades_organigrama.sql): SQL Server relaciona los
	// parámetros de tabla por posición, no por nombre.
	private static DataTable ConstruirTablaDetalle(IReadOnlyList<NuevaLineaFactura> detalle)
	{
		var tabla = new DataTable();
		tabla.Columns.Add("det_item", typeof(int));
		tabla.Columns.Add("det_bien_o_servicio", typeof(string));
		tabla.Columns.Add("det_cantidad", typeof(decimal));
		tabla.Columns.Add("det_descripcion", typeof(string));
		tabla.Columns.Add("det_precio_unitario", typeof(decimal));
		tabla.Columns.Add("det_valor_descuento", typeof(decimal));
		tabla.Columns.Add("det_sub_total", typeof(decimal));
		tabla.Columns.Add("det_costo_unitario", typeof(decimal));
		tabla.Columns.Add("det_porc_iva", typeof(decimal));
		tabla.Columns.Add("bod_id", typeof(int));
		tabla.Columns.Add("pro_id", typeof(int));
		tabla.Columns.Add("ppr_id", typeof(int));
		tabla.Columns.Add("ume_id", typeof(int));

		var item = 1;
		foreach (var linea in detalle)
		{
			tabla.Rows.Add(
				item++,
				linea.BienOServicio,
				linea.Cantidad,
				linea.Descripcion,
				linea.PrecioUnitario,
				linea.ValorDescuento,
				linea.SubTotal,
				(object?)linea.CostoUnitario ?? DBNull.Value,
				(object?)linea.PorcentajeIva ?? DBNull.Value,
				linea.BodId,
				(object?)linea.ProId ?? DBNull.Value,
				(object?)linea.PprId ?? DBNull.Value,
				(object?)linea.UmeId ?? DBNull.Value);
		}

		return tabla;
	}

	public async Task<FacturaImpresion?> ConsultarImpresionAsync(int encId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paFacturaImpresionConsultar", new { EncId = encId }, commandType: CommandType.StoredProcedure);
		var encabezado = await lector.ReadFirstOrDefaultAsync<FacturaImpresionEncabezado>();
		var lineas = (await lector.ReadAsync<FacturaImpresionLinea>()).ToList();
		var frases = (await lector.ReadAsync<FacturaImpresionFrase>()).ToList();
		var cuotas = (await lector.ReadAsync<FacturaImpresionCuota>()).ToList();
		var pagos = (await lector.ReadAsync<FacturaImpresionPago>()).ToList();
		return encabezado is null ? null : new FacturaImpresion(encabezado, lineas, frases, cuotas, pagos);
	}
}
