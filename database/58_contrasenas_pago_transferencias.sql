/*
================================================================================
 58_contrasenas_pago_transferencias.sql
 Contraseñas de pago a proveedores, pago por cheque o por transferencia y
 archivo de transferencias para el banco (proveedores y planilla).

   - Proveedor: banco, tipo y número de cuenta, titular y forma de pago
     preferida (cheque o transferencia).
   - Compañía: día de la semana en que se paga a proveedores (viernes por
     omisión).
   - Contraseña de pago (cxp_contrasena_enc / _det): el comprobante que se le
     da al proveedor por las facturas recibidas, con la fecha en que se le
     pagará. La fecha sugerida es el primer día de pago en o después del
     vencimiento más lejano de las facturas incluidas. Una cuota solo puede
     estar en una contraseña pendiente.
   - Pago de una contraseña:
       * con cheque: paContrasenaPagarCheque usa paCxpChequeEmitir (42), con
         su póliza; si se anula el cheque la contraseña vuelve a pendiente;
       * por transferencia: paContrasenaPagarTransferencia arma un lote
         (bco_lote_transferencia) con una línea por contraseña, aplica el pago
         a cada cuota y genera una sola póliza:
           Debe  PAGO_PROVEEDORES (una línea por contraseña)
           Haber cuenta de abonos de la cuenta bancaria (o PAGO_BANCOS)
         El lote se puede anular (devuelve el saldo y la contraseña queda
         pendiente).
   - Formatos de archivo por banco (bco_formato_archivo y sus columnas):
     delimitado o de ancho fijo, separador, títulos, encabezado y pie con
     marcadores, formato de fecha y de monto, códigos de tipo de cuenta y
     códigos de los bancos destino. La aplicación escribe el archivo con el
     lote (proveedores) o con el pago de la nómina (planilla).
   - El estado de cuenta del proveedor, el control 6 de integridad y el
     tablero de compras cuentan los pagos por transferencia.

 Errores nuevos: 54801 a 54830.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Origen de partida nuevo
------------------------------------------------------------
-- La lista es la misma en todos los scripts que la tocan (36, 38, 45, 58);
-- si ya tiene el último origen agregado no se vuelve a crear, así correr de
-- nuevo un script anterior no la deja sin los orígenes nuevos.
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_cont_asiento_enc_origen' AND definition LIKE '%CONCILIACION%')
BEGIN
	IF OBJECT_ID('dbo.CK_cont_asiento_enc_origen', 'C') IS NOT NULL
		ALTER TABLE dbo.cont_asiento_enc DROP CONSTRAINT [CK_cont_asiento_enc_origen];
	ALTER TABLE dbo.cont_asiento_enc ADD CONSTRAINT [CK_cont_asiento_enc_origen]
		CHECK ([asi_origen] IN ('MANUAL','VENTA','COMPRA','PAGO_CLIENTE','PAGO_PROVEEDOR','DEPOSITO','CIERRE_CAJA','NOMINA',
								'NOTA_CREDITO','NOTA_DEBITO',		-- 32
								'CHEQUE','PAGO_NOMINA',				-- 36
								'AJUSTE_INVENTARIO','APERTURA',		-- 38
								'TRASLADO',							-- 45
								'PAGO_TRANSFERENCIA',				-- 58
								'CAJA_CHICA','DEPRECIACION','ACTIVO_FIJO','CIERRE_ANUAL',
								'CONCILIACION'));	-- 60 en adelante
END
GO

------------------------------------------------------------
-- 2. Datos de pago del proveedor y día de pago
------------------------------------------------------------
IF COL_LENGTH('dbo.inv_proveedor', 'prv_forma_pago') IS NULL
	ALTER TABLE dbo.inv_proveedor ADD
		[prv_forma_pago]		CHAR(1)			NOT NULL CONSTRAINT [DF_inv_proveedor_forma_pago] DEFAULT ('C'),	-- C cheque, T transferencia
		[prv_gef_id]			INT				NULL,
		[prv_tipo_cuenta]		CHAR(1)			NULL,	-- M monetaria, A ahorro
		[prv_numero_cuenta]		VARCHAR(30)		NULL,
		[prv_cuenta_titular]	VARCHAR(150)	NULL;	-- nombre de la cuenta, si difiere del nombre comercial
GO
IF OBJECT_ID('dbo.FK_inv_proveedor_banco', 'F') IS NULL
	ALTER TABLE dbo.inv_proveedor ADD
		CONSTRAINT [FK_inv_proveedor_banco] FOREIGN KEY ([prv_gef_id]) REFERENCES dbo.gen_entidad_financiera ([gef_id]),
		CONSTRAINT [CK_inv_proveedor_pago] CHECK ([prv_forma_pago] IN ('C', 'T') AND ([prv_tipo_cuenta] IS NULL OR [prv_tipo_cuenta] IN ('M', 'A'))
			AND ([prv_forma_pago] = 'C' OR ([prv_gef_id] IS NOT NULL AND [prv_tipo_cuenta] IS NOT NULL AND [prv_numero_cuenta] IS NOT NULL)));
GO

-- 1 = lunes ... 7 = domingo; NULL = cualquier día.
IF COL_LENGTH('dbo.gen_compania', 'cia_dia_pago_proveedores') IS NULL
	ALTER TABLE dbo.gen_compania ADD [cia_dia_pago_proveedores] TINYINT NULL
		CONSTRAINT [DF_gen_compania_dia_pago] DEFAULT (5) WITH VALUES	-- las compañías que ya existen quedan con viernes
		CONSTRAINT [CK_gen_compania_dia_pago] CHECK ([cia_dia_pago_proveedores] IS NULL OR [cia_dia_pago_proveedores] BETWEEN 1 AND 7);
GO

CREATE OR ALTER PROCEDURE [dbo].[paProveedorPagoConsultar]
	@PrvId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT prov.prv_id AS PrvId, prov.prv_forma_pago AS FormaPago, prov.prv_gef_id AS GefId, enti.gef_descripcion AS Banco,
		   prov.prv_tipo_cuenta AS TipoCuenta, prov.prv_numero_cuenta AS NumeroCuenta, prov.prv_cuenta_titular AS Titular
	FROM dbo.inv_proveedor prov
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = prov.prv_gef_id
	WHERE prov.prv_id = @PrvId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProveedorPagoGuardar]
	@PrvId			INT,
	@FormaPago		CHAR(1),
	@GefId			INT = NULL,
	@TipoCuenta		CHAR(1) = NULL,
	@NumeroCuenta	VARCHAR(30) = NULL,
	@Titular		VARCHAR(150) = NULL,
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT @NumeroCuenta = NULLIF(REPLACE(LTRIM(RTRIM(@NumeroCuenta)), ' ', ''), ''), @Titular = NULLIF(LTRIM(RTRIM(@Titular)), ''),
		   @TipoCuenta = NULLIF(@TipoCuenta, ''), @GefId = NULLIF(@GefId, 0);
	IF ISNULL(@FormaPago, '') NOT IN ('C', 'T')
		THROW 54801, 'La forma de pago del proveedor es C (cheque) o T (transferencia).', 1;
	IF @FormaPago = 'T' AND (@GefId IS NULL OR @TipoCuenta IS NULL OR @NumeroCuenta IS NULL)
		THROW 54802, 'Para pagar por transferencia indique el banco, el tipo y el número de cuenta del proveedor.', 1;
	IF @TipoCuenta IS NOT NULL AND @TipoCuenta NOT IN ('M', 'A')
		THROW 54803, 'El tipo de cuenta es M (monetaria) o A (ahorro).', 1;
	IF @NumeroCuenta LIKE '%[^0-9-]%'
		THROW 54804, 'El número de cuenta solo lleva dígitos y guiones.', 1;
	UPDATE dbo.inv_proveedor
	   SET prv_forma_pago = @FormaPago, prv_gef_id = @GefId, prv_tipo_cuenta = @TipoCuenta, prv_numero_cuenta = @NumeroCuenta,
		   prv_cuenta_titular = @Titular, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE prv_id = @PrvId;
	IF @@ROWCOUNT = 0
		THROW 54805, 'El proveedor no existe.', 1;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaDiaPagoConsultar]
	@CiaId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cia_id AS CiaId, cia_dia_pago_proveedores AS DiaPago FROM dbo.gen_compania WHERE cia_id = @CiaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaDiaPagoGuardar]
	@CiaId		INT,
	@DiaPago	TINYINT = NULL,
	@UsuId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @DiaPago IS NOT NULL AND @DiaPago NOT BETWEEN 1 AND 7
		THROW 54806, 'El día de pago va de 1 (lunes) a 7 (domingo); vacío = cualquier día.', 1;
	UPDATE dbo.gen_compania SET cia_dia_pago_proveedores = @DiaPago, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE cia_id = @CiaId;
END;
GO

-- Primer día de pago (@Dia: 1 lunes ... 7 domingo) en o después de @Fecha,
-- sin depender de SET DATEFIRST (el 1/1/1900 fue lunes).
CREATE OR ALTER FUNCTION [dbo].[fnProximoDiaPago] (@Fecha DATE, @Dia TINYINT)
RETURNS DATE
AS
BEGIN
	IF @Dia IS NULL RETURN @Fecha;
	DECLARE @actual INT = DATEDIFF(DAY, '19000101', @Fecha) % 7 + 1;
	RETURN DATEADD(DAY, (@Dia - @actual + 7) % 7, @Fecha);
END;
GO

------------------------------------------------------------
-- 3. Contraseñas de pago
------------------------------------------------------------
IF OBJECT_ID('dbo.cxp_contrasena_enc', 'U') IS NULL
CREATE TABLE [dbo].[cxp_contrasena_enc](
	[cpa_id]				INT				IDENTITY(1, 1) NOT NULL,
	[cpa_numero]			VARCHAR(16)		NOT NULL,
	[prv_id]				INT				NOT NULL,
	[suc_id]				INT				NOT NULL,		-- donde se emitió (datos del emisor al imprimir)
	[cpa_fecha]				DATE			NOT NULL,
	[cpa_fecha_pago]		DATE			NOT NULL,
	[cpa_forma_pago]		CHAR(1)			NOT NULL,		-- C cheque, T transferencia
	[cpa_total]				NUMERIC(14, 2)	NOT NULL,
	[cpa_observaciones]		VARCHAR(250)	NULL,
	[cpa_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_cxp_contrasena_enc_estado] DEFAULT ('E'),	-- E pendiente, P pagada, A anulada
	[bce_id]				INT				NULL,			-- cheque que la pagó
	[blt_id]				INT				NULL,			-- lote de transferencias que la pagó
	[cpa_motivo_anulacion]	VARCHAR(250)	NULL,
	[usu_id]				INT				NULL,
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NULL,
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_cxp_contrasena_enc] PRIMARY KEY ([cpa_id]),
	CONSTRAINT [UQ_cxp_contrasena_enc_numero] UNIQUE ([cpa_numero]),
	CONSTRAINT [FK_cxp_contrasena_enc_proveedor] FOREIGN KEY ([prv_id]) REFERENCES dbo.inv_proveedor ([prv_id]),
	CONSTRAINT [FK_cxp_contrasena_enc_sucursal] FOREIGN KEY ([suc_id]) REFERENCES dbo.gen_sucursal ([suc_id]),
	CONSTRAINT [FK_cxp_contrasena_enc_cheque] FOREIGN KEY ([bce_id]) REFERENCES dbo.bco_cheque_emitido_enc ([bce_id]),
	CONSTRAINT [FK_cxp_contrasena_enc_usuario] FOREIGN KEY ([usu_id]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_cxp_contrasena_enc_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_cxp_contrasena_enc_UpdUsuario] FOREIGN KEY ([UpdUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [CK_cxp_contrasena_enc_valores] CHECK ([cpa_estado] IN ('E', 'P', 'A') AND [cpa_forma_pago] IN ('C', 'T')
		AND [cpa_total] > 0 AND [cpa_fecha_pago] >= [cpa_fecha]),
	CONSTRAINT [CK_cxp_contrasena_enc_pago] CHECK ([cpa_estado] <> 'P' OR [bce_id] IS NOT NULL OR [blt_id] IS NOT NULL)
);
GO

IF OBJECT_ID('dbo.cxp_contrasena_det', 'U') IS NULL
CREATE TABLE [dbo].[cxp_contrasena_det](
	[cpa_id]		INT				NOT NULL,
	[ppg_id]		INT				NOT NULL,
	[enc_id]		INT				NOT NULL,
	[cpd_monto]		NUMERIC(12, 2)	NOT NULL,
	CONSTRAINT [PK_cxp_contrasena_det] PRIMARY KEY ([cpa_id], [ppg_id]),
	CONSTRAINT [FK_cxp_contrasena_det_contrasena] FOREIGN KEY ([cpa_id]) REFERENCES dbo.cxp_contrasena_enc ([cpa_id]),
	CONSTRAINT [FK_cxp_contrasena_det_cuota] FOREIGN KEY ([ppg_id]) REFERENCES dbo.inv_proveedor_plan_pago ([ppg_id]),
	CONSTRAINT [FK_cxp_contrasena_det_compra] FOREIGN KEY ([enc_id]) REFERENCES dbo.inv_documento_enc ([enc_id]),
	CONSTRAINT [CK_cxp_contrasena_det_monto] CHECK ([cpd_monto] > 0)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cxp_contrasena_det_cuota')
	CREATE INDEX [IX_cxp_contrasena_det_cuota] ON dbo.cxp_contrasena_det ([ppg_id]) INCLUDE ([cpa_id], [cpd_monto]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cxp_contrasena_enc_pago')
	CREATE INDEX [IX_cxp_contrasena_enc_pago] ON dbo.cxp_contrasena_enc ([cpa_estado], [cpa_fecha_pago]) INCLUDE ([prv_id], [cpa_total]);
GO

------------------------------------------------------------
-- 4. Lotes de transferencias
------------------------------------------------------------
IF OBJECT_ID('dbo.bco_lote_transferencia', 'U') IS NULL
CREATE TABLE [dbo].[bco_lote_transferencia](
	[blt_id]				INT				IDENTITY(1, 1) NOT NULL,
	[blt_numero]			VARCHAR(16)		NOT NULL,
	[blt_tipo]				CHAR(1)			NOT NULL CONSTRAINT [DF_bco_lote_transferencia_tipo] DEFAULT ('P'),	-- P proveedores
	[bcb_id]				INT				NOT NULL,		-- cuenta de la empresa que paga
	[blt_fecha]				DATE			NOT NULL,
	[blt_referencia]		VARCHAR(60)		NULL,
	[blt_total]				NUMERIC(14, 2)	NOT NULL,
	[blt_cantidad]			INT				NOT NULL,
	[blt_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_bco_lote_transferencia_estado] DEFAULT ('A'),	-- A vigente, N anulado
	[blt_motivo_anulacion]	VARCHAR(250)	NULL,
	[usu_id]				INT				NULL,
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NULL,
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_bco_lote_transferencia] PRIMARY KEY ([blt_id]),
	CONSTRAINT [UQ_bco_lote_transferencia_numero] UNIQUE ([blt_numero]),
	CONSTRAINT [FK_bco_lote_transferencia_cuenta] FOREIGN KEY ([bcb_id]) REFERENCES dbo.bco_cuenta_bancaria ([bcb_id]),
	CONSTRAINT [FK_bco_lote_transferencia_usuario] FOREIGN KEY ([usu_id]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_bco_lote_transferencia_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_bco_lote_transferencia_UpdUsuario] FOREIGN KEY ([UpdUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [CK_bco_lote_transferencia_valores] CHECK ([blt_tipo] IN ('P') AND [blt_estado] IN ('A', 'N') AND [blt_total] > 0 AND [blt_cantidad] > 0)
);
GO

IF OBJECT_ID('dbo.bco_lote_transferencia_det', 'U') IS NULL
CREATE TABLE [dbo].[bco_lote_transferencia_det](
	[bld_id]			INT				IDENTITY(1, 1) NOT NULL,
	[blt_id]			INT				NOT NULL,
	[bld_correlativo]	INT				NOT NULL,
	[cpa_id]			INT				NULL,
	[prv_id]			INT				NOT NULL,
	[bld_beneficiario]	VARCHAR(150)	NOT NULL,
	[bld_identificacion] VARCHAR(20)	NULL,		-- NIT del proveedor
	[gef_id]			INT				NOT NULL,	-- banco destino
	[bld_tipo_cuenta]	CHAR(1)			NOT NULL,
	[bld_cuenta]		VARCHAR(30)		NOT NULL,
	[bld_monto]			NUMERIC(14, 2)	NOT NULL,
	[bld_referencia]	VARCHAR(100)	NULL,
	[bld_correo]		VARCHAR(100)	NULL,
	CONSTRAINT [PK_bco_lote_transferencia_det] PRIMARY KEY ([bld_id]),
	CONSTRAINT [UQ_bco_lote_transferencia_det_correlativo] UNIQUE ([blt_id], [bld_correlativo]),
	CONSTRAINT [FK_bco_lote_transferencia_det_lote] FOREIGN KEY ([blt_id]) REFERENCES dbo.bco_lote_transferencia ([blt_id]),
	CONSTRAINT [FK_bco_lote_transferencia_det_contrasena] FOREIGN KEY ([cpa_id]) REFERENCES dbo.cxp_contrasena_enc ([cpa_id]),
	CONSTRAINT [FK_bco_lote_transferencia_det_proveedor] FOREIGN KEY ([prv_id]) REFERENCES dbo.inv_proveedor ([prv_id]),
	CONSTRAINT [FK_bco_lote_transferencia_det_banco] FOREIGN KEY ([gef_id]) REFERENCES dbo.gen_entidad_financiera ([gef_id]),
	CONSTRAINT [CK_bco_lote_transferencia_det_valores] CHECK ([bld_monto] > 0 AND [bld_tipo_cuenta] IN ('M', 'A'))
);
GO

-- Lo que cada transferencia pagó de cada cuota (para el estado de cuenta y la anulación).
IF OBJECT_ID('dbo.bco_lote_transferencia_cuota', 'U') IS NULL
CREATE TABLE [dbo].[bco_lote_transferencia_cuota](
	[bld_id]		INT				NOT NULL,
	[ppg_id]		INT				NOT NULL,
	[enc_id]		INT				NOT NULL,
	[blc_monto]		NUMERIC(12, 2)	NOT NULL,
	CONSTRAINT [PK_bco_lote_transferencia_cuota] PRIMARY KEY ([bld_id], [ppg_id]),
	CONSTRAINT [FK_bco_lote_transferencia_cuota_linea] FOREIGN KEY ([bld_id]) REFERENCES dbo.bco_lote_transferencia_det ([bld_id]),
	CONSTRAINT [FK_bco_lote_transferencia_cuota_cuota] FOREIGN KEY ([ppg_id]) REFERENCES dbo.inv_proveedor_plan_pago ([ppg_id]),
	CONSTRAINT [FK_bco_lote_transferencia_cuota_compra] FOREIGN KEY ([enc_id]) REFERENCES dbo.inv_documento_enc ([enc_id]),
	CONSTRAINT [CK_bco_lote_transferencia_cuota_monto] CHECK ([blc_monto] > 0)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bco_lote_transferencia_cuota_cuota')
	CREATE INDEX [IX_bco_lote_transferencia_cuota_cuota] ON dbo.bco_lote_transferencia_cuota ([ppg_id]) INCLUDE ([blc_monto]);
GO

IF OBJECT_ID('dbo.FK_cxp_contrasena_enc_lote', 'F') IS NULL
	ALTER TABLE dbo.cxp_contrasena_enc ADD CONSTRAINT [FK_cxp_contrasena_enc_lote] FOREIGN KEY ([blt_id]) REFERENCES dbo.bco_lote_transferencia ([blt_id]);
GO

IF TYPE_ID('dbo.id_lista_type') IS NULL
	CREATE TYPE dbo.id_lista_type AS TABLE ([id] INT NOT NULL PRIMARY KEY);
GO

------------------------------------------------------------
-- 5. Formatos del archivo de transferencias por banco
------------------------------------------------------------
IF OBJECT_ID('dbo.bco_formato_archivo', 'U') IS NULL
CREATE TABLE [dbo].[bco_formato_archivo](
	[bfa_id]				INT				IDENTITY(1, 1) NOT NULL,
	[bfa_nombre]			VARCHAR(80)		NOT NULL,
	[gef_id]				INT				NULL,		-- banco al que se envía (NULL = cualquiera)
	[bfa_uso]				CHAR(1)			NOT NULL CONSTRAINT [DF_bco_formato_archivo_uso] DEFAULT ('A'),	-- P proveedores, N planilla, A ambos
	[bfa_tipo]				CHAR(1)			NOT NULL CONSTRAINT [DF_bco_formato_archivo_tipo] DEFAULT ('D'),	-- D delimitado, F ancho fijo
	[bfa_separador]			VARCHAR(5)		NULL,		-- en delimitado: , ; | TAB
	[bfa_titulos]			BIT				NOT NULL CONSTRAINT [DF_bco_formato_archivo_titulos] DEFAULT (0),
	[bfa_comillas]			BIT				NOT NULL CONSTRAINT [DF_bco_formato_archivo_comillas] DEFAULT (0),
	[bfa_encabezado]		VARCHAR(500)	NULL,		-- línea antes del detalle, con marcadores {CAMPO} o {CAMPO,ancho}
	[bfa_pie]				VARCHAR(500)	NULL,		-- línea después del detalle
	[bfa_extension]			VARCHAR(5)		NOT NULL CONSTRAINT [DF_bco_formato_archivo_extension] DEFAULT ('txt'),
	[bfa_codificacion]		VARCHAR(10)		NOT NULL CONSTRAINT [DF_bco_formato_archivo_codificacion] DEFAULT ('ANSI'),	-- ANSI o UTF-8
	[bfa_fin_linea]			VARCHAR(4)		NOT NULL CONSTRAINT [DF_bco_formato_archivo_fin_linea] DEFAULT ('CRLF'),
	[bfa_formato_fecha]		VARCHAR(20)		NOT NULL CONSTRAINT [DF_bco_formato_archivo_fecha] DEFAULT ('yyyyMMdd'),
	[bfa_decimales]			TINYINT			NOT NULL CONSTRAINT [DF_bco_formato_archivo_decimales] DEFAULT (2),
	[bfa_separador_decimal]	CHAR(1)			NOT NULL CONSTRAINT [DF_bco_formato_archivo_sep_decimal] DEFAULT ('.'),
	[bfa_monto_sin_punto]	BIT				NOT NULL CONSTRAINT [DF_bco_formato_archivo_sin_punto] DEFAULT (0),	-- 1250.50 -> 125050
	[bfa_codigo_monetaria]	VARCHAR(20)		NOT NULL CONSTRAINT [DF_bco_formato_archivo_monetaria] DEFAULT ('M'),
	[bfa_codigo_ahorro]		VARCHAR(20)		NOT NULL CONSTRAINT [DF_bco_formato_archivo_ahorro] DEFAULT ('A'),
	[bfa_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_bco_formato_archivo_estado] DEFAULT ('A'),
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NULL,
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_bco_formato_archivo] PRIMARY KEY ([bfa_id]),
	CONSTRAINT [UQ_bco_formato_archivo_nombre] UNIQUE ([bfa_nombre]),
	CONSTRAINT [FK_bco_formato_archivo_banco] FOREIGN KEY ([gef_id]) REFERENCES dbo.gen_entidad_financiera ([gef_id]),
	CONSTRAINT [FK_bco_formato_archivo_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_bco_formato_archivo_UpdUsuario] FOREIGN KEY ([UpdUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [CK_bco_formato_archivo_valores] CHECK ([bfa_uso] IN ('P', 'N', 'A') AND [bfa_tipo] IN ('D', 'F') AND [bfa_estado] IN ('A', 'I')
		AND [bfa_codificacion] IN ('ANSI', 'UTF-8') AND [bfa_fin_linea] IN ('CRLF', 'LF') AND [bfa_decimales] <= 4
		AND [bfa_separador_decimal] IN ('.', ',') AND ([bfa_tipo] = 'F' OR [bfa_separador] IS NOT NULL))
);
GO

-- Campos del detalle: CORRELATIVO, CODIGO, BENEFICIARIO, IDENTIFICACION,
-- BANCO_DESTINO, TIPO_CUENTA, CUENTA_DESTINO, MONTO, REFERENCIA, CORREO,
-- FECHA, CUENTA_ORIGEN, MONEDA y FIJO (el texto de bfc_valor).
IF OBJECT_ID('dbo.bco_formato_archivo_columna', 'U') IS NULL
CREATE TABLE [dbo].[bco_formato_archivo_columna](
	[bfc_id]			INT				IDENTITY(1, 1) NOT NULL,
	[bfa_id]			INT				NOT NULL,
	[bfc_orden]			INT				NOT NULL,
	[bfc_campo]			VARCHAR(20)		NOT NULL,
	[bfc_titulo]		VARCHAR(60)		NULL,
	[bfc_longitud]		INT				NULL,		-- ancho fijo (obligatorio en tipo F; en D recorta si se indica)
	[bfc_relleno]		CHAR(1)			NULL,		-- ' ' o '0'
	[bfc_alineacion]	CHAR(1)			NOT NULL CONSTRAINT [DF_bco_formato_archivo_columna_alineacion] DEFAULT ('I'),	-- I izquierda, D derecha
	[bfc_valor]			VARCHAR(100)	NULL,
	[bfc_mayusculas]	BIT				NOT NULL CONSTRAINT [DF_bco_formato_archivo_columna_mayusculas] DEFAULT (0),
	CONSTRAINT [PK_bco_formato_archivo_columna] PRIMARY KEY ([bfc_id]),
	CONSTRAINT [UQ_bco_formato_archivo_columna_orden] UNIQUE ([bfa_id], [bfc_orden]),
	CONSTRAINT [FK_bco_formato_archivo_columna_formato] FOREIGN KEY ([bfa_id]) REFERENCES dbo.bco_formato_archivo ([bfa_id]),
	CONSTRAINT [CK_bco_formato_archivo_columna_valores] CHECK ([bfc_campo] IN ('CORRELATIVO', 'CODIGO', 'BENEFICIARIO', 'IDENTIFICACION',
		'BANCO_DESTINO', 'TIPO_CUENTA', 'CUENTA_DESTINO', 'MONTO', 'REFERENCIA', 'CORREO', 'FECHA', 'CUENTA_ORIGEN', 'MONEDA', 'FIJO')
		AND [bfc_alineacion] IN ('I', 'D') AND ([bfc_relleno] IS NULL OR [bfc_relleno] IN (' ', '0'))
		AND ([bfc_longitud] IS NULL OR [bfc_longitud] BETWEEN 1 AND 200))
);
GO

-- Código con que el banco del formato identifica a cada banco destino.
IF OBJECT_ID('dbo.bco_formato_archivo_banco', 'U') IS NULL
CREATE TABLE [dbo].[bco_formato_archivo_banco](
	[bfa_id]	INT				NOT NULL,
	[gef_id]	INT				NOT NULL,
	[bfb_codigo] VARCHAR(10)	NOT NULL,
	CONSTRAINT [PK_bco_formato_archivo_banco] PRIMARY KEY ([bfa_id], [gef_id]),
	CONSTRAINT [FK_bco_formato_archivo_banco_formato] FOREIGN KEY ([bfa_id]) REFERENCES dbo.bco_formato_archivo ([bfa_id]),
	CONSTRAINT [FK_bco_formato_archivo_banco_banco] FOREIGN KEY ([gef_id]) REFERENCES dbo.gen_entidad_financiera ([gef_id])
);
GO

IF TYPE_ID('dbo.formato_archivo_columna_type') IS NULL
	CREATE TYPE dbo.formato_archivo_columna_type AS TABLE (
		orden		INT				NOT NULL PRIMARY KEY,
		campo		VARCHAR(20)		NOT NULL,
		titulo		VARCHAR(60)		NULL,
		longitud	INT				NULL,
		relleno		CHAR(1)			NULL,
		alineacion	CHAR(1)			NOT NULL,
		valor		VARCHAR(100)	NULL,
		mayusculas	BIT				NOT NULL
	);
GO
IF TYPE_ID('dbo.formato_archivo_banco_type') IS NULL
	CREATE TYPE dbo.formato_archivo_banco_type AS TABLE (
		gef_id		INT				NOT NULL PRIMARY KEY,
		codigo		VARCHAR(10)		NOT NULL
	);
GO

CREATE OR ALTER PROCEDURE [dbo].[paBcoFormatoArchivoConsultar]
	@BfaId			INT = NULL,
	@SoloActivos	BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT form.bfa_id AS BfaId, form.bfa_nombre AS Nombre, form.gef_id AS GefId, enti.gef_descripcion AS Banco, form.bfa_uso AS Uso,
		   form.bfa_tipo AS Tipo, form.bfa_separador AS Separador, form.bfa_titulos AS Titulos, form.bfa_comillas AS Comillas,
		   form.bfa_encabezado AS Encabezado, form.bfa_pie AS Pie, form.bfa_extension AS Extension, form.bfa_codificacion AS Codificacion,
		   form.bfa_fin_linea AS FinLinea, form.bfa_formato_fecha AS FormatoFecha, form.bfa_decimales AS Decimales,
		   form.bfa_separador_decimal AS SeparadorDecimal, form.bfa_monto_sin_punto AS MontoSinPunto,
		   form.bfa_codigo_monetaria AS CodigoMonetaria, form.bfa_codigo_ahorro AS CodigoAhorro, form.bfa_estado AS Estado
	FROM dbo.bco_formato_archivo form
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = form.gef_id
	WHERE (@BfaId IS NULL OR form.bfa_id = @BfaId) AND (@SoloActivos = 0 OR form.bfa_estado = 'A')
	ORDER BY form.bfa_nombre;

	SELECT colu.bfa_id AS BfaId, colu.bfc_orden AS Orden, colu.bfc_campo AS Campo, colu.bfc_titulo AS Titulo, colu.bfc_longitud AS Longitud,
		   colu.bfc_relleno AS Relleno, colu.bfc_alineacion AS Alineacion, colu.bfc_valor AS Valor, colu.bfc_mayusculas AS Mayusculas
	FROM dbo.bco_formato_archivo_columna colu
	INNER JOIN dbo.bco_formato_archivo form ON form.bfa_id = colu.bfa_id
	WHERE (@BfaId IS NULL OR colu.bfa_id = @BfaId) AND (@SoloActivos = 0 OR form.bfa_estado = 'A')
	ORDER BY colu.bfa_id, colu.bfc_orden;

	SELECT banc.bfa_id AS BfaId, banc.gef_id AS GefId, enti.gef_descripcion AS Banco, banc.bfb_codigo AS Codigo
	FROM dbo.bco_formato_archivo_banco banc
	INNER JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = banc.gef_id
	INNER JOIN dbo.bco_formato_archivo form ON form.bfa_id = banc.bfa_id
	WHERE (@BfaId IS NULL OR banc.bfa_id = @BfaId) AND (@SoloActivos = 0 OR form.bfa_estado = 'A')
	ORDER BY banc.bfa_id, enti.gef_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBcoFormatoArchivoGuardar]
	@BfaId				INT OUTPUT,
	@Nombre				VARCHAR(80),
	@GefId				INT = NULL,
	@Uso				CHAR(1) = 'A',
	@Tipo				CHAR(1) = 'D',
	@Separador			VARCHAR(5) = NULL,
	@Titulos			BIT = 0,
	@Comillas			BIT = 0,
	@Encabezado			VARCHAR(500) = NULL,
	@Pie				VARCHAR(500) = NULL,
	@Extension			VARCHAR(5) = 'txt',
	@Codificacion		VARCHAR(10) = 'ANSI',
	@FinLinea			VARCHAR(4) = 'CRLF',
	@FormatoFecha		VARCHAR(20) = 'yyyyMMdd',
	@Decimales			TINYINT = 2,
	@SeparadorDecimal	CHAR(1) = '.',
	@MontoSinPunto		BIT = 0,
	@CodigoMonetaria	VARCHAR(20) = 'M',
	@CodigoAhorro		VARCHAR(20) = 'A',
	@Estado				CHAR(1) = 'A',
	@Columnas			dbo.formato_archivo_columna_type READONLY,
	@Bancos				dbo.formato_archivo_banco_type READONLY,
	@UsuId				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SELECT @Nombre = NULLIF(LTRIM(RTRIM(@Nombre)), ''), @Separador = NULLIF(@Separador, ''), @GefId = NULLIF(@GefId, 0),
		   @Encabezado = NULLIF(RTRIM(@Encabezado), ''), @Pie = NULLIF(RTRIM(@Pie), ''),
		   @Extension = LOWER(REPLACE(ISNULL(NULLIF(LTRIM(RTRIM(@Extension)), ''), 'txt'), '.', ''));
	IF @Nombre IS NULL
		THROW 54810, 'Indique el nombre del formato.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_formato_archivo WHERE bfa_nombre = @Nombre AND bfa_id <> ISNULL(@BfaId, 0))
		THROW 54811, 'Ya existe un formato con ese nombre.', 1;
	IF @Tipo = 'D' AND @Separador IS NULL
		THROW 54812, 'Un archivo delimitado necesita el separador de columnas (, ; | o TAB).', 1;
	IF NOT EXISTS (SELECT 1 FROM @Columnas)
		THROW 54813, 'El formato debe tener al menos una columna.', 1;
	IF @Tipo = 'F' AND EXISTS (SELECT 1 FROM @Columnas WHERE longitud IS NULL)
		THROW 54814, 'En un archivo de ancho fijo cada columna necesita su ancho.', 1;
	IF EXISTS (SELECT 1 FROM @Columnas WHERE campo = 'FIJO' AND valor IS NULL)
		THROW 54815, 'Una columna de texto fijo necesita el texto.', 1;
	IF EXISTS (SELECT 1 FROM @Columnas WHERE campo NOT IN ('CORRELATIVO', 'CODIGO', 'BENEFICIARIO', 'IDENTIFICACION', 'BANCO_DESTINO',
			   'TIPO_CUENTA', 'CUENTA_DESTINO', 'MONTO', 'REFERENCIA', 'CORREO', 'FECHA', 'CUENTA_ORIGEN', 'MONEDA', 'FIJO'))
		THROW 54816, 'Una columna tiene un campo que no existe.', 1;
	IF NOT EXISTS (SELECT 1 FROM @Columnas WHERE campo = 'MONTO') OR NOT EXISTS (SELECT 1 FROM @Columnas WHERE campo = 'CUENTA_DESTINO')
		THROW 54817, 'El formato debe llevar al menos la cuenta destino y el monto.', 1;

	BEGIN TRANSACTION;
	IF @BfaId IS NULL
	BEGIN
		INSERT INTO dbo.bco_formato_archivo
			(bfa_nombre, gef_id, bfa_uso, bfa_tipo, bfa_separador, bfa_titulos, bfa_comillas, bfa_encabezado, bfa_pie, bfa_extension,
			 bfa_codificacion, bfa_fin_linea, bfa_formato_fecha, bfa_decimales, bfa_separador_decimal, bfa_monto_sin_punto,
			 bfa_codigo_monetaria, bfa_codigo_ahorro, bfa_estado, InsUsuario, InsFechaHora)
		VALUES
			(@Nombre, @GefId, @Uso, @Tipo, @Separador, @Titulos, @Comillas, @Encabezado, @Pie, @Extension,
			 @Codificacion, @FinLinea, @FormatoFecha, @Decimales, @SeparadorDecimal, @MontoSinPunto,
			 @CodigoMonetaria, @CodigoAhorro, @Estado, @UsuId, SYSDATETIME());
		SET @BfaId = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.bco_formato_archivo
		   SET bfa_nombre = @Nombre, gef_id = @GefId, bfa_uso = @Uso, bfa_tipo = @Tipo, bfa_separador = @Separador, bfa_titulos = @Titulos,
			   bfa_comillas = @Comillas, bfa_encabezado = @Encabezado, bfa_pie = @Pie, bfa_extension = @Extension,
			   bfa_codificacion = @Codificacion, bfa_fin_linea = @FinLinea, bfa_formato_fecha = @FormatoFecha, bfa_decimales = @Decimales,
			   bfa_separador_decimal = @SeparadorDecimal, bfa_monto_sin_punto = @MontoSinPunto, bfa_codigo_monetaria = @CodigoMonetaria,
			   bfa_codigo_ahorro = @CodigoAhorro, bfa_estado = @Estado, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE bfa_id = @BfaId;
		IF @@ROWCOUNT = 0
			THROW 54818, 'El formato no existe.', 1;
		DELETE FROM dbo.bco_formato_archivo_columna WHERE bfa_id = @BfaId;
		DELETE FROM dbo.bco_formato_archivo_banco WHERE bfa_id = @BfaId;
	END

	INSERT INTO dbo.bco_formato_archivo_columna (bfa_id, bfc_orden, bfc_campo, bfc_titulo, bfc_longitud, bfc_relleno, bfc_alineacion, bfc_valor, bfc_mayusculas)
	SELECT @BfaId, ROW_NUMBER() OVER (ORDER BY orden), campo, NULLIF(LTRIM(RTRIM(titulo)), ''), longitud, relleno, alineacion, valor, mayusculas
	FROM @Columnas;
	INSERT INTO dbo.bco_formato_archivo_banco (bfa_id, gef_id, bfb_codigo)
	SELECT @BfaId, gef_id, LTRIM(RTRIM(codigo)) FROM @Bancos WHERE LTRIM(RTRIM(codigo)) <> '';
	COMMIT;
END;
GO

------------------------------------------------------------
-- 6. Contraseñas: consultar, emitir y anular
------------------------------------------------------------
-- Cuotas con saldo del proveedor que no están en una contraseña pendiente.
CREATE OR ALTER PROCEDURE [dbo].[paContrasenaCuotasDisponibles]
	@PrvId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cuot.ppg_id AS PpgId, docu.enc_id AS EncId,
		   CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto) AS Documento,
		   docu.enc_fecha_docto AS FechaDocumento, cuot.ppg_nro_pago AS Cuota, cuot.ppg_fecha_pago AS Vencimiento,
		   cuot.ppg_valor_pago AS ValorCuota, ISNULL(cuot.ppg_valor_real_pago, 0) AS Pagado,
		   cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) AS Saldo
	FROM dbo.inv_proveedor_plan_pago cuot
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	WHERE docu.prv_id = @PrvId
	  AND cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) > 0
	  AND NOT EXISTS (SELECT 1 FROM dbo.cxp_contrasena_det deta
					  INNER JOIN dbo.cxp_contrasena_enc cont ON cont.cpa_id = deta.cpa_id AND cont.cpa_estado = 'E'
					  WHERE deta.ppg_id = cuot.ppg_id)
	ORDER BY cuot.ppg_fecha_pago, docu.enc_fecha_docto, cuot.ppg_id;
END;
GO

-- @Estado: E pendientes, P pagadas, A anuladas, NULL todas.
-- @PagoHasta: pendientes cuya fecha de pago ya llegó (la lista del día de pago).
CREATE OR ALTER PROCEDURE [dbo].[paContrasenaConsultar]
	@Estado		CHAR(1) = NULL,
	@PrvId		INT = NULL,
	@Desde		DATE = NULL,
	@Hasta		DATE = NULL,
	@PagoHasta	DATE = NULL,
	@FormaPago	CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cont.cpa_id AS CpaId, cont.cpa_numero AS Numero, cont.cpa_fecha AS Fecha, cont.cpa_fecha_pago AS FechaPago,
		   cont.cpa_forma_pago AS FormaPago, cont.cpa_total AS Total, cont.cpa_estado AS Estado,
		   cont.prv_id AS PrvId, prov.prv_codigo AS ProveedorCodigo, prov.prv_nombre_comercial AS Proveedor, prov.prv_nit AS Nit,
		   CAST(CASE WHEN prov.prv_gef_id IS NOT NULL AND prov.prv_numero_cuenta IS NOT NULL AND prov.prv_tipo_cuenta IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS TieneCuenta,
		   banc.gef_descripcion AS Banco, prov.prv_numero_cuenta AS CuentaProveedor,
		   (SELECT COUNT(DISTINCT deta.enc_id) FROM dbo.cxp_contrasena_det deta WHERE deta.cpa_id = cont.cpa_id) AS Facturas,
		   cheq.bce_numero_cheque AS Cheque, lote.blt_numero AS Lote
	FROM dbo.cxp_contrasena_enc cont
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = cont.prv_id
	LEFT JOIN dbo.gen_entidad_financiera banc ON banc.gef_id = prov.prv_gef_id
	LEFT JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = cont.bce_id
	LEFT JOIN dbo.bco_lote_transferencia lote ON lote.blt_id = cont.blt_id
	WHERE (@Estado IS NULL OR cont.cpa_estado = @Estado)
	  AND (@PrvId IS NULL OR cont.prv_id = @PrvId)
	  AND (@Desde IS NULL OR cont.cpa_fecha >= @Desde)
	  AND (@Hasta IS NULL OR cont.cpa_fecha <= @Hasta)
	  AND (@PagoHasta IS NULL OR (cont.cpa_estado = 'E' AND cont.cpa_fecha_pago <= @PagoHasta))
	  AND (@FormaPago IS NULL OR cont.cpa_forma_pago = @FormaPago)
	ORDER BY CASE WHEN @PagoHasta IS NULL THEN 0 ELSE DATEDIFF(DAY, '19000101', cont.cpa_fecha_pago) END, cont.cpa_id DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paContrasenaConsultarPorId]
	@CpaId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cont.cpa_id AS CpaId, cont.cpa_numero AS Numero, cont.cpa_fecha AS Fecha, cont.cpa_fecha_pago AS FechaPago,
		   cont.cpa_forma_pago AS FormaPago, cont.cpa_total AS Total, cont.cpa_observaciones AS Observaciones, cont.cpa_estado AS Estado,
		   cont.cpa_motivo_anulacion AS MotivoAnulacion, cont.bce_id AS BceId, cheq.bce_numero_cheque AS Cheque,
		   cont.blt_id AS BltId, lote.blt_numero AS Lote, usua.usu_codigo AS Usuario,
		   cont.prv_id AS PrvId, prov.prv_codigo AS ProveedorCodigo, prov.prv_nombre_comercial AS Proveedor, prov.prv_nit AS Nit,
		   prov.prv_direccion AS ProveedorDireccion, banc.gef_descripcion AS Banco, prov.prv_tipo_cuenta AS TipoCuenta,
		   prov.prv_numero_cuenta AS CuentaProveedor,
		   -- Emisor
		   comp.cia_id AS CiaId, comp.cia_nit AS NitEmisor, ISNULL(comp.cia_fel_nombre_emisor, comp.cia_nombre_comercial) AS NombreEmisor,
		   ISNULL(sucu.suc_fel_nombre_comercial, comp.cia_nombre_comercial) AS NombreComercial,
		   ISNULL(sucu.suc_direccion, comp.cia_direccion) AS DireccionEmisor, ISNULL(sucu.suc_telefono, comp.cia_telefono) AS TelefonoEmisor,
		   CAST(CASE WHEN comp.cia_logo IS NULL THEN 0 ELSE 1 END AS BIT) AS TieneLogo, comp.cia_logo_actualizado AS LogoActualizado
	FROM dbo.cxp_contrasena_enc cont
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = cont.prv_id
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = cont.suc_id
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	LEFT JOIN dbo.gen_entidad_financiera banc ON banc.gef_id = prov.prv_gef_id
	LEFT JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = cont.bce_id
	LEFT JOIN dbo.bco_lote_transferencia lote ON lote.blt_id = cont.blt_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = cont.usu_id
	WHERE cont.cpa_id = @CpaId;

	SELECT deta.ppg_id AS PpgId, deta.enc_id AS EncId,
		   CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto) AS Documento,
		   docu.enc_fecha_docto AS FechaDocumento, cuot.ppg_nro_pago AS Cuota, cuot.ppg_fecha_pago AS Vencimiento,
		   deta.cpd_monto AS Monto, cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) AS SaldoActual
	FROM dbo.cxp_contrasena_det deta
	INNER JOIN dbo.inv_proveedor_plan_pago cuot ON cuot.ppg_id = deta.ppg_id
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = deta.enc_id
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	WHERE deta.cpa_id = @CpaId
	ORDER BY docu.enc_fecha_docto, cuot.ppg_nro_pago;
END;
GO

-- @FechaPago NULL: el primer día de pago en o después del vencimiento más
-- lejano de las cuotas (y no antes de hoy). @FormaPago NULL: la del proveedor.
CREATE OR ALTER PROCEDURE [dbo].[paContrasenaEmitir]
	@PrvId			INT,
	@SucId			INT,
	@Fecha			DATE = NULL,
	@FechaPago		DATE = NULL,
	@FormaPago		CHAR(1) = NULL,
	@Observaciones	VARCHAR(250) = NULL,
	@Cuotas			dbo.cxp_pago_cuota_type READONLY,
	@UsuId			INT = NULL,
	@CpaId			INT OUTPUT,
	@Numero			VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SELECT @CpaId = NULL, @Numero = NULL, @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));

	IF NOT EXISTS (SELECT 1 FROM @Cuotas)
		THROW 54820, 'Seleccione al menos una factura para la contraseña.', 1;
	IF EXISTS (SELECT 1 FROM @Cuotas WHERE monto <= 0)
		THROW 54821, 'Cada cuota debe llevar un monto mayor a cero.', 1;

	DECLARE @forma_proveedor CHAR(1), @dia TINYINT;
	SELECT @forma_proveedor = prov.prv_forma_pago FROM dbo.inv_proveedor prov WHERE prov.prv_id = @PrvId AND prov.prv_estado = 'A';
	IF @forma_proveedor IS NULL
		THROW 54822, 'Elija un proveedor activo.', 1;
	SELECT @dia = comp.cia_dia_pago_proveedores
	FROM dbo.gen_sucursal sucu INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	WHERE sucu.suc_id = @SucId;
	SET @FormaPago = ISNULL(NULLIF(@FormaPago, ''), @forma_proveedor);
	IF @FormaPago NOT IN ('C', 'T')
		THROW 54823, 'La forma de pago es C (cheque) o T (transferencia).', 1;

	DECLARE @mensaje NVARCHAR(300);
	BEGIN TRY
		BEGIN TRANSACTION;

		DECLARE @lineas TABLE (ppg_id INT PRIMARY KEY, enc_id INT, prv_id INT, estado CHAR(1), documento VARCHAR(40), vence DATE, saldo NUMERIC(12, 2), monto NUMERIC(12, 2));
		INSERT INTO @lineas
		SELECT pide.ppg_id, cuot.enc_id, docu.prv_id, docu.enc_estado, CONCAT(ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto),
			   cuot.ppg_fecha_pago, cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0), pide.monto
		FROM @Cuotas pide
		LEFT JOIN dbo.inv_proveedor_plan_pago cuot WITH (UPDLOCK, HOLDLOCK) ON cuot.ppg_id = pide.ppg_id
		LEFT JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id;

		IF EXISTS (SELECT 1 FROM @lineas WHERE enc_id IS NULL OR prv_id <> @PrvId OR estado <> 'G')
			THROW 54824, 'Una de las cuotas no existe, no es de este proveedor o su compra está anulada.', 1;
		IF EXISTS (SELECT 1 FROM @lineas WHERE monto > saldo)
		BEGIN
			SELECT TOP 1 @mensaje = CONCAT(N'El monto de ', documento, N' (Q', FORMAT(monto, 'N2'), N') supera su saldo (Q', FORMAT(saldo, 'N2'), N').')
			FROM @lineas WHERE monto > saldo;
			THROW 54825, @mensaje, 1;
		END
		IF EXISTS (SELECT 1 FROM @lineas line
				   INNER JOIN dbo.cxp_contrasena_det deta ON deta.ppg_id = line.ppg_id
				   INNER JOIN dbo.cxp_contrasena_enc cont ON cont.cpa_id = deta.cpa_id AND cont.cpa_estado = 'E')
		BEGIN
			SELECT TOP 1 @mensaje = CONCAT(N'La factura ', line.documento, N' ya está en la contraseña ', cont.cpa_numero, N', pendiente de pago.')
			FROM @lineas line
			INNER JOIN dbo.cxp_contrasena_det deta ON deta.ppg_id = line.ppg_id
			INNER JOIN dbo.cxp_contrasena_enc cont ON cont.cpa_id = deta.cpa_id AND cont.cpa_estado = 'E';
			THROW 54826, @mensaje, 1;
		END

		DECLARE @base DATE = (SELECT MAX(vence) FROM @lineas);
		IF @base < @Fecha SET @base = @Fecha;
		SET @FechaPago = ISNULL(@FechaPago, dbo.fnProximoDiaPago(@base, @dia));
		IF @FechaPago < @Fecha
			THROW 54827, 'La fecha de pago no puede ser anterior a la fecha de la contraseña.', 1;

		DECLARE @siguiente INT = ISNULL((SELECT MAX(CAST(SUBSTRING(cpa_numero, 4, 12) AS INT)) FROM dbo.cxp_contrasena_enc WITH (UPDLOCK, HOLDLOCK)), 0) + 1;
		INSERT INTO dbo.cxp_contrasena_enc
			(cpa_numero, prv_id, suc_id, cpa_fecha, cpa_fecha_pago, cpa_forma_pago, cpa_total, cpa_observaciones, cpa_estado, usu_id, InsUsuario, InsFechaHora)
		VALUES
			(CONCAT('CP-', RIGHT(CONCAT('000000', @siguiente), 6)), @PrvId, @SucId, @Fecha, @FechaPago, @FormaPago,
			 (SELECT SUM(monto) FROM @lineas), NULLIF(LTRIM(RTRIM(@Observaciones)), ''), 'E', @UsuId, @UsuId, SYSDATETIME());
		SET @CpaId = SCOPE_IDENTITY();
		INSERT INTO dbo.cxp_contrasena_det (cpa_id, ppg_id, enc_id, cpd_monto)
		SELECT @CpaId, ppg_id, enc_id, monto FROM @lineas;
		SELECT @Numero = cpa_numero FROM dbo.cxp_contrasena_enc WHERE cpa_id = @CpaId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		SELECT @CpaId = NULL, @Numero = NULL;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paContrasenaAnular]
	@CpaId	INT,
	@Motivo	VARCHAR(250),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(LTRIM(RTRIM(@Motivo)), '') = ''
		THROW 54828, 'Indique el motivo de la anulación.', 1;
	UPDATE dbo.cxp_contrasena_enc
	   SET cpa_estado = 'A', cpa_motivo_anulacion = LTRIM(RTRIM(@Motivo)), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cpa_id = @CpaId AND cpa_estado = 'E';
	IF @@ROWCOUNT = 0
		THROW 54829, 'Solo se anula una contraseña pendiente de pago.', 1;
END;
GO

------------------------------------------------------------
-- 7. Pagar contraseñas
------------------------------------------------------------
-- Con cheque: lo pendiente de cada cuota de la contraseña (puede haberse
-- abonado algo por otro lado desde que se emitió).
CREATE OR ALTER PROCEDURE [dbo].[paContrasenaPagarCheque]
	@CpaId	INT,
	@CbcId	INT,
	@Numero	VARCHAR(16) = NULL,
	@UsuId	INT = NULL,
	@BceId	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	BEGIN TRY
		BEGIN TRANSACTION;
		DECLARE @prv_id INT, @numero_contrasena VARCHAR(16), @estado CHAR(1);
		SELECT @prv_id = prv_id, @numero_contrasena = cpa_numero, @estado = cpa_estado
		FROM dbo.cxp_contrasena_enc WITH (UPDLOCK, HOLDLOCK) WHERE cpa_id = @CpaId;
		IF @estado IS NULL OR @estado <> 'E'
			THROW 54830, 'Solo se paga una contraseña pendiente.', 1;

		DECLARE @cuotas dbo.cxp_pago_cuota_type;
		INSERT INTO @cuotas (ppg_id, monto)
		SELECT deta.ppg_id, IIF(deta.cpd_monto < cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0),
								deta.cpd_monto, cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0))
		FROM dbo.cxp_contrasena_det deta
		INNER JOIN dbo.inv_proveedor_plan_pago cuot ON cuot.ppg_id = deta.ppg_id
		WHERE deta.cpa_id = @CpaId AND cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) > 0;
		IF NOT EXISTS (SELECT 1 FROM @cuotas)
			THROW 54831, 'Las facturas de la contraseña ya no tienen saldo: anúlela.', 1;

		DECLARE @concepto VARCHAR(250) = LEFT(CONCAT('Pago contraseña ', @numero_contrasena, ': ',
			(SELECT STRING_AGG(CAST(CONCAT(ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto) AS VARCHAR(MAX)), ', ')
			 FROM (SELECT DISTINCT deta.enc_id FROM dbo.cxp_contrasena_det deta WHERE deta.cpa_id = @CpaId) facs
			 INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = facs.enc_id)), 250);

		EXEC dbo.paCxpChequeEmitir @PrvId = @prv_id, @CbcId = @CbcId, @Numero = @Numero, @Concepto = @concepto,
			@Cuotas = @cuotas, @UsuId = @UsuId, @BceId = @BceId OUTPUT;

		UPDATE dbo.cxp_contrasena_enc
		   SET cpa_estado = 'P', bce_id = @BceId, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE cpa_id = @CpaId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Por transferencia: un lote con una línea por contraseña y una sola póliza.
CREATE OR ALTER PROCEDURE [dbo].[paContrasenaPagarTransferencia]
	@BcbId			INT,
	@Fecha			DATE = NULL,
	@Referencia		VARCHAR(60) = NULL,
	@Contrasenas	dbo.id_lista_type READONLY,
	@UsuId			INT = NULL,
	@BltId			INT OUTPUT,
	@Numero			VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SELECT @BltId = NULL, @Numero = NULL, @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE)), @Referencia = NULLIF(LTRIM(RTRIM(@Referencia)), '');

	IF NOT EXISTS (SELECT 1 FROM @Contrasenas)
		THROW 54832, 'Seleccione al menos una contraseña a pagar.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId AND bcb_estado = 'A')
		THROW 54833, 'Elija una cuenta bancaria activa de la empresa.', 1;

	DECLARE @cta_proveedores INT, @cta_banco INT = dbo.fnBcoCuentaContable(@BcbId);
	EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_PROVEEDORES', @CtaId = @cta_proveedores OUTPUT;
	IF @cta_banco IS NULL
		EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_banco OUTPUT;

	DECLARE @mensaje NVARCHAR(300);
	BEGIN TRY
		BEGIN TRANSACTION;

		DECLARE @conts TABLE (cpa_id INT PRIMARY KEY, numero VARCHAR(16), prv_id INT, estado CHAR(1), proveedor VARCHAR(150), nit VARCHAR(20),
							  gef_id INT, tipo CHAR(1), cuenta VARCHAR(30), titular VARCHAR(150), correo VARCHAR(100));
		INSERT INTO @conts
		SELECT pide.id, cont.cpa_numero, cont.prv_id, cont.cpa_estado, prov.prv_nombre_comercial, prov.prv_nit,
			   prov.prv_gef_id, prov.prv_tipo_cuenta, prov.prv_numero_cuenta, ISNULL(prov.prv_cuenta_titular, prov.prv_nombre_comercial),
			   COALESCE(prov.prv_email_contacto, prov.prv_email_empresa)
		FROM @Contrasenas pide
		LEFT JOIN dbo.cxp_contrasena_enc cont WITH (UPDLOCK, HOLDLOCK) ON cont.cpa_id = pide.id
		LEFT JOIN dbo.inv_proveedor prov ON prov.prv_id = cont.prv_id;

		IF EXISTS (SELECT 1 FROM @conts WHERE estado IS NULL OR estado <> 'E')
			THROW 54834, 'Una de las contraseñas no existe o ya no está pendiente.', 1;
		IF EXISTS (SELECT 1 FROM @conts WHERE gef_id IS NULL OR tipo IS NULL OR cuenta IS NULL)
		BEGIN
			SELECT TOP 1 @mensaje = CONCAT(N'El proveedor ', proveedor, N' (contraseña ', numero, N') no tiene banco y cuenta para transferencia: complételos en Proveedores.')
			FROM @conts WHERE gef_id IS NULL OR tipo IS NULL OR cuenta IS NULL;
			THROW 54835, @mensaje, 1;
		END

		-- Lo que se paga de cada cuota: lo de la contraseña, sin pasar del saldo actual.
		DECLARE @cuotas TABLE (cpa_id INT, ppg_id INT, enc_id INT, documento VARCHAR(40), programado NUMERIC(12, 2), pagado NUMERIC(12, 2), monto NUMERIC(12, 2),
							   PRIMARY KEY (cpa_id, ppg_id));
		INSERT INTO @cuotas
		SELECT deta.cpa_id, deta.ppg_id, deta.enc_id, CONCAT(ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto),
			   cuot.ppg_valor_pago, ISNULL(cuot.ppg_valor_real_pago, 0),
			   IIF(deta.cpd_monto < cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0), deta.cpd_monto, cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0))
		FROM dbo.cxp_contrasena_det deta
		INNER JOIN @conts cont ON cont.cpa_id = deta.cpa_id
		INNER JOIN dbo.inv_proveedor_plan_pago cuot WITH (UPDLOCK, HOLDLOCK) ON cuot.ppg_id = deta.ppg_id
		INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = deta.enc_id AND docu.enc_estado = 'G'
		WHERE cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) > 0;
		IF EXISTS (SELECT 1 FROM @conts cont WHERE NOT EXISTS (SELECT 1 FROM @cuotas cuot WHERE cuot.cpa_id = cont.cpa_id))
		BEGIN
			SELECT TOP 1 @mensaje = CONCAT(N'Las facturas de la contraseña ', numero, N' ya no tienen saldo: anúlela.')
			FROM @conts cont WHERE NOT EXISTS (SELECT 1 FROM @cuotas cuot WHERE cuot.cpa_id = cont.cpa_id);
			THROW 54831, @mensaje, 1;
		END

		DECLARE @total NUMERIC(14, 2) = (SELECT SUM(monto) FROM @cuotas);
		DECLARE @siguiente INT = ISNULL((SELECT MAX(CAST(SUBSTRING(blt_numero, 4, 12) AS INT)) FROM dbo.bco_lote_transferencia WITH (UPDLOCK, HOLDLOCK)), 0) + 1;
		SET @Numero = CONCAT('LT-', RIGHT(CONCAT('000000', @siguiente), 6));
		INSERT INTO dbo.bco_lote_transferencia (blt_numero, blt_tipo, bcb_id, blt_fecha, blt_referencia, blt_total, blt_cantidad, blt_estado, usu_id, InsUsuario, InsFechaHora)
		VALUES (@Numero, 'P', @BcbId, @Fecha, @Referencia, @total, (SELECT COUNT(*) FROM @conts), 'A', @UsuId, @UsuId, SYSDATETIME());
		SET @BltId = SCOPE_IDENTITY();

		INSERT INTO dbo.bco_lote_transferencia_det
			(blt_id, bld_correlativo, cpa_id, prv_id, bld_beneficiario, bld_identificacion, gef_id, bld_tipo_cuenta, bld_cuenta, bld_monto, bld_referencia, bld_correo)
		SELECT @BltId, ROW_NUMBER() OVER (ORDER BY cont.proveedor, cont.cpa_id), cont.cpa_id, cont.prv_id, LEFT(cont.titular, 150),
			   NULLIF(REPLACE(cont.nit, '-', ''), ''), cont.gef_id, cont.tipo, cont.cuenta,
			   (SELECT SUM(cuot.monto) FROM @cuotas cuot WHERE cuot.cpa_id = cont.cpa_id),
			   LEFT(CONCAT('Pago contraseña ', cont.numero, ISNULL(' ' + @Referencia, '')), 100), cont.correo
		FROM @conts cont;

		INSERT INTO dbo.bco_lote_transferencia_cuota (bld_id, ppg_id, enc_id, blc_monto)
		SELECT line.bld_id, cuot.ppg_id, cuot.enc_id, cuot.monto
		FROM @cuotas cuot
		INNER JOIN dbo.bco_lote_transferencia_det line ON line.blt_id = @BltId AND line.cpa_id = cuot.cpa_id;

		UPDATE plan_
		   SET ppg_valor_real_pago = cuot.pagado + cuot.monto,
			   ppg_fecha_real_pago = @Fecha,
			   ppg_numero_cheque = @Numero,
			   ppg_estado = CASE WHEN cuot.pagado + cuot.monto >= cuot.programado THEN 'A' ELSE plan_.ppg_estado END,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		FROM dbo.inv_proveedor_plan_pago plan_
		INNER JOIN @cuotas cuot ON cuot.ppg_id = plan_.ppg_id;

		UPDATE cont
		   SET cpa_estado = 'P', blt_id = @BltId, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		FROM dbo.cxp_contrasena_enc cont
		INNER JOIN @conts pide ON pide.cpa_id = cont.cpa_id;

		-- Póliza: una línea al Debe por contraseña y el total al Haber del banco.
		DECLARE @asi_id INT, @partida dbo.cont_asiento_det_type;
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT @cta_proveedores, SUM(cuot.monto), 0, LEFT(CONCAT('Contraseña ', cont.numero, ' - ', cont.proveedor), 256)
		FROM @cuotas cuot INNER JOIN @conts cont ON cont.cpa_id = cuot.cpa_id
		GROUP BY cont.cpa_id, cont.numero, cont.proveedor;
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_banco, 0, @total, LEFT(CONCAT('Transferencias ', @Numero, ISNULL(' - ' + @Referencia, '')), 256));

		DECLARE @asi_descripcion VARCHAR(256) = LEFT(CONCAT('Pago a proveedores por transferencia ', @Numero,
			' (', (SELECT COUNT(*) FROM @conts), ' contraseña', IIF((SELECT COUNT(*) FROM @conts) = 1, '', 's'), ')'), 256);
		EXEC dbo.sp_contabilidad_insertar_asiento
			@asi_fecha = @Fecha, @asi_descripcion = @asi_descripcion,
			@asi_origen = 'PAGO_TRANSFERENCIA', @asi_origen_id = @BltId,
			@usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Anular un lote: devuelve el saldo a cada cuota, las contraseñas vuelven a
-- quedar pendientes y la póliza se anula.
CREATE OR ALTER PROCEDURE [dbo].[paLoteTransferenciaAnular]
	@BltId	INT,
	@Motivo	VARCHAR(250),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 54836, 'Indique el motivo de la anulación (al menos 5 caracteres).', 1;
	BEGIN TRY
		BEGIN TRANSACTION;
		IF NOT EXISTS (SELECT 1 FROM dbo.bco_lote_transferencia WITH (UPDLOCK, HOLDLOCK) WHERE blt_id = @BltId AND blt_estado = 'A')
			THROW 54837, 'El lote no existe o ya está anulado.', 1;

		UPDATE cuot
		   SET ppg_valor_real_pago = ISNULL(cuot.ppg_valor_real_pago, 0) - pago.monto,
			   ppg_estado = 'P',
			   ppg_numero_cheque = CASE WHEN cuot.ppg_numero_cheque = lote.blt_numero THEN NULL ELSE cuot.ppg_numero_cheque END,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		FROM dbo.inv_proveedor_plan_pago cuot
		INNER JOIN (SELECT blcu.ppg_id, SUM(blcu.blc_monto) AS monto
					FROM dbo.bco_lote_transferencia_cuota blcu
					INNER JOIN dbo.bco_lote_transferencia_det line ON line.bld_id = blcu.bld_id
					WHERE line.blt_id = @BltId GROUP BY blcu.ppg_id) pago ON pago.ppg_id = cuot.ppg_id
		CROSS JOIN (SELECT blt_numero FROM dbo.bco_lote_transferencia WHERE blt_id = @BltId) lote;

		UPDATE dbo.cxp_contrasena_enc
		   SET cpa_estado = 'E', blt_id = NULL, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE blt_id = @BltId AND cpa_estado = 'P';

		UPDATE dbo.bco_lote_transferencia
		   SET blt_estado = 'N', blt_motivo_anulacion = LTRIM(RTRIM(@Motivo)), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE blt_id = @BltId;

		UPDATE dbo.cont_asiento_enc
		   SET asi_estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE asi_origen = 'PAGO_TRANSFERENCIA' AND asi_origen_id = @BltId AND asi_estado = 'A';
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paLoteTransferenciaConsultar]
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT lote.blt_id AS BltId, lote.blt_numero AS Numero, lote.blt_fecha AS Fecha, lote.blt_referencia AS Referencia,
		   lote.blt_total AS Total, lote.blt_cantidad AS Cantidad, lote.blt_estado AS Estado, lote.blt_motivo_anulacion AS MotivoAnulacion,
		   lote.bcb_id AS BcbId, CONCAT(enti.gef_descripcion, ' ', cuba.bcb_numero_cuenta) AS CuentaOrigen, cuba.gef_id AS GefIdOrigen,
		   usua.usu_codigo AS Usuario
	FROM dbo.bco_lote_transferencia lote
	INNER JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = lote.bcb_id
	INNER JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuba.gef_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = lote.usu_id
	WHERE (@Desde IS NULL OR lote.blt_fecha >= @Desde) AND (@Hasta IS NULL OR lote.blt_fecha <= @Hasta)
	ORDER BY lote.blt_id DESC;
END;
GO

------------------------------------------------------------
-- 8. Datos para escribir el archivo del banco
------------------------------------------------------------
-- Las dos consultas devuelven las mismas columnas: 1) encabezado del lote,
-- 2) una fila por transferencia.
CREATE OR ALTER PROCEDURE [dbo].[paLoteTransferenciaArchivo]
	@BltId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT lote.blt_numero AS Numero, lote.blt_fecha AS Fecha, lote.blt_referencia AS Referencia, lote.blt_total AS Total,
		   lote.blt_cantidad AS Cantidad, REPLACE(cuba.bcb_numero_cuenta, ' ', '') AS CuentaOrigen, cuba.gef_id AS GefIdOrigen,
		   enti.gef_descripcion AS BancoOrigen, lote.blt_estado AS Estado, 'Pago a proveedores' AS Descripcion
	FROM dbo.bco_lote_transferencia lote
	INNER JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = lote.bcb_id
	INNER JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuba.gef_id
	WHERE lote.blt_id = @BltId;

	SELECT line.bld_correlativo AS Correlativo, prov.prv_codigo AS Codigo, line.bld_beneficiario AS Beneficiario,
		   line.bld_identificacion AS Identificacion, line.gef_id AS GefId, enti.gef_codigo AS BancoCodigo, enti.gef_descripcion AS Banco,
		   line.bld_tipo_cuenta AS TipoCuenta, line.bld_cuenta AS Cuenta, line.bld_monto AS Monto, line.bld_referencia AS Referencia,
		   line.bld_correo AS Correo, cont.cpa_numero AS Documento
	FROM dbo.bco_lote_transferencia_det line
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = line.prv_id
	INNER JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = line.gef_id
	LEFT JOIN dbo.cxp_contrasena_enc cont ON cont.cpa_id = line.cpa_id
	WHERE line.blt_id = @BltId
	ORDER BY line.bld_correlativo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaTransferenciaArchivo]
	@IdNominaPago	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT CONCAT('NOM-', pago.IdNominaPago) AS Numero, pago.FechaPago AS Fecha, pago.Referencia, pago.Monto AS Total,
		   pago.Empleados AS Cantidad, REPLACE(cuba.bcb_numero_cuenta, ' ', '') AS CuentaOrigen, cuba.gef_id AS GefIdOrigen,
		   enti.gef_descripcion AS BancoOrigen, pago.Estado, CONCAT('Planilla ', nomi.Descripcion) AS Descripcion
	FROM dbo.rrhhNominaPago pago
	INNER JOIN dbo.rrhhNomina nomi ON nomi.IdNomina = pago.IdNomina
	INNER JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = pago.bcb_id
	INNER JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuba.gef_id
	WHERE pago.IdNominaPago = @IdNominaPago AND pago.Tipo = 'T';

	SELECT ROW_NUMBER() OVER (ORDER BY empl.PrimerApellido, empl.PrimerNombre, empl.IdEmpleado) AS Correlativo,
		   empl.CodigoEmpleado AS Codigo,
		   CONCAT_WS(' ', empl.PrimerNombre, NULLIF(empl.SegundoNombre, ''), empl.PrimerApellido, NULLIF(empl.SegundoApellido, '')) AS Beneficiario,
		   empl.NumeroDocumento AS Identificacion, nemp.gef_id AS GefId, enti.gef_codigo AS BancoCodigo, enti.gef_descripcion AS Banco,
		   ISNULL(nemp.TipoCuenta, 'M') AS TipoCuenta, REPLACE(nemp.NumeroCuenta, ' ', '') AS Cuenta, nemp.Liquido AS Monto,
		   LEFT(CONCAT('Planilla ', nomi.Descripcion), 100) AS Referencia, empl.Email AS Correo, CAST(NULL AS VARCHAR(16)) AS Documento
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = nemp.IdEmpleado
	INNER JOIN dbo.rrhhNominaPago pago ON pago.IdNominaPago = nemp.IdNominaPago
	INNER JOIN dbo.rrhhNomina nomi ON nomi.IdNomina = pago.IdNomina
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = nemp.gef_id
	WHERE nemp.IdNominaPago = @IdNominaPago
	ORDER BY empl.PrimerApellido, empl.PrimerNombre, empl.IdEmpleado;
END;
GO

------------------------------------------------------------
-- 9. Lo que ya existía, contando las transferencias
------------------------------------------------------------
-- Igual que en 36; si el cheque pagaba una contraseña, la contraseña vuelve
-- a quedar pendiente de pago.
CREATE OR ALTER PROCEDURE [dbo].[paCxpChequeAnular]
	@BceId	INT,
	@Motivo	VARCHAR(256),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado CHAR(1) = (SELECT bce_estado_cheque FROM dbo.bco_cheque_emitido_enc WHERE bce_id = @BceId);
	IF @estado IS NULL
		THROW 53218, 'El cheque indicado no existe.', 1;
	IF @estado = 'A'
		THROW 53219, 'El cheque ya está anulado.', 1;
	IF @estado = 'C'
		THROW 53220, 'El cheque ya fue cobrado por el proveedor; no se puede anular.', 1;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 53214, 'Indique el motivo de la anulación (al menos 5 caracteres).', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_det WHERE bce_id = @BceId AND ppg_id IS NULL)
		THROW 53221, 'No se puede determinar la cuota que pagó este cheque; anúlelo manualmente con contabilidad.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		UPDATE cuot
		   SET ppg_valor_real_pago = ISNULL(cuot.ppg_valor_real_pago, 0) - chdt.ced_valor,
			   ppg_estado = 'P',
			   ppg_numero_cheque = CASE WHEN cuot.ppg_numero_cheque = cheq.bce_numero_cheque THEN NULL ELSE cuot.ppg_numero_cheque END,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		FROM dbo.inv_proveedor_plan_pago cuot
		INNER JOIN dbo.bco_cheque_emitido_det chdt ON chdt.ppg_id = cuot.ppg_id
		INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = chdt.bce_id
		WHERE chdt.bce_id = @BceId;

		UPDATE dbo.bco_cheque_emitido_enc
		   SET bce_estado_cheque = 'A',
			   bce_observaciones = LEFT(CONCAT('ANULADO: ', LTRIM(RTRIM(@Motivo)), ISNULL(' | ' + bce_observaciones, '')), 250),
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE bce_id = @BceId;

		UPDATE dbo.cont_asiento_enc
		   SET asi_estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE asi_origen = 'PAGO_PROVEEDOR' AND asi_origen_id = @BceId AND asi_estado = 'A';

		UPDATE dbo.cxp_contrasena_enc
		   SET cpa_estado = 'E', bce_id = NULL, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE bce_id = @BceId AND cpa_estado = 'P';

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Igual que en 34, con las transferencias como abonos.
CREATE OR ALTER PROCEDURE [dbo].[paCxpEstadoCuentaConsultar]
	@PrvId	INT,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @Hasta = ISNULL(@Hasta, CAST(GETDATE() AS DATE));

	-- Desde el punto de vista de lo que se le debe al proveedor: la compra y
	-- la nota de débito son cargos; el cheque, la transferencia y la nota de
	-- crédito, abonos.
	DECLARE @movimientos TABLE (Fecha DATE, Orden INT, Id INT, Tipo VARCHAR(20), Documento VARCHAR(40), Referencia VARCHAR(80),
		Cargo NUMERIC(14, 2), Abono NUMERIC(14, 2));

	INSERT INTO @movimientos
	SELECT enca.enc_fecha_docto, 1, enca.enc_id, 'Compra',
		   CONCAT(tipo.tdo_codigo, ' ', ISNULL(enca.enc_serie_docto + '-', ''), enca.enc_numero_docto),
		   CONCAT(enca.enc_numero_cuotas, ' cuota(s)'), enca.enc_monto_total, 0
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_naturaleza = '+' AND tipo.tdo_es_nota = 0
	WHERE enca.prv_id = @PrvId AND enca.enc_estado = 'G'
	UNION ALL
	SELECT nota.enc_fecha_docto, 2, nota.enc_id, CASE tnot.tdo_codigo WHEN 'NCP' THEN 'Nota de crédito' ELSE 'Nota de débito' END,
		   CONCAT(tnot.tdo_codigo, ' ', nota.enc_numero_docto), CONCAT('Doc. ', refe.enc_numero_docto, ': ', LEFT(nota.enc_motivo, 60)),
		   CASE WHEN tnot.tdo_codigo = 'NDP' THEN nota.enc_monto_total ELSE 0 END,
		   CASE WHEN tnot.tdo_codigo = 'NCP' THEN nota.enc_monto_total ELSE 0 END
	FROM dbo.inv_documento_enc nota
	INNER JOIN dbo.inv_documento_tipo tnot ON tnot.tdo_id = nota.tdo_id AND tnot.tdo_codigo IN ('NCP', 'NDP')
	INNER JOIN dbo.inv_documento_enc refe ON refe.enc_id = nota.enc_id_referencia AND refe.enc_estado = 'G'
	WHERE nota.prv_id = @PrvId AND nota.enc_estado = 'G'
	UNION ALL
	SELECT cheq.bce_fecha_emision, 3, chdt.ced_id, 'Cheque', CONCAT('Cheque ', cheq.bce_numero_cheque),
		   CONCAT('Doc. ', docu.enc_numero_docto), 0, chdt.ced_valor
	FROM dbo.bco_cheque_emitido_det chdt
	INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = chdt.bce_id AND cheq.bce_estado_cheque <> 'A'
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = chdt.enc_id AND docu.enc_estado = 'G'
	WHERE docu.prv_id = @PrvId
	UNION ALL
	SELECT lote.blt_fecha, 3, 1000000000 + blcu.ppg_id, 'Transferencia', CONCAT('Transferencia ', lote.blt_numero),
		   CONCAT('Doc. ', docu.enc_numero_docto), 0, blcu.blc_monto
	FROM dbo.bco_lote_transferencia_cuota blcu
	INNER JOIN dbo.bco_lote_transferencia_det line ON line.bld_id = blcu.bld_id
	INNER JOIN dbo.bco_lote_transferencia lote ON lote.blt_id = line.blt_id AND lote.blt_estado = 'A'
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = blcu.enc_id AND docu.enc_estado = 'G'
	WHERE docu.prv_id = @PrvId;

	DECLARE @saldo_inicial NUMERIC(14, 2) = (SELECT ISNULL(SUM(Cargo - Abono), 0) FROM @movimientos WHERE @Desde IS NOT NULL AND Fecha < @Desde);

	SELECT Fecha, Tipo, Documento, Referencia, Cargo, Abono,
		   @saldo_inicial + SUM(Cargo - Abono) OVER (ORDER BY Fecha, Orden, Id ROWS UNBOUNDED PRECEDING) AS Saldo,
		   @saldo_inicial AS SaldoInicial
	FROM @movimientos
	WHERE (@Desde IS NULL OR Fecha >= @Desde) AND Fecha <= @Hasta
	ORDER BY Fecha, Orden, Id;
END;
GO

-- Igual que en 42; lo pagado del período incluye las transferencias.
CREATE OR ALTER PROCEDURE [dbo].[paTableroCompras]
	@Desde	DATE,
	@Hasta	DATE,
	@SucId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @Hasta < @Desde
		THROW 53314, 'La fecha final no puede ser anterior a la inicial.', 1;
	DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
	DECLARE @dias INT = DATEDIFF(DAY, @Desde, @Hasta) + 1;
	DECLARE @antDesde DATE = DATEADD(DAY, -@dias, @Desde);

	DECLARE @docs TABLE (enc_id INT PRIMARY KEY, fecha DATE, actual BIT, prv_id INT, neto NUMERIC(14, 2), total NUMERIC(14, 2));
	INSERT INTO @docs
	SELECT docu.enc_id, docu.enc_fecha_docto, CASE WHEN docu.enc_fecha_docto >= @Desde THEN 1 ELSE 0 END, docu.prv_id,
		   (SELECT SUM(deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) FROM dbo.inv_documento_det deta WHERE deta.enc_id = docu.enc_id),
		   docu.enc_monto_total
	FROM dbo.inv_documento_enc docu
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id AND tipo.tdo_naturaleza = '+' AND tipo.tdo_es_nota = 0 AND tipo.tdo_es_interno = 0
	WHERE docu.enc_estado = 'G' AND docu.enc_fecha_docto BETWEEN @antDesde AND @Hasta
	  AND (@SucId IS NULL OR dbo.fnDocumentoSucursal(docu.enc_id) = @SucId);

	-- Cuotas por pagar (todas las compras vigentes, no solo las del período).
	DECLARE @cuotas TABLE (ppg_id INT PRIMARY KEY, enc_id INT, prv_id INT, nro INT, vence DATE, saldo NUMERIC(14, 2));
	INSERT INTO @cuotas
	SELECT cuot.ppg_id, cuot.enc_id, docu.prv_id, cuot.ppg_nro_pago, cuot.ppg_fecha_pago, cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0)
	FROM dbo.inv_proveedor_plan_pago cuot
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
	WHERE cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0) > 0
	  AND (@SucId IS NULL OR dbo.fnDocumentoSucursal(docu.enc_id) = @SucId);

	DECLARE @pagos TABLE (tipo CHAR(1), id INT, fecha DATE, valor NUMERIC(14, 2), PRIMARY KEY (tipo, id));
	INSERT INTO @pagos
	SELECT 'C', cheq.bce_id, cheq.bce_fecha_emision, cheq.bce_valor
	FROM dbo.bco_cheque_emitido_enc cheq
	WHERE cheq.bce_estado_cheque <> 'A' AND cheq.bce_fecha_emision BETWEEN @Desde AND @Hasta
	  AND (@SucId IS NULL OR EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_det chdt WHERE chdt.bce_id = cheq.bce_id
									 AND dbo.fnDocumentoSucursal(chdt.enc_id) = @SucId))
	UNION ALL
	SELECT 'T', line.bld_id, lote.blt_fecha, ISNULL(SUM(blcu.blc_monto), 0)
	FROM dbo.bco_lote_transferencia_det line
	INNER JOIN dbo.bco_lote_transferencia lote ON lote.blt_id = line.blt_id AND lote.blt_estado = 'A'
	INNER JOIN dbo.bco_lote_transferencia_cuota blcu ON blcu.bld_id = line.bld_id
	WHERE lote.blt_fecha BETWEEN @Desde AND @Hasta
	  AND (@SucId IS NULL OR dbo.fnDocumentoSucursal(blcu.enc_id) = @SucId)
	GROUP BY line.bld_id, lote.blt_fecha;

	SELECT ISNULL(SUM(CASE WHEN actual = 1 THEN neto END), 0) AS Compras,
		   COUNT(CASE WHEN actual = 1 THEN 1 END) AS Documentos,
		   ISNULL(SUM(CASE WHEN actual = 0 THEN neto END), 0) AS ComprasAnterior,
		   ISNULL((SELECT SUM(saldo) FROM @cuotas), 0) AS PorPagar,
		   ISNULL((SELECT SUM(saldo) FROM @cuotas WHERE vence < @hoy), 0) AS Vencido,
		   ISNULL((SELECT SUM(saldo) FROM @cuotas WHERE vence BETWEEN @hoy AND DATEADD(DAY, 30, @hoy)), 0) AS Proximos30,
		   ISNULL((SELECT SUM(valor) FROM @pagos), 0) AS Pagado,
		   (SELECT COUNT(*) FROM @pagos) AS Cheques,
		   CAST(CASE WHEN @dias <= 62 THEN 'D' ELSE 'M' END AS CHAR(1)) AS Agrupacion
	FROM @docs;

	;WITH compras AS (
		SELECT dbo.fnTableroPeriodo(fecha, @Desde, @Hasta) AS Periodo, SUM(neto) AS Monto FROM @docs WHERE actual = 1
		GROUP BY dbo.fnTableroPeriodo(fecha, @Desde, @Hasta)
	), pagado AS (
		SELECT dbo.fnTableroPeriodo(fecha, @Desde, @Hasta) AS Periodo, SUM(valor) AS Monto FROM @pagos
		GROUP BY dbo.fnTableroPeriodo(fecha, @Desde, @Hasta)
	)
	SELECT COALESCE(comp.Periodo, paga.Periodo) AS Periodo, ISNULL(comp.Monto, 0) AS Compras, ISNULL(paga.Monto, 0) AS Pagado
	FROM compras comp FULL OUTER JOIN pagado paga ON paga.Periodo = comp.Periodo
	ORDER BY Periodo;

	SELECT TOP 10 prov.prv_id AS Id, prov.prv_codigo AS Codigo, prov.prv_nombre_comercial AS Nombre,
		   ISNULL(SUM(docs.neto), 0) AS Compras,
		   ISNULL((SELECT SUM(cuot.saldo) FROM @cuotas cuot WHERE cuot.prv_id = prov.prv_id), 0) AS Saldo
	FROM @docs docs INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = docs.prv_id
	WHERE docs.actual = 1
	GROUP BY prov.prv_id, prov.prv_codigo, prov.prv_nombre_comercial
	ORDER BY Compras DESC;

	-- Compromisos de pago: lo vencido y las próximas 12 semanas (lunes a domingo).
	DECLARE @lunes DATE = DATEADD(DAY, -((DATEPART(WEEKDAY, @hoy) + @@DATEFIRST - 2) % 7), @hoy);
	;WITH semanas AS (
		SELECT 0 AS Orden, CAST(NULL AS DATE) AS Desde, DATEADD(DAY, -1, @hoy) AS Hasta
		UNION ALL
		SELECT n.n, DATEADD(WEEK, n.n - 1, @lunes), DATEADD(DAY, 6, DATEADD(WEEK, n.n - 1, @lunes))
		FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12)) n(n)
	)
	SELECT sema.Orden, sema.Desde, sema.Hasta, ISNULL(SUM(cuot.saldo), 0) AS Monto, COUNT(cuot.ppg_id) AS Cuotas
	FROM semanas sema
	LEFT JOIN @cuotas cuot ON (sema.Orden = 0 AND cuot.vence < @hoy)
						   OR (sema.Orden > 0 AND cuot.vence BETWEEN CASE WHEN sema.Desde < @hoy THEN @hoy ELSE sema.Desde END AND sema.Hasta)
	GROUP BY sema.Orden, sema.Desde, sema.Hasta
	ORDER BY sema.Orden;

	SELECT TOP 15 prov.prv_id AS PrvId, prov.prv_nombre_comercial AS Proveedor, cuot.enc_id AS EncId,
		   CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto) AS Documento,
		   cuot.nro AS Cuota, cuot.vence AS Vence, cuot.saldo AS Saldo, DATEDIFF(DAY, @hoy, cuot.vence) AS Dias
	FROM @cuotas cuot
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = cuot.prv_id
	ORDER BY cuot.vence, cuot.ppg_id;
END;
GO

-- Igual que en 51; el control 6 suma cheques y transferencias vigentes.
CREATE OR ALTER PROCEDURE [dbo].[paAuditoriaIntegridadConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @r TABLE (Orden INT, Control VARCHAR(120), Casos INT, Ejemplo VARCHAR(200));

	INSERT INTO @r
	SELECT 1, 'Pólizas descuadradas (Debe distinto del Haber)', COUNT(*), MIN(CAST(asi_id AS VARCHAR(20)))
	FROM (SELECT asi_id FROM dbo.cont_asiento_det GROUP BY asi_id HAVING SUM(asd_debe) <> SUM(asd_haber)) desc_;

	INSERT INTO @r
	SELECT 2, 'Líneas de póliza en cuentas de agrupación', COUNT(*), MIN(CONCAT('póliza ', deta.asi_id, ' cuenta ', cuen.cta_codigo))
	FROM dbo.cont_asiento_det deta INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = deta.cta_id
	WHERE cuen.cta_acepta_movimiento = 0;

	INSERT INTO @r
	SELECT 3, 'Documentos vigentes sin póliza vigente', COUNT(*), MIN(CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_numero_unico, docu.enc_numero_docto)))
	FROM dbo.inv_documento_enc docu
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	WHERE docu.enc_estado = 'G' AND tipo.tdo_codigo <> 'INVI'
	  AND NOT EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.enc_id = docu.enc_id AND asie.asi_estado = 'A')
	  AND NOT EXISTS (SELECT 1 FROM dbo.inv_traslado tras WHERE docu.enc_id IN (tras.enc_id_salida, tras.enc_id_ingreso, tras.enc_id_devolucion));

	INSERT INTO @r
	SELECT 4, 'Documentos anulados con póliza vigente', COUNT(*), MIN(CAST(docu.enc_id AS VARCHAR(20)))
	FROM dbo.inv_documento_enc docu
	WHERE docu.enc_estado = 'A' AND EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.enc_id = docu.enc_id AND asie.asi_estado = 'A'
											 AND asie.asi_origen NOT IN ('PAGO_CLIENTE', 'PAGO_PROVEEDOR'));

	INSERT INTO @r
	-- La nota de crédito rebaja el saldo de la cuota; la de débito crea una
	-- cuota nueva por su monto (no se resta).
	SELECT 5, 'Cuotas de clientes: saldo distinto de valor - cobros vigentes - notas de crédito', COUNT(*), MIN(CAST(cuot.cpp_id AS VARCHAR(20)))
	FROM dbo.pos_cliente_plan_pagos cuot
	CROSS APPLY (SELECT ISNULL(SUM(deta.ppd_valor_aplicado), 0) AS Cobrado
				 FROM dbo.pos_pago_det deta INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id
				 WHERE deta.cpp_id = cuot.cpp_id AND pago.ppe_estado = 'A') cobr
	CROSS APPLY (SELECT ISNULL(SUM(apli.cna_monto), 0) AS Notas
				 FROM dbo.pos_cliente_nota_aplicacion apli
				 INNER JOIN dbo.inv_documento_enc nota ON nota.enc_id = apli.enc_id_nota
				 INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = nota.tdo_id
				 WHERE apli.cpp_id = cuot.cpp_id AND tipo.tdo_codigo = 'NCC') nota
	WHERE ABS(cuot.cpp_valor_cuota - cobr.Cobrado - nota.Notas - cuot.cpp_saldo_cuota) > 0.01;

	INSERT INTO @r
	-- Las notas a proveedores cambian el valor de la cuota (o crean una), no lo pagado.
	SELECT 6, 'Cuotas de proveedores: pagado distinto de los cheques y transferencias vigentes', COUNT(*), MIN(CAST(cuot.ppg_id AS VARCHAR(20)))
	FROM dbo.inv_proveedor_plan_pago cuot
	CROSS APPLY (SELECT ISNULL(SUM(deta.ced_valor), 0) AS Pagado
				 FROM dbo.bco_cheque_emitido_det deta INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = deta.bce_id
				 WHERE deta.ppg_id = cuot.ppg_id AND cheq.bce_estado_cheque <> 'A') cheq
	CROSS APPLY (SELECT ISNULL(SUM(blcu.blc_monto), 0) AS Pagado
				 FROM dbo.bco_lote_transferencia_cuota blcu
				 INNER JOIN dbo.bco_lote_transferencia_det line ON line.bld_id = blcu.bld_id
				 INNER JOIN dbo.bco_lote_transferencia lote ON lote.blt_id = line.blt_id AND lote.blt_estado = 'A'
				 WHERE blcu.ppg_id = cuot.ppg_id) trns
	WHERE ABS(ISNULL(cuot.ppg_valor_real_pago, 0) - cheq.Pagado - trns.Pagado) > 0.01
	   OR ISNULL(cuot.ppg_valor_real_pago, 0) > cuot.ppg_valor_pago + 0.01;

	INSERT INTO @r
	SELECT 7, 'Existencias negativas', COUNT(*), MIN(CONCAT('producto ', pro_id, ' bodega ', bod_id))
	FROM dbo.inv_producto_existencia_bodega WHERE existencia < 0;

	INSERT INTO @r
	SELECT 8, 'Nóminas aprobadas sin póliza vigente', COUNT(*), MIN(nomi.Descripcion)
	FROM dbo.rrhhNomina nomi
	WHERE nomi.Estado = 'A' AND NOT EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.asi_origen = 'NOMINA' AND asie.asi_origen_id = nomi.IdNomina AND asie.asi_estado = 'A');

	INSERT INTO @r
	SELECT 9, 'Pagos de nómina vigentes que no suman el líquido de sus empleados', COUNT(*), MIN(CAST(pago.IdNominaPago AS VARCHAR(20)))
	FROM dbo.rrhhNominaPago pago
	CROSS APPLY (SELECT ISNULL(SUM(nemp.Liquido), 0) AS Liquido FROM dbo.rrhhNominaEmpleado nemp WHERE nemp.IdNominaPago = pago.IdNominaPago) suma
	WHERE pago.Estado = 'A' AND pago.Monto <> suma.Liquido;

	INSERT INTO @r
	SELECT 10, 'Empleados pagados en una nómina no aprobada', COUNT(*), MIN(CAST(nemp.IdNominaEmpleado AS VARCHAR(20)))
	FROM dbo.rrhhNominaEmpleado nemp INNER JOIN dbo.rrhhNomina nomi ON nomi.IdNomina = nemp.IdNomina
	WHERE nemp.IdNominaPago IS NOT NULL AND nomi.Estado <> 'A';

	INSERT INTO @r
	SELECT 11, 'Traslados en tránsito sin salida de inventario', COUNT(*), MIN(CAST(tras.tra_numero AS VARCHAR(20)))
	FROM dbo.inv_traslado tras
	WHERE tras.tra_estado = 'E' AND (tras.enc_id_salida IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.inv_documento_enc docu WHERE docu.enc_id = tras.enc_id_salida AND docu.enc_estado = 'G'));

	INSERT INTO @r
	SELECT 12, 'Recibos vigentes sin póliza vigente', COUNT(*), MIN(CAST(pago.ppe_id AS VARCHAR(20)))
	FROM dbo.pos_pago_enc pago
	WHERE pago.ppe_estado = 'A'
	  AND NOT EXISTS (SELECT 1 FROM dbo.pos_pago_det deta WHERE deta.ppe_id = pago.ppe_id AND deta.enc_id IS NOT NULL)
	  AND NOT EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie WHERE asie.asi_origen = 'PAGO_CLIENTE' AND asie.asi_origen_id = pago.ppe_id AND asie.asi_estado = 'A');

	INSERT INTO @r
	-- Script 51: una nota se aplica completa a las cuotas o no se graba.
	SELECT 13, 'Notas vigentes cuyo total no coincide con lo aplicado a las cuotas', COUNT(*), MIN(CONCAT(tipo.tdo_codigo, ' ', ISNULL(nota.enc_numero_unico, nota.enc_numero_docto)))
	FROM dbo.inv_documento_enc nota
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = nota.tdo_id
	CROSS APPLY (SELECT ISNULL((SELECT SUM(apli.cna_monto) FROM dbo.pos_cliente_nota_aplicacion apli WHERE apli.enc_id_nota = nota.enc_id), 0)
					  + ISNULL((SELECT SUM(apli.pna_monto) FROM dbo.inv_proveedor_nota_aplicacion apli WHERE apli.enc_id_nota = nota.enc_id), 0) AS Aplicado) apli
	WHERE tipo.tdo_es_nota = 1 AND nota.enc_estado = 'G'
	  AND (EXISTS (SELECT 1 FROM dbo.pos_cliente_nota_aplicacion x WHERE x.enc_id_nota = nota.enc_id)
		   OR EXISTS (SELECT 1 FROM dbo.inv_proveedor_nota_aplicacion x WHERE x.enc_id_nota = nota.enc_id))
	  AND ABS(nota.enc_monto_total - apli.Aplicado) > 0.01;

	SELECT Orden, Control, Casos, CASE WHEN Casos = 0 THEN NULL ELSE Ejemplo END AS Ejemplo,
		   CASE WHEN Casos = 0 THEN 'OK' ELSE 'REVISAR' END AS Resultado
	FROM @r ORDER BY Orden;
END;
GO

-- Igual que en 34; una compra pagada por transferencia o en una contraseña
-- pendiente no se anula sin anular antes el lote o la contraseña.
CREATE OR ALTER PROCEDURE [dbo].[sp_documento_anular]
	@enc_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado_actual CHAR(1), @es_nota BIT;
	SELECT @estado_actual = enca.enc_estado, @es_nota = tipo.tdo_es_nota
	FROM dbo.inv_documento_enc enca INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @enc_id;

	IF @estado_actual IS NULL
		THROW 51421, 'El documento indicado no existe.', 1;
	IF @estado_actual <> 'G'
		THROW 51422, 'Solo se pueden anular documentos que estén en estado Grabado.', 1;
	IF @es_nota = 1
		THROW 51423, 'Una nota de crédito o débito no se anula; emita la nota contraria.', 1;
	IF EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_id_referencia = @enc_id AND enc_estado = 'G')
		THROW 51424, 'El documento tiene notas de crédito o débito; no se puede anular.', 1;
	IF EXISTS (SELECT 1 FROM dbo.pos_pago_det deta
			   INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
			   INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = deta.cpp_id
			   WHERE cuot.enc_id = @enc_id)
		THROW 53227, 'La factura tiene cobros de cuotas; anule primero esos recibos en Cuentas por cobrar › Cobros.', 1;
	IF EXISTS (SELECT 1 FROM dbo.pos_pago_det deta
			   INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
			   LEFT JOIN dbo.pos_caja_apertura aper ON aper.pca_id = pago.pca_id
			   WHERE deta.enc_id = @enc_id AND ISNULL(aper.pca_estado, 'C') <> 'A')
		THROW 53228, 'El pago de esta factura entró a una caja que ya se cerró; no se puede anular: emita una nota de crédito.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_det chdt
			   INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = chdt.bce_id AND cheq.bce_estado_cheque <> 'A'
			   WHERE chdt.enc_id = @enc_id)
		THROW 53229, 'La compra tiene cheques emitidos; anule primero esos cheques en Cuentas por pagar › Pagos.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_lote_transferencia_cuota blcu
			   INNER JOIN dbo.bco_lote_transferencia_det line ON line.bld_id = blcu.bld_id
			   INNER JOIN dbo.bco_lote_transferencia lote ON lote.blt_id = line.blt_id AND lote.blt_estado = 'A'
			   WHERE blcu.enc_id = @enc_id)
		THROW 54838, 'La compra se pagó por transferencia; anule primero ese lote en Cuentas por pagar › Pagos programados.', 1;
	IF EXISTS (SELECT 1 FROM dbo.cxp_contrasena_det deta
			   INNER JOIN dbo.cxp_contrasena_enc cont ON cont.cpa_id = deta.cpa_id AND cont.cpa_estado = 'E'
			   WHERE deta.enc_id = @enc_id)
		THROW 54839, 'La compra está en una contraseña de pago pendiente; anule primero la contraseña.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		-- El pago de contado o enganche sale del cuadre de la caja (sigue abierta).
		DECLARE @ppe_id INT;
		DECLARE recibos CURSOR LOCAL FAST_FORWARD FOR
			SELECT DISTINCT deta.ppe_id FROM dbo.pos_pago_det deta
			INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
			WHERE deta.enc_id = @enc_id;
		OPEN recibos;
		FETCH NEXT FROM recibos INTO @ppe_id;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			EXEC dbo.paCxcReciboReversar @PpeId = @ppe_id, @Motivo = 'Anulación de la factura', @UsuId = @usu_id;
			FETCH NEXT FROM recibos INTO @ppe_id;
		END
		CLOSE recibos; DEALLOCATE recibos;

		EXEC dbo.sp_inventario_ajustar_existencia_documento @enc_id = @enc_id, @reversar = 1, @usu_id = @usu_id;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'A',
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @enc_id;

		UPDATE dbo.cont_asiento_enc
		   SET asi_estado = 'N',
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @enc_id;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 10. Formatos de ejemplo
------------------------------------------------------------
-- Genérico: CSV con títulos, sirve para revisar el lote o para bancos que
-- aceptan una hoja simple. Ancho fijo: un ejemplo de archivo de banco con
-- encabezado y pie; cada banco entrega su especificación y se ajusta en
-- Bancos › Formatos de archivo.
DECLARE @columnas dbo.formato_archivo_columna_type, @bancos dbo.formato_archivo_banco_type, @bfa INT;
IF NOT EXISTS (SELECT 1 FROM dbo.bco_formato_archivo WHERE bfa_nombre = 'Genérico CSV')
BEGIN
	INSERT INTO @columnas (orden, campo, titulo, longitud, relleno, alineacion, valor, mayusculas) VALUES
		(1, 'CORRELATIVO', 'No.', NULL, NULL, 'I', NULL, 0),
		(2, 'CODIGO', 'Código', NULL, NULL, 'I', NULL, 0),
		(3, 'BENEFICIARIO', 'Beneficiario', NULL, NULL, 'I', NULL, 0),
		(4, 'IDENTIFICACION', 'NIT/DPI', NULL, NULL, 'I', NULL, 0),
		(5, 'BANCO_DESTINO', 'Banco', NULL, NULL, 'I', NULL, 0),
		(6, 'TIPO_CUENTA', 'Tipo de cuenta', NULL, NULL, 'I', NULL, 0),
		(7, 'CUENTA_DESTINO', 'Cuenta', NULL, NULL, 'I', NULL, 0),
		(8, 'MONTO', 'Monto', NULL, NULL, 'D', NULL, 0),
		(9, 'REFERENCIA', 'Referencia', NULL, NULL, 'I', NULL, 0),
		(10, 'CORREO', 'Correo', NULL, NULL, 'I', NULL, 0);
	SET @bfa = NULL;
	EXEC dbo.paBcoFormatoArchivoGuardar @BfaId = @bfa OUTPUT, @Nombre = 'Genérico CSV', @Uso = 'A', @Tipo = 'D', @Separador = ',',
		@Titulos = 1, @Comillas = 1, @Extension = 'csv', @Codificacion = 'UTF-8', @FormatoFecha = 'dd/MM/yyyy',
		@CodigoMonetaria = 'Monetaria', @CodigoAhorro = 'Ahorro', @Columnas = @columnas, @Bancos = @bancos;
END
DELETE FROM @columnas;
IF NOT EXISTS (SELECT 1 FROM dbo.bco_formato_archivo WHERE bfa_nombre = 'Ancho fijo (ejemplo)')
BEGIN
	INSERT INTO @columnas (orden, campo, titulo, longitud, relleno, alineacion, valor, mayusculas) VALUES
		(1, 'FIJO', NULL, 1, NULL, 'I', 'D', 0),
		(2, 'CORRELATIVO', NULL, 5, '0', 'D', NULL, 0),
		(3, 'BANCO_DESTINO', NULL, 3, '0', 'D', NULL, 0),
		(4, 'TIPO_CUENTA', NULL, 1, NULL, 'I', NULL, 0),
		(5, 'CUENTA_DESTINO', NULL, 20, '0', 'D', NULL, 0),
		(6, 'MONTO', NULL, 15, '0', 'D', NULL, 0),
		(7, 'BENEFICIARIO', NULL, 40, ' ', 'I', NULL, 1),
		(8, 'IDENTIFICACION', NULL, 15, ' ', 'I', NULL, 0),
		(9, 'REFERENCIA', NULL, 30, ' ', 'I', NULL, 1);
	INSERT INTO @bancos (gef_id, codigo)
	SELECT gef_id, CASE gef_codigo WHEN 'BI' THEN '001' WHEN 'BAM' THEN '002' WHEN 'GYT' THEN '003' WHEN 'BANRURAL' THEN '004' END
	FROM dbo.gen_entidad_financiera WHERE gef_codigo IN ('BI', 'BAM', 'GYT', 'BANRURAL');
	SET @bfa = NULL;
	EXEC dbo.paBcoFormatoArchivoGuardar @BfaId = @bfa OUTPUT, @Nombre = 'Ancho fijo (ejemplo)', @Uso = 'A', @Tipo = 'F',
		@Encabezado = 'H{CUENTA_ORIGEN,20}{FECHA}{CANTIDAD,5}{TOTAL,15}', @Pie = 'T{CANTIDAD,5}{TOTAL,15}',
		@Extension = 'txt', @Codificacion = 'ANSI', @FormatoFecha = 'yyyyMMdd', @MontoSinPunto = 1,
		@CodigoMonetaria = '1', @CodigoAhorro = '2', @Columnas = @columnas, @Bancos = @bancos;
END
GO

------------------------------------------------------------
-- 11. Permisos
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT v.modulo, v.codigo, v.descripcion
FROM (VALUES
	('CXP', 'CXP_CONTRASENA', 'Contraseñas de pago a proveedores: emitir, imprimir y anular'),
	('CXP', 'CXP_PAGO_PROGRAMADO', 'Pagos programados: pagar contraseñas con cheque o por transferencia y anular lotes'),
	('BANCOS', 'BANCOS_FORMATO_ARCHIVO', 'Formatos del archivo de transferencias de cada banco')) v (modulo, codigo, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso perm WHERE perm.per_codigo = v.codigo);

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT rol.rol_id, perm.per_id
FROM (VALUES
	('ADMIN', 'CXP_CONTRASENA'), ('ADMIN', 'CXP_PAGO_PROGRAMADO'), ('ADMIN', 'BANCOS_FORMATO_ARCHIVO'),
	('CONTADOR', 'CXP_CONTRASENA'), ('CONTADOR', 'CXP_PAGO_PROGRAMADO'), ('CONTADOR', 'BANCOS_FORMATO_ARCHIVO'),
	('CONTADOR_GENERAL', 'CXP_CONTRASENA'), ('CONTADOR_GENERAL', 'CXP_PAGO_PROGRAMADO'), ('CONTADOR_GENERAL', 'BANCOS_FORMATO_ARCHIVO')) v (rol, permiso)
INNER JOIN dbo.sec_rol rol ON rol.rol_codigo = v.rol
INNER JOIN dbo.sec_permiso perm ON perm.per_codigo = v.permiso
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO

------------------------------------------------------------
-- 12. Datos de ejemplo: cuenta de dos proveedores para transferencia
--     (solo si ningún proveedor tiene todavía esa forma de pago)
------------------------------------------------------------
UPDATE prov
   SET prv_forma_pago = 'T', prv_gef_id = enti.gef_id, prv_tipo_cuenta = 'M',
	   prv_numero_cuenta = CONCAT('30', RIGHT(CONCAT('00000000', prov.prv_id * 7919), 8))
FROM dbo.inv_proveedor prov
CROSS APPLY (SELECT TOP 1 gef_id FROM dbo.gen_entidad_financiera WHERE gef_estado = 'A' AND gef_codigo IN ('BI', 'BAM', 'GYT', 'BANRURAL')
			 ORDER BY CASE WHEN gef_id % 2 = prov.prv_id % 2 THEN 0 ELSE 1 END, gef_id) enti
-- Los dos primeros con saldo por pagar, para poder probar el pago por transferencia.
WHERE prov.prv_id IN (SELECT TOP 2 otro.prv_id FROM dbo.inv_proveedor otro WHERE otro.prv_estado = 'A'
					  ORDER BY CASE WHEN EXISTS (SELECT 1 FROM dbo.inv_proveedor_plan_pago cuot
												 INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id AND docu.enc_estado = 'G'
												 WHERE docu.prv_id = otro.prv_id AND cuot.ppg_valor_pago > ISNULL(cuot.ppg_valor_real_pago, 0))
									THEN 0 ELSE 1 END, otro.prv_id)
  AND NOT EXISTS (SELECT 1 FROM dbo.inv_proveedor WHERE prv_forma_pago = 'T');
GO

PRINT '58_contrasenas_pago_transferencias.sql aplicado.';
GO
