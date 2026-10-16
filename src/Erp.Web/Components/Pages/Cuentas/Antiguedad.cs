using Erp.Data.Cuentas;

namespace Erp.Web.Components.Pages.Cuentas;

public sealed record TerceroSeleccion(int Id, string Codigo, string Nombre);

// Rangos de la antigüedad de saldos por vencimiento.
public static class RangosAntiguedad
{
	public static readonly string[] Etiquetas = { "No vencido", "1-30 días", "31-60 días", "61-90 días", "Más de 90 días" };

	public static decimal[] De(AntiguedadFila f) => new[] { f.NoVencido, f.De1a30, f.De31a60, f.De61a90, f.Mas90 };
}

public sealed class AntiguedadDocumento
{
	public int EncId { get; init; }
	public string Documento { get; init; } = "";
	public DateTime FechaDocumento { get; init; }
	public DateTime VencimientoMasAntiguo { get; set; }
	public int DiasMaximos { get; set; }
	public int Cuotas { get; set; }
	public decimal[] Rangos { get; } = new decimal[5];
	public decimal Total => Rangos.Sum();
}

public sealed class AntiguedadGrupo
{
	public int Id { get; init; }
	public string Codigo { get; init; } = "";
	public string Nombre { get; init; } = "";
	public List<AntiguedadDocumento> Documentos { get; } = new();
	public decimal[] Rangos { get; } = new decimal[5];
	public decimal Total => Rangos.Sum();

	// Agrupa las cuotas pendientes por tercero y documento.
	public static List<AntiguedadGrupo> Agrupar(IEnumerable<AntiguedadFila> filas)
	{
		var grupos = new List<AntiguedadGrupo>();
		foreach (var porTercero in filas.GroupBy(f => f.Id))
		{
			var primera = porTercero.First();
			var grupo = new AntiguedadGrupo { Id = primera.Id, Codigo = primera.Codigo, Nombre = primera.Nombre };
			foreach (var porDocumento in porTercero.GroupBy(f => f.EncId))
			{
				var d = porDocumento.First();
				var documento = new AntiguedadDocumento
				{
					EncId = d.EncId, Documento = d.Documento, FechaDocumento = d.FechaDocumento,
					VencimientoMasAntiguo = porDocumento.Min(f => f.Vencimiento),
					DiasMaximos = porDocumento.Max(f => f.Dias),
					Cuotas = porDocumento.Count()
				};
				foreach (var f in porDocumento)
				{
					var r = RangosAntiguedad.De(f);
					for (var i = 0; i < 5; i++)
					{
						documento.Rangos[i] += r[i];
						grupo.Rangos[i] += r[i];
					}
				}
				grupo.Documentos.Add(documento);
			}
			grupos.Add(grupo);
		}
		return grupos.OrderBy(g => g.Nombre, StringComparer.CurrentCulture).ToList();
	}

	public static decimal[] Totales(IEnumerable<AntiguedadGrupo> grupos)
	{
		var t = new decimal[5];
		foreach (var g in grupos)
			for (var i = 0; i < 5; i++) t[i] += g.Rangos[i];
		return t;
	}
}
