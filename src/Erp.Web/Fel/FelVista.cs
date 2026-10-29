namespace Erp.Web.Fel;

// Presentación del estado FEL en las pantallas.
public static class FelVista
{
	public static string Clase(string? estado) => estado switch
	{
		"C" => "estado-badge-activo",
		"R" => "estado-badge-anulada",
		"X" => "estado-badge-anulada",
		"P" => "estado-badge-pendiente",
		_ => "estado-badge-inactivo"
	};

	public static readonly (string Codigo, string Texto)[] Estados =
	{
		("N", "No enviado"), ("P", "Pendiente"), ("R", "Rechazado"), ("C", "Certificado"), ("X", "Anulación pendiente"), ("A", "Anulado en SAT")
	};
}
