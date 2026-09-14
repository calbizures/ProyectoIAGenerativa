/*
	Script 05: Módulo de contabilidad (nuevo).

	Provee un catálogo de cuentas, períodos contables y un libro de asientos
	(partida doble) donde se registran automáticamente las ventas, compras
	y pagos (ver 11_procedimientos_procesos.sql), o manualmente cuando se
	necesite.

	Regla de integridad: todo asiento debe quedar balanceado (suma de Debe =
	suma de Haber). Esto se garantiza con un trigger sobre [cont_asiento_det]
	en vez de un CHECK (un CHECK no puede sumar varias filas). Por eso el
	detalle de un asiento SIEMPRE debe insertarse en una sola sentencia
	(un solo INSERT con todas las líneas, tal como hacen los procedimientos
	de negocio) y no línea por línea.

	Todas las tablas agregan además [InsUsuario]/[InsFechaHora]/[UpdUsuario]/
	[UpdFechaHora] (ver el comentario de cabecera de 02_tablas_generales_seguridad.sql
	para la convención completa). En [cont_asiento_enc] esto es adicional a
	[usu_id]/[asi_fecha_creacion], que ya existían con el mismo fin y se
	conservan por compatibilidad.
*/
USE [erp_db];
GO

CREATE TABLE [dbo].[cont_cuenta_contable](
	[cta_id]				INT				IDENTITY(1,1)	NOT NULL,
	[cta_codigo]			VARCHAR(20)		NOT NULL,
	[cta_nombre]			VARCHAR(128)	NOT NULL,
	[cta_tipo]				CHAR(1)			NOT NULL,	-- A=Activo, P=Pasivo, K=Patrimonio, I=Ingreso, G=Gasto
	[cta_naturaleza]		CHAR(1)			NOT NULL,	-- D=Deudora, H=Acreedora
	[cta_acepta_movimiento]	BIT				NOT NULL DEFAULT (1),	-- 0 = cuenta de agrupación (no recibe partidas)
	[cta_id_padre]			INT				NULL,
	[cta_nivel]				INT				NOT NULL DEFAULT (1),
	[cta_estado]			CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_cont_cuenta_contable] PRIMARY KEY CLUSTERED ([cta_id] ASC),
	CONSTRAINT [UQ_cont_cuenta_contable_codigo] UNIQUE ([cta_codigo]),
	CONSTRAINT [CK_cont_cuenta_contable_tipo] CHECK ([cta_tipo] IN ('A','P','K','I','G')),
	CONSTRAINT [CK_cont_cuenta_contable_naturaleza] CHECK ([cta_naturaleza] IN ('D','H')),
	CONSTRAINT [CK_cont_cuenta_contable_estado] CHECK ([cta_estado] IN ('A','I'))
);
GO
-- Autorreferencia para armar el árbol de cuentas (grupo -> subgrupo -> cuenta).
ALTER TABLE [dbo].[cont_cuenta_contable]
	ADD CONSTRAINT [FK_cont_cuenta_contable_padre] FOREIGN KEY ([cta_id_padre])
	REFERENCES [dbo].[cont_cuenta_contable] ([cta_id]);
GO

CREATE TABLE [dbo].[cont_periodo_contable](
	[pdo_id]		INT				IDENTITY(1,1)	NOT NULL,
	[pdo_anio]		INT				NOT NULL,
	[pdo_mes]		INT				NOT NULL,
	[pdo_estado]	CHAR(1)			NOT NULL DEFAULT ('A'),	-- A=Abierto, C=Cerrado
	[InsUsuario]	INT				NULL,
	[InsFechaHora]	DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]	INT				NULL,
	[UpdFechaHora]	DATETIME2(0)	NULL,
	CONSTRAINT [PK_cont_periodo_contable] PRIMARY KEY CLUSTERED ([pdo_id] ASC),
	CONSTRAINT [UQ_cont_periodo_contable] UNIQUE ([pdo_anio], [pdo_mes]),
	CONSTRAINT [CK_cont_periodo_contable_mes] CHECK ([pdo_mes] BETWEEN 1 AND 12),
	CONSTRAINT [CK_cont_periodo_contable_estado] CHECK ([pdo_estado] IN ('A','C'))
);
GO

CREATE TABLE [dbo].[cont_asiento_enc](
	[asi_id]				INT				IDENTITY(1,1)	NOT NULL,
	[asi_fecha]				DATE			NOT NULL DEFAULT (CAST(GETDATE() AS DATE)),
	[asi_descripcion]		VARCHAR(256)	NULL,
	[asi_origen]			VARCHAR(20)		NOT NULL DEFAULT ('MANUAL'),	-- MANUAL, VENTA, COMPRA, PAGO_CLIENTE, PAGO_PROVEEDOR
	[enc_id]				INT				NULL,	-- documento de inventario que originó el asiento, si aplica
	[pdo_id]				INT				NOT NULL,
	[usu_id]				INT				NULL,
	[asi_fecha_creacion]	DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[asi_estado]			CHAR(1)			NOT NULL DEFAULT ('A'),	-- A=Activo, N=Anulado
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_cont_asiento_enc] PRIMARY KEY CLUSTERED ([asi_id] ASC),
	CONSTRAINT [CK_cont_asiento_enc_origen] CHECK ([asi_origen] IN ('MANUAL','VENTA','COMPRA','PAGO_CLIENTE','PAGO_PROVEEDOR')),
	CONSTRAINT [CK_cont_asiento_enc_estado] CHECK ([asi_estado] IN ('A','N'))
);
GO

CREATE TABLE [dbo].[cont_asiento_det](
	[asd_id]			INT				IDENTITY(1,1)	NOT NULL,
	[asi_id]			INT				NOT NULL,
	[cta_id]			INT				NOT NULL,
	[asd_debe]			DECIMAL(14, 2)	NOT NULL DEFAULT (0),
	[asd_haber]			DECIMAL(14, 2)	NOT NULL DEFAULT (0),
	[asd_descripcion]	VARCHAR(256)	NULL,
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_cont_asiento_det] PRIMARY KEY CLUSTERED ([asd_id] ASC),
	CONSTRAINT [CK_cont_asiento_det_signos] CHECK (
		([asd_debe] > 0 AND [asd_haber] = 0) OR
		([asd_haber] > 0 AND [asd_debe] = 0)
	)
);
GO
CREATE INDEX [IX_cont_asiento_det_asi_id] ON [dbo].[cont_asiento_det]([asi_id]);
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE TRIGGER [dbo].[trg_cont_asiento_det_valida_balance]
ON [dbo].[cont_asiento_det]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @asientos TABLE ([asi_id] INT PRIMARY KEY);

	INSERT INTO @asientos ([asi_id])
	SELECT [asi_id] FROM inserted
	UNION
	SELECT [asi_id] FROM deleted;

	IF EXISTS (
		SELECT d.[asi_id]
		FROM [dbo].[cont_asiento_det] d
		INNER JOIN @asientos a ON a.[asi_id] = d.[asi_id]
		GROUP BY d.[asi_id]
		HAVING SUM(d.[asd_debe]) <> SUM(d.[asd_haber])
	)
	BEGIN
		ROLLBACK TRANSACTION;
		THROW 50001, 'El asiento contable no quedó balanceado: la suma del Debe debe ser igual a la suma del Haber. Inserte/actualice todas las líneas del asiento en una sola sentencia.', 1;
	END
END;
GO
