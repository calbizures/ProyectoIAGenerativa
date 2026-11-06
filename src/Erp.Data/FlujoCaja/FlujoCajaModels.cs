namespace Erp.Data.FlujoCaja;

// Actividad: O operación, I inversión, F financiamiento.
public sealed class FlujoRealFila
{
	public DateTime Periodo { get; set; }
	public string Actividad { get; set; } = "O";
	public string Concepto { get; set; } = "";
	public decimal Entradas { get; set; }
	public decimal Salidas { get; set; }
}

public sealed class FlujoRealPoliza
{
	public int AsiId { get; set; }
	public DateTime Fecha { get; set; }
	public string Origen { get; set; } = "";
	public string Descripcion { get; set; } = "";
	public decimal Neto { get; set; }
	public string? Clasificacion { get; set; }
}

public sealed class FlujoReal
{
	public decimal SaldoInicial { get; set; }
	public decimal SaldoFinal { get; set; }
	public IReadOnlyList<FlujoRealFila> Filas { get; set; } = Array.Empty<FlujoRealFila>();
	public IReadOnlyList<FlujoRealPoliza> Polizas { get; set; } = Array.Empty<FlujoRealPoliza>();
}

public sealed class FlujoProyectadoItem
{
	public DateTime Fecha { get; set; }
	public string Actividad { get; set; } = "O";
	public string Concepto { get; set; } = "";
	public decimal Monto { get; set; }
	public string? Detalle { get; set; }
	public bool Vencido { get; set; }
}

public sealed class FlujoProyectado
{
	public decimal SaldoInicial { get; set; }
	public IReadOnlyList<FlujoProyectadoItem> Items { get; set; } = Array.Empty<FlujoProyectadoItem>();
}

public sealed class PartidaProyectada
{
	public int FcpId { get; set; }
	public DateTime Fecha { get; set; } = DateTime.Today;
	public string Actividad { get; set; } = "O";
	public string Concepto { get; set; } = "";
	public decimal Monto { get; set; }
	// U una vez, M cada mes hasta FechaFin.
	public string Recurrencia { get; set; } = "U";
	public DateTime? FechaFin { get; set; }
	public string Estado { get; set; } = "A";
}

public sealed class CuentaEfectivo
{
	public int CtaId { get; set; }
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public int Cuentas { get; set; }
}

public static class ActividadesFlujo
{
	public static readonly IReadOnlyList<(string Codigo, string Nombre)> Todas = new[]
	{
		("O", "Actividades de operación"), ("I", "Actividades de inversión"), ("F", "Actividades de financiamiento")
	};

	public static string Nombre(string codigo) => Todas.FirstOrDefault(a => a.Codigo == codigo).Nombre ?? codigo;
}
