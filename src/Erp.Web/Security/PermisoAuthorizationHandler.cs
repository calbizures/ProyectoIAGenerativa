using Microsoft.AspNetCore.Authorization;

namespace Erp.Web.Security;

public sealed class PermisoAuthorizationHandler : AuthorizationHandler<PermisoRequirement>
{
	protected override Task HandleRequirementAsync(AuthorizationHandlerContext context, PermisoRequirement requirement)
	{
		if (context.User.HasClaim(ClaimsPermiso.TipoClaim, requirement.CodigoPermiso))
		{
			context.Succeed(requirement);
		}

		return Task.CompletedTask;
	}
}
