/*
================================================================================
 68_caja_chica_vale_sin_proveedor.sql
 Fase 4, punto 7: en la caja chica el vale y el recibo no necesitan proveedor.

   - cch_gasto.ccg_proveedor acepta NULL.
   - paCajaChicaGastoGuardar: el proveedor es obligatorio solo en la factura
     (F) y en la factura de pequeño contribuyente (P), con su NIT y número;
     en el recibo (R) y el vale (V) se puede dejar en blanco.
   - paCajaChicaLiquidar: la línea de la póliza de un gasto sin proveedor
     lleva solo el concepto.

 Errores nuevos: 55134.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.cch_gasto') AND name = 'ccg_proveedor' AND is_nullable = 0)
	ALTER TABLE dbo.cch_gasto ALTER COLUMN [ccg_proveedor] VARCHAR(150) NULL;
GO

-- Graba o corrige un gasto pendiente. IVA: solo factura normal (F), incluido
-- en el total: total × tasa / (100 + tasa). El proveedor es obligatorio en las
-- facturas; en el recibo y el vale es opcional (fase 4).
CREATE OR ALTER PROCEDURE [dbo].[paCajaChicaGastoGuardar]
	@CcgId			INT = NULL OUTPUT,
	@CchId			INT,
	@Fecha			DATE,
	@Tipo			CHAR(1),
	@PrvId			INT = NULL,
	@Nit			VARCHAR(20) = NULL,
	@Proveedor		VARCHAR(150) = NULL,
	@Serie			VARCHAR(20) = NULL,
	@Numero			VARCHAR(30) = NULL,
	@Concepto		VARCHAR(250),
	@CtaId			INT,
	@IdDepartamento	INT = NULL,
	@Total			NUMERIC(12, 2),
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	DECLARE @mensaje NVARCHAR(300);
	SET @Proveedor = NULLIF(LTRIM(RTRIM(@Proveedor)), '');
	SET @Concepto = NULLIF(LTRIM(RTRIM(@Concepto)), '');
	SET @Nit = NULLIF(UPPER(REPLACE(REPLACE(LTRIM(RTRIM(@Nit)), '-', ''), ' ', '')), '');
	SET @Serie = NULLIF(UPPER(LTRIM(RTRIM(@Serie))), '');
	SET @Numero = NULLIF(LTRIM(RTRIM(@Numero)), '');

	IF NOT EXISTS (SELECT 1 FROM dbo.cch_fondo WHERE cch_id = @CchId AND cch_estado = 'A')
		THROW 55115, 'El fondo de caja chica no existe o está inactivo.', 1;
	IF @Tipo NOT IN ('F', 'P', 'R', 'V')
		THROW 55116, 'El tipo de comprobante es F (factura), P (factura de pequeño contribuyente), R (recibo) o V (vale).', 1;
	IF @Fecha IS NULL OR @Fecha > CAST(GETDATE() AS DATE)
		THROW 55117, 'La fecha del gasto no puede ser futura.', 1;
	IF @Concepto IS NULL
		THROW 55118, 'Indique el concepto del gasto.', 1;
	IF @Tipo IN ('F', 'P') AND @Proveedor IS NULL
		THROW 55134, 'Para una factura indique el proveedor.', 1;
	IF @Tipo IN ('R', 'V') AND @Proveedor IS NULL
		SET @PrvId = NULL;
	IF @Tipo IN ('F', 'P') AND (@Nit IS NULL OR @Numero IS NULL)
		THROW 55119, 'Para una factura indique el NIT del proveedor y el número de la factura.', 1;
	IF ISNULL(@Total, 0) <= 0
		THROW 55120, 'El monto del gasto debe ser mayor a cero.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId AND cta_acepta_movimiento = 1 AND cta_estado = 'A')
		THROW 55121, 'Elija una cuenta de gasto de detalle y activa.', 1;
	IF @IdDepartamento IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.rrhhDepartamento WHERE IdDepartamento = @IdDepartamento AND Estado = 'A')
		THROW 55122, 'El centro de costo (departamento) no existe o está inactivo.', 1;
	IF @CcgId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.cch_gasto WHERE ccg_id = @CcgId AND cch_id = @CchId AND ccg_estado = 'P')
		THROW 55123, 'Solo se corrige un gasto pendiente (no liquidado ni anulado).', 1;
	IF @Tipo IN ('F', 'P') AND EXISTS (SELECT 1 FROM dbo.cch_gasto WHERE ccg_nit = @Nit AND ISNULL(ccg_serie, '') = ISNULL(@Serie, '')
									   AND ccg_numero = @Numero AND ccg_estado <> 'A' AND ccg_id <> ISNULL(@CcgId, 0))
		THROW 55124, 'Esa factura (NIT, serie y número) ya está registrada en caja chica.', 1;

	DECLARE @disponible NUMERIC(12, 2) = (SELECT Constituido - Pendiente - PorReponer FROM dbo.fnCajaChicaSaldo(@CchId))
		+ ISNULL((SELECT ccg_total FROM dbo.cch_gasto WHERE ccg_id = @CcgId), 0);
	IF @Total > @disponible
	BEGIN
		SET @mensaje = CONCAT(N'El gasto (Q', FORMAT(@Total, 'N2'), N') pasa del disponible del fondo (Q', FORMAT(@disponible, 'N2'),
			N'). Liquide y reponga el fondo, o auméntelo.');
		THROW 55125, @mensaje, 1;
	END

	DECLARE @tasa NUMERIC(5, 2) = ISNULL((SELECT TOP 1 comp.cia_porc_iva FROM dbo.cch_fondo fond
										   INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = fond.suc_id
										   INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id WHERE fond.cch_id = @CchId), 12);
	DECLARE @iva NUMERIC(12, 2) = IIF(@Tipo = 'F', ROUND(@Total * @tasa / (100 + @tasa), 2), 0);

	IF @CcgId IS NULL
	BEGIN
		INSERT INTO dbo.cch_gasto (cch_id, ccg_fecha, ccg_tipo, prv_id, ccg_nit, ccg_proveedor, ccg_serie, ccg_numero, ccg_concepto, cta_id,
								   IdDepartamento, ccg_total, ccg_iva, InsUsuario)
		VALUES (@CchId, @Fecha, @Tipo, @PrvId, @Nit, @Proveedor, @Serie, @Numero, @Concepto, @CtaId, @IdDepartamento, @Total, @iva, @UsuId);
		SET @CcgId = SCOPE_IDENTITY();
	END
	ELSE
		UPDATE dbo.cch_gasto
		   SET ccg_fecha = @Fecha, ccg_tipo = @Tipo, prv_id = @PrvId, ccg_nit = @Nit, ccg_proveedor = @Proveedor, ccg_serie = @Serie,
			   ccg_numero = @Numero, ccg_concepto = @Concepto, cta_id = @CtaId, IdDepartamento = @IdDepartamento, ccg_total = @Total,
			   ccg_iva = @iva, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE ccg_id = @CcgId;
END;
GO

------------------------------------------------------------
-- 6. Liquidación
------------------------------------------------------------
-- @Gastos vacío: todos los pendientes del fondo hasta @Fecha.
CREATE OR ALTER PROCEDURE [dbo].[paCajaChicaLiquidar]
	@CchId	INT,
	@Fecha	DATE = NULL,
	@Gastos	dbo.id_lista_type READONLY,
	@UsuId	INT = NULL,
	@LccId	INT OUTPUT,
	@Numero	VARCHAR(12) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @LccId = NULL;
	SET @Numero = NULL;
	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));
	DECLARE @cta_fondo INT, @codigo VARCHAR(10), @nombre VARCHAR(100), @cta_iva INT, @mensaje NVARCHAR(300);
	SELECT @cta_fondo = cta_id, @codigo = cch_codigo, @nombre = cch_nombre FROM dbo.cch_fondo WHERE cch_id = @CchId AND cch_estado = 'A';
	IF @cta_fondo IS NULL
		THROW 55115, 'El fondo de caja chica no existe o está inactivo.', 1;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'COMPRA_IVA_CREDITO', @CtaId = @cta_iva OUTPUT;

	DECLARE @lista TABLE (ccg_id INT PRIMARY KEY);
	IF EXISTS (SELECT 1 FROM @Gastos)
		INSERT INTO @lista SELECT DISTINCT id FROM @Gastos;
	ELSE
		INSERT INTO @lista SELECT ccg_id FROM dbo.cch_gasto WHERE cch_id = @CchId AND ccg_estado = 'P' AND ccg_fecha <= @Fecha;
	IF NOT EXISTS (SELECT 1 FROM @lista)
		THROW 55128, 'No hay gastos pendientes para liquidar.', 1;
	IF EXISTS (SELECT 1 FROM @lista list LEFT JOIN dbo.cch_gasto gast ON gast.ccg_id = list.ccg_id AND gast.cch_id = @CchId AND gast.ccg_estado = 'P'
			   WHERE gast.ccg_id IS NULL)
		THROW 55129, 'Algún gasto elegido no es de este fondo o ya no está pendiente.', 1;
	IF EXISTS (SELECT 1 FROM @lista list INNER JOIN dbo.cch_gasto gast ON gast.ccg_id = list.ccg_id WHERE gast.ccg_fecha > @Fecha)
		THROW 55130, 'La fecha de la liquidación no puede ser anterior a la de sus gastos.', 1;

	DECLARE @total NUMERIC(12, 2), @iva NUMERIC(12, 2);
	SELECT @total = SUM(gast.ccg_total), @iva = SUM(gast.ccg_iva)
	FROM @lista list INNER JOIN dbo.cch_gasto gast ON gast.ccg_id = list.ccg_id;

	BEGIN TRY
		BEGIN TRANSACTION;
			SELECT @Numero = CONCAT('LCC-', RIGHT(CONCAT('00000', ISNULL(MAX(CAST(SUBSTRING(lcc_numero, 5, 8) AS INT)), 0) + 1), 6))
			FROM dbo.cch_liquidacion WITH (UPDLOCK, HOLDLOCK);
			INSERT INTO dbo.cch_liquidacion (cch_id, lcc_numero, lcc_fecha, lcc_total, lcc_iva, InsUsuario)
			VALUES (@CchId, @Numero, @Fecha, @total, @iva, @UsuId);
			SET @LccId = SCOPE_IDENTITY();

			DECLARE @partida dbo.cont_asiento_det_cc_type, @asi_id INT;
			INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion, IdDepartamento)
			SELECT gast.cta_id, gast.ccg_total - gast.ccg_iva, 0,
				   LEFT(CONCAT(gast.ccg_concepto, ' · ' + gast.ccg_proveedor,
							   CASE WHEN gast.ccg_numero IS NOT NULL THEN CONCAT(' ', ISNULL(gast.ccg_serie + '-', ''), gast.ccg_numero) ELSE '' END), 256),
				   gast.IdDepartamento
			FROM @lista list INNER JOIN dbo.cch_gasto gast ON gast.ccg_id = list.ccg_id;
			IF @iva > 0
				INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_iva, @iva, 0, CONCAT('IVA crédito fiscal caja chica ', @Numero));
			INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_fondo, 0, @total, CONCAT('Liquidación ', @Numero, ' de ', @codigo));

			DECLARE @descripcion VARCHAR(256) = LEFT(CONCAT('Liquidación de caja chica ', @Numero, ' · ', @codigo, ' ', @nombre), 256);
			EXEC dbo.paContabilidadAsientoInsertarCc @asi_fecha = @Fecha, @asi_descripcion = @descripcion, @asi_origen = 'CAJA_CHICA',
				@asi_origen_id = @LccId, @usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;

			UPDATE dbo.cch_liquidacion SET asi_id = @asi_id WHERE lcc_id = @LccId;
			UPDATE gast SET ccg_estado = 'L', lcc_id = @LccId, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
			FROM dbo.cch_gasto gast INNER JOIN @lista list ON list.ccg_id = gast.ccg_id;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

PRINT '68_caja_chica_vale_sin_proveedor.sql aplicado.';
GO
