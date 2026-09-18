/*
	Script 10: Procedimientos CRUD de las entidades principales.

	Convención:
	- sp_<entidad>_insertar        -> inserta y regresa el id nuevo por OUTPUT
	- sp_<entidad>_actualizar      -> actualiza por id, valida existencia
	- sp_<entidad>_eliminar        -> baja lógica (estado='I') salvo que se
	                                   indique lo contrario
	- sp_<entidad>_consultar       -> listado con filtros opcionales y paginado
	- sp_<entidad>_consultar_por_id -> detalle de un registro

	Auditoría: todo procedimiento que inserta, actualiza o da de baja recibe
	un parámetro @usu_id (el usuario que ejecuta la acción; NULL si no se
	informa) y lo graba en [InsUsuario]/[UpdUsuario] de la fila afectada,
	junto con [InsFechaHora]/[UpdFechaHora] = SYSDATETIME(). En los
	procedimientos de [gen_usuario], donde @usu_id ya se usa para identificar
	la fila objetivo, el usuario que ejecuta la acción se recibe como
	@usu_id_accion para no chocar con ese parámetro.

	Los procesos de negocio (crear factura/compra, pagos, cheques, login,
	existencias, asientos contables automáticos) están en
	11_procedimientos_procesos.sql.
*/
USE [erp_db];
GO

------------------------------------------------------------
-- inv_producto
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_producto_insertar]
	@pro_codigo				VARCHAR(64),
	@pro_descripcion		VARCHAR(256),
	@prt_id					INT,
	@pro_tipo_item			CHAR(1) = 'B',
	@pro_maneja_existencia	BIT = 1,
	@pro_id_padre			INT = NULL,
	@usu_id					INT = NULL,
	@pro_id					INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_codigo = @pro_codigo)
		THROW 51001, 'Ya existe un producto con ese código.', 1;

	INSERT INTO dbo.inv_producto
		(pro_codigo, pro_descripcion, prt_id, pro_tipo_item, pro_maneja_existencia, pro_id_padre, InsUsuario, InsFechaHora)
	VALUES
		(@pro_codigo, @pro_descripcion, @prt_id, @pro_tipo_item, @pro_maneja_existencia, @pro_id_padre, @usu_id, SYSDATETIME());

	SET @pro_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_producto_actualizar]
	@pro_id					INT,
	@pro_codigo				VARCHAR(64),
	@pro_descripcion		VARCHAR(256),
	@prt_id					INT,
	@pro_tipo_item			CHAR(1),
	@pro_maneja_existencia	BIT,
	@pro_id_padre			INT = NULL,
	@pro_ptje_rentabilidad	NUMERIC(8, 2) = NULL,
	@usu_id					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_id = @pro_id)
		THROW 51002, 'El producto indicado no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_codigo = @pro_codigo AND pro_id <> @pro_id)
		THROW 51001, 'Ya existe otro producto con ese código.', 1;

	UPDATE dbo.inv_producto
	   SET pro_codigo = @pro_codigo,
		   pro_descripcion = @pro_descripcion,
		   prt_id = @prt_id,
		   pro_tipo_item = @pro_tipo_item,
		   pro_maneja_existencia = @pro_maneja_existencia,
		   pro_id_padre = @pro_id_padre,
		   pro_ptje_rentabilidad = @pro_ptje_rentabilidad,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pro_id = @pro_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_producto_eliminar]
	@pro_id INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_id = @pro_id)
		THROW 51002, 'El producto indicado no existe.', 1;

	UPDATE dbo.inv_producto
	   SET pro_estado = 'I',
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pro_id = @pro_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_producto_consultar]
	@pro_codigo			VARCHAR(64) = NULL,
	@pro_descripcion	VARCHAR(256) = NULL,
	@prt_id				INT = NULL,
	@pro_estado			CHAR(1) = 'A',
	@pagina				INT = 1,
	@tamanio_pagina		INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT pro.pro_id, pro.pro_codigo, pro.pro_descripcion, pro.pro_tipo_item,
		   pro.pro_maneja_existencia, pro.pro_total_cantidad, pro.pro_costo_unitario,
		   pro.prt_id, prt.prt_descripcion, pro.pro_estado
	FROM dbo.inv_producto pro
	INNER JOIN dbo.inv_producto_tipo prt ON prt.prt_id = pro.prt_id
	WHERE (@pro_codigo IS NULL OR pro.pro_codigo LIKE '%' + @pro_codigo + '%')
	  AND (@pro_descripcion IS NULL OR pro.pro_descripcion LIKE '%' + @pro_descripcion + '%')
	  AND (@prt_id IS NULL OR pro.prt_id = @prt_id)
	  AND (@pro_estado IS NULL OR pro.pro_estado = @pro_estado)
	ORDER BY pro.pro_descripcion
	OFFSET (@pagina - 1) * @tamanio_pagina ROWS FETCH NEXT @tamanio_pagina ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_producto_consultar_por_id]
	@pro_id INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT pro.*, prt.prt_descripcion
	FROM dbo.inv_producto pro
	INNER JOIN dbo.inv_producto_tipo prt ON prt.prt_id = pro.prt_id
	WHERE pro.pro_id = @pro_id;

	SELECT peb.bod_id, bod.bod_descripcion, peb.existencia
	FROM dbo.inv_producto_existencia_bodega peb
	INNER JOIN dbo.inv_bodega bod ON bod.bod_id = peb.bod_id
	WHERE peb.pro_id = @pro_id;

	SELECT ppr.ppr_id, ppr.bod_id, ppr.ppr_precio_unitario_venta, ppr.ppr_vigencia_desde, ppr.ppr_vigencia_hasta, ppr.mon_id
	FROM dbo.inv_producto_precio ppr
	WHERE ppr.pro_id = @pro_id AND ppr.ppr_estado = 'A';
END;
GO

------------------------------------------------------------
-- inv_producto_tipo_caracteristica (catálogo, solo consulta desde el
-- frontend; se siembra con 12_datos_sinteticos.sql)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paProductoTipoCaracteristicaConsultar]
	@ptc_estado CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT ptc_id, ptc_codigo, ptc_descripcion, ptc_orden, ptc_estado
	FROM dbo.inv_producto_tipo_caracteristica
	WHERE (@ptc_estado IS NULL OR ptc_estado = @ptc_estado)
	ORDER BY ptc_orden, ptc_descripcion;
END;
GO

------------------------------------------------------------
-- inv_producto_caracteristica
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paProductoCaracteristicaInsertar]
	@pro_id				INT,
	@ptc_id				INT,
	@pca_valor			VARCHAR(64),
	@pca_descripcion	VARCHAR(64) = NULL,
	@usu_id				INT = NULL,
	@pca_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_id = @pro_id)
		THROW 51101, 'El producto indicado no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.inv_producto_caracteristica WHERE pro_id = @pro_id AND ptc_id = @ptc_id)
		THROW 51102, 'El producto ya tiene un valor asignado para esa característica.', 1;

	INSERT INTO dbo.inv_producto_caracteristica
		(pca_valor, pca_descripcion, pro_id, ptc_id, InsUsuario, InsFechaHora)
	VALUES
		(@pca_valor, @pca_descripcion, @pro_id, @ptc_id, @usu_id, SYSDATETIME());

	SET @pca_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoCaracteristicaActualizar]
	@pca_id				INT,
	@pca_valor			VARCHAR(64),
	@pca_descripcion	VARCHAR(64) = NULL,
	@usu_id				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto_caracteristica WHERE pca_id = @pca_id)
		THROW 51103, 'La característica indicada no existe.', 1;

	UPDATE dbo.inv_producto_caracteristica
	   SET pca_valor = @pca_valor,
		   pca_descripcion = @pca_descripcion,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pca_id = @pca_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoCaracteristicaEliminar]
	@pca_id INT
AS
BEGIN
	SET NOCOUNT ON;

	-- inv_producto_caracteristica no tiene columna de estado (es un valor
	-- puntual por producto/característica), así que la baja es física.
	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto_caracteristica WHERE pca_id = @pca_id)
		THROW 51103, 'La característica indicada no existe.', 1;

	DELETE FROM dbo.inv_producto_caracteristica WHERE pca_id = @pca_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoCaracteristicaConsultar]
	@pro_id INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	SELECT prca.pca_id, prca.pca_valor, prca.pca_descripcion, prca.pro_id,
		   prod.pro_codigo, prod.pro_descripcion,
		   prca.ptc_id, ptca.ptc_codigo, ptca.ptc_descripcion
	FROM dbo.inv_producto_caracteristica prca
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = prca.pro_id
	INNER JOIN dbo.inv_producto_tipo_caracteristica ptca ON ptca.ptc_id = prca.ptc_id
	WHERE (@pro_id IS NULL OR prca.pro_id = @pro_id)
	ORDER BY prod.pro_descripcion, ptca.ptc_orden;
END;
GO

------------------------------------------------------------
-- inv_producto_existencia_bodega (solo consulta; la existencia la
-- mantienen los procesos de negocio al grabar/anular documentos)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paProductoExistenciaConsultar]
	@pro_id	INT = NULL,
	@bod_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	SELECT pexi.peb_id, pexi.pro_id, prod.pro_codigo, prod.pro_descripcion,
		   pexi.bod_id, bode.bod_descripcion, pexi.existencia
	FROM dbo.inv_producto_existencia_bodega pexi
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = pexi.pro_id
	INNER JOIN dbo.inv_bodega bode ON bode.bod_id = pexi.bod_id
	WHERE (@pro_id IS NULL OR pexi.pro_id = @pro_id)
	  AND (@bod_id IS NULL OR pexi.bod_id = @bod_id)
	ORDER BY prod.pro_descripcion, bode.bod_descripcion;
END;
GO

------------------------------------------------------------
-- inv_producto_precio
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paProductoPrecioInsertar]
	@pro_id							INT,
	@bod_id							INT,
	@mon_id							INT,
	@ppr_precio_unitario_venta		NUMERIC(12, 2),
	@ppr_descripcion				VARCHAR(128) = NULL,
	@ppr_vigencia_desde				DATE,
	@ppr_vigencia_hasta				DATE = NULL,
	@usu_id							INT = NULL,
	@ppr_id							INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_id = @pro_id)
		THROW 51111, 'El producto indicado no existe.', 1;

	INSERT INTO dbo.inv_producto_precio
		(ppr_precio_unitario_venta, ppr_descripcion, ppr_vigencia_desde, ppr_vigencia_hasta,
		 pro_id, bod_id, mon_id, ppr_estado, InsUsuario, InsFechaHora)
	VALUES
		(@ppr_precio_unitario_venta, @ppr_descripcion, @ppr_vigencia_desde, @ppr_vigencia_hasta,
		 @pro_id, @bod_id, @mon_id, 'A', @usu_id, SYSDATETIME());

	SET @ppr_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoPrecioActualizar]
	@ppr_id							INT,
	@bod_id							INT,
	@mon_id							INT,
	@ppr_precio_unitario_venta		NUMERIC(12, 2),
	@ppr_descripcion				VARCHAR(128) = NULL,
	@ppr_vigencia_desde				DATE,
	@ppr_vigencia_hasta				DATE = NULL,
	@usu_id							INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto_precio WHERE ppr_id = @ppr_id)
		THROW 51112, 'El precio indicado no existe.', 1;

	UPDATE dbo.inv_producto_precio
	   SET bod_id = @bod_id,
		   mon_id = @mon_id,
		   ppr_precio_unitario_venta = @ppr_precio_unitario_venta,
		   ppr_descripcion = @ppr_descripcion,
		   ppr_vigencia_desde = @ppr_vigencia_desde,
		   ppr_vigencia_hasta = @ppr_vigencia_hasta,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE ppr_id = @ppr_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoPrecioEliminar]
	@ppr_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto_precio WHERE ppr_id = @ppr_id)
		THROW 51112, 'El precio indicado no existe.', 1;

	UPDATE dbo.inv_producto_precio
	   SET ppr_estado = 'I',
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE ppr_id = @ppr_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoPrecioConsultar]
	@pro_id		INT = NULL,
	@bod_id		INT = NULL,
	@ppr_estado	CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT prec.ppr_id, prec.pro_id, prod.pro_codigo, prod.pro_descripcion,
		   prec.bod_id, bode.bod_descripcion, prec.mon_id, mone.mon_codigo,
		   prec.ppr_precio_unitario_venta, prec.ppr_descripcion,
		   prec.ppr_vigencia_desde, prec.ppr_vigencia_hasta, prec.ppr_estado
	FROM dbo.inv_producto_precio prec
	INNER JOIN dbo.inv_producto prod ON prod.pro_id = prec.pro_id
	INNER JOIN dbo.inv_bodega bode ON bode.bod_id = prec.bod_id
	INNER JOIN dbo.gen_moneda mone ON mone.mon_id = prec.mon_id
	WHERE (@pro_id IS NULL OR prec.pro_id = @pro_id)
	  AND (@bod_id IS NULL OR prec.bod_id = @bod_id)
	  AND (@ppr_estado IS NULL OR prec.ppr_estado = @ppr_estado)
	ORDER BY prod.pro_descripcion, bode.bod_descripcion, prec.ppr_vigencia_desde DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoPrecioConsultarPorId]
	@ppr_id INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT prec.*
	FROM dbo.inv_producto_precio prec
	WHERE prec.ppr_id = @ppr_id;
END;
GO

------------------------------------------------------------
-- pos_cliente
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_cliente_insertar]
	@cli_codigo				VARCHAR(32),
	@cli_nombres			VARCHAR(64),
	@cli_apellidos			VARCHAR(64) = NULL,
	@cli_direccion			VARCHAR(128) = NULL,
	@cli_telefono_celular	VARCHAR(16) = NULL,
	@cli_nit				VARCHAR(16) = NULL,
	@cli_email				VARCHAR(64) = NULL,
	@cli_limite_credito		DECIMAL(14, 2) = 0,
	@cli_direccion_pais		INT = NULL,
	@cli_direccion_estado	INT = NULL,
	@cli_direccion_provincia INT = NULL,
	@usu_id					INT = NULL,
	@cli_id					INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_codigo = @cli_codigo)
		THROW 51011, 'Ya existe un cliente con ese código.', 1;

	IF @cli_nit IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_nit = @cli_nit)
		THROW 51012, 'Ya existe un cliente con ese NIT.', 1;

	INSERT INTO dbo.pos_cliente
		(cli_codigo, cli_nombres, cli_apellidos, cli_direccion, cli_telefono_celular,
		 cli_nit, cli_email, cli_limite_credito, cli_direccion_pais, cli_direccion_estado, cli_direccion_provincia,
		 InsUsuario, InsFechaHora)
	VALUES
		(@cli_codigo, @cli_nombres, @cli_apellidos, @cli_direccion, @cli_telefono_celular,
		 @cli_nit, @cli_email, @cli_limite_credito, @cli_direccion_pais, @cli_direccion_estado, @cli_direccion_provincia,
		 @usu_id, SYSDATETIME());

	SET @cli_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_cliente_actualizar]
	@cli_id					INT,
	@cli_nombres			VARCHAR(64),
	@cli_apellidos			VARCHAR(64) = NULL,
	@cli_direccion			VARCHAR(128) = NULL,
	@cli_telefono_celular	VARCHAR(16) = NULL,
	@cli_nit				VARCHAR(16) = NULL,
	@cli_email				VARCHAR(64) = NULL,
	@cli_limite_credito		DECIMAL(14, 2) = 0,
	@usu_id					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_id = @cli_id)
		THROW 51013, 'El cliente indicado no existe.', 1;

	IF @cli_nit IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_nit = @cli_nit AND cli_id <> @cli_id)
		THROW 51012, 'Ya existe otro cliente con ese NIT.', 1;

	UPDATE dbo.pos_cliente
	   SET cli_nombres = @cli_nombres,
		   cli_apellidos = @cli_apellidos,
		   cli_direccion = @cli_direccion,
		   cli_telefono_celular = @cli_telefono_celular,
		   cli_nit = @cli_nit,
		   cli_email = @cli_email,
		   cli_limite_credito = @cli_limite_credito,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE cli_id = @cli_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_cliente_eliminar]
	@cli_id INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_id = @cli_id)
		THROW 51013, 'El cliente indicado no existe.', 1;

	UPDATE dbo.pos_cliente
	   SET cli_estado = 'I',
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE cli_id = @cli_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_cliente_consultar]
	@texto			VARCHAR(128) = NULL,	-- busca en código, nombres, apellidos o NIT
	@cli_estado		CHAR(1) = 'A',
	@pagina			INT = 1,
	@tamanio_pagina	INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT cli_id, cli_codigo, cli_nombres, cli_apellidos, cli_nit, cli_email,
		   cli_telefono_celular, cli_limite_credito, cli_estado
	FROM dbo.pos_cliente
	WHERE (@cli_estado IS NULL OR cli_estado = @cli_estado)
	  AND (@texto IS NULL
		   OR cli_codigo LIKE '%' + @texto + '%'
		   OR cli_nombres LIKE '%' + @texto + '%'
		   OR cli_apellidos LIKE '%' + @texto + '%'
		   OR cli_nit LIKE '%' + @texto + '%')
	ORDER BY cli_nombres, cli_apellidos
	OFFSET (@pagina - 1) * @tamanio_pagina ROWS FETCH NEXT @tamanio_pagina ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_cliente_consultar_por_id]
	@cli_id INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.pos_cliente WHERE cli_id = @cli_id;
END;
GO

------------------------------------------------------------
-- inv_proveedor
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_proveedor_insertar]
	@prv_codigo				VARCHAR(16),
	@prv_nombre_comercial	VARCHAR(128),
	@prv_nit				VARCHAR(16) = NULL,
	@prv_contacto			VARCHAR(128) = NULL,
	@prv_direccion			VARCHAR(128) = NULL,
	@prv_telefono_oficina	VARCHAR(16) = NULL,
	@prv_email_empresa		VARCHAR(64) = NULL,
	@usu_id					INT = NULL,
	@prv_id					INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.inv_proveedor WHERE prv_codigo = @prv_codigo)
		THROW 51021, 'Ya existe un proveedor con ese código.', 1;

	INSERT INTO dbo.inv_proveedor
		(prv_codigo, prv_nombre_comercial, prv_nit, prv_contacto, prv_direccion, prv_telefono_oficina, prv_email_empresa,
		 InsUsuario, InsFechaHora)
	VALUES
		(@prv_codigo, @prv_nombre_comercial, @prv_nit, @prv_contacto, @prv_direccion, @prv_telefono_oficina, @prv_email_empresa,
		 @usu_id, SYSDATETIME());

	SET @prv_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_proveedor_actualizar]
	@prv_id					INT,
	@prv_nombre_comercial	VARCHAR(128),
	@prv_nit				VARCHAR(16) = NULL,
	@prv_contacto			VARCHAR(128) = NULL,
	@prv_direccion			VARCHAR(128) = NULL,
	@prv_telefono_oficina	VARCHAR(16) = NULL,
	@prv_email_empresa		VARCHAR(64) = NULL,
	@usu_id					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_proveedor WHERE prv_id = @prv_id)
		THROW 51022, 'El proveedor indicado no existe.', 1;

	UPDATE dbo.inv_proveedor
	   SET prv_nombre_comercial = @prv_nombre_comercial,
		   prv_nit = @prv_nit,
		   prv_contacto = @prv_contacto,
		   prv_direccion = @prv_direccion,
		   prv_telefono_oficina = @prv_telefono_oficina,
		   prv_email_empresa = @prv_email_empresa,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE prv_id = @prv_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_proveedor_eliminar]
	@prv_id INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_proveedor WHERE prv_id = @prv_id)
		THROW 51022, 'El proveedor indicado no existe.', 1;

	UPDATE dbo.inv_proveedor
	   SET prv_estado = 'I',
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE prv_id = @prv_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_proveedor_consultar]
	@texto			VARCHAR(128) = NULL,
	@prv_estado		CHAR(1) = 'A',
	@pagina			INT = 1,
	@tamanio_pagina	INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT prv_id, prv_codigo, prv_nombre_comercial, prv_nit, prv_contacto,
		   prv_telefono_oficina, prv_email_empresa, prv_estado
	FROM dbo.inv_proveedor
	WHERE (@prv_estado IS NULL OR prv_estado = @prv_estado)
	  AND (@texto IS NULL
		   OR prv_codigo LIKE '%' + @texto + '%'
		   OR prv_nombre_comercial LIKE '%' + @texto + '%'
		   OR prv_nit LIKE '%' + @texto + '%')
	ORDER BY prv_nombre_comercial
	OFFSET (@pagina - 1) * @tamanio_pagina ROWS FETCH NEXT @tamanio_pagina ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_proveedor_consultar_por_id]
	@prv_id INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.inv_proveedor WHERE prv_id = @prv_id;
END;
GO

------------------------------------------------------------
-- gen_usuario (contraseña con hash + sal; ver también sp_seguridad_login
-- en 11_procedimientos_procesos.sql)
--
-- Aquí @usu_id siempre identifica la fila objetivo (el usuario sobre el que
-- se actúa), así que el usuario que ejecuta la acción se recibe como
-- @usu_id_accion para no chocar con ese nombre.
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_usuario_insertar]
	@usu_codigo		VARCHAR(32),
	@usu_usuario	VARCHAR(128),
	@usu_password	VARCHAR(256),
	@usu_email		VARCHAR(128) = NULL,
	@usu_id_accion	INT = NULL,
	@usu_id			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_usuario = @usu_usuario)
		THROW 51031, 'Ya existe un usuario con ese nombre de acceso.', 1;

	DECLARE @salt UNIQUEIDENTIFIER = NEWID();

	INSERT INTO dbo.gen_usuario
		(usu_codigo, usu_usuario, usu_password_hash, usu_password_salt, usu_email, InsUsuario, InsFechaHora)
	VALUES
		(@usu_codigo, @usu_usuario,
		 HASHBYTES('SHA2_256', CAST(@salt AS VARCHAR(36)) + @usu_password),
		 @salt, @usu_email, @usu_id_accion, SYSDATETIME());

	SET @usu_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_usuario_actualizar]
	@usu_id			INT,
	@usu_usuario	VARCHAR(128),
	@usu_email		VARCHAR(128) = NULL,
	@usu_id_accion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_id = @usu_id)
		THROW 51032, 'El usuario indicado no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_usuario = @usu_usuario AND usu_id <> @usu_id)
		THROW 51031, 'Ya existe otro usuario con ese nombre de acceso.', 1;

	UPDATE dbo.gen_usuario
	   SET usu_usuario = @usu_usuario,
		   usu_email = @usu_email,
		   UpdUsuario = @usu_id_accion,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @usu_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_usuario_cambiar_password]
	@usu_id				INT,
	@password_actual	VARCHAR(256),
	@password_nuevo		VARCHAR(256)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @salt UNIQUEIDENTIFIER, @hash VARBINARY(64);

	SELECT @salt = usu_password_salt, @hash = usu_password_hash
	FROM dbo.gen_usuario WHERE usu_id = @usu_id;

	IF @salt IS NULL
		THROW 51032, 'El usuario indicado no existe.', 1;

	IF HASHBYTES('SHA2_256', CAST(@salt AS VARCHAR(36)) + @password_actual) <> @hash
		THROW 51033, 'La contraseña actual no es correcta.', 1;

	DECLARE @salt_nuevo UNIQUEIDENTIFIER = NEWID();

	-- Es un cambio hecho por el propio usuario: UpdUsuario queda como el
	-- mismo @usu_id que se está actualizando.
	UPDATE dbo.gen_usuario
	   SET usu_password_hash = HASHBYTES('SHA2_256', CAST(@salt_nuevo AS VARCHAR(36)) + @password_nuevo),
		   usu_password_salt = @salt_nuevo,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @usu_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_usuario_eliminar]
	@usu_id			INT,
	@usu_id_accion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_id = @usu_id)
		THROW 51032, 'El usuario indicado no existe.', 1;

	UPDATE dbo.gen_usuario
	   SET usu_estado = 'I',
		   UpdUsuario = @usu_id_accion,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @usu_id;
END;
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

CREATE OR ALTER PROCEDURE [dbo].[sp_usuario_consultar]
	@usu_usuario	VARCHAR(128) = NULL,
	@usu_estado		CHAR(1) = 'A',
	@pagina			INT = 1,
	@tamanio_pagina	INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT usu_id, usu_codigo, usu_usuario, usu_email, usu_fecha_ingreso,
		   usu_bloqueado, usu_ultimo_login, usu_estado
	FROM dbo.gen_usuario
	WHERE (@usu_estado IS NULL OR usu_estado = @usu_estado)
	  AND (@usu_usuario IS NULL OR usu_usuario LIKE '%' + @usu_usuario + '%')
	ORDER BY usu_usuario
	OFFSET (@pagina - 1) * @tamanio_pagina ROWS FETCH NEXT @tamanio_pagina ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_usuario_consultar_por_id]
	@usu_id INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT usu_id, usu_codigo, usu_usuario, usu_email, usu_fecha_ingreso,
		   usu_bloqueado, usu_ultimo_login, usu_estado
	FROM dbo.gen_usuario
	WHERE usu_id = @usu_id;

	SELECT r.rol_id, r.rol_codigo, r.rol_nombre
	FROM dbo.sec_usuario_rol ur
	INNER JOIN dbo.sec_rol r ON r.rol_id = ur.rol_id
	WHERE ur.usu_id = @usu_id;
END;
GO

------------------------------------------------------------
-- inv_bodega
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_bodega_insertar]
	@bod_codigo			VARCHAR(8),
	@bod_descripcion	VARCHAR(128),
	@suc_id				INT,
	@usu_id				INT = NULL,
	@bod_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE suc_id = @suc_id AND bod_codigo = @bod_codigo)
		THROW 51041, 'Ya existe una bodega con ese código en la sucursal.', 1;

	INSERT INTO dbo.inv_bodega (bod_codigo, bod_descripcion, suc_id, InsUsuario, InsFechaHora)
	VALUES (@bod_codigo, @bod_descripcion, @suc_id, @usu_id, SYSDATETIME());

	SET @bod_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_bodega_actualizar]
	@bod_id				INT,
	@bod_descripcion	VARCHAR(128),
	@suc_id				INT,
	@usu_id				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE bod_id = @bod_id)
		THROW 51042, 'La bodega indicada no existe.', 1;

	UPDATE dbo.inv_bodega
	   SET bod_descripcion = @bod_descripcion,
		   suc_id = @suc_id,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE bod_id = @bod_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_bodega_eliminar]
	@bod_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE bod_id = @bod_id)
		THROW 51042, 'La bodega indicada no existe.', 1;

	UPDATE dbo.inv_bodega
	   SET bod_estado = 'I',
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE bod_id = @bod_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_bodega_consultar]
	@suc_id			INT = NULL,
	@bod_estado		CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT bod.bod_id, bod.bod_codigo, bod.bod_descripcion, bod.suc_id, suc.suc_descripcion, bod.bod_estado
	FROM dbo.inv_bodega bod
	INNER JOIN dbo.gen_sucursal suc ON suc.suc_id = bod.suc_id
	WHERE (@suc_id IS NULL OR bod.suc_id = @suc_id)
	  AND (@bod_estado IS NULL OR bod.bod_estado = @bod_estado)
	ORDER BY bod.bod_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_bodega_consultar_por_id]
	@bod_id INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.inv_bodega WHERE bod_id = @bod_id;
END;
GO

------------------------------------------------------------
-- bco_cuenta_bancaria
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_cuenta_bancaria_insertar]
	@bcb_numero_cuenta	VARCHAR(16),
	@bcb_descripcion	VARCHAR(64) = NULL,
	@gef_id				INT,
	@usu_id				INT = NULL,
	@bcb_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_numero_cuenta = @bcb_numero_cuenta)
		THROW 51051, 'Ya existe una cuenta bancaria con ese número.', 1;

	INSERT INTO dbo.bco_cuenta_bancaria (bcb_numero_cuenta, bcb_descripcion, gef_id, InsUsuario, InsFechaHora)
	VALUES (@bcb_numero_cuenta, @bcb_descripcion, @gef_id, @usu_id, SYSDATETIME());

	SET @bcb_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_cuenta_bancaria_actualizar]
	@bcb_id				INT,
	@bcb_descripcion	VARCHAR(64) = NULL,
	@gef_id				INT,
	@usu_id				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @bcb_id)
		THROW 51052, 'La cuenta bancaria indicada no existe.', 1;

	UPDATE dbo.bco_cuenta_bancaria
	   SET bcb_descripcion = @bcb_descripcion,
		   gef_id = @gef_id,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE bcb_id = @bcb_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_cuenta_bancaria_eliminar]
	@bcb_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @bcb_id)
		THROW 51052, 'La cuenta bancaria indicada no existe.', 1;

	UPDATE dbo.bco_cuenta_bancaria
	   SET bcb_estado = 'I',
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE bcb_id = @bcb_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_cuenta_bancaria_consultar]
	@bcb_estado CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT bcb.bcb_id, bcb.bcb_numero_cuenta, bcb.bcb_descripcion, bcb.gef_id, gef.gef_descripcion, bcb.bcb_estado
	FROM dbo.bco_cuenta_bancaria bcb
	INNER JOIN dbo.gen_entidad_financiera gef ON gef.gef_id = bcb.gef_id
	WHERE (@bcb_estado IS NULL OR bcb.bcb_estado = @bcb_estado)
	ORDER BY bcb.bcb_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_cuenta_bancaria_consultar_por_id]
	@bcb_id INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @bcb_id;
END;
GO

------------------------------------------------------------
-- cont_cuenta_contable
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_cuenta_contable_insertar]
	@cta_codigo				VARCHAR(20),
	@cta_nombre				VARCHAR(128),
	@cta_tipo				CHAR(1),
	@cta_naturaleza			CHAR(1),
	@cta_acepta_movimiento	BIT = 1,
	@cta_id_padre			INT = NULL,
	@usu_id					INT = NULL,
	@cta_id					INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_codigo = @cta_codigo)
		THROW 51061, 'Ya existe una cuenta contable con ese código.', 1;

	DECLARE @nivel INT = 1;
	IF @cta_id_padre IS NOT NULL
		SELECT @nivel = cta_nivel + 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @cta_id_padre;

	INSERT INTO dbo.cont_cuenta_contable
		(cta_codigo, cta_nombre, cta_tipo, cta_naturaleza, cta_acepta_movimiento, cta_id_padre, cta_nivel, InsUsuario, InsFechaHora)
	VALUES
		(@cta_codigo, @cta_nombre, @cta_tipo, @cta_naturaleza, @cta_acepta_movimiento, @cta_id_padre, @nivel, @usu_id, SYSDATETIME());

	SET @cta_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_cuenta_contable_actualizar]
	@cta_id					INT,
	@cta_nombre				VARCHAR(128),
	@cta_acepta_movimiento	BIT,
	@usu_id					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @cta_id)
		THROW 51062, 'La cuenta contable indicada no existe.', 1;

	UPDATE dbo.cont_cuenta_contable
	   SET cta_nombre = @cta_nombre,
		   cta_acepta_movimiento = @cta_acepta_movimiento,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE cta_id = @cta_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_cuenta_contable_eliminar]
	@cta_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @cta_id)
		THROW 51062, 'La cuenta contable indicada no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.cont_asiento_det WHERE cta_id = @cta_id)
		THROW 51063, 'No se puede inactivar: la cuenta ya tiene movimientos contables.', 1;

	UPDATE dbo.cont_cuenta_contable
	   SET cta_estado = 'I',
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE cta_id = @cta_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_cuenta_contable_consultar]
	@cta_tipo	CHAR(1) = NULL,
	@cta_estado	CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT cta_id, cta_codigo, cta_nombre, cta_tipo, cta_naturaleza,
		   cta_acepta_movimiento, cta_id_padre, cta_nivel, cta_estado
	FROM dbo.cont_cuenta_contable
	WHERE (@cta_tipo IS NULL OR cta_tipo = @cta_tipo)
	  AND (@cta_estado IS NULL OR cta_estado = @cta_estado)
	ORDER BY cta_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_cuenta_contable_consultar_por_id]
	@cta_id INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.cont_cuenta_contable WHERE cta_id = @cta_id;
END;
GO

------------------------------------------------------------
-- Seguridad: roles, permisos y asignaciones
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_rol_insertar]
	@rol_codigo	VARCHAR(32),
	@rol_nombre	VARCHAR(64),
	@usu_id		INT = NULL,
	@rol_id		INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.sec_rol WHERE rol_codigo = @rol_codigo)
		THROW 51071, 'Ya existe un rol con ese código.', 1;

	INSERT INTO dbo.sec_rol (rol_codigo, rol_nombre, InsUsuario, InsFechaHora)
	VALUES (@rol_codigo, @rol_nombre, @usu_id, SYSDATETIME());
	SET @rol_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_rol_actualizar]
	@rol_id		INT,
	@rol_nombre	VARCHAR(64),
	@usu_id		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.sec_rol WHERE rol_id = @rol_id)
		THROW 51072, 'El rol indicado no existe.', 1;

	UPDATE dbo.sec_rol
	   SET rol_nombre = @rol_nombre,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE rol_id = @rol_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_rol_eliminar]
	@rol_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.sec_rol WHERE rol_id = @rol_id)
		THROW 51072, 'El rol indicado no existe.', 1;

	UPDATE dbo.sec_rol
	   SET rol_estado = 'I',
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE rol_id = @rol_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_rol_consultar]
	@rol_estado CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;
	SELECT rol_id, rol_codigo, rol_nombre, rol_estado
	FROM dbo.sec_rol
	WHERE (@rol_estado IS NULL OR rol_estado = @rol_estado)
	ORDER BY rol_nombre;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_permiso_insertar]
	@per_modulo			VARCHAR(32),
	@per_codigo			VARCHAR(64),
	@per_descripcion	VARCHAR(128) = NULL,
	@usu_id				INT = NULL,
	@per_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_codigo = @per_codigo)
		THROW 51081, 'Ya existe un permiso con ese código.', 1;

	INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion, InsUsuario, InsFechaHora)
	VALUES (@per_modulo, @per_codigo, @per_descripcion, @usu_id, SYSDATETIME());

	SET @per_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_permiso_consultar]
	@per_modulo VARCHAR(32) = NULL,
	@per_estado CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;
	SELECT per_id, per_modulo, per_codigo, per_descripcion, per_estado
	FROM dbo.sec_permiso
	WHERE (@per_modulo IS NULL OR per_modulo = @per_modulo)
	  AND (@per_estado IS NULL OR per_estado = @per_estado)
	ORDER BY per_modulo, per_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_rol_asignar_permiso]
	@rol_id	INT,
	@per_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso WHERE rol_id = @rol_id AND per_id = @per_id)
		INSERT INTO dbo.sec_rol_permiso (rol_id, per_id, InsUsuario, InsFechaHora)
		VALUES (@rol_id, @per_id, @usu_id, SYSDATETIME());
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_rol_revocar_permiso]
	@rol_id INT,
	@per_id INT
AS
BEGIN
	SET NOCOUNT ON;
	DELETE FROM dbo.sec_rol_permiso WHERE rol_id = @rol_id AND per_id = @per_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_usuario_asignar_rol]
	@usu_id			INT,
	@rol_id			INT,
	@usu_id_accion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.sec_usuario_rol WHERE usu_id = @usu_id AND rol_id = @rol_id)
		INSERT INTO dbo.sec_usuario_rol (usu_id, rol_id, InsUsuario, InsFechaHora)
		VALUES (@usu_id, @rol_id, @usu_id_accion, SYSDATETIME());
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_usuario_revocar_rol]
	@usu_id INT,
	@rol_id INT
AS
BEGIN
	SET NOCOUNT ON;
	DELETE FROM dbo.sec_usuario_rol WHERE usu_id = @usu_id AND rol_id = @rol_id;
END;
GO

------------------------------------------------------------
-- Consulta de documentos (la creación está en el script de procesos)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paDocumentoConsultar]
	@tdo_id			INT = NULL,
	@cli_id			INT = NULL,
	@prv_id			INT = NULL,
	@fecha_desde	DATE = NULL,
	@fecha_hasta	DATE = NULL,
	@enc_estado		CHAR(1) = NULL,
	@pagina			INT = 1,
	@tamanio_pagina	INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT enca.enc_id, enca.enc_fecha_docto, enca.enc_serie_docto, enca.enc_numero_docto,
		   tdoc.tdo_codigo, tdoc.tdo_descripcion, enca.cli_id, enca.prv_id, enca.enc_monto_total, enca.enc_estado,
		   clie.cli_nombres, clie.cli_apellidos, prov.prv_nombre_comercial
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tdoc ON tdoc.tdo_id = enca.tdo_id
	LEFT JOIN dbo.pos_cliente clie ON clie.cli_id = enca.cli_id
	LEFT JOIN dbo.inv_proveedor prov ON prov.prv_id = enca.prv_id
	WHERE (@tdo_id IS NULL OR enca.tdo_id = @tdo_id)
	  AND (@cli_id IS NULL OR enca.cli_id = @cli_id)
	  AND (@prv_id IS NULL OR enca.prv_id = @prv_id)
	  AND (@fecha_desde IS NULL OR enca.enc_fecha_docto >= @fecha_desde)
	  AND (@fecha_hasta IS NULL OR enca.enc_fecha_docto <= @fecha_hasta)
	  AND (@enc_estado IS NULL OR enca.enc_estado = @enc_estado)
	ORDER BY enca.enc_fecha_docto DESC, enca.enc_id DESC
	OFFSET (@pagina - 1) * @tamanio_pagina ROWS FETCH NEXT @tamanio_pagina ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_documento_consultar_por_id]
	@enc_id INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT enc.*, tdo.tdo_descripcion, tdo.tdo_naturaleza
	FROM dbo.inv_documento_enc enc
	INNER JOIN dbo.inv_documento_tipo tdo ON tdo.tdo_id = enc.tdo_id
	WHERE enc.enc_id = @enc_id;

	SELECT det.*
	FROM dbo.inv_documento_det det
	WHERE det.enc_id = @enc_id
	ORDER BY det.det_item;
END;
GO

-------------------------------------------------------------
-- pos_vendedor
-- Nota de nomenclatura: estos procedimientos usan el estándar "pa" +
-- PascalCase (paVendedorInsertar, ...) a solicitud explícita, distinto
-- del "sp_<entidad>_<accion>" usado en el resto del archivo. Es el único
-- módulo con este estándar por ahora; los demás procedimientos existentes
-- no se renombraron para no romper las llamadas ya desplegadas.
-------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paVendedorInsertar]
	@pve_codigo			VARCHAR(16),
	@pve_nombres		VARCHAR(64),
	@pve_apellidos		VARCHAR(64) = NULL,
	@pve_fecha_ingreso	DATE = NULL,
	@pve_porc_comision	NUMERIC(8, 2) = 0,
	@usu_id				INT = NULL,
	@pve_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.pos_vendedor WHERE pve_codigo = @pve_codigo)
		THROW 51091, 'Ya existe un vendedor con ese código.', 1;

	INSERT INTO dbo.pos_vendedor
		(pve_codigo, pve_nombres, pve_apellidos, pve_fecha_ingreso, pve_porc_comision, InsUsuario, InsFechaHora)
	VALUES
		(@pve_codigo, @pve_nombres, @pve_apellidos, @pve_fecha_ingreso, @pve_porc_comision, @usu_id, SYSDATETIME());

	SET @pve_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paVendedorActualizar]
	@pve_id				INT,
	@pve_nombres		VARCHAR(64),
	@pve_apellidos		VARCHAR(64) = NULL,
	@pve_fecha_ingreso	DATE = NULL,
	@pve_porc_comision	NUMERIC(8, 2) = 0,
	@usu_id				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_vendedor WHERE pve_id = @pve_id)
		THROW 51092, 'El vendedor indicado no existe.', 1;

	UPDATE dbo.pos_vendedor
	   SET pve_nombres = @pve_nombres,
		   pve_apellidos = @pve_apellidos,
		   pve_fecha_ingreso = @pve_fecha_ingreso,
		   pve_porc_comision = @pve_porc_comision,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pve_id = @pve_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paVendedorEliminar]
	@pve_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_vendedor WHERE pve_id = @pve_id)
		THROW 51092, 'El vendedor indicado no existe.', 1;

	UPDATE dbo.pos_vendedor
	   SET pve_estado = 'I',
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pve_id = @pve_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paVendedorConsultar]
	@pve_estado CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;
	SELECT pve_id, pve_codigo, pve_nombres, pve_apellidos, pve_fecha_ingreso, pve_porc_comision, pve_estado
	FROM dbo.pos_vendedor
	WHERE (@pve_estado IS NULL OR pve_estado = @pve_estado)
	ORDER BY pve_nombres, pve_apellidos;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paVendedorConsultarPorId]
	@pve_id INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.pos_vendedor WHERE pve_id = @pve_id;
END;
GO
