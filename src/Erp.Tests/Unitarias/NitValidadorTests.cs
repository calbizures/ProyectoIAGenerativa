using Erp.Data.General;

namespace Erp.Tests.Unitarias;

public class NitValidadorTests
{
	private static readonly char[] Verificadores = "0123456789K".ToCharArray();

	[Theory]
	[InlineData("123456")]
	[InlineData("576937")]
	[InlineData("1")]
	[InlineData("99999999")]
	public void Un_solo_digito_verificador_es_valido(string cuerpo)
	{
		var validos = Verificadores.Where(v => NitValidador.EsValido(cuerpo + v)).ToList();
		Assert.Single(validos);
	}

	[Fact]
	public void El_verificador_K_se_acepta_en_minuscula_y_con_guion()
	{
		// 12345678: suma = 8·2+7·3+6·4+5·5+4·6+3·7+2·8+1·9 = 156; 11 - 156 % 11 = 9.
		Assert.True(NitValidador.EsValido("12345678-9"));
		// Un cuerpo cuyo verificador es K (11 - suma % 11 = 10).
		var cuerpo = Enumerable.Range(100000, 1000).Select(n => n.ToString())
			.First(c => NitValidador.EsValido(c + "K"));
		Assert.True(NitValidador.EsValido($"{cuerpo}-k"));
		Assert.Equal($"{cuerpo}-K", NitValidador.Formatear($"{cuerpo}k"));
	}

	[Theory]
	[InlineData("CF")]
	[InlineData("c/f")]
	[InlineData(" C F ")]
	[InlineData("")]
	[InlineData(null)]
	public void Consumidor_final_o_vacio_es_valido(string? nit)
	{
		Assert.True(NitValidador.EsValido(nit));
	}

	[Theory]
	[InlineData("ABC")]
	[InlineData("12A4567")]
	[InlineData("1234567-X")]
	public void Texto_que_no_es_NIT_no_es_valido(string nit)
	{
		Assert.False(NitValidador.EsValido(nit));
	}

	[Theory]
	[InlineData("1234567890123")]	// departamento 01, municipio 23: Guatemala tiene 17
	[InlineData("1234567892301")]	// departamento 23 no existe
	[InlineData("1234567890100")]	// municipio 00
	public void CUI_con_departamento_o_municipio_inexistente_no_es_valido(string cui)
	{
		Assert.False(NitValidador.EsCuiValido(cui));
	}

	[Fact]
	public void Un_solo_verificador_de_CUI_es_valido()
	{
		// Correlativo 12345678, departamento 01 (Guatemala), municipio 01.
		var validos = Enumerable.Range(0, 10).Where(v => NitValidador.EsCuiValido($"12345678{v}0101")).ToList();
		Assert.Single(validos);
		Assert.True(NitValidador.EsCui($"12345678{validos[0]}0101"));
	}
}
