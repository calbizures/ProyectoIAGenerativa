using System.Globalization;
using System.Security.Claims;
using Erp.Data.Security;
using Microsoft.AspNetCore.Authentication.Cookies;

namespace Erp.Web.Security;

// Los roles y permisos se copian a la cookie al iniciar sesión. Sin esto, un
// permiso asignado después (desde Seguridad > Roles o por un script, como
// GENERAL_CONFIG_ADMIN en 26_parametros_general_caja.sql) no se veía hasta
// cerrar sesión y volver a entrar. Aquí se vuelven a leer de la base de datos
// como máximo una vez por minuto y, si cambiaron, se reemplazan en la cookie.
public sealed class RefrescoPermisosCookie : CookieAuthenticationEvents
{
	private const string ClaimVerificado = "permisos_verificados";
	private static readonly TimeSpan Intervalo = TimeSpan.FromMinutes(1);

	public override async Task ValidatePrincipal(CookieValidatePrincipalContext context)
	{
		var principal = context.Principal;
		var usuId = principal?.ObtenerUsuId();
		if (principal?.Identity is not ClaimsIdentity identidadActual || usuId is null)
		{
			return;
		}

		var verificado = principal.FindFirst(ClaimVerificado)?.Value;
		if (long.TryParse(verificado, NumberStyles.Integer, CultureInfo.InvariantCulture, out var ticks)
			&& DateTime.UtcNow - new DateTime(ticks, DateTimeKind.Utc) < Intervalo)
		{
			return;
		}

		UsuarioClaims claims;
		try
		{
			var repositorio = context.HttpContext.RequestServices.GetRequiredService<IAuthRepository>();
			claims = await repositorio.ObtenerClaimsAsync(usuId.Value);
		}
		catch
		{
			// Si la base de datos no responde se conservan los permisos actuales.
			return;
		}

		// Se conservan identidad, nombre y sucursal; roles y permisos se toman frescos.
		var identidad = new ClaimsIdentity(identidadActual.AuthenticationType);
		identidad.AddClaims(identidadActual.Claims.Where(c =>
			c.Type != ClaimTypes.Role && c.Type != ClaimsPermiso.TipoClaim && c.Type != ClaimVerificado));
		identidad.AddClaims(claims.Roles.Select(rol => new Claim(ClaimTypes.Role, rol)));
		identidad.AddClaims(claims.Permisos.Select(permiso => new Claim(ClaimsPermiso.TipoClaim, permiso)));
		identidad.AddClaim(new Claim(ClaimVerificado, DateTime.UtcNow.Ticks.ToString(CultureInfo.InvariantCulture)));

		context.ReplacePrincipal(new ClaimsPrincipal(identidad));
		context.ShouldRenew = true;
	}
}
