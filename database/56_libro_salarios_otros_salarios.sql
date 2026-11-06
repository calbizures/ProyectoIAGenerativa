/*
================================================================================
 56_libro_salarios_otros_salarios.sql
 Libro de salarios: columna "Otros salarios" del formato único del Ministerio
 de Trabajo (Acuerdo Ministerial 124-2019).

   El formato único separa, dentro del salario devengado, el salario
   ordinario, el extraordinario, OTROS SALARIOS (comisiones, destajo,
   producción), los séptimos y asuetos y las vacaciones. Hasta ahora las
   comisiones se sumaban al ordinario.
   - Nueva columna OTROS_SALARIOS para los tipos de movimiento de nómina.
   - El tipo COMISION pasa a esa columna (si seguía en ORDINARIO).
   - paRrhhLibroSalariosConsultar devuelve OtrosSalarios y lo incluye en el
     salario total.
   - El promedio de salario ordinario (aguinaldo, Bono 14 y sus provisiones)
     sigue incluyendo las comisiones: cuenta ORDINARIO y OTROS_SALARIOS.

 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.CK_rrhhTipoMovimientoNomina_ColumnaLibro', 'C') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_rrhhTipoMovimientoNomina_ColumnaLibro' AND definition LIKE '%OTROS_SALARIOS%')
	ALTER TABLE dbo.rrhhTipoMovimientoNomina DROP CONSTRAINT [CK_rrhhTipoMovimientoNomina_ColumnaLibro];
GO
IF OBJECT_ID('dbo.CK_rrhhTipoMovimientoNomina_ColumnaLibro', 'C') IS NULL
	ALTER TABLE dbo.rrhhTipoMovimientoNomina ADD CONSTRAINT [CK_rrhhTipoMovimientoNomina_ColumnaLibro]
		CHECK ([ColumnaLibro] IS NULL OR [ColumnaLibro] IN ('ORDINARIO', 'EXTRAORDINARIO', 'OTROS_SALARIOS', 'SEPTIMOS', 'VACACIONES',
			'BONIFICACION', 'AGUINALDO', 'BONO14', 'OTRAS_BONIF', 'INDEMNIZACION', 'IGSS', 'OTRAS_DEDUCCIONES'));
GO

UPDATE dbo.rrhhTipoMovimientoNomina
   SET ColumnaLibro = 'OTROS_SALARIOS', UpdFechaHora = SYSDATETIME()
 WHERE Codigo = 'COMISION' AND ColumnaLibro = 'ORDINARIO';
GO

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
		   colu.HorasExtra, colu.Ordinario, colu.Extraordinario, colu.OtrosSalarios, colu.Septimos, colu.Vacaciones,
		   colu.Ordinario + colu.Extraordinario + colu.OtrosSalarios + colu.Septimos + colu.Vacaciones AS SalarioTotal,
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
						ISNULL(SUM(CASE WHEN colu.Columna = 'OTROS_SALARIOS' THEN deta.Monto END), 0) AS OtrosSalarios,
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

-- Promedios y provisiones: ORDINARIO + OTROS_SALARIOS.
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
								   WHERE deta.IdNominaEmpleado = nemp.IdNominaEmpleado AND tord.ColumnaLibro IN ('ORDINARIO', 'OTROS_SALARIOS')) AS Ordinario,
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
						ISNULL(SUM(CASE WHEN tipo.ColumnaLibro IN ('ORDINARIO', 'OTROS_SALARIOS') THEN deta.Monto END), 0) AS Ordinario
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
		(@Naturaleza = 'I' AND @ColumnaLibro NOT IN ('ORDINARIO','EXTRAORDINARIO','OTROS_SALARIOS','SEPTIMOS','VACACIONES','BONIFICACION','AGUINALDO','BONO14','OTRAS_BONIF','INDEMNIZACION'))
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

PRINT '56_libro_salarios_otros_salarios.sql aplicado.';
GO
