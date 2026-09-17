------------------------------------------------------------------------------
-- 16_activar_usuario.sql
--
-- Agrega paUsuarioActivar (faltaba el complemento de sp_usuario_eliminar):
-- reactiva un usuario que fue desactivado desde el mantenimiento de Usuarios.
--
-- Usa el estándar de nomenclatura vigente para procedimientos nuevos
-- (pa + PascalCase, ver "Estándares de nomenclatura" en README.md).
--
-- Seguro de correr una sola vez contra una base ya creada con 00-15.
------------------------------------------------------------------------------

USE [erp_db];
GO

-- Por si ya habías corrido una versión anterior de este script con el
-- nombre viejo (sp_usuario_activar), antes de fijar el estándar pa+PascalCase.
DROP PROCEDURE IF EXISTS [dbo].[sp_usuario_activar];
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioActivar]
	@usu_id			INT,
	@usu_id_accion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_id = @usu_id)
		THROW 51032, 'El usuario indicado no existe.', 1;

	UPDATE dbo.gen_usuario
	   SET usu_estado = 'A',
		   UpdUsuario = @usu_id_accion,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @usu_id;
END;
GO
