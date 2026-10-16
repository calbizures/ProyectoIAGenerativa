using System.Globalization;
using System.Text;
using Erp.Data.Rrhh;

namespace Erp.Web.Reportes;

// Archivo de la planilla del IGSS para "sistema propio", versión 2.2.0.
// Sigue el manual GenerarArchivoPlanilla 2.2.0 y la plantilla oficial
// SISTEMA_PROPIO_2.2.0.xls del IGSS:
//   - datos de tipo letra en MAYÚSCULAS, campos separados por "|", un registro por línea;
//   - encabezado: 2.2.0|dd/mm/yyyy|patronal|mes|año|nombre comercial|NIT sin guion|correo|0 producción / 1 pruebas;
//   - bloques [centros], [tiposplanilla], [liquidaciones], [empleados], [suspendidos],
//     [licencias], [juramento] y [finplanilla], con los nombres que escribe la plantilla oficial;
//   - cada registro de un bloque termina en "|", como en la plantilla oficial;
//   - nombre: patronal-AAAAMM-ddmmyyyy-HHMM.txt.
public static class ArchivoPlanillaIgss
{
	public const string Version = "2.2.0";

	public const string Juramento = "BAJO MI EXCLUSIVA Y ABSOLUTA RESPONSABILIDAD, DECLARO QUE LA INFORMACION QUE AQUI CONSIGNO ES FIEL Y EXACTA, " +
		"QUE ESTA PLANILLA INCLUYE A TODOS LOS TRABAJADORES QUE ESTUVIERON A MI SERVICIO Y QUE SUS SALARIOS SON LOS EFECTIVAMENTE " +
		"DEVENGADOS, DURANTE EL MES ARRIBA INDICADO";

	// Latin-1: la Ñ es el único carácter fuera de ASCII que queda después de quitar tildes.
	public static readonly Encoding Codificacion = Encoding.Latin1;

	public sealed record Opciones(DateTime Generado, bool Pruebas = false, bool Complementaria = false, string? NotaCargo = null);

	public static string NombreArchivo(IgssArchivoDatos datos, DateTime generado) =>
		$"{datos.Patrono?.NumeroPatronal}-{datos.Patrono?.Anio:0000}{datos.Patrono?.Mes:00}-{generado:ddMMyyyy}-{generado:HHmm}.txt";

	public static string Generar(IgssArchivoDatos datos, Opciones opciones)
	{
		var p = datos.Patrono ?? throw new InvalidOperationException("No hay datos del patrono.");
		var texto = new StringBuilder();
		void Linea(string linea) => texto.Append(linea).Append("\r\n");
		void Registro(params string?[] campos) => Linea(string.Join("|", campos.Select(c => c ?? "")) + "|");

		Linea(string.Join("|", Version, Fecha(opciones.Generado), Numero(p.NumeroPatronal, 10), p.Mes.ToString("00"), p.Anio.ToString("0000"),
			Letra(p.NombreComercial, 200), Nit(p.Nit), Libre(p.Correo, 100), opciones.Pruebas ? "1" : "0"));

		Linea("[centros]");
		foreach (var c in datos.Centros)
			Registro(Numero(c.Codigo, 5), Letra(c.Nombre, 200), Letra(c.Direccion, 200), c.Zona?.ToString(), Libre(c.Telefono, 100),
				Libre(c.Fax, 60), Letra(c.Contacto, 100), Libre(c.Email, 60), Entero(c.Departamento), Entero(c.Municipio), Numero(c.Actividad, 6));

		Linea("[tiposplanilla]");
		foreach (var t in datos.TiposPlanilla)
			Registro(t.Codigo.ToString(CultureInfo.InvariantCulture), Letra(t.Nombre, 100), t.TipoAfiliado, t.Periodo, Entero(t.Departamento),
				Numero(t.Actividad, 6), t.Clase, t.TiempoContrato);

		Linea("[liquidaciones]");
		foreach (var l in datos.Liquidaciones)
			Registro(l.Numero.ToString(CultureInfo.InvariantCulture), l.TipoPlanilla.ToString(CultureInfo.InvariantCulture), Fecha(l.FechaInicio),
				Fecha(l.FechaFin), opciones.Complementaria ? "C" : "O", Letra(opciones.NotaCargo, 10));

		Linea("[empleados]");
		foreach (var e in datos.Empleados)
			Registro(e.Liquidacion.ToString(CultureInfo.InvariantCulture), Afiliacion(e.Afiliacion), Letra(e.PrimerNombre, 60), Letra(e.SegundoNombre, 100),
				Letra(e.PrimerApellido, 60), Letra(e.SegundoApellido, 60), Letra(e.ApellidoCasada, 60), Monto(e.Sueldo), Fecha(e.FechaAlta),
				Fecha(e.FechaBaja), Numero(e.Centro, 5), Nit(e.Nit), Numero(e.Ocupacion, 4), e.Condicion, "", e.TipoSalario.ToString(CultureInfo.InvariantCulture),
				e.Horas?.ToString("0", CultureInfo.InvariantCulture), e.TiempoContrato, e.Dias.ToString("0.##", CultureInfo.InvariantCulture));

		Linea("[suspendidos]");
		foreach (var a in datos.Ausencias.Where(a => a.Tipo == "S"))
			Ausencia(a);
		Linea("[licencias]");
		foreach (var a in datos.Ausencias.Where(a => a.Tipo == "L"))
			Ausencia(a);

		Linea("[juramento]");
		Linea(Juramento);
		Linea("[finplanilla]");
		return texto.ToString();

		void Ausencia(IgssArchivoAusencia a) =>
			Registro(a.Liquidacion.ToString(CultureInfo.InvariantCulture), Afiliacion(a.Afiliacion), Letra(a.PrimerNombre, 60), Letra(a.SegundoNombre, 100),
				Letra(a.PrimerApellido, 60), Letra(a.SegundoApellido, 60), Letra(a.ApellidoCasada, 60), Fecha(a.FechaInicio), Fecha(a.FechaFin));
	}

	private static string Fecha(DateTime? fecha) => fecha?.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture) ?? "";

	// Campos "entero" del manual (departamento, municipio): sin ceros a la izquierda, como en su ejemplo.
	private static string Entero(string? valor) =>
		int.TryParse(Limpio(valor), NumberStyles.None, CultureInfo.InvariantCulture, out var numero) ? numero.ToString(CultureInfo.InvariantCulture) : "";

	private static string Monto(decimal valor) => valor.ToString("0.00", CultureInfo.InvariantCulture);

	private static string Nit(string? nit) => Limpio(nit)?.Replace("-", "").Replace(" ", "").ToUpperInvariant() ?? "";

	private static string Afiliacion(string? numero) => Limpio(numero)?.Replace(" ", "") ?? "";

	private static string Numero(string? valor, int largo)
	{
		var limpio = Limpio(valor) ?? "";
		return limpio.Length > largo ? limpio[..largo] : limpio;
	}

	// Texto libre que no es "letra" (correo, teléfonos): sin separadores ni saltos de línea.
	private static string Libre(string? valor, int largo)
	{
		var limpio = Limpio(valor) ?? "";
		return limpio.Length > largo ? limpio[..largo] : limpio;
	}

	// Dato de tipo letra: MAYÚSCULAS y sin tildes (la Ñ se conserva).
	public static string Letra(string? valor, int largo)
	{
		var limpio = Limpio(valor);
		if (limpio is null) return "";
		var resultado = new StringBuilder(limpio.Length);
		foreach (var c in limpio.ToUpper(CultureInfo.GetCultureInfo("es-GT")))
		{
			if (c == 'Ñ') { resultado.Append(c); continue; }
			foreach (var parte in c.ToString().Normalize(NormalizationForm.FormD))
				if (CharUnicodeInfo.GetUnicodeCategory(parte) != UnicodeCategory.NonSpacingMark) resultado.Append(parte);
		}
		return resultado.Length > largo ? resultado.ToString(0, largo) : resultado.ToString();
	}

	private static string? Limpio(string? valor)
	{
		if (string.IsNullOrWhiteSpace(valor)) return null;
		var limpio = valor.Replace("|", " ").Replace("\r", " ").Replace("\n", " ").Replace("\t", " ").Trim();
		while (limpio.Contains("  ")) limpio = limpio.Replace("  ", " ");
		return limpio;
	}
}
