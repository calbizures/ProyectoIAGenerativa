using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;

namespace Erp.Tests.Integracion;

// Pruebas contra una base erp_db instalada (instalar_01_al_NN.sql). La cadena
// de conexión va en la variable de entorno ERP_PRUEBAS_BD; sin ella estas
// pruebas se saltan y solo corren las unitarias. Las que cambian datos lo
// hacen dentro de una transacción que se revierte.
public static class BaseDatos
{
	public const string Variable = "ERP_PRUEBAS_BD";

	public static string? Cadena => Environment.GetEnvironmentVariable(Variable) is { Length: > 0 } c ? c : null;

	public static SqlConnection Abrir()
	{
		Dapper.DefaultTypeMap.MatchNamesWithUnderscores = true;
		var conexion = new SqlConnection(Cadena ?? throw new InvalidOperationException($"Falta {Variable}."));
		conexion.Open();
		return conexion;
	}

	public static Task<T> ProcedimientoEscalarAsync<T>(IDbConnection conexion, string nombre, object? parametros = null, IDbTransaction? transaccion = null) =>
		conexion.ExecuteScalarAsync<T>(nombre, parametros, transaccion, commandType: CommandType.StoredProcedure)!;

	// Saldo deudor (debe - haber) de la cuenta configurada para un concepto.
	public static Task<decimal> SaldoCuentaAsync(IDbConnection conexion, string concepto, IDbTransaction? transaccion = null) =>
		conexion.ExecuteScalarAsync<decimal>("""
			SELECT ISNULL(SUM(deta.asd_debe - deta.asd_haber), 0)
			FROM dbo.cont_asiento_det deta
			INNER JOIN dbo.cont_asiento_enc enca ON enca.asi_id = deta.asi_id AND enca.asi_estado = 'A'
			WHERE deta.cta_id = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = @concepto)
			""", new { concepto }, transaccion);
}

// [Fact] que se salta cuando no hay base de pruebas configurada.
public sealed class FactBaseDatosAttribute : FactAttribute
{
	public FactBaseDatosAttribute()
	{
		if (BaseDatos.Cadena is null)
			Skip = $"Sin base de pruebas: defina {BaseDatos.Variable} con la cadena de conexión.";
	}
}
