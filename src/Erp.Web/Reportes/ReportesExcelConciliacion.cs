using ClosedXML.Excel;
using Erp.Data.Conciliacion;

namespace Erp.Web.Reportes;

public static partial class ReportesExcel
{
	// Conciliación bancaria en tres hojas: Resumen (con fórmulas sobre las
	// diferencias, para que sea auditable), Partidas conciliadas y Diferencias.
	public static byte[] Conciliacion(ConciliacionDetalle detalle, string mes, CompaniaReporte compania)
	{
		var r = detalle.Resumen;
		var subtitulo = L("{0} · {1} · corte al {2:dd/MM/yyyy}", r.Cuenta, mes, r.FechaCorte);
		using var libro = new XLWorkbook();
		var resumen = libro.Worksheets.Add(L("Resumen"));
		var conciliadas = libro.Worksheets.Add(L("Partidas conciliadas"));
		var diferencias = libro.Worksheets.Add(L("Diferencias"));

		// Diferencias: una fila por partida sin conciliar, con su categoría.
		var deposito = L("Depósito en tránsito");
		var cheque = L("Cheque o pago en circulación");
		var credito = L("Crédito del banco sin registrar");
		var debito = L("Débito del banco sin registrar");
		var fila = Encabezado(diferencias, compania, L("Diferencias de la conciliación"), subtitulo);
		fila = Titulos(diferencias, fila, new List<string> { L("Categoría"), L("Fecha"), L("Descripción"), L("Monto"), L("Días al corte"), L("Observación") });
		var inicioDif = fila;
		foreach (var l in detalle.Libros.Where(l => !l.Conciliado))
		{
			diferencias.Cell(fila, 1).Value = l.Debe > 0 ? deposito : cheque;
			diferencias.Cell(fila, 2).Value = l.Fecha;
			diferencias.Cell(fila, 3).Value = $"#{l.AsiId} {l.Descripcion}";
			diferencias.Cell(fila, 4).Value = l.Debe > 0 ? l.Debe : l.Haber;
			diferencias.Cell(fila, 5).Value = l.Dias;
			if (l.Revisar)
				diferencias.Cell(fila, 6).Value = l.Debe > 0
					? L("Revisar: más de {0} días en tránsito", r.DiasDeposito)
					: L("Revisar: más de {0} días sin cobrarse", r.DiasCheque);
			fila++;
		}
		foreach (var l in detalle.Extracto.Where(l => l.AsdId is null))
		{
			diferencias.Cell(fila, 1).Value = l.Credito > 0 ? credito : debito;
			diferencias.Cell(fila, 2).Value = l.Fecha;
			diferencias.Cell(fila, 3).Value = l.Descripcion ?? "";
			diferencias.Cell(fila, 4).Value = l.Credito > 0 ? l.Credito : l.Debito;
			diferencias.Cell(fila, 6).Value = l.Clase switch
			{
				"COMISION" => L("Comisión o cargo del banco"),
				"INTERES" => L("Intereses del banco"),
				_ => L("Sin clasificar: confirmar qué es antes de registrarlo")
			};
			fila++;
		}
		var finDif = Math.Max(fila - 1, inicioDif);
		diferencias.Range(inicioDif, 2, finDif, 2).Style.DateFormat.Format = "dd/MM/yyyy";
		diferencias.Range(inicioDif, 4, finDif, 4).Style.NumberFormat.Format = FormatoMonto;
		diferencias.Columns().AdjustToContents();

		// Partidas conciliadas: banco y libros lado a lado.
		fila = Encabezado(conciliadas, compania, L("Partidas conciliadas"), subtitulo);
		fila = Titulos(conciliadas, fila, new List<string> { L("Fecha banco"), L("Descripción del banco"), L("Monto banco"), L("Fecha libros"), L("Póliza / concepto"), L("Monto libros"), L("Días de diferencia"), L("Forma") });
		var inicioConc = fila;
		var libros = detalle.Libros.ToDictionary(l => l.AsdId);
		foreach (var b in detalle.Extracto.Where(b => b.AsdId is not null && b.Grupo is null))
		{
			conciliadas.Cell(fila, 1).Value = b.Fecha;
			conciliadas.Cell(fila, 2).Value = b.Descripcion ?? "";
			conciliadas.Cell(fila, 3).Value = b.Credito - b.Debito;
			if (libros.TryGetValue(b.AsdId!.Value, out var l))
			{
				conciliadas.Cell(fila, 4).Value = l.Fecha;
				conciliadas.Cell(fila, 5).Value = $"#{l.AsiId} {l.Descripcion}";
				conciliadas.Cell(fila, 6).Value = l.Debe - l.Haber;
				conciliadas.Cell(fila, 7).Value = Math.Abs((b.Fecha - l.Fecha).Days);
			}
			conciliadas.Cell(fila, 8).Value = b.Forma switch { "A" => L("Automática"), "M" => L("Manual"), "J" => L("Ajuste"), _ => "" };
			fila++;
		}
		foreach (var grupo in detalle.Extracto.Where(b => b.Grupo is not null).GroupBy(b => b.Grupo!.Value))
		{
			var forma = L("Grupo {0}", grupo.Key);
			foreach (var b in grupo)
			{
				conciliadas.Cell(fila, 1).Value = b.Fecha;
				conciliadas.Cell(fila, 2).Value = b.Descripcion ?? "";
				conciliadas.Cell(fila, 3).Value = b.Credito - b.Debito;
				conciliadas.Cell(fila, 8).Value = forma;
				fila++;
			}
			foreach (var l in detalle.Libros.Where(l => l.Grupo == grupo.Key))
			{
				conciliadas.Cell(fila, 4).Value = l.Fecha;
				conciliadas.Cell(fila, 5).Value = $"#{l.AsiId} {l.Descripcion}";
				conciliadas.Cell(fila, 6).Value = l.Debe - l.Haber;
				conciliadas.Cell(fila, 8).Value = forma;
				fila++;
			}
		}
		foreach (var l in detalle.Libros.Where(l => l.Conciliado && l.BexId is null))
		{
			conciliadas.Cell(fila, 4).Value = l.Fecha;
			conciliadas.Cell(fila, 5).Value = $"#{l.AsiId} {l.Descripcion}";
			conciliadas.Cell(fila, 6).Value = l.Debe - l.Haber;
			conciliadas.Cell(fila, 8).Value = L("Marcado a mano");
			fila++;
		}
		var finConc = Math.Max(fila - 1, inicioConc);
		conciliadas.Range(inicioConc, 1, finConc, 1).Style.DateFormat.Format = "dd/MM/yyyy";
		conciliadas.Range(inicioConc, 4, finConc, 4).Style.DateFormat.Format = "dd/MM/yyyy";
		conciliadas.Range(inicioConc, 3, finConc, 3).Style.NumberFormat.Format = FormatoMonto;
		conciliadas.Range(inicioConc, 6, finConc, 6).Style.NumberFormat.Format = FormatoMonto;
		conciliadas.Columns().AdjustToContents();

		// Resumen: los ajustes suman las diferencias por categoría.
		fila = Encabezado(resumen, compania, L("Conciliación bancaria"), subtitulo);
		var hojaDif = $"'{diferencias.Name}'";
		string Suma(string categoria) => $"SUMIF({hojaDif}!$A${inicioDif}:$A${finDif},\"{categoria}\",{hojaDif}!$D${inicioDif}:$D${finDif})";
		void Linea(int f, string concepto, object? valor = null, string? formula = null, bool negrita = false)
		{
			resumen.Cell(f, 1).Value = concepto;
			if (formula is not null) resumen.Cell(f, 2).FormulaA1 = formula;
			else if (valor is decimal d) resumen.Cell(f, 2).Value = d;
			resumen.Cell(f, 2).Style.NumberFormat.Format = FormatoMonto;
			if (negrita) resumen.Range(f, 1, f, 2).Style.Font.Bold = true;
		}
		var saldoBanco = fila;
		Linea(fila++, L("Saldo según estado de cuenta del banco"), r.SaldoBanco, negrita: true);
		Linea(fila++, L("(+) Depósitos en tránsito"), formula: Suma(deposito));
		Linea(fila++, L("(−) Cheques y pagos en circulación"), formula: Suma(cheque));
		var bancoAjustado = fila;
		Linea(fila++, L("Saldo según banco ajustado"), formula: $"B{saldoBanco}+B{saldoBanco + 1}-B{saldoBanco + 2}", negrita: true);
		fila++;
		var saldoLibros = fila;
		Linea(fila++, L("Saldo según libros"), r.SaldoLibros, negrita: true);
		Linea(fila++, L("(+) Créditos del banco sin registrar"), formula: Suma(credito));
		Linea(fila++, L("(−) Débitos del banco sin registrar"), formula: Suma(debito));
		var librosAjustado = fila;
		Linea(fila++, L("Saldo según libros ajustado"), formula: $"B{saldoLibros}+B{saldoLibros + 1}-B{saldoLibros + 2}", negrita: true);
		fila++;
		var diferencia = fila;
		Linea(fila++, L("Diferencia"), formula: $"B{bancoAjustado}-B{librosAjustado}", negrita: true);
		resumen.Cell(fila, 1).Value = L("Concilia");
		resumen.Cell(fila, 2).FormulaA1 = $"IF(ABS(B{diferencia})<0.005,\"{L("Sí")}\",\"{L("No")}\")";
		resumen.Range(fila, 1, fila, 2).Style.Font.Bold = true;
		fila += 2;
		resumen.Cell(fila++, 1).Value = L("Estado: {0}", r.Estado == "C" ? L("Cerrada") : L("En proceso"));
		resumen.Cell(fila++, 1).Value = L("Partidas para revisar: {0}", detalle.Libros.Count(l => l.Revisar)
			+ detalle.Extracto.Count(l => l.AsdId is null && l.Clase == "SIN_CLASIFICAR"));
		fila += 2;
		resumen.Cell(fila, 1).Value = L("Elaborado por: ______________________");
		resumen.Cell(fila + 2, 1).Value = L("Revisado por: ______________________");
		resumen.Columns().AdjustToContents();
		return Guardar(libro);
	}
}
