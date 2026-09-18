using System.Data;
using Dapper;

namespace Erp.Data.Compras;

public sealed class CompraRepository(IDbConnectionFactory connectionFactory) : ICompraRepository
{
	public async Task<IReadOnlyList<Proveedor>> ConsultarProveedoresAsync(string? texto, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { texto, prv_estado = estado };
		var filas = await connection.QueryAsync<Proveedor>("dbo.sp_proveedor_consultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	// Sin procedimiento dedicado (catálogo sin lógica que auditar): tipos de
	// documento cuya naturaleza es "+" (ingresan existencia), es decir, de compra.
	public async Task<IReadOnlyList<DocumentoTipoCompra>> ConsultarTiposDocumentoAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<DocumentoTipoCompra>(
			"SELECT tdo_id, tdo_codigo, tdo_descripcion FROM dbo.inv_documento_tipo WHERE tdo_naturaleza = '+' AND tdo_estado = 'A' ORDER BY tdo_descripcion");
		return filas.ToList();
	}

	// Mismo catálogo gen_moneda que usa Ventas; se duplica aquí (en vez de
	// referenciar Erp.Data.Ventas) para que cada módulo quede autocontenido.
	public async Task<IReadOnlyList<Moneda>> ConsultarMonedasAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<Moneda>(
			"SELECT mon_id, mon_codigo, mon_nombre, mon_simbolo, mon_es_local FROM dbo.gen_moneda WHERE mon_estado = 'A' ORDER BY mon_es_local DESC, mon_codigo");
		return filas.ToList();
	}

	public async Task<int> CrearAsync(NuevaCompraEncabezado encabezado, IReadOnlyList<NuevaLineaCompra> detalle, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var tablaDetalle = ConstruirTablaDetalle(detalle);

		var parametros = new DynamicParameters();
		parametros.Add("@enc_fecha_docto", encabezado.FechaDocumento);
		parametros.Add("@enc_numero_autorizacion", encabezado.NumeroAutorizacion);
		parametros.Add("@enc_serie_docto", encabezado.SerieDocumento);
		parametros.Add("@enc_numero_docto", encabezado.NumeroDocumento);
		parametros.Add("@prv_id", encabezado.PrvId);
		parametros.Add("@prv_enc_nombres_proveedor", encabezado.NombreProveedor);
		parametros.Add("@prv_enc_apellidos_proveedor", (string?)null);
		parametros.Add("@prv_nit", encabezado.Nit);
		parametros.Add("@tdo_id", encabezado.TdoId);
		parametros.Add("@enc_fecha_primer_pago", encabezado.FechaPrimerPago);
		parametros.Add("@enc_monto_enganche", encabezado.MontoEnganche);
		parametros.Add("@enc_numero_cuotas", encabezado.NumeroCuotas);
		parametros.Add("@enc_valor_descuento", encabezado.ValorDescuento);
		parametros.Add("@mon_id", encabezado.MonId);
		parametros.Add("@usu_id", usuarioAccionId);
		parametros.Add("@detalle", tablaDetalle.AsTableValuedParameter("dbo.compra_det_type"));
		parametros.Add("@enc_id", dbType: DbType.Int32, direction: ParameterDirection.Output);

		await connection.ExecuteAsync("dbo.sp_compras_crear_documento", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@enc_id");
	}

	public async Task AnularAsync(int encId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { enc_id = encId, usu_id = usuarioAccionId };
		await connection.ExecuteAsync("dbo.sp_documento_anular", parametros, commandType: CommandType.StoredProcedure);
	}

	// paDocumentoConsultar filtra por un único @tdo_id; como Compras agrupa
	// más de un tipo de documento (COMP, GAST), se consulta cada tipo por
	// separado y se combinan los resultados (mismo criterio que la búsqueda
	// de productos por código/descripción en Facturas.razor).
	public async Task<IReadOnlyList<CompraEncabezado>> ConsultarAsync(IReadOnlyList<int> tiposDocumento, int? prvId, DateTime? fechaDesde, DateTime? fechaHasta, string? estado, int pagina, int tamanioPagina)
	{
		using var connection = connectionFactory.CreateConnection();
		var resultados = new List<CompraEncabezado>();

		foreach (var tdoId in tiposDocumento)
		{
			var parametros = new
			{
				tdo_id = tdoId,
				cli_id = (int?)null,
				prv_id = prvId,
				fecha_desde = fechaDesde,
				fecha_hasta = fechaHasta,
				enc_estado = estado,
				pagina = 1,
				tamanio_pagina = tamanioPagina
			};
			var filas = await connection.QueryAsync<CompraEncabezado>("dbo.paDocumentoConsultar", parametros, commandType: CommandType.StoredProcedure);
			resultados.AddRange(filas);
		}

		return resultados
			.OrderByDescending(e => e.EncFechaDocto)
			.ThenByDescending(e => e.EncId)
			.Skip((pagina - 1) * tamanioPagina)
			.Take(tamanioPagina)
			.ToList();
	}

	public async Task<(CompraEncabezadoDetalle? Encabezado, IReadOnlyList<CompraDetalleLinea> Detalle)> ConsultarPorIdAsync(int encId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var multi = await connection.QueryMultipleAsync(
			"dbo.sp_documento_consultar_por_id",
			new { enc_id = encId },
			commandType: CommandType.StoredProcedure);

		var encabezado = await multi.ReadFirstOrDefaultAsync<CompraEncabezadoDetalle>();
		var detalle = (await multi.ReadAsync<CompraDetalleLinea>()).ToList();
		return (encabezado, detalle);
	}

	// El orden de las columnas debe coincidir exactamente con CREATE TYPE
	// dbo.compra_det_type (01_tipos_tabla.sql): SQL Server relaciona los
	// parámetros de tabla por posición, no por nombre.
	private static DataTable ConstruirTablaDetalle(IReadOnlyList<NuevaLineaCompra> detalle)
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
				(object?)linea.ProId ?? DBNull.Value);
		}

		return tabla;
	}
}
