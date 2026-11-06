using System.Security.Cryptography;
using System.Text;

namespace Erp.Data.Security;

// Hash de contraseñas con PBKDF2-HMAC-SHA256 (script 83). La sal son 16 bytes
// aleatorios guardados en usu_password_salt (uniqueidentifier) y las
// iteraciones en usu_password_iteraciones, para poder subirlas con el tiempo:
// un hash con menos iteraciones que las actuales se rehace al iniciar sesión.
public static class ContrasenaHash
{
	public const int Iteraciones = 600_000;
	private const int LargoHash = 32;

	public const string MensajePolitica = "La contraseña debe tener al menos 8 caracteres, con letras y números.";

	public sealed record Resultado(byte[] Hash, Guid Salt, int Iteraciones);

	public static Resultado Calcular(string password)
	{
		var salt = new Guid(RandomNumberGenerator.GetBytes(16));
		return new Resultado(Derivar(password, salt, Iteraciones), salt, Iteraciones);
	}

	public static bool Verificar(string password, byte[] hash, Guid salt, int iteraciones) =>
		CryptographicOperations.FixedTimeEquals(Derivar(password, salt, iteraciones, hash.Length), hash);

	// La misma regla que dbo.fnSeguridadPasswordValido.
	public static bool CumplePolitica(string? password) =>
		password is not null && password.Length >= 8
		&& password.Any(c => c is >= 'a' and <= 'z' or >= 'A' and <= 'Z')
		&& password.Any(char.IsAsciiDigit);

	public static void ValidarPolitica(string? password)
	{
		if (!CumplePolitica(password))
			throw new InvalidOperationException(MensajePolitica);
	}

	private static byte[] Derivar(string password, Guid salt, int iteraciones, int largo = LargoHash) =>
		Rfc2898DeriveBytes.Pbkdf2(Encoding.UTF8.GetBytes(password), salt.ToByteArray(), iteraciones, HashAlgorithmName.SHA256, largo);

	// Para que un usuario que no existe tarde lo mismo que uno que sí.
	private static readonly Guid SaltFicticia = Guid.NewGuid();
	public static void CalcularFicticio(string password) => Derivar(password, SaltFicticia, Iteraciones);
}
