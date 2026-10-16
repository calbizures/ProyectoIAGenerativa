/*
================================================================================
 72_transferencias_boletas_hora.sql
 Lote E: comprobante de las transferencias que recibe la caja, pago con boleta
 (el cliente pagó en el banco) con verificación y hora en los listados.

   1. Hora de grabación en los listados de facturas (paDocumentoConsultar) y
      de documentos electrónicos (paFelDocumentosConsultar).
   2. Transferencia como forma de pago en la factura y en el cobro (sigue
      entrando a la caja como hoy): el número de operación va en el número
      de cheque o referencia y se puede adjuntar el comprobante del banco
      (PDF o imagen, hasta 5 MB) en pos_pago_forma_comprobante.
   3. Pago con boleta: el cliente depositó o transfirió a una cuenta de la
      empresa y manda la boleta. Se registra en Cuentas por cobrar › Cobros
      con la cuenta bancaria, la fecha, el número de boleta u operación, las
      cuotas que paga y la boleta adjunta; queda POR VERIFICAR y no rebaja
      el saldo. Contabilidad la verifica al verla en el estado de cuenta del
      banco: entonces se graba el recibo (sin caja) y la póliza
          Debe  cuenta de depósitos de la cuenta bancaria (o DEPOSITO_BANCOS)
          Haber COBRO_CLIENTES
      con la fecha del depósito, así aparece en la conciliación bancaria.
      También se puede rechazar (no se tocó nada) o, ya verificada, anular
      (devuelve el saldo a las cuotas y anula la póliza) si esa póliza no
      está conciliada. Permiso nuevo: CXC_BOLETA_VERIFICAR.
      pos_pago_enc.pca_id pasa a aceptar nulos: un recibo sin caja lleva la
      cuenta bancaria (bcb_id). El corte de caja no lo incluye; el recibo
      impreso (paCxcReciboDetalleConsultar) muestra esa cuenta.

 Errores nuevos: 55801-55835.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Hora de grabación en los listados
------------------------------------------------------------
-- Igual que en 17, más la fecha y hora en que se grabó (InsFechaHora).
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
		   clie.cli_nombres, clie.cli_apellidos, prov.prv_nombre_comercial, enca.InsFechaHora
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

-- Igual que en 35, más la fecha y hora en que se grabó el documento.
CREATE OR ALTER PROCEDURE [dbo].[paFelDocumentosConsultar]
	@Estado	CHAR(1) = NULL,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT docu.enc_id AS EncId, docu.enc_fecha_docto AS Fecha, docu.InsFechaHora AS FechaHora, tipo.tdo_codigo AS TdoCodigo,
		   ISNULL(docu.enc_numero_unico, CONCAT(docu.enc_serie_docto, '-', docu.enc_numero_docto)) AS Documento,
		   LTRIM(RTRIM(CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos))) AS Cliente, docu.enc_monto_total AS Total,
		   docu.enc_estado AS EstadoDocumento, ISNULL(feld.fdo_estado, 'N') AS FelEstado, feld.fdo_tipo_dte AS TipoDte,
		   feld.fdo_uuid AS Uuid, feld.fdo_serie AS Serie, feld.fdo_numero AS Numero, feld.fdo_fecha_certificacion AS FechaCertificacion,
		   feld.fdo_mensaje AS Mensaje, ISNULL(feld.fdo_intentos, 0) AS Intentos, feld.fdo_fecha_ultimo_intento AS UltimoIntento,
		   feld.fdo_certificador AS Certificador
	FROM dbo.inv_documento_enc docu
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id AND tipo.tdo_fel_certifica = 1
	LEFT JOIN dbo.pos_cliente clie ON clie.cli_id = docu.cli_id
	LEFT JOIN dbo.fel_documento feld ON feld.enc_id = docu.enc_id
	WHERE (@Estado IS NULL OR ISNULL(feld.fdo_estado, 'N') = @Estado)
	  AND (@Desde IS NULL OR docu.enc_fecha_docto >= @Desde)
	  AND (@Hasta IS NULL OR docu.enc_fecha_docto <= @Hasta)
	  -- Un documento anulado en el sistema que nunca se certificó no hay que enviarlo.
	  AND NOT (docu.enc_estado <> 'G' AND feld.enc_id IS NULL)
	ORDER BY docu.enc_fecha_docto DESC, docu.enc_id DESC;
END;
GO

------------------------------------------------------------
-- 2. Comprobante de una transferencia recibida en caja
------------------------------------------------------------
-- Uno por forma de pago (aparte, para no leer el archivo al listar).
IF OBJECT_ID('dbo.pos_pago_forma_comprobante', 'U') IS NULL
CREATE TABLE [dbo].[pos_pago_forma_comprobante](
	[ppf_id]			INT				NOT NULL,
	[pfc_nombre]		VARCHAR(200)	NOT NULL,
	[pfc_tipo]			VARCHAR(100)	NOT NULL,
	[pfc_tamanio]		INT				NOT NULL,
	[pfc_contenido]		VARBINARY(MAX)	NOT NULL,
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_pos_pago_forma_comprobante] PRIMARY KEY ([ppf_id]),
	CONSTRAINT [FK_pos_pago_forma_comprobante_forma] FOREIGN KEY ([ppf_id]) REFERENCES dbo.pos_pago_forma ([ppf_id]),
	CONSTRAINT [FK_pos_pago_forma_comprobante_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [CK_pos_pago_forma_comprobante_archivo] CHECK ([pfc_tamanio] > 0 AND [pfc_tamanio] <= 5242880
		AND [pfc_tipo] IN ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif'))
);
GO

-- Guarda el comprobante de la transferencia con ese número de operación en
-- el pago de un cobro (@PpeId) o en el pago de contado o enganche de una
-- factura (@EncId). La aplicación lo llama en la misma transacción en que
-- graba la factura o el cobro.
CREATE OR ALTER PROCEDURE [dbo].[paPagoFormaComprobanteGuardar]
	@PpeId		INT = NULL,
	@EncId		INT = NULL,
	@Referencia	VARCHAR(16),
	@Nombre		VARCHAR(200),
	@Tipo		VARCHAR(100),
	@Contenido	VARBINARY(MAX),
	@UsuId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT @Referencia = NULLIF(LTRIM(RTRIM(@Referencia)), ''), @Nombre = NULLIF(LTRIM(RTRIM(@Nombre)), ''),
		   @Tipo = LOWER(LTRIM(RTRIM(@Tipo)));

	IF @PpeId IS NULL AND @EncId IS NOT NULL
		SELECT TOP 1 @PpeId = deta.ppe_id
		FROM dbo.pos_pago_det deta
		INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
		WHERE deta.enc_id = @EncId
		ORDER BY deta.ppe_id DESC;

	DECLARE @encontradas INT, @ppf_id INT;
	SELECT @encontradas = COUNT(*), @ppf_id = MIN(form.ppf_id)
	FROM dbo.pos_pago_forma form
	INNER JOIN dbo.pos_pago_forma_tipo tipo ON tipo.pft_id = form.pft_id AND tipo.pft_descripcion = 'Transferencia'
	WHERE form.ppe_id = @PpeId AND form.ppf_numero_cheque = @Referencia;

	IF @Referencia IS NULL OR @encontradas = 0
		THROW 55801, 'No se encontró la transferencia con ese número de operación en el pago.', 1;
	IF @encontradas > 1
		THROW 55802, 'Hay más de una transferencia con el mismo número de operación en el pago.', 1;
	IF @Contenido IS NULL OR DATALENGTH(@Contenido) = 0 OR @Nombre IS NULL
		THROW 55803, 'Adjunte el comprobante de la transferencia.', 1;
	IF @Tipo NOT IN ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif')
		THROW 55804, 'El comprobante debe ser un PDF o una imagen (JPG, PNG, WEBP o GIF).', 1;
	IF DATALENGTH(@Contenido) > 5242880
		THROW 55805, 'El comprobante no puede pesar más de 5 MB.', 1;

	DELETE FROM dbo.pos_pago_forma_comprobante WHERE ppf_id = @ppf_id;
	INSERT INTO dbo.pos_pago_forma_comprobante (ppf_id, pfc_nombre, pfc_tipo, pfc_tamanio, pfc_contenido, InsUsuario, InsFechaHora)
	VALUES (@ppf_id, @Nombre, @Tipo, DATALENGTH(@Contenido), @Contenido, @UsuId, SYSDATETIME());
END;
GO

-- Transferencias de un cobro o de la factura (pago de contado o enganche),
-- con o sin comprobante.
CREATE OR ALTER PROCEDURE [dbo].[paPagoFormaTransferenciasConsultar]
	@PpeId	INT = NULL,
	@EncId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT form.ppf_id AS PpfId, form.ppe_id AS PpeId, form.ppf_numero_cheque AS Referencia, form.ppf_monto AS Monto,
		   enti.gef_descripcion AS Banco, comp.pfc_nombre AS ComprobanteNombre, comp.pfc_tamanio AS ComprobanteTamanio
	FROM dbo.pos_pago_forma form
	INNER JOIN dbo.pos_pago_forma_tipo tipo ON tipo.pft_id = form.pft_id AND tipo.pft_descripcion = 'Transferencia'
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = form.gef_id
	LEFT JOIN dbo.pos_pago_forma_comprobante comp ON comp.ppf_id = form.ppf_id
	WHERE (@PpeId IS NOT NULL AND form.ppe_id = @PpeId)
	   OR (@EncId IS NOT NULL AND form.ppe_id IN (SELECT deta.ppe_id FROM dbo.pos_pago_det deta WHERE deta.enc_id = @EncId))
	ORDER BY form.ppf_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paPagoFormaComprobanteConsultar]
	@PpfId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT comp.ppf_id AS PpfId, form.ppf_numero_cheque AS Referencia, comp.pfc_nombre AS Nombre, comp.pfc_tipo AS Tipo,
		   comp.pfc_contenido AS Contenido
	FROM dbo.pos_pago_forma_comprobante comp
	INNER JOIN dbo.pos_pago_forma form ON form.ppf_id = comp.ppf_id
	WHERE comp.ppf_id = @PpfId;
END;
GO

------------------------------------------------------------
-- 3. Pago con boleta
------------------------------------------------------------
-- Un recibo sin caja (boleta verificada) lleva la cuenta bancaria donde se
-- depositó. El índice de pca_id se vuelve a crear después del cambio.
IF COL_LENGTH('dbo.pos_pago_enc', 'bcb_id') IS NULL
	ALTER TABLE dbo.pos_pago_enc ADD [bcb_id] INT NULL;
GO
IF OBJECT_ID('dbo.FK_pos_pago_enc_bcb_id', 'F') IS NULL
	ALTER TABLE dbo.pos_pago_enc ADD CONSTRAINT [FK_pos_pago_enc_bcb_id] FOREIGN KEY ([bcb_id]) REFERENCES dbo.bco_cuenta_bancaria ([bcb_id]);
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.pos_pago_enc') AND name = 'pca_id' AND is_nullable = 0)
BEGIN
	IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.pos_pago_enc') AND name = 'IX_pos_pago_enc_pca_id')
		DROP INDEX [IX_pos_pago_enc_pca_id] ON dbo.pos_pago_enc;
	ALTER TABLE dbo.pos_pago_enc ALTER COLUMN [pca_id] INT NULL;
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.pos_pago_enc') AND name = 'IX_pos_pago_enc_pca_id')
	CREATE INDEX [IX_pos_pago_enc_pca_id] ON dbo.pos_pago_enc ([pca_id]) INCLUDE ([ppe_estado]);
GO
IF OBJECT_ID('dbo.CK_pos_pago_enc_caja_o_banco', 'C') IS NULL
	ALTER TABLE dbo.pos_pago_enc ADD CONSTRAINT [CK_pos_pago_enc_caja_o_banco] CHECK ([pca_id] IS NOT NULL OR [bcb_id] IS NOT NULL);
GO

-- Estado: P = por verificar, V = verificada (tiene recibo), R = rechazada,
-- N = anulada después de verificada.
IF OBJECT_ID('dbo.cxc_boleta', 'U') IS NULL
CREATE TABLE [dbo].[cxc_boleta](
	[cbo_id]				INT IDENTITY(1,1) NOT NULL,
	[cli_id]				INT				NOT NULL,
	[bcb_id]				INT				NOT NULL,
	[cbo_fecha]				DATE			NOT NULL,		-- fecha del depósito o de la transferencia
	[cbo_referencia]		VARCHAR(16)		NOT NULL,		-- número de boleta u operación
	[cbo_monto]				NUMERIC(12, 2)	NOT NULL,
	[cbo_observaciones]		VARCHAR(250)	NULL,
	[cbo_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_cxc_boleta_estado] DEFAULT ('P'),
	[cbo_motivo]			VARCHAR(250)	NULL,			-- del rechazo o de la anulación
	[ppe_id]				INT				NULL,			-- recibo que generó al verificarse
	[usu_id_verifica]		INT				NULL,
	[cbo_fecha_verifica]	DATETIME2(0)	NULL,
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NULL,
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_cxc_boleta] PRIMARY KEY ([cbo_id]),
	CONSTRAINT [FK_cxc_boleta_cliente] FOREIGN KEY ([cli_id]) REFERENCES dbo.pos_cliente ([cli_id]),
	CONSTRAINT [FK_cxc_boleta_cuenta] FOREIGN KEY ([bcb_id]) REFERENCES dbo.bco_cuenta_bancaria ([bcb_id]),
	CONSTRAINT [FK_cxc_boleta_recibo] FOREIGN KEY ([ppe_id]) REFERENCES dbo.pos_pago_enc ([ppe_id]),
	CONSTRAINT [FK_cxc_boleta_usu_verifica] FOREIGN KEY ([usu_id_verifica]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_cxc_boleta_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_cxc_boleta_UpdUsuario] FOREIGN KEY ([UpdUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [CK_cxc_boleta_valores] CHECK ([cbo_monto] > 0 AND [cbo_estado] IN ('P', 'V', 'R', 'N')
		AND ([cbo_estado] NOT IN ('V', 'N') OR [ppe_id] IS NOT NULL))
);
GO
-- La misma boleta no se registra dos veces en la misma cuenta (salvo rechazada o anulada).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.cxc_boleta') AND name = 'UX_cxc_boleta_referencia')
	CREATE UNIQUE INDEX [UX_cxc_boleta_referencia] ON dbo.cxc_boleta ([bcb_id], [cbo_referencia]) WHERE [cbo_estado] IN ('P', 'V');
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.cxc_boleta') AND name = 'IX_cxc_boleta_estado')
	CREATE INDEX [IX_cxc_boleta_estado] ON dbo.cxc_boleta ([cbo_estado], [cli_id]);
GO

IF OBJECT_ID('dbo.cxc_boleta_det', 'U') IS NULL
CREATE TABLE [dbo].[cxc_boleta_det](
	[cbo_id]		INT				NOT NULL,
	[cpp_id]		INT				NOT NULL,
	[cbd_monto]		NUMERIC(12, 2)	NOT NULL,
	CONSTRAINT [PK_cxc_boleta_det] PRIMARY KEY ([cbo_id], [cpp_id]),
	CONSTRAINT [FK_cxc_boleta_det_boleta] FOREIGN KEY ([cbo_id]) REFERENCES dbo.cxc_boleta ([cbo_id]),
	CONSTRAINT [FK_cxc_boleta_det_cuota] FOREIGN KEY ([cpp_id]) REFERENCES dbo.pos_cliente_plan_pagos ([cpp_id]),
	CONSTRAINT [CK_cxc_boleta_det_monto] CHECK ([cbd_monto] > 0)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.cxc_boleta_det') AND name = 'IX_cxc_boleta_det_cuota')
	CREATE INDEX [IX_cxc_boleta_det_cuota] ON dbo.cxc_boleta_det ([cpp_id]);
GO

IF OBJECT_ID('dbo.cxc_boleta_comprobante', 'U') IS NULL
CREATE TABLE [dbo].[cxc_boleta_comprobante](
	[cbo_id]			INT				NOT NULL,
	[cbc_nombre]		VARCHAR(200)	NOT NULL,
	[cbc_tipo]			VARCHAR(100)	NOT NULL,
	[cbc_tamanio]		INT				NOT NULL,
	[cbc_contenido]		VARBINARY(MAX)	NOT NULL,
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_cxc_boleta_comprobante] PRIMARY KEY ([cbo_id]),
	CONSTRAINT [FK_cxc_boleta_comprobante_boleta] FOREIGN KEY ([cbo_id]) REFERENCES dbo.cxc_boleta ([cbo_id]),
	CONSTRAINT [FK_cxc_boleta_comprobante_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [CK_cxc_boleta_comprobante_archivo] CHECK ([cbc_tamanio] > 0 AND [cbc_tamanio] <= 5242880
		AND [cbc_tipo] IN ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif'))
);
GO

INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT 'CXC', 'CXC_BOLETA_VERIFICAR', 'Cobros: verificar, rechazar o anular pagos con boleta (contra el estado de cuenta del banco)'
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_codigo = 'CXC_BOLETA_VERIFICAR');
INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT rol.rol_id, perm.per_id
FROM dbo.sec_rol rol CROSS JOIN dbo.sec_permiso perm
WHERE rol.rol_codigo IN ('ADMIN', 'CONTADOR', 'CONTADOR_GENERAL') AND perm.per_codigo = 'CXC_BOLETA_VERIFICAR'
  AND NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO

-- Registrar: queda por verificar y no toca saldos ni contabilidad. Lo que
-- una cuota tiene en otras boletas por verificar cuenta contra su saldo.
CREATE OR ALTER PROCEDURE [dbo].[paCxcBoletaRegistrar]
	@CliId				INT,
	@BcbId				INT,
	@Fecha				DATE,
	@Referencia			VARCHAR(16),
	@Observaciones		VARCHAR(250) = NULL,
	@Cuotas				dbo.cobro_cuota_type READONLY,
	@ComprobanteNombre	VARCHAR(200),
	@ComprobanteTipo	VARCHAR(100),
	@Comprobante		VARBINARY(MAX),
	@UsuId				INT = NULL,
	@CboId				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SELECT @CboId = NULL, @Referencia = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@Referencia)), ' ', '')), ''),
		   @Observaciones = NULLIF(LTRIM(RTRIM(@Observaciones)), ''),
		   @ComprobanteNombre = NULLIF(LTRIM(RTRIM(@ComprobanteNombre)), ''), @ComprobanteTipo = LOWER(LTRIM(RTRIM(@ComprobanteTipo)));

	DECLARE @total NUMERIC(12, 2) = (SELECT SUM(monto) FROM @Cuotas);
	DECLARE @msg NVARCHAR(400);

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_id = @CliId)
		THROW 55810, 'El cliente indicado no existe.', 1;
	IF @total IS NULL
		THROW 55811, 'Seleccione al menos una cuota que paga la boleta.', 1;
	IF EXISTS (SELECT 1 FROM @Cuotas WHERE monto <= 0)
		THROW 55812, 'El monto aplicado a cada cuota debe ser mayor a cero.', 1;
	IF EXISTS (SELECT cpp_id FROM @Cuotas GROUP BY cpp_id HAVING COUNT(*) > 1)
		THROW 55813, 'Una cuota aparece más de una vez en la boleta.', 1;
	IF EXISTS (SELECT 1 FROM @Cuotas apli
			   LEFT JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = apli.cpp_id
			   LEFT JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
			   WHERE cuot.cpp_id IS NULL OR cuot.cli_id <> @CliId OR docu.enc_estado <> 'G')
		THROW 55814, 'Una de las cuotas no existe, no es del cliente o es de una factura anulada.', 1;

	SELECT TOP 1 @msg = CONCAT(N'La cuota ', cuot.cpp_nro_cuota, N' de ', ISNULL(docu.enc_numero_unico, docu.enc_numero_docto),
		N' tiene saldo de Q', FORMAT(cuot.cpp_saldo_cuota, 'N2'),
		CASE WHEN pend.Monto > 0 THEN CONCAT(N' y Q', FORMAT(pend.Monto, 'N2'), N' en otras boletas por verificar') ELSE N'' END,
		N'; no alcanza para aplicarle Q', FORMAT(apli.monto, 'N2'), N'.')
	FROM @Cuotas apli
	INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = apli.cpp_id
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
	OUTER APPLY (SELECT SUM(bdet.cbd_monto) AS Monto FROM dbo.cxc_boleta_det bdet
				 INNER JOIN dbo.cxc_boleta bole ON bole.cbo_id = bdet.cbo_id AND bole.cbo_estado = 'P'
				 WHERE bdet.cpp_id = apli.cpp_id) pend
	WHERE apli.monto > cuot.cpp_saldo_cuota - ISNULL(pend.Monto, 0);
	IF @msg IS NOT NULL
		THROW 55815, @msg, 1;

	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId AND bcb_estado = 'A')
		THROW 55816, 'Elija la cuenta bancaria activa de la empresa donde depositó el cliente.', 1;
	IF @Fecha IS NULL OR @Fecha > CAST(GETDATE() AS DATE)
		THROW 55817, 'Indique la fecha del depósito o de la transferencia (no puede ser futura).', 1;
	IF @Referencia IS NULL OR LEN(@Referencia) < 4
		THROW 55818, 'Escriba el número de la boleta o de la operación (al menos 4 caracteres).', 1;
	IF EXISTS (SELECT 1 FROM dbo.cxc_boleta WHERE bcb_id = @BcbId AND cbo_referencia = @Referencia AND cbo_estado IN ('P', 'V'))
		THROW 55819, 'Esa boleta ya está registrada en la misma cuenta bancaria.', 1;
	IF @Comprobante IS NULL OR DATALENGTH(@Comprobante) = 0 OR @ComprobanteNombre IS NULL
		THROW 55820, 'Adjunte la boleta o el comprobante que mandó el cliente.', 1;
	IF @ComprobanteTipo NOT IN ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif')
		THROW 55821, 'La boleta debe ser un PDF o una imagen (JPG, PNG, WEBP o GIF).', 1;
	IF DATALENGTH(@Comprobante) > 5242880
		THROW 55822, 'La boleta no puede pesar más de 5 MB.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;
		INSERT INTO dbo.cxc_boleta (cli_id, bcb_id, cbo_fecha, cbo_referencia, cbo_monto, cbo_observaciones, InsUsuario, InsFechaHora)
		VALUES (@CliId, @BcbId, @Fecha, @Referencia, @total, @Observaciones, @UsuId, SYSDATETIME());
		SET @CboId = SCOPE_IDENTITY();

		INSERT INTO dbo.cxc_boleta_det (cbo_id, cpp_id, cbd_monto)
		SELECT @CboId, cpp_id, monto FROM @Cuotas;

		INSERT INTO dbo.cxc_boleta_comprobante (cbo_id, cbc_nombre, cbc_tipo, cbc_tamanio, cbc_contenido, InsUsuario, InsFechaHora)
		VALUES (@CboId, @ComprobanteNombre, @ComprobanteTipo, DATALENGTH(@Comprobante), @Comprobante, @UsuId, SYSDATETIME());
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Verificar: el dinero está en el banco. Graba el recibo (sin caja, con la
-- cuenta bancaria), rebaja las cuotas y graba la póliza Bancos / Clientes
-- con la fecha del depósito.
CREATE OR ALTER PROCEDURE [dbo].[paCxcBoletaVerificar]
	@CboId	INT,
	@UsuId	INT = NULL,
	@PpeId	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @PpeId = NULL;

	DECLARE @estado CHAR(1), @cli_id INT, @bcb_id INT, @fecha DATE, @referencia VARCHAR(16), @total NUMERIC(12, 2), @gef_id INT, @msg NVARCHAR(400);
	SELECT @estado = bole.cbo_estado, @cli_id = bole.cli_id, @bcb_id = bole.bcb_id, @fecha = bole.cbo_fecha,
		   @referencia = bole.cbo_referencia, @total = bole.cbo_monto, @gef_id = cuen.gef_id
	FROM dbo.cxc_boleta bole
	INNER JOIN dbo.bco_cuenta_bancaria cuen ON cuen.bcb_id = bole.bcb_id
	WHERE bole.cbo_id = @CboId;

	IF @estado IS NULL
		THROW 55823, 'La boleta indicada no existe.', 1;
	IF @estado <> 'P'
		THROW 55824, 'Solo se verifica una boleta que está por verificar.', 1;
	IF EXISTS (SELECT 1 FROM dbo.cxc_boleta_det bdet
			   INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = bdet.cpp_id
			   INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
			   WHERE bdet.cbo_id = @CboId AND docu.enc_estado <> 'G')
		THROW 55825, 'Una de las cuotas de la boleta es de una factura anulada: rechace la boleta y regístrela de nuevo.', 1;

	SELECT TOP 1 @msg = CONCAT(N'La cuota ', cuot.cpp_nro_cuota, N' de ', ISNULL(docu.enc_numero_unico, docu.enc_numero_docto),
		N' ya solo tiene saldo de Q', FORMAT(cuot.cpp_saldo_cuota, 'N2'), N' y la boleta le aplica Q', FORMAT(bdet.cbd_monto, 'N2'),
		N'. Rechace la boleta y regístrela de nuevo con los montos correctos.')
	FROM dbo.cxc_boleta_det bdet
	INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = bdet.cpp_id
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
	WHERE bdet.cbo_id = @CboId AND bdet.cbd_monto > cuot.cpp_saldo_cuota;
	IF @msg IS NOT NULL
		THROW 55826, @msg, 1;

	DECLARE @cta_banco INT = dbo.fnBcoCuentaContableCargo(@bcb_id), @cta_clientes INT, @pft_id INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'COBRO_CLIENTES', @CtaId = @cta_clientes OUTPUT;
	IF @cta_banco IS NULL
		THROW 55827, 'La cuenta bancaria no tiene cuenta contable de depósitos ni hay cuenta DEPOSITO_BANCOS configurada.', 1;
	SELECT @pft_id = pft_id FROM dbo.pos_pago_forma_tipo WHERE pft_descripcion = 'Transferencia';

	DECLARE @enc_id INT = (SELECT CASE WHEN COUNT(DISTINCT cuot.enc_id) = 1 THEN MIN(cuot.enc_id) END
						   FROM dbo.cxc_boleta_det bdet INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = bdet.cpp_id
						   WHERE bdet.cbo_id = @CboId);

	BEGIN TRY
		BEGIN TRANSACTION;

		-- Bloquea la boleta: dos personas no la verifican a la vez.
		IF NOT EXISTS (SELECT 1 FROM dbo.cxc_boleta WITH (UPDLOCK, ROWLOCK) WHERE cbo_id = @CboId AND cbo_estado = 'P')
			THROW 55824, 'Solo se verifica una boleta que está por verificar.', 1;

		UPDATE cuot
		   SET cpp_saldo_cuota = cuot.cpp_saldo_cuota - bdet.cbd_monto,
			   cpp_fecha_real_pago = CASE WHEN cuot.cpp_saldo_cuota - bdet.cbd_monto <= 0 THEN @fecha ELSE cuot.cpp_fecha_real_pago END,
			   cpp_estado = CASE WHEN cuot.cpp_saldo_cuota - bdet.cbd_monto <= 0 THEN 'A' ELSE cuot.cpp_estado END,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		FROM dbo.pos_cliente_plan_pagos cuot WITH (UPDLOCK, ROWLOCK)
		INNER JOIN dbo.cxc_boleta_det bdet ON bdet.cpp_id = cuot.cpp_id
		WHERE bdet.cbo_id = @CboId AND cuot.cpp_saldo_cuota >= bdet.cbd_monto;

		IF @@ROWCOUNT <> (SELECT COUNT(*) FROM dbo.cxc_boleta_det WHERE cbo_id = @CboId)
			THROW 55826, 'El saldo de una de las cuotas cambió mientras se verificaba la boleta. Vuelva a consultar.', 1;

		INSERT INTO dbo.pos_pago_enc (ppe_fecha_pago, cli_id, pca_id, bcb_id, usu_id, InsUsuario, InsFechaHora)
		VALUES (@fecha, @cli_id, NULL, @bcb_id, @UsuId, @UsuId, SYSDATETIME());
		SET @PpeId = SCOPE_IDENTITY();

		INSERT INTO dbo.pos_pago_det (ppe_id, cpp_id, ppd_valor_aplicado, InsUsuario, InsFechaHora)
		SELECT @PpeId, cpp_id, cbd_monto, @UsuId, SYSDATETIME() FROM dbo.cxc_boleta_det WHERE cbo_id = @CboId;

		INSERT INTO dbo.pos_pago_forma (gef_id, ppf_numero_cheque, ppf_monto, ppe_id, pft_id, InsUsuario, InsFechaHora)
		VALUES (@gef_id, @referencia, @total, @PpeId, @pft_id, @UsuId, SYSDATETIME());

		UPDATE dbo.cxc_boleta
		   SET cbo_estado = 'V', ppe_id = @PpeId, usu_id_verifica = @UsuId, cbo_fecha_verifica = SYSDATETIME(),
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE cbo_id = @CboId;

		DECLARE @asi_id INT, @partida dbo.cont_asiento_det_type;
		DECLARE @descripcion VARCHAR(64) = CONCAT('Recibo ', @PpeId, ' · boleta ', @referencia);
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_banco, @total, 0, @descripcion), (@cta_clientes, 0, @total, @descripcion);

		EXEC dbo.paContabilidadAsientoInsertar
			@AsiFecha = @fecha, @AsiDescripcion = 'Cobro a cliente con boleta',
			@AsiOrigen = 'PAGO_CLIENTE', @AsiOrigenId = @PpeId, @EncId = @enc_id,
			@UsuId = @UsuId, @Detalle = @partida, @AsiId = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCxcBoletaRechazar]
	@CboId	INT,
	@Motivo	VARCHAR(250),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @Motivo = NULLIF(LTRIM(RTRIM(@Motivo)), '');
	IF NOT EXISTS (SELECT 1 FROM dbo.cxc_boleta WHERE cbo_id = @CboId)
		THROW 55823, 'La boleta indicada no existe.', 1;
	IF LEN(ISNULL(@Motivo, '')) < 5
		THROW 55828, 'Indique el motivo del rechazo (al menos 5 caracteres).', 1;
	UPDATE dbo.cxc_boleta
	   SET cbo_estado = 'R', cbo_motivo = @Motivo, usu_id_verifica = @UsuId, cbo_fecha_verifica = SYSDATETIME(),
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cbo_id = @CboId AND cbo_estado = 'P';
	IF @@ROWCOUNT = 0
		THROW 55829, 'Solo se rechaza una boleta que está por verificar.', 1;
END;
GO

-- Anular una boleta verificada: devuelve el saldo a las cuotas y anula el
-- recibo y la póliza, salvo que la póliza ya esté conciliada con el banco.
CREATE OR ALTER PROCEDURE [dbo].[paCxcBoletaAnular]
	@CboId	INT,
	@Motivo	VARCHAR(250),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @Motivo = NULLIF(LTRIM(RTRIM(@Motivo)), '');

	DECLARE @estado CHAR(1), @ppe_id INT;
	SELECT @estado = cbo_estado, @ppe_id = ppe_id FROM dbo.cxc_boleta WHERE cbo_id = @CboId;
	IF @estado IS NULL
		THROW 55823, 'La boleta indicada no existe.', 1;
	IF @estado <> 'V'
		THROW 55830, 'Solo se anula una boleta verificada; una por verificar se rechaza.', 1;
	IF LEN(ISNULL(@Motivo, '')) < 5
		THROW 55831, 'Indique el motivo de la anulación (al menos 5 caracteres).', 1;
	IF EXISTS (SELECT 1 FROM dbo.cont_asiento_enc asie
			   INNER JOIN dbo.cont_asiento_det deta ON deta.asi_id = asie.asi_id
			   WHERE asie.asi_origen = 'PAGO_CLIENTE' AND asie.asi_origen_id = @ppe_id
				 AND (EXISTS (SELECT 1 FROM dbo.bco_conciliacion_libro libr WHERE libr.asd_id = deta.asd_id)
					  OR EXISTS (SELECT 1 FROM dbo.bco_extracto extr WHERE extr.asd_id = deta.asd_id)))
		THROW 55832, 'La póliza de esta boleta ya está conciliada con el banco; corrija el saldo con una nota de débito.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;
		EXEC dbo.paCxcReciboReversar @PpeId = @ppe_id, @Motivo = @Motivo, @UsuId = @UsuId;
		UPDATE dbo.cxc_boleta
		   SET cbo_estado = 'N', cbo_motivo = @Motivo, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE cbo_id = @CboId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Boletas por estado, cliente o período (por fecha del depósito).
CREATE OR ALTER PROCEDURE [dbo].[paCxcBoletasConsultar]
	@Estado	CHAR(1) = NULL,
	@CliId	INT = NULL,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT bole.cbo_id AS CboId, bole.cli_id AS CliId, clie.cli_codigo AS ClienteCodigo,
		   LTRIM(RTRIM(CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos))) AS Cliente, clie.cli_email AS ClienteCorreo,
		   bole.bcb_id AS BcbId, CONCAT(enti.gef_descripcion, ' ', cuen.bcb_numero_cuenta) AS Cuenta,
		   bole.cbo_fecha AS Fecha, bole.cbo_referencia AS Referencia, bole.cbo_monto AS Monto, bole.cbo_observaciones AS Observaciones,
		   bole.cbo_estado AS Estado, bole.cbo_motivo AS Motivo, bole.ppe_id AS PpeId,
		   regi.usu_usuario AS Registro, bole.InsFechaHora AS FechaRegistro,
		   veri.usu_usuario AS Verifico, bole.cbo_fecha_verifica AS FechaVerificacion,
		   apli.Documentos, CAST(CASE WHEN comp.cbo_id IS NULL THEN 0 ELSE 1 END AS BIT) AS TieneComprobante
	FROM dbo.cxc_boleta bole
	INNER JOIN dbo.pos_cliente clie ON clie.cli_id = bole.cli_id
	INNER JOIN dbo.bco_cuenta_bancaria cuen ON cuen.bcb_id = bole.bcb_id
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuen.gef_id
	LEFT JOIN dbo.gen_usuario regi ON regi.usu_id = bole.InsUsuario
	LEFT JOIN dbo.gen_usuario veri ON veri.usu_id = bole.usu_id_verifica
	LEFT JOIN dbo.cxc_boleta_comprobante comp ON comp.cbo_id = bole.cbo_id
	OUTER APPLY (SELECT STRING_AGG(CAST(CONCAT(ISNULL(docu.enc_numero_unico, docu.enc_numero_docto), ' #', cuot.cpp_nro_cuota) AS VARCHAR(MAX)), ', ') AS Documentos
				 FROM dbo.cxc_boleta_det bdet
				 INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = bdet.cpp_id
				 INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
				 WHERE bdet.cbo_id = bole.cbo_id) apli
	WHERE (@Estado IS NULL OR bole.cbo_estado = @Estado)
	  AND (@CliId IS NULL OR bole.cli_id = @CliId)
	  AND (@Desde IS NULL OR bole.cbo_fecha >= @Desde)
	  AND (@Hasta IS NULL OR bole.cbo_fecha <= @Hasta)
	ORDER BY CASE bole.cbo_estado WHEN 'P' THEN 0 ELSE 1 END, bole.cbo_fecha DESC, bole.cbo_id DESC;
END;
GO

-- Cuotas que paga una boleta, con el saldo que tienen hoy.
CREATE OR ALTER PROCEDURE [dbo].[paCxcBoletaDetalleConsultar]
	@CboId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT bdet.cpp_id AS CppId, ISNULL(docu.enc_numero_unico, docu.enc_numero_docto) AS Documento, cuot.cpp_nro_cuota AS Cuota,
		   cuot.cpp_fecha_maxima_pago AS Vence, bdet.cbd_monto AS Monto, cuot.cpp_saldo_cuota AS SaldoActual
	FROM dbo.cxc_boleta_det bdet
	INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = bdet.cpp_id
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
	WHERE bdet.cbo_id = @CboId
	ORDER BY cuot.cpp_fecha_maxima_pago, cuot.cpp_nro_cuota;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCxcBoletaComprobanteConsultar]
	@CboId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT comp.cbo_id AS CboId, bole.cbo_referencia AS Referencia, comp.cbc_nombre AS Nombre, comp.cbc_tipo AS Tipo, comp.cbc_contenido AS Contenido
	FROM dbo.cxc_boleta_comprobante comp
	INNER JOIN dbo.cxc_boleta bole ON bole.cbo_id = comp.cbo_id
	WHERE comp.cbo_id = @CboId;
END;
GO

-- Recibo: igual que en 34, más el cliente y su correo (para enviarlo); un
-- recibo sin caja (boleta verificada) muestra la cuenta bancaria donde se
-- depositó y la compañía principal.
CREATE OR ALTER PROCEDURE [dbo].[paCxcReciboDetalleConsultar]
	@PpeId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT pago.ppe_id AS PpeId, pago.ppe_fecha_pago AS Fecha, pago.ppe_estado AS Estado, pago.ppe_motivo_anulacion AS MotivoAnulacion,
		   clie.cli_codigo AS ClienteCodigo, CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos) AS Cliente, clie.cli_nit AS ClienteNit,
		   comp.cia_nombre_comercial AS Compania, comp.cia_nit AS CompaniaNit, comp.cia_direccion AS CompaniaDireccion,
		   ISNULL(sucu.suc_descripcion, 'Pago con boleta') AS Sucursal, clie.cli_id AS CliId, clie.cli_email AS ClienteCorreo, comp.cia_id AS CiaId,
		   ISNULL(caja.pcr_descripcion, CONCAT('Depósito en ', enba.gef_descripcion, ' ', cuen.bcb_numero_cuenta)) AS Caja,
		   usua.usu_usuario AS Usuario
	FROM dbo.pos_pago_enc pago
	INNER JOIN dbo.pos_cliente clie ON clie.cli_id = pago.cli_id
	LEFT JOIN dbo.pos_caja_apertura aper ON aper.pca_id = pago.pca_id
	LEFT JOIN dbo.pos_caja_receptora caja ON caja.pcr_id = aper.pcr_id
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_id = caja.suc_id
	LEFT JOIN dbo.bco_cuenta_bancaria cuen ON cuen.bcb_id = pago.bcb_id
	LEFT JOIN dbo.gen_entidad_financiera enba ON enba.gef_id = cuen.gef_id
	LEFT JOIN dbo.gen_compania comp ON comp.cia_id = COALESCE(sucu.cia_id, (SELECT MIN(cia_id) FROM dbo.gen_compania))
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = pago.usu_id
	WHERE pago.ppe_id = @PpeId;

	SELECT ISNULL(docu.enc_numero_unico, docu.enc_numero_docto) AS Documento, cuot.cpp_nro_cuota AS Cuota,
		   cuot.cpp_fecha_maxima_pago AS Vencimiento, deta.ppd_valor_aplicado AS Monto, cuot.cpp_saldo_cuota AS SaldoCuota
	FROM dbo.pos_pago_det deta
	LEFT JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = deta.cpp_id
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = COALESCE(deta.enc_id, cuot.enc_id)
	WHERE deta.ppe_id = @PpeId
	ORDER BY deta.ppd_id;

	SELECT tipo.pft_descripcion AS Forma, forma.ppf_monto AS Monto, enti.gef_descripcion AS Entidad,
		   COALESCE(forma.ppf_numero_cheque, forma.ppf_numero_tarjeta_ult4) AS Referencia
	FROM dbo.pos_pago_forma forma
	INNER JOIN dbo.pos_pago_forma_tipo tipo ON tipo.pft_id = forma.pft_id
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = forma.gef_id
	WHERE forma.ppe_id = @PpeId
	ORDER BY forma.ppf_id;
END;
GO

PRINT '72_transferencias_boletas_hora.sql aplicado.';
GO
