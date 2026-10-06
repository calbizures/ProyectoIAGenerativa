using System.Data;
using Dapper;

namespace Erp.Data.Compras;

public sealed class CompraRepository(IDbConnectionFactory connectionFactory) : ICompraRepository
{
	public async Task<IReadOnlyList<Proveedor>> ConsultarProveedoresAsync(string? texto, string? estado)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { Texto = texto, PrvEstado = estado };
		var filas = await connection.QueryAsync<Proveedor>("dbo.paProveedorConsultar", parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	// Sin procedimiento dedicado (catálogo sin lógica que auditar): tipos de
	// documento cuya naturaleza es "+" (ingresan existencia), es decir, de compra.
	public async Task<IReadOnlyList<DocumentoTipoCompra>> ConsultarTiposDocumentoAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<DocumentoTipoCompra>(
			"SELECT tdo_id, tdo_codigo, tdo_descripcion FROM dbo.inv_documento_tipo WHERE tdo_naturaleza = '+' AND tdo_estado = 'A' AND tdo_es_nota = 0 AND tdo_es_interno = 0 ORDER BY tdo_descripcion");
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
		parametros.Add("@EncFechaDocto", encabezado.FechaDocumento);
		parametros.Add("@EncNumeroAutorizacion", encabezado.NumeroAutorizacion);
		parametros.Add("@EncSerieDocto", encabezado.SerieDocumento);
		parametros.Add("@EncNumeroDocto", encabezado.NumeroDocumento);
		parametros.Add("@PrvId", encabezado.PrvId);
		parametros.Add("@PrvEncNombresProveedor", encabezado.NombreProveedor);
		parametros.Add("@PrvEncApellidosProveedor", (string?)null);
		parametros.Add("@PrvNit", encabezado.Nit);
		parametros.Add("@TdoId", encabezado.TdoId);
		parametros.Add("@EncFechaPrimerPago", encabezado.FechaPrimerPago);
		parametros.Add("@EncMontoEnganche", encabezado.MontoEnganche);
		parametros.Add("@EncNumeroCuotas", encabezado.NumeroCuotas);
		parametros.Add("@EncValorDescuento", encabezado.ValorDescuento);
		parametros.Add("@MonId", encabezado.MonId);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@Detalle", tablaDetalle.AsTableValuedParameter("dbo.compra_det_type"));
		parametros.Add("@EncId", dbType: DbType.Int32, direction: ParameterDirection.Output);

		// Líneas de activo fijo: det_item (posición) → categoría y centro de costo.
		var tablaActivos = new DataTable();
		tablaActivos.Columns.Add("det_item", typeof(int));
		tablaActivos.Columns.Add("afc_id", typeof(int));
		tablaActivos.Columns.Add("IdDepartamento", typeof(int));
		for (var i = 0; i < detalle.Count; i++)
			if (detalle[i].AfcId is int afcId)
				tablaActivos.Rows.Add(i + 1, afcId, (object?)detalle[i].IdDepartamento ?? DBNull.Value);
		parametros.Add("@Activos", tablaActivos.AsTableValuedParameter("dbo.compra_activo_type"));

		await connection.ExecuteAsync("dbo.paCompraDocumentoCrear", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@EncId");
	}

	public async Task AnularAsync(int encId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var parametros = new { EncId = encId, UsuId = usuarioAccionId };
		await connection.ExecuteAsync("dbo.paDocumentoAnular", parametros, commandType: CommandType.StoredProcedure);
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
			"dbo.paDocumentoConsultarPorId",
			new { EncId = encId },
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
