using Erp.Data.Security;

namespace Erp.Tests.Unitarias;

public class ContrasenaHashTests
{
	[Fact]
	public void Calcular_y_verificar_la_misma_contrasena()
	{
		var hash = ContrasenaHash.Calcular("Segura#2026");

		Assert.Equal(32, hash.Hash.Length);
		Assert.Equal(ContrasenaHash.Iteraciones, hash.Iteraciones);
		Assert.True(ContrasenaHash.Verificar("Segura#2026", hash.Hash, hash.Salt, hash.Iteraciones));
	}

	[Fact]
	public void Una_contrasena_distinta_no_se_acepta()
	{
		var hash = ContrasenaHash.Calcular("Segura#2026");

		Assert.False(ContrasenaHash.Verificar("segura#2026", hash.Hash, hash.Salt, hash.Iteraciones));
		Assert.False(ContrasenaHash.Verificar("Segura#2027", hash.Hash, hash.Salt, hash.Iteraciones));
	}

	[Fact]
	public void La_misma_contrasena_da_hashes_distintos_por_la_sal()
	{
		var a = ContrasenaHash.Calcular("Segura#2026");
		var b = ContrasenaHash.Calcular("Segura#2026");

		Assert.NotEqual(a.Salt, b.Salt);
		Assert.NotEqual(a.Hash, b.Hash);
	}

	[Fact]
	public void Verifica_con_las_iteraciones_guardadas()
	{
		// Un usuario con un hash de menos iteraciones (antes de subirlas) sigue entrando.
		var salt = Guid.NewGuid();
		var hash = System.Security.Cryptography.Rfc2898DeriveBytes.Pbkdf2(
			System.Text.Encoding.UTF8.GetBytes("Anterior#1"), salt.ToByteArray(), 100_000,
			System.Security.Cryptography.HashAlgorithmName.SHA256, 32);

		Assert.True(ContrasenaHash.Verificar("Anterior#1", hash, salt, 100_000));
		Assert.False(ContrasenaHash.Verificar("Anterior#1", hash, salt, ContrasenaHash.Iteraciones));
	}

	[Theory]
	[InlineData("abc12345", true)]
	[InlineData("Clave2026", true)]
	[InlineData("ñandú#2026", true)]
	[InlineData("abcdefgh", false)]
	[InlineData("12345678", false)]
	[InlineData("abc1234", false)]
	[InlineData("", false)]
	[InlineData(null, false)]
	public void Politica_de_contrasena(string? password, bool esperado)
	{
		Assert.Equal(esperado, ContrasenaHash.CumplePolitica(password));
	}

	[Fact]
	public void La_politica_lanza_un_mensaje_para_el_usuario()
	{
		var error = Assert.Throws<InvalidOperationException>(() => ContrasenaHash.ValidarPolitica("corta"));
		Assert.Equal(ContrasenaHash.MensajePolitica, error.Message);
	}
}
