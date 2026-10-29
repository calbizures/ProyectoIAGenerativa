/*
================================================================================
 80_inventario_fisico_supervisar.sql
 Inventario físico: conteo a ciegas y permiso de supervisar.

   - Permiso INVENTARIO_FISICO_SUPERVISAR (roles Administrador, Contador y
     Contador general; se puede dar a otros roles en Seguridad › Roles).
     En la aplicación, quien NO lo tiene cuenta a ciegas: ve código,
     producto, unidad y conteo, sin la existencia del sistema, la diferencia,
     el costo ni los valores (ni en la hoja de conteo de Excel). Quien lo
     tiene ve todo.
   - Terminar el conteo (desbloquear la bodega) lo puede hacer cualquiera con
     INVENTARIO_FISICO; aplicar los ajustes (genera documentos y pólizas) y
     anular una toma ya aplicada requieren INVENTARIO_FISICO_SUPERVISAR:
        paInvTomaAplicar   (error 55944)
        paInvTomaAnular    (error 55945, solo si la toma está aplicada)
   - fnSeguridadUsuarioTienePermiso: si un usuario activo tiene un permiso
     activo por alguno de sus roles activos.

 Requiere el 77. Errores nuevos: 55944 y 55945.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Permiso
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT 'INVENTARIO', 'INVENTARIO_FISICO_SUPERVISAR', 'Inventario físico: ver existencia, diferencias y costos, aplicar los ajustes y anular tomas aplicadas'
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_codigo = 'INVENTARIO_FISICO_SUPERVISAR');
GO

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT rol.rol_id, perm.per_id
FROM dbo.sec_rol rol CROSS JOIN dbo.sec_permiso perm
WHERE rol.rol_codigo IN ('ADMIN', 'CONTADOR', 'CONTADOR_GENERAL') AND perm.per_codigo = 'INVENTARIO_FISICO_SUPERVISAR'
  AND NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO

CREATE OR ALTER FUNCTION [dbo].[fnSeguridadUsuarioTienePermiso] (@UsuId INT, @Codigo VARCHAR(64))
RETURNS BIT
AS
BEGIN
	RETURN CASE WHEN EXISTS (
		SELECT 1
		FROM dbo.gen_usuario usua
		INNER JOIN dbo.sec_usuario_rol urol ON urol.usu_id = usua.usu_id
		INNER JOIN dbo.sec_rol srol ON srol.rol_id = urol.rol_id AND srol.rol_estado = 'A'
		INNER JOIN dbo.sec_rol_permiso rper ON rper.rol_id = srol.rol_id
		INNER JOIN dbo.sec_permiso perm ON perm.per_id = rper.per_id AND perm.per_estado = 'A'
		WHERE usua.usu_id = @UsuId AND usua.usu_estado = 'A' AND perm.per_codigo = @Codigo) THEN 1 ELSE 0 END;
END;
GO

------------------------------------------------------------
-- 2. Aplicar y anular piden el permiso de supervisar
------------------------------------------------------------
-- Igual que en 77; aplicar requiere INVENTARIO_FISICO_SUPERVISAR.
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
	IF dbo.fnSeguridadUsuarioTienePermiso(@UsuId, 'INVENTARIO_FISICO_SUPERVISAR') = 0
		THROW 55944, 'Aplicar los ajustes del inventario físico requiere el permiso de supervisar (INVENTARIO_FISICO_SUPERVISAR).', 1;
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

-- Igual que en 66; anular una toma aplicada requiere INVENTARIO_FISICO_SUPERVISAR.
CREATE OR ALTER PROCEDURE [dbo].[paInvTomaAnular]
	@TfiId	INT,
	@Motivo	VARCHAR(250),
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado CHAR(1), @sobrante INT, @faltante INT;
	SELECT @estado = tfi_estado, @sobrante = enc_id_sobrante, @faltante = enc_id_faltante FROM dbo.inv_toma_fisica WHERE tfi_id = @TfiId;
	IF @estado IS NULL OR @estado = 'N'
		THROW 53509, 'La toma no existe o ya está anulada.', 1;
	IF @estado = 'A' AND dbo.fnSeguridadUsuarioTienePermiso(@UsuId, 'INVENTARIO_FISICO_SUPERVISAR') = 0
		THROW 55945, 'Anular una toma ya aplicada (revierte ajustes y pólizas) requiere el permiso de supervisar (INVENTARIO_FISICO_SUPERVISAR).', 1;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 53214, 'Indique el motivo de la anulación (al menos 5 caracteres).', 1;

	BEGIN TRY
		BEGIN TRANSACTION;
		IF @sobrante IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_id = @sobrante AND enc_estado = 'G')
			EXEC dbo.paDocumentoAnular @EncId = @sobrante, @UsuId = @UsuId;
		IF @faltante IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_id = @faltante AND enc_estado = 'G')
			EXEC dbo.paDocumentoAnular @EncId = @faltante, @UsuId = @UsuId;
		UPDATE dbo.inv_toma_fisica
		   SET tfi_estado = 'N', tfi_motivo_anulacion = LEFT(LTRIM(RTRIM(@Motivo)), 250), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE tfi_id = @TfiId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO
