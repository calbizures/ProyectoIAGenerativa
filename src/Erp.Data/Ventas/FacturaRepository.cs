using System.Data;
using Dapper;

namespace Erp.Data.Ventas;

public sealed class FacturaRepository(IDbConnectionFactory connectionFactory) : IFacturaRepository
{
	public async Task<IReadOnlyList<Cliente>> ConsultarClientesAsync(string? texto, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { texto, cli_estado = estado };
		var filas = await connection.QueryAsync<Cliente>("dbo.sp_cliente_consultar", parametros, commandType: CommandType.StoredProcedure);
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
			"SELECT tdo_id, tdo_codigo, tdo_descripcion FROM dbo.inv_documento_tipo WHERE tdo_naturaleza = '-' AND tdo_estado = 'A' ORDER BY tdo_descripcion");
		return filas.ToList();
	}

	public async Task<(int EncId, string NumeroUnico)> CrearAsync(NuevaFacturaEncabezado encabezado, IReadOnlyList<NuevaLineaFactura> detalle, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var tablaDetalle = ConstruirTablaDetalle(detalle);

		var parametros = new DynamicParameters();
		parametros.Add("@enc_fecha_docto", encabezado.FechaDocumento);
		parametros.Add("@enc_numero_autorizacion", encabezado.NumeroAutorizacion);
		parametros.Add("@enc_serie_docto", encabezado.SerieDocumento);
		parametros.Add("@enc_numero_docto", encabezado.NumeroDocumento);
		parametros.Add("@cli_id", encabezado.CliId);
		parametros.Add("@enc_nombres_cliente", encabezado.NombresCliente);
		parametros.Add("@enc_apellidos_cliente", encabezado.ApellidosCliente);
		parametros.Add("@cli_nit", encabezado.Nit);
		parametros.Add("@tdo_id", encabezado.TdoId);
		parametros.Add("@pve_id", encabezado.PveId);
		parametros.Add("@enc_fecha_primer_pago", encabezado.FechaPrimerPago);
		parametros.Add("@enc_monto_enganche", encabezado.MontoEnganche);
		parametros.Add("@enc_numero_cuotas", encabezado.NumeroCuotas);
		parametros.Add("@enc_valor_descuento", encabezado.ValorDescuento);
		parametros.Add("@enc_direccion_cliente", encabezado.DireccionCliente);
		parametros.Add("@mon_id", encabezado.MonId);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@detalle", tablaDetalle.AsTableValuedParameter("dbo.factura_det_type"));
		parametros.Add("@enc_id", dbType: DbType.Int32, direction: ParameterDirection.Output);
		parametros.Add("@enc_numero_unico", dbType: DbType.String, size: 16, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.sp_ventas_crear_factura", parametros, commandType: CommandType.StoredProcedure);
		return (parametros.Get<int>("@enc_id"), parametros.Get<string>("@enc_numero_unico"));
	}

	public async Task AnularAsync(int encId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { enc_id = encId, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.sp_documento_anular", parametros, commandType: CommandType.StoredProcedure);
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
		var filas = await connection.QueryAsync<FacturaEncabezado>("dbo.sp_documento_consultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<(FacturaEncabezadoDetalle? Encabezado, IReadOnlyList<FacturaDetalleLinea> Detalle)> ConsultarPorIdAsync(int encId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var multi = await connection.QueryMultipleAsync(
			"dbo.sp_documento_consultar_por_id",
			new { enc_id = encId },
			commandType: CommandType.StoredProcedure);

		var encabezado = await multi.ReadFirstOrDefaultAsync<FacturaEncabezadoDetalle>();
		var detalle = (await multi.ReadAsync<FacturaDetalleLinea>()).ToList();
		return (encabezado, detalle);
	}

	// El orden de las columnas debe coincidir exactamente con CREATE TYPE
	// dbo.factura_det_type (01_tipos_tabla.sql): SQL Server relaciona los
	// parámetros de tabla por posición, no por nombre.
	private static DataTable ConstruirTablaDetalle(IReadOnlyList<NuevaLineaFactura> detalle)
	{
		var tabla = new DataTable();
		tabla.Columns.Add("det_item", typeof(int));
		tabla.Columns.Add("det_bien_o_servicio", typeof(string));
		tabla.Columns.Add("det_cantidad", typeof(int));
		tabla.Columns.Add("det_descripcion", typeof(string));
		tabla.Columns.Add("det_precio_unitario", typeof(decimal));
		tabla.Columns.Add("det_valor_descuento", typeof(decimal));
		tabla.Columns.Add("det_sub_total", typeof(decimal));
		tabla.Columns.Add("det_porc_iva", typeof(decimal));
		tabla.Columns.Add("bod_id", typeof(int));
		tabla.Columns.Add("pro_id", typeof(int));
		tabla.Columns.Add("ppr_id", typeof(int));

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
				(object?)linea.PorcentajeIva ?? DBNull.Value,
				linea.BodId,
				linea.ProId,
				DBNull.Value);
		}

		return tabla;
	}
}
