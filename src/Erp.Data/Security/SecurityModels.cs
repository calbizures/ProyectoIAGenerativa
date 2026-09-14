namespace Erp.Data.Security;

public sealed class Usuario
{
	public int UsuId { get; set; }
	public string UsuCodigo { get; set; } = "";
	public string UsuUsuario { get; set; } = "";
	public string? UsuEmail { get; set; }
	public DateTime UsuFechaIngreso { get; set; }
	public bool UsuBloqueado { get; set; }
	public DateTime? UsuUltimoLogin { get; set; }
	public string UsuEstado { get; set; } = "A";
}

public sealed class UsuarioRol
{
	public int RolId { get; set; }
	public string RolCodigo { get; set; } = "";
	public string RolNombre { get; set; } = "";
}

public sealed class Rol
{
	public int RolId { get; set; }
	public string RolCodigo { get; set; } = "";
	public string RolNombre { get; set; } = "";
	public string RolEstado { get; set; } = "A";
}

public sealed class Permiso
{
	public int PerId { get; set; }
	public string PerModulo { get; set; } = "";
	public string PerCodigo { get; set; } = "";
	public string? PerDescripcion { get; set; }
	public string PerEstado { get; set; } = "A";
}

public sealed class LoginResultado
{
	public string Estado { get; set; } = "";
	public string Mensaje { get; set; } = "";
	public int? UsuId { get; set; }

	public bool EsExitoso => Estado == "success";
}
