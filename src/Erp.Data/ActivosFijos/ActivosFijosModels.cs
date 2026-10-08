namespace Erp.Data.ActivosFijos;

public sealed class CategoriaActivo
{
	public int AfcId { get; set; }
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public decimal Porcentaje { get; set; }
	public int CtaIdActivo { get; set; }
	public string? CuentaActivo { get; set; }
	public int? CtaIdDepreciacion { get; set; }
	public string? CuentaDepreciacion { get; set; }
	public int? CtaIdGasto { get; set; }
	public string? CuentaGasto { get; set; }
	public string Estado { get; set; } = "A";
	public int Activos { get; set; }
}

// Estado: A en uso, B dado de baja, V vendido, N anulado (su compra se anuló).
public sealed class ActivoFijo
{
	public int AfaId { get; set; }
	public string Codigo { get; set; } = "";
	public string Descripcion { get; set; } = "";
	public int AfcId { get; set; }
	public string Categoria { get; set; } = "";
	public int SucId { get; set; }
	public string Sucursal { get; set; } = "";
	public int? IdDepartamento { get; set; }
	public string? Departamento { get; set; }
	public string? Responsable { get; set; }
	public string? Serie { get; set; }
	public string? Ubicacion { get; set; }
	public DateTime FechaAdquisicion { get; set; } = DateTime.Today;
	public decimal Costo { get; set; }
	public decimal ValorResidual { get; set; }
	public decimal Porcentaje { get; set; }
	public decimal DepreciacionInicial { get; set; }
	public decimal Acumulada { get; set; }
	public decimal ValorLibros { get; set; }
	public decimal CuotaMensual { get; set; }
	public int? UltimoMes { get; set; }
	public int? EncId { get; set; }
	public string? Documento { get; set; }
	public int? AsiIdAlta { get; set; }
	public string Estado { get; set; } = "A";
	public DateTime? FechaBaja { get; set; }
	public string? MotivoBaja { get; set; }
	public decimal? PrecioVenta { get; set; }
	public int? AsiIdBaja { get; set; }

	// Solo para el alta manual: cuenta contra la que se graba la póliza (null = ya en libros).
	public int? CtaIdContrapartida { get; set; }

	public static string NombreEstado(string estado) => estado switch
	{
		"A" => "En uso",
		"B" => "Dado de baja",
		"V" => "Vendido",
		_ => "Anulado"
	};
}

public sealed class DepreciacionMes
{
	public int Anio { get; set; }
	public int Mes { get; set; }
	public decimal Monto { get; set; }
	public int? AsiId { get; set; }
	public decimal Acumulada { get; set; }
}

public sealed class DepreciacionPrevia
{
	public int AfaId { get; set; }
	public string Codigo { get; set; } = "";
	public string Descripcion { get; set; } = "";
	public string Categoria { get; set; } = "";
	public string? Departamento { get; set; }
	public decimal Monto { get; set; }
}

public sealed class DepreciacionCorrida
{
	public int AdcId { get; set; }
	public int Anio { get; set; }
	public int Mes { get; set; }
	public decimal Total { get; set; }
	public int Activos { get; set; }
	public int? AsiId { get; set; }
	public string Estado { get; set; } = "V";
	public string? Usuario { get; set; }
	public DateTime Grabada { get; set; }
}
