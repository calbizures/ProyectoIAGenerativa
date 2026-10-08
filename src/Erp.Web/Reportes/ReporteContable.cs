using System.Globalization;

namespace Erp.Web.Reportes;

// Parámetros de los reportes contables (libro diario, mayor, balanza y estados
// financieros); los comparten la pantalla, la vista imprimible y el Excel.
public sealed class ReporteContable
{
	public string Tipo { get; set; } = "diario";
	public DateTime Desde { get; set; } = new(DateTime.Today.Year, DateTime.Today.Month, 1);
	public DateTime Hasta { get; set; } = DateTime.Today;
	public int Nivel { get; set; } = 3;
	public int? CtaId { get; set; }
	public bool Comparar { get; set; }
	public DateTime? DesdeComparativo { get; set; }
	public DateTime? HastaComparativo { get; set; }

	public static readonly IReadOnlyList<(int Nivel, string Nombre)> Niveles = new[]
	{
		(1, "Nivel 1 (grupos)"), (2, "Nivel 2"), (3, "Nivel 3 (mayor)"), (4, "Nivel 4 (detalle)")
	};

	public string Titulo => Tipo switch
	{
		"mayor" => "Libro mayor",
		"balanza" => "Balanza de comprobación",
		"balance" => "Balance General",
		"resultados" => "Estado de Resultados",
		_ => "Libro diario"
	};

	public string Rango => Tipo == "balance"
		? $"Al {Hasta:dd/MM/yyyy}" + (Comparar && HastaComparativo is not null ? $" comparado con el {HastaComparativo:dd/MM/yyyy}" : "")
		: $"Del {Desde:dd/MM/yyyy} al {Hasta:dd/MM/yyyy}"
		  + (Tipo == "resultados" && Comparar && DesdeComparativo is not null && HastaComparativo is not null
			  ? $" comparado con del {DesdeComparativo:dd/MM/yyyy} al {HastaComparativo:dd/MM/yyyy}" : "");

	public string Query()
	{
		var partes = new List<string> { $"tipo={Tipo}", $"desde={Desde:yyyy-MM-dd}", $"hasta={Hasta:yyyy-MM-dd}", $"nivel={Nivel}" };
		if (CtaId is not null) partes.Add($"cta={CtaId}");
		if (Comparar)
		{
			partes.Add("comparar=true");
			if (DesdeComparativo is not null) partes.Add($"desdec={DesdeComparativo:yyyy-MM-dd}");
			if (HastaComparativo is not null) partes.Add($"hastac={HastaComparativo:yyyy-MM-dd}");
		}
		return string.Join("&", partes);
	}

	public static ReporteContable Crear(string? tipo, DateTime? desde, DateTime? hasta, int? nivel, int? cta, bool? comparar, DateTime? desdec, DateTime? hastac)
	{
		var r = new ReporteContable { Tipo = tipo ?? "diario", Nivel = Math.Clamp(nivel ?? 3, 1, 4), CtaId = cta, Comparar = comparar == true };
		if (desde is not null) r.Desde = desde.Value.Date;
		if (hasta is not null) r.Hasta = hasta.Value.Date;
		r.DesdeComparativo = desdec?.Date;
		r.HastaComparativo = hastac?.Date;
		return r;
	}

	public string EtiquetaActual => Tipo == "balance" ? Hasta.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture) : $"{Desde:dd/MM/yy}–{Hasta:dd/MM/yy}";
	public string EtiquetaComparativa => Tipo == "balance"
		? HastaComparativo?.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture) ?? ""
		: $"{DesdeComparativo:dd/MM/yy}–{HastaComparativo:dd/MM/yy}";
}
