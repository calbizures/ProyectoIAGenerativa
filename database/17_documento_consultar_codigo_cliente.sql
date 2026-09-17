------------------------------------------------------------------------------
-- 17_documento_consultar_codigo_cliente.sql
--
-- El listado de Facturas (y Compras, que comparte el mismo procedimiento)
-- mostraba la descripción completa del tipo de documento y no traía el
-- nombre del cliente/proveedor. Se agrega tdo_codigo y el nombre de
-- cliente/proveedor al resultado de sp_documento_consultar.
--
-- Seguro de correr una sola vez contra una base ya creada con 00-16.
------------------------------------------------------------------------------

USE [erp_db];
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_documento_consultar]
	@tdo_id			INT = NULL,
	@cli_id			INT = NULL,
	@prv_id			INT = NULL,
	@fecha_desde	DATE = NULL,
	@fecha_hasta	DATE = NULL,
	@enc_estado		CHAR(1) = NULL,
	@pagina			INT = 1,
	@tamanio_pagina	INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT enc.enc_id, enc.enc_fecha_docto, enc.enc_serie_docto, enc.enc_numero_docto,
		   tdo.tdo_codigo, tdo.tdo_descripcion, enc.cli_id, enc.prv_id, enc.enc_monto_total, enc.enc_estado,
		   cli.cli_nombres, cli.cli_apellidos, prv.prv_nombre_comercial
	FROM dbo.inv_documento_enc enc
	INNER JOIN dbo.inv_documento_tipo tdo ON tdo.tdo_id = enc.tdo_id
	LEFT JOIN dbo.pos_cliente cli ON cli.cli_id = enc.cli_id
	LEFT JOIN dbo.inv_proveedor prv ON prv.prv_id = enc.prv_id
	WHERE (@tdo_id IS NULL OR enc.tdo_id = @tdo_id)
	  AND (@cli_id IS NULL OR enc.cli_id = @cli_id)
	  AND (@prv_id IS NULL OR enc.prv_id = @prv_id)
	  AND (@fecha_desde IS NULL OR enc.enc_fecha_docto >= @fecha_desde)
	  AND (@fecha_hasta IS NULL OR enc.enc_fecha_docto <= @fecha_hasta)
	  AND (@enc_estado IS NULL OR enc.enc_estado = @enc_estado)
	ORDER BY enc.enc_fecha_docto DESC, enc.enc_id DESC
	OFFSET (@pagina - 1) * @tamanio_pagina ROWS FETCH NEXT @tamanio_pagina ROWS ONLY;
END;
GO
