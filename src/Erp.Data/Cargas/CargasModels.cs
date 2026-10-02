namespace Erp.Data.Cargas;

// Mensaje de una carga desde Excel: Fila = fila del archivo (0 = general),
// Tipo E = error (no se graba nada) o A = advertencia.
public sealed class MensajeCarga
{
	public int Fila { get; set; }
	public string Tipo { get; set; } = "E";
	public string Mensaje { get; set; } = "";
	public bool EsError => Tipo == "E";
}

public sealed class ResultadoCarga<TResumen>
{
	public IReadOnlyList<MensajeCarga> Mensajes { get; init; } = Array.Empty<MensajeCarga>();
	public TResumen? Resumen { get; init; }
	public bool TieneErrores => Mensajes.Any(m => m.EsError);
}

// Inventario inicial
public sealed class FilaInventarioInicial
{
	public int Fila { get; set; }
	public string? Sucursal { get; set; }
	public string? Bodega { get; set; }
	public string? Producto { get; set; }
	public string? Descripcion { get; set; }
	public string? Tipo { get; set; }
	public string? Unidad { get; set; }
	public decimal? Cantidad { get; set; }
	public decimal? CostoTotal { get; set; }
	public decimal? PrecioVenta { get; set; }
}

public sealed class ResumenInventarioInicial
{
	public int Filas { get; set; }
	public int ProductosNuevos { get; set; }
	public int Bodegas { get; set; }
	public decimal Cantidad { get; set; }
	public decimal CostoTotal { get; set; }
	public bool Grabado { get; set; }
}

public sealed class CargaInventarioInicial
{
	public int EncId { get; set; }
	public DateTime Fecha { get; set; }
	public string Documento { get; set; } = "";
	public string? Bodega { get; set; }
	public string? Sucursal { get; set; }
	public int Lineas { get; set; }
	public decimal Cantidad { get; set; }
	public decimal Valor { get; set; }
	public string Estado { get; set; } = "G";
	public string? Usuario { get; set; }
	public DateTime FechaGrabado { get; set; }
}

// Saldos iniciales
public sealed class FilaSaldoInicial
{
	public int Fila { get; set; }
	public string? Codigo { get; set; }
	public decimal? Debe { get; set; }
	public decimal? Haber { get; set; }
}

public sealed class ResumenSaldosIniciales
{
	public int Cuentas { get; set; }
	public decimal TotalDebe { get; set; }
	public decimal TotalHaber { get; set; }
	public decimal InventarioPartida { get; set; }
	public decimal InventarioCargado { get; set; }
	public int? AsiId { get; set; }
	public bool Grabado { get; set; }
}

public sealed class CuentaSaldoInicial
{
	public int CtaId { get; set; }
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public string? Tipo { get; set; }
	public string? Naturaleza { get; set; }
	public int Nivel { get; set; }
	public bool AceptaMovimiento { get; set; }
	public decimal? Debe { get; set; }
	public decimal? Haber { get; set; }
}

public sealed class PartidaApertura
{
	public int AsiId { get; set; }
	public DateTime Fecha { get; set; }
	public string? Descripcion { get; set; }
	public string? Usuario { get; set; }
	public DateTime? FechaCreacion { get; set; }
	public decimal TotalDebe { get; set; }
}

public sealed class LineaApertura
{
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public decimal Debe { get; set; }
	public decimal Haber { get; set; }
}

// Empleados
public sealed class FilaEmpleado
{
	public int Fila { get; set; }
	public string? Codigo { get; set; }
	public string? PrimerNombre { get; set; }
	public string? SegundoNombre { get; set; }
	public string? PrimerApellido { get; set; }
	public string? SegundoApellido { get; set; }
	public string? Genero { get; set; }
	public DateTime? FechaNacimiento { get; set; }
	public DateTime? FechaIngreso { get; set; }
	public string? TipoDocumento { get; set; }
	public string? NumeroDocumento { get; set; }
	public string? AfiliacionIGSS { get; set; }
	public string? Nit { get; set; }
	public string? Email { get; set; }
	public string? Direccion { get; set; }
	public string? Plaza { get; set; }
	public decimal? SalarioBase { get; set; }
	public string? TipoNomina { get; set; }
	public string? FormaPago { get; set; }
	public string? Banco { get; set; }
	public string? TipoCuenta { get; set; }
	public string? NumeroCuenta { get; set; }
}

public sealed class ResumenEmpleados
{
	public int Filas { get; set; }
	public int Nuevos { get; set; }
	public int Actualizados { get; set; }
	public bool Grabado { get; set; }
}
