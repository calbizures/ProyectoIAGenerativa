using Erp.Data.Inventario;
using Erp.Data.Security;
using Microsoft.Extensions.DependencyInjection;

namespace Erp.Data;

public static class DependencyInjection
{
	public static IServiceCollection AddErpData(this IServiceCollection services, string connectionString)
	{
		// Los procedimientos usan columnas snake_case (usu_id, rol_codigo, ...);
		// esto le dice a Dapper que las relacione con propiedades PascalCase
		// (UsuId, RolCodigo, ...) sin tener que mapear cada una a mano.
		Dapper.DefaultTypeMap.MatchNamesWithUnderscores = true;

		services.AddSingleton<IDbConnectionFactory>(_ => new SqlServerConnectionFactory(connectionString));
		services.AddScoped<IUsuarioRepository, UsuarioRepository>();
		services.AddScoped<IRolRepository, RolRepository>();
		services.AddScoped<IPermisoRepository, PermisoRepository>();
		services.AddScoped<IAuthRepository, AuthRepository>();
		services.AddScoped<IProductoRepository, ProductoRepository>();
		return services;
	}
}
