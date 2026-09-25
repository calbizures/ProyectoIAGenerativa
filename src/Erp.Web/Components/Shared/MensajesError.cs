using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;

namespace Erp.Web.Components.Shared;

// Traduce las excepciones que llegan a las pantallas a mensajes en español
// que el usuario pueda entender. Los errores de negocio lanzados por los
// procedimientos (THROW 5xxxx) ya vienen redactados en español y se muestran
// tal cual; los errores propios del motor (llaves foráneas, duplicados,
// longitudes, conexión) se reemplazan por un texto equivalente.
public static partial class MensajesError
{
	public static string Traducir(Exception ex)
	{
		var sql = ex as SqlException ?? ex.InnerException as SqlException;
		if (sql is not null)
		{
			return TraducirSql(sql);
		}

		return ex switch
		{
			// Mensajes redactados por la propia aplicación (ya en español).
			InvalidOperationException or ArgumentException when EsTextoPropio(ex.Message) => ex.Message,
			TimeoutException => "La operación tardó demasiado en responder. Intente de nuevo.",
			FormatException => "Uno de los valores ingresados no tiene el formato correcto.",
			OverflowException => "Uno de los valores ingresados es demasiado grande.",
			UnauthorizedAccessException => "No tiene permiso para realizar esta operación.",
			_ => "Ocurrió un error inesperado. Intente de nuevo o comuníquese con el administrador del sistema."
		};
	}

	private static string TraducirSql(SqlException sql)
	{
		// Errores de negocio definidos en los procedimientos almacenados.
		if (sql.Number >= 50000)
		{
			return sql.Message;
		}

		switch (sql.Number)
		{
			case 547:
				if (sql.Message.Contains("CHECK", StringComparison.OrdinalIgnoreCase))
				{
					return "Uno de los valores no cumple las reglas permitidas para este dato" + Detalle(sql.Message) + ".";
				}
				return sql.Message.Contains("DELETE", StringComparison.OrdinalIgnoreCase)
					? "No se puede eliminar el registro porque está siendo utilizado por otros datos" + Detalle(sql.Message) + "."
					: "El registro hace referencia a un dato que no existe o fue eliminado" + Detalle(sql.Message) + ".";
			case 2627:
			case 2601:
				var valor = ValorDuplicadoRegex().Match(sql.Message);
				return valor.Success
					? $"Ya existe un registro con el valor {valor.Groups[1].Value}. Verifique los datos ingresados."
					: "Ya existe un registro con esos datos. Verifique los datos ingresados.";
			case 515:
				var columna = ColumnaNulaRegex().Match(sql.Message);
				return columna.Success
					? $"Falta un dato obligatorio ({columna.Groups[1].Value})."
					: "Falta un dato obligatorio.";
			case 2628:
			case 8152:
				return "Uno de los textos ingresados excede la longitud permitida.";
			case 8114:
			case 245:
				return "Uno de los valores ingresados no tiene el formato correcto.";
			case 8115:
				return "Uno de los valores numéricos es demasiado grande.";
			case 1205:
				return "La operación entró en conflicto con otro usuario. Intente de nuevo.";
			case -2:
				return "La base de datos tardó demasiado en responder. Intente de nuevo.";
			case -1:
			case 2:
			case 53:
			case 4060:
			case 18456:
				return "No se pudo conectar con la base de datos. Comuníquese con el administrador del sistema.";
			case 2812:
				return "La base de datos no tiene instalado un procedimiento requerido. Ejecute los scripts pendientes.";
			case 207:
			case 208:
				return "La base de datos no está actualizada con esta versión del sistema. Ejecute los scripts pendientes.";
			default:
				return "Ocurrió un error en la base de datos. Comuníquese con el administrador del sistema.";
		}
	}

	// Nombre de la tabla involucrada en una violación de llave foránea, si aparece.
	private static string Detalle(string mensaje)
	{
		var tabla = TablaRegex().Match(mensaje);
		return tabla.Success ? $" (tabla {tabla.Groups[1].Value})" : "";
	}

	// Heurística simple: los mensajes propios llevan tildes o signos del español.
	private static bool EsTextoPropio(string mensaje) =>
		mensaje.IndexOfAny(['á', 'é', 'í', 'ó', 'ú', 'ñ', '¿', '¡']) >= 0
		|| mensaje.StartsWith("No ", StringComparison.Ordinal)
		|| mensaje.StartsWith("Debe ", StringComparison.Ordinal)
		|| mensaje.StartsWith("Seleccione ", StringComparison.Ordinal);

	[GeneratedRegex(@"duplicate key value is \((.+?)\)")]
	private static partial Regex ValorDuplicadoRegex();

	[GeneratedRegex(@"column '([^']+)'")]
	private static partial Regex ColumnaNulaRegex();

	[GeneratedRegex(@"table ""dbo\.([^""]+)""")]
	private static partial Regex TablaRegex();
}
