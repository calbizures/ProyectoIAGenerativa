/*
	Script 08: Funciones escalares.

	Se conserva la lógica de negocio del script original (nombres,
	direcciones, números en letras, últimos movimientos de un producto),
	adaptada a los nombres/tipos de columna nuevos y con LEFT JOIN donde
	antes un INNER JOIN podía devolver NULL silenciosamente si al cliente
	le faltaba un dato de geografía.
*/
USE [erp_db];
GO

-- Id de la moneda local/funcional de la compañía, usada como valor por
-- defecto en los procedimientos de negocio cuando no se indica moneda.
CREATE OR ALTER FUNCTION [dbo].[fn_moneda_local]()
RETURNS INT
AS
BEGIN
	RETURN (SELECT TOP 1 [mon_id] FROM [dbo].[gen_moneda] WHERE [mon_es_local] = 1);
END;
GO

-- select dbo.fn_direccion_completa_cliente(2)
CREATE OR ALTER FUNCTION [dbo].[fn_direccion_completa_cliente] (@cli_id INT)
RETURNS VARCHAR(1000)
AS
BEGIN
	DECLARE @DireccionCompleta VARCHAR(1000);

	SELECT @DireccionCompleta = ISNULL(cli.cli_direccion, '')
			+ ISNULL(', ' + prv.prov_nombre, '')
			+ ISNULL(', ' + est.est_nombre, '')
	FROM dbo.pos_cliente cli
	LEFT JOIN dbo.gen_provincia prv ON prv.prov_id = cli.cli_direccion_provincia
	LEFT JOIN dbo.gen_estado est ON est.est_id = cli.cli_direccion_estado
	WHERE cli.cli_id = @cli_id;

	RETURN @DireccionCompleta;
END;
GO

-- select dbo.fn_nombre_completo_cliente(2)
CREATE OR ALTER FUNCTION [dbo].[fn_nombre_completo_cliente] (@cli_id INT)
RETURNS VARCHAR(200)
AS
BEGIN
	DECLARE @NombreCompleto VARCHAR(200);

	SELECT @NombreCompleto = ISNULL(cli.cli_nombres, '') + ISNULL(' ' + cli.cli_apellidos, '')
	FROM dbo.pos_cliente cli
	WHERE cli.cli_id = @cli_id;

	RETURN @NombreCompleto;
END;
GO

-- select dbo.fn_nombre_completo_cliente_encabezado(2)
CREATE OR ALTER FUNCTION [dbo].[fn_nombre_completo_cliente_encabezado] (@enc_id INT)
RETURNS VARCHAR(256)
AS
BEGIN
	DECLARE @NombreCompleto VARCHAR(256);

	SELECT @NombreCompleto = ISNULL(enc.enc_nombres_cliente, '') + ISNULL(' ' + enc.enc_apellidos_cliente, '')
	FROM dbo.inv_documento_enc enc
	WHERE enc.enc_id = @enc_id;

	RETURN @NombreCompleto;
END;
GO

-- select dbo.fn_ultimo_costo_unitario(51)
CREATE OR ALTER FUNCTION [dbo].[fn_ultimo_costo_unitario] (@pro_id INT)
RETURNS NUMERIC(12, 5)
AS
BEGIN
	DECLARE @costo_unitario NUMERIC(12, 5);

	SELECT TOP 1 @costo_unitario = ISNULL(det.det_precio_unitario, det.det_costo_unitario)
	FROM dbo.inv_documento_det det
	INNER JOIN dbo.inv_documento_enc enc ON enc.enc_id = det.enc_id
	INNER JOIN dbo.inv_documento_tipo tip ON tip.tdo_id = enc.tdo_id
	WHERE tip.tdo_naturaleza = '+'
	  AND det.pro_id = @pro_id
	  AND enc.enc_estado = 'G'
	ORDER BY enc.enc_fecha_docto DESC;

	RETURN @costo_unitario;
END;
GO

-- select dbo.fn_descripcion_ultimo_movimiento(52)
CREATE OR ALTER FUNCTION [dbo].[fn_descripcion_ultimo_movimiento] (@pro_id INT)
RETURNS VARCHAR(100)
AS
BEGIN
	DECLARE @tdo_descripcion VARCHAR(128);

	SELECT TOP 1 @tdo_descripcion = tip.tdo_descripcion
	FROM dbo.inv_documento_det det
	INNER JOIN dbo.inv_documento_enc enc ON enc.enc_id = det.enc_id
	INNER JOIN dbo.inv_documento_tipo tip ON tip.tdo_id = enc.tdo_id
	WHERE tip.tdo_naturaleza = '+'
	  AND det.pro_id = @pro_id
	  AND enc.enc_estado = 'G'
	ORDER BY enc.enc_fecha_docto DESC;

	RETURN @tdo_descripcion;
END;
GO

-- select dbo.fn_fecha_ultimo_movimiento(51)
CREATE OR ALTER FUNCTION [dbo].[fn_fecha_ultimo_movimiento] (@pro_id INT)
RETURNS DATE
AS
BEGIN
	DECLARE @fecha_documento DATE;

	SELECT TOP 1 @fecha_documento = enc.enc_fecha_docto
	FROM dbo.inv_documento_det det
	INNER JOIN dbo.inv_documento_enc enc ON enc.enc_id = det.enc_id
	INNER JOIN dbo.inv_documento_tipo tip ON tip.tdo_id = enc.tdo_id
	WHERE tip.tdo_naturaleza = '+'
	  AND det.pro_id = @pro_id
	  AND enc.enc_estado = 'G'
	ORDER BY enc.enc_fecha_docto DESC;

	RETURN @fecha_documento;
END;
GO

/*
	select dbo.fn_numeros_a_letras(13525.43)
	Convierte un monto a letras en Quetzales. Práctico hasta 999,999,999.99;
	no se extendió a billones porque ningún monto del modelo llega a esa
	magnitud.
*/
CREATE OR ALTER FUNCTION [dbo].[fn_numeros_a_letras]
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
