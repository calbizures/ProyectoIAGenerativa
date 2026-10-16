using System.Data;
using Dapper;

namespace Erp.Data.Pagos;

public sealed class PagosRepository(IDbConnectionFactory connectionFactory) : IPagosRepository
{
	private async Task<IReadOnlyList<T>> ConsultarAsync<T>(string procedimiento, object? parametros = null)
	{
		using var connection = connectionFactory.CreateConnection();
		var filas = await connection.QueryAsync<T>(procedimiento, parametros, commandType: CommandType.StoredProcedure);
		return filas.ToList();
	}

	private async Task EjecutarAsync(string procedimiento, object parametros)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync(procedimiento, parametros, commandType: CommandType.StoredProcedure);
	}

	private static string? Texto(string? valor) => string.IsNullOrWhiteSpace(valor) ? null : valor.Trim();

	public async Task<ProveedorPago?> ConsultarProveedorPagoAsync(int prvId) =>
		(await ConsultarAsync<ProveedorPago>("dbo.paProveedorPagoConsultar", new { PrvId = prvId })).FirstOrDefault();

	public Task GuardarProveedorPagoAsync(ProveedorPago pago, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paProveedorPagoGuardar", new
		{
			pago.PrvId,
			pago.FormaPago,
			GefId = pago.GefId is > 0 ? pago.GefId : null,
			TipoCuenta = Texto(pago.TipoCuenta),
			NumeroCuenta = Texto(pago.NumeroCuenta),
			Titular = Texto(pago.Titular),
			UsuId = usuarioAccionId
		});

	public async Task<int?> ConsultarDiaPagoAsync(int ciaId)
	{
		using var connection = connectionFactory.CreateConnection();
		var fila = await connection.QueryFirstOrDefaultAsync<(int CiaId, byte? DiaPago)>("dbo.paCompaniaDiaPagoConsultar", new { CiaId = ciaId },
			commandType: CommandType.StoredProcedure);
		return fila.DiaPago;
	}

	// El día de pago de la compañía de la sucursal (1 lunes ... 7 domingo; null = cualquier día).
	public async Task<int?> ConsultarDiaPagoSucursalAsync(int sucId)
	{
		using var connection = connectionFactory.CreateConnection();
		return await connection.ExecuteScalarAsync<int?>(
			"SELECT CAST(comp.cia_dia_pago_proveedores AS INT) FROM dbo.gen_sucursal sucu INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id WHERE sucu.suc_id = @SucId",
			new { SucId = sucId });
	}

	public Task GuardarDiaPagoAsync(int ciaId, int? diaPago, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paCompaniaDiaPagoGuardar", new { CiaId = ciaId, DiaPago = (byte?)diaPago, UsuId = usuarioAccionId });

	public Task<IReadOnlyList<ContrasenaCuotaDisponible>> ConsultarCuotasDisponiblesAsync(int prvId) =>
		ConsultarAsync<ContrasenaCuotaDisponible>("dbo.paContrasenaCuotasDisponibles", new { PrvId = prvId });

	public Task<IReadOnlyList<ContrasenaResumen>> ConsultarContrasenasAsync(string? estado, int? prvId, DateTime? desde, DateTime? hasta,
		DateTime? pagoHasta, string? formaPago) =>
		ConsultarAsync<ContrasenaResumen>("dbo.paContrasenaConsultar", new
		{
			Estado = Texto(estado),
			PrvId = prvId,
			Desde = desde?.Date,
			Hasta = hasta?.Date,
			PagoHasta = pagoHasta?.Date,
			FormaPago = Texto(formaPago)
		});

	public async Task<Contrasena?> ConsultarContrasenaAsync(int cpaId)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paContrasenaConsultarPorId", new { CpaId = cpaId },
			commandType: CommandType.StoredProcedure);
		var contrasena = await lector.ReadFirstOrDefaultAsync<Contrasena>();
		if (contrasena is null) return null;
		contrasena.Lineas = (await lector.ReadAsync<ContrasenaLinea>()).ToList();
		return contrasena;
	}

	public async Task<(int CpaId, string Numero)> EmitirContrasenaAsync(int prvId, int sucId, DateTime? fechaPago, string? formaPago,
		string? observaciones, IReadOnlyList<ContrasenaCuota> cuotas, int? usuarioAccionId)
	{
		var tabla = new DataTable();
		tabla.Columns.Add("ppg_id", typeof(int));
		tabla.Columns.Add("monto", typeof(decimal));
		foreach (var c in cuotas) tabla.Rows.Add(c.PpgId, c.Monto);

		var parametros = new DynamicParameters();
		parametros.Add("@PrvId", prvId);
		parametros.Add("@SucId", sucId);
		parametros.Add("@FechaPago", fechaPago?.Date, DbType.Date);
		parametros.Add("@FormaPago", Texto(formaPago));
		parametros.Add("@Observaciones", Texto(observaciones));
		parametros.Add("@Cuotas", tabla.AsTableValuedParameter("dbo.cxp_pago_cuota_type"));
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@CpaId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		parametros.Add("@Numero", dbType: DbType.String, direction: ParameterDirection.Output, size: 16);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paContrasenaEmitir", parametros, commandType: CommandType.StoredProcedure);
		return (parametros.Get<int>("@CpaId"), parametros.Get<string>("@Numero"));
	}

	public Task AnularContrasenaAsync(int cpaId, string motivo, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paContrasenaAnular", new { CpaId = cpaId, Motivo = motivo, UsuId = usuarioAccionId });

	public async Task<int> PagarContrasenaChequeAsync(int cpaId, int cbcId, string? numero, int? usuarioAccionId)
	{
		var parametros = new DynamicParameters();
		parametros.Add("@CpaId", cpaId);
		parametros.Add("@CbcId", cbcId);
		parametros.Add("@Numero", Texto(numero), DbType.String, ParameterDirection.Input, 16);
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@BceId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paContrasenaPagarCheque", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@BceId");
	}

	public async Task<(int BltId, string Numero)> PagarTransferenciaAsync(int bcbId, DateTime fecha, string? referencia, IReadOnlyList<int> contrasenas,
		int? usuarioAccionId)
	{
		var tabla = new DataTable();
		tabla.Columns.Add("id", typeof(int));
		foreach (var id in contrasenas.Distinct()) tabla.Rows.Add(id);

		var parametros = new DynamicParameters();
		parametros.Add("@BcbId", bcbId);
		parametros.Add("@Fecha", fecha.Date, DbType.Date);
		parametros.Add("@Referencia", Texto(referencia));
		parametros.Add("@Contrasenas", tabla.AsTableValuedParameter("dbo.id_lista_type"));
		parametros.Add("@UsuId", usuarioAccionId);
		parametros.Add("@BltId", dbType: DbType.Int32, direction: ParameterDirection.Output);
		parametros.Add("@Numero", dbType: DbType.String, direction: ParameterDirection.Output, size: 16);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paContrasenaPagarTransferencia", parametros, commandType: CommandType.StoredProcedure);
		return (parametros.Get<int>("@BltId"), parametros.Get<string>("@Numero"));
	}

	public Task<IReadOnlyList<LoteTransferencia>> ConsultarLotesAsync(DateTime? desde, DateTime? hasta) =>
		ConsultarAsync<LoteTransferencia>("dbo.paLoteTransferenciaConsultar", new { Desde = desde?.Date, Hasta = hasta?.Date });

	public Task AnularLoteAsync(int bltId, string motivo, int? usuarioAccionId) =>
		EjecutarAsync("dbo.paLoteTransferenciaAnular", new { BltId = bltId, Motivo = motivo, UsuId = usuarioAccionId });

	public Task<ArchivoBancoDatos> ConsultarArchivoLoteAsync(int bltId) =>
		ConsultarArchivoAsync("dbo.paLoteTransferenciaArchivo", new { BltId = bltId });

	public Task<ArchivoBancoDatos> ConsultarArchivoNominaAsync(int idNominaPago) =>
		ConsultarArchivoAsync("dbo.paRrhhNominaTransferenciaArchivo", new { IdNominaPago = idNominaPago });

	private async Task<ArchivoBancoDatos> ConsultarArchivoAsync(string procedimiento, object parametros)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync(procedimiento, parametros, commandType: CommandType.StoredProcedure);
		return new ArchivoBancoDatos
		{
			Encabezado = await lector.ReadFirstOrDefaultAsync<ArchivoBancoEncabezado>(),
			Lineas = (await lector.ReadAsync<ArchivoBancoLinea>()).ToList()
		};
	}

	public async Task<IReadOnlyList<FormatoArchivo>> ConsultarFormatosAsync(int? bfaId, bool soloActivos)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paBcoFormatoArchivoConsultar", new { BfaId = bfaId, SoloActivos = soloActivos },
			commandType: CommandType.StoredProcedure);
		var formatos = (await lector.ReadAsync<FormatoArchivo>()).ToList();
		var columnas = (await lector.ReadAsync<FormatoColumna>()).ToLookup(c => c.BfaId);
		var bancos = (await lector.ReadAsync<FormatoBanco>()).ToLookup(b => b.BfaId);
		foreach (var f in formatos)
		{
			f.Columnas = columnas[f.BfaId].OrderBy(c => c.Orden).ToList();
			f.Bancos = bancos[f.BfaId].ToList();
		}
		return formatos;
	}

	public async Task<int> GuardarFormatoAsync(FormatoArchivo formato, int? usuarioAccionId)
	{
		var columnas = new DataTable();
		columnas.Columns.Add("orden", typeof(int));
		columnas.Columns.Add("campo", typeof(string));
		columnas.Columns.Add("titulo", typeof(string));
		columnas.Columns.Add("longitud", typeof(int));
		columnas.Columns.Add("relleno", typeof(string));
		columnas.Columns.Add("alineacion", typeof(string));
		columnas.Columns.Add("valor", typeof(string));
		columnas.Columns.Add("mayusculas", typeof(bool));
		var orden = 0;
		foreach (var c in formato.Columnas)
			columnas.Rows.Add(++orden, c.Campo, (object?)Texto(c.Titulo) ?? DBNull.Value, (object?)c.Longitud ?? DBNull.Value,
				string.IsNullOrEmpty(c.Relleno) ? DBNull.Value : c.Relleno, c.Alineacion, (object?)(c.Valor is { Length: > 0 } ? c.Valor : null) ?? DBNull.Value,
				c.Mayusculas);

		var bancos = new DataTable();
		bancos.Columns.Add("gef_id", typeof(int));
		bancos.Columns.Add("codigo", typeof(string));
		foreach (var b in formato.Bancos.Where(b => !string.IsNullOrWhiteSpace(b.Codigo)).GroupBy(b => b.GefId).Select(g => g.First()))
			bancos.Rows.Add(b.GefId, b.Codigo.Trim());

		var parametros = new DynamicParameters();
		parametros.Add("@BfaId", formato.BfaId == 0 ? null : formato.BfaId, DbType.Int32, ParameterDirection.InputOutput);
		parametros.Add("@Nombre", formato.Nombre);
		parametros.Add("@GefId", formato.GefId is > 0 ? formato.GefId : null);
		parametros.Add("@Uso", formato.Uso);
		parametros.Add("@Tipo", formato.Tipo);
		parametros.Add("@Separador", formato.Tipo == "D" ? formato.Separador : null);
		parametros.Add("@Titulos", formato.Titulos);
		parametros.Add("@Comillas", formato.Comillas);
		parametros.Add("@Encabezado", formato.Encabezado);
		parametros.Add("@Pie", formato.Pie);
		parametros.Add("@Extension", formato.Extension);
		parametros.Add("@Codificacion", formato.Codificacion);
		parametros.Add("@FinLinea", formato.FinLinea);
		parametros.Add("@FormatoFecha", formato.FormatoFecha);
		parametros.Add("@Decimales", formato.Decimales);
		parametros.Add("@SeparadorDecimal", formato.SeparadorDecimal);
		parametros.Add("@MontoSinPunto", formato.MontoSinPunto);
		parametros.Add("@CodigoMonetaria", formato.CodigoMonetaria);
		parametros.Add("@CodigoAhorro", formato.CodigoAhorro);
		parametros.Add("@Estado", formato.Estado);
		parametros.Add("@Columnas", columnas.AsTableValuedParameter("dbo.formato_archivo_columna_type"));
		parametros.Add("@Bancos", bancos.AsTableValuedParameter("dbo.formato_archivo_banco_type"));
		parametros.Add("@UsuId", usuarioAccionId);
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paBcoFormatoArchivoGuardar", parametros, commandType: CommandType.StoredProcedure);
		return parametros.Get<int>("@BfaId");
	}
}
