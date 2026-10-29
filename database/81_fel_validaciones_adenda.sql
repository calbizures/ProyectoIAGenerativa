/*
================================================================================
 81_fel_validaciones_adenda.sql
 Factura electrónica: consumidor final hasta un monto, frase de exención,
 largos de SAT y Adenda con datos internos.

   1. gen_compania.cia_fel_cf_monto_maximo: una factura a Consumidor final
      (CF) por este monto o más no se graba: hay que identificar al comprador
      con NIT o CUI (regla de SAT; por omisión Q2,500.00; NULL = sin límite).
      Se cambia en Factura electrónica › Configuración.
        paFelLimiteCfConsultar / paFelLimiteCfGuardar.
   2. Frase de exención: las frases tipo 4 (exenciones) solo van en el DTE
      cuando tiene líneas exentas, y una factura con líneas exentas exige
      tener configurada una frase tipo 4 (se valida en la aplicación antes
      de enviar al certificador).
   3. Los textos se recortan a los largos del esquema de SAT al armar el XML
      (en la aplicación).
   4. Adenda: número interno, sucursal, vendedor y usuario del documento van
      en <dte:Adenda> (no afecta la validez del DTE).
        paFelAdendaConsultar.

 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('dbo.gen_compania', 'cia_fel_cf_monto_maximo') IS NULL
	ALTER TABLE dbo.gen_compania ADD [cia_fel_cf_monto_maximo] NUMERIC(14, 2) NULL
		CONSTRAINT [DF_gen_compania_fel_cf_monto_maximo] DEFAULT (2500) WITH VALUES
		CONSTRAINT [CK_gen_compania_fel_cf_monto_maximo] CHECK ([cia_fel_cf_monto_maximo] IS NULL OR [cia_fel_cf_monto_maximo] > 0);
GO

CREATE OR ALTER PROCEDURE [dbo].[paFelLimiteCfConsultar]
	@CiaId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cia_fel_cf_monto_maximo AS MontoMaximoCf FROM dbo.gen_compania WHERE cia_id = @CiaId;
END;
GO

-- @MontoMaximoCf NULL: sin límite.
CREATE OR ALTER PROCEDURE [dbo].[paFelLimiteCfGuardar]
	@CiaId			INT,
	@MontoMaximoCf	NUMERIC(14, 2) = NULL,
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @MontoMaximoCf IS NOT NULL AND @MontoMaximoCf <= 0
		THROW 55960, 'El monto máximo para consumidor final debe ser mayor a cero (o vacío, sin límite).', 1;
	UPDATE dbo.gen_compania
	   SET cia_fel_cf_monto_maximo = @MontoMaximoCf, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cia_id = @CiaId;
END;
GO

-- Datos internos del documento para la Adenda del DTE.
CREATE OR ALTER PROCEDURE [dbo].[paFelAdendaConsultar]
	@EncId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT TOP (1)
		   ISNULL(docu.enc_numero_unico, CONCAT(docu.enc_serie_docto, IIF(docu.enc_serie_docto IS NULL, '', '-'), docu.enc_numero_docto)) AS NumeroInterno,
		   sucu.suc_descripcion AS Sucursal,
		   NULLIF(LTRIM(CONCAT(vend.pve_codigo, ' ', vend.pve_nombres, ' ', vend.pve_apellidos)), '') AS Vendedor,
		   usua.usu_usuario AS Usuario
	FROM dbo.inv_documento_enc docu
	LEFT JOIN dbo.pos_vendedor vend ON vend.pve_id = docu.pve_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = docu.usu_id_creacion
	OUTER APPLY (SELECT TOP (1) bode.suc_id FROM dbo.inv_documento_det deta
				 INNER JOIN dbo.inv_bodega bode ON bode.bod_id = deta.bod_id
				 WHERE deta.enc_id = docu.enc_id ORDER BY deta.det_item) linea
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_id = linea.suc_id
	WHERE docu.enc_id = @EncId;
END;
GO
