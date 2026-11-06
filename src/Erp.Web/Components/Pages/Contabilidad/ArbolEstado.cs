using Erp.Data.Contabilidad;

namespace Erp.Web.Components.Pages.Contabilidad;

// Estados financieros por nodos: cada cuenta de agrupación se expande o se
// contrae; una fila se ve si todos sus ancestros están expandidos. El padre
// de una cuenta es la de mayor nivel cuyo código es prefijo del suyo.
public sealed class ArbolEstado
{
	private readonly Dictionary<int, int?> padres = new();
	private readonly HashSet<int> conHijos = new();
	private readonly HashSet<int> expandidos = new();
	private IReadOnlyList<EstadoFila> filas = Array.Empty<EstadoFila>();

	public void Cargar(IReadOnlyList<EstadoFila> nuevas, int expandirHasta)
	{
		filas = nuevas;
		padres.Clear();
		conHijos.Clear();
		foreach (var f in filas)
		{
			var padre = filas.Where(p => p.Nivel < f.Nivel && p.Tipo == f.Tipo && f.Codigo.StartsWith(p.Codigo, StringComparison.Ordinal))
				.OrderByDescending(p => p.Nivel).FirstOrDefault();
			padres[f.CtaId] = padre?.CtaId;
			if (padre is not null) conHijos.Add(padre.CtaId);
		}
		ExpandirHasta(expandirHasta);
	}

	public bool TieneHijos(EstadoFila f) => conHijos.Contains(f.CtaId);
	public bool Expandido(EstadoFila f) => expandidos.Contains(f.CtaId);

	public bool Visible(EstadoFila f)
	{
		var padre = padres.GetValueOrDefault(f.CtaId);
		while (padre is int id)
		{
			if (!expandidos.Contains(id)) return false;
			padre = padres.GetValueOrDefault(id);
		}
		return true;
	}

	public void Alternar(EstadoFila f)
	{
		if (!expandidos.Remove(f.CtaId)) expandidos.Add(f.CtaId);
	}

	// Deja abiertas las cuentas de nivel menor a @nivel (1 = solo los grupos).
	public void ExpandirHasta(int nivel)
	{
		expandidos.Clear();
		foreach (var f in filas.Where(f => f.Nivel < nivel && conHijos.Contains(f.CtaId)))
			expandidos.Add(f.CtaId);
	}
}
