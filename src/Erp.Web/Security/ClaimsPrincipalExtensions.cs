using System.Security.Claims;

namespace Erp.Web.Security;

public static class ClaimsPrincipalExtensions
{
	public static int? ObtenerUsuId(this ClaimsPrincipal usuario)
	{
		var valor = usuario.FindFirst(ClaimTypes.NameIdentifier)?.Value;
		return int.TryParse(valor, out var usuId) ? usuId : null;
	}
}
