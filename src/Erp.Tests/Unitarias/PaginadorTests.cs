using Erp.Web.Components.Shared;

namespace Erp.Tests.Unitarias;

public class PaginadorTests
{
	private static readonly IReadOnlyList<int> Cien = Enumerable.Range(1, 100).ToList();

	[Fact]
	public void Primera_y_ultima_pagina()
	{
		Assert.Equal(Enumerable.Range(1, 25), Paginador.Recortar(Cien, 1));
		Assert.Equal(Enumerable.Range(91, 10), Paginador.Recortar(Cien, 10, 10));
	}

	[Fact]
	public void Una_pagina_fuera_de_rango_muestra_la_ultima()
	{
		// La lista se achicó (por ejemplo, otra consulta) y la página quedó atrás.
		Assert.Equal(Enumerable.Range(76, 25), Paginador.Recortar(Cien, 9));
		Assert.Equal(Enumerable.Range(1, 25), Paginador.Recortar(Cien, 0));
	}

	[Fact]
	public void Lista_vacia()
	{
		Assert.Empty(Paginador.Recortar(Array.Empty<int>(), 1));
	}
}
