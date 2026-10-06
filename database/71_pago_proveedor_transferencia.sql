/*
================================================================================
 71_pago_proveedor_transferencia.sql
 Fase 4, punto 8: pago a proveedores por transferencia, además del cheque
 (Cuentas por pagar › Pagos a proveedores, forma de pago "Transferencia").

 Registra una transferencia que ya se hizo desde la banca electrónica:
   - la cuenta de la empresa de la que salió el dinero, la fecha, el número
     de autorización que dio el banco (obligatorio) y la referencia;
   - el banco, el tipo y el número de la cuenta del proveedor que recibió el
     dinero (se proponen los de Proveedores › Pago, pero se pueden cambiar);
   - el comprobante del banco adjunto (PDF o imagen, hasta 5 MB);
   - las cuotas que paga, igual que el cheque: el monto se aplica de la cuota
     más antigua a la más reciente o a las que se marquen.
 Se guarda en las mismas tablas de los lotes de transferencias (58) como un
 lote de un solo pago de tipo D (directa), con su propio correlativo TR-;
 así el estado de cuenta del proveedor, el flujo de caja, la conciliación
 bancaria y el control 6 de integridad la toman sin cambios. La póliza es
 la de las transferencias (origen PAGO_TRANSFERENCIA):
     Debe  PAGO_PROVEEDORES    (una línea por factura)
     Haber cuenta contable del banco (o PAGO_BANCOS)
 Anular la transferencia devuelve el saldo a las cuotas y anula la póliza.

 Cambios en objetos de 58:
   - bco_lote_transferencia: tipo D, autorización y concepto; un número de
     autorización no se repite en la misma cuenta mientras esté vigente.
   - paContrasenaPagarTransferencia: el correlativo LT- ya no se mezcla con
     el TR- de las transferencias directas.
   - paLoteTransferenciaConsultar: solo los lotes (tipo P).

 Errores nuevos: 55701-55716.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Tablas
------------------------------------------------------------
IF COL_LENGTH('dbo.bco_lote_transferencia', 'blt_autorizacion') IS NULL
	ALTER TABLE dbo.bco_lote_transferencia ADD [blt_autorizacion] VARCHAR(40) NULL;	-- número de autorización del banco (tipo D)
IF COL_LENGTH('dbo.bco_lote_transferencia', 'blt_concepto') IS NULL
	ALTER TABLE dbo.bco_lote_transferencia ADD [blt_concepto] VARCHAR(250) NULL;
GO

-- Tipo P: lote de contraseñas (archivo para el banco). D: transferencia
-- directa ya hecha, registrada desde Pagos a proveedores.
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_bco_lote_transferencia_valores' AND definition LIKE '%''D''%')
BEGIN
	IF OBJECT_ID('dbo.CK_bco_lote_transferencia_valores', 'C') IS NOT NULL
		ALTER TABLE dbo.bco_lote_transferencia DROP CONSTRAINT [CK_bco_lote_transferencia_valores];
	ALTER TABLE dbo.bco_lote_transferencia ADD CONSTRAINT [CK_bco_lote_transferencia_valores]
		CHECK ([blt_tipo] IN ('P', 'D') AND [blt_estado] IN ('A', 'N') AND [blt_total] > 0 AND [blt_cantidad] > 0
			   AND ([blt_tipo] <> 'D' OR [blt_autorizacion] IS NOT NULL));
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_bco_lote_transferencia_autorizacion')
	CREATE UNIQUE INDEX [UX_bco_lote_transferencia_autorizacion] ON dbo.bco_lote_transferencia ([bcb_id], [blt_autorizacion])
		WHERE [blt_tipo] = 'D' AND [blt_estado] = 'A';
GO

-- Comprobante del banco de cada transferencia directa (aparte, para no leer
-- el archivo al listar).
IF OBJECT_ID('dbo.bco_transferencia_comprobante', 'U') IS NULL
CREATE TABLE [dbo].[bco_transferencia_comprobante](
	[blt_id]			INT				NOT NULL,
	[btc_nombre]		VARCHAR(200)	NOT NULL,
	[btc_tipo]			VARCHAR(100)	NOT NULL,
	[btc_tamanio]		INT				NOT NULL,
	[btc_contenido]		VARBINARY(MAX)	NOT NULL,
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_bco_transferencia_comprobante] PRIMARY KEY ([blt_id]),
	CONSTRAINT [FK_bco_transferencia_comprobante_lote] FOREIGN KEY ([blt_id]) REFERENCES dbo.bco_lote_transferencia ([blt_id]),
	CONSTRAINT [FK_bco_transferencia_comprobante_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [CK_bco_transferencia_comprobante_archivo] CHECK ([btc_tamanio] > 0 AND [btc_tamanio] <= 5242880
		AND [btc_tipo] IN ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif'))
);
GO

------------------------------------------------------------
-- 2. Lotes de contraseñas: correlativo LT- aparte del TR-
------------------------------------------------------------
-- Igual que en 58; solo cambia el cálculo del siguiente número de lote.
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
		DECLARE @siguiente INT = ISNULL((SELECT MAX(CAST(SUBSTRING(blt_numero, 4, 12) AS INT)) FROM dbo.bco_lote_transferencia WITH (UPDLOCK, HOLDLOCK)
										 WHERE blt_tipo = 'P' AND blt_numero LIKE 'LT-%'), 0) + 1;
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
		EXEC dbo.paContabilidadAsientoInsertar
			@AsiFecha = @Fecha, @AsiDescripcion = @asi_descripcion,
			@AsiOrigen = 'PAGO_TRANSFERENCIA', @AsiOrigenId = @BltId,
			@UsuId = @UsuId, @Detalle = @partida, @AsiId = @asi_id OUTPUT;

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
	WHERE lote.blt_tipo = 'P'
	  AND (@Desde IS NULL OR lote.blt_fecha >= @Desde) AND (@Hasta IS NULL OR lote.blt_fecha <= @Hasta)
	ORDER BY lote.blt_id DESC;
END;
GO

------------------------------------------------------------
-- 3. Registrar una transferencia ya hecha
------------------------------------------------------------
-- @Cuotas: las cuotas y lo que se paga de cada una (como el cheque).
CREATE OR ALTER PROCEDURE [dbo].[paCxpTransferenciaRegistrar]
	@PrvId				INT,
	@BcbId				INT,
	@Fecha				DATE,
	@Autorizacion		VARCHAR(40),
	@Referencia			VARCHAR(60) = NULL,
	@Concepto			VARCHAR(250) = NULL,	-- vacío = "Pago factura(s) ..." automático
	@GefId				INT,
	@TipoCuenta			CHAR(1),
	@Cuenta				VARCHAR(30),
	@Cuotas				dbo.cxp_pago_cuota_type READONLY,
	@ComprobanteNombre	VARCHAR(200),
	@ComprobanteTipo	VARCHAR(100),
	@Comprobante		VARBINARY(MAX),
	@UsuId				INT = NULL,
	@BltId				INT OUTPUT,
	@Numero				VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SELECT @BltId = NULL, @Numero = NULL,
		   @Autorizacion = NULLIF(LTRIM(RTRIM(@Autorizacion)), ''), @Referencia = NULLIF(LTRIM(RTRIM(@Referencia)), ''),
		   @Cuenta = NULLIF(REPLACE(LTRIM(RTRIM(@Cuenta)), ' ', ''), ''), @TipoCuenta = UPPER(@TipoCuenta),
		   @ComprobanteNombre = NULLIF(LTRIM(RTRIM(@ComprobanteNombre)), ''), @ComprobanteTipo = LOWER(LTRIM(RTRIM(@ComprobanteTipo)));

	DECLARE @proveedor VARCHAR(150), @nit VARCHAR(20), @correo VARCHAR(100);
	SELECT @proveedor = prv_nombre_comercial, @nit = prv_nit, @correo = COALESCE(prv_email_contacto, prv_email_empresa)
	FROM dbo.inv_proveedor WHERE prv_id = @PrvId;
	IF @proveedor IS NULL
		THROW 55701, 'El proveedor indicado no existe.', 1;
	IF NOT EXISTS (SELECT 1 FROM @Cuotas)
		THROW 55702, 'Seleccione al menos una cuota a pagar.', 1;
	IF EXISTS (SELECT 1 FROM @Cuotas WHERE monto <= 0)
		THROW 55703, 'Cada cuota seleccionada debe llevar un monto mayor a cero.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId AND bcb_estado = 'A')
		THROW 55704, 'Elija la cuenta bancaria activa de la empresa de la que salió la transferencia.', 1;
	IF @Fecha IS NULL OR @Fecha > CAST(GETDATE() AS DATE)
		THROW 55705, 'Indique la fecha en que se hizo la transferencia (no puede ser futura).', 1;
	IF @Autorizacion IS NULL OR LEN(@Autorizacion) < 4
		THROW 55706, 'Escriba el número de autorización que dio el banco (al menos 4 caracteres).', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_entidad_financiera WHERE gef_id = @GefId) OR @TipoCuenta IS NULL OR @TipoCuenta NOT IN ('M', 'A') OR @Cuenta IS NULL
		THROW 55708, 'Indique el banco, el tipo (monetaria o ahorro) y el número de la cuenta del proveedor que recibió la transferencia.', 1;
	IF @Comprobante IS NULL OR DATALENGTH(@Comprobante) = 0 OR @ComprobanteNombre IS NULL
		THROW 55709, 'Adjunte el comprobante del banco de la transferencia.', 1;
	IF @ComprobanteTipo NOT IN ('application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'image/gif')
		THROW 55710, 'El comprobante debe ser un PDF o una imagen (JPG, PNG, WEBP o GIF).', 1;
	IF DATALENGTH(@Comprobante) > 5242880
		THROW 55711, 'El comprobante no puede pesar más de 5 MB.', 1;

	DECLARE @cta_proveedores INT, @cta_banco INT = dbo.fnBcoCuentaContable(@BcbId);
	EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_PROVEEDORES', @CtaId = @cta_proveedores OUTPUT;
	IF @cta_banco IS NULL
		EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_banco OUTPUT;

	DECLARE @mensaje NVARCHAR(300);
	DECLARE @lineas TABLE (
		ppg_id		INT PRIMARY KEY,
		enc_id		INT,
		prv_id		INT,
		enc_estado	CHAR(1),
		documento	VARCHAR(40),
		nro_pago	INT,
		fecha_pago	DATE,
		fecha_docto	DATE,
		programado	NUMERIC(12, 2),
		pagado		NUMERIC(12, 2),
		monto		NUMERIC(12, 2)
	);

	BEGIN TRY
		BEGIN TRANSACTION;

		IF EXISTS (SELECT 1 FROM dbo.bco_lote_transferencia WITH (UPDLOCK, HOLDLOCK)
				   WHERE bcb_id = @BcbId AND blt_autorizacion = @Autorizacion AND blt_tipo = 'D' AND blt_estado = 'A')
		BEGIN
			SELECT TOP 1 @mensaje = CONCAT(N'La autorización ', @Autorizacion, N' de esta cuenta ya está registrada en la transferencia ', blt_numero, N'.')
			FROM dbo.bco_lote_transferencia WHERE bcb_id = @BcbId AND blt_autorizacion = @Autorizacion AND blt_tipo = 'D' AND blt_estado = 'A';
			THROW 55707, @mensaje, 1;
		END

		-- Bloquea las cuotas mientras se validan y se pagan.
		INSERT INTO @lineas (ppg_id, enc_id, prv_id, enc_estado, documento, nro_pago, fecha_pago, fecha_docto, programado, pagado, monto)
		SELECT pago.ppg_id, cuot.enc_id, docu.prv_id, docu.enc_estado,
			   CONCAT(ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto),
			   cuot.ppg_nro_pago, cuot.ppg_fecha_pago, docu.enc_fecha_docto,
			   cuot.ppg_valor_pago, ISNULL(cuot.ppg_valor_real_pago, 0), pago.monto
		FROM @Cuotas pago
		LEFT JOIN dbo.inv_proveedor_plan_pago cuot WITH (UPDLOCK, HOLDLOCK) ON cuot.ppg_id = pago.ppg_id
		LEFT JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id;

		IF EXISTS (SELECT 1 FROM @lineas WHERE enc_id IS NULL OR prv_id IS NULL OR prv_id <> @PrvId)
			THROW 55712, 'Una de las cuotas no existe o no es de este proveedor.', 1;
		IF EXISTS (SELECT 1 FROM @lineas WHERE enc_estado <> 'G')
		BEGIN
			SELECT TOP 1 @mensaje = CONCAT(N'La compra ', documento, N' está anulada; quítela del pago.') FROM @lineas WHERE enc_estado <> 'G';
			THROW 55713, @mensaje, 1;
		END
		IF EXISTS (SELECT 1 FROM @lineas WHERE monto > programado - pagado)
		BEGIN
			SELECT TOP 1 @mensaje = CONCAT(N'El pago a la cuota ', nro_pago, N' de ', documento, N' (Q', FORMAT(monto, 'N2'),
					N') supera su saldo (Q', FORMAT(programado - pagado, 'N2'), N').')
			FROM @lineas WHERE monto > programado - pagado ORDER BY fecha_pago, nro_pago;
			THROW 55714, @mensaje, 1;
		END
		IF EXISTS (SELECT 1 FROM @lineas WHERE fecha_docto > @Fecha)
		BEGIN
			SELECT TOP 1 @mensaje = CONCAT(N'La compra ', documento, N' es del ', FORMAT(fecha_docto, 'dd/MM/yyyy'),
					N'; la transferencia no puede ser anterior.')
			FROM @lineas WHERE fecha_docto > @Fecha ORDER BY fecha_docto DESC;
			THROW 55715, @mensaje, 1;
		END

		DECLARE @total NUMERIC(12, 2) = (SELECT SUM(monto) FROM @lineas);
		DECLARE @facturas INT = (SELECT COUNT(DISTINCT enc_id) FROM @lineas);
		DECLARE @enc_unico INT = CASE WHEN @facturas = 1 THEN (SELECT MIN(enc_id) FROM @lineas) END;

		-- Concepto automático: los documentos pagados, del más antiguo al más reciente.
		SET @Concepto = NULLIF(LTRIM(RTRIM(@Concepto)), '');
		IF @Concepto IS NULL
		BEGIN
			DECLARE @documentos VARCHAR(MAX) = (
				SELECT STRING_AGG(CAST(docs.documento AS VARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY docs.fecha_docto, docs.enc_id)
				FROM (SELECT enc_id, MIN(documento) AS documento, MIN(fecha_docto) AS fecha_docto FROM @lineas GROUP BY enc_id) docs);
			SET @Concepto = CONCAT(CASE WHEN @facturas = 1 THEN 'Pago factura ' ELSE 'Pago facturas ' END, @documentos);
			IF LEN(@Concepto) > 250
				SET @Concepto = LEFT(@Concepto, 247) + '...';
		END

		DECLARE @siguiente INT = ISNULL((SELECT MAX(CAST(SUBSTRING(blt_numero, 4, 12) AS INT)) FROM dbo.bco_lote_transferencia WITH (UPDLOCK, HOLDLOCK)
										 WHERE blt_tipo = 'D' AND blt_numero LIKE 'TR-%'), 0) + 1;
		SET @Numero = CONCAT('TR-', RIGHT(CONCAT('000000', @siguiente), 6));

		INSERT INTO dbo.bco_lote_transferencia
			(blt_numero, blt_tipo, bcb_id, blt_fecha, blt_referencia, blt_autorizacion, blt_concepto, blt_total, blt_cantidad, blt_estado,
			 usu_id, InsUsuario, InsFechaHora)
		VALUES (@Numero, 'D', @BcbId, @Fecha, @Referencia, @Autorizacion, @Concepto, @total, 1, 'A', @UsuId, @UsuId, SYSDATETIME());
		SET @BltId = SCOPE_IDENTITY();

		INSERT INTO dbo.bco_lote_transferencia_det
			(blt_id, bld_correlativo, cpa_id, prv_id, bld_beneficiario, bld_identificacion, gef_id, bld_tipo_cuenta, bld_cuenta, bld_monto, bld_referencia, bld_correo)
		VALUES (@BltId, 1, NULL, @PrvId, @proveedor, NULLIF(REPLACE(@nit, '-', ''), ''), @GefId, @TipoCuenta, @Cuenta, @total,
				LEFT(CONCAT('Aut. ', @Autorizacion, ISNULL(' - ' + @Referencia, '')), 100), @correo);

		INSERT INTO dbo.bco_lote_transferencia_cuota (bld_id, ppg_id, enc_id, blc_monto)
		SELECT line.bld_id, cuot.ppg_id, cuot.enc_id, cuot.monto
		FROM @lineas cuot
		CROSS JOIN (SELECT bld_id FROM dbo.bco_lote_transferencia_det WHERE blt_id = @BltId) line;

		INSERT INTO dbo.bco_transferencia_comprobante (blt_id, btc_nombre, btc_tipo, btc_tamanio, btc_contenido, InsUsuario, InsFechaHora)
		VALUES (@BltId, LEFT(@ComprobanteNombre, 200), @ComprobanteTipo, DATALENGTH(@Comprobante), @Comprobante, @UsuId, SYSDATETIME());

		UPDATE cuot
		   SET ppg_valor_real_pago = line.pagado + line.monto,
			   ppg_fecha_real_pago = @Fecha,
			   ppg_numero_cheque = @Numero,
			   ppg_estado = CASE WHEN line.pagado + line.monto >= line.programado THEN 'A' ELSE cuot.ppg_estado END,
			   UpdUsuario = @UsuId,
			   UpdFechaHora = SYSDATETIME()
		FROM dbo.inv_proveedor_plan_pago cuot
		INNER JOIN @lineas line ON line.ppg_id = cuot.ppg_id;

		-- Póliza: una línea al Debe por factura y el total al Haber del banco.
		DECLARE @asi_id INT, @partida dbo.cont_asiento_det_type;
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT @cta_proveedores, SUM(monto), 0, LEFT(CONCAT('Pago doc. ', MIN(documento), ' - transferencia ', @Numero), 256)
		FROM @lineas
		GROUP BY enc_id;
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_banco, 0, @total, LEFT(CONCAT('Transferencia ', @Numero, ' aut. ', @Autorizacion, ' - ', @proveedor), 256));

		DECLARE @asi_descripcion VARCHAR(256) = LEFT(CONCAT('Pago a proveedor por transferencia ', @Numero, ' (aut. ', @Autorizacion, ')',
			CASE WHEN @facturas > 1 THEN CONCAT(' - ', @facturas, ' facturas') END), 256);
		EXEC dbo.paContabilidadAsientoInsertar
			@AsiFecha = @Fecha, @AsiDescripcion = @asi_descripcion,
			@AsiOrigen = 'PAGO_TRANSFERENCIA', @AsiOrigenId = @BltId, @EncId = @enc_unico,
			@UsuId = @UsuId, @Detalle = @partida, @AsiId = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 4. Consultas
------------------------------------------------------------
-- Transferencias directas: de un proveedor (todas) o de un período.
CREATE OR ALTER PROCEDURE [dbo].[paCxpTransferenciaConsultar]
	@PrvId	INT = NULL,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT lote.blt_id AS BltId, lote.blt_numero AS Numero, lote.blt_fecha AS Fecha, lote.blt_autorizacion AS Autorizacion,
		   lote.blt_referencia AS Referencia, lote.blt_concepto AS Concepto, lote.blt_total AS Total, lote.blt_estado AS Estado,
		   lote.blt_motivo_anulacion AS MotivoAnulacion,
		   lote.bcb_id AS BcbId, CONCAT(enti.gef_descripcion, ' ', cuba.bcb_numero_cuenta) AS CuentaOrigen,
		   line.prv_id AS PrvId, prov.prv_nombre_comercial AS Proveedor,
		   line.gef_id AS GefIdDestino, dest.gef_descripcion AS BancoDestino, line.bld_tipo_cuenta AS TipoCuentaDestino, line.bld_cuenta AS CuentaDestino,
		   docs.Documentos, docs.Cuotas,
		   comp.btc_nombre AS ComprobanteNombre, comp.btc_tipo AS ComprobanteTipo, comp.btc_tamanio AS ComprobanteTamanio,
		   usua.usu_codigo AS Usuario, lote.InsFechaHora AS Registrado
	FROM dbo.bco_lote_transferencia lote
	INNER JOIN dbo.bco_lote_transferencia_det line ON line.blt_id = lote.blt_id
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = line.prv_id
	INNER JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = lote.bcb_id
	INNER JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuba.gef_id
	LEFT JOIN dbo.gen_entidad_financiera dest ON dest.gef_id = line.gef_id
	LEFT JOIN dbo.bco_transferencia_comprobante comp ON comp.blt_id = lote.blt_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = lote.usu_id
	OUTER APPLY (SELECT STRING_AGG(CAST(lista.documento AS VARCHAR(MAX)), ', ') WITHIN GROUP (ORDER BY lista.fecha, lista.enc_id) AS Documentos,
						SUM(lista.cuotas) AS Cuotas
				 FROM (SELECT docu.enc_id, MIN(docu.enc_fecha_docto) AS fecha, COUNT(*) AS cuotas,
							  MIN(CONCAT(ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto)) AS documento
					   FROM dbo.bco_lote_transferencia_cuota blcu
					   INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = blcu.enc_id
					   WHERE blcu.bld_id = line.bld_id
					   GROUP BY docu.enc_id) lista) docs
	WHERE lote.blt_tipo = 'D'
	  AND (@PrvId IS NULL OR line.prv_id = @PrvId)
	  AND (@Desde IS NULL OR lote.blt_fecha >= @Desde) AND (@Hasta IS NULL OR lote.blt_fecha <= @Hasta)
	ORDER BY lote.blt_fecha DESC, lote.blt_id DESC;
END;
GO

-- Las cuotas que pagó una transferencia directa (mismas columnas que el
-- detalle del cheque).
CREATE OR ALTER PROCEDURE [dbo].[paCxpTransferenciaDetalleConsultar]
	@BltId	INT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_lote_transferencia WHERE blt_id = @BltId AND blt_tipo = 'D')
		THROW 55716, 'La transferencia indicada no existe.', 1;

	SELECT ROW_NUMBER() OVER (ORDER BY cuot.ppg_fecha_pago, docu.enc_fecha_docto, docu.enc_id, cuot.ppg_nro_pago) AS CedId,
		   docu.enc_id AS EncId,
		   CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto) AS Documento,
		   docu.enc_fecha_docto AS FechaDocumento, cuot.ppg_nro_pago AS Cuota, cuot.ppg_fecha_pago AS Vencimiento,
		   cuot.ppg_valor_pago AS ValorCuota, blcu.blc_monto AS Monto,
		   -- Cancelación si con este pago la cuota quedó pagada (lo pagado después no cuenta).
		   CASE WHEN cuot.ppg_valor_pago - ISNULL(cuot.ppg_valor_real_pago, 0)
					 + ISNULL((SELECT SUM(desp.blc_monto) FROM dbo.bco_lote_transferencia_cuota desp
							   INNER JOIN dbo.bco_lote_transferencia_det dlin ON dlin.bld_id = desp.bld_id
							   INNER JOIN dbo.bco_lote_transferencia dlot ON dlot.blt_id = dlin.blt_id AND dlot.blt_estado = 'A'
							   WHERE desp.ppg_id = blcu.ppg_id AND dlot.blt_id > line.blt_id), 0) <= 0.005
				THEN 'Cancelación' ELSE 'Abono' END AS Aplicacion
	FROM dbo.bco_lote_transferencia_cuota blcu
	INNER JOIN dbo.bco_lote_transferencia_det line ON line.bld_id = blcu.bld_id
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = blcu.enc_id
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	LEFT JOIN dbo.inv_proveedor_plan_pago cuot ON cuot.ppg_id = blcu.ppg_id
	WHERE line.blt_id = @BltId
	ORDER BY CedId;
END;
GO

-- El comprobante del banco, para descargarlo o verlo.
CREATE OR ALTER PROCEDURE [dbo].[paCxpTransferenciaComprobanteConsultar]
	@BltId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT comp.blt_id AS BltId, lote.blt_numero AS Numero, comp.btc_nombre AS Nombre, comp.btc_tipo AS Tipo, comp.btc_contenido AS Contenido
	FROM dbo.bco_transferencia_comprobante comp
	INNER JOIN dbo.bco_lote_transferencia lote ON lote.blt_id = comp.blt_id
	WHERE comp.blt_id = @BltId;
END;
GO

------------------------------------------------------------
-- 5. Anular
------------------------------------------------------------
-- Devuelve el saldo a las cuotas y anula la póliza (como un lote). El
-- comprobante se conserva; la autorización se puede volver a registrar.
CREATE OR ALTER PROCEDURE [dbo].[paCxpTransferenciaAnular]
	@BltId	INT,
	@Motivo	VARCHAR(250),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_lote_transferencia WHERE blt_id = @BltId AND blt_tipo = 'D')
		THROW 55716, 'La transferencia indicada no existe.', 1;
	EXEC dbo.paLoteTransferenciaAnular @BltId = @BltId, @Motivo = @Motivo, @UsuId = @UsuId;
END;
GO

PRINT '71_pago_proveedor_transferencia.sql aplicado.';
GO
