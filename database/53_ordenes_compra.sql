/*
================================================================================
 53_ordenes_compra.sql
 Órdenes de compra con aprobación, convertibles en ingresos a bodega.

   - cmp_orden_compra_enc / cmp_orden_compra_det: la orden al proveedor con
     los productos, cantidades y costos CON IVA (como los cotiza el proveedor),
     la bodega donde se recibe y la fecha de entrega esperada.
   - Estados guardados: B borrador, A aprobada, C cerrada (se recibió una parte
     y se cancela el saldo), N anulada. "Parcial" y "Recibida" no se guardan:
     se calculan de lo recibido en compras vigentes. Si se anula una compra que
     vino de la orden, lo que esa compra recibió vuelve a quedar pendiente.
   - Aprobación: solo una orden aprobada se recibe; aprobar requiere el
     permiso COMPRAS_ORDEN_APROBAR. Una orden en borrador se puede editar.
   - Recepción (paOrdenCompraRecibir): con la factura del proveedor se recibe
     todo o parte de lo pendiente. Crea la compra (COMP) con
     paCompraDocumentoCrear en la misma transacción: entra el inventario a
     la bodega de la orden, se genera la cuenta por pagar y la póliza.
   - Corrección: el total de una compra es el de la factura del proveedor
     (costo con IVA por unidad × cantidad); antes podía diferir un centavo.
   - Permisos: COMPRAS_ORDEN (crear, editar, anular y cerrar),
     COMPRAS_ORDEN_APROBAR y COMPRAS_ORDEN_RECIBIR.

 Errores nuevos: 54501 a 54522.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Tablas
------------------------------------------------------------
IF OBJECT_ID('dbo.cmp_orden_compra_enc', 'U') IS NULL
CREATE TABLE [dbo].[cmp_orden_compra_enc](
	[ocp_id]				INT				IDENTITY(1, 1) NOT NULL,
	[ocp_numero]			VARCHAR(16)		NOT NULL,
	[ocp_fecha]				DATE			NOT NULL,
	[ocp_fecha_entrega]		DATE			NULL,		-- fecha de entrega esperada
	[prv_id]				INT				NOT NULL,
	[suc_id]				INT				NOT NULL,
	[bod_id]				INT				NOT NULL,	-- bodega donde se recibe
	[mon_id]				INT				NOT NULL,
	[ocp_porc_iva]			NUMERIC(8, 2)	NOT NULL,
	[ocp_total]				NUMERIC(14, 2)	NOT NULL,	-- con IVA
	[ocp_condiciones]		VARCHAR(256)	NULL,		-- forma de pago, plazo, flete...
	[ocp_observaciones]		VARCHAR(500)	NULL,
	[ocp_estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_cmp_orden_compra_enc_estado] DEFAULT ('B'),
	[usu_id_aprobacion]		INT				NULL,
	[ocp_fecha_aprobacion]	DATETIME2(0)	NULL,
	[ocp_motivo_cierre]		VARCHAR(256)	NULL,		-- motivo de anulación o de cierre
	[usu_id]				INT				NULL,
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NULL,
	[UpdUsuario]			INT				NULL,
	[UpdFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_cmp_orden_compra_enc] PRIMARY KEY ([ocp_id]),
	CONSTRAINT [UQ_cmp_orden_compra_enc_numero] UNIQUE ([ocp_numero]),
	CONSTRAINT [FK_cmp_orden_compra_enc_proveedor] FOREIGN KEY ([prv_id]) REFERENCES dbo.inv_proveedor ([prv_id]),
	CONSTRAINT [FK_cmp_orden_compra_enc_sucursal] FOREIGN KEY ([suc_id]) REFERENCES dbo.gen_sucursal ([suc_id]),
	CONSTRAINT [FK_cmp_orden_compra_enc_bodega] FOREIGN KEY ([bod_id]) REFERENCES dbo.inv_bodega ([bod_id]),
	CONSTRAINT [FK_cmp_orden_compra_enc_moneda] FOREIGN KEY ([mon_id]) REFERENCES dbo.gen_moneda ([mon_id]),
	CONSTRAINT [FK_cmp_orden_compra_enc_aprobo] FOREIGN KEY ([usu_id_aprobacion]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_cmp_orden_compra_enc_usuario] FOREIGN KEY ([usu_id]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_cmp_orden_compra_enc_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_cmp_orden_compra_enc_UpdUsuario] FOREIGN KEY ([UpdUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [CK_cmp_orden_compra_enc_estado] CHECK ([ocp_estado] IN ('B', 'A', 'C', 'N')),
	CONSTRAINT [CK_cmp_orden_compra_enc_aprobacion] CHECK ([ocp_estado] = 'B' OR [ocp_estado] = 'N' OR [ocp_fecha_aprobacion] IS NOT NULL),
	CONSTRAINT [CK_cmp_orden_compra_enc_entrega] CHECK ([ocp_fecha_entrega] IS NULL OR [ocp_fecha_entrega] >= [ocp_fecha]),
	CONSTRAINT [CK_cmp_orden_compra_enc_total] CHECK ([ocp_total] >= 0)
);
GO

IF OBJECT_ID('dbo.cmp_orden_compra_det', 'U') IS NULL
CREATE TABLE [dbo].[cmp_orden_compra_det](
	[ocd_id]				INT				IDENTITY(1, 1) NOT NULL,
	[ocp_id]				INT				NOT NULL,
	[ocd_item]				INT				NOT NULL,
	[pro_id]				INT				NOT NULL,
	[ume_id]				INT				NULL,
	[ocd_descripcion]		VARCHAR(256)	NOT NULL,
	[ocd_cantidad]			INT				NOT NULL,
	[ocd_costo_unitario]	NUMERIC(12, 2)	NOT NULL,	-- con IVA
	[ocd_total]				NUMERIC(14, 2)	NOT NULL,	-- con IVA
	CONSTRAINT [PK_cmp_orden_compra_det] PRIMARY KEY ([ocd_id]),
	CONSTRAINT [UQ_cmp_orden_compra_det_item] UNIQUE ([ocp_id], [ocd_item]),
	CONSTRAINT [UQ_cmp_orden_compra_det_producto] UNIQUE ([ocp_id], [pro_id]),
	CONSTRAINT [FK_cmp_orden_compra_det_orden] FOREIGN KEY ([ocp_id]) REFERENCES dbo.cmp_orden_compra_enc ([ocp_id]),
	CONSTRAINT [FK_cmp_orden_compra_det_producto] FOREIGN KEY ([pro_id]) REFERENCES dbo.inv_producto ([pro_id]),
	CONSTRAINT [FK_cmp_orden_compra_det_unidad] FOREIGN KEY ([ume_id]) REFERENCES dbo.inv_unidad_medida ([ume_id]),
	CONSTRAINT [CK_cmp_orden_compra_det_montos] CHECK ([ocd_cantidad] > 0 AND [ocd_costo_unitario] >= 0 AND [ocd_total] >= 0)
);
GO

-- Cada recepción es una compra (inv_documento_enc) ligada a la orden.
IF OBJECT_ID('dbo.cmp_orden_compra_recepcion', 'U') IS NULL
CREATE TABLE [dbo].[cmp_orden_compra_recepcion](
	[ocr_id]				INT				IDENTITY(1, 1) NOT NULL,
	[ocp_id]				INT				NOT NULL,
	[enc_id]				INT				NOT NULL,
	[ocr_fecha]				DATE			NOT NULL,
	[usu_id]				INT				NULL,
	[InsUsuario]			INT				NULL,
	[InsFechaHora]			DATETIME2(0)	NULL,
	CONSTRAINT [PK_cmp_orden_compra_recepcion] PRIMARY KEY ([ocr_id]),
	CONSTRAINT [UQ_cmp_orden_compra_recepcion_compra] UNIQUE ([enc_id]),
	CONSTRAINT [FK_cmp_orden_compra_recepcion_orden] FOREIGN KEY ([ocp_id]) REFERENCES dbo.cmp_orden_compra_enc ([ocp_id]),
	CONSTRAINT [FK_cmp_orden_compra_recepcion_compra] FOREIGN KEY ([enc_id]) REFERENCES dbo.inv_documento_enc ([enc_id]),
	CONSTRAINT [FK_cmp_orden_compra_recepcion_usuario] FOREIGN KEY ([usu_id]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_cmp_orden_compra_recepcion_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES dbo.gen_usuario ([usu_id])
);
GO

IF OBJECT_ID('dbo.cmp_orden_compra_recepcion_det', 'U') IS NULL
CREATE TABLE [dbo].[cmp_orden_compra_recepcion_det](
	[ocr_id]				INT				NOT NULL,
	[ocd_id]				INT				NOT NULL,
	[ord_cantidad]			INT				NOT NULL,
	[ord_costo_unitario]	NUMERIC(12, 2)	NOT NULL,	-- con IVA, el de la factura del proveedor
	CONSTRAINT [PK_cmp_orden_compra_recepcion_det] PRIMARY KEY ([ocr_id], [ocd_id]),
	CONSTRAINT [FK_cmp_orden_compra_recepcion_det_recepcion] FOREIGN KEY ([ocr_id]) REFERENCES dbo.cmp_orden_compra_recepcion ([ocr_id]),
	CONSTRAINT [FK_cmp_orden_compra_recepcion_det_linea] FOREIGN KEY ([ocd_id]) REFERENCES dbo.cmp_orden_compra_det ([ocd_id]),
	CONSTRAINT [CK_cmp_orden_compra_recepcion_det_montos] CHECK ([ord_cantidad] > 0 AND [ord_costo_unitario] >= 0)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cmp_orden_compra_enc_fecha')
	CREATE INDEX [IX_cmp_orden_compra_enc_fecha] ON dbo.cmp_orden_compra_enc ([ocp_fecha]) INCLUDE ([ocp_estado], [prv_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cmp_orden_compra_enc_proveedor')
	CREATE INDEX [IX_cmp_orden_compra_enc_proveedor] ON dbo.cmp_orden_compra_enc ([prv_id], [ocp_estado]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cmp_orden_compra_recepcion_orden')
	CREATE INDEX [IX_cmp_orden_compra_recepcion_orden] ON dbo.cmp_orden_compra_recepcion ([ocp_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_cmp_orden_compra_recepcion_det_linea')
	CREATE INDEX [IX_cmp_orden_compra_recepcion_det_linea] ON dbo.cmp_orden_compra_recepcion_det ([ocd_id]) INCLUDE ([ord_cantidad]);
GO

IF TYPE_ID('dbo.orden_compra_det_type') IS NULL
	CREATE TYPE dbo.orden_compra_det_type AS TABLE (
		item			INT				NOT NULL PRIMARY KEY,
		pro_id			INT				NOT NULL,
		descripcion		VARCHAR(256)	NULL,
		cantidad		INT				NOT NULL,
		costo_unitario	NUMERIC(12, 2)	NOT NULL	-- con IVA
	);
GO

IF TYPE_ID('dbo.orden_compra_recepcion_type') IS NULL
	CREATE TYPE dbo.orden_compra_recepcion_type AS TABLE (
		ocd_id			INT				NOT NULL PRIMARY KEY,
		cantidad		INT				NOT NULL,
		costo_unitario	NUMERIC(12, 2)	NOT NULL	-- con IVA
	);
GO

------------------------------------------------------------
-- 2. Lo recibido por línea (solo compras vigentes)
------------------------------------------------------------
CREATE OR ALTER FUNCTION [dbo].[fnOrdenCompraRecibido] (@OcpId INT)
RETURNS TABLE
AS
RETURN
	SELECT deta.ocd_id,
		   SUM(CASE WHEN comp.enc_estado = 'G' THEN rdet.ord_cantidad ELSE 0 END) AS recibido
	FROM dbo.cmp_orden_compra_det deta
	LEFT JOIN dbo.cmp_orden_compra_recepcion_det rdet ON rdet.ocd_id = deta.ocd_id
	LEFT JOIN dbo.cmp_orden_compra_recepcion rece ON rece.ocr_id = rdet.ocr_id
	LEFT JOIN dbo.inv_documento_enc comp ON comp.enc_id = rece.enc_id
	WHERE deta.ocp_id = @OcpId
	GROUP BY deta.ocd_id;
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

CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraAprobar]
	@OcpId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	UPDATE dbo.cmp_orden_compra_enc
	   SET ocp_estado = 'A', usu_id_aprobacion = @UsuId, ocp_fecha_aprobacion = SYSDATETIME(),
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE ocp_id = @OcpId AND ocp_estado = 'B';
	IF @@ROWCOUNT = 0
		THROW 54509, 'Solo se aprueba una orden de compra en borrador.', 1;
END;
GO

-- Anular: en borrador, o aprobada sin nada recibido en compras vigentes.
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraAnular]
	@OcpId	INT,
	@Motivo	VARCHAR(256),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF ISNULL(LTRIM(RTRIM(@Motivo)), '') = ''
		THROW 54510, 'Indique el motivo.', 1;

	BEGIN TRANSACTION;
	DECLARE @estado CHAR(1) = (SELECT ocp_estado FROM dbo.cmp_orden_compra_enc WITH (UPDLOCK, HOLDLOCK) WHERE ocp_id = @OcpId);
	IF @estado IS NULL OR @estado NOT IN ('B', 'A')
		THROW 54511, 'Solo se anula una orden en borrador o aprobada.', 1;
	IF EXISTS (SELECT 1 FROM dbo.fnOrdenCompraRecibido(@OcpId) WHERE recibido > 0)
		THROW 54512, 'La orden ya tiene mercadería recibida: ciérrela para cancelar lo pendiente.', 1;
	UPDATE dbo.cmp_orden_compra_enc
	   SET ocp_estado = 'N', ocp_motivo_cierre = LTRIM(RTRIM(@Motivo)), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE ocp_id = @OcpId;
	COMMIT;
END;
GO

-- Cerrar: aprobada con una parte recibida; lo pendiente ya no se espera.
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraCerrar]
	@OcpId	INT,
	@Motivo	VARCHAR(256),
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	IF ISNULL(LTRIM(RTRIM(@Motivo)), '') = ''
		THROW 54510, 'Indique el motivo.', 1;

	BEGIN TRANSACTION;
	IF NOT EXISTS (SELECT 1 FROM dbo.cmp_orden_compra_enc WITH (UPDLOCK, HOLDLOCK) WHERE ocp_id = @OcpId AND ocp_estado = 'A')
		THROW 54513, 'Solo se cierra una orden aprobada.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.fnOrdenCompraRecibido(@OcpId) WHERE recibido > 0)
		THROW 54514, 'La orden no tiene nada recibido: anúlela en lugar de cerrarla.', 1;
	UPDATE dbo.cmp_orden_compra_enc
	   SET ocp_estado = 'C', ocp_motivo_cierre = LTRIM(RTRIM(@Motivo)), UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE ocp_id = @OcpId;
	COMMIT;
END;
GO

------------------------------------------------------------
-- 4. Consultas
------------------------------------------------------------
-- Estado efectivo: B borrador, A aprobada (nada recibido), P parcial,
-- R recibida (todo), C cerrada, N anulada.
-- @Estado: uno de esos, 'X' = por recibir (A o P), NULL todas.
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraConsultar]
	@Estado	CHAR(1) = NULL,
	@PrvId	INT = NULL,
	@Desde	DATE = NULL,
	@Hasta	DATE = NULL,
	@Texto	VARCHAR(100) = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @Texto = NULLIF(LTRIM(RTRIM(@Texto)), '');

	WITH ordenes AS (
		SELECT orde.ocp_id, orde.ocp_numero, orde.ocp_fecha, orde.ocp_fecha_entrega, orde.prv_id, orde.ocp_total,
			   orde.mon_id, orde.bod_id, orde.ocp_estado, cant.ordenado, cant.recibido,
			   CASE WHEN orde.ocp_estado <> 'A' THEN orde.ocp_estado
					WHEN cant.recibido >= cant.ordenado THEN 'R'
					WHEN cant.recibido > 0 THEN 'P'
					ELSE 'A' END AS estado
		FROM dbo.cmp_orden_compra_enc orde
		CROSS APPLY (SELECT SUM(deta.ocd_cantidad) AS ordenado, SUM(reci.recibido) AS recibido
					 FROM dbo.cmp_orden_compra_det deta
					 INNER JOIN dbo.fnOrdenCompraRecibido(orde.ocp_id) reci ON reci.ocd_id = deta.ocd_id) cant
		WHERE (@PrvId IS NULL OR orde.prv_id = @PrvId)
		  AND (@Desde IS NULL OR orde.ocp_fecha >= @Desde)
		  AND (@Hasta IS NULL OR orde.ocp_fecha <= @Hasta)
	)
	SELECT orde.ocp_id AS OcpId, orde.ocp_numero AS Numero, orde.ocp_fecha AS Fecha, orde.ocp_fecha_entrega AS FechaEntrega,
		   orde.prv_id AS PrvId, prov.prv_nombre_comercial AS Proveedor, prov.prv_nit AS Nit,
		   bode.bod_descripcion AS Bodega, ISNULL(mone.mon_simbolo, 'Q') AS Simbolo, orde.ocp_total AS Total,
		   orde.ordenado AS Ordenado, orde.recibido AS Recibido, orde.estado AS Estado,
		   CAST(CASE WHEN orde.estado IN ('A', 'P') AND orde.ocp_fecha_entrega < CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END AS BIT) AS Atrasada
	FROM ordenes orde
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = orde.prv_id
	INNER JOIN dbo.inv_bodega bode ON bode.bod_id = orde.bod_id
	LEFT JOIN dbo.gen_moneda mone ON mone.mon_id = orde.mon_id
	WHERE (@Estado IS NULL OR orde.estado = @Estado OR (@Estado = 'X' AND orde.estado IN ('A', 'P')))
	  AND (@Texto IS NULL OR orde.ocp_numero LIKE '%' + @Texto + '%' OR prov.prv_nombre_comercial LIKE '%' + @Texto + '%'
		   OR prov.prv_nit LIKE '%' + @Texto + '%' OR prov.prv_codigo LIKE '%' + @Texto + '%')
	ORDER BY orde.ocp_fecha DESC, orde.ocp_id DESC;
END;
GO

-- Una orden: encabezado (con emisor y proveedor para imprimirla), líneas con
-- lo recibido y lo pendiente, y las recepciones (compras) que la atendieron.
CREATE OR ALTER PROCEDURE [dbo].[paOrdenCompraConsultarPorId]
	@OcpId	INT
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @ordenado INT, @recibido INT;
	SELECT @ordenado = SUM(deta.ocd_cantidad), @recibido = SUM(reci.recibido)
	FROM dbo.cmp_orden_compra_det deta
	INNER JOIN dbo.fnOrdenCompraRecibido(@OcpId) reci ON reci.ocd_id = deta.ocd_id;

	SELECT orde.ocp_id AS OcpId, orde.ocp_numero AS Numero, orde.ocp_fecha AS Fecha, orde.ocp_fecha_entrega AS FechaEntrega,
		   CASE WHEN orde.ocp_estado <> 'A' THEN orde.ocp_estado
				WHEN @recibido >= @ordenado THEN 'R'
				WHEN @recibido > 0 THEN 'P'
				ELSE 'A' END AS Estado,
		   orde.prv_id AS PrvId, prov.prv_codigo AS ProveedorCodigo, prov.prv_nombre_comercial AS Proveedor, prov.prv_nit AS Nit,
		   prov.prv_direccion AS ProveedorDireccion, prov.prv_contacto AS ProveedorContacto,
		   COALESCE(prov.prv_telefono_oficina, prov.prv_celular) AS ProveedorTelefono,
		   COALESCE(prov.prv_email_contacto, prov.prv_email_empresa) AS ProveedorCorreo,
		   orde.suc_id AS SucId, orde.bod_id AS BodId, bode.bod_descripcion AS Bodega, orde.mon_id AS MonId,
		   ISNULL(mone.mon_codigo, 'GTQ') AS Moneda, ISNULL(mone.mon_simbolo, 'Q') AS Simbolo,
		   orde.ocp_porc_iva AS PorcentajeIva, orde.ocp_total AS Total,
		   CAST(ROUND(orde.ocp_total * orde.ocp_porc_iva / (100 + orde.ocp_porc_iva), 2) AS NUMERIC(14, 2)) AS IvaIncluido,
		   orde.ocp_condiciones AS Condiciones, orde.ocp_observaciones AS Observaciones, orde.ocp_motivo_cierre AS MotivoCierre,
		   usua.usu_codigo AS Usuario, apro.usu_codigo AS Aprobo, orde.ocp_fecha_aprobacion AS FechaAprobacion,
		   ISNULL(@ordenado, 0) AS Ordenado, ISNULL(@recibido, 0) AS Recibido,
		   -- Emisor y lugar de entrega
		   comp.cia_id AS CiaId, comp.cia_nit AS NitEmisor, ISNULL(comp.cia_fel_nombre_emisor, comp.cia_nombre_comercial) AS NombreEmisor,
		   ISNULL(sucu.suc_fel_nombre_comercial, comp.cia_nombre_comercial) AS NombreComercial,
		   ISNULL(sucu.suc_direccion, comp.cia_direccion) AS DireccionEmisor, ISNULL(sucu.suc_telefono, comp.cia_telefono) AS TelefonoEmisor,
		   ISNULL(comp.cia_fel_correo_emisor, comp.cia_email) AS CorreoEmisor, sucu.suc_descripcion AS Sucursal,
		   CAST(CASE WHEN comp.cia_logo IS NULL THEN 0 ELSE 1 END AS BIT) AS TieneLogo, comp.cia_logo_actualizado AS LogoActualizado
	FROM dbo.cmp_orden_compra_enc orde
	INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = orde.prv_id
	INNER JOIN dbo.inv_bodega bode ON bode.bod_id = orde.bod_id
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = orde.suc_id
	INNER JOIN dbo.gen_compania comp ON comp.cia_id = sucu.cia_id
	LEFT JOIN dbo.gen_moneda mone ON mone.mon_id = orde.mon_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = orde.usu_id
	LEFT JOIN dbo.gen_usuario apro ON apro.usu_id = orde.usu_id_aprobacion
	WHERE orde.ocp_id = @OcpId;

	SELECT deta.ocd_id AS OcdId, deta.ocd_item AS Item, deta.pro_id AS ProId, prod.pro_codigo AS Codigo,
		   rela.ppp_codigo_proveedor AS CodigoProveedor, deta.ocd_descripcion AS Descripcion,
		   ISNULL(unid.ume_codigo, 'UND') AS Unidad, deta.ocd_cantidad AS Cantidad, reci.recibido AS Recibido,
		   IIF(deta.ocd_cantidad > reci.recibido, deta.ocd_cantidad - reci.recibido, 0) AS Pendiente,
		   deta.ocd_costo_unitario AS CostoUnitario, deta.ocd_total AS Total, exis.existencia AS Existencia
	FROM dbo.cmp_orden_compra_det deta
	INNER JOIN dbo.cmp_orden_compra_enc orde ON orde.ocp_id = deta.ocp_id
	INNER JOIN dbo.fnOrdenCompraRecibido(@OcpId) reci ON reci.ocd_id = deta.ocd_id
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = deta.pro_id
	LEFT JOIN dbo.inv_unidad_medida unid ON unid.ume_id = deta.ume_id
	LEFT JOIN dbo.inv_producto_proveedor rela ON rela.pro_id = deta.pro_id AND rela.prv_id = orde.prv_id
	LEFT JOIN dbo.inv_producto_existencia_bodega exis ON exis.pro_id = deta.pro_id AND exis.bod_id = orde.bod_id
	WHERE deta.ocp_id = @OcpId
	ORDER BY deta.ocd_item;

	SELECT rece.ocr_id AS OcrId, rece.enc_id AS EncId, rece.ocr_fecha AS Fecha,
		   CONCAT(comp.enc_serie_docto, IIF(comp.enc_serie_docto IS NULL, '', '-'), comp.enc_numero_docto) AS Documento,
		   comp.enc_monto_total AS Total, comp.enc_estado AS EstadoCompra, usua.usu_codigo AS Usuario,
		   (SELECT SUM(rdet.ord_cantidad) FROM dbo.cmp_orden_compra_recepcion_det rdet WHERE rdet.ocr_id = rece.ocr_id) AS Unidades
	FROM dbo.cmp_orden_compra_recepcion rece
	INNER JOIN dbo.inv_documento_enc comp ON comp.enc_id = rece.enc_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = rece.usu_id
	WHERE rece.ocp_id = @OcpId
	ORDER BY rece.ocr_fecha, rece.ocr_id;
END;
GO

------------------------------------------------------------
-- 5. Total de la compra igual al de la factura del proveedor
------------------------------------------------------------
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
	@EncId							INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF NOT EXISTS (SELECT 1 FROM @Detalle)
		THROW 51411, 'La compra debe tener al menos una línea de detalle.', 1;

	IF @MonId IS NULL
		SET @MonId = dbo.fnMonedaLocal();

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

		EXEC dbo.paProveedorPlanPagosGenerar @EncId = @EncId, @UsuId = @UsuId;

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

------------------------------------------------------------
-- 7. Permisos
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT v.modulo, v.codigo, v.descripcion
FROM (VALUES ('COMPRAS', 'COMPRAS_ORDEN', 'Órdenes de compra: crear, editar, anular y cerrar'),
			 ('COMPRAS', 'COMPRAS_ORDEN_APROBAR', 'Órdenes de compra: aprobar'),
			 ('COMPRAS', 'COMPRAS_ORDEN_RECIBIR', 'Órdenes de compra: recibir mercadería (crea la compra)')) v (modulo, codigo, descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso perm WHERE perm.per_codigo = v.codigo);
GO

INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT rol.rol_id, perm.per_id
FROM (VALUES ('Administrador', 'COMPRAS_ORDEN'), ('Administrador', 'COMPRAS_ORDEN_APROBAR'), ('Administrador', 'COMPRAS_ORDEN_RECIBIR'),
			 ('Contador', 'COMPRAS_ORDEN'), ('Contador', 'COMPRAS_ORDEN_RECIBIR')) v (rol, permiso)
INNER JOIN dbo.sec_rol rol ON rol.rol_nombre = v.rol
INNER JOIN dbo.sec_permiso perm ON perm.per_codigo = v.permiso
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = rol.rol_id AND rope.per_id = perm.per_id);
GO

PRINT '53_ordenes_compra.sql aplicado.';
GO
