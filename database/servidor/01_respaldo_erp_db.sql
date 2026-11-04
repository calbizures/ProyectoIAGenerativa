/*
================================================================================
 servidor/01_respaldo_erp_db.sql
 Respaldo completo de erp_db (hallazgo 2 de la auditoría del 02/11/2026).

 No es parte de instalar_01_al_NN.sql: lo corre quien administra el servidor,
 conectado como sysadmin.

 Qué hace:
   1. Crea dbo.paRespaldoBaseDatos en master: respaldo completo con CHECKSUM
      (y compresión cuando la edición la permite), nombre con fecha y hora, y
      RESTORE VERIFYONLY para comprobar que el archivo sirve.
   2. Saca un respaldo ahora mismo.
   3. Si el servidor tiene SQL Server Agent (no existe en Express) y
      @CrearTrabajo = 1, crea el trabajo "Respaldo erp_db" diario a las 23:30.
      En Express, programe en Windows (Programador de tareas):
        sqlcmd -S <servidor> -E -Q "EXEC master.dbo.paRespaldoBaseDatos @Carpeta = N'C:\Respaldos\'"

 Antes de correrlo, ajuste @Carpeta: debe existir en el SERVIDOR y SQL Server
 debe poder escribir en ella. En Docker (Linux) use /var/opt/mssql/backup/ y
 copie los archivos fuera del contenedor (docker cp), o monte un volumen.

 Importante:
   - Un respaldo en el mismo disco del servidor no protege de que se dañe el
     disco: copie los .bak a otro equipo o a la nube.
   - Pruebe de vez en cuando restaurar un respaldo en otra base (RESTORE
     DATABASE erp_db_prueba FROM DISK = ... WITH MOVE ...).
   - El modelo de recuperación queda como está (SIMPLE): se puede volver al
     último respaldo diario. Para no perder más de unos minutos hay que pasar
     a FULL y respaldar además el log cada 15-30 minutos; si se pasa a FULL
     sin respaldar el log, el archivo .ldf crece sin parar.
   - Los respaldos viejos no se borran solos: elimine los de más de 30 días.

 Se puede ejecutar más de una vez.
================================================================================
*/
USE master;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.paRespaldoBaseDatos
	@Carpeta		NVARCHAR(400),
	@BaseDatos		SYSNAME = N'erp_db'
AS
BEGIN
	SET NOCOUNT ON;
	IF DB_ID(@BaseDatos) IS NULL
		THROW 50001, 'La base de datos indicada no existe.', 1;
	IF RIGHT(@Carpeta, 1) NOT IN ('\', '/')
		SET @Carpeta += CASE WHEN CHARINDEX('/', @Carpeta) > 0 THEN '/' ELSE '\' END;

	DECLARE @archivo NVARCHAR(600) = @Carpeta + @BaseDatos + N'_'
		+ FORMAT(SYSDATETIME(), 'yyyyMMdd_HHmmss') + N'.bak';
	-- La compresión no existe en Express (EngineEdition 4).
	DECLARE @compresion NVARCHAR(20) = CASE WHEN CAST(SERVERPROPERTY('EngineEdition') AS INT) = 4 THEN N'' ELSE N', COMPRESSION' END;
	DECLARE @sql NVARCHAR(MAX) = N'BACKUP DATABASE ' + QUOTENAME(@BaseDatos)
		+ N' TO DISK = @archivo WITH INIT, CHECKSUM' + @compresion
		+ N', NAME = @nombre;';
	DECLARE @nombre NVARCHAR(128) = @BaseDatos + N' respaldo completo';

	EXEC sys.sp_executesql @sql, N'@archivo NVARCHAR(600), @nombre NVARCHAR(128)', @archivo, @nombre;
	RESTORE VERIFYONLY FROM DISK = @archivo WITH CHECKSUM;

	SELECT @archivo AS ArchivoRespaldo;
END;
GO

-- ===== Ajuste aquí =====
DECLARE @Carpeta		NVARCHAR(400) = N'/var/opt/mssql/backup/';	-- Windows: N'C:\Respaldos\'
DECLARE @CrearTrabajo	BIT = 1;
-- =======================

EXEC master.dbo.paRespaldoBaseDatos @Carpeta = @Carpeta;

IF @CrearTrabajo = 1
   AND CAST(SERVERPROPERTY('EngineEdition') AS INT) <> 4
   AND EXISTS (SELECT 1 FROM msdb.sys.objects WHERE name = 'sp_add_job')
   AND NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Respaldo erp_db')
BEGIN
	DECLARE @comando NVARCHAR(MAX) = N'EXEC master.dbo.paRespaldoBaseDatos @Carpeta = N''' + REPLACE(@Carpeta, '''', '''''') + N''';';
	EXEC msdb.dbo.sp_add_job @job_name = N'Respaldo erp_db', @description = N'Respaldo completo diario de erp_db.';
	EXEC msdb.dbo.sp_add_jobstep @job_name = N'Respaldo erp_db', @step_name = N'Respaldo completo',
		@subsystem = N'TSQL', @database_name = N'master', @command = @comando;
	EXEC msdb.dbo.sp_add_schedule @schedule_name = N'Diario 23:30', @freq_type = 4, @freq_interval = 1,
		@active_start_time = 233000;
	EXEC msdb.dbo.sp_attach_schedule @job_name = N'Respaldo erp_db', @schedule_name = N'Diario 23:30';
	EXEC msdb.dbo.sp_add_jobserver @job_name = N'Respaldo erp_db';
	PRINT 'Trabajo "Respaldo erp_db" creado: todos los días a las 23:30. Verifique que SQL Server Agent esté iniciado.';
END
ELSE IF @CrearTrabajo = 1 AND NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Respaldo erp_db')
	PRINT 'Este servidor no tiene SQL Server Agent: programe el respaldo con el Programador de tareas de Windows (vea el encabezado).';
GO
