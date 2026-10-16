using Erp.Data.Caja;

namespace Erp.Web.Components.Shared;

// Forma de pago capturada (efectivo, cheque, tarjeta...) dentro del borrador
// de una factura o un cobro (BorradorDocumento).
public sealed record BorradorFormaPago(int PftId, decimal Monto, int? GefId, string? NumeroTarjetaUlt4, string? FechaVencimientoTarjeta, string? NumeroCheque)
{
	public static BorradorFormaPago De(FormaPagoCaptura f) =>
		new(f.PftId, f.Monto, f.GefId, f.NumeroTarjetaUlt4, f.FechaVencimientoTarjeta, f.NumeroCheque);

	public FormaPagoCaptura Captura() => new()
	{
		PftId = PftId,
		Monto = Monto,
		GefId = GefId,
		NumeroTarjetaUlt4 = NumeroTarjetaUlt4,
		FechaVencimientoTarjeta = FechaVencimientoTarjeta,
		NumeroCheque = NumeroCheque
	};
}
