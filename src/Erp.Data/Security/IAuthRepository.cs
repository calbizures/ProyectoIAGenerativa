namespace Erp.Data.Security;

public sealed class UsuarioClaims
{
	public IReadOnlyList<string> Roles { get; init; } = Array.Empty<string>();
	public IReadOnlyList<string> Permisos { get; init; } = Array.Empty<string>();
}

public interface IAuthRepository
{
	Task<LoginResultado> LoginAsync(string usuario, string password);
	Task<UsuarioClaims> ObtenerClaimsAsync(int usuId);
}
