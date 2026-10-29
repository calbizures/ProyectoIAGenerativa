namespace Erp.Data.Conciliacion;

// Estado: B en proceso, C cerrada.
public sealed class ConciliacionBancaria
{
	public int BcnId { get; set; }
	public int BcbId { get; set; }
	public string Cuenta { get; set; } = "";
	public int Anio { get; set; }
	public int Mes { get; set; }
	public DateTime FechaCorte { get; set; }
	public decimal SaldoInicialBanco { get; set; }
	public decimal SaldoBanco { get; set; }
	public string Estado { get; set; } = "B";
	public DateTime? FechaCierre { get; set; }
	public string? CerradaPor { get; set; }
	public int LineasExtracto { get; set; }
	public int Pendientes { get; set; }
}

public sealed class ConciliacionResumen
{
	public int BcnId { get; set; }
	public int BcbId { get; set; }
	public string Cuenta { get; set; } = "";
	public int Anio { get; set; }
	public int Mes { get; set; }
	public DateTime FechaCorte { get; set; }
	public string Estado { get; set; } = "B";
	public decimal SaldoInicialBanco { get; set; }
	public decimal SaldoBanco { get; set; }
	public decimal CreditosExtracto { get; set; }
	public decimal DebitosExtracto { get; set; }
	public decimal DepositosTransito { get; set; }
	public decimal ChequesCirculacion { get; set; }
	public decimal SaldoLibros { get; set; }
	public decimal CreditosNoRegistrados { get; set; }
	public decimal DebitosNoRegistrados { get; set; }
	// Días al corte desde los que un depósito en tránsito o un cheque en
	// circulación se marca para revisar (parámetros de la conciliación).
	public int DiasDeposito { get; set; }
	public int DiasCheque { get; set; }

	public decimal BancoAjustado => SaldoBanco + DepositosTransito - ChequesCirculacion;
	public decimal LibrosAjustado => SaldoLibros + CreditosNoRegistrados - DebitosNoRegistrados;
	public decimal Diferencia => BancoAjustado - LibrosAjustado;
	// Saldo inicial + créditos − débitos del estado de cuenta contra el saldo final.
	public decimal DiferenciaExtracto => SaldoInicialBanco + CreditosExtracto - DebitosExtracto - SaldoBanco;
}

// Forma: A automática, M manual, J ajuste, G en grupo.
public sealed class LineaExtracto
{
	public int BexId { get; set; }
	public DateTime Fecha { get; set; }
	public string? Descripcion { get; set; }
	public string? Referencia { get; set; }
	public decimal Debito { get; set; }
	public decimal Credito { get; set; }
	public int? AsdId { get; set; }
	public string? Forma { get; set; }
	public int? AsiId { get; set; }
	// Emparejada en grupo (varios con uno): el id de la primera línea del grupo.
	public int? Grupo { get; set; }
	// COMISION, INTERES o SIN_CLASIFICAR (por la descripción).
	public string Clase { get; set; } = "SIN_CLASIFICAR";
}

public sealed class LineaLibro
{
	public int AsdId { get; set; }
	public int AsiId { get; set; }
	public DateTime Fecha { get; set; }
	public string Origen { get; set; } = "";
	public string? Descripcion { get; set; }
	public decimal Debe { get; set; }
	public decimal Haber { get; set; }
	public int? BexId { get; set; }
	public bool Conciliado { get; set; }
	public int? Grupo { get; set; }
	// Días al corte y marca de revisión de lo que sigue en tránsito.
	public int Dias { get; set; }
	public bool Revisar { get; set; }
}

public sealed class ConciliacionParametros
{
	public int ToleranciaDias { get; set; } = 5;
	public int DiasDeposito { get; set; } = 3;
	public int DiasCheque { get; set; } = 30;
}

public sealed class ConciliacionDetalle
{
	public ConciliacionResumen Resumen { get; set; } = new();
	public IReadOnlyList<LineaExtracto> Extracto { get; set; } = Array.Empty<LineaExtracto>();
	public IReadOnlyList<LineaLibro> Libros { get; set; } = Array.Empty<LineaLibro>();
}

public sealed class NuevaLineaExtracto
{
	public DateTime Fecha { get; set; }
	public string? Descripcion { get; set; }
	public string? Referencia { get; set; }
	public decimal Debito { get; set; }
	public decimal Credito { get; set; }
}
