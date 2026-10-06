/*
================================================================================
 60_contabilidad_libros_estados.sql
 Contabilidad completa para el usuario: pólizas manuales, libros, balanza,
 estados financieros y cierres.

   - Pólizas: consulta de todas las pólizas (automáticas y manuales) con su
     documento de origen; póliza manual con varias líneas, centro de costo
     por línea y validación de cuadre, cuentas de detalle activas y período
     abierto; anulación de pólizas manuales y de cierre con motivo.
   - Libro diario, libro mayor (saldo inicial, movimientos y saldo corrido por
     cuenta) y balanza de comprobación por nivel de la nomenclatura.
   - Estados financieros:
       * Balance General a una fecha (activo, pasivo y capital por nivel, con
         el resultado del ejercicio y, si los hay, los resultados de años
         anteriores sin cierre), con comparativo a otra fecha;
       * Estado de Resultados de un período (ingresos, costo, utilidad bruta,
         gastos y utilidad neta), con comparativo a otro período. No toma en
         cuenta la partida de cierre anual.
   - Períodos contables: cerrar y volver a abrir un mes (en un período cerrado
     no se graban ni se anulan pólizas, script 50).
   - Cierre anual: partida al 31 de diciembre que salda las cuentas de
     resultados contra Utilidades o Pérdidas del ejercicio.
   - Corrección: el gasto de la cuota patronal del IRTRA iba a FALTANTES DE
     INVENTARIO (no había cuenta propia); se crea CUOTA PATRONAL IRTRA.

 Errores nuevos: 55001 a 55030.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Columnas nuevas
------------------------------------------------------------
IF COL_LENGTH('dbo.cont_asiento_enc', 'asi_motivo_anulacion') IS NULL
	ALTER TABLE dbo.cont_asiento_enc ADD [asi_motivo_anulacion] VARCHAR(250) NULL;
GO
IF COL_LENGTH('dbo.cont_periodo_contable', 'pdo_fecha_cierre') IS NULL
	ALTER TABLE dbo.cont_periodo_contable ADD
		[pdo_fecha_cierre]	DATETIME2(0)	NULL,
		[usu_id_cierre]		INT				NULL
			CONSTRAINT [FK_cont_periodo_contable_usuario_cierre] FOREIGN KEY REFERENCES dbo.gen_usuario ([usu_id]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cont_asiento_enc_fecha')
	CREATE INDEX [IX_cont_asiento_enc_fecha] ON dbo.cont_asiento_enc ([asi_fecha], [asi_estado]) INCLUDE ([asi_origen], [asi_origen_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cont_asiento_det_cuenta')
	CREATE INDEX [IX_cont_asiento_det_cuenta] ON dbo.cont_asiento_det ([cta_id], [asi_id]) INCLUDE ([asd_debe], [asd_haber]);
GO

------------------------------------------------------------
-- 2. Cuentas: IRTRA y cierre anual
------------------------------------------------------------
-- La cuota patronal del IRTRA estaba parametrizada a FALTANTES DE INVENTARIO.
-- Solo se corrige con la nomenclatura base (cuenta 511 y el parámetro aún en
-- la cuenta de faltantes); con otra nomenclatura no se toca.
IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_codigo = '5110074')
   AND EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_codigo = '511')
   AND EXISTS (SELECT 1 FROM dbo.cont_cuenta_parametro parm INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = parm.cta_id
			   WHERE parm.ccp_codigo = 'NOMINA_IRTRA_GASTO' AND cuen.cta_nombre LIKE '%FALTANTE%INVENTARIO%')
	INSERT INTO dbo.cont_cuenta_contable (cta_codigo, cta_nombre, cta_tipo, cta_naturaleza, cta_acepta_movimiento, cta_id_padre, cta_nivel, InsFechaHora)
	SELECT '5110074', 'CUOTA PATRONAL IRTRA', 'G', 'D', 1, cta_id, 4, SYSDATETIME() FROM dbo.cont_cuenta_contable WHERE cta_codigo = '511';
UPDATE parm
   SET cta_id = nuev.cta_id, UpdFechaHora = SYSDATETIME()
FROM dbo.cont_cuenta_parametro parm
INNER JOIN dbo.cont_cuenta_contable actu ON actu.cta_id = parm.cta_id
CROSS JOIN (SELECT cta_id FROM dbo.cont_cuenta_contable WHERE cta_codigo = '5110074') nuev
WHERE parm.ccp_codigo = 'NOMINA_IRTRA_GASTO' AND actu.cta_nombre LIKE '%FALTANTE%INVENTARIO%';
GO

-- Cuentas de la partida de cierre (UTILIDADES / PÉRDIDAS DEL EJERCICIO).
INSERT INTO dbo.cont_cuenta_parametro (ccp_codigo, ccp_descripcion, ccp_naturaleza, cta_id, InsFechaHora)
SELECT v.codigo, v.descripcion, v.naturaleza,
	   (SELECT TOP 1 cuen.cta_id FROM dbo.cont_cuenta_contable cuen
		WHERE cuen.cta_acepta_movimiento = 1 AND cuen.cta_tipo = 'K' AND cuen.cta_nombre LIKE v.nombre ORDER BY cuen.cta_codigo),
	   SYSDATETIME()
FROM (VALUES
	('CIERRE_UTILIDAD', 'Cierre anual: utilidad del ejercicio', 'H', 'UTILIDAD%DEL EJERCICIO'),
	('CIERRE_PERDIDA',  'Cierre anual: pérdida del ejercicio',  'D', 'PERDIDA%DEL EJERCICIO')) v (codigo, descripcion, naturaleza, nombre)
WHERE NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_parametro parm WHERE parm.ccp_codigo = v.codigo);
GO

------------------------------------------------------------
-- 3. Pólizas
------------------------------------------------------------
-- @Origen NULL: todos; 'MANUAL', 'VENTA', ... ; @Texto busca en la descripción,
-- el número de póliza y el documento.
CREATE OR ALTER PROCEDURE [dbo].[paPolizaConsultar]
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL,
	@Origen	VARCHAR(20) = NULL,
	@Estado	CHAR(1) = NULL,
	@Texto	VARCHAR(100) = NULL,
	@CtaId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @Texto = NULLIF(LTRIM(RTRIM(@Texto)), '');
	SELECT asie.asi_id AS AsiId, asie.asi_fecha AS Fecha, asie.asi_descripcion AS Descripcion, asie.asi_origen AS Origen,
		   asie.asi_origen_id AS OrigenId, asie.asi_estado AS Estado, asie.asi_motivo_anulacion AS MotivoAnulacion,
		   tota.Debe AS Total, tota.Lineas, usua.usu_codigo AS Usuario, peri.pdo_estado AS EstadoPeriodo,
		   CASE WHEN docu.enc_id IS NOT NULL THEN CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto) END AS Documento,
		   asie.enc_id AS EncId
	FROM dbo.cont_asiento_enc asie
	CROSS APPLY (SELECT SUM(deta.asd_debe) AS Debe, COUNT(*) AS Lineas FROM dbo.cont_asiento_det deta WHERE deta.asi_id = asie.asi_id) tota
	INNER JOIN dbo.cont_periodo_contable peri ON peri.pdo_id = asie.pdo_id
	LEFT JOIN dbo.inv_documento_enc docu ON docu.enc_id = asie.enc_id
	LEFT JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = asie.usu_id
	WHERE (@Desde IS NULL OR asie.asi_fecha >= @Desde)
	  AND (@Hasta IS NULL OR asie.asi_fecha <= @Hasta)
	  AND (@Origen IS NULL OR asie.asi_origen = @Origen)
	  AND (@Estado IS NULL OR asie.asi_estado = @Estado)
	  AND (@CtaId IS NULL OR EXISTS (SELECT 1 FROM dbo.cont_asiento_det deta WHERE deta.asi_id = asie.asi_id AND deta.cta_id = @CtaId))
	  AND (@Texto IS NULL OR asie.asi_descripcion LIKE '%' + @Texto + '%' OR CAST(asie.asi_id AS VARCHAR(12)) = @Texto
		   OR docu.enc_numero_docto LIKE '%' + @Texto + '%')
	ORDER BY asie.asi_fecha DESC, asie.asi_id DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paPolizaConsultarPorId]
	@AsiId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT asie.asi_id AS AsiId, asie.asi_fecha AS Fecha, asie.asi_descripcion AS Descripcion, asie.asi_origen AS Origen,
		   asie.asi_origen_id AS OrigenId, asie.asi_estado AS Estado, asie.asi_motivo_anulacion AS MotivoAnulacion,
		   usua.usu_codigo AS Usuario, asie.asi_fecha_creacion AS Creada, peri.pdo_estado AS EstadoPeriodo,
		   CASE WHEN docu.enc_id IS NOT NULL THEN CONCAT(tipo.tdo_codigo, ' ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto) END AS Documento,
		   asie.enc_id AS EncId
	FROM dbo.cont_asiento_enc asie
	INNER JOIN dbo.cont_periodo_contable peri ON peri.pdo_id = asie.pdo_id
	LEFT JOIN dbo.inv_documento_enc docu ON docu.enc_id = asie.enc_id
	LEFT JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = docu.tdo_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = asie.usu_id
	WHERE asie.asi_id = @AsiId;

	SELECT deta.asd_id AS AsdId, deta.cta_id AS CtaId, cuen.cta_codigo AS Codigo, cuen.cta_nombre AS Cuenta,
		   deta.asd_debe AS Debe, deta.asd_haber AS Haber, deta.asd_descripcion AS Descripcion,
		   deta.IdDepartamento, depa.Descripcion AS Departamento
	FROM dbo.cont_asiento_det deta
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = deta.cta_id
	LEFT JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = deta.IdDepartamento
	WHERE deta.asi_id = @AsiId
	ORDER BY deta.asd_id;
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

-- Se anulan aquí solo las pólizas manuales y la de cierre anual; las demás se
-- anulan desde su documento (factura, compra, cheque...).
CREATE OR ALTER PROCEDURE [dbo].[paPolizaAnular]
	@AsiId	INT,
	@Motivo	VARCHAR(250),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @origen VARCHAR(20), @estado CHAR(1);
	SELECT @origen = asi_origen, @estado = asi_estado FROM dbo.cont_asiento_enc WHERE asi_id = @AsiId;
	IF @origen IS NULL
		THROW 55008, 'La póliza no existe.', 1;
	IF @estado <> 'A'
		THROW 55009, 'La póliza ya está anulada.', 1;
	IF @origen NOT IN ('MANUAL', 'CIERRE_ANUAL')
		THROW 55010, 'Esta póliza se generó desde un documento: anule el documento (factura, compra, cheque, recibo...) y su póliza se anula con él.', 1;
	IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, '')))) < 5
		THROW 55011, 'Indique el motivo de la anulación (al menos 5 caracteres).', 1;
	UPDATE dbo.cont_asiento_enc
	   SET asi_estado = 'N', asi_motivo_anulacion = LTRIM(RTRIM(@Motivo)), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE asi_id = @AsiId;
END;
GO

------------------------------------------------------------
-- 4. Libros
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paLibroDiarioConsultar]
	@Desde	DATE,
	@Hasta	DATE
AS
BEGIN
	SET NOCOUNT ON;
	IF @Hasta < @Desde
		THROW 55012, 'La fecha final no puede ser anterior a la inicial.', 1;
	SELECT asie.asi_id AS AsiId, asie.asi_fecha AS Fecha, asie.asi_descripcion AS Descripcion, asie.asi_origen AS Origen,
		   cuen.cta_codigo AS Codigo, cuen.cta_nombre AS Cuenta, deta.asd_debe AS Debe, deta.asd_haber AS Haber,
		   deta.asd_descripcion AS DescripcionLinea
	FROM dbo.cont_asiento_enc asie
	INNER JOIN dbo.cont_asiento_det deta ON deta.asi_id = asie.asi_id
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = deta.cta_id
	WHERE asie.asi_estado = 'A' AND asie.asi_fecha BETWEEN @Desde AND @Hasta
	ORDER BY asie.asi_fecha, asie.asi_id, CASE WHEN deta.asd_debe > 0 THEN 0 ELSE 1 END, deta.asd_id;
END;
GO

-- @CtaId: una cuenta de detalle, o una de agrupación (todas sus cuentas de
-- detalle); NULL = todas las que tienen saldo o movimiento.
-- Saldo con el signo de la naturaleza de la cuenta (deudora: Debe - Haber).
CREATE OR ALTER PROCEDURE [dbo].[paLibroMayorConsultar]
	@Desde	DATE,
	@Hasta	DATE,
	@CtaId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @Hasta < @Desde
		THROW 55012, 'La fecha final no puede ser anterior a la inicial.', 1;
	DECLARE @prefijo VARCHAR(20) = (SELECT cta_codigo FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId);

	DECLARE @cuentas TABLE (cta_id INT PRIMARY KEY, codigo VARCHAR(20), nombre VARCHAR(128), naturaleza CHAR(1), inicial NUMERIC(16, 2), debe NUMERIC(16, 2), haber NUMERIC(16, 2));
	INSERT INTO @cuentas
	SELECT cuen.cta_id, cuen.cta_codigo, cuen.cta_nombre, cuen.cta_naturaleza,
		   ISNULL(SUM(CASE WHEN asie.asi_fecha < @Desde THEN deta.asd_debe - deta.asd_haber END), 0),
		   ISNULL(SUM(CASE WHEN asie.asi_fecha >= @Desde THEN deta.asd_debe END), 0),
		   ISNULL(SUM(CASE WHEN asie.asi_fecha >= @Desde THEN deta.asd_haber END), 0)
	FROM dbo.cont_cuenta_contable cuen
	LEFT JOIN dbo.cont_asiento_det deta ON deta.cta_id = cuen.cta_id
	LEFT JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id AND asie.asi_estado = 'A' AND asie.asi_fecha <= @Hasta
	WHERE cuen.cta_acepta_movimiento = 1
	  AND (@prefijo IS NULL OR cuen.cta_codigo LIKE @prefijo + '%')
	  AND (asie.asi_id IS NOT NULL OR deta.asd_id IS NULL)
	GROUP BY cuen.cta_id, cuen.cta_codigo, cuen.cta_nombre, cuen.cta_naturaleza;
	DELETE FROM @cuentas WHERE inicial = 0 AND debe = 0 AND haber = 0 AND @CtaId IS NULL;

	SELECT cta_id AS CtaId, codigo AS Codigo, nombre AS Cuenta, naturaleza AS Naturaleza,
		   CASE naturaleza WHEN 'D' THEN inicial ELSE -inicial END AS SaldoInicial, debe AS Debe, haber AS Haber,
		   CASE naturaleza WHEN 'D' THEN inicial + debe - haber ELSE -(inicial + debe - haber) END AS SaldoFinal
	FROM @cuentas ORDER BY codigo;

	SELECT deta.cta_id AS CtaId, asie.asi_fecha AS Fecha, asie.asi_id AS AsiId, asie.asi_origen AS Origen,
		   ISNULL(deta.asd_descripcion, asie.asi_descripcion) AS Descripcion, deta.asd_debe AS Debe, deta.asd_haber AS Haber
	FROM dbo.cont_asiento_det deta
	INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id AND asie.asi_estado = 'A'
	INNER JOIN @cuentas cuen ON cuen.cta_id = deta.cta_id
	WHERE asie.asi_fecha BETWEEN @Desde AND @Hasta
	ORDER BY cuen.codigo, asie.asi_fecha, asie.asi_id, deta.asd_id;
END;
GO

-- Saldos por cuenta de detalle en un rango, acumulados a las cuentas padre
-- (el código de cada cuenta empieza con el de su padre).
CREATE OR ALTER FUNCTION [dbo].[fnContSaldosRango] (@Desde DATE, @Hasta DATE, @SinCierre BIT)
RETURNS TABLE
AS
RETURN
	SELECT cuen.cta_id, ISNULL(SUM(deta.asd_debe), 0) AS debe, ISNULL(SUM(deta.asd_haber), 0) AS haber
	FROM dbo.cont_cuenta_contable cuen
	INNER JOIN dbo.cont_asiento_det deta ON deta.cta_id = cuen.cta_id
	INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id AND asie.asi_estado = 'A'
	WHERE cuen.cta_acepta_movimiento = 1
	  AND (@Desde IS NULL OR asie.asi_fecha >= @Desde) AND asie.asi_fecha <= @Hasta
	  AND (@SinCierre = 0 OR asie.asi_origen <> 'CIERRE_ANUAL')
	GROUP BY cuen.cta_id;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBalanzaComprobacionConsultar]
	@Desde	DATE,
	@Hasta	DATE,
	@Nivel	INT = 4
AS
BEGIN
	SET NOCOUNT ON;
	IF @Hasta < @Desde
		THROW 55012, 'La fecha final no puede ser anterior a la inicial.', 1;
	DECLARE @antes DATE = DATEADD(DAY, -1, @Desde);

	WITH detalle AS (
		SELECT cuen.cta_id, cuen.cta_codigo,
			   ISNULL(inic.debe, 0) - ISNULL(inic.haber, 0) AS inicial, ISNULL(movi.debe, 0) AS debe, ISNULL(movi.haber, 0) AS haber
		FROM dbo.cont_cuenta_contable cuen
		LEFT JOIN dbo.fnContSaldosRango(NULL, @antes, 0) inic ON inic.cta_id = cuen.cta_id
		LEFT JOIN dbo.fnContSaldosRango(@Desde, @Hasta, 0) movi ON movi.cta_id = cuen.cta_id
		WHERE cuen.cta_acepta_movimiento = 1
	), acumulado AS (
		SELECT padr.cta_id, padr.cta_codigo, padr.cta_nombre, padr.cta_nivel, padr.cta_tipo, padr.cta_naturaleza,
			   SUM(deta.inicial) AS inicial, SUM(deta.debe) AS debe, SUM(deta.haber) AS haber
		FROM dbo.cont_cuenta_contable padr
		INNER JOIN detalle deta ON deta.cta_codigo LIKE padr.cta_codigo + '%'
		WHERE padr.cta_nivel <= @Nivel
		GROUP BY padr.cta_id, padr.cta_codigo, padr.cta_nombre, padr.cta_nivel, padr.cta_tipo, padr.cta_naturaleza
	)
	SELECT cta_id AS CtaId, cta_codigo AS Codigo, cta_nombre AS Cuenta, cta_nivel AS Nivel, cta_tipo AS Tipo, cta_naturaleza AS Naturaleza,
		   IIF(inicial > 0, inicial, 0) AS InicialDeudor, IIF(inicial < 0, -inicial, 0) AS InicialAcreedor,
		   debe AS Debe, haber AS Haber,
		   IIF(inicial + debe - haber > 0, inicial + debe - haber, 0) AS FinalDeudor,
		   IIF(inicial + debe - haber < 0, -(inicial + debe - haber), 0) AS FinalAcreedor
	FROM acumulado
	WHERE inicial <> 0 OR debe <> 0 OR haber <> 0
	ORDER BY cta_codigo;
END;
GO

------------------------------------------------------------
-- 5. Estados financieros
------------------------------------------------------------
-- Balance General a @Fecha (y a @FechaComparativa si se indica). Saldo de cada
-- cuenta con el signo de su naturaleza; las de resultados se presentan como
-- "Resultado del ejercicio" (del 1 de enero a la fecha) y "Resultados de
-- ejercicios anteriores sin cierre".
CREATE OR ALTER PROCEDURE [dbo].[paBalanceGeneralConsultar]
	@Fecha				DATE,
	@Nivel				INT = 3,
	@FechaComparativa	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @inicioAnio DATE = DATEFROMPARTS(YEAR(@Fecha), 1, 1);
	DECLARE @inicioAnioC DATE = CASE WHEN @FechaComparativa IS NULL THEN NULL ELSE DATEFROMPARTS(YEAR(@FechaComparativa), 1, 1) END;

	WITH detalle AS (
		SELECT cuen.cta_id, cuen.cta_codigo, cuen.cta_tipo,
			   ISNULL(actu.debe, 0) - ISNULL(actu.haber, 0) AS neto,
			   ISNULL(comp.debe, 0) - ISNULL(comp.haber, 0) AS neto_comp
		FROM dbo.cont_cuenta_contable cuen
		LEFT JOIN dbo.fnContSaldosRango(NULL, @Fecha, 0) actu ON actu.cta_id = cuen.cta_id
		LEFT JOIN dbo.fnContSaldosRango(NULL, ISNULL(@FechaComparativa, '19000101'), 0) comp ON comp.cta_id = cuen.cta_id AND @FechaComparativa IS NOT NULL
		WHERE cuen.cta_acepta_movimiento = 1 AND cuen.cta_tipo IN ('A', 'P', 'K')
	)
	SELECT padr.cta_id AS CtaId, padr.cta_codigo AS Codigo, padr.cta_nombre AS Cuenta, padr.cta_nivel AS Nivel, padr.cta_tipo AS Tipo,
		   SUM(CASE WHEN padr.cta_tipo = 'A' THEN deta.neto ELSE -deta.neto END) AS Saldo,
		   SUM(CASE WHEN padr.cta_tipo = 'A' THEN deta.neto_comp ELSE -deta.neto_comp END) AS SaldoComparativo
	FROM dbo.cont_cuenta_contable padr
	INNER JOIN detalle deta ON deta.cta_codigo LIKE padr.cta_codigo + '%'
	WHERE padr.cta_nivel <= @Nivel AND padr.cta_tipo IN ('A', 'P', 'K')
	GROUP BY padr.cta_id, padr.cta_codigo, padr.cta_nombre, padr.cta_nivel, padr.cta_tipo
	HAVING SUM(deta.neto) <> 0 OR SUM(deta.neto_comp) <> 0
	ORDER BY padr.cta_codigo;

	-- Totales y resultados (signo acreedor: positivo = utilidad).
	SELECT
		(SELECT ISNULL(SUM(saldo.debe - saldo.haber), 0) FROM dbo.fnContSaldosRango(NULL, @Fecha, 0) saldo
		 INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = saldo.cta_id WHERE cuen.cta_tipo = 'A') AS Activo,
		(SELECT ISNULL(SUM(saldo.haber - saldo.debe), 0) FROM dbo.fnContSaldosRango(NULL, @Fecha, 0) saldo
		 INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = saldo.cta_id WHERE cuen.cta_tipo = 'P') AS Pasivo,
		(SELECT ISNULL(SUM(saldo.haber - saldo.debe), 0) FROM dbo.fnContSaldosRango(NULL, @Fecha, 0) saldo
		 INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = saldo.cta_id WHERE cuen.cta_tipo = 'K') AS Capital,
		(SELECT ISNULL(SUM(saldo.haber - saldo.debe), 0) FROM dbo.fnContSaldosRango(@inicioAnio, @Fecha, 0) saldo
		 INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = saldo.cta_id WHERE cuen.cta_tipo IN ('I', 'G')) AS ResultadoEjercicio,
		(SELECT ISNULL(SUM(saldo.haber - saldo.debe), 0) FROM dbo.fnContSaldosRango(NULL, DATEADD(DAY, -1, @inicioAnio), 0) saldo
		 INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = saldo.cta_id WHERE cuen.cta_tipo IN ('I', 'G')) AS ResultadosAnteriores,
		-- Comparativo
		(SELECT ISNULL(SUM(saldo.debe - saldo.haber), 0) FROM dbo.fnContSaldosRango(NULL, @FechaComparativa, 0) saldo
		 INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = saldo.cta_id WHERE cuen.cta_tipo = 'A' AND @FechaComparativa IS NOT NULL) AS ActivoComparativo,
		(SELECT ISNULL(SUM(saldo.haber - saldo.debe), 0) FROM dbo.fnContSaldosRango(NULL, @FechaComparativa, 0) saldo
		 INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = saldo.cta_id WHERE cuen.cta_tipo = 'P' AND @FechaComparativa IS NOT NULL) AS PasivoComparativo,
		(SELECT ISNULL(SUM(saldo.haber - saldo.debe), 0) FROM dbo.fnContSaldosRango(NULL, @FechaComparativa, 0) saldo
		 INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = saldo.cta_id WHERE cuen.cta_tipo = 'K' AND @FechaComparativa IS NOT NULL) AS CapitalComparativo,
		(SELECT ISNULL(SUM(saldo.haber - saldo.debe), 0) FROM dbo.fnContSaldosRango(@inicioAnioC, @FechaComparativa, 0) saldo
		 INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = saldo.cta_id WHERE cuen.cta_tipo IN ('I', 'G') AND @FechaComparativa IS NOT NULL) AS ResultadoEjercicioComparativo,
		(SELECT ISNULL(SUM(saldo.haber - saldo.debe), 0) FROM dbo.fnContSaldosRango(NULL, DATEADD(DAY, -1, @inicioAnioC), 0) saldo
		 INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = saldo.cta_id WHERE cuen.cta_tipo IN ('I', 'G') AND @FechaComparativa IS NOT NULL) AS ResultadosAnterioresComparativo;
END;
GO

-- Estado de Resultados de @Desde a @Hasta (sin la partida de cierre anual).
-- Saldo con el signo de la naturaleza (ingresos y costos en positivo).
CREATE OR ALTER PROCEDURE [dbo].[paEstadoResultadosConsultar]
	@Desde				DATE,
	@Hasta				DATE,
	@Nivel				INT = 3,
	@DesdeComparativo	DATE = NULL,
	@HastaComparativo	DATE = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @Hasta < @Desde OR @HastaComparativo < @DesdeComparativo
		THROW 55012, 'La fecha final no puede ser anterior a la inicial.', 1;
	DECLARE @comparar BIT = IIF(@DesdeComparativo IS NOT NULL AND @HastaComparativo IS NOT NULL, 1, 0);

	WITH detalle AS (
		SELECT cuen.cta_id, cuen.cta_codigo,
			   ISNULL(actu.haber, 0) - ISNULL(actu.debe, 0) AS acreedor,
			   ISNULL(comp.haber, 0) - ISNULL(comp.debe, 0) AS acreedor_comp
		FROM dbo.cont_cuenta_contable cuen
		LEFT JOIN dbo.fnContSaldosRango(@Desde, @Hasta, 1) actu ON actu.cta_id = cuen.cta_id
		LEFT JOIN dbo.fnContSaldosRango(ISNULL(@DesdeComparativo, '19000101'), ISNULL(@HastaComparativo, '19000101'), 1) comp
			ON comp.cta_id = cuen.cta_id AND @comparar = 1
		WHERE cuen.cta_acepta_movimiento = 1 AND cuen.cta_tipo IN ('I', 'G')
	)
	SELECT padr.cta_id AS CtaId, padr.cta_codigo AS Codigo, padr.cta_nombre AS Cuenta, padr.cta_nivel AS Nivel, padr.cta_tipo AS Tipo,
		   padr.cta_naturaleza AS Naturaleza,
		   SUM(CASE WHEN padr.cta_naturaleza = 'H' THEN deta.acreedor ELSE -deta.acreedor END) AS Saldo,
		   SUM(CASE WHEN padr.cta_naturaleza = 'H' THEN deta.acreedor_comp ELSE -deta.acreedor_comp END) AS SaldoComparativo
	FROM dbo.cont_cuenta_contable padr
	INNER JOIN detalle deta ON deta.cta_codigo LIKE padr.cta_codigo + '%'
	WHERE padr.cta_nivel <= @Nivel AND padr.cta_tipo IN ('I', 'G')
	GROUP BY padr.cta_id, padr.cta_codigo, padr.cta_nombre, padr.cta_nivel, padr.cta_tipo, padr.cta_naturaleza
	HAVING SUM(deta.acreedor) <> 0 OR SUM(deta.acreedor_comp) <> 0
	ORDER BY padr.cta_codigo;

	-- Utilidad bruta = cuentas de ingresos (incluye el costo de ventas si la
	-- nomenclatura lo tiene dentro de ingresos); gastos = cuentas de gastos.
	-- Ingresos y costos se separan por la naturaleza de la cuenta de mayor
	-- (411 ingresos brutos, acreedora; 412 costo de ventas, deudora), así una
	-- devolución dentro de 411 resta de los ingresos y no se suma al costo.
	SELECT
		ISNULL(SUM(CASE WHEN cuen.cta_tipo = 'I' THEN saldo.haber - saldo.debe END), 0) AS UtilidadBruta,
		ISNULL(SUM(CASE WHEN cuen.cta_tipo = 'I' AND ISNULL(mayo.cta_naturaleza, cuen.cta_naturaleza) = 'H' THEN saldo.haber - saldo.debe END), 0) AS Ingresos,
		ISNULL(SUM(CASE WHEN cuen.cta_tipo = 'I' AND ISNULL(mayo.cta_naturaleza, cuen.cta_naturaleza) = 'D' THEN saldo.debe - saldo.haber END), 0) AS Costos,
		ISNULL(SUM(CASE WHEN cuen.cta_tipo = 'G' THEN saldo.debe - saldo.haber END), 0) AS Gastos,
		ISNULL(SUM(saldo.haber - saldo.debe), 0) AS UtilidadNeta
	FROM dbo.fnContSaldosRango(@Desde, @Hasta, 1) saldo
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = saldo.cta_id AND cuen.cta_tipo IN ('I', 'G')
	OUTER APPLY (SELECT TOP 1 padr.cta_naturaleza FROM dbo.cont_cuenta_contable padr
				 WHERE padr.cta_nivel = 3 AND cuen.cta_codigo LIKE padr.cta_codigo + '%' ORDER BY LEN(padr.cta_codigo) DESC) mayo;

	SELECT
		ISNULL(SUM(CASE WHEN cuen.cta_tipo = 'I' THEN saldo.haber - saldo.debe END), 0) AS UtilidadBruta,
		ISNULL(SUM(CASE WHEN cuen.cta_tipo = 'I' AND ISNULL(mayo.cta_naturaleza, cuen.cta_naturaleza) = 'H' THEN saldo.haber - saldo.debe END), 0) AS Ingresos,
		ISNULL(SUM(CASE WHEN cuen.cta_tipo = 'I' AND ISNULL(mayo.cta_naturaleza, cuen.cta_naturaleza) = 'D' THEN saldo.debe - saldo.haber END), 0) AS Costos,
		ISNULL(SUM(CASE WHEN cuen.cta_tipo = 'G' THEN saldo.debe - saldo.haber END), 0) AS Gastos,
		ISNULL(SUM(saldo.haber - saldo.debe), 0) AS UtilidadNeta
	FROM dbo.fnContSaldosRango(ISNULL(@DesdeComparativo, '19000101'), ISNULL(@HastaComparativo, '19000101'), 1) saldo
	INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = saldo.cta_id AND cuen.cta_tipo IN ('I', 'G')
	OUTER APPLY (SELECT TOP 1 padr.cta_naturaleza FROM dbo.cont_cuenta_contable padr
				 WHERE padr.cta_nivel = 3 AND cuen.cta_codigo LIKE padr.cta_codigo + '%' ORDER BY LEN(padr.cta_codigo) DESC) mayo
	WHERE @comparar = 1;
END;
GO

------------------------------------------------------------
-- 6. Períodos y cierre anual
------------------------------------------------------------
-- Los 12 meses del año (los que aún no existen aparecen abiertos, sin id).
CREATE OR ALTER PROCEDURE [dbo].[paPeriodoContableConsultar]
	@Anio	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT @Anio AS Anio, mese.mes AS Mes, peri.pdo_id AS PdoId, ISNULL(peri.pdo_estado, 'A') AS Estado,
		   peri.pdo_fecha_cierre AS FechaCierre, usua.usu_codigo AS CerradoPor,
		   ISNULL(tota.Polizas, 0) AS Polizas, ISNULL(tota.Anuladas, 0) AS Anuladas, ISNULL(tota.Debe, 0) AS Total
	FROM (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12)) mese (mes)
	LEFT JOIN dbo.cont_periodo_contable peri ON peri.pdo_anio = @Anio AND peri.pdo_mes = mese.mes
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = peri.usu_id_cierre
	OUTER APPLY (SELECT SUM(IIF(asie.asi_estado = 'A', 1, 0)) AS Polizas, SUM(IIF(asie.asi_estado = 'N', 1, 0)) AS Anuladas,
						(SELECT SUM(deta.asd_debe) FROM dbo.cont_asiento_det deta INNER JOIN dbo.cont_asiento_enc vige ON vige.asi_id = deta.asi_id
						 WHERE vige.pdo_id = peri.pdo_id AND vige.asi_estado = 'A') AS Debe
				 FROM dbo.cont_asiento_enc asie WHERE asie.pdo_id = peri.pdo_id) tota
	ORDER BY mese.mes;

	SELECT asie.asi_id AS AsiId, asie.asi_fecha AS Fecha, tota.Total, usua.usu_codigo AS Usuario
	FROM dbo.cont_asiento_enc asie
	CROSS APPLY (SELECT SUM(deta.asd_debe) AS Total FROM dbo.cont_asiento_det deta WHERE deta.asi_id = asie.asi_id) tota
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = asie.usu_id
	WHERE asie.asi_origen = 'CIERRE_ANUAL' AND asie.asi_origen_id = @Anio AND asie.asi_estado = 'A';
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

------------------------------------------------------------
-- 7. Permisos
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT v.modulo, v.codigo, v.descripcion
FROM (VALUES
	('CONTABILIDAD', 'CONTABILIDAD_POLIZAS', 'Pólizas, libro diario y libro mayor: consultar e imprimir'),
	('CONTABILIDAD', 'CONTABILIDAD_ESTADOS', 'Balanza de comprobación y estados financieros (Balance General y Estado de Resultados)'),
	('CONTABILIDAD', 'CONTABILIDAD_CIERRE', 'Cerrar y abrir períodos contables y generar la partida de cierre anual')) v (modulo, codigo, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso perm WHERE perm.per_codigo = v.codigo);
UPDATE dbo.sec_permiso SET per_descripcion = 'Pólizas manuales: grabar y anular'
 WHERE per_codigo = 'CONTABILIDAD_ASIENTO_MANUAL';

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT rol.rol_id, perm.per_id
FROM (VALUES ('ADMIN'), ('CONTADOR'), ('CONTADOR_GENERAL')) r (rol)
CROSS JOIN (VALUES ('CONTABILIDAD_POLIZAS'), ('CONTABILIDAD_ESTADOS'), ('CONTABILIDAD_CIERRE')) p (permiso)
INNER JOIN dbo.sec_rol rol ON rol.rol_codigo = r.rol
INNER JOIN dbo.sec_permiso perm ON perm.per_codigo = p.permiso
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO

------------------------------------------------------------
-- 8. Datos de demostración
------------------------------------------------------------
-- En los datos de prueba el cheque 1009 paga una compra de inventario de más
-- de Q1.1 millones sin fondos y el banco queda en negativo. Se registra el
-- préstamo bancario que la financia, para que el Balance General tenga sentido:
-- lo que le falta al banco más Q100,000, en múltiplos de Q100,000 (los datos de
-- prueba dependen de la fecha en que se instalan). Solo con los datos de
-- demostración (ese cheque) y una sola vez.
IF EXISTS (SELECT 1 FROM dbo.cont_asiento_enc WHERE asi_descripcion = 'Pago a proveedor con cheque 1009' AND asi_estado = 'A')
   AND NOT EXISTS (SELECT 1 FROM dbo.cont_asiento_enc WHERE asi_descripcion LIKE 'Desembolso de préstamo bancario%')
   AND EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_codigo = '1120014')
   AND EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_codigo = '2160001')
   AND NOT EXISTS (SELECT 1 FROM dbo.cont_periodo_contable WHERE pdo_anio = 2026 AND pdo_mes = 9 AND pdo_estado = 'C')
BEGIN
	DECLARE @lineas dbo.cont_asiento_det_cc_type, @asi_id INT;
	DECLARE @saldo_banco NUMERIC(16, 2) = (
		SELECT ISNULL(SUM(deta.asd_debe - deta.asd_haber), 0) FROM dbo.cont_asiento_det deta
		INNER JOIN dbo.cont_asiento_enc asie ON asie.asi_id = deta.asi_id AND asie.asi_estado = 'A'
		INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = deta.cta_id AND cuen.cta_codigo = '1120014');
	DECLARE @prestamo NUMERIC(16, 2) = IIF(@saldo_banco < 0, CEILING((100000 - @saldo_banco) / 100000) * 100000, 1200000);
	INSERT INTO @lineas (cta_id, asd_debe, asd_haber, asd_descripcion)
	SELECT cta_id, @prestamo, 0, 'Desembolso del préstamo' FROM dbo.cont_cuenta_contable WHERE cta_codigo = '1120014'
	UNION ALL
	SELECT cta_id, 0, @prestamo, 'Préstamo a 5 años para compra de inventario' FROM dbo.cont_cuenta_contable WHERE cta_codigo = '2160001';
	EXEC dbo.paPolizaManualGrabar @Fecha = '20260930', @Descripcion = 'Desembolso de préstamo bancario para compra de inventario (datos de demostración)',
		@Lineas = @lineas, @UsuId = 1, @AsiId = @asi_id OUTPUT;
END
GO

PRINT '60_contabilidad_libros_estados.sql aplicado.';
GO
