------------------------------------------------------------------------------
-- 26_parametros_general_caja.sql
--
--   1. Parámetros de uso general en gen_compania (IVA, comisiones, tolerancia
--      del cierre de caja, periodicidad de nómina) y su mantenimiento.
--   2. Mantenimiento de entidades financieras y sus tipos (maestro-detalle).
--   3. Facturas por cliente y facturas + comisiones por vendedor.
--   4. Cierre de caja con cuadre obligatorio:
--        teórico = monto inicial + efectivo cobrado - depósitos
--                  + cheques + tarjetas + transferencias
--      El cierre se rechaza si |físico - teórico| supera la tolerancia de la
--      compañía (por defecto Q0.00, cuadre exacto).
--   5. Permisos nuevos: GENERAL_CONFIG_ADMIN y RRHH_ADMIN, asignados al rol
--      Administrador.
--
-- Requiere 25_rrhh.sql. Se puede volver a correr.
------------------------------------------------------------------------------

USE [erp_db];
GO

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Parámetros de la compañía
--
-- Criterio: un parámetro va en la compañía cuando es una política de todo
-- el negocio que hoy estaba fija en el código o que cambia por decisión
-- administrativa, no por operación diaria.
------------------------------------------------------------
IF COL_LENGTH('dbo.gen_compania', 'cia_porc_iva') IS NULL
	ALTER TABLE [dbo].[gen_compania] ADD [cia_porc_iva] NUMERIC(5, 2) NOT NULL
		CONSTRAINT [DF_gen_compania_porc_iva] DEFAULT (12);
GO
IF COL_LENGTH('dbo.gen_compania', 'cia_paga_comision') IS NULL
	ALTER TABLE [dbo].[gen_compania] ADD [cia_paga_comision] BIT NOT NULL
		CONSTRAINT [DF_gen_compania_paga_comision] DEFAULT (0);
GO
IF COL_LENGTH('dbo.gen_compania', 'cia_tolerancia_cierre_caja') IS NULL
	ALTER TABLE [dbo].[gen_compania] ADD [cia_tolerancia_cierre_caja] NUMERIC(12, 2) NOT NULL
		CONSTRAINT [DF_gen_compania_tolerancia_cierre_caja] DEFAULT (0);
GO
IF COL_LENGTH('dbo.gen_compania', 'cia_periodicidad_nomina') IS NULL
	ALTER TABLE [dbo].[gen_compania] ADD [cia_periodicidad_nomina] CHAR(1) NOT NULL
		CONSTRAINT [DF_gen_compania_periodicidad_nomina] DEFAULT ('M');
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_gen_compania_parametros')
	ALTER TABLE [dbo].[gen_compania] ADD CONSTRAINT [CK_gen_compania_parametros] CHECK (
		[cia_porc_iva] >= 0 AND [cia_porc_iva] < 100
		AND [cia_tolerancia_cierre_caja] >= 0
		AND [cia_periodicidad_nomina] IN ('M','Q'));
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaConsultar]
	@SoloActivas BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cia_id, cia_nombre_comercial, cia_direccion, cia_representante_legal, cia_DPI_representante_legal,
		   cia_fecha_nacimiento_representante_legal, cia_nit, cia_telefono, cia_email, cia_estado,
		   cia_porc_iva, cia_paga_comision, cia_tolerancia_cierre_caja, cia_periodicidad_nomina
	FROM dbo.gen_compania
	WHERE @SoloActivas = 0 OR cia_estado = 'A'
	ORDER BY cia_nombre_comercial;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaGuardar]
	@CiaId								INT = NULL,
	@NombreComercial					VARCHAR(128),
	@Direccion							VARCHAR(128) = NULL,
	@RepresentanteLegal					VARCHAR(128) = NULL,
	@DpiRepresentanteLegal				VARCHAR(32) = NULL,
	@FechaNacimientoRepresentanteLegal	DATE = NULL,
	@Nit								VARCHAR(32),
	@Telefono							VARCHAR(16) = NULL,
	@Email								VARCHAR(64) = NULL,
	@PorcIva							NUMERIC(5, 2),
	@PagaComision						BIT,
	@ToleranciaCierreCaja				NUMERIC(12, 2),
	@PeriodicidadNomina					CHAR(1),
	@UsuId								INT,
	@IdResultado						INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(LTRIM(RTRIM(@NombreComercial)), '') = '' OR ISNULL(LTRIM(RTRIM(@Nit)), '') = ''
		THROW 52200, 'El nombre comercial y el NIT son obligatorios.', 1;
	IF @PorcIva < 0 OR @PorcIva >= 100
		THROW 52201, 'El porcentaje de IVA debe estar entre 0 y 99.99.', 1;
	IF @ToleranciaCierreCaja < 0
		THROW 52202, 'La tolerancia del cierre de caja no puede ser negativa.', 1;
	IF @PeriodicidadNomina NOT IN ('M','Q')
		THROW 52203, 'La periodicidad de nómina debe ser mensual o quincenal.', 1;
	IF EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_nit = @Nit AND (@CiaId IS NULL OR cia_id <> @CiaId))
		THROW 52204, 'Ya existe una compañía con ese NIT.', 1;

	IF @CiaId IS NULL
	BEGIN
		INSERT INTO dbo.gen_compania (cia_nombre_comercial, cia_direccion, cia_representante_legal, cia_DPI_representante_legal,
			cia_fecha_nacimiento_representante_legal, cia_nit, cia_telefono, cia_email,
			cia_porc_iva, cia_paga_comision, cia_tolerancia_cierre_caja, cia_periodicidad_nomina, InsUsuario, InsFechaHora)
		VALUES (@NombreComercial, @Direccion, @RepresentanteLegal, @DpiRepresentanteLegal,
			@FechaNacimientoRepresentanteLegal, @Nit, @Telefono, @Email,
			@PorcIva, @PagaComision, @ToleranciaCierreCaja, @PeriodicidadNomina, @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.gen_compania
		   SET cia_nombre_comercial = @NombreComercial, cia_direccion = @Direccion, cia_representante_legal = @RepresentanteLegal,
			   cia_DPI_representante_legal = @DpiRepresentanteLegal, cia_fecha_nacimiento_representante_legal = @FechaNacimientoRepresentanteLegal,
			   cia_nit = @Nit, cia_telefono = @Telefono, cia_email = @Email,
			   cia_porc_iva = @PorcIva, cia_paga_comision = @PagaComision, cia_tolerancia_cierre_caja = @ToleranciaCierreCaja,
			   cia_periodicidad_nomina = @PeriodicidadNomina, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE cia_id = @CiaId;
		SET @IdResultado = @CiaId;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaCambiarEstado]
	@CiaId	INT,
	@Estado	CHAR(1),
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	IF @Estado = 'I' AND NOT EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_estado = 'A' AND cia_id <> @CiaId)
		THROW 52205, 'No se puede desactivar la única compañía activa.', 1;
	UPDATE dbo.gen_compania SET cia_estado = @Estado, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE cia_id = @CiaId;
END;
GO

-- Parámetros de la compañía a la que pertenece la sucursal de la sesión;
-- sin sucursal (p. ej. el administrador), los de la primera compañía activa.
CREATE OR ALTER PROCEDURE [dbo].[paCompaniaParametrosConsultar]
	@SucId INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT TOP 1 comp.cia_id, comp.cia_nombre_comercial, comp.cia_porc_iva, comp.cia_paga_comision,
		   comp.cia_tolerancia_cierre_caja, comp.cia_periodicidad_nomina
	FROM dbo.gen_compania comp
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.cia_id = comp.cia_id AND sucu.suc_id = @SucId
	WHERE comp.cia_estado = 'A'
	ORDER BY CASE WHEN sucu.suc_id IS NOT NULL THEN 0 ELSE 1 END, comp.cia_id;
END;
GO

------------------------------------------------------------
-- 2. Entidades financieras (tipo = maestro, entidad = detalle)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paEntidadFinancieraTipoConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT tipo.geft_id, tipo.geft_descripcion,
		   (SELECT COUNT(*) FROM dbo.gen_entidad_financiera enti WHERE enti.geft_id = tipo.geft_id) AS CantidadEntidades
	FROM dbo.gen_entidad_financiera_tipo tipo
	ORDER BY tipo.geft_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paEntidadFinancieraTipoGuardar]
	@GeftId			INT = NULL,
	@Descripcion	VARCHAR(50),
	@UsuId			INT,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(LTRIM(RTRIM(@Descripcion)), '') = ''
		THROW 52210, 'La descripción del tipo es obligatoria.', 1;
	IF EXISTS (SELECT 1 FROM dbo.gen_entidad_financiera_tipo WHERE geft_descripcion = @Descripcion AND (@GeftId IS NULL OR geft_id <> @GeftId))
		THROW 52211, 'Ya existe un tipo de entidad con esa descripción.', 1;

	IF @GeftId IS NULL
	BEGIN
		INSERT INTO dbo.gen_entidad_financiera_tipo (geft_descripcion, InsUsuario, InsFechaHora) VALUES (@Descripcion, @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.gen_entidad_financiera_tipo SET geft_descripcion = @Descripcion, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE geft_id = @GeftId;
		SET @IdResultado = @GeftId;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paEntidadFinancieraTipoEliminar]
	@GeftId INT
AS
BEGIN
	SET NOCOUNT ON;
	IF EXISTS (SELECT 1 FROM dbo.gen_entidad_financiera WHERE geft_id = @GeftId)
		THROW 52212, 'No se puede eliminar el tipo porque tiene entidades financieras; elimínelas o cámbielas de tipo primero.', 1;
	DELETE FROM dbo.gen_entidad_financiera_tipo WHERE geft_id = @GeftId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paEntidadFinancieraConsultar]
	@GeftId			INT = NULL,
	@SoloActivas	BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT enti.gef_id, enti.geft_id, tipo.geft_descripcion, enti.gef_codigo, enti.gef_descripcion, enti.gef_estado
	FROM dbo.gen_entidad_financiera enti
	INNER JOIN dbo.gen_entidad_financiera_tipo tipo ON tipo.geft_id = enti.geft_id
	WHERE (@GeftId IS NULL OR enti.geft_id = @GeftId)
	  AND (@SoloActivas = 0 OR enti.gef_estado = 'A')
	ORDER BY tipo.geft_descripcion, enti.gef_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paEntidadFinancieraGuardar]
	@GefId			INT = NULL,
	@GeftId			INT,
	@Codigo			VARCHAR(16),
	@Descripcion	VARCHAR(50),
	@Estado			CHAR(1) = 'A',
	@UsuId			INT,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(LTRIM(RTRIM(@Codigo)), '') = '' OR ISNULL(LTRIM(RTRIM(@Descripcion)), '') = ''
		THROW 52213, 'El código y la descripción de la entidad son obligatorios.', 1;
	IF EXISTS (SELECT 1 FROM dbo.gen_entidad_financiera WHERE gef_codigo = @Codigo AND (@GefId IS NULL OR gef_id <> @GefId))
		THROW 52214, 'Ya existe una entidad financiera con ese código.', 1;

	IF @GefId IS NULL
	BEGIN
		INSERT INTO dbo.gen_entidad_financiera (geft_id, gef_codigo, gef_descripcion, gef_estado, InsUsuario, InsFechaHora)
		VALUES (@GeftId, @Codigo, @Descripcion, @Estado, @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.gen_entidad_financiera
		   SET geft_id = @GeftId, gef_codigo = @Codigo, gef_descripcion = @Descripcion, gef_estado = @Estado,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE gef_id = @GefId;
		SET @IdResultado = @GefId;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paEntidadFinancieraEliminar]
	@GefId INT
AS
BEGIN
	SET NOCOUNT ON;
	IF EXISTS (SELECT 1 FROM dbo.pos_caja_deposito WHERE gef_id = @GefId)
	   OR EXISTS (SELECT 1 FROM dbo.inv_documento_enc WHERE gef_id = @GefId)
	   OR EXISTS (SELECT 1 FROM dbo.pos_pago_forma WHERE gef_id = @GefId)
		THROW 52215, 'La entidad ya tiene depósitos, pagos o documentos registrados; desactívela en lugar de eliminarla.', 1;
	DELETE FROM dbo.gen_entidad_financiera WHERE gef_id = @GefId;
END;
GO

------------------------------------------------------------
-- 3. Facturas por cliente y por vendedor (con comisión)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paClienteFacturasConsultar]
	@CliId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT enca.enc_id, enca.enc_fecha_docto, enca.enc_serie_docto, enca.enc_numero_docto, tipo.tdo_codigo,
		   enca.enc_monto_total, enca.enc_estado,
		   LTRIM(CONCAT(vend.pve_nombres, ' ', vend.pve_apellidos)) AS Vendedor,
		   usua.usu_usuario AS UsuarioGrabo,
		   CASE WHEN enca.enc_numero_cuotas > 1 OR enca.enc_fecha_primer_pago IS NOT NULL THEN 'Crédito' ELSE 'Contado' END AS Condicion,
		   ISNULL(cuotas.Saldo, 0) AS SaldoPendiente
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_naturaleza = '-'
	LEFT JOIN dbo.pos_vendedor vend ON vend.pve_id = enca.pve_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = ISNULL(enca.usu_id_creacion, enca.InsUsuario)
	OUTER APPLY (SELECT SUM(cuot.cpp_saldo_cuota) AS Saldo FROM dbo.pos_cliente_plan_pagos cuot
				 WHERE cuot.enc_id = enca.enc_id AND cuot.cpp_estado <> 'A') cuotas
	WHERE enca.cli_id = @CliId AND enca.enc_estado IN ('G','A')
	ORDER BY enca.enc_fecha_docto DESC, enca.enc_id DESC;
END;
GO

-- La comisión se calcula sobre la venta sin IVA (subtotal neto de
-- descuento) de las facturas grabadas del rango; las anuladas se listan
-- pero no comisionan. Si la compañía no paga comisión, la columna sale en 0.
CREATE OR ALTER PROCEDURE [dbo].[paVendedorFacturasConsultar]
	@PveId		INT,
	@FechaDel	DATE,
	@FechaAl	DATE,
	@SucId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @FechaAl < @FechaDel
		THROW 52220, 'La fecha final no puede ser anterior a la inicial.', 1;

	DECLARE @PagaComision BIT, @PorcComision NUMERIC(8, 2);
	SELECT TOP 1 @PagaComision = comp.cia_paga_comision
	FROM dbo.gen_compania comp
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.cia_id = comp.cia_id AND sucu.suc_id = @SucId
	WHERE comp.cia_estado = 'A'
	ORDER BY CASE WHEN sucu.suc_id IS NOT NULL THEN 0 ELSE 1 END, comp.cia_id;
	SELECT @PorcComision = pve_porc_comision FROM dbo.pos_vendedor WHERE pve_id = @PveId;
	SET @PagaComision = ISNULL(@PagaComision, 0);

	SELECT enca.enc_id, enca.enc_fecha_docto, enca.enc_serie_docto, enca.enc_numero_docto, tipo.tdo_codigo,
		   LTRIM(CONCAT(enca.enc_nombres_cliente, ' ', enca.enc_apellidos_cliente)) AS Cliente,
		   enca.enc_monto_total, neto.SubtotalSinIva, enca.enc_estado,
		   CASE WHEN @PagaComision = 1 AND enca.enc_estado = 'G'
				THEN ROUND(neto.SubtotalSinIva * ISNULL(@PorcComision, 0) / 100.0, 2) ELSE 0 END AS Comision
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_naturaleza = '-'
	CROSS APPLY (SELECT ISNULL(SUM(deta.det_sub_total - deta.det_valor_descuento), 0) AS SubtotalSinIva
				 FROM dbo.inv_documento_det deta WHERE deta.enc_id = enca.enc_id) neto
	WHERE enca.pve_id = @PveId
	  AND enca.enc_estado IN ('G','A')
	  AND enca.enc_fecha_docto BETWEEN @FechaDel AND @FechaAl
	ORDER BY enca.enc_fecha_docto DESC, enca.enc_id DESC;

	SELECT @PagaComision AS PagaComision, ISNULL(@PorcComision, 0) AS PorcComision;
END;
GO

------------------------------------------------------------
-- 4. Cuadre de caja
------------------------------------------------------------
-- Teórico por forma de pago; el efectivo ya incluye el fondo inicial y
-- descuenta lo que salió de la caja en depósitos al banco.
CREATE OR ALTER PROCEDURE [dbo].[paCorteCajaTeoricoConsultar]
	@pca_id INT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @monto_inicial NUMERIC(12, 2) = (SELECT pca_monto_inicial FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id);
	DECLARE @depositos NUMERIC(12, 2) = (SELECT ISNULL(SUM(pcd_valor_deposito), 0) FROM dbo.pos_caja_deposito WHERE pca_id = @pca_id);

	SELECT tipo.pft_id, tipo.pft_descripcion,
		   ISNULL(cobrado.monto, 0)
		   + CASE WHEN tipo.pft_descripcion = 'Efectivo' THEN ISNULL(@monto_inicial, 0) - @depositos ELSE 0 END AS monto_teorico
	FROM dbo.pos_pago_forma_tipo tipo
	LEFT JOIN (
		SELECT forma.pft_id, SUM(forma.ppf_monto) AS monto
		FROM dbo.pos_pago_forma forma
		INNER JOIN dbo.pos_pago_enc penc ON penc.ppe_id = forma.ppe_id
		WHERE penc.pca_id = @pca_id
		GROUP BY forma.pft_id
	) cobrado ON cobrado.pft_id = tipo.pft_id
	WHERE tipo.pft_estado = 'A'
	ORDER BY tipo.pft_descripcion;
END;
GO

-- Resumen del cuadre para mostrarlo antes de cerrar y para validar el cierre.
CREATE OR ALTER PROCEDURE [dbo].[paCorteCajaCuadreConsultar]
	@pca_id INT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @monto_inicial NUMERIC(12, 2), @tolerancia NUMERIC(12, 2);
	SELECT @monto_inicial = aper.pca_monto_inicial, @tolerancia = ISNULL(comp.cia_tolerancia_cierre_caja, 0)
	FROM dbo.pos_caja_apertura aper
	INNER JOIN dbo.pos_caja_receptora caja ON caja.pcr_id = aper.pcr_id
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = caja.suc_id
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	WHERE aper.pca_id = @pca_id;

	IF @monto_inicial IS NULL
		THROW 51702, 'La apertura de caja indicada no existe.', 1;

	DECLARE @efectivo NUMERIC(12, 2), @cheques NUMERIC(12, 2), @tarjetas NUMERIC(12, 2), @otras NUMERIC(12, 2);
	SELECT @efectivo = ISNULL(SUM(CASE WHEN tipo.pft_descripcion = 'Efectivo' THEN forma.ppf_monto ELSE 0 END), 0),
		   @cheques  = ISNULL(SUM(CASE WHEN tipo.pft_descripcion = 'Cheque' THEN forma.ppf_monto ELSE 0 END), 0),
		   @tarjetas = ISNULL(SUM(CASE WHEN tipo.pft_descripcion = 'Tarjeta' THEN forma.ppf_monto ELSE 0 END), 0),
		   @otras    = ISNULL(SUM(CASE WHEN tipo.pft_descripcion NOT IN ('Efectivo','Cheque','Tarjeta') THEN forma.ppf_monto ELSE 0 END), 0)
	FROM dbo.pos_pago_forma forma
	INNER JOIN dbo.pos_pago_enc penc ON penc.ppe_id = forma.ppe_id
	INNER JOIN dbo.pos_pago_forma_tipo tipo ON tipo.pft_id = forma.pft_id
	WHERE penc.pca_id = @pca_id;

	DECLARE @depositos NUMERIC(12, 2) = (SELECT ISNULL(SUM(pcd_valor_deposito), 0) FROM dbo.pos_caja_deposito WHERE pca_id = @pca_id);
	DECLARE @fisico_efectivo NUMERIC(12, 2) = (SELECT ISNULL(SUM(def_denominacion * def_cantidad), 0) FROM dbo.pos_caja_desglose_efectivo WHERE pca_id = @pca_id);
	DECLARE @fisico_otras NUMERIC(12, 2) = (SELECT ISNULL(SUM(pcf_monto_fisico), 0) FROM dbo.pos_caja_corte_forma WHERE pca_id = @pca_id);

	DECLARE @teorico NUMERIC(12, 2) = @monto_inicial + @efectivo - @depositos + @cheques + @tarjetas + @otras;
	DECLARE @fisico NUMERIC(12, 2) = @fisico_efectivo + @fisico_otras;

	SELECT @monto_inicial AS MontoInicial, @efectivo AS EfectivoCobrado, @depositos AS Depositos,
		   @cheques AS Cheques, @tarjetas AS Tarjetas, @otras AS OtrasFormas,
		   @teorico AS TeoricoTotal, @fisico_efectivo AS FisicoEfectivo, @fisico_otras AS FisicoOtrasFormas, @fisico AS FisicoTotal,
		   @fisico - @teorico AS Diferencia, @tolerancia AS Tolerancia,
		   CAST(CASE WHEN ABS(@fisico - @teorico) <= @tolerancia THEN 1 ELSE 0 END AS BIT) AS Cuadra;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_pos_caja_cerrar]
	@pca_id	INT,
	@usu_id	INT
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_apertura WHERE pca_id = @pca_id AND pca_estado = 'A')
		THROW 51702, 'La apertura de caja indicada no existe o ya está cerrada.', 1;

	DECLARE @cuadre TABLE (MontoInicial NUMERIC(12, 2), EfectivoCobrado NUMERIC(12, 2), Depositos NUMERIC(12, 2), Cheques NUMERIC(12, 2),
		Tarjetas NUMERIC(12, 2), OtrasFormas NUMERIC(12, 2), TeoricoTotal NUMERIC(12, 2), FisicoEfectivo NUMERIC(12, 2),
		FisicoOtrasFormas NUMERIC(12, 2), FisicoTotal NUMERIC(12, 2), Diferencia NUMERIC(12, 2), Tolerancia NUMERIC(12, 2), Cuadra BIT);
	INSERT INTO @cuadre EXEC dbo.paCorteCajaCuadreConsultar @pca_id = @pca_id;

	DECLARE @teorico NUMERIC(12, 2), @fisico NUMERIC(12, 2), @diferencia NUMERIC(12, 2), @tolerancia NUMERIC(12, 2), @cuadra BIT;
	SELECT @teorico = TeoricoTotal, @fisico = FisicoTotal, @diferencia = Diferencia, @tolerancia = Tolerancia, @cuadra = Cuadra FROM @cuadre;

	IF @cuadra = 0
	BEGIN
		DECLARE @mensaje NVARCHAR(400) = CONCAT(N'La caja no cuadra: teórico Q', FORMAT(@teorico, 'N2'), N', contado Q', FORMAT(@fisico, 'N2'),
			N', diferencia Q', FORMAT(@diferencia, 'N2'), N' (tolerancia permitida Q', FORMAT(@tolerancia, 'N2'),
			N'). Revise el conteo y los depósitos antes de cerrar.');
		THROW 51703, @mensaje, 1;
	END

	UPDATE dbo.pos_caja_apertura
	   SET pca_estado = 'C',
		   pca_fecha_corte = SYSDATETIME(),
		   pca_fecha_cierre = SYSDATETIME(),
		   usu_id_cierre = @usu_id,
		   pca_monto_teorico_total = @teorico,
		   pca_monto_fisico_total = @fisico,
		   pca_diferencia = @diferencia,
		   UpdUsuario = @usu_id, UpdFechaHora = SYSDATETIME()
	 WHERE pca_id = @pca_id;
END;
GO

------------------------------------------------------------
-- 5. Permisos nuevos para los módulos General y RRHH
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT v.modulo, v.codigo, v.descripcion
FROM (VALUES
	('GENERAL', 'GENERAL_CONFIG_ADMIN', 'Administrar compañía, parámetros y entidades financieras'),
	('RRHH',    'RRHH_ADMIN',           'Administrar recursos humanos y nómina')
) v(modulo, codigo, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso perm WHERE perm.per_codigo = v.codigo);

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id, InsFechaHora)
SELECT rol.rol_id, perm.per_id, SYSDATETIME()
FROM dbo.sec_rol rol
CROSS JOIN dbo.sec_permiso perm
WHERE rol.rol_codigo = 'ADMIN'
  AND perm.per_codigo IN ('GENERAL_CONFIG_ADMIN', 'RRHH_ADMIN')
  AND NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO
