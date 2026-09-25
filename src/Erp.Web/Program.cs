using Erp.Data;
using Erp.Web.Components;
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

app.MapPost("/logout", async (HttpContext context) =>
{
	await context.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
	return Results.LocalRedirect("/login");
});

app.Run();
