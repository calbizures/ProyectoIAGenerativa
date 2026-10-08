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

-- Opciones requeridas por los índices filtrados (p. ej. enc_numero_unico,
-- IdEmpleado) y guardadas con cada procedimiento: sqlcmd las apaga por defecto.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- inv_producto
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paProductoInsertar]
	@ProCodigo				VARCHAR(64),
	@ProDescripcion		VARCHAR(256),
	@PrtId					INT,
	@ProTipoItem			CHAR(1) = 'B',
	@ProManejaExistencia	BIT = 1,
	@ProIdPadre			INT = NULL,
	@UsuId					INT = NULL,
	@ProId					INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_codigo = @ProCodigo)
		THROW 51001, 'Ya existe un producto con ese código.', 1;

	INSERT INTO dbo.inv_producto
		(pro_codigo, pro_descripcion, prt_id, pro_tipo_item, pro_maneja_existencia, pro_id_padre, InsUsuario, InsFechaHora)
	VALUES
		(@ProCodigo, @ProDescripcion, @PrtId, @ProTipoItem, @ProManejaExistencia, @ProIdPadre, @UsuId, SYSDATETIME());

	SET @ProId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoActualizar]
	@ProId					INT,
	@ProCodigo				VARCHAR(64),
	@ProDescripcion		VARCHAR(256),
	@PrtId					INT,
	@ProTipoItem			CHAR(1),
	@ProManejaExistencia	BIT,
	@ProIdPadre			INT = NULL,
	@ProPtjeRentabilidad	NUMERIC(8, 2) = NULL,
	@UsuId					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_id = @ProId)
		THROW 51002, 'El producto indicado no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_codigo = @ProCodigo AND pro_id <> @ProId)
		THROW 51001, 'Ya existe otro producto con ese código.', 1;

	UPDATE dbo.inv_producto
	   SET pro_codigo = @ProCodigo,
		   pro_descripcion = @ProDescripcion,
		   prt_id = @PrtId,
		   pro_tipo_item = @ProTipoItem,
		   pro_maneja_existencia = @ProManejaExistencia,
		   pro_id_padre = @ProIdPadre,
		   pro_ptje_rentabilidad = @ProPtjeRentabilidad,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pro_id = @ProId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoEliminar]
	@ProId INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto WHERE pro_id = @ProId)
		THROW 51002, 'El producto indicado no existe.', 1;

	UPDATE dbo.inv_producto
	   SET pro_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE pro_id = @ProId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoConsultar]
	@ProCodigo			VARCHAR(64) = NULL,
	@ProDescripcion	VARCHAR(256) = NULL,
	@PrtId				INT = NULL,
	@ProEstado			CHAR(1) = 'A',
	@Pagina				INT = 1,
	@TamanioPagina		INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT prod.pro_id, prod.pro_codigo, prod.pro_descripcion, prod.pro_tipo_item,
		   prod.pro_maneja_existencia, prod.pro_total_cantidad, prod.pro_costo_unitario,
		   prod.prt_id, ptip.prt_descripcion, prod.pro_estado
	FROM dbo.inv_producto prod
	INNER JOIN dbo.inv_producto_tipo ptip ON ptip.prt_id = prod.prt_id
	WHERE (@ProCodigo IS NULL OR prod.pro_codigo LIKE '%' + @ProCodigo + '%')
	  AND (@ProDescripcion IS NULL OR prod.pro_descripcion LIKE '%' + @ProDescripcion + '%')
	  AND (@PrtId IS NULL OR prod.prt_id = @PrtId)
	  AND (@ProEstado IS NULL OR prod.pro_estado = @ProEstado)
	ORDER BY prod.pro_descripcion
	OFFSET (@Pagina - 1) * @TamanioPagina ROWS FETCH NEXT @TamanioPagina ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoConsultarPorId]
	@ProId INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT prod.*, ptip.prt_descripcion
	FROM dbo.inv_producto prod
	INNER JOIN dbo.inv_producto_tipo ptip ON ptip.prt_id = prod.prt_id
	WHERE prod.pro_id = @ProId;

	SELECT exis.bod_id, bode.bod_descripcion, exis.existencia
	FROM dbo.inv_producto_existencia_bodega exis
	INNER JOIN dbo.inv_bodega bode ON bode.bod_id = exis.bod_id
	WHERE exis.pro_id = @ProId;

	SELECT prec.ppr_id, prec.bod_id, prec.ppr_precio_unitario_venta, prec.ppr_vigencia_desde, prec.ppr_vigencia_hasta, prec.mon_id
	FROM dbo.inv_producto_precio prec
	WHERE prec.pro_id = @ProId AND prec.ppr_estado = 'A';
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

CREATE OR ALTER PROCEDURE [dbo].[paProductoTipoCaracteristicaInsertar]
	@ptc_codigo			VARCHAR(16),
	@ptc_descripcion	VARCHAR(64),
	@ptc_orden			INT = 0,
	@usu_id				INT = NULL,
	@ptc_id				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.inv_producto_tipo_caracteristica WHERE ptc_codigo = @ptc_codigo)
		THROW 51121, 'Ya existe un tipo de característica con ese código.', 1;

	INSERT INTO dbo.inv_producto_tipo_caracteristica
		(ptc_codigo, ptc_descripcion, ptc_orden, ptc_estado, InsUsuario, InsFechaHora)
	VALUES
		(@ptc_codigo, @ptc_descripcion, @ptc_orden, 'A', @usu_id, SYSDATETIME());

	SET @ptc_id = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoTipoCaracteristicaActualizar]
	@ptc_id				INT,
	@ptc_codigo			VARCHAR(16),
	@ptc_descripcion	VARCHAR(64),
	@ptc_orden			INT,
	@usu_id				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto_tipo_caracteristica WHERE ptc_id = @ptc_id)
		THROW 51122, 'El tipo de característica indicado no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.inv_producto_tipo_caracteristica WHERE ptc_codigo = @ptc_codigo AND ptc_id <> @ptc_id)
		THROW 51121, 'Ya existe otro tipo de característica con ese código.', 1;

	UPDATE dbo.inv_producto_tipo_caracteristica
	   SET ptc_codigo = @ptc_codigo,
		   ptc_descripcion = @ptc_descripcion,
		   ptc_orden = @ptc_orden,
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE ptc_id = @ptc_id;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProductoTipoCaracteristicaEliminar]
	@ptc_id	INT,
	@usu_id	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_producto_tipo_caracteristica WHERE ptc_id = @ptc_id)
		THROW 51122, 'El tipo de característica indicado no existe.', 1;

	UPDATE dbo.inv_producto_tipo_caracteristica
	   SET ptc_estado = 'I',
		   UpdUsuario = @usu_id,
		   UpdFechaHora = SYSDATETIME()
	 WHERE ptc_id = @ptc_id;
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
CREATE OR ALTER PROCEDURE [dbo].[paClienteInsertar]
	@CliCodigo				VARCHAR(32),
	@CliNombres			VARCHAR(64),
	@CliApellidos			VARCHAR(64) = NULL,
	@CliDireccion			VARCHAR(128) = NULL,
	@CliTelefonoCelular	VARCHAR(16) = NULL,
	@CliNit				VARCHAR(16) = NULL,
	@CliEmail				VARCHAR(64) = NULL,
	@CliLimiteCredito		DECIMAL(14, 2) = 0,
	@CliDireccionPais		INT = NULL,
	@CliDireccionEstado	INT = NULL,
	@CliDireccionProvincia INT = NULL,
	@UsuId					INT = NULL,
	@CliId					INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_codigo = @CliCodigo)
		THROW 51011, 'Ya existe un cliente con ese código.', 1;

	IF @CliNit IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_nit = @CliNit)
		THROW 51012, 'Ya existe un cliente con ese NIT.', 1;

	INSERT INTO dbo.pos_cliente
		(cli_codigo, cli_nombres, cli_apellidos, cli_direccion, cli_telefono_celular,
		 cli_nit, cli_email, cli_limite_credito, cli_direccion_pais, cli_direccion_estado, cli_direccion_provincia,
		 InsUsuario, InsFechaHora)
	VALUES
		(@CliCodigo, @CliNombres, @CliApellidos, @CliDireccion, @CliTelefonoCelular,
		 @CliNit, @CliEmail, @CliLimiteCredito, @CliDireccionPais, @CliDireccionEstado, @CliDireccionProvincia,
		 @UsuId, SYSDATETIME());

	SET @CliId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paClienteActualizar]
	@CliId					INT,
	@CliNombres			VARCHAR(64),
	@CliApellidos			VARCHAR(64) = NULL,
	@CliDireccion			VARCHAR(128) = NULL,
	@CliTelefonoCelular	VARCHAR(16) = NULL,
	@CliNit				VARCHAR(16) = NULL,
	@CliEmail				VARCHAR(64) = NULL,
	@CliLimiteCredito		DECIMAL(14, 2) = 0,
	@UsuId					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_id = @CliId)
		THROW 51013, 'El cliente indicado no existe.', 1;

	IF @CliNit IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_nit = @CliNit AND cli_id <> @CliId)
		THROW 51012, 'Ya existe otro cliente con ese NIT.', 1;

	UPDATE dbo.pos_cliente
	   SET cli_nombres = @CliNombres,
		   cli_apellidos = @CliApellidos,
		   cli_direccion = @CliDireccion,
		   cli_telefono_celular = @CliTelefonoCelular,
		   cli_nit = @CliNit,
		   cli_email = @CliEmail,
		   cli_limite_credito = @CliLimiteCredito,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE cli_id = @CliId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paClienteEliminar]
	@CliId INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.pos_cliente WHERE cli_id = @CliId)
		THROW 51013, 'El cliente indicado no existe.', 1;

	UPDATE dbo.pos_cliente
	   SET cli_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE cli_id = @CliId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paClienteConsultar]
	@Texto			VARCHAR(128) = NULL,	-- busca en código, nombres, apellidos o NIT
	@CliEstado		CHAR(1) = 'A',
	@Pagina			INT = 1,
	@TamanioPagina	INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT cli_id, cli_codigo, cli_nombres, cli_apellidos, cli_nit, cli_email,
		   cli_telefono_celular, cli_limite_credito, cli_estado
	FROM dbo.pos_cliente
	WHERE (@CliEstado IS NULL OR cli_estado = @CliEstado)
	  AND (@Texto IS NULL
		   OR cli_codigo LIKE '%' + @Texto + '%'
		   OR cli_nombres LIKE '%' + @Texto + '%'
		   OR cli_apellidos LIKE '%' + @Texto + '%'
		   OR cli_nit LIKE '%' + @Texto + '%')
	ORDER BY cli_nombres, cli_apellidos
	OFFSET (@Pagina - 1) * @TamanioPagina ROWS FETCH NEXT @TamanioPagina ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paClienteConsultarPorId]
	@CliId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.pos_cliente WHERE cli_id = @CliId;
END;
GO

------------------------------------------------------------
-- inv_proveedor
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paProveedorInsertar]
	@PrvCodigo				VARCHAR(16),
	@PrvNombreComercial	VARCHAR(128),
	@PrvNit				VARCHAR(16) = NULL,
	@PrvContacto			VARCHAR(128) = NULL,
	@PrvDireccion			VARCHAR(128) = NULL,
	@PrvTelefonoOficina	VARCHAR(16) = NULL,
	@PrvEmailEmpresa		VARCHAR(64) = NULL,
	@UsuId					INT = NULL,
	@PrvId					INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.inv_proveedor WHERE prv_codigo = @PrvCodigo)
		THROW 51021, 'Ya existe un proveedor con ese código.', 1;

	INSERT INTO dbo.inv_proveedor
		(prv_codigo, prv_nombre_comercial, prv_nit, prv_contacto, prv_direccion, prv_telefono_oficina, prv_email_empresa,
		 InsUsuario, InsFechaHora)
	VALUES
		(@PrvCodigo, @PrvNombreComercial, @PrvNit, @PrvContacto, @PrvDireccion, @PrvTelefonoOficina, @PrvEmailEmpresa,
		 @UsuId, SYSDATETIME());

	SET @PrvId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProveedorActualizar]
	@PrvId					INT,
	@PrvNombreComercial	VARCHAR(128),
	@PrvNit				VARCHAR(16) = NULL,
	@PrvContacto			VARCHAR(128) = NULL,
	@PrvDireccion			VARCHAR(128) = NULL,
	@PrvTelefonoOficina	VARCHAR(16) = NULL,
	@PrvEmailEmpresa		VARCHAR(64) = NULL,
	@UsuId					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_proveedor WHERE prv_id = @PrvId)
		THROW 51022, 'El proveedor indicado no existe.', 1;

	UPDATE dbo.inv_proveedor
	   SET prv_nombre_comercial = @PrvNombreComercial,
		   prv_nit = @PrvNit,
		   prv_contacto = @PrvContacto,
		   prv_direccion = @PrvDireccion,
		   prv_telefono_oficina = @PrvTelefonoOficina,
		   prv_email_empresa = @PrvEmailEmpresa,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE prv_id = @PrvId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProveedorEliminar]
	@PrvId INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_proveedor WHERE prv_id = @PrvId)
		THROW 51022, 'El proveedor indicado no existe.', 1;

	UPDATE dbo.inv_proveedor
	   SET prv_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE prv_id = @PrvId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProveedorConsultar]
	@Texto			VARCHAR(128) = NULL,
	@PrvEstado		CHAR(1) = 'A',
	@Pagina			INT = 1,
	@TamanioPagina	INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT prv_id, prv_codigo, prv_nombre_comercial, prv_nit, prv_contacto,
		   prv_telefono_oficina, prv_email_empresa, prv_estado
	FROM dbo.inv_proveedor
	WHERE (@PrvEstado IS NULL OR prv_estado = @PrvEstado)
	  AND (@Texto IS NULL
		   OR prv_codigo LIKE '%' + @Texto + '%'
		   OR prv_nombre_comercial LIKE '%' + @Texto + '%'
		   OR prv_nit LIKE '%' + @Texto + '%')
	ORDER BY prv_nombre_comercial
	OFFSET (@Pagina - 1) * @TamanioPagina ROWS FETCH NEXT @TamanioPagina ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paProveedorConsultarPorId]
	@PrvId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.inv_proveedor WHERE prv_id = @PrvId;
END;
GO

------------------------------------------------------------
-- gen_usuario (contraseña con hash + sal; ver también paSeguridadLogin
-- en 11_procedimientos_procesos.sql)
--
-- Aquí @usu_id siempre identifica la fila objetivo (el usuario sobre el que
-- se actúa), así que el usuario que ejecuta la acción se recibe como
-- @usu_id_accion para no chocar con ese nombre.
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paUsuarioInsertar]
	@UsuCodigo		VARCHAR(32),
	@UsuUsuario	VARCHAR(128),
	@UsuPassword	VARCHAR(256),
	@UsuEmail		VARCHAR(128) = NULL,
	@UsuIdAccion	INT = NULL,
	@UsuId			INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_usuario = @UsuUsuario)
		THROW 51031, 'Ya existe un usuario con ese nombre de acceso.', 1;

	DECLARE @salt UNIQUEIDENTIFIER = NEWID();

	INSERT INTO dbo.gen_usuario
		(usu_codigo, usu_usuario, usu_password_hash, usu_password_salt, usu_email, InsUsuario, InsFechaHora)
	VALUES
		(@UsuCodigo, @UsuUsuario,
		 HASHBYTES('SHA2_256', CAST(@salt AS VARCHAR(36)) + @UsuPassword),
		 @salt, @UsuEmail, @UsuIdAccion, SYSDATETIME());

	SET @UsuId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioActualizar]
	@UsuId			INT,
	@UsuUsuario	VARCHAR(128),
	@UsuEmail		VARCHAR(128) = NULL,
	@UsuIdAccion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_id = @UsuId)
		THROW 51032, 'El usuario indicado no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_usuario = @UsuUsuario AND usu_id <> @UsuId)
		THROW 51031, 'Ya existe otro usuario con ese nombre de acceso.', 1;

	UPDATE dbo.gen_usuario
	   SET usu_usuario = @UsuUsuario,
		   usu_email = @UsuEmail,
		   UpdUsuario = @UsuIdAccion,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @UsuId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioPasswordCambiar]
	@UsuId				INT,
	@PasswordActual	VARCHAR(256),
	@PasswordNuevo		VARCHAR(256)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @salt UNIQUEIDENTIFIER, @hash VARBINARY(64);

	SELECT @salt = usu_password_salt, @hash = usu_password_hash
	FROM dbo.gen_usuario WHERE usu_id = @UsuId;

	IF @salt IS NULL
		THROW 51032, 'El usuario indicado no existe.', 1;

	IF HASHBYTES('SHA2_256', CAST(@salt AS VARCHAR(36)) + @PasswordActual) <> @hash
		THROW 51033, 'La contraseña actual no es correcta.', 1;

	DECLARE @salt_nuevo UNIQUEIDENTIFIER = NEWID();

	-- Es un cambio hecho por el propio usuario: UpdUsuario queda como el
	-- mismo @usu_id que se está actualizando.
	UPDATE dbo.gen_usuario
	   SET usu_password_hash = HASHBYTES('SHA2_256', CAST(@salt_nuevo AS VARCHAR(36)) + @PasswordNuevo),
		   usu_password_salt = @salt_nuevo,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @UsuId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioEliminar]
	@UsuId			INT,
	@UsuIdAccion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.gen_usuario WHERE usu_id = @UsuId)
		THROW 51032, 'El usuario indicado no existe.', 1;

	UPDATE dbo.gen_usuario
	   SET usu_estado = 'I',
		   UpdUsuario = @UsuIdAccion,
		   UpdFechaHora = SYSDATETIME()
	 WHERE usu_id = @UsuId;
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

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioConsultar]
	@UsuUsuario	VARCHAR(128) = NULL,
	@UsuEstado		CHAR(1) = 'A',
	@Pagina			INT = 1,
	@TamanioPagina	INT = 50
AS
BEGIN
	SET NOCOUNT ON;

	SELECT usu_id, usu_codigo, usu_usuario, usu_email, usu_fecha_ingreso,
		   usu_bloqueado, usu_ultimo_login, usu_estado
	FROM dbo.gen_usuario
	WHERE (@UsuEstado IS NULL OR usu_estado = @UsuEstado)
	  AND (@UsuUsuario IS NULL OR usu_usuario LIKE '%' + @UsuUsuario + '%')
	ORDER BY usu_usuario
	OFFSET (@Pagina - 1) * @TamanioPagina ROWS FETCH NEXT @TamanioPagina ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioConsultarPorId]
	@UsuId INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT usu_id, usu_codigo, usu_usuario, usu_email, usu_fecha_ingreso,
		   usu_bloqueado, usu_ultimo_login, usu_estado
	FROM dbo.gen_usuario
	WHERE usu_id = @UsuId;

	SELECT srol.rol_id, srol.rol_codigo, srol.rol_nombre
	FROM dbo.sec_usuario_rol urol
	INNER JOIN dbo.sec_rol srol ON srol.rol_id = urol.rol_id
	WHERE urol.usu_id = @UsuId;
END;
GO

------------------------------------------------------------
-- inv_bodega
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paBodegaInsertar]
	@BodCodigo			VARCHAR(8),
	@BodDescripcion	VARCHAR(128),
	@SucId				INT,
	@UsuId				INT = NULL,
	@BodId				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE suc_id = @SucId AND bod_codigo = @BodCodigo)
		THROW 51041, 'Ya existe una bodega con ese código en la sucursal.', 1;

	INSERT INTO dbo.inv_bodega (bod_codigo, bod_descripcion, suc_id, InsUsuario, InsFechaHora)
	VALUES (@BodCodigo, @BodDescripcion, @SucId, @UsuId, SYSDATETIME());

	SET @BodId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBodegaActualizar]
	@BodId				INT,
	@BodDescripcion	VARCHAR(128),
	@SucId				INT,
	@UsuId				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE bod_id = @BodId)
		THROW 51042, 'La bodega indicada no existe.', 1;

	UPDATE dbo.inv_bodega
	   SET bod_descripcion = @BodDescripcion,
		   suc_id = @SucId,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE bod_id = @BodId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBodegaEliminar]
	@BodId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.inv_bodega WHERE bod_id = @BodId)
		THROW 51042, 'La bodega indicada no existe.', 1;

	UPDATE dbo.inv_bodega
	   SET bod_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE bod_id = @BodId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBodegaListar]
	@SucId			INT = NULL,
	@BodEstado		CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT bode.bod_id, bode.bod_codigo, bode.bod_descripcion, bode.suc_id, sucu.suc_descripcion, bode.bod_estado
	FROM dbo.inv_bodega bode
	INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = bode.suc_id
	WHERE (@SucId IS NULL OR bode.suc_id = @SucId)
	  AND (@BodEstado IS NULL OR bode.bod_estado = @BodEstado)
	ORDER BY bode.bod_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paBodegaConsultarPorId]
	@BodId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.inv_bodega WHERE bod_id = @BodId;
END;
GO

------------------------------------------------------------
-- bco_cuenta_bancaria
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCuentaBancariaInsertar]
	@BcbNumeroCuenta	VARCHAR(16),
	@BcbDescripcion	VARCHAR(64) = NULL,
	@GefId				INT,
	@UsuId				INT = NULL,
	@BcbId				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_numero_cuenta = @BcbNumeroCuenta)
		THROW 51051, 'Ya existe una cuenta bancaria con ese número.', 1;

	INSERT INTO dbo.bco_cuenta_bancaria (bcb_numero_cuenta, bcb_descripcion, gef_id, InsUsuario, InsFechaHora)
	VALUES (@BcbNumeroCuenta, @BcbDescripcion, @GefId, @UsuId, SYSDATETIME());

	SET @BcbId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaBancariaActualizar]
	@BcbId				INT,
	@BcbDescripcion	VARCHAR(64) = NULL,
	@GefId				INT,
	@UsuId				INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId)
		THROW 51052, 'La cuenta bancaria indicada no existe.', 1;

	UPDATE dbo.bco_cuenta_bancaria
	   SET bcb_descripcion = @BcbDescripcion,
		   gef_id = @GefId,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE bcb_id = @BcbId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaBancariaEliminar]
	@BcbId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId)
		THROW 51052, 'La cuenta bancaria indicada no existe.', 1;

	UPDATE dbo.bco_cuenta_bancaria
	   SET bcb_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE bcb_id = @BcbId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaBancariaConsultar]
	@BcbEstado CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT cuba.bcb_id, cuba.bcb_numero_cuenta, cuba.bcb_descripcion, cuba.gef_id, enti.gef_descripcion, cuba.bcb_estado
	FROM dbo.bco_cuenta_bancaria cuba
	INNER JOIN dbo.gen_entidad_financiera enti ON enti.gef_id = cuba.gef_id
	WHERE (@BcbEstado IS NULL OR cuba.bcb_estado = @BcbEstado)
	ORDER BY cuba.bcb_descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaBancariaConsultarPorId]
	@BcbId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.bco_cuenta_bancaria WHERE bcb_id = @BcbId;
END;
GO

------------------------------------------------------------
-- cont_cuenta_contable
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableInsertar]
	@CtaCodigo				VARCHAR(20),
	@CtaNombre				VARCHAR(128),
	@CtaTipo				CHAR(1),
	@CtaNaturaleza			CHAR(1),
	@CtaAceptaMovimiento	BIT = 1,
	@CtaIdPadre			INT = NULL,
	@UsuId					INT = NULL,
	@CtaId					INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_codigo = @CtaCodigo)
		THROW 51061, 'Ya existe una cuenta contable con ese código.', 1;

	DECLARE @nivel INT = 1;
	IF @CtaIdPadre IS NOT NULL
		SELECT @nivel = cta_nivel + 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaIdPadre;

	INSERT INTO dbo.cont_cuenta_contable
		(cta_codigo, cta_nombre, cta_tipo, cta_naturaleza, cta_acepta_movimiento, cta_id_padre, cta_nivel, InsUsuario, InsFechaHora)
	VALUES
		(@CtaCodigo, @CtaNombre, @CtaTipo, @CtaNaturaleza, @CtaAceptaMovimiento, @CtaIdPadre, @nivel, @UsuId, SYSDATETIME());

	SET @CtaId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableActualizar]
	@CtaId					INT,
	@CtaNombre				VARCHAR(128),
	@CtaAceptaMovimiento	BIT,
	@UsuId					INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId)
		THROW 51062, 'La cuenta contable indicada no existe.', 1;

	UPDATE dbo.cont_cuenta_contable
	   SET cta_nombre = @CtaNombre,
		   cta_acepta_movimiento = @CtaAceptaMovimiento,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE cta_id = @CtaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableEliminar]
	@CtaId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId)
		THROW 51062, 'La cuenta contable indicada no existe.', 1;

	IF EXISTS (SELECT 1 FROM dbo.cont_asiento_det WHERE cta_id = @CtaId)
		THROW 51063, 'No se puede inactivar: la cuenta ya tiene movimientos contables.', 1;

	UPDATE dbo.cont_cuenta_contable
	   SET cta_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE cta_id = @CtaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableConsultar]
	@CtaTipo	CHAR(1) = NULL,
	@CtaEstado	CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;

	SELECT cta_id, cta_codigo, cta_nombre, cta_tipo, cta_naturaleza,
		   cta_acepta_movimiento, cta_id_padre, cta_nivel, cta_estado
	FROM dbo.cont_cuenta_contable
	WHERE (@CtaTipo IS NULL OR cta_tipo = @CtaTipo)
	  AND (@CtaEstado IS NULL OR cta_estado = @CtaEstado)
	ORDER BY cta_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCuentaContableConsultarPorId]
	@CtaId INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT * FROM dbo.cont_cuenta_contable WHERE cta_id = @CtaId;
END;
GO

------------------------------------------------------------
-- Seguridad: roles, permisos y asignaciones
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRolInsertar]
	@RolCodigo	VARCHAR(32),
	@RolNombre	VARCHAR(64),
	@UsuId		INT = NULL,
	@RolId		INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.sec_rol WHERE rol_codigo = @RolCodigo)
		THROW 51071, 'Ya existe un rol con ese código.', 1;

	INSERT INTO dbo.sec_rol (rol_codigo, rol_nombre, InsUsuario, InsFechaHora)
	VALUES (@RolCodigo, @RolNombre, @UsuId, SYSDATETIME());
	SET @RolId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRolActualizar]
	@RolId		INT,
	@RolNombre	VARCHAR(64),
	@UsuId		INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.sec_rol WHERE rol_id = @RolId)
		THROW 51072, 'El rol indicado no existe.', 1;

	UPDATE dbo.sec_rol
	   SET rol_nombre = @RolNombre,
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE rol_id = @RolId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRolEliminar]
	@RolId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.sec_rol WHERE rol_id = @RolId)
		THROW 51072, 'El rol indicado no existe.', 1;

	UPDATE dbo.sec_rol
	   SET rol_estado = 'I',
		   UpdUsuario = @UsuId,
		   UpdFechaHora = SYSDATETIME()
	 WHERE rol_id = @RolId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRolConsultar]
	@RolEstado CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;
	SELECT rol_id, rol_codigo, rol_nombre, rol_estado
	FROM dbo.sec_rol
	WHERE (@RolEstado IS NULL OR rol_estado = @RolEstado)
	ORDER BY rol_nombre;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paPermisoInsertar]
	@PerModulo			VARCHAR(32),
	@PerCodigo			VARCHAR(64),
	@PerDescripcion	VARCHAR(128) = NULL,
	@UsuId				INT = NULL,
	@PerId				INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	IF EXISTS (SELECT 1 FROM dbo.sec_permiso WHERE per_codigo = @PerCodigo)
		THROW 51081, 'Ya existe un permiso con ese código.', 1;

	INSERT INTO dbo.sec_permiso (per_modulo, per_codigo, per_descripcion, InsUsuario, InsFechaHora)
	VALUES (@PerModulo, @PerCodigo, @PerDescripcion, @UsuId, SYSDATETIME());

	SET @PerId = SCOPE_IDENTITY();
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paPermisoConsultar]
	@PerModulo VARCHAR(32) = NULL,
	@PerEstado CHAR(1) = 'A'
AS
BEGIN
	SET NOCOUNT ON;
	SELECT per_id, per_modulo, per_codigo, per_descripcion, per_estado
	FROM dbo.sec_permiso
	WHERE (@PerModulo IS NULL OR per_modulo = @PerModulo)
	  AND (@PerEstado IS NULL OR per_estado = @PerEstado)
	ORDER BY per_modulo, per_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRolPermisoAsignar]
	@RolId	INT,
	@PerId	INT,
	@UsuId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.sec_rol_permiso WHERE rol_id = @RolId AND per_id = @PerId)
		INSERT INTO dbo.sec_rol_permiso (rol_id, per_id, InsUsuario, InsFechaHora)
		VALUES (@RolId, @PerId, @UsuId, SYSDATETIME());
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRolPermisoRevocar]
	@RolId INT,
	@PerId INT
AS
BEGIN
	SET NOCOUNT ON;
	DELETE FROM dbo.sec_rol_permiso WHERE rol_id = @RolId AND per_id = @PerId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioRolAsignar]
	@UsuId			INT,
	@RolId			INT,
	@UsuIdAccion	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;

	IF NOT EXISTS (SELECT 1 FROM dbo.sec_usuario_rol WHERE usu_id = @UsuId AND rol_id = @RolId)
		INSERT INTO dbo.sec_usuario_rol (usu_id, rol_id, InsUsuario, InsFechaHora)
		VALUES (@UsuId, @RolId, @UsuIdAccion, SYSDATETIME());
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paUsuarioRolRevocar]
	@UsuId INT,
	@RolId INT
AS
BEGIN
	SET NOCOUNT ON;
	DELETE FROM dbo.sec_usuario_rol WHERE usu_id = @UsuId AND rol_id = @RolId;
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

CREATE OR ALTER PROCEDURE [dbo].[paDocumentoConsultarPorId]
	@EncId INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT enca.*, tipo.tdo_descripcion, tipo.tdo_naturaleza
	FROM dbo.inv_documento_enc enca
	INNER JOIN dbo.inv_documento_tipo tipo ON tipo.tdo_id = enca.tdo_id
	WHERE enca.enc_id = @EncId;

	SELECT deta.*
	FROM dbo.inv_documento_det deta
	WHERE deta.enc_id = @EncId
	ORDER BY deta.det_item;
END;
GO

------------------------------------------------------------
-- pos_cliente_plan_pagos (solo consulta; se usa como detalle informativo
-- al grabar una factura a crédito)
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paClientePlanPagosConsultar]
	@enc_id INT
AS
BEGIN
	SET NOCOUNT ON;

	SELECT cpp_id, cpp_nro_cuota, cpp_valor_cuota, cpp_saldo_cuota,
		   cpp_fecha_maxima_pago, cpp_fecha_real_pago, cpp_estado, enc_id, cli_id
	FROM dbo.pos_cliente_plan_pagos
	WHERE enc_id = @enc_id
	ORDER BY cpp_nro_cuota;
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
