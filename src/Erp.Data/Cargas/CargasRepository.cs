using System.Data;
using Dapper;

namespace Erp.Data.Cargas;

public sealed class CargasRepository(IDbConnectionFactory connectionFactory) : ICargasRepository
{
	// Los procedimientos de carga devuelven dos conjuntos: los mensajes y el resumen.
	private async Task<ResultadoCarga<T>> ProcesarAsync<T>(string procedimiento, DynamicParameters parametros)
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync(procedimiento, parametros, commandType: CommandType.StoredProcedure, commandTimeout: 300);
		var mensajes = (await lector.ReadAsync<MensajeCarga>()).ToList();
		var resumen = await lector.ReadSingleOrDefaultAsync<T>();
		return new ResultadoCarga<T> { Mensajes = mensajes, Resumen = resumen };
	}

	private static DataTable Tabla(params (string Nombre, Type Tipo)[] columnas)
	{
		var tabla = new DataTable();
		foreach (var (nombre, tipo) in columnas) tabla.Columns.Add(nombre, tipo);
		return tabla;
	}

	private static object Valor(object? valor) => valor ?? DBNull.Value;

	private static object Texto(string? valor) => string.IsNullOrWhiteSpace(valor) ? DBNull.Value : valor.Trim();

	public Task<ResultadoCarga<ResumenInventarioInicial>> ProcesarInventarioInicialAsync(DateTime fecha, IReadOnlyList<FilaInventarioInicial> filas, bool soloValidar, int? usuarioAccionId)
	{
		var tabla = Tabla(("Fila", typeof(int)), ("Sucursal", typeof(string)), ("Bodega", typeof(string)), ("Producto", typeof(string)),
			("Descripcion", typeof(string)), ("Tipo", typeof(string)), ("Unidad", typeof(string)), ("Cantidad", typeof(decimal)),
			("CostoTotal", typeof(decimal)), ("PrecioVenta", typeof(decimal)));
		foreach (var f in filas)
			tabla.Rows.Add(f.Fila, Texto(f.Sucursal), Texto(f.Bodega), Texto(f.Producto), Texto(f.Descripcion), Texto(f.Tipo), Texto(f.Unidad),
				Valor(f.Cantidad), Valor(f.CostoTotal), Valor(f.PrecioVenta));
		var parametros = new DynamicParameters();
		parametros.Add("@Fecha", fecha.Date);
		parametros.Add("@Filas", tabla.AsTableValuedParameter("dbo.inv_carga_inicial_type"));
		parametros.Add("@SoloValidar", soloValidar);
		parametros.Add("@UsuId", usuarioAccionId);
		return ProcesarAsync<ResumenInventarioInicial>("dbo.paInvCargaInicialProcesar", parametros);
	}

	public async Task<IReadOnlyList<CargaInventarioInicial>> ConsultarInventarioInicialAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		return (await connection.QueryAsync<CargaInventarioInicial>("dbo.paInvCargaInicialConsultar", commandType: CommandType.StoredProcedure)).ToList();
	}

	public async Task AnularInventarioInicialAsync(int encId, int? usuarioAccionId)
	{
		using var connection = connectionFactory.CreateConnection();
		await connection.ExecuteAsync("dbo.paInvCargaInicialAnular", new { EncId = encId, UsuId = usuarioAccionId }, commandType: CommandType.StoredProcedure);
	}

	public async Task<IReadOnlyList<CuentaSaldoInicial>> ConsultarPlantillaSaldosAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		return (await connection.QueryAsync<CuentaSaldoInicial>("dbo.paContabilidadSaldosInicialesPlantilla", commandType: CommandType.StoredProcedure)).ToList();
	}

	public Task<ResultadoCarga<ResumenSaldosIniciales>> ProcesarSaldosInicialesAsync(DateTime fecha, IReadOnlyList<FilaSaldoInicial> filas, bool soloValidar, bool reemplazar, int? usuarioAccionId)
	{
		var tabla = Tabla(("Fila", typeof(int)), ("Codigo", typeof(string)), ("Debe", typeof(decimal)), ("Haber", typeof(decimal)));
		foreach (var f in filas) tabla.Rows.Add(f.Fila, Texto(f.Codigo), Valor(f.Debe), Valor(f.Haber));
		var parametros = new DynamicParameters();
		parametros.Add("@Fecha", fecha.Date);
		parametros.Add("@Filas", tabla.AsTableValuedParameter("dbo.cont_saldo_inicial_type"));
		parametros.Add("@SoloValidar", soloValidar);
		parametros.Add("@Reemplazar", reemplazar);
		parametros.Add("@UsuId", usuarioAccionId);
		return ProcesarAsync<ResumenSaldosIniciales>("dbo.paContabilidadSaldosInicialesProcesar", parametros);
	}

	public async Task<(PartidaApertura? Partida, IReadOnlyList<LineaApertura> Lineas)> ConsultarAperturaAsync()
	{
		using var connection = connectionFactory.CreateConnection();
		using var lector = await connection.QueryMultipleAsync("dbo.paContabilidadAperturaConsultar", commandType: CommandType.StoredProcedure);
		var partida = await lector.ReadSingleOrDefaultAsync<PartidaApertura>();
		var lineas = (await lector.ReadAsync<LineaApertura>()).ToList();
		return (partida, lineas);
	}

	public Task<ResultadoCarga<ResumenEmpleados>> ProcesarEmpleadosAsync(int ciaId, IReadOnlyList<FilaEmpleado> filas, bool soloValidar, int? usuarioAccionId)
	{
		var tabla = Tabla(("Fila", typeof(int)), ("Codigo", typeof(string)), ("PrimerNombre", typeof(string)), ("SegundoNombre", typeof(string)),
			("PrimerApellido", typeof(string)), ("SegundoApellido", typeof(string)), ("Genero", typeof(string)), ("FechaNacimiento", typeof(DateTime)),
			("FechaIngreso", typeof(DateTime)), ("TipoDocumento", typeof(string)), ("NumeroDocumento", typeof(string)), ("AfiliacionIGSS", typeof(string)),
			("Nit", typeof(string)), ("Email", typeof(string)), ("Direccion", typeof(string)), ("Plaza", typeof(string)), ("SalarioBase", typeof(decimal)),
			("TipoNomina", typeof(string)), ("FormaPago", typeof(string)), ("Banco", typeof(string)), ("TipoCuenta", typeof(string)),
			("NumeroCuenta", typeof(string)));
		foreach (var f in filas)
			tabla.Rows.Add(f.Fila, Texto(f.Codigo), Texto(f.PrimerNombre), Texto(f.SegundoNombre), Texto(f.PrimerApellido), Texto(f.SegundoApellido),
				Texto(f.Genero), Valor(f.FechaNacimiento?.Date), Valor(f.FechaIngreso?.Date), Texto(f.TipoDocumento), Texto(f.NumeroDocumento),
				Texto(f.AfiliacionIGSS), Texto(f.Nit), Texto(f.Email), Texto(f.Direccion), Texto(f.Plaza), Valor(f.SalarioBase), Texto(f.TipoNomina),
				Texto(f.FormaPago), Texto(f.Banco), Texto(f.TipoCuenta), Texto(f.NumeroCuenta));
		var parametros = new DynamicParameters();
		parametros.Add("@CiaId", ciaId);
		parametros.Add("@Filas", tabla.AsTableValuedParameter("dbo.rrhh_empleado_carga_type"));
		parametros.Add("@SoloValidar", soloValidar);
		parametros.Add("@UsuId", usuarioAccionId);
		return ProcesarAsync<ResumenEmpleados>("dbo.paRrhhEmpleadoCargaProcesar", parametros);
	}
}
