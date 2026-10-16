------------------------------------------------------------------------------
-- 41_datos_sinteticos_productos_proveedor.sql
--
-- Datos de prueba de la fase C (script 40), grabados con sus procedimientos:
--
--   Productos por proveedor: cada compra vigente actualiza el último costo
--   de sus productos y relaciona con el proveedor los que no lo estaban; las
--   relaciones sin código del proveedor reciben uno (código del proveedor +
--   código del producto).
--
-- Requiere 40. Se puede volver a correr.
------------------------------------------------------------------------------

USE [erp_db];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- Productos por proveedor
------------------------------------------------------------
DECLARE @usu INT = (SELECT usu_id FROM dbo.gen_usuario WHERE usu_usuario = 'admin');
DECLARE @enc_id INT;
DECLARE @resultado TABLE (Relacionados INT);

DECLARE compras CURSOR LOCAL FAST_FORWARD FOR
	SELECT enca.enc_id
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_naturaleza = '+' AND tipo.tdo_es_nota = 0 AND tipo.tdo_es_interno = 0
	WHERE enca.enc_estado = 'G' AND enca.prv_id IS NOT NULL
	ORDER BY enca.enc_fecha_docto, enca.enc_id;
OPEN compras;
FETCH NEXT FROM compras INTO @enc_id;
WHILE @@FETCH_STATUS = 0
BEGIN
	INSERT INTO @resultado EXEC dbo.paProductoProveedorRegistrarCompra @EncId = @enc_id, @Relacionar = 1, @UsuId = @usu;
	FETCH NEXT FROM compras INTO @enc_id;
END
CLOSE compras; DEALLOCATE compras;

UPDATE rela SET ppp_codigo_proveedor = CONCAT(prov.prv_codigo, '-', prod.pro_codigo), UpdUsuario = @usu, UpdFechaHora = SYSDATETIME()
FROM dbo.inv_producto_proveedor rela
INNER JOIN dbo.inv_proveedor prov ON prov.prv_id = rela.prv_id
INNER JOIN dbo.inv_producto prod ON prod.pro_id = rela.pro_id
WHERE rela.ppp_codigo_proveedor IS NULL;

DECLARE @nuevas INT = (SELECT ISNULL(SUM(Relacionados), 0) FROM @resultado),
		@total INT = (SELECT COUNT(*) FROM dbo.inv_producto_proveedor);
PRINT CONCAT('Productos por proveedor: ', @nuevas, ' relación(es) nueva(s) desde las compras; ', @total, ' en total.');
GO
