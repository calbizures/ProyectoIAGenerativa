using System.Data;
using Dapper;

namespace Erp.Data.Ventas;

public sealed class CotizacionRepository(IDbConnectionFactory connectionFactory) : ICotizacionRepository
{
	public async Task<IReadOnlyList<CotizacionResumen>> ConsultarAsync(int? sucId, DateTime? desde, DateTime? hasta, string? estado, string? texto)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<CotizacionResumen>("dbo.paCotizacionConsultar",
			new { SucId = sucId, Desde = desde, Hasta = hasta, Estado = string.IsNullOrEmpty(estado) ? null : estado, Texto = texto },
			commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	public async Task<(CotizacionEncabezado? Encabezado, IReadOnlyList<CotizacionLinea> Lineas)> ConsultarPorIdAsync(int cotId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paCotizacionConsultarPorId", new { CotId = cotId },
			commandType: CommandType.StoredProcedure);
		var encabezado = await lector.ReadFirstOrDefaultAsync<CotizacionEncabezado>();
		var lineas = (await lector.ReadAsync<CotizacionLinea>()).ToList();
		return (encabezado, lineas);
	}

	public async Task<(int CotId, string Numero)> GuardarAsync(NuevaCotizacion cotizacion, IReadOnlyList<NuevaLineaCotizacion> lineas, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		var tabla = new DataTable();
		tabla.Columns.Add("item", typeof(int));
		tabla.Columns.Add("bien_o_servicio", typeof(string));
		tabla.Columns.Add("pro_id", typeof(int));
		tabla.Columns.Add("ppr_id", typeof(int));
		tabla.Columns.Add("ume_id", typeof(int));
		tabla.Columns.Add("descripcion", typeof(string));
		tabla.Columns.Add("cantidad", typeof(decimal));
		tabla.Columns.Add("precio_unitario", typeof(decimal));
		tabla.Columns.Add("valor_descuento", typeof(decimal));
		var item = 1;
		foreach (var linea in lineas)
		{
			tabla.Rows.Add(item++, linea.BienOServicio, (object?)linea.ProId ?? DBNull.Value, (object?)linea.PprId ?? DBNull.Value,
				(object?)linea.UmeId ?? DBNull.Value, linea.Descripcion, linea.Cantidad, linea.PrecioUnitario, linea.Descuento);
		}

		var parametros = new DynamicParameters();
		parametros.Add("@Fecha", cotizacion.Fecha);
		parametros.Add("@BodId", cotizacion.BodId);
		parametros.Add("@MonId", cotizacion.MonId);
		parametros.Add("@CliId", cotizacion.CliId);
		parametros.Add("@Nit", cotizacion.Nit);
		parametros.Add("@Nombre", cotizacion.Nombre);
		parametros.Add("@Direccion", cotizacion.Direccion);
		parametros.Add("@Telefono", cotizacion.Telefono);
		parametros.Add("@Correo", cotizacion.Correo);
		parametros.Add("@PveId", cotizacion.PveId);
		parametros.Add("@Observaciones", cotizacion.Observaciones);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@Detalle", tabla.AsTableValuedParameter("dbo.cotizacion_det_type"));
		parametros.Add("@CotId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		parametros.Add("@Numero", dbType: DbType.String, size: 16, direction: ParameterDirection.Output);
		await connection.ExecuteAsync("dbo.paCotizacionGuardar", parametros, commandType: CommandType.StoredProcedure);
		return (parametros.Get<int>("@CotId"), parametros.Get<string>("@Numero"));
	}

	public async Task AnularAsync(int cotId, string motivo, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paCotizacionAnular", new { CotId = cotId, Motivo = motivo, UsuId = usuarioAccionId },
			commandType: CommandType.StoredProcedure);
	}
}
