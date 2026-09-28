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

// Exportación a Excel de cuentas por cobrar y por pagar.
const string TipoExcel = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

async Task<string> NombreCompaniaAsync(HttpContext contexto, IGeneralRepository general) =>
	(await general.ConsultarParametrosAsync(contexto.User.ObtenerSucId())).CiaNombreComercial;

app.MapGet("/reportes/{modulo}/antiguedad.xlsx", async (string modulo, DateTime? fecha, int? id, HttpContext contexto,
	ICuentasRepository cuentas, IGeneralRepository general, IAuthorizationService autorizacion) =>
{
	var esCliente = modulo == "cxc";
	if (!esCliente && modulo != "cxp") return Results.NotFound();
	var politica = esCliente ? "Permiso:CXC_ADMIN,VENTAS_FACTURA_CREAR,VENTAS_FACTURA_ANULAR" : "Permiso:CXP_ADMIN";
	if (!(await autorizacion.AuthorizeAsync(contexto.User, politica)).Succeeded) return Results.Forbid();

	var corte = (fecha ?? DateTime.Today).Date;
	var filas = esCliente ? await cuentas.ConsultarAntiguedadClientesAsync(corte, id) : await cuentas.ConsultarAntiguedadProveedoresAsync(corte, id);
	var archivo = ReportesExcel.Antiguedad(filas, esCliente, corte, await NombreCompaniaAsync(contexto, general));
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
	var archivo = ReportesExcel.EstadoCuenta(movimientos, documentos, esCliente, tercero, desde, hasta, await NombreCompaniaAsync(contexto, general));
	return Results.File(archivo, TipoExcel, $"estado-cuenta-{(esCliente ? "cliente" : "proveedor")}-{id}.xlsx");
}).RequireAuthorization();

app.MapPost("/logout", async (HttpContext context) =>
{
	await context.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
	return Results.LocalRedirect("/login");
});

app.Run();
