------------------------------------------------------------------------------
-- 37_datos_sinteticos_bancos_nomina.sql
--
-- Datos de prueba de la fase A (script 36). Todo pasa por los procedimientos
-- de la aplicación, así que también sirve de prueba de humo de sus partidas:
--
--   1. Bancos: una segunda cuenta (Banrural, para nómina) con su chequera.
--   2. Empleados: forma de pago y cuenta de cada uno. Tres cobran por
--      transferencia y uno con cheque. Se agrega un técnico de soporte que
--      cobra por nómina semanal y con cheque.
--   3. Pago de la nómina mensual que dejó el 30: un lote de transferencias
--      y los cheques.
--   4. Nómina semanal de la semana pasada: se crea, calcula, aprueba (con el
--      gasto desglosado por centro de costo) y se paga con cheque.
--   5. Dos cheques libres con cuenta de gasto y centro de costo.
--
-- Todos los números de cuenta son inventados.
--
-- Requiere 36. Se puede volver a correr: cada sección se omite si sus datos
-- ya existen.
------------------------------------------------------------------------------

USE [erp_db];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Cuenta bancaria para nómina y su chequera
------------------------------------------------------------
DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
DECLARE @banrural INT = (SELECT gef_id FROM dbo.gen_entidad_financiera WHERE gef_codigo = 'BANRURAL');
DECLARE @cta_banco INT = (SELECT cta_id FROM dbo.cont_cuenta_contable WHERE cta_codigo = '1120017');
DECLARE @bcb_id INT, @cbc_id INT;

IF EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_numero_cuenta = '3-445-00981-2')
	PRINT 'Bancos: la cuenta de nómina ya existe, se omite la sección.';
ELSE
BEGIN
	EXEC dbo.paBcoCuentaBancariaGuardar @NumeroCuenta = '3-445-00981-2', @Descripcion = 'Cuenta de nómina', @GefId = @banrural,
		@Tipo = 'M', @CtaId = @cta_banco, @UsuId = @usu, @IdResultado = @bcb_id OUTPUT;
	DECLARE @recepcion DATE = DATEADD(MONTH, -2, CAST(GETDATE() AS DATE));
	EXEC dbo.paBcoChequeraGuardar @BcbId = @bcb_id, @ChequeDel = 5001, @ChequeAl = 5050, @FechaRecepcion = @recepcion,
		@UsuId = @usu, @IdResultado = @cbc_id OUTPUT;
	PRINT 'Bancos: cuenta de nómina Banrural con chequera 5001-5050.';
END
GO

------------------------------------------------------------
-- 2. Datos de pago de los empleados y un empleado de nómina semanal
------------------------------------------------------------
DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
DECLARE @bi INT = (SELECT gef_id FROM dbo.gen_entidad_financiera WHERE gef_codigo = 'BI'),
		@bam INT = (SELECT gef_id FROM dbo.gen_entidad_financiera WHERE gef_codigo = 'BAM'),
		@banrural INT = (SELECT gef_id FROM dbo.gen_entidad_financiera WHERE gef_codigo = 'BANRURAL');
DECLARE @id INT, @tipo_nomina CHAR(1);

DECLARE @pagos TABLE (Codigo VARCHAR(16), FormaPago CHAR(1), GefId INT NULL, TipoCuenta CHAR(1) NULL, NumeroCuenta VARCHAR(30) NULL);
INSERT INTO @pagos VALUES
	('EMP001', 'T', @bi,       'M', '301-5501234-1'),
	('EMP002', 'T', @bam,      'A', '40-2213345-0'),
	('EMP003', 'T', @banrural, 'A', '4450087712'),
	('EMP004', 'C', NULL,      NULL, NULL);

DECLARE @codigo VARCHAR(16), @forma CHAR(1), @gef INT, @tcta CHAR(1), @ncta VARCHAR(30);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
	SELECT pago.Codigo, pago.FormaPago, pago.GefId, pago.TipoCuenta, pago.NumeroCuenta
	FROM @pagos pago
	INNER JOIN dbo.rrhhEmpleado empl ON empl.CodigoEmpleado = pago.Codigo
	WHERE empl.FormaPago IS NULL;
OPEN cur;
FETCH NEXT FROM cur INTO @codigo, @forma, @gef, @tcta, @ncta;
WHILE @@FETCH_STATUS = 0
BEGIN
	SELECT @id = IdEmpleado, @tipo_nomina = TipoNomina FROM dbo.rrhhEmpleado WHERE CodigoEmpleado = @codigo;
	EXEC dbo.paRrhhEmpleadoPagoGuardar @IdEmpleado = @id, @TipoNomina = @tipo_nomina, @FormaPago = @forma,
		@GefId = @gef, @TipoCuenta = @tcta, @NumeroCuenta = @ncta, @UsuId = @usu;
	PRINT CONCAT('Empleado ', @codigo, ': forma de pago ', @forma, '.');
	FETCH NEXT FROM cur INTO @codigo, @forma, @gef, @tcta, @ncta;
END
CLOSE cur; DEALLOCATE cur;

-- Técnico de soporte con nómina semanal, en la plaza vacante de Soporte técnico.
IF NOT EXISTS (SELECT 1 FROM dbo.rrhhEmpleado WHERE CodigoEmpleado = 'EMP005')
BEGIN
	DECLARE @cia INT = (SELECT cia_id FROM dbo.rrhhEmpleado WHERE CodigoEmpleado = 'EMP001'),
			@tdoc INT = (SELECT IdTipoDocumentoIdentificacion FROM dbo.rrhhEmpleado WHERE CodigoEmpleado = 'EMP001'),
			@plaza INT = (SELECT TOP 1 plaz.IdPlaza FROM dbo.rrhhPlaza plaz
						  WHERE plaz.Descripcion = 'Técnico de soporte 1' AND plaz.Estado = 'A'
							AND NOT EXISTS (SELECT 1 FROM dbo.rrhhEmpleado empl WHERE empl.IdPlaza = plaz.IdPlaza AND empl.Estado = 'A')),
			@ingreso DATE = DATEADD(MONTH, -2, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)),
			@nuevo INT;
	EXEC dbo.paRrhhEmpleadoGuardar @CodigoEmpleado = 'EMP005', @CiaId = @cia, @PrimerNombre = 'Pedro', @SegundoNombre = 'Antonio',
		@PrimerApellido = 'Xol', @SegundoApellido = 'Caal', @Genero = 'M', @FechaNacimiento = '1998-03-14', @FechaIngreso = @ingreso,
		@Direccion = 'Zona 7, Ciudad de Guatemala', @IdTipoDocumentoIdentificacion = @tdoc, @NumeroDocumento = '3124567890101',
		@IdPlaza = @plaza, @SalarioBase = 4200.00, @UsuId = @usu, @IdResultado = @nuevo OUTPUT;
	EXEC dbo.paRrhhEmpleadoPagoGuardar @IdEmpleado = @nuevo, @TipoNomina = 'S', @FormaPago = 'C', @UsuId = @usu;
	PRINT 'Empleado EMP005: nómina semanal, pago con cheque.';
END
GO

------------------------------------------------------------
-- 3. Pago de la nómina mensual aprobada por el 30
------------------------------------------------------------
DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
DECLARE @nomina INT = (SELECT TOP 1 IdNomina FROM dbo.rrhhNomina WHERE TipoPeriodo = 'M' AND Estado = 'A' ORDER BY FechaDel DESC);
DECLARE @bcb_bi INT = (SELECT bcb_id FROM dbo.bco_cuenta_bancaria WHERE bcb_numero_cuenta = '301-0001122-3');
DECLARE @cbc_bi INT = (SELECT TOP 1 cbc_id FROM dbo.bco_cuenta_bancaria_chequera WHERE bcb_id = @bcb_bi AND cbc_estado = 'A' ORDER BY cbc_cheque_del);
DECLARE @pago INT, @fecha DATE;

IF @nomina IS NULL
	PRINT 'Nómina mensual: no hay una aprobada, se omite la sección.';
ELSE IF EXISTS (SELECT 1 FROM dbo.rrhhNominaPago WHERE IdNomina = @nomina)
	PRINT 'Nómina mensual: ya tiene pagos, se omite la sección.';
ELSE
BEGIN
	-- Se aprobó antes del 36: se le toma la foto de los datos de pago y
	-- del departamento de cada empleado.
	UPDATE nemp
	   SET IdDepartamento = dbo.fnRrhhEmpleadoDepartamento(empl.IdEmpleado),
		   FormaPago = empl.FormaPago, gef_id = empl.gef_id, TipoCuenta = empl.TipoCuenta, NumeroCuenta = empl.NumeroCuenta
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = nemp.IdEmpleado
	WHERE nemp.IdNomina = @nomina;

	SET @fecha = (SELECT ISNULL(FechaPago, FechaAl) FROM dbo.rrhhNomina WHERE IdNomina = @nomina);
	IF @fecha > CAST(GETDATE() AS DATE) SET @fecha = CAST(GETDATE() AS DATE);
	EXEC dbo.paRrhhNominaPagarTransferencias @IdNomina = @nomina, @BcbId = @bcb_bi, @Fecha = @fecha,
		@Referencia = 'Lote BI-0001', @UsuId = @usu, @IdNominaPago = @pago OUTPUT;
	EXEC dbo.paRrhhNominaEmitirCheques @IdNomina = @nomina, @CbcId = @cbc_bi, @Fecha = @fecha, @UsuId = @usu, @IdNominaPago = @pago OUTPUT;
	PRINT 'Nómina mensual: transferencias y cheques emitidos.';
END
GO

------------------------------------------------------------
-- 4. Nómina semanal de la semana pasada
------------------------------------------------------------
DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
DECLARE @cia INT = (SELECT cia_id FROM dbo.rrhhEmpleado WHERE CodigoEmpleado = 'EMP005');
DECLARE @hoy DATE = CAST(GETDATE() AS DATE);
DECLARE @lunes DATE = DATEADD(DAY, -7 - (DATEDIFF(DAY, '19000101', @hoy) % 7), @hoy);
DECLARE @domingo DATE = DATEADD(DAY, 6, @lunes);
DECLARE @nomina INT, @pago INT;
DECLARE @cbc_nomina INT = (SELECT TOP 1 cheq.cbc_id FROM dbo.bco_cuenta_bancaria_chequera cheq
						   INNER JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = cheq.bcb_id
						   WHERE cuba.bcb_numero_cuenta = '3-445-00981-2' AND cheq.cbc_estado = 'A');

IF @cia IS NULL
	PRINT 'Nómina semanal: no existe el empleado EMP005, se omite la sección.';
ELSE IF EXISTS (SELECT 1 FROM dbo.rrhhNomina WHERE TipoPeriodo = 'S' AND Estado <> 'N')
	PRINT 'Nómina semanal: ya existe, se omite la sección.';
ELSE
BEGIN
	DECLARE @descripcion VARCHAR(100) = CONCAT('Nómina semanal - Semana del ', FORMAT(@lunes, 'dd/MM'), ' al ', FORMAT(@domingo, 'dd/MM/yyyy'));
	EXEC dbo.paRrhhNominaCrear @CiaId = @cia, @Descripcion = @descripcion, @TipoPeriodo = 'S', @FechaDel = @lunes, @FechaAl = @domingo,
		@FechaPago = @domingo, @UsuId = @usu, @IdResultado = @nomina OUTPUT;
	EXEC dbo.paRrhhNominaCalcular @IdNomina = @nomina, @UsuId = @usu;
	EXEC dbo.paRrhhNominaAprobar @IdNomina = @nomina, @UsuId = @usu;
	EXEC dbo.paRrhhNominaEmitirCheques @IdNomina = @nomina, @CbcId = @cbc_nomina, @Fecha = @domingo, @UsuId = @usu, @IdNominaPago = @pago OUTPUT;
	PRINT CONCAT('Nómina semanal: ', @descripcion, ' aprobada y pagada con cheque.');
END
GO

------------------------------------------------------------
-- 5. Cheques libres
------------------------------------------------------------
DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
DECLARE @cbc_bi INT = (SELECT TOP 1 cheq.cbc_id FROM dbo.bco_cuenta_bancaria_chequera cheq
					   INNER JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = cheq.bcb_id
					   WHERE cuba.bcb_numero_cuenta = '301-0001122-3' AND cheq.cbc_estado = 'A' ORDER BY cheq.cbc_cheque_del);
DECLARE @varios INT = (SELECT bmp_id FROM dbo.bco_motivo_pago WHERE bmp_descripcion = 'Gastos varios'),
		@servicios INT = (SELECT bmp_id FROM dbo.bco_motivo_pago WHERE bmp_descripcion = 'Pago de servicios');
DECLARE @papeleria INT = (SELECT cta_id FROM dbo.cont_cuenta_contable WHERE cta_codigo = '5110010'),
		@mantenimiento INT = (SELECT cta_id FROM dbo.cont_cuenta_contable WHERE cta_codigo = '5110012');
DECLARE @ventas INT = (SELECT IdDepartamento FROM dbo.rrhhDepartamento WHERE Descripcion = 'Ventas'),
		@soporte INT = (SELECT IdDepartamento FROM dbo.rrhhDepartamento WHERE Descripcion = 'Soporte técnico');
DECLARE @fecha DATE = DATEADD(DAY, -3, CAST(GETDATE() AS DATE)), @bce INT;

IF EXISTS (SELECT 1 FROM dbo.bco_cheque_emitido_enc WHERE bce_tipo = 'L')
	PRINT 'Cheques libres: ya existen, se omite la sección.';
ELSE
BEGIN
	EXEC dbo.paBcoChequeEmitirLibre @CbcId = @cbc_bi, @Fecha = @fecha, @Beneficiario = 'Librería y Papelería El Estudiante',
		@BmpId = @varios, @CtaId = @papeleria, @IdDepartamento = @ventas, @Valor = 850.00,
		@Observaciones = 'Talonarios y papelería de sala de ventas', @UsuId = @usu, @BceId = @bce OUTPUT;
	EXEC dbo.paBcoChequeEmitirLibre @CbcId = @cbc_bi, @Fecha = @fecha, @Beneficiario = 'Servicios Técnicos Rivera',
		@BmpId = @servicios, @CtaId = @mantenimiento, @IdDepartamento = @soporte, @Valor = 1200.00,
		@Observaciones = 'Mantenimiento de equipo del área de soporte', @UsuId = @usu, @BceId = @bce OUTPUT;
	PRINT 'Cheques libres: dos emitidos con su centro de costo.';
END
GO
