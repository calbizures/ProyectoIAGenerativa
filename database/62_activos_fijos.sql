/*
================================================================================
 62_activos_fijos.sql
 Activos fijos: registro, compra, depreciación mensual y bajas.

   - Categorías con el porcentaje anual máximo de depreciación de la Ley de
     Actualización Tributaria (Decreto 10-2012, artículo 28): edificios 5 %;
     maquinaria, vehículos y mobiliario y equipo 20 %; equipo de computación
     33.33 %; herramientas 25 %; demás bienes 10 %; terrenos no se deprecian.
     Cada categoría lleva su cuenta de activo, de depreciación acumulada y de
     gasto. Se crean las cuentas de depreciación acumulada que faltaban.
   - Activo AF-000001: descripción, categoría, sucursal, centro de costo,
     responsable, serie/marca, fecha de adquisición, costo, valor residual y
     porcentaje (no mayor al de la categoría). Se da de alta:
       * desde Compras: una línea marcada como activo fijo crea un activo por
         unidad y su póliza va a la cuenta del activo (no a inventario/gasto);
       * manualmente: un bien que ya estaba en libros (con su depreciación
         acumulada anterior) o con póliza contra la cuenta que se elija.
   - Depreciación mensual (línea recta): una corrida por mes con su póliza
     DEPRECIACION (Debe gasto por centro de costo / Haber depreciación
     acumulada). Empieza el mes siguiente a la adquisición y para al llegar al
     valor residual. La última corrida se puede anular.
   - Baja (desuso, robo, destrucción) o venta: póliza ACTIVO_FIJO que saca el
     costo y la depreciación acumulada; la diferencia va a pérdida o a otros
     ingresos; la venta lleva su IVA débito.
   - Al anular una compra se anulan sus activos (si no se han depreciado).

 Errores nuevos: 55201 a 55260.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Cuentas: depreciación acumulada, pérdida en baja
------------------------------------------------------------
-- Cuentas de detalle nuevas bajo su grupo (solo con la nomenclatura base).
INSERT INTO dbo.cont_cuenta_contable (cta_codigo, cta_nombre, cta_tipo, cta_naturaleza, cta_acepta_movimiento, cta_id_padre, cta_nivel, InsFechaHora)
SELECT v.codigo, v.nombre, v.tipo, v.naturaleza, 1, padr.cta_id, 4, SYSDATETIME()
FROM (VALUES
	('1210002', '121', 'DEPRECIACION ACUMULADA VEHICULOS', 'A', 'H'),
	('1240003', '124', 'DEPRECIACION ACUMULADA EDIFICIOS', 'A', 'H'),
	('1250002', '125', 'DEPRECIACION ACUMULADA EQUIPO DE COMPUTACION', 'A', 'H'),
	('5110075', '511', 'PERDIDA EN BAJA DE ACTIVOS FIJOS', 'G', 'D')) v (codigo, padre, nombre, tipo, naturaleza)
INNER JOIN dbo.cont_cuenta_contable padr ON padr.cta_codigo = v.padre AND padr.cta_acepta_movimiento = 0
WHERE NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable cuen WHERE cuen.cta_codigo = v.codigo);
-- La depreciación acumulada de mobiliario ya existía con el nombre del activo.
UPDATE dbo.cont_cuenta_contable SET cta_nombre = 'DEPRECIACION ACUMULADA MOBILIARIO Y EQUIPO', UpdFechaHora = SYSDATETIME()
 WHERE cta_codigo = '1222001' AND cta_nombre = 'MOBILIARIO Y EQUIPO' AND cta_naturaleza = 'H';
UPDATE dbo.cont_cuenta_contable SET cta_nombre = 'DEPRECIACION ACUMULADA PLANTA TELEFONICA', UpdFechaHora = SYSDATETIME()
 WHERE cta_codigo = '1222002' AND cta_nombre = 'PLANTA TELEFONICA' AND cta_naturaleza = 'H';
UPDATE dbo.cont_cuenta_contable SET cta_nombre = 'DEPRECIACION ACUMULADA ROTULOS', UpdFechaHora = SYSDATETIME()
 WHERE cta_codigo = '1222003' AND cta_nombre = 'ROTULOS' AND cta_naturaleza = 'H';
UPDATE dbo.cont_cuenta_contable SET cta_nombre = 'MOBILIARIO Y EQUIPO', UpdFechaHora = SYSDATETIME()
 WHERE cta_codigo = '1221001' AND cta_nombre = '1221001 - MOBILIARIO Y EQUIPO';
GO

INSERT INTO dbo.cont_cuenta_parametro (ccp_codigo, ccp_descripcion, ccp_naturaleza, cta_id, InsFechaHora)
SELECT v.codigo, v.descripcion, v.naturaleza, (SELECT cta_id FROM dbo.cont_cuenta_contable WHERE cta_codigo = v.cuenta), SYSDATETIME()
FROM (VALUES
	('ACTIVO_FIJO_PERDIDA', 'Activos fijos: pérdida en baja o venta', 'D', '5110075'),
	('ACTIVO_FIJO_GANANCIA', 'Activos fijos: ganancia en venta (otros ingresos)', 'H', '4110026')) v (codigo, descripcion, naturaleza, cuenta)
WHERE NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_parametro parm WHERE parm.ccp_codigo = v.codigo);
GO

------------------------------------------------------------
-- 2. Tablas
------------------------------------------------------------
IF OBJECT_ID('dbo.afi_categoria', 'U') IS NULL
CREATE TABLE dbo.afi_categoria (
	[afc_id]				INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_afi_categoria] PRIMARY KEY,
	[afc_codigo]			VARCHAR(10)		NOT NULL CONSTRAINT [UQ_afi_categoria_codigo] UNIQUE,
	[afc_nombre]			VARCHAR(100)	NOT NULL,
	[afc_porcentaje]		NUMERIC(5, 2)	NOT NULL CONSTRAINT [CK_afi_categoria_porcentaje] CHECK ([afc_porcentaje] BETWEEN 0 AND 100),
	[cta_id_activo]			INT				NOT NULL CONSTRAINT [FK_afi_categoria_activo] REFERENCES dbo.cont_cuenta_contable ([cta_id]),
	[cta_id_depreciacion]	INT				NULL CONSTRAINT [FK_afi_categoria_depreciacion] REFERENCES dbo.cont_cuenta_contable ([cta_id]),
	[cta_id_gasto]			INT				NULL CONSTRAINT [FK_afi_categoria_gasto] REFERENCES dbo.cont_cuenta_contable ([cta_id]),
	[afc_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_afi_categoria_estado] DEFAULT ('A') CONSTRAINT [CK_afi_categoria_estado] CHECK ([afc_estado] IN ('A', 'I')),
	[InsUsuario]			INT				NULL CONSTRAINT [FK_afi_categoria_ins] REFERENCES dbo.gen_usuario ([usu_id]),
	[InsFechaHora]			DATETIME2(0)	NOT NULL CONSTRAINT [DF_afi_categoria_ins] DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL CONSTRAINT [FK_afi_categoria_upd] REFERENCES dbo.gen_usuario ([usu_id]),
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [CK_afi_categoria_cuentas] CHECK ([afc_porcentaje] = 0 OR ([cta_id_depreciacion] IS NOT NULL AND [cta_id_gasto] IS NOT NULL))
);
GO

-- Estado: A en uso, B dado de baja, V vendido, N anulado (su compra se anuló).
IF OBJECT_ID('dbo.afi_activo', 'U') IS NULL
CREATE TABLE dbo.afi_activo (
	[afa_id]					INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_afi_activo] PRIMARY KEY,
	[afa_codigo]				VARCHAR(12)		NOT NULL CONSTRAINT [UQ_afi_activo_codigo] UNIQUE,
	[afa_descripcion]			VARCHAR(200)	NOT NULL,
	[afc_id]					INT				NOT NULL CONSTRAINT [FK_afi_activo_categoria] REFERENCES dbo.afi_categoria ([afc_id]),
	[suc_id]					INT				NOT NULL CONSTRAINT [FK_afi_activo_sucursal] REFERENCES dbo.gen_sucursal ([suc_id]),
	[IdDepartamento]			INT				NULL CONSTRAINT [FK_afi_activo_departamento] REFERENCES dbo.rrhhDepartamento ([IdDepartamento]),
	[afa_responsable]			VARCHAR(150)	NULL,
	[afa_serie]					VARCHAR(100)	NULL,
	[afa_ubicacion]				VARCHAR(150)	NULL,
	[afa_fecha_adquisicion]		DATE			NOT NULL,
	[afa_costo]					NUMERIC(14, 2)	NOT NULL CONSTRAINT [CK_afi_activo_costo] CHECK ([afa_costo] > 0),
	[afa_valor_residual]		NUMERIC(14, 2)	NOT NULL CONSTRAINT [DF_afi_activo_residual] DEFAULT (0),
	[afa_porcentaje]			NUMERIC(5, 2)	NOT NULL,
	[afa_depreciacion_inicial]	NUMERIC(14, 2)	NOT NULL CONSTRAINT [DF_afi_activo_dep_inicial] DEFAULT (0),
	[enc_id]					INT				NULL CONSTRAINT [FK_afi_activo_compra] REFERENCES dbo.inv_documento_enc ([enc_id]),
	[det_id]					INT				NULL CONSTRAINT [FK_afi_activo_compra_det] REFERENCES dbo.inv_documento_det ([det_id]),
	[asi_id_alta]				INT				NULL CONSTRAINT [FK_afi_activo_asiento_alta] REFERENCES dbo.cont_asiento_enc ([asi_id]),
	[afa_documento]				VARCHAR(100)	NULL,
	[afa_estado]				CHAR(1)			NOT NULL CONSTRAINT [DF_afi_activo_estado] DEFAULT ('A') CONSTRAINT [CK_afi_activo_estado] CHECK ([afa_estado] IN ('A', 'B', 'V', 'N')),
	[afa_fecha_baja]			DATE			NULL,
	[afa_motivo_baja]			VARCHAR(250)	NULL,
	[afa_precio_venta]			NUMERIC(14, 2)	NULL,
	[asi_id_baja]				INT				NULL CONSTRAINT [FK_afi_activo_asiento_baja] REFERENCES dbo.cont_asiento_enc ([asi_id]),
	[InsUsuario]				INT				NULL CONSTRAINT [FK_afi_activo_ins] REFERENCES dbo.gen_usuario ([usu_id]),
	[InsFechaHora]				DATETIME2(0)	NOT NULL CONSTRAINT [DF_afi_activo_ins] DEFAULT (SYSDATETIME()),
	[UpdUsuario]				INT				NULL CONSTRAINT [FK_afi_activo_upd] REFERENCES dbo.gen_usuario ([usu_id]),
	[UpdFechaHora]				DATETIME2(0)	NULL,
	CONSTRAINT [CK_afi_activo_residual] CHECK ([afa_valor_residual] >= 0 AND [afa_valor_residual] < [afa_costo]),
	CONSTRAINT [CK_afi_activo_dep_inicial] CHECK ([afa_depreciacion_inicial] >= 0 AND [afa_depreciacion_inicial] <= [afa_costo] - [afa_valor_residual])
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_afi_activo_compra')
	CREATE INDEX [IX_afi_activo_compra] ON dbo.afi_activo ([enc_id]) WHERE [enc_id] IS NOT NULL;
GO

IF OBJECT_ID('dbo.afi_depreciacion_corrida', 'U') IS NULL
CREATE TABLE dbo.afi_depreciacion_corrida (
	[adc_id]				INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_afi_depreciacion_corrida] PRIMARY KEY,
	[adc_anio]				INT				NOT NULL,
	[adc_mes]				INT				NOT NULL CONSTRAINT [CK_afi_depreciacion_corrida_mes] CHECK ([adc_mes] BETWEEN 1 AND 12),
	[adc_total]				NUMERIC(14, 2)	NOT NULL,
	[adc_activos]			INT				NOT NULL,
	[asi_id]				INT				NULL CONSTRAINT [FK_afi_depreciacion_corrida_asiento] REFERENCES dbo.cont_asiento_enc ([asi_id]),
	[adc_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_afi_depreciacion_corrida_estado] DEFAULT ('V') CONSTRAINT [CK_afi_depreciacion_corrida_estado] CHECK ([adc_estado] IN ('V', 'A')),
	[InsUsuario]			INT				NULL CONSTRAINT [FK_afi_depreciacion_corrida_ins] REFERENCES dbo.gen_usuario ([usu_id]),
	[InsFechaHora]			DATETIME2(0)	NOT NULL CONSTRAINT [DF_afi_depreciacion_corrida_ins] DEFAULT (SYSDATETIME()),
	[UpdUsuario]			INT				NULL CONSTRAINT [FK_afi_depreciacion_corrida_upd] REFERENCES dbo.gen_usuario ([usu_id]),
	[UpdFechaHora]			DATETIME2(0)	NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_afi_depreciacion_corrida_mes')
	CREATE UNIQUE INDEX [UX_afi_depreciacion_corrida_mes] ON dbo.afi_depreciacion_corrida ([adc_anio], [adc_mes]) WHERE [adc_estado] = 'V';
GO

IF OBJECT_ID('dbo.afi_depreciacion', 'U') IS NULL
CREATE TABLE dbo.afi_depreciacion (
	[afd_id]				INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_afi_depreciacion] PRIMARY KEY,
	[adc_id]				INT				NOT NULL CONSTRAINT [FK_afi_depreciacion_corrida] REFERENCES dbo.afi_depreciacion_corrida ([adc_id]),
	[afa_id]				INT				NOT NULL CONSTRAINT [FK_afi_depreciacion_activo] REFERENCES dbo.afi_activo ([afa_id]),
	[afd_monto]				NUMERIC(14, 2)	NOT NULL,
	CONSTRAINT [UQ_afi_depreciacion] UNIQUE ([adc_id], [afa_id])
);
GO

-- Línea de compra que es activo fijo (su categoría).
IF COL_LENGTH('dbo.inv_documento_det', 'afc_id') IS NULL
	ALTER TABLE dbo.inv_documento_det ADD [afc_id] INT NULL CONSTRAINT [FK_inv_documento_det_afi_categoria] REFERENCES dbo.afi_categoria ([afc_id]);
GO

IF TYPE_ID('dbo.compra_activo_type') IS NULL
	CREATE TYPE dbo.compra_activo_type AS TABLE (
		[det_item]			INT		NOT NULL PRIMARY KEY,
		[afc_id]			INT		NOT NULL,
		[IdDepartamento]	INT		NULL
	);
GO

------------------------------------------------------------
-- 3. Categorías (porcentajes máximos del artículo 28, Decreto 10-2012)
------------------------------------------------------------
INSERT INTO dbo.afi_categoria (afc_codigo, afc_nombre, afc_porcentaje, cta_id_activo, cta_id_depreciacion, cta_id_gasto, InsFechaHora)
SELECT v.codigo, v.nombre, v.porcentaje, acti.cta_id, depr.cta_id, IIF(v.porcentaje = 0, NULL, gast.cta_id), SYSDATETIME()
FROM (VALUES
	('EDIF', 'Edificios, construcciones e instalaciones', 5.00, '1240001', '1240003'),
	('MAQ', 'Maquinaria y equipo', 20.00, '1221001', '1222001'),
	('VEH', 'Vehículos', 20.00, '1210001', '1210002'),
	('MOB', 'Mobiliario y equipo de oficina', 20.00, '1221001', '1222001'),
	('COMP', 'Equipo de computación', 33.33, '1250001', '1250002'),
	('HERR', 'Herramientas', 25.00, '1221001', '1222001'),
	('OTRO', 'Demás bienes muebles', 10.00, '1221001', '1222001'),
	('TERR', 'Terrenos (no se deprecian)', 0.00, '1230001', NULL)) v (codigo, nombre, porcentaje, activo, depreciacion)
INNER JOIN dbo.cont_cuenta_contable acti ON acti.cta_codigo = v.activo
LEFT JOIN dbo.cont_cuenta_contable depr ON depr.cta_codigo = v.depreciacion
CROSS JOIN (SELECT TOP 1 cta_id FROM dbo.cont_cuenta_contable WHERE cta_tipo = 'G' AND cta_acepta_movimiento = 1 AND cta_nombre LIKE 'DEPRECIACION%' ORDER BY cta_codigo) gast
WHERE (v.depreciacion IS NULL OR depr.cta_id IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM dbo.afi_categoria cate WHERE cate.afc_codigo = v.codigo);
GO

------------------------------------------------------------
-- 4. Permisos
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT 'CONTABILIDAD', 'ACTIVOS_FIJOS', 'Activos fijos: registro, depreciación mensual, bajas y ventas'
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_codigo = 'ACTIVOS_FIJOS');
INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT rol.rol_id, perm.per_id
FROM dbo.sec_rol rol CROSS JOIN dbo.sec_permiso perm
WHERE rol.rol_codigo IN ('ADMIN', 'CONTADOR', 'CONTADOR_GENERAL') AND perm.per_codigo = 'ACTIVOS_FIJOS'
  AND NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO

------------------------------------------------------------
-- 5. Consultas
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paActivoFijoCategoriaConsultar]
	@SoloActivas	BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cate.afc_id AS AfcId, cate.afc_codigo AS Codigo, cate.afc_nombre AS Nombre, cate.afc_porcentaje AS Porcentaje,
		   cate.cta_id_activo AS CtaIdActivo, acti.cta_codigo + ' ' + acti.cta_nombre AS CuentaActivo,
		   cate.cta_id_depreciacion AS CtaIdDepreciacion, depr.cta_codigo + ' ' + depr.cta_nombre AS CuentaDepreciacion,
		   cate.cta_id_gasto AS CtaIdGasto, gast.cta_codigo + ' ' + gast.cta_nombre AS CuentaGasto, cate.afc_estado AS Estado,
		   (SELECT COUNT(*) FROM dbo.afi_activo acfi WHERE acfi.afc_id = cate.afc_id AND acfi.afa_estado = 'A') AS Activos
	FROM dbo.afi_categoria cate
	INNER JOIN dbo.cont_cuenta_contable acti ON acti.cta_id = cate.cta_id_activo
	LEFT JOIN dbo.cont_cuenta_contable depr ON depr.cta_id = cate.cta_id_depreciacion
	LEFT JOIN dbo.cont_cuenta_contable gast ON gast.cta_id = cate.cta_id_gasto
	WHERE @SoloActivas = 0 OR cate.afc_estado = 'A'
	ORDER BY cate.afc_nombre;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paActivoFijoCategoriaGuardar]
	@AfcId				INT = NULL OUTPUT,
	@Codigo				VARCHAR(10),
	@Nombre				VARCHAR(100),
	@Porcentaje			NUMERIC(5, 2),
	@CtaIdActivo		INT,
	@CtaIdDepreciacion	INT = NULL,
	@CtaIdGasto			INT = NULL,
	@Estado				CHAR(1) = 'A',
	@UsuId				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @Codigo = NULLIF(UPPER(LTRIM(RTRIM(@Codigo))), '');
	SET @Nombre = NULLIF(LTRIM(RTRIM(@Nombre)), '');
	IF @Codigo IS NULL OR @Nombre IS NULL
		THROW 55201, 'Indique el código y el nombre de la categoría.', 1;
	IF @Porcentaje IS NULL OR @Porcentaje < 0 OR @Porcentaje > 100
		THROW 55202, 'El porcentaje anual de depreciación va de 0 a 100.', 1;
	IF @Porcentaje > 0 AND (@CtaIdDepreciacion IS NULL OR @CtaIdGasto IS NULL)
		THROW 55203, 'Una categoría que se deprecia necesita su cuenta de depreciación acumulada y su cuenta de gasto.', 1;
	IF EXISTS (SELECT 1 FROM (VALUES (@CtaIdActivo), (@CtaIdDepreciacion), (@CtaIdGasto)) v (cta_id)
			   LEFT JOIN dbo.cont_cuenta_contable cuen ON cuen.cta_id = v.cta_id
			   WHERE v.cta_id IS NOT NULL AND (cuen.cta_id IS NULL OR cuen.cta_acepta_movimiento = 0 OR cuen.cta_estado <> 'A'))
		THROW 55204, 'Las cuentas de la categoría deben ser de detalle y estar activas.', 1;
	IF EXISTS (SELECT 1 FROM dbo.afi_categoria WHERE afc_codigo = @Codigo AND afc_id <> ISNULL(@AfcId, 0))
		THROW 55205, 'Ya existe una categoría con ese código.', 1;
	IF @AfcId IS NULL
	BEGIN
		INSERT INTO dbo.afi_categoria (afc_codigo, afc_nombre, afc_porcentaje, cta_id_activo, cta_id_depreciacion, cta_id_gasto, afc_estado, InsUsuario)
		VALUES (@Codigo, @Nombre, @Porcentaje, @CtaIdActivo, IIF(@Porcentaje = 0, NULL, @CtaIdDepreciacion), IIF(@Porcentaje = 0, NULL, @CtaIdGasto), ISNULL(@Estado, 'A'), @UsuId);
		SET @AfcId = SCOPE_IDENTITY();
	END
	ELSE
		UPDATE dbo.afi_categoria
		   SET afc_codigo = @Codigo, afc_nombre = @Nombre, afc_porcentaje = @Porcentaje, cta_id_activo = @CtaIdActivo,
			   cta_id_depreciacion = IIF(@Porcentaje = 0, NULL, @CtaIdDepreciacion), cta_id_gasto = IIF(@Porcentaje = 0, NULL, @CtaIdGasto),
			   afc_estado = ISNULL(@Estado, 'A'), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE afc_id = @AfcId;
END;
GO

-- Depreciación acumulada de cada activo (inicial + corridas vigentes) y la
-- cuota mensual que le toca.
CREATE OR ALTER FUNCTION [dbo].[fnActivoFijoSaldo] ()
RETURNS TABLE
AS
RETURN
	SELECT acfi.afa_id,
		   acfi.afa_depreciacion_inicial + ISNULL(depr.Monto, 0) AS Acumulada,
		   depr.UltimoMes,
		   CAST(ROUND((acfi.afa_costo - acfi.afa_valor_residual) * acfi.afa_porcentaje / 1200.0, 2) AS NUMERIC(14, 2)) AS Cuota
	FROM dbo.afi_activo acfi
	OUTER APPLY (SELECT SUM(deta.afd_monto) AS Monto, MAX(corr.adc_anio * 100 + corr.adc_mes) AS UltimoMes
				 FROM dbo.afi_depreciacion deta
				 INNER JOIN dbo.afi_depreciacion_corrida corr ON corr.adc_id = deta.adc_id AND corr.adc_estado = 'V'
				 WHERE deta.afa_id = acfi.afa_id) depr;
GO

CREATE OR ALTER PROCEDURE [dbo].[paActivoFijoConsultar]
	@AfaId	INT = NULL,
	@AfcId	INT = NULL,
	@SucId	INT = NULL,
	@Estado	CHAR(1) = NULL,
	@Texto	VARCHAR(100) = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @Texto = NULLIF(LTRIM(RTRIM(@Texto)), '');
	SELECT acfi.afa_id AS AfaId, acfi.afa_codigo AS Codigo, acfi.afa_descripcion AS Descripcion, acfi.afc_id AS AfcId, cate.afc_nombre AS Categoria,
		   acfi.suc_id AS SucId, sucu.suc_descripcion AS Sucursal, acfi.IdDepartamento, depa.Descripcion AS Departamento,
		   acfi.afa_responsable AS Responsable, acfi.afa_serie AS Serie, acfi.afa_ubicacion AS Ubicacion,
		   acfi.afa_fecha_adquisicion AS FechaAdquisicion, acfi.afa_costo AS Costo, acfi.afa_valor_residual AS ValorResidual,
		   acfi.afa_porcentaje AS Porcentaje, acfi.afa_depreciacion_inicial AS DepreciacionInicial,
		   sald.Acumulada, acfi.afa_costo - sald.Acumulada AS ValorLibros,
		   IIF(acfi.afa_estado = 'A' AND acfi.afa_porcentaje > 0, sald.Cuota, 0) AS CuotaMensual,
		   sald.UltimoMes, acfi.enc_id AS EncId,
		   CASE WHEN docu.enc_id IS NOT NULL THEN CONCAT('Compra ', ISNULL(docu.enc_serie_docto + '-', ''), docu.enc_numero_docto, ' · ', prov.prv_nombre_comercial) ELSE acfi.afa_documento END AS Documento,
		   acfi.asi_id_alta AS AsiIdAlta, acfi.afa_estado AS Estado, acfi.afa_fecha_baja AS FechaBaja, acfi.afa_motivo_baja AS MotivoBaja,
		   acfi.afa_precio_venta AS PrecioVenta, acfi.asi_id_baja AS AsiIdBaja
	FROM dbo.afi_activo acfi
	INNER JOIN dbo.afi_categoria cate ON cate.afc_id = acfi.afc_id
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = acfi.suc_id
	INNER JOIN dbo.fnActivoFijoSaldo() sald ON sald.afa_id = acfi.afa_id
	LEFT JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = acfi.IdDepartamento
	LEFT JOIN dbo.inv_documento_enc docu ON docu.enc_id = acfi.enc_id
	LEFT JOIN dbo.inv_proveedor prov ON prov.prv_id = docu.prv_id
	WHERE (@AfaId IS NULL OR acfi.afa_id = @AfaId)
	  AND (@AfcId IS NULL OR acfi.afc_id = @AfcId)
	  AND (@SucId IS NULL OR acfi.suc_id = @SucId)
	  AND (@Estado IS NULL OR acfi.afa_estado = @Estado)
	  AND (@Texto IS NULL OR acfi.afa_descripcion LIKE '%' + @Texto + '%' OR acfi.afa_codigo LIKE '%' + @Texto + '%'
		   OR acfi.afa_serie LIKE '%' + @Texto + '%' OR acfi.afa_responsable LIKE '%' + @Texto + '%')
	ORDER BY acfi.afa_codigo;
END;
GO

-- Historial de depreciación de un activo.
CREATE OR ALTER PROCEDURE [dbo].[paActivoFijoDepreciacionHistorial]
	@AfaId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT corr.adc_anio AS Anio, corr.adc_mes AS Mes, deta.afd_monto AS Monto, corr.asi_id AS AsiId,
		   acfi.afa_depreciacion_inicial + SUM(deta.afd_monto) OVER (ORDER BY corr.adc_anio, corr.adc_mes ROWS UNBOUNDED PRECEDING) AS Acumulada
	FROM dbo.afi_depreciacion deta
	INNER JOIN dbo.afi_depreciacion_corrida corr ON corr.adc_id = deta.adc_id AND corr.adc_estado = 'V'
	INNER JOIN dbo.afi_activo acfi ON acfi.afa_id = deta.afa_id
	WHERE deta.afa_id = @AfaId
	ORDER BY corr.adc_anio, corr.adc_mes;
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

------------------------------------------------------------
-- 7. Compras: líneas de activo fijo
------------------------------------------------------------
-- Crea un activo por unidad de cada línea de la compra marcada como activo
-- fijo; el costo es el de la línea sin IVA (la última unidad absorbe el
-- redondeo).
CREATE OR ALTER PROCEDURE [dbo].[paActivoFijoCrearDesdeCompra]
	@EncId			INT,
	@Departamentos	dbo.compra_activo_type READONLY,
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @fecha DATE, @suc_id INT, @documento VARCHAR(100);
	SELECT @fecha = docu.enc_fecha_docto, @suc_id = ISNULL(bode.suc_id, 1)
	FROM dbo.inv_documento_enc docu
	OUTER APPLY (SELECT TOP 1 bod.suc_id FROM dbo.inv_documento_det deta INNER JOIN dbo.inv_bodega bod ON bod.bod_id = deta.bod_id WHERE deta.enc_id = docu.enc_id) bode
	WHERE docu.enc_id = @EncId;

	DECLARE @lineas TABLE (det_id INT, afc_id INT, cantidad INT, neto NUMERIC(14, 2), descripcion VARCHAR(200), porcentaje NUMERIC(5, 2), IdDepartamento INT);
	INSERT INTO @lineas
	SELECT deta.det_id, deta.afc_id, deta.det_cantidad, deta.det_sub_total - deta.det_valor_descuento, LEFT(deta.det_descripcion, 200),
		   cate.afc_porcentaje, depa.IdDepartamento
	FROM dbo.inv_documento_det deta
	INNER JOIN dbo.afi_categoria cate ON cate.afc_id = deta.afc_id
	LEFT JOIN @Departamentos depa ON depa.det_item = deta.det_item
	WHERE deta.enc_id = @EncId AND deta.afc_id IS NOT NULL;

	DECLARE @det_id INT, @afc_id INT, @cantidad INT, @neto NUMERIC(14, 2), @descripcion VARCHAR(200), @porcentaje NUMERIC(5, 2), @depto INT,
			@unidad INT, @costo NUMERIC(14, 2), @numero INT;
	DECLARE lineas CURSOR LOCAL FAST_FORWARD FOR SELECT det_id, afc_id, cantidad, neto, descripcion, porcentaje, IdDepartamento FROM @lineas ORDER BY det_id;
	OPEN lineas;
	FETCH NEXT FROM lineas INTO @det_id, @afc_id, @cantidad, @neto, @descripcion, @porcentaje, @depto;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @unidad = 1;
		WHILE @unidad <= @cantidad
		BEGIN
			SET @costo = IIF(@unidad < @cantidad, ROUND(@neto / @cantidad, 2), @neto - ROUND(@neto / @cantidad, 2) * (@cantidad - 1));
			SELECT @numero = ISNULL(MAX(CAST(SUBSTRING(afa_codigo, 4, 9) AS INT)), 0) + 1 FROM dbo.afi_activo WITH (UPDLOCK, HOLDLOCK);
			INSERT INTO dbo.afi_activo (afa_codigo, afa_descripcion, afc_id, suc_id, IdDepartamento, afa_fecha_adquisicion, afa_costo,
										afa_porcentaje, enc_id, det_id, InsUsuario)
			VALUES (CONCAT('AF-', RIGHT(CONCAT('00000', @numero), 6)), IIF(@cantidad > 1, LEFT(CONCAT(@descripcion, ' (', @unidad, ' de ', @cantidad, ')'), 200), @descripcion),
					@afc_id, @suc_id, @depto, @fecha, @costo, @porcentaje, @EncId, @det_id, @UsuId);
			SET @unidad += 1;
		END
		FETCH NEXT FROM lineas INTO @det_id, @afc_id, @cantidad, @neto, @descripcion, @porcentaje, @depto;
	END
	CLOSE lineas; DEALLOCATE lineas;
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
-- 8. Depreciación mensual
------------------------------------------------------------
-- Vista previa: lo que depreciaría cada activo en @Anio/@Mes.
CREATE OR ALTER FUNCTION [dbo].[fnActivoFijoCuotaMes] (@Anio INT, @Mes INT)
RETURNS TABLE
AS
RETURN
	SELECT acfi.afa_id, acfi.afa_codigo, acfi.afa_descripcion, acfi.IdDepartamento, cate.cta_id_gasto, cate.cta_id_depreciacion, cate.afc_nombre,
		   CAST(IIF(sald.Cuota < acfi.afa_costo - acfi.afa_valor_residual - sald.Acumulada, sald.Cuota,
					acfi.afa_costo - acfi.afa_valor_residual - sald.Acumulada) AS NUMERIC(14, 2)) AS Monto
	FROM dbo.afi_activo acfi
	INNER JOIN dbo.afi_categoria cate ON cate.afc_id = acfi.afc_id
	INNER JOIN dbo.fnActivoFijoSaldo() sald ON sald.afa_id = acfi.afa_id
	WHERE acfi.afa_estado = 'A' AND acfi.afa_porcentaje > 0 AND cate.cta_id_depreciacion IS NOT NULL
	  -- Empieza el mes siguiente al de la adquisición.
	  AND DATEFROMPARTS(@Anio, @Mes, 1) > EOMONTH(acfi.afa_fecha_adquisicion)
	  AND acfi.afa_costo - acfi.afa_valor_residual - sald.Acumulada > 0
	  AND ISNULL(sald.UltimoMes, 0) < @Anio * 100 + @Mes;
GO

CREATE OR ALTER PROCEDURE [dbo].[paActivoFijoDepreciacionPrevia]
	@Anio	INT,
	@Mes	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cuot.afa_id AS AfaId, cuot.afa_codigo AS Codigo, cuot.afa_descripcion AS Descripcion, cuot.afc_nombre AS Categoria,
		   depa.Descripcion AS Departamento, cuot.Monto
	FROM dbo.fnActivoFijoCuotaMes(@Anio, @Mes) cuot
	LEFT JOIN dbo.rrhhDepartamento depa ON depa.IdDepartamento = cuot.IdDepartamento
	WHERE cuot.Monto > 0
	ORDER BY cuot.afa_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paActivoFijoDepreciacionCorridaConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT corr.adc_id AS AdcId, corr.adc_anio AS Anio, corr.adc_mes AS Mes, corr.adc_total AS Total, corr.adc_activos AS Activos,
		   corr.asi_id AS AsiId, corr.adc_estado AS Estado, usua.usu_codigo AS Usuario, corr.InsFechaHora AS Grabada
	FROM dbo.afi_depreciacion_corrida corr
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = corr.InsUsuario
	ORDER BY corr.adc_anio DESC, corr.adc_mes DESC, corr.adc_id DESC;
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

-- Solo la última corrida vigente, y si ninguno de sus activos se dio de baja después.
CREATE OR ALTER PROCEDURE [dbo].[paActivoFijoDepreciacionAnular]
	@AdcId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	DECLARE @anio INT, @mes INT, @asi_id INT;
	SELECT @anio = adc_anio, @mes = adc_mes, @asi_id = asi_id FROM dbo.afi_depreciacion_corrida WHERE adc_id = @AdcId AND adc_estado = 'V';
	IF @anio IS NULL
		THROW 55230, 'La corrida de depreciación no existe o ya está anulada.', 1;
	IF EXISTS (SELECT 1 FROM dbo.afi_depreciacion_corrida WHERE adc_estado = 'V' AND adc_anio * 100 + adc_mes > @anio * 100 + @mes)
		THROW 55231, 'Solo se anula la última depreciación grabada.', 1;
	IF EXISTS (SELECT 1 FROM dbo.afi_depreciacion deta INNER JOIN dbo.afi_activo acfi ON acfi.afa_id = deta.afa_id
			   WHERE deta.adc_id = @AdcId AND acfi.afa_estado IN ('B', 'V'))
		THROW 55232, 'Algún activo de esta depreciación ya se dio de baja o se vendió.', 1;
	BEGIN TRY
		BEGIN TRANSACTION;
			UPDATE dbo.afi_depreciacion_corrida SET adc_estado = 'A', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE adc_id = @AdcId;
			UPDATE dbo.cont_asiento_enc SET asi_estado = 'N', asi_motivo_anulacion = 'Depreciación anulada', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
			 WHERE asi_id = @asi_id AND asi_estado = 'A';
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

------------------------------------------------------------
-- 10. Anulación de la compra
------------------------------------------------------------
-- Al anular una compra (enc_estado → A) sus activos quedan anulados; no se
-- permite si alguno ya tiene depreciación o se dio de baja.
CREATE OR ALTER TRIGGER [dbo].[trg_inv_documento_enc_activos_fijos]
ON dbo.inv_documento_enc
AFTER UPDATE
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT UPDATE(enc_estado) RETURN;
	IF NOT EXISTS (SELECT 1 FROM inserted inse INNER JOIN deleted dele ON dele.enc_id = inse.enc_id
				   INNER JOIN dbo.afi_activo acfi ON acfi.enc_id = inse.enc_id
				   WHERE inse.enc_estado = 'A' AND dele.enc_estado <> 'A')
		RETURN;
	IF EXISTS (SELECT 1 FROM inserted inse INNER JOIN dbo.afi_activo acfi ON acfi.enc_id = inse.enc_id
			   WHERE inse.enc_estado = 'A' AND (acfi.afa_estado IN ('B', 'V') OR EXISTS (SELECT 1 FROM dbo.afi_depreciacion deta
						INNER JOIN dbo.afi_depreciacion_corrida corr ON corr.adc_id = deta.adc_id AND corr.adc_estado = 'V' WHERE deta.afa_id = acfi.afa_id)))
		THROW 55242, 'La compra tiene activos fijos ya depreciados, dados de baja o vendidos; no se puede anular.', 1;
	UPDATE acfi SET afa_estado = 'N', afa_motivo_baja = 'Compra anulada', UpdFechaHora = SYSDATETIME()
	FROM dbo.afi_activo acfi INNER JOIN inserted inse ON inse.enc_id = acfi.enc_id
	WHERE inse.enc_estado = 'A' AND acfi.afa_estado = 'A';
END;
GO

------------------------------------------------------------
-- 11. Datos de demostración: activos ya en libros (saldos iniciales) y
-- una compra de computadoras; depreciación de septiembre.
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.afi_activo)
   AND EXISTS (SELECT 1 FROM dbo.cont_asiento_enc WHERE asi_descripcion = 'Pago a proveedor con cheque 1009')
   AND EXISTS (SELECT 1 FROM dbo.afi_categoria WHERE afc_codigo = 'COMP')
   AND NOT EXISTS (SELECT 1 FROM dbo.cont_periodo_contable WHERE pdo_anio = 2026 AND pdo_mes IN (8, 9) AND pdo_estado = 'C')
BEGIN
	DECLARE @afa_id INT, @adc_id INT, @enc_id INT, @prv_id INT = (SELECT MIN(prv_id) FROM dbo.inv_proveedor WHERE prv_estado = 'A'),
			@tdo_gasto INT = (SELECT TOP 1 tdo_id FROM dbo.inv_documento_tipo WHERE tdo_codigo = 'GAST'),
			@bod_id INT = (SELECT MIN(bod_id) FROM dbo.inv_bodega WHERE suc_id = 1),
			@cta_capital INT = (SELECT cta_id FROM dbo.cont_cuenta_contable WHERE cta_codigo = '3410001'),
			@comp INT = (SELECT afc_id FROM dbo.afi_categoria WHERE afc_codigo = 'COMP'),
			@mob INT = (SELECT afc_id FROM dbo.afi_categoria WHERE afc_codigo = 'MOB'),
			@veh INT = (SELECT afc_id FROM dbo.afi_categoria WHERE afc_codigo = 'VEH'),
			@depto INT = (SELECT MIN(IdDepartamento) FROM dbo.rrhhDepartamento WHERE Estado = 'A');

	-- Aporte de un vehículo y mobiliario (póliza contra capital).
	SET @afa_id = NULL;
	EXEC dbo.paActivoFijoGuardar @AfaId = @afa_id OUTPUT, @Descripcion = 'Pick-up Toyota Hilux 2024 placa P-123ABC', @AfcId = @veh, @SucId = 1,
		@IdDepartamento = @depto, @Responsable = 'Jefe de bodega', @Serie = 'Motor 2GD-445566', @FechaAdquisicion = '20260520', @Costo = 285000,
		@ValorResidual = 0, @Documento = 'Aporte de socios', @CtaIdContrapartida = @cta_capital, @UsuId = 1;
	SET @afa_id = NULL;
	EXEC dbo.paActivoFijoGuardar @AfaId = @afa_id OUTPUT, @Descripcion = 'Escritorios y sillas de oficina (lote)', @AfcId = @mob, @SucId = 1,
		@IdDepartamento = @depto, @FechaAdquisicion = '20260515', @Costo = 18500, @Documento = 'Aporte de socios',
		@CtaIdContrapartida = @cta_capital, @UsuId = 1;

	-- Compra de dos computadoras (líneas de activo fijo).
	IF @prv_id IS NOT NULL AND @tdo_gasto IS NOT NULL AND @bod_id IS NOT NULL
	BEGIN
		DECLARE @detalle dbo.compra_det_type, @activos dbo.compra_activo_type;
		INSERT INTO @detalle (det_item, det_bien_o_servicio, det_cantidad, det_descripcion, det_precio_unitario, det_valor_descuento, det_sub_total, det_porc_iva, bod_id, pro_id)
		VALUES (1, 'B', 2, 'Computadora Dell Optiplex i7 16 GB', 7500, 0, 15000, 12, @bod_id, NULL);
		INSERT INTO @activos (det_item, afc_id, IdDepartamento) VALUES (1, @comp, @depto);
		EXEC dbo.paCompraDocumentoCrear @EncFechaDocto = '20260810', @EncSerieDocto = 'FC', @EncNumeroDocto = '880123', @PrvId = @prv_id,
			@TdoId = @tdo_gasto, @EncNumeroCuotas = 1, @EncFechaPrimerPago = '20260910', @UsuId = 1, @Detalle = @detalle,
			@EncId = @enc_id OUTPUT, @Activos = @activos;
	END

	EXEC dbo.paActivoFijoDepreciar @Anio = 2026, @Mes = 6, @UsuId = 1, @AdcId = @adc_id OUTPUT;
	EXEC dbo.paActivoFijoDepreciar @Anio = 2026, @Mes = 7, @UsuId = 1, @AdcId = @adc_id OUTPUT;
	EXEC dbo.paActivoFijoDepreciar @Anio = 2026, @Mes = 8, @UsuId = 1, @AdcId = @adc_id OUTPUT;
	EXEC dbo.paActivoFijoDepreciar @Anio = 2026, @Mes = 9, @UsuId = 1, @AdcId = @adc_id OUTPUT;
END
GO

PRINT '62_activos_fijos.sql aplicado.';
GO
