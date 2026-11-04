/*
================================================================================
 servidor/03_usuarios_demo.sql
 Usuarios de demostración y de prueba antes de pasar a producción
 (hallazgo 6 de la auditoría del 02/11/2026).

 No es parte de instalar_01_al_NN.sql: se corre una vez, cuando el sistema
 va a empezar a usarse con datos reales.

 Qué hace:
   1. Desactiva los usuarios de prueba de carga (prueba01 a prueba10), que
      tienen el rol ADMIN.
   2. Obliga a todos los demás usuarios activos a cambiar su contraseña al
      entrar (usu_cambiar_password = 1, el mismo paso del script 75),
      incluido "admin": así nadie sigue con una clave de la etapa de pruebas
      como la de demostración (Demo#2024). Desde el script 83 las claves se
      guardan con PBKDF2 y la base ya no puede saber cuál es cuál.
   3. Nunca deja el sistema sin administrador activo: si eso pasara, revierte
      todo.

 Por omisión solo MUESTRA lo que haría (@Aplicar = 0). Revise la lista y
 vuelva a correrlo con @Aplicar = 1.

 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- ===== Ajuste aquí =====
DECLARE @Aplicar BIT = 0;	-- 0 = solo mostrar; 1 = aplicar
-- =======================

DECLARE @cambios TABLE (usu_id INT PRIMARY KEY, usu_usuario VARCHAR(64), accion VARCHAR(40));

INSERT INTO @cambios (usu_id, usu_usuario, accion)
SELECT usu_id, usu_usuario,
	   CASE WHEN usu_usuario LIKE 'prueba[0-9][0-9]' THEN 'Desactivar' ELSE 'Debe cambiar su contraseña' END
FROM dbo.gen_usuario
WHERE usu_estado = 'A';

SELECT usu_usuario AS Usuario, accion AS Accion,
	   IIF(dbo.fnSeguridadUsuarioTienePermiso(usu_id, 'SEGURIDAD_USUARIO_ADMIN') = 1, 'Sí', 'No') AS Administrador
FROM @cambios
ORDER BY accion, usu_usuario;

IF @Aplicar = 0
BEGIN
	PRINT 'Solo se mostraron los cambios. Para aplicarlos, ponga @Aplicar = 1 y vuelva a correr el script.';
	RETURN;
END

BEGIN TRANSACTION;

UPDATE usua
   SET usu_estado = 'I', UpdFechaHora = SYSDATETIME()
FROM dbo.gen_usuario usua
INNER JOIN @cambios camb ON camb.usu_id = usua.usu_id AND camb.accion = 'Desactivar';

UPDATE usua
   SET usu_cambiar_password = 1, UpdFechaHora = SYSDATETIME()
FROM dbo.gen_usuario usua
INNER JOIN @cambios camb ON camb.usu_id = usua.usu_id AND camb.accion <> 'Desactivar';

IF dbo.fnSeguridadAdministradores() = 0
BEGIN
	ROLLBACK TRANSACTION;
	THROW 50003, 'No se aplicó nada: el sistema quedaría sin un administrador activo.', 1;
END

COMMIT TRANSACTION;
PRINT 'Cambios aplicados. Los usuarios marcados deben cambiar su contraseña la próxima vez que entren.';
GO
