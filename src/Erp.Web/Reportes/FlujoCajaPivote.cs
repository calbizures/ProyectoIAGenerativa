using System.Globalization;
using Erp.Data.FlujoCaja;

namespace Erp.Web.Reportes;

// Flujo de caja en columnas por período (semana o mes): saldo inicial, cada
// concepto agrupado por actividad, flujo neto y saldo final. Lo usan la
// pantalla y el Excel, para el flujo real y el proyectado.
public sealed class FlujoCajaPivote
{
	public sealed record Fila(string Actividad, string Concepto, IReadOnlyDictionary<DateTime, decimal> Montos)
	{
		public decimal Total => Montos.Values.Sum();
	}

	public IReadOnlyList<DateTime> Periodos { get; init; } = Array.Empty<DateTime>();
	public IReadOnlyList<Fila> Filas { get; init; } = Array.Empty<Fila>();
	public decimal SaldoInicial { get; init; }
	public string Agrupar { get; init; } = "M";

	public decimal Neto(DateTime periodo) => Filas.Sum(f => f.Montos.GetValueOrDefault(periodo));
	public decimal Neto(DateTime periodo, string actividad) => Filas.Where(f => f.Actividad == actividad).Sum(f => f.Montos.GetValueOrDefault(periodo));
	public decimal Entradas(DateTime periodo) => Filas.Sum(f => Math.Max(0, f.Montos.GetValueOrDefault(periodo)));
	public decimal Salidas(DateTime periodo) => Filas.Sum(f => Math.Max(0, -f.Montos.GetValueOrDefault(periodo)));

	public decimal SaldoInicialDe(DateTime periodo) => SaldoInicial + Periodos.TakeWhile(p => p < periodo).Sum(Neto);
	public decimal SaldoFinalDe(DateTime periodo) => SaldoInicialDe(periodo) + Neto(periodo);
	public decimal SaldoFinal => SaldoInicial + Periodos.Sum(Neto);

	public string Etiqueta(DateTime periodo) => Agrupar == "S"
		? $"Sem. {periodo:dd/MM}"
		: CultureInfo.GetCultureInfo("es-GT").TextInfo.ToTitleCase(periodo.ToString("MMM yyyy", CultureInfo.GetCultureInfo("es-GT")).Replace(".", ""));

	public static DateTime Periodo(DateTime fecha, string agrupar) => agrupar == "S"
		? fecha.Date.AddDays(-(((int)fecha.DayOfWeek + 6) % 7))
		: new DateTime(fecha.Year, fecha.Month, 1);

	// Todos los períodos del rango, aunque no tengan movimiento.
	private static List<DateTime> Rango(DateTime desde, DateTime hasta, string agrupar)
	{
		var periodos = new List<DateTime>();
		for (var p = Periodo(desde, agrupar); p <= hasta; p = agrupar == "S" ? p.AddDays(7) : p.AddMonths(1))
			periodos.Add(p);
		return periodos;
	}

	private static IReadOnlyList<Fila> AgruparFilas(IEnumerable<(string Actividad, string Concepto, DateTime Periodo, decimal Monto)> montos) =>
		montos.GroupBy(m => (m.Actividad, m.Concepto))
			.OrderBy(g => "OIF".IndexOf(g.Key.Actividad, StringComparison.Ordinal)).ThenByDescending(g => g.Sum(m => Math.Abs(m.Monto)))
			.Select(g => new Fila(g.Key.Actividad, g.Key.Concepto, g.GroupBy(m => m.Periodo).ToDictionary(p => p.Key, p => p.Sum(m => m.Monto))))
			.ToList();

	public static FlujoCajaPivote DeReal(FlujoReal real, DateTime desde, DateTime hasta, string agrupar) => new()
	{
		Agrupar = agrupar,
		SaldoInicial = real.SaldoInicial,
		Periodos = Rango(desde, hasta, agrupar),
		Filas = AgruparFilas(real.Filas.Select(f => (f.Actividad, f.Concepto, f.Periodo, f.Entradas - f.Salidas)))
	};

	public static FlujoCajaPivote DeProyectado(FlujoProyectado proyectado, DateTime hasta, string agrupar) => new()
	{
		Agrupar = agrupar,
		SaldoInicial = proyectado.SaldoInicial,
		Periodos = Rango(DateTime.Today, hasta, agrupar),
		Filas = AgruparFilas(proyectado.Items.Select(i => (i.Actividad, i.Concepto, Periodo(i.Fecha, agrupar), i.Monto)))
	};
}
