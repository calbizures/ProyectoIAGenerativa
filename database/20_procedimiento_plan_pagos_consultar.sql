------------------------------------------------------------------------------
-- 20_procedimiento_plan_pagos_consultar.sql
--
-- Agrega la consulta del plan de pagos (cuotas) de una factura a crédito
-- (pos_cliente_plan_pagos), que hasta ahora solo se generaba al grabar
-- pero no se podía volver a leer desde el frontend. Se usa para mostrar
-- el plan de pagos como detalle informativo justo al grabar una factura
-- a crédito.
--
-- Usa el estándar de nomenclatura vigente para procedimientos nuevos
-- (pa + PascalCase, ver "Estándares de nomenclatura" en README.md).
--
-- Seguro de correr una sola vez contra una base ya creada con 00-19.
------------------------------------------------------------------------------

USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[paClientePlanPagosConsultar]
	@enc_id INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT cpp_id, cpp_nro_cuota, cpp_valor_cuota, cpp_saldo_cuota,
		   cpp_fecha_maxima_pago, cpp_fecha_real_pago, cpp_estado, enc_id, cli_id
	FROM dbo.pos_cliente_plan_pagos
	WHERE enc_id = @enc_id
	ORDER BY cpp_nro_cuota;
END;
GO
