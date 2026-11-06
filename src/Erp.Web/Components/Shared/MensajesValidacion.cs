using System.Text.RegularExpressions;
using static Erp.Web.Idioma.Textos;

namespace Erp.Web.Components.Shared;

// Traduce los mensajes de validación por defecto de DataAnnotations y de los
// componentes Input* de Blazor (que vienen en inglés) al idioma del usuario,
// con el nombre del campo legible. Los mensajes propios (ErrorMessage) están
// en español y se traducen con Textos.Mensaje.
public static partial class MensajesValidacion
{
	private static readonly Dictionary<string, string> Etiquetas = new(StringComparer.OrdinalIgnoreCase)
	{
		["Codigo"] = "Código",
		["Descripcion"] = "Descripción",
		["Direccion"] = "Dirección",
		["Telefono"] = "Teléfono",
		["TelefonoCelular"] = "Teléfono celular",
		["Password"] = "Contraseña",
		["Contrasena"] = "Contraseña",
		["Nit"] = "NIT",
		["Email"] = "Correo electrónico",
		["LimiteCredito"] = "Límite de crédito",
		["PorcentajeComision"] = "Porcentaje de comisión",
		["PorcIva"] = "% IVA",
		["CiaPorcIva"] = "% IVA",
		["CiaNombreComercial"] = "Nombre comercial",
		["CiaToleranciaCierreCaja"] = "Tolerancia de cierre de caja",
		["PrimerNombre"] = "Primer nombre",
		["PrimerApellido"] = "Primer apellido",
		["CodigoEmpleado"] = "Código de empleado",
		["SalarioBase"] = "Salario base",
		["FechaIngreso"] = "Fecha de ingreso",
		["FechaDel"] = "Fecha del",
		["FechaAl"] = "Fecha al",
		["Monto"] = "Monto",
		["Valor"] = "Valor",
		["Numero"] = "Número",
	};

	public static string Traducir(string mensaje)
	{
		var m = RequeridoRegex().Match(mensaje);
		if (m.Success) return L("El campo {0} es obligatorio.", Etiqueta(m.Groups[1].Value));

		m = NumeroRegex().Match(mensaje);
		if (m.Success) return L("El campo {0} debe ser un número.", Etiqueta(m.Groups[1].Value));

		m = FechaRegex().Match(mensaje);
		if (m.Success) return L("El campo {0} debe ser una fecha válida.", Etiqueta(m.Groups[1].Value));

		m = RangoRegex().Match(mensaje);
		if (m.Success) return L("El campo {0} debe estar entre {1} y {2}.", Etiqueta(m.Groups[1].Value), m.Groups[2].Value, m.Groups[3].Value);

		m = LongitudRegex().Match(mensaje);
		if (m.Success) return L("El campo {0} admite como máximo {1} caracteres.", Etiqueta(m.Groups[1].Value), m.Groups[2].Value);

		m = CorreoRegex().Match(mensaje);
		if (m.Success) return L("El campo {0} no es un correo electrónico válido.", Etiqueta(m.Groups[1].Value));

		m = NoValidoRegex().Match(mensaje);
		if (m.Success) return L("El valor del campo {0} no es válido.", Etiqueta(m.Groups[1].Value));

		return Mensaje(mensaje);
	}

	// "TelefonoCelular" -> "Teléfono celular" (diccionario) o "Salario minimo" (separando PascalCase).
	private static string Etiqueta(string campo)
	{
		if (Etiquetas.TryGetValue(campo, out var etiqueta)) return L(etiqueta);
		var partes = PascalRegex().Split(campo).Where(p => p.Length > 0).ToArray();
		if (partes.Length == 0) return campo;
		return L(string.Join(" ", partes.Select((p, i) => i == 0 ? p : p.ToLowerInvariant())));
	}

	[GeneratedRegex(@"^The (.+?) field is required\.$")]
	private static partial Regex RequeridoRegex();

	[GeneratedRegex(@"^The (.+?) field must be a number\.$")]
	private static partial Regex NumeroRegex();

	[GeneratedRegex(@"^The (.+?) field must be a date\.$")]
	private static partial Regex FechaRegex();

	[GeneratedRegex(@"^The field (.+?) must be between (.+?) and (.+?)\.$")]
	private static partial Regex RangoRegex();

	[GeneratedRegex(@"^The field (.+?) must be a string (?:or array type )?with a maximum length of '?(\d+)'?\.$")]
	private static partial Regex LongitudRegex();

	[GeneratedRegex(@"^The (.+?) field is not a valid e-mail address\.$")]
	private static partial Regex CorreoRegex();

	[GeneratedRegex(@"^The (.+?) field is not valid\.$")]
	private static partial Regex NoValidoRegex();

	[GeneratedRegex(@"(?<!^)(?=[A-Z])")]
	private static partial Regex PascalRegex();
}
