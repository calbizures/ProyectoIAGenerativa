/*
================================================================================
 75_fel_infile_pruebas.sql
 Factura electrónica con el ambiente de pruebas de INFILE por defecto.

   La compañía de demostración (NIT 1234567-9) queda con el certificador
   INFILE activo, en el ambiente PRUEBAS, con los usuarios del emisor de
   pruebas DESARROLLOMODERNO_DEMO:
     usuario de firma   = Alias
     usuario de la API  = Prefijo
   Las URLs de certificación y anulación son las del 35 (INFILE usa la misma
   dirección en pruebas y en producción; las credenciales deciden el ambiente).

   INFILE asigna a ese emisor el NIT 9300000118K. El NIT de la compañía no
   cambia, porque el de pruebas no pasa la validación del dígito verificador:
   la aplicación lo toma de Fel:Credenciales:12345679:NitEmisor (appsettings)
   y es el que va en el XML.

   Las llaves no van en la base ni en el repositorio: se configuran en la
   aplicación (por ejemplo con dotnet user-secrets) como
   Fel:Credenciales:12345679:LlaveFirma (el Token) y :LlaveApi (la Llave).
   Sin llaves o sin conexión con INFILE la factura se graba igual y queda
   Pendiente de certificar; para volver al simulador basta con elegirlo en
   General › Factura electrónica.

   Solo cambia la configuración si sigue como la dejó el 35 (SIMULADOR y sin
   usuarios), así que no pisa una configuración hecha a mano.

 Requiere el 35 y el 44. Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

UPDATE conf
   SET fco_certificador = 'INFILE', fco_activo = 1, fco_ambiente = 'PRUEBAS',
	   fco_url_certificacion = ISNULL(conf.fco_url_certificacion, 'https://certificador.feel.com.gt/fel/procesounificado/transaccion/v2/xml'),
	   fco_url_anulacion = ISNULL(conf.fco_url_anulacion, 'https://certificador.feel.com.gt/fel/procesounificado/transaccion/v2/xml'),
	   fco_usuario_firma = 'DESARROLLOMODERNO_DEMO', fco_usuario_api = 'DESARROLLOMODERNO_DEMO',
	   UpdFechaHora = SYSDATETIME()
FROM dbo.fel_configuracion conf
INNER JOIN dbo.gen_compania comp ON comp.cia_id = conf.cia_id
WHERE dbo.fnNitNormalizar(comp.cia_nit) = '12345679'
  AND conf.fco_certificador = 'SIMULADOR'
  AND conf.fco_usuario_firma IS NULL
  AND conf.fco_usuario_api IS NULL;
GO

PRINT '75_fel_infile_pruebas.sql: compañía de demostración con INFILE (ambiente de pruebas).';
GO
