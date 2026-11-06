using System.Data;
using Microsoft.Data.SqlClient;

namespace Erp.Data;

public interface IDbConnectionFactory
{
	IDbConnection CreateConnection();
}

public sealed class SqlServerConnectionFactory(string connectionString) : IDbConnectionFactory
{
	public IDbConnection CreateConnection() => new SqlConnection(connectionString);
}
