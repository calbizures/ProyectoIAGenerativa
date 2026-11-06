/*
 05_limpiar.sql — Después de la prueba: borra la base de resultados e inactiva los
 usuarios prueba01 a prueba10. Los documentos que grabó la prueba quedan en la base
 (por eso la prueba es solo para una base de prueba).
*/
USE erp_db;
UPDATE dbo.gen_usuario SET usu_estado = 'I' WHERE usu_usuario LIKE 'prueba[0-9][0-9]';
GO
USE master;
IF DB_ID('prueba_carga') IS NOT NULL
BEGIN
	ALTER DATABASE prueba_carga SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE prueba_carga;
END
GO
