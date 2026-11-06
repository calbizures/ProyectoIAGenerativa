/*
================================================================================
 78_vuelto_efectivo.sql
 Efectivo recibido y vuelto en la caja (como en un supermercado).

   - pos_caja_receptora.pcr_calcula_vuelto: parámetro por caja. Si está
     activo, al cobrar en efectivo (factura de contado, enganche o cobro de
     cuotas) el cajero escribe el efectivo que entrega el cliente y el
     sistema le muestra el vuelto.
   - pos_pago_enc.ppe_efectivo_recibido y ppe_vuelto: se guardan con el pago
     y salen en la factura, el ticket y el recibo. Son informativos: a la
     caja entra lo cobrado en efectivo (ppf_monto), así que el cuadre y las
     pólizas no cambian.
        paCajaReceptoraInsertar / Actualizar  @pcr_calcula_vuelto.
        paCajaReceptoraConsultar, paCajaAperturaConsultarActivaPorSucursal
                                    devuelven pcr_calcula_vuelto.
        paPagoEfectivoRecibidoRegistrar   graba el efectivo recibido de un
                                    pago (por recibo o por factura).
        paPagoEfectivoRecibidoConsultar   para la impresión.

 Errores nuevos: 55950 a 55952.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Columnas
------------------------------------------------------------
IF COL_LENGTH('dbo.pos_caja_receptora', 'pcr_calcula_vuelto') IS NULL
	ALTER TABLE dbo.pos_caja_receptora ADD [pcr_calcula_vuelto] BIT NOT NULL
		CONSTRAINT [DF_pos_caja_receptora_calcula_vuelto] DEFAULT (0);
GO

IF COL_LENGTH('dbo.pos_pago_enc', 'ppe_efectivo_recibido') IS NULL
	ALTER TABLE dbo.pos_pago_enc ADD
		[ppe_efectivo_recibido]	NUMERIC(12, 2)	NULL,	-- lo que entregó el cliente en efectivo
		[ppe_vuelto]			NUMERIC(12, 2)	NULL;	-- recibido − cobrado en efectivo
GO

IF OBJECT_ID('dbo.CK_pos_pago_enc_vuelto', 'C') IS NULL
	ALTER TABLE dbo.pos_pago_enc ADD CONSTRAINT [CK_pos_pago_enc_vuelto]
		CHECK ([ppe_efectivo_recibido] IS NULL OR ([ppe_efectivo_recibido] > 0 AND [ppe_vuelto] >= 0));
GO

------------------------------------------------------------
-- 2. Cajas receptoras
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCajaReceptoraInsertar]
	@pcr_descripcion	VARCHAR(64),
	@suc_id				INT,
	@usu_id				INT = NULL,
	@pcr_id				INT OUTPUT,
	@pcr_calcula_vuelto	BIT = 0
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.pos_caja_receptora WHERE pcr_descripcion = @pcr_descripcion)
		THROW 51901, 'Ya existe una caja receptora con esa descripción.', 1;

	INSERT INTO dbo.pos_caja_receptora (pcr_descripcion, suc_id, pcr_estado, pcr_calcula_vuelto, InsUsuario, InsFechaHora)
	VALUES (@pcr_descripcion, @suc_id, 'A', ISNULL(@pcr_calcula_vuelto, 0), @usu_id, SYSDATETIME());

	SET @pcr_id = SCOPE_IDENTITY();
END;
GO

-- @pcr_calcula_vuelto NULL conserva el valor actual.
CREATE OR ALTER PROCEDURE [dbo].[paCajaReceptoraActualizar]
	@pcr_id				INT,
	@pcr_descripcion	VARCHAR(64),
	@suc_id				INT,
	@usu_id				INT = NULL,
	@pcr_calcula_vuelto	BIT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_caja_receptora WHERE pcr_id = @pcr_id)
		THROW 51902, 'La caja receptora indicada no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.pos_caja_receptora WHERE pcr_descripcion = @pcr_descripcion AND pcr_id <> @pcr_id)
		THROW 51901, 'Ya existe otra caja receptora con esa descripción.', 1;

	UPDATE dbo.pos_caja_receptora
	   SET pcr_descripcion = @pcr_descripcion,
		   suc_id = @suc_id,
		   pcr_calcula_vuelto = ISNULL(@pcr_calcula_vuelto, pcr_calcula_vuelto),
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pcr_id = @pcr_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaReceptoraConsultar]
	@suc_id		INT = NULL,
	@pcr_estado	CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT pcaj.pcr_id, pcaj.pcr_descripcion, pcaj.suc_id, sucu.suc_codigo, sucu.suc_descripcion, pcaj.pcr_estado, pcaj.pcr_calcula_vuelto
	FROM dbo.pos_caja_receptora pcaj
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = pcaj.suc_id
	WHERE (@suc_id IS NULL OR pcaj.suc_id = @suc_id)
	  AND (@pcr_estado IS NULL OR pcaj.pcr_estado = @pcr_estado)
	ORDER BY sucu.suc_descripcion, pcaj.pcr_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCajaAperturaConsultarActivaPorSucursal]
	@suc_id INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT apca.pca_id, apca.pca_fecha_apertura, apca.pca_monto_inicial,
		   pcaj.pcr_id, pcaj.pcr_descripcion, pcaj.pcr_calcula_vuelto,
		   usua.usu_usuario AS usuario_apertura
	FROM dbo.pos_caja_apertura apca
	INNER JOIN dbo.pos_caja_receptora pcaj ON pcaj.pcr_id = apca.pcr_id
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = apca.usu_id_apertura
	WHERE pcaj.suc_id = @suc_id AND apca.pca_estado = 'A'
	ORDER BY pcaj.pcr_descripcion;
END;
GO

------------------------------------------------------------
-- 3. Efectivo recibido y vuelto de un pago
------------------------------------------------------------
-- El pago se indica por su recibo (@PpeId) o por la factura que se pagó al
-- grabarla (@EncId). El vuelto es lo recibido menos lo cobrado en efectivo.
CREATE OR ALTER PROCEDURE [dbo].[paPagoEfectivoRecibidoRegistrar]
	@PpeId				INT = NULL,
	@EncId				INT = NULL,
	@EfectivoRecibido	NUMERIC(12, 2),
	@UsuId				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	IF @PpeId IS NULL
		SET @PpeId = (SELECT TOP (1) deta.ppe_id FROM dbo.pos_pago_det deta
					  INNER JOIN dbo.pos_pago_enc pago ON pago.ppe_id = deta.ppe_id
					  WHERE deta.enc_id = @EncId ORDER BY deta.ppe_id);

	DECLARE @efectivo NUMERIC(12, 2) = (
		SELECT SUM(form.ppf_monto) FROM dbo.pos_pago_forma form
		INNER JOIN dbo.pos_pago_forma_tipo tipo ON tipo.pft_id = form.pft_id
		WHERE form.ppe_id = @PpeId AND tipo.pft_descripcion = 'Efectivo');
	IF @efectivo IS NULL
		THROW 55950, 'El pago no tiene una parte en efectivo.', 1;
	IF ISNULL(@EfectivoRecibido, 0) < @efectivo
	BEGIN
		DECLARE @mensaje NVARCHAR(200) = CONCAT(N'El efectivo recibido no alcanza: el cobro en efectivo es de Q', FORMAT(@efectivo, 'N2'), N'.');
		THROW 55951, @mensaje, 1;
	END

	UPDATE dbo.pos_pago_enc
	   SET ppe_efectivo_recibido = @EfectivoRecibido, ppe_vuelto = @EfectivoRecibido - @efectivo,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE ppe_id = @PpeId;
END;
GO

-- Para la factura, el ticket y el recibo.
CREATE OR ALTER PROCEDURE [dbo].[paPagoEfectivoRecibidoConsultar]
	@PpeId	INT = NULL,
	@EncId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT TOP (1) pago.ppe_id AS PpeId, pago.ppe_efectivo_recibido AS Recibido, pago.ppe_vuelto AS Vuelto
	FROM dbo.pos_pago_enc pago
	WHERE pago.ppe_efectivo_recibido IS NOT NULL
	  AND (pago.ppe_id = @PpeId
		   OR (@PpeId IS NULL AND EXISTS (SELECT 1 FROM dbo.pos_pago_det deta WHERE deta.ppe_id = pago.ppe_id AND deta.enc_id = @EncId)))
	ORDER BY pago.ppe_id;
END;
GO
