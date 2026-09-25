------------------------------------------------------------------------------
-- 23_procedimientos_caja_sucursal.sql
--
-- Procedimientos para:
--   * Sucursales autorizadas por usuario (login).
--   * CRUD de cajas receptoras (antes solo se podían insertar a mano).
--   * Apertura de caja con monto inicial libre; consulta de aperturas
--     activas por sucursal (para el aviso no bloqueante del login y para
--     saber con qué caja operar en Facturas/Cobros).
--   * Corte de caja: cálculo del teórico por forma de pago, captura del
--     conteo físico (efectivo por denominación + demás formas) y cierre
--     con la diferencia teórico-físico.
--   * Depósitos parciales a banco (pos_caja_deposito).
--
-- Usa el estándar de nomenclatura vigente para procedimientos y alias
-- nuevos (pa + PascalCase, alias de 4+ caracteres). sp_pos_caja_abrir y
-- sp_pos_caja_cerrar ya existían con el nombre viejo: se extienden con
-- CREATE OR ALTER sin renombrarlos, tal como con los demás procedimientos
-- ya desplegados.
--
-- Se puede volver a correr sin error sobre una base ya creada con 00-22.
------------------------------------------------------------------------------

USE [erp_db];
GO

------------------------------------------------------------
-- Tipos de tabla nuevos (conteo físico de corte de caja)
------------------------------------------------------------
-- Si el script ya se corrió antes, hay que quitar primero los
-- procedimientos que usan estos tipos (SQL Server no permite DROP TYPE
-- mientras siga en uso); se vuelven a crear más abajo.
DROP PROCEDURE IF EXISTS [dbo].[paCajaDesgloseEfectivoGuardar];
DROP PROCEDURE IF EXISTS [dbo].[paCajaCorteFormaGuardar];
GO

IF TYPE_ID(N'dbo.caja_denominacion_type') IS NOT NULL
	DROP TYPE [dbo].[caja_denominacion_type];
GO
CREATE TYPE [dbo].[caja_denominacion_type] AS TABLE
(
	[def_tipo_denominacion]	CHAR(1)			NOT NULL,	-- B=Billete, M=Moneda
	[def_denominacion]		NUMERIC(12, 2)	NOT NULL,
	[def_cantidad]			NUMERIC(8, 0)	NOT NULL
);
GO

IF TYPE_ID(N'dbo.caja_corte_forma_type') IS NOT NULL
	DROP TYPE [dbo].[caja_corte_forma_type];
GO
CREATE TYPE [dbo].[caja_corte_forma_type] AS TABLE
(
	[pft_id]			INT				NOT NULL,
	[pcf_monto_fisico]	NUMERIC(12, 2)	NOT NULL
);
GO

------------------------------------------------------------
-- Sucursales autorizadas por usuario
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paUsuarioSucursalConsultar]
	@usu_id INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT suc.suc_id, suc.suc_codigo, suc.suc_descripcion
	FROM dbo.sec_usuario_sucursal user_suc
	INNER JOIN dbo.gen_sucursal suc ON suc.suc_id = user_suc.suc_id
	WHERE user_suc.usu_id = @usu_id AND suc.suc_estado = 'A'
	ORDER BY suc.suc_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioSucursalAsignar]
	@usu_id			INT,
	@suc_id			INT,
	@usu_id_accion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.sec_usuario_sucursal WHERE usu_id = @usu_id AND suc_id = @suc_id)
		INSERT INTO dbo.sec_usuario_sucursal (usu_id, suc_id, InsUsuario, InsFechaHora)
		VALUES (@usu_id, @suc_id, @usu_id_accion, SYSDATETIME());
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioSucursalRevocar]
	@usu_id	INT,
	@suc_id	INT
AS
BEGIN
	SET NOCOUNT ON;

	DELETE FROM dbo.sec_usuario_sucursal WHERE usu_id = @usu_id AND suc_id = @suc_id;
END;
GO

------------------------------------------------------------
-- Cajas receptoras (CRUD; antes solo se podían insertar a mano)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCajaReceptoraInsertar]
	@pcr_descripcion	VARCHAR(64),
	@suc_id				INT,
	@usu_id				INT = NULL,
	@pcr_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.pos_caja_receptora WHERE pcr_descripcion = @pcr_descripcion)
		THROW 51901, 'Ya existe una caja receptora con esa descripción.', 1;

	INSERT INTO dbo.pos_caja_receptora (pcr_descripcion, suc_id, pcr_estado, InsUsuario, InsFechaHora)
	VALUES (@pcr_descripcion, @suc_id, 'A', @usu_id, SYSDATETIME());

	SET @pcr_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaReceptoraActualizar]
	@pcr_id				INT,
	@pcr_descripcion	VARCHAR(64),
	@suc_id				INT,
	@usu_id				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_receptora WHERE pcr_id = @pcr_id)
		THROW 51902, 'La caja receptora indicada no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.pos_caja_receptora WHERE pcr_descripcion = @pcr_descripcion AND pcr_id <> @pcr_id)
		THROW 51901, 'Ya existe otra caja receptora con esa descripción.', 1;

	UPDATE dbo.pos_caja_receptora
	   SET pcr_descripcion = @pcr_descripcion,
		   suc_id = @suc_id,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pcr_id = @pcr_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaReceptoraEliminar]
	@pcr_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_receptora WHERE pcr_id = @pcr_id)
		THROW 51902, 'La caja receptora indicada no existe.', 1;

	UPDATE dbo.pos_caja_receptora
	   SET pcr_estado = 'I',
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pcr_id = @pcr_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaReceptoraConsultar]
	@suc_id		INT = NULL,
	@pcr_estado	CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT pcaj.pcr_id, pcaj.pcr_descripcion, pcaj.suc_id, sucu.suc_codigo, sucu.suc_descripcion, pcaj.pcr_estado
	FROM dbo.pos_caja_receptora pcaj
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = pcaj.suc_id
	WHERE (@suc_id IS NULL OR pcaj.suc_id = @suc_id)
	  AND (@pcr_estado IS NULL OR pcaj.pcr_estado = @pcr_estado)
	ORDER BY sucu.suc_descripcion, pcaj.pcr_descripcion;
END;
GO

------------------------------------------------------------
-- Apertura de caja: monto inicial libre
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_pos_caja_abrir]
	@pcr_id				INT,
	@usu_id				INT,
	@pca_monto_inicial	NUMERIC(12, 2) = 0,
	@pca_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pcr_id = @pcr_id AND pca_estado = 'A')
		THROW 51701, 'Ya existe una apertura de caja activa para esta caja receptora. Debe cerrarse antes de abrir una nueva.', 1;

	INSERT INTO dbo.pos_caja_apertura (pcr_id, usu_id_apertura, pca_monto_inicial, InsUsuario, InsFechaHora)
	VALUES (@pcr_id, @usu_id, ISNULL(@pca_monto_inicial, 0), @usu_id, SYSDATETIME());

	SET @pca_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaAperturaConsultarActivaPorSucursal]
	@suc_id INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT apca.pca_id, apca.pca_fecha_apertura, apca.pca_monto_inicial,
		   pcaj.pcr_id, pcaj.pcr_descripcion,
		   usua.usu_usuario AS usuario_apertura
	FROM dbo.pos_caja_apertura apca
	INNER JOIN dbo.pos_caja_receptora pcaj ON pcaj.pcr_id = apca.pcr_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = apca.usu_id_apertura
	WHERE pcaj.suc_id = @suc_id AND apca.pca_estado = 'A'
	ORDER BY pcaj.pcr_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaAperturaConsultar]
	@suc_id			INT = NULL,
	@pca_estado		CHAR(1) = NULL,
	@pagina			INT = 1,
	@tamanio_pagina	INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT apca.pca_id, apca.pca_fecha_apertura, apca.pca_fecha_cierre, apca.pca_estado,
		   apca.pca_monto_inicial, apca.pca_monto_teorico_total, apca.pca_monto_fisico_total, apca.pca_diferencia,
		   pcaj.pcr_id, pcaj.pcr_descripcion, pcaj.suc_id, sucu.suc_descripcion,
		   usua.usu_usuario AS usuario_apertura, usuc.usu_usuario AS usuario_cierre
	FROM dbo.pos_caja_apertura apca
	INNER JOIN dbo.pos_caja_receptora pcaj ON pcaj.pcr_id = apca.pcr_id
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = pcaj.suc_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = apca.usu_id_apertura
	LEFT JOIN dbo.gen_usuario usuc ON usuc.usu_id = apca.usu_id_cierre
	WHERE (@suc_id IS NULL OR pcaj.suc_id = @suc_id)
	  AND (@pca_estado IS NULL OR apca.pca_estado = @pca_estado)
	ORDER BY apca.pca_fecha_apertura DESC
	OFFSET (@pagina - 1) * @tamanio_pagina ROWS FETCH NEXT @tamanio_pagina ROWS ONLY;
END;
GO

------------------------------------------------------------
-- Corte de caja: teórico por forma de pago, conteo físico y cierre
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCorteCajaTeoricoConsultar]
	@pca_id INT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @monto_inicial NUMERIC(12, 2) = (SELECT pca_monto_inicial FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id);

	SELECT tipo.pft_id, tipo.pft_descripcion,
		   ISNULL(cobrado.monto, 0) + CASE WHEN tipo.pft_descripcion = 'Efectivo' THEN ISNULL(@monto_inicial, 0) ELSE 0 END AS monto_teorico
	FROM dbo.pos_pago_forma_tipo tipo
	LEFT JOIN (
		SELECT forma.pft_id, SUM(forma.ppf_monto) AS monto
		FROM dbo.pos_pago_forma forma
		INNER JOIN dbo.pos_pago_enc penc ON penc.ppe_id = forma.ppe_id
		WHERE penc.pca_id = @pca_id
		GROUP BY forma.pft_id
	) cobrado ON cobrado.pft_id = tipo.pft_id
	WHERE tipo.pft_estado = 'A'
	ORDER BY tipo.pft_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaDesgloseEfectivoGuardar]
	@pca_id			INT,
	@denominaciones	dbo.caja_denominacion_type READONLY,
	@usu_id			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id AND pca_estado = 'A')
		THROW 51702, 'La apertura de caja indicada no existe o ya está cerrada.', 1;

	DELETE FROM dbo.pos_caja_desglose_efectivo WHERE pca_id = @pca_id;

	INSERT INTO dbo.pos_caja_desglose_efectivo (def_tipo_denominacion, def_denominacion, def_cantidad, pca_id, InsUsuario, InsFechaHora)
	SELECT def_tipo_denominacion, def_denominacion, def_cantidad, @pca_id, @usu_id, SYSDATETIME()
	FROM @denominaciones
	WHERE def_cantidad > 0;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaCorteFormaGuardar]
	@pca_id	INT,
	@formas	dbo.caja_corte_forma_type READONLY,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id AND pca_estado = 'A')
		THROW 51702, 'La apertura de caja indicada no existe o ya está cerrada.', 1;

	DELETE FROM dbo.pos_caja_corte_forma WHERE pca_id = @pca_id;

	INSERT INTO dbo.pos_caja_corte_forma (pca_id, pft_id, pcf_monto_fisico, InsUsuario, InsFechaHora)
	SELECT @pca_id, pft_id, pcf_monto_fisico, @usu_id, SYSDATETIME()
	FROM @formas;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_pos_caja_cerrar]
	@pca_id	INT,
	@usu_id	INT
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id AND pca_estado = 'A')
		THROW 51702, 'La apertura de caja indicada no existe o ya está cerrada.', 1;

	DECLARE @monto_inicial NUMERIC(12, 2), @teorico_cobrado NUMERIC(12, 2), @fisico_efectivo NUMERIC(12, 2), @fisico_otras_formas NUMERIC(12, 2);

	SELECT @monto_inicial = pca_monto_inicial FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id;

	SELECT @teorico_cobrado = SUM(forma.ppf_monto)
	FROM dbo.pos_pago_forma forma
	INNER JOIN dbo.pos_pago_enc penc ON penc.ppe_id = forma.ppe_id
	WHERE penc.pca_id = @pca_id;

	SELECT @fisico_efectivo = SUM(def_denominacion * def_cantidad)
	FROM dbo.pos_caja_desglose_efectivo
	WHERE pca_id = @pca_id;

	SELECT @fisico_otras_formas = SUM(pcf_monto_fisico)
	FROM dbo.pos_caja_corte_forma
	WHERE pca_id = @pca_id;

	DECLARE @monto_teorico_total NUMERIC(12, 2) = ISNULL(@monto_inicial, 0) + ISNULL(@teorico_cobrado, 0);
	DECLARE @monto_fisico_total NUMERIC(12, 2) = ISNULL(@fisico_efectivo, 0) + ISNULL(@fisico_otras_formas, 0);

	UPDATE dbo.pos_caja_apertura
	   SET pca_estado = 'C',
		   pca_fecha_corte = SYSDATETIME(),
		   pca_fecha_cierre = SYSDATETIME(),
		   usu_id_cierre = @usu_id,
		   pca_monto_teorico_total = @monto_teorico_total,
		   pca_monto_fisico_total = @monto_fisico_total,
		   pca_diferencia = @monto_fisico_total - @monto_teorico_total,
		   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
	 WHERE pca_id = @pca_id;
END;
GO

------------------------------------------------------------
-- Depósitos parciales a banco
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCajaDepositoInsertar]
	@pca_id				INT,
	@gef_id				INT,
	@pcd_fecha_deposito	DATE,
	@pcd_valor_deposito	DECIMAL(14, 2),
	@pcd_numero_boleta	VARCHAR(32) = NULL,
	@pcd_observaciones	VARCHAR(128) = NULL,
	@usu_id				INT = NULL,
	@pcd_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id)
		THROW 51904, 'La apertura de caja indicada no existe.', 1;

	INSERT INTO dbo.pos_caja_deposito
		(pcd_fecha_deposito, pcd_valor_deposito, pcd_numero_boleta, pcd_observaciones, pca_id, gef_id, InsUsuario, InsFechaHora)
	VALUES
		(@pcd_fecha_deposito, @pcd_valor_deposito, @pcd_numero_boleta, @pcd_observaciones, @pca_id, @gef_id, @usu_id, SYSDATETIME());

	SET @pcd_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaDepositoConsultar]
	@pca_id INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	SELECT depo.pcd_id, depo.pcd_fecha_deposito, depo.pcd_valor_deposito, depo.pcd_numero_boleta,
		   depo.pcd_observaciones, depo.pca_id, depo.gef_id, enti.gef_codigo, enti.gef_descripcion
	FROM dbo.pos_caja_deposito depo
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = depo.gef_id
	WHERE (@pca_id IS NULL OR depo.pca_id = @pca_id)
	ORDER BY depo.pcd_fecha_deposito DESC;
END;
GO
