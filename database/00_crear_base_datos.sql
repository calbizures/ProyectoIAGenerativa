/*
	ERP de Servicios Informáticos
	Script 00: Creación de la base de datos y configuración general.

	Notas de diseño:
	- Se renombra la base de datos de "texasdb" a "erp_db" para que el nombre
	  no quede atado a un negocio específico y el modelo pueda adaptarse a
	  distintos giros (ver database/README.md, sección "Cambios generales").
	- Compatibilidad y opciones alineadas a SQL Server 2019+ (nivel 150).
	- Ejecutar este script una sola vez; los siguientes scripts asumen que
	  la base ya existe y hacen USE [erp_db].
*/
IF DB_ID(N'erp_db') IS NULL
BEGIN
	CREATE DATABASE [erp_db];
END
GO

ALTER DATABASE [erp_db] SET COMPATIBILITY_LEVEL = 150;
GO

ALTER DATABASE [erp_db] SET ANSI_NULLS ON;
ALTER DATABASE [erp_db] SET ANSI_PADDING ON;
ALTER DATABASE [erp_db] SET ANSI_WARNINGS ON;
ALTER DATABASE [erp_db] SET ARITHABORT ON;
ALTER DATABASE [erp_db] SET CONCAT_NULL_YIELDS_NULL ON;
ALTER DATABASE [erp_db] SET QUOTED_IDENTIFIER ON;
ALTER DATABASE [erp_db] SET NUMERIC_ROUNDABORT OFF;
ALTER DATABASE [erp_db] SET RECURSIVE_TRIGGERS OFF;
ALTER DATABASE [erp_db] SET READ_COMMITTED_SNAPSHOT ON;
ALTER DATABASE [erp_db] SET RECOVERY SIMPLE;
GO

USE [erp_db];
GO
