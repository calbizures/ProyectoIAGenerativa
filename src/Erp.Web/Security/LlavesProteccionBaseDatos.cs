using System.Data;
using System.Xml.Linq;
using Dapper;
using Erp.Data;
using Microsoft.AspNetCore.DataProtection.Repositories;

namespace Erp.Web.Security;

// Guarda las llaves de Data Protection en gen_proteccion_llave (script 84):
// la cookie de sesión, los borradores del navegador y la contraseña del
// correo siguen siendo legibles al reiniciar, reinstalar o correr la
// aplicación en varios servidores.
public sealed class LlavesProteccionBaseDatos(IDbConnectionFactory conexiones) : IXmlRepository
{
	public IReadOnlyCollection<XElement> GetAllElements()
	{
		using var conexion = conexiones.CreateConnection();
		return conexion.Query<string>("dbo.paProteccionLlaveListar", commandType: CommandType.StoredProcedure)
			.Select(XElement.Parse)
			.ToList();
	}

	public void StoreElement(XElement element, string friendlyName)
	{
		using var conexion = conexiones.CreateConnection();
		conexion.Execute("dbo.paProteccionLlaveGuardar",
			new { Nombre = friendlyName, Xml = element.ToString(SaveOptions.DisableFormatting) },
			commandType: CommandType.StoredProcedure);
	}
}
