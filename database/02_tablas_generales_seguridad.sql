/*
	Script 02: Catálogos generales, seguridad, monedas y auditoría.

	Convenciones usadas en todo el modelo:
	- <prefijo>_id           : llave primaria IDENTITY(1,1).
	- <prefijo>_estado CHAR(1): 'A' Activo / 'I' Inactivo (excepto donde se
	  documente lo contrario, p.ej. asientos contables usan 'A'/'N').
	- Las llaves foráneas se agregan todas juntas en 06_llaves_foraneas.sql.
*/
USE [erp_db];
GO

------------------------------------------------------------
-- Geografía
------------------------------------------------------------
CREATE TABLE [dbo].[gen_pais](
	[pai_id]				INT				IDENTITY(1,1)	NOT NULL,
	[pai_nombre]			VARCHAR(128)	NOT NULL,
	[pai_codigo_alfa2]		VARCHAR(2)		NOT NULL,
	[pai_codigo_alfa3]		VARCHAR(3)		NOT NULL,
	[pai_codigo_numero]	VARCHAR(3)		NULL,
	[pai_nacionalidad]		VARCHAR(64)		NULL,
	[pai_estado]			CHAR(1)			NOT NULL DEFAULT ('A'),
	CONSTRAINT [PK_gen_pais] PRIMARY KEY CLUSTERED ([pai_id] ASC),
	CONSTRAINT [UQ_gen_pais_alfa2] UNIQUE ([pai_codigo_alfa2]),
	CONSTRAINT [UQ_gen_pais_alfa3] UNIQUE ([pai_codigo_alfa3]),
	CONSTRAINT [CK_gen_pais_estado] CHECK ([pai_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[gen_estado](
	[est_id]		INT				IDENTITY(1,1)	NOT NULL,
	[est_codigo]	VARCHAR(2)		NOT NULL,
	[pai_id]		INT				NOT NULL,
	[est_nombre]	VARCHAR(128)	NOT NULL,
	[est_estado]	CHAR(1)			NOT NULL DEFAULT ('A'),
	CONSTRAINT [PK_gen_estado] PRIMARY KEY CLUSTERED ([est_id] ASC),
	CONSTRAINT [UQ_gen_estado_pais_codigo] UNIQUE ([pai_id], [est_codigo]),
	CONSTRAINT [CK_gen_estado_estado] CHECK ([est_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[gen_provincia](
	[prov_id]		INT				IDENTITY(1,1)	NOT NULL,
	[prov_codigo]	VARCHAR(2)		NOT NULL,
	[est_id]		INT				NOT NULL,
	[prov_nombre]	VARCHAR(128)	NOT NULL,
	[prov_estado]	CHAR(1)			NOT NULL DEFAULT ('A'),
	CONSTRAINT [PK_gen_provincia] PRIMARY KEY CLUSTERED ([prov_id] ASC),
	CONSTRAINT [UQ_gen_provincia_estado_codigo] UNIQUE ([est_id], [prov_codigo]),
	CONSTRAINT [CK_gen_provincia_estado] CHECK ([prov_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[gen_profesion](
	[prf_id]			INT				IDENTITY(1,1)	NOT NULL,
	[prf_descripcion]	VARCHAR(128)	NOT NULL,
	[prf_estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	CONSTRAINT [PK_gen_profesion] PRIMARY KEY CLUSTERED ([prf_id] ASC),
	CONSTRAINT [UQ_gen_profesion_descripcion] UNIQUE ([prf_descripcion]),
	CONSTRAINT [CK_gen_profesion_estado] CHECK ([prf_estado] IN ('A','I'))
);
GO

------------------------------------------------------------
-- Compañía / sucursales
------------------------------------------------------------
CREATE TABLE [dbo].[gen_compania](
	[cia_id]									INT				IDENTITY(1,1)	NOT NULL,
	[cia_nombre_comercial]						VARCHAR(128)	NOT NULL,
	[cia_direccion]								VARCHAR(128)	NULL,
	[cia_representante_legal]					VARCHAR(128)	NULL,
	[cia_DPI_representante_legal]				VARCHAR(32)		NULL,
	[cia_fecha_nacimiento_representante_legal]	DATE			NULL,
	[cia_nit]									VARCHAR(32)		NOT NULL,
	[cia_telefono]								VARCHAR(16)		NULL,
	[cia_email]									VARCHAR(64)		NULL,
	[cia_estado]								CHAR(1)			NOT NULL DEFAULT ('A'),
	CONSTRAINT [PK_gen_compania] PRIMARY KEY CLUSTERED ([cia_id] ASC),
	CONSTRAINT [UQ_gen_compania_nit] UNIQUE ([cia_nit]),
	CONSTRAINT [CK_gen_compania_estado] CHECK ([cia_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[gen_sucursal](
	[suc_id]			INT				IDENTITY(1,1)	NOT NULL,
	[suc_codigo]		VARCHAR(8)		NOT NULL,
	[suc_descripcion]	VARCHAR(128)	NOT NULL,
	[suc_direccion]		VARCHAR(128)	NULL,
	[suc_telefono]		VARCHAR(16)		NULL,
	[cia_id]			INT				NOT NULL,
	[suc_estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	CONSTRAINT [PK_gen_sucursal] PRIMARY KEY CLUSTERED ([suc_id] ASC),
	CONSTRAINT [UQ_gen_sucursal_cia_codigo] UNIQUE ([cia_id], [suc_codigo]),
	CONSTRAINT [CK_gen_sucursal_estado] CHECK ([suc_estado] IN ('A','I'))
);
GO

------------------------------------------------------------
-- Entidades financieras (bancos, tarjetas, etc.)
------------------------------------------------------------
CREATE TABLE [dbo].[gen_entidad_financiera_tipo](
	[geft_id]			INT				IDENTITY(1,1)	NOT NULL,
	[geft_descripcion]	VARCHAR(50)		NOT NULL,
	CONSTRAINT [PK_gen_entidad_financiera_tipo] PRIMARY KEY CLUSTERED ([geft_id] ASC),
	CONSTRAINT [UQ_gen_entidad_financiera_tipo_desc] UNIQUE ([geft_descripcion])
);
GO

CREATE TABLE [dbo].[gen_entidad_financiera](
	[gef_id]			INT				IDENTITY(1,1)	NOT NULL,
	[geft_id]			INT				NOT NULL,
	[gef_codigo]		VARCHAR(16)		NOT NULL,
	[gef_descripcion]	VARCHAR(50)		NOT NULL,
	[gef_estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	CONSTRAINT [PK_gen_entidad_financiera] PRIMARY KEY CLUSTERED ([gef_id] ASC),
	CONSTRAINT [UQ_gen_entidad_financiera_codigo] UNIQUE ([gef_codigo]),
	CONSTRAINT [CK_gen_entidad_financiera_estado] CHECK ([gef_estado] IN ('A','I'))
);
GO

------------------------------------------------------------
-- Moneda y tipo de cambio (módulo nuevo: soporte multi-moneda)
------------------------------------------------------------
CREATE TABLE [dbo].[gen_moneda](
	[mon_id]		INT				IDENTITY(1,1)	NOT NULL,
	[mon_codigo]	CHAR(3)			NOT NULL,			-- ISO 4217, p.ej. GTQ, USD
	[mon_nombre]	VARCHAR(64)		NOT NULL,
	[mon_simbolo]	VARCHAR(5)		NULL,
	[mon_es_local]	BIT				NOT NULL DEFAULT (0),	-- moneda funcional/base de la compañía
	[mon_estado]	CHAR(1)			NOT NULL DEFAULT ('A'),
	CONSTRAINT [PK_gen_moneda] PRIMARY KEY CLUSTERED ([mon_id] ASC),
	CONSTRAINT [UQ_gen_moneda_codigo] UNIQUE ([mon_codigo]),
	CONSTRAINT [CK_gen_moneda_estado] CHECK ([mon_estado] IN ('A','I'))
);
GO

-- Solo puede existir una moneda local activa a la vez.
CREATE UNIQUE INDEX [UX_gen_moneda_local]
	ON [dbo].[gen_moneda]([mon_es_local])
	WHERE [mon_es_local] = 1;
GO

CREATE TABLE [dbo].[gen_tipo_cambio](
	[tpc_id]		INT				IDENTITY(1,1)	NOT NULL,
	[mon_id]		INT				NOT NULL,
	[tpc_fecha]		DATE			NOT NULL,
	[tpc_valor]		DECIMAL(12,6)	NOT NULL,		-- unidades de moneda local por 1 unidad de [mon_id]
	CONSTRAINT [PK_gen_tipo_cambio] PRIMARY KEY CLUSTERED ([tpc_id] ASC),
	CONSTRAINT [UQ_gen_tipo_cambio_mon_fecha] UNIQUE ([mon_id], [tpc_fecha]),
	CONSTRAINT [CK_gen_tipo_cambio_valor] CHECK ([tpc_valor] > 0)
);
GO

------------------------------------------------------------
-- Usuarios (contraseña reforzada: hash + sal, antes viajaba en texto plano)
------------------------------------------------------------
CREATE TABLE [dbo].[gen_usuario](
	[usu_id]				INT					IDENTITY(1,1)	NOT NULL,
	[usu_codigo]			VARCHAR(32)			NOT NULL,
	[usu_usuario]			VARCHAR(128)		NOT NULL,
	[usu_password_hash]		VARBINARY(64)		NOT NULL,	-- HASHBYTES('SHA2_256', sal + contraseña)
	[usu_password_salt]		UNIQUEIDENTIFIER	NOT NULL DEFAULT (NEWID()),
	[usu_email]				VARCHAR(128)		NULL,
	[usu_fecha_ingreso]		DATE				NOT NULL DEFAULT (CAST(GETDATE() AS DATE)),
	[usu_intentos_fallidos]	INT					NOT NULL DEFAULT (0),
	[usu_bloqueado]			BIT					NOT NULL DEFAULT (0),
	[usu_ultimo_login]		DATETIME2(0)		NULL,
	[usu_estado]			CHAR(1)				NOT NULL DEFAULT ('A'),
	CONSTRAINT [PK_gen_usuario] PRIMARY KEY CLUSTERED ([usu_id] ASC),
	CONSTRAINT [UQ_gen_usuario_codigo] UNIQUE ([usu_codigo]),
	CONSTRAINT [UQ_gen_usuario_usuario] UNIQUE ([usu_usuario]),
	CONSTRAINT [CK_gen_usuario_estado] CHECK ([usu_estado] IN ('A','I'))
);
GO

------------------------------------------------------------
-- Seguridad: roles y permisos (módulo nuevo)
------------------------------------------------------------
CREATE TABLE [dbo].[sec_rol](
	[rol_id]		INT				IDENTITY(1,1)	NOT NULL,
	[rol_codigo]	VARCHAR(32)		NOT NULL,
	[rol_nombre]	VARCHAR(64)		NOT NULL,
	[rol_estado]	CHAR(1)			NOT NULL DEFAULT ('A'),
	CONSTRAINT [PK_sec_rol] PRIMARY KEY CLUSTERED ([rol_id] ASC),
	CONSTRAINT [UQ_sec_rol_codigo] UNIQUE ([rol_codigo]),
	CONSTRAINT [CK_sec_rol_estado] CHECK ([rol_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[sec_permiso](
	[per_id]			INT				IDENTITY(1,1)	NOT NULL,
	[per_modulo]		VARCHAR(32)		NOT NULL,		-- p.ej. INVENTARIO, VENTAS, BANCOS
	[per_codigo]		VARCHAR(64)		NOT NULL,		-- p.ej. INVENTARIO_PRODUCTO_CREAR
	[per_descripcion]	VARCHAR(128)	NULL,
	[per_estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	CONSTRAINT [PK_sec_permiso] PRIMARY KEY CLUSTERED ([per_id] ASC),
	CONSTRAINT [UQ_sec_permiso_codigo] UNIQUE ([per_codigo]),
	CONSTRAINT [CK_sec_permiso_estado] CHECK ([per_estado] IN ('A','I'))
);
GO

CREATE TABLE [dbo].[sec_rol_permiso](
	[rol_id]	INT	NOT NULL,
	[per_id]	INT	NOT NULL,
	CONSTRAINT [PK_sec_rol_permiso] PRIMARY KEY CLUSTERED ([rol_id] ASC, [per_id] ASC)
);
GO

CREATE TABLE [dbo].[sec_usuario_rol](
	[usu_id]	INT	NOT NULL,
	[rol_id]	INT	NOT NULL,
	CONSTRAINT [PK_sec_usuario_rol] PRIMARY KEY CLUSTERED ([usu_id] ASC, [rol_id] ASC)
);
GO

------------------------------------------------------------
-- Auditoría de cambios (módulo nuevo)
------------------------------------------------------------
CREATE TABLE [dbo].[gen_auditoria](
	[aud_id]				BIGINT			IDENTITY(1,1)	NOT NULL,
	[aud_tabla]				VARCHAR(128)	NOT NULL,
	[aud_accion]			CHAR(1)			NOT NULL,		-- I=Insert, U=Update, D=Delete
	[aud_llave]				VARCHAR(100)	NOT NULL,
	[aud_valores_anteriores]	NVARCHAR(MAX)	NULL,		-- JSON (FOR JSON PATH)
	[aud_valores_nuevos]	NVARCHAR(MAX)	NULL,			-- JSON (FOR JSON PATH)
	[usu_id]				INT				NULL,			-- SESSION_CONTEXT('usuario_id')
	[aud_fecha]				DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[aud_host]				VARCHAR(128)	NULL DEFAULT (HOST_NAME()),
	CONSTRAINT [PK_gen_auditoria] PRIMARY KEY CLUSTERED ([aud_id] ASC),
	CONSTRAINT [CK_gen_auditoria_accion] CHECK ([aud_accion] IN ('I','U','D'))
);
GO
CREATE INDEX [IX_gen_auditoria_tabla_llave] ON [dbo].[gen_auditoria]([aud_tabla], [aud_llave]);
GO

------------------------------------------------------------
-- Correlativos de documentos
------------------------------------------------------------
CREATE TABLE [dbo].[conf_correlativos](
	[id_serie]		INT				IDENTITY(1,1)	NOT NULL,
	[tdo_id]		INT				NOT NULL,		-- tipo de documento al que pertenece la serie
	[serie]			VARCHAR(32)		NOT NULL,
	[correlativo]	NUMERIC(12, 0)	NOT NULL DEFAULT (0),	-- antes "correlatio" (typo corregido)
	[cor_estado]	CHAR(1)			NOT NULL DEFAULT ('A'),
	CONSTRAINT [PK_conf_correlativos] PRIMARY KEY CLUSTERED ([id_serie] ASC),
	CONSTRAINT [UQ_conf_correlativos_serie] UNIQUE ([serie]),
	CONSTRAINT [CK_conf_correlativos_estado] CHECK ([cor_estado] IN ('A','I'))
);
GO
