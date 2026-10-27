/*
 01_preparar.sql — Prueba de carga con 10 usuarios simultáneos.
 SOLO PARA UNA BASE DE PRUEBA: crea 10 usuarios (prueba01 a prueba10, con la misma
 contraseña que admin), abre la caja 2 si no está abierta y graba documentos reales.
 Crea la base prueba_carga (resultados) y toma la foto de existencias antes de correr.
*/
IF DB_ID('prueba_carga') IS NULL CREATE DATABASE prueba_carga;
GO
USE prueba_carga;
IF OBJECT_ID('dbo.resultado') IS NULL
CREATE TABLE dbo.resultado (
	id INT IDENTITY PRIMARY KEY, corrida VARCHAR(20), usuario INT, rol VARCHAR(20), operacion VARCHAR(40),
	inicio DATETIME2(3), ms INT, ok BIT, error_num INT NULL, error_msg NVARCHAR(400) NULL, enc_id INT NULL);
GO
USE erp_db;
SET NOCOUNT ON;
DECLARE @i INT = 1;
WHILE @i <= 10
BEGIN
	DECLARE @login VARCHAR(20) = CONCAT('prueba', RIGHT(CONCAT('0', @i), 2));
	IF NOT EXISTS (SELECT 1 FROM gen_usuario WHERE usu_usuario = @login)
	BEGIN
		INSERT INTO gen_usuario (usu_codigo, usu_usuario, usu_password_hash, usu_password_salt, usu_email, usu_fecha_ingreso, usu_intentos_fallidos, usu_bloqueado, usu_estado)
		SELECT UPPER(@login), @login, usu_password_hash, usu_password_salt, CONCAT(@login, '@siq.com.gt'), usu_fecha_ingreso, 0, 0, 'A'
		FROM gen_usuario WHERE usu_usuario = 'admin';
		DECLARE @nuevo INT = SCOPE_IDENTITY();
		INSERT INTO sec_usuario_rol (usu_id, rol_id) SELECT @nuevo, rol_id FROM sec_usuario_rol WHERE usu_id = 1;
		INSERT INTO sec_usuario_sucursal (usu_id, suc_id) SELECT @nuevo, suc_id FROM sec_usuario_sucursal WHERE usu_id = 1;
	END
	SET @i += 1;
END
-- Caja 2 abierta por prueba06 (la caja 1 ya tiene una apertura activa).
IF NOT EXISTS (SELECT 1 FROM pos_caja_apertura WHERE pcr_id = 2 AND pca_estado = 'A')
BEGIN
	DECLARE @usu6 INT = (SELECT usu_id FROM gen_usuario WHERE usu_usuario = 'prueba06'), @pca INT;
	EXEC dbo.paCajaAbrir @PcrId = 2, @UsuId = @usu6, @PcaMontoInicial = 0, @PcaId = @pca OUTPUT;
END
SELECT usu_id, usu_usuario FROM gen_usuario WHERE usu_usuario LIKE 'prueba%';
SELECT pca_id, pcr_id, pca_estado FROM pos_caja_apertura WHERE pca_estado = 'A';
GO
-- Foto antes de correr: existencias y último documento y recibo.
IF OBJECT_ID('prueba_carga.dbo.antes_exis') IS NOT NULL DROP TABLE prueba_carga.dbo.antes_exis;
SELECT pro_id, bod_id, existencia INTO prueba_carga.dbo.antes_exis FROM dbo.inv_producto_existencia_bodega;
IF OBJECT_ID('prueba_carga.dbo.antes_max') IS NOT NULL DROP TABLE prueba_carga.dbo.antes_max;
SELECT MAX(enc_id) AS enc_max, (SELECT MAX(ppe_id) FROM dbo.pos_pago_enc) AS ppe_max INTO prueba_carga.dbo.antes_max FROM dbo.inv_documento_enc;
DELETE FROM prueba_carga.dbo.resultado;
GO
