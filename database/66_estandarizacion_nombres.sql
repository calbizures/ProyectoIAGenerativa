/*
================================================================================
 66_estandarizacion_nombres.sql
 Estandarización de nombres (punto 10 de la fase 4, alternativa B).

 Los 62 procedimientos sp_<entidad>_<accion> y las 8 funciones fn_<nombre> de
 los primeros scripts pasan al estándar del proyecto:
   - procedimientos: pa + PascalCase, entidad y luego acción
     (sp_ventas_crear_factura -> paVentaFacturaCrear,
      sp_cliente_consultar_por_id -> paClienteConsultarPorId);
   - funciones: fn + PascalCase (fn_moneda_local -> fnMonedaLocal);
   - parámetros en PascalCase (@enc_fecha_docto -> @EncFechaDocto);
   - alias de tabla de 4 letras como mínimo (pro -> prod, enc -> enca).
 La tabla completa de nombres está en el README (sección "Estandarización
 de nombres").

 Los scripts 00 a 65 ya usan los nombres nuevos: en una instalación nueva este
 script solo vuelve a grabar lo mismo. En una base instalada antes de este
 cambio crea los objetos con su nombre nuevo, actualiza los procedimientos que
 los llaman y borra los nombres viejos. La aplicación de esta misma versión ya
 llama a los nombres nuevos: actualice base y aplicación juntas.

 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- select dbo.fnClienteDireccionCompleta(2)
CREATE OR ALTER FUNCTION [dbo].[fnClienteDireccionCompleta] (@CliId INT)
RETURNS VARCHAR(1000)
AS
BEGIN
	DECLARE @DireccionCompleta VARCHAR(1000);

	SELECT @DireccionCompleta = ISNULL(clie.cli_direccion, '')
			+ ISNULL(', ' + prov.prov_nombre, '')
			+ ISNULL(', ' + esta.est_nombre, '')
	FROM dbo.pos_cliente clie
	LEFT JOIN dbo.gen_provincia prov ON prov.prov_id = clie.cli_direccion_provincia
	LEFT JOIN dbo.gen_estado esta ON esta.est_id = clie.cli_direccion_estado
	WHERE clie.cli_id = @CliId;

	RETURN @DireccionCompleta;
END;
GO

-- select dbo.fnClienteNombreCompleto(2)
CREATE OR ALTER FUNCTION [dbo].[fnClienteNombreCompleto] (@CliId INT)
RETURNS VARCHAR(200)
AS
BEGIN
	DECLARE @NombreCompleto VARCHAR(200);

	SELECT @NombreCompleto = ISNULL(clie.cli_nombres, '') + ISNULL(' ' + clie.cli_apellidos, '')
	FROM dbo.pos_cliente clie
	WHERE clie.cli_id = @CliId;

	RETURN @NombreCompleto;
END;
GO

-- select dbo.fnDocumentoClienteNombreCompleto(2)
CREATE OR ALTER FUNCTION [dbo].[fnDocumentoClienteNombreCompleto] (@EncId INT)
RETURNS VARCHAR(256)
AS
BEGIN
	DECLARE @NombreCompleto VARCHAR(256);

	SELECT @NombreCompleto = ISNULL(enca.enc_nombres_cliente, '') + ISNULL(' ' + enca.enc_apellidos_cliente, '')
	FROM dbo.inv_documento_enc enca
	WHERE enca.enc_id = @EncId;

	RETURN @NombreCompleto;
END;
GO

-- Id de la moneda local/funcional de la compañía, usada como valor por
-- defecto en los procedimientos de negocio cuando no se indica moneda.
CREATE OR ALTER FUNCTION [dbo].[fnMonedaLocal]()
RETURNS INT
AS
BEGIN
	RETURN (SELECT TOP 1 [mon_id] FROM [dbo].[gen_moneda] WHERE [mon_es_local] = 1);
END;
GO

/*
	select dbo.fnNumeroALetras(13525.43)
	Convierte un monto a letras en Quetzales. Práctico hasta 999,999,999.99;
	no se extendió a billones porque ningún monto del modelo llega a esa
	magnitud.
*/
CREATE OR ALTER FUNCTION [dbo].[fnNumeroALetras]
(
	@Numero DECIMAL(18, 2)
)
RETURNS VARCHAR(180)
AS
BEGIN
	DECLARE @ImpLetra VARCHAR(180);
	DECLARE @lnEntero BIGINT,
			@lcRetorno VARCHAR(512),
			@lnTerna BIGINT,
			@lcCadena VARCHAR(512),
			@lnUnidades BIGINT,
			@lnDecenas BIGINT,
			@lnCentenas BIGINT,
			@lnFraccion BIGINT;

	SELECT @lnEntero = CAST(@Numero AS BIGINT),
		   @lnFraccion = (@Numero - CAST(@Numero AS BIGINT)) * 100,
		   @lcRetorno = '',
		   @lnTerna = 1;

	WHILE @lnEntero > 0
	BEGIN /* WHILE */
		SELECT @lcCadena = ''
		SELECT @lnUnidades = @lnEntero % 10
		SELECT @lnEntero = CAST(@lnEntero / 10 AS BIGINT)
		SELECT @lnDecenas = @lnEntero % 10
		SELECT @lnEntero = CAST(@lnEntero / 10 AS BIGINT)
		SELECT @lnCentenas = @lnEntero % 10
		SELECT @lnEntero = CAST(@lnEntero / 10 AS BIGINT)

		SELECT @lcCadena =
		CASE /* UNIDADES */
			WHEN @lnUnidades = 1 THEN 'UN ' + @lcCadena
			WHEN @lnUnidades = 2 THEN 'DOS ' + @lcCadena
			WHEN @lnUnidades = 3 THEN 'TRES ' + @lcCadena
			WHEN @lnUnidades = 4 THEN 'CUATRO ' + @lcCadena
			WHEN @lnUnidades = 5 THEN 'CINCO ' + @lcCadena
			WHEN @lnUnidades = 6 THEN 'SEIS ' + @lcCadena
			WHEN @lnUnidades = 7 THEN 'SIETE ' + @lcCadena
			WHEN @lnUnidades = 8 THEN 'OCHO ' + @lcCadena
			WHEN @lnUnidades = 9 THEN 'NUEVE ' + @lcCadena
			ELSE @lcCadena
		END /* UNIDADES */

		SELECT @lcCadena =
		CASE /* DECENAS */
			WHEN @lnDecenas = 1 THEN
				CASE @lnUnidades
					WHEN 0 THEN 'DIEZ '
					WHEN 1 THEN 'ONCE '
					WHEN 2 THEN 'DOCE '
					WHEN 3 THEN 'TRECE '
					WHEN 4 THEN 'CATORCE '
					WHEN 5 THEN 'QUINCE '
					WHEN 6 THEN 'DIECISEIS '
					WHEN 7 THEN 'DIECISIETE '
					WHEN 8 THEN 'DIECIOCHO '
					WHEN 9 THEN 'DIECINUEVE '
				END
			WHEN @lnDecenas = 2 THEN
				CASE @lnUnidades WHEN 0 THEN 'VEINTE ' ELSE 'VEINTI' + @lcCadena END
			WHEN @lnDecenas = 3 THEN
				CASE @lnUnidades WHEN 0 THEN 'TREINTA ' ELSE 'TREINTA Y ' + @lcCadena END
			WHEN @lnDecenas = 4 THEN
				CASE @lnUnidades WHEN 0 THEN 'CUARENTA ' ELSE 'CUARENTA Y ' + @lcCadena END
			WHEN @lnDecenas = 5 THEN
				CASE @lnUnidades WHEN 0 THEN 'CINCUENTA ' ELSE 'CINCUENTA Y ' + @lcCadena END
			WHEN @lnDecenas = 6 THEN
				CASE @lnUnidades WHEN 0 THEN 'SESENTA ' ELSE 'SESENTA Y ' + @lcCadena END
			WHEN @lnDecenas = 7 THEN
				CASE @lnUnidades WHEN 0 THEN 'SETENTA ' ELSE 'SETENTA Y ' + @lcCadena END
			WHEN @lnDecenas = 8 THEN
				CASE @lnUnidades WHEN 0 THEN 'OCHENTA ' ELSE 'OCHENTA Y ' + @lcCadena END
			WHEN @lnDecenas = 9 THEN
				CASE @lnUnidades WHEN 0 THEN 'NOVENTA ' ELSE 'NOVENTA Y ' + @lcCadena END
			ELSE @lcCadena
		END /* DECENAS */

		SELECT @lcCadena =
		CASE /* CENTENAS */
			WHEN @lnCentenas = 1 THEN 'CIENTO ' + @lcCadena
			WHEN @lnCentenas = 2 THEN 'DOSCIENTOS ' + @lcCadena
			WHEN @lnCentenas = 3 THEN 'TRESCIENTOS ' + @lcCadena
			WHEN @lnCentenas = 4 THEN 'CUATROCIENTOS ' + @lcCadena
			WHEN @lnCentenas = 5 THEN 'QUINIENTOS ' + @lcCadena
			WHEN @lnCentenas = 6 THEN 'SEISCIENTOS ' + @lcCadena
			WHEN @lnCentenas = 7 THEN 'SETECIENTOS ' + @lcCadena
			WHEN @lnCentenas = 8 THEN 'OCHOCIENTOS ' + @lcCadena
			WHEN @lnCentenas = 9 THEN 'NOVECIENTOS ' + @lcCadena
			ELSE @lcCadena
		END /* CENTENAS */

		SELECT @lcCadena =
		CASE /* TERNA */
			WHEN @lnTerna = 1 THEN @lcCadena
			WHEN @lnTerna = 2 THEN @lcCadena + 'MIL '
			WHEN @lnTerna = 3 THEN @lcCadena + 'MILLONES '
			WHEN @lnTerna = 4 THEN @lcCadena + 'MIL '
			ELSE ''
		END /* TERNA */

		SELECT @lcRetorno = @lcCadena + @lcRetorno
		SELECT @lnTerna = @lnTerna + 1
	END /* WHILE */

	IF @lnTerna = 1
		SELECT @lcRetorno = 'CERO'

	DECLARE @sFraccion VARCHAR(15);
	SET @sFraccion = '00' + LTRIM(CAST(@lnFraccion AS VARCHAR));
	SELECT @ImpLetra = RTRIM(@lcRetorno) + ' QUETZALES CON ' + SUBSTRING(@sFraccion, LEN(@sFraccion) - 1, 2) + '/100';
	RETURN @ImpLetra;
END;
GO

-- select dbo.fnProductoUltimoCostoUnitario(51)
CREATE OR ALTER FUNCTION [dbo].[fnProductoUltimoCostoUnitario] (@ProId INT)
RETURNS NUMERIC(12, 5)
AS
BEGIN
	DECLARE @costo_unitario NUMERIC(12, 5);

	SELECT TOP 1 @costo_unitario = ISNULL(deta.det_precio_unitario, deta.det_costo_unitario)
	FROM dbo.inv_documento_det deta
	INNER JOIN dbo.inv_documento_enc enca ON enca.enc_id = deta.enc_id
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE tipo.tdo_naturaleza = '+'
	  AND deta.pro_id = @ProId
	  AND enca.enc_estado = 'G'
	ORDER BY enca.enc_fecha_docto DESC;

	RETURN @costo_unitario;
END;
GO

-- select dbo.fnProductoUltimoMovimientoDescripcion(52)
CREATE OR ALTER FUNCTION [dbo].[fnProductoUltimoMovimientoDescripcion] (@ProId INT)
RETURNS VARCHAR(100)
AS
BEGIN
	DECLARE @tdo_descripcion VARCHAR(128);

	SELECT TOP 1 @tdo_descripcion = tipo.tdo_descripcion
	FROM dbo.inv_documento_det deta
	INNER JOIN dbo.inv_documento_enc enca ON enca.enc_id = deta.enc_id
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE tipo.tdo_naturaleza = '+'
	  AND deta.pro_id = @ProId
	  AND enca.enc_estado = 'G'
	ORDER BY enca.enc_fecha_docto DESC;

	RETURN @tdo_descripcion;
END;
GO

-- select dbo.fnProductoUltimoMovimientoFecha(51)
CREATE OR ALTER FUNCTION [dbo].[fnProductoUltimoMovimientoFecha] (@ProId INT)
RETURNS DATE
AS
BEGIN
	DECLARE @fecha_documento DATE;

	SELECT TOP 1 @fecha_documento = enca.enc_fecha_docto
	FROM dbo.inv_documento_det deta
	INNER JOIN dbo.inv_documento_enc enca ON enca.enc_id = deta.enc_id
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE tipo.tdo_naturaleza = '+'
	  AND deta.pro_id = @ProId
	  AND enca.enc_estado = 'G'
	ORDER BY enca.enc_fecha_docto DESC;

	RETURN @fecha_documento;
END;
GO

------------------------------------------------------------
-- Contabilidad: inserción genérica de asientos y generación automática
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paContabilidadPeriodoObtenerOCrear]
	@Fecha	DATE = NULL,
	@UsuId	INT = NULL,
	@PdoId	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));
	DECLARE @anio INT = YEAR(@Fecha), @mes INT = MONTH(@Fecha);

	SELECT @PdoId = pdo_id FROM dbo.cont_periodo_contable WHERE pdo_anio = @anio AND pdo_mes = @mes;

	IF @PdoId IS NULL
	BEGIN
		INSERT INTO dbo.cont_periodo_contable (pdo_anio, pdo_mes, InsUsuario, InsFechaHora)
		VALUES (@anio, @mes, @UsuId, SYSDATETIME());
		SET @PdoId = SCOPE_IDENTITY();
	END
END;
GO

-- Igual que paContabilidadAsientoInsertar, con centro de costo por línea.
CREATE OR ALTER PROCEDURE [dbo].[paContabilidadAsientoInsertarCc]
	@asi_fecha			DATE,
	@asi_descripcion	VARCHAR(256) = NULL,
	@asi_origen			VARCHAR(20) = 'MANUAL',
	@enc_id				INT = NULL,
	@usu_id				INT = NULL,
	@detalle			dbo.cont_asiento_det_cc_type READONLY,
	@asi_id				INT OUTPUT,
	@asi_origen_id		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @detalle)
		THROW 51301, 'El asiento debe tener al menos una línea.', 1;
	IF (SELECT ISNULL(SUM(asd_debe), 0) FROM @detalle) <> (SELECT ISNULL(SUM(asd_haber), 0) FROM @detalle)
		THROW 51302, 'El asiento no está balanceado: la suma del Debe debe ser igual a la suma del Haber.', 1;

	DECLARE @pdo_id INT;
	EXEC dbo.paContabilidadPeriodoObtenerOCrear @Fecha = @asi_fecha, @UsuId = @usu_id, @PdoId = @pdo_id OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.cont_asiento_enc
			(asi_fecha, asi_descripcion, asi_origen, asi_origen_id, enc_id, pdo_id, usu_id, InsUsuario, InsFechaHora)
		VALUES
			(@asi_fecha, @asi_descripcion, @asi_origen, @asi_origen_id, @enc_id, @pdo_id, @usu_id, @usu_id, SYSDATETIME());
		SET @asi_id = SCOPE_IDENTITY();

		INSERT INTO dbo.cont_asiento_det (asi_id, cta_id, asd_debe, asd_haber, asd_descripcion, IdDepartamento, InsUsuario, InsFechaHora)
		SELECT @asi_id, cta_id, asd_debe, asd_haber, asd_descripcion, IdDepartamento, @usu_id, SYSDATETIME()
		FROM @detalle;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 9. Baja y venta
------------------------------------------------------------
-- @Tipo B baja (desuso, robo, destrucción): Debe depreciación acumulada +
-- pérdida (valor en libros) / Haber activo.
-- @Tipo V venta por @PrecioVenta (IVA incluido) cobrado en @CtaIdCobro (caja,
-- banco o cuenta por cobrar): Debe cobro + depreciación acumulada / Haber
-- activo + IVA débito; la diferencia es ganancia (Haber) o pérdida (Debe).
CREATE OR ALTER PROCEDURE [dbo].[paActivoFijoBaja]
	@AfaId			INT,
	@Tipo			CHAR(1),
	@Fecha			DATE,
	@Motivo			VARCHAR(250),
	@PrecioVenta	NUMERIC(14, 2) = NULL,
	@CtaIdCobro		INT = NULL,
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	DECLARE @mensaje NVARCHAR(300), @estado CHAR(1), @codigo VARCHAR(12), @descripcion VARCHAR(200), @costo NUMERIC(14, 2), @acumulada NUMERIC(14, 2),
			@ultimo INT, @cta_activo INT, @cta_depreciacion INT, @depto INT, @adquisicion DATE;
	SELECT @estado = acfi.afa_estado, @codigo = acfi.afa_codigo, @descripcion = acfi.afa_descripcion, @costo = acfi.afa_costo,
		   @acumulada = sald.Acumulada, @ultimo = sald.UltimoMes, @cta_activo = cate.cta_id_activo, @cta_depreciacion = cate.cta_id_depreciacion,
		   @depto = acfi.IdDepartamento, @adquisicion = acfi.afa_fecha_adquisicion
	FROM dbo.afi_activo acfi
	INNER JOIN dbo.afi_categoria cate ON cate.afc_id = acfi.afc_id
	INNER JOIN dbo.fnActivoFijoSaldo() sald ON sald.afa_id = acfi.afa_id
	WHERE acfi.afa_id = @AfaId;

	IF @estado IS NULL
		THROW 55215, 'El activo no existe.', 1;
	IF @estado <> 'A'
		THROW 55233, 'El activo ya no está en uso (dado de baja, vendido o anulado).', 1;
	IF @Tipo NOT IN ('B', 'V')
		THROW 55234, 'Indique si es baja (B) o venta (V).', 1;
	IF @Fecha IS NULL OR @Fecha > CAST(GETDATE() AS DATE) OR @Fecha < @adquisicion
		THROW 55235, 'La fecha de la baja va de la adquisición a hoy.', 1;
	IF @ultimo IS NOT NULL AND YEAR(@Fecha) * 100 + MONTH(@Fecha) < @ultimo
		THROW 55236, 'El activo tiene depreciación grabada de meses posteriores a la fecha de baja; anule esas depreciaciones primero.', 1;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 55237, 'Indique el motivo (al menos 5 caracteres).', 1;
	IF @Tipo = 'V' AND (ISNULL(@PrecioVenta, 0) <= 0 OR @CtaIdCobro IS NULL)
		THROW 55238, 'Para una venta indique el precio y la cuenta donde se cobra (caja, banco o cuenta por cobrar).', 1;
	IF @Tipo = 'V' AND NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaIdCobro AND cta_acepta_movimiento = 1 AND cta_estado = 'A')
		THROW 55239, 'La cuenta de cobro debe ser de detalle y estar activa.', 1;
	IF @acumulada > 0 AND @cta_depreciacion IS NULL
		THROW 55240, 'La categoría del activo no tiene cuenta de depreciación acumulada.', 1;

	DECLARE @tasa NUMERIC(5, 2) = ISNULL((SELECT TOP 1 comp.cia_porc_iva FROM dbo.afi_activo acfi INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = acfi.suc_id
										   INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id WHERE acfi.afa_id = @AfaId), 12);
	DECLARE @iva NUMERIC(14, 2) = IIF(@Tipo = 'V', ROUND(@PrecioVenta * @tasa / (100 + @tasa), 2), 0);
	DECLARE @resultado NUMERIC(14, 2) = IIF(@Tipo = 'V', @PrecioVenta - @iva, 0) - (@costo - @acumulada);	-- > 0 ganancia
	DECLARE @cta_perdida INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'ACTIVO_FIJO_PERDIDA'),
			@cta_ganancia INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'ACTIVO_FIJO_GANANCIA'),
			@cta_iva INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'VENTA_IVA_DEBITO');
	IF (@resultado < 0 AND @cta_perdida IS NULL) OR (@resultado > 0 AND @cta_ganancia IS NULL)
		THROW 55241, 'Asigne las cuentas ACTIVO_FIJO_PERDIDA y ACTIVO_FIJO_GANANCIA en Cuentas de pólizas.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;
			DECLARE @partida dbo.cont_asiento_det_cc_type, @asi_id INT,
					@texto VARCHAR(256) = LEFT(CONCAT(IIF(@Tipo = 'V', 'Venta', 'Baja'), ' de activo fijo ', @codigo, ' ', @descripcion), 256);
			IF @Tipo = 'V'
				INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@CtaIdCobro, @PrecioVenta, 0, @texto);
			IF @acumulada > 0
				INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_depreciacion, @acumulada, 0, @texto);
			IF @resultado < 0
				INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion, IdDepartamento) VALUES (@cta_perdida, -@resultado, 0, @texto, @depto);
			INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_activo, 0, @costo, @texto);
			IF @iva > 0
				INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_iva, 0, @iva, CONCAT('IVA débito venta de activo ', @codigo));
			IF @resultado > 0
				INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_ganancia, 0, @resultado, @texto);
			EXEC dbo.paContabilidadAsientoInsertarCc @asi_fecha = @Fecha, @asi_descripcion = @texto, @asi_origen = 'ACTIVO_FIJO',
				@asi_origen_id = @AfaId, @usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;
			UPDATE dbo.afi_activo
			   SET afa_estado = @Tipo, afa_fecha_baja = @Fecha, afa_motivo_baja = LTRIM(RTRIM(@Motivo)),
				   afa_precio_venta = IIF(@Tipo = 'V', @PrecioVenta, NULL), asi_id_baja = @asi_id, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
			 WHERE afa_id = @AfaId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Graba la depreciación de un mes: un registro por activo y la póliza
-- DEPRECIACION al último día del mes. Los meses van en orden: no se corre un
-- mes anterior a la última corrida vigente.
CREATE OR ALTER PROCEDURE [dbo].[paActivoFijoDepreciar]
	@Anio	INT,
	@Mes	INT,
	@UsuId	INT = NULL,
	@AdcId	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @AdcId = NULL;
	DECLARE @mensaje NVARCHAR(300);
	IF @Mes NOT BETWEEN 1 AND 12 OR @Anio NOT BETWEEN 2000 AND 2100
		THROW 55224, 'Mes no válido.', 1;
	DECLARE @fin DATE = EOMONTH(DATEFROMPARTS(@Anio, @Mes, 1));
	IF DATEFROMPARTS(@Anio, @Mes, 1) > CAST(GETDATE() AS DATE)
		THROW 55225, 'No se deprecia un mes que todavía no empieza.', 1;
	IF EXISTS (SELECT 1 FROM dbo.afi_depreciacion_corrida WHERE adc_anio = @Anio AND adc_mes = @Mes AND adc_estado = 'V')
	BEGIN
		SET @mensaje = CONCAT(N'La depreciación de ', @Mes, N'/', @Anio, N' ya está grabada.');
		THROW 55226, @mensaje, 1;
	END
	IF EXISTS (SELECT 1 FROM dbo.afi_depreciacion_corrida WHERE adc_estado = 'V' AND adc_anio * 100 + adc_mes > @Anio * 100 + @Mes)
		THROW 55227, 'Ya hay depreciación grabada de un mes posterior: los meses se deprecian en orden.', 1;
	IF EXISTS (SELECT 1 FROM dbo.cont_periodo_contable WHERE pdo_anio = @Anio AND pdo_mes = @Mes AND pdo_estado = 'C')
	BEGIN
		SET @mensaje = CONCAT(N'El período ', @Mes, N'/', @Anio, N' está cerrado.');
		THROW 55228, @mensaje, 1;
	END

	DECLARE @cuotas TABLE (afa_id INT PRIMARY KEY, IdDepartamento INT, cta_id_gasto INT, cta_id_depreciacion INT, monto NUMERIC(14, 2));
	INSERT INTO @cuotas SELECT afa_id, IdDepartamento, cta_id_gasto, cta_id_depreciacion, Monto FROM dbo.fnActivoFijoCuotaMes(@Anio, @Mes) WHERE Monto > 0;
	IF NOT EXISTS (SELECT 1 FROM @cuotas)
	BEGIN
		SET @mensaje = CONCAT(N'No hay activos que depreciar en ', @Mes, N'/', @Anio, N' (se deprecian desde el mes siguiente a su adquisición).');
		THROW 55229, @mensaje, 1;
	END

	BEGIN TRY
		BEGIN TRANSACTION;
			INSERT INTO dbo.afi_depreciacion_corrida (adc_anio, adc_mes, adc_total, adc_activos, InsUsuario)
			SELECT @Anio, @Mes, SUM(monto), COUNT(*), @UsuId FROM @cuotas;
			SET @AdcId = SCOPE_IDENTITY();
			INSERT INTO dbo.afi_depreciacion (adc_id, afa_id, afd_monto) SELECT @AdcId, afa_id, monto FROM @cuotas;

			DECLARE @partida dbo.cont_asiento_det_cc_type, @asi_id INT, @texto VARCHAR(256) = CONCAT('Depreciación de activos fijos ', RIGHT(CONCAT('0', @Mes), 2), '/', @Anio);
			INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion, IdDepartamento)
			SELECT cta_id_gasto, SUM(monto), 0, @texto, IdDepartamento FROM @cuotas GROUP BY cta_id_gasto, IdDepartamento
			UNION ALL
			SELECT cta_id_depreciacion, 0, SUM(monto), @texto, NULL FROM @cuotas GROUP BY cta_id_depreciacion;
			EXEC dbo.paContabilidadAsientoInsertarCc @asi_fecha = @fin, @asi_descripcion = @texto, @asi_origen = 'DEPRECIACION',
				@asi_origen_id = @AdcId, @usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;
			UPDATE dbo.afi_depreciacion_corrida SET asi_id = @asi_id WHERE adc_id = @AdcId;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 6. Alta manual y edición
------------------------------------------------------------
-- @CtaIdContrapartida NULL: el bien ya está en libros (saldos iniciales), no
-- se graba póliza. Con cuenta: póliza ACTIVO_FIJO Debe activo / Haber esa
-- cuenta (banco, proveedores, capital...). Al editar solo cambian los datos
-- descriptivos; el costo y las fechas, mientras no tenga depreciación.
CREATE OR ALTER PROCEDURE [dbo].[paActivoFijoGuardar]
	@AfaId					INT = NULL OUTPUT,
	@Descripcion			VARCHAR(200),
	@AfcId					INT,
	@SucId					INT,
	@IdDepartamento			INT = NULL,
	@Responsable			VARCHAR(150) = NULL,
	@Serie					VARCHAR(100) = NULL,
	@Ubicacion				VARCHAR(150) = NULL,
	@FechaAdquisicion		DATE,
	@Costo					NUMERIC(14, 2),
	@ValorResidual			NUMERIC(14, 2) = 0,
	@Porcentaje				NUMERIC(5, 2) = NULL,
	@DepreciacionInicial	NUMERIC(14, 2) = 0,
	@Documento				VARCHAR(100) = NULL,
	@CtaIdContrapartida		INT = NULL,
	@UsuId					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	DECLARE @mensaje NVARCHAR(300), @maximo NUMERIC(5, 2), @cta_activo INT;
	SET @Descripcion = NULLIF(LTRIM(RTRIM(@Descripcion)), '');
	SELECT @maximo = afc_porcentaje, @cta_activo = cta_id_activo FROM dbo.afi_categoria WHERE afc_id = @AfcId AND afc_estado = 'A';
	SET @Porcentaje = ISNULL(@Porcentaje, @maximo);
	SET @ValorResidual = ISNULL(@ValorResidual, 0);
	SET @DepreciacionInicial = ISNULL(@DepreciacionInicial, 0);

	IF @Descripcion IS NULL
		THROW 55206, 'Indique la descripción del activo.', 1;
	IF @maximo IS NULL
		THROW 55207, 'Elija una categoría activa.', 1;
	IF @Porcentaje < 0 OR @Porcentaje > @maximo
	BEGIN
		SET @mensaje = CONCAT(N'El porcentaje anual no puede pasar del máximo de la categoría (', FORMAT(@maximo, 'N2'), N' por ciento anual, Decreto 10-2012 art. 28).');
		THROW 55208, @mensaje, 1;
	END
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE suc_id = @SucId)
		THROW 55209, 'Elija la sucursal donde está el activo.', 1;
	IF @IdDepartamento IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.rrhhDepartamento WHERE IdDepartamento = @IdDepartamento)
		THROW 55210, 'El centro de costo (departamento) no existe.', 1;
	IF @FechaAdquisicion IS NULL OR @FechaAdquisicion > CAST(GETDATE() AS DATE)
		THROW 55211, 'La fecha de adquisición no puede ser futura.', 1;
	IF ISNULL(@Costo, 0) <= 0
		THROW 55212, 'El costo del activo debe ser mayor a cero.', 1;
	IF @ValorResidual < 0 OR @ValorResidual >= @Costo
		THROW 55213, 'El valor residual va de cero a menos que el costo.', 1;
	IF @DepreciacionInicial < 0 OR @DepreciacionInicial > @Costo - @ValorResidual
		THROW 55214, 'La depreciación acumulada anterior no puede pasar del costo menos el valor residual.', 1;

	IF @AfaId IS NOT NULL
	BEGIN
		DECLARE @estado CHAR(1), @costo_actual NUMERIC(14, 2), @enc_id INT;
		SELECT @estado = afa_estado, @costo_actual = afa_costo, @enc_id = enc_id FROM dbo.afi_activo WHERE afa_id = @AfaId;
		IF @estado IS NULL
			THROW 55215, 'El activo no existe.', 1;
		IF @estado <> 'A'
			THROW 55216, 'Solo se modifica un activo en uso (no dado de baja, vendido ni anulado).', 1;
		IF EXISTS (SELECT 1 FROM dbo.afi_depreciacion WHERE afa_id = @AfaId)
		   AND EXISTS (SELECT 1 FROM dbo.afi_activo WHERE afa_id = @AfaId
					   AND (afa_costo <> @Costo OR afa_valor_residual <> @ValorResidual OR afa_porcentaje <> @Porcentaje
							OR afa_fecha_adquisicion <> @FechaAdquisicion OR afa_depreciacion_inicial <> @DepreciacionInicial OR afc_id <> @AfcId))
			THROW 55217, 'El activo ya tiene depreciación: solo se cambian sus datos descriptivos (sucursal, responsable, serie, ubicación, centro de costo).', 1;
		IF (@enc_id IS NOT NULL OR EXISTS (SELECT 1 FROM dbo.afi_activo WHERE afa_id = @AfaId AND asi_id_alta IS NOT NULL))
		   AND (@costo_actual <> @Costo OR EXISTS (SELECT 1 FROM dbo.afi_activo acfi INNER JOIN dbo.afi_categoria cate ON cate.afc_id = acfi.afc_id
												   WHERE acfi.afa_id = @AfaId AND cate.cta_id_activo <> @cta_activo))
			THROW 55218, 'El costo y la cuenta del activo salen de su compra o de su póliza de alta y no se cambian aquí.', 1;
		UPDATE dbo.afi_activo
		   SET afa_descripcion = @Descripcion, afc_id = @AfcId, suc_id = @SucId, IdDepartamento = @IdDepartamento,
			   afa_responsable = NULLIF(LTRIM(RTRIM(@Responsable)), ''), afa_serie = NULLIF(LTRIM(RTRIM(@Serie)), ''),
			   afa_ubicacion = NULLIF(LTRIM(RTRIM(@Ubicacion)), ''), afa_fecha_adquisicion = @FechaAdquisicion, afa_costo = @Costo,
			   afa_valor_residual = @ValorResidual, afa_porcentaje = @Porcentaje, afa_depreciacion_inicial = @DepreciacionInicial,
			   afa_documento = IIF(enc_id IS NULL, NULLIF(LTRIM(RTRIM(@Documento)), ''), afa_documento),
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE afa_id = @AfaId;
		RETURN;
	END

	IF @CtaIdContrapartida IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaIdContrapartida AND cta_acepta_movimiento = 1 AND cta_estado = 'A')
		THROW 55219, 'La cuenta de contrapartida debe ser de detalle y estar activa.', 1;
	IF @CtaIdContrapartida IS NOT NULL AND @DepreciacionInicial > 0
		THROW 55220, 'Con póliza de alta el activo es nuevo en libros: no lleva depreciación acumulada anterior.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;
			DECLARE @codigo VARCHAR(12);
			SELECT @codigo = CONCAT('AF-', RIGHT(CONCAT('00000', ISNULL(MAX(CAST(SUBSTRING(afa_codigo, 4, 9) AS INT)), 0) + 1), 6))
			FROM dbo.afi_activo WITH (UPDLOCK, HOLDLOCK);
			INSERT INTO dbo.afi_activo (afa_codigo, afa_descripcion, afc_id, suc_id, IdDepartamento, afa_responsable, afa_serie, afa_ubicacion,
										afa_fecha_adquisicion, afa_costo, afa_valor_residual, afa_porcentaje, afa_depreciacion_inicial, afa_documento, InsUsuario)
			VALUES (@codigo, @Descripcion, @AfcId, @SucId, @IdDepartamento, NULLIF(LTRIM(RTRIM(@Responsable)), ''), NULLIF(LTRIM(RTRIM(@Serie)), ''),
					NULLIF(LTRIM(RTRIM(@Ubicacion)), ''), @FechaAdquisicion, @Costo, @ValorResidual, @Porcentaje, @DepreciacionInicial,
					NULLIF(LTRIM(RTRIM(@Documento)), ''), @UsuId);
			SET @AfaId = SCOPE_IDENTITY();

			IF @CtaIdContrapartida IS NOT NULL
			BEGIN
				DECLARE @partida dbo.cont_asiento_det_cc_type, @asi_id INT, @texto VARCHAR(256) = LEFT(CONCAT('Alta de activo fijo ', @codigo, ' ', @Descripcion), 256);
				INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion, IdDepartamento)
				VALUES (@cta_activo, @Costo, 0, @texto, @IdDepartamento), (@CtaIdContrapartida, 0, @Costo, @texto, NULL);
				EXEC dbo.paContabilidadAsientoInsertarCc @asi_fecha = @FechaAdquisicion, @asi_descripcion = @texto, @asi_origen = 'ACTIVO_FIJO',
					@asi_origen_id = @AfaId, @usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;
				UPDATE dbo.afi_activo SET asi_id_alta = @asi_id WHERE afa_id = @AfaId;
			END
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paContabilidadAsientoInsertar]
	@AsiFecha			DATE,
	@AsiDescripcion	VARCHAR(256) = NULL,
	@AsiOrigen			VARCHAR(20) = 'MANUAL',
	@EncId				INT = NULL,
	@PdoId				INT = NULL,
	@UsuId				INT = NULL,
	@Detalle			dbo.cont_asiento_det_type READONLY,
	@AsiId				INT OUTPUT,
	@AsiOrigenId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 51301, 'El asiento debe tener al menos una línea.', 1;

	IF (SELECT ISNULL(SUM(asd_debe), 0) FROM @Detalle) <> (SELECT ISNULL(SUM(asd_haber), 0) FROM @Detalle)
		THROW 51302, 'El asiento no está balanceado: la suma del Debe debe ser igual a la suma del Haber.', 1;

	IF @PdoId IS NULL
		EXEC dbo.paContabilidadPeriodoObtenerOCrear @Fecha = @AsiFecha, @UsuId = @UsuId, @PdoId = @PdoId OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.cont_asiento_enc
			(asi_fecha, asi_descripcion, asi_origen, asi_origen_id, enc_id, pdo_id, usu_id, InsUsuario, InsFechaHora)
		VALUES
			(@AsiFecha, @AsiDescripcion, @AsiOrigen, @AsiOrigenId, @EncId, @PdoId, @UsuId, @UsuId, SYSDATETIME());

		SET @AsiId = SCOPE_IDENTITY();

		INSERT INTO dbo.cont_asiento_det (asi_id, cta_id, asd_debe, asd_haber, asd_descripcion, InsUsuario, InsFechaHora)
		SELECT @AsiId, cta_id, asd_debe, asd_haber, asd_descripcion, @UsuId, SYSDATETIME()
		FROM @Detalle;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Cheque a proveedor por una sola cuota (lo usan los datos de prueba).
CREATE OR ALTER PROCEDURE [dbo].[paBancoChequePagoProveedorEmitir]
	@PpgId				INT,
	@CbcId				INT,
	@BceNumeroCheque	VARCHAR(16),
	@ValorPago			NUMERIC(12, 2),
	@BmpId				INT = NULL,
	@UsuId				INT = NULL,
	@BceId				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF @ValorPago <= 0
		THROW 51601, 'El valor del pago debe ser mayor a cero.', 1;

	DECLARE @enc_id INT, @valor_programado NUMERIC(12, 2), @valor_pagado NUMERIC(12, 2), @estado CHAR(1);
	SELECT @enc_id = enc_id, @valor_programado = ppg_valor_pago, @valor_pagado = ISNULL(ppg_valor_real_pago, 0), @estado = ppg_estado
	FROM dbo.inv_proveedor_plan_pago WHERE ppg_id = @PpgId;

	IF @enc_id IS NULL
		THROW 51602, 'La cuota de proveedor indicada no existe.', 1;
	IF @estado = 'A' OR @valor_programado - @valor_pagado <= 0
		THROW 51603, 'La cuota de proveedor indicada ya está pagada por completo.', 1;
	IF @ValorPago > @valor_programado - @valor_pagado
	BEGIN
		DECLARE @msg NVARCHAR(200) = CONCAT(N'El pago (Q', FORMAT(@ValorPago, 'N2'), N') supera el saldo de la cuota (Q',
			FORMAT(@valor_programado - @valor_pagado, 'N2'), N').');
		THROW 51604, @msg, 1;
	END
	IF EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_id = @enc_id AND enc_estado <> 'G')
		THROW 53217, 'La compra de esa cuota está anulada.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @CbcId)
		THROW 51606, 'La chequera indicada no existe.', 1;
	-- Chequera activa, número dentro del rango y sin repetir (vacío = siguiente).
	EXEC dbo.paBcoChequeValidarNumero @CbcId = @CbcId, @Numero = @BceNumeroCheque OUTPUT;

	DECLARE @cta_proveedores INT, @cta_bancos INT = dbo.fnBcoCuentaContable((SELECT bcb_id FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @CbcId));
	EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_PROVEEDORES', @CtaId = @cta_proveedores OUTPUT;
	IF @cta_bancos IS NULL
		EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_bancos OUTPUT;

	DECLARE @beneficiario VARCHAR(150) = (SELECT prov.prv_nombre_comercial FROM dbo.inv_documento_enc docu
										  INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = docu.prv_id WHERE docu.enc_id = @enc_id);

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.bco_cheque_emitido_enc
			(cbc_id, bce_fecha_emision, usu_id, bce_numero_cheque, bce_documento_ref, bce_valor, bmp_id, bce_tipo, bce_beneficiario, InsUsuario, InsFechaHora)
		VALUES
			(@CbcId, CAST(GETDATE() AS DATE), @UsuId, @BceNumeroCheque, CAST(@enc_id AS VARCHAR(16)), @ValorPago, @BmpId, 'P', @beneficiario, @UsuId, SYSDATETIME());

		SET @BceId = SCOPE_IDENTITY();

		INSERT INTO dbo.bco_cheque_emitido_det (bce_id, bmp_id, enc_id, ppg_id, ced_valor, ced_abono_cancelacion, InsUsuario, InsFechaHora)
		VALUES (@BceId, @BmpId, @enc_id, @PpgId, @ValorPago,
				CASE WHEN @valor_pagado + @ValorPago >= @valor_programado THEN 'C' ELSE 'A' END,
				@UsuId, SYSDATETIME());

		UPDATE dbo.inv_proveedor_plan_pago
		   SET ppg_valor_real_pago = @valor_pagado + @ValorPago,
			   ppg_fecha_real_pago = CAST(GETDATE() AS DATE),
			   ppg_numero_cheque = @BceNumeroCheque,
			   cbc_id = @CbcId,
			   ppg_estado = CASE WHEN @valor_pagado + @ValorPago >= @valor_programado THEN 'A' ELSE ppg_estado END,
			   UpdUsuario = @UsuId,
			   UpdFechaHora = SYSDATETIME()
		 WHERE ppg_id = @PpgId
		   AND ISNULL(ppg_valor_real_pago, 0) = @valor_pagado;
		-- El pagado se leyó antes de la transacción: si otro cheque pagó la
		-- misma cuota mientras tanto, no se sobrescribe su pago.
		IF @@ROWCOUNT = 0
			THROW 54303, 'Otro usuario pagó la misma cuota mientras se emitía el cheque. Vuelva a consultarla e intente de nuevo.', 1;

		DECLARE @asi_id INT, @partida dbo.cont_asiento_det_type, @fecha_hoy DATE = CAST(GETDATE() AS DATE);
		DECLARE @referencia VARCHAR(64) = 'Pago a proveedor - cheque ' + @BceNumeroCheque;
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_proveedores, @ValorPago, 0, @referencia), (@cta_bancos, 0, @ValorPago, @referencia);

		DECLARE @asi_descripcion VARCHAR(256) = 'Pago a proveedor con cheque ' + @BceNumeroCheque;
		EXEC dbo.paContabilidadAsientoInsertar
			@AsiFecha = @fecha_hoy, @AsiDescripcion = @asi_descripcion,
			@AsiOrigen = 'PAGO_PROVEEDOR', @AsiOrigenId = @BceId, @EncId = @enc_id,
			@UsuId = @UsuId, @Detalle = @partida, @AsiId = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Cheque libre: beneficiario, motivo y cuenta de gasto (con centro de costo
-- opcional). Partida: Debe cuenta elegida / Haber cuenta del banco.
CREATE OR ALTER PROCEDURE [dbo].[paBcoChequeEmitirLibre]
	@CbcId			INT,
	@Numero			VARCHAR(16) = NULL,
	@Fecha			DATE = NULL,
	@Beneficiario	VARCHAR(150),
	@BmpId			INT,
	@CtaId			INT,
	@IdDepartamento	INT = NULL,
	@Valor			NUMERIC(12, 2),
	@Observaciones	VARCHAR(250) = NULL,
	@UsuId			INT,
	@BceId			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));
	SET @Beneficiario = LTRIM(RTRIM(ISNULL(@Beneficiario, '')));
	IF LEN(@Beneficiario) < 3
		THROW 53416, 'Ingrese el nombre del beneficiario del cheque.', 1;
	IF ISNULL(@Valor, 0) <= 0
		THROW 51601, 'El valor del cheque debe ser mayor a cero.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.bco_motivo_pago WHERE bmp_id = @BmpId AND bmp_estado = 'A')
		THROW 53418, 'Elija un motivo de pago activo.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId AND cta_estado = 'A' AND cta_acepta_movimiento = 1)
		THROW 53404, 'La cuenta contable debe existir, estar activa y aceptar movimientos.', 1;
	IF @IdDepartamento IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.rrhhDepartamento WHERE IdDepartamento = @IdDepartamento AND Estado = 'A')
		THROW 53419, 'El centro de costo (departamento) no existe o está inactivo.', 1;

	EXEC dbo.paBcoChequeValidarNumero @CbcId = @CbcId, @Numero = @Numero OUTPUT;

	DECLARE @cta_banco INT = dbo.fnBcoCuentaContable((SELECT bcb_id FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @CbcId));
	IF @cta_banco IS NULL
		EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_banco OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.bco_cheque_emitido_enc
			(cbc_id, bce_fecha_emision, usu_id, bce_numero_cheque, bce_observaciones, bce_valor, bmp_id,
			 bce_tipo, bce_beneficiario, cta_id, IdDepartamento, InsUsuario, InsFechaHora)
		VALUES
			(@CbcId, @Fecha, @UsuId, @Numero, NULLIF(LTRIM(RTRIM(@Observaciones)), ''), @Valor, @BmpId,
			 'L', @Beneficiario, @CtaId, @IdDepartamento, @UsuId, SYSDATETIME());
		SET @BceId = SCOPE_IDENTITY();

		DECLARE @partida dbo.cont_asiento_det_cc_type, @asi_id INT;
		DECLARE @referencia VARCHAR(256) = LEFT(CONCAT('Cheque ', @Numero, ' a ', @Beneficiario), 256);
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion, IdDepartamento)
		VALUES (@CtaId, @Valor, 0, @referencia, @IdDepartamento),
			   (@cta_banco, 0, @Valor, @referencia, NULL);

		EXEC dbo.paContabilidadAsientoInsertarCc
			@asi_fecha = @Fecha, @asi_descripcion = @referencia, @asi_origen = 'CHEQUE', @asi_origen_id = @BceId,
			@usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBodegaActualizar]
	@BodId				INT,
	@BodDescripcion	VARCHAR(128),
	@SucId				INT,
	@UsuId				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE bod_id = @BodId)
		THROW 51042, 'La bodega indicada no existe.', 1;

	UPDATE dbo.inv_bodega
	   SET bod_descripcion = @BodDescripcion,
		   suc_id = @SucId,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE bod_id = @BodId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBodegaConsultarPorId]
	@BodId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.inv_bodega WHERE bod_id = @BodId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBodegaEliminar]
	@BodId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE bod_id = @BodId)
		THROW 51042, 'La bodega indicada no existe.', 1;

	UPDATE dbo.inv_bodega
	   SET bod_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE bod_id = @BodId;
END;
GO

------------------------------------------------------------
-- inv_bodega
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paBodegaInsertar]
	@BodCodigo			VARCHAR(8),
	@BodDescripcion	VARCHAR(128),
	@SucId				INT,
	@UsuId				INT = NULL,
	@BodId				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE suc_id = @SucId AND bod_codigo = @BodCodigo)
		THROW 51041, 'Ya existe una bodega con ese código en la sucursal.', 1;

	INSERT INTO dbo.inv_bodega (bod_codigo, bod_descripcion, suc_id, InsUsuario, InsFechaHora)
	VALUES (@BodCodigo, @BodDescripcion, @SucId, @UsuId, SYSDATETIME());

	SET @BodId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBodegaListar]
	@SucId			INT = NULL,
	@BodEstado		CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT bode.bod_id, bode.bod_codigo, bode.bod_descripcion, bode.suc_id, sucu.suc_descripcion, bode.bod_estado
	FROM dbo.inv_bodega bode
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
	WHERE (@SucId IS NULL OR bode.suc_id = @SucId)
	  AND (@BodEstado IS NULL OR bode.bod_estado = @BodEstado)
	ORDER BY bode.bod_descripcion;
END;
GO

------------------------------------------------------------
-- 6. Apertura y cierre de caja simultáneos
------------------------------------------------------------
-- Apertura de caja: monto inicial libre.
CREATE OR ALTER PROCEDURE [dbo].[paCajaAbrir]
	@PcrId				INT,
	@UsuId				INT,
	@PcaMontoInicial	NUMERIC(12, 2) = 0,
	@PcaId				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	BEGIN TRANSACTION;
	-- El bloqueo de rango (UPDLOCK, HOLDLOCK) hace que una segunda apertura
	-- simultánea de la misma caja espere a la primera y luego la encuentre.
	IF EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WITH (UPDLOCK, HOLDLOCK) WHERE pcr_id = @PcrId AND pca_estado = 'A')
		THROW 51701, 'Ya existe una apertura de caja activa para esta caja receptora. Debe cerrarse antes de abrir una nueva.', 1;

	INSERT INTO dbo.pos_caja_apertura (pcr_id, usu_id_apertura, pca_monto_inicial, InsUsuario, InsFechaHora)
	VALUES (@PcrId, @UsuId, ISNULL(@PcaMontoInicial, 0), @UsuId, SYSDATETIME());

	SET @PcaId = SCOPE_IDENTITY();
	COMMIT TRANSACTION;
END;
GO

-- Cierre de caja: faltante o sobrante dentro de la tolerancia.
CREATE OR ALTER PROCEDURE [dbo].[paCajaCerrar]
	@PcaId	INT,
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @PcaId AND pca_estado = 'A')
		THROW 51702, 'La apertura de caja indicada no existe o ya está cerrada.', 1;

	DECLARE @cuadre TABLE (MontoInicial NUMERIC(12, 2), EfectivoCobrado NUMERIC(12, 2), Depositos NUMERIC(12, 2), Cheques NUMERIC(12, 2),
		Tarjetas NUMERIC(12, 2), OtrasFormas NUMERIC(12, 2), TeoricoTotal NUMERIC(12, 2), FisicoEfectivo NUMERIC(12, 2),
		FisicoOtrasFormas NUMERIC(12, 2), FisicoTotal NUMERIC(12, 2), Diferencia NUMERIC(12, 2), Tolerancia NUMERIC(12, 2), Cuadra BIT);
	INSERT INTO @cuadre EXEC dbo.paCorteCajaCuadreConsultar @pca_id = @PcaId;

	DECLARE @teorico NUMERIC(12, 2), @fisico NUMERIC(12, 2), @diferencia NUMERIC(12, 2), @tolerancia NUMERIC(12, 2), @cuadra BIT;
	SELECT @teorico = TeoricoTotal, @fisico = FisicoTotal, @diferencia = Diferencia, @tolerancia = Tolerancia, @cuadra = Cuadra FROM @cuadre;

	IF @cuadra = 0
	BEGIN
		DECLARE @mensaje NVARCHAR(400) = CONCAT(N'La caja no cuadra: teórico Q', FORMAT(@teorico, 'N2'), N', contado Q', FORMAT(@fisico, 'N2'),
			N', diferencia Q', FORMAT(@diferencia, 'N2'), N' (tolerancia permitida Q', FORMAT(@tolerancia, 'N2'),
			N'). Revise el conteo y los depósitos antes de cerrar.');
		THROW 51703, @mensaje, 1;
	END

	-- La caja absorbe la diferencia contra faltantes (gasto) o sobrantes
	-- (ingreso). La cuenta de caja es la misma donde entran los cobros.
	DECLARE @detalle dbo.cont_asiento_det_type, @asi_id INT, @cta_caja INT, @cta_diferencia INT;
	IF @diferencia <> 0
	BEGIN
		EXEC dbo.paCuentaParametroObtener @Codigo = 'COBRO_CAJA', @CtaId = @cta_caja OUTPUT;
		IF @diferencia < 0
		BEGIN
			EXEC dbo.paCuentaParametroObtener @Codigo = 'CAJA_FALTANTE', @CtaId = @cta_diferencia OUTPUT;
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			VALUES (@cta_diferencia, -@diferencia, 0, CONCAT('Faltante al cerrar la apertura ', @PcaId)),
				   (@cta_caja, 0, -@diferencia, CONCAT('Faltante al cerrar la apertura ', @PcaId));
		END
		ELSE
		BEGIN
			EXEC dbo.paCuentaParametroObtener @Codigo = 'CAJA_SOBRANTE', @CtaId = @cta_diferencia OUTPUT;
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			VALUES (@cta_caja, @diferencia, 0, CONCAT('Sobrante al cerrar la apertura ', @PcaId)),
				   (@cta_diferencia, 0, @diferencia, CONCAT('Sobrante al cerrar la apertura ', @PcaId));
		END
	END

	BEGIN TRANSACTION;

	UPDATE dbo.pos_caja_apertura
	   SET pca_estado = 'C',
		   pca_fecha_corte = SYSDATETIME(),
		   pca_fecha_cierre = SYSDATETIME(),
		   usu_id_cierre = @UsuId,
		   pca_monto_teorico_total = @teorico,
		   pca_monto_fisico_total = @fisico,
		   pca_diferencia = @diferencia,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE pca_id = @PcaId AND pca_estado = 'A';
	-- Dos cierres simultáneos pasan la validación de arriba; solo el primero
	-- cierra y graba la póliza de la diferencia.
	IF @@ROWCOUNT = 0
		THROW 51702, 'La apertura de caja indicada no existe o ya está cerrada.', 1;

	IF EXISTS (SELECT 1 FROM @detalle)
	BEGIN
		DECLARE @fecha DATE = CAST(GETDATE() AS DATE);
		DECLARE @descripcion VARCHAR(256) = CONCAT('Diferencia en el cierre de caja, apertura ', @PcaId);
		EXEC dbo.paContabilidadAsientoInsertar
			@AsiFecha = @fecha, @AsiDescripcion = @descripcion, @AsiOrigen = 'CIERRE_CAJA', @AsiOrigenId = @PcaId,
			@UsuId = @UsuId, @Detalle = @detalle, @AsiId = @asi_id OUTPUT;
	END

	COMMIT TRANSACTION;
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
				   LEFT(CONCAT(gast.ccg_concepto, ' · ', gast.ccg_proveedor,
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

-- Depósito de caja a una cuenta bancaria: Debe la cuenta de cargos de la
-- cuenta bancaria / Haber DEPOSITO_CAJA. Sin cuenta bancaria (llamadas
-- anteriores a este script) se usa el concepto DEPOSITO_BANCOS.
CREATE OR ALTER PROCEDURE [dbo].[paCajaDepositoInsertar]
	@pca_id				INT,
	@gef_id				INT = NULL,
	@pcd_fecha_deposito	DATE,
	@pcd_valor_deposito	DECIMAL(14, 2),
	@pcd_numero_boleta	VARCHAR(32) = NULL,
	@pcd_observaciones	VARCHAR(128) = NULL,
	@usu_id				INT = NULL,
	@bcb_id				INT = NULL,
	@pcd_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id)
		THROW 51904, 'La apertura de caja indicada no existe.', 1;
	IF ISNULL(@pcd_valor_deposito, 0) <= 0
		THROW 52501, 'El valor del depósito debe ser mayor a cero.', 1;
	IF @bcb_id IS NOT NULL
	BEGIN
		DECLARE @gef_cuenta INT = (SELECT gef_id FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @bcb_id AND bcb_estado = 'A');
		IF @gef_cuenta IS NULL
			THROW 53601, 'La cuenta bancaria del depósito no existe o está inactiva.', 1;
		IF @gef_id IS NOT NULL AND @gef_id <> @gef_cuenta
			THROW 53602, 'La cuenta bancaria no pertenece al banco indicado.', 1;
		SET @gef_id = @gef_cuenta;
	END
	ELSE IF @gef_id IS NULL
		THROW 53603, 'Indique la cuenta bancaria a la que se depositó.', 1;

	DECLARE @cta_banco INT = dbo.fnBcoCuentaContableCargo(@bcb_id), @cta_caja INT;
	IF @cta_banco IS NULL
		EXEC dbo.paCuentaParametroObtener @Codigo = 'DEPOSITO_BANCOS', @CtaId = @cta_banco OUTPUT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'DEPOSITO_CAJA', @CtaId = @cta_caja OUTPUT;

	BEGIN TRANSACTION;

	INSERT INTO dbo.pos_caja_deposito
		(pcd_fecha_deposito, pcd_valor_deposito, pcd_numero_boleta, pcd_observaciones, pca_id, gef_id, bcb_id, InsUsuario, InsFechaHora)
	VALUES
		(@pcd_fecha_deposito, @pcd_valor_deposito, @pcd_numero_boleta, @pcd_observaciones, @pca_id, @gef_id, @bcb_id, @usu_id, SYSDATETIME());

	SET @pcd_id = SCOPE_IDENTITY();

	DECLARE @cuenta VARCHAR(40) = (SELECT CONCAT(' a cuenta ', bcb_numero_cuenta) FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @bcb_id);
	DECLARE @referencia VARCHAR(100) = CONCAT('Depósito boleta ', ISNULL(@pcd_numero_boleta, 's/n'), @cuenta, ' - apertura ', @pca_id);
	DECLARE @detalle dbo.cont_asiento_det_type, @asi_id INT;
	INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
	VALUES (@cta_banco, @pcd_valor_deposito, 0, @referencia),
		   (@cta_caja, 0, @pcd_valor_deposito, @referencia);

	EXEC dbo.paContabilidadAsientoInsertar
		@AsiFecha = @pcd_fecha_deposito, @AsiDescripcion = @referencia, @AsiOrigen = 'DEPOSITO', @AsiOrigenId = @pcd_id,
		@UsuId = @usu_id, @Detalle = @detalle, @AsiId = @asi_id OUTPUT;

	COMMIT TRANSACTION;
END;
GO

-- Partida de cierre al 31/12/@Anio: salda cada cuenta de resultados (ingresos,
-- costos y gastos) contra Utilidades del ejercicio (o Pérdidas del ejercicio).
CREATE OR ALTER PROCEDURE [dbo].[paCierreAnualGenerar]
	@Anio	INT,
	@UsuId	INT = NULL,
	@AsiId	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @AsiId = NULL;
	DECLARE @fecha DATE = DATEFROMPARTS(@Anio, 12, 31), @mensaje NVARCHAR(300);
	IF EXISTS (SELECT 1 FROM dbo.cont_asiento_enc WHERE asi_origen = 'CIERRE_ANUAL' AND asi_origen_id = @Anio AND asi_estado = 'A')
		THROW 55016, 'El año ya tiene su partida de cierre vigente; anúlela en Pólizas si necesita volver a generarla.', 1;
	IF EXISTS (SELECT 1 FROM dbo.cont_periodo_contable WHERE pdo_anio = @Anio AND pdo_mes = 12 AND pdo_estado = 'C')
		THROW 55017, 'Diciembre está cerrado: ábralo para grabar la partida de cierre.', 1;

	DECLARE @cta_utilidad INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'CIERRE_UTILIDAD'),
			@cta_perdida INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'CIERRE_PERDIDA');
	IF @cta_utilidad IS NULL OR @cta_perdida IS NULL
		THROW 55018, 'Asigne las cuentas de Utilidades y Pérdidas del ejercicio (conceptos CIERRE_UTILIDAD y CIERRE_PERDIDA) en Cuentas de pólizas.', 1;

	DECLARE @detalle dbo.cont_asiento_det_cc_type;
	INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
	SELECT saldo.cta_id, IIF(saldo.haber > saldo.debe, saldo.haber - saldo.debe, 0), IIF(saldo.debe > saldo.haber, saldo.debe - saldo.haber, 0),
		   LEFT(CONCAT('Cierre ', @Anio, ': ', cuen.cta_nombre), 256)
	FROM dbo.fnContSaldosRango(DATEFROMPARTS(@Anio, 1, 1), @fecha, 1) saldo
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = saldo.cta_id AND cuen.cta_tipo IN ('I', 'G')
	WHERE saldo.debe <> saldo.haber;
	IF NOT EXISTS (SELECT 1 FROM @detalle)
	BEGIN
		SET @mensaje = CONCAT(N'El año ', @Anio, N' no tiene saldos en cuentas de resultados.');
		THROW 55019, @mensaje, 1;
	END

	DECLARE @resultado NUMERIC(16, 2) = (SELECT SUM(asd_debe) - SUM(asd_haber) FROM @detalle);	-- Debe > Haber: utilidad
	INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
	SELECT IIF(@resultado > 0, @cta_utilidad, @cta_perdida), IIF(@resultado < 0, -@resultado, 0), IIF(@resultado > 0, @resultado, 0),
		   CONCAT(IIF(@resultado >= 0, 'Utilidad', 'Pérdida'), ' del ejercicio ', @Anio)
	WHERE @resultado <> 0;

	DECLARE @descripcion VARCHAR(256) = CONCAT('Partida de cierre del ejercicio ', @Anio, ': ', IIF(@resultado >= 0, 'utilidad', 'pérdida'), ' Q', FORMAT(ABS(@resultado), 'N2'));
	EXEC dbo.paContabilidadAsientoInsertarCc @asi_fecha = @fecha, @asi_descripcion = @descripcion, @asi_origen = 'CIERRE_ANUAL',
		@asi_origen_id = @Anio, @usu_id = @UsuId, @detalle = @detalle, @asi_id = @AsiId OUTPUT;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paClienteActualizar]
	@CliId					INT,
	@CliNombres			VARCHAR(64),
	@CliApellidos			VARCHAR(64) = NULL,
	@CliDireccion			VARCHAR(128) = NULL,
	@CliTelefonoCelular	VARCHAR(16) = NULL,
	@CliNit				VARCHAR(16) = NULL,
	@CliEmail				VARCHAR(64) = NULL,
	@CliLimiteCredito		DECIMAL(14, 2) = 0,
	@UsuId					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_id = @CliId)
		THROW 51013, 'El cliente indicado no existe.', 1;

	IF @CliNit IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_nit = @CliNit AND cli_id <> @CliId)
		THROW 51012, 'Ya existe otro cliente con ese NIT.', 1;

	UPDATE dbo.pos_cliente
	   SET cli_nombres = @CliNombres,
		   cli_apellidos = @CliApellidos,
		   cli_direccion = @CliDireccion,
		   cli_telefono_celular = @CliTelefonoCelular,
		   cli_nit = @CliNit,
		   cli_email = @CliEmail,
		   cli_limite_credito = @CliLimiteCredito,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE cli_id = @CliId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paClienteConsultar]
	@Texto			VARCHAR(128) = NULL,	-- busca en código, nombres, apellidos o NIT
	@CliEstado		CHAR(1) = 'A',
	@Pagina			INT = 1,
	@TamanioPagina	INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT cli_id, cli_codigo, cli_nombres, cli_apellidos, cli_nit, cli_email,
		   cli_telefono_celular, cli_limite_credito, cli_estado
	FROM dbo.pos_cliente
	WHERE (@CliEstado IS NULL OR cli_estado = @CliEstado)
	  AND (@Texto IS NULL
		   OR cli_codigo LIKE '%' + @Texto + '%'
		   OR cli_nombres LIKE '%' + @Texto + '%'
		   OR cli_apellidos LIKE '%' + @Texto + '%'
		   OR cli_nit LIKE '%' + @Texto + '%')
	ORDER BY cli_nombres, cli_apellidos
	OFFSET (@Pagina - 1) * @TamanioPagina ROWS FETCH NEXT @TamanioPagina ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paClienteConsultarPorId]
	@CliId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.pos_cliente WHERE cli_id = @CliId;
END;
GO

------------------------------------------------------------
-- 2. Cobro de una o varias cuotas en un recibo
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCxcCobroRegistrar]
	@CliId	INT,
	@PcaId	INT,
	@UsuId	INT = NULL,
	@Cuotas	dbo.cobro_cuota_type READONLY,
	@Formas	dbo.pago_forma_type READONLY,
	@PpeId	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @PpeId = NULL;

	DECLARE @total NUMERIC(12, 2) = (SELECT SUM(monto) FROM @Cuotas);
	DECLARE @msg NVARCHAR(400);

	IF @total IS NULL
		THROW 53201, 'Seleccione al menos una cuota a cobrar.', 1;
	IF EXISTS (SELECT 1 FROM @Cuotas WHERE monto <= 0)
		THROW 53202, 'El monto aplicado a cada cuota debe ser mayor a cero.', 1;
	IF EXISTS (SELECT cpp_id FROM @Cuotas GROUP BY cpp_id HAVING COUNT(*) > 1)
		THROW 53203, 'Una cuota aparece más de una vez en el cobro.', 1;
	IF EXISTS (SELECT 1 FROM @Cuotas apli
			   LEFT JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = apli.cpp_id
			   WHERE cuot.cpp_id IS NULL OR cuot.cli_id <> @CliId)
		THROW 53204, 'Una de las cuotas no existe o no es del cliente.', 1;
	IF EXISTS (SELECT 1 FROM @Cuotas apli
			   INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = apli.cpp_id
			   INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
			   WHERE docu.enc_estado <> 'G')
		THROW 53205, 'Una de las cuotas es de una factura anulada.', 1;

	SELECT TOP 1 @msg = CONCAT(N'El monto aplicado a la cuota ', cuot.cpp_nro_cuota, N' de ', ISNULL(docu.enc_numero_unico, docu.enc_numero_docto),
		N' (Q', FORMAT(apli.monto, 'N2'), N') supera su saldo (Q', FORMAT(cuot.cpp_saldo_cuota, 'N2'), N').')
	FROM @Cuotas apli
	INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = apli.cpp_id
	INNER JOIN dbo.inv_documento_enc docu ON docu.enc_id = cuot.enc_id
	WHERE apli.monto > cuot.cpp_saldo_cuota;
	IF @msg IS NOT NULL
		THROW 53206, @msg, 1;

	IF NOT EXISTS (SELECT 1 FROM @Formas)
		THROW 53207, 'Indique la forma de pago del cobro.', 1;
	IF EXISTS (SELECT 1 FROM @Formas WHERE ppf_monto <= 0)
		THROW 53208, 'El monto de cada forma de pago debe ser mayor a cero.', 1;
	IF (SELECT SUM(ppf_monto) FROM @Formas) <> @total
	BEGIN
		SET @msg = CONCAT(N'Las formas de pago suman Q', FORMAT((SELECT SUM(ppf_monto) FROM @Formas), 'N2'),
			N' y el cobro es de Q', FORMAT(@total, 'N2'), N'.');
		THROW 53209, @msg, 1;
	END
	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @PcaId AND pca_estado = 'A')
		THROW 53210, 'No hay una caja abierta para recibir el cobro.', 1;

	DECLARE @cta_caja INT, @cta_clientes INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'COBRO_CAJA', @CtaId = @cta_caja OUTPUT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'COBRO_CLIENTES', @CtaId = @cta_clientes OUTPUT;

	-- La póliza queda ligada a la factura solo si el recibo cobra una sola.
	DECLARE @enc_id INT = (SELECT CASE WHEN COUNT(DISTINCT cuot.enc_id) = 1 THEN MIN(cuot.enc_id) END
						   FROM @Cuotas apli INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = apli.cpp_id);

	BEGIN TRY
		BEGIN TRANSACTION;

		-- El saldo se vuelve a comprobar al rebajarlo por si otro cajero cobró
		-- la misma cuota entre la validación y este punto.
		UPDATE cuot
		   SET cpp_saldo_cuota = cuot.cpp_saldo_cuota - apli.monto,
			   cpp_fecha_real_pago = CASE WHEN cuot.cpp_saldo_cuota - apli.monto <= 0 THEN CAST(GETDATE() AS DATE) ELSE cuot.cpp_fecha_real_pago END,
			   cpp_estado = CASE WHEN cuot.cpp_saldo_cuota - apli.monto <= 0 THEN 'A' ELSE cuot.cpp_estado END,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		FROM dbo.pos_cliente_plan_pagos cuot WITH (UPDLOCK, ROWLOCK)
		INNER JOIN @Cuotas apli ON apli.cpp_id = cuot.cpp_id
		WHERE cuot.cpp_saldo_cuota >= apli.monto;

		IF @@ROWCOUNT <> (SELECT COUNT(*) FROM @Cuotas)
			THROW 53211, 'El saldo de una de las cuotas cambió mientras se registraba el cobro. Vuelva a consultar y cobre de nuevo.', 1;

		INSERT INTO dbo.pos_pago_enc (cli_id, pca_id, usu_id, InsUsuario, InsFechaHora)
		VALUES (@CliId, @PcaId, @UsuId, @UsuId, SYSDATETIME());
		SET @PpeId = SCOPE_IDENTITY();

		INSERT INTO dbo.pos_pago_det (ppe_id, cpp_id, ppd_valor_aplicado, InsUsuario, InsFechaHora)
		SELECT @PpeId, cpp_id, monto, @UsuId, SYSDATETIME() FROM @Cuotas;

		INSERT INTO dbo.pos_pago_forma
			(gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, ppe_id, pft_id, InsUsuario, InsFechaHora)
		SELECT gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, @PpeId, pft_id, @UsuId, SYSDATETIME()
		FROM @Formas;

		DECLARE @asi_id INT, @partida dbo.cont_asiento_det_type, @fecha_hoy DATE = CAST(GETDATE() AS DATE);
		DECLARE @referencia VARCHAR(64) = CONCAT('Recibo ', @PpeId);
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_caja, @total, 0, @referencia), (@cta_clientes, 0, @total, @referencia);

		EXEC dbo.paContabilidadAsientoInsertar
			@AsiFecha = @fecha_hoy, @AsiDescripcion = 'Cobro a cliente',
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

-- Atajo de una sola cuota (lo usan los datos de prueba). Sin formas de pago
-- el monto se toma como Efectivo.
CREATE OR ALTER PROCEDURE [dbo].[paClienteCuotaPagoRegistrar]
	@CppId			INT,
	@ValorPago		NUMERIC(12, 2),
	@PcaId			INT,
	@UsuId			INT = NULL,
	@FormasPago	dbo.pago_forma_type READONLY,
	@PpeId			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @cli_id INT = (SELECT cli_id FROM dbo.pos_cliente_plan_pagos WHERE cpp_id = @CppId);
	IF @cli_id IS NULL
		THROW 51502, 'La cuota indicada no existe.', 1;

	DECLARE @cuotas dbo.cobro_cuota_type, @formas dbo.pago_forma_type;
	INSERT INTO @cuotas (cpp_id, monto) VALUES (@CppId, @ValorPago);
	INSERT INTO @formas SELECT * FROM @FormasPago;
	IF NOT EXISTS (SELECT 1 FROM @formas)
		INSERT INTO @formas (pft_id, ppf_monto)
		SELECT pft_id, @ValorPago FROM dbo.pos_pago_forma_tipo WHERE pft_descripcion = 'Efectivo';

	EXEC dbo.paCxcCobroRegistrar @CliId = @cli_id, @PcaId = @PcaId, @UsuId = @UsuId,
		@Cuotas = @cuotas, @Formas = @formas, @PpeId = @PpeId OUTPUT;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paClienteEliminar]
	@CliId INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_id = @CliId)
		THROW 51013, 'El cliente indicado no existe.', 1;

	UPDATE dbo.pos_cliente
	   SET cli_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE cli_id = @CliId;
END;
GO

------------------------------------------------------------
-- pos_cliente
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paClienteInsertar]
	@CliCodigo				VARCHAR(32),
	@CliNombres			VARCHAR(64),
	@CliApellidos			VARCHAR(64) = NULL,
	@CliDireccion			VARCHAR(128) = NULL,
	@CliTelefonoCelular	VARCHAR(16) = NULL,
	@CliNit				VARCHAR(16) = NULL,
	@CliEmail				VARCHAR(64) = NULL,
	@CliLimiteCredito		DECIMAL(14, 2) = 0,
	@CliDireccionPais		INT = NULL,
	@CliDireccionEstado	INT = NULL,
	@CliDireccionProvincia INT = NULL,
	@UsuId					INT = NULL,
	@CliId					INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_codigo = @CliCodigo)
		THROW 51011, 'Ya existe un cliente con ese código.', 1;

	IF @CliNit IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_nit = @CliNit)
		THROW 51012, 'Ya existe un cliente con ese NIT.', 1;

	INSERT INTO dbo.pos_cliente
		(cli_codigo, cli_nombres, cli_apellidos, cli_direccion, cli_telefono_celular,
		 cli_nit, cli_email, cli_limite_credito, cli_direccion_pais, cli_direccion_estado, cli_direccion_provincia,
		 InsUsuario, InsFechaHora)
	VALUES
		(@CliCodigo, @CliNombres, @CliApellidos, @CliDireccion, @CliTelefonoCelular,
		 @CliNit, @CliEmail, @CliLimiteCredito, @CliDireccionPais, @CliDireccionEstado, @CliDireccionProvincia,
		 @UsuId, SYSDATETIME());

	SET @CliId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paClientePlanPagosGenerar]
	@EncId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @contador INT, @fecha_iteracion DATE, @valor_cuota NUMERIC(13, 2),
			@cli_id INT, @numero_cuotas INT, @fecha_primer_pago DATE,
			@monto_enganche NUMERIC(13, 2), @monto_total NUMERIC(13, 2);

	SELECT @cli_id = cli_id, @numero_cuotas = enc_numero_cuotas,
		   @fecha_primer_pago = enc_fecha_primer_pago, @monto_total = enc_monto_total,
		   @monto_enganche = enc_monto_enganche
	FROM dbo.inv_documento_enc
	WHERE enc_id = @EncId;

	-- enc_monto_total ya viene neto de descuento (ver paVentaFacturaCrear),
	-- así que aquí sólo se resta el enganche; restar también el descuento
	-- duplicaba la resta y dejaba el monto financiado por debajo del real.
	IF @fecha_primer_pago IS NOT NULL AND @monto_total IS NOT NULL AND @numero_cuotas IS NOT NULL AND @numero_cuotas > 0
	BEGIN
		SET @contador = 1;
		SET @valor_cuota = (ISNULL(@monto_total, 0) - ISNULL(@monto_enganche, 0)) / @numero_cuotas;
		SET @fecha_iteracion = @fecha_primer_pago;

		WHILE @contador <= @numero_cuotas
		BEGIN
			INSERT INTO dbo.pos_cliente_plan_pagos
				(cpp_nro_cuota, cpp_fecha_maxima_pago, cpp_valor_cuota, cpp_saldo_cuota, enc_id, cli_id, cpp_estado,
				 InsUsuario, InsFechaHora)
			VALUES
				(@contador, @fecha_iteracion, @valor_cuota, @valor_cuota, @EncId, @cli_id, 'P',
				 @UsuId, SYSDATETIME());

			SET @contador = @contador + 1;
			SET @fecha_iteracion = DATEADD(MONTH, 1, @fecha_iteracion);
			IF DATEPART(dw, @fecha_iteracion) = 7
				SET @fecha_iteracion = DATEADD(DAY, 1, @fecha_iteracion);
		END

		-- Ajusta la última cuota para que la suma cuadre exactamente con el monto financiado.
		DECLARE @monto_cuotas NUMERIC(12, 2), @monto_restante NUMERIC(12, 2);

		SELECT @monto_cuotas = SUM(cpp_valor_cuota) FROM dbo.pos_cliente_plan_pagos WHERE enc_id = @EncId;
		SET @monto_restante = (ISNULL(@monto_total, 0) - ISNULL(@monto_enganche, 0)) - ISNULL(@monto_cuotas, 0);

		IF @monto_restante <> 0
			UPDATE dbo.pos_cliente_plan_pagos
			   SET cpp_valor_cuota = cpp_valor_cuota + @monto_restante,
				   cpp_saldo_cuota = cpp_saldo_cuota + @monto_restante,
				   UpdUsuario = @UsuId,
				   UpdFechaHora = SYSDATETIME()
			 WHERE enc_id = @EncId
			   AND cpp_nro_cuota = (SELECT MAX(cpp_nro_cuota) FROM dbo.pos_cliente_plan_pagos WHERE enc_id = @EncId);
	END
END;
GO

-- Registra el cliente que no existe (devuelve el existente si ya está).
-- @Nombre en formato SAT "APELLIDO1,APELLIDO2,APELLIDO CASADA,NOMBRE1,NOMBRE2"
-- o libre (queda completo en nombres, p. ej. una empresa).
CREATE OR ALTER PROCEDURE [dbo].[paClienteRegistrarPorNit]
	@Nit		VARCHAR(32),
	@Nombre		VARCHAR(256),
	@Direccion	VARCHAR(128) = NULL,
	@UsuId		INT = NULL,
	@CliId		INT OUTPUT,
	@Nuevo		BIT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @n VARCHAR(32) = dbo.fnNitNormalizar(@Nit);
	IF @n IS NULL
		THROW 53809, 'Indique el NIT del cliente (o C/F).', 1;
	IF dbo.fnNitValido(@n) = 0
	BEGIN
		DECLARE @mensaje NVARCHAR(200) = CONCAT(N'El NIT ', @Nit, N' no es válido: revise el dígito verificador.');
		THROW 53801, @mensaje, 1;
	END

	SET @Nuevo = 0;
	SET @CliId = (SELECT TOP 1 cli_id FROM dbo.pos_cliente WHERE cli_nit_normalizado = @n
				  ORDER BY CASE cli_estado WHEN 'A' THEN 0 ELSE 1 END, cli_id);
	IF @CliId IS NOT NULL
		RETURN;

	SET @Nombre = NULLIF(LTRIM(RTRIM(@Nombre)), '');
	IF @n = 'CF' AND @Nombre IS NULL SET @Nombre = 'CONSUMIDOR FINAL';
	IF @Nombre IS NULL
		THROW 53810, 'Indique el nombre del cliente.', 1;

	-- Nombre SAT separado por comas.
	DECLARE @nombres VARCHAR(64), @apellidos VARCHAR(64);
	IF LEN(@Nombre) - LEN(REPLACE(@Nombre, ',', '')) >= 3
	BEGIN
		DECLARE @partes TABLE (orden INT IDENTITY(1, 1), parte VARCHAR(128));
		DECLARE @resto VARCHAR(256) = @Nombre + ',', @pos INT;
		WHILE LEN(@resto) > 0
		BEGIN
			SET @pos = CHARINDEX(',', @resto);
			INSERT INTO @partes (parte) VALUES (LTRIM(RTRIM(LEFT(@resto, @pos - 1))));
			SET @resto = SUBSTRING(@resto, @pos + 1, 256);
		END
		SELECT @apellidos = LEFT(CONCAT_WS(' ', NULLIF(MAX(CASE orden WHEN 1 THEN parte END), ''), NULLIF(MAX(CASE orden WHEN 2 THEN parte END), ''),
										   'DE ' + NULLIF(MAX(CASE orden WHEN 3 THEN parte END), '')), 64),
			   @nombres = LEFT(CONCAT_WS(' ', NULLIF(MAX(CASE orden WHEN 4 THEN parte END), ''), NULLIF(MAX(CASE orden WHEN 5 THEN parte END), ''),
										 NULLIF(MAX(CASE WHEN orden > 5 THEN parte END), '')), 64)
		FROM @partes;
		IF NULLIF(@nombres, '') IS NULL
			SELECT @nombres = LEFT(@apellidos, 64), @apellidos = NULL;
	END
	ELSE
		SET @nombres = LEFT(@Nombre, 64);

	BEGIN TRY
		BEGIN TRANSACTION;
		-- Siguiente código CLI### disponible.
		DECLARE @siguiente INT = ISNULL((SELECT MAX(TRY_CAST(SUBSTRING(cli_codigo, 4, 20) AS INT)) FROM dbo.pos_cliente WITH (UPDLOCK, HOLDLOCK)
										 WHERE cli_codigo LIKE 'CLI%'), 0) + 1;
		DECLARE @codigo VARCHAR(32) = CONCAT('CLI', RIGHT(CONCAT('000', @siguiente), CASE WHEN @siguiente > 999 THEN LEN(@siguiente) ELSE 3 END));
		DECLARE @nit_grabar VARCHAR(16) = CASE WHEN @n = 'CF' THEN 'CF'
											   WHEN LEN(@n) = 13 THEN @n
											   ELSE CONCAT(LEFT(@n, LEN(@n) - 1), '-', RIGHT(@n, 1)) END;
		EXEC dbo.paClienteInsertar @CliCodigo = @codigo, @CliNombres = @nombres, @CliApellidos = @apellidos,
			@CliDireccion = @Direccion, @CliNit = @nit_grabar, @UsuId = @UsuId, @CliId = @CliId OUTPUT;
		SET @Nuevo = 1;
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Póliza de documento (script 35): las líneas de activo fijo de una compra
-- van a la cuenta de activo de su categoría.
CREATE OR ALTER PROCEDURE [dbo].[paContabilidadAsientoDocumentoGenerar]
	@EncId	INT,
	@UsuId	INT = NULL,
	@AsiId	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @tdo_naturaleza CHAR(1), @afecta_costo CHAR(1), @fecha DATE, @monto_total NUMERIC(12, 2), @origen VARCHAR(20);

	SELECT @tdo_naturaleza = tipo.tdo_naturaleza, @afecta_costo = tipo.afecta_costo,
		   @fecha = enca.enc_fecha_docto, @monto_total = enca.enc_monto_total,
		   @origen = CASE WHEN tipo.tdo_naturaleza = '+' THEN 'COMPRA' ELSE 'VENTA' END
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @EncId;

	IF @fecha IS NULL
		THROW 51303, 'El documento indicado no existe.', 1;

	DECLARE @cuentas TABLE (ccp_codigo VARCHAR(40) PRIMARY KEY, cta_id INT);
	INSERT INTO @cuentas SELECT ccp_codigo, cta_id FROM dbo.cont_cuenta_parametro
	WHERE ccp_codigo IN ('VENTA_CAJA','VENTA_CLIENTES','VENTA_INGRESO','VENTA_IVA_DEBITO','VENTA_COSTO','INVENTARIO',
						 'COMPRA_GASTO','COMPRA_IVA_CREDITO','COMPRA_PROVEEDORES');

	DECLARE @faltante VARCHAR(40) = (SELECT TOP 1 conc.codigo FROM (VALUES ('VENTA_CAJA'),('VENTA_CLIENTES'),('VENTA_INGRESO'),('VENTA_IVA_DEBITO'),
		('VENTA_COSTO'),('INVENTARIO'),('COMPRA_GASTO'),('COMPRA_IVA_CREDITO'),('COMPRA_PROVEEDORES')) conc(codigo)
		LEFT JOIN @cuentas cuen ON cuen.ccp_codigo = conc.codigo WHERE cuen.cta_id IS NULL);
	IF @faltante IS NOT NULL
	BEGIN
		DECLARE @msg_faltante NVARCHAR(200) = CONCAT(N'El concepto contable ', @faltante, N' no tiene cuenta asignada; configúrelo en cont_cuenta_parametro.');
		THROW 51304, @msg_faltante, 1;
	END

	DECLARE @cta_caja INT, @cta_clientes INT, @cta_ingreso INT, @cta_iva_debito INT, @cta_costo INT, @cta_inventario INT,
			@cta_gasto INT, @cta_iva_credito INT, @cta_proveedores INT;
	SELECT @cta_caja = MAX(CASE ccp_codigo WHEN 'VENTA_CAJA' THEN cta_id END),
		   @cta_clientes = MAX(CASE ccp_codigo WHEN 'VENTA_CLIENTES' THEN cta_id END),
		   @cta_ingreso = MAX(CASE ccp_codigo WHEN 'VENTA_INGRESO' THEN cta_id END),
		   @cta_iva_debito = MAX(CASE ccp_codigo WHEN 'VENTA_IVA_DEBITO' THEN cta_id END),
		   @cta_costo = MAX(CASE ccp_codigo WHEN 'VENTA_COSTO' THEN cta_id END),
		   @cta_inventario = MAX(CASE ccp_codigo WHEN 'INVENTARIO' THEN cta_id END),
		   @cta_gasto = MAX(CASE ccp_codigo WHEN 'COMPRA_GASTO' THEN cta_id END),
		   @cta_iva_credito = MAX(CASE ccp_codigo WHEN 'COMPRA_IVA_CREDITO' THEN cta_id END),
		   @cta_proveedores = MAX(CASE ccp_codigo WHEN 'COMPRA_PROVEEDORES' THEN cta_id END)
	FROM @cuentas;

	DECLARE @iva NUMERIC(14, 2) =
		(SELECT ISNULL(SUM((det_sub_total - det_valor_descuento) * ISNULL(det_porc_iva, 0) / 100.0), 0) FROM dbo.inv_documento_det WHERE enc_id = @EncId);

	DECLARE @costo_venta NUMERIC(14, 2);
	SELECT @costo_venta = ISNULL(SUM(deta2.det_cantidad * COALESCE(deta2.det_costo_unitario, prod.pro_costo_unitario)), 0)
	FROM dbo.inv_documento_det deta2
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta2.pro_id
	WHERE deta2.enc_id = @EncId AND prod.pro_maneja_existencia = 1;

	DECLARE @pdo_id INT;
	EXEC dbo.paContabilidadPeriodoObtenerOCrear @Fecha = @fecha, @UsuId = @UsuId, @PdoId = @pdo_id OUTPUT;

	DECLARE @detalle dbo.cont_asiento_det_type;
	DECLARE @ref VARCHAR(10) = CAST(@EncId AS VARCHAR(10));

	IF @tdo_naturaleza = '-' -- venta
	BEGIN
		DECLARE @cobrado NUMERIC(12, 2) = (SELECT ISNULL(SUM(ppd_valor_aplicado), 0) FROM dbo.pos_pago_det WHERE enc_id = @EncId);
		IF @cobrado > @monto_total SET @cobrado = @monto_total;

		IF @cobrado > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_caja, @cobrado, 0, 'Cobro al facturar - documento ' + @ref);
		IF @monto_total - @cobrado > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_clientes, @monto_total - @cobrado, 0, 'Cuentas por cobrar - documento ' + @ref);

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_ingreso, 0, @monto_total - @iva, 'Venta - documento ' + @ref);

		IF @iva > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_iva_debito, 0, @iva, 'IVA débito fiscal - documento ' + @ref);

		IF @costo_venta > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			VALUES (@cta_costo, @costo_venta, 0, 'Costo de venta - documento ' + @ref),
				   (@cta_inventario, 0, @costo_venta, 'Salida de inventario - documento ' + @ref);
	END
	ELSE -- compra
	BEGIN
		-- Las líneas de activo fijo van a la cuenta de su categoría; el resto
		-- (que absorbe el redondeo) a inventario o gasto como antes.
		DECLARE @activos TABLE (cta_id INT PRIMARY KEY, neto NUMERIC(14, 2));
		INSERT INTO @activos (cta_id, neto)
		SELECT cate.cta_id_activo, SUM(deta.det_sub_total - deta.det_valor_descuento)
		FROM dbo.inv_documento_det deta
		INNER JOIN dbo.afi_categoria cate ON cate.afc_id = deta.afc_id
		WHERE deta.enc_id = @EncId
		GROUP BY cate.cta_id_activo;
		DECLARE @neto_activos NUMERIC(14, 2) = ISNULL((SELECT SUM(neto) FROM @activos), 0);

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, neto, 0, 'Compra de activo fijo - documento ' + @ref FROM @activos WHERE neto > 0;

		IF @monto_total - @iva - @neto_activos <> 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
			VALUES (CASE WHEN @afecta_costo = 'S' THEN @cta_inventario ELSE @cta_gasto END, @monto_total - @iva - @neto_activos, 0, 'Compra - documento ' + @ref);

		IF @iva > 0
			INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_iva_credito, @iva, 0, 'IVA crédito fiscal - documento ' + @ref);

		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_proveedores, 0, @monto_total, 'Cuentas por pagar - documento ' + @ref);
	END

	DECLARE @asi_descripcion VARCHAR(256) = 'Generado automáticamente desde documento ' + @ref;

	EXEC dbo.paContabilidadAsientoInsertar
		@AsiFecha = @fecha, @AsiDescripcion = @asi_descripcion, @AsiOrigen = @origen,
		@EncId = @EncId, @PdoId = @pdo_id, @UsuId = @UsuId, @Detalle = @detalle, @AsiId = @AsiId OUTPUT;
END;
GO

------------------------------------------------------------
-- 1. Costo unitario en ventas y compras
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paInventarioExistenciaDocumentoAjustar]
	@EncId		INT,
	@Reversar	BIT = 0,	-- 1 = revertir el efecto (usado al anular un documento)
	@UsuId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @naturaleza_signo INT, @reversar_signo INT = CASE WHEN @Reversar = 1 THEN -1 ELSE 1 END;

	SELECT @naturaleza_signo = CASE WHEN tipo.tdo_naturaleza = '+' THEN 1 ELSE -1 END
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @EncId;

	IF @naturaleza_signo IS NULL
		THROW 51201, 'El documento indicado no existe.', 1;

	-- Al grabar, cada línea con producto guarda su costo unitario: en un
	-- ingreso (compra) es lo pagado sin IVA y neto de descuento; en un egreso
	-- (venta) es el costo promedio del producto en este momento.
	IF @Reversar = 0
		UPDATE deta
		   SET det_costo_unitario = CASE WHEN @naturaleza_signo = 1
										 THEN (deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) / NULLIF(deta.det_cantidad, 0)
										 ELSE prod.pro_costo_unitario END
		FROM dbo.inv_documento_det deta
		INNER JOIN dbo.inv_producto prod WITH (UPDLOCK) ON prod.pro_id = deta.pro_id
		WHERE deta.enc_id = @EncId AND deta.det_cantidad > 0;

	DECLARE @movimientos TABLE (
		[pro_id]	INT				NOT NULL,
		[bod_id]	INT				NOT NULL,
		[cantidad]	NUMERIC(12, 4)	NOT NULL,
		[costo]		NUMERIC(14, 2)	NOT NULL,
		PRIMARY KEY ([pro_id], [bod_id])
	);

	INSERT INTO @movimientos ([pro_id], [bod_id], [cantidad], [costo])
	SELECT deta2.pro_id, deta2.bod_id,
		   SUM(deta2.det_cantidad) * @naturaleza_signo * @reversar_signo,
		   SUM(deta2.det_cantidad * COALESCE(deta2.det_costo_unitario, prod2.pro_costo_unitario)) * @naturaleza_signo * @reversar_signo
	FROM dbo.inv_documento_det deta2
	INNER JOIN dbo.inv_producto prod2 ON prod2.pro_id = deta2.pro_id
	WHERE deta2.enc_id = @EncId
	  AND deta2.pro_id IS NOT NULL
	  AND prod2.pro_maneja_existencia = 1
	GROUP BY deta2.pro_id, deta2.bod_id;

	MERGE dbo.inv_producto_existencia_bodega AS destino
	USING @movimientos AS origen
		ON destino.pro_id = origen.pro_id AND destino.bod_id = origen.bod_id
	WHEN MATCHED THEN
		UPDATE SET existencia = destino.existencia + origen.cantidad,
				   UpdUsuario = @UsuId,
				   UpdFechaHora = SYSDATETIME()
	WHEN NOT MATCHED THEN
		INSERT (bod_id, pro_id, existencia, InsUsuario, InsFechaHora)
		VALUES (origen.bod_id, origen.pro_id, origen.cantidad, @UsuId, SYSDATETIME());

	-- Costo promedio ponderado: (costo acumulado + costo del movimiento) /
	-- (cantidad acumulada + cantidad del movimiento). Sin existencia el
	-- producto conserva su último costo promedio.
	;WITH totales AS (
		SELECT pro_id, SUM(cantidad) AS cantidad, SUM(costo) AS costo
		FROM @movimientos
		GROUP BY pro_id
	)
	UPDATE prod3
	   SET prod3.pro_total_cantidad = prod3.pro_total_cantidad + tota.cantidad,
		   prod3.pro_total_costo = CASE WHEN prod3.pro_total_cantidad + tota.cantidad > 0 THEN prod3.pro_total_costo + tota.costo ELSE 0 END,
		   prod3.pro_costo_unitario = CASE WHEN prod3.pro_total_cantidad + tota.cantidad > 0
									   THEN (prod3.pro_total_costo + tota.costo) / (prod3.pro_total_cantidad + tota.cantidad)
									   ELSE prod3.pro_costo_unitario END,
		   prod3.UpdUsuario = @UsuId,
		   prod3.UpdFechaHora = SYSDATETIME()
	FROM dbo.inv_producto prod3
	INNER JOIN totales tota ON tota.pro_id = prod3.pro_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProveedorPlanPagosGenerar]
	@EncId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @contador INT, @fecha_iteracion DATE, @valor_cuota NUMERIC(13, 2),
			@prv_id INT, @numero_cuotas INT, @fecha_primer_pago DATE,
			@monto_total NUMERIC(13, 2), @monto_enganche NUMERIC(13, 2);

	SELECT @prv_id = prv_id, @numero_cuotas = enc_numero_cuotas,
		   @fecha_primer_pago = enc_fecha_primer_pago, @monto_total = enc_monto_total,
		   @monto_enganche = enc_monto_enganche
	FROM dbo.inv_documento_enc
	WHERE enc_id = @EncId;

	IF @fecha_primer_pago IS NOT NULL AND @monto_total IS NOT NULL AND @numero_cuotas IS NOT NULL AND @numero_cuotas > 0
	BEGIN
		SET @contador = 1;
		SET @valor_cuota = (ISNULL(@monto_total, 0) - ISNULL(@monto_enganche, 0)) / @numero_cuotas;
		SET @fecha_iteracion = @fecha_primer_pago;

		WHILE @contador <= @numero_cuotas
		BEGIN
			INSERT INTO dbo.inv_proveedor_plan_pago
				(ppg_nro_pago, ppg_fecha_pago, ppg_valor_pago, enc_id, prv_id, ppg_estado,
				 InsUsuario, InsFechaHora)
			VALUES
				(@contador, @fecha_iteracion, @valor_cuota, @EncId, @prv_id, 'P',
				 @UsuId, SYSDATETIME());

			SET @contador = @contador + 1;
			SET @fecha_iteracion = DATEADD(MONTH, 1, @fecha_iteracion);
			IF DATEPART(dw, @fecha_iteracion) = 7
				SET @fecha_iteracion = DATEADD(DAY, 1, @fecha_iteracion);
		END

		DECLARE @monto_cuotas NUMERIC(12, 2), @monto_restante NUMERIC(12, 2);

		SELECT @monto_cuotas = SUM(ppg_valor_pago) FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @EncId;
		SET @monto_restante = (ISNULL(@monto_total, 0) - ISNULL(@monto_enganche, 0)) - ISNULL(@monto_cuotas, 0);

		IF @monto_restante <> 0
			UPDATE dbo.inv_proveedor_plan_pago
			   SET ppg_valor_pago = ppg_valor_pago + @monto_restante,
				   UpdUsuario = @UsuId,
				   UpdFechaHora = SYSDATETIME()
			 WHERE enc_id = @EncId
			   AND ppg_nro_pago = (SELECT MAX(ppg_nro_pago) FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @EncId);
	END
END;
GO

-- Compra (script 53) con la lista opcional de líneas de activo fijo.
CREATE OR ALTER PROCEDURE [dbo].[paCompraDocumentoCrear]
	@EncFechaDocto				DATE,
	@EncNumeroAutorizacion		VARCHAR(64) = NULL,
	@EncSerieDocto				VARCHAR(32) = NULL,
	@EncNumeroDocto				VARCHAR(32) = NULL,
	@PrvId							INT,
	@PrvEncNombresProveedor		VARCHAR(128) = NULL,
	@PrvEncApellidosProveedor	VARCHAR(128) = NULL,
	@PrvNit						VARCHAR(16) = NULL,
	@TdoId							INT,
	@EncFechaPrimerPago			DATE = NULL,
	@EncMontoEnganche				NUMERIC(12, 2) = 0,
	@EncNumeroCuotas				INT = 1,
	@EncValorDescuento			NUMERIC(13, 2) = 0,
	@MonId							INT = NULL,
	@UsuId							INT = NULL,
	@Detalle						dbo.compra_det_type READONLY,
	@EncId							INT OUTPUT,
	-- Líneas que son activo fijo (det_item → categoría y centro de costo).
	@Activos						dbo.compra_activo_type READONLY
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 51411, 'La compra debe tener al menos una línea de detalle.', 1;

	IF @MonId IS NULL
		SET @MonId = dbo.fnMonedaLocal();

	IF EXISTS (SELECT 1 FROM @Activos acti LEFT JOIN @Detalle deta ON deta.det_item = acti.det_item WHERE deta.det_item IS NULL)
		THROW 55221, 'Una línea marcada como activo fijo no existe en el detalle de la compra.', 1;
	IF EXISTS (SELECT 1 FROM @Activos acti LEFT JOIN dbo.afi_categoria cate ON cate.afc_id = acti.afc_id AND cate.afc_estado = 'A' WHERE cate.afc_id IS NULL)
		THROW 55222, 'Elija una categoría de activo fijo activa para cada línea de activo.', 1;
	IF EXISTS (SELECT 1 FROM @Activos acti INNER JOIN @Detalle deta ON deta.det_item = acti.det_item WHERE deta.pro_id IS NOT NULL)
		THROW 55223, 'Una línea de activo fijo no lleva producto de inventario: escriba la descripción del bien.', 1;

	-- El total es el de la factura del proveedor: costo unitario con IVA
	-- redondeado a centavos × cantidad, menos el descuento con IVA (igual que
	-- en paVentaFacturaCrear desde el script 52). El asiento sigue
	-- cuadrado: inventario o gasto = total - IVA.
	DECLARE @monto_total NUMERIC(12, 2) = (
		SELECT SUM(ROUND(ROUND(det_precio_unitario * (1 + ISNULL(det_porc_iva, 0) / 100.0), 2) * det_cantidad, 2)
				 - ROUND(det_valor_descuento * (1 + ISNULL(det_porc_iva, 0) / 100.0), 2))
		FROM @Detalle
	);

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.inv_documento_enc
			(enc_fecha_docto, enc_numero_autorizacion, enc_serie_docto, enc_numero_docto,
			 prv_id, prv_enc_nombres_proveedor, prv_enc_apellidos_proveedor, prv_nit, tdo_id,
			 enc_fecha_primer_pago, enc_monto_enganche, enc_numero_cuotas, enc_monto_total,
			 enc_valor_descuento, mon_id, usu_id_creacion,
			 InsUsuario, InsFechaHora)
		VALUES
			(@EncFechaDocto, @EncNumeroAutorizacion, @EncSerieDocto, @EncNumeroDocto,
			 @PrvId, @PrvEncNombresProveedor, @PrvEncApellidosProveedor, @PrvNit, @TdoId,
			 @EncFechaPrimerPago, @EncMontoEnganche, @EncNumeroCuotas, @monto_total,
			 @EncValorDescuento, @MonId, @UsuId,
			 @UsuId, SYSDATETIME());

		SET @EncId = SCOPE_IDENTITY();

		INSERT INTO dbo.inv_documento_det
			(enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			 det_precio_unitario, det_valor_descuento, det_sub_total, det_porc_iva, bod_id, pro_id,
			 InsUsuario, InsFechaHora)
		SELECT
			@EncId, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			det_precio_unitario, det_valor_descuento, det_sub_total, det_porc_iva, bod_id, pro_id,
			@UsuId, SYSDATETIME()
		FROM @Detalle;

		UPDATE deta SET afc_id = acti.afc_id
		FROM dbo.inv_documento_det deta INNER JOIN @Activos acti ON acti.det_item = deta.det_item
		WHERE deta.enc_id = @EncId;

		EXEC dbo.paProveedorPlanPagosGenerar @EncId = @EncId, @UsuId = @UsuId;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'G',
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId;

		EXEC dbo.paInventarioExistenciaDocumentoAjustar @EncId = @EncId, @UsuId = @UsuId;

		DECLARE @asi_id INT;
		EXEC dbo.paContabilidadAsientoDocumentoGenerar @EncId = @EncId, @UsuId = @UsuId, @AsiId = @asi_id OUTPUT;

		IF EXISTS (SELECT 1 FROM @Activos)
			EXEC dbo.paActivoFijoCrearDesdeCompra @EncId = @EncId, @Departamentos = @Activos, @UsuId = @UsuId;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

-- Póliza de ajuste por una línea del banco que no está en libros: débito del
-- banco = Debe @CtaId / Haber banco; crédito = Debe banco / Haber @CtaId.
-- Queda conciliada con esa línea.
CREATE OR ALTER PROCEDURE [dbo].[paConciliacionAjuste]
	@BcnId			INT,
	@BexId			INT,
	@CtaId			INT = NULL,
	@Descripcion	VARCHAR(256) = NULL,
	@UsuId			INT = NULL,
	@AsiId			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @AsiId = NULL;
	DECLARE @bcb_id INT, @fecha DATE, @debito NUMERIC(14, 2), @credito NUMERIC(14, 2), @texto VARCHAR(250);
	SELECT @bcb_id = conc.bcb_id, @fecha = extr.bex_fecha, @debito = extr.bex_debito, @credito = extr.bex_credito, @texto = extr.bex_descripcion
	FROM dbo.bco_extracto extr INNER JOIN dbo.bco_conciliacion conc ON conc.bcn_id = extr.bcn_id AND conc.bcn_estado = 'B'
	WHERE extr.bex_id = @BexId AND extr.bcn_id = @BcnId AND extr.asd_id IS NULL;
	IF @bcb_id IS NULL
		THROW 55413, 'La línea del estado de cuenta no existe, ya está conciliada o la conciliación está cerrada.', 1;
	SET @CtaId = ISNULL(@CtaId, (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = IIF(@debito > 0, 'CONCILIACION_GASTO', 'CONCILIACION_INGRESO')));
	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId AND cta_acepta_movimiento = 1 AND cta_estado = 'A')
		THROW 55416, 'Elija la cuenta contable del ajuste (de detalle y activa).', 1;
	DECLARE @cta_banco INT = IIF(@debito > 0, dbo.fnBcoCuentaContable(@bcb_id),
								 ISNULL((SELECT cta_id_cargo FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @bcb_id), dbo.fnBcoCuentaContable(@bcb_id)));
	DECLARE @monto NUMERIC(14, 2) = IIF(@debito > 0, @debito, @credito);
	SET @Descripcion = LEFT(ISNULL(NULLIF(LTRIM(RTRIM(@Descripcion)), ''), CONCAT('Conciliación bancaria: ', ISNULL(@texto, IIF(@debito > 0, 'cargo del banco', 'crédito del banco')))), 256);

	BEGIN TRY
		BEGIN TRANSACTION;
			DECLARE @partida dbo.cont_asiento_det_cc_type;
			INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
			VALUES (IIF(@debito > 0, @CtaId, @cta_banco), @monto, 0, @Descripcion), (IIF(@debito > 0, @cta_banco, @CtaId), 0, @monto, @Descripcion);
			EXEC dbo.paContabilidadAsientoInsertarCc @asi_fecha = @fecha, @asi_descripcion = @Descripcion, @asi_origen = 'CONCILIACION',
				@asi_origen_id = @BcnId, @usu_id = @UsuId, @detalle = @partida, @asi_id = @AsiId OUTPUT;
			DECLARE @asd_id INT = (SELECT asd_id FROM dbo.cont_asiento_det WHERE asi_id = @AsiId AND cta_id = @cta_banco);
			UPDATE dbo.bco_extracto SET asd_id = @asd_id, bex_forma = 'J' WHERE bex_id = @BexId;
			INSERT INTO dbo.bco_conciliacion_libro (bcn_id, asd_id, bex_id) VALUES (@BcnId, @asd_id, @BexId);
		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paContabilidadSaldosInicialesProcesar]
	@Fecha			DATE,
	@Filas			dbo.cont_saldo_inicial_type READONLY,
	@SoloValidar	BIT = 1,
	@Reemplazar		BIT = 0,	-- anula la partida de apertura vigente y graba la nueva
	@UsuId			INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- Las filas sin montos se ignoran (son las cuentas que el contador dejó vacías).
	DECLARE @datos TABLE (Fila INT PRIMARY KEY, Codigo VARCHAR(20), cta_id INT, acepta BIT, estado CHAR(1), naturaleza CHAR(1), nombre VARCHAR(128),
						  Debe DECIMAL(14, 2), Haber DECIMAL(14, 2));
	INSERT INTO @datos
	SELECT fila.Fila, LTRIM(RTRIM(fila.Codigo)), cuen.cta_id, cuen.cta_acepta_movimiento, cuen.cta_estado, cuen.cta_naturaleza, cuen.cta_nombre,
		   ISNULL(fila.Debe, 0), ISNULL(fila.Haber, 0)
	FROM @Filas fila
	LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_codigo = LTRIM(RTRIM(fila.Codigo))
	WHERE ISNULL(fila.Debe, 0) <> 0 OR ISNULL(fila.Haber, 0) <> 0;

	DECLARE @mensajes TABLE (Fila INT, Tipo CHAR(1), Mensaje NVARCHAR(400));
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT Fila, 'E', Mensaje FROM (
		SELECT Fila, CASE
			WHEN cta_id IS NULL THEN CONCAT(N'La cuenta "', Codigo, N'" no existe en la nomenclatura.')
			WHEN estado <> 'A' THEN CONCAT(N'La cuenta ', Codigo, N' está inactiva.')
			WHEN acepta = 0 THEN CONCAT(N'La cuenta ', Codigo, N' es de agrupación: el saldo va en sus cuentas de movimiento.')
			WHEN Debe < 0 OR Haber < 0 THEN CONCAT(N'La cuenta ', Codigo, N' tiene un monto negativo; use la otra columna.')
			WHEN Debe > 0 AND Haber > 0 THEN CONCAT(N'La cuenta ', Codigo, N' tiene Debe y Haber: deje solo su saldo neto.')
		END AS Mensaje FROM @datos) vali
	WHERE Mensaje IS NOT NULL;

	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT dato.Fila, 'E', CONCAT(N'La cuenta ', dato.Codigo, N' se repite en el archivo.')
	FROM @datos dato
	WHERE dato.cta_id IS NOT NULL AND EXISTS (SELECT 1 FROM @datos otro WHERE otro.cta_id = dato.cta_id AND otro.Fila < dato.Fila);

	-- Saldo contrario a la naturaleza de la cuenta: se permite, pero se avisa.
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT Fila, 'A', CONCAT(N'La cuenta ', Codigo, N' ', nombre, N' es de naturaleza ', CASE naturaleza WHEN 'D' THEN N'deudora' ELSE N'acreedora' END,
							 N' y queda con saldo ', CASE WHEN Debe > 0 THEN N'deudor' ELSE N'acreedor' END, N'.')
	FROM @datos
	WHERE cta_id IS NOT NULL AND ((naturaleza = 'D' AND Haber > 0) OR (naturaleza = 'H' AND Debe > 0));

	DECLARE @debe DECIMAL(14, 2) = (SELECT ISNULL(SUM(Debe), 0) FROM @datos),
			@haber DECIMAL(14, 2) = (SELECT ISNULL(SUM(Haber), 0) FROM @datos);
	IF NOT EXISTS (SELECT 1 FROM @datos)
		INSERT INTO @mensajes VALUES (0, 'E', N'El archivo no tiene saldos: llene la columna Debe o Haber de las cuentas de movimiento.');
	ELSE IF @debe <> @haber
		INSERT INTO @mensajes VALUES (0, 'E', CONCAT(N'La partida no cuadra: Debe Q', FORMAT(@debe, 'N2'), N', Haber Q', FORMAT(@haber, 'N2'),
													 N', diferencia Q', FORMAT(ABS(@debe - @haber), 'N2'), N'.'));

	DECLARE @apertura INT = (SELECT TOP 1 asi_id FROM dbo.cont_asiento_enc WHERE asi_origen = 'APERTURA' AND asi_estado = 'A' ORDER BY asi_id DESC);
	IF @apertura IS NOT NULL AND @Reemplazar = 0
		INSERT INTO @mensajes VALUES (0, 'E', N'Ya existe una partida de apertura vigente; marque "Reemplazar" para anularla y grabar la nueva.');
	ELSE IF @apertura IS NOT NULL
		INSERT INTO @mensajes VALUES (0, 'A', CONCAT(N'Se anulará la partida de apertura vigente (#', @apertura, N').'));

	-- La cuenta de inventario contra el inventario inicial cargado.
	DECLARE @cta_inventario INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'INVENTARIO');
	DECLARE @inv_partida DECIMAL(14, 2) = (SELECT ISNULL(SUM(Debe - Haber), 0) FROM @datos WHERE cta_id = @cta_inventario);
	DECLARE @inv_cargado DECIMAL(14, 2) = (SELECT ISNULL(SUM(enca.enc_monto_total), 0) FROM dbo.inv_documento_enc enca
										   INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_codigo = 'INVI'
										   WHERE enca.enc_estado = 'G');
	IF @inv_partida <> @inv_cargado
		INSERT INTO @mensajes VALUES (0, 'A', CONCAT(N'La cuenta de inventario (', (SELECT cta_codigo FROM dbo.cont_cuenta_contable WHERE cta_id = @cta_inventario),
			N') queda en Q', FORMAT(@inv_partida, 'N2'), N' y el inventario inicial cargado vale Q', FORMAT(@inv_cargado, 'N2'),
			N': diferencia Q', FORMAT(ABS(@inv_partida - @inv_cargado), 'N2'), N'.'));

	DECLARE @asi_id INT;
	IF @SoloValidar = 0 AND NOT EXISTS (SELECT 1 FROM @mensajes WHERE Tipo = 'E')
	BEGIN
		DECLARE @partida dbo.cont_asiento_det_type;
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT cta_id, Debe, Haber, 'Saldo inicial' FROM @datos ORDER BY Codigo;

		BEGIN TRY
			BEGIN TRANSACTION;
			IF @apertura IS NOT NULL
				UPDATE dbo.cont_asiento_enc SET asi_estado = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE asi_id = @apertura;
			DECLARE @descripcion VARCHAR(256) = CONCAT('Partida de apertura: saldos iniciales al ', FORMAT(@Fecha, 'dd/MM/yyyy'));
			EXEC dbo.paContabilidadAsientoInsertar @AsiFecha = @Fecha, @AsiDescripcion = @descripcion, @AsiOrigen = 'APERTURA',
				@UsuId = @UsuId, @Detalle = @partida, @AsiId = @asi_id OUTPUT;
			COMMIT TRANSACTION;
		END TRY
		BEGIN CATCH
			IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
			THROW;
		END CATCH
	END

	SELECT Fila, Tipo, Mensaje FROM @mensajes ORDER BY Fila, Tipo DESC;

	SELECT (SELECT COUNT(*) FROM @datos) AS Cuentas, @debe AS TotalDebe, @haber AS TotalHaber,
		   @inv_partida AS InventarioPartida, @inv_cargado AS InventarioCargado, @asi_id AS AsiId,
		   CAST(CASE WHEN @asi_id IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS Grabado;
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

------------------------------------------------------------
-- 3. Grabar, consultar y anular
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCotizacionGuardar]
	@Fecha			DATE,
	@BodId			INT,
	@MonId			INT = NULL,
	@CliId			INT = NULL,
	@Nit			VARCHAR(16) = NULL,
	@Nombre			VARCHAR(256) = NULL,
	@Direccion		VARCHAR(256) = NULL,
	@Telefono		VARCHAR(64) = NULL,
	@Correo			VARCHAR(128) = NULL,
	@PveId			INT = NULL,
	@Observaciones	VARCHAR(500) = NULL,
	@UsuId			INT = NULL,
	@Detalle		dbo.cotizacion_det_type READONLY,
	@CotId			INT OUTPUT,
	@Numero			VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SELECT @CotId = NULL, @Numero = NULL;

	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 54401, 'La cotización debe tener al menos una línea.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE bien_o_servicio NOT IN ('B', 'S'))
		THROW 54402, 'Cada línea debe ser bien (B) o servicio (S).', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE bien_o_servicio = 'B' AND pro_id IS NULL)
		THROW 54403, 'Una línea de bien debe indicar el producto.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE LTRIM(RTRIM(descripcion)) = '')
		THROW 54404, 'Toda línea debe tener descripción.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE cantidad <= 0 OR precio_unitario < 0 OR valor_descuento < 0
				OR valor_descuento > ROUND(cantidad * precio_unitario, 2))
		THROW 54405, 'La cantidad debe ser mayor a cero, el precio no negativo y el descuento no mayor que el valor de la línea.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle deta INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
			   WHERE prod.pro_maneja_existencia = 1 AND deta.cantidad <> ROUND(deta.cantidad, 0))
		THROW 54406, 'Los productos con existencia se cotizan en cantidades enteras.', 1;

	DECLARE @suc_id INT, @cia_id INT, @vigencia INT, @iva NUMERIC(8, 2);
	SELECT @suc_id = bode.suc_id, @cia_id = sucu.cia_id, @vigencia = comp.cia_cotizacion_vigencia_dias, @iva = comp.cia_porc_iva
	FROM dbo.inv_bodega bode
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	WHERE bode.bod_id = @BodId AND bode.bod_estado = 'A';
	IF @suc_id IS NULL
		THROW 54407, 'Elija una bodega activa.', 1;

	-- Datos del cliente: los de su ficha si no se escribieron otros.
	IF @CliId IS NOT NULL
		SELECT @Nombre = ISNULL(NULLIF(LTRIM(RTRIM(@Nombre)), ''), LTRIM(RTRIM(CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos)))),
			   @Nit = ISNULL(NULLIF(LTRIM(RTRIM(@Nit)), ''), clie.cli_nit),
			   @Direccion = ISNULL(NULLIF(LTRIM(RTRIM(@Direccion)), ''), clie.cli_direccion),
			   @Telefono = ISNULL(NULLIF(LTRIM(RTRIM(@Telefono)), ''), COALESCE(clie.cli_telefono_celular, clie.cli_telefono_casa, clie.cli_telefono_trabajo)),
			   @Correo = ISNULL(NULLIF(LTRIM(RTRIM(@Correo)), ''), clie.cli_email)
		FROM dbo.pos_cliente clie WHERE clie.cli_id = @CliId;
	IF ISNULL(LTRIM(RTRIM(@Nombre)), '') = ''
		THROW 54408, 'Indique el cliente o el nombre a quien se dirige la cotización.', 1;

	SET @MonId = ISNULL(@MonId, dbo.fnMonedaLocal());
	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));

	DECLARE @descuento NUMERIC(14, 2) = (SELECT SUM(valor_descuento) FROM @Detalle),
			@total NUMERIC(14, 2) = (SELECT SUM(ROUND(cantidad * precio_unitario, 2) - valor_descuento) FROM @Detalle);

	BEGIN TRANSACTION;
	DECLARE @siguiente INT = ISNULL((SELECT MAX(CAST(SUBSTRING(cot_numero, 5, 12) AS INT)) FROM dbo.ven_cotizacion_enc WITH (UPDLOCK, HOLDLOCK)), 0) + 1;
	INSERT INTO dbo.ven_cotizacion_enc
		(cot_numero, cot_fecha, cot_vigencia_dias, cot_fecha_vencimiento, suc_id, bod_id, mon_id, cli_id, cot_nit, cot_nombre,
		 cot_direccion, cot_telefono, cot_correo, pve_id, cot_porc_iva, cot_descuento, cot_total, cot_observaciones, cot_estado,
		 usu_id, InsUsuario, InsFechaHora)
	VALUES
		(CONCAT('COT-', RIGHT(CONCAT('000000', @siguiente), 6)), @Fecha, @vigencia, DATEADD(DAY, @vigencia, @Fecha), @suc_id, @BodId,
		 @MonId, @CliId, NULLIF(UPPER(LTRIM(RTRIM(@Nit))), ''), LTRIM(RTRIM(@Nombre)), NULLIF(LTRIM(RTRIM(@Direccion)), ''),
		 NULLIF(LTRIM(RTRIM(@Telefono)), ''), NULLIF(LTRIM(RTRIM(@Correo)), ''), @PveId, @iva, @descuento, @total,
		 NULLIF(LTRIM(RTRIM(@Observaciones)), ''), 'V', @UsuId, @UsuId, SYSDATETIME());
	SET @CotId = SCOPE_IDENTITY();

	INSERT INTO dbo.ven_cotizacion_det
		(cot_id, cod_item, cod_bien_o_servicio, pro_id, ppr_id, ume_id, cod_descripcion, cod_cantidad, cod_precio_unitario,
		 cod_valor_descuento, cod_total)
	SELECT @CotId, ROW_NUMBER() OVER (ORDER BY deta.item), deta.bien_o_servicio, deta.pro_id, deta.ppr_id,
		   COALESCE(deta.ume_id, prod.ume_id), LTRIM(RTRIM(deta.descripcion)), deta.cantidad, deta.precio_unitario,
		   deta.valor_descuento, ROUND(deta.cantidad * deta.precio_unitario, 2) - deta.valor_descuento
	FROM @Detalle deta
	LEFT JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id;

	SELECT @Numero = cot_numero FROM dbo.ven_cotizacion_enc WHERE cot_id = @CotId;
	COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaBancariaActualizar]
	@BcbId				INT,
	@BcbDescripcion	VARCHAR(64) = NULL,
	@GefId				INT,
	@UsuId				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId)
		THROW 51052, 'La cuenta bancaria indicada no existe.', 1;

	UPDATE dbo.bco_cuenta_bancaria
	   SET bcb_descripcion = @BcbDescripcion,
		   gef_id = @GefId,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE bcb_id = @BcbId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaBancariaConsultar]
	@BcbEstado CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT cuba.bcb_id, cuba.bcb_numero_cuenta, cuba.bcb_descripcion, cuba.gef_id, enti.gef_descripcion, cuba.bcb_estado
	FROM dbo.bco_cuenta_bancaria cuba
	INNER JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuba.gef_id
	WHERE (@BcbEstado IS NULL OR cuba.bcb_estado = @BcbEstado)
	ORDER BY cuba.bcb_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaBancariaConsultarPorId]
	@BcbId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaBancariaEliminar]
	@BcbId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId)
		THROW 51052, 'La cuenta bancaria indicada no existe.', 1;

	UPDATE dbo.bco_cuenta_bancaria
	   SET bcb_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE bcb_id = @BcbId;
END;
GO

------------------------------------------------------------
-- bco_cuenta_bancaria
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCuentaBancariaInsertar]
	@BcbNumeroCuenta	VARCHAR(16),
	@BcbDescripcion	VARCHAR(64) = NULL,
	@GefId				INT,
	@UsuId				INT = NULL,
	@BcbId				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_numero_cuenta = @BcbNumeroCuenta)
		THROW 51051, 'Ya existe una cuenta bancaria con ese número.', 1;

	INSERT INTO dbo.bco_cuenta_bancaria (bcb_numero_cuenta, bcb_descripcion, gef_id, InsUsuario, InsFechaHora)
	VALUES (@BcbNumeroCuenta, @BcbDescripcion, @GefId, @UsuId, SYSDATETIME());

	SET @BcbId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableActualizar]
	@CtaId					INT,
	@CtaNombre				VARCHAR(128),
	@CtaAceptaMovimiento	BIT,
	@UsuId					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId)
		THROW 51062, 'La cuenta contable indicada no existe.', 1;

	UPDATE dbo.cont_cuenta_contable
	   SET cta_nombre = @CtaNombre,
		   cta_acepta_movimiento = @CtaAceptaMovimiento,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE cta_id = @CtaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableConsultar]
	@CtaTipo	CHAR(1) = NULL,
	@CtaEstado	CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT cta_id, cta_codigo, cta_nombre, cta_tipo, cta_naturaleza,
		   cta_acepta_movimiento, cta_id_padre, cta_nivel, cta_estado
	FROM dbo.cont_cuenta_contable
	WHERE (@CtaTipo IS NULL OR cta_tipo = @CtaTipo)
	  AND (@CtaEstado IS NULL OR cta_estado = @CtaEstado)
	ORDER BY cta_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableConsultarPorId]
	@CtaId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableEliminar]
	@CtaId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId)
		THROW 51062, 'La cuenta contable indicada no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.cont_asiento_det WHERE cta_id = @CtaId)
		THROW 51063, 'No se puede inactivar: la cuenta ya tiene movimientos contables.', 1;

	UPDATE dbo.cont_cuenta_contable
	   SET cta_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE cta_id = @CtaId;
END;
GO

------------------------------------------------------------
-- cont_cuenta_contable
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableInsertar]
	@CtaCodigo				VARCHAR(20),
	@CtaNombre				VARCHAR(128),
	@CtaTipo				CHAR(1),
	@CtaNaturaleza			CHAR(1),
	@CtaAceptaMovimiento	BIT = 1,
	@CtaIdPadre			INT = NULL,
	@UsuId					INT = NULL,
	@CtaId					INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_codigo = @CtaCodigo)
		THROW 51061, 'Ya existe una cuenta contable con ese código.', 1;

	DECLARE @nivel INT = 1;
	IF @CtaIdPadre IS NOT NULL
		SELECT @nivel = cta_nivel + 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaIdPadre;

	INSERT INTO dbo.cont_cuenta_contable
		(cta_codigo, cta_nombre, cta_tipo, cta_naturaleza, cta_acepta_movimiento, cta_id_padre, cta_nivel, InsUsuario, InsFechaHora)
	VALUES
		(@CtaCodigo, @CtaNombre, @CtaTipo, @CtaNaturaleza, @CtaAceptaMovimiento, @CtaIdPadre, @nivel, @UsuId, SYSDATETIME());

	SET @CtaId = SCOPE_IDENTITY();
END;
GO

------------------------------------------------------------
-- 3. Cheque por varias cuotas (de una o varias facturas)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCxpChequeEmitir]
	@PrvId		INT,
	@CbcId		INT,
	@Numero		VARCHAR(16) = NULL,		-- vacío = siguiente de la chequera
	@BmpId		INT = NULL,
	@Concepto	VARCHAR(250) = NULL,	-- vacío = "Pago factura(s) ..." automático
	@Cuotas		dbo.cxp_pago_cuota_type READONLY,
	@UsuId		INT = NULL,
	@BceId		INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @beneficiario VARCHAR(150) = (SELECT prv_nombre_comercial FROM dbo.inv_proveedor WHERE prv_id = @PrvId);
	IF @beneficiario IS NULL
		THROW 53701, 'El proveedor indicado no existe.', 1;
	IF NOT EXISTS (SELECT 1 FROM @Cuotas)
		THROW 53702, 'Seleccione al menos una cuota a pagar.', 1;
	IF EXISTS (SELECT 1 FROM @Cuotas WHERE monto <= 0)
		THROW 53703, 'Cada cuota seleccionada debe llevar un monto mayor a cero.', 1;

	-- Chequera activa, número dentro del rango y sin repetir (vacío = siguiente).
	EXEC dbo.paBcoChequeValidarNumero @CbcId = @CbcId, @Numero = @Numero OUTPUT;

	DECLARE @cta_proveedores INT, @cta_bancos INT = dbo.fnBcoCuentaContable((SELECT bcb_id FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @CbcId));
	EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_PROVEEDORES', @CtaId = @cta_proveedores OUTPUT;
	IF @cta_bancos IS NULL
		EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_bancos OUTPUT;

	DECLARE @hoy DATE = CAST(GETDATE() AS DATE), @mensaje NVARCHAR(300);
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
			THROW 53704, 'Una de las cuotas no existe o no es de este proveedor.', 1;
		IF EXISTS (SELECT 1 FROM @lineas WHERE enc_estado <> 'G')
		BEGIN
			SELECT TOP 1 @mensaje = CONCAT(N'La compra ', documento, N' está anulada; quítela del pago.') FROM @lineas WHERE enc_estado <> 'G';
			THROW 53705, @mensaje, 1;
		END
		IF EXISTS (SELECT 1 FROM @lineas WHERE monto > programado - pagado)
		BEGIN
			SELECT TOP 1 @mensaje = CONCAT(N'El pago a la cuota ', nro_pago, N' de ', documento, N' (Q', FORMAT(monto, 'N2'),
					N') supera su saldo (Q', FORMAT(programado - pagado, 'N2'), N').')
			FROM @lineas WHERE monto > programado - pagado ORDER BY fecha_pago, nro_pago;
			THROW 53706, @mensaje, 1;
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

		INSERT INTO dbo.bco_cheque_emitido_enc
			(cbc_id, bce_fecha_emision, usu_id, bce_numero_cheque, bce_observaciones, bce_documento_ref, bce_valor, bmp_id,
			 bce_tipo, bce_beneficiario, InsUsuario, InsFechaHora)
		VALUES
			(@CbcId, @hoy, @UsuId, @Numero, @Concepto, CAST(@enc_unico AS VARCHAR(16)), @total, @BmpId,
			 'P', @beneficiario, @UsuId, SYSDATETIME());

		SET @BceId = SCOPE_IDENTITY();

		INSERT INTO dbo.bco_cheque_emitido_det (bce_id, bmp_id, enc_id, ppg_id, ced_valor, ced_abono_cancelacion, InsUsuario, InsFechaHora)
		SELECT @BceId, @BmpId, enc_id, ppg_id, monto,
			   CASE WHEN pagado + monto >= programado THEN 'C' ELSE 'A' END,
			   @UsuId, SYSDATETIME()
		FROM @lineas
		ORDER BY fecha_pago, fecha_docto, enc_id, nro_pago;

		UPDATE cuot
		   SET ppg_valor_real_pago = line.pagado + line.monto,
			   ppg_fecha_real_pago = @hoy,
			   ppg_numero_cheque = @Numero,
			   cbc_id = @CbcId,
			   ppg_estado = CASE WHEN line.pagado + line.monto >= line.programado THEN 'A' ELSE cuot.ppg_estado END,
			   UpdUsuario = @UsuId,
			   UpdFechaHora = SYSDATETIME()
		FROM dbo.inv_proveedor_plan_pago cuot
		INNER JOIN @lineas line ON line.ppg_id = cuot.ppg_id;

		-- Póliza: una línea al Debe por factura y el total al Haber del banco.
		DECLARE @asi_id INT, @partida dbo.cont_asiento_det_type;
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		SELECT @cta_proveedores, SUM(monto), 0, LEFT(CONCAT('Pago doc. ', MIN(documento), ' - cheque ', @Numero), 256)
		FROM @lineas
		GROUP BY enc_id;
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_bancos, 0, @total, 'Pago a proveedor - cheque ' + @Numero);

		DECLARE @asi_descripcion VARCHAR(256) = LEFT(CONCAT('Pago a proveedor con cheque ', @Numero,
			CASE WHEN @facturas > 1 THEN CONCAT(' (', @facturas, ' facturas)') END), 256);
		EXEC dbo.paContabilidadAsientoInsertar
			@AsiFecha = @hoy, @AsiDescripcion = @asi_descripcion,
			@AsiOrigen = 'PAGO_PROVEEDOR', @AsiOrigenId = @BceId, @EncId = @enc_unico,
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
-- 4. Factura desde una cotización (paVentaFacturaCrear con @cot_id)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paVentaFacturaCrear]
	@EncFechaDocto			DATE,
	@EncNumeroAutorizacion	VARCHAR(64) = NULL,
	@EncSerieDocto			VARCHAR(32) = NULL,
	@EncNumeroDocto			VARCHAR(32) = NULL,
	@CliId						INT,
	@EncNombresCliente		VARCHAR(128) = NULL,
	@EncApellidosCliente		VARCHAR(128) = NULL,
	@CliNit					VARCHAR(16) = NULL,
	@TdoId						INT,
	@PveId						INT = NULL,
	@EncFechaPrimerPago		DATE = NULL,
	@EncMontoEnganche			NUMERIC(12, 2) = 0,
	@EncNumeroCuotas			INT = 1,
	@EncValorDescuento		NUMERIC(13, 2) = 0,
	@EncDireccionCliente		VARCHAR(256) = NULL,
	@MonId						INT = NULL,
	@UsuId						INT = NULL,
	@Detalle					dbo.factura_det_type READONLY,
	@PcaId						INT = NULL,				-- apertura de caja activa donde se recibe el pago inicial
	@FormasPago				dbo.pago_forma_type READONLY,	-- pago de contado, o enganche si es a crédito; pasar tabla vacía si no aplica
	@EncId						INT OUTPUT,
	@EncNumeroUnico			VARCHAR(16) OUTPUT,
	@CotId						INT = NULL				-- cotización que se convierte en esta factura (script 52)
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 51401, 'La factura debe tener al menos una línea de detalle.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE det_bien_o_servicio NOT IN ('B', 'S'))
		THROW 53031, 'Cada línea debe ser bien (B) o servicio (S).', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE det_bien_o_servicio = 'B' AND pro_id IS NULL)
		THROW 53032, 'Una línea de bien debe indicar el producto.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE LTRIM(RTRIM(det_descripcion)) = '')
		THROW 53033, 'Toda línea debe tener descripción; en un servicio, describa el servicio prestado.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE det_cantidad <= 0 OR det_precio_unitario < 0)
		THROW 53034, 'La cantidad debe ser mayor a cero y el precio no puede ser negativo.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle deta INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
			   WHERE prod.pro_maneja_existencia = 1 AND deta.det_cantidad <> ROUND(deta.det_cantidad, 0))
		THROW 53035, 'Los productos con existencia se venden en cantidades enteras.', 1;

	IF @MonId IS NULL
		SET @MonId = dbo.fnMonedaLocal();

	IF EXISTS (
		SELECT 1
		FROM (SELECT pro_id, bod_id, SUM(det_cantidad) AS cantidad FROM @Detalle WHERE pro_id IS NOT NULL GROUP BY pro_id, bod_id) pedi
		INNER JOIN dbo.inv_producto prod2 ON prod2.pro_id = pedi.pro_id
		LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = pedi.pro_id AND exis.bod_id = pedi.bod_id
		WHERE prod2.pro_maneja_existencia = 1
		  AND ISNULL(exis.existencia, 0) < pedi.cantidad
	)
		THROW 51402, 'No hay existencia suficiente para uno o más productos del detalle.', 1;

	-- El total del documento es el que certifica FEL: precio unitario con IVA
	-- redondeado a centavos × cantidad, menos el descuento con IVA (ver
	-- FelXmlBuilder.Calcular). Antes se sumaba el IVA al neto de la línea y,
	-- con cantidades mayores a uno, el total podía quedar un centavo abajo o
	-- arriba del que ve el cliente. El asiento sigue cuadrado: el ingreso es
	-- el total menos el IVA (paContabilidadAsientoDocumentoGenerar).
	DECLARE @monto_total NUMERIC(12, 2) = (
		SELECT SUM(ROUND(ROUND(det_precio_unitario * (1 + ISNULL(det_porc_iva, 0) / 100.0), 2) * det_cantidad, 2)
				 - ROUND(det_valor_descuento * (1 + ISNULL(det_porc_iva, 0) / 100.0), 2))
		FROM @Detalle
	);

	-- Contado: las formas de pago cubren el total. Crédito: cubren el enganche
	-- y el resto (lo financiado) no puede pasar del crédito disponible.
	DECLARE @es_credito BIT = CASE WHEN @EncFechaPrimerPago IS NOT NULL AND ISNULL(@EncNumeroCuotas, 0) > 0 THEN 1 ELSE 0 END;
	DECLARE @a_pagar NUMERIC(12, 2) = CASE WHEN @es_credito = 1 THEN ISNULL(@EncMontoEnganche, 0) ELSE @monto_total END;
	DECLARE @formas_total NUMERIC(12, 2) = (SELECT SUM(ppf_monto) FROM @FormasPago);
	DECLARE @msg NVARCHAR(400);

	IF @es_credito = 1 AND (ISNULL(@EncMontoEnganche, 0) < 0 OR ISNULL(@EncMontoEnganche, 0) >= @monto_total)
		THROW 53222, 'El enganche debe ser mayor o igual a cero y menor que el total de la factura.', 1;
	IF @a_pagar > 0 AND @formas_total IS NULL
		THROW 53223, 'Registre la forma de pago del contado o del enganche.', 1;
	IF @formas_total IS NOT NULL AND @formas_total <> @a_pagar
	BEGIN
		SET @msg = CONCAT(N'Las formas de pago suman Q', FORMAT(@formas_total, 'N2'), N' y deben sumar Q', FORMAT(@a_pagar, 'N2'),
			CASE WHEN @es_credito = 1 THEN N' (enganche).' ELSE N' (total de la factura).' END);
		THROW 53224, @msg, 1;
	END
	IF @formas_total IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @PcaId AND pca_estado = 'A')
		THROW 53225, 'No hay una caja abierta para recibir el pago de la factura.', 1;

	IF @es_credito = 1
	BEGIN
		DECLARE @limite NUMERIC(14, 2), @saldo_actual NUMERIC(14, 2);
		SELECT @limite = credito.Limite, @saldo_actual = credito.Saldo FROM dbo.fnClienteCredito(@CliId) credito;
		IF @limite > 0 AND @saldo_actual + (@monto_total - ISNULL(@EncMontoEnganche, 0)) > @limite
		BEGIN
			SET @msg = CONCAT(N'La factura excede el límite de crédito del cliente: límite Q', FORMAT(@limite, 'N2'),
				N', saldo actual Q', FORMAT(@saldo_actual, 'N2'), N', disponible Q', FORMAT(IIF(@limite - @saldo_actual > 0, @limite - @saldo_actual, 0), 'N2'),
				N', a financiar Q', FORMAT(@monto_total - ISNULL(@EncMontoEnganche, 0), 'N2'), N'.');
			THROW 53226, @msg, 1;
		END
	END

	BEGIN TRY
		BEGIN TRANSACTION;

		DECLARE @serie VARCHAR(32), @correlativo NUMERIC(12, 0);

		SELECT @serie = serie, @correlativo = correlativo + 1
		FROM dbo.conf_correlativos WITH (UPDLOCK, ROWLOCK)
		WHERE tdo_id = @TdoId;

		IF @serie IS NULL
			THROW 51403, 'No existe una serie de correlativos configurada para este tipo de documento.', 1;

		UPDATE dbo.conf_correlativos
		   SET correlativo = @correlativo,
			   UpdUsuario = @UsuId,
			   UpdFechaHora = SYSDATETIME()
		 WHERE tdo_id = @TdoId;

		SET @EncNumeroUnico = @serie + '-' + CAST(@correlativo AS VARCHAR(20));

		INSERT INTO dbo.inv_documento_enc
			(enc_fecha_docto, enc_numero_autorizacion, enc_serie_docto, enc_numero_docto,
			 cli_id, enc_nombres_cliente, enc_apellidos_cliente, cli_nit, tdo_id, pve_id,
			 enc_fecha_primer_pago, enc_monto_enganche, enc_numero_cuotas, enc_monto_total,
			 enc_valor_descuento, enc_direccion_cliente, mon_id, usu_id_creacion, enc_numero_unico,
			 InsUsuario, InsFechaHora)
		VALUES
			(@EncFechaDocto, @EncNumeroAutorizacion, @EncSerieDocto, @EncNumeroDocto,
			 @CliId, @EncNombresCliente, @EncApellidosCliente, @CliNit, @TdoId, @PveId,
			 @EncFechaPrimerPago, @EncMontoEnganche, @EncNumeroCuotas, @monto_total,
			 @EncValorDescuento, @EncDireccionCliente, @MonId, @UsuId, @EncNumeroUnico,
			 @UsuId, SYSDATETIME());

		SET @EncId = SCOPE_IDENTITY();

		-- Factura desde una cotización: solo una vigente (hoy no ha pasado su
		-- fecha de vencimiento) y que nadie más haya facturado o anulado.
		IF @CotId IS NOT NULL
		BEGIN
			UPDATE dbo.ven_cotizacion_enc
			   SET cot_estado = 'F', enc_id = @EncId, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
			 WHERE cot_id = @CotId AND cot_estado = 'V' AND cot_fecha_vencimiento >= CAST(GETDATE() AS DATE);
			IF @@ROWCOUNT = 0
				THROW 54412, 'La cotización ya venció, ya se facturó o está anulada: no se puede convertir en factura. Haga una cotización nueva.', 1;
		END

		INSERT INTO dbo.inv_documento_det
			(enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion,
			 det_precio_unitario, det_valor_descuento, det_sub_total, det_costo_unitario, det_porc_iva, bod_id, pro_id, ppr_id, ume_id,
			 InsUsuario, InsFechaHora)
		SELECT
			@EncId, deta.det_item, deta.det_bien_o_servicio, deta.det_cantidad, deta.det_descripcion,
			deta.det_precio_unitario, deta.det_valor_descuento, deta.det_sub_total, deta.det_costo_unitario, deta.det_porc_iva,
			deta.bod_id, deta.pro_id, deta.ppr_id, COALESCE(deta.ume_id, prod.ume_id),
			@UsuId, SYSDATETIME()
		FROM @Detalle deta
		LEFT JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id;

		IF @PcaId IS NOT NULL AND EXISTS (SELECT 1 FROM @FormasPago)
		BEGIN
			DECLARE @ppe_id INT;

			INSERT INTO dbo.pos_pago_enc (cli_id, pca_id, usu_id, InsUsuario, InsFechaHora)
			VALUES (@CliId, @PcaId, @UsuId, @UsuId, SYSDATETIME());

			SET @ppe_id = SCOPE_IDENTITY();

			INSERT INTO dbo.pos_pago_forma
				(gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, ppe_id, pft_id, InsUsuario, InsFechaHora)
			SELECT gef_id, ppf_numero_tarjeta_ult4, ppf_fecha_vencimiento_tarjeta, ppf_numero_cheque, ppf_monto, @ppe_id, pft_id, @UsuId, SYSDATETIME()
			FROM @FormasPago;

			INSERT INTO dbo.pos_pago_det (ppe_id, enc_id, ppd_valor_aplicado, InsUsuario, InsFechaHora)
			SELECT @ppe_id, @EncId, SUM(ppf_monto), @UsuId, SYSDATETIME()
			FROM @FormasPago;
		END

		EXEC dbo.paClientePlanPagosGenerar @EncId = @EncId, @UsuId = @UsuId;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'G',
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId;

		EXEC dbo.paInventarioExistenciaDocumentoAjustar @EncId = @EncId, @UsuId = @UsuId;

		DECLARE @asi_id INT;
		EXEC dbo.paContabilidadAsientoDocumentoGenerar @EncId = @EncId, @UsuId = @UsuId, @AsiId = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 4. Prueba de grabado de una factura (se revierte siempre)
------------------------------------------------------------
-- Graba una factura al crédito de prueba (1 unidad, 1 cuota) y registra un
-- cliente por NIT dentro de una transacción que SIEMPRE se revierte: no queda
-- ninguna factura, cliente, póliza ni correlativo usado. Si algo falla,
-- muestra el número, el procedimiento, la línea y el mensaje del error real
-- (el que la aplicación resumía como "Ocurrió un error en la base de datos").
CREATE OR ALTER PROCEDURE [dbo].[paDiagnosticoFacturaProbar]
	@SucId			INT = NULL,				-- sucursal de la bodega (NULL = cualquiera)
	@Usuario		VARCHAR(128) = 'admin'
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = @Usuario);
	DECLARE @bod INT, @pro INT, @descripcion VARCHAR(256), @costo NUMERIC(14, 4), @ume INT;
	SELECT TOP 1 @bod = exis.bod_id, @pro = prod.pro_id, @descripcion = prod.pro_descripcion,
		   @costo = ISNULL(prod.pro_costo_unitario, 0), @ume = prod.ume_id
	FROM dbo.inv_producto_existencia_bodega exis
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = exis.pro_id AND prod.pro_estado = 'A' AND prod.pro_maneja_existencia = 1
	INNER JOIN dbo.inv_bodega bode ON bode.bod_id = exis.bod_id AND bode.bod_estado = 'A'
	WHERE exis.existencia >= 1 AND (@SucId IS NULL OR bode.suc_id = @SucId)
	ORDER BY exis.existencia DESC;
	DECLARE @tdo INT = (SELECT TOP 1 tdo_id FROM dbo.inv_documento_tipo
						WHERE tdo_naturaleza = '-' AND tdo_estado = 'A' AND tdo_es_nota = 0 AND tdo_es_interno = 0
						ORDER BY CASE tdo_codigo WHEN 'FCAM' THEN 0 ELSE 1 END, tdo_descripcion);
	-- Consumidor final o un cliente con crédito libre (la prueba es al crédito).
	DECLARE @cli INT = (SELECT TOP 1 clie.cli_id FROM dbo.pos_cliente clie
						CROSS APPLY dbo.fnClienteCredito(clie.cli_id) cred
						WHERE clie.cli_estado = 'A' AND (cred.Limite = 0 OR cred.Limite - cred.Saldo >= 10)
						ORDER BY CASE WHEN clie.cli_nit_normalizado = 'CF' THEN 0 WHEN cred.Limite = 0 THEN 1 ELSE 2 END, clie.cli_id);
	DECLARE @mon INT = (SELECT TOP 1 mon_id FROM dbo.gen_moneda WHERE mon_estado = 'A' ORDER BY mon_es_local DESC, mon_id);

	IF @usu IS NULL OR @bod IS NULL OR @tdo IS NULL OR @cli IS NULL OR @mon IS NULL
	BEGIN
		SELECT 'NO SE PUDO PROBAR' AS Resultado,
			   CONCAT_WS(', ', IIF(@usu IS NULL, 'usuario', NULL), IIF(@bod IS NULL, 'producto con existencia', NULL),
						 IIF(@tdo IS NULL, 'tipo de documento de venta', NULL), IIF(@cli IS NULL, 'cliente activo con crédito disponible', NULL),
						 IIF(@mon IS NULL, 'moneda', NULL)) AS Falta;
		RETURN;
	END

	DECLARE @precio NUMERIC(14, 2) = 1;	-- Q1.00 (más IVA): no depende del crédito del cliente
	DECLARE @detalle dbo.factura_det_type, @formas dbo.pago_forma_type;
	INSERT INTO @detalle (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_valor_descuento,
						  det_sub_total, det_costo_unitario, det_porc_iva, bod_id, pro_id, ppr_id, ume_id)
	VALUES (1, 'B', 1, LEFT(@descripcion, 256), @precio, 0, @precio, @costo, 12, @bod, @pro, NULL, @ume);

	DECLARE @hoy DATE = CAST(GETDATE() AS DATE), @primer DATE = DATEADD(MONTH, 1, CAST(GETDATE() AS DATE));
	DECLARE @enc INT, @numero VARCHAR(16), @paso VARCHAR(64), @cli_nuevo INT, @nuevo BIT;
	BEGIN TRY
		BEGIN TRANSACTION;
		SET @paso = 'Grabar la factura (paVentaFacturaCrear)';
		EXEC dbo.paVentaFacturaCrear @EncFechaDocto = @hoy, @EncNumeroAutorizacion = NULL, @EncSerieDocto = NULL, @EncNumeroDocto = NULL,
			@CliId = @cli, @EncNombresCliente = NULL, @EncApellidosCliente = NULL, @CliNit = NULL, @TdoId = @tdo, @PveId = NULL,
			@EncFechaPrimerPago = @primer, @EncMontoEnganche = 0, @EncNumeroCuotas = 1, @EncValorDescuento = 0,
			@EncDireccionCliente = NULL, @MonId = @mon, @UsuId = @usu, @Detalle = @detalle, @PcaId = NULL, @FormasPago = @formas,
			@EncId = @enc OUTPUT, @EncNumeroUnico = @numero OUTPUT;
		SET @paso = 'Registrar un cliente por NIT (paClienteRegistrarPorNit)';
		EXEC dbo.paClienteRegistrarPorNit @Nit = '7654321-8', @Nombre = 'PRUEBA,DIAGNOSTICO,,CLIENTE,', @UsuId = @usu,
			@CliId = @cli_nuevo OUTPUT, @Nuevo = @nuevo OUTPUT;
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
		SELECT 'OK' AS Resultado, CONCAT('Se grabó la factura de prueba ', @numero, ' y se registró un cliente por NIT; todo se revirtió.') AS Detalle;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
		SELECT 'ERROR' AS Resultado, @paso AS Paso, ERROR_NUMBER() AS Numero, ERROR_PROCEDURE() AS Procedimiento,
			   ERROR_LINE() AS Linea, ERROR_MESSAGE() AS Mensaje;
	END CATCH
END;
GO

-- Igual que en 34; una compra pagada por transferencia o en una contraseña
-- pendiente no se anula sin anular antes el lote o la contraseña.
CREATE OR ALTER PROCEDURE [dbo].[paDocumentoAnular]
	@EncId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @estado_actual CHAR(1), @es_nota BIT;
	SELECT @estado_actual = enca.enc_estado, @es_nota = tipo.tdo_es_nota
	FROM dbo.inv_documento_enc enca INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @EncId;

	IF @estado_actual IS NULL
		THROW 51421, 'El documento indicado no existe.', 1;
	IF @estado_actual <> 'G'
		THROW 51422, 'Solo se pueden anular documentos que estén en estado Grabado.', 1;
	IF @es_nota = 1
		THROW 51423, 'Una nota de crédito o débito no se anula; emita la nota contraria.', 1;
	IF EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE enc_id_referencia = @EncId AND enc_estado = 'G')
		THROW 51424, 'El documento tiene notas de crédito o débito; no se puede anular.', 1;
	IF EXISTS (SELECT 1 FROM dbo.pos_pago_det deta
			   INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
			   INNER JOIN dbo.pos_cliente_plan_pagos cuot ON cuot.cpp_id = deta.cpp_id
			   WHERE cuot.enc_id = @EncId)
		THROW 53227, 'La factura tiene cobros de cuotas; anule primero esos recibos en Cuentas por cobrar › Cobros.', 1;
	IF EXISTS (SELECT 1 FROM dbo.pos_pago_det deta
			   INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
			   LEFT JOIN dbo.pos_caja_apertura aper ON aper.pca_id = pago.pca_id
			   WHERE deta.enc_id = @EncId AND ISNULL(aper.pca_estado, 'C') <> 'A')
		THROW 53228, 'El pago de esta factura entró a una caja que ya se cerró; no se puede anular: emita una nota de crédito.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_det chdt
			   INNER JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = chdt.bce_id AND cheq.bce_estado_cheque <> 'A'
			   WHERE chdt.enc_id = @EncId)
		THROW 53229, 'La compra tiene cheques emitidos; anule primero esos cheques en Cuentas por pagar › Pagos.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_lote_transferencia_cuota blcu
			   INNER JOIN dbo.bco_lote_transferencia_det line ON line.bld_id = blcu.bld_id
			   INNER JOIN dbo.bco_lote_transferencia lote ON lote.blt_id = line.blt_id AND lote.blt_estado = 'A'
			   WHERE blcu.enc_id = @EncId)
		THROW 54838, 'La compra se pagó por transferencia; anule primero ese lote en Cuentas por pagar › Pagos programados.', 1;
	IF EXISTS (SELECT 1 FROM dbo.cxp_contrasena_det deta
			   INNER JOIN dbo.cxp_contrasena_enc cont ON cont.cpa_id = deta.cpa_id AND cont.cpa_estado = 'E'
			   WHERE deta.enc_id = @EncId)
		THROW 54839, 'La compra está en una contraseña de pago pendiente; anule primero la contraseña.', 1;

	BEGIN TRY
		BEGIN TRANSACTION;

		-- El pago de contado o enganche sale del cuadre de la caja (sigue abierta).
		DECLARE @ppe_id INT;
		DECLARE recibos CURSOR LOCAL FAST_FORWARD FOR
			SELECT DISTINCT deta.ppe_id FROM dbo.pos_pago_det deta
			INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id AND pago.ppe_estado = 'A'
			WHERE deta.enc_id = @EncId;
		OPEN recibos;
		FETCH NEXT FROM recibos INTO @ppe_id;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			EXEC dbo.paCxcReciboReversar @PpeId = @ppe_id, @Motivo = 'Anulación de la factura', @UsuId = @UsuId;
			FETCH NEXT FROM recibos INTO @ppe_id;
		END
		CLOSE recibos; DEALLOCATE recibos;

		EXEC dbo.paInventarioExistenciaDocumentoAjustar @EncId = @EncId, @Reversar = 1, @UsuId = @UsuId;

		UPDATE dbo.inv_documento_enc
		   SET enc_estado = 'A',
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId;

		UPDATE dbo.cont_asiento_enc
		   SET asi_estado = 'N',
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE enc_id = @EncId;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paDocumentoConsultarPorId]
	@EncId INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT enca.*, tipo.tdo_descripcion, tipo.tdo_naturaleza
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @EncId;

	SELECT deta.*
	FROM dbo.inv_documento_det deta
	WHERE deta.enc_id = @EncId
	ORDER BY deta.det_item;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paInvCargaInicialAnular]
	@EncId	INT,
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_documento_enc enca
				   INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_codigo = 'INVI'
				   WHERE enca.enc_id = @EncId AND enca.enc_estado = 'G')
		THROW 53510, 'La carga de inventario inicial no existe o ya está anulada.', 1;
	EXEC dbo.paDocumentoAnular @EncId = @EncId, @UsuId = @UsuId;
END;
GO

-- Graba un documento interno (INVI, AJIS o AJIF) y mueve existencias y costo.
CREATE OR ALTER PROCEDURE [dbo].[paInvDocumentoInternoCrear]
	@TdoCodigo	VARCHAR(8),
	@Fecha		DATE,
	@Motivo		VARCHAR(256) = NULL,
	@Lineas		dbo.inv_documento_interno_type READONLY,
	@UsuId		INT,
	@EncId		INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @tdo_id INT, @naturaleza CHAR(1);
	SELECT @tdo_id = tdo_id, @naturaleza = tdo_naturaleza FROM dbo.inv_documento_tipo WHERE tdo_codigo = @TdoCodigo AND tdo_es_interno = 1;
	IF @tdo_id IS NULL
		THROW 53501, 'El tipo de documento interno no existe.', 1;
	IF NOT EXISTS (SELECT 1 FROM @Lineas WHERE cantidad > 0)
		THROW 53502, 'El documento no tiene líneas.', 1;

	DECLARE @numero INT = (SELECT COUNT(*) + 1 FROM dbo.inv_documento_enc WHERE tdo_id = @tdo_id);

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.inv_documento_enc
			(enc_fecha_docto, enc_serie_docto, enc_numero_docto, tdo_id, enc_monto_total, mon_id, usu_id_creacion, enc_estado, enc_motivo,
			 InsUsuario, InsFechaHora)
		VALUES
			(@Fecha, @TdoCodigo, CAST(@numero AS VARCHAR(32)), @tdo_id, (SELECT SUM(costo_total) FROM @Lineas WHERE cantidad > 0), dbo.fnMonedaLocal(),
			 @UsuId, 'G', @Motivo, @UsuId, SYSDATETIME());
		SET @EncId = SCOPE_IDENTITY();

		INSERT INTO dbo.inv_documento_det
			(enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_valor_descuento, det_sub_total,
			 det_porc_iva, bod_id, pro_id, ume_id, InsUsuario, InsFechaHora)
		SELECT @EncId, ROW_NUMBER() OVER (ORDER BY prod.pro_codigo, lins.bod_id), 'B', lins.cantidad, LEFT(prod.pro_descripcion, 512),
			   ROUND(lins.costo_total / lins.cantidad, 2), 0, lins.costo_total, 0, lins.bod_id, lins.pro_id, prod.ume_id, @UsuId, SYSDATETIME()
		FROM @Lineas lins
		INNER JOIN dbo.inv_producto prod ON prod.pro_id = lins.pro_id
		WHERE lins.cantidad > 0;

		-- Un ingreso toma como costo subtotal / cantidad; un egreso, el costo
		-- promedio del producto.
		EXEC dbo.paInventarioExistenciaDocumentoAjustar @EncId = @EncId, @Reversar = 0, @UsuId = @UsuId;

		IF @naturaleza = '-'
			UPDATE enca
			   SET enc_monto_total = (SELECT ROUND(SUM(deta.det_cantidad * deta.det_costo_unitario), 2) FROM dbo.inv_documento_det deta WHERE deta.enc_id = enca.enc_id)
			FROM dbo.inv_documento_enc enca WHERE enca.enc_id = @EncId;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paInvCargaInicialProcesar]
	@Fecha			DATE,
	@Filas			dbo.inv_carga_inicial_type READONLY,
	@SoloValidar	BIT = 1,
	@UsuId			INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @datos TABLE (Fila INT PRIMARY KEY, suc_id INT, bod_id INT, bod_suc_id INT, pro_id INT, pro_ume_id INT, pro_maneja BIT,
						  prt_id INT, ume_id INT, Producto VARCHAR(64), Descripcion VARCHAR(256), Cantidad NUMERIC(12, 4),
						  CostoTotal NUMERIC(12, 2), PrecioVenta NUMERIC(12, 2), Sucursal VARCHAR(16), Bodega VARCHAR(16),
						  Tipo VARCHAR(16), Unidad VARCHAR(16));
	INSERT INTO @datos
	SELECT fila.Fila, sucu.suc_id, bode.bod_id, bode.suc_id, prod.pro_id, prod.ume_id, prod.pro_maneja_existencia,
		   tipo.prt_id, unid.ume_id, NULLIF(LTRIM(RTRIM(fila.Producto)), ''), NULLIF(LTRIM(RTRIM(fila.Descripcion)), ''),
		   fila.Cantidad, fila.CostoTotal, fila.PrecioVenta, fila.Sucursal, fila.Bodega, fila.Tipo, fila.Unidad
	FROM @Filas fila
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_codigo = LTRIM(RTRIM(fila.Sucursal))
	LEFT JOIN dbo.inv_bodega bode ON bode.bod_codigo = LTRIM(RTRIM(fila.Bodega))
	LEFT JOIN dbo.inv_producto prod ON prod.pro_codigo = LTRIM(RTRIM(fila.Producto))
	LEFT JOIN dbo.inv_producto_tipo tipo ON tipo.prt_codigo = LTRIM(RTRIM(fila.Tipo))
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_codigo = LTRIM(RTRIM(fila.Unidad));

	DECLARE @mensajes TABLE (Fila INT, Tipo CHAR(1), Mensaje NVARCHAR(400));
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT Fila, 'E', Mensaje FROM (
		SELECT Fila, CASE
			WHEN suc_id IS NULL THEN CONCAT(N'La sucursal "', Sucursal, N'" no existe.')
			WHEN bod_id IS NULL THEN CONCAT(N'La bodega "', Bodega, N'" no existe.')
			WHEN bod_suc_id <> suc_id THEN CONCAT(N'La bodega "', Bodega, N'" no pertenece a la sucursal "', Sucursal, N'".')
			WHEN Producto IS NULL THEN N'Falta el código del producto.'
			WHEN pro_id IS NOT NULL AND pro_maneja = 0 THEN CONCAT(N'El producto "', Producto, N'" es un servicio: no maneja existencia.')
			WHEN pro_id IS NULL AND Descripcion IS NULL THEN CONCAT(N'El producto "', Producto, N'" no existe: indique su descripción para crearlo.')
			WHEN pro_id IS NULL AND prt_id IS NULL THEN CONCAT(N'El producto "', Producto, N'" no existe: indique un tipo de producto válido para crearlo.')
			WHEN Unidad IS NOT NULL AND ume_id IS NULL THEN CONCAT(N'La unidad de medida "', Unidad, N'" no existe.')
			WHEN pro_id IS NULL AND ume_id IS NULL THEN CONCAT(N'El producto "', Producto, N'" no existe: indique su unidad de medida para crearlo.')
			WHEN pro_id IS NOT NULL AND ume_id IS NOT NULL AND ISNULL(pro_ume_id, 0) <> ume_id
				THEN CONCAT(N'El producto "', Producto, N'" ya existe con otra unidad de medida.')
			WHEN ISNULL(Cantidad, 0) <= 0 THEN N'La cantidad debe ser mayor a cero.'
			WHEN CostoTotal IS NULL OR CostoTotal < 0 THEN N'El costo total debe ser cero o mayor.'
			WHEN PrecioVenta IS NOT NULL AND PrecioVenta < 0 THEN N'El precio de venta no puede ser negativo.'
		END AS Mensaje
		FROM @datos) vali
	WHERE Mensaje IS NOT NULL;

	-- El mismo producto dos veces en la misma bodega.
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT dato.Fila, 'E', CONCAT(N'El producto "', dato.Producto, N'" se repite en la bodega "', dato.Bodega, N'".')
	FROM @datos dato
	WHERE dato.Producto IS NOT NULL AND dato.bod_id IS NOT NULL
	  AND EXISTS (SELECT 1 FROM @datos otro WHERE otro.Producto = dato.Producto AND otro.bod_id = dato.bod_id AND otro.Fila < dato.Fila);

	-- Advertencias: la bodega ya tiene existencia de ese producto (se suma).
	INSERT INTO @mensajes (Fila, Tipo, Mensaje)
	SELECT dato.Fila, 'A', CONCAT(N'El producto "', dato.Producto, N'" ya tiene ', FORMAT(exis.existencia, 'N2'), N' en la bodega; la carga se suma.')
	FROM @datos dato
	INNER JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = dato.pro_id AND exis.bod_id = dato.bod_id AND exis.existencia <> 0
	WHERE NOT EXISTS (SELECT 1 FROM @mensajes mens WHERE mens.Fila = dato.Fila AND mens.Tipo = 'E');

	IF NOT EXISTS (SELECT 1 FROM @datos)
		INSERT INTO @mensajes VALUES (0, 'E', N'El archivo no tiene filas.');

	DECLARE @nuevos INT = (SELECT COUNT(DISTINCT Producto) FROM @datos WHERE pro_id IS NULL);
	IF @SoloValidar = 0 AND NOT EXISTS (SELECT 1 FROM @mensajes WHERE Tipo = 'E')
	BEGIN
		BEGIN TRY
			BEGIN TRANSACTION;

			-- Productos nuevos (una sola vez por código aunque venga en varias bodegas).
			INSERT INTO dbo.inv_producto (pro_codigo, pro_descripcion, pro_tipo_item, pro_maneja_existencia, pro_total_cantidad, pro_total_costo,
										  pro_costo_unitario, prt_id, pro_estado, ume_id, InsUsuario, InsFechaHora)
			SELECT prim.Producto, prim.Descripcion, 'B', 1, 0, 0, 0, prim.prt_id, 'A', prim.ume_id, @UsuId, SYSDATETIME()
			FROM (SELECT dato.*, ROW_NUMBER() OVER (PARTITION BY dato.Producto ORDER BY dato.Fila) AS orden FROM @datos dato WHERE dato.pro_id IS NULL) prim
			WHERE prim.orden = 1;

			UPDATE dato SET pro_id = prod.pro_id
			FROM @datos dato INNER JOIN dbo.inv_producto prod ON prod.pro_codigo = dato.Producto
			WHERE dato.pro_id IS NULL;

			-- Un documento INVI por bodega.
			DECLARE @bod_id INT, @enc_id INT, @lineas dbo.inv_documento_interno_type, @motivo VARCHAR(256);
			DECLARE bodegas CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT bod_id FROM @datos;
			OPEN bodegas;
			FETCH NEXT FROM bodegas INTO @bod_id;
			WHILE @@FETCH_STATUS = 0
			BEGIN
				DELETE FROM @lineas;
				INSERT INTO @lineas (bod_id, pro_id, cantidad, costo_total)
				SELECT bod_id, pro_id, Cantidad, CostoTotal FROM @datos WHERE bod_id = @bod_id;
				SET @motivo = CONCAT('Inventario inicial - ', (SELECT bod_descripcion FROM dbo.inv_bodega WHERE bod_id = @bod_id));
				EXEC dbo.paInvDocumentoInternoCrear @TdoCodigo = 'INVI', @Fecha = @Fecha, @Motivo = @motivo, @Lineas = @lineas,
					@UsuId = @UsuId, @EncId = @enc_id OUTPUT;
				FETCH NEXT FROM bodegas INTO @bod_id;
			END
			CLOSE bodegas; DEALLOCATE bodegas;

			-- Precio de venta (con IVA) de cada producto en su bodega: se
			-- actualiza el vigente o se crea uno nuevo.
			DECLARE @mon_id INT = dbo.fnMonedaLocal();
			UPDATE prec
			   SET ppr_precio_unitario_venta = dato.PrecioVenta, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
			FROM dbo.inv_producto_precio prec
			INNER JOIN @datos dato ON dato.pro_id = prec.pro_id AND dato.bod_id = prec.bod_id
			WHERE dato.PrecioVenta IS NOT NULL AND prec.mon_id = @mon_id AND prec.ppr_estado = 'A'
			  AND (prec.ppr_vigencia_hasta IS NULL OR prec.ppr_vigencia_hasta >= @Fecha);

			INSERT INTO dbo.inv_producto_precio (ppr_precio_unitario_venta, ppr_descripcion, ppr_vigencia_desde, pro_id, bod_id, mon_id, ppr_estado,
												 InsUsuario, InsFechaHora)
			SELECT dato.PrecioVenta, 'Precio de venta (inventario inicial)', @Fecha, dato.pro_id, dato.bod_id, @mon_id, 'A', @UsuId, SYSDATETIME()
			FROM @datos dato
			WHERE dato.PrecioVenta IS NOT NULL
			  AND NOT EXISTS (SELECT 1 FROM dbo.inv_producto_precio prec
							  WHERE prec.pro_id = dato.pro_id AND prec.bod_id = dato.bod_id AND prec.mon_id = @mon_id AND prec.ppr_estado = 'A'
								AND (prec.ppr_vigencia_hasta IS NULL OR prec.ppr_vigencia_hasta >= @Fecha));

			COMMIT TRANSACTION;
		END TRY
		BEGIN CATCH
			IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
			THROW;
		END CATCH
	END

	SELECT Fila, Tipo, Mensaje FROM @mensajes ORDER BY Fila, Tipo DESC;

	SELECT COUNT(*) AS Filas,
		   @nuevos AS ProductosNuevos,
		   COUNT(DISTINCT bod_id) AS Bodegas,
		   ISNULL(SUM(Cantidad), 0) AS Cantidad,
		   ISNULL(SUM(CostoTotal), 0) AS CostoTotal,
		   CAST(CASE WHEN @SoloValidar = 0 AND NOT EXISTS (SELECT 1 FROM @mensajes WHERE Tipo = 'E') THEN 1 ELSE 0 END AS BIT) AS Grabado
	FROM @datos;
END;
GO

/*
	Recálculo completo desde cero de existencias y costo promedio, recorriendo
	TODO el historial de documentos grabados en orden cronológico. Es la
	versión corregida de SPR_ACTUALIZA_EXISTENCIAS del script original: úsese
	solo como utilidad de mantenimiento/reconciliación (por ejemplo tras una
	migración de datos), nunca como parte del flujo normal de grabar una
	factura o una compra.
*/
CREATE OR ALTER PROCEDURE [dbo].[paInventarioExistenciaRecalcular]
	@UsuId INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	UPDATE dbo.inv_producto
	   SET pro_total_cantidad = 0, pro_total_costo = 0, pro_costo_unitario = 0,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE pro_maneja_existencia = 1;

	UPDATE exis
	   SET existencia = 0,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	FROM dbo.inv_producto_existencia_bodega exis
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = exis.pro_id
	WHERE prod.pro_maneja_existencia = 1;

	DECLARE @enc_id INT;

	DECLARE c1 CURSOR LOCAL FAST_FORWARD FOR
		SELECT enca.enc_id
		FROM dbo.inv_documento_enc enca
		WHERE enca.enc_estado = 'G'
		ORDER BY enca.enc_fecha_docto, enca.enc_id;

	OPEN c1;
	FETCH NEXT FROM c1 INTO @enc_id;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		EXEC dbo.paInventarioExistenciaDocumentoAjustar @EncId = @enc_id, @Reversar = 0, @UsuId = @UsuId;
		FETCH NEXT FROM c1 INTO @enc_id;
	END
	CLOSE c1;
	DEALLOCATE c1;
END;
GO

-- Anula una toma. Si estaba aplicada, anula sus documentos de ajuste
-- (revierte existencias) y sus partidas.
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

-- Aplica la toma: diferencia = conteo - existencia actual. Los sobrantes
-- entran al costo promedio del producto y los faltantes salen a ese costo.
CREATE OR ALTER PROCEDURE [dbo].[paInvTomaAplicar]
	@TfiId	INT,
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @bod_id INT, @fecha DATE, @bodega VARCHAR(128);
	SELECT @bod_id = toma.bod_id, @fecha = toma.tfi_fecha, @bodega = bode.bod_descripcion
	FROM dbo.inv_toma_fisica toma INNER JOIN dbo.inv_bodega bode ON bode.bod_id = toma.bod_id
	WHERE toma.tfi_id = @TfiId AND toma.tfi_estado = 'B';
	IF @bod_id IS NULL
		THROW 53506, 'Solo se aplica una toma abierta.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_toma_fisica_det WHERE tfi_id = @TfiId AND tfd_conteo IS NOT NULL)
		THROW 53508, 'La toma no tiene ningún producto contado.', 1;

	DECLARE @cta_inventario INT, @cta_faltante INT, @cta_sobrante INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO', @CtaId = @cta_inventario OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		-- La existencia y el costo que valen son los de este momento.
		UPDATE deta
		   SET tfd_existencia = ISNULL(exis.existencia, 0), tfd_costo_unitario = prod.pro_costo_unitario
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

------------------------------------------------------------
-- 3. Procedimientos
------------------------------------------------------------
-- Póliza de un movimiento del traslado (interna).
CREATE OR ALTER PROCEDURE [dbo].[paInvTrasladoPoliza]
	@TraId		INT,
	@Fecha		DATE,
	@Valor		NUMERIC(14, 2),
	@CtaDebe	INT,
	@CtaHaber	INT,
	@Texto		VARCHAR(256),
	@EncId		INT,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(@Valor, 0) <= 0
		RETURN;
	DECLARE @partida dbo.cont_asiento_det_type, @asi_id INT;
	INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
	VALUES (@CtaDebe, @Valor, 0, @Texto), (@CtaHaber, 0, @Valor, @Texto);
	EXEC dbo.paContabilidadAsientoInsertar @AsiFecha = @Fecha, @AsiDescripcion = @Texto, @AsiOrigen = 'TRASLADO',
		@AsiOrigenId = @TraId, @EncId = @EncId, @UsuId = @UsuId, @Detalle = @partida, @AsiId = @asi_id OUTPUT;
END;
GO

------------------------------------------------------------
-- 4. Nota de crédito y cheque a una cuota con el saldo cambiado
--    por otro usuario al mismo tiempo
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paNotaCrear]
	@TipoNota			CHAR(3),			-- NCC, NDC, NCP, NDP
	@EncIdReferencia	INT,
	@Fecha				DATE,
	@NumeroDocto		VARCHAR(32) = NULL,	-- número del proveedor (NCP/NDP)
	@Motivo				VARCHAR(256),
	@FechaVencimiento	DATE = NULL,		-- nota de débito: vencimiento de la cuota nueva
	@UsuId				INT = NULL,
	@Detalle			dbo.nota_det_type READONLY,
	@EncId				INT OUTPUT,
	@NumeroUnico		VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	-- Los parámetros OUTPUT también llegan con el valor que traiga quien llama.
	SELECT @EncId = NULL, @NumeroUnico = NULL;

	DECLARE @es_cliente BIT = CASE WHEN @TipoNota IN ('NCC', 'NDC') THEN 1 ELSE 0 END,
			@es_credito BIT = CASE WHEN @TipoNota IN ('NCC', 'NCP') THEN 1 ELSE 0 END;

	IF @TipoNota NOT IN ('NCC', 'NDC', 'NCP', 'NDP')
		THROW 53101, 'El tipo de nota debe ser NCC, NDC, NCP o NDP.', 1;
	IF ISNULL(LTRIM(RTRIM(@Motivo)), '') = ''
		THROW 53102, 'Ingrese el motivo de la nota.', 1;
	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 53103, 'La nota debe tener al menos una línea.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE det_cantidad <= 0 OR det_precio_unitario < 0 OR LTRIM(RTRIM(det_descripcion)) = '')
		THROW 53104, 'Cada línea necesita descripción, cantidad mayor a cero y precio no negativo.', 1;
	IF @es_credito = 0 AND EXISTS (SELECT 1 FROM @Detalle WHERE det_id_origen IS NOT NULL)
		THROW 53105, 'Una nota de débito no lleva devoluciones de producto.', 1;
	IF @es_credito = 0 AND @FechaVencimiento IS NULL
		THROW 53106, 'Indique la fecha de vencimiento del cargo de la nota de débito.', 1;
	IF @es_cliente = 0 AND ISNULL(LTRIM(RTRIM(@NumeroDocto)), '') = ''
		THROW 53107, 'Ingrese el número de la nota del proveedor.', 1;

	-- Documento de referencia: factura (cliente) o compra (proveedor) grabada.
	DECLARE @ref_cli INT, @ref_prv INT, @ref_estado CHAR(1), @ref_es_nota BIT, @ref_naturaleza CHAR(1), @ref_afecta_costo CHAR(1),
			@ref_mon INT, @ref_bod INT;
	SELECT @ref_cli = enca.cli_id, @ref_prv = enca.prv_id, @ref_estado = enca.enc_estado, @ref_es_nota = tipo.tdo_es_nota,
		   @ref_naturaleza = tipo.tdo_naturaleza, @ref_afecta_costo = tipo.afecta_costo, @ref_mon = enca.mon_id,
		   @ref_bod = (SELECT TOP 1 bod_id FROM dbo.inv_documento_det WHERE enc_id = enca.enc_id ORDER BY det_item)
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @EncIdReferencia;

	IF @ref_estado IS NULL OR @ref_es_nota = 1
		THROW 53108, 'El documento de referencia no existe o es otra nota.', 1;
	IF @ref_estado <> 'G'
		THROW 53109, 'El documento de referencia debe estar grabado (no anulado).', 1;
	IF @es_cliente = 1 AND (@ref_cli IS NULL OR @ref_naturaleza <> '-')
		THROW 53110, 'Una nota a cliente debe referirse a una factura.', 1;
	IF @es_cliente = 0 AND (@ref_prv IS NULL OR @ref_naturaleza <> '+')
		THROW 53111, 'Una nota de proveedor debe referirse a una compra.', 1;

	-- Líneas con los datos que faltan tomados de la línea original.
	DECLARE @lineas TABLE (det_item INT PRIMARY KEY, det_descripcion VARCHAR(256), det_cantidad NUMERIC(12, 4), det_precio_unitario NUMERIC(12, 2),
		det_sub_total NUMERIC(12, 2), det_porc_iva NUMERIC(8, 2), ume_id INT, det_id_origen INT, pro_id INT, bod_id INT, maneja_existencia BIT,
		costo_unitario NUMERIC(14, 5));
	INSERT INTO @lineas
	SELECT deta.det_item, deta.det_descripcion, deta.det_cantidad, deta.det_precio_unitario,
		   ROUND(deta.det_cantidad * deta.det_precio_unitario, 2), ISNULL(deta.det_porc_iva, orig.det_porc_iva),
		   COALESCE(orig.ume_id, deta.ume_id), deta.det_id_origen, orig.pro_id, ISNULL(orig.bod_id, @ref_bod),
		   ISNULL(prod.pro_maneja_existencia, 0),
		   -- costo con que vuelve (o sale) la mercadería: el costo de la venta
		   -- original; en compras, el costo de compra de la línea.
		   CASE WHEN @es_cliente = 1 THEN COALESCE(orig.det_costo_unitario, prod.pro_costo_unitario, 0)
				ELSE deta.det_precio_unitario END
	FROM @Detalle deta
	LEFT JOIN dbo.inv_documento_det orig ON orig.det_id = deta.det_id_origen
	LEFT JOIN dbo.inv_producto prod ON prod.pro_id = orig.pro_id;

	IF EXISTS (SELECT 1 FROM @lineas lin LEFT JOIN dbo.inv_documento_det orig ON orig.det_id = lin.det_id_origen
			   WHERE lin.det_id_origen IS NOT NULL AND (orig.enc_id IS NULL OR orig.enc_id <> @EncIdReferencia OR orig.pro_id IS NULL))
		THROW 53112, 'Una línea de devolución no corresponde a un producto del documento de referencia.', 1;

	-- No se puede devolver más de lo vendido/comprado menos lo ya devuelto.
	IF EXISTS (
		SELECT 1
		FROM (SELECT det_id_origen, SUM(det_cantidad) AS cantidad FROM @lineas WHERE det_id_origen IS NOT NULL GROUP BY det_id_origen) dev
		INNER JOIN dbo.inv_documento_det orig ON orig.det_id = dev.det_id_origen
		CROSS APPLY (SELECT ISNULL(SUM(prev.det_cantidad), 0) AS devuelto
					 FROM dbo.inv_documento_det prev
					 INNER JOIN dbo.inv_documento_enc nota ON nota.enc_id = prev.enc_id AND nota.enc_estado = 'G'
					 WHERE prev.det_id_origen = orig.det_id) ante
		WHERE dev.cantidad > orig.det_cantidad - ante.devuelto)
		THROW 53113, 'La cantidad devuelta supera lo que queda por devolver de esa línea.', 1;

	IF EXISTS (SELECT 1 FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1 AND det_cantidad <> ROUND(det_cantidad, 0))
		THROW 53114, 'Los productos con existencia se devuelven en cantidades enteras.', 1;

	-- Devolución al proveedor: la mercadería debe estar en la bodega.
	IF @es_cliente = 0 AND @es_credito = 1 AND EXISTS (
		SELECT 1
		FROM (SELECT pro_id, bod_id, SUM(det_cantidad) AS cantidad FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1 GROUP BY pro_id, bod_id) dev
		LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = dev.pro_id AND exis.bod_id = dev.bod_id
		WHERE ISNULL(exis.existencia, 0) < dev.cantidad)
		THROW 53115, 'No hay existencia suficiente en la bodega para devolver esa mercadería al proveedor.', 1;

	DECLARE @neto NUMERIC(14, 2) = (SELECT SUM(det_sub_total) FROM @lineas),
			@neto_devolucion NUMERIC(14, 2) = (SELECT ISNULL(SUM(det_sub_total), 0) FROM @lineas WHERE det_id_origen IS NOT NULL),
			@costo_devolucion NUMERIC(14, 2) = (SELECT ISNULL(SUM(ROUND(det_cantidad * costo_unitario, 2)), 0) FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1),
			@total NUMERIC(14, 2) = (SELECT ROUND(SUM(det_sub_total * (1 + ISNULL(det_porc_iva, 0) / 100.0)), 2) FROM @lineas);
	DECLARE @iva NUMERIC(14, 2) = @total - @neto;

	IF @total <= 0
		THROW 53116, 'El total de la nota debe ser mayor a cero.', 1;

	-- Una nota de crédito no puede dejar el documento con saldo negativo.
	DECLARE @pendiente NUMERIC(14, 2) = CASE WHEN @es_cliente = 1
		THEN (SELECT ISNULL(SUM(cpp_saldo_cuota), 0) FROM dbo.pos_cliente_plan_pagos WHERE enc_id = @EncIdReferencia AND cpp_saldo_cuota > 0)
		ELSE (SELECT ISNULL(SUM(ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0)), 0) FROM dbo.inv_proveedor_plan_pago
			  WHERE enc_id = @EncIdReferencia AND ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0) > 0) END;
	IF @es_credito = 1 AND @total > @pendiente
	BEGIN
		DECLARE @msg_saldo NVARCHAR(300) = CONCAT(N'La nota de crédito (Q', FORMAT(@total, 'N2'), N') supera el saldo pendiente del documento (Q',
			FORMAT(@pendiente, 'N2'), N').');
		THROW 53117, @msg_saldo, 1;
	END

	-- Cuentas de la póliza (se validan antes de grabar nada).
	DECLARE @cta_clientes INT, @cta_iva_debito INT, @cta_inventario INT, @cta_costo INT, @cta_proveedores INT, @cta_iva_credito INT,
			@cta_gasto_compra INT, @cta_contrapartida INT;
	IF @es_cliente = 1
	BEGIN
		EXEC dbo.paCuentaParametroObtener @Codigo = 'VENTA_CLIENTES', @CtaId = @cta_clientes OUTPUT;
		EXEC dbo.paCuentaParametroObtener @Codigo = 'VENTA_IVA_DEBITO', @CtaId = @cta_iva_debito OUTPUT;
		IF @es_credito = 1
		BEGIN
			EXEC dbo.paCuentaParametroObtener @Codigo = 'NC_CLIENTE_REBAJA', @CtaId = @cta_contrapartida OUTPUT;
			IF @costo_devolucion > 0
			BEGIN
				EXEC dbo.paCuentaParametroObtener @Codigo = 'INVENTARIO', @CtaId = @cta_inventario OUTPUT;
				EXEC dbo.paCuentaParametroObtener @Codigo = 'VENTA_COSTO', @CtaId = @cta_costo OUTPUT;
			END
		END
		ELSE
			EXEC dbo.paCuentaParametroObtener @Codigo = 'ND_CLIENTE_INGRESO', @CtaId = @cta_contrapartida OUTPUT;
	END
	ELSE
	BEGIN
		EXEC dbo.paCuentaParametroObtener @Codigo = 'COMPRA_PROVEEDORES', @CtaId = @cta_proveedores OUTPUT;
		EXEC dbo.paCuentaParametroObtener @Codigo = 'COMPRA_IVA_CREDITO', @CtaId = @cta_iva_credito OUTPUT;
		IF @es_credito = 1
		BEGIN
			IF @neto - @neto_devolucion > 0
				EXEC dbo.paCuentaParametroObtener @Codigo = 'NC_PROVEEDOR_REBAJA', @CtaId = @cta_contrapartida OUTPUT;
			IF @neto_devolucion > 0
			BEGIN
				-- EXEC no acepta una expresión como valor de un parámetro.
				DECLARE @concepto_devolucion VARCHAR(40) = CASE WHEN @ref_afecta_costo = 'S' THEN 'INVENTARIO' ELSE 'COMPRA_GASTO' END;
				EXEC dbo.paCuentaParametroObtener @Codigo = @concepto_devolucion, @CtaId = @cta_inventario OUTPUT;
			END
		END
		ELSE
			EXEC dbo.paCuentaParametroObtener @Codigo = 'ND_PROVEEDOR_GASTO', @CtaId = @cta_contrapartida OUTPUT;
	END

	DECLARE @tdo_id INT = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo = @TipoNota);
	DECLARE @referencia VARCHAR(40);

	BEGIN TRANSACTION;

	-- Correlativo (solo notas a clientes).
	IF @es_cliente = 1
	BEGIN
		DECLARE @serie VARCHAR(32), @correlativo NUMERIC(12, 0);
		SELECT @serie = serie, @correlativo = correlativo + 1 FROM dbo.conf_correlativos WITH (UPDLOCK, ROWLOCK) WHERE tdo_id = @tdo_id;
		IF @serie IS NULL
			THROW 51403, 'No existe una serie de correlativos configurada para este tipo de documento.', 1;
		UPDATE dbo.conf_correlativos SET correlativo = @correlativo, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE tdo_id = @tdo_id;
		SET @NumeroUnico = @serie + '-' + CAST(@correlativo AS VARCHAR(20));
	END

	INSERT INTO dbo.inv_documento_enc
		(enc_fecha_docto, enc_numero_docto, cli_id, enc_nombres_cliente, enc_apellidos_cliente, cli_nit,
		 prv_id, prv_enc_nombres_proveedor, prv_enc_apellidos_proveedor, prv_nit, tdo_id, enc_monto_total, enc_id_referencia,
		 mon_id, enc_numero_unico, enc_motivo, usu_id_creacion, enc_estado, InsUsuario, InsFechaHora)
	SELECT @Fecha, @NumeroDocto, refe.cli_id, refe.enc_nombres_cliente, refe.enc_apellidos_cliente, refe.cli_nit,
		   refe.prv_id, refe.prv_enc_nombres_proveedor, refe.prv_enc_apellidos_proveedor, refe.prv_nit, @tdo_id, @total, @EncIdReferencia,
		   @ref_mon, @NumeroUnico, LTRIM(RTRIM(@Motivo)), @UsuId, 'G', @UsuId, SYSDATETIME()
	FROM dbo.inv_documento_enc refe WHERE refe.enc_id = @EncIdReferencia;
	SET @EncId = SCOPE_IDENTITY();
	SET @referencia = CONCAT(@TipoNota, ' ', ISNULL(@NumeroUnico, @NumeroDocto));

	INSERT INTO dbo.inv_documento_det
		(enc_id, det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total, det_costo_unitario,
		 det_porc_iva, bod_id, pro_id, ume_id, det_id_origen, InsUsuario, InsFechaHora)
	SELECT @EncId, det_item, CASE WHEN pro_id IS NULL THEN 'S' ELSE 'B' END, det_cantidad, det_descripcion, det_precio_unitario, det_sub_total,
		   CASE WHEN maneja_existencia = 1 THEN costo_unitario END, det_porc_iva, bod_id, pro_id, ume_id, det_id_origen, @UsuId, SYSDATETIME()
	FROM @lineas;

	-- Inventario de las devoluciones: entra (cliente) o sale (proveedor) al
	-- costo de la línea, y se recalcula el costo promedio.
	IF EXISTS (SELECT 1 FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1)
	BEGIN
		DECLARE @signo INT = CASE WHEN @es_cliente = 1 THEN 1 ELSE -1 END;
		DECLARE @movimientos TABLE (pro_id INT, bod_id INT, cantidad NUMERIC(14, 4), costo NUMERIC(14, 2), PRIMARY KEY (pro_id, bod_id));
		INSERT INTO @movimientos
		SELECT pro_id, bod_id, SUM(det_cantidad) * @signo, SUM(ROUND(det_cantidad * costo_unitario, 2)) * @signo
		FROM @lineas WHERE det_id_origen IS NOT NULL AND maneja_existencia = 1
		GROUP BY pro_id, bod_id;

		MERGE dbo.inv_producto_existencia_bodega AS destino
		USING @movimientos AS origen ON destino.pro_id = origen.pro_id AND destino.bod_id = origen.bod_id
		WHEN MATCHED THEN UPDATE SET existencia = destino.existencia + origen.cantidad, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		WHEN NOT MATCHED THEN INSERT (bod_id, pro_id, existencia, InsUsuario, InsFechaHora) VALUES (origen.bod_id, origen.pro_id, origen.cantidad, @UsuId, SYSDATETIME());

		;WITH totales AS (SELECT pro_id, SUM(cantidad) AS cantidad, SUM(costo) AS costo FROM @movimientos GROUP BY pro_id)
		UPDATE prod
		   SET prod.pro_total_cantidad = prod.pro_total_cantidad + tota.cantidad,
			   prod.pro_total_costo = prod.pro_total_costo + tota.costo,
			   prod.pro_costo_unitario = CASE WHEN prod.pro_total_cantidad + tota.cantidad > 0
											  THEN (prod.pro_total_costo + tota.costo) / (prod.pro_total_cantidad + tota.cantidad) ELSE 0 END,
			   prod.UpdUsuario = @UsuId, prod.UpdFechaHora = SYSDATETIME()
		FROM dbo.inv_producto prod INNER JOIN totales tota ON tota.pro_id = prod.pro_id;
	END

	-- Plan de pagos.
	IF @es_credito = 1
	BEGIN
		-- Rebaja desde la última cuota hacia atrás.
		DECLARE @restante NUMERIC(14, 2) = @total, @cuota INT, @saldo_cuota NUMERIC(14, 2), @aplicado NUMERIC(14, 2);
		IF @es_cliente = 1
		BEGIN
			DECLARE cuotas_cur CURSOR LOCAL FAST_FORWARD FOR
				SELECT cpp_id, cpp_saldo_cuota FROM dbo.pos_cliente_plan_pagos
				WHERE enc_id = @EncIdReferencia AND cpp_saldo_cuota > 0 ORDER BY cpp_nro_cuota DESC;
			OPEN cuotas_cur;
			FETCH NEXT FROM cuotas_cur INTO @cuota, @saldo_cuota;
			WHILE @@FETCH_STATUS = 0 AND @restante > 0
			BEGIN
				SET @aplicado = CASE WHEN @saldo_cuota < @restante THEN @saldo_cuota ELSE @restante END;
				UPDATE dbo.pos_cliente_plan_pagos
				   SET cpp_saldo_cuota = cpp_saldo_cuota - @aplicado,
					   cpp_estado = CASE WHEN cpp_saldo_cuota - @aplicado <= 0 THEN 'A' ELSE cpp_estado END,
					   cpp_fecha_real_pago = CASE WHEN cpp_saldo_cuota - @aplicado <= 0 THEN @Fecha ELSE cpp_fecha_real_pago END,
					   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
				 WHERE cpp_id = @cuota;
				INSERT INTO dbo.pos_cliente_nota_aplicacion (enc_id_nota, cpp_id, cna_monto, InsUsuario) VALUES (@EncId, @cuota, @aplicado, @UsuId);
				SET @restante = @restante - @aplicado;
				FETCH NEXT FROM cuotas_cur INTO @cuota, @saldo_cuota;
			END
			CLOSE cuotas_cur; DEALLOCATE cuotas_cur;
		END
		ELSE
		BEGIN
			DECLARE pagos_cur CURSOR LOCAL FAST_FORWARD FOR
				SELECT ppg_id, ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0) FROM dbo.inv_proveedor_plan_pago
				WHERE enc_id = @EncIdReferencia AND ppg_valor_pago - ISNULL(ppg_valor_real_pago, 0) > 0 ORDER BY ppg_nro_pago DESC;
			OPEN pagos_cur;
			FETCH NEXT FROM pagos_cur INTO @cuota, @saldo_cuota;
			WHILE @@FETCH_STATUS = 0 AND @restante > 0
			BEGIN
				SET @aplicado = CASE WHEN @saldo_cuota < @restante THEN @saldo_cuota ELSE @restante END;
				UPDATE dbo.inv_proveedor_plan_pago
				   SET ppg_valor_pago = ppg_valor_pago - @aplicado,
					   ppg_estado = CASE WHEN ppg_valor_pago - @aplicado <= ISNULL(ppg_valor_real_pago, 0) THEN 'A' ELSE ppg_estado END,
					   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
				 WHERE ppg_id = @cuota;
				INSERT INTO dbo.inv_proveedor_nota_aplicacion (enc_id_nota, ppg_id, pna_monto, InsUsuario) VALUES (@EncId, @cuota, @aplicado, @UsuId);
				SET @restante = @restante - @aplicado;
				FETCH NEXT FROM pagos_cur INTO @cuota, @saldo_cuota;
			END
			CLOSE pagos_cur; DEALLOCATE pagos_cur;
		END
		-- La validación del saldo (antes de la transacción) lee la versión
		-- confirmada: si otro usuario aplicó un cobro, un pago o una nota al
		-- mismo documento al mismo tiempo, aquí el saldo ya no alcanza y la
		-- nota no se graba (antes se grababa por el total y solo rebajaba lo
		-- que quedaba, y la póliza no cuadraba con las cuotas).
		IF @restante > 0
			THROW 54302, 'El saldo del documento cambió mientras se grababa la nota (otro usuario aplicó un cobro, pago o nota al mismo tiempo). Vuelva a consultarlo e intente de nuevo.', 1;
	END
	ELSE
	BEGIN
		-- Nota de débito: cuota nueva al final del plan del documento.
		DECLARE @nueva_cuota INT;
		IF @es_cliente = 1
		BEGIN
			INSERT INTO dbo.pos_cliente_plan_pagos
				(cpp_nro_cuota, cpp_fecha_maxima_pago, cpp_valor_cuota, cpp_saldo_cuota, enc_id, cli_id, cpp_estado, InsUsuario, InsFechaHora)
			SELECT ISNULL(MAX(cpp_nro_cuota), 0) + 1, @FechaVencimiento, @total, @total, @EncIdReferencia, @ref_cli, 'P', @UsuId, SYSDATETIME()
			FROM dbo.pos_cliente_plan_pagos WHERE enc_id = @EncIdReferencia;
			SET @nueva_cuota = SCOPE_IDENTITY();
			INSERT INTO dbo.pos_cliente_nota_aplicacion (enc_id_nota, cpp_id, cna_monto, InsUsuario) VALUES (@EncId, @nueva_cuota, @total, @UsuId);
		END
		ELSE
		BEGIN
			INSERT INTO dbo.inv_proveedor_plan_pago (ppg_nro_pago, ppg_fecha_pago, ppg_valor_pago, enc_id, prv_id, ppg_estado, InsUsuario, InsFechaHora)
			SELECT ISNULL(MAX(ppg_nro_pago), 0) + 1, @FechaVencimiento, @total, @EncIdReferencia, @ref_prv, 'P', @UsuId, SYSDATETIME()
			FROM dbo.inv_proveedor_plan_pago WHERE enc_id = @EncIdReferencia;
			SET @nueva_cuota = SCOPE_IDENTITY();
			INSERT INTO dbo.inv_proveedor_nota_aplicacion (enc_id_nota, ppg_id, pna_monto, InsUsuario) VALUES (@EncId, @nueva_cuota, @total, @UsuId);
		END
	END

	-- Póliza.
	DECLARE @partida dbo.cont_asiento_det_type, @asi_id INT;
	IF @TipoNota = 'NCC'
	BEGIN
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion) VALUES (@cta_contrapartida, @neto, 0, @referencia);
		IF @iva > 0 INSERT INTO @partida VALUES (@cta_iva_debito, @iva, 0, @referencia);
		INSERT INTO @partida VALUES (@cta_clientes, 0, @total, @referencia);
		IF @costo_devolucion > 0
			INSERT INTO @partida VALUES (@cta_inventario, @costo_devolucion, 0, CONCAT(@referencia, ' - reingreso')),
										(@cta_costo, 0, @costo_devolucion, CONCAT(@referencia, ' - reingreso'));
	END
	ELSE IF @TipoNota = 'NDC'
	BEGIN
		INSERT INTO @partida VALUES (@cta_clientes, @total, 0, @referencia), (@cta_contrapartida, 0, @neto, @referencia);
		IF @iva > 0 INSERT INTO @partida VALUES (@cta_iva_debito, 0, @iva, @referencia);
	END
	ELSE IF @TipoNota = 'NCP'
	BEGIN
		INSERT INTO @partida VALUES (@cta_proveedores, @total, 0, @referencia);
		IF @neto_devolucion > 0 INSERT INTO @partida VALUES (@cta_inventario, 0, @neto_devolucion, CONCAT(@referencia, ' - devolución'));
		IF @neto - @neto_devolucion > 0 INSERT INTO @partida VALUES (@cta_contrapartida, 0, @neto - @neto_devolucion, @referencia);
		IF @iva > 0 INSERT INTO @partida VALUES (@cta_iva_credito, 0, @iva, @referencia);
	END
	ELSE
	BEGIN
		INSERT INTO @partida VALUES (@cta_contrapartida, @neto, 0, @referencia);
		IF @iva > 0 INSERT INTO @partida VALUES (@cta_iva_credito, @iva, 0, @referencia);
		INSERT INTO @partida VALUES (@cta_proveedores, 0, @total, @referencia);
	END

	DECLARE @origen VARCHAR(20) = CASE WHEN @es_credito = 1 THEN 'NOTA_CREDITO' ELSE 'NOTA_DEBITO' END;
	DECLARE @descripcion VARCHAR(256) = CONCAT(@referencia, ' - ', LTRIM(RTRIM(@Motivo)));
	EXEC dbo.paContabilidadAsientoInsertar
		@AsiFecha = @Fecha, @AsiDescripcion = @descripcion, @AsiOrigen = @origen, @AsiOrigenId = @EncId, @EncId = @EncId,
		@UsuId = @UsuId, @Detalle = @partida, @AsiId = @asi_id OUTPUT;

	COMMIT TRANSACTION;
END;
GO

------------------------------------------------------------
-- 3. Grabar, aprobar, anular y cerrar
------------------------------------------------------------
-- @OcpId NULL crea la orden en borrador; con valor, reemplaza la orden (solo en borrador).
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraGuardar]
	@OcpId			INT OUTPUT,
	@Fecha			DATE,
	@FechaEntrega	DATE = NULL,
	@PrvId			INT,
	@BodId			INT,
	@MonId			INT = NULL,
	@Condiciones	VARCHAR(256) = NULL,
	@Observaciones	VARCHAR(500) = NULL,
	@UsuId			INT = NULL,
	@Detalle		dbo.orden_compra_det_type READONLY,
	@Numero			VARCHAR(16) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @Numero = NULL;

	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 54501, 'La orden de compra debe tener al menos un producto.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle WHERE cantidad <= 0 OR costo_unitario < 0)
		THROW 54502, 'La cantidad debe ser mayor a cero y el costo no puede ser negativo.', 1;
	IF EXISTS (SELECT pro_id FROM @Detalle GROUP BY pro_id HAVING COUNT(*) > 1)
		THROW 54503, 'Un producto aparece en más de una línea: sume las cantidades en una sola.', 1;
	IF EXISTS (SELECT 1 FROM @Detalle deta LEFT JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
			   WHERE prod.pro_id IS NULL OR prod.pro_estado <> 'A' OR prod.pro_tipo_item <> 'B')
		THROW 54504, 'Solo se ordenan productos (bienes) activos.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_proveedor WHERE prv_id = @PrvId AND prv_estado = 'A')
		THROW 54505, 'Elija un proveedor activo.', 1;

	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));
	IF @FechaEntrega IS NOT NULL AND @FechaEntrega < @Fecha
		THROW 54506, 'La fecha de entrega no puede ser anterior a la fecha de la orden.', 1;

	DECLARE @suc_id INT, @iva NUMERIC(8, 2);
	SELECT @suc_id = bode.suc_id, @iva = comp.cia_porc_iva
	FROM dbo.inv_bodega bode
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	WHERE bode.bod_id = @BodId AND bode.bod_estado = 'A';
	IF @suc_id IS NULL
		THROW 54507, 'Elija una bodega activa para recibir la orden.', 1;

	SET @MonId = ISNULL(@MonId, dbo.fnMonedaLocal());
	DECLARE @total NUMERIC(14, 2) = (SELECT SUM(ROUND(cantidad * costo_unitario, 2)) FROM @Detalle);

	BEGIN TRANSACTION;
	IF @OcpId IS NULL
	BEGIN
		DECLARE @siguiente INT = ISNULL((SELECT MAX(CAST(SUBSTRING(ocp_numero, 4, 12) AS INT)) FROM dbo.cmp_orden_compra_enc WITH (UPDLOCK, HOLDLOCK)), 0) + 1;
		INSERT INTO dbo.cmp_orden_compra_enc
			(ocp_numero, ocp_fecha, ocp_fecha_entrega, prv_id, suc_id, bod_id, mon_id, ocp_porc_iva, ocp_total,
			 ocp_condiciones, ocp_observaciones, ocp_estado, usu_id, InsUsuario, InsFechaHora)
		VALUES
			(CONCAT('OC-', RIGHT(CONCAT('000000', @siguiente), 6)), @Fecha, @FechaEntrega, @PrvId, @suc_id, @BodId, @MonId, @iva, @total,
			 NULLIF(LTRIM(RTRIM(@Condiciones)), ''), NULLIF(LTRIM(RTRIM(@Observaciones)), ''), 'B', @UsuId, @UsuId, SYSDATETIME());
		SET @OcpId = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.cmp_orden_compra_enc
		   SET ocp_fecha = @Fecha, ocp_fecha_entrega = @FechaEntrega, prv_id = @PrvId, suc_id = @suc_id, bod_id = @BodId,
			   mon_id = @MonId, ocp_porc_iva = @iva, ocp_total = @total,
			   ocp_condiciones = NULLIF(LTRIM(RTRIM(@Condiciones)), ''), ocp_observaciones = NULLIF(LTRIM(RTRIM(@Observaciones)), ''),
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE ocp_id = @OcpId AND ocp_estado = 'B';
		IF @@ROWCOUNT = 0
			THROW 54508, 'Solo se modifica una orden de compra en borrador.', 1;
		DELETE FROM dbo.cmp_orden_compra_det WHERE ocp_id = @OcpId;
	END

	INSERT INTO dbo.cmp_orden_compra_det (ocp_id, ocd_item, pro_id, ume_id, ocd_descripcion, ocd_cantidad, ocd_costo_unitario, ocd_total)
	SELECT @OcpId, ROW_NUMBER() OVER (ORDER BY deta.item), deta.pro_id, prod.ume_id,
		   ISNULL(NULLIF(LTRIM(RTRIM(deta.descripcion)), ''), prod.pro_descripcion), deta.cantidad, deta.costo_unitario,
		   ROUND(deta.cantidad * deta.costo_unitario, 2)
	FROM @Detalle deta
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id;

	SELECT @Numero = ocp_numero FROM dbo.cmp_orden_compra_enc WHERE ocp_id = @OcpId;
	COMMIT;
END;
GO

------------------------------------------------------------
-- 6. Recepción: la orden se convierte en una compra (ingreso a bodega)
------------------------------------------------------------
-- @Lineas: lo que llegó en esta factura del proveedor (cantidad y costo con IVA).
-- Contado si @FechaPrimerPago es NULL; crédito con @NumeroCuotas cuotas.
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraRecibir]
	@OcpId				INT,
	@Fecha				DATE,
	@Serie				VARCHAR(32) = NULL,
	@NumeroDocumento	VARCHAR(32),
	@Autorizacion		VARCHAR(64) = NULL,
	@FechaPrimerPago	DATE = NULL,
	@NumeroCuotas		INT = 1,
	@Enganche			NUMERIC(12, 2) = 0,
	@UsuId				INT = NULL,
	@Lineas				dbo.orden_compra_recepcion_type READONLY,
	@EncId				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @EncId = NULL;

	IF ISNULL(LTRIM(RTRIM(@NumeroDocumento)), '') = ''
		THROW 54515, 'Indique el número de la factura del proveedor.', 1;
	IF NOT EXISTS (SELECT 1 FROM @Lineas WHERE cantidad > 0)
		THROW 54516, 'Indique la cantidad recibida de al menos un producto.', 1;
	IF EXISTS (SELECT 1 FROM @Lineas WHERE cantidad < 0 OR costo_unitario < 0)
		THROW 54517, 'La cantidad y el costo no pueden ser negativos.', 1;
	SELECT @Serie = NULLIF(LTRIM(RTRIM(@Serie)), ''), @NumeroDocumento = LTRIM(RTRIM(@NumeroDocumento));
	IF @FechaPrimerPago IS NOT NULL AND ISNULL(@NumeroCuotas, 0) < 1
		THROW 54518, 'Para una compra al crédito indique el número de cuotas.', 1;

	DECLARE @tdo_id INT = (SELECT tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo = 'COMP');

	BEGIN TRANSACTION;

	DECLARE @prv_id INT, @bod_id INT, @mon_id INT, @iva NUMERIC(8, 2), @estado CHAR(1), @numero_oc VARCHAR(16);
	SELECT @prv_id = prv_id, @bod_id = bod_id, @mon_id = mon_id, @iva = ocp_porc_iva, @estado = ocp_estado, @numero_oc = ocp_numero
	FROM dbo.cmp_orden_compra_enc WITH (UPDLOCK, HOLDLOCK)
	WHERE ocp_id = @OcpId;
	IF @estado IS NULL OR @estado <> 'A'
		THROW 54519, 'Solo se recibe mercadería de una orden aprobada (no en borrador, cerrada ni anulada).', 1;
	IF EXISTS (SELECT 1 FROM @Lineas line LEFT JOIN dbo.cmp_orden_compra_det deta ON deta.ocd_id = line.ocd_id AND deta.ocp_id = @OcpId
			   WHERE deta.ocd_id IS NULL)
		THROW 54520, 'Una línea recibida no pertenece a la orden.', 1;

	DECLARE @msg NVARCHAR(400) = (
		SELECT TOP 1 CONCAT(N'De ', deta.ocd_descripcion, N' quedan ', deta.ocd_cantidad - reci.recibido,
							N' pendientes y se quieren recibir ', line.cantidad, N'.')
		FROM @Lineas line
		INNER JOIN dbo.cmp_orden_compra_det deta ON deta.ocd_id = line.ocd_id
		INNER JOIN dbo.fnOrdenCompraRecibido(@OcpId) reci ON reci.ocd_id = deta.ocd_id
		WHERE line.cantidad > deta.ocd_cantidad - reci.recibido);
	IF @msg IS NOT NULL
		THROW 54521, @msg, 1;

	IF EXISTS (SELECT 1 FROM dbo.inv_documento_enc
			   WHERE prv_id = @prv_id AND tdo_id = @tdo_id AND enc_estado = 'G'
				 AND ISNULL(enc_serie_docto, '') = ISNULL(@Serie, '') AND enc_numero_docto = @NumeroDocumento)
		THROW 54522, 'Esa factura del proveedor ya está registrada como compra vigente.', 1;

	DECLARE @nombre VARCHAR(128), @nit VARCHAR(16);
	SELECT @nombre = LEFT(prv_nombre_comercial, 128), @nit = prv_nit FROM dbo.inv_proveedor WHERE prv_id = @prv_id;

	-- Costos con IVA a neto, como lo hace la pantalla de Compras.
	DECLARE @detalle dbo.compra_det_type;
	INSERT INTO @detalle (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario,
						  det_valor_descuento, det_sub_total, det_porc_iva, bod_id, pro_id)
	SELECT ROW_NUMBER() OVER (ORDER BY deta.ocd_item), 'B', line.cantidad, deta.ocd_descripcion,
		   ROUND(line.costo_unitario / (1 + @iva / 100.0), 2), 0,
		   ROUND(ROUND(line.costo_unitario / (1 + @iva / 100.0), 2) * line.cantidad, 2), @iva, @bod_id, deta.pro_id
	FROM @Lineas line
	INNER JOIN dbo.cmp_orden_compra_det deta ON deta.ocd_id = line.ocd_id
	WHERE line.cantidad > 0;

	EXEC dbo.paCompraDocumentoCrear
		@EncFechaDocto = @Fecha, @EncNumeroAutorizacion = @Autorizacion,
		@EncSerieDocto = @Serie, @EncNumeroDocto = @NumeroDocumento,
		@PrvId = @prv_id, @PrvEncNombresProveedor = @nombre, @PrvEncApellidosProveedor = NULL, @PrvNit = @nit,
		@TdoId = @tdo_id, @EncFechaPrimerPago = @FechaPrimerPago, @EncMontoEnganche = @Enganche,
		@EncNumeroCuotas = @NumeroCuotas, @EncValorDescuento = 0, @MonId = @mon_id, @UsuId = @UsuId,
		@Detalle = @detalle, @EncId = @EncId OUTPUT;

	DECLARE @ocr_id INT;
	INSERT INTO dbo.cmp_orden_compra_recepcion (ocp_id, enc_id, ocr_fecha, usu_id, InsUsuario, InsFechaHora)
	VALUES (@OcpId, @EncId, @Fecha, @UsuId, @UsuId, SYSDATETIME());
	SET @ocr_id = SCOPE_IDENTITY();

	INSERT INTO dbo.cmp_orden_compra_recepcion_det (ocr_id, ocd_id, ord_cantidad, ord_costo_unitario)
	SELECT @ocr_id, ocd_id, cantidad, costo_unitario FROM @Lineas WHERE cantidad > 0;

	-- Marca de la última actividad de la orden.
	UPDATE dbo.cmp_orden_compra_enc SET UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE ocp_id = @OcpId;

	COMMIT;
END;
GO

-- @Estado: C cerrar, A volver a abrir.
CREATE OR ALTER PROCEDURE [dbo].[paPeriodoContableCambiarEstado]
	@Anio	INT,
	@Mes	INT,
	@Estado	CHAR(1),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF @Estado NOT IN ('A', 'C')
		THROW 55013, 'El estado del período es A (abierto) o C (cerrado).', 1;
	IF @Mes NOT BETWEEN 1 AND 12 OR @Anio NOT BETWEEN 2000 AND 2100
		THROW 55014, 'Período no válido.', 1;
	IF @Estado = 'C' AND DATEFROMPARTS(@Anio, @Mes, 1) > CAST(GETDATE() AS DATE)
		THROW 55015, 'No se cierra un período que todavía no empieza.', 1;
	DECLARE @pdo_id INT, @inicio DATE = DATEFROMPARTS(@Anio, @Mes, 1);
	EXEC dbo.paContabilidadPeriodoObtenerOCrear @Fecha = @inicio, @UsuId = @UsuId, @PdoId = @pdo_id OUTPUT;
	UPDATE dbo.cont_periodo_contable
	   SET pdo_estado = @Estado,
		   pdo_fecha_cierre = IIF(@Estado = 'C', SYSDATETIME(), NULL), usu_id_cierre = IIF(@Estado = 'C', @UsuId, NULL),
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE pdo_id = @pdo_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paPermisoConsultar]
	@PerModulo VARCHAR(32) = NULL,
	@PerEstado CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;
	SELECT per_id, per_modulo, per_codigo, per_descripcion, per_estado
	FROM dbo.sec_permiso
	WHERE (@PerModulo IS NULL OR per_modulo = @PerModulo)
	  AND (@PerEstado IS NULL OR per_estado = @PerEstado)
	ORDER BY per_modulo, per_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paPermisoInsertar]
	@PerModulo			VARCHAR(32),
	@PerCodigo			VARCHAR(64),
	@PerDescripcion	VARCHAR(128) = NULL,
	@UsuId				INT = NULL,
	@PerId				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_codigo = @PerCodigo)
		THROW 51081, 'Ya existe un permiso con ese código.', 1;

	INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion, InsUsuario, InsFechaHora)
	VALUES (@PerModulo, @PerCodigo, @PerDescripcion, @UsuId, SYSDATETIME());

	SET @PerId = SCOPE_IDENTITY();
END;
GO

-- Póliza manual: cuentas de detalle activas, cada línea al Debe o al Haber,
-- cuadrada y en un período abierto.
CREATE OR ALTER PROCEDURE [dbo].[paPolizaManualGrabar]
	@Fecha			DATE,
	@Descripcion	VARCHAR(256),
	@Lineas			dbo.cont_asiento_det_cc_type READONLY,
	@UsuId			INT = NULL,
	@AsiId			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @AsiId = NULL;
	SET @Descripcion = NULLIF(LTRIM(RTRIM(@Descripcion)), '');
	DECLARE @mensaje NVARCHAR(300);

	IF @Fecha IS NULL
		THROW 55001, 'Indique la fecha de la póliza.', 1;
	IF @Descripcion IS NULL
		THROW 55002, 'Indique la descripción (concepto) de la póliza.', 1;
	IF (SELECT COUNT(*) FROM @Lineas) < 2
		THROW 55003, 'La póliza necesita al menos dos líneas (un cargo y un abono).', 1;
	IF EXISTS (SELECT 1 FROM @Lineas WHERE ISNULL(asd_debe, 0) < 0 OR ISNULL(asd_haber, 0) < 0
			   OR (ISNULL(asd_debe, 0) > 0 AND ISNULL(asd_haber, 0) > 0) OR (ISNULL(asd_debe, 0) = 0 AND ISNULL(asd_haber, 0) = 0))
		THROW 55004, 'Cada línea lleva un monto mayor a cero al Debe o al Haber (no en los dos).', 1;
	IF EXISTS (SELECT 1 FROM @Lineas line LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = line.cta_id
			   WHERE cuen.cta_id IS NULL OR cuen.cta_acepta_movimiento = 0 OR cuen.cta_estado <> 'A')
	BEGIN
		SELECT TOP 1 @mensaje = CONCAT(N'La cuenta ', ISNULL(cuen.cta_codigo + ' ' + cuen.cta_nombre, CAST(line.cta_id AS VARCHAR(10))),
			N' no acepta movimientos (es de agrupación o está inactiva).')
		FROM @Lineas line LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = line.cta_id
		WHERE cuen.cta_id IS NULL OR cuen.cta_acepta_movimiento = 0 OR cuen.cta_estado <> 'A';
		THROW 55005, @mensaje, 1;
	END
	DECLARE @debe NUMERIC(14, 2) = (SELECT SUM(ISNULL(asd_debe, 0)) FROM @Lineas),
			@haber NUMERIC(14, 2) = (SELECT SUM(ISNULL(asd_haber, 0)) FROM @Lineas);
	IF @debe <> @haber
	BEGIN
		SET @mensaje = CONCAT(N'La póliza no cuadra: Debe Q', FORMAT(@debe, 'N2'), N' y Haber Q', FORMAT(@haber, 'N2'),
			N' (diferencia Q', FORMAT(ABS(@debe - @haber), 'N2'), N').');
		THROW 55006, @mensaje, 1;
	END
	IF EXISTS (SELECT 1 FROM dbo.cont_periodo_contable WHERE pdo_anio = YEAR(@Fecha) AND pdo_mes = MONTH(@Fecha) AND pdo_estado = 'C')
	BEGIN
		SET @mensaje = CONCAT(N'El período ', MONTH(@Fecha), N'/', YEAR(@Fecha), N' está cerrado: elija una fecha de un período abierto.');
		THROW 55007, @mensaje, 1;
	END

	DECLARE @detalle dbo.cont_asiento_det_cc_type;
	INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion, IdDepartamento)
	SELECT cta_id, ISNULL(asd_debe, 0), ISNULL(asd_haber, 0), NULLIF(LTRIM(RTRIM(asd_descripcion)), ''), IdDepartamento FROM @Lineas;
	EXEC dbo.paContabilidadAsientoInsertarCc @asi_fecha = @Fecha, @asi_descripcion = @Descripcion, @asi_origen = 'MANUAL',
		@usu_id = @UsuId, @detalle = @detalle, @asi_id = @AsiId OUTPUT;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoActualizar]
	@ProId					INT,
	@ProCodigo				VARCHAR(64),
	@ProDescripcion		VARCHAR(256),
	@PrtId					INT,
	@ProTipoItem			CHAR(1),
	@ProManejaExistencia	BIT,
	@ProIdPadre			INT = NULL,
	@ProPtjeRentabilidad	NUMERIC(8, 2) = NULL,
	@UsuId					INT = NULL,
	@UmeId					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_id = @ProId)
		THROW 51002, 'El producto indicado no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_codigo = @ProCodigo AND pro_id <> @ProId)
		THROW 51001, 'Ya existe otro producto con ese código.', 1;

	UPDATE dbo.inv_producto
	   SET pro_codigo = @ProCodigo,
		   pro_descripcion = @ProDescripcion,
		   prt_id = @PrtId,
		   pro_tipo_item = @ProTipoItem,
		   pro_maneja_existencia = @ProManejaExistencia,
		   pro_id_padre = @ProIdPadre,
		   pro_ptje_rentabilidad = @ProPtjeRentabilidad,
		   ume_id = ISNULL(@UmeId, ume_id),
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pro_id = @ProId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoConsultar]
	@ProCodigo			VARCHAR(64) = NULL,
	@ProDescripcion	VARCHAR(256) = NULL,
	@PrtId				INT = NULL,
	@ProEstado			CHAR(1) = 'A',
	@Pagina				INT = 1,
	@TamanioPagina		INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT prod.pro_id, prod.pro_codigo, prod.pro_descripcion, prod.pro_tipo_item,
		   prod.pro_maneja_existencia, prod.pro_total_cantidad, prod.pro_costo_unitario,
		   prod.prt_id, ptip.prt_descripcion, prod.pro_estado,
		   prod.ume_id, unid.ume_codigo, unid.ume_descripcion
	FROM dbo.inv_producto prod
	INNER JOIN dbo.inv_producto_tipo ptip ON ptip.prt_id = prod.prt_id
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = prod.ume_id
	WHERE (@ProCodigo IS NULL OR prod.pro_codigo LIKE '%' + @ProCodigo + '%')
	  AND (@ProDescripcion IS NULL OR prod.pro_descripcion LIKE '%' + @ProDescripcion + '%')
	  AND (@PrtId IS NULL OR prod.prt_id = @PrtId)
	  AND (@ProEstado IS NULL OR prod.pro_estado = @ProEstado)
	ORDER BY prod.pro_descripcion
	OFFSET (@Pagina - 1) * @TamanioPagina ROWS FETCH NEXT @TamanioPagina ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoConsultarPorId]
	@ProId INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT prod.*, ptip.prt_descripcion
	FROM dbo.inv_producto prod
	INNER JOIN dbo.inv_producto_tipo ptip ON ptip.prt_id = prod.prt_id
	WHERE prod.pro_id = @ProId;

	SELECT exis.bod_id, bode.bod_descripcion, exis.existencia
	FROM dbo.inv_producto_existencia_bodega exis
	INNER JOIN dbo.inv_bodega bode ON bode.bod_id = exis.bod_id
	WHERE exis.pro_id = @ProId;

	SELECT prec.ppr_id, prec.bod_id, prec.ppr_precio_unitario_venta, prec.ppr_vigencia_desde, prec.ppr_vigencia_hasta, prec.mon_id
	FROM dbo.inv_producto_precio prec
	WHERE prec.pro_id = @ProId AND prec.ppr_estado = 'A';
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoEliminar]
	@ProId INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_id = @ProId)
		THROW 51002, 'El producto indicado no existe.', 1;

	UPDATE dbo.inv_producto
	   SET pro_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pro_id = @ProId;
END;
GO

-- Producto: se agrega la unidad de medida (opcional; si no viene se deja la actual).
CREATE OR ALTER PROCEDURE [dbo].[paProductoInsertar]
	@ProCodigo				VARCHAR(64),
	@ProDescripcion		VARCHAR(256),
	@PrtId					INT,
	@ProTipoItem			CHAR(1) = 'B',
	@ProManejaExistencia	BIT = 1,
	@ProIdPadre			INT = NULL,
	@UsuId					INT = NULL,
	@ProId					INT OUTPUT,
	@UmeId					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_codigo = @ProCodigo)
		THROW 51001, 'Ya existe un producto con ese código.', 1;

	IF @UmeId IS NULL
		SET @UmeId = (SELECT ume_id FROM dbo.inv_unidad_medida WHERE ume_codigo = CASE WHEN @ProTipoItem = 'S' THEN 'SRV' ELSE 'UND' END);

	INSERT INTO dbo.inv_producto
		(pro_codigo, pro_descripcion, prt_id, pro_tipo_item, pro_maneja_existencia, pro_id_padre, ume_id, InsUsuario, InsFechaHora)
	VALUES
		(@ProCodigo, @ProDescripcion, @PrtId, @ProTipoItem, @ProManejaExistencia, @ProIdPadre, @UmeId, @UsuId, SYSDATETIME());

	SET @ProId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProveedorActualizar]
	@PrvId					INT,
	@PrvNombreComercial	VARCHAR(128),
	@PrvNit				VARCHAR(16) = NULL,
	@PrvContacto			VARCHAR(128) = NULL,
	@PrvDireccion			VARCHAR(128) = NULL,
	@PrvTelefonoOficina	VARCHAR(16) = NULL,
	@PrvEmailEmpresa		VARCHAR(64) = NULL,
	@UsuId					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_proveedor WHERE prv_id = @PrvId)
		THROW 51022, 'El proveedor indicado no existe.', 1;

	UPDATE dbo.inv_proveedor
	   SET prv_nombre_comercial = @PrvNombreComercial,
		   prv_nit = @PrvNit,
		   prv_contacto = @PrvContacto,
		   prv_direccion = @PrvDireccion,
		   prv_telefono_oficina = @PrvTelefonoOficina,
		   prv_email_empresa = @PrvEmailEmpresa,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE prv_id = @PrvId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProveedorConsultar]
	@Texto			VARCHAR(128) = NULL,
	@PrvEstado		CHAR(1) = 'A',
	@Pagina			INT = 1,
	@TamanioPagina	INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT prv_id, prv_codigo, prv_nombre_comercial, prv_nit, prv_contacto,
		   prv_telefono_oficina, prv_email_empresa, prv_estado
	FROM dbo.inv_proveedor
	WHERE (@PrvEstado IS NULL OR prv_estado = @PrvEstado)
	  AND (@Texto IS NULL
		   OR prv_codigo LIKE '%' + @Texto + '%'
		   OR prv_nombre_comercial LIKE '%' + @Texto + '%'
		   OR prv_nit LIKE '%' + @Texto + '%')
	ORDER BY prv_nombre_comercial
	OFFSET (@Pagina - 1) * @TamanioPagina ROWS FETCH NEXT @TamanioPagina ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProveedorConsultarPorId]
	@PrvId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.inv_proveedor WHERE prv_id = @PrvId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProveedorEliminar]
	@PrvId INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_proveedor WHERE prv_id = @PrvId)
		THROW 51022, 'El proveedor indicado no existe.', 1;

	UPDATE dbo.inv_proveedor
	   SET prv_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE prv_id = @PrvId;
END;
GO

------------------------------------------------------------
-- inv_proveedor
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paProveedorInsertar]
	@PrvCodigo				VARCHAR(16),
	@PrvNombreComercial	VARCHAR(128),
	@PrvNit				VARCHAR(16) = NULL,
	@PrvContacto			VARCHAR(128) = NULL,
	@PrvDireccion			VARCHAR(128) = NULL,
	@PrvTelefonoOficina	VARCHAR(16) = NULL,
	@PrvEmailEmpresa		VARCHAR(64) = NULL,
	@UsuId					INT = NULL,
	@PrvId					INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.inv_proveedor WHERE prv_codigo = @PrvCodigo)
		THROW 51021, 'Ya existe un proveedor con ese código.', 1;

	INSERT INTO dbo.inv_proveedor
		(prv_codigo, prv_nombre_comercial, prv_nit, prv_contacto, prv_direccion, prv_telefono_oficina, prv_email_empresa,
		 InsUsuario, InsFechaHora)
	VALUES
		(@PrvCodigo, @PrvNombreComercial, @PrvNit, @PrvContacto, @PrvDireccion, @PrvTelefonoOficina, @PrvEmailEmpresa,
		 @UsuId, SYSDATETIME());

	SET @PrvId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRolActualizar]
	@RolId		INT,
	@RolNombre	VARCHAR(64),
	@UsuId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.sec_rol WHERE rol_id = @RolId)
		THROW 51072, 'El rol indicado no existe.', 1;

	UPDATE dbo.sec_rol
	   SET rol_nombre = @RolNombre,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE rol_id = @RolId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRolConsultar]
	@RolEstado CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;
	SELECT rol_id, rol_codigo, rol_nombre, rol_estado
	FROM dbo.sec_rol
	WHERE (@RolEstado IS NULL OR rol_estado = @RolEstado)
	ORDER BY rol_nombre;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRolEliminar]
	@RolId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.sec_rol WHERE rol_id = @RolId)
		THROW 51072, 'El rol indicado no existe.', 1;

	UPDATE dbo.sec_rol
	   SET rol_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE rol_id = @RolId;
END;
GO

------------------------------------------------------------
-- Seguridad: roles, permisos y asignaciones
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRolInsertar]
	@RolCodigo	VARCHAR(32),
	@RolNombre	VARCHAR(64),
	@UsuId		INT = NULL,
	@RolId		INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.sec_rol WHERE rol_codigo = @RolCodigo)
		THROW 51071, 'Ya existe un rol con ese código.', 1;

	INSERT INTO dbo.sec_rol (rol_codigo, rol_nombre, InsUsuario, InsFechaHora)
	VALUES (@RolCodigo, @RolNombre, @UsuId, SYSDATETIME());
	SET @RolId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRolPermisoAsignar]
	@RolId	INT,
	@PerId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso WHERE rol_id = @RolId AND per_id = @PerId)
		INSERT INTO dbo.sec_rol_permiso (rol_id, per_id, InsUsuario, InsFechaHora)
		VALUES (@RolId, @PerId, @UsuId, SYSDATETIME());
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRolPermisoRevocar]
	@RolId INT,
	@PerId INT
AS
BEGIN
	SET NOCOUNT ON;
	DELETE FROM dbo.sec_rol_permiso WHERE rol_id = @RolId AND per_id = @PerId;
END;
GO

------------------------------------------------------------
-- 7. Aprobación con cuota patronal y provisiones
--
-- Igual que en 36 (ingresos por centro de costo, descuentos y líquido sin
-- él). Además, en la nómina ordinaria: gasto de cuota patronal, IRTRA e
-- INTECAP contra cuotas patronales por pagar, y gasto de aguinaldo y bono
-- 14 contra su provisión. Solo las cuentas de gasto llevan departamento.
------------------------------------------------------------
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
		THROW 52091, 'La nómina no tiene empleados; revise las fechas, el tipo de nómina y los empleados activos.', 1;

	DECLARE @Clase CHAR(1) = (SELECT Clase FROM dbo.rrhhNomina WHERE IdNomina = @IdNomina);

	UPDATE nemp
	   SET IdDepartamento = dbo.fnRrhhEmpleadoDepartamento(empl.IdEmpleado),
		   FormaPago = empl.FormaPago, gef_id = empl.gef_id, TipoCuenta = empl.TipoCuenta, NumeroCuenta = empl.NumeroCuenta
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = nemp.IdEmpleado
	WHERE nemp.IdNomina = @IdNomina;

	DECLARE @sin_pago VARCHAR(200);
	SELECT @sin_pago = STRING_AGG(CAST(empl.CodigoEmpleado AS VARCHAR(20)), ', ')
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = nemp.IdEmpleado
	WHERE nemp.IdNomina = @IdNomina AND nemp.Liquido > 0
	  AND (nemp.FormaPago IS NULL OR (nemp.FormaPago = 'T' AND (nemp.gef_id IS NULL OR nemp.NumeroCuenta IS NULL)));
	IF @sin_pago IS NOT NULL
	BEGIN
		DECLARE @msg_pago NVARCHAR(400) = CONCAT(N'Estos empleados no tienen forma de pago o datos bancarios completos: ', @sin_pago,
			N'. Complételos en RRHH > Empleados (Pago de nómina) antes de aprobar.');
		THROW 53428, @msg_pago, 1;
	END

	DECLARE @cta_sueldos INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'NOMINA_SUELDOS_GASTO'),
			@cta_bonificacion INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'NOMINA_BONIFICACION'),
			@cta_igss INT = (SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'NOMINA_IGSS_POR_PAGAR'),
			@cta_liquido INT;
	EXEC dbo.paCuentaParametroObtener @Codigo = 'NOMINA_SUELDOS_POR_PAGAR', @CtaId = @cta_liquido OUTPUT;

	DECLARE @lineas TABLE (cta_id INT NULL, Codigo VARCHAR(40) NOT NULL, Descripcion VARCHAR(100) NOT NULL, Naturaleza CHAR(1) NOT NULL,
						   IdDepartamento INT NULL, Departamento VARCHAR(100) NULL, Monto NUMERIC(14, 2) NOT NULL);
	INSERT INTO @lineas (cta_id, Codigo, Descripcion, Naturaleza, IdDepartamento, Departamento, Monto)
	SELECT COALESCE(tipo.cta_id,
					CASE WHEN tipo.Codigo = 'BONIF_INCENTIVO' THEN @cta_bonificacion
						 WHEN tipo.Codigo = 'IGSS_LABORAL' THEN @cta_igss
						 WHEN deta.Naturaleza = 'I' THEN @cta_sueldos END),
		   tipo.Codigo, tipo.Descripcion, deta.Naturaleza,
		   CASE WHEN deta.Naturaleza = 'I' THEN nemp.IdDepartamento END,
		   CASE WHEN deta.Naturaleza = 'I' THEN depa.Descripcion END,
		   SUM(deta.Monto)
	FROM dbo.rrhhNominaDetalle deta
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = deta.IdNominaEmpleado
	INNER JOIN dbo.rrhhTipoMovimientoNomina tipo ON tipo.IdTipoMovimientoNomina = deta.IdTipoMovimientoNomina
	LEFT JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = nemp.IdDepartamento
	WHERE nemp.IdNomina = @IdNomina
	GROUP BY tipo.IdTipoMovimientoNomina, tipo.cta_id, tipo.Codigo, tipo.Descripcion, deta.Naturaleza,
			 CASE WHEN deta.Naturaleza = 'I' THEN nemp.IdDepartamento END,
			 CASE WHEN deta.Naturaleza = 'I' THEN depa.Descripcion END;

	DECLARE @sin_cuenta VARCHAR(40) = (SELECT TOP 1 Codigo FROM @lineas WHERE cta_id IS NULL ORDER BY Codigo);
	IF @sin_cuenta IS NOT NULL
	BEGIN
		DECLARE @mensaje NVARCHAR(300) = CONCAT(N'El tipo de movimiento ', @sin_cuenta,
			N' no tiene cuenta contable; asígnela en RRHH > Tipos de movimiento antes de aprobar la nómina.');
		THROW 52502, @mensaje, 1;
	END

	IF @Clase = 'O'
	BEGIN
		DECLARE @conceptos TABLE (Codigo VARCHAR(40) PRIMARY KEY, cta_id INT NULL);
		INSERT INTO @conceptos (Codigo, cta_id)
		SELECT v.Codigo, para.cta_id
		FROM (VALUES ('NOMINA_IGSS_PATRONAL_GASTO'), ('NOMINA_IRTRA_GASTO'), ('NOMINA_INTECAP_GASTO'), ('NOMINA_PATRONAL_POR_PAGAR'),
					 ('NOMINA_AGUINALDO_GASTO'), ('NOMINA_BONO14_GASTO'), ('NOMINA_PROVISION_AGUINALDO'), ('NOMINA_PROVISION_BONO14')) v(Codigo)
		LEFT JOIN dbo.cont_cuenta_parametro para ON para.ccp_codigo = v.Codigo;

		DECLARE @sin_concepto VARCHAR(40) = (SELECT TOP 1 Codigo FROM @conceptos WHERE cta_id IS NULL ORDER BY Codigo);
		IF @sin_concepto IS NOT NULL
		BEGIN
			DECLARE @msg_concepto NVARCHAR(300) = CONCAT(N'El concepto contable ', @sin_concepto,
				N' no tiene cuenta; asígnela en Contabilidad > Cuentas por concepto antes de aprobar la nómina.');
			THROW 54106, @msg_concepto, 1;
		END

		-- Gastos por departamento (I = Debe) y pasivos en una sola línea (D = Haber).
		INSERT INTO @lineas (cta_id, Codigo, Descripcion, Naturaleza, IdDepartamento, Departamento, Monto)
		SELECT conc.cta_id, gast.Codigo, gast.Descripcion, 'I', nemp.IdDepartamento, depa.Descripcion, SUM(gast.Monto)
		FROM dbo.rrhhNominaEmpleado nemp
		LEFT JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = nemp.IdDepartamento
		CROSS APPLY (VALUES ('NOMINA_IGSS_PATRONAL_GASTO', 'Cuota patronal IGSS', nemp.IgssPatronal),
							('NOMINA_IRTRA_GASTO', 'Cuota IRTRA', nemp.Irtra),
							('NOMINA_INTECAP_GASTO', 'Cuota INTECAP', nemp.Intecap),
							('NOMINA_AGUINALDO_GASTO', 'Provisión de aguinaldo', nemp.ProvAguinaldo),
							('NOMINA_BONO14_GASTO', 'Provisión de bono 14', nemp.ProvBono14)) gast(Codigo, Descripcion, Monto)
		INNER JOIN @conceptos conc ON conc.Codigo = gast.Codigo
		WHERE nemp.IdNomina = @IdNomina
		GROUP BY conc.cta_id, gast.Codigo, gast.Descripcion, nemp.IdDepartamento, depa.Descripcion
		HAVING SUM(gast.Monto) > 0;

		INSERT INTO @lineas (cta_id, Codigo, Descripcion, Naturaleza, Monto)
		SELECT conc.cta_id, pasi.Codigo, pasi.Descripcion, 'D', pasi.Monto
		FROM (SELECT 'NOMINA_PATRONAL_POR_PAGAR' AS Codigo, 'Cuotas patronales IGSS, IRTRA e INTECAP por pagar' AS Descripcion,
					 ISNULL(SUM(IgssPatronal + Irtra + Intecap), 0) AS Monto
			  FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina
			  UNION ALL
			  SELECT 'NOMINA_PROVISION_AGUINALDO', 'Provisión de aguinaldo', ISNULL(SUM(ProvAguinaldo), 0)
			  FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina
			  UNION ALL
			  SELECT 'NOMINA_PROVISION_BONO14', 'Provisión de bono 14', ISNULL(SUM(ProvBono14), 0)
			  FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina) pasi
		INNER JOIN @conceptos conc ON conc.Codigo = pasi.Codigo
		WHERE pasi.Monto > 0;
	END

	-- El centro de costo solo aplica a cuentas de gasto (p. ej. el pago del
	-- aguinaldo carga la provisión, que es pasivo).
	UPDATE line SET IdDepartamento = NULL, Departamento = NULL
	FROM @lineas line
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = line.cta_id
	WHERE cuen.cta_tipo <> 'G';

	DECLARE @liquido NUMERIC(14, 2) = (SELECT ISNULL(SUM(Liquido), 0) FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina);
	DECLARE @descripcion_nomina VARCHAR(100), @fecha DATE;
	SELECT @descripcion_nomina = Descripcion, @fecha = ISNULL(FechaPago, FechaAl) FROM dbo.rrhhNomina WHERE IdNomina = @IdNomina;

	DECLARE @detalle dbo.cont_asiento_det_cc_type, @asi_id INT;
	INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion, IdDepartamento)
	SELECT cta_id,
		   SUM(CASE WHEN Naturaleza = 'I' THEN Monto ELSE 0 END),
		   SUM(CASE WHEN Naturaleza = 'D' THEN Monto ELSE 0 END),
		   LEFT(CONCAT(Descripcion, ISNULL(' - ' + Departamento, '')), 256),
		   IdDepartamento
	FROM @lineas
	GROUP BY cta_id, Codigo, Descripcion, Naturaleza, IdDepartamento, Departamento;
	IF @liquido <> 0
		INSERT INTO @detalle (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_liquido, CASE WHEN @liquido < 0 THEN -@liquido ELSE 0 END, CASE WHEN @liquido > 0 THEN @liquido ELSE 0 END, 'Líquido a pagar a empleados');

	BEGIN TRANSACTION;

	UPDATE movi SET IdNomina = @IdNomina, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	FROM dbo.rrhhMovimientoNomina movi
	INNER JOIN dbo.rrhhNominaDetalle deta ON deta.IdMovimientoNomina = movi.IdMovimientoNomina
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = deta.IdNominaEmpleado
	WHERE nemp.IdNomina = @IdNomina;

	UPDATE dbo.rrhhNomina
	   SET Estado = 'A', UsuarioAprobo = @UsuId, FechaAprobacion = SYSDATETIME(), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdNomina = @IdNomina;

	DECLARE @descripcion VARCHAR(256) = CONCAT(CASE WHEN @Clase = 'O' THEN 'Nómina ' ELSE 'Pago de ' END, @descripcion_nomina);
	EXEC dbo.paContabilidadAsientoInsertarCc
		@asi_fecha = @fecha, @asi_descripcion = @descripcion, @asi_origen = 'NOMINA', @asi_origen_id = @IdNomina,
		@usu_id = @UsuId, @detalle = @detalle, @asi_id = @asi_id OUTPUT;

	COMMIT TRANSACTION;
END;
GO

-- Un cheque por cada empleado pendiente que cobra con cheque, con números
-- correlativos de la chequera y una partida por cheque.
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaEmitirCheques]
	@IdNomina		INT,
	@CbcId			INT,
	@Fecha			DATE = NULL,
	@UsuId			INT,
	@IdNominaPago	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));

	DECLARE @BcbId INT = (SELECT bcb_id FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @CbcId AND cbc_estado = 'A');
	IF @BcbId IS NULL
		THROW 53413, 'La chequera no existe o está inactiva (ella o su cuenta bancaria).', 1;
	EXEC dbo.paRrhhNominaPagoValidar @IdNomina = @IdNomina, @BcbId = @BcbId, @FormaPago = 'C';

	DECLARE @pendientes TABLE (Orden INT IDENTITY(1,1), IdNominaEmpleado INT, Beneficiario VARCHAR(150), Liquido NUMERIC(14, 2));
	INSERT INTO @pendientes (IdNominaEmpleado, Beneficiario, Liquido)
	SELECT nemp.IdNominaEmpleado,
		   LEFT(CONCAT_WS(' ', empl.PrimerNombre, NULLIF(empl.SegundoNombre, ''), empl.PrimerApellido, NULLIF(empl.SegundoApellido, '')), 150),
		   nemp.Liquido
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = nemp.IdEmpleado
	WHERE nemp.IdNomina = @IdNomina AND nemp.FormaPago = 'C' AND nemp.Liquido > 0 AND nemp.IdNominaPago IS NULL
	ORDER BY empl.PrimerApellido, empl.PrimerNombre;

	DECLARE @cantidad INT = (SELECT COUNT(*) FROM @pendientes);
	DECLARE @siguiente INT = dbo.fnBcoChequeSiguiente(@CbcId), @al INT = (SELECT cbc_cheque_al FROM dbo.bco_cuenta_bancaria_chequera WHERE cbc_id = @CbcId);
	IF @siguiente IS NULL OR @al - @siguiente + 1 < @cantidad
	BEGIN
		DECLARE @msg NVARCHAR(200) = CONCAT(N'La chequera no alcanza: se necesitan ', @cantidad, N' cheques y quedan ',
			CASE WHEN @siguiente IS NULL THEN 0 ELSE @al - @siguiente + 1 END, N'.');
		THROW 53432, @msg, 1;
	END

	DECLARE @cta_por_pagar INT, @cta_banco INT = dbo.fnBcoCuentaContable(@BcbId), @bmp_id INT = (SELECT bmp_id FROM dbo.bco_motivo_pago WHERE bmp_descripcion = 'Pago de nómina');
	EXEC dbo.paCuentaParametroObtener @Codigo = 'NOMINA_SUELDOS_POR_PAGAR', @CtaId = @cta_por_pagar OUTPUT;
	IF @cta_banco IS NULL
		EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_banco OUTPUT;
	DECLARE @descripcion_nomina VARCHAR(100) = (SELECT Descripcion FROM dbo.rrhhNomina WHERE IdNomina = @IdNomina);

	BEGIN TRY
		BEGIN TRANSACTION;

		INSERT INTO dbo.rrhhNominaPago (IdNomina, Tipo, bcb_id, cbc_id, FechaPago, Monto, Empleados, Referencia, InsUsuario)
		SELECT @IdNomina, 'C', @BcbId, @CbcId, @Fecha, SUM(Liquido), COUNT(*),
			   CONCAT('Cheques ', @siguiente, CASE WHEN COUNT(*) > 1 THEN CONCAT(' al ', @siguiente + COUNT(*) - 1) ELSE '' END), @UsuId
		FROM @pendientes;
		SET @IdNominaPago = SCOPE_IDENTITY();

		DECLARE @orden INT = 1, @IdNominaEmpleado INT, @beneficiario VARCHAR(150), @liquido NUMERIC(14, 2), @numero VARCHAR(16), @bce_id INT, @asi_id INT;
		DECLARE @partida dbo.cont_asiento_det_cc_type, @texto VARCHAR(256);
		WHILE @orden <= @cantidad
		BEGIN
			SELECT @IdNominaEmpleado = IdNominaEmpleado, @beneficiario = Beneficiario, @liquido = Liquido FROM @pendientes WHERE Orden = @orden;
			SET @numero = CAST(@siguiente + @orden - 1 AS VARCHAR(16));

			INSERT INTO dbo.bco_cheque_emitido_enc
				(cbc_id, bce_fecha_emision, usu_id, bce_numero_cheque, bce_documento_ref, bce_valor, bmp_id, bce_tipo, bce_beneficiario, IdNominaEmpleado, InsUsuario, InsFechaHora)
			VALUES
				(@CbcId, @Fecha, @UsuId, @numero, CAST(@IdNomina AS VARCHAR(16)), @liquido, @bmp_id, 'N', @beneficiario, @IdNominaEmpleado, @UsuId, SYSDATETIME());
			SET @bce_id = SCOPE_IDENTITY();

			UPDATE dbo.rrhhNominaEmpleado SET IdNominaPago = @IdNominaPago, bce_id = @bce_id WHERE IdNominaEmpleado = @IdNominaEmpleado;

			DELETE FROM @partida;
			SET @texto = LEFT(CONCAT('Cheque ', @numero, ' nómina ', @descripcion_nomina, ' - ', @beneficiario), 256);
			INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
			VALUES (@cta_por_pagar, @liquido, 0, @texto), (@cta_banco, 0, @liquido, @texto);
			EXEC dbo.paContabilidadAsientoInsertarCc
				@asi_fecha = @Fecha, @asi_descripcion = @texto, @asi_origen = 'CHEQUE', @asi_origen_id = @bce_id,
				@usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;

			SET @orden += 1;
		END

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- 3. Pago de nómina por transferencia (monto calculado con la nómina
--    bloqueada, dentro de la transacción)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaPagarTransferencias]
	@IdNomina		INT,
	@BcbId			INT,
	@Fecha			DATE = NULL,
	@Referencia		VARCHAR(60) = NULL,
	@UsuId			INT,
	@IdNominaPago	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	SET @Fecha = ISNULL(@Fecha, CAST(GETDATE() AS DATE));

	EXEC dbo.paRrhhNominaPagoValidar @IdNomina = @IdNomina, @BcbId = @BcbId, @FormaPago = 'T';

	DECLARE @cta_por_pagar INT, @cta_banco INT = dbo.fnBcoCuentaContable(@BcbId);
	EXEC dbo.paCuentaParametroObtener @Codigo = 'NOMINA_SUELDOS_POR_PAGAR', @CtaId = @cta_por_pagar OUTPUT;
	IF @cta_banco IS NULL
		EXEC dbo.paCuentaParametroObtener @Codigo = 'PAGO_BANCOS', @CtaId = @cta_banco OUTPUT;

	BEGIN TRY
		BEGIN TRANSACTION;

		-- Un pago a la vez por nómina: el segundo espera y luego ya no
		-- encuentra empleados pendientes.
		DECLARE @descripcion_nomina VARCHAR(100);
		SELECT @descripcion_nomina = Descripcion FROM dbo.rrhhNomina WITH (UPDLOCK, HOLDLOCK) WHERE IdNomina = @IdNomina;

		DECLARE @monto NUMERIC(14, 2), @empleados INT;
		SELECT @monto = SUM(Liquido), @empleados = COUNT(*)
		FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina AND FormaPago = 'T' AND Liquido > 0 AND IdNominaPago IS NULL;
		IF ISNULL(@empleados, 0) = 0
			THROW 53430, 'No hay empleados pendientes de pago por transferencia en esta nómina (quizá otro usuario ya los pagó).', 1;

		INSERT INTO dbo.rrhhNominaPago (IdNomina, Tipo, bcb_id, FechaPago, Monto, Empleados, Referencia, InsUsuario)
		VALUES (@IdNomina, 'T', @BcbId, @Fecha, @monto, @empleados, NULLIF(LTRIM(RTRIM(@Referencia)), ''), @UsuId);
		SET @IdNominaPago = SCOPE_IDENTITY();

		UPDATE dbo.rrhhNominaEmpleado SET IdNominaPago = @IdNominaPago
		 WHERE IdNomina = @IdNomina AND FormaPago = 'T' AND Liquido > 0 AND IdNominaPago IS NULL;
		IF @@ROWCOUNT <> @empleados
			THROW 54208, 'Los empleados pendientes cambiaron mientras se registraba el pago; vuelva a intentarlo.', 1;

		DECLARE @partida dbo.cont_asiento_det_cc_type, @asi_id INT;
		DECLARE @texto VARCHAR(256) = LEFT(CONCAT('Transferencias nómina ', @descripcion_nomina, ISNULL(' - ' + NULLIF(LTRIM(RTRIM(@Referencia)), ''), '')), 256);
		INSERT INTO @partida (cta_id, asd_debe, asd_haber, asd_descripcion)
		VALUES (@cta_por_pagar, @monto, 0, @texto), (@cta_banco, 0, @monto, @texto);
		EXEC dbo.paContabilidadAsientoInsertarCc
			@asi_fecha = @Fecha, @asi_descripcion = @texto, @asi_origen = 'PAGO_NOMINA', @asi_origen_id = @IdNominaPago,
			@usu_id = @UsuId, @detalle = @partida, @asi_id = @asi_id OUTPUT;

		COMMIT TRANSACTION;
	END TRY
	BEGIN CATCH
		IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
		THROW;
	END CATCH
END;
GO

------------------------------------------------------------
-- Seguridad: inicio de sesión
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paSeguridadLogin]
	@UsuUsuario	VARCHAR(128),
	@UsuPassword	VARCHAR(256)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @usu_id INT, @hash VARBINARY(64), @salt UNIQUEIDENTIFIER, @intentos INT, @bloqueado BIT, @estado CHAR(1);

	SELECT @usu_id = usu_id, @hash = usu_password_hash, @salt = usu_password_salt,
		   @intentos = usu_intentos_fallidos, @bloqueado = usu_bloqueado, @estado = usu_estado
	FROM dbo.gen_usuario
	WHERE usu_usuario = @UsuUsuario;

	IF @usu_id IS NULL
	BEGIN
		SELECT 'error' AS estado, 'Usuario o contraseña no son válidos.' AS mensaje;
		RETURN;
	END

	IF @estado = 'I' OR @bloqueado = 1
	BEGIN
		SELECT 'error' AS estado, 'El usuario está inactivo o bloqueado. Contacte al administrador.' AS mensaje;
		RETURN;
	END

	-- Es el propio usuario quien produce el cambio (éxito o intento fallido):
	-- UpdUsuario queda como el mismo @usu_id encontrado arriba.
	IF HASHBYTES('SHA2_256', CAST(@salt AS VARCHAR(36)) + @UsuPassword) = @hash
	BEGIN
		UPDATE dbo.gen_usuario
		   SET usu_intentos_fallidos = 0, usu_ultimo_login = SYSDATETIME(),
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE usu_id = @usu_id;

		SELECT 'success' AS estado, 'Bienvenido, ' + @UsuUsuario + '.' AS mensaje, @usu_id AS usu_id;
	END
	ELSE
	BEGIN
		UPDATE dbo.gen_usuario
		   SET usu_intentos_fallidos = usu_intentos_fallidos + 1,
			   usu_bloqueado = CASE WHEN usu_intentos_fallidos + 1 >= 5 THEN 1 ELSE 0 END,
			   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
		 WHERE usu_id = @usu_id;

		SELECT 'error' AS estado, 'Usuario o contraseña no son válidos.' AS mensaje;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioActualizar]
	@UsuId			INT,
	@UsuUsuario	VARCHAR(128),
	@UsuEmail		VARCHAR(128) = NULL,
	@UsuIdAccion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_id = @UsuId)
		THROW 51032, 'El usuario indicado no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_usuario = @UsuUsuario AND usu_id <> @UsuId)
		THROW 51031, 'Ya existe otro usuario con ese nombre de acceso.', 1;

	UPDATE dbo.gen_usuario
	   SET usu_usuario = @UsuUsuario,
		   usu_email = @UsuEmail,
		   UpdUsuario = @UsuIdAccion,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @UsuId;
END;
GO

------------------------------------------------------------
-- 6. Usuarios con su empleado y vendedor
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paUsuarioConsultar]
	@UsuUsuario	VARCHAR(128) = NULL,
	@UsuEstado		CHAR(1) = 'A',
	@Pagina			INT = 1,
	@TamanioPagina	INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT usua.usu_id, usua.usu_codigo, usua.usu_usuario, usua.usu_email, usua.usu_fecha_ingreso,
		   usua.usu_bloqueado, usua.usu_ultimo_login, usua.usu_estado,
		   usua.IdEmpleado AS IdEmpleado,
		   NULLIF(CONCAT_WS(' ', empl.PrimerNombre, empl.SegundoNombre, empl.PrimerApellido, empl.SegundoApellido,
							'de ' + NULLIF(empl.ApellidoCasada, '')), '') AS Empleado,
		   vend.pve_codigo AS VendedorCodigo
	FROM dbo.gen_usuario usua
	LEFT JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = usua.IdEmpleado
	OUTER APPLY (SELECT TOP 1 vend.pve_codigo FROM dbo.pos_vendedor vend
				 WHERE vend.IdEmpleado = usua.IdEmpleado AND usua.IdEmpleado IS NOT NULL
				 ORDER BY CASE vend.pve_estado WHEN 'A' THEN 0 ELSE 1 END, vend.pve_id) vend
	WHERE (@UsuEstado IS NULL OR usua.usu_estado = @UsuEstado)
	  AND (@UsuUsuario IS NULL OR usua.usu_usuario LIKE '%' + @UsuUsuario + '%'
		   OR CONCAT_WS(' ', empl.PrimerNombre, empl.SegundoNombre, empl.PrimerApellido, empl.SegundoApellido) LIKE '%' + @UsuUsuario + '%')
	ORDER BY usua.usu_usuario
	OFFSET (@Pagina - 1) * @TamanioPagina ROWS FETCH NEXT @TamanioPagina ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioConsultarPorId]
	@UsuId INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT usu_id, usu_codigo, usu_usuario, usu_email, usu_fecha_ingreso,
		   usu_bloqueado, usu_ultimo_login, usu_estado
	FROM dbo.gen_usuario
	WHERE usu_id = @UsuId;

	SELECT srol.rol_id, srol.rol_codigo, srol.rol_nombre
	FROM dbo.sec_usuario_rol urol
	INNER JOIN dbo.sec_rol srol ON srol.rol_id = urol.rol_id
	WHERE urol.usu_id = @UsuId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioEliminar]
	@UsuId			INT,
	@UsuIdAccion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_id = @UsuId)
		THROW 51032, 'El usuario indicado no existe.', 1;

	UPDATE dbo.gen_usuario
	   SET usu_estado = 'I',
		   UpdUsuario = @UsuIdAccion,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @UsuId;
END;
GO

------------------------------------------------------------
-- gen_usuario (contraseña con hash + sal; ver también paSeguridadLogin
-- en 11_procedimientos_procesos.sql)
--
-- Aquí @usu_id siempre identifica la fila objetivo (el usuario sobre el que
-- se actúa), así que el usuario que ejecuta la acción se recibe como
-- @usu_id_accion para no chocar con ese nombre.
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paUsuarioInsertar]
	@UsuCodigo		VARCHAR(32),
	@UsuUsuario	VARCHAR(128),
	@UsuPassword	VARCHAR(256),
	@UsuEmail		VARCHAR(128) = NULL,
	@UsuIdAccion	INT = NULL,
	@UsuId			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_usuario = @UsuUsuario)
		THROW 51031, 'Ya existe un usuario con ese nombre de acceso.', 1;

	DECLARE @salt UNIQUEIDENTIFIER = NEWID();

	INSERT INTO dbo.gen_usuario
		(usu_codigo, usu_usuario, usu_password_hash, usu_password_salt, usu_email, InsUsuario, InsFechaHora)
	VALUES
		(@UsuCodigo, @UsuUsuario,
		 HASHBYTES('SHA2_256', CAST(@salt AS VARCHAR(36)) + @UsuPassword),
		 @salt, @UsuEmail, @UsuIdAccion, SYSDATETIME());

	SET @UsuId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioPasswordCambiar]
	@UsuId				INT,
	@PasswordActual	VARCHAR(256),
	@PasswordNuevo		VARCHAR(256)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @salt UNIQUEIDENTIFIER, @hash VARBINARY(64);

	SELECT @salt = usu_password_salt, @hash = usu_password_hash
	FROM dbo.gen_usuario WHERE usu_id = @UsuId;

	IF @salt IS NULL
		THROW 51032, 'El usuario indicado no existe.', 1;

	IF HASHBYTES('SHA2_256', CAST(@salt AS VARCHAR(36)) + @PasswordActual) <> @hash
		THROW 51033, 'La contraseña actual no es correcta.', 1;

	DECLARE @salt_nuevo UNIQUEIDENTIFIER = NEWID();

	-- Es un cambio hecho por el propio usuario: UpdUsuario queda como el
	-- mismo @usu_id que se está actualizando.
	UPDATE dbo.gen_usuario
	   SET usu_password_hash = HASHBYTES('SHA2_256', CAST(@salt_nuevo AS VARCHAR(36)) + @PasswordNuevo),
		   usu_password_salt = @salt_nuevo,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @UsuId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioRolAsignar]
	@UsuId			INT,
	@RolId			INT,
	@UsuIdAccion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.sec_usuario_rol WHERE usu_id = @UsuId AND rol_id = @RolId)
		INSERT INTO dbo.sec_usuario_rol (usu_id, rol_id, InsUsuario, InsFechaHora)
		VALUES (@UsuId, @RolId, @UsuIdAccion, SYSDATETIME());
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioRolRevocar]
	@UsuId INT,
	@RolId INT
AS
BEGIN
	SET NOCOUNT ON;
	DELETE FROM dbo.sec_usuario_rol WHERE usu_id = @UsuId AND rol_id = @RolId;
END;
GO

DROP FUNCTION IF EXISTS [dbo].[fn_descripcion_ultimo_movimiento];
DROP FUNCTION IF EXISTS [dbo].[fn_direccion_completa_cliente];
DROP FUNCTION IF EXISTS [dbo].[fn_fecha_ultimo_movimiento];
DROP FUNCTION IF EXISTS [dbo].[fn_moneda_local];
DROP FUNCTION IF EXISTS [dbo].[fn_nombre_completo_cliente];
DROP FUNCTION IF EXISTS [dbo].[fn_nombre_completo_cliente_encabezado];
DROP FUNCTION IF EXISTS [dbo].[fn_numeros_a_letras];
DROP FUNCTION IF EXISTS [dbo].[fn_ultimo_costo_unitario];
DROP PROCEDURE IF EXISTS [dbo].[sp_bancos_emitir_cheque_pago_proveedor];
DROP PROCEDURE IF EXISTS [dbo].[sp_bodega_actualizar];
DROP PROCEDURE IF EXISTS [dbo].[sp_bodega_consultar];
DROP PROCEDURE IF EXISTS [dbo].[sp_bodega_consultar_por_id];
DROP PROCEDURE IF EXISTS [dbo].[sp_bodega_eliminar];
DROP PROCEDURE IF EXISTS [dbo].[sp_bodega_insertar];
DROP PROCEDURE IF EXISTS [dbo].[sp_cliente_actualizar];
DROP PROCEDURE IF EXISTS [dbo].[sp_cliente_consultar];
DROP PROCEDURE IF EXISTS [dbo].[sp_cliente_consultar_por_id];
DROP PROCEDURE IF EXISTS [dbo].[sp_cliente_eliminar];
DROP PROCEDURE IF EXISTS [dbo].[sp_cliente_insertar];
DROP PROCEDURE IF EXISTS [dbo].[sp_compras_crear_documento];
DROP PROCEDURE IF EXISTS [dbo].[sp_contabilidad_generar_asiento_documento];
DROP PROCEDURE IF EXISTS [dbo].[sp_contabilidad_insertar_asiento];
DROP PROCEDURE IF EXISTS [dbo].[sp_contabilidad_obtener_o_crear_periodo];
DROP PROCEDURE IF EXISTS [dbo].[sp_cuenta_bancaria_actualizar];
DROP PROCEDURE IF EXISTS [dbo].[sp_cuenta_bancaria_consultar];
DROP PROCEDURE IF EXISTS [dbo].[sp_cuenta_bancaria_consultar_por_id];
DROP PROCEDURE IF EXISTS [dbo].[sp_cuenta_bancaria_eliminar];
DROP PROCEDURE IF EXISTS [dbo].[sp_cuenta_bancaria_insertar];
DROP PROCEDURE IF EXISTS [dbo].[sp_cuenta_contable_actualizar];
DROP PROCEDURE IF EXISTS [dbo].[sp_cuenta_contable_consultar];
DROP PROCEDURE IF EXISTS [dbo].[sp_cuenta_contable_consultar_por_id];
DROP PROCEDURE IF EXISTS [dbo].[sp_cuenta_contable_eliminar];
DROP PROCEDURE IF EXISTS [dbo].[sp_cuenta_contable_insertar];
DROP PROCEDURE IF EXISTS [dbo].[sp_documento_anular];
DROP PROCEDURE IF EXISTS [dbo].[sp_documento_consultar_por_id];
DROP PROCEDURE IF EXISTS [dbo].[sp_inv_generar_plan_pagos_proveedor];
DROP PROCEDURE IF EXISTS [dbo].[sp_inventario_ajustar_existencia_documento];
DROP PROCEDURE IF EXISTS [dbo].[sp_inventario_recalcular_existencias_completo];
DROP PROCEDURE IF EXISTS [dbo].[sp_permiso_consultar];
DROP PROCEDURE IF EXISTS [dbo].[sp_permiso_insertar];
DROP PROCEDURE IF EXISTS [dbo].[sp_pos_caja_abrir];
DROP PROCEDURE IF EXISTS [dbo].[sp_pos_caja_cerrar];
DROP PROCEDURE IF EXISTS [dbo].[sp_pos_generar_plan_pagos_cliente];
DROP PROCEDURE IF EXISTS [dbo].[sp_pos_registrar_pago_cuota];
DROP PROCEDURE IF EXISTS [dbo].[sp_producto_actualizar];
DROP PROCEDURE IF EXISTS [dbo].[sp_producto_consultar];
DROP PROCEDURE IF EXISTS [dbo].[sp_producto_consultar_por_id];
DROP PROCEDURE IF EXISTS [dbo].[sp_producto_eliminar];
DROP PROCEDURE IF EXISTS [dbo].[sp_producto_insertar];
DROP PROCEDURE IF EXISTS [dbo].[sp_proveedor_actualizar];
DROP PROCEDURE IF EXISTS [dbo].[sp_proveedor_consultar];
DROP PROCEDURE IF EXISTS [dbo].[sp_proveedor_consultar_por_id];
DROP PROCEDURE IF EXISTS [dbo].[sp_proveedor_eliminar];
DROP PROCEDURE IF EXISTS [dbo].[sp_proveedor_insertar];
DROP PROCEDURE IF EXISTS [dbo].[sp_rol_actualizar];
DROP PROCEDURE IF EXISTS [dbo].[sp_rol_asignar_permiso];
DROP PROCEDURE IF EXISTS [dbo].[sp_rol_consultar];
DROP PROCEDURE IF EXISTS [dbo].[sp_rol_eliminar];
DROP PROCEDURE IF EXISTS [dbo].[sp_rol_insertar];
DROP PROCEDURE IF EXISTS [dbo].[sp_rol_revocar_permiso];
DROP PROCEDURE IF EXISTS [dbo].[sp_seguridad_login];
DROP PROCEDURE IF EXISTS [dbo].[sp_usuario_actualizar];
DROP PROCEDURE IF EXISTS [dbo].[sp_usuario_asignar_rol];
DROP PROCEDURE IF EXISTS [dbo].[sp_usuario_cambiar_password];
DROP PROCEDURE IF EXISTS [dbo].[sp_usuario_consultar];
DROP PROCEDURE IF EXISTS [dbo].[sp_usuario_consultar_por_id];
DROP PROCEDURE IF EXISTS [dbo].[sp_usuario_eliminar];
DROP PROCEDURE IF EXISTS [dbo].[sp_usuario_insertar];
DROP PROCEDURE IF EXISTS [dbo].[sp_usuario_revocar_rol];
DROP PROCEDURE IF EXISTS [dbo].[sp_ventas_crear_factura];
GO

PRINT '66_estandarizacion_nombres.sql aplicado.';
GO
