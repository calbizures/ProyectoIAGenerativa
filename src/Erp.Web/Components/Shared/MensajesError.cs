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
				// Regla de la base (script 50): ninguna bodega queda con existencia negativa.
				if (sql.Message.Contains("CK_inv_existencia_no_negativa", StringComparison.OrdinalIgnoreCase))
				{
					return "No hay existencia suficiente: la operación dejaría la bodega en negativo. Puede que otro usuario haya vendido o "
						+ "trasladado la mercadería al mismo tiempo, o que la mercadería de la compra o carga que intenta anular ya se haya vendido.";
				}
				// Reglas del script 51: ninguna cuota queda con saldo negativo ni pagada de más.
				if (sql.Message.Contains("CK_pos_cliente_plan_pagos_saldo", StringComparison.OrdinalIgnoreCase)
					|| sql.Message.Contains("CK_inv_proveedor_plan_pago_saldo", StringComparison.OrdinalIgnoreCase))
				{
					return "La operación dejaría una cuota con saldo negativo o pagada de más. Puede que otro usuario haya aplicado un cobro, "
						+ "pago o nota al mismo documento al mismo tiempo: vuelva a consultarlo e intente de nuevo.";
				}
				if (sql.Message.Contains("CHECK", StringComparison.OrdinalIgnoreCase))
				{
					return "Uno de los valores no cumple las reglas permitidas para este dato" + Detalle(sql.Message) + ".";
				}
				return sql.Message.Contains("DELETE", StringComparison.OrdinalIgnoreCase)
					? "No se puede eliminar el registro porque está siendo utilizado por otros datos" + Detalle(sql.Message) + "."
					: "El registro hace referencia a un dato que no existe o fue eliminado" + Detalle(sql.Message) + ".";
			case 2627:
			case 2601:
				if (sql.Message.Contains("UQ_bco_cheque_emitido_enc_numero", StringComparison.OrdinalIgnoreCase))
				{
					return "Ese número de cheque ya se usó en la chequera (quizá otro usuario emitió un cheque al mismo tiempo). Vuelva a intentarlo para tomar el siguiente número.";
				}
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
				return "La base de datos no está actualizada con esta versión del sistema. Ejecute los scripts pendientes" + Referencia(sql) + ".";
			case 1934:
				// Procedimiento creado con QUOTED_IDENTIFIER u otra opción SET en OFF.
				return "Un procedimiento de la base de datos se creó con opciones SET incorrectas y no puede grabar" + Referencia(sql)
					+ ". Ejecute el script 47_reparar_opciones_set.sql y vuelva a intentarlo.";
			default:
				// Sin el número y el procedimiento el error no se puede diagnosticar.
				return "Ocurrió un error en la base de datos" + Referencia(sql) + ". Comuníquese con el administrador del sistema.";
		}
	}

	// "(error SQL 1934 en dbo.sp_cliente_insertar, línea 25)" para el soporte.
	private static string Referencia(SqlException sql) =>
		$" (error SQL {sql.Number}{(string.IsNullOrEmpty(sql.Procedure) ? "" : $" en {sql.Procedure}")}{(sql.LineNumber > 0 ? $", línea {sql.LineNumber}" : "")})";

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
