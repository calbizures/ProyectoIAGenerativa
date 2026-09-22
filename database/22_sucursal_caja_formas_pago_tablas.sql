------------------------------------------------------------------------------
-- 22_sucursal_caja_formas_pago_tablas.sql
--
-- Cambios de esquema para: login con sucursal + verificación de permisos por
-- sucursal, apertura de caja con monto inicial libre, depósitos parciales
-- relacionados con la entidad financiera, y formas de pago (efectivo,
-- cheque, tarjeta) tanto en el pago inicial de una factura (contado o
-- enganche de crédito) como en el cobro de cuotas.
--
--   1. pos_caja_receptora ahora se relaciona con gen_sucursal (una sucursal
--      puede tener varias cajas receptoras).
--   2. Tabla nueva sec_usuario_sucursal: qué sucursales tiene autorizadas
--      cada usuario (se usa para validar la sucursal elegida en el login).
--      Se "apadrina" (grandfather) a todos los usuarios activos en todas
--      las sucursales activas, para no romper el acceso de nadie; un
--      administrador puede luego restringirlo desde Usuarios.
--   3. pos_caja_apertura agrega el monto inicial (fondo de caja) y los
--      totales de corte (teórico, físico, diferencia), que se calculan y
--      graban al cerrar el día.
--   4. pos_caja_deposito ahora se relaciona con gen_entidad_financiera
--      (y transitivamente con gen_entidad_financiera_tipo, vía gef_id).
--   5. Tabla nueva pos_caja_corte_forma: conteo físico por forma de pago
--      (cheque, tarjeta, transferencia) al momento del corte de caja; el
--      efectivo se sigue reconciliando con pos_caja_desglose_efectivo, que
--      ya existía.
--   6. pos_pago_forma agrega el monto de esa forma de pago (antes no lo
--      tenía: no se podía saber cuánto correspondía a cada forma cuando un
--      pago se dividía en varias).
--   7. pos_pago_det ahora puede referenciar directamente una factura
--      (enc_id) además de una cuota (cpp_id), para registrar el pago de
--      contado o el enganche de crédito al momento de facturar — antes
--      solo se podía pagar (pos_pago_det) una cuota ya generada, y una
--      factura de contado o el enganche de una de crédito no generan
--      cuota propia (ver sp_pos_generar_plan_pagos_cliente).
--
-- Seguro de correr una sola vez contra una base ya creada con 00-21.
------------------------------------------------------------------------------

USE [erp_db];
GO

------------------------------------------------------------
-- 1. pos_caja_receptora <-> gen_sucursal
------------------------------------------------------------
IF COL_LENGTH('dbo.pos_caja_receptora', 'suc_id') IS NULL
BEGIN
	ALTER TABLE [dbo].[pos_caja_receptora] ADD [suc_id] INT NULL;
END
GO

-- Backfill: las cajas que ya existían (sin sucursal) quedan asignadas a la
-- primera sucursal activa, para no dejar filas inválidas; un administrador
-- puede reasignarlas después desde el mantenimiento de Cajas.
UPDATE [dbo].[pos_caja_receptora]
   SET [suc_id] = (SELECT TOP 1 suc_id FROM dbo.gen_sucursal WHERE suc_estado = 'A' ORDER BY suc_id)
 WHERE [suc_id] IS NULL
   AND EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE suc_estado = 'A');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_receptora WHERE suc_id IS NULL)
   AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.pos_caja_receptora') AND name = 'suc_id' AND is_nullable = 1)
BEGIN
	ALTER TABLE [dbo].[pos_caja_receptora] ALTER COLUMN [suc_id] INT NOT NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_pos_caja_receptora_sucursal')
BEGIN
	ALTER TABLE [dbo].[pos_caja_receptora]
		ADD CONSTRAINT [FK_pos_caja_receptora_sucursal] FOREIGN KEY([suc_id]) REFERENCES [dbo].[gen_sucursal]([suc_id]);
END
GO

CREATE INDEX [IX_pos_caja_receptora_suc_id] ON [dbo].[pos_caja_receptora]([suc_id]);
GO

------------------------------------------------------------
-- 2. Sucursales autorizadas por usuario (para el login)
------------------------------------------------------------
CREATE TABLE [dbo].[sec_usuario_sucursal](
	[usu_id]		INT				NOT NULL,
	[suc_id]		INT				NOT NULL,
	[InsUsuario]	INT				NULL,
	[InsFechaHora]	DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]	INT				NULL,
	[UpdFechaHora]	DATETIME2(0)	NULL,
	CONSTRAINT [PK_sec_usuario_sucursal] PRIMARY KEY CLUSTERED ([usu_id] ASC, [suc_id] ASC),
	CONSTRAINT [FK_sec_usuario_sucursal_usuario] FOREIGN KEY([usu_id]) REFERENCES [dbo].[gen_usuario]([usu_id]),
	CONSTRAINT [FK_sec_usuario_sucursal_sucursal] FOREIGN KEY([suc_id]) REFERENCES [dbo].[gen_sucursal]([suc_id])
);
GO

-- Apadrina a todos los usuarios activos en todas las sucursales activas,
-- para que nadie quede bloqueado del login el día que se activa este
-- control; un administrador ajusta después los accesos reales desde
-- Usuarios > Sucursales asignadas.
INSERT INTO dbo.sec_usuario_sucursal (usu_id, suc_id, InsFechaHora)
SELECT u.usu_id, s.suc_id, SYSDATETIME()
FROM dbo.gen_usuario u
CROSS JOIN dbo.gen_sucursal s
WHERE u.usu_estado = 'A' AND s.suc_estado = 'A'
  AND NOT EXISTS (
	SELECT 1 FROM dbo.sec_usuario_sucursal us WHERE us.usu_id = u.usu_id AND us.suc_id = s.suc_id
  );
GO

------------------------------------------------------------
-- 3. pos_caja_apertura: monto inicial y totales de corte
------------------------------------------------------------
IF COL_LENGTH('dbo.pos_caja_apertura', 'pca_monto_inicial') IS NULL
	ALTER TABLE [dbo].[pos_caja_apertura] ADD [pca_monto_inicial] NUMERIC(12, 2) NOT NULL DEFAULT (0);
GO

IF COL_LENGTH('dbo.pos_caja_apertura', 'pca_monto_teorico_total') IS NULL
	ALTER TABLE [dbo].[pos_caja_apertura] ADD [pca_monto_teorico_total] NUMERIC(12, 2) NULL;
GO

IF COL_LENGTH('dbo.pos_caja_apertura', 'pca_monto_fisico_total') IS NULL
	ALTER TABLE [dbo].[pos_caja_apertura] ADD [pca_monto_fisico_total] NUMERIC(12, 2) NULL;
GO

IF COL_LENGTH('dbo.pos_caja_apertura', 'pca_diferencia') IS NULL
	ALTER TABLE [dbo].[pos_caja_apertura] ADD [pca_diferencia] NUMERIC(12, 2) NULL;
GO

------------------------------------------------------------
-- 4. pos_caja_deposito <-> gen_entidad_financiera
------------------------------------------------------------
IF COL_LENGTH('dbo.pos_caja_deposito', 'gef_id') IS NULL
	ALTER TABLE [dbo].[pos_caja_deposito] ADD [gef_id] INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_pos_caja_deposito_entidad')
BEGIN
	ALTER TABLE [dbo].[pos_caja_deposito]
		ADD CONSTRAINT [FK_pos_caja_deposito_entidad] FOREIGN KEY([gef_id]) REFERENCES [dbo].[gen_entidad_financiera]([gef_id]);
END
GO

CREATE INDEX [IX_pos_caja_deposito_gef_id] ON [dbo].[pos_caja_deposito]([gef_id]);
GO

------------------------------------------------------------
-- 5. Corte de caja: conteo físico por forma de pago (no efectivo)
--    El efectivo se reconcilia con pos_caja_desglose_efectivo, que ya
--    existía (billete/moneda x cantidad).
------------------------------------------------------------
CREATE TABLE [dbo].[pos_caja_corte_forma](
	[pcf_id]			INT				IDENTITY(1,1)	NOT NULL,
	[pca_id]			INT				NOT NULL,
	[pft_id]			INT				NOT NULL,
	[pcf_monto_fisico]	NUMERIC(12, 2)	NOT NULL DEFAULT (0),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_pos_caja_corte_forma] PRIMARY KEY CLUSTERED ([pcf_id] ASC),
	CONSTRAINT [UQ_pos_caja_corte_forma] UNIQUE ([pca_id], [pft_id]),
	CONSTRAINT [FK_pos_caja_corte_forma_apertura] FOREIGN KEY([pca_id]) REFERENCES [dbo].[pos_caja_apertura]([pca_id]),
	CONSTRAINT [FK_pos_caja_corte_forma_tipo] FOREIGN KEY([pft_id]) REFERENCES [dbo].[pos_pago_forma_tipo]([pft_id]),
	CONSTRAINT [CK_pos_caja_corte_forma_monto] CHECK ([pcf_monto_fisico] >= 0)
);
GO

------------------------------------------------------------
-- 6. pos_pago_forma: monto de esa forma de pago
------------------------------------------------------------
IF COL_LENGTH('dbo.pos_pago_forma', 'ppf_monto') IS NULL
	ALTER TABLE [dbo].[pos_pago_forma] ADD [ppf_monto] NUMERIC(12, 2) NOT NULL DEFAULT (0);
GO

------------------------------------------------------------
-- 7. pos_pago_det: puede referenciar una cuota (cpp_id, como antes) o
--    directamente una factura (enc_id, nuevo: pago de contado o enganche).
------------------------------------------------------------
IF COL_LENGTH('dbo.pos_pago_det', 'enc_id') IS NULL
	ALTER TABLE [dbo].[pos_pago_det] ADD [enc_id] INT NULL;
GO

-- cpp_id era NOT NULL; se vuelve opcional para permitir pagos ligados a
-- enc_id en su lugar. Las filas existentes ya tienen cpp_id, así que este
-- ALTER no las afecta.
ALTER TABLE [dbo].[pos_pago_det] ALTER COLUMN [cpp_id] INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_pos_pago_det_referencia')
BEGIN
	ALTER TABLE [dbo].[pos_pago_det]
		ADD CONSTRAINT [CK_pos_pago_det_referencia]
		CHECK (([cpp_id] IS NOT NULL AND [enc_id] IS NULL) OR ([cpp_id] IS NULL AND [enc_id] IS NOT NULL));
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_pos_pago_det_documento')
BEGIN
	ALTER TABLE [dbo].[pos_pago_det]
		ADD CONSTRAINT [FK_pos_pago_det_documento] FOREIGN KEY([enc_id]) REFERENCES [dbo].[inv_documento_enc]([enc_id]);
END
GO

CREATE INDEX [IX_pos_pago_det_enc_id] ON [dbo].[pos_pago_det]([enc_id]);
GO
