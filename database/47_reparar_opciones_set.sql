/*
================================================================================
 47_reparar_opciones_set.sql
 Recrea con QUOTED_IDENTIFIER ON y ANSI_NULLS ON los procedimientos, funciones,
 triggers y vistas que se crearon con alguna de esas opciones en OFF.

 Por qué: SQL Server guarda en cada procedimiento las opciones SET con que se
 creó. Uno creado con QUOTED_IDENTIFIER OFF (por ejemplo, un script corrido
 con sqlcmd sin -I, o desde una herramienta con esa opción apagada) no puede
 escribir en una tabla con índice filtrado o índice sobre columna calculada:
 falla con el error 1934 "INSERT failed because the following SET options
 have incorrect settings: 'QUOTED_IDENTIFIER'". En la aplicación se veía como
 "Ocurrió un error en la base de datos" al grabar facturas o registrar
 clientes.

 Qué hace:
   1. Lista los objetos con alguna opción en OFF (antes de reparar).
   2. Recrea cada uno con CREATE OR ALTER y las opciones en ON, a partir de su
      propia definición (no cambia el código ni los permisos).
   3. Lista lo que no se pudo reparar (si queda algo) y el total final.
   4. Crea paDiagnosticoFacturaProbar y la ejecuta: graba una factura de
      prueba y un cliente por NIT dentro de una transacción que se revierte,
      y muestra "OK" o el error real (número, procedimiento, línea).

 No depende de ningún otro script. Se puede volver a correr (si no hay nada en
 OFF no hace nada). Requiere SQL Server 2016 SP1 o superior (CREATE OR ALTER).
================================================================================
*/
USE [erp_db];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

-- 1. Objetos con alguna opción en OFF.
SELECT SCHEMA_NAME(obje.schema_id) + '.' + obje.name AS Objeto, obje.type_desc AS Tipo,
	   modu.uses_quoted_identifier AS QuotedIdentifier, modu.uses_ansi_nulls AS AnsiNulls
FROM sys.sql_modules modu
INNER JOIN sys.objects obje ON obje.object_id = modu.object_id
WHERE (modu.uses_quoted_identifier = 0 OR modu.uses_ansi_nulls = 0)
  AND obje.is_ms_shipped = 0
ORDER BY obje.type_desc, obje.name;
GO

-- 2. Recrear cada uno con las opciones en ON.
DECLARE @objetos TABLE (orden INT IDENTITY(1, 1), objeto NVARCHAR(300), definicion NVARCHAR(MAX));
INSERT INTO @objetos (objeto, definicion)
SELECT SCHEMA_NAME(obje.schema_id) + N'.' + obje.name, modu.definition
FROM sys.sql_modules modu
INNER JOIN sys.objects obje ON obje.object_id = modu.object_id
WHERE (modu.uses_quoted_identifier = 0 OR modu.uses_ansi_nulls = 0)
  AND obje.is_ms_shipped = 0
  AND modu.definition IS NOT NULL
  AND obje.type IN ('P', 'FN', 'IF', 'TF', 'TR', 'V')
-- Funciones y vistas primero (los procedimientos pueden depender de ellas).
ORDER BY CASE obje.type WHEN 'FN' THEN 0 WHEN 'IF' THEN 0 WHEN 'TF' THEN 0 WHEN 'V' THEN 1 ELSE 2 END, obje.name;

DECLARE @i INT = 1, @total INT = (SELECT COUNT(*) FROM @objetos), @reparados INT = 0;
DECLARE @objeto NVARCHAR(300), @def NVARCHAR(MAX), @pos INT, @largo INT, @fin INT, @resto NVARCHAR(MAX), @sql NVARCHAR(MAX);
DECLARE @blancos NVARCHAR(10) = N' ' + CHAR(9) + CHAR(10) + CHAR(13);

WHILE @i <= @total
BEGIN
	SELECT @objeto = objeto, @def = definicion FROM @objetos WHERE orden = @i;

	-- Salta espacios y comentarios del inicio hasta la palabra CREATE.
	SET @pos = 1; SET @largo = LEN(@def + N'x') - 1;
	WHILE @pos <= @largo
	BEGIN
		IF CHARINDEX(SUBSTRING(@def, @pos, 1), @blancos) > 0
			SET @pos += 1;
		ELSE IF SUBSTRING(@def, @pos, 2) = N'--'
		BEGIN
			SET @fin = CHARINDEX(CHAR(10), @def, @pos);
			SET @pos = CASE WHEN @fin = 0 THEN @largo + 1 ELSE @fin + 1 END;
		END
		ELSE IF SUBSTRING(@def, @pos, 2) = N'/*'
		BEGIN
			SET @fin = CHARINDEX(N'*/', @def, @pos + 2);
			SET @pos = CASE WHEN @fin = 0 THEN @largo + 1 ELSE @fin + 2 END;
		END
		ELSE
			BREAK;
	END

	IF UPPER(SUBSTRING(@def, @pos, 6)) <> N'CREATE'
	BEGIN
		PRINT CONCAT(N'NO REPARADO ', @objeto, N': su definición no empieza con CREATE.');
	END
	ELSE
	BEGIN
		-- "CREATE PROCEDURE ..." -> "CREATE OR ALTER PROCEDURE ..." (si ya dice
		-- CREATE OR ALTER se deja igual).
		SET @resto = LTRIM(REPLACE(REPLACE(REPLACE(SUBSTRING(@def, @pos + 6, 40), CHAR(9), N' '), CHAR(13), N' '), CHAR(10), N' '));
		SET @sql = CASE WHEN UPPER(@resto) LIKE N'OR ALTER%' THEN SUBSTRING(@def, @pos, @largo)
						ELSE N'CREATE OR ALTER' + SUBSTRING(@def, @pos + 6, @largo) END;
		BEGIN TRY
			EXEC sys.sp_executesql @sql;
			SET @reparados += 1;
			PRINT CONCAT(N'Reparado: ', @objeto);
		END TRY
		BEGIN CATCH
			PRINT CONCAT(N'NO REPARADO ', @objeto, N': error ', ERROR_NUMBER(), N' - ', ERROR_MESSAGE());
		END CATCH
	END
	SET @i += 1;
END

PRINT CONCAT(N'Objetos con opciones en OFF: ', @total, N'. Reparados: ', @reparados, N'.');
GO

-- 3. Lo que quede en OFF (debe salir vacío).
SELECT SCHEMA_NAME(obje.schema_id) + '.' + obje.name AS PendienteObjeto, obje.type_desc AS Tipo,
	   modu.uses_quoted_identifier AS QuotedIdentifier, modu.uses_ansi_nulls AS AnsiNulls
FROM sys.sql_modules modu
INNER JOIN sys.objects obje ON obje.object_id = modu.object_id
WHERE (modu.uses_quoted_identifier = 0 OR modu.uses_ansi_nulls = 0)
  AND obje.is_ms_shipped = 0
ORDER BY obje.type_desc, obje.name;
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
		SET @paso = 'Grabar la factura (sp_ventas_crear_factura)';
		EXEC dbo.sp_ventas_crear_factura @enc_fecha_docto = @hoy, @enc_numero_autorizacion = NULL, @enc_serie_docto = NULL, @enc_numero_docto = NULL,
			@cli_id = @cli, @enc_nombres_cliente = NULL, @enc_apellidos_cliente = NULL, @cli_nit = NULL, @tdo_id = @tdo, @pve_id = NULL,
			@enc_fecha_primer_pago = @primer, @enc_monto_enganche = 0, @enc_numero_cuotas = 1, @enc_valor_descuento = 0,
			@enc_direccion_cliente = NULL, @mon_id = @mon, @usu_id = @usu, @detalle = @detalle, @pca_id = NULL, @formas_pago = @formas,
			@enc_id = @enc OUTPUT, @enc_numero_unico = @numero OUTPUT;
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

EXEC dbo.paDiagnosticoFacturaProbar;
GO

PRINT '47_reparar_opciones_set.sql aplicado.';
GO
