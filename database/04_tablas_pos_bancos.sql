/*
	Script 04: Punto de venta (caja, clientes, pagos, vendedores) y bancos.

	Cambios relevantes vs. el script original:
	- [bco_cuenta_bacaria_chequera] se renombra a [bco_cuenta_bancaria_chequera]
	  (typo) y su columna "cbc_fecha_recepciòn_chequera" (con acento mal
	  codificado) pasa a "cbc_fecha_recepcion_chequera".
	- [pos_caja_deposito].pcd_valor_deposito estaba tipado como DATETIME en el
	  script original a pesar de ser un monto en dinero: se corrige a DECIMAL.
	- [pos_pago_det] no tenía columna de monto, por lo que no se podía saber
	  cuánto de un pago se aplicó a cada cuota: se agrega [ppd_valor_aplicado].
	- [pos_pago_forma] guardaba el número completo de tarjeta y el código de
	  verificación (CVV) en texto plano, lo cual viola PCI-DSS. Se elimina el
	  CVV por completo y el número de tarjeta se limita a los últimos 4
	  dígitos, que es lo único que un ERP debería conservar.
	- Se agrega trazabilidad de usuario en apertura/cierre de caja y en pagos.

	Todas las tablas agregan además [InsUsuario]/[InsFechaHora]/[UpdUsuario]/
	[UpdFechaHora] (ver el comentario de cabecera de 02_tablas_generales_seguridad.sql
	para la convención completa).
*/
USE [erp_db];
GO

------------------------------------------------------------
-- Bancos
------------------------------------------------------------
CREATE TABLE [dbo].[bco_cuenta_bancaria](
	[bcb_id]				INT				IDENTITY(1,1)	NOT NULL,
	[bcb_numero_cuenta]		VARCHAR(16)		NOT NULL,
	[bcb_descripcion]		VARCHAR(64)		NULL,
	[gef_id]				INT				NOT NULL,
	[bcb_estado]			CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_bco_cuenta_bancaria] PRIMARY KEY CLUSTERED ([bcb_id] ASC),
	CONSTRAINT [UQ_bco_cuenta_bancaria_numero] UNIQUE ([bcb_numero_cuenta]),
	CONSTRAINT [CK_bco_cuenta_bancaria_estado] CHECK ([bcb_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[bco_cuenta_bancaria_chequera](
	[cbc_id]							INT				IDENTITY(1,1)	NOT NULL,
	[cbc_cheque_del]					INT				NOT NULL,
	[cbc_cheque_al]						INT				NOT NULL,
	[cbc_fecha_recepcion_chequera]		DATE			NULL,
	[bcb_id]							INT				NOT NULL,
	[cbc_estado]						CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]						INT				NULL,
	[InsFechaHora]						DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]						INT				NULL,
	[UpdFechaHora]						DATETIME2(0)	NULL,
	CONSTRAINT [PK_bco_cuenta_bancaria_chequera] PRIMARY KEY CLUSTERED ([cbc_id] ASC),
	CONSTRAINT [CK_bco_cuenta_bancaria_chequera_rango] CHECK ([cbc_cheque_al] >= [cbc_cheque_del]),
	CONSTRAINT [CK_bco_cuenta_bancaria_chequera_estado] CHECK ([cbc_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[bco_motivo_pago](
	[bmp_id]			INT				IDENTITY(1,1)	NOT NULL,
	[bmp_descripcion]	VARCHAR(64)		NOT NULL,
	[bmp_estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_bco_motivo_pago] PRIMARY KEY CLUSTERED ([bmp_id] ASC),
	CONSTRAINT [UQ_bco_motivo_pago_descripcion] UNIQUE ([bmp_descripcion]),
	CONSTRAINT [CK_bco_motivo_pago_estado] CHECK ([bmp_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[bco_cheque_emitido_enc](
	[bce_id]				INT				IDENTITY(1,1)	NOT NULL,
	[cbc_id]				INT				NOT NULL,
	[bce_fecha_emision]		DATE			NOT NULL,
	[bce_fecha_grabado]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[usu_id]				INT				NULL,
	[bce_numero_cheque]		VARCHAR(16)		NOT NULL,
	[bce_observaciones]		VARCHAR(250)	NULL,
	[bce_documento_ref]		VARCHAR(16)		NULL,
	[bce_saldo_anterior]	DECIMAL(13, 2)	NULL,
	[bce_valor]				DECIMAL(13, 2)	NOT NULL,
	[bmp_id]				INT				NULL,
	[bce_estado_cheque]		CHAR(1)			NOT NULL DEFAULT ('E'),	-- E=Emitido, C=Cobrado, A=Anulado
	[bce_estado]			CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_bco_cheque_emitido_enc] PRIMARY KEY CLUSTERED ([bce_id] ASC),
	CONSTRAINT [UQ_bco_cheque_emitido_enc_numero] UNIQUE ([cbc_id], [bce_numero_cheque]),
	CONSTRAINT [CK_bco_cheque_emitido_enc_valor] CHECK ([bce_valor] > 0),
	CONSTRAINT [CK_bco_cheque_emitido_enc_estado_cheque] CHECK ([bce_estado_cheque] IN ('E','C','A')),
	CONSTRAINT [CK_bco_cheque_emitido_enc_estado] CHECK ([bce_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[bco_cheque_emitido_det](
	[ced_id]					INT				IDENTITY(1,1)	NOT NULL,
	[bce_id]					INT				NOT NULL,
	[bmp_id]					INT				NULL,
	[enc_id]					INT				NULL,
	[ced_valor]					DECIMAL(12, 2)	NOT NULL,
	[ced_abono_cancelacion]		CHAR(1)			NOT NULL,	-- A=Abono, C=Cancelación total
	[ced_estado]				CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]				INT				NULL,
	[InsFechaHora]				DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]				INT				NULL,
	[UpdFechaHora]				DATETIME2(0)	NULL,
	CONSTRAINT [PK_bco_cheque_emitido_det] PRIMARY KEY CLUSTERED ([ced_id] ASC),
	CONSTRAINT [CK_bco_cheque_emitido_det_valor] CHECK ([ced_valor] > 0),
	CONSTRAINT [CK_bco_cheque_emitido_det_abono] CHECK ([ced_abono_cancelacion] IN ('A','C')),
	CONSTRAINT [CK_bco_cheque_emitido_det_estado] CHECK ([ced_estado] IN ('A','I'))
);
GO

------------------------------------------------------------
-- Punto de venta: cajas
------------------------------------------------------------
CREATE TABLE [dbo].[pos_caja_receptora](
	[pcr_id]			INT				IDENTITY(1,1)	NOT NULL,
	[pcr_descripcion]	VARCHAR(64)		NOT NULL,
	[pcr_estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_pos_caja_receptora] PRIMARY KEY CLUSTERED ([pcr_id] ASC),
	CONSTRAINT [UQ_pos_caja_receptora_desc] UNIQUE ([pcr_descripcion]),
	CONSTRAINT [CK_pos_caja_receptora_estado] CHECK ([pcr_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[pos_caja_apertura](
	[pca_id]				INT				IDENTITY(1,1)	NOT NULL,
	[pca_fecha_apertura]	DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[pca_fecha_corte]		DATETIME2(0)	NULL,
	[pca_fecha_cierre]		DATETIME2(0)	NULL,
	[pcr_id]				INT				NOT NULL,
	[usu_id_apertura]		INT				NULL,
	[usu_id_cierre]			INT				NULL,
	[pca_estado]			CHAR(1)			NOT NULL DEFAULT ('A'),	-- A=Abierta, C=Cerrada
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_pos_caja_apertura] PRIMARY KEY CLUSTERED ([pca_id] ASC),
	CONSTRAINT [CK_pos_caja_apertura_fechas] CHECK ([pca_fecha_cierre] IS NULL OR [pca_fecha_cierre] >= [pca_fecha_apertura]),
	CONSTRAINT [CK_pos_caja_apertura_estado] CHECK ([pca_estado] IN ('A','C'))
);
GO

CREATE TABLE [dbo].[pos_caja_desglose_efectivo](
	[def_id]				INT				IDENTITY(1,1)	NOT NULL,
	[def_tipo_denominacion]	CHAR(1)			NOT NULL,		-- B=Billete, M=Moneda
	[def_denominacion]		NUMERIC(12, 2)	NOT NULL,
	[def_cantidad]			NUMERIC(8, 0)	NOT NULL DEFAULT (0),
	[pca_id]				INT				NOT NULL,
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_pos_caja_desglose_efectivo] PRIMARY KEY CLUSTERED ([def_id] ASC),
	CONSTRAINT [CK_pos_caja_desglose_efectivo_tipo] CHECK ([def_tipo_denominacion] IN ('B','M')),
	CONSTRAINT [CK_pos_caja_desglose_efectivo_denom] CHECK ([def_denominacion] > 0),
	CONSTRAINT [CK_pos_caja_desglose_efectivo_cant] CHECK ([def_cantidad] >= 0)
);
GO

CREATE TABLE [dbo].[pos_caja_deposito](
	[pcd_id]				INT				IDENTITY(1,1)	NOT NULL,
	[pcd_fecha_deposito]	DATE			NOT NULL,
	[pcd_valor_deposito]	DECIMAL(14, 2)	NOT NULL,		-- antes DATETIME por error; es un monto
	[pcd_numero_boleta]		VARCHAR(32)		NULL,
	[pcd_observaciones]		VARCHAR(128)	NULL,
	[pcd_fecha_registro]	DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[pca_id]				INT				NOT NULL,
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_pos_caja_deposito] PRIMARY KEY CLUSTERED ([pcd_id] ASC),
	CONSTRAINT [CK_pos_caja_deposito_valor] CHECK ([pcd_valor_deposito] > 0)
);
GO

------------------------------------------------------------
-- Clientes
------------------------------------------------------------
CREATE TABLE [dbo].[pos_cliente](
	[cli_id]							INT				IDENTITY(1,1)	NOT NULL,
	[cli_codigo]						VARCHAR(32)		NOT NULL,
	[cli_nombres]						VARCHAR(64)		NOT NULL,
	[cli_apellidos]						VARCHAR(64)		NULL,
	[cli_nombre_conyuge]				VARCHAR(256)	NULL,
	[cli_direccion]						VARCHAR(128)	NULL,
	[cli_telefono_casa]					VARCHAR(16)		NULL,
	[cli_telefono_celular]				VARCHAR(16)		NULL,
	[cli_lugar_trabajo]					VARCHAR(128)	NULL,
	[cli_telefono_trabajo]				VARCHAR(16)		NULL,
	[cli_nit]							VARCHAR(16)		NULL,
	[cli_email]							VARCHAR(64)		NULL,
	[cli_estado_civil]					CHAR(1)			NULL,	-- S,C,D,V,U
	[cli_limite_credito]				DECIMAL(14, 2)	NOT NULL DEFAULT (0),
	[cli_fecha_ultima_compra]			DATETIME2(0)	NULL,
	[cli_fecha_nacimiento]				DATE			NULL,
	[cli_fecha_registro]				DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[cli_referencia_personal_1]			VARCHAR(256)	NULL,
	[cli_referencia_personal_2]			VARCHAR(256)	NULL,
	[cli_DPI]							VARCHAR(32)		NULL,
	[cli_telefono_conyuge]				VARCHAR(16)		NULL,
	[cli_ref_personal_1_telefono]		VARCHAR(16)		NULL,
	[cli_ref_personal_2_telefono]		VARCHAR(16)		NULL,
	[cli_nacionalidad]					INT				NULL,
	[cli_direccion_pais]				INT				NULL,
	[cli_direccion_estado]				INT				NULL,
	[cli_direccion_provincia]			INT				NULL,
	[cli_profesion]						INT				NULL,
	[cli_DPI_extendido_pais]			INT				NULL,
	[cli_DPI_extendido_estado]			INT				NULL,
	[cli_DPI_extendido_provincia]		INT				NULL,
	[cli_estado]						CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]						INT				NULL,
	[InsFechaHora]						DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]						INT				NULL,
	[UpdFechaHora]						DATETIME2(0)	NULL,
	CONSTRAINT [PK_pos_cliente] PRIMARY KEY CLUSTERED ([cli_id] ASC),
	CONSTRAINT [UQ_pos_cliente_codigo] UNIQUE ([cli_codigo]),
	CONSTRAINT [CK_pos_cliente_estado_civil] CHECK ([cli_estado_civil] IS NULL OR [cli_estado_civil] IN ('S','C','D','V','U')),
	CONSTRAINT [CK_pos_cliente_limite_credito] CHECK ([cli_limite_credito] >= 0),
	CONSTRAINT [CK_pos_cliente_estado] CHECK ([cli_estado] IN ('A','I'))
);
GO
CREATE UNIQUE INDEX [UX_pos_cliente_nit] ON [dbo].[pos_cliente]([cli_nit]) WHERE [cli_nit] IS NOT NULL;
GO

CREATE TABLE [dbo].[pos_cliente_tipo_pago](
	[tpa_id]			INT				IDENTITY(1,1)	NOT NULL,
	[tpa_codigo]		VARCHAR(16)		NOT NULL,
	[tpa_descripcion]	VARCHAR(64)		NOT NULL,
	[tpa_estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_pos_cliente_tipo_pago] PRIMARY KEY CLUSTERED ([tpa_id] ASC),
	CONSTRAINT [UQ_pos_cliente_tipo_pago_codigo] UNIQUE ([tpa_codigo]),
	CONSTRAINT [CK_pos_cliente_tipo_pago_estado] CHECK ([tpa_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[pos_cliente_plan_pagos](
	[cpp_id]				INT				IDENTITY(1,1)	NOT NULL,
	[cpp_nro_cuota]			INT				NOT NULL,
	[cpp_valor_cuota]		NUMERIC(12, 2)	NOT NULL,
	[cpp_saldo_cuota]		NUMERIC(12, 2)	NOT NULL,
	[cpp_fecha_maxima_pago]	DATE			NOT NULL,
	[cpp_fecha_real_pago]	DATE			NULL,
	[cpp_dias_mora]			INT				NOT NULL DEFAULT (0),
	[cpp_dias_no_pago]		INT				NOT NULL DEFAULT (0),
	[enc_id]				INT				NOT NULL,
	[cli_id]				INT				NOT NULL,
	[tpa_id]				INT				NULL,
	[cpp_estado]			CHAR(1)			NOT NULL DEFAULT ('P'),	-- P=Pendiente, A=Abonado/pagado, V=Vencido
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_pos_cliente_plan_pagos] PRIMARY KEY CLUSTERED ([cpp_id] ASC),
	CONSTRAINT [UQ_pos_cliente_plan_pagos_cuota] UNIQUE ([enc_id], [cpp_nro_cuota]),
	CONSTRAINT [CK_pos_cliente_plan_pagos_estado] CHECK ([cpp_estado] IN ('P','A','V'))
);
GO

------------------------------------------------------------
-- Formas y pagos
------------------------------------------------------------
CREATE TABLE [dbo].[pos_pago_forma_tipo](
	[pft_id]			INT				IDENTITY(1,1)	NOT NULL,
	[pft_descripcion]	VARCHAR(50)		NOT NULL,
	[pft_estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_pos_pago_forma_tipo] PRIMARY KEY CLUSTERED ([pft_id] ASC),
	CONSTRAINT [UQ_pos_pago_forma_tipo_desc] UNIQUE ([pft_descripcion]),
	CONSTRAINT [CK_pos_pago_forma_tipo_estado] CHECK ([pft_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[pos_pago_enc](
	[ppe_id]			INT				IDENTITY(1,1)	NOT NULL,
	[ppe_fecha_pago]	DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[ppe_nombres]		VARCHAR(64)		NULL,
	[ppe_apellidos]		VARCHAR(64)		NULL,
	[cli_id]			INT				NOT NULL,
	[pca_id]			INT				NOT NULL,
	[usu_id]			INT				NULL,
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_pos_pago_enc] PRIMARY KEY CLUSTERED ([ppe_id] ASC)
);
GO

CREATE TABLE [dbo].[pos_pago_forma](
	[ppf_id]							INT				IDENTITY(1,1)	NOT NULL,
	[gef_id]							INT				NULL,
	[ppf_numero_tarjeta_ult4]			VARCHAR(4)		NULL,	-- antes guardaba el número completo (PCI-DSS)
	[ppf_fecha_vencimiento_tarjeta]	VARCHAR(4)		NULL,
	[ppf_numero_cheque]				VARCHAR(16)		NULL,
	[ppe_id]							INT				NOT NULL,
	[pft_id]							INT				NOT NULL,
	[InsUsuario]						INT				NULL,
	[InsFechaHora]						DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]						INT				NULL,
	[UpdFechaHora]						DATETIME2(0)	NULL,
	CONSTRAINT [PK_pos_pago_forma] PRIMARY KEY CLUSTERED ([ppf_id] ASC)
);
GO

CREATE TABLE [dbo].[pos_pago_det](
	[ppd_id]				INT				IDENTITY(1,1)	NOT NULL,
	[ppe_id]				INT				NOT NULL,
	[cpp_id]				INT				NOT NULL,
	[ppd_valor_aplicado]	NUMERIC(12, 2)	NOT NULL,	-- antes no existía: no se podía saber cuánto se abonó a cada cuota
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_pos_pago_det] PRIMARY KEY CLUSTERED ([ppd_id] ASC),
	CONSTRAINT [CK_pos_pago_det_valor] CHECK ([ppd_valor_aplicado] > 0)
);
GO

------------------------------------------------------------
-- Vendedores
------------------------------------------------------------
CREATE TABLE [dbo].[pos_vendedor](
	[pve_id]			INT				IDENTITY(1,1)	NOT NULL,
	[pve_codigo]		VARCHAR(16)		NOT NULL,
	[pve_nombres]		VARCHAR(64)		NOT NULL,
	[pve_apellidos]		VARCHAR(64)		NULL,
	[pve_fecha_ingreso]	DATE			NULL,
	[pve_porc_comision]	NUMERIC(8, 2)	NOT NULL DEFAULT (0),
	[pve_estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_pos_vendedor] PRIMARY KEY CLUSTERED ([pve_id] ASC),
	CONSTRAINT [UQ_pos_vendedor_codigo] UNIQUE ([pve_codigo]),
	CONSTRAINT [CK_pos_vendedor_estado] CHECK ([pve_estado] IN ('A','I'))
);
GO
