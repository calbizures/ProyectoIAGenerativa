using Microsoft.AspNetCore.Authorization;

namespace Erp.Web.Security;

// Satisfecho si el usuario tiene AL MENOS UNO de los códigos (permite políticas
// tipo "Permiso:A,B" para pantallas donde basta con cualquiera de varios permisos,
// ej. una pantalla de listado a la que puede entrar quien crea O quien edita).
public sealed class PermisoRequirement(IReadOnlyList<string> codigos) : IAuthorizationRequirement
{
	public IReadOnlyList<string> Codigos { get; } = codigos;
}
