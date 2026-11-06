/*
================================================================================
 73_ubicacion_geografica.sql
 Ubicación en cascada País › Departamento › Municipio (gen_pais › gen_estado ›
 gen_provincia) para ampliar la dirección de la compañía y de los empleados.

   1. Catálogo oficial de Guatemala (INE): 22 departamentos y 340 municipios
      con su código (departamento 01-22, municipio 01-nn dentro del
      departamento). Los registros que ya existen se conservan (mismo id) y
      se reconocen por nombre; solo se les corrige el código y el nombre.
   2. gen_compania.prov_id (municipio, nuevo) y rrhhEmpleado.prov_id (ya
      existía). Solo se guarda el municipio: el departamento y el país se
      obtienen de la relación, así no hay datos que se contradigan.
   3. Para desplegar o usar la dirección completa:
        vwGenUbicacion          municipio, departamento y país en una fila.
        fnGenDireccionCompleta  'dirección, municipio, departamento[, país]'.
   4. Mantenimiento del catálogo (General › Ubicación geográfica):
        paGenUbicacionConsultar (países, departamentos y municipios),
        paGenPaisGuardar, paGenDepartamentoGuardar, paGenMunicipioGuardar.
   5. paCompaniaConsultar/Guardar y paRrhhEmpleadoConsultarPorId/Guardar con
      el municipio y la dirección completa. En paRrhhEmpleadoGuardar,
      @ProvId = -1 (valor por omisión) conserva el municipio que ya tenía el
      empleado, para que la carga desde Excel no lo borre.

 Errores nuevos: 55901-55914.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Catálogo oficial de Guatemala
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.gen_pais WHERE pai_codigo_alfa2 = 'GT')
	INSERT INTO dbo.gen_pais (pai_nombre, pai_codigo_alfa2, pai_codigo_alfa3, pai_codigo_numero, pai_nacionalidad)
	VALUES ('Guatemala', 'GT', 'GTM', '320', 'Guatemalteca');
GO

DECLARE @gt INT = (SELECT pai_id FROM dbo.gen_pais WHERE pai_codigo_alfa2 = 'GT');
DECLARE @depto TABLE (codigo VARCHAR(2) PRIMARY KEY, nombre VARCHAR(128));
INSERT INTO @depto VALUES
('01', 'Guatemala'), ('02', 'El Progreso'), ('03', 'Sacatepéquez'), ('04', 'Chimaltenango'), ('05', 'Escuintla'),
('06', 'Santa Rosa'), ('07', 'Sololá'), ('08', 'Totonicapán'), ('09', 'Quetzaltenango'), ('10', 'Suchitepéquez'),
('11', 'Retalhuleu'), ('12', 'San Marcos'), ('13', 'Huehuetenango'), ('14', 'Quiché'), ('15', 'Baja Verapaz'),
('16', 'Alta Verapaz'), ('17', 'Petén'), ('18', 'Izabal'), ('19', 'Zacapa'), ('20', 'Chiquimula'),
('21', 'Jalapa'), ('22', 'Jutiapa');

-- Departamentos que ya existen: se reconocen por nombre (sin importar
-- tildes ni mayúsculas) o por el código oficial.
UPDATE esta
   SET est_codigo = ofic.codigo, est_nombre = ofic.nombre, UpdFechaHora = SYSDATETIME()
FROM dbo.gen_estado esta
INNER JOIN @depto ofic ON esta.est_nombre COLLATE Latin1_General_CI_AI = ofic.nombre COLLATE Latin1_General_CI_AI
WHERE esta.pai_id = @gt AND (esta.est_codigo <> ofic.codigo OR esta.est_nombre COLLATE Latin1_General_CS_AS <> ofic.nombre COLLATE Latin1_General_CS_AS)
  AND NOT EXISTS (SELECT 1 FROM dbo.gen_estado otro WHERE otro.pai_id = @gt AND otro.est_codigo = ofic.codigo AND otro.est_id <> esta.est_id);

INSERT INTO dbo.gen_estado (est_codigo, pai_id, est_nombre)
SELECT ofic.codigo, @gt, ofic.nombre
FROM @depto ofic
WHERE NOT EXISTS (SELECT 1 FROM dbo.gen_estado esta WHERE esta.pai_id = @gt AND esta.est_codigo = ofic.codigo);
GO

DECLARE @gt INT = (SELECT pai_id FROM dbo.gen_pais WHERE pai_codigo_alfa2 = 'GT');
DECLARE @muni TABLE (depto VARCHAR(2), codigo VARCHAR(2), nombre VARCHAR(128), PRIMARY KEY (depto, codigo));
INSERT INTO @muni (depto, codigo, nombre) VALUES
('01', '01', N'Guatemala'),
('01', '02', N'Santa Catarina Pinula'),
('01', '03', N'San José Pinula'),
('01', '04', N'San José del Golfo'),
('01', '05', N'Palencia'),
('01', '06', N'Chinautla'),
('01', '07', N'San Pedro Ayampuc'),
('01', '08', N'Mixco'),
('01', '09', N'San Pedro Sacatepéquez'),
('01', '10', N'San Juan Sacatepéquez'),
('01', '11', N'San Raymundo'),
('01', '12', N'Chuarrancho'),
('01', '13', N'Fraijanes'),
('01', '14', N'Amatitlán'),
('01', '15', N'Villa Nueva'),
('01', '16', N'Villa Canales'),
('01', '17', N'San Miguel Petapa'),
('02', '01', N'Guastatoya'),
('02', '02', N'Morazán'),
('02', '03', N'San Agustín Acasaguastlán'),
('02', '04', N'San Cristóbal Acasaguastlán'),
('02', '05', N'El Jícaro'),
('02', '06', N'Sansare'),
('02', '07', N'Sanarate'),
('02', '08', N'San Antonio La Paz'),
('03', '01', N'Antigua Guatemala'),
('03', '02', N'Jocotenango'),
('03', '03', N'Pastores'),
('03', '04', N'Sumpango'),
('03', '05', N'Santo Domingo Xenacoj'),
('03', '06', N'Santiago Sacatepéquez'),
('03', '07', N'San Bartolomé Milpas Altas'),
('03', '08', N'San Lucas Sacatepéquez'),
('03', '09', N'Santa Lucía Milpas Altas'),
('03', '10', N'Magdalena Milpas Altas'),
('03', '11', N'Santa María de Jesús'),
('03', '12', N'Ciudad Vieja'),
('03', '13', N'San Miguel Dueñas'),
('03', '14', N'Alotenango'),
('03', '15', N'San Antonio Aguas Calientes'),
('03', '16', N'Santa Catarina Barahona'),
('04', '01', N'Chimaltenango'),
('04', '02', N'San José Poaquil'),
('04', '03', N'San Martín Jilotepeque'),
('04', '04', N'San Juan Comalapa'),
('04', '05', N'Santa Apolonia'),
('04', '06', N'Tecpán Guatemala'),
('04', '07', N'Patzún'),
('04', '08', N'San Miguel Pochuta'),
('04', '09', N'Patzicía'),
('04', '10', N'Santa Cruz Balanyá'),
('04', '11', N'Acatenango'),
('04', '12', N'Yepocapa'),
('04', '13', N'San Andrés Itzapa'),
('04', '14', N'Parramos'),
('04', '15', N'Zaragoza'),
('04', '16', N'El Tejar'),
('05', '01', N'Escuintla'),
('05', '02', N'Santa Lucía Cotzumalguapa'),
('05', '03', N'La Democracia'),
('05', '04', N'Siquinalá'),
('05', '05', N'Masagua'),
('05', '06', N'Tiquisate'),
('05', '07', N'La Gomera'),
('05', '08', N'Guanagazapa'),
('05', '09', N'San José'),
('05', '10', N'Iztapa'),
('05', '11', N'Palín'),
('05', '12', N'San Vicente Pacaya'),
('05', '13', N'Nueva Concepción'),
('05', '14', N'Sipacate'),
('06', '01', N'Cuilapa'),
('06', '02', N'Barberena'),
('06', '03', N'Santa Rosa de Lima'),
('06', '04', N'Casillas'),
('06', '05', N'San Rafael Las Flores'),
('06', '06', N'Oratorio'),
('06', '07', N'San Juan Tecuaco'),
('06', '08', N'Chiquimulilla'),
('06', '09', N'Taxisco'),
('06', '10', N'Santa María Ixhuatán'),
('06', '11', N'Guazacapán'),
('06', '12', N'Santa Cruz Naranjo'),
('06', '13', N'Pueblo Nuevo Viñas'),
('06', '14', N'Nueva Santa Rosa'),
('07', '01', N'Sololá'),
('07', '02', N'San José Chacayá'),
('07', '03', N'Santa María Visitación'),
('07', '04', N'Santa Lucía Utatlán'),
('07', '05', N'Nahualá'),
('07', '06', N'Santa Catarina Ixtahuacán'),
('07', '07', N'Santa Clara La Laguna'),
('07', '08', N'Concepción'),
('07', '09', N'San Andrés Semetabaj'),
('07', '10', N'Panajachel'),
('07', '11', N'Santa Catarina Palopó'),
('07', '12', N'San Antonio Palopó'),
('07', '13', N'San Lucas Tolimán'),
('07', '14', N'Santa Cruz La Laguna'),
('07', '15', N'San Pablo La Laguna'),
('07', '16', N'San Marcos La Laguna'),
('07', '17', N'San Juan La Laguna'),
('07', '18', N'San Pedro La Laguna'),
('07', '19', N'Santiago Atitlán'),
('08', '01', N'Totonicapán'),
('08', '02', N'San Cristóbal Totonicapán'),
('08', '03', N'San Francisco El Alto'),
('08', '04', N'San Andrés Xecul'),
('08', '05', N'Momostenango'),
('08', '06', N'Santa María Chiquimula'),
('08', '07', N'Santa Lucía La Reforma'),
('08', '08', N'San Bartolo'),
('09', '01', N'Quetzaltenango'),
('09', '02', N'Salcajá'),
('09', '03', N'Olintepeque'),
('09', '04', N'San Carlos Sija'),
('09', '05', N'Sibilia'),
('09', '06', N'Cabricán'),
('09', '07', N'Cajolá'),
('09', '08', N'San Miguel Sigüilá'),
('09', '09', N'San Juan Ostuncalco'),
('09', '10', N'San Mateo'),
('09', '11', N'Concepción Chiquirichapa'),
('09', '12', N'San Martín Sacatepéquez'),
('09', '13', N'Almolonga'),
('09', '14', N'Cantel'),
('09', '15', N'Huitán'),
('09', '16', N'Zunil'),
('09', '17', N'Colomba'),
('09', '18', N'San Francisco La Unión'),
('09', '19', N'El Palmar'),
('09', '20', N'Coatepeque'),
('09', '21', N'Génova'),
('09', '22', N'Flores Costa Cuca'),
('09', '23', N'La Esperanza'),
('09', '24', N'Palestina de los Altos'),
('10', '01', N'Mazatenango'),
('10', '02', N'Cuyotenango'),
('10', '03', N'San Francisco Zapotitlán'),
('10', '04', N'San Bernardino'),
('10', '05', N'San José El Ídolo'),
('10', '06', N'Santo Domingo Suchitepéquez'),
('10', '07', N'San Lorenzo'),
('10', '08', N'Samayac'),
('10', '09', N'San Pablo Jocopilas'),
('10', '10', N'San Antonio Suchitepéquez'),
('10', '11', N'San Miguel Panán'),
('10', '12', N'San Gabriel'),
('10', '13', N'Chicacao'),
('10', '14', N'Patulul'),
('10', '15', N'Santa Bárbara'),
('10', '16', N'San Juan Bautista'),
('10', '17', N'Santo Tomás La Unión'),
('10', '18', N'Zunilito'),
('10', '19', N'Pueblo Nuevo'),
('10', '20', N'Río Bravo'),
('10', '21', N'San José La Máquina'),
('11', '01', N'Retalhuleu'),
('11', '02', N'San Sebastián'),
('11', '03', N'Santa Cruz Muluá'),
('11', '04', N'San Martín Zapotitlán'),
('11', '05', N'San Felipe'),
('11', '06', N'San Andrés Villa Seca'),
('11', '07', N'Champerico'),
('11', '08', N'Nuevo San Carlos'),
('11', '09', N'El Asintal'),
('12', '01', N'San Marcos'),
('12', '02', N'San Pedro Sacatepéquez'),
('12', '03', N'San Antonio Sacatepéquez'),
('12', '04', N'Comitancillo'),
('12', '05', N'San Miguel Ixtahuacán'),
('12', '06', N'Concepción Tutuapa'),
('12', '07', N'Tacaná'),
('12', '08', N'Sibinal'),
('12', '09', N'Tajumulco'),
('12', '10', N'Tejutla'),
('12', '11', N'San Rafael Pie de la Cuesta'),
('12', '12', N'Nuevo Progreso'),
('12', '13', N'El Tumbador'),
('12', '14', N'El Rodeo'),
('12', '15', N'Malacatán'),
('12', '16', N'Catarina'),
('12', '17', N'Ayutla'),
('12', '18', N'Ocós'),
('12', '19', N'San Pablo'),
('12', '20', N'El Quetzal'),
('12', '21', N'La Reforma'),
('12', '22', N'Pajapita'),
('12', '23', N'Ixchiguán'),
('12', '24', N'San José Ojetenam'),
('12', '25', N'San Cristóbal Cucho'),
('12', '26', N'Sipacapa'),
('12', '27', N'Esquipulas Palo Gordo'),
('12', '28', N'Río Blanco'),
('12', '29', N'San Lorenzo'),
('12', '30', N'La Blanca'),
('13', '01', N'Huehuetenango'),
('13', '02', N'Chiantla'),
('13', '03', N'Malacatancito'),
('13', '04', N'Cuilco'),
('13', '05', N'Nentón'),
('13', '06', N'San Pedro Necta'),
('13', '07', N'Jacaltenango'),
('13', '08', N'San Pedro Soloma'),
('13', '09', N'San Ildefonso Ixtahuacán'),
('13', '10', N'Santa Bárbara'),
('13', '11', N'La Libertad'),
('13', '12', N'La Democracia'),
('13', '13', N'San Miguel Acatán'),
('13', '14', N'San Rafael La Independencia'),
('13', '15', N'Todos Santos Cuchumatán'),
('13', '16', N'San Juan Atitán'),
('13', '17', N'Santa Eulalia'),
('13', '18', N'San Mateo Ixtatán'),
('13', '19', N'Colotenango'),
('13', '20', N'San Sebastián Huehuetenango'),
('13', '21', N'Tectitán'),
('13', '22', N'Concepción'),
('13', '23', N'San Juan Ixcoy'),
('13', '24', N'San Antonio Huista'),
('13', '25', N'San Sebastián Coatán'),
('13', '26', N'Santa Cruz Barillas'),
('13', '27', N'Aguacatán'),
('13', '28', N'San Rafael Petzal'),
('13', '29', N'San Gaspar Ixchil'),
('13', '30', N'Santiago Chimaltenango'),
('13', '31', N'Santa Ana Huista'),
('13', '32', N'La Unión Cantinil'),
('13', '33', N'Petatán'),
('14', '01', N'Santa Cruz del Quiché'),
('14', '02', N'Chiché'),
('14', '03', N'Chinique'),
('14', '04', N'Zacualpa'),
('14', '05', N'San Gaspar Chajul'),
('14', '06', N'Santo Tomás Chichicastenango'),
('14', '07', N'Patzité'),
('14', '08', N'San Antonio Ilotenango'),
('14', '09', N'San Pedro Jocopilas'),
('14', '10', N'Cunén'),
('14', '11', N'San Juan Cotzal'),
('14', '12', N'Joyabaj'),
('14', '13', N'Santa María Nebaj'),
('14', '14', N'San Andrés Sajcabajá'),
('14', '15', N'San Miguel Uspantán'),
('14', '16', N'Sacapulas'),
('14', '17', N'San Bartolomé Jocotenango'),
('14', '18', N'Canillá'),
('14', '19', N'Chicamán'),
('14', '20', N'Ixcán'),
('14', '21', N'Pachalum'),
('15', '01', N'Salamá'),
('15', '02', N'San Miguel Chicaj'),
('15', '03', N'Rabinal'),
('15', '04', N'Cubulco'),
('15', '05', N'Granados'),
('15', '06', N'El Chol'),
('15', '07', N'San Jerónimo'),
('15', '08', N'Purulhá'),
('16', '01', N'Cobán'),
('16', '02', N'Santa Cruz Verapaz'),
('16', '03', N'San Cristóbal Verapaz'),
('16', '04', N'Tactic'),
('16', '05', N'Tamahú'),
('16', '06', N'Tucurú'),
('16', '07', N'Panzós'),
('16', '08', N'Senahú'),
('16', '09', N'San Pedro Carchá'),
('16', '10', N'San Juan Chamelco'),
('16', '11', N'Lanquín'),
('16', '12', N'Santa María Cahabón'),
('16', '13', N'Chisec'),
('16', '14', N'Chahal'),
('16', '15', N'Fray Bartolomé de las Casas'),
('16', '16', N'Santa Catalina La Tinta'),
('16', '17', N'Raxruhá'),
('17', '01', N'Flores'),
('17', '02', N'San José'),
('17', '03', N'San Benito'),
('17', '04', N'San Andrés'),
('17', '05', N'La Libertad'),
('17', '06', N'San Francisco'),
('17', '07', N'Santa Ana'),
('17', '08', N'Dolores'),
('17', '09', N'San Luis'),
('17', '10', N'Sayaxché'),
('17', '11', N'Melchor de Mencos'),
('17', '12', N'Poptún'),
('17', '13', N'Las Cruces'),
('17', '14', N'El Chal'),
('18', '01', N'Puerto Barrios'),
('18', '02', N'Livingston'),
('18', '03', N'El Estor'),
('18', '04', N'Morales'),
('18', '05', N'Los Amates'),
('19', '01', N'Zacapa'),
('19', '02', N'Estanzuela'),
('19', '03', N'Río Hondo'),
('19', '04', N'Gualán'),
('19', '05', N'Teculután'),
('19', '06', N'Usumatlán'),
('19', '07', N'Cabañas'),
('19', '08', N'San Diego'),
('19', '09', N'La Unión'),
('19', '10', N'Huité'),
('19', '11', N'San Jorge'),
('20', '01', N'Chiquimula'),
('20', '02', N'San José La Arada'),
('20', '03', N'San Juan Ermita'),
('20', '04', N'Jocotán'),
('20', '05', N'Camotán'),
('20', '06', N'Olopa'),
('20', '07', N'Esquipulas'),
('20', '08', N'Concepción Las Minas'),
('20', '09', N'Quezaltepeque'),
('20', '10', N'San Jacinto'),
('20', '11', N'Ipala'),
('21', '01', N'Jalapa'),
('21', '02', N'San Pedro Pinula'),
('21', '03', N'San Luis Jilotepeque'),
('21', '04', N'San Manuel Chaparrón'),
('21', '05', N'San Carlos Alzatate'),
('21', '06', N'Monjas'),
('21', '07', N'Mataquescuintla'),
('22', '01', N'Jutiapa'),
('22', '02', N'El Progreso'),
('22', '03', N'Santa Catarina Mita'),
('22', '04', N'Agua Blanca'),
('22', '05', N'Asunción Mita'),
('22', '06', N'Yupiltepeque'),
('22', '07', N'Atescatempa'),
('22', '08', N'Jerez'),
('22', '09', N'El Adelanto'),
('22', '10', N'Zapotitlán'),
('22', '11', N'Comapa'),
('22', '12', N'Jalpatagua'),
('22', '13', N'Conguaco'),
('22', '14', N'Moyuta'),
('22', '15', N'Pasaco'),
('22', '16', N'San José Acatempa'),
('22', '17', N'Quezada')

-- Nombres con que el catálogo de prueba traía algunos municipios.
DECLARE @alias TABLE (depto VARCHAR(2), nombre VARCHAR(128), codigo VARCHAR(2));
INSERT INTO @alias VALUES ('01', 'Ciudad de Guatemala', '01'), ('05', 'Puerto San José', '09'), ('01', 'Petapa', '17'), ('09', 'Quezaltenango', '01');

DECLARE @existente TABLE (prov_id INT PRIMARY KEY, est_id INT, codigo VARCHAR(2), nombre VARCHAR(128));
INSERT INTO @existente (prov_id, est_id, codigo, nombre)
SELECT prov.prov_id, prov.est_id, ofic.codigo, ofic.nombre
FROM dbo.gen_provincia prov
INNER JOIN dbo.gen_estado esta ON esta.est_id = prov.est_id AND esta.pai_id = @gt
CROSS APPLY (SELECT TOP 1 cand.codigo, cand.nombre
			 FROM @muni cand
			 WHERE cand.depto = esta.est_codigo
			   AND (cand.nombre COLLATE Latin1_General_CI_AI = prov.prov_nombre COLLATE Latin1_General_CI_AI
					OR EXISTS (SELECT 1 FROM @alias alia WHERE alia.depto = cand.depto AND alia.codigo = cand.codigo
							   AND alia.nombre COLLATE Latin1_General_CI_AI = prov.prov_nombre COLLATE Latin1_General_CI_AI))) ofic;

-- Un municipio propio (no reconocido) que ocupe un código oficial se pasa a
-- un código libre 'X?' para no chocar con el oficial.
WITH choque AS (
	SELECT prov.prov_id, ROW_NUMBER() OVER (PARTITION BY prov.est_id ORDER BY prov.prov_id) AS n
	FROM dbo.gen_provincia prov
	INNER JOIN dbo.gen_estado esta ON esta.est_id = prov.est_id AND esta.pai_id = @gt
	WHERE NOT EXISTS (SELECT 1 FROM @existente exis WHERE exis.prov_id = prov.prov_id)
	  AND EXISTS (SELECT 1 FROM @muni ofic WHERE ofic.depto = esta.est_codigo AND ofic.codigo = prov.prov_codigo))
UPDATE prov
   SET prov_codigo = 'X' + CHAR(64 + choq.n), UpdFechaHora = SYSDATETIME()
FROM dbo.gen_provincia prov
INNER JOIN choque choq ON choq.prov_id = prov.prov_id;

UPDATE prov
   SET prov_codigo = exis.codigo, prov_nombre = exis.nombre, UpdFechaHora = SYSDATETIME()
FROM dbo.gen_provincia prov
INNER JOIN @existente exis ON exis.prov_id = prov.prov_id
WHERE prov.prov_codigo <> exis.codigo OR prov.prov_nombre COLLATE Latin1_General_CS_AS <> exis.nombre COLLATE Latin1_General_CS_AS;

INSERT INTO dbo.gen_provincia (prov_codigo, est_id, prov_nombre)
SELECT ofic.codigo, esta.est_id, ofic.nombre
FROM @muni ofic
INNER JOIN dbo.gen_estado esta ON esta.pai_id = @gt AND esta.est_codigo = ofic.depto
WHERE NOT EXISTS (SELECT 1 FROM dbo.gen_provincia prov WHERE prov.est_id = esta.est_id AND prov.prov_codigo = ofic.codigo);
GO

------------------------------------------------------------
-- 2. Municipio de la compañía
------------------------------------------------------------
IF COL_LENGTH('dbo.gen_compania', 'prov_id') IS NULL
	ALTER TABLE dbo.gen_compania ADD [prov_id] INT NULL;
GO
IF OBJECT_ID('dbo.FK_gen_compania_municipio', 'F') IS NULL
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [FK_gen_compania_municipio] FOREIGN KEY ([prov_id]) REFERENCES dbo.gen_provincia ([prov_id]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rrhhEmpleado_prov_id')
	CREATE INDEX [IX_rrhhEmpleado_prov_id] ON dbo.rrhhEmpleado ([prov_id]) WHERE [prov_id] IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_gen_provincia_est_id')
	CREATE INDEX [IX_gen_provincia_est_id] ON dbo.gen_provincia ([est_id]) INCLUDE ([prov_nombre], [prov_estado]);
GO

-- La compañía de prueba queda en el municipio de su casa matriz.
UPDATE comp
   SET prov_id = (SELECT TOP 1 sucu.prov_id FROM dbo.gen_sucursal sucu WHERE sucu.cia_id = comp.cia_id AND sucu.prov_id IS NOT NULL ORDER BY sucu.suc_id)
FROM dbo.gen_compania comp
WHERE comp.prov_id IS NULL;
GO

------------------------------------------------------------
-- 3. Vista y función para desplegar la ubicación
------------------------------------------------------------
CREATE OR ALTER VIEW [dbo].[vwGenUbicacion]
AS
SELECT muni.prov_id AS ProvId, muni.prov_codigo AS MunicipioCodigo, muni.prov_nombre AS Municipio,
	   depa.est_id AS EstId, depa.est_codigo AS DepartamentoCodigo, depa.est_nombre AS Departamento,
	   pais.pai_id AS PaiId, pais.pai_codigo_alfa2 AS PaisCodigo, pais.pai_nombre AS Pais,
	   depa.est_codigo + muni.prov_codigo AS CodigoUbicacion,
	   CONCAT(muni.prov_nombre, ', ', depa.est_nombre) AS Ubicacion,
	   CAST(CASE WHEN muni.prov_estado = 'A' AND depa.est_estado = 'A' AND pais.pai_estado = 'A' THEN 1 ELSE 0 END AS BIT) AS Activo
FROM dbo.gen_provincia muni
INNER JOIN dbo.gen_estado depa ON depa.est_id = muni.est_id
INNER JOIN dbo.gen_pais pais ON pais.pai_id = depa.pai_id;
GO

-- Dirección para imprimir o mostrar: 'calle, municipio, departamento'; con
-- @ConPais = 1 agrega el país (útil para direcciones fuera de Guatemala).
CREATE OR ALTER FUNCTION [dbo].[fnGenDireccionCompleta] (@Direccion VARCHAR(256), @ProvId INT, @ConPais BIT)
RETURNS VARCHAR(600)
AS
BEGIN
	DECLARE @muni VARCHAR(128), @depa VARCHAR(128), @pais VARCHAR(128);
	SELECT @muni = muni.prov_nombre, @depa = depa.est_nombre, @pais = pais.pai_nombre
	FROM dbo.gen_provincia muni
	INNER JOIN dbo.gen_estado depa ON depa.est_id = muni.est_id
	INNER JOIN dbo.gen_pais pais ON pais.pai_id = depa.pai_id
	WHERE muni.prov_id = @ProvId;
	RETURN NULLIF(CONCAT_WS(', ', NULLIF(LTRIM(RTRIM(@Direccion)), ''), @muni, @depa, CASE WHEN @ConPais = 1 THEN @pais END), '');
END;
GO

------------------------------------------------------------
-- 4. Mantenimiento del catálogo
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paGenUbicacionConsultar]
	@SoloActivos BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT pais.pai_id AS PaiId, pais.pai_nombre AS Nombre, pais.pai_codigo_alfa2 AS CodigoAlfa2, pais.pai_codigo_alfa3 AS CodigoAlfa3,
		   pais.pai_codigo_numero AS CodigoNumero, pais.pai_nacionalidad AS Nacionalidad, pais.pai_estado AS Estado
	FROM dbo.gen_pais pais
	WHERE @SoloActivos = 0 OR pais.pai_estado = 'A'
	ORDER BY CASE WHEN pais.pai_codigo_alfa2 = 'GT' THEN 0 ELSE 1 END, pais.pai_nombre;

	SELECT depa.est_id AS EstId, depa.pai_id AS PaiId, depa.est_codigo AS Codigo, depa.est_nombre AS Nombre, depa.est_estado AS Estado
	FROM dbo.gen_estado depa
	WHERE @SoloActivos = 0 OR depa.est_estado = 'A'
	ORDER BY depa.pai_id, depa.est_nombre;

	SELECT muni.prov_id AS ProvId, muni.est_id AS EstId, muni.prov_codigo AS Codigo, muni.prov_nombre AS Nombre, muni.prov_estado AS Estado
	FROM dbo.gen_provincia muni
	WHERE @SoloActivos = 0 OR muni.prov_estado = 'A'
	ORDER BY muni.est_id, muni.prov_nombre;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paGenPaisGuardar]
	@PaiId			INT = NULL,
	@Nombre			VARCHAR(128),
	@CodigoAlfa2	VARCHAR(2),
	@CodigoAlfa3	VARCHAR(3),
	@CodigoNumero	VARCHAR(3) = NULL,
	@Nacionalidad	VARCHAR(64) = NULL,
	@Estado			CHAR(1) = 'A',
	@UsuId			INT = NULL,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT @Nombre = LTRIM(RTRIM(@Nombre)), @CodigoAlfa2 = UPPER(LTRIM(RTRIM(@CodigoAlfa2))), @CodigoAlfa3 = UPPER(LTRIM(RTRIM(@CodigoAlfa3))),
		   @CodigoNumero = NULLIF(LTRIM(RTRIM(@CodigoNumero)), ''), @Nacionalidad = NULLIF(LTRIM(RTRIM(@Nacionalidad)), '');
	IF ISNULL(@Nombre, '') = '' OR LEN(ISNULL(@CodigoAlfa2, '')) <> 2 OR LEN(ISNULL(@CodigoAlfa3, '')) <> 3
		THROW 55901, 'Indique el nombre del país y sus códigos ISO de 2 y de 3 letras.', 1;
	IF @Estado NOT IN ('A', 'I')
		THROW 55902, 'El estado debe ser activo o inactivo.', 1;
	IF @PaiId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.gen_pais WHERE pai_id = @PaiId)
		THROW 55903, 'El país indicado no existe.', 1;
	IF EXISTS (SELECT 1 FROM dbo.gen_pais WHERE (pai_codigo_alfa2 = @CodigoAlfa2 OR pai_codigo_alfa3 = @CodigoAlfa3) AND (@PaiId IS NULL OR pai_id <> @PaiId))
		THROW 55904, 'Ya existe otro país con ese código ISO.', 1;
	IF EXISTS (SELECT 1 FROM dbo.gen_pais WHERE pai_nombre = @Nombre AND (@PaiId IS NULL OR pai_id <> @PaiId))
		THROW 55905, 'Ya existe un país con ese nombre.', 1;

	IF @PaiId IS NULL
	BEGIN
		INSERT INTO dbo.gen_pais (pai_nombre, pai_codigo_alfa2, pai_codigo_alfa3, pai_codigo_numero, pai_nacionalidad, pai_estado, InsUsuario)
		VALUES (@Nombre, @CodigoAlfa2, @CodigoAlfa3, @CodigoNumero, @Nacionalidad, @Estado, @UsuId);
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.gen_pais
		   SET pai_nombre = @Nombre, pai_codigo_alfa2 = @CodigoAlfa2, pai_codigo_alfa3 = @CodigoAlfa3, pai_codigo_numero = @CodigoNumero,
			   pai_nacionalidad = @Nacionalidad, pai_estado = @Estado, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE pai_id = @PaiId;
		SET @IdResultado = @PaiId;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paGenDepartamentoGuardar]
	@EstId			INT = NULL,
	@PaiId			INT,
	@Codigo			VARCHAR(2),
	@Nombre			VARCHAR(128),
	@Estado			CHAR(1) = 'A',
	@UsuId			INT = NULL,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT @Nombre = LTRIM(RTRIM(@Nombre)), @Codigo = UPPER(LTRIM(RTRIM(@Codigo)));
	IF ISNULL(@Nombre, '') = '' OR ISNULL(@Codigo, '') = ''
		THROW 55906, 'Indique el código y el nombre del departamento.', 1;
	IF @Estado NOT IN ('A', 'I')
		THROW 55902, 'El estado debe ser activo o inactivo.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_pais WHERE pai_id = @PaiId)
		THROW 55903, 'El país indicado no existe.', 1;
	IF @EstId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.gen_estado WHERE est_id = @EstId)
		THROW 55907, 'El departamento indicado no existe.', 1;
	IF @EstId IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.gen_estado WHERE est_id = @EstId AND pai_id <> @PaiId)
		THROW 55908, 'Un departamento no se puede mover a otro país.', 1;
	IF EXISTS (SELECT 1 FROM dbo.gen_estado WHERE pai_id = @PaiId AND (est_codigo = @Codigo OR est_nombre = @Nombre) AND (@EstId IS NULL OR est_id <> @EstId))
		THROW 55909, 'El país ya tiene un departamento con ese código o ese nombre.', 1;

	IF @EstId IS NULL
	BEGIN
		INSERT INTO dbo.gen_estado (est_codigo, pai_id, est_nombre, est_estado, InsUsuario)
		VALUES (@Codigo, @PaiId, @Nombre, @Estado, @UsuId);
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.gen_estado
		   SET est_codigo = @Codigo, est_nombre = @Nombre, est_estado = @Estado, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE est_id = @EstId;
		SET @IdResultado = @EstId;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paGenMunicipioGuardar]
	@ProvId			INT = NULL,
	@EstId			INT,
	@Codigo			VARCHAR(2),
	@Nombre			VARCHAR(128),
	@Estado			CHAR(1) = 'A',
	@UsuId			INT = NULL,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT @Nombre = LTRIM(RTRIM(@Nombre)), @Codigo = UPPER(LTRIM(RTRIM(@Codigo)));
	IF ISNULL(@Nombre, '') = '' OR ISNULL(@Codigo, '') = ''
		THROW 55910, 'Indique el código y el nombre del municipio.', 1;
	IF @Estado NOT IN ('A', 'I')
		THROW 55902, 'El estado debe ser activo o inactivo.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_estado WHERE est_id = @EstId)
		THROW 55907, 'El departamento indicado no existe.', 1;
	IF @ProvId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.gen_provincia WHERE prov_id = @ProvId)
		THROW 55911, 'El municipio indicado no existe.', 1;
	IF @ProvId IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.gen_provincia WHERE prov_id = @ProvId AND est_id <> @EstId)
		THROW 55912, 'Un municipio no se puede mover a otro departamento.', 1;
	IF EXISTS (SELECT 1 FROM dbo.gen_provincia WHERE est_id = @EstId AND (prov_codigo = @Codigo OR prov_nombre = @Nombre) AND (@ProvId IS NULL OR prov_id <> @ProvId))
		THROW 55913, 'El departamento ya tiene un municipio con ese código o ese nombre.', 1;

	IF @ProvId IS NULL
	BEGIN
		INSERT INTO dbo.gen_provincia (prov_codigo, est_id, prov_nombre, prov_estado, InsUsuario)
		VALUES (@Codigo, @EstId, @Nombre, @Estado, @UsuId);
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.gen_provincia
		   SET prov_codigo = @Codigo, prov_nombre = @Nombre, prov_estado = @Estado, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE prov_id = @ProvId;
		SET @IdResultado = @ProvId;
	END
END;
GO

------------------------------------------------------------
-- 5. Compañía y empleado con su municipio
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paCompaniaConsultar]
	@SoloActivas BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT comp.cia_id, comp.cia_nombre_comercial, comp.cia_direccion, comp.cia_representante_legal, comp.cia_DPI_representante_legal,
		   comp.cia_fecha_nacimiento_representante_legal, comp.cia_nit, comp.cia_telefono, comp.cia_email, comp.cia_estado,
		   comp.cia_porc_iva, comp.cia_paga_comision, comp.cia_tolerancia_cierre_caja, comp.cia_periodicidad_nomina,
		   CAST(CASE WHEN comp.cia_logo IS NULL THEN 0 ELSE 1 END AS BIT) AS cia_tiene_logo, comp.cia_logo_actualizado,
		   comp.prov_id, ubic.EstId AS est_id, ubic.PaiId AS pai_id, ubic.Municipio AS municipio, ubic.Departamento AS departamento, ubic.Pais AS pais,
		   dbo.fnGenDireccionCompleta(comp.cia_direccion, comp.prov_id, 0) AS cia_direccion_completa
	FROM dbo.gen_compania comp
	LEFT JOIN dbo.vwGenUbicacion ubic ON ubic.ProvId = comp.prov_id
	WHERE @SoloActivas = 0 OR comp.cia_estado = 'A'
	ORDER BY comp.cia_nombre_comercial;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaGuardar]
	@CiaId								INT = NULL,
	@NombreComercial					VARCHAR(128),
	@Direccion							VARCHAR(128) = NULL,
	@RepresentanteLegal					VARCHAR(128) = NULL,
	@DpiRepresentanteLegal				VARCHAR(32) = NULL,
	@FechaNacimientoRepresentanteLegal	DATE = NULL,
	@Nit								VARCHAR(32),
	@Telefono							VARCHAR(16) = NULL,
	@Email								VARCHAR(64) = NULL,
	@PorcIva							NUMERIC(5, 2),
	@PagaComision						BIT,
	@ToleranciaCierreCaja				NUMERIC(12, 2),
	@PeriodicidadNomina					CHAR(1),
	@ProvId								INT = NULL,
	@UsuId								INT,
	@IdResultado						INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(LTRIM(RTRIM(@NombreComercial)), '') = '' OR ISNULL(LTRIM(RTRIM(@Nit)), '') = ''
		THROW 52200, 'El nombre comercial y el NIT son obligatorios.', 1;
	IF @PorcIva < 0 OR @PorcIva >= 100
		THROW 52201, 'El porcentaje de IVA debe estar entre 0 y 99.99.', 1;
	IF @ToleranciaCierreCaja < 0
		THROW 52202, 'La tolerancia del cierre de caja no puede ser negativa.', 1;
	IF @PeriodicidadNomina NOT IN ('S','Q','M')
		THROW 52203, 'La periodicidad de nómina debe ser semanal, quincenal o mensual.', 1;
	IF EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_nit = @Nit AND (@CiaId IS NULL OR cia_id <> @CiaId))
		THROW 52204, 'Ya existe una compañía con ese NIT.', 1;
	-- Un municipio inactivo solo se acepta si es el que ya tenía.
	IF @ProvId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.vwGenUbicacion WHERE ProvId = @ProvId
			AND (Activo = 1 OR EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_id = @CiaId AND prov_id = @ProvId)))
		THROW 55914, 'El municipio indicado no existe o está inactivo.', 1;

	IF @CiaId IS NULL
	BEGIN
		INSERT INTO dbo.gen_compania (cia_nombre_comercial, cia_direccion, cia_representante_legal, cia_DPI_representante_legal,
			cia_fecha_nacimiento_representante_legal, cia_nit, cia_telefono, cia_email,
			cia_porc_iva, cia_paga_comision, cia_tolerancia_cierre_caja, cia_periodicidad_nomina, prov_id, InsUsuario, InsFechaHora)
		VALUES (@NombreComercial, @Direccion, @RepresentanteLegal, @DpiRepresentanteLegal,
			@FechaNacimientoRepresentanteLegal, @Nit, @Telefono, @Email,
			@PorcIva, @PagaComision, @ToleranciaCierreCaja, @PeriodicidadNomina, @ProvId, @UsuId, SYSDATETIME());
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.gen_compania
		   SET cia_nombre_comercial = @NombreComercial, cia_direccion = @Direccion, cia_representante_legal = @RepresentanteLegal,
			   cia_DPI_representante_legal = @DpiRepresentanteLegal, cia_fecha_nacimiento_representante_legal = @FechaNacimientoRepresentanteLegal,
			   cia_nit = @Nit, cia_telefono = @Telefono, cia_email = @Email,
			   cia_porc_iva = @PorcIva, cia_paga_comision = @PagaComision, cia_tolerancia_cierre_caja = @ToleranciaCierreCaja,
			   cia_periodicidad_nomina = @PeriodicidadNomina, prov_id = @ProvId, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE cia_id = @CiaId;
		SET @IdResultado = @CiaId;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoConsultarPorId]
	@IdEmpleado INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT empl.*,
		   (SELECT TOP 1 usua.usu_id FROM dbo.gen_usuario usua WHERE usua.IdEmpleado = empl.IdEmpleado) AS usu_id,
		   (SELECT TOP 1 vend.pve_id FROM dbo.pos_vendedor vend WHERE vend.IdEmpleado = empl.IdEmpleado) AS pve_id,
		   ubic.EstId AS est_id, ubic.PaiId AS pai_id, ubic.Municipio, ubic.Departamento, ubic.Pais,
		   dbo.fnGenDireccionCompleta(empl.Direccion, empl.prov_id, 0) AS DireccionCompleta
	FROM dbo.rrhhEmpleado empl
	LEFT JOIN dbo.vwGenUbicacion ubic ON ubic.ProvId = empl.prov_id
	WHERE empl.IdEmpleado = @IdEmpleado;

	SELECT hist.IdHistorialPlaza, hist.IdPlaza, plaz.Descripcion AS Plaza, hist.FechaDel, hist.FechaAl, hist.Salario
	FROM dbo.rrhhHistorialPlaza hist
	INNER JOIN dbo.rrhhPlaza plaz ON plaz.IdPlaza = hist.IdPlaza
	WHERE hist.IdEmpleado = @IdEmpleado
	ORDER BY hist.FechaDel DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoGuardar]
	@IdEmpleado						INT = NULL,
	@CodigoEmpleado					VARCHAR(16),
	@CiaId							INT,
	@PrimerNombre					VARCHAR(50),
	@SegundoNombre					VARCHAR(50) = NULL,
	@PrimerApellido					VARCHAR(50),
	@SegundoApellido				VARCHAR(50) = NULL,
	@ApellidoCasada					VARCHAR(50) = NULL,
	@Genero							CHAR(1) = NULL,
	@FechaNacimiento				DATE = NULL,
	@FechaIngreso					DATE,
	@Direccion						VARCHAR(200) = NULL,
	@IdTipoDocumentoIdentificacion	INT = NULL,
	@NumeroDocumento				VARCHAR(32) = NULL,
	@NumeroAfiliacionIGSS			VARCHAR(20) = NULL,
	@Nit							VARCHAR(20) = NULL,
	@Email							VARCHAR(100) = NULL,
	@IdPlaza						INT = NULL,
	@SalarioBase					NUMERIC(12, 2),
	@UsuId							INT,
	@IdResultado					INT OUTPUT,
	@ProvId							INT = -1	-- -1 = conservar el municipio actual
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	IF ISNULL(LTRIM(RTRIM(@CodigoEmpleado)), '') = '' OR ISNULL(LTRIM(RTRIM(@PrimerNombre)), '') = '' OR ISNULL(LTRIM(RTRIM(@PrimerApellido)), '') = ''
		THROW 52040, 'El código, el primer nombre y el primer apellido son obligatorios.', 1;
	IF @SalarioBase < 0
		THROW 52041, 'El salario base no puede ser negativo.', 1;
	IF EXISTS (SELECT 1 FROM dbo.rrhhEmpleado WHERE CodigoEmpleado = @CodigoEmpleado AND (@IdEmpleado IS NULL OR IdEmpleado <> @IdEmpleado))
		THROW 52042, 'Ya existe un empleado con ese código.', 1;
	IF @IdPlaza IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.rrhhEmpleado WHERE IdPlaza = @IdPlaza AND Estado = 'A' AND (@IdEmpleado IS NULL OR IdEmpleado <> @IdEmpleado))
		THROW 52043, 'La plaza ya está ocupada por otro empleado activo.', 1;

	DECLARE @PlazaAnterior INT, @SalarioAnterior NUMERIC(12, 2), @ProvAnterior INT;
	SELECT @PlazaAnterior = IdPlaza, @SalarioAnterior = SalarioBase, @ProvAnterior = prov_id FROM dbo.rrhhEmpleado WHERE IdEmpleado = @IdEmpleado;
	IF @ProvId = -1
		SET @ProvId = @ProvAnterior;
	ELSE IF @ProvId IS NOT NULL AND ISNULL(@ProvAnterior, 0) <> @ProvId
		AND NOT EXISTS (SELECT 1 FROM dbo.vwGenUbicacion WHERE ProvId = @ProvId AND Activo = 1)
		THROW 55914, 'El municipio indicado no existe o está inactivo.', 1;

	BEGIN TRANSACTION;

	IF @IdEmpleado IS NULL
	BEGIN
		INSERT INTO dbo.rrhhEmpleado (CodigoEmpleado, cia_id, PrimerNombre, SegundoNombre, PrimerApellido, SegundoApellido, ApellidoCasada,
			Genero, FechaNacimiento, FechaIngreso, Direccion, prov_id, IdTipoDocumentoIdentificacion, NumeroDocumento, NumeroAfiliacionIGSS, Nit, Email,
			IdPlaza, SalarioBase, InsUsuario)
		VALUES (@CodigoEmpleado, @CiaId, @PrimerNombre, @SegundoNombre, @PrimerApellido, @SegundoApellido, @ApellidoCasada,
			@Genero, @FechaNacimiento, @FechaIngreso, @Direccion, @ProvId, @IdTipoDocumentoIdentificacion, @NumeroDocumento, @NumeroAfiliacionIGSS, @Nit, @Email,
			@IdPlaza, @SalarioBase, @UsuId);
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.rrhhEmpleado
		   SET CodigoEmpleado = @CodigoEmpleado, cia_id = @CiaId, PrimerNombre = @PrimerNombre, SegundoNombre = @SegundoNombre,
			   PrimerApellido = @PrimerApellido, SegundoApellido = @SegundoApellido, ApellidoCasada = @ApellidoCasada, Genero = @Genero,
			   FechaNacimiento = @FechaNacimiento, FechaIngreso = @FechaIngreso, Direccion = @Direccion, prov_id = @ProvId,
			   IdTipoDocumentoIdentificacion = @IdTipoDocumentoIdentificacion, NumeroDocumento = @NumeroDocumento,
			   NumeroAfiliacionIGSS = @NumeroAfiliacionIGSS, Nit = @Nit, Email = @Email, IdPlaza = @IdPlaza, SalarioBase = @SalarioBase,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE IdEmpleado = @IdEmpleado;
		SET @IdResultado = @IdEmpleado;
	END

	-- Cada cambio de plaza o de salario abre un nuevo tramo en el historial.
	IF @IdPlaza IS NOT NULL AND (@IdEmpleado IS NULL OR ISNULL(@PlazaAnterior, 0) <> @IdPlaza OR ISNULL(@SalarioAnterior, -1) <> @SalarioBase)
	BEGIN
		DECLARE @Hoy DATE = CAST(SYSDATETIME() AS DATE);
		DECLARE @Desde DATE = CASE WHEN @IdEmpleado IS NULL THEN @FechaIngreso ELSE @Hoy END;

		UPDATE dbo.rrhhHistorialPlaza SET FechaAl = DATEADD(DAY, -1, @Desde)
		 WHERE IdEmpleado = @IdResultado AND FechaAl IS NULL AND FechaDel < @Desde;
		DELETE FROM dbo.rrhhHistorialPlaza WHERE IdEmpleado = @IdResultado AND FechaAl IS NULL AND FechaDel >= @Desde;

		INSERT INTO dbo.rrhhHistorialPlaza (IdEmpleado, IdPlaza, FechaDel, Salario, InsUsuario)
		VALUES (@IdResultado, @IdPlaza, @Desde, @SalarioBase, @UsuId);
	END

	COMMIT TRANSACTION;
END;
GO

-- Empleados de prueba sin municipio: el de la sucursal donde trabajan.
UPDATE empl
   SET prov_id = sucu.prov_id
FROM dbo.rrhhEmpleado empl
INNER JOIN dbo.gen_sucursal sucu ON sucu.suc_id = empl.suc_id
WHERE empl.prov_id IS NULL AND sucu.prov_id IS NOT NULL;
GO

PRINT '73_ubicacion_geografica.sql aplicado.';
GO
