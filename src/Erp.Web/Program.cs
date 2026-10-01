using Erp.Data;
using Erp.Data.Compras;
using Erp.Data.Cuentas;
using Erp.Data.General;
using Erp.Data.Ventas;
using Erp.Web.Components;
using Erp.Web.Fel;
using Erp.Web.Reportes;
using Erp.Web.Security;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddRazorComponents()
	.AddInteractiveServerComponents();

builder.Services.AddCascadingAuthenticationState();

var connectionString = builder.Configuration.GetConnectionString("ErpDb")
	?? throw new InvalidOperationException("Falta la cadena de conexión 'ErpDb' en la configuración (appsettings.json).");
builder.Services.AddErpData(connectionString);

// Factura electrónica: certificadores disponibles (la compañía elige uno en su
// configuración FEL), servicio de envío y reintento automático.
builder.Services.AddHttpClient("Fel");
builder.Services.AddSingleton<IFelCertificador, SimuladorCertificador>();
builder.Services.AddSingleton<IFelCertificador, InfileCertificador>();
builder.Services.AddScoped<FelService>();
builder.Services.AddScoped<Erp.Web.Components.Shared.AvisosServicio>();
builder.Services.AddScoped<Erp.Web.Components.Shared.EdicionServicio>();
builder.Services.AddScoped<FelConsultaNitServicio>();
builder.Services.AddHostedService<FelReintentoServicio>();

builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
	.AddCookie(options =>
	{
		options.LoginPath = "/login";
		options.AccessDeniedPath = "/acceso-denegado";
		options.ExpireTimeSpan = TimeSpan.FromHours(8);
		options.SlidingExpiration = true;
		options.EventsType = typeof(RefrescoPermisosCookie);
	});
builder.Services.AddScoped<RefrescoPermisosCookie>();

// Proveedor dinámico: cualquier [Authorize(Policy = "Permiso:<CODIGO>")] se resuelve
// contra el catálogo sec_permiso sin tener que registrar cada política a mano.
builder.Services.AddSingleton<IAuthorizationPolicyProvider, PermisoAuthorizationPolicyProvider>();
builder.Services.AddSingleton<IAuthorizationHandler, PermisoAuthorizationHandler>();
builder.Services.AddAuthorization(options =>
{
	// Por defecto toda página requiere sesión iniciada; las páginas públicas
	// (como /login) se marcan explícitamente con [AllowAnonymous].
	options.FallbackPolicy = new AuthorizationPolicyBuilder()
		.RequireAuthenticatedUser()
		.Build();
});

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
	app.UseExceptionHandler("/Error", createScopeForErrors: true);
	app.UseHsts();
}

app.UseHttpsRedirection();

app.UseStaticFiles();

// La FallbackPolicy exige sesión en todo endpoint sin metadata de
// autorización, y el framework mapea _framework/blazor.web.js sin ella: la
// página de login (anónima) recibía el HTML del login en lugar del script.
// Es el script público de Blazor, así que se marca como anónimo aquí.
app.Use((contexto, siguiente) =>
{
	if (contexto.GetEndpoint() is RouteEndpoint endpoint
		&& string.Equals(endpoint.RoutePattern.RawText, "/_framework/blazor.web.js", StringComparison.OrdinalIgnoreCase)
		&& endpoint.Metadata.GetMetadata<IAllowAnonymous>() is null)
	{
		contexto.SetEndpoint(new Endpoint(
			endpoint.RequestDelegate,
			new EndpointMetadataCollection(endpoint.Metadata.Append(new AllowAnonymousAttribute())),
			endpoint.DisplayName));
	}
	return siguiente(contexto);
});

app.UseAuthentication();
app.UseAuthorization();

app.UseAntiforgery();

app.MapRazorComponents<App>()
	.AddInteractiveServerRenderMode();

// XML de factura electrónica (enviado, certificado o de anulación).
app.MapGet("/fel/xml/{encId:int}/{tipo}", async (int encId, string tipo, HttpContext contexto,
	Erp.Data.Fel.IFelRepository fel, IAuthorizationService autorizacion) =>
{
	if (!(await autorizacion.AuthorizeAsync(contexto.User, "Permiso:FEL_ADMIN")).Succeeded) return Results.Forbid();
	var (detalle, _) = await fel.ConsultarDetalleAsync(encId);
	var xml = tipo switch { "enviado" => detalle?.XmlEnviado, "certificado" => detalle?.XmlCertificado, "anulacion" => detalle?.XmlAnulacion, _ => null };
	if (string.IsNullOrEmpty(xml)) return Results.NotFound();
	return Results.File(System.Text.Encoding.UTF8.GetBytes(xml), "application/xml", $"dte-{encId}-{tipo}.xml");
}).RequireAuthorization();

// Logotipo de la compañía. Es público porque también se muestra en la
// pantalla de inicio de sesión; con la versión (v) en la dirección se guarda
// en caché, porque al cambiar el logotipo cambia la dirección.
app.MapGet("/compania/logo", async (int? cia, HttpContext contexto, IGeneralRepository general) =>
{
	var logo = await general.ConsultarLogoAsync(cia, contexto.User.ObtenerSucId(), soloVersion: false);
	if (logo?.Logo is null || logo.Tipo is null) return Results.NotFound();
	contexto.Response.Headers.CacheControl = contexto.Request.Query.ContainsKey("v") ? "public, max-age=31536000, immutable" : "no-cache";
	contexto.Response.Headers.XContentTypeOptions = "nosniff";
	return Results.File(logo.Logo, logo.Tipo);
}).AllowAnonymous();

// Exportación a Excel de cuentas por cobrar y por pagar.
const string TipoExcel = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

// Compañía de la sucursal del usuario, con su logotipo, para el encabezado.
async Task<CompaniaReporte> CompaniaReporteAsync(HttpContext contexto, IGeneralRepository general)
{
	var parametros = await general.ConsultarParametrosAsync(contexto.User.ObtenerSucId());
	var logo = parametros.CiaId == 0 ? null : await general.ConsultarLogoAsync(parametros.CiaId, null, soloVersion: false);
	return new CompaniaReporte(parametros.CiaNombreComercial, logo?.Logo);
}

app.MapGet("/reportes/{modulo}/antiguedad.xlsx", async (string modulo, DateTime? fecha, int? id, HttpContext contexto,
	ICuentasRepository cuentas, IGeneralRepository general, IAuthorizationService autorizacion) =>
{
	var esCliente = modulo == "cxc";
	if (!esCliente && modulo != "cxp") return Results.NotFound();
	var politica = esCliente ? "Permiso:CXC_ADMIN,VENTAS_FACTURA_CREAR,VENTAS_FACTURA_ANULAR" : "Permiso:CXP_ADMIN";
	if (!(await autorizacion.AuthorizeAsync(contexto.User, politica)).Succeeded) return Results.Forbid();

	var corte = (fecha ?? DateTime.Today).Date;
	var filas = esCliente ? await cuentas.ConsultarAntiguedadClientesAsync(corte, id) : await cuentas.ConsultarAntiguedadProveedoresAsync(corte, id);
	var archivo = ReportesExcel.Antiguedad(filas, esCliente, corte, await CompaniaReporteAsync(contexto, general));
	return Results.File(archivo, TipoExcel, $"antiguedad-{(esCliente ? "clientes" : "proveedores")}-{corte:yyyyMMdd}.xlsx");
}).RequireAuthorization();

app.MapGet("/reportes/{modulo}/estado-cuenta.xlsx", async (string modulo, int id, DateTime? desde, DateTime? hasta, HttpContext contexto,
	ICuentasRepository cuentas, IGeneralRepository general, IClienteRepository clientes, IProveedorRepository proveedores,
	IAuthorizationService autorizacion) =>
{
	var esCliente = modulo == "cxc";
	if (!esCliente && modulo != "cxp") return Results.NotFound();
	if (!(await autorizacion.AuthorizeAsync(contexto.User, esCliente ? "Permiso:CXC_ADMIN" : "Permiso:CXP_ADMIN")).Succeeded) return Results.Forbid();

	string tercero;
	IReadOnlyList<MovimientoEstadoCuenta> movimientos;
	IReadOnlyList<DocumentoSaldo> documentos;
	if (esCliente)
	{
		var cliente = await clientes.ConsultarPorIdAsync(id);
		if (cliente is null) return Results.NotFound();
		tercero = $"{cliente.CliCodigo} {cliente.NombreCompleto}";
		movimientos = await cuentas.ConsultarEstadoCuentaClienteAsync(id, desde, hasta);
		documentos = await cuentas.ConsultarDocumentosCxcAsync(id, soloPendientes: true);
	}
	else
	{
		var proveedor = await proveedores.ConsultarPorIdAsync(id);
		if (proveedor is null) return Results.NotFound();
		tercero = $"{proveedor.PrvCodigo} {proveedor.PrvNombreComercial}";
		movimientos = await cuentas.ConsultarEstadoCuentaProveedorAsync(id, desde, hasta);
		documentos = await cuentas.ConsultarDocumentosCxpAsync(id, soloPendientes: true);
	}
	var archivo = ReportesExcel.EstadoCuenta(movimientos, documentos, esCliente, tercero, desde, hasta, await CompaniaReporteAsync(contexto, general));
	return Results.File(archivo, TipoExcel, $"estado-cuenta-{(esCliente ? "cliente" : "proveedor")}-{id}.xlsx");
}).RequireAuthorization();

// Listado de un lote de transferencias de nómina, por banco destino.
app.MapGet("/reportes/nomina/transferencias/{idNominaPago:int}.xlsx", async (int idNominaPago, HttpContext contexto,
	Erp.Data.Rrhh.IRrhhRepository rrhh, IGeneralRepository general, IAuthorizationService autorizacion) =>
{
	if (!(await autorizacion.AuthorizeAsync(contexto.User, "Permiso:BANCOS_ADMIN")).Succeeded) return Results.Forbid();
	var filas = await rrhh.ConsultarListadoTransferenciasAsync(idNominaPago);
	if (filas.Count == 0) return Results.NotFound();
	var archivo = ReportesExcel.TransferenciasNomina(filas, await CompaniaReporteAsync(contexto, general));
	return Results.File(archivo, TipoExcel, $"transferencias-nomina-{idNominaPago}.xlsx");
}).RequireAuthorization();

// Archivo de transferencias para el banco, con el formato elegido:
// tipo "lote" (pago a proveedores) o "nomina" (pago de una nómina).
app.MapGet("/bancos/archivo/{tipo}/{id:int}", async (string tipo, int id, int formato, HttpContext contexto,
	Erp.Data.Pagos.IPagosRepository pagos, IAuthorizationService autorizacion) =>
{
	if (tipo is not ("lote" or "nomina")) return Results.NotFound();
	var politica = tipo == "lote" ? "Permiso:CXP_PAGO_PROGRAMADO" : "Permiso:BANCOS_ADMIN,RRHH_ADMIN";
	if (!(await autorizacion.AuthorizeAsync(contexto.User, politica)).Succeeded) return Results.Forbid();
	var formatoArchivo = (await pagos.ConsultarFormatosAsync(formato, soloActivos: false)).FirstOrDefault();
	if (formatoArchivo is null) return Results.NotFound();
	var datos = tipo == "lote" ? await pagos.ConsultarArchivoLoteAsync(id) : await pagos.ConsultarArchivoNominaAsync(id);
	var resultado = ArchivoBanco.Generar(formatoArchivo, datos);
	if (!resultado.Valido) return Results.BadRequest("El archivo no se puede generar: " + string.Join(" ", resultado.Errores));
	var tipoContenido = formatoArchivo.Extension.Equals("csv", StringComparison.OrdinalIgnoreCase) ? "text/csv" : "text/plain";
	return Results.File(resultado.Contenido!, $"{tipoContenido}; charset={(formatoArchivo.Codificacion == "UTF-8" ? "utf-8" : "iso-8859-1")}", resultado.NombreArchivo);
}).RequireAuthorization();

// Rotación del inventario y punto de reorden (bodega, o todas las de la sucursal).
app.MapGet("/reportes/inventario/rotacion.xlsx", async (int? bodega, int? sucursal, int? dias, DateTime? hasta, HttpContext contexto,
	Erp.Data.Inventario.IReordenRepository reorden, Erp.Data.Inventario.IBodegaRepository bodegas, IGeneralRepository general,
	IAuthorizationService autorizacion) =>
{
	if (!(await autorizacion.AuthorizeAsync(contexto.User, "Permiso:INVENTARIO_REORDEN")).Succeeded) return Results.Forbid();
	var filas = await reorden.ConsultarRotacionAsync(bodega, bodega is null ? sucursal : null, dias, hasta);
	var ambito = bodega is int b ? (await bodegas.ConsultarAsync(null, null)).FirstOrDefault(x => x.BodId == b)?.BodDescripcion ?? $"Bodega {b}"
		: "Todas las bodegas";
	var archivo = ReportesExcel.Rotacion(filas, ambito, await CompaniaReporteAsync(contexto, general));
	return Results.File(archivo, TipoExcel, $"rotacion-inventario-{(hasta ?? DateTime.Today):yyyyMMdd}.xlsx");
}).RequireAuthorization();

// Libro de salarios y planilla mensual del IGSS de una compañía.
app.MapGet("/reportes/rrhh/libro-salarios.xlsx", async (int cia, int anio, int? empleado, HttpContext contexto,
	Erp.Data.Rrhh.IRrhhRepository rrhh, IGeneralRepository general, IAuthorizationService autorizacion) =>
{
	if (!(await autorizacion.AuthorizeAsync(contexto.User, "Permiso:RRHH_ADMIN")).Succeeded) return Results.Forbid();
	var libro = await rrhh.ConsultarLibroSalariosAsync(cia, anio, empleado);
	if (libro.Patrono is null) return Results.NotFound();
	var logo = await general.ConsultarLogoAsync(cia, null, soloVersion: false);
	var archivo = ReportesExcel.LibroSalarios(libro, new CompaniaReporte(libro.Patrono.NombreComercial, logo?.Logo));
	return Results.File(archivo, TipoExcel, $"libro-salarios-{anio}{(empleado is int e ? $"-{e}" : "")}.xlsx");
}).RequireAuthorization();

app.MapGet("/reportes/rrhh/planilla-igss.xlsx", async (int cia, int anio, int mes, HttpContext contexto,
	Erp.Data.Rrhh.IRrhhRepository rrhh, IGeneralRepository general, IAuthorizationService autorizacion) =>
{
	if (!(await autorizacion.AuthorizeAsync(contexto.User, "Permiso:RRHH_ADMIN")).Succeeded) return Results.Forbid();
	var planilla = await rrhh.ConsultarPlanillaIgssAsync(cia, anio, mes);
	if (planilla.Resumen is null) return Results.NotFound();
	var logo = await general.ConsultarLogoAsync(cia, null, soloVersion: false);
	var archivo = ReportesExcel.PlanillaIgss(planilla, new CompaniaReporte(planilla.Resumen.NombreComercial, logo?.Logo));
	return Results.File(archivo, TipoExcel, $"planilla-igss-{anio}-{mes:00}.xlsx");
}).RequireAuthorization();

// Archivo de la planilla del IGSS para "sistema propio" (formato 2.2.0).
app.MapGet("/reportes/rrhh/planilla-igss.txt", async (int cia, int anio, int mes, bool? pruebas, bool? complementaria, string? nota,
	HttpContext contexto, Erp.Data.Rrhh.IIgssRepository igss, IAuthorizationService autorizacion) =>
{
	if (!(await autorizacion.AuthorizeAsync(contexto.User, "Permiso:RRHH_ADMIN")).Succeeded) return Results.Forbid();
	var datos = await igss.ConsultarArchivoAsync(cia, anio, mes);
	if (datos.Patrono is null) return Results.NotFound();
	if (datos.TieneErrores)
		return Results.BadRequest("El archivo no se puede generar: " + string.Join(" ", datos.Observaciones.Where(o => o.Nivel == "E").Select(o => o.Mensaje)));
	var ahora = DateTime.Now;
	var texto = ArchivoPlanillaIgss.Generar(datos, new ArchivoPlanillaIgss.Opciones(ahora, pruebas == true, complementaria == true, nota));
	return Results.File(ArchivoPlanillaIgss.Codificacion.GetBytes(texto), "text/plain; charset=iso-8859-1", ArchivoPlanillaIgss.NombreArchivo(datos, ahora));
}).RequireAuthorization();

app.MapGet("/reportes/contabilidad/centros-costo.xlsx", async (DateTime desde, DateTime hasta, int? departamento, HttpContext contexto,
	Erp.Data.Contabilidad.ICentroCostoRepository centros, IGeneralRepository general, IAuthorizationService autorizacion) =>
{
	if (!(await autorizacion.AuthorizeAsync(contexto.User, "Permiso:CONTABILIDAD_CENTRO_COSTO")).Succeeded) return Results.Forbid();
	var filas = await centros.ConsultarAsync(desde, hasta, departamento);
	var archivo = ReportesExcel.CentrosCosto(filas, desde, hasta, await CompaniaReporteAsync(contexto, general));
	return Results.File(archivo, TipoExcel, $"centros-costo-{desde:yyyyMMdd}-{hasta:yyyyMMdd}.xlsx");
}).RequireAuthorization();

// Plantillas y hojas de trabajo de las cargas desde Excel.
app.MapGet("/reportes/inventario/plantilla-inventario-inicial.xlsx", async (HttpContext contexto, Erp.Data.Inventario.IBodegaRepository bodegas,
	Erp.Data.Inventario.IProductoRepository productos, IGeneralRepository general, IAuthorizationService autorizacion) =>
{
	if (!(await autorizacion.AuthorizeAsync(contexto.User, "Permiso:INVENTARIO_CARGA_INICIAL")).Succeeded) return Results.Forbid();
	var archivo = ReportesExcel.PlantillaInventarioInicial(await bodegas.ConsultarDetalleAsync(null, soloActivas: true), await productos.ConsultarTiposAsync(),
		await bodegas.ConsultarUnidadesAsync(soloActivas: true), await CompaniaReporteAsync(contexto, general));
	return Results.File(archivo, TipoExcel, "plantilla-inventario-inicial.xlsx");
}).RequireAuthorization();

app.MapGet("/reportes/inventario/toma/{tfiId:int}.xlsx", async (int tfiId, HttpContext contexto, Erp.Data.Inventario.IInventarioFisicoRepository tomas,
	IGeneralRepository general, IAuthorizationService autorizacion) =>
{
	if (!(await autorizacion.AuthorizeAsync(contexto.User, "Permiso:INVENTARIO_FISICO")).Succeeded) return Results.Forbid();
	var toma = (await tomas.ConsultarAsync(null, null, null)).FirstOrDefault(t => t.TfiId == tfiId);
	if (toma is null) return Results.NotFound();
	var archivo = ReportesExcel.HojaConteo(toma, await tomas.ConsultarLineasAsync(tfiId), await CompaniaReporteAsync(contexto, general));
	return Results.File(archivo, TipoExcel, $"inventario-fisico-{tfiId}.xlsx");
}).RequireAuthorization();

app.MapGet("/reportes/contabilidad/saldos-iniciales.xlsx", async (HttpContext contexto, Erp.Data.Cargas.ICargasRepository cargas,
	IGeneralRepository general, IAuthorizationService autorizacion) =>
{
	if (!(await autorizacion.AuthorizeAsync(contexto.User, "Permiso:CONTABILIDAD_SALDOS_INICIALES")).Succeeded) return Results.Forbid();
	var archivo = ReportesExcel.SaldosIniciales(await cargas.ConsultarPlantillaSaldosAsync(), await CompaniaReporteAsync(contexto, general));
	return Results.File(archivo, TipoExcel, "saldos-iniciales.xlsx");
}).RequireAuthorization();

app.MapGet("/reportes/rrhh/plantilla-empleados.xlsx", async (HttpContext contexto, Erp.Data.Rrhh.IRrhhRepository rrhh,
	IGeneralRepository general, IAuthorizationService autorizacion) =>
{
	if (!(await autorizacion.AuthorizeAsync(contexto.User, "Permiso:RRHH_ADMIN")).Succeeded) return Results.Forbid();
	var tipoBanco = (await general.ConsultarTiposEntidadAsync()).FirstOrDefault(t => t.GeftDescripcion == "Banco");
	var bancos = tipoBanco is null ? Array.Empty<Erp.Data.Caja.EntidadFinanciera>() : await general.ConsultarEntidadesAsync(tipoBanco.GeftId, soloActivas: true);
	var archivo = ReportesExcel.PlantillaEmpleados(await rrhh.ConsultarPlazasAsync(soloActivos: true), bancos,
		await rrhh.ConsultarCatalogoAsync("TipoDocumentoIdentificacion", soloActivos: true), await CompaniaReporteAsync(contexto, general));
	return Results.File(archivo, TipoExcel, "plantilla-empleados.xlsx");
}).RequireAuthorization();

app.MapPost("/logout", async (HttpContext context) =>
{
	await context.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
	return Results.LocalRedirect("/login");
});

app.Run();
