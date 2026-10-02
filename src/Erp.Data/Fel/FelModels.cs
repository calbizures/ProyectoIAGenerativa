namespace Erp.Data.Fel;

// Datos de un documento para armar su DTE (paFelDocumentoDatosConsultar).
public sealed class FelEncabezado
{
	public int EncId { get; set; }
	public string TdoCodigo { get; set; } = "";
	public bool EsNota { get; set; }
	public bool Certifica { get; set; }
	public string? TipoDte { get; set; }
	public DateTime FechaHoraEmision { get; set; }
	public string CodigoMoneda { get; set; } = "GTQ";
	public string? NumeroUnico { get; set; }
	public string EstadoDocumento { get; set; } = "";
	public decimal MontoTotal { get; set; }

	public int CiaId { get; set; }
	public string NitEmisor { get; set; } = "";
	public string NombreEmisor { get; set; } = "";
	public string NombreComercial { get; set; } = "";
	public string AfiliacionIva { get; set; } = "GEN";
	public int? CodigoEstablecimiento { get; set; }
	public string? CorreoEmisor { get; set; }
	public string? DireccionEmisor { get; set; }
	public string CodigoPostalEmisor { get; set; } = "01001";
	public string? MunicipioEmisor { get; set; }
	public string? DepartamentoEmisor { get; set; }
	public string PaisEmisor { get; set; } = "GT";

	public string IdReceptor { get; set; } = "CF";
	public string? TipoEspecial { get; set; }
	public string NombreReceptor { get; set; } = "";
	public string? CorreoReceptor { get; set; }
	public string DireccionReceptor { get; set; } = "Ciudad";
	public string CodigoPostalReceptor { get; set; } = "01001";
	public string MunicipioReceptor { get; set; } = "Guatemala";
	public string DepartamentoReceptor { get; set; } = "Guatemala";
	public string PaisReceptor { get; set; } = "GT";

	public string? MotivoAjuste { get; set; }
	public string? OrigenUuid { get; set; }
	public string? OrigenSerie { get; set; }
	public string? OrigenNumero { get; set; }
	public DateTime? OrigenFechaEmision { get; set; }
	public int? OrigenEncId { get; set; }

	public string? Certificador { get; set; }
	public bool Activo { get; set; }
	public string? Ambiente { get; set; }
	public string? UrlCertificacion { get; set; }
	public string? UrlAnulacion { get; set; }
	public string? UsuarioFirma { get; set; }
	public string? UsuarioApi { get; set; }
	public string? CorreoCopia { get; set; }
	public int TimeoutSegundos { get; set; } = 30;
	public string XmlnsDte { get; set; } = "http://www.sat.gob.gt/dte/fel/0.2.0";
	public string VersionDte { get; set; } = "0.1";

	public string? FelEstado { get; set; }
	public string? FelUuid { get; set; }
	public DateTime? FelFechaCertificacion { get; set; }
	public string? FelTipoDte { get; set; }
	public int FelIntentos { get; set; }
}

public sealed class FelItem
{
	public int NumeroLinea { get; set; }
	public string BienOServicio { get; set; } = "B";
	public decimal Cantidad { get; set; }
	public string UnidadMedida { get; set; } = "UND";
	public string Descripcion { get; set; } = "";
	public decimal PrecioUnitarioNeto { get; set; }
	public decimal SubTotalNeto { get; set; }
	public decimal DescuentoNeto { get; set; }
	public decimal PorcIva { get; set; }
}

public sealed class FelFraseDocumento
{
	public int TipoFrase { get; set; }
	public int CodigoEscenario { get; set; }
	public bool AplicaNotas { get; set; }
}

public sealed class FelAbono
{
	public int NumeroAbono { get; set; }
	public DateTime FechaVencimiento { get; set; }
	public decimal MontoAbono { get; set; }
}

public sealed record FelDocumentoDatos(FelEncabezado Encabezado, IReadOnlyList<FelItem> Items,
	IReadOnlyList<FelFraseDocumento> Frases, IReadOnlyList<FelAbono> Abonos);

// Resultado de una certificación o anulación que se guarda en fel_documento.
public sealed class FelResultado
{
	public int EncId { get; set; }
	public string Operacion { get; set; } = "CERTIFICAR";	// CERTIFICAR | ANULAR
	public bool Exito { get; set; }
	public string Estado { get; set; } = "P";				// P R C A X
	public string TipoDte { get; set; } = "";
	public string Certificador { get; set; } = "";
	public string? Uuid { get; set; }
	public string? Serie { get; set; }
	public string? Numero { get; set; }
	public DateTime? FechaCertificacion { get; set; }
	public string? Mensaje { get; set; }
	public string? XmlEnviado { get; set; }
	public string? XmlCertificado { get; set; }
	public string? Respuesta { get; set; }
	public string? MotivoAnulacion { get; set; }
}

public sealed class FelDocumentoResumen
{
	public int EncId { get; set; }
	public DateTime Fecha { get; set; }
	public string TdoCodigo { get; set; } = "";
	public string Documento { get; set; } = "";
	public string? Cliente { get; set; }
	public decimal Total { get; set; }
	public string EstadoDocumento { get; set; } = "";
	public string FelEstado { get; set; } = "N";
	public string? TipoDte { get; set; }
	public string? Uuid { get; set; }
	public string? Serie { get; set; }
	public string? Numero { get; set; }
	public DateTime? FechaCertificacion { get; set; }
	public string? Mensaje { get; set; }
	public int Intentos { get; set; }
	public DateTime? UltimoIntento { get; set; }
	public string? Certificador { get; set; }
}

public sealed class FelDocumentoDetalle
{
	public int EncId { get; set; }
	public string TipoDte { get; set; } = "";
	public string Estado { get; set; } = "";
	public string Certificador { get; set; } = "";
	public string? Uuid { get; set; }
	public string? Serie { get; set; }
	public string? Numero { get; set; }
	public DateTime? FechaCertificacion { get; set; }
	public string? XmlEnviado { get; set; }
	public string? XmlCertificado { get; set; }
	public string? Mensaje { get; set; }
	public int Intentos { get; set; }
	public string? MotivoAnulacion { get; set; }
	public DateTime? FechaAnulacion { get; set; }
	public string? XmlAnulacion { get; set; }
}

public sealed class FelBitacora
{
	public int FbiId { get; set; }
	public DateTime Fecha { get; set; }
	public string Operacion { get; set; } = "";
	public bool Exito { get; set; }
	public string? Mensaje { get; set; }
	public string? Usuario { get; set; }
}

// Certificador autorizado y su servicio de consulta de NIT (catálogo fel_certificador).
public sealed class FelCertificador
{
	public string Codigo { get; set; } = "";
	public string Nombre { get; set; } = "";
	public string? Nit { get; set; }
	public string? ApiConsultaNit { get; set; }
	public string? Metodo { get; set; }
	public string? UrlPruebas { get; set; }
	public string? UrlProduccion { get; set; }
	public string? Cuerpo { get; set; }
	public string? Encabezado { get; set; }
	public string? CampoNombre { get; set; }
	public bool Implementado { get; set; }
	public string? Documentacion { get; set; }
	public string? Notas { get; set; }
}

// Lo necesario para consultar un NIT con el certificador de la compañía.
public sealed class FelConsultaNitConfiguracion
{
	public int CiaId { get; set; }
	public string NitEmisor { get; set; } = "";
	public string Certificador { get; set; } = "SIMULADOR";
	public string? NombreCertificador { get; set; }
	public bool Activa { get; set; } = true;
	public string Ambiente { get; set; } = "PRUEBAS";
	public string? Url { get; set; }
	public string? Metodo { get; set; }
	public string? Cuerpo { get; set; }
	public string? Encabezado { get; set; }
	public string? CampoNombre { get; set; }
	public bool Implementado { get; set; }
	public string? UsuarioApi { get; set; }
	public int TimeoutSegundos { get; set; } = 30;
	public string? UrlPropia { get; set; }
}

public sealed class FelConfiguracion
{
	public int CiaId { get; set; }
	public string Compania { get; set; } = "";
	public string Nit { get; set; } = "";
	public string AfiliacionIva { get; set; } = "GEN";
	public string? NombreEmisor { get; set; }
	public string? CorreoEmisor { get; set; }
	public string Certificador { get; set; } = "SIMULADOR";
	public bool Activo { get; set; } = true;
	public string Ambiente { get; set; } = "PRUEBAS";
	public string? UrlCertificacion { get; set; }
	public string? UrlAnulacion { get; set; }
	public string? UsuarioFirma { get; set; }
	public string? UsuarioApi { get; set; }
	public string? CorreoCopia { get; set; }
	public int TimeoutSegundos { get; set; } = 30;
	public string XmlnsDte { get; set; } = "http://www.sat.gob.gt/dte/fel/0.2.0";
	public string VersionDte { get; set; } = "0.1";
	public string ReceptorDireccion { get; set; } = "Ciudad";
	public string ReceptorCodigoPostal { get; set; } = "01001";
	public string ReceptorMunicipio { get; set; } = "Guatemala";
	public string ReceptorDepartamento { get; set; } = "Guatemala";
	public string ReceptorPais { get; set; } = "GT";
}

public sealed class FelFrase
{
	public int FfrId { get; set; }
	public int CiaId { get; set; }
	public short TipoFrase { get; set; }
	public short CodigoEscenario { get; set; }
	public string? Descripcion { get; set; }
	public bool AplicaNotas { get; set; }
	public string Estado { get; set; } = "A";
}

public sealed class FelEstablecimiento
{
	public int SucId { get; set; }
	public string SucCodigo { get; set; } = "";
	public string SucDescripcion { get; set; } = "";
	public string? Direccion { get; set; }
	public int? CodigoEstablecimiento { get; set; }
	public string? NombreComercial { get; set; }
	public string? CodigoPostal { get; set; }
	public int? ProvId { get; set; }
	public string? Municipio { get; set; }
	public string? Departamento { get; set; }
	public string? Pais { get; set; }
	public string Estado { get; set; } = "A";
}

public sealed class FelMunicipio
{
	public int ProvId { get; set; }
	public string Municipio { get; set; } = "";
	public string Departamento { get; set; } = "";
	public string Pais { get; set; } = "";
}

public sealed class FelTipoDocumento
{
	public int TdoId { get; set; }
	public string TdoCodigo { get; set; } = "";
	public string TdoDescripcion { get; set; } = "";
	public string Naturaleza { get; set; } = "";
	public bool EsNota { get; set; }
	public string? TipoDte { get; set; }
	public string? TipoDteContado { get; set; }
	public bool Certifica { get; set; }
}

public sealed class FelUnidadMedida
{
	public int UmeId { get; set; }
	public string UmeCodigo { get; set; } = "";
	public string UmeDescripcion { get; set; } = "";
	public string? FelCodigo { get; set; }
	public string Estado { get; set; } = "A";
}
