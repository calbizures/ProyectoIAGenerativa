/*
================================================================================
 67_antiguedad_vendedor_permisos.sql
 Fase 4, puntos 1 y 4.

   - Antigüedad de saldos de clientes por vendedor: quien tiene el permiso
     CXC_ANTIGUEDAD_TODOS (administrador, contador y contador general) ve
     todos los clientes; los demás ven todo el saldo de los clientes a los
     que su vendedor (usuario -> empleado -> vendedor) les ha vendido, con
     al menos una factura vigente. Un usuario sin vendedor no ve clientes.
   - Mantenimiento de permisos (sec_permiso): modificar módulo, descripción
     y estado, eliminar el que no está asignado a ningún rol y detalle con
     los roles y los usuarios que lo tienen.
   - Los permisos de un rol inactivo ya no cuentan (fnUsuarioTienePermiso).

 Errores nuevos: 55501 a 55520.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Funciones de apoyo
------------------------------------------------------------
-- 1 si el usuario tiene el permiso por alguno de sus roles activos.
CREATE OR ALTER FUNCTION [dbo].[fnUsuarioTienePermiso] (@UsuId INT, @Codigo VARCHAR(64))
RETURNS BIT
AS
BEGIN
	RETURN IIF(EXISTS (SELECT 1 FROM dbo.sec_usuario_rol usro
					   INNER JOIN dbo.sec_rol srol ON srol.rol_id = usro.rol_id AND srol.rol_estado = 'A'
					   INNER JOIN dbo.sec_rol_permiso rope ON rope.rol_id = srol.rol_id
					   INNER JOIN dbo.sec_permiso perm ON perm.per_id = rope.per_id AND perm.per_estado = 'A'
					   WHERE usro.usu_id = @UsuId AND perm.per_codigo = @Codigo), 1, 0);
END;
GO

-- Vendedor activo del usuario (usuario -> empleado -> vendedor), o NULL.
CREATE OR ALTER FUNCTION [dbo].[fnUsuarioVendedor] (@UsuId INT)
RETURNS INT
AS
BEGIN
	RETURN (SELECT TOP 1 vend.pve_id FROM dbo.gen_usuario usua
			INNER JOIN dbo.pos_vendedor vend ON vend.IdEmpleado = usua.IdEmpleado AND vend.pve_estado = 'A'
			WHERE usua.usu_id = @UsuId AND usua.IdEmpleado IS NOT NULL ORDER BY vend.pve_id);
END;
GO

-- Clientes que puede ver el usuario en la antigüedad de saldos.
CREATE OR ALTER FUNCTION [dbo].[fnCxcClientesUsuario] (@UsuId INT)
RETURNS TABLE
AS
RETURN
	SELECT clie.cli_id
	FROM dbo.pos_cliente clie
	WHERE dbo.fnUsuarioTienePermiso(@UsuId, 'CXC_ANTIGUEDAD_TODOS') = 1
	   OR EXISTS (SELECT 1 FROM dbo.inv_documento_enc enca
				  INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id AND tipo.tdo_naturaleza = '-'
				  WHERE enca.cli_id = clie.cli_id AND enca.enc_estado = 'G'
					AND enca.pve_id = dbo.fnUsuarioVendedor(@UsuId));
GO

------------------------------------------------------------
-- 2. Permiso para ver todos los clientes
------------------------------------------------------------
INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion)
SELECT 'CXC', 'CXC_ANTIGUEDAD_TODOS', 'Antigüedad de saldos: ver todos los clientes (sin él, solo los clientes a los que su vendedor ha vendido)'
WHERE NOT EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_codigo = 'CXC_ANTIGUEDAD_TODOS');
INSERT INTO dbo.sec_rol_permiso (rol_id, per_id)
SELECT srol.rol_id, perm.per_id
FROM dbo.sec_rol srol CROSS JOIN dbo.sec_permiso perm
WHERE srol.rol_codigo IN ('ADMIN', 'CONTADOR', 'CONTADOR_GENERAL') AND perm.per_codigo = 'CXC_ANTIGUEDAD_TODOS'
  AND NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso rope WHERE rope.rol_id = srol.rol_id AND rope.per_id = perm.per_id);
GO

------------------------------------------------------------
-- 3. Antigüedad de saldos de clientes
------------------------------------------------------------
-- @UsuId NULL: sin filtro (uso interno: estado de cuenta, correo). Con
-- usuario: solo los clientes que ese usuario puede ver.
CREATE OR ALTER PROCEDURE [dbo].[paCxcAntiguedadConsultar]
	@FechaCorte	DATE = NULL,
	@CliId		INT = NULL,
	@UsuId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @FechaCorte = ISNULL(@FechaCorte, CAST(GETDATE() AS DATE));

	SELECT clie.cli_id AS Id, clie.cli_codigo AS Codigo, CONCAT(clie.cli_nombres, ' ', clie.cli_apellidos) AS Nombre,
		   enca.enc_id, ISNULL(enca.enc_numero_unico, CONCAT(enca.enc_serie_docto, '-', enca.enc_numero_docto)) AS Documento,
		   enca.enc_fecha_docto AS FechaDocumento, cuot.cpp_nro_cuota AS Cuota, cuot.cpp_fecha_maxima_pago AS Vencimiento,
		   dias.Dias, cuot.cpp_saldo_cuota AS Saldo,
		   CASE WHEN dias.Dias <= 0 THEN cuot.cpp_saldo_cuota ELSE 0 END AS NoVencido,
		   CASE WHEN dias.Dias BETWEEN 1 AND 30 THEN cuot.cpp_saldo_cuota ELSE 0 END AS De1a30,
		   CASE WHEN dias.Dias BETWEEN 31 AND 60 THEN cuot.cpp_saldo_cuota ELSE 0 END AS De31a60,
		   CASE WHEN dias.Dias BETWEEN 61 AND 90 THEN cuot.cpp_saldo_cuota ELSE 0 END AS De61a90,
		   CASE WHEN dias.Dias > 90 THEN cuot.cpp_saldo_cuota ELSE 0 END AS Mas90
	FROM dbo.pos_cliente_plan_pagos cuot
	INNER JOIN dbo.inv_documento_enc enca ON enca.enc_id = cuot.enc_id AND enca.enc_estado = 'G'
	INNER JOIN dbo.pos_cliente clie ON clie.cli_id = enca.cli_id
	CROSS APPLY (SELECT DATEDIFF(DAY, cuot.cpp_fecha_maxima_pago, @FechaCorte) AS Dias) dias
	WHERE cuot.cpp_saldo_cuota > 0
	  AND enca.enc_fecha_docto <= @FechaCorte
	  AND (@CliId IS NULL OR clie.cli_id = @CliId)
	  AND (@UsuId IS NULL OR clie.cli_id IN (SELECT cli_id FROM dbo.fnCxcClientesUsuario(@UsuId)))
	ORDER BY Nombre, enca.enc_fecha_docto, enca.enc_id, cuot.cpp_nro_cuota;
END;
GO

-- Alcance del usuario: si ve todos los clientes y, si no, su vendedor y los
-- clientes que puede elegir (resultado 2).
CREATE OR ALTER PROCEDURE [dbo].[paCxcAntiguedadAlcanceConsultar]
	@UsuId	INT
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @todos BIT = dbo.fnUsuarioTienePermiso(@UsuId, 'CXC_ANTIGUEDAD_TODOS'), @pve_id INT = dbo.fnUsuarioVendedor(@UsuId);
	SELECT @todos AS VerTodos, @pve_id AS PveId,
		   (SELECT CONCAT(vend.pve_codigo, ' - ', vend.pve_nombres, ' ', vend.pve_apellidos) FROM dbo.pos_vendedor vend WHERE vend.pve_id = @pve_id) AS Vendedor;
	SELECT cli_id AS CliId FROM dbo.fnCxcClientesUsuario(@UsuId) WHERE @todos = 0;
END;
GO

------------------------------------------------------------
-- 4. Permisos
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paPermisoConsultar]
	@PerModulo	VARCHAR(32) = NULL,
	@PerEstado	CHAR(1) = NULL,
	@Texto		VARCHAR(100) = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @Texto = NULLIF(LTRIM(RTRIM(@Texto)), '');
	SELECT perm.per_id, perm.per_modulo, perm.per_codigo, perm.per_descripcion, perm.per_estado,
		   (SELECT COUNT(*) FROM dbo.sec_rol_permiso rope WHERE rope.per_id = perm.per_id) AS Roles,
		   (SELECT COUNT(DISTINCT usro.usu_id) FROM dbo.sec_rol_permiso rope
			INNER JOIN dbo.sec_rol srol ON srol.rol_id = rope.rol_id AND srol.rol_estado = 'A'
			INNER JOIN dbo.sec_usuario_rol usro ON usro.rol_id = srol.rol_id
			INNER JOIN dbo.gen_usuario usua ON usua.usu_id = usro.usu_id AND usua.usu_estado = 'A'
			WHERE rope.per_id = perm.per_id) AS Usuarios
	FROM dbo.sec_permiso perm
	WHERE (@PerModulo IS NULL OR perm.per_modulo LIKE '%' + @PerModulo + '%')
	  AND (@PerEstado IS NULL OR perm.per_estado = @PerEstado)
	  AND (@Texto IS NULL OR perm.per_codigo LIKE '%' + @Texto + '%' OR perm.per_descripcion LIKE '%' + @Texto + '%' OR perm.per_modulo LIKE '%' + @Texto + '%')
	ORDER BY perm.per_modulo, perm.per_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paPermisoInsertar]
	@PerModulo		VARCHAR(32),
	@PerCodigo		VARCHAR(64),
	@PerDescripcion	VARCHAR(128) = NULL,
	@UsuId			INT = NULL,
	@PerId			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SET @PerModulo = NULLIF(UPPER(LTRIM(RTRIM(@PerModulo))), '');
	SET @PerCodigo = NULLIF(UPPER(LTRIM(RTRIM(@PerCodigo))), '');
	IF @PerModulo IS NULL OR @PerCodigo IS NULL
		THROW 55501, 'Indique el módulo y el código del permiso.', 1;
	IF @PerCodigo LIKE '%[^A-Z0-9_]%'
		THROW 55502, 'El código del permiso lleva solo letras sin tilde, números y guion bajo (por ejemplo CXC_ANTIGUEDAD_TODOS).', 1;
	IF EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_codigo = @PerCodigo)
		THROW 51081, 'Ya existe un permiso con ese código.', 1;

	INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion, InsUsuario, InsFechaHora)
	VALUES (@PerModulo, @PerCodigo, NULLIF(LTRIM(RTRIM(@PerDescripcion)), ''), @UsuId, SYSDATETIME());
	SET @PerId = SCOPE_IDENTITY();
END;
GO

-- El código no se cambia: la aplicación lo usa para mostrar opciones y botones.
CREATE OR ALTER PROCEDURE [dbo].[paPermisoActualizar]
	@PerId			INT,
	@PerModulo		VARCHAR(32),
	@PerDescripcion	VARCHAR(128) = NULL,
	@PerEstado		CHAR(1) = 'A',
	@UsuId			INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SET @PerModulo = NULLIF(UPPER(LTRIM(RTRIM(@PerModulo))), '');
	IF NOT EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_id = @PerId)
		THROW 55503, 'El permiso no existe.', 1;
	IF @PerModulo IS NULL
		THROW 55501, 'Indique el módulo y el código del permiso.', 1;
	IF @PerEstado NOT IN ('A', 'I')
		THROW 55504, 'El estado del permiso es A (activo) o I (inactivo).', 1;
	IF @PerEstado = 'I' AND EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_id = @PerId AND per_codigo = 'SEGURIDAD_USUARIO_ADMIN')
		THROW 55505, 'El permiso SEGURIDAD_USUARIO_ADMIN no se inactiva: sin él nadie podría administrar usuarios, roles ni permisos.', 1;
	UPDATE dbo.sec_permiso
	   SET per_modulo = @PerModulo, per_descripcion = NULLIF(LTRIM(RTRIM(@PerDescripcion)), ''), per_estado = @PerEstado,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE per_id = @PerId;
END;
GO

-- Solo un permiso que ningún rol tiene asignado.
CREATE OR ALTER PROCEDURE [dbo].[paPermisoEliminar]
	@PerId	INT
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @roles INT = (SELECT COUNT(*) FROM dbo.sec_rol_permiso WHERE per_id = @PerId), @mensaje NVARCHAR(300);
	IF NOT EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_id = @PerId)
		THROW 55503, 'El permiso no existe.', 1;
	IF @roles > 0
	BEGIN
		SET @mensaje = CONCAT(N'El permiso está asignado a ', @roles, IIF(@roles = 1, N' rol', N' roles'), N': quíteselo en Roles o inactívelo.');
		THROW 55506, @mensaje, 1;
	END
	DELETE FROM dbo.sec_permiso WHERE per_id = @PerId;
END;
GO

-- Resultado 1: el permiso. 2: roles que lo tienen. 3: usuarios que lo
-- tienen y por qué roles (Vigente = 1 si usuario y rol están activos).
CREATE OR ALTER PROCEDURE [dbo].[paPermisoDetalleConsultar]
	@PerId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT perm.per_id, perm.per_modulo, perm.per_codigo, perm.per_descripcion, perm.per_estado,
		   perm.InsFechaHora AS Creado, usua.usu_usuario AS CreadoPor, perm.UpdFechaHora AS Modificado
	FROM dbo.sec_permiso perm
	LEFT JOIN dbo.gen_usuario usua ON usua.usu_id = perm.InsUsuario
	WHERE perm.per_id = @PerId;

	SELECT srol.rol_id AS RolId, srol.rol_codigo AS Codigo, srol.rol_nombre AS Nombre, srol.rol_estado AS Estado,
		   (SELECT COUNT(*) FROM dbo.sec_usuario_rol usro WHERE usro.rol_id = srol.rol_id) AS Usuarios,
		   rope.InsFechaHora AS Asignado
	FROM dbo.sec_rol_permiso rope
	INNER JOIN dbo.sec_rol srol ON srol.rol_id = rope.rol_id
	WHERE rope.per_id = @PerId
	ORDER BY srol.rol_codigo;

	SELECT usua.usu_id AS UsuId, usua.usu_codigo AS Codigo, usua.usu_usuario AS Usuario, usua.usu_email AS Email,
		   usua.usu_estado AS Estado, usua.usu_ultimo_login AS UltimoIngreso,
		   CONCAT_WS(' ', empl.PrimerNombre, empl.PrimerApellido) AS Empleado,
		   STRING_AGG(srol.rol_codigo, ', ') WITHIN GROUP (ORDER BY srol.rol_codigo) AS Roles,
		   CAST(MAX(IIF(usua.usu_estado = 'A' AND srol.rol_estado = 'A', 1, 0)) AS BIT) AS Vigente
	FROM dbo.sec_rol_permiso rope
	INNER JOIN dbo.sec_rol srol ON srol.rol_id = rope.rol_id
	INNER JOIN dbo.sec_usuario_rol usro ON usro.rol_id = srol.rol_id
	INNER JOIN dbo.gen_usuario usua ON usua.usu_id = usro.usu_id
	LEFT JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = usua.IdEmpleado
	WHERE rope.per_id = @PerId
	GROUP BY usua.usu_id, usua.usu_codigo, usua.usu_usuario, usua.usu_email, usua.usu_estado, usua.usu_ultimo_login, empl.PrimerNombre, empl.PrimerApellido
	ORDER BY usua.usu_usuario;
END;
GO

PRINT '67_antiguedad_vendedor_permisos.sql aplicado.';
GO
