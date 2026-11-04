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

	[Fact]
	public void El_tope_recorta_y_avisa_solo_si_habia_mas()
	{
		var (recortada, hayMas) = AvisoTope.Recortar(Enumerable.Range(1, 2001).ToList(), 2000);
		Assert.Equal(2000, recortada.Count);
		Assert.True(hayMas);

		var (completa, sinMas) = AvisoTope.Recortar(Enumerable.Range(1, 2000).ToList(), 2000);
		Assert.Equal(2000, completa.Count);
		Assert.False(sinMas);
	}
}
