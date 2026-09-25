------------------------------------------------------------------------------
-- 25_rrhh.sql
--
-- Módulo de Recursos Humanos, basado en ERD_RRHH_20260105_0926.
--
-- Nomenclatura: tablas rrhh + PascalCase (rrhhEmpleado, rrhhPlaza...),
-- columnas en PascalCase como en el diagrama, procedimientos pa + PascalCase.
-- Las llaves foráneas llevan el mismo nombre que la llave primaria a la que
-- apuntan (IdEmpleado, IdPlaza...), igual que en el resto del modelo.
--
-- Cambios respecto al diagrama:
--   * TipoIngreso y TipoDescuento se unifican en rrhhTipoMovimientoNomina,
--     con Naturaleza I (ingreso, suma) o D (descuento, resta); Ingresos y
--     Descuentos se unifican en rrhhMovimientoNomina.
--   * PaisEstadoProvincia no se crea: se reutilizan gen_pais / gen_estado /
--     gen_provincia, que ya existen.
--   * El rango salarial (SalarioMinimo/SalarioMaximo) va en rrhhPuesto y no
--     en RequisitosPuesto: es un atributo del puesto, no de cada requisito.
--   * Teléfono, Referencia y Escolaridad sirven tanto a un candidato como a
--     un empleado (una de las dos llaves debe venir llena).
--   * Se agregan rrhhCurso (catálogo de HistorialCapacitacion) y las tablas
--     de nómina: rrhhNomina, rrhhNominaEmpleado y rrhhNominaDetalle.
--
-- Cálculo de nómina (paRrhhNominaCalcular): cada tipo de movimiento define
-- cómo se calcula:
--   S = sueldo base proporcional a los días laborados (base de 30 días),
--   F = monto fijo mensual, proporcional a los días laborados,
--   P = porcentaje sobre los ingresos marcados como EsBaseCalculo,
--   M = manual: sale de los movimientos capturados en rrhhMovimientoNomina
--       con fecha de aplicación dentro del período.
-- Solo los tipos con EsAutomatico = 1 se aplican solos a todos los empleados.
--
-- Se puede volver a correr: tablas y datos iniciales verifican si ya existen.
------------------------------------------------------------------------------

USE [erp_db];
GO

------------------------------------------------------------
-- Catálogos simples (Id, Descripcion, Estado)
------------------------------------------------------------
IF OBJECT_ID('dbo.rrhhUnidadOrganizativa', 'U') IS NULL
CREATE TABLE [dbo].[rrhhUnidadOrganizativa](
	[IdUnidadOrganizativa]	INT				IDENTITY(1,1)	NOT NULL,
	[Descripcion]			VARCHAR(100)	NOT NULL,
	[Estado]				CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhUnidadOrganizativa] PRIMARY KEY CLUSTERED ([IdUnidadOrganizativa]),
	CONSTRAINT [UQ_rrhhUnidadOrganizativa_Descripcion] UNIQUE ([Descripcion]),
	CONSTRAINT [CK_rrhhUnidadOrganizativa_Estado] CHECK ([Estado] IN ('A','I'))
);
GO

IF OBJECT_ID('dbo.rrhhTipoRequisito', 'U') IS NULL
CREATE TABLE [dbo].[rrhhTipoRequisito](
	[IdTipoRequisito]	INT				IDENTITY(1,1)	NOT NULL,
	[Descripcion]		VARCHAR(100)	NOT NULL,
	[Estado]			CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhTipoRequisito] PRIMARY KEY CLUSTERED ([IdTipoRequisito]),
	CONSTRAINT [UQ_rrhhTipoRequisito_Descripcion] UNIQUE ([Descripcion]),
	CONSTRAINT [CK_rrhhTipoRequisito_Estado] CHECK ([Estado] IN ('A','I'))
);
GO

IF OBJECT_ID('dbo.rrhhTipoDocumentoIdentificacion', 'U') IS NULL
CREATE TABLE [dbo].[rrhhTipoDocumentoIdentificacion](
	[IdTipoDocumentoIdentificacion]	INT				IDENTITY(1,1)	NOT NULL,
	[Descripcion]					VARCHAR(100)	NOT NULL,
	[Estado]						CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]					INT				NULL,
	[InsFechaHora]					DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]					INT				NULL,
	[UpdFechaHora]					DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhTipoDocumentoIdentificacion] PRIMARY KEY CLUSTERED ([IdTipoDocumentoIdentificacion]),
	CONSTRAINT [UQ_rrhhTipoDocumentoIdentificacion_Descripcion] UNIQUE ([Descripcion]),
	CONSTRAINT [CK_rrhhTipoDocumentoIdentificacion_Estado] CHECK ([Estado] IN ('A','I'))
);
GO

IF OBJECT_ID('dbo.rrhhTipoTelefono', 'U') IS NULL
CREATE TABLE [dbo].[rrhhTipoTelefono](
	[IdTipoTelefono]	INT				IDENTITY(1,1)	NOT NULL,
	[Descripcion]		VARCHAR(100)	NOT NULL,
	[Estado]			CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhTipoTelefono] PRIMARY KEY CLUSTERED ([IdTipoTelefono]),
	CONSTRAINT [UQ_rrhhTipoTelefono_Descripcion] UNIQUE ([Descripcion]),
	CONSTRAINT [CK_rrhhTipoTelefono_Estado] CHECK ([Estado] IN ('A','I'))
);
GO

IF OBJECT_ID('dbo.rrhhTipoEscolaridad', 'U') IS NULL
CREATE TABLE [dbo].[rrhhTipoEscolaridad](
	[IdTipoEscolaridad]	INT				IDENTITY(1,1)	NOT NULL,
	[Descripcion]		VARCHAR(100)	NOT NULL,
	[Estado]			CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhTipoEscolaridad] PRIMARY KEY CLUSTERED ([IdTipoEscolaridad]),
	CONSTRAINT [UQ_rrhhTipoEscolaridad_Descripcion] UNIQUE ([Descripcion]),
	CONSTRAINT [CK_rrhhTipoEscolaridad_Estado] CHECK ([Estado] IN ('A','I'))
);
GO

IF OBJECT_ID('dbo.rrhhTipoEvaluacion', 'U') IS NULL
CREATE TABLE [dbo].[rrhhTipoEvaluacion](
	[IdTipoEvaluacion]	INT				IDENTITY(1,1)	NOT NULL,
	[Descripcion]		VARCHAR(100)	NOT NULL,
	[Estado]			CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhTipoEvaluacion] PRIMARY KEY CLUSTERED ([IdTipoEvaluacion]),
	CONSTRAINT [UQ_rrhhTipoEvaluacion_Descripcion] UNIQUE ([Descripcion]),
	CONSTRAINT [CK_rrhhTipoEvaluacion_Estado] CHECK ([Estado] IN ('A','I'))
);
GO

IF OBJECT_ID('dbo.rrhhCurso', 'U') IS NULL
CREATE TABLE [dbo].[rrhhCurso](
	[IdCurso]		INT				IDENTITY(1,1)	NOT NULL,
	[Descripcion]	VARCHAR(100)	NOT NULL,
	[Estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]	INT				NULL,
	[InsFechaHora]	DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]	INT				NULL,
	[UpdFechaHora]	DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhCurso] PRIMARY KEY CLUSTERED ([IdCurso]),
	CONSTRAINT [UQ_rrhhCurso_Descripcion] UNIQUE ([Descripcion]),
	CONSTRAINT [CK_rrhhCurso_Estado] CHECK ([Estado] IN ('A','I'))
);
GO

------------------------------------------------------------
-- Estructura organizativa: departamento, puesto, plaza
------------------------------------------------------------
IF OBJECT_ID('dbo.rrhhDepartamento', 'U') IS NULL
CREATE TABLE [dbo].[rrhhDepartamento](
	[IdDepartamento]		INT				IDENTITY(1,1)	NOT NULL,
	[Descripcion]			VARCHAR(100)	NOT NULL,
	[IdUnidadOrganizativa]	INT				NULL,
	[suc_id]				INT				NULL,		-- ubicación física (Location_ID del diagrama)
	[Estado]				CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhDepartamento] PRIMARY KEY CLUSTERED ([IdDepartamento]),
	CONSTRAINT [UQ_rrhhDepartamento_Descripcion] UNIQUE ([Descripcion]),
	CONSTRAINT [CK_rrhhDepartamento_Estado] CHECK ([Estado] IN ('A','I')),
	CONSTRAINT [FK_rrhhDepartamento_UnidadOrganizativa] FOREIGN KEY ([IdUnidadOrganizativa]) REFERENCES [dbo].[rrhhUnidadOrganizativa]([IdUnidadOrganizativa]),
	CONSTRAINT [FK_rrhhDepartamento_Sucursal] FOREIGN KEY ([suc_id]) REFERENCES [dbo].[gen_sucursal]([suc_id])
);
GO

IF OBJECT_ID('dbo.rrhhPuesto', 'U') IS NULL
CREATE TABLE [dbo].[rrhhPuesto](
	[IdPuesto]		INT				IDENTITY(1,1)	NOT NULL,
	[Descripcion]	VARCHAR(100)	NOT NULL,
	[SalarioMinimo]	NUMERIC(12, 2)	NOT NULL DEFAULT (0),
	[SalarioMaximo]	NUMERIC(12, 2)	NOT NULL DEFAULT (0),
	[Estado]		CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]	INT				NULL,
	[InsFechaHora]	DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]	INT				NULL,
	[UpdFechaHora]	DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhPuesto] PRIMARY KEY CLUSTERED ([IdPuesto]),
	CONSTRAINT [UQ_rrhhPuesto_Descripcion] UNIQUE ([Descripcion]),
	CONSTRAINT [CK_rrhhPuesto_Estado] CHECK ([Estado] IN ('A','I')),
	CONSTRAINT [CK_rrhhPuesto_Salario] CHECK ([SalarioMinimo] >= 0 AND [SalarioMaximo] >= [SalarioMinimo])
);
GO

IF OBJECT_ID('dbo.rrhhDepartamentoPuesto', 'U') IS NULL
CREATE TABLE [dbo].[rrhhDepartamentoPuesto](
	[IdDepartamentoPuesto]	INT				IDENTITY(1,1)	NOT NULL,
	[IdDepartamento]		INT				NOT NULL,
	[IdPuesto]				INT				NOT NULL,
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	CONSTRAINT [PK_rrhhDepartamentoPuesto] PRIMARY KEY CLUSTERED ([IdDepartamentoPuesto]),
	CONSTRAINT [UQ_rrhhDepartamentoPuesto] UNIQUE ([IdDepartamento], [IdPuesto]),
	CONSTRAINT [FK_rrhhDepartamentoPuesto_Departamento] FOREIGN KEY ([IdDepartamento]) REFERENCES [dbo].[rrhhDepartamento]([IdDepartamento]),
	CONSTRAINT [FK_rrhhDepartamentoPuesto_Puesto] FOREIGN KEY ([IdPuesto]) REFERENCES [dbo].[rrhhPuesto]([IdPuesto])
);
GO

IF OBJECT_ID('dbo.rrhhRequisitoPuesto', 'U') IS NULL
CREATE TABLE [dbo].[rrhhRequisitoPuesto](
	[IdRequisitoPuesto]	INT				IDENTITY(1,1)	NOT NULL,
	[IdPuesto]			INT				NOT NULL,
	[IdTipoRequisito]	INT				NOT NULL,
	[Descripcion]		VARCHAR(200)	NOT NULL,
	[Observaciones]		VARCHAR(400)	NULL,
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhRequisitoPuesto] PRIMARY KEY CLUSTERED ([IdRequisitoPuesto]),
	CONSTRAINT [FK_rrhhRequisitoPuesto_Puesto] FOREIGN KEY ([IdPuesto]) REFERENCES [dbo].[rrhhPuesto]([IdPuesto]),
	CONSTRAINT [FK_rrhhRequisitoPuesto_TipoRequisito] FOREIGN KEY ([IdTipoRequisito]) REFERENCES [dbo].[rrhhTipoRequisito]([IdTipoRequisito])
);
GO

IF OBJECT_ID('dbo.rrhhPlaza', 'U') IS NULL
CREATE TABLE [dbo].[rrhhPlaza](
	[IdPlaza]				INT				IDENTITY(1,1)	NOT NULL,
	[Descripcion]			VARCHAR(100)	NOT NULL,
	[IdDepartamentoPuesto]	INT				NOT NULL,
	[Estado]				CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhPlaza] PRIMARY KEY CLUSTERED ([IdPlaza]),
	CONSTRAINT [UQ_rrhhPlaza_Descripcion] UNIQUE ([Descripcion]),
	CONSTRAINT [CK_rrhhPlaza_Estado] CHECK ([Estado] IN ('A','I')),
	CONSTRAINT [FK_rrhhPlaza_DepartamentoPuesto] FOREIGN KEY ([IdDepartamentoPuesto]) REFERENCES [dbo].[rrhhDepartamentoPuesto]([IdDepartamentoPuesto])
);
GO

------------------------------------------------------------
-- Personas: candidato y empleado
------------------------------------------------------------
IF OBJECT_ID('dbo.rrhhCandidato', 'U') IS NULL
CREATE TABLE [dbo].[rrhhCandidato](
	[IdCandidato]					INT				IDENTITY(1,1)	NOT NULL,
	[PrimerNombre]					VARCHAR(50)		NOT NULL,
	[SegundoNombre]					VARCHAR(50)		NULL,
	[PrimerApellido]				VARCHAR(50)		NOT NULL,
	[SegundoApellido]				VARCHAR(50)		NULL,
	[ApellidoCasada]				VARCHAR(50)		NULL,
	[FechaNacimiento]				DATE			NULL,
	[Genero]						CHAR(1)			NULL,	-- M, F
	[EstadoCivil]					CHAR(1)			NULL,	-- S, C, U (unido), D, V
	[Direccion]						VARCHAR(200)	NULL,
	[prov_id]						INT				NULL,
	[IdTipoDocumentoIdentificacion]	INT				NULL,
	[NumeroDocumento]				VARCHAR(32)		NULL,	-- CUI del DPI
	[IdPlaza]						INT				NULL,	-- plaza a la que aplica
	[PretensionSalarial]			NUMERIC(12, 2)	NULL,
	[HojaDeVidaURL]					VARCHAR(400)	NULL,
	[AntecedentesPenalesURL]		VARCHAR(400)	NULL,
	[AntecedentesPoliciacosURL]		VARCHAR(400)	NULL,
	[UltimoGradoAcademicoURL]		VARCHAR(400)	NULL,
	[Estado]						CHAR(1)			NOT NULL DEFAULT ('A'),	-- A=activo, C=contratado, D=descartado
	[InsUsuario]					INT				NULL,
	[InsFechaHora]					DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]					INT				NULL,
	[UpdFechaHora]					DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhCandidato] PRIMARY KEY CLUSTERED ([IdCandidato]),
	CONSTRAINT [CK_rrhhCandidato_Estado] CHECK ([Estado] IN ('A','C','D')),
	CONSTRAINT [CK_rrhhCandidato_Genero] CHECK ([Genero] IS NULL OR [Genero] IN ('M','F')),
	CONSTRAINT [CK_rrhhCandidato_EstadoCivil] CHECK ([EstadoCivil] IS NULL OR [EstadoCivil] IN ('S','C','U','D','V')),
	CONSTRAINT [FK_rrhhCandidato_Provincia] FOREIGN KEY ([prov_id]) REFERENCES [dbo].[gen_provincia]([prov_id]),
	CONSTRAINT [FK_rrhhCandidato_TipoDocumento] FOREIGN KEY ([IdTipoDocumentoIdentificacion]) REFERENCES [dbo].[rrhhTipoDocumentoIdentificacion]([IdTipoDocumentoIdentificacion]),
	CONSTRAINT [FK_rrhhCandidato_Plaza] FOREIGN KEY ([IdPlaza]) REFERENCES [dbo].[rrhhPlaza]([IdPlaza])
);
GO

IF OBJECT_ID('dbo.rrhhEmpleado', 'U') IS NULL
CREATE TABLE [dbo].[rrhhEmpleado](
	[IdEmpleado]					INT				IDENTITY(1,1)	NOT NULL,
	[CodigoEmpleado]				VARCHAR(16)		NOT NULL,
	[cia_id]						INT				NOT NULL,
	[IdCandidato]					INT				NULL,
	[PrimerNombre]					VARCHAR(50)		NOT NULL,
	[SegundoNombre]					VARCHAR(50)		NULL,
	[PrimerApellido]				VARCHAR(50)		NOT NULL,
	[SegundoApellido]				VARCHAR(50)		NULL,
	[ApellidoCasada]				VARCHAR(50)		NULL,
	[Genero]						CHAR(1)			NULL,
	[FechaNacimiento]				DATE			NULL,
	[FechaIngreso]					DATE			NOT NULL,
	[FechaBaja]						DATE			NULL,
	[Direccion]						VARCHAR(200)	NULL,
	[prov_id]						INT				NULL,
	[IdTipoDocumentoIdentificacion]	INT				NULL,
	[NumeroDocumento]				VARCHAR(32)		NULL,
	[NumeroAfiliacionIGSS]			VARCHAR(20)		NULL,	-- SeguroSocial del diagrama
	[Nit]							VARCHAR(20)		NULL,
	[Email]							VARCHAR(100)	NULL,
	[IdPlaza]						INT				NULL,	-- plaza actual; el histórico va en rrhhHistorialPlaza
	[SalarioBase]					NUMERIC(12, 2)	NOT NULL DEFAULT (0),	-- mensual
	[Estado]						CHAR(1)			NOT NULL DEFAULT ('A'),	-- A=activo, B=baja
	[InsUsuario]					INT				NULL,
	[InsFechaHora]					DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]					INT				NULL,
	[UpdFechaHora]					DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhEmpleado] PRIMARY KEY CLUSTERED ([IdEmpleado]),
	CONSTRAINT [UQ_rrhhEmpleado_Codigo] UNIQUE ([CodigoEmpleado]),
	CONSTRAINT [CK_rrhhEmpleado_Estado] CHECK ([Estado] IN ('A','B')),
	CONSTRAINT [CK_rrhhEmpleado_Genero] CHECK ([Genero] IS NULL OR [Genero] IN ('M','F')),
	CONSTRAINT [CK_rrhhEmpleado_Salario] CHECK ([SalarioBase] >= 0),
	CONSTRAINT [CK_rrhhEmpleado_Fechas] CHECK ([FechaBaja] IS NULL OR [FechaBaja] >= [FechaIngreso]),
	CONSTRAINT [FK_rrhhEmpleado_Compania] FOREIGN KEY ([cia_id]) REFERENCES [dbo].[gen_compania]([cia_id]),
	CONSTRAINT [FK_rrhhEmpleado_Candidato] FOREIGN KEY ([IdCandidato]) REFERENCES [dbo].[rrhhCandidato]([IdCandidato]),
	CONSTRAINT [FK_rrhhEmpleado_Provincia] FOREIGN KEY ([prov_id]) REFERENCES [dbo].[gen_provincia]([prov_id]),
	CONSTRAINT [FK_rrhhEmpleado_TipoDocumento] FOREIGN KEY ([IdTipoDocumentoIdentificacion]) REFERENCES [dbo].[rrhhTipoDocumentoIdentificacion]([IdTipoDocumentoIdentificacion]),
	CONSTRAINT [FK_rrhhEmpleado_Plaza] FOREIGN KEY ([IdPlaza]) REFERENCES [dbo].[rrhhPlaza]([IdPlaza])
);
GO

IF OBJECT_ID('dbo.rrhhHistorialPlaza', 'U') IS NULL
CREATE TABLE [dbo].[rrhhHistorialPlaza](
	[IdHistorialPlaza]	INT				IDENTITY(1,1)	NOT NULL,
	[IdEmpleado]		INT				NOT NULL,
	[IdPlaza]			INT				NOT NULL,
	[FechaDel]			DATE			NOT NULL,
	[FechaAl]			DATE			NULL,
	[Salario]			NUMERIC(12, 2)	NOT NULL,
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	CONSTRAINT [PK_rrhhHistorialPlaza] PRIMARY KEY CLUSTERED ([IdHistorialPlaza]),
	CONSTRAINT [FK_rrhhHistorialPlaza_Empleado] FOREIGN KEY ([IdEmpleado]) REFERENCES [dbo].[rrhhEmpleado]([IdEmpleado]),
	CONSTRAINT [FK_rrhhHistorialPlaza_Plaza] FOREIGN KEY ([IdPlaza]) REFERENCES [dbo].[rrhhPlaza]([IdPlaza])
);
GO

IF OBJECT_ID('dbo.rrhhTelefono', 'U') IS NULL
CREATE TABLE [dbo].[rrhhTelefono](
	[IdTelefono]		INT				IDENTITY(1,1)	NOT NULL,
	[IdCandidato]		INT				NULL,
	[IdEmpleado]		INT				NULL,
	[IdTipoTelefono]	INT				NOT NULL,
	[Numero]			VARCHAR(20)		NOT NULL,
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	CONSTRAINT [PK_rrhhTelefono] PRIMARY KEY CLUSTERED ([IdTelefono]),
	CONSTRAINT [CK_rrhhTelefono_Persona] CHECK ([IdCandidato] IS NOT NULL OR [IdEmpleado] IS NOT NULL),
	CONSTRAINT [FK_rrhhTelefono_Candidato] FOREIGN KEY ([IdCandidato]) REFERENCES [dbo].[rrhhCandidato]([IdCandidato]),
	CONSTRAINT [FK_rrhhTelefono_Empleado] FOREIGN KEY ([IdEmpleado]) REFERENCES [dbo].[rrhhEmpleado]([IdEmpleado]),
	CONSTRAINT [FK_rrhhTelefono_Tipo] FOREIGN KEY ([IdTipoTelefono]) REFERENCES [dbo].[rrhhTipoTelefono]([IdTipoTelefono])
);
GO

IF OBJECT_ID('dbo.rrhhReferencia', 'U') IS NULL
CREATE TABLE [dbo].[rrhhReferencia](
	[IdReferencia]			INT				IDENTITY(1,1)	NOT NULL,
	[IdCandidato]			INT				NULL,
	[IdEmpleado]			INT				NULL,
	[NombreCompleto]		VARCHAR(150)	NOT NULL,
	[Telefono]				VARCHAR(20)		NULL,
	[CorreoElectronico]		VARCHAR(100)	NULL,
	[LugarTrabajo]			VARCHAR(150)	NULL,
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	CONSTRAINT [PK_rrhhReferencia] PRIMARY KEY CLUSTERED ([IdReferencia]),
	CONSTRAINT [CK_rrhhReferencia_Persona] CHECK ([IdCandidato] IS NOT NULL OR [IdEmpleado] IS NOT NULL),
	CONSTRAINT [FK_rrhhReferencia_Candidato] FOREIGN KEY ([IdCandidato]) REFERENCES [dbo].[rrhhCandidato]([IdCandidato]),
	CONSTRAINT [FK_rrhhReferencia_Empleado] FOREIGN KEY ([IdEmpleado]) REFERENCES [dbo].[rrhhEmpleado]([IdEmpleado])
);
GO

IF OBJECT_ID('dbo.rrhhEscolaridad', 'U') IS NULL
CREATE TABLE [dbo].[rrhhEscolaridad](
	[IdEscolaridad]		INT				IDENTITY(1,1)	NOT NULL,
	[IdCandidato]		INT				NULL,
	[IdEmpleado]		INT				NULL,
	[IdTipoEscolaridad]	INT				NOT NULL,
	[DelAnio]			SMALLINT		NULL,
	[AlAnio]			SMALLINT		NULL,
	[GradoCursado]		VARCHAR(100)	NOT NULL,
	[CentroEducativo]	VARCHAR(150)	NULL,
	[Finalizado]		BIT				NOT NULL DEFAULT (0),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	CONSTRAINT [PK_rrhhEscolaridad] PRIMARY KEY CLUSTERED ([IdEscolaridad]),
	CONSTRAINT [CK_rrhhEscolaridad_Persona] CHECK ([IdCandidato] IS NOT NULL OR [IdEmpleado] IS NOT NULL),
	CONSTRAINT [FK_rrhhEscolaridad_Candidato] FOREIGN KEY ([IdCandidato]) REFERENCES [dbo].[rrhhCandidato]([IdCandidato]),
	CONSTRAINT [FK_rrhhEscolaridad_Empleado] FOREIGN KEY ([IdEmpleado]) REFERENCES [dbo].[rrhhEmpleado]([IdEmpleado]),
	CONSTRAINT [FK_rrhhEscolaridad_Tipo] FOREIGN KEY ([IdTipoEscolaridad]) REFERENCES [dbo].[rrhhTipoEscolaridad]([IdTipoEscolaridad])
);
GO

IF OBJECT_ID('dbo.rrhhEvaluacionDesempenio', 'U') IS NULL
CREATE TABLE [dbo].[rrhhEvaluacionDesempenio](
	[IdEvaluacionDesempenio]	INT				IDENTITY(1,1)	NOT NULL,
	[IdEmpleado]				INT				NOT NULL,
	[IdTipoEvaluacion]			INT				NOT NULL,
	[FechaRevision]				DATE			NOT NULL,
	[Calificacion]				NUMERIC(5, 2)	NULL,
	[ComentariosEvaluador]		VARCHAR(1000)	NULL,
	[ComentariosEmpleado]		VARCHAR(1000)	NULL,
	[InsUsuario]				INT				NULL,
	[InsFechaHora]				DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	CONSTRAINT [PK_rrhhEvaluacionDesempenio] PRIMARY KEY CLUSTERED ([IdEvaluacionDesempenio]),
	CONSTRAINT [FK_rrhhEvaluacionDesempenio_Empleado] FOREIGN KEY ([IdEmpleado]) REFERENCES [dbo].[rrhhEmpleado]([IdEmpleado]),
	CONSTRAINT [FK_rrhhEvaluacionDesempenio_Tipo] FOREIGN KEY ([IdTipoEvaluacion]) REFERENCES [dbo].[rrhhTipoEvaluacion]([IdTipoEvaluacion])
);
GO

IF OBJECT_ID('dbo.rrhhHistorialCapacitacion', 'U') IS NULL
CREATE TABLE [dbo].[rrhhHistorialCapacitacion](
	[IdHistorialCapacitacion]	INT				IDENTITY(1,1)	NOT NULL,
	[IdEmpleado]				INT				NOT NULL,
	[IdCurso]					INT				NOT NULL,
	[FechaFinalizacion]			DATE			NULL,
	[InsUsuario]				INT				NULL,
	[InsFechaHora]				DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	CONSTRAINT [PK_rrhhHistorialCapacitacion] PRIMARY KEY CLUSTERED ([IdHistorialCapacitacion]),
	CONSTRAINT [FK_rrhhHistorialCapacitacion_Empleado] FOREIGN KEY ([IdEmpleado]) REFERENCES [dbo].[rrhhEmpleado]([IdEmpleado]),
	CONSTRAINT [FK_rrhhHistorialCapacitacion_Curso] FOREIGN KEY ([IdCurso]) REFERENCES [dbo].[rrhhCurso]([IdCurso])
);
GO

------------------------------------------------------------
-- Nómina
------------------------------------------------------------
IF OBJECT_ID('dbo.rrhhTipoMovimientoNomina', 'U') IS NULL
CREATE TABLE [dbo].[rrhhTipoMovimientoNomina](
	[IdTipoMovimientoNomina]	INT				IDENTITY(1,1)	NOT NULL,
	[Codigo]					VARCHAR(20)		NOT NULL,
	[Descripcion]				VARCHAR(100)	NOT NULL,
	[Naturaleza]				CHAR(1)			NOT NULL,	-- I = ingreso (suma), D = descuento (resta)
	[FormaCalculo]				CHAR(1)			NOT NULL,	-- S = sueldo base, F = monto fijo mensual, P = porcentaje, M = manual
	[Valor]						NUMERIC(12, 4)	NOT NULL DEFAULT (0),	-- monto (F) o porcentaje (P)
	[EsAutomatico]				BIT				NOT NULL DEFAULT (0),	-- se aplica solo a todos los empleados
	[EsBaseCalculo]				BIT				NOT NULL DEFAULT (0),	-- el ingreso forma parte de la base de los porcentajes (IGSS)
	[Orden]						SMALLINT		NOT NULL DEFAULT (0),
	[cta_id]					INT				NULL,		-- cuenta contable para la partida de nómina
	[Estado]					CHAR(1)			NOT NULL DEFAULT ('A'),
	[InsUsuario]				INT				NULL,
	[InsFechaHora]				DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]				INT				NULL,
	[UpdFechaHora]				DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhTipoMovimientoNomina] PRIMARY KEY CLUSTERED ([IdTipoMovimientoNomina]),
	CONSTRAINT [UQ_rrhhTipoMovimientoNomina_Codigo] UNIQUE ([Codigo]),
	CONSTRAINT [CK_rrhhTipoMovimientoNomina_Naturaleza] CHECK ([Naturaleza] IN ('I','D')),
	CONSTRAINT [CK_rrhhTipoMovimientoNomina_FormaCalculo] CHECK ([FormaCalculo] IN ('S','F','P','M')),
	CONSTRAINT [CK_rrhhTipoMovimientoNomina_Sueldo] CHECK ([FormaCalculo] <> 'S' OR [Naturaleza] = 'I'),
	CONSTRAINT [CK_rrhhTipoMovimientoNomina_Base] CHECK ([EsBaseCalculo] = 0 OR [Naturaleza] = 'I'),
	CONSTRAINT [CK_rrhhTipoMovimientoNomina_Valor] CHECK ([Valor] >= 0),
	CONSTRAINT [CK_rrhhTipoMovimientoNomina_Estado] CHECK ([Estado] IN ('A','I')),
	CONSTRAINT [FK_rrhhTipoMovimientoNomina_Cuenta] FOREIGN KEY ([cta_id]) REFERENCES [dbo].[cont_cuenta_contable]([cta_id])
);
GO

IF OBJECT_ID('dbo.rrhhNomina', 'U') IS NULL
CREATE TABLE [dbo].[rrhhNomina](
	[IdNomina]			INT				IDENTITY(1,1)	NOT NULL,
	[cia_id]			INT				NOT NULL,
	[Descripcion]		VARCHAR(100)	NOT NULL,
	[TipoPeriodo]		CHAR(1)			NOT NULL,	-- M = mensual, Q = quincenal
	[FechaDel]			DATE			NOT NULL,
	[FechaAl]			DATE			NOT NULL,
	[FechaPago]			DATE			NULL,
	[TotalIngresos]		NUMERIC(14, 2)	NOT NULL DEFAULT (0),
	[TotalDescuentos]	NUMERIC(14, 2)	NOT NULL DEFAULT (0),
	[TotalLiquido]		NUMERIC(14, 2)	NOT NULL DEFAULT (0),
	[Estado]			CHAR(1)			NOT NULL DEFAULT ('B'),	-- B = borrador, C = calculada, A = aprobada, N = anulada
	[FechaCalculo]		DATETIME2(0)	NULL,
	[UsuarioAprobo]		INT				NULL,
	[FechaAprobacion]	DATETIME2(0)	NULL,
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhNomina] PRIMARY KEY CLUSTERED ([IdNomina]),
	CONSTRAINT [CK_rrhhNomina_TipoPeriodo] CHECK ([TipoPeriodo] IN ('M','Q')),
	CONSTRAINT [CK_rrhhNomina_Estado] CHECK ([Estado] IN ('B','C','A','N')),
	CONSTRAINT [CK_rrhhNomina_Fechas] CHECK ([FechaAl] >= [FechaDel]),
	CONSTRAINT [FK_rrhhNomina_Compania] FOREIGN KEY ([cia_id]) REFERENCES [dbo].[gen_compania]([cia_id]),
	CONSTRAINT [FK_rrhhNomina_UsuarioAprobo] FOREIGN KEY ([UsuarioAprobo]) REFERENCES [dbo].[gen_usuario]([usu_id])
);
GO

IF OBJECT_ID('dbo.rrhhNominaEmpleado', 'U') IS NULL
CREATE TABLE [dbo].[rrhhNominaEmpleado](
	[IdNominaEmpleado]	INT				IDENTITY(1,1)	NOT NULL,
	[IdNomina]			INT				NOT NULL,
	[IdEmpleado]		INT				NOT NULL,
	[SalarioBase]		NUMERIC(12, 2)	NOT NULL,
	[DiasLaborados]		NUMERIC(5, 2)	NOT NULL,
	[TotalIngresos]		NUMERIC(14, 2)	NOT NULL DEFAULT (0),
	[TotalDescuentos]	NUMERIC(14, 2)	NOT NULL DEFAULT (0),
	[Liquido]			NUMERIC(14, 2)	NOT NULL DEFAULT (0),
	CONSTRAINT [PK_rrhhNominaEmpleado] PRIMARY KEY CLUSTERED ([IdNominaEmpleado]),
	CONSTRAINT [UQ_rrhhNominaEmpleado] UNIQUE ([IdNomina], [IdEmpleado]),
	CONSTRAINT [FK_rrhhNominaEmpleado_Nomina] FOREIGN KEY ([IdNomina]) REFERENCES [dbo].[rrhhNomina]([IdNomina]),
	CONSTRAINT [FK_rrhhNominaEmpleado_Empleado] FOREIGN KEY ([IdEmpleado]) REFERENCES [dbo].[rrhhEmpleado]([IdEmpleado])
);
GO

IF OBJECT_ID('dbo.rrhhMovimientoNomina', 'U') IS NULL
CREATE TABLE [dbo].[rrhhMovimientoNomina](
	[IdMovimientoNomina]		INT				IDENTITY(1,1)	NOT NULL,
	[IdEmpleado]				INT				NOT NULL,
	[IdTipoMovimientoNomina]	INT				NOT NULL,
	[Descripcion]				VARCHAR(200)	NULL,
	[Monto]						NUMERIC(12, 2)	NOT NULL,
	[FechaAplicacion]			DATE			NOT NULL,
	[IdNomina]					INT				NULL,	-- nómina aprobada en la que se aplicó
	[Estado]					CHAR(1)			NOT NULL DEFAULT ('A'),	-- A = activo, N = anulado
	[InsUsuario]				INT				NULL,
	[InsFechaHora]				DATETIME2(0)	NOT NULL DEFAULT (SYSDATETIME()),
	[UpdUsuario]				INT				NULL,
	[UpdFechaHora]				DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhMovimientoNomina] PRIMARY KEY CLUSTERED ([IdMovimientoNomina]),
	CONSTRAINT [CK_rrhhMovimientoNomina_Monto] CHECK ([Monto] > 0),
	CONSTRAINT [CK_rrhhMovimientoNomina_Estado] CHECK ([Estado] IN ('A','N')),
	CONSTRAINT [FK_rrhhMovimientoNomina_Empleado] FOREIGN KEY ([IdEmpleado]) REFERENCES [dbo].[rrhhEmpleado]([IdEmpleado]),
	CONSTRAINT [FK_rrhhMovimientoNomina_Tipo] FOREIGN KEY ([IdTipoMovimientoNomina]) REFERENCES [dbo].[rrhhTipoMovimientoNomina]([IdTipoMovimientoNomina]),
	CONSTRAINT [FK_rrhhMovimientoNomina_Nomina] FOREIGN KEY ([IdNomina]) REFERENCES [dbo].[rrhhNomina]([IdNomina])
);
GO

IF OBJECT_ID('dbo.rrhhNominaDetalle', 'U') IS NULL
CREATE TABLE [dbo].[rrhhNominaDetalle](
	[IdNominaDetalle]			INT				IDENTITY(1,1)	NOT NULL,
	[IdNominaEmpleado]			INT				NOT NULL,
	[IdTipoMovimientoNomina]	INT				NOT NULL,
	[IdMovimientoNomina]		INT				NULL,
	[Naturaleza]				CHAR(1)			NOT NULL,
	[Descripcion]				VARCHAR(200)	NOT NULL,
	[Monto]						NUMERIC(12, 2)	NOT NULL,
	CONSTRAINT [PK_rrhhNominaDetalle] PRIMARY KEY CLUSTERED ([IdNominaDetalle]),
	CONSTRAINT [CK_rrhhNominaDetalle_Naturaleza] CHECK ([Naturaleza] IN ('I','D')),
	CONSTRAINT [FK_rrhhNominaDetalle_NominaEmpleado] FOREIGN KEY ([IdNominaEmpleado]) REFERENCES [dbo].[rrhhNominaEmpleado]([IdNominaEmpleado]),
	CONSTRAINT [FK_rrhhNominaDetalle_Tipo] FOREIGN KEY ([IdTipoMovimientoNomina]) REFERENCES [dbo].[rrhhTipoMovimientoNomina]([IdTipoMovimientoNomina]),
	CONSTRAINT [FK_rrhhNominaDetalle_Movimiento] FOREIGN KEY ([IdMovimientoNomina]) REFERENCES [dbo].[rrhhMovimientoNomina]([IdMovimientoNomina])
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rrhhMovimientoNomina_Empleado_Fecha')
	CREATE INDEX [IX_rrhhMovimientoNomina_Empleado_Fecha] ON [dbo].[rrhhMovimientoNomina]([IdEmpleado], [FechaAplicacion]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rrhhNominaDetalle_NominaEmpleado')
	CREATE INDEX [IX_rrhhNominaDetalle_NominaEmpleado] ON [dbo].[rrhhNominaDetalle]([IdNominaEmpleado]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rrhhEmpleado_Compania')
	CREATE INDEX [IX_rrhhEmpleado_Compania] ON [dbo].[rrhhEmpleado]([cia_id], [Estado]);
GO

------------------------------------------------------------
-- Relación persona - usuario - vendedor
--
-- La persona es el empleado. El usuario del sistema y el vendedor son dos
-- roles que esa persona puede tener, así que ambos apuntan al empleado en
-- lugar de relacionarse directamente entre sí: un vendedor puede no tener
-- usuario (vende y otro captura) y un usuario puede no ser vendedor
-- (cajero, contador). Del usuario con sesión iniciada se llega a su
-- vendedor por usuario -> empleado -> vendedor. Ambas columnas son
-- opcionales para no obligar a dar de alta en RRHH a quien no es empleado
-- (p. ej. un vendedor externo por comisión).
------------------------------------------------------------
IF COL_LENGTH('dbo.gen_usuario', 'IdEmpleado') IS NULL
	ALTER TABLE [dbo].[gen_usuario] ADD [IdEmpleado] INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_gen_usuario_Empleado')
	ALTER TABLE [dbo].[gen_usuario] ADD CONSTRAINT [FK_gen_usuario_Empleado] FOREIGN KEY ([IdEmpleado]) REFERENCES [dbo].[rrhhEmpleado]([IdEmpleado]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_gen_usuario_IdEmpleado')
	CREATE UNIQUE INDEX [UX_gen_usuario_IdEmpleado] ON [dbo].[gen_usuario]([IdEmpleado]) WHERE [IdEmpleado] IS NOT NULL;
GO

IF COL_LENGTH('dbo.pos_vendedor', 'IdEmpleado') IS NULL
	ALTER TABLE [dbo].[pos_vendedor] ADD [IdEmpleado] INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_pos_vendedor_Empleado')
	ALTER TABLE [dbo].[pos_vendedor] ADD CONSTRAINT [FK_pos_vendedor_Empleado] FOREIGN KEY ([IdEmpleado]) REFERENCES [dbo].[rrhhEmpleado]([IdEmpleado]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_pos_vendedor_IdEmpleado')
	CREATE UNIQUE INDEX [UX_pos_vendedor_IdEmpleado] ON [dbo].[pos_vendedor]([IdEmpleado]) WHERE [IdEmpleado] IS NOT NULL;
GO

------------------------------------------------------------
-- Datos iniciales
------------------------------------------------------------
INSERT INTO dbo.rrhhTipoDocumentoIdentificacion (Descripcion)
SELECT v.d FROM (VALUES ('DPI'), ('Pasaporte')) v(d)
WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhTipoDocumentoIdentificacion t WHERE t.Descripcion = v.d);

INSERT INTO dbo.rrhhTipoTelefono (Descripcion)
SELECT v.d FROM (VALUES ('Celular'), ('Casa'), ('Trabajo')) v(d)
WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhTipoTelefono t WHERE t.Descripcion = v.d);

INSERT INTO dbo.rrhhTipoEscolaridad (Descripcion)
SELECT v.d FROM (VALUES ('Primaria'), ('Básicos'), ('Diversificado'), ('Universidad'), ('Postgrado')) v(d)
WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhTipoEscolaridad t WHERE t.Descripcion = v.d);

INSERT INTO dbo.rrhhTipoEvaluacion (Descripcion)
SELECT v.d FROM (VALUES ('Período de prueba'), ('Anual')) v(d)
WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhTipoEvaluacion t WHERE t.Descripcion = v.d);

INSERT INTO dbo.rrhhTipoRequisito (Descripcion)
SELECT v.d FROM (VALUES ('Académico'), ('Experiencia'), ('Certificación')) v(d)
WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhTipoRequisito t WHERE t.Descripcion = v.d);

-- Tipos de movimiento de nómina de uso general en Guatemala. Los valores
-- legales (IGSS laboral 4.83%, bonificación incentivo Q250 del Decreto
-- 37-2001) quedan como datos editables, no como reglas en el código.
INSERT INTO dbo.rrhhTipoMovimientoNomina (Codigo, Descripcion, Naturaleza, FormaCalculo, Valor, EsAutomatico, EsBaseCalculo, Orden)
SELECT v.Codigo, v.Descripcion, v.Naturaleza, v.FormaCalculo, v.Valor, v.EsAutomatico, v.EsBaseCalculo, v.Orden
FROM (VALUES
	('SUELDO',          'Sueldo ordinario',            'I', 'S', 0,      1, 1, 10),
	('HORAS_EXTRA',     'Horas extra',                 'I', 'M', 0,      0, 1, 20),
	('COMISION',        'Comisiones sobre ventas',     'I', 'M', 0,      0, 1, 30),
	('BONIF_INCENTIVO', 'Bonificación incentivo',      'I', 'F', 250,    1, 0, 40),
	('OTRO_INGRESO',    'Otros ingresos',              'I', 'M', 0,      0, 0, 50),
	('IGSS_LABORAL',    'IGSS cuota laboral',          'D', 'P', 4.83,   1, 0, 110),
	('ISR',             'Retención ISR',               'D', 'M', 0,      0, 0, 120),
	('ANTICIPO',        'Anticipo de sueldo',          'D', 'M', 0,      0, 0, 130),
	('PRESTAMO',        'Descuento por préstamo',      'D', 'M', 0,      0, 0, 140),
	('OTRO_DESCUENTO',  'Otros descuentos',            'D', 'M', 0,      0, 0, 150)
) v(Codigo, Descripcion, Naturaleza, FormaCalculo, Valor, EsAutomatico, EsBaseCalculo, Orden)
WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhTipoMovimientoNomina t WHERE t.Codigo = v.Codigo);
GO

------------------------------------------------------------
-- Procedimientos: catálogos simples
--
-- Los siete catálogos de Id + Descripcion + Estado comparten el mismo
-- mantenimiento. El nombre de la tabla nunca viene del usuario: se toma de
-- la lista fija de abajo y cualquier otro valor se rechaza.
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhCatalogoTabla]
	@Catalogo	VARCHAR(50),
	@Tabla		SYSNAME OUTPUT,
	@ColumnaId	SYSNAME OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT @Tabla = cata.Tabla, @ColumnaId = cata.ColumnaId
	FROM (VALUES
		('UnidadOrganizativa',          'rrhhUnidadOrganizativa',          'IdUnidadOrganizativa'),
		('TipoRequisito',               'rrhhTipoRequisito',               'IdTipoRequisito'),
		('TipoDocumentoIdentificacion', 'rrhhTipoDocumentoIdentificacion', 'IdTipoDocumentoIdentificacion'),
		('TipoTelefono',                'rrhhTipoTelefono',                'IdTipoTelefono'),
		('TipoEscolaridad',             'rrhhTipoEscolaridad',             'IdTipoEscolaridad'),
		('TipoEvaluacion',              'rrhhTipoEvaluacion',              'IdTipoEvaluacion'),
		('Curso',                       'rrhhCurso',                       'IdCurso')
	) cata(Catalogo, Tabla, ColumnaId)
	WHERE cata.Catalogo = @Catalogo;

	IF @Tabla IS NULL
		THROW 52001, 'El catálogo indicado no existe.', 1;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhCatalogoConsultar]
	@Catalogo		VARCHAR(50),
	@SoloActivos	BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Tabla SYSNAME, @ColumnaId SYSNAME;
	EXEC dbo.paRrhhCatalogoTabla @Catalogo, @Tabla OUTPUT, @ColumnaId OUTPUT;

	DECLARE @sql NVARCHAR(MAX) = N'SELECT ' + QUOTENAME(@ColumnaId) + N' AS Id, Descripcion, Estado FROM dbo.' + QUOTENAME(@Tabla)
		+ N' WHERE (@SoloActivos = 0 OR Estado = ''A'') ORDER BY Descripcion;';
	EXEC sp_executesql @sql, N'@SoloActivos BIT', @SoloActivos;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhCatalogoGuardar]
	@Catalogo		VARCHAR(50),
	@Id				INT = NULL,
	@Descripcion	VARCHAR(100),
	@UsuId			INT,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Tabla SYSNAME, @ColumnaId SYSNAME;
	EXEC dbo.paRrhhCatalogoTabla @Catalogo, @Tabla OUTPUT, @ColumnaId OUTPUT;

	SET @Descripcion = LTRIM(RTRIM(@Descripcion));
	IF ISNULL(@Descripcion, '') = ''
		THROW 52002, 'La descripción es obligatoria.', 1;

	DECLARE @existe INT;
	DECLARE @sql NVARCHAR(MAX) = N'SELECT @existe = ' + QUOTENAME(@ColumnaId) + N' FROM dbo.' + QUOTENAME(@Tabla)
		+ N' WHERE Descripcion = @Descripcion AND (@Id IS NULL OR ' + QUOTENAME(@ColumnaId) + N' <> @Id);';
	EXEC sp_executesql @sql, N'@Descripcion VARCHAR(100), @Id INT, @existe INT OUTPUT', @Descripcion, @Id, @existe OUTPUT;
	IF @existe IS NOT NULL
		THROW 52003, 'Ya existe un registro con esa descripción.', 1;

	IF @Id IS NULL
	BEGIN
		SET @sql = N'INSERT INTO dbo.' + QUOTENAME(@Tabla) + N' (Descripcion, InsUsuario) VALUES (@Descripcion, @UsuId); SET @IdResultado = SCOPE_IDENTITY();';
		EXEC sp_executesql @sql, N'@Descripcion VARCHAR(100), @UsuId INT, @IdResultado INT OUTPUT', @Descripcion, @UsuId, @IdResultado OUTPUT;
	END
	ELSE
	BEGIN
		SET @sql = N'UPDATE dbo.' + QUOTENAME(@Tabla) + N' SET Descripcion = @Descripcion, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE '
			+ QUOTENAME(@ColumnaId) + N' = @Id; IF @@ROWCOUNT = 0 THROW 52004, ''El registro no existe.'', 1;';
		EXEC sp_executesql @sql, N'@Descripcion VARCHAR(100), @UsuId INT, @Id INT', @Descripcion, @UsuId, @Id;
		SET @IdResultado = @Id;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhCatalogoCambiarEstado]
	@Catalogo	VARCHAR(50),
	@Id			INT,
	@Estado		CHAR(1),
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	IF @Estado NOT IN ('A','I')
		THROW 52005, 'El estado debe ser A (activo) o I (inactivo).', 1;

	DECLARE @Tabla SYSNAME, @ColumnaId SYSNAME;
	EXEC dbo.paRrhhCatalogoTabla @Catalogo, @Tabla OUTPUT, @ColumnaId OUTPUT;

	DECLARE @sql NVARCHAR(MAX) = N'UPDATE dbo.' + QUOTENAME(@Tabla) + N' SET Estado = @Estado, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE '
		+ QUOTENAME(@ColumnaId) + N' = @Id;';
	EXEC sp_executesql @sql, N'@Estado CHAR(1), @UsuId INT, @Id INT', @Estado, @UsuId, @Id;
END;
GO

------------------------------------------------------------
-- Procedimientos: departamento, puesto y plaza
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhDepartamentoConsultar]
	@SoloActivos BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT depa.IdDepartamento, depa.Descripcion, depa.IdUnidadOrganizativa, unid.Descripcion AS UnidadOrganizativa,
		   depa.suc_id, sucu.suc_descripcion, depa.Estado
	FROM dbo.rrhhDepartamento depa
	LEFT JOIN dbo.rrhhUnidadOrganizativa unid ON unid.IdUnidadOrganizativa = depa.IdUnidadOrganizativa
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_id = depa.suc_id
	WHERE @SoloActivos = 0 OR depa.Estado = 'A'
	ORDER BY depa.Descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhDepartamentoGuardar]
	@IdDepartamento			INT = NULL,
	@Descripcion			VARCHAR(100),
	@IdUnidadOrganizativa	INT = NULL,
	@SucId					INT = NULL,
	@Estado					CHAR(1) = 'A',
	@UsuId					INT,
	@IdResultado			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(LTRIM(RTRIM(@Descripcion)), '') = ''
		THROW 52010, 'La descripción del departamento es obligatoria.', 1;
	IF EXISTS (SELECT 1 FROM dbo.rrhhDepartamento WHERE Descripcion = @Descripcion AND (@IdDepartamento IS NULL OR IdDepartamento <> @IdDepartamento))
		THROW 52011, 'Ya existe un departamento con esa descripción.', 1;

	IF @IdDepartamento IS NULL
	BEGIN
		INSERT INTO dbo.rrhhDepartamento (Descripcion, IdUnidadOrganizativa, suc_id, Estado, InsUsuario)
		VALUES (@Descripcion, @IdUnidadOrganizativa, @SucId, @Estado, @UsuId);
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.rrhhDepartamento
		   SET Descripcion = @Descripcion, IdUnidadOrganizativa = @IdUnidadOrganizativa, suc_id = @SucId, Estado = @Estado,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE IdDepartamento = @IdDepartamento;
		SET @IdResultado = @IdDepartamento;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhPuestoConsultar]
	@SoloActivos BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT IdPuesto, Descripcion, SalarioMinimo, SalarioMaximo, Estado
	FROM dbo.rrhhPuesto
	WHERE @SoloActivos = 0 OR Estado = 'A'
	ORDER BY Descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhPuestoGuardar]
	@IdPuesto		INT = NULL,
	@Descripcion	VARCHAR(100),
	@SalarioMinimo	NUMERIC(12, 2),
	@SalarioMaximo	NUMERIC(12, 2),
	@Estado			CHAR(1) = 'A',
	@UsuId			INT,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(LTRIM(RTRIM(@Descripcion)), '') = ''
		THROW 52020, 'La descripción del puesto es obligatoria.', 1;
	IF @SalarioMaximo < @SalarioMinimo
		THROW 52021, 'El salario máximo no puede ser menor que el mínimo.', 1;
	IF EXISTS (SELECT 1 FROM dbo.rrhhPuesto WHERE Descripcion = @Descripcion AND (@IdPuesto IS NULL OR IdPuesto <> @IdPuesto))
		THROW 52022, 'Ya existe un puesto con esa descripción.', 1;

	IF @IdPuesto IS NULL
	BEGIN
		INSERT INTO dbo.rrhhPuesto (Descripcion, SalarioMinimo, SalarioMaximo, Estado, InsUsuario)
		VALUES (@Descripcion, @SalarioMinimo, @SalarioMaximo, @Estado, @UsuId);
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.rrhhPuesto
		   SET Descripcion = @Descripcion, SalarioMinimo = @SalarioMinimo, SalarioMaximo = @SalarioMaximo, Estado = @Estado,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE IdPuesto = @IdPuesto;
		SET @IdResultado = @IdPuesto;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhPlazaConsultar]
	@SoloActivos BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT plaz.IdPlaza, plaz.Descripcion, plaz.Estado,
		   depu.IdDepartamento, depa.Descripcion AS Departamento,
		   depu.IdPuesto, pues.Descripcion AS Puesto,
		   ocup.IdEmpleado AS IdEmpleadoOcupante,
		   ocup.PrimerNombre + ' ' + ocup.PrimerApellido AS EmpleadoOcupante
	FROM dbo.rrhhPlaza plaz
	INNER JOIN dbo.rrhhDepartamentoPuesto depu ON depu.IdDepartamentoPuesto = plaz.IdDepartamentoPuesto
	INNER JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = depu.IdDepartamento
	INNER JOIN dbo.rrhhPuesto pues ON pues.IdPuesto = depu.IdPuesto
	OUTER APPLY (SELECT TOP 1 empl.IdEmpleado, empl.PrimerNombre, empl.PrimerApellido
				 FROM dbo.rrhhEmpleado empl WHERE empl.IdPlaza = plaz.IdPlaza AND empl.Estado = 'A') ocup
	WHERE @SoloActivos = 0 OR plaz.Estado = 'A'
	ORDER BY depa.Descripcion, plaz.Descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhPlazaGuardar]
	@IdPlaza		INT = NULL,
	@Descripcion	VARCHAR(100),
	@IdDepartamento	INT,
	@IdPuesto		INT,
	@Estado			CHAR(1) = 'A',
	@UsuId			INT,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(LTRIM(RTRIM(@Descripcion)), '') = ''
		THROW 52030, 'La descripción de la plaza es obligatoria.', 1;
	IF EXISTS (SELECT 1 FROM dbo.rrhhPlaza WHERE Descripcion = @Descripcion AND (@IdPlaza IS NULL OR IdPlaza <> @IdPlaza))
		THROW 52031, 'Ya existe una plaza con esa descripción.', 1;

	-- El par departamento-puesto se crea la primera vez que se usa.
	DECLARE @IdDepartamentoPuesto INT = (SELECT IdDepartamentoPuesto FROM dbo.rrhhDepartamentoPuesto WHERE IdDepartamento = @IdDepartamento AND IdPuesto = @IdPuesto);
	IF @IdDepartamentoPuesto IS NULL
	BEGIN
		INSERT INTO dbo.rrhhDepartamentoPuesto (IdDepartamento, IdPuesto, InsUsuario) VALUES (@IdDepartamento, @IdPuesto, @UsuId);
		SET @IdDepartamentoPuesto = SCOPE_IDENTITY();
	END

	IF @IdPlaza IS NULL
	BEGIN
		INSERT INTO dbo.rrhhPlaza (Descripcion, IdDepartamentoPuesto, Estado, InsUsuario)
		VALUES (@Descripcion, @IdDepartamentoPuesto, @Estado, @UsuId);
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.rrhhPlaza
		   SET Descripcion = @Descripcion, IdDepartamentoPuesto = @IdDepartamentoPuesto, Estado = @Estado,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE IdPlaza = @IdPlaza;
		SET @IdResultado = @IdPlaza;
	END
END;
GO

------------------------------------------------------------
-- Procedimientos: empleados
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoConsultar]
	@Filtro	VARCHAR(100) = NULL,
	@Estado	CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT empl.IdEmpleado, empl.CodigoEmpleado,
		   LTRIM(CONCAT(empl.PrimerNombre, ' ', empl.SegundoNombre)) AS Nombres,
		   LTRIM(CONCAT(empl.PrimerApellido, ' ', empl.SegundoApellido)) AS Apellidos,
		   empl.FechaIngreso, empl.FechaBaja, empl.SalarioBase, empl.Estado,
		   plaz.Descripcion AS Plaza, pues.Descripcion AS Puesto, depa.Descripcion AS Departamento
	FROM dbo.rrhhEmpleado empl
	LEFT JOIN dbo.rrhhPlaza plaz ON plaz.IdPlaza = empl.IdPlaza
	LEFT JOIN dbo.rrhhDepartamentoPuesto depu ON depu.IdDepartamentoPuesto = plaz.IdDepartamentoPuesto
	LEFT JOIN dbo.rrhhPuesto pues ON pues.IdPuesto = depu.IdPuesto
	LEFT JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = depu.IdDepartamento
	WHERE (@Estado IS NULL OR empl.Estado = @Estado)
	  AND (@Filtro IS NULL OR empl.CodigoEmpleado LIKE '%' + @Filtro + '%'
		   OR CONCAT(empl.PrimerNombre, ' ', empl.SegundoNombre, ' ', empl.PrimerApellido, ' ', empl.SegundoApellido) LIKE '%' + @Filtro + '%')
	ORDER BY empl.PrimerApellido, empl.PrimerNombre;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoConsultarPorId]
	@IdEmpleado INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT empl.*,
		   (SELECT TOP 1 usua.usu_id FROM dbo.gen_usuario usua WHERE usua.IdEmpleado = empl.IdEmpleado) AS usu_id,
		   (SELECT TOP 1 vend.pve_id FROM dbo.pos_vendedor vend WHERE vend.IdEmpleado = empl.IdEmpleado) AS pve_id
	FROM dbo.rrhhEmpleado empl
	WHERE empl.IdEmpleado = @IdEmpleado;

	SELECT hist.IdHistorialPlaza, hist.IdPlaza, plaz.Descripcion AS Plaza, hist.FechaDel, hist.FechaAl, hist.Salario
	FROM dbo.rrhhHistorialPlaza hist
	INNER JOIN dbo.rrhhPlaza plaz ON plaz.IdPlaza = hist.IdPlaza
	WHERE hist.IdEmpleado = @IdEmpleado
	ORDER BY hist.FechaDel DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoGuardar]
	@IdEmpleado						INT = NULL,
	@CodigoEmpleado					VARCHAR(16),
	@CiaId							INT,
	@PrimerNombre					VARCHAR(50),
	@SegundoNombre					VARCHAR(50) = NULL,
	@PrimerApellido					VARCHAR(50),
	@SegundoApellido				VARCHAR(50) = NULL,
	@ApellidoCasada					VARCHAR(50) = NULL,
	@Genero							CHAR(1) = NULL,
	@FechaNacimiento				DATE = NULL,
	@FechaIngreso					DATE,
	@Direccion						VARCHAR(200) = NULL,
	@IdTipoDocumentoIdentificacion	INT = NULL,
	@NumeroDocumento				VARCHAR(32) = NULL,
	@NumeroAfiliacionIGSS			VARCHAR(20) = NULL,
	@Nit							VARCHAR(20) = NULL,
	@Email							VARCHAR(100) = NULL,
	@IdPlaza						INT = NULL,
	@SalarioBase					NUMERIC(12, 2),
	@UsuId							INT,
	@IdResultado					INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF ISNULL(LTRIM(RTRIM(@CodigoEmpleado)), '') = '' OR ISNULL(LTRIM(RTRIM(@PrimerNombre)), '') = '' OR ISNULL(LTRIM(RTRIM(@PrimerApellido)), '') = ''
		THROW 52040, 'El código, el primer nombre y el primer apellido son obligatorios.', 1;
	IF @SalarioBase < 0
		THROW 52041, 'El salario base no puede ser negativo.', 1;
	IF EXISTS (SELECT 1 FROM dbo.rrhhEmpleado WHERE CodigoEmpleado = @CodigoEmpleado AND (@IdEmpleado IS NULL OR IdEmpleado <> @IdEmpleado))
		THROW 52042, 'Ya existe un empleado con ese código.', 1;
	IF @IdPlaza IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.rrhhEmpleado WHERE IdPlaza = @IdPlaza AND Estado = 'A' AND (@IdEmpleado IS NULL OR IdEmpleado <> @IdEmpleado))
		THROW 52043, 'La plaza ya está ocupada por otro empleado activo.', 1;

	DECLARE @PlazaAnterior INT, @SalarioAnterior NUMERIC(12, 2);
	SELECT @PlazaAnterior = IdPlaza, @SalarioAnterior = SalarioBase FROM dbo.rrhhEmpleado WHERE IdEmpleado = @IdEmpleado;

	BEGIN TRANSACTION;

	IF @IdEmpleado IS NULL
	BEGIN
		INSERT INTO dbo.rrhhEmpleado (CodigoEmpleado, cia_id, PrimerNombre, SegundoNombre, PrimerApellido, SegundoApellido, ApellidoCasada,
			Genero, FechaNacimiento, FechaIngreso, Direccion, IdTipoDocumentoIdentificacion, NumeroDocumento, NumeroAfiliacionIGSS, Nit, Email,
			IdPlaza, SalarioBase, InsUsuario)
		VALUES (@CodigoEmpleado, @CiaId, @PrimerNombre, @SegundoNombre, @PrimerApellido, @SegundoApellido, @ApellidoCasada,
			@Genero, @FechaNacimiento, @FechaIngreso, @Direccion, @IdTipoDocumentoIdentificacion, @NumeroDocumento, @NumeroAfiliacionIGSS, @Nit, @Email,
			@IdPlaza, @SalarioBase, @UsuId);
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.rrhhEmpleado
		   SET CodigoEmpleado = @CodigoEmpleado, cia_id = @CiaId, PrimerNombre = @PrimerNombre, SegundoNombre = @SegundoNombre,
			   PrimerApellido = @PrimerApellido, SegundoApellido = @SegundoApellido, ApellidoCasada = @ApellidoCasada, Genero = @Genero,
			   FechaNacimiento = @FechaNacimiento, FechaIngreso = @FechaIngreso, Direccion = @Direccion,
			   IdTipoDocumentoIdentificacion = @IdTipoDocumentoIdentificacion, NumeroDocumento = @NumeroDocumento,
			   NumeroAfiliacionIGSS = @NumeroAfiliacionIGSS, Nit = @Nit, Email = @Email, IdPlaza = @IdPlaza, SalarioBase = @SalarioBase,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE IdEmpleado = @IdEmpleado;
		SET @IdResultado = @IdEmpleado;
	END

	-- Cada cambio de plaza o de salario abre un nuevo tramo en el historial.
	IF @IdPlaza IS NOT NULL AND (@IdEmpleado IS NULL OR ISNULL(@PlazaAnterior, 0) <> @IdPlaza OR ISNULL(@SalarioAnterior, -1) <> @SalarioBase)
	BEGIN
		DECLARE @Hoy DATE = CAST(SYSDATETIME() AS DATE);
		DECLARE @Desde DATE = CASE WHEN @IdEmpleado IS NULL THEN @FechaIngreso ELSE @Hoy END;

		UPDATE dbo.rrhhHistorialPlaza SET FechaAl = DATEADD(DAY, -1, @Desde)
		 WHERE IdEmpleado = @IdResultado AND FechaAl IS NULL AND FechaDel < @Desde;
		DELETE FROM dbo.rrhhHistorialPlaza WHERE IdEmpleado = @IdResultado AND FechaAl IS NULL AND FechaDel >= @Desde;

		INSERT INTO dbo.rrhhHistorialPlaza (IdEmpleado, IdPlaza, FechaDel, Salario, InsUsuario)
		VALUES (@IdResultado, @IdPlaza, @Desde, @SalarioBase, @UsuId);
	END

	COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoDarBaja]
	@IdEmpleado	INT,
	@FechaBaja	DATE,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	IF EXISTS (SELECT 1 FROM dbo.rrhhEmpleado WHERE IdEmpleado = @IdEmpleado AND FechaIngreso > @FechaBaja)
		THROW 52044, 'La fecha de baja no puede ser anterior a la fecha de ingreso.', 1;

	UPDATE dbo.rrhhEmpleado
	   SET Estado = 'B', FechaBaja = @FechaBaja, IdPlaza = NULL, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdEmpleado = @IdEmpleado;

	UPDATE dbo.rrhhHistorialPlaza SET FechaAl = @FechaBaja WHERE IdEmpleado = @IdEmpleado AND FechaAl IS NULL;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoReactivar]
	@IdEmpleado	INT,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	UPDATE dbo.rrhhEmpleado
	   SET Estado = 'A', FechaBaja = NULL, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdEmpleado = @IdEmpleado;
END;
GO

------------------------------------------------------------
-- Procedimientos: tipos de movimiento y movimientos de nómina
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhTipoMovimientoNominaConsultar]
	@SoloActivos BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT tipo.IdTipoMovimientoNomina, tipo.Codigo, tipo.Descripcion, tipo.Naturaleza, tipo.FormaCalculo, tipo.Valor,
		   tipo.EsAutomatico, tipo.EsBaseCalculo, tipo.Orden, tipo.cta_id, cuen.cta_codigo, cuen.cta_nombre, tipo.Estado
	FROM dbo.rrhhTipoMovimientoNomina tipo
	LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = tipo.cta_id
	WHERE @SoloActivos = 0 OR tipo.Estado = 'A'
	ORDER BY tipo.Naturaleza DESC, tipo.Orden, tipo.Descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhTipoMovimientoNominaGuardar]
	@IdTipoMovimientoNomina	INT = NULL,
	@Codigo					VARCHAR(20),
	@Descripcion			VARCHAR(100),
	@Naturaleza				CHAR(1),
	@FormaCalculo			CHAR(1),
	@Valor					NUMERIC(12, 4),
	@EsAutomatico			BIT,
	@EsBaseCalculo			BIT,
	@Orden					SMALLINT,
	@CtaId					INT = NULL,
	@Estado					CHAR(1) = 'A',
	@UsuId					INT,
	@IdResultado			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(LTRIM(RTRIM(@Codigo)), '') = '' OR ISNULL(LTRIM(RTRIM(@Descripcion)), '') = ''
		THROW 52050, 'El código y la descripción son obligatorios.', 1;
	IF @Naturaleza NOT IN ('I','D')
		THROW 52051, 'La naturaleza debe ser Ingreso (suma) o Descuento (resta).', 1;
	IF @FormaCalculo NOT IN ('S','F','P','M')
		THROW 52052, 'La forma de cálculo no es válida.', 1;
	IF @FormaCalculo = 'S' AND @Naturaleza <> 'I'
		THROW 52053, 'El sueldo base solo puede ser un ingreso.', 1;
	IF @EsBaseCalculo = 1 AND @Naturaleza <> 'I'
		THROW 52054, 'Solo un ingreso puede formar parte de la base para porcentajes.', 1;
	IF @FormaCalculo = 'P' AND (@Valor <= 0 OR @Valor > 100)
		THROW 52055, 'El porcentaje debe ser mayor que 0 y no mayor que 100.', 1;
	IF @FormaCalculo = 'M' AND @EsAutomatico = 1
		THROW 52056, 'Un movimiento manual no puede ser automático: se captura por empleado.', 1;
	IF EXISTS (SELECT 1 FROM dbo.rrhhTipoMovimientoNomina WHERE Codigo = @Codigo AND (@IdTipoMovimientoNomina IS NULL OR IdTipoMovimientoNomina <> @IdTipoMovimientoNomina))
		THROW 52057, 'Ya existe un tipo de movimiento con ese código.', 1;

	IF @IdTipoMovimientoNomina IS NULL
	BEGIN
		INSERT INTO dbo.rrhhTipoMovimientoNomina (Codigo, Descripcion, Naturaleza, FormaCalculo, Valor, EsAutomatico, EsBaseCalculo, Orden, cta_id, Estado, InsUsuario)
		VALUES (@Codigo, @Descripcion, @Naturaleza, @FormaCalculo, @Valor, @EsAutomatico, @EsBaseCalculo, @Orden, @CtaId, @Estado, @UsuId);
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.rrhhTipoMovimientoNomina
		   SET Codigo = @Codigo, Descripcion = @Descripcion, Naturaleza = @Naturaleza, FormaCalculo = @FormaCalculo, Valor = @Valor,
			   EsAutomatico = @EsAutomatico, EsBaseCalculo = @EsBaseCalculo, Orden = @Orden, cta_id = @CtaId, Estado = @Estado,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE IdTipoMovimientoNomina = @IdTipoMovimientoNomina;
		SET @IdResultado = @IdTipoMovimientoNomina;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhMovimientoNominaConsultar]
	@IdEmpleado		INT = NULL,
	@FechaDel		DATE = NULL,
	@FechaAl		DATE = NULL,
	@SoloPendientes	BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT movi.IdMovimientoNomina, movi.IdEmpleado, empl.CodigoEmpleado,
		   empl.PrimerNombre + ' ' + empl.PrimerApellido AS Empleado,
		   movi.IdTipoMovimientoNomina, tipo.Descripcion AS TipoMovimiento, tipo.Naturaleza,
		   movi.Descripcion, movi.Monto, movi.FechaAplicacion, movi.IdNomina, nomi.Descripcion AS Nomina, movi.Estado
	FROM dbo.rrhhMovimientoNomina movi
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = movi.IdEmpleado
	INNER JOIN dbo.rrhhTipoMovimientoNomina tipo ON tipo.IdTipoMovimientoNomina = movi.IdTipoMovimientoNomina
	LEFT JOIN dbo.rrhhNomina nomi ON nomi.IdNomina = movi.IdNomina
	WHERE (@IdEmpleado IS NULL OR movi.IdEmpleado = @IdEmpleado)
	  AND (@FechaDel IS NULL OR movi.FechaAplicacion >= @FechaDel)
	  AND (@FechaAl IS NULL OR movi.FechaAplicacion <= @FechaAl)
	  AND (@SoloPendientes = 0 OR (movi.IdNomina IS NULL AND movi.Estado = 'A'))
	ORDER BY movi.FechaAplicacion DESC, empl.PrimerApellido;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhMovimientoNominaGuardar]
	@IdMovimientoNomina		INT = NULL,
	@IdEmpleado				INT,
	@IdTipoMovimientoNomina	INT,
	@Descripcion			VARCHAR(200) = NULL,
	@Monto					NUMERIC(12, 2),
	@FechaAplicacion		DATE,
	@UsuId					INT,
	@IdResultado			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF @Monto <= 0
		THROW 52060, 'El monto debe ser mayor que cero.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhTipoMovimientoNomina WHERE IdTipoMovimientoNomina = @IdTipoMovimientoNomina AND FormaCalculo = 'M' AND Estado = 'A')
		THROW 52061, 'Solo se pueden capturar movimientos de tipos manuales y activos.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhEmpleado WHERE IdEmpleado = @IdEmpleado AND Estado = 'A')
		THROW 52062, 'El empleado no existe o está de baja.', 1;
	IF @IdMovimientoNomina IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.rrhhMovimientoNomina WHERE IdMovimientoNomina = @IdMovimientoNomina AND (IdNomina IS NOT NULL OR Estado <> 'A'))
		THROW 52063, 'El movimiento ya se aplicó en una nómina aprobada o está anulado; no se puede modificar.', 1;

	IF @IdMovimientoNomina IS NULL
	BEGIN
		INSERT INTO dbo.rrhhMovimientoNomina (IdEmpleado, IdTipoMovimientoNomina, Descripcion, Monto, FechaAplicacion, InsUsuario)
		VALUES (@IdEmpleado, @IdTipoMovimientoNomina, @Descripcion, @Monto, @FechaAplicacion, @UsuId);
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.rrhhMovimientoNomina
		   SET IdEmpleado = @IdEmpleado, IdTipoMovimientoNomina = @IdTipoMovimientoNomina, Descripcion = @Descripcion, Monto = @Monto,
			   FechaAplicacion = @FechaAplicacion, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE IdMovimientoNomina = @IdMovimientoNomina;
		SET @IdResultado = @IdMovimientoNomina;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhMovimientoNominaAnular]
	@IdMovimientoNomina	INT,
	@UsuId				INT
AS
BEGIN
	SET NOCOUNT ON;
	IF EXISTS (SELECT 1 FROM dbo.rrhhMovimientoNomina WHERE IdMovimientoNomina = @IdMovimientoNomina AND IdNomina IS NOT NULL)
		THROW 52064, 'El movimiento ya se aplicó en una nómina aprobada; no se puede anular.', 1;

	UPDATE dbo.rrhhMovimientoNomina
	   SET Estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdMovimientoNomina = @IdMovimientoNomina;
END;
GO

------------------------------------------------------------
-- Procedimientos: nómina
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaConsultar]
	@CiaId INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT nomi.IdNomina, nomi.cia_id, comp.cia_nombre_comercial, nomi.Descripcion, nomi.TipoPeriodo, nomi.FechaDel, nomi.FechaAl,
		   nomi.FechaPago, nomi.TotalIngresos, nomi.TotalDescuentos, nomi.TotalLiquido, nomi.Estado, nomi.FechaCalculo, nomi.FechaAprobacion,
		   (SELECT COUNT(*) FROM dbo.rrhhNominaEmpleado nemp WHERE nemp.IdNomina = nomi.IdNomina) AS CantidadEmpleados
	FROM dbo.rrhhNomina nomi
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = nomi.cia_id
	WHERE @CiaId IS NULL OR nomi.cia_id = @CiaId
	ORDER BY nomi.FechaDel DESC, nomi.IdNomina DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaCrear]
	@CiaId			INT,
	@Descripcion	VARCHAR(100),
	@TipoPeriodo	CHAR(1),
	@FechaDel		DATE,
	@FechaAl		DATE,
	@FechaPago		DATE = NULL,
	@UsuId			INT,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF @TipoPeriodo NOT IN ('M','Q')
		THROW 52070, 'El período debe ser mensual o quincenal.', 1;
	IF @FechaAl < @FechaDel
		THROW 52071, 'La fecha final no puede ser anterior a la inicial.', 1;
	IF DATEDIFF(DAY, @FechaDel, @FechaAl) + 1 > CASE @TipoPeriodo WHEN 'M' THEN 31 ELSE 16 END
		THROW 52072, 'El rango de fechas es más largo que el período elegido.', 1;
	IF EXISTS (SELECT 1 FROM dbo.rrhhNomina WHERE cia_id = @CiaId AND Estado <> 'N' AND FechaDel <= @FechaAl AND FechaAl >= @FechaDel)
		THROW 52073, 'Ya existe una nómina de esta compañía que se traslapa con esas fechas.', 1;

	INSERT INTO dbo.rrhhNomina (cia_id, Descripcion, TipoPeriodo, FechaDel, FechaAl, FechaPago, InsUsuario)
	VALUES (@CiaId, @Descripcion, @TipoPeriodo, @FechaDel, @FechaAl, @FechaPago, @UsuId);
	SET @IdResultado = SCOPE_IDENTITY();
END;
GO

-- Calcula (o recalcula) una nómina en borrador o calculada. Se puede correr
-- tantas veces como haga falta antes de aprobarla: borra el cálculo previo
-- y lo vuelve a generar con los datos vigentes.
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaCalcular]
	@IdNomina	INT,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @CiaId INT, @FechaDel DATE, @FechaAl DATE, @TipoPeriodo CHAR(1), @Estado CHAR(1);
	SELECT @CiaId = cia_id, @FechaDel = FechaDel, @FechaAl = FechaAl, @TipoPeriodo = TipoPeriodo, @Estado = Estado
	FROM dbo.rrhhNomina WHERE IdNomina = @IdNomina;

	IF @Estado IS NULL
		THROW 52080, 'La nómina indicada no existe.', 1;
	IF @Estado NOT IN ('B','C')
		THROW 52081, 'Solo se puede calcular una nómina en borrador o ya calculada (no aprobada ni anulada).', 1;

	-- Días base del período: mes comercial de 30 días, quincena de 15.
	DECLARE @DiasPeriodo NUMERIC(5, 2) = CASE @TipoPeriodo WHEN 'M' THEN 30 ELSE 15 END;

	BEGIN TRANSACTION;

	DELETE deta FROM dbo.rrhhNominaDetalle deta
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = deta.IdNominaEmpleado
	WHERE nemp.IdNomina = @IdNomina;
	DELETE FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina;

	-- Empleados que trabajaron al menos un día del período. Si estuvo todo
	-- el período se le pagan los días base completos; si entró o salió a
	-- mitad, los días calendario trabajados (sin pasar de los días base).
	INSERT INTO dbo.rrhhNominaEmpleado (IdNomina, IdEmpleado, SalarioBase, DiasLaborados)
	SELECT @IdNomina, empl.IdEmpleado, empl.SalarioBase,
		   CASE WHEN empl.FechaIngreso <= @FechaDel AND (empl.FechaBaja IS NULL OR empl.FechaBaja >= @FechaAl)
				THEN @DiasPeriodo
				ELSE CASE WHEN rango.Dias > @DiasPeriodo THEN @DiasPeriodo ELSE rango.Dias END
		   END
	FROM dbo.rrhhEmpleado empl
	CROSS APPLY (SELECT CAST(DATEDIFF(DAY,
					CASE WHEN empl.FechaIngreso > @FechaDel THEN empl.FechaIngreso ELSE @FechaDel END,
					CASE WHEN empl.FechaBaja IS NOT NULL AND empl.FechaBaja < @FechaAl THEN empl.FechaBaja ELSE @FechaAl END) + 1 AS NUMERIC(5, 2)) AS Dias) rango
	WHERE empl.cia_id = @CiaId
	  AND empl.FechaIngreso <= @FechaAl
	  AND (empl.FechaBaja IS NULL OR empl.FechaBaja >= @FechaDel)
	  AND (empl.Estado = 'A' OR empl.FechaBaja IS NOT NULL);

	-- 1) Sueldo (S) e ingresos/descuentos fijos (F) automáticos: montos
	--    mensuales proporcionales a los días laborados sobre 30.
	INSERT INTO dbo.rrhhNominaDetalle (IdNominaEmpleado, IdTipoMovimientoNomina, Naturaleza, Descripcion, Monto)
	SELECT nemp.IdNominaEmpleado, tipo.IdTipoMovimientoNomina, tipo.Naturaleza, tipo.Descripcion,
		   ROUND(CASE tipo.FormaCalculo WHEN 'S' THEN nemp.SalarioBase ELSE tipo.Valor END * nemp.DiasLaborados / 30.0, 2)
	FROM dbo.rrhhNominaEmpleado nemp
	CROSS JOIN dbo.rrhhTipoMovimientoNomina tipo
	WHERE nemp.IdNomina = @IdNomina
	  AND tipo.Estado = 'A' AND tipo.EsAutomatico = 1 AND tipo.FormaCalculo IN ('S','F');

	-- 2) Movimientos manuales (M) del período que no se han aplicado en
	--    otra nómina aprobada.
	INSERT INTO dbo.rrhhNominaDetalle (IdNominaEmpleado, IdTipoMovimientoNomina, IdMovimientoNomina, Naturaleza, Descripcion, Monto)
	SELECT nemp.IdNominaEmpleado, tipo.IdTipoMovimientoNomina, movi.IdMovimientoNomina, tipo.Naturaleza,
		   ISNULL(NULLIF(movi.Descripcion, ''), tipo.Descripcion), movi.Monto
	FROM dbo.rrhhMovimientoNomina movi
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdEmpleado = movi.IdEmpleado AND nemp.IdNomina = @IdNomina
	INNER JOIN dbo.rrhhTipoMovimientoNomina tipo ON tipo.IdTipoMovimientoNomina = movi.IdTipoMovimientoNomina
	WHERE movi.Estado = 'A' AND movi.IdNomina IS NULL
	  AND movi.FechaAplicacion BETWEEN @FechaDel AND @FechaAl;

	-- 3) Porcentajes (P) automáticos sobre los ingresos que forman la base
	--    (p. ej. IGSS laboral sobre sueldo + horas extra + comisiones).
	INSERT INTO dbo.rrhhNominaDetalle (IdNominaEmpleado, IdTipoMovimientoNomina, Naturaleza, Descripcion, Monto)
	SELECT nemp.IdNominaEmpleado, tipo.IdTipoMovimientoNomina, tipo.Naturaleza, tipo.Descripcion,
		   ROUND(base.Monto * tipo.Valor / 100.0, 2)
	FROM dbo.rrhhNominaEmpleado nemp
	CROSS APPLY (SELECT ISNULL(SUM(deta.Monto), 0) AS Monto
				 FROM dbo.rrhhNominaDetalle deta
				 INNER JOIN dbo.rrhhTipoMovimientoNomina tbas ON tbas.IdTipoMovimientoNomina = deta.IdTipoMovimientoNomina
				 WHERE deta.IdNominaEmpleado = nemp.IdNominaEmpleado AND tbas.EsBaseCalculo = 1) base
	CROSS JOIN dbo.rrhhTipoMovimientoNomina tipo
	WHERE nemp.IdNomina = @IdNomina
	  AND tipo.Estado = 'A' AND tipo.EsAutomatico = 1 AND tipo.FormaCalculo = 'P'
	  AND base.Monto > 0;

	DELETE deta FROM dbo.rrhhNominaDetalle deta
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = deta.IdNominaEmpleado
	WHERE nemp.IdNomina = @IdNomina AND deta.Monto <= 0;

	UPDATE nemp
	   SET TotalIngresos = tota.Ingresos, TotalDescuentos = tota.Descuentos, Liquido = tota.Ingresos - tota.Descuentos
	FROM dbo.rrhhNominaEmpleado nemp
	CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN deta.Naturaleza = 'I' THEN deta.Monto ELSE 0 END), 0) AS Ingresos,
						ISNULL(SUM(CASE WHEN deta.Naturaleza = 'D' THEN deta.Monto ELSE 0 END), 0) AS Descuentos
				 FROM dbo.rrhhNominaDetalle deta WHERE deta.IdNominaEmpleado = nemp.IdNominaEmpleado) tota
	WHERE nemp.IdNomina = @IdNomina;

	UPDATE nomi
	   SET TotalIngresos = tota.Ingresos, TotalDescuentos = tota.Descuentos, TotalLiquido = tota.Liquido,
		   Estado = 'C', FechaCalculo = SYSDATETIME(), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	FROM dbo.rrhhNomina nomi
	CROSS APPLY (SELECT ISNULL(SUM(TotalIngresos), 0) AS Ingresos, ISNULL(SUM(TotalDescuentos), 0) AS Descuentos, ISNULL(SUM(Liquido), 0) AS Liquido
				 FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina) tota
	WHERE nomi.IdNomina = @IdNomina;

	COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaEmpleadoConsultar]
	@IdNomina INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT nemp.IdNominaEmpleado, nemp.IdEmpleado, empl.CodigoEmpleado,
		   empl.PrimerNombre + ' ' + empl.PrimerApellido AS Empleado,
		   nemp.SalarioBase, nemp.DiasLaborados, nemp.TotalIngresos, nemp.TotalDescuentos, nemp.Liquido
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = nemp.IdEmpleado
	WHERE nemp.IdNomina = @IdNomina
	ORDER BY empl.PrimerApellido, empl.PrimerNombre;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaDetalleConsultar]
	@IdNominaEmpleado INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT deta.IdNominaDetalle, deta.IdTipoMovimientoNomina, tipo.Codigo, deta.Naturaleza, deta.Descripcion, deta.Monto
	FROM dbo.rrhhNominaDetalle deta
	INNER JOIN dbo.rrhhTipoMovimientoNomina tipo ON tipo.IdTipoMovimientoNomina = deta.IdTipoMovimientoNomina
	WHERE deta.IdNominaEmpleado = @IdNominaEmpleado
	ORDER BY deta.Naturaleza DESC, tipo.Orden, deta.IdNominaDetalle;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaAprobar]
	@IdNomina	INT,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhNomina WHERE IdNomina = @IdNomina AND Estado = 'C')
		THROW 52090, 'Solo se puede aprobar una nómina calculada.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina)
		THROW 52091, 'La nómina no tiene empleados; revise las fechas y los empleados activos.', 1;

	BEGIN TRANSACTION;

	-- Los movimientos manuales quedan ligados a esta nómina y ya no entran
	-- en ninguna otra.
	UPDATE movi SET IdNomina = @IdNomina, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	FROM dbo.rrhhMovimientoNomina movi
	INNER JOIN dbo.rrhhNominaDetalle deta ON deta.IdMovimientoNomina = movi.IdMovimientoNomina
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = deta.IdNominaEmpleado
	WHERE nemp.IdNomina = @IdNomina;

	UPDATE dbo.rrhhNomina
	   SET Estado = 'A', UsuarioAprobo = @UsuId, FechaAprobacion = SYSDATETIME(), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdNomina = @IdNomina;

	COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaAnular]
	@IdNomina	INT,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhNomina WHERE IdNomina = @IdNomina AND Estado <> 'N')
		THROW 52092, 'La nómina no existe o ya está anulada.', 1;

	BEGIN TRANSACTION;
	-- Libera los movimientos manuales para que entren en otra nómina.
	UPDATE dbo.rrhhMovimientoNomina SET IdNomina = NULL, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE IdNomina = @IdNomina;
	UPDATE dbo.rrhhNomina SET Estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE IdNomina = @IdNomina;
	COMMIT TRANSACTION;
END;
GO

------------------------------------------------------------
-- Procedimientos: usuario y vendedor de un empleado
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoAsignarUsuario]
	@IdEmpleado	INT,
	@UsuIdAsignado	INT = NULL,		-- NULL quita la relación
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF @UsuIdAsignado IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_id = @UsuIdAsignado AND IdEmpleado IS NOT NULL AND IdEmpleado <> @IdEmpleado)
		THROW 52100, 'Ese usuario ya está asignado a otro empleado.', 1;

	BEGIN TRANSACTION;
	UPDATE dbo.gen_usuario SET IdEmpleado = NULL, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdEmpleado = @IdEmpleado AND (@UsuIdAsignado IS NULL OR usu_id <> @UsuIdAsignado);
	IF @UsuIdAsignado IS NOT NULL
		UPDATE dbo.gen_usuario SET IdEmpleado = @IdEmpleado, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE usu_id = @UsuIdAsignado;
	COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoAsignarVendedor]
	@IdEmpleado	INT,
	@PveId		INT = NULL,		-- NULL quita la relación
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF @PveId IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.pos_vendedor WHERE pve_id = @PveId AND IdEmpleado IS NOT NULL AND IdEmpleado <> @IdEmpleado)
		THROW 52101, 'Ese vendedor ya está asignado a otro empleado.', 1;

	BEGIN TRANSACTION;
	UPDATE dbo.pos_vendedor SET IdEmpleado = NULL, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdEmpleado = @IdEmpleado AND (@PveId IS NULL OR pve_id <> @PveId);
	IF @PveId IS NOT NULL
		UPDATE dbo.pos_vendedor SET IdEmpleado = @IdEmpleado, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE pve_id = @PveId;
	COMMIT TRANSACTION;
END;
GO

-- Vendedor del usuario con sesión iniciada (usuario -> empleado -> vendedor),
-- para proponerlo por defecto al facturar.
CREATE OR ALTER PROCEDURE [dbo].[paVendedorConsultarPorUsuario]
	@UsuId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT vend.pve_id, vend.pve_codigo, vend.pve_nombres, vend.pve_apellidos, vend.pve_porc_comision
	FROM dbo.gen_usuario usua
	INNER JOIN dbo.pos_vendedor vend ON vend.IdEmpleado = usua.IdEmpleado AND vend.pve_estado = 'A'
	WHERE usua.usu_id = @UsuId;
END;
GO

------------------------------------------------------------
-- Datos de ejemplo (solo si todavía no hay empleados)
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.rrhhEmpleado)
   AND EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_estado = 'A')
BEGIN
	DECLARE @cia INT = (SELECT MIN(cia_id) FROM dbo.gen_compania WHERE cia_estado = 'A');
	DECLARE @suc INT = (SELECT MIN(suc_id) FROM dbo.gen_sucursal WHERE cia_id = @cia);
	DECLARE @dpi INT = (SELECT IdTipoDocumentoIdentificacion FROM dbo.rrhhTipoDocumentoIdentificacion WHERE Descripcion = 'DPI');
	DECLARE @inicioMes DATE = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);

	INSERT INTO dbo.rrhhUnidadOrganizativa (Descripcion)
	SELECT v.d FROM (VALUES ('Operaciones'), ('Administración')) v(d)
	WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhUnidadOrganizativa u WHERE u.Descripcion = v.d);

	INSERT INTO dbo.rrhhDepartamento (Descripcion, IdUnidadOrganizativa, suc_id)
	SELECT v.d, unid.IdUnidadOrganizativa, @suc
	FROM (VALUES ('Ventas', 'Operaciones'), ('Caja', 'Operaciones'), ('Contabilidad', 'Administración')) v(d, u)
	INNER JOIN dbo.rrhhUnidadOrganizativa unid ON unid.Descripcion = v.u
	WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhDepartamento depa WHERE depa.Descripcion = v.d);

	INSERT INTO dbo.rrhhPuesto (Descripcion, SalarioMinimo, SalarioMaximo)
	SELECT v.d, v.mi, v.ma FROM (VALUES ('Vendedor', 4000, 8000), ('Cajero', 3800, 5000), ('Contador', 6000, 10000)) v(d, mi, ma)
	WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhPuesto pues WHERE pues.Descripcion = v.d);

	INSERT INTO dbo.rrhhDepartamentoPuesto (IdDepartamento, IdPuesto)
	SELECT depa.IdDepartamento, pues.IdPuesto
	FROM (VALUES ('Ventas', 'Vendedor'), ('Caja', 'Cajero'), ('Contabilidad', 'Contador')) v(d, p)
	INNER JOIN dbo.rrhhDepartamento depa ON depa.Descripcion = v.d
	INNER JOIN dbo.rrhhPuesto pues ON pues.Descripcion = v.p
	WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhDepartamentoPuesto x WHERE x.IdDepartamento = depa.IdDepartamento AND x.IdPuesto = pues.IdPuesto);

	INSERT INTO dbo.rrhhPlaza (Descripcion, IdDepartamentoPuesto)
	SELECT v.plaza, depu.IdDepartamentoPuesto
	FROM (VALUES ('Vendedor 1', 'Ventas', 'Vendedor'), ('Vendedor 2', 'Ventas', 'Vendedor'),
				 ('Cajero 1', 'Caja', 'Cajero'), ('Contador general', 'Contabilidad', 'Contador')) v(plaza, d, p)
	INNER JOIN dbo.rrhhDepartamento depa ON depa.Descripcion = v.d
	INNER JOIN dbo.rrhhPuesto pues ON pues.Descripcion = v.p
	INNER JOIN dbo.rrhhDepartamentoPuesto depu ON depu.IdDepartamento = depa.IdDepartamento AND depu.IdPuesto = pues.IdPuesto;

	-- Ana Lucía entra a mitad del mes en curso, para que la nómina de
	-- ejemplo muestre el cálculo proporcional por días laborados.
	INSERT INTO dbo.rrhhEmpleado (CodigoEmpleado, cia_id, PrimerNombre, SegundoNombre, PrimerApellido, SegundoApellido, Genero, FechaNacimiento,
		FechaIngreso, IdTipoDocumentoIdentificacion, NumeroDocumento, NumeroAfiliacionIGSS, Email, IdPlaza, SalarioBase)
	SELECT v.cod, @cia, v.n1, v.n2, v.a1, v.a2, v.g, v.nac, v.ing, @dpi, v.dpi, v.igss, v.mail, plaz.IdPlaza, v.sal
	FROM (VALUES
		('EMP001', 'Julio',   NULL,    'Pérez',     'Ramírez', 'M', CAST('1990-04-12' AS DATE), CAST('2023-02-01' AS DATE), '2456789010101', '100200300', 'jperez@siq.com.gt',     'Vendedor 1',       4500.00),
		('EMP002', 'María',   'José',  'García',    'López',   'F', CAST('1994-09-30' AS DATE), CAST('2023-06-15' AS DATE), '2987654320101', '100200301', 'mgarcia@siq.com.gt',    'Cajero 1',         4000.00),
		('EMP003', 'Luis',    'Fernando', 'Rodríguez', 'Mejía', 'M', CAST('1985-01-20' AS DATE), CAST('2022-01-10' AS DATE), '1876543210101', '100200302', 'lrodriguez@siq.com.gt', 'Contador general', 7500.00),
		('EMP004', 'Ana',     'Lucía', 'Morales',   'Gómez',   'F', CAST('1997-11-05' AS DATE), DATEADD(DAY, 15, @inicioMes), '3012345670101', '100200303', NULL, 'Vendedor 2', 4500.00)
	) v(cod, n1, n2, a1, a2, g, nac, ing, dpi, igss, mail, plaza, sal)
	INNER JOIN dbo.rrhhPlaza plaz ON plaz.Descripcion = v.plaza;

	INSERT INTO dbo.rrhhHistorialPlaza (IdEmpleado, IdPlaza, FechaDel, Salario)
	SELECT IdEmpleado, IdPlaza, FechaIngreso, SalarioBase FROM dbo.rrhhEmpleado;

	UPDATE usua SET IdEmpleado = empl.IdEmpleado
	FROM dbo.gen_usuario usua
	INNER JOIN dbo.rrhhEmpleado empl ON empl.Email = usua.usu_email;

	UPDATE vend SET IdEmpleado = empl.IdEmpleado
	FROM dbo.pos_vendedor vend
	INNER JOIN (VALUES ('VEN01', 'EMP001'), ('VEN02', 'EMP004')) v(pve, emp) ON v.pve = vend.pve_codigo
	INNER JOIN dbo.rrhhEmpleado empl ON empl.CodigoEmpleado = v.emp;

	INSERT INTO dbo.rrhhMovimientoNomina (IdEmpleado, IdTipoMovimientoNomina, Descripcion, Monto, FechaAplicacion)
	SELECT empl.IdEmpleado, tipo.IdTipoMovimientoNomina, v.descr, v.monto, DATEADD(DAY, v.dia, @inicioMes)
	FROM (VALUES
		('EMP001', 'COMISION',    'Comisiones del mes',       650.00, 20),
		('EMP002', 'ANTICIPO',    'Anticipo quincena',        500.00, 14),
		('EMP003', 'HORAS_EXTRA', 'Cierre contable (8 h)',    350.00, 24)
	) v(emp, tipo, descr, monto, dia)
	INNER JOIN dbo.rrhhEmpleado empl ON empl.CodigoEmpleado = v.emp
	INNER JOIN dbo.rrhhTipoMovimientoNomina tipo ON tipo.Codigo = v.tipo;
END;
GO
