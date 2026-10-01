using System.Data;
using Dapper;

namespace Erp.Data.Compras;

public sealed class OrdenCompraRepository(IDbConnectionFactory connectionFactory) : IOrdenCompraRepository
{
	public async Task<IReadOnlyList<OrdenCompraResumen>> ConsultarAsync(string? estado, int? prvId, DateTime? desde, DateTime? hasta, string? texto)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<OrdenCompraResumen>("dbo.paOrdenCompraConsultar",
			new { Estado = string.IsNullOrEmpty(estado) ? null : estado, PrvId = prvId, Desde = desde, Hasta = hasta, Texto = texto },
			commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<(OrdenCompraEncabezado? Encabezado, IReadOnlyList<OrdenCompraLinea> Lineas, IReadOnlyList<OrdenCompraRecepcion> Recepciones)> ConsultarPorIdAsync(int ocpId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paOrdenCompraConsultarPorId", new { OcpId = ocpId },
			commandType: CommandType.StoredProcedure);
		var encabezado = await lector.ReadFirstOrDefaultAsync<OrdenCompraEncabezado>();
		var lineas = (await lector.ReadAsync<OrdenCompraLinea>()).ToList();
		var recepciones = (await lector.ReadAsync<OrdenCompraRecepcion>()).ToList();
		return (encabezado, lineas, recepciones);
	}

	public async Task<(int OcpId, string Numero)> GuardarAsync(NuevaOrdenCompra orden, IReadOnlyList<NuevaLineaOrdenCompra> lineas, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var tabla = new DataTable();
		tabla.Columns.Add("item", typeof(int));
		tabla.Columns.Add("pro_id", typeof(int));
		tabla.Columns.Add("descripcion", typeof(string));
		tabla.Columns.Add("cantidad", typeof(int));
		tabla.Columns.Add("costo_unitario", typeof(decimal));
		var item = 1;
		foreach (var linea in lineas)
			tabla.Rows.Add(item++, linea.ProId, (object?)linea.Descripcion ?? DBNull.Value, linea.Cantidad, linea.CostoUnitario);

		var parametros = new DynamicParameters();
		parametros.Add("@OcpId", orden.OcpId, DbType.Int32, ParameterDirection.InputOutput);
		parametros.Add("@Fecha", orden.Fecha);
		parametros.Add("@FechaEntrega", orden.FechaEntrega);
		parametros.Add("@PrvId", orden.PrvId);
		parametros.Add("@BodId", orden.BodId);
		parametros.Add("@MonId", orden.MonId);
		parametros.Add("@Condiciones", orden.Condiciones);
		parametros.Add("@Observaciones", orden.Observaciones);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@Detalle", tabla.AsTableValuedParameter("dbo.orden_compra_det_type"));
		parametros.Add("@Numero", dbType: DbType.String, size: 16, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paOrdenCompraGuardar", parametros, commandType: CommandType.StoredProcedure);
		return (parametros.Get<int>("@OcpId"), parametros.Get<string>("@Numero"));
	}

	public async Task AprobarAsync(int ocpId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paOrdenCompraAprobar", new { OcpId = ocpId, UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}

	public async Task AnularAsync(int ocpId, string motivo, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paOrdenCompraAnular", new { OcpId = ocpId, Motivo = motivo, UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}

	public async Task CerrarAsync(int ocpId, string motivo, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paOrdenCompraCerrar", new { OcpId = ocpId, Motivo = motivo, UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}

	public async Task<int> RecibirAsync(int ocpId, RecepcionOrdenCompra recepcion, IReadOnlyList<LineaRecepcionOrdenCompra> lineas, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var tabla = new DataTable();
		tabla.Columns.Add("ocd_id", typeof(int));
		tabla.Columns.Add("cantidad", typeof(int));
		tabla.Columns.Add("costo_unitario", typeof(decimal));
		foreach (var linea in lineas)
			tabla.Rows.Add(linea.OcdId, linea.Cantidad, linea.CostoUnitario);

		var parametros = new DynamicParameters();
		parametros.Add("@OcpId", ocpId);
		parametros.Add("@Fecha", recepcion.Fecha);
		parametros.Add("@Serie", recepcion.Serie);
		parametros.Add("@NumeroDocumento", recepcion.NumeroDocumento);
		parametros.Add("@Autorizacion", recepcion.Autorizacion);
		parametros.Add("@FechaPrimerPago", recepcion.FechaPrimerPago);
		parametros.Add("@NumeroCuotas", recepcion.FechaPrimerPago is null ? 1 : recepcion.NumeroCuotas);
		parametros.Add("@Enganche", recepcion.FechaPrimerPago is null ? 0 : recepcion.Enganche);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@Lineas", tabla.AsTableValuedParameter("dbo.orden_compra_recepcion_type"));
		parametros.Add("@EncId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paOrdenCompraRecibir", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@EncId");
	}
}
