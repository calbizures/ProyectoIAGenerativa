namespace Erp.Data.Contabilidad;

// Nodo de la nomenclatura contable. El nivel lo define la longitud del código:
// 1 grupo (1 posición), 2 subgrupo (2), 3 cuenta (3), 4 subcuenta (7).
public sealed class NodoCuenta
{
	public int CtaId { get; set; }
	public string CtaCodigo { get; set; } = "";
	public string CtaNombre { get; set; } = "";
	// A = Activo, P = Pasivo, K = Capital, I = Ingreso, G = Gasto
	public string CtaTipo { get; set; } = "A";
	// D = deudora, H = acreedora
	public string CtaNaturaleza { get; set; } = "D";
	public bool CtaAceptaMovimiento { get; set; }
	public int? CtaIdPadre { get; set; }
	public int CtaNivel { get; set; }
	public string CtaEstado { get; set; } = "A";
	public int CantidadHijos { get; set; }
	public int CantidadPartidas { get; set; }
	// Pólizas automáticas y tipos de movimiento de nómina que usan la cuenta.
	public int CantidadAsignaciones { get; set; }

	public string TipoNodo => CtaNivel switch { 1 => "Grupo", 2 => "Subgrupo", 3 => "Cuenta", _ => "Subcuenta" };
}
