/*
================================================================================
 49_rrhh_libro_salarios_igss.sql
 Cumplimiento laboral de la nómina en Guatemala.

   1. Datos del patrono y centros de trabajo.
        gen_compania: número patronal del IGSS y número de autorización del
          libro de salarios (Ministerio de Trabajo).
        gen_sucursal: cada sucursal es un centro de trabajo del IGSS, con su
          número y sus tasas. Por defecto las de la capital: IGSS patronal
          10.67 %, IRTRA 1 %, INTECAP 1 %. La cuota laboral queda vacía para
          usar la del tipo de movimiento IGSS_LABORAL (4.83 %); se llena solo
          si el centro de trabajo tiene otra.
        rrhhEmpleado: centro de trabajo (si no se indica, el de la sucursal de
          su departamento y, si tampoco, la primera sucursal de la compañía),
          nacionalidad, jornada (diurna, mixta, nocturna), contrato a tiempo
          completo o parcial (TC/TP de la planilla del IGSS) y folio del libro.

   2. Cuota patronal. Al calcular la nómina ordinaria, sobre el mismo salario
      afecto que la cuota laboral (tipos con EsBaseCalculo: sueldo, horas
      extra, comisiones, vacaciones, séptimos; no la bonificación incentivo,
      el aguinaldo, el bono 14 ni la indemnización) se calculan IGSS
      patronal, IRTRA e INTECAP con las tasas del centro de trabajo. Se
      guardan por empleado junto con las tasas usadas.

   3. Aguinaldo (Decreto 76-78) y bono 14 (Decreto 42-92).
        * Provisión: cada nómina ordinaria provisiona 1/12 del salario
          ordinario del período para cada prestación.
        * Pago: nómina especial (Clase A = aguinaldo, B = bono 14) de un año:
            aguinaldo  1 de diciembre del año anterior al 30 de noviembre
            bono 14    1 de julio del año anterior al 30 de junio
          Monto = salario ordinario promedio mensual del período × días
          laborados / días del período, menos lo que ya se le haya pagado
          por ese concepto en el período (p. ej. en una liquidación). El
          promedio sale de las nóminas ordinarias aprobadas; si no hay, se usa
          el salario base. Se calcula, aprueba y paga como cualquier nómina.

   4. Póliza al aprobar la nómina, además de lo que ya llevaba:
            Debe  cuota patronal IGSS, IRTRA e INTECAP (gasto, por departamento)
            Haber cuotas patronales por pagar
            Debe  aguinaldo y bono 14 (gasto, por departamento)
            Haber provisión de aguinaldo y de bono 14
      El pago de la nómina especial carga la provisión (pasivo).

   5. Libro de salarios (Código de Trabajo art. 102 y Acuerdo Ministerial
      124-2019): un folio por trabajador con sus datos y, por cada período
      pagado, días y horas trabajadas, salario ordinario y extraordinario,
      séptimos y asuetos, vacaciones, salario total, cuota laboral del IGSS,
      otras deducciones, bono 14, aguinaldo, bonificación incentivo (Decreto
      37-2001), otras bonificaciones, indemnización y líquido.

   6. Planilla mensual del IGSS: por centro de trabajo y por empleado, el
      salario afecto del mes y las cuotas laboral, patronal, IRTRA e INTECAP,
      con altas y bajas del mes.

 Las nóminas ya aprobadas antes de este script reciben sus cálculos de
 cuota patronal y provisión (para el libro y la planilla) sin cambiar su
 póliza.

 Requiere 25, 28, 29 y 36. Errores 54101-54118. Se puede volver a correr.
================================================================================
*/
USE [erp_db];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Columnas nuevas
------------------------------------------------------------
IF COL_LENGTH('dbo.gen_compania', 'cia_igss_numero_patronal') IS NULL
	ALTER TABLE dbo.gen_compania ADD [cia_igss_numero_patronal] VARCHAR(20) NULL;
IF COL_LENGTH('dbo.gen_compania', 'cia_libro_salarios_autorizacion') IS NULL
	ALTER TABLE dbo.gen_compania ADD [cia_libro_salarios_autorizacion] VARCHAR(60) NULL;
GO

IF COL_LENGTH('dbo.gen_sucursal', 'suc_igss_centro_trabajo') IS NULL
	ALTER TABLE dbo.gen_sucursal ADD [suc_igss_centro_trabajo] VARCHAR(10) NULL;
IF COL_LENGTH('dbo.gen_sucursal', 'suc_tasa_igss_patronal') IS NULL
	ALTER TABLE dbo.gen_sucursal ADD [suc_tasa_igss_patronal] NUMERIC(6, 3) NOT NULL
		CONSTRAINT [DF_gen_sucursal_tasa_igss_patronal] DEFAULT (10.67);
IF COL_LENGTH('dbo.gen_sucursal', 'suc_tasa_igss_laboral') IS NULL
	ALTER TABLE dbo.gen_sucursal ADD [suc_tasa_igss_laboral] NUMERIC(6, 3) NULL;
IF COL_LENGTH('dbo.gen_sucursal', 'suc_tasa_irtra') IS NULL
	ALTER TABLE dbo.gen_sucursal ADD [suc_tasa_irtra] NUMERIC(6, 3) NOT NULL
		CONSTRAINT [DF_gen_sucursal_tasa_irtra] DEFAULT (1);
IF COL_LENGTH('dbo.gen_sucursal', 'suc_tasa_intecap') IS NULL
	ALTER TABLE dbo.gen_sucursal ADD [suc_tasa_intecap] NUMERIC(6, 3) NOT NULL
		CONSTRAINT [DF_gen_sucursal_tasa_intecap] DEFAULT (1);
GO
IF OBJECT_ID('dbo.CK_gen_sucursal_tasas_igss', 'C') IS NULL
	ALTER TABLE dbo.gen_sucursal ADD CONSTRAINT [CK_gen_sucursal_tasas_igss] CHECK (
		[suc_tasa_igss_patronal] BETWEEN 0 AND 100 AND [suc_tasa_irtra] BETWEEN 0 AND 100
		AND [suc_tasa_intecap] BETWEEN 0 AND 100 AND ([suc_tasa_igss_laboral] IS NULL OR [suc_tasa_igss_laboral] BETWEEN 0 AND 100));
GO

IF COL_LENGTH('dbo.rrhhEmpleado', 'suc_id') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD [suc_id] INT NULL;				-- centro de trabajo (IGSS)
IF COL_LENGTH('dbo.rrhhEmpleado', 'Nacionalidad') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD [Nacionalidad] VARCHAR(40) NULL;	-- vacío = guatemalteca
IF COL_LENGTH('dbo.rrhhEmpleado', 'Jornada') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD [Jornada] CHAR(1) NOT NULL
		CONSTRAINT [DF_rrhhEmpleado_Jornada] DEFAULT ('D');			-- D = diurna, M = mixta, N = nocturna
IF COL_LENGTH('dbo.rrhhEmpleado', 'TiempoContrato') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD [TiempoContrato] CHAR(2) NOT NULL
		CONSTRAINT [DF_rrhhEmpleado_TiempoContrato] DEFAULT ('TC');	-- TC = tiempo completo, TP = tiempo parcial
IF COL_LENGTH('dbo.rrhhEmpleado', 'FolioLibroSalarios') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD [FolioLibroSalarios] INT NULL;
GO
IF OBJECT_ID('dbo.FK_rrhhEmpleado_Sucursal', 'F') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD CONSTRAINT [FK_rrhhEmpleado_Sucursal] FOREIGN KEY ([suc_id]) REFERENCES dbo.gen_sucursal ([suc_id]);
IF OBJECT_ID('dbo.CK_rrhhEmpleado_Jornada', 'C') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD CONSTRAINT [CK_rrhhEmpleado_Jornada] CHECK ([Jornada] IN ('D','M','N'));
IF OBJECT_ID('dbo.CK_rrhhEmpleado_TiempoContrato', 'C') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD CONSTRAINT [CK_rrhhEmpleado_TiempoContrato] CHECK ([TiempoContrato] IN ('TC','TP'));
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_rrhhEmpleado_FolioLibro')
	CREATE UNIQUE INDEX [UX_rrhhEmpleado_FolioLibro] ON dbo.rrhhEmpleado ([cia_id], [FolioLibroSalarios]) WHERE [FolioLibroSalarios] IS NOT NULL;
GO

-- Columna del libro de salarios en la que cae cada tipo de movimiento.
IF COL_LENGTH('dbo.rrhhTipoMovimientoNomina', 'ColumnaLibro') IS NULL
	ALTER TABLE dbo.rrhhTipoMovimientoNomina ADD [ColumnaLibro] VARCHAR(20) NULL;
GO
IF OBJECT_ID('dbo.CK_rrhhTipoMovimientoNomina_ColumnaLibro', 'C') IS NULL
	ALTER TABLE dbo.rrhhTipoMovimientoNomina ADD CONSTRAINT [CK_rrhhTipoMovimientoNomina_ColumnaLibro] CHECK ([ColumnaLibro] IS NULL OR [ColumnaLibro] IN
		('ORDINARIO','EXTRAORDINARIO','SEPTIMOS','VACACIONES','BONIFICACION','AGUINALDO','BONO14','OTRAS_BONIF','INDEMNIZACION','IGSS','OTRAS_DEDUCCIONES'));
GO

-- Horas extra trabajadas (van al libro de salarios).
IF COL_LENGTH('dbo.rrhhMovimientoNomina', 'Horas') IS NULL
	ALTER TABLE dbo.rrhhMovimientoNomina ADD [Horas] NUMERIC(6, 2) NULL;
IF COL_LENGTH('dbo.rrhhNominaDetalle', 'Horas') IS NULL
	ALTER TABLE dbo.rrhhNominaDetalle ADD [Horas] NUMERIC(6, 2) NULL;
GO

IF COL_LENGTH('dbo.rrhhNomina', 'Clase') IS NULL
	ALTER TABLE dbo.rrhhNomina ADD [Clase] CHAR(1) NOT NULL
		CONSTRAINT [DF_rrhhNomina_Clase] DEFAULT ('O');				-- O = ordinaria, A = aguinaldo, B = bono 14
IF COL_LENGTH('dbo.rrhhNomina', 'TotalPatronal') IS NULL
	ALTER TABLE dbo.rrhhNomina ADD [TotalPatronal] NUMERIC(14, 2) NOT NULL
		CONSTRAINT [DF_rrhhNomina_TotalPatronal] DEFAULT (0);			-- IGSS patronal + IRTRA + INTECAP
GO
IF OBJECT_ID('dbo.CK_rrhhNomina_Clase', 'C') IS NULL
	ALTER TABLE dbo.rrhhNomina ADD CONSTRAINT [CK_rrhhNomina_Clase] CHECK ([Clase] IN ('O','A','B'));
GO

IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'suc_id') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [suc_id] INT NULL;
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'BaseIgss') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [BaseIgss] NUMERIC(14, 2) NOT NULL CONSTRAINT [DF_rrhhNominaEmpleado_BaseIgss] DEFAULT (0);
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'TasaIgssPatronal') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [TasaIgssPatronal] NUMERIC(6, 3) NULL;
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'TasaIrtra') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [TasaIrtra] NUMERIC(6, 3) NULL;
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'TasaIntecap') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [TasaIntecap] NUMERIC(6, 3) NULL;
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'IgssPatronal') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [IgssPatronal] NUMERIC(12, 2) NOT NULL CONSTRAINT [DF_rrhhNominaEmpleado_IgssPatronal] DEFAULT (0);
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'Irtra') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [Irtra] NUMERIC(12, 2) NOT NULL CONSTRAINT [DF_rrhhNominaEmpleado_Irtra] DEFAULT (0);
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'Intecap') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [Intecap] NUMERIC(12, 2) NOT NULL CONSTRAINT [DF_rrhhNominaEmpleado_Intecap] DEFAULT (0);
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'ProvAguinaldo') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [ProvAguinaldo] NUMERIC(12, 2) NOT NULL CONSTRAINT [DF_rrhhNominaEmpleado_ProvAguinaldo] DEFAULT (0);
IF COL_LENGTH('dbo.rrhhNominaEmpleado', 'ProvBono14') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD [ProvBono14] NUMERIC(12, 2) NOT NULL CONSTRAINT [DF_rrhhNominaEmpleado_ProvBono14] DEFAULT (0);
GO
IF OBJECT_ID('dbo.FK_rrhhNominaEmpleado_Sucursal', 'F') IS NULL
	ALTER TABLE dbo.rrhhNominaEmpleado ADD CONSTRAINT [FK_rrhhNominaEmpleado_Sucursal] FOREIGN KEY ([suc_id]) REFERENCES dbo.gen_sucursal ([suc_id]);
GO

------------------------------------------------------------
-- 2. Tipos de movimiento y cuentas contables
------------------------------------------------------------
INSERT INTO dbo.rrhhTipoMovimientoNomina (Codigo, Descripcion, Naturaleza, FormaCalculo, Valor, EsAutomatico, EsBaseCalculo, Orden)
SELECT v.Codigo, v.Descripcion, 'I', 'M', 0, 0, v.EsBase, v.Orden
FROM (VALUES
	('SEPTIMOS',      'Séptimos y asuetos',                1, 22),
	('VACACIONES',    'Vacaciones',                        1, 25),
	('AGUINALDO',     'Aguinaldo (Decreto 76-78)',         0, 60),
	('BONO14',        'Bono 14 (Decreto 42-92)',           0, 61),
	('INDEMNIZACION', 'Indemnización',                     0, 70)
) v(Codigo, Descripcion, EsBase, Orden)
WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhTipoMovimientoNomina tipo WHERE tipo.Codigo = v.Codigo);

UPDATE tipo SET ColumnaLibro = v.Columna
FROM dbo.rrhhTipoMovimientoNomina tipo
INNER JOIN (VALUES ('SUELDO', 'ORDINARIO'), ('COMISION', 'ORDINARIO'), ('HORAS_EXTRA', 'EXTRAORDINARIO'),
				   ('SEPTIMOS', 'SEPTIMOS'), ('VACACIONES', 'VACACIONES'), ('BONIF_INCENTIVO', 'BONIFICACION'),
				   ('AGUINALDO', 'AGUINALDO'), ('BONO14', 'BONO14'), ('OTRO_INGRESO', 'OTRAS_BONIF'),
				   ('INDEMNIZACION', 'INDEMNIZACION'), ('IGSS_LABORAL', 'IGSS'), ('ISR', 'OTRAS_DEDUCCIONES'),
				   ('ANTICIPO', 'OTRAS_DEDUCCIONES'), ('PRESTAMO', 'OTRAS_DEDUCCIONES'), ('OTRO_DESCUENTO', 'OTRAS_DEDUCCIONES')) v(Codigo, Columna)
	ON v.Codigo = tipo.Codigo
WHERE tipo.ColumnaLibro IS NULL;
GO

-- Cuentas nuevas de la nomenclatura (subcuentas de 7 posiciones).
DECLARE @cuentas TABLE (Codigo VARCHAR(20), Nombre VARCHAR(128), Tipo CHAR(1), Naturaleza CHAR(1));
INSERT INTO @cuentas VALUES
	('2110016', 'CUOTAS PATRONALES IGSS, IRTRA E INTECAP POR PAGAR', 'P', 'H'),
	('2110017', 'PROVISION AGUINALDO', 'P', 'H'),
	('2110018', 'PROVISION BONO 14', 'P', 'H'),
	('5110072', 'CUOTA PATRONAL IRTRA', 'G', 'D'),
	('5110073', 'CUOTA PATRONAL INTECAP', 'G', 'D');
INSERT INTO dbo.cont_cuenta_contable (cta_codigo, cta_nombre, cta_tipo, cta_naturaleza, cta_acepta_movimiento, cta_id_padre, cta_nivel)
SELECT cuen.Codigo, cuen.Nombre, cuen.Tipo, cuen.Naturaleza, 1, padr.cta_id, padr.cta_nivel + 1
FROM @cuentas cuen
INNER JOIN dbo.cont_cuenta_contable padr ON padr.cta_codigo = LEFT(cuen.Codigo, 3)
WHERE NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable exis WHERE exis.cta_codigo = cuen.Codigo);

DECLARE @conceptos TABLE (Codigo VARCHAR(40), Descripcion VARCHAR(128), Naturaleza CHAR(1), Cuenta VARCHAR(20));
INSERT INTO @conceptos VALUES
	('NOMINA_IGSS_PATRONAL_GASTO',  'Nómina: gasto de cuota patronal IGSS',                'D', '5110008'),
	('NOMINA_IRTRA_GASTO',          'Nómina: gasto de cuota IRTRA',                        'D', '5110072'),
	('NOMINA_INTECAP_GASTO',        'Nómina: gasto de cuota INTECAP',                      'D', '5110073'),
	('NOMINA_PATRONAL_POR_PAGAR',   'Nómina: cuotas patronales IGSS, IRTRA e INTECAP por pagar', 'H', '2110016'),
	('NOMINA_AGUINALDO_GASTO',      'Nómina: gasto de aguinaldo (provisión mensual)',      'D', '5110005'),
	('NOMINA_BONO14_GASTO',         'Nómina: gasto de bono 14 (provisión mensual)',        'D', '5110004'),
	('NOMINA_PROVISION_AGUINALDO',  'Nómina: provisión de aguinaldo',                      'H', '2110017'),
	('NOMINA_PROVISION_BONO14',     'Nómina: provisión de bono 14',                        'H', '2110018');
INSERT INTO dbo.cont_cuenta_parametro (ccp_codigo, ccp_descripcion, ccp_naturaleza, cta_id)
SELECT conc.Codigo, conc.Descripcion, conc.Naturaleza, cuen.cta_id
FROM @conceptos conc
LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_codigo = conc.Cuenta
WHERE NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_parametro para WHERE para.ccp_codigo = conc.Codigo);
UPDATE para SET cta_id = cuen.cta_id, UpdFechaHora = SYSDATETIME()
FROM dbo.cont_cuenta_parametro para
INNER JOIN @conceptos conc ON conc.Codigo = para.ccp_codigo
INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_codigo = conc.Cuenta
WHERE para.cta_id IS NULL;

-- El pago del aguinaldo y del bono 14 carga su provisión; vacaciones,
-- séptimos e indemnización van a su gasto.
UPDATE tipo SET cta_id = cuen.cta_id
FROM dbo.rrhhTipoMovimientoNomina tipo
INNER JOIN (VALUES ('SEPTIMOS', '5110001'), ('VACACIONES', '5110006'), ('AGUINALDO', '2110017'),
				   ('BONO14', '2110018'), ('INDEMNIZACION', '5110007')) v(Codigo, Cuenta) ON v.Codigo = tipo.Codigo
INNER JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_codigo = v.Cuenta
WHERE tipo.cta_id IS NULL;
GO

------------------------------------------------------------
-- 3. Funciones
------------------------------------------------------------
-- Centro de trabajo del empleado: el que tiene asignado; si no, la sucursal
-- de su departamento; si tampoco, la primera sucursal activa de la compañía.
CREATE OR ALTER FUNCTION [dbo].[fnRrhhEmpleadoSucursal] (@IdEmpleado INT)
RETURNS INT
AS
BEGIN
	RETURN (SELECT COALESCE(empl.suc_id, depa.suc_id,
					(SELECT TOP 1 sucu.suc_id FROM dbo.gen_sucursal sucu WHERE sucu.cia_id = empl.cia_id
					 ORDER BY CASE sucu.suc_estado WHEN 'A' THEN 0 ELSE 1 END, sucu.suc_codigo, sucu.suc_id))
			FROM dbo.rrhhEmpleado empl
			LEFT JOIN dbo.rrhhPlaza plaz ON plaz.IdPlaza = empl.IdPlaza
			LEFT JOIN dbo.rrhhDepartamentoPuesto depu ON depu.IdDepartamentoPuesto = plaz.IdDepartamentoPuesto
			LEFT JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = depu.IdDepartamento AND depa.suc_id IN
				(SELECT sdep.suc_id FROM dbo.gen_sucursal sdep WHERE sdep.cia_id = empl.cia_id)
			WHERE empl.IdEmpleado = @IdEmpleado);
END;
GO

------------------------------------------------------------
-- 4. Cuota patronal y provisiones de una nómina ordinaria
--
-- Se usa al calcular y para completar las nóminas aprobadas antes de este
-- script (sin tocar su póliza). La base es la suma de los ingresos con
-- EsBaseCalculo; la provisión, 1/12 del salario ordinario del período.
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaPatronalCalcular]
	@IdNomina	INT
AS
BEGIN
	SET NOCOUNT ON;

	UPDATE nemp
	   SET suc_id = ISNULL(nemp.suc_id, dbo.fnRrhhEmpleadoSucursal(nemp.IdEmpleado))
	FROM dbo.rrhhNominaEmpleado nemp
	WHERE nemp.IdNomina = @IdNomina;

	UPDATE nemp
	   SET BaseIgss = calc.Base,
		   TasaIgssPatronal = tasa.Patronal, TasaIrtra = tasa.Irtra, TasaIntecap = tasa.Intecap,
		   IgssPatronal = ROUND(calc.Base * tasa.Patronal / 100.0, 2),
		   Irtra = ROUND(calc.Base * tasa.Irtra / 100.0, 2),
		   Intecap = ROUND(calc.Base * tasa.Intecap / 100.0, 2),
		   ProvAguinaldo = ROUND(calc.Ordinario / 12.0, 2),
		   ProvBono14 = ROUND(calc.Ordinario / 12.0, 2)
	FROM dbo.rrhhNominaEmpleado nemp
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_id = nemp.suc_id
	CROSS APPLY (SELECT ISNULL(sucu.suc_tasa_igss_patronal, 10.67) AS Patronal,
						ISNULL(sucu.suc_tasa_irtra, 1) AS Irtra,
						ISNULL(sucu.suc_tasa_intecap, 1) AS Intecap) tasa
	CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN tipo.EsBaseCalculo = 1 THEN deta.Monto END), 0) AS Base,
						ISNULL(SUM(CASE WHEN tipo.ColumnaLibro = 'ORDINARIO' THEN deta.Monto END), 0) AS Ordinario
				 FROM dbo.rrhhNominaDetalle deta
				 INNER JOIN dbo.rrhhTipoMovimientoNomina tipo ON tipo.IdTipoMovimientoNomina = deta.IdTipoMovimientoNomina
				 WHERE deta.IdNominaEmpleado = nemp.IdNominaEmpleado AND deta.Naturaleza = 'I') calc
	WHERE nemp.IdNomina = @IdNomina;

	UPDATE nomi
	   SET TotalPatronal = (SELECT ISNULL(SUM(nemp.IgssPatronal + nemp.Irtra + nemp.Intecap), 0)
							FROM dbo.rrhhNominaEmpleado nemp WHERE nemp.IdNomina = nomi.IdNomina)
	FROM dbo.rrhhNomina nomi
	WHERE nomi.IdNomina = @IdNomina;
END;
GO

------------------------------------------------------------
-- 5. Nómina: consulta, período sugerido y creación (solo ordinarias)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaConsultar]
	@CiaId INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT nomi.IdNomina, nomi.cia_id, comp.cia_nombre_comercial, nomi.Descripcion, nomi.TipoPeriodo, nomi.Clase, nomi.FechaDel, nomi.FechaAl,
		   nomi.FechaPago, nomi.TotalIngresos, nomi.TotalDescuentos, nomi.TotalLiquido, nomi.TotalPatronal, nomi.Estado, nomi.FechaCalculo, nomi.FechaAprobacion,
		   resu.CantidadEmpleados, resu.TotalPagado, resu.PendientesPago
	FROM dbo.rrhhNomina nomi
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = nomi.cia_id
	CROSS APPLY (SELECT COUNT(*) AS CantidadEmpleados,
						ISNULL(SUM(CASE WHEN nemp.IdNominaPago IS NOT NULL THEN nemp.Liquido END), 0) AS TotalPagado,
						SUM(CASE WHEN nemp.IdNominaPago IS NULL AND nemp.Liquido > 0 THEN 1 ELSE 0 END) AS PendientesPago
				 FROM dbo.rrhhNominaEmpleado nemp WHERE nemp.IdNomina = nomi.IdNomina) resu
	WHERE @CiaId IS NULL OR nomi.cia_id = @CiaId
	ORDER BY ISNULL(nomi.FechaPago, nomi.FechaAl) DESC, nomi.IdNomina DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaPeriodoSugerido]
	@CiaId			INT,
	@TipoPeriodo	CHAR(1)
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(@TipoPeriodo, '') NOT IN ('S','Q','M')
		THROW 52070, 'El período debe ser semanal, quincenal o mensual.', 1;

	DECLARE @ultima DATE = (SELECT MAX(FechaAl) FROM dbo.rrhhNomina
							WHERE cia_id = @CiaId AND TipoPeriodo = @TipoPeriodo AND Clase = 'O' AND Estado <> 'N');
	DECLARE @del DATE, @al DATE, @hoy DATE = CAST(GETDATE() AS DATE);

	IF @ultima IS NOT NULL
		SET @del = DATEADD(DAY, 1, @ultima);
	ELSE
		SET @del = CASE @TipoPeriodo
					   -- 1900-01-01 fue lunes: no depende de SET DATEFIRST.
					   WHEN 'S' THEN DATEADD(DAY, -(DATEDIFF(DAY, '19000101', @hoy) % 7), @hoy)
					   WHEN 'Q' THEN DATEFROMPARTS(YEAR(@hoy), MONTH(@hoy), CASE WHEN DAY(@hoy) <= 15 THEN 1 ELSE 16 END)
					   ELSE DATEFROMPARTS(YEAR(@hoy), MONTH(@hoy), 1) END;

	SET @al = CASE @TipoPeriodo
				  WHEN 'S' THEN DATEADD(DAY, 6, @del)
				  WHEN 'Q' THEN CASE WHEN DAY(@del) <= 15 THEN DATEFROMPARTS(YEAR(@del), MONTH(@del), 15) ELSE EOMONTH(@del) END
				  ELSE EOMONTH(@del) END;

	DECLARE @mes VARCHAR(30) = FORMAT(@del, 'MMMM yyyy', 'es-GT');
	SET @mes = UPPER(LEFT(@mes, 1)) + SUBSTRING(@mes, 2, 30);

	SELECT @del AS FechaDel, @al AS FechaAl, @al AS FechaPago,
		   CASE @TipoPeriodo
			   WHEN 'S' THEN CONCAT('Semana del ', FORMAT(@del, 'dd/MM'), ' al ', FORMAT(@al, 'dd/MM/yyyy'))
			   WHEN 'Q' THEN CONCAT(CASE WHEN DAY(@del) <= 15 THEN 'Primera' ELSE 'Segunda' END, ' quincena de ', LOWER(@mes))
			   ELSE @mes END AS Descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaCrear]
	@CiaId			INT,
	@Descripcion	VARCHAR(100),
	@TipoPeriodo	CHAR(1),
	@FechaDel		DATE,
	@FechaAl		DATE,
	@FechaPago		DATE = NULL,
	@UsuId			INT,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(@TipoPeriodo, '') NOT IN ('S','Q','M')
		THROW 52070, 'El período debe ser semanal, quincenal o mensual.', 1;
	IF @FechaAl < @FechaDel
		THROW 52071, 'La fecha final no puede ser anterior a la inicial.', 1;
	IF DATEDIFF(DAY, @FechaDel, @FechaAl) + 1 > CASE @TipoPeriodo WHEN 'M' THEN 31 WHEN 'Q' THEN 16 ELSE 7 END
		THROW 52072, 'El rango de fechas es más largo que el período elegido.', 1;
	-- Solo choca con otra nómina ordinaria del mismo tipo: el aguinaldo y el
	-- bono 14 cubren todo un año y no se traslapan con las ordinarias.
	IF EXISTS (SELECT 1 FROM dbo.rrhhNomina
			   WHERE cia_id = @CiaId AND TipoPeriodo = @TipoPeriodo AND Clase = 'O' AND Estado <> 'N'
				 AND FechaDel <= @FechaAl AND FechaAl >= @FechaDel)
		THROW 52073, 'Ya existe una nómina de este tipo que se traslapa con esas fechas.', 1;

	INSERT INTO dbo.rrhhNomina (cia_id, Descripcion, TipoPeriodo, Clase, FechaDel, FechaAl, FechaPago, InsUsuario)
	VALUES (@CiaId, @Descripcion, @TipoPeriodo, 'O', @FechaDel, @FechaAl, @FechaPago, @UsuId);
	SET @IdResultado = SCOPE_IDENTITY();
END;
GO

-- Nómina de aguinaldo (A) o bono 14 (B) del año indicado. El período de
-- cómputo lo fija la ley; la fecha de pago por defecto es el 15 de
-- diciembre (aguinaldo) o el 15 de julio (bono 14).
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaPrestacionCrear]
	@CiaId			INT,
	@Clase			CHAR(1),
	@Anio			INT,
	@FechaPago		DATE = NULL,
	@UsuId			INT,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(@Clase, '') NOT IN ('A','B')
		THROW 54101, 'Indique si la nómina es de aguinaldo o de bono 14.', 1;
	IF @Anio IS NULL OR @Anio < 2000 OR @Anio > 2100
		THROW 54102, 'El año no es válido.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_id = @CiaId)
		THROW 54103, 'La compañía no existe.', 1;

	DECLARE @del DATE = CASE @Clase WHEN 'A' THEN DATEFROMPARTS(@Anio - 1, 12, 1) ELSE DATEFROMPARTS(@Anio - 1, 7, 1) END,
			@al DATE = CASE @Clase WHEN 'A' THEN DATEFROMPARTS(@Anio, 11, 30) ELSE DATEFROMPARTS(@Anio, 6, 30) END;
	SET @FechaPago = ISNULL(@FechaPago, CASE @Clase WHEN 'A' THEN DATEFROMPARTS(@Anio, 12, 15) ELSE DATEFROMPARTS(@Anio, 7, 15) END);

	IF EXISTS (SELECT 1 FROM dbo.rrhhNomina WHERE cia_id = @CiaId AND Clase = @Clase AND FechaAl = @al AND Estado <> 'N')
		THROW 54104, 'Ya existe una nómina de esa prestación para ese año; anúlela si necesita volver a crearla.', 1;

	INSERT INTO dbo.rrhhNomina (cia_id, Descripcion, TipoPeriodo, Clase, FechaDel, FechaAl, FechaPago, InsUsuario)
	VALUES (@CiaId, CONCAT(CASE @Clase WHEN 'A' THEN 'Aguinaldo ' ELSE 'Bono 14 ' END, @Anio), 'M', @Clase, @del, @al, @FechaPago, @UsuId);
	SET @IdResultado = SCOPE_IDENTITY();
END;
GO

------------------------------------------------------------
-- 6. Cálculo de la nómina
--
-- Ordinaria: igual que en 36, más la cuota laboral con la tasa del centro
-- de trabajo (si la tiene), las horas extra, la cuota patronal y las
-- provisiones. Aguinaldo y bono 14: la prestación de cada empleado.
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaCalcular]
	@IdNomina	INT,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @CiaId INT, @FechaDel DATE, @FechaAl DATE, @TipoPeriodo CHAR(1), @Estado CHAR(1), @Clase CHAR(1);
	SELECT @CiaId = cia_id, @FechaDel = FechaDel, @FechaAl = FechaAl, @TipoPeriodo = TipoPeriodo, @Estado = Estado, @Clase = Clase
	FROM dbo.rrhhNomina WHERE IdNomina = @IdNomina;

	IF @Estado IS NULL
		THROW 52080, 'La nómina indicada no existe.', 1;
	IF @Estado NOT IN ('B','C')
		THROW 52081, 'Solo se puede calcular una nómina en borrador o ya calculada (no aprobada ni anulada).', 1;

	DECLARE @DiasPeriodo NUMERIC(5, 2) = CASE @TipoPeriodo WHEN 'M' THEN 30 WHEN 'Q' THEN 15 ELSE 7 END;
	DECLARE @FraccionMes NUMERIC(12, 10) = CASE @TipoPeriodo WHEN 'M' THEN 1 WHEN 'Q' THEN 0.5 ELSE 12.0 / 52.0 END;

	BEGIN TRANSACTION;

	DELETE deta FROM dbo.rrhhNominaDetalle deta
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = deta.IdNominaEmpleado
	WHERE nemp.IdNomina = @IdNomina;
	DELETE FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina;

	IF @Clase = 'O'
	BEGIN
		INSERT INTO dbo.rrhhNominaEmpleado (IdNomina, IdEmpleado, SalarioBase, DiasLaborados, IdDepartamento, suc_id, FormaPago, gef_id, TipoCuenta, NumeroCuenta)
		SELECT @IdNomina, empl.IdEmpleado, empl.SalarioBase,
			   CASE WHEN empl.FechaIngreso <= @FechaDel AND (empl.FechaBaja IS NULL OR empl.FechaBaja >= @FechaAl)
					THEN @DiasPeriodo
					ELSE CASE WHEN rango.Dias > @DiasPeriodo THEN @DiasPeriodo ELSE rango.Dias END
			   END,
			   dbo.fnRrhhEmpleadoDepartamento(empl.IdEmpleado), dbo.fnRrhhEmpleadoSucursal(empl.IdEmpleado),
			   empl.FormaPago, empl.gef_id, empl.TipoCuenta, empl.NumeroCuenta
		FROM dbo.rrhhEmpleado empl
		CROSS APPLY (SELECT CAST(DATEDIFF(DAY,
						CASE WHEN empl.FechaIngreso > @FechaDel THEN empl.FechaIngreso ELSE @FechaDel END,
						CASE WHEN empl.FechaBaja IS NOT NULL AND empl.FechaBaja < @FechaAl THEN empl.FechaBaja ELSE @FechaAl END) + 1 AS NUMERIC(5, 2)) AS Dias) rango
		WHERE empl.cia_id = @CiaId
		  AND empl.TipoNomina = @TipoPeriodo
		  AND empl.FechaIngreso <= @FechaAl
		  AND (empl.FechaBaja IS NULL OR empl.FechaBaja >= @FechaDel)
		  AND (empl.Estado = 'A' OR empl.FechaBaja IS NOT NULL);

		-- 1) Sueldo (S) y fijos (F) automáticos, llevados al período.
		INSERT INTO dbo.rrhhNominaDetalle (IdNominaEmpleado, IdTipoMovimientoNomina, Naturaleza, Descripcion, Monto)
		SELECT nemp.IdNominaEmpleado, tipo.IdTipoMovimientoNomina, tipo.Naturaleza, tipo.Descripcion,
			   ROUND(CASE tipo.FormaCalculo WHEN 'S' THEN nemp.SalarioBase ELSE tipo.Valor END * @FraccionMes * nemp.DiasLaborados / @DiasPeriodo, 2)
		FROM dbo.rrhhNominaEmpleado nemp
		CROSS JOIN dbo.rrhhTipoMovimientoNomina tipo
		WHERE nemp.IdNomina = @IdNomina
		  AND tipo.Estado = 'A' AND tipo.EsAutomatico = 1 AND tipo.FormaCalculo IN ('S','F');

		-- 2) Movimientos manuales (M) del período no aplicados en otra nómina.
		INSERT INTO dbo.rrhhNominaDetalle (IdNominaEmpleado, IdTipoMovimientoNomina, IdMovimientoNomina, Naturaleza, Descripcion, Monto, Horas)
		SELECT nemp.IdNominaEmpleado, tipo.IdTipoMovimientoNomina, movi.IdMovimientoNomina, tipo.Naturaleza,
			   ISNULL(NULLIF(movi.Descripcion, ''), tipo.Descripcion), movi.Monto, movi.Horas
		FROM dbo.rrhhMovimientoNomina movi
		INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdEmpleado = movi.IdEmpleado AND nemp.IdNomina = @IdNomina
		INNER JOIN dbo.rrhhTipoMovimientoNomina tipo ON tipo.IdTipoMovimientoNomina = movi.IdTipoMovimientoNomina
		WHERE movi.Estado = 'A' AND movi.IdNomina IS NULL
		  AND movi.FechaAplicacion BETWEEN @FechaDel AND @FechaAl;

		-- 3) Porcentajes (P) automáticos sobre la base. La cuota laboral del
		--    IGSS usa la tasa del centro de trabajo cuando la tiene.
		INSERT INTO dbo.rrhhNominaDetalle (IdNominaEmpleado, IdTipoMovimientoNomina, Naturaleza, Descripcion, Monto)
		SELECT nemp.IdNominaEmpleado, tipo.IdTipoMovimientoNomina, tipo.Naturaleza, tipo.Descripcion,
			   ROUND(base.Monto * CASE WHEN tipo.Codigo = 'IGSS_LABORAL' THEN ISNULL(sucu.suc_tasa_igss_laboral, tipo.Valor) ELSE tipo.Valor END / 100.0, 2)
		FROM dbo.rrhhNominaEmpleado nemp
		LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_id = nemp.suc_id
		CROSS APPLY (SELECT ISNULL(SUM(deta.Monto), 0) AS Monto
					 FROM dbo.rrhhNominaDetalle deta
					 INNER JOIN dbo.rrhhTipoMovimientoNomina tbas ON tbas.IdTipoMovimientoNomina = deta.IdTipoMovimientoNomina
					 WHERE deta.IdNominaEmpleado = nemp.IdNominaEmpleado AND tbas.EsBaseCalculo = 1) base
		CROSS JOIN dbo.rrhhTipoMovimientoNomina tipo
		WHERE nemp.IdNomina = @IdNomina
		  AND tipo.Estado = 'A' AND tipo.EsAutomatico = 1 AND tipo.FormaCalculo = 'P'
		  AND base.Monto > 0;
	END
	ELSE
	BEGIN
		-- Aguinaldo o bono 14: entran los empleados que trabajaron en el
		-- período y siguen en la empresa al cerrarlo (a quien se retiró antes
		-- se le paga en su liquidación). El salario ordinario promedio se
		-- guarda en SalarioBase y los días del período en DiasLaborados.
		DECLARE @Codigo VARCHAR(20) = CASE @Clase WHEN 'A' THEN 'AGUINALDO' ELSE 'BONO14' END;
		DECLARE @IdTipo INT = (SELECT IdTipoMovimientoNomina FROM dbo.rrhhTipoMovimientoNomina WHERE Codigo = @Codigo);
		DECLARE @DiasAnio NUMERIC(5, 2) = DATEDIFF(DAY, @FechaDel, @FechaAl) + 1;
		IF @IdTipo IS NULL
		BEGIN
			DECLARE @msg_tipo NVARCHAR(200) = CONCAT(N'No existe el tipo de movimiento ', @Codigo, N'; vuelva a correr el script 49.');
			THROW 54105, @msg_tipo, 1;
		END

		INSERT INTO dbo.rrhhNominaEmpleado (IdNomina, IdEmpleado, SalarioBase, DiasLaborados, IdDepartamento, suc_id, FormaPago, gef_id, TipoCuenta, NumeroCuenta)
		SELECT @IdNomina, empl.IdEmpleado,
			   CASE WHEN prom.Meses > 0 THEN ROUND(prom.Ordinario / prom.Meses, 2) ELSE empl.SalarioBase END,
			   DATEDIFF(DAY, CASE WHEN empl.FechaIngreso > @FechaDel THEN empl.FechaIngreso ELSE @FechaDel END, @FechaAl) + 1,
			   dbo.fnRrhhEmpleadoDepartamento(empl.IdEmpleado), dbo.fnRrhhEmpleadoSucursal(empl.IdEmpleado),
			   empl.FormaPago, empl.gef_id, empl.TipoCuenta, empl.NumeroCuenta
		FROM dbo.rrhhEmpleado empl
		CROSS APPLY (SELECT ISNULL(SUM(orde.Ordinario), 0) AS Ordinario,
							ISNULL(SUM(orde.Meses), 0) AS Meses
					 FROM (SELECT (SELECT ISNULL(SUM(deta.Monto), 0)
								   FROM dbo.rrhhNominaDetalle deta
								   INNER JOIN dbo.rrhhTipoMovimientoNomina tord ON tord.IdTipoMovimientoNomina = deta.IdTipoMovimientoNomina
								   WHERE deta.IdNominaEmpleado = nemp.IdNominaEmpleado AND tord.ColumnaLibro = 'ORDINARIO') AS Ordinario,
								  CASE nomo.TipoPeriodo WHEN 'M' THEN 1.0 WHEN 'Q' THEN 0.5 ELSE 12.0 / 52.0 END
								  * nemp.DiasLaborados / CASE nomo.TipoPeriodo WHEN 'M' THEN 30.0 WHEN 'Q' THEN 15.0 ELSE 7.0 END AS Meses
						   FROM dbo.rrhhNominaEmpleado nemp
						   INNER JOIN dbo.rrhhNomina nomo ON nomo.IdNomina = nemp.IdNomina
						   WHERE nemp.IdEmpleado = empl.IdEmpleado AND nomo.Clase = 'O' AND nomo.Estado = 'A'
							 AND nomo.FechaAl BETWEEN @FechaDel AND @FechaAl) orde) prom
		WHERE empl.cia_id = @CiaId
		  AND empl.FechaIngreso <= @FechaAl
		  AND (empl.FechaBaja IS NULL OR empl.FechaBaja >= @FechaAl)
		  AND empl.Estado = 'A';

		-- Lo ya pagado por el mismo concepto dentro del período (anticipos o
		-- liquidaciones en nóminas ordinarias aprobadas) se descuenta.
		INSERT INTO dbo.rrhhNominaDetalle (IdNominaEmpleado, IdTipoMovimientoNomina, Naturaleza, Descripcion, Monto)
		SELECT nemp.IdNominaEmpleado, @IdTipo, 'I',
			   LEFT(CONCAT(CASE @Clase WHEN 'A' THEN 'Aguinaldo' ELSE 'Bono 14' END, ': ', CAST(nemp.DiasLaborados AS INT), ' de ', CAST(@DiasAnio AS INT),
					' días sobre Q ', FORMAT(nemp.SalarioBase, 'N2'),
					CASE WHEN pago.Monto > 0 THEN CONCAT(' (menos Q ', FORMAT(pago.Monto, 'N2'), ' ya pagados)') ELSE '' END), 200),
			   ROUND(nemp.SalarioBase * nemp.DiasLaborados / @DiasAnio, 2) - pago.Monto
		FROM dbo.rrhhNominaEmpleado nemp
		CROSS APPLY (SELECT ISNULL(SUM(deta.Monto), 0) AS Monto
					 FROM dbo.rrhhNominaDetalle deta
					 INNER JOIN dbo.rrhhNominaEmpleado nant ON nant.IdNominaEmpleado = deta.IdNominaEmpleado
					 INNER JOIN dbo.rrhhNomina nomo ON nomo.IdNomina = nant.IdNomina
					 WHERE nant.IdEmpleado = nemp.IdEmpleado AND deta.IdTipoMovimientoNomina = @IdTipo
					   AND nomo.Clase = 'O' AND nomo.Estado = 'A' AND nomo.FechaAl BETWEEN @FechaDel AND @FechaAl) pago
		WHERE nemp.IdNomina = @IdNomina;
	END

	DELETE deta FROM dbo.rrhhNominaDetalle deta
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = deta.IdNominaEmpleado
	WHERE nemp.IdNomina = @IdNomina AND deta.Monto <= 0;

	-- Empleados sin nada que cobrar en una prestación (ya se les pagó).
	IF @Clase <> 'O'
		DELETE nemp FROM dbo.rrhhNominaEmpleado nemp
		WHERE nemp.IdNomina = @IdNomina
		  AND NOT EXISTS (SELECT 1 FROM dbo.rrhhNominaDetalle deta WHERE deta.IdNominaEmpleado = nemp.IdNominaEmpleado);

	UPDATE nemp
	   SET TotalIngresos = tota.Ingresos, TotalDescuentos = tota.Descuentos, Liquido = tota.Ingresos - tota.Descuentos
	FROM dbo.rrhhNominaEmpleado nemp
	CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN deta.Naturaleza = 'I' THEN deta.Monto ELSE 0 END), 0) AS Ingresos,
						ISNULL(SUM(CASE WHEN deta.Naturaleza = 'D' THEN deta.Monto ELSE 0 END), 0) AS Descuentos
				 FROM dbo.rrhhNominaDetalle deta WHERE deta.IdNominaEmpleado = nemp.IdNominaEmpleado) tota
	WHERE nemp.IdNomina = @IdNomina;

	IF @Clase = 'O'
		EXEC dbo.paRrhhNominaPatronalCalcular @IdNomina = @IdNomina;
	ELSE
		UPDATE dbo.rrhhNomina SET TotalPatronal = 0 WHERE IdNomina = @IdNomina;

	UPDATE nomi
	   SET TotalIngresos = tota.Ingresos, TotalDescuentos = tota.Descuentos, TotalLiquido = tota.Liquido,
		   Estado = 'C', FechaCalculo = SYSDATETIME(), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	FROM dbo.rrhhNomina nomi
	CROSS APPLY (SELECT ISNULL(SUM(TotalIngresos), 0) AS Ingresos, ISNULL(SUM(TotalDescuentos), 0) AS Descuentos, ISNULL(SUM(Liquido), 0) AS Liquido
				 FROM dbo.rrhhNominaEmpleado WHERE IdNomina = @IdNomina) tota
	WHERE nomi.IdNomina = @IdNomina;

	COMMIT TRANSACTION;
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

------------------------------------------------------------
-- 8. Consultas de la nómina con los datos nuevos
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaEmpleadoConsultar]
	@IdNomina INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT nemp.IdNominaEmpleado, nemp.IdEmpleado, empl.CodigoEmpleado,
		   empl.PrimerNombre + ' ' + empl.PrimerApellido AS Empleado,
		   nemp.SalarioBase, nemp.DiasLaborados, nemp.TotalIngresos, nemp.TotalDescuentos, nemp.Liquido,
		   depa.Descripcion AS Departamento,
		   ISNULL(nemp.FormaPago, empl.FormaPago) AS FormaPago,
		   enti.gef_descripcion AS Banco,
		   ISNULL(nemp.TipoCuenta, empl.TipoCuenta) AS TipoCuenta,
		   ISNULL(nemp.NumeroCuenta, empl.NumeroCuenta) AS NumeroCuenta,
		   nemp.IdNominaPago, cheq.bce_numero_cheque AS NumeroCheque, pago.Tipo AS TipoPago, pago.FechaPago,
		   sucu.suc_descripcion AS CentroTrabajo, nemp.BaseIgss, nemp.IgssPatronal, nemp.Irtra, nemp.Intecap,
		   nemp.ProvAguinaldo, nemp.ProvBono14
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = nemp.IdEmpleado
	LEFT JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = nemp.IdDepartamento
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_id = nemp.suc_id
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = ISNULL(nemp.gef_id, empl.gef_id)
	LEFT JOIN dbo.rrhhNominaPago pago ON pago.IdNominaPago = nemp.IdNominaPago
	LEFT JOIN dbo.bco_cheque_emitido_enc cheq ON cheq.bce_id = nemp.bce_id
	WHERE nemp.IdNomina = @IdNomina
	ORDER BY empl.PrimerApellido, empl.PrimerNombre;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhNominaDetalleConsultar]
	@IdNominaEmpleado INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT deta.IdNominaDetalle, deta.IdTipoMovimientoNomina, tipo.Codigo, deta.Naturaleza, deta.Descripcion, deta.Monto, deta.Horas
	FROM dbo.rrhhNominaDetalle deta
	INNER JOIN dbo.rrhhTipoMovimientoNomina tipo ON tipo.IdTipoMovimientoNomina = deta.IdTipoMovimientoNomina
	WHERE deta.IdNominaEmpleado = @IdNominaEmpleado
	ORDER BY deta.Naturaleza DESC, tipo.Orden, deta.IdNominaDetalle;
END;
GO

------------------------------------------------------------
-- 9. Tipos de movimiento (columna del libro) y movimientos (horas)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhTipoMovimientoNominaConsultar]
	@SoloActivos BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT tipo.IdTipoMovimientoNomina, tipo.Codigo, tipo.Descripcion, tipo.Naturaleza, tipo.FormaCalculo, tipo.Valor,
		   tipo.EsAutomatico, tipo.EsBaseCalculo, tipo.Orden, tipo.cta_id, cuen.cta_codigo, cuen.cta_nombre, tipo.Estado, tipo.ColumnaLibro
	FROM dbo.rrhhTipoMovimientoNomina tipo
	LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = tipo.cta_id
	WHERE @SoloActivos = 0 OR tipo.Estado = 'A'
	ORDER BY tipo.Naturaleza DESC, tipo.Orden, tipo.Descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhTipoMovimientoNominaGuardar]
	@IdTipoMovimientoNomina	INT = NULL,
	@Codigo					VARCHAR(20),
	@Descripcion			VARCHAR(100),
	@Naturaleza				CHAR(1),
	@FormaCalculo			CHAR(1),
	@Valor					NUMERIC(12, 4),
	@EsAutomatico			BIT,
	@EsBaseCalculo			BIT,
	@Orden					SMALLINT,
	@CtaId					INT = NULL,
	@Estado					CHAR(1) = 'A',
	@ColumnaLibro			VARCHAR(20) = NULL,
	@UsuId					INT,
	@IdResultado			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(LTRIM(RTRIM(@Codigo)), '') = '' OR ISNULL(LTRIM(RTRIM(@Descripcion)), '') = ''
		THROW 52050, 'El código y la descripción son obligatorios.', 1;
	IF @Naturaleza NOT IN ('I','D')
		THROW 52051, 'La naturaleza debe ser Ingreso (suma) o Descuento (resta).', 1;
	IF @FormaCalculo NOT IN ('S','F','P','M')
		THROW 52052, 'La forma de cálculo no es válida.', 1;
	IF @FormaCalculo = 'S' AND @Naturaleza <> 'I'
		THROW 52053, 'El sueldo base solo puede ser un ingreso.', 1;
	IF @EsBaseCalculo = 1 AND @Naturaleza <> 'I'
		THROW 52054, 'Solo un ingreso puede formar parte de la base para porcentajes.', 1;
	IF @FormaCalculo = 'P' AND (@Valor <= 0 OR @Valor > 100)
		THROW 52055, 'El porcentaje debe ser mayor que 0 y no mayor que 100.', 1;
	IF @FormaCalculo = 'M' AND @EsAutomatico = 1
		THROW 52056, 'Un movimiento manual no puede ser automático: se captura por empleado.', 1;
	IF EXISTS (SELECT 1 FROM dbo.rrhhTipoMovimientoNomina WHERE Codigo = @Codigo AND (@IdTipoMovimientoNomina IS NULL OR IdTipoMovimientoNomina <> @IdTipoMovimientoNomina))
		THROW 52057, 'Ya existe un tipo de movimiento con ese código.', 1;
	SET @ColumnaLibro = NULLIF(LTRIM(RTRIM(@ColumnaLibro)), '');
	IF @ColumnaLibro IS NOT NULL AND (
		(@Naturaleza = 'I' AND @ColumnaLibro NOT IN ('ORDINARIO','EXTRAORDINARIO','SEPTIMOS','VACACIONES','BONIFICACION','AGUINALDO','BONO14','OTRAS_BONIF','INDEMNIZACION'))
		OR (@Naturaleza = 'D' AND @ColumnaLibro NOT IN ('IGSS','OTRAS_DEDUCCIONES')))
		THROW 54107, 'La columna del libro de salarios no corresponde a la naturaleza del movimiento.', 1;

	IF @IdTipoMovimientoNomina IS NULL
	BEGIN
		INSERT INTO dbo.rrhhTipoMovimientoNomina (Codigo, Descripcion, Naturaleza, FormaCalculo, Valor, EsAutomatico, EsBaseCalculo, Orden, cta_id, Estado, ColumnaLibro, InsUsuario)
		VALUES (@Codigo, @Descripcion, @Naturaleza, @FormaCalculo, @Valor, @EsAutomatico, @EsBaseCalculo, @Orden, @CtaId, @Estado, @ColumnaLibro, @UsuId);
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.rrhhTipoMovimientoNomina
		   SET Codigo = @Codigo, Descripcion = @Descripcion, Naturaleza = @Naturaleza, FormaCalculo = @FormaCalculo, Valor = @Valor,
			   EsAutomatico = @EsAutomatico, EsBaseCalculo = @EsBaseCalculo, Orden = @Orden, cta_id = @CtaId, Estado = @Estado,
			   ColumnaLibro = @ColumnaLibro, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE IdTipoMovimientoNomina = @IdTipoMovimientoNomina;
		SET @IdResultado = @IdTipoMovimientoNomina;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhMovimientoNominaConsultar]
	@IdEmpleado		INT = NULL,
	@FechaDel		DATE = NULL,
	@FechaAl		DATE = NULL,
	@SoloPendientes	BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT movi.IdMovimientoNomina, movi.IdEmpleado, empl.CodigoEmpleado,
		   empl.PrimerNombre + ' ' + empl.PrimerApellido AS Empleado,
		   movi.IdTipoMovimientoNomina, tipo.Descripcion AS TipoMovimiento, tipo.Naturaleza,
		   movi.Descripcion, movi.Monto, movi.FechaAplicacion, movi.IdNomina, nomi.Descripcion AS Nomina, movi.Estado, movi.Horas
	FROM dbo.rrhhMovimientoNomina movi
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = movi.IdEmpleado
	INNER JOIN dbo.rrhhTipoMovimientoNomina tipo ON tipo.IdTipoMovimientoNomina = movi.IdTipoMovimientoNomina
	LEFT JOIN dbo.rrhhNomina nomi ON nomi.IdNomina = movi.IdNomina
	WHERE (@IdEmpleado IS NULL OR movi.IdEmpleado = @IdEmpleado)
	  AND (@FechaDel IS NULL OR movi.FechaAplicacion >= @FechaDel)
	  AND (@FechaAl IS NULL OR movi.FechaAplicacion <= @FechaAl)
	  AND (@SoloPendientes = 0 OR (movi.IdNomina IS NULL AND movi.Estado = 'A'))
	ORDER BY movi.FechaAplicacion DESC, empl.PrimerApellido;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhMovimientoNominaGuardar]
	@IdMovimientoNomina		INT = NULL,
	@IdEmpleado				INT,
	@IdTipoMovimientoNomina	INT,
	@Descripcion			VARCHAR(200) = NULL,
	@Monto					NUMERIC(12, 2),
	@FechaAplicacion		DATE,
	@Horas					NUMERIC(6, 2) = NULL,
	@UsuId					INT,
	@IdResultado			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF @Monto <= 0
		THROW 52060, 'El monto debe ser mayor que cero.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhTipoMovimientoNomina WHERE IdTipoMovimientoNomina = @IdTipoMovimientoNomina AND FormaCalculo = 'M' AND Estado = 'A')
		THROW 52061, 'Solo se pueden capturar movimientos de tipos manuales y activos.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhEmpleado WHERE IdEmpleado = @IdEmpleado AND Estado = 'A')
		THROW 52062, 'El empleado no existe o está de baja.', 1;
	IF @IdMovimientoNomina IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.rrhhMovimientoNomina WHERE IdMovimientoNomina = @IdMovimientoNomina AND (IdNomina IS NOT NULL OR Estado <> 'A'))
		THROW 52063, 'El movimiento ya se aplicó en una nómina aprobada o está anulado; no se puede modificar.', 1;
	IF @Horas IS NOT NULL AND (@Horas <= 0 OR @Horas > 744)
		THROW 54108, 'Las horas deben ser mayores que cero.', 1;
	-- Las horas extra se anotan en el libro de salarios.
	IF @Horas IS NULL AND EXISTS (SELECT 1 FROM dbo.rrhhTipoMovimientoNomina
								  WHERE IdTipoMovimientoNomina = @IdTipoMovimientoNomina AND ColumnaLibro = 'EXTRAORDINARIO')
		THROW 54109, 'Indique cuántas horas extra trabajó el empleado: van al libro de salarios.', 1;

	IF @IdMovimientoNomina IS NULL
	BEGIN
		INSERT INTO dbo.rrhhMovimientoNomina (IdEmpleado, IdTipoMovimientoNomina, Descripcion, Monto, FechaAplicacion, Horas, InsUsuario)
		VALUES (@IdEmpleado, @IdTipoMovimientoNomina, @Descripcion, @Monto, @FechaAplicacion, @Horas, @UsuId);
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.rrhhMovimientoNomina
		   SET IdEmpleado = @IdEmpleado, IdTipoMovimientoNomina = @IdTipoMovimientoNomina, Descripcion = @Descripcion, Monto = @Monto,
			   FechaAplicacion = @FechaAplicacion, Horas = @Horas, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE IdMovimientoNomina = @IdMovimientoNomina;
		SET @IdResultado = @IdMovimientoNomina;
	END
END;
GO

------------------------------------------------------------
-- 10. Datos del patrono, centros de trabajo y datos laborales del empleado
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCompaniaRrhhConsultar]
	@CiaId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cia_id AS CiaId, cia_igss_numero_patronal AS IgssNumeroPatronal, cia_libro_salarios_autorizacion AS LibroSalariosAutorizacion
	FROM dbo.gen_compania
	WHERE cia_id = @CiaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaRrhhGuardar]
	@CiaId						INT,
	@IgssNumeroPatronal			VARCHAR(20) = NULL,
	@LibroSalariosAutorizacion	VARCHAR(60) = NULL,
	@UsuId						INT
AS
BEGIN
	SET NOCOUNT ON;
	SET @IgssNumeroPatronal = NULLIF(LTRIM(RTRIM(@IgssNumeroPatronal)), '');
	IF @IgssNumeroPatronal IS NOT NULL AND @IgssNumeroPatronal LIKE '%[^0-9]%'
		THROW 54110, 'El número patronal del IGSS solo lleva dígitos.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_id = @CiaId)
		THROW 54103, 'La compañía no existe.', 1;

	UPDATE dbo.gen_compania
	   SET cia_igss_numero_patronal = @IgssNumeroPatronal,
		   cia_libro_salarios_autorizacion = NULLIF(LTRIM(RTRIM(@LibroSalariosAutorizacion)), ''),
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cia_id = @CiaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paSucursalIgssConsultar]
	@CiaId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT sucu.suc_id AS SucId, sucu.cia_id AS CiaId, sucu.suc_codigo AS Codigo, sucu.suc_descripcion AS Descripcion,
		   sucu.suc_igss_centro_trabajo AS CentroTrabajo, sucu.suc_tasa_igss_patronal AS TasaIgssPatronal,
		   sucu.suc_tasa_igss_laboral AS TasaIgssLaboral, sucu.suc_tasa_irtra AS TasaIrtra, sucu.suc_tasa_intecap AS TasaIntecap,
		   sucu.suc_estado AS Estado
	FROM dbo.gen_sucursal sucu
	WHERE @CiaId IS NULL OR sucu.cia_id = @CiaId
	ORDER BY sucu.cia_id, sucu.suc_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paSucursalIgssGuardar]
	@SucId				INT,
	@CentroTrabajo		VARCHAR(10) = NULL,
	@TasaIgssPatronal	NUMERIC(6, 3),
	@TasaIgssLaboral	NUMERIC(6, 3) = NULL,
	@TasaIrtra			NUMERIC(6, 3),
	@TasaIntecap		NUMERIC(6, 3),
	@UsuId				INT
AS
BEGIN
	SET NOCOUNT ON;
	SET @CentroTrabajo = NULLIF(LTRIM(RTRIM(@CentroTrabajo)), '');
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE suc_id = @SucId)
		THROW 54111, 'La sucursal no existe.', 1;
	IF @CentroTrabajo IS NOT NULL AND @CentroTrabajo LIKE '%[^0-9]%'
		THROW 54112, 'El número de centro de trabajo del IGSS solo lleva dígitos.', 1;
	IF @TasaIgssPatronal NOT BETWEEN 0 AND 100 OR @TasaIrtra NOT BETWEEN 0 AND 100 OR @TasaIntecap NOT BETWEEN 0 AND 100
	   OR (@TasaIgssLaboral IS NOT NULL AND @TasaIgssLaboral NOT BETWEEN 0 AND 100)
		THROW 54113, 'Las tasas son porcentajes entre 0 y 100.', 1;

	UPDATE dbo.gen_sucursal
	   SET suc_igss_centro_trabajo = @CentroTrabajo, suc_tasa_igss_patronal = @TasaIgssPatronal, suc_tasa_igss_laboral = @TasaIgssLaboral,
		   suc_tasa_irtra = @TasaIrtra, suc_tasa_intecap = @TasaIntecap, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE suc_id = @SucId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoLaboralGuardar]
	@IdEmpleado		INT,
	@SucId			INT = NULL,
	@Nacionalidad	VARCHAR(40) = NULL,
	@Jornada		CHAR(1) = 'D',
	@TiempoContrato	CHAR(2) = 'TC',
	@UsuId			INT
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @CiaId INT = (SELECT cia_id FROM dbo.rrhhEmpleado WHERE IdEmpleado = @IdEmpleado);
	IF @CiaId IS NULL
		THROW 54114, 'El empleado no existe.', 1;
	IF @SucId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE suc_id = @SucId AND cia_id = @CiaId)
		THROW 54115, 'El centro de trabajo debe ser una sucursal de la compañía del empleado.', 1;
	IF ISNULL(@Jornada, '') NOT IN ('D','M','N')
		THROW 54116, 'La jornada debe ser diurna, mixta o nocturna.', 1;
	IF ISNULL(@TiempoContrato, '') NOT IN ('TC','TP')
		THROW 54117, 'El contrato debe ser a tiempo completo o a tiempo parcial.', 1;

	UPDATE dbo.rrhhEmpleado
	   SET suc_id = @SucId, Nacionalidad = NULLIF(UPPER(LTRIM(RTRIM(@Nacionalidad))), ''), Jornada = @Jornada, TiempoContrato = @TiempoContrato,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdEmpleado = @IdEmpleado;
END;
GO

------------------------------------------------------------
-- 11. Libro de salarios
--
-- Un folio por trabajador. El folio se asigna la primera vez que el
-- trabajador aparece en el libro, en orden de ingreso, y no cambia. Cada
-- nómina aprobada es un renglón; las de aguinaldo y bono 14 caen en el año
-- de su fecha de pago y las ordinarias en el de su fecha final.
-- Horas ordinarias: días × jornada semanal / 7 (diurna 48, mixta 42,
-- nocturna 36, Código de Trabajo arts. 116 y 117).
-- Resultados: 1) patrono, 2) trabajadores, 3) renglones.
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhLibroSalariosConsultar]
	@CiaId		INT,
	@Anio		INT,
	@IdEmpleado	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_id = @CiaId)
		THROW 54103, 'La compañía no existe.', 1;

	DECLARE @renglones TABLE (IdNominaEmpleado INT PRIMARY KEY, IdEmpleado INT NOT NULL, IdNomina INT NOT NULL);
	INSERT INTO @renglones (IdNominaEmpleado, IdEmpleado, IdNomina)
	SELECT nemp.IdNominaEmpleado, nemp.IdEmpleado, nemp.IdNomina
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhNomina nomi ON nomi.IdNomina = nemp.IdNomina
	WHERE nomi.cia_id = @CiaId AND nomi.Estado = 'A'
	  AND YEAR(CASE WHEN nomi.Clase = 'O' THEN nomi.FechaAl ELSE ISNULL(nomi.FechaPago, nomi.FechaAl) END) = @Anio
	  AND (@IdEmpleado IS NULL OR nemp.IdEmpleado = @IdEmpleado);

	-- Folios nuevos a continuación del último de la compañía.
	BEGIN TRANSACTION;
	DECLARE @ultimo INT = (SELECT ISNULL(MAX(FolioLibroSalarios), 0) FROM dbo.rrhhEmpleado WITH (UPDLOCK, HOLDLOCK) WHERE cia_id = @CiaId);
	UPDATE empl SET FolioLibroSalarios = nuev.Folio
	FROM dbo.rrhhEmpleado empl
	INNER JOIN (SELECT sinf.IdEmpleado, @ultimo + ROW_NUMBER() OVER (ORDER BY sinf.FechaIngreso, sinf.IdEmpleado) AS Folio
				FROM dbo.rrhhEmpleado sinf
				WHERE sinf.cia_id = @CiaId AND sinf.FolioLibroSalarios IS NULL
				  AND EXISTS (SELECT 1 FROM @renglones reng WHERE reng.IdEmpleado = sinf.IdEmpleado)) nuev ON nuev.IdEmpleado = empl.IdEmpleado;
	COMMIT TRANSACTION;

	SELECT comp.cia_id AS CiaId, comp.cia_nombre_comercial AS NombreComercial, comp.cia_nit AS Nit, comp.cia_direccion AS Direccion,
		   comp.cia_representante_legal AS RepresentanteLegal, comp.cia_igss_numero_patronal AS IgssNumeroPatronal,
		   comp.cia_libro_salarios_autorizacion AS LibroSalariosAutorizacion, @Anio AS Anio
	FROM dbo.gen_compania comp
	WHERE comp.cia_id = @CiaId;

	DECLARE @referencia DATE = CASE WHEN @Anio = YEAR(GETDATE()) THEN CAST(GETDATE() AS DATE) ELSE DATEFROMPARTS(@Anio, 12, 31) END;
	SELECT empl.IdEmpleado, empl.FolioLibroSalarios AS Folio, empl.CodigoEmpleado,
		   CONCAT_WS(' ', empl.PrimerNombre, NULLIF(empl.SegundoNombre, ''), empl.PrimerApellido, NULLIF(empl.SegundoApellido, ''),
				'DE ' + NULLIF(empl.ApellidoCasada, '')) AS NombreCompleto,
		   CASE WHEN empl.FechaNacimiento IS NULL THEN NULL
				ELSE DATEDIFF(YEAR, empl.FechaNacimiento, @referencia)
					 - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, empl.FechaNacimiento, @referencia), empl.FechaNacimiento) > @referencia THEN 1 ELSE 0 END
		   END AS Edad,
		   empl.Genero, ISNULL(empl.Nacionalidad, 'GUATEMALTECA') AS Nacionalidad,
		   tdoc.Descripcion AS TipoDocumento, empl.NumeroDocumento, empl.NumeroAfiliacionIGSS, empl.Nit,
		   pues.Descripcion AS Puesto, empl.FechaIngreso, empl.FechaBaja, empl.Jornada, empl.TiempoContrato, empl.SalarioBase
	FROM dbo.rrhhEmpleado empl
	LEFT JOIN dbo.rrhhTipoDocumentoIdentificacion tdoc ON tdoc.IdTipoDocumentoIdentificacion = empl.IdTipoDocumentoIdentificacion
	LEFT JOIN dbo.rrhhPlaza plaz ON plaz.IdPlaza = empl.IdPlaza
	LEFT JOIN dbo.rrhhDepartamentoPuesto depu ON depu.IdDepartamentoPuesto = plaz.IdDepartamentoPuesto
	LEFT JOIN dbo.rrhhPuesto pues ON pues.IdPuesto = depu.IdPuesto
	WHERE EXISTS (SELECT 1 FROM @renglones reng WHERE reng.IdEmpleado = empl.IdEmpleado)
	ORDER BY empl.FolioLibroSalarios;

	SELECT reng.IdEmpleado, nomi.IdNomina, nomi.Descripcion AS Nomina, nomi.Clase, nomi.TipoPeriodo, nomi.FechaDel, nomi.FechaAl, nomi.FechaPago,
		   nemp.SalarioBase, nemp.DiasLaborados,
		   CASE WHEN nomi.Clase = 'O'
				THEN CAST(ROUND(nemp.DiasLaborados * CASE empl.Jornada WHEN 'M' THEN 42.0 WHEN 'N' THEN 36.0 ELSE 48.0 END / 7.0, 0) AS INT)
				ELSE 0 END AS HorasOrdinarias,
		   colu.HorasExtra, colu.Ordinario, colu.Extraordinario, colu.Septimos, colu.Vacaciones,
		   colu.Ordinario + colu.Extraordinario + colu.Septimos + colu.Vacaciones AS SalarioTotal,
		   colu.Igss, colu.OtrasDeducciones, colu.Igss + colu.OtrasDeducciones AS TotalDeducciones,
		   colu.Bono14, colu.Aguinaldo, colu.Bonificacion, colu.OtrasBonificaciones, colu.Indemnizacion,
		   nemp.Liquido
	FROM @renglones reng
	INNER JOIN dbo.rrhhNominaEmpleado nemp ON nemp.IdNominaEmpleado = reng.IdNominaEmpleado
	INNER JOIN dbo.rrhhNomina nomi ON nomi.IdNomina = reng.IdNomina
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = reng.IdEmpleado
	CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN colu.Columna = 'EXTRAORDINARIO' THEN deta.Horas END), 0) AS HorasExtra,
						ISNULL(SUM(CASE WHEN colu.Columna = 'ORDINARIO' THEN deta.Monto END), 0) AS Ordinario,
						ISNULL(SUM(CASE WHEN colu.Columna = 'EXTRAORDINARIO' THEN deta.Monto END), 0) AS Extraordinario,
						ISNULL(SUM(CASE WHEN colu.Columna = 'SEPTIMOS' THEN deta.Monto END), 0) AS Septimos,
						ISNULL(SUM(CASE WHEN colu.Columna = 'VACACIONES' THEN deta.Monto END), 0) AS Vacaciones,
						ISNULL(SUM(CASE WHEN colu.Columna = 'IGSS' THEN deta.Monto END), 0) AS Igss,
						ISNULL(SUM(CASE WHEN colu.Columna = 'OTRAS_DEDUCCIONES' THEN deta.Monto END), 0) AS OtrasDeducciones,
						ISNULL(SUM(CASE WHEN colu.Columna = 'BONO14' THEN deta.Monto END), 0) AS Bono14,
						ISNULL(SUM(CASE WHEN colu.Columna = 'AGUINALDO' THEN deta.Monto END), 0) AS Aguinaldo,
						ISNULL(SUM(CASE WHEN colu.Columna = 'BONIFICACION' THEN deta.Monto END), 0) AS Bonificacion,
						ISNULL(SUM(CASE WHEN colu.Columna = 'OTRAS_BONIF' THEN deta.Monto END), 0) AS OtrasBonificaciones,
						ISNULL(SUM(CASE WHEN colu.Columna = 'INDEMNIZACION' THEN deta.Monto END), 0) AS Indemnizacion
				 FROM dbo.rrhhNominaDetalle deta
				 INNER JOIN dbo.rrhhTipoMovimientoNomina tipo ON tipo.IdTipoMovimientoNomina = deta.IdTipoMovimientoNomina
				 -- Un tipo sin columna va a otras bonificaciones o a otras deducciones.
				 CROSS APPLY (SELECT ISNULL(tipo.ColumnaLibro, CASE deta.Naturaleza WHEN 'I' THEN 'OTRAS_BONIF' ELSE 'OTRAS_DEDUCCIONES' END) AS Columna) colu
				 WHERE deta.IdNominaEmpleado = nemp.IdNominaEmpleado) colu
	ORDER BY empl.FolioLibroSalarios, CASE WHEN nomi.Clase = 'O' THEN nomi.FechaAl ELSE ISNULL(nomi.FechaPago, nomi.FechaAl) END, nomi.IdNomina;
END;
GO

------------------------------------------------------------
-- 12. Planilla mensual del IGSS
--
-- Nóminas ordinarias aprobadas cuya fecha final cae en el mes. Por
-- empleado y centro de trabajo: salario afecto, cuota laboral (la que se
-- le descontó), cuota patronal, IRTRA e INTECAP, con fecha de alta o de
-- baja si ocurrió en el mes. Resultados: 1) patrono y totales, 2) centros
-- de trabajo, 3) empleados.
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhPlanillaIgssConsultar]
	@CiaId	INT,
	@Anio	INT,
	@Mes	INT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_id = @CiaId)
		THROW 54103, 'La compañía no existe.', 1;
	IF @Mes IS NULL OR @Mes NOT BETWEEN 1 AND 12 OR @Anio IS NULL OR @Anio NOT BETWEEN 2000 AND 2100
		THROW 54118, 'Indique un mes y un año válidos.', 1;

	DECLARE @del DATE = DATEFROMPARTS(@Anio, @Mes, 1);
	DECLARE @al DATE = EOMONTH(@del);

	DECLARE @empleados TABLE (IdEmpleado INT NOT NULL, suc_id INT NULL, Dias NUMERIC(7, 2) NOT NULL, SalarioAfecto NUMERIC(14, 2) NOT NULL,
							  CuotaLaboral NUMERIC(14, 2) NOT NULL, CuotaPatronal NUMERIC(14, 2) NOT NULL, Irtra NUMERIC(14, 2) NOT NULL,
							  Intecap NUMERIC(14, 2) NOT NULL, Nominas INT NOT NULL);
	INSERT INTO @empleados
	SELECT nemp.IdEmpleado, nemp.suc_id, SUM(nemp.DiasLaborados), SUM(nemp.BaseIgss),
		   SUM(ISNULL(labo.Monto, 0)), SUM(nemp.IgssPatronal), SUM(nemp.Irtra), SUM(nemp.Intecap), COUNT(*)
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhNomina nomi ON nomi.IdNomina = nemp.IdNomina
	OUTER APPLY (SELECT SUM(deta.Monto) AS Monto
				 FROM dbo.rrhhNominaDetalle deta
				 INNER JOIN dbo.rrhhTipoMovimientoNomina tipo ON tipo.IdTipoMovimientoNomina = deta.IdTipoMovimientoNomina
				 WHERE deta.IdNominaEmpleado = nemp.IdNominaEmpleado AND tipo.ColumnaLibro = 'IGSS') labo
	WHERE nomi.cia_id = @CiaId AND nomi.Clase = 'O' AND nomi.Estado = 'A' AND nomi.FechaAl BETWEEN @del AND @al
	GROUP BY nemp.IdEmpleado, nemp.suc_id;

	SELECT comp.cia_id AS CiaId, comp.cia_nombre_comercial AS NombreComercial, comp.cia_nit AS Nit, comp.cia_email AS Email,
		   comp.cia_igss_numero_patronal AS IgssNumeroPatronal, @Anio AS Anio, @Mes AS Mes,
		   (SELECT COUNT(DISTINCT IdEmpleado) FROM @empleados) AS Empleados,
		   (SELECT ISNULL(SUM(SalarioAfecto), 0) FROM @empleados) AS SalarioAfecto,
		   (SELECT ISNULL(SUM(CuotaLaboral), 0) FROM @empleados) AS CuotaLaboral,
		   (SELECT ISNULL(SUM(CuotaPatronal), 0) FROM @empleados) AS CuotaPatronal,
		   (SELECT ISNULL(SUM(Irtra), 0) FROM @empleados) AS Irtra,
		   (SELECT ISNULL(SUM(Intecap), 0) FROM @empleados) AS Intecap,
		   (SELECT ISNULL(SUM(CuotaLaboral + CuotaPatronal + Irtra + Intecap), 0) FROM @empleados) AS TotalPagar,
		   -- Nóminas del mes que todavía no están aprobadas: no entran en la planilla.
		   (SELECT COUNT(*) FROM dbo.rrhhNomina WHERE cia_id = @CiaId AND Clase = 'O' AND Estado IN ('B','C') AND FechaAl BETWEEN @del AND @al) AS NominasPendientes
	FROM dbo.gen_compania comp
	WHERE comp.cia_id = @CiaId;

	SELECT sucu.suc_id AS SucId, sucu.suc_codigo AS Codigo, sucu.suc_descripcion AS Descripcion, sucu.suc_igss_centro_trabajo AS CentroTrabajo,
		   sucu.suc_tasa_igss_patronal AS TasaIgssPatronal, sucu.suc_tasa_irtra AS TasaIrtra, sucu.suc_tasa_intecap AS TasaIntecap,
		   COUNT(DISTINCT emps.IdEmpleado) AS Empleados, SUM(emps.SalarioAfecto) AS SalarioAfecto, SUM(emps.CuotaLaboral) AS CuotaLaboral,
		   SUM(emps.CuotaPatronal) AS CuotaPatronal, SUM(emps.Irtra) AS Irtra, SUM(emps.Intecap) AS Intecap,
		   SUM(emps.CuotaLaboral + emps.CuotaPatronal + emps.Irtra + emps.Intecap) AS TotalPagar
	FROM @empleados emps
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_id = emps.suc_id
	GROUP BY sucu.suc_id, sucu.suc_codigo, sucu.suc_descripcion, sucu.suc_igss_centro_trabajo,
			 sucu.suc_tasa_igss_patronal, sucu.suc_tasa_irtra, sucu.suc_tasa_intecap
	ORDER BY sucu.suc_codigo;

	SELECT emps.IdEmpleado, empl.CodigoEmpleado, empl.NumeroAfiliacionIGSS, empl.NumeroDocumento AS Dpi, empl.Nit,
		   empl.PrimerNombre, empl.SegundoNombre, empl.PrimerApellido, empl.SegundoApellido, empl.ApellidoCasada,
		   sucu.suc_igss_centro_trabajo AS CentroTrabajo, sucu.suc_descripcion AS Sucursal, pues.Descripcion AS Puesto,
		   empl.TiempoContrato,
		   CASE WHEN empl.FechaIngreso BETWEEN @del AND @al THEN empl.FechaIngreso END AS FechaAlta,
		   CASE WHEN empl.FechaBaja BETWEEN @del AND @al THEN empl.FechaBaja END AS FechaBaja,
		   emps.Dias, emps.SalarioAfecto, emps.CuotaLaboral, emps.CuotaPatronal, emps.Irtra, emps.Intecap,
		   emps.CuotaLaboral + emps.CuotaPatronal + emps.Irtra + emps.Intecap AS Total, emps.Nominas
	FROM @empleados emps
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = emps.IdEmpleado
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_id = emps.suc_id
	LEFT JOIN dbo.rrhhPlaza plaz ON plaz.IdPlaza = empl.IdPlaza
	LEFT JOIN dbo.rrhhDepartamentoPuesto depu ON depu.IdDepartamentoPuesto = plaz.IdDepartamentoPuesto
	LEFT JOIN dbo.rrhhPuesto pues ON pues.IdPuesto = depu.IdPuesto
	ORDER BY sucu.suc_codigo, empl.PrimerApellido, empl.SegundoApellido, empl.PrimerNombre;
END;
GO

------------------------------------------------------------
-- 13. Nóminas aprobadas antes de este script: cuota patronal y
--     provisiones para el libro y la planilla (su póliza no cambia).
------------------------------------------------------------
DECLARE @pendientes TABLE (IdNomina INT PRIMARY KEY);
INSERT INTO @pendientes (IdNomina)
SELECT DISTINCT nemp.IdNomina
FROM dbo.rrhhNominaEmpleado nemp
INNER JOIN dbo.rrhhNomina nomi ON nomi.IdNomina = nemp.IdNomina
WHERE nomi.Clase = 'O' AND nomi.Estado IN ('C','A') AND nemp.suc_id IS NULL;

DECLARE @id INT = (SELECT MIN(IdNomina) FROM @pendientes);
WHILE @id IS NOT NULL
BEGIN
	EXEC dbo.paRrhhNominaPatronalCalcular @IdNomina = @id;
	SET @id = (SELECT MIN(IdNomina) FROM @pendientes WHERE IdNomina > @id);
END
GO

PRINT '49: cuota patronal, aguinaldo y bono 14, libro de salarios y planilla del IGSS listos.';
GO
