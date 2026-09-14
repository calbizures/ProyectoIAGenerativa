using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Options;

namespace Erp.Web.Security;

// Convierte cualquier política con nombre "Permiso:<CODIGO>" (ej. "Permiso:USU_CREAR",
// o "Permiso:A,B" para exigir cualquiera de varios códigos) en un requisito
// PermisoRequirement, sin tener que registrar cada permiso a mano con AddPolicy().
// Cualquier otra política cae al proveedor por defecto.
public sealed class PermisoAuthorizationPolicyProvider(IOptions<AuthorizationOptions> opciones) : IAuthorizationPolicyProvider
{
	public const string Prefijo = "Permiso:";

	private readonly DefaultAuthorizationPolicyProvider _proveedorPorDefecto = new(opciones);

	public Task<AuthorizationPolicy> GetDefaultPolicyAsync() => _proveedorPorDefecto.GetDefaultPolicyAsync();

	public Task<AuthorizationPolicy?> GetFallbackPolicyAsync() => _proveedorPorDefecto.GetFallbackPolicyAsync();

	public Task<AuthorizationPolicy?> GetPolicyAsync(string policyName)
	{
		if (policyName.StartsWith(Prefijo, StringComparison.OrdinalIgnoreCase))
		{
			var codigos = policyName[Prefijo.Length..]
				.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
			var politica = new AuthorizationPolicyBuilder()
				.RequireAuthenticatedUser()
				.AddRequirements(new PermisoRequirement(codigos))
				.Build();
			return Task.FromResult<AuthorizationPolicy?>(politica);
		}

		return _proveedorPorDefecto.GetPolicyAsync(policyName);
	}
}
