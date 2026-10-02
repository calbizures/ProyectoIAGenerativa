/*
================================================================================
 48_impresion_factura.sql
 Impresión de la factura (representación gráfica del DTE) en impresora
 térmica o en papel carta, según la compañía.

   1. gen_compania:
        cia_factura_impresora   'C' carta (impresora de tinta o láser, p. ej.
                                Epson L3250) o 'T' térmica (rollo).
        cia_factura_ancho_termica  ancho del rollo: 80 o 58 mm.
        cia_factura_pie         texto al pie (p. ej. "Gracias por su compra";
                                política de cambios).
      paCompaniaImpresionConsultar / paCompaniaImpresionGuardar.
   2. paFacturaImpresionConsultar: todo lo que lleva el impreso en cinco
      resultados: encabezado (emisor, establecimiento, receptor, datos FEL,
      condición, vendedor, cajero, formato), detalle con precios con IVA,
      frases FEL, cuotas del crédito y formas de pago.

 Requiere 35 (FEL). Errores 54001-54003. Se puede volver a correr.
================================================================================
*/
USE [erp_db];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Formato de impresión por compañía
------------------------------------------------------------
IF COL_LENGTH('dbo.gen_compania', 'cia_factura_impresora') IS NULL
	ALTER TABLE dbo.gen_compania ADD [cia_factura_impresora] CHAR(1) NOT NULL
		CONSTRAINT [DF_gen_compania_factura_impresora] DEFAULT ('C');
IF COL_LENGTH('dbo.gen_compania', 'cia_factura_ancho_termica') IS NULL
	ALTER TABLE dbo.gen_compania ADD [cia_factura_ancho_termica] TINYINT NOT NULL
		CONSTRAINT [DF_gen_compania_factura_ancho] DEFAULT (80);
IF COL_LENGTH('dbo.gen_compania', 'cia_factura_pie') IS NULL
	ALTER TABLE dbo.gen_compania ADD [cia_factura_pie] VARCHAR(256) NULL;
GO
IF OBJECT_ID('dbo.CK_gen_compania_factura_impresora', 'C') IS NULL
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [CK_gen_compania_factura_impresora] CHECK ([cia_factura_impresora] IN ('C', 'T'));
IF OBJECT_ID('dbo.CK_gen_compania_factura_ancho', 'C') IS NULL
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [CK_gen_compania_factura_ancho] CHECK ([cia_factura_ancho_termica] IN (58, 80));
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaImpresionConsultar]
	@CiaId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cia_id AS CiaId, cia_factura_impresora AS Impresora, cia_factura_ancho_termica AS AnchoTermica, cia_factura_pie AS Pie
	FROM dbo.gen_compania
	WHERE cia_id = @CiaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaImpresionGuardar]
	@CiaId			INT,
	@Impresora		CHAR(1),
	@AnchoTermica	TINYINT = 80,
	@Pie			VARCHAR(256) = NULL,
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_id = @CiaId)
		THROW 54001, 'La compañía no existe.', 1;
	IF ISNULL(@Impresora, '') NOT IN ('C', 'T')
		THROW 54002, 'Elija la impresora de la factura: C (carta) o T (térmica).', 1;
	IF ISNULL(@AnchoTermica, 0) NOT IN (58, 80)
		THROW 54003, 'El ancho del rollo de la impresora térmica debe ser 58 u 80 mm.', 1;
	UPDATE dbo.gen_compania
	   SET cia_factura_impresora = @Impresora, cia_factura_ancho_termica = @AnchoTermica,
		   cia_factura_pie = NULLIF(LTRIM(RTRIM(@Pie)), ''), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cia_id = @CiaId;
END;
GO

------------------------------------------------------------
-- 2. Datos de la factura para imprimir
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paFacturaImpresionConsultar]
	@EncId	INT
AS
BEGIN
	SET NOCOUNT ON;

	-- Establecimiento: la sucursal de la bodega de la primera línea (igual que
	-- el XML del DTE).
	DECLARE @suc_id INT = (SELECT TOP 1 bode.suc_id FROM dbo.inv_documento_det deta
						   INNER JOIN dbo.inv_bodega bode ON bode.bod_id = deta.bod_id
						   WHERE deta.enc_id = @EncId ORDER BY deta.det_item);
	IF @suc_id IS NULL
		SET @suc_id = (SELECT TOP 1 suc_id FROM dbo.gen_sucursal ORDER BY suc_id);

	DECLARE @es_credito BIT = CASE WHEN EXISTS (SELECT 1 FROM dbo.pos_cliente_plan_pagos WHERE enc_id = @EncId) THEN 1 ELSE 0 END;

	-- 1. Encabezado
	SELECT docu.enc_id AS EncId, tipo.tdo_codigo AS TdoCodigo, tipo.tdo_descripcion AS TdoDescripcion, tipo.tdo_es_nota AS EsNota,
		   CASE WHEN tipo.tdo_fel_tipo_dte_contado IS NOT NULL AND @es_credito = 0 THEN tipo.tdo_fel_tipo_dte_contado
				ELSE tipo.tdo_fel_tipo_dte END AS TipoDte,
		   docu.enc_numero_unico AS NumeroUnico, docu.enc_serie_docto AS SerieInterna, docu.enc_numero_docto AS NumeroInterno,
		   DATEADD(SECOND, DATEDIFF(SECOND, CAST(docu.enc_fecha_grabado AS DATE), docu.enc_fecha_grabado),
				   CAST(docu.enc_fecha_docto AS DATETIME2(0))) AS FechaEmision,
		   docu.enc_estado AS Estado, docu.enc_motivo AS Motivo,
		   ISNULL(mone.mon_codigo, 'GTQ') AS Moneda, ISNULL(mone.mon_simbolo, 'Q') AS Simbolo,
		   docu.enc_monto_total AS Total,
		   ISNULL((SELECT SUM(ROUND((deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) * ISNULL(deta.det_porc_iva, 0) / 100.0, 2))
				   FROM dbo.inv_documento_det deta WHERE deta.enc_id = docu.enc_id), 0) AS Iva,
		   ISNULL((SELECT SUM(ROUND(ISNULL(deta.det_valor_descuento, 0) * (1 + ISNULL(deta.det_porc_iva, 0) / 100.0), 2))
				   FROM dbo.inv_documento_det deta WHERE deta.enc_id = docu.enc_id), 0) AS Descuento,
		   @es_credito AS EsCredito, docu.enc_monto_enganche AS Enganche, docu.enc_numero_cuotas AS NumeroCuotas,
		   -- Emisor y establecimiento
		   comp.cia_id AS CiaId, comp.cia_nit AS NitEmisor, ISNULL(comp.cia_fel_nombre_emisor, comp.cia_nombre_comercial) AS NombreEmisor,
		   ISNULL(sucu.suc_fel_nombre_comercial, comp.cia_nombre_comercial) AS NombreComercial,
		   ISNULL(sucu.suc_direccion, comp.cia_direccion) AS DireccionEmisor, muni.prov_nombre AS MunicipioEmisor, depa.est_nombre AS DepartamentoEmisor,
		   ISNULL(sucu.suc_telefono, comp.cia_telefono) AS TelefonoEmisor, ISNULL(comp.cia_fel_correo_emisor, comp.cia_email) AS CorreoEmisor,
		   comp.cia_fel_afiliacion_iva AS AfiliacionIva, sucu.suc_descripcion AS Sucursal, sucu.suc_fel_codigo_establecimiento AS CodigoEstablecimiento,
		   CAST(CASE WHEN comp.cia_logo IS NULL THEN 0 ELSE 1 END AS BIT) AS TieneLogo, comp.cia_logo_actualizado AS LogoActualizado,
		   -- Receptor
		   ISNULL(NULLIF(LTRIM(RTRIM(ISNULL(docu.cli_nit, clie.cli_nit))), ''), 'CF') AS NitReceptor,
		   LTRIM(RTRIM(CONCAT(ISNULL(docu.enc_nombres_cliente, clie.cli_nombres), ' ', ISNULL(docu.enc_apellidos_cliente, clie.cli_apellidos)))) AS NombreReceptor,
		   COALESCE(NULLIF(docu.enc_direccion_cliente, ''), NULLIF(clie.cli_direccion, ''), 'Ciudad') AS DireccionReceptor,
		   clie.cli_codigo AS ClienteCodigo,
		   -- Vendedor y cajero
		   NULLIF(LTRIM(RTRIM(CONCAT(vend.pve_nombres, ' ', vend.pve_apellidos))), '') AS Vendedor, usua.usu_usuario AS Usuario,
		   -- Factura electrónica
		   feld.fdo_estado AS FelEstado, feld.fdo_uuid AS Uuid, feld.fdo_serie AS SerieDte, feld.fdo_numero AS NumeroDte,
		   feld.fdo_fecha_certificacion AS FechaCertificacion, feld.fdo_certificador AS Certificador, feld.fdo_xml_certificado AS XmlCertificado,
		   feld.fdo_fecha_anulacion AS FechaAnulacionDte,
		   -- Referencia de una nota
		   refe.enc_numero_unico AS OrigenNumeroUnico, orig.fdo_uuid AS OrigenUuid, orig.fdo_serie AS OrigenSerie, orig.fdo_numero AS OrigenNumero,
		   -- Formato
		   comp.cia_factura_impresora AS Impresora, comp.cia_factura_ancho_termica AS AnchoTermica, comp.cia_factura_pie AS Pie
	FROM dbo.inv_documento_enc docu
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = @suc_id
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	LEFT JOIN dbo.gen_moneda mone ON mone.mon_id = docu.mon_id
	LEFT JOIN dbo.gen_provincia muni ON muni.prov_id = sucu.prov_id
	LEFT JOIN dbo.gen_estado depa ON depa.est_id = muni.est_id
	LEFT JOIN dbo.pos_cliente clie ON clie.cli_id = docu.cli_id
	LEFT JOIN dbo.pos_vendedor vend ON vend.pve_id = docu.pve_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = ISNULL(docu.usu_id_creacion, docu.InsUsuario)
	LEFT JOIN dbo.fel_documento feld ON feld.enc_id = docu.enc_id
	LEFT JOIN dbo.inv_documento_enc refe ON refe.enc_id = docu.enc_id_referencia
	LEFT JOIN dbo.fel_documento orig ON orig.enc_id = docu.enc_id_referencia
	WHERE docu.enc_id = @EncId;

	-- 2. Detalle con precios con IVA (como se vende al público)
	SELECT deta.det_item AS Linea, deta.det_bien_o_servicio AS BienOServicio, deta.det_cantidad AS Cantidad,
		   ISNULL(unid.ume_codigo, 'UND') AS Unidad, deta.det_descripcion AS Descripcion, prod.pro_codigo AS Codigo,
		   ROUND(deta.det_precio_unitario * (1 + ISNULL(deta.det_porc_iva, 0) / 100.0), 2) AS PrecioUnitario,
		   ROUND(ISNULL(deta.det_valor_descuento, 0) * (1 + ISNULL(deta.det_porc_iva, 0) / 100.0), 2) AS Descuento,
		   ROUND((deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) * (1 + ISNULL(deta.det_porc_iva, 0) / 100.0), 2) AS Total
	FROM dbo.inv_documento_det deta
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = deta.ume_id
	LEFT JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
	WHERE deta.enc_id = @EncId
	ORDER BY deta.det_item;

	-- 3. Frases del emisor (SAT)
	SELECT frase.ffr_tipo_frase AS TipoFrase, frase.ffr_codigo_escenario AS Escenario, frase.ffr_descripcion AS Texto
	FROM dbo.fel_frase frase
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = @EncId
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	WHERE frase.ffr_estado = 'A'
	  AND frase.cia_id = (SELECT sucu.cia_id FROM dbo.gen_sucursal sucu WHERE sucu.suc_id = @suc_id)
	  AND (tipo.tdo_es_nota = 0 OR frase.ffr_aplica_notas = 1)
	ORDER BY frase.ffr_tipo_frase, frase.ffr_codigo_escenario;

	-- 4. Cuotas del crédito
	SELECT cuot.cpp_nro_cuota AS Cuota, cuot.cpp_fecha_maxima_pago AS Vencimiento, cuot.cpp_valor_cuota AS Monto
	FROM dbo.pos_cliente_plan_pagos cuot
	WHERE cuot.enc_id = @EncId
	ORDER BY cuot.cpp_nro_cuota;

	-- 5. Formas de pago recibidas al facturar (contado o enganche)
	SELECT tipo.pft_descripcion AS Forma, SUM(form.ppf_monto) AS Monto,
		   MAX(CASE WHEN form.ppf_numero_cheque IS NOT NULL THEN CONCAT('Cheque ', form.ppf_numero_cheque)
					WHEN form.ppf_numero_tarjeta_ult4 IS NOT NULL THEN CONCAT('Tarjeta ****', form.ppf_numero_tarjeta_ult4) END) AS Referencia
	FROM dbo.pos_pago_forma form
	INNER JOIN dbo.pos_pago_forma_tipo tipo ON tipo.pft_id = form.pft_id
	INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = form.ppe_id AND ISNULL(pago.ppe_estado, 'A') <> 'N'
	WHERE form.ppe_id IN (SELECT DISTINCT pdet.ppe_id FROM dbo.pos_pago_det pdet WHERE pdet.enc_id = @EncId AND pdet.cpp_id IS NULL)
	GROUP BY tipo.pft_descripcion
	ORDER BY tipo.pft_descripcion;
END;
GO

PRINT '48_impresion_factura.sql aplicado.';
GO
