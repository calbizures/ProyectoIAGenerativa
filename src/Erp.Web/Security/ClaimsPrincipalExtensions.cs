using System.Security.Claims;

namespace Erp.Web.Security;

public static class ClaimsPrincipalExtensions
{
	public static int? ObtenerUsuId(this ClaimsPrincipal usuario)
	{
		var valor = usuario.FindFirst(ClaimTypes.NameIdentifier)?.Value;
		return int.TryParse(valor, out var usuId) ? usuId : null;
	}

	public static int? ObtenerSucId(this ClaimsPrincipal usuario)
	{
		var valor = usuario.FindFirst(ClaimsSucursal.TipoClaim)?.Value;
		return int.TryParse(valor, out var sucId) ? sucId : null;
	}
}
