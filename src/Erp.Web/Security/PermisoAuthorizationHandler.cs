using Microsoft.AspNetCore.Authorization;

namespace Erp.Web.Security;

public sealed class PermisoAuthorizationHandler : AuthorizationHandler<PermisoRequirement>
{
	protected override Task HandleRequirementAsync(AuthorizationHandlerContext context, PermisoRequirement requirement)
	{
		if (requirement.Codigos.Any(codigo => context.User.HasClaim(ClaimsPermiso.TipoClaim, codigo)))
		{
			context.Succeed(requirement);
		}

		return Task.CompletedTask;
	}
}
