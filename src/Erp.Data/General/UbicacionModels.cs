namespace Erp.Data.General;

// Ubicación en cascada País › Departamento › Municipio (gen_pais ›
// gen_estado › gen_provincia, script 73). Los registros guardan solo el
// municipio (prov_id); departamento y país se obtienen de aquí.
public sealed class Pais
{
	public int PaiId { get; set; }
	public string Nombre { get; set; } = "";
	public string CodigoAlfa2 { get; set; } = "";
	public string CodigoAlfa3 { get; set; } = "";
	public string? CodigoNumero { get; set; }
	public string? Nacionalidad { get; set; }
	public string Estado { get; set; } = "A";
}

public sealed class DepartamentoGeografico
{
	public int EstId { get; set; }
	public int PaiId { get; set; }
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public string Estado { get; set; } = "A";
}

public sealed class Municipio
{
	public int ProvId { get; set; }
	public int EstId { get; set; }
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public string Estado { get; set; } = "A";
}

public sealed class CatalogoUbicacion
{
	public IReadOnlyList<Pais> Paises { get; init; } = Array.Empty<Pais>();
	public IReadOnlyList<DepartamentoGeografico> Departamentos { get; init; } = Array.Empty<DepartamentoGeografico>();
	public IReadOnlyList<Municipio> Municipios { get; init; } = Array.Empty<Municipio>();

	public Municipio? BuscarMunicipio(int? provId) => provId is null ? null : Municipios.FirstOrDefault(m => m.ProvId == provId);
	public DepartamentoGeografico? BuscarDepartamento(int? estId) => estId is null ? null : Departamentos.FirstOrDefault(d => d.EstId == estId);
	public Pais? BuscarPais(int? paiId) => paiId is null ? null : Paises.FirstOrDefault(p => p.PaiId == paiId);

	// "Municipio, Departamento" (más el país si no es Guatemala).
	public string? Describir(int? provId)
	{
		var muni = BuscarMunicipio(provId);
		if (muni is null) return null;
		var depa = BuscarDepartamento(muni.EstId);
		var pais = BuscarPais(depa?.PaiId);
		var partes = new List<string> { muni.Nombre };
		if (depa is not null) partes.Add(depa.Nombre);
		if (pais is not null && pais.CodigoAlfa2 != "GT") partes.Add(pais.Nombre);
		return string.Join(", ", partes);
	}
}
