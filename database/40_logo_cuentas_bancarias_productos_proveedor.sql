------------------------------------------------------------------------------
-- 40_logo_cuentas_bancarias_productos_proveedor.sql
--
-- Fase C del segundo bloque de requerimientos:
--
--   1. Nomenclatura sin datos confidenciales. Las cuentas de bancos que se
--      migraron del sistema anterior traían números de cuenta y nombres
--      reales; se reemplazan por datos sintéticos. Solo se cambian si todavía
--      tienen el nombre original (se compara su huella SHA-256, así el texto
--      original no queda escrito en este script); un nombre que ya se cambió
--      desde Contabilidad > Nomenclatura se respeta.
--
--   2. Cuentas bancarias con dos cuentas contables:
--          Cargos  (cta_id_cargo): depósitos a la cuenta  -> Debe
--          Abonos  (cta_id):       cheques y pagos        -> Haber
--      El depósito de caja ahora se hace a una cuenta bancaria
--      (pos_caja_deposito.bcb_id) y su partida carga la cuenta de cargos de
--      esa cuenta; los cheques ya abonaban cta_id (fnBcoCuentaContable).
--
--   3. Logotipo de la compañía en gen_compania (imagen PNG, JPG, GIF o WEBP
--      de hasta 1 MB). Se muestra en el menú, el inicio de sesión, los
--      documentos impresos y los libros de Excel.
--
--   4. Productos por proveedor (inv_producto_proveedor): mantenimiento,
--      proveedor preferido (uno por producto), código del producto en el
--      catálogo del proveedor y último costo de compra. Al grabar una compra
--      se actualiza el último costo y, si se pide, se relacionan con el
--      proveedor los productos que todavía no lo estaban.
--
-- El vendedor por defecto al facturar (usuario -> empleado -> vendedor) ya lo
-- resuelve paVendedorConsultarPorUsuario (25); este script no lo cambia.
--
-- Errores 53601-53611. Requiere 36 y 38. Se puede volver a correr; si se
-- vuelve a correr 23, 29 o 36, correr este después.
------------------------------------------------------------------------------

USE [erp_db];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Nomenclatura sin datos confidenciales
------------------------------------------------------------
DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
DECLARE @nombres TABLE (Codigo VARCHAR(20) PRIMARY KEY, Huella VARBINARY(32) NOT NULL, Nombre VARCHAR(128) NOT NULL);
INSERT INTO @nombres (Codigo, Huella, Nombre) VALUES
	('1120014', 0x0E14CE9A2F4DA11D42946E413B01AD908DD3E1CF732BD0705BEFB4EE5AE8485C, 'BANCO INDUSTRIAL MONETARIA 301-0001122-3'),
	('1120017', 0x892959A70D141CA81125765BC041B7833D34A7B0E9BD6BF51FEF1C41910B5D57, 'BANRURAL MONETARIA NÓMINA 3-445-00981-2'),
	('1120018', 0xF66B5121029C814C4D00710767AAF2B312A66B43C7187A6A826427CEB1AA9040, 'BANCO INDUSTRIAL AHORRO 301-0004455-6'),
	('1120019', 0x56EDE76C49CFD95DA9A50E4F7B02006756EDB199DE84ABBA87ACFB258BC6AF66, 'BANCO INDUSTRIAL DÓLARES 301-0007788-9'),
	('1120020', 0xBCC39604B02675F12D39EAF702F11A027048E979FBB56E633D5D688B7EC4A4FC, 'DIFERENCIAL CAMBIARIO BANCO INDUSTRIAL DÓLARES'),
	('1120021', 0xEB8A3EFB8F162096DDF7E8B98D4EC284F0A4A2597A5BFD068725F9BF7D86C2DC, 'BANCO G&T CONTINENTAL MONETARIA 045-000321-7'),
	('1120022', 0xFFE0190D55D5CDD66213912C10E6EB4DF80E3B69B27F47CCAAE533F5A6518FEC, 'BANCO AGROMERCANTIL MONETARIA 30-4012345-6'),
	('2160003', 0x93D0F848ECC6EBCDCFA6C377B04450159AE234D114245E3F1475D0165471E330, 'PRÉSTAMOS DE EMPRESAS RELACIONADAS'),
	('5110058', 0x73AD6F0E0F1E05B5C0A13D7BCD16E7D0FE0CEE2AC28F8802F1B4943BE00823C2, 'GASTOS DE VEHÍCULOS');

UPDATE cuen
   SET cta_nombre = nomb.Nombre, UpdUsuario = @usu, UpdFechaHora = SYSDATETIME()
FROM dbo.cont_cuenta_contable cuen
INNER JOIN @nombres nomb ON nomb.Codigo = cuen.cta_codigo AND nomb.Huella = HASHBYTES('SHA2_256', cuen.cta_nombre);
PRINT CONCAT('Nomenclatura: ', @@ROWCOUNT, ' cuenta(s) con datos confidenciales renombradas.');
GO

------------------------------------------------------------
-- 2. Cuentas bancarias: cuenta de cargos y cuenta de abonos
------------------------------------------------------------
IF COL_LENGTH('dbo.bco_cuenta_bancaria', 'cta_id_cargo') IS NULL
	ALTER TABLE dbo.bco_cuenta_bancaria ADD [cta_id_cargo] INT NULL;	-- cuenta contable que se carga con los depósitos
GO
IF OBJECT_ID('dbo.FK_bco_cuenta_bancaria_cuenta_cargo', 'F') IS NULL
	ALTER TABLE dbo.bco_cuenta_bancaria ADD CONSTRAINT [FK_bco_cuenta_bancaria_cuenta_cargo]
		FOREIGN KEY ([cta_id_cargo]) REFERENCES dbo.cont_cuenta_contable ([cta_id]);
GO
-- Las cuentas que ya existían cargan los depósitos a la misma cuenta contable
-- con la que abonan los cheques.
UPDATE dbo.bco_cuenta_bancaria SET cta_id_cargo = cta_id WHERE cta_id_cargo IS NULL AND cta_id IS NOT NULL;
GO

IF COL_LENGTH('dbo.pos_caja_deposito', 'bcb_id') IS NULL
	ALTER TABLE dbo.pos_caja_deposito ADD [bcb_id] INT NULL;	-- cuenta bancaria a la que se depositó
GO
IF OBJECT_ID('dbo.FK_pos_caja_deposito_cuenta_bancaria', 'F') IS NULL
	ALTER TABLE dbo.pos_caja_deposito ADD CONSTRAINT [FK_pos_caja_deposito_cuenta_bancaria]
		FOREIGN KEY ([bcb_id]) REFERENCES dbo.bco_cuenta_bancaria ([bcb_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_pos_caja_deposito_bcb_id' AND object_id = OBJECT_ID('dbo.pos_caja_deposito'))
	CREATE INDEX [IX_pos_caja_deposito_bcb_id] ON dbo.pos_caja_deposito ([bcb_id]);
GO
-- Los depósitos anteriores quedan en la cuenta bancaria de su banco cuando
-- ese banco tiene una sola cuenta (sus partidas no cambian).
UPDATE depo SET bcb_id = unic.bcb_id
FROM dbo.pos_caja_deposito depo
CROSS APPLY (SELECT MIN(cuba.bcb_id) AS bcb_id FROM dbo.bco_cuenta_bancaria cuba WHERE cuba.gef_id = depo.gef_id HAVING COUNT(*) = 1) unic
WHERE depo.bcb_id IS NULL;
GO

-- Cuenta contable que se carga al depositar en una cuenta bancaria; sin
-- cuenta bancaria o sin cuenta de cargos, la del concepto DEPOSITO_BANCOS.
CREATE OR ALTER FUNCTION [dbo].[fnBcoCuentaContableCargo] (@BcbId INT)
RETURNS INT
AS
BEGIN
	RETURN COALESCE((SELECT cta_id_cargo FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId),
					(SELECT cta_id FROM dbo.cont_cuenta_parametro WHERE ccp_codigo = 'DEPOSITO_BANCOS'));
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBcoCuentaBancariaConsultar]
	@SoloActivas BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cuba.bcb_id AS BcbId, cuba.bcb_numero_cuenta AS NumeroCuenta, cuba.bcb_descripcion AS Descripcion,
		   cuba.gef_id AS GefId, enti.gef_descripcion AS Banco, cuba.bcb_tipo AS Tipo,
		   cuba.cta_id AS CtaId, abon.cta_codigo AS CuentaCodigo, abon.cta_nombre AS CuentaNombre,
		   cuba.cta_id_cargo AS CtaIdCargo, carg.cta_codigo AS CuentaCargoCodigo, carg.cta_nombre AS CuentaCargoNombre,
		   cuba.bcb_estado AS Estado,
		   (SELECT COUNT(*) FROM dbo.bco_cuenta_bancaria_chequera cheq WHERE cheq.bcb_id = cuba.bcb_id AND cheq.cbc_estado = 'A') AS ChequerasActivas
	FROM dbo.bco_cuenta_bancaria cuba
	INNER JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuba.gef_id
	LEFT JOIN dbo.cont_cuenta_contable abon ON abon.cta_id = cuba.cta_id
	LEFT JOIN dbo.cont_cuenta_contable carg ON carg.cta_id = cuba.cta_id_cargo
	WHERE @SoloActivas = 0 OR cuba.bcb_estado = 'A'
	ORDER BY enti.gef_descripcion, cuba.bcb_numero_cuenta;
END;
GO

-- @CtaId es la cuenta de abonos (cheques y pagos) y @CtaIdCargo la de
-- cargos (depósitos). Si solo se indica una, la otra queda igual.
CREATE OR ALTER PROCEDURE [dbo].[paBcoCuentaBancariaGuardar]
	@BcbId			INT = NULL,
	@NumeroCuenta	VARCHAR(16),
	@Descripcion	VARCHAR(64) = NULL,
	@GefId			INT,
	@Tipo			CHAR(1),
	@CtaId			INT = NULL,
	@CtaIdCargo		INT = NULL,
	@Estado			CHAR(1) = 'A',
	@UsuId			INT,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET @NumeroCuenta = LTRIM(RTRIM(ISNULL(@NumeroCuenta, '')));
	SET @CtaId = COALESCE(@CtaId, @CtaIdCargo);
	SET @CtaIdCargo = COALESCE(@CtaIdCargo, @CtaId);
	IF @NumeroCuenta = ''
		THROW 53401, 'Ingrese el número de cuenta.', 1;
	IF EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_numero_cuenta = @NumeroCuenta AND bcb_id <> ISNULL(@BcbId, 0))
		THROW 53402, 'Ya existe una cuenta bancaria con ese número.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_entidad_financiera enti
				   INNER JOIN dbo.gen_entidad_financiera_tipo tipo ON tipo.geft_id = enti.geft_id
				   WHERE enti.gef_id = @GefId AND tipo.geft_descripcion = 'Banco')
		THROW 53403, 'Elija un banco (entidad financiera de tipo Banco).', 1;
	IF @Tipo NOT IN ('M','A')
		THROW 53405, 'El tipo de cuenta debe ser monetaria o de ahorro.', 1;
	IF EXISTS (SELECT 1 FROM (VALUES (@CtaId), (@CtaIdCargo)) v(cta_id)
			   WHERE v.cta_id IS NOT NULL
				 AND NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable cuen WHERE cuen.cta_id = v.cta_id AND cuen.cta_estado = 'A' AND cuen.cta_acepta_movimiento = 1))
		THROW 53404, 'La cuenta contable debe existir, estar activa y aceptar movimientos.', 1;

	IF @BcbId IS NULL
	BEGIN
		INSERT INTO dbo.bco_cuenta_bancaria (bcb_numero_cuenta, bcb_descripcion, gef_id, bcb_tipo, cta_id, cta_id_cargo, bcb_estado, InsUsuario, InsFechaHora)
		VALUES (@NumeroCuenta, NULLIF(LTRIM(RTRIM(@Descripcion)), ''), @GefId, @Tipo, @CtaId, @CtaIdCargo, ISNULL(@Estado, 'A'), @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId)
			THROW 53406, 'La cuenta bancaria indicada no existe.', 1;
		UPDATE dbo.bco_cuenta_bancaria
		   SET bcb_numero_cuenta = @NumeroCuenta, bcb_descripcion = NULLIF(LTRIM(RTRIM(@Descripcion)), ''), gef_id = @GefId,
			   bcb_tipo = @Tipo, cta_id = @CtaId, cta_id_cargo = @CtaIdCargo, bcb_estado = ISNULL(@Estado, bcb_estado),
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE bcb_id = @BcbId;
		SET @IdResultado = @BcbId;
	END
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

CREATE OR ALTER PROCEDURE [dbo].[paCajaDepositoConsultar]
	@pca_id INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	SELECT depo.pcd_id, depo.pcd_fecha_deposito, depo.pcd_valor_deposito, depo.pcd_numero_boleta,
		   depo.pcd_observaciones, depo.pca_id, depo.gef_id, enti.gef_codigo, enti.gef_descripcion,
		   depo.bcb_id, cuba.bcb_numero_cuenta
	FROM dbo.pos_caja_deposito depo
	LEFT JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = depo.gef_id
	LEFT JOIN dbo.bco_cuenta_bancaria cuba ON cuba.bcb_id = depo.bcb_id
	WHERE (@pca_id IS NULL OR depo.pca_id = @pca_id)
	ORDER BY depo.pcd_fecha_deposito DESC;
END;
GO

------------------------------------------------------------
-- 3. Logotipo de la compañía
------------------------------------------------------------
IF COL_LENGTH('dbo.gen_compania', 'cia_logo') IS NULL
	ALTER TABLE dbo.gen_compania ADD
		[cia_logo]				VARBINARY(MAX)	NULL,	-- imagen del logotipo
		[cia_logo_tipo]			VARCHAR(32)		NULL,	-- image/png, image/jpeg, image/gif o image/webp
		[cia_logo_actualizado]	DATETIME2(0)	NULL;	-- versión de la imagen (evita que el navegador muestre la anterior)
GO
IF OBJECT_ID('dbo.CK_gen_compania_logo_tipo', 'C') IS NULL
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [CK_gen_compania_logo_tipo]
		CHECK ([cia_logo_tipo] IS NULL OR [cia_logo_tipo] IN ('image/png','image/jpeg','image/gif','image/webp'));
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaConsultar]
	@SoloActivas BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cia_id, cia_nombre_comercial, cia_direccion, cia_representante_legal, cia_DPI_representante_legal,
		   cia_fecha_nacimiento_representante_legal, cia_nit, cia_telefono, cia_email, cia_estado,
		   cia_porc_iva, cia_paga_comision, cia_tolerancia_cierre_caja, cia_periodicidad_nomina,
		   CAST(CASE WHEN cia_logo IS NULL THEN 0 ELSE 1 END AS BIT) AS cia_tiene_logo, cia_logo_actualizado
	FROM dbo.gen_compania
	WHERE @SoloActivas = 0 OR cia_estado = 'A'
	ORDER BY cia_nombre_comercial;
END;
GO

-- Graba o quita (@Logo NULL) el logotipo de una compañía.
CREATE OR ALTER PROCEDURE [dbo].[paCompaniaLogoGuardar]
	@CiaId	INT,
	@Logo	VARBINARY(MAX) = NULL,
	@Tipo	VARCHAR(32) = NULL,
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_id = @CiaId)
		THROW 53604, 'La compañía indicada no existe.', 1;
	IF @Logo IS NOT NULL AND ISNULL(@Tipo, '') NOT IN ('image/png','image/jpeg','image/gif','image/webp')
		THROW 53605, 'El logotipo debe ser una imagen PNG, JPG, GIF o WEBP.', 1;
	IF DATALENGTH(@Logo) > 1048576
		THROW 53606, 'El logotipo no puede pesar más de 1 MB.', 1;

	UPDATE dbo.gen_compania
	   SET cia_logo = @Logo, cia_logo_tipo = CASE WHEN @Logo IS NULL THEN NULL ELSE @Tipo END,
		   cia_logo_actualizado = CASE WHEN @Logo IS NULL THEN NULL ELSE SYSDATETIME() END,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cia_id = @CiaId;
END;
GO

-- Logotipo de una compañía; sin @CiaId, el de la compañía de la sucursal y
-- si no, el de la primera compañía activa. Con @SoloVersion = 1 no devuelve
-- la imagen (para saber si hay logo y armar su dirección).
CREATE OR ALTER PROCEDURE [dbo].[paCompaniaLogoConsultar]
	@CiaId			INT = NULL,
	@SucId			INT = NULL,
	@SoloVersion	BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT TOP 1 comp.cia_id AS CiaId, comp.cia_nombre_comercial AS Nombre,
		   CASE WHEN @SoloVersion = 1 THEN NULL ELSE comp.cia_logo END AS Logo,
		   comp.cia_logo_tipo AS Tipo, comp.cia_logo_actualizado AS Actualizado
	FROM dbo.gen_compania comp
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.cia_id = comp.cia_id AND sucu.suc_id = @SucId
	WHERE (@CiaId IS NULL AND comp.cia_estado = 'A') OR comp.cia_id = @CiaId
	ORDER BY CASE WHEN sucu.suc_id IS NOT NULL THEN 0 ELSE 1 END, comp.cia_id;
END;
GO

------------------------------------------------------------
-- 4. Productos por proveedor
------------------------------------------------------------
IF COL_LENGTH('dbo.inv_producto_proveedor', 'ppp_codigo_proveedor') IS NULL
	ALTER TABLE dbo.inv_producto_proveedor ADD
		[ppp_codigo_proveedor]		VARCHAR(64)		NULL,	-- código del producto en el catálogo del proveedor
		[ppp_ultimo_costo]			NUMERIC(14, 5)	NULL,	-- costo unitario sin IVA de la última compra
		[ppp_fecha_ultima_compra]	DATE			NULL,
		[enc_id_ultima_compra]		INT				NULL;
GO
IF OBJECT_ID('dbo.FK_inv_producto_proveedor_ultima_compra', 'F') IS NULL
	ALTER TABLE dbo.inv_producto_proveedor ADD CONSTRAINT [FK_inv_producto_proveedor_ultima_compra]
		FOREIGN KEY ([enc_id_ultima_compra]) REFERENCES dbo.inv_documento_enc ([enc_id]);
GO

-- Un solo proveedor preferido por producto: si había varios, queda el más antiguo.
UPDATE rela SET ppp_preferencia = 'N'
FROM dbo.inv_producto_proveedor rela
WHERE rela.ppp_preferencia = 'S'
  AND EXISTS (SELECT 1 FROM dbo.inv_producto_proveedor otra
			  WHERE otra.pro_id = rela.pro_id AND otra.ppp_preferencia = 'S' AND otra.ppp_id < rela.ppp_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_inv_producto_proveedor_preferido' AND object_id = OBJECT_ID('dbo.inv_producto_proveedor'))
	CREATE UNIQUE INDEX [UX_inv_producto_proveedor_preferido] ON dbo.inv_producto_proveedor ([pro_id]) WHERE [ppp_preferencia] = 'S';
GO

-- Relaciones de un proveedor (sus productos) o de un producto (sus proveedores).
CREATE OR ALTER PROCEDURE [dbo].[paProductoProveedorConsultar]
	@PrvId	INT = NULL,
	@ProId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT rela.ppp_id AS PppId, rela.prv_id AS PrvId, prov.prv_codigo AS PrvCodigo, prov.prv_nombre_comercial AS Proveedor,
		   rela.pro_id AS ProId, prod.pro_codigo AS ProCodigo, prod.pro_descripcion AS ProDescripcion, prod.pro_tipo_item AS ProTipoItem,
		   unid.ume_codigo AS UmeCodigo, prod.pro_costo_unitario AS ProCostoUnitario, prod.pro_estado AS ProEstado,
		   CAST(CASE WHEN rela.ppp_preferencia = 'S' THEN 1 ELSE 0 END AS BIT) AS Preferido,
		   rela.ppp_codigo_proveedor AS CodigoProveedor, rela.ppp_ultimo_costo AS UltimoCosto,
		   rela.ppp_fecha_ultima_compra AS FechaUltimaCompra
	FROM dbo.inv_producto_proveedor rela
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = rela.prv_id
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = rela.pro_id
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = prod.ume_id
	WHERE (@PrvId IS NULL OR rela.prv_id = @PrvId)
	  AND (@ProId IS NULL OR rela.pro_id = @ProId)
	ORDER BY CASE WHEN @PrvId IS NULL THEN prov.prv_nombre_comercial ELSE prod.pro_descripcion END;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoProveedorGuardar]
	@PppId				INT = NULL,
	@PrvId				INT,
	@ProId				INT,
	@Preferido			BIT = 0,
	@CodigoProveedor	VARCHAR(64) = NULL,
	@UsuId				INT,
	@IdResultado		INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_proveedor WHERE prv_id = @PrvId AND prv_estado = 'A')
		THROW 53607, 'El proveedor no existe o está inactivo.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_id = @ProId AND pro_estado = 'A')
		THROW 53608, 'El producto no existe o está inactivo.', 1;
	IF EXISTS (SELECT 1 FROM dbo.inv_producto_proveedor WHERE prv_id = @PrvId AND pro_id = @ProId AND ppp_id <> ISNULL(@PppId, 0))
		THROW 53609, 'Ese producto ya está relacionado con el proveedor.', 1;
	IF @PppId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.inv_producto_proveedor WHERE ppp_id = @PppId)
		THROW 53610, 'La relación producto-proveedor indicada no existe.', 1;

	SET @CodigoProveedor = NULLIF(LTRIM(RTRIM(@CodigoProveedor)), '');

	BEGIN TRANSACTION;
	-- El preferido anterior del producto pasa a alterno.
	IF @Preferido = 1
		UPDATE dbo.inv_producto_proveedor SET ppp_preferencia = 'N', UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE pro_id = @ProId AND ppp_preferencia = 'S' AND ppp_id <> ISNULL(@PppId, 0);

	IF @PppId IS NULL
	BEGIN
		INSERT INTO dbo.inv_producto_proveedor (prv_id, pro_id, ppp_preferencia, ppp_codigo_proveedor, InsUsuario, InsFechaHora)
		VALUES (@PrvId, @ProId, CASE WHEN @Preferido = 1 THEN 'S' ELSE 'N' END, @CodigoProveedor, @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.inv_producto_proveedor
		   SET prv_id = @PrvId, pro_id = @ProId, ppp_preferencia = CASE WHEN @Preferido = 1 THEN 'S' ELSE 'N' END,
			   ppp_codigo_proveedor = @CodigoProveedor, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE ppp_id = @PppId;
		SET @IdResultado = @PppId;
	END
	COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoProveedorEliminar]
	@PppId	INT,
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto_proveedor WHERE ppp_id = @PppId)
		THROW 53610, 'La relación producto-proveedor indicada no existe.', 1;
	DELETE FROM dbo.inv_producto_proveedor WHERE ppp_id = @PppId;
END;
GO

-- Después de grabar una compra: actualiza el último costo (sin IVA, neto de
-- descuento) de sus productos con el proveedor y, con @Relacionar = 1,
-- relaciona los que todavía no lo estaban (preferido si el producto no
-- tenía ninguno). Devuelve cuántas relaciones nuevas se crearon.
CREATE OR ALTER PROCEDURE [dbo].[paProductoProveedorRegistrarCompra]
	@EncId		INT,
	@Relacionar	BIT = 0,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @prv_id INT, @fecha DATE;
	SELECT @prv_id = enca.prv_id, @fecha = enca.enc_fecha_docto
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_naturaleza = '+' AND tipo.tdo_es_nota = 0 AND tipo.tdo_es_interno = 0
	WHERE enca.enc_id = @EncId AND enca.enc_estado = 'G';
	IF @prv_id IS NULL
		THROW 53611, 'La compra no existe, está anulada o no tiene proveedor.', 1;

	DECLARE @costos TABLE (pro_id INT PRIMARY KEY, costo NUMERIC(14, 5));
	INSERT INTO @costos (pro_id, costo)
	SELECT deta.pro_id, SUM(deta.det_sub_total - ISNULL(deta.det_valor_descuento, 0)) / NULLIF(SUM(deta.det_cantidad), 0)
	FROM dbo.inv_documento_det deta
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id AND prod.pro_estado = 'A'
	WHERE deta.enc_id = @EncId AND deta.pro_id IS NOT NULL
	GROUP BY deta.pro_id;

	DECLARE @nuevos INT = 0;
	BEGIN TRANSACTION;
	IF @Relacionar = 1
	BEGIN
		INSERT INTO dbo.inv_producto_proveedor (prv_id, pro_id, ppp_preferencia, InsUsuario, InsFechaHora)
		SELECT @prv_id, cost.pro_id,
			   CASE WHEN EXISTS (SELECT 1 FROM dbo.inv_producto_proveedor pref WHERE pref.pro_id = cost.pro_id AND pref.ppp_preferencia = 'S') THEN 'N' ELSE 'S' END,
			   @UsuId, SYSDATETIME()
		FROM @costos cost
		WHERE NOT EXISTS (SELECT 1 FROM dbo.inv_producto_proveedor rela WHERE rela.prv_id = @prv_id AND rela.pro_id = cost.pro_id);
		SET @nuevos = @@ROWCOUNT;
	END

	-- Una compra con fecha anterior a la última registrada no cambia el último costo.
	UPDATE rela
	   SET ppp_ultimo_costo = cost.costo, ppp_fecha_ultima_compra = @fecha, enc_id_ultima_compra = @EncId,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	FROM dbo.inv_producto_proveedor rela
	INNER JOIN @costos cost ON cost.pro_id = rela.pro_id
	WHERE rela.prv_id = @prv_id AND (rela.ppp_fecha_ultima_compra IS NULL OR rela.ppp_fecha_ultima_compra <= @fecha);
	COMMIT TRANSACTION;

	SELECT @nuevos AS Relacionados;
END;
GO
