using Erp.Data.Rrhh;

namespace Erp.Web.Components.Pages.Rrhh;

// Códigos de posición del organigrama, como en el ejemplo de la estructura:
//   n1 Junta Directiva · n2.1 Gerencia de Operaciones · n2.2 Gerencia IT
//   n2.2.d1 Soporte técnico (departamento) · n2.2.d1.p1 (plaza)
// Una unidad se numera por nivel (n<nivel>.<posición en el nivel>); si el
// nivel tiene una sola unidad basta n<nivel>. Departamentos y plazas se
// numeran dentro de su padre.
public static class OrganigramaCodigos
{
	public static Dictionary<int, string> CodigosUnidades(IReadOnlyList<UnidadOrganizativaNodo> arbol)
	{
		var porNivel = arbol.GroupBy(n => n.Nivel).ToDictionary(g => g.Key, g => g.Count());
		var contador = new Dictionary<int, int>();
		var codigos = new Dictionary<int, string>();
		// El procedimiento ya devuelve el árbol en orden (cada nodo seguido de sus hijos).
		foreach (var n in arbol)
		{
			contador[n.Nivel] = contador.GetValueOrDefault(n.Nivel) + 1;
			codigos[n.IdUnidadOrganizativa] = porNivel[n.Nivel] == 1 ? $"n{n.Nivel}" : $"n{n.Nivel}.{contador[n.Nivel]}";
		}
		return codigos;
	}

	public sealed class NodoGrafico
	{
		public required OrganigramaNodo Nodo { get; init; }
		public string Codigo { get; set; } = "";
		public int Nivel { get; set; }
		public List<NodoGrafico> Hijos { get; } = new();
	}

	// Arma el árbol del organigrama y asigna los códigos.
	public static List<NodoGrafico> Construir(IReadOnlyList<OrganigramaNodo> nodos, bool incluirPlazas)
	{
		var visibles = nodos.Where(n => incluirPlazas || n.Tipo != "P").ToList();
		var graficos = visibles.ToDictionary(n => n.Clave, n => new NodoGrafico { Nodo = n });
		var raices = new List<NodoGrafico>();
		foreach (var g in graficos.Values)
		{
			if (g.Nodo.ClavePadre is not null && graficos.TryGetValue(g.Nodo.ClavePadre, out var padre))
				padre.Hijos.Add(g);
			else
				raices.Add(g);
		}

		// Unidades primero y por su orden; luego departamentos y plazas por nombre.
		static int Rango(string tipo) => tipo switch { "U" => 0, "D" => 1, _ => 2 };
		void Ordenar(List<NodoGrafico> lista)
		{
			lista.Sort((a, b) =>
			{
				var r = Rango(a.Nodo.Tipo).CompareTo(Rango(b.Nodo.Tipo));
				if (r != 0) return r;
				r = a.Nodo.Orden.CompareTo(b.Nodo.Orden);
				return r != 0 ? r : string.Compare(a.Nodo.Descripcion, b.Nodo.Descripcion, StringComparison.CurrentCulture);
			});
			foreach (var h in lista) Ordenar(h.Hijos);
		}
		Ordenar(raices);

		// Niveles de las unidades para numerarlas por nivel.
		var unidadesPorNivel = new List<NodoGrafico>();
		void Niveles(NodoGrafico g, int nivel)
		{
			g.Nivel = nivel;
			if (g.Nodo.Tipo == "U") unidadesPorNivel.Add(g);
			foreach (var h in g.Hijos) Niveles(h, g.Nodo.Tipo == "U" ? nivel + 1 : nivel);
		}
		foreach (var r in raices) Niveles(r, 1);

		var totalPorNivel = unidadesPorNivel.GroupBy(u => u.Nivel).ToDictionary(x => x.Key, x => x.Count());
		var contador = new Dictionary<int, int>();
		foreach (var u in unidadesPorNivel)
		{
			contador[u.Nivel] = contador.GetValueOrDefault(u.Nivel) + 1;
			u.Codigo = totalPorNivel[u.Nivel] == 1 ? $"n{u.Nivel}" : $"n{u.Nivel}.{contador[u.Nivel]}";
		}

		void Subcodigos(NodoGrafico g)
		{
			var d = 0;
			var p = 0;
			foreach (var h in g.Hijos)
			{
				if (h.Nodo.Tipo == "D") h.Codigo = $"{g.Codigo}.d{++d}".TrimStart('.');
				else if (h.Nodo.Tipo == "P") h.Codigo = $"{g.Codigo}.p{++p}".TrimStart('.');
				Subcodigos(h);
			}
		}
		var sueltos = 0;
		foreach (var r in raices)
		{
			if (r.Nodo.Tipo == "D") r.Codigo = $"d{++sueltos}";
			Subcodigos(r);
		}
		return raices;
	}
}
