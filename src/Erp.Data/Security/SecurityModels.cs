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
	// Del empleado vinculado (nombre completo) y de su vendedor (código).
	public int? IdEmpleado { get; set; }
	public string? Empleado { get; set; }
	public string? VendedorCodigo { get; set; }
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
	public int Roles { get; set; }
	public int Usuarios { get; set; }
}

// Detalle de un permiso: quién lo tiene (roles y usuarios por esos roles).
public sealed class PermisoDetalle
{
	public Permiso Permiso { get; set; } = new();
	public DateTime? Creado { get; set; }
	public string? CreadoPor { get; set; }
	public DateTime? Modificado { get; set; }
	public IReadOnlyList<PermisoRol> Roles { get; set; } = Array.Empty<PermisoRol>();
	public IReadOnlyList<PermisoUsuario> Usuarios { get; set; } = Array.Empty<PermisoUsuario>();
}

public sealed class PermisoRol
{
	public int RolId { get; set; }
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public string Estado { get; set; } = "A";
	public int Usuarios { get; set; }
	public DateTime? Asignado { get; set; }
}

public sealed class PermisoUsuario
{
	public int UsuId { get; set; }
	public string? Codigo { get; set; }
	public string Usuario { get; set; } = "";
	public string? Email { get; set; }
	public string Estado { get; set; } = "A";
	public DateTime? UltimoIngreso { get; set; }
	public string? Empleado { get; set; }
	public string Roles { get; set; } = "";
	public bool Vigente { get; set; }
}

public sealed class Sucursal
{
	public int SucId { get; set; }
	public string SucCodigo { get; set; } = "";
	public string SucDescripcion { get; set; } = "";
}

public sealed class LoginResultado
{
	public string Estado { get; set; } = "";
	public string Mensaje { get; set; } = "";
	public int? UsuId { get; set; }

	public bool EsExitoso => Estado == "success";
}
