/*
================================================================================
 77_inventario_fisico_bloqueo.sql
 Inventario físico con foto de existencias y bodega bloqueada mientras se
 cuenta.

 Antes, al aplicar la toma la diferencia se calculaba contra la existencia
 del momento de APLICAR: lo vendido o trasladado entre el conteo y la
 aplicación descuadraba los ajustes. Ahora:

   1. Abrir la toma (paInvTomaCrear) toma la foto de las existencias de la
      bodega (tfd_existencia) y la bodega queda BLOQUEADA: ningún movimiento
      de inventario entra ni sale de ella (ventas, compras, recepciones de
      órdenes de compra, traslados de salida y de entrada, devoluciones de
      notas, inventario inicial, anulaciones). Lo impide el trigger
      trgInvExistenciaBodegaBloqueo sobre inv_producto_existencia_bodega,
      así ningún camino (presente o futuro) se lo salta.
   2. El conteo se registra mientras la bodega está bloqueada.
   3. Terminar el conteo (paInvTomaConteoTerminar) desbloquea la bodega,
      que vuelve a operar. También sirve para levantar el bloqueo en una
      emergencia: queda quién y cuándo.
   4. Aplicar la toma (después, cuando ya se revisaron las diferencias):
      la diferencia es conteo − foto, y se aplica sobre la existencia actual.
      Lo que se movió después del conteo no afecta los ajustes. El costo es
      el promedio del momento de aplicar.
   Anular una toma en conteo también desbloquea la bodega.

   Las tomas que ya estaban abiertas al correr este script quedan con el
   conteo terminado y sin foto (tfi_usa_foto = 0): se aplican como antes,
   contra la existencia del momento de aplicar, y no bloquean la bodega.

 Errores nuevos: 55940 a 55943.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Columnas
------------------------------------------------------------
IF COL_LENGTH('dbo.inv_toma_fisica', 'tfi_conteo_fin') IS NULL
BEGIN
	ALTER TABLE dbo.inv_toma_fisica ADD
		[tfi_conteo_fin]		DATETIME2(0)	NULL,	-- NULL mientras se cuenta (bodega bloqueada)
		[usu_id_conteo_fin]		INT				NULL CONSTRAINT [FK_inv_toma_fisica_conteo_fin] REFERENCES dbo.gen_usuario ([usu_id]),
		[tfi_usa_foto]			BIT				NOT NULL CONSTRAINT [DF_inv_toma_fisica_usa_foto] DEFAULT (1);	-- 0: tomas anteriores a este script
	-- Para que el lote siguiente sepa que las columnas son nuevas.
	EXEC sp_set_session_context @key = N'toma_77_nueva', @value = 1;
END
GO

-- Solo la primera vez: las tomas que ya estaban abiertas quedan con el conteo
-- terminado y sin foto (se aplican como antes y no bloquean la bodega).
IF SESSION_CONTEXT(N'toma_77_nueva') = 1
	UPDATE dbo.inv_toma_fisica
	   SET tfi_usa_foto = 0, tfi_conteo_fin = ISNULL(UpdFechaHora, InsFechaHora)
	 WHERE tfi_estado = 'B';
GO

-- Las aplicadas o anuladas no se cuentan más.
UPDATE dbo.inv_toma_fisica
   SET tfi_conteo_fin = ISNULL(tfi_fecha_aplicacion, ISNULL(UpdFechaHora, InsFechaHora))
 WHERE tfi_estado IN ('A', 'N') AND tfi_conteo_fin IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_inv_toma_fisica_bloqueo')
	CREATE INDEX [IX_inv_toma_fisica_bloqueo] ON dbo.inv_toma_fisica ([bod_id])
		WHERE [tfi_estado] = 'B' AND [tfi_conteo_fin] IS NULL;
GO

------------------------------------------------------------
-- 2. Bodega bloqueada: ningún movimiento de existencias
------------------------------------------------------------
CREATE OR ALTER TRIGGER [dbo].[trgInvExistenciaBodegaBloqueo]
ON dbo.inv_producto_existencia_bodega
AFTER INSERT, UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

	DECLARE @mensaje NVARCHAR(400) = (
		SELECT TOP (1) CONCAT(N'La bodega ', bode.bod_descripcion, N' está en inventario físico (toma #', toma.tfi_id,
							  N'): no admite movimientos hasta que se termine el conteo.')
		FROM inserted inse
		LEFT JOIN deleted dele ON dele.pro_id = inse.pro_id AND dele.bod_id = inse.bod_id
		INNER JOIN dbo.inv_toma_fisica toma ON toma.bod_id = inse.bod_id AND toma.tfi_estado = 'B' AND toma.tfi_conteo_fin IS NULL
		INNER JOIN dbo.inv_bodega bode ON bode.bod_id = inse.bod_id
		WHERE inse.existencia <> ISNULL(dele.existencia, 0));
	IF @mensaje IS NOT NULL
		THROW 55940, @mensaje, 1;
END;
GO

------------------------------------------------------------
-- 3. Toma: abrir (foto y bloqueo), contar, terminar, aplicar, anular
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paInvTomaCrear]
	@BodId				INT,
	@Fecha				DATE,
	@Observaciones		VARCHAR(250) = NULL,
	@SoloConExistencia	BIT = 0,
	@UsuId				INT,
	@IdResultado		INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE bod_id = @BodId AND bod_estado = 'A')
		THROW 53503, 'La bodega no existe o está inactiva.', 1;
	IF EXISTS (SELECT 1 FROM dbo.inv_toma_fisica WHERE bod_id = @BodId AND tfi_estado = 'B')
		THROW 53504, 'Esta bodega ya tiene una toma de inventario abierta; aplíquela o anúlela antes de abrir otra.', 1;

	BEGIN TRANSACTION;
	-- Primero la toma (desde aquí la bodega queda bloqueada); la foto espera a
	-- que terminen los movimientos que estaban en curso.
	INSERT INTO dbo.inv_toma_fisica (bod_id, tfi_fecha, tfi_observaciones, tfi_usa_foto, InsUsuario)
	VALUES (@BodId, ISNULL(@Fecha, CAST(GETDATE() AS DATE)), NULLIF(LTRIM(RTRIM(@Observaciones)), ''), 1, @UsuId);
	SET @IdResultado = SCOPE_IDENTITY();

	INSERT INTO dbo.inv_toma_fisica_det (tfi_id, pro_id, tfd_existencia)
	SELECT @IdResultado, prod.pro_id, ISNULL(exis.existencia, 0)
	FROM dbo.inv_producto prod
	LEFT JOIN dbo.inv_producto_existencia_bodega exis WITH (UPDLOCK, HOLDLOCK) ON exis.pro_id = prod.pro_id AND exis.bod_id = @BodId
	WHERE prod.pro_estado = 'A' AND prod.pro_maneja_existencia = 1
	  AND (@SoloConExistencia = 0 OR ISNULL(exis.existencia, 0) <> 0);

	IF @@ROWCOUNT = 0
		THROW 53505, 'No hay productos para contar en esta bodega.', 1;
	COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paInvTomaConteoGuardar]
	@TfiId		INT,
	@Conteos	dbo.inv_toma_conteo_type READONLY,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_toma_fisica WHERE tfi_id = @TfiId AND tfi_estado = 'B')
		THROW 53506, 'Solo se registra el conteo de una toma abierta.', 1;
	IF EXISTS (SELECT 1 FROM dbo.inv_toma_fisica WHERE tfi_id = @TfiId AND tfi_usa_foto = 1 AND tfi_conteo_fin IS NOT NULL)
		THROW 55941, 'El conteo ya se terminó y la bodega volvió a operar: el conteo ya no se puede cambiar. Si hay que volver a contar, anule la toma y abra otra.', 1;
	IF EXISTS (SELECT 1 FROM @Conteos WHERE conteo < 0)
		THROW 53507, 'El conteo no puede ser negativo.', 1;

	UPDATE deta SET tfd_conteo = cont.conteo
	FROM dbo.inv_toma_fisica_det deta
	INNER JOIN @Conteos cont ON cont.pro_id = deta.pro_id
	WHERE deta.tfi_id = @TfiId;

	UPDATE dbo.inv_toma_fisica SET UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE tfi_id = @TfiId;
END;
GO

-- Termina el conteo y desbloquea la bodega (también en una emergencia).
CREATE OR ALTER PROCEDURE [dbo].[paInvTomaConteoTerminar]
	@TfiId	INT,
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	UPDATE dbo.inv_toma_fisica
	   SET tfi_conteo_fin = SYSDATETIME(), usu_id_conteo_fin = @UsuId, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE tfi_id = @TfiId AND tfi_estado = 'B' AND tfi_conteo_fin IS NULL;
	IF @@ROWCOUNT = 0
		THROW 55942, 'La toma no está en conteo: no existe, ya se terminó el conteo, se aplicó o se anuló.', 1;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paInvTomaConsultar]
	@SucId	INT = NULL,
	@BodId	INT = NULL,
	@Estado	CHAR(1) = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT toma.tfi_id AS TfiId, toma.bod_id AS BodId, bode.bod_descripcion AS Bodega, sucu.suc_id AS SucId, sucu.suc_descripcion AS Sucursal,
		   toma.tfi_fecha AS Fecha, toma.tfi_observaciones AS Observaciones, toma.tfi_estado AS Estado, toma.tfi_fecha_aplicacion AS FechaAplicacion,
		   toma.tfi_motivo_anulacion AS MotivoAnulacion, resu.Productos, resu.Contados,
		   ISNULL(sobr.enc_monto_total, 0) AS ValorSobrante, ISNULL(falt.enc_monto_total, 0) AS ValorFaltante,
		   usua.usu_usuario AS Usuario,
		   toma.InsFechaHora AS ConteoInicio, toma.tfi_conteo_fin AS ConteoFin, fina.usu_usuario AS ConteoTerminadoPor,
		   toma.tfi_usa_foto AS UsaFoto,
		   CAST(IIF(toma.tfi_estado = 'B' AND toma.tfi_conteo_fin IS NULL, 1, 0) AS BIT) AS BodegaBloqueada
	FROM dbo.inv_toma_fisica toma
	INNER JOIN dbo.inv_bodega bode ON bode.bod_id = toma.bod_id
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
	CROSS APPLY (SELECT COUNT(*) AS Productos, COUNT(deta.tfd_conteo) AS Contados FROM dbo.inv_toma_fisica_det deta WHERE deta.tfi_id = toma.tfi_id) resu
	LEFT JOIN dbo.inv_documento_enc sobr ON sobr.enc_id = toma.enc_id_sobrante
	LEFT JOIN dbo.inv_documento_enc falt ON falt.enc_id = toma.enc_id_faltante
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = toma.InsUsuario
	LEFT JOIN dbo.gen_usuario fina ON fina.usu_id = toma.usu_id_conteo_fin
	WHERE (@SucId IS NULL OR sucu.suc_id = @SucId)
	  AND (@BodId IS NULL OR toma.bod_id = @BodId)
	  AND (@Estado IS NULL OR toma.tfi_estado = @Estado)
	ORDER BY toma.tfi_fecha DESC, toma.tfi_id DESC;
END;
GO

-- Existencia: la foto (tomas nuevas) o, en las anteriores abiertas, la actual.
CREATE OR ALTER PROCEDURE [dbo].[paInvTomaDetalleConsultar]
	@TfiId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT deta.tfd_id AS TfdId, deta.pro_id AS ProId, prod.pro_codigo AS Codigo, prod.pro_descripcion AS Descripcion,
		   unid.ume_codigo AS Unidad, tipo.prt_descripcion AS TipoProducto,
		   CASE WHEN toma.tfi_estado = 'B' AND toma.tfi_usa_foto = 0 THEN ISNULL(exis.existencia, 0) ELSE deta.tfd_existencia END AS Existencia,
		   deta.tfd_conteo AS Conteo,
		   CASE WHEN toma.tfi_estado = 'B' THEN prod.pro_costo_unitario ELSE deta.tfd_costo_unitario END AS CostoUnitario,
		   ISNULL(exis.existencia, 0) AS ExistenciaActual
	FROM dbo.inv_toma_fisica_det deta
	INNER JOIN dbo.inv_toma_fisica toma ON toma.tfi_id = deta.tfi_id
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
	LEFT JOIN dbo.inv_producto_tipo tipo ON tipo.prt_id = prod.prt_id
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = prod.ume_id
	LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = deta.pro_id AND exis.bod_id = toma.bod_id
	WHERE deta.tfi_id = @TfiId
	ORDER BY tipo.prt_descripcion, prod.pro_descripcion;
END;
GO

-- Igual que en 66; con foto, la diferencia es conteo − foto y la existencia
-- no se vuelve a leer. Requiere el conteo terminado.
CREATE OR ALTER PROCEDURE [dbo].[paInvTomaAplicar]
	@TfiId	INT,
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @bod_id INT, @fecha DATE, @bodega VARCHAR(128), @usa_foto BIT, @conteo_fin DATETIME2(0);
	SELECT @bod_id = toma.bod_id, @fecha = toma.tfi_fecha, @bodega = bode.bod_descripcion, @usa_foto = toma.tfi_usa_foto, @conteo_fin = toma.tfi_conteo_fin
	FROM dbo.inv_toma_fisica toma INNER JOIN dbo.inv_bodega bode ON bode.bod_id = toma.bod_id
	WHERE toma.tfi_id = @TfiId AND toma.tfi_estado = 'B';
	IF @bod_id IS NULL
		THROW 53506, 'Solo se aplica una toma abierta.', 1;
	IF @conteo_fin IS NULL
		THROW 55943, 'Termine el conteo antes de aplicar los ajustes (la bodega sigue bloqueada).', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_toma_fisica_det WHERE tfi_id = @TfiId AND tfd_conteo IS NOT NULL)
		THROW 53508, 'La toma no tiene ningún producto contado.', 1;

	DECLARE @cta_inventario INT, @cta_faltante INT, @cta_sobrante INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO', @CtaId = @cta_inventario OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		-- El costo es el promedio de este momento. La existencia: la foto de
		-- cuando se abrió la toma o, en una toma anterior a este script, la
		-- de este momento.
		UPDATE deta
		   SET tfd_existencia = CASE WHEN @usa_foto = 1 THEN deta.tfd_existencia ELSE ISNULL(exis.existencia, 0) END,
			   tfd_costo_unitario = prod.pro_costo_unitario
		FROM dbo.inv_toma_fisica_det deta
		INNER JOIN dbo.inv_producto prod WITH (UPDLOCK) ON prod.pro_id = deta.pro_id
		LEFT JOIN dbo.inv_producto_existencia_bodega exis WITH (UPDLOCK) ON exis.pro_id = deta.pro_id AND exis.bod_id = @bod_id
		WHERE deta.tfi_id = @TfiId;

		DECLARE @sobrantes dbo.inv_documento_interno_type, @faltantes dbo.inv_documento_interno_type;
		INSERT INTO @sobrantes (bod_id, pro_id, cantidad, costo_total)
		SELECT @bod_id, pro_id, tfd_conteo - tfd_existencia, ROUND((tfd_conteo - tfd_existencia) * ISNULL(tfd_costo_unitario, 0), 2)
		FROM dbo.inv_toma_fisica_det WHERE tfi_id = @TfiId AND tfd_conteo > tfd_existencia;
		INSERT INTO @faltantes (bod_id, pro_id, cantidad, costo_total)
		SELECT @bod_id, pro_id, tfd_existencia - tfd_conteo, ROUND((tfd_existencia - tfd_conteo) * ISNULL(tfd_costo_unitario, 0), 2)
		FROM dbo.inv_toma_fisica_det WHERE tfi_id = @TfiId AND tfd_conteo < tfd_existencia;

		DECLARE @enc_sobrante INT, @enc_faltante INT, @valor NUMERIC(14, 2), @asi_id INT, @partida dbo.cont_asiento_det_type, @texto VARCHAR(256);
		DECLARE @motivo VARCHAR(256) = CONCAT('Inventario físico #', @TfiId, ' - ', @bodega);

		IF EXISTS (SELECT 1 FROM @sobrantes)
		BEGIN
			EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO_SOBRANTE', @CtaId = @cta_sobrante OUTPUT;
			EXEC dbo.paInvDocumentoInternoCrear @TdoCodigo = 'AJIS', @Fecha = @fecha, @Motivo = @motivo, @Lineas = @sobrantes,
				@UsuId = @UsuId, @EncId = @enc_sobrante OUTPUT;
			SET @valor = (SELECT enc_monto_total FROM dbo.inv_documento_enc WHERE enc_id = @enc_sobrante);
			IF @valor > 0
			BEGIN
				SET @texto = CONCAT('Sobrante de ', LOWER(@motivo));
				INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
				VALUES (@cta_inventario, @valor, 0, @texto), (@cta_sobrante, 0, @valor, @texto);
				EXEC dbo.paContabilidadAsientoInsertar @AsiFecha = @fecha, @AsiDescripcion = @texto, @AsiOrigen = 'AJUSTE_INVENTARIO',
					@AsiOrigenId = @TfiId, @EncId = @enc_sobrante, @UsuId = @UsuId, @Detalle = @partida, @AsiId = @asi_id OUTPUT;
			END
		END

		IF EXISTS (SELECT 1 FROM @faltantes)
		BEGIN
			EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO_FALTANTE', @CtaId = @cta_faltante OUTPUT;
			EXEC dbo.paInvDocumentoInternoCrear @TdoCodigo = 'AJIF', @Fecha = @fecha, @Motivo = @motivo, @Lineas = @faltantes,
				@UsuId = @UsuId, @EncId = @enc_faltante OUTPUT;
			SET @valor = (SELECT enc_monto_total FROM dbo.inv_documento_enc WHERE enc_id = @enc_faltante);
			IF @valor > 0
			BEGIN
				DELETE FROM @partida;
				SET @texto = CONCAT('Faltante de ', LOWER(@motivo));
				INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
				VALUES (@cta_faltante, @valor, 0, @texto), (@cta_inventario, 0, @valor, @texto);
				EXEC dbo.paContabilidadAsientoInsertar @AsiFecha = @fecha, @AsiDescripcion = @texto, @AsiOrigen = 'AJUSTE_INVENTARIO',
					@AsiOrigenId = @TfiId, @EncId = @enc_faltante, @UsuId = @UsuId, @Detalle = @partida, @AsiId = @asi_id OUTPUT;
			END
		END

		UPDATE dbo.inv_toma_fisica
		   SET tfi_estado = 'A', enc_id_sobrante = @enc_sobrante, enc_id_faltante = @enc_faltante, tfi_fecha_aplicacion = SYSDATETIME(),
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE tfi_id = @TfiId;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO
