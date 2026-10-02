------------------------------------------------------------------------------
-- 17_documento_consultar_codigo_cliente.sql
--
-- El listado de Facturas (y Compras, que comparte el mismo procedimiento)
-- mostraba la descripción completa del tipo de documento y no traía el
-- nombre del cliente/proveedor. Se agrega tdo_codigo y el nombre de
-- cliente/proveedor al resultado.
--
-- De paso, se renombra sp_documento_consultar a paDocumentoConsultar y los
-- alias de tabla pasan a 4+ caracteres, siguiendo el estándar de
-- nomenclatura vigente (ver "Estándares de nomenclatura" en README.md).
-- El procedimiento viejo se elimina para no dejar una copia desactualizada
-- (sin estas columnas) dando vueltas; Erp.Data ya llama al nombre nuevo.
--
-- Seguro de correr una sola vez contra una base ya creada con 00-16.
------------------------------------------------------------------------------

USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DROP PROCEDURE IF EXISTS [dbo].[sp_documento_consultar];
GO

CREATE OR ALTER PROCEDURE [dbo].[paDocumentoConsultar]
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

	SELECT enca.enc_id, enca.enc_fecha_docto, enca.enc_serie_docto, enca.enc_numero_docto,
		   tdoc.tdo_codigo, tdoc.tdo_descripcion, enca.cli_id, enca.prv_id, enca.enc_monto_total, enca.enc_estado,
		   clie.cli_nombres, clie.cli_apellidos, prov.prv_nombre_comercial
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tdoc ON tdoc.tdo_id = enca.tdo_id
	LEFT JOIN dbo.pos_cliente clie ON clie.cli_id = enca.cli_id
	LEFT JOIN dbo.inv_proveedor prov ON prov.prv_id = enca.prv_id
	WHERE (@tdo_id IS NULL OR enca.tdo_id = @tdo_id)
	  AND (@cli_id IS NULL OR enca.cli_id = @cli_id)
	  AND (@prv_id IS NULL OR enca.prv_id = @prv_id)
	  AND (@fecha_desde IS NULL OR enca.enc_fecha_docto >= @fecha_desde)
	  AND (@fecha_hasta IS NULL OR enca.enc_fecha_docto <= @fecha_hasta)
	  AND (@enc_estado IS NULL OR enca.enc_estado = @enc_estado)
	ORDER BY enca.enc_fecha_docto DESC, enca.enc_id DESC
	OFFSET (@pagina - 1) * @tamanio_pagina ROWS FETCH NEXT @tamanio_pagina ROWS ONLY;
END;
GO
