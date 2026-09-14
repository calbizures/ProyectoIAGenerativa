using Microsoft.AspNetCore.Authorization;

namespace Erp.Web.Security;

public sealed class PermisoRequirement(string codigoPermiso) : IAuthorizationRequirement
{
	public string CodigoPermiso { get; } = codigoPermiso;
}
