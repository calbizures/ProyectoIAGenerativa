/*
================================================================================
 55_planilla_igss_archivo.sql
 Archivo de la planilla del IGSS para "sistema propio", formato 2.2.0
 (manual GenerarArchivoPlanilla 2.2.0 y plantilla SISTEMA_PROPIO_2.2.0.xls).

   - Catálogos oficiales del IGSS (de la plantilla): actividades económicas
     (CIIU 3.1, 6 dígitos), ocupaciones (CIUO-88, grupo primario de 4
     dígitos), departamentos y municipios, y tipos de salario (1 a 9).
   - Patrono: correo para las respuestas del IGSS y actividad económica.
   - Centros de trabajo (cada sucursal): zona, fax, contacto, correo,
     departamento, municipio y actividad económica.
   - Tipos de planilla por compañía (rrhhIgssTipoPlanilla): tipo de
     afiliado (C con IVS / S sin IVS), período (M mensual, C catorcenal,
     S semanal), departamento, actividad, clase (N normal, V sin movimiento)
     y tiempo de contrato (TC/TP).
   - Por puesto: ocupación CIUO-88. Por empleado: tipo de planilla,
     condición laboral (P permanente / T temporal), tipo de salario, horas
     diarias (tiempo parcial) y, si difiere del puesto, su ocupación.
   - Suspensiones del IGSS y licencias sin goce de salario (rrhhIgssAusencia).
   - paRrhhPlanillaIgssArchivoConsultar arma, para un mes, los bloques del
     archivo y la lista de observaciones (lo que falta para que el IGSS lo
     acepte). El texto lo escribe la aplicación.

   Liquidaciones: una por tipo de planilla y período. Si el tipo es mensual,
   una por el mes completo aunque haya varias nóminas; si es catorcenal o
   semanal, una por cada nómina ordinaria aprobada.

 Errores nuevos: 54701 a 54710.
 Se puede ejecutar más de una vez.
================================================================================
*/
USE erp_db;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

------------------------------------------------------------
-- 1. Catálogos del IGSS
------------------------------------------------------------
IF OBJECT_ID('dbo.rrhhIgssActividadEconomica', 'U') IS NULL
CREATE TABLE [dbo].[rrhhIgssActividadEconomica](
	[Codigo]		CHAR(6)			NOT NULL,
	[Descripcion]	NVARCHAR(200)	NOT NULL,
	[Categoria]		CHAR(1)			NULL,
	CONSTRAINT [PK_rrhhIgssActividadEconomica] PRIMARY KEY ([Codigo])
);
GO
IF OBJECT_ID('dbo.rrhhIgssOcupacion', 'U') IS NULL
CREATE TABLE [dbo].[rrhhIgssOcupacion](
	[Codigo]		CHAR(4)			NOT NULL,
	[Descripcion]	NVARCHAR(200)	NOT NULL,
	CONSTRAINT [PK_rrhhIgssOcupacion] PRIMARY KEY ([Codigo])
);
GO
IF OBJECT_ID('dbo.rrhhIgssDepartamento', 'U') IS NULL
CREATE TABLE [dbo].[rrhhIgssDepartamento](
	[Departamento]	CHAR(2)			NOT NULL,
	[Nombre]		NVARCHAR(60)	NOT NULL,
	CONSTRAINT [PK_rrhhIgssDepartamento] PRIMARY KEY ([Departamento])
);
GO
IF OBJECT_ID('dbo.rrhhIgssMunicipio', 'U') IS NULL
CREATE TABLE [dbo].[rrhhIgssMunicipio](
	[Departamento]	CHAR(2)			NOT NULL,
	[Municipio]		CHAR(2)			NOT NULL,
	[Nombre]		NVARCHAR(80)	NOT NULL,
	CONSTRAINT [PK_rrhhIgssMunicipio] PRIMARY KEY ([Departamento], [Municipio]),
	CONSTRAINT [FK_rrhhIgssMunicipio_Departamento] FOREIGN KEY ([Departamento]) REFERENCES dbo.rrhhIgssDepartamento ([Departamento])
);
GO
IF OBJECT_ID('dbo.rrhhIgssTipoSalario', 'U') IS NULL
CREATE TABLE [dbo].[rrhhIgssTipoSalario](
	[Codigo]		TINYINT			NOT NULL,
	[Descripcion]	NVARCHAR(100)	NOT NULL,
	CONSTRAINT [PK_rrhhIgssTipoSalario] PRIMARY KEY ([Codigo])
);
GO
INSERT INTO dbo.rrhhIgssTipoSalario (Codigo, Descripcion)
SELECT v.Codigo, v.Descripcion
FROM (VALUES (1, N'Salario base mensual'), (2, N'Salario base mensual + extraordinario'), (3, N'Salario por día'),
			 (4, N'Salario por período + extraordinario'), (5, N'Salario a destajo'), (6, N'Salario por producción'),
			 (7, N'Salario por comisión'), (8, N'Salario base mensual + comisiones (mixto)'), (9, N'Salario por período + comisiones')) v (Codigo, Descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssTipoSalario t WHERE t.Codigo = v.Codigo);
GO

-- Una primera versión de este script cargó un código mal formado. En una
-- instalación limpia las columnas que lo referencian aún no existen (se crean
-- en las secciones 2 y 3), por eso la verificación se ejecuta dinámicamente.
IF COL_LENGTH('dbo.gen_compania', 'cia_igss_actividad') IS NULL
   AND COL_LENGTH('dbo.gen_sucursal', 'suc_igss_actividad') IS NULL
   AND OBJECT_ID('dbo.rrhhIgssTipoPlanilla', 'U') IS NULL
    DELETE FROM dbo.rrhhIgssActividadEconomica WHERE Codigo = '00000.';
ELSE IF COL_LENGTH('dbo.gen_compania', 'cia_igss_actividad') IS NOT NULL
   AND COL_LENGTH('dbo.gen_sucursal', 'suc_igss_actividad') IS NOT NULL
   AND OBJECT_ID('dbo.rrhhIgssTipoPlanilla', 'U') IS NOT NULL
    EXEC sys.sp_executesql N'
    DELETE FROM dbo.rrhhIgssActividadEconomica
     WHERE Codigo = ''00000.''
       AND NOT EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_igss_actividad = ''00000.'')
       AND NOT EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE suc_igss_actividad = ''00000.'')
       AND NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssTipoPlanilla WHERE Actividad = ''00000.'');';
GO
INSERT INTO dbo.rrhhIgssActividadEconomica (Codigo, Descripcion, Categoria)
SELECT v.* FROM (VALUES
('011101', N'Maiz', 'A'),
('011102', N'Arroz', 'A'),
('011103', N'Trigo', 'A'),
('011104', N'Frijol', 'A'),
('011105', N'Papa', 'A'),
('011106', N'Ajonjoli', 'A'),
('011107', N'Tabaco sin elaborar', 'A'),
('011108', N'Siembra y cultivo de Caña de Azucar', 'A'),
('011109', N'Hule Natural o Latex', 'A'),
('011110', N'Algodón', 'A'),
('011199', N'Otros cereales y cultivos n.c.p.', 'A'),
('011201', N'Arbeja China', 'A'),
('011202', N'Brocoli', 'A'),
('011203', N'Rosas y Claveles', 'A'),
('011204', N'Chile Pimiento', 'A'),
('011299', N'Otros Cultivos de hortalizas, legumbres, especialidades hortícolas y productos de vivero n.c.p', 'A'),
('011301', N'Siembra y cultivo de Café', 'A'),
('011302', N'Banano', 'A'),
('011303', N'Cardamomo', 'A'),
('011304', N'melon', 'A'),
('011305', N'té Verde', 'A'),
('011306', N'Cacao en grano', 'A'),
('011307', N'Especias', 'A'),
('011308', N'Siembra y cultivo de Citronela', 'A'),
('011309', N'Piña', 'A'),
('011310', N'Aguacate', 'A'),
('011399', N'Otros cultivo de frutas, nueces, plantas cuyas hojas o frutas se utilizan para preparar bebidas y especias n.c.p.', 'A'),
('012101', N'Crianza y engorde de ganado vacuno', 'A'),
('012102', N'Cría de ovejas, cabras, caballos, asnos, mulas y burdéganos', 'A'),
('012199', N'Crianza y engorde de otros ganados n.c.p.', 'A'),
('012201', N'Ganado porcino', 'A'),
('012202', N'Cría y destace de aves de corral', 'A'),
('012203', N'Huevos', 'A'),
('012204', N'Apicultura (miel)', 'A'),
('012299', N'Cría de otros animales n.c.p.', 'A'),
('013000', N'Cultivo de productos agrícolas en combinación con la cría de animales (explotación mixta)', 'A'),
('014001', N'Jardinería ornamental', 'A'),
('014002', N'servicios agrícolas, (no corresponde a siembra, solo mover la tierra )', 'A'),
('014099', N'Otras actividades de servicios agrícolas y ganaderos n.c.p.', 'A'),
('015000', N'Caza ordinaria y mediante trampas, y repoblación de animales de caza, incluso las actividades de servicios conexas', 'A'),
('020001', N'Silvicultura', 'A'),
('020002', N'Tala y corte', 'A'),
('020099', N'Extracción de madera y actividades de servicios conexas n.c.p.', 'A'),
('050101', N'Pesca de litoral', 'B'),
('050102', N'Pesca de alta mar', 'B'),
('050199', N'Otro tipo de pesca n.c.p.', 'B'),
('050201', N'Pescado', 'B'),
('050202', N'Camaron', 'B'),
('050299', N'Otras especies n.c.p.', 'B'),
('101000', N'Extracción y aglomeración de carbón de piedra', 'C'),
('102000', N'Extracción y aglomeración de lignito', 'C'),
('103000', N'Extracción y aglomeración de turba', 'C'),
('111000', N'Extracción de petróleo crudo y gas natural (perforación y explotación)', 'C'),
('112000', N'Actividades de servicios relacionadas con la extracción de petróleo y gas, excepto las actividades de prospección', 'C'),
('120000', N'Extracción de minerales de uranio y torio', 'C'),
('131001', N'Extracción de minerales de hierro', 'C'),
('131099', N'Extracción de otros minerales metalicos (plomo, plata, cromo etc.)', 'C'),
('132000', N'Extracción de minerales metalíferos no ferrosos, excepto los minerales de uranio y torio', 'C'),
('141000', N'Extracción de piedra, arena y arcilla', 'C'),
('142100', N'Extracción de minerales para la fabricación de abonos y productos químicos', 'C'),
('142200', N'Extracción de sal', 'C'),
('142900', N'Explotación de otras minas y canteras n.c.p.', 'C'),
('151101', N'Producción, procesamiento y conservación de carne y productos cárnicos', 'D'),
('151102', N'Matanza de ganado, matadero, rastro (ganado mayor y menor)', 'D'),
('151199', N'Producción, procesamiento y conservación de carne y productos cárnicos n.c.p.', 'D'),
('151200', N'Elaboración y conservación de pescado y productos de pescado', 'D'),
('151301', N'Legumbres congeladas y en conserva', 'D'),
('151302', N'Jugos de frutas y de legumbres', 'D'),
('151303', N'frutas preparadas o conservadas', 'D'),
('151399', N'otras frutas, legumbres y conservas n.c.p.', 'D'),
('151400', N'Elaboración de aceites y grasas de origen vegetal y animal', 'D'),
('152000', N'Elaboración de productos lácteos', 'D'),
('153101', N'Beneficio de café', 'D'),
('153102', N'Beneficio de Arroz', 'D'),
('153199', N'Elaboración de productos de molinería n.c.p.', 'D'),
('153200', N'Elaboración de almidones y productos derivados del almidón', 'D'),
('153300', N'Elaboración de alimentos preparados para animales', 'D'),
('154100', N'Elaboración de productos de panadería', 'D'),
('154201', N'Azucar de caña refinada (Ingenios)', 'D'),
('154202', N'Azucar de caña sin refinar (trapiches)', 'D'),
('154203', N'Melaza', 'D'),
('154299', N'Otros productos derivados de la caña de azucar n.c.p.', 'D'),
('154300', N'Elaboración de cacao y chocolate y de productos de confitería', 'D'),
('154400', N'Elaboración de macarrones, fideos, alcuzcuz y productos farináceos similares', 'D'),
('154901', N'Tortillería, elaboración de tamales', 'D'),
('154999', N'Elaboración de otros productos alimenticios n.c.p.', 'D'),
('155100', N'Destilación, rectificación y mezcla de bebidas alcohólicas; producción de alcohol etílico a partir de sustancias fermentadas', 'D'),
('155200', N'Elaboración de vinos', 'D'),
('155301', N'Fabrica de cerveza', 'D'),
('155399', N'Elaboración de otras bebidas malteadas y de malta n.c.p', 'D'),
('155401', N'Elaboración de bebidas no alcohólicas; producción de aguas minerales', 'D'),
('155499', N'Fabricación de bebidas no alcohólicas y aguas Gaseosas n.c.p.', 'D'),
('160001', N'Fabricación de cigarrillos', 'D'),
('160002', N'Fabricación de puros', 'D'),
('160099', N'Elaboración de productos de tabaco n.c.p.', 'D'),
('171100', N'Preparación e hilatura de fibras textiles; tejedura de productos textiles', 'D'),
('171201', N'Fabrica de tejdos de punto', 'D'),
('171202', N'Hilado, tejido y acabado de productos textiles', 'D'),
('171299', N'Acabado de productos textiles n.c.p.', 'D'),
('172100', N'Fabricación de artículos confeccionados de materiales textiles, excepto prendas de vestir', 'D'),
('172201', N'Fabricación de tapices y alfombras', 'D'),
('172299', N'Fabricación de tapices y alfombras, telas impermeabilizadas, vinil-polyester n.c.p.', 'D'),
('172300', N'Fabricación de cuerdas, cordeles, bramantes y redes', 'D'),
('172900', N'Fabricación de otros productos textiles n.c.p.', 'D'),
('173001', N'Articulos confeccionados con materiales textiles, excepto prendas de vestir', 'D'),
('173099', N'Fabricación de tejidos y artículos de punto y ganchillo n.c.p.', 'D'),
('181001', N'Fabricación de prendas de vestir, excepto prendas de piel', 'D'),
('180199', N'Fabricación de otras prendas de vestir n.c.p.', 'D'),
('182000', N'Adobo y teñido de pieles; fabricación de artículos de piel', 'D'),
('191100', N'Curtido y adobo de cueros', 'D'),
('191200', N'Fabricación de maletas, bolsos de mano y artículos similares, y de artículos de talabartería y guarnicionería', 'D'),
('192000', N'Fabricación de calzado', 'D'),
('201000', N'Aserrado y acepilladura de madera', 'D'),
('202100', N'Fabricación de hojas de madera para enchapado; fabricación de tableros contrachapados, tableros laminados, tableros de partículas y otros tableros y paneles', 'D'),
('202200', N'Fabricación de partes y piezas de carpintería para edificios y construcciones', 'D'),
('202300', N'Fabricación de recipientes de madera', 'D'),
('202900', N'Fabricación de otros productos de madera; fabricación de artículos de corcho, paja y materiales trenzables', 'D'),
('210100', N'Fabricación de pasta de madera, papel y cartón', 'D'),
('210200', N'Fabricación de papel y cartón ondulado y de envases de papel y cartón', 'D'),
('210900', N'Fabricación de otros artículos de papel y cartón', 'D'),
('221100', N'Edición de libros, folletos y otras publicaciones', 'D'),
('221200', N'Edición de periódicos, revistas y publicaciones periódicas', 'D'),
('221300', N'Edición de música', 'D'),
('221900', N'Otras actividades de edición', 'D'),
('222100', N'Actividades de impresión', 'D'),
('222200', N'Actividades de servicios relacionadas con la impresión', 'D'),
('223000', N'Reproducción de grabaciones', 'D'),
('231000', N'Fabricación de productos de hornos de coque', 'D'),
('232000', N'Fabricación de productos de la refinación del petróleo', 'D'),
('233000', N'Elaboración de combustible nuclear', 'D'),
('241100', N'Fabricación de sustancias químicas básicas, excepto abonos y compuestos de nitrógeno', 'D'),
('241200', N'Fabricación de abonos y compuestos de nitrógeno', 'D'),
('241300', N'Fabricación de plásticos en formas primarias y de caucho sintético', 'D'),
('242100', N'Fabricación de plaguicidas y otros productos químicos de uso agropecuario', 'D'),
('242200', N'Fabricación de pinturas, barnices y productos de revestimiento similares, tintas de imprenta y masillas', 'D'),
('242300', N'Fabricación de productos farmacéuticos, sustancias químicas medicinales y productos botánicos', 'D'),
('242400', N'Fabricación de jabones y detergentes, preparados para limpiar y pulir, perfumes y preparados de tocador', 'D'),
('292901', N'Pirotecnia, fabricación de cohetes, bombas y otros fuegos artificiales', 'D'),
('292902', N'Fabricación de fósforos', 'D'),
('292999', N'Fabricación de otros productos químicos n.c.p.', 'D'),
('243000', N'Fabricación de fibras artificiales', 'D'),
('251100', N'Fabricación de cubiertas y cámaras de caucho; recauchutado y renovación de cubiertas de caucho', 'D'),
('251900', N'Fabricación de otros productos de caucho', 'D'),
('252000', N'Fabricación de productos de plástico', 'D'),
('261000', N'Fabricación de vidrio y productos de vidrio', 'D'),
('269100', N'Fabricación de productos de cerámica no refractaria para uso no estructural', 'D'),
('269200', N'Fabricación de productos de cerámica refractaria', 'D'),
('269301', N'Fabrica de Block', 'D'),
('269302', N'Fabrica de Ladrillo, Teja, etc.', 'D'),
('269399', N'Fabricación de otros productos de arcilla y cerámica no refractarias para uso estructural', 'D'),
('269401', N'Cemento', 'D'),
('269499', N'Cal, yeso y derivados n.c.p.', 'D'),
('269500', N'Fabricación de artículos de hormigón, cemento y yeso', 'D'),
('269600', N'Corte, tallado y acabado de la piedra', 'D'),
('269900', N'Fabricación de otros productos minerales no metálicos n.c.p.', 'D'),
('271000', N'Industrias básicas de hierro y acero', 'D'),
('272000', N'Fabricación de productos primarios de metales preciosos y metales no ferrosos', 'D'),
('273100', N'Fundición de hierro y acero', 'D'),
('273201', N'Fundición de metales no ferrosos', 'D'),
('273299', N'Fundición de metales no ferrosos n.c.p.', 'D'),
('281100', N'Fabricación de productos metálicos para uso estructural', 'D'),
('281200', N'Fabricación de tanques, depósitos y recipientes de metal', 'D'),
('281300', N'Fabricación de generadores de vapor, excepto calderas de agua caliente para calefacción central', 'D'),
('289101', N'Forja, prensado, estampado y laminado de metales; pulvimetalurgia', 'D'),
('289199', N'Fabricación de otros artìculos de metal', 'D'),
('289200', N'Tratamiento y revestimiento de metales; obras de ingeniería mecánica en general realizadas a cambio de una retribución o por contrato', 'D'),
('289300', N'Fabricación de artículos de cuchillería, herramientas de mano y artículos de ferretería', 'D'),
('289900', N'Fabricación de otros productos elaborados de metal n.c.p.', 'D'),
('291100', N'Fabricación de motores y turbinas, excepto motores para aeronaves, vehículos automotores y motocicletas', 'D'),
('291200', N'Fabricación de bombas, compresores, grifos y válvulas', 'D'),
('291300', N'Fabricación de cojinetes, engranajes, trenes de engranajes y piezas de transmisión', 'D'),
('291400', N'Fabricación de hornos, hogares y quemadores', 'D'),
('291500', N'Fabricación de equipo de elevación y manipulación', 'D'),
('291900', N'Fabricación de otros tipos de maquinaria de uso general', 'D'),
('292100', N'Fabricación de maquinaria agropecuaria y forestal', 'D'),
('292200', N'Fabricación de máquinas herramienta', 'D'),
('292300', N'Fabricación de maquinaria metalúrgica', 'D'),
('292400', N'Fabricación de maquinaria para la explotación de minas y canteras y para obras de construcción', 'D'),
('292500', N'Fabricación de maquinaria para la elaboración de alimentos, bebidas y tabaco', 'D'),
('292600', N'Fabricación de maquinaria para la elaboración de productos textiles, prendas de vestir y cueros', 'D'),
('292700', N'Fabricación de armas y municiones', 'D'),
('292900', N'Fabricación de otros tipos de maquinaria de uso especial', 'D'),
('293000', N'Fabricación de aparatos de uso doméstico n.c.p.', 'D'),
('300000', N'Fabricación de maquinaria de oficina, contabilidad e informática', 'D'),
('311001', N'Construcción y reparación de maquinaria, aparatos y articulos electricos', 'D'),
('311099', N'Fabricación de motores, generadores y transformadores eléctricos', 'D'),
('312000', N'Fabricación de aparatos de distribución y control de la energía eléctrica', 'D'),
('313000', N'Fabricación de hilos y cables aislados', 'D'),
('314000', N'Fabricación de acumuladores y de pilas y baterías primarias', 'D'),
('315000', N'Fabricación de lámparas eléctricas y equipo de iluminación', 'D'),
('319000', N'Fabricación de otros tipos de equipo eléctrico n.c.p.', 'D'),
('321000', N'Fabricación de tubos y válvulas electrónicos y de otros componentes electrónicos', 'D'),
('322000', N'Fabricación de transmisores de radio y televisión y de aparatos para telefonía y telegrafía con hilos', 'D'),
('323000', N'Fabricación de receptores de radio y televisión, aparatos de grabación y reproducción de sonido y vídeo, y productos conexos', 'D'),
('331100', N'Fabricación de equipo médico y quirúrgico y de aparatos ortopédicos', 'D'),
('331200', N'Fabricación de instrumentos y aparatos para medir, verificar, ensayar, navegar y otros fines, excepto el equipo de control de procesos industriales', 'D'),
('331300', N'Fabricación de equipo de control de procesos industriales', 'D'),
('332000', N'Fabricación de instrumentos de óptica y equipo fotográfico', 'D'),
('333001', N'Fabricación de relojes', 'D'),
('333002', N'Reparación de relojes', 'D'),
('341000', N'Fabricación de vehículos automotores', 'D'),
('342000', N'Fabricación de carrocerías para vehículos automotores; fabricación de remolques y semirremolques', 'D'),
('343000', N'Fabricación de partes, piezas y accesorios para vehículos automotores y sus motores', 'D'),
('351100', N'Construcción y reparación de buques', 'D'),
('351200', N'Construcción y reparación de embarcaciones de recreo y deporte', 'D'),
('352000', N'Fabricación de locomotoras y de material rodante para ferrocarriles y tranvías', 'D'),
('353000', N'Fabricación de aeronaves y naves espacia', 'D'),
('359100', N'Fabricación de motocicletas', 'D'),
('359200', N'Fabricación de bicicletas y de sillones de ruedas para inválidos', 'D'),
('359900', N'Fabricación de otros tipos de equipo de transporte n.c.p.', 'D'),
('361000', N'Fabricación de muebles', 'D'),
('369100', N'Fabricación de joyas y artículos conexos', 'D'),
('369200', N'Fabricación de instrumentos de música', 'D'),
('369300', N'Fabricación de artículos de deporte', 'D'),
('369400', N'Fabricación de juegos y juguetes', 'D'),
('369901', N'Maquila de vestuario y textiles', 'D'),
('369902', N'Fabrica de piñatas y similares', 'D'),
('369999', N'Otras industrias manufactureras n.c.p.', 'D'),
('371000', N'Reciclado de desperdicios y desechos metálicos', 'D'),
('372000', N'Reciclado de desperdicios y desechos no metálicos', 'D'),
('401000', N'Generación, captación y distribución de energía eléctrica', 'E'),
('402000', N'Fabricación de gas; distribución de combustibles gaseosos por tuberías', 'E'),
('403000', N'Suministro de vapor y agua caliente', 'E'),
('410001', N'Captación, depuración y distribución de agua', 'E'),
('410099', N'Otro tipo de captación y depuración de agua n.c.p.', 'E'),
('451001', N'Demolición y preparación de terrenos para la construcción de edificaciones', 'F'),
('451002', N'Preparación de terrenos para obras civiles (obras privadas)', 'F'),
('451003', N'Construcción y reparación de caminos (oficial del Estado)', 'F'),
('451099', N'Preparación del terreno n.c.p.', 'F'),
('452001', N'Construcción de edificaciones para uso residencial', 'F'),
('452002', N'Construcción de edificaciones para uso no residencial (obras privadas)', 'F'),
('452003', N'Construcción y reparación de obras publicas, municipales y de otras entidades publicas', 'F'),
('452004', N'Construcción y reparación de obras privadas, demolición, excavación, drenajes, perforación de pozos, urbanización (obras privadas)', 'F'),
('452099', N'Otras construcciones de edificaciones y obras de ingeniería civil n.c.p.', 'F'),
('453001', N'Instalaciones hidraulicas y trabajos conexos', 'F'),
('453002', N'Trabajos de electricidad', 'F'),
('453003', N'Trabajos de instalación de equipos', 'F'),
('453099', N'Otros trabajos de acondicionamiento n.c.p.', 'F'),
('454001', N'Ornamentaciòn e intalaciòn de vidrios y ventanas', 'F'),
('454002', N'Trabajos de pintura y terminaciòn de muros y pisos', 'F'),
('454003', N'Trabajos de instalaciòn de puertas y balcones', 'F'),
('454099', N'Otros trabajos de terminaciòn y acabados n.c.p.', 'F'),
('455000', N'Alquiler de equipo de construcción o demolición con operarios', 'F'),
('501000', N'Venta de vehículos automotores', 'G'),
('502001', N'Mecanica de vehiculos automotores', 'G'),
('502002', N'Enderezado y pintura para vehiculos automotores', 'G'),
('502003', N'Electricos y electronicos para vehiculos automotores', 'G'),
('502004', N'Reparaciòn de radiadores, escapes, aros y llantas', 'G'),
('502005', N'Mantenimiento, revisión y alineaciòn (sistema de frenos, aros, llantas, etc.)', 'G'),
('502099', N'Otros servicios de mantenimiento y reparaciòn a vehiculos automotores', 'G'),
('503000', N'Ventas de partes, piezas y accesorios de vehículos automotores', 'G'),
('504000', N'Venta, mantenimiento y reparación de motocicletas y de sus partes, piezas y accesorios', 'G'),
('505000', N'Venta al por menor de combustible para automotores (gasolineras)', 'G'),
('511000', N'Venta al por mayor a cambio de una retribución o por contrato', 'G'),
('512100', N'Venta al por mayor de materias primas agropecuarias y de animales vivos', 'G'),
('512200', N'Venta al por mayor de alimentos, bebidas y tabaco', 'G'),
('513100', N'Venta al por mayor de productos textiles, prendas de vestir y calzado', 'G'),
('513900', N'Venta al por mayor de otros enseres domésticos', 'G'),
('514101', N'Venta al mayoreo de bunker, gas, gasolina y diesel.', 'G'),
('514102', N'Venta al mayoreo de Gas propano', 'G'),
('514199', N'Otras ventas al mayoreo de combustibles sòlidos, lìquidos y gaseosos y de productos conexos n.c.p.', 'G'),
('514200', N'Venta al por mayor de metales y minerales metalíferos', 'G'),
('514300', N'Venta al por mayor de materiales de construcción, artículos de ferretería y equipo y materiales de fontanería y calefacción', 'G'),
('514900', N'Venta al por mayor de otros productos intermedios, desperdicios y desechos', 'G'),
('515100', N'Venta al por mayor de ordenadores, equipo periférico y programas informáticos', 'G'),
('515200', N'Venta al por mayor de partes y equipo electrónicos y de comunicaciones', 'G'),
('515900', N'Venta al por mayor de otros tipos de maquinaria, equipo y materiales', 'G'),
('519000', N'Venta al por mayor de otros productos', 'G'),
('521100', N'Venta al por menor en almacenes no especializados con surtido compuesto principalmente de alimentos, bebidas y tabaco', 'G'),
('521900', N'Venta al por menor de otros productos en almacenes no especializados', 'G'),
('522000', N'Venta al por menor de alimentos, bebidas y tabaco en almacenes especializados', 'G'),
('523100', N'Venta al por menor de productos farmacéuticos y medicinales, cosméticos y artículos de tocador', 'G'),
('523200', N'Venta al por menor de productos textiles, prendas de vestir, calzado y artículos de cuero', 'G'),
('523300', N'Venta al por menor de aparatos, artículos y equipo de uso doméstico', 'G'),
('523400', N'Venta al por menor de artículos de ferretería, pinturas y productos de vidrio', 'G'),
('523900', N'Venta al por menor de otros productos en almacenes especializados', 'G'),
('524000', N'Venta al por menor en almacenes de artículos usados', 'G'),
('525100', N'Venta al por menor de casas de venta por correo', 'G'),
('525200', N'Venta al por menor en puestos de venta y mercados', 'G'),
('525900', N'Otros tipos de venta al por menor no realizada en almacenes', 'G'),
('526000', N'Reparación de efectos personales y enseres domésticos', 'G'),
('551001', N'Hoteles', 'H'),
('551002', N'Campamentes', 'H'),
('551099', N'Otros tipos de hospedaje temporal n.c.p.', 'H'),
('552001', N'Restaurantes, Comedores y cafeterias', 'H'),
('552002', N'Bares y Cantinas', 'H'),
('552099', N'Otros restaurantes, bares y cantinas n.c.p.', 'H'),
('601000', N'Transporte por vía férrea', 'I'),
('602101', N'Transporte urbano regular de pasajeros.', 'I'),
('602102', N'Transporte extraurbano regular de pasajeros', 'I'),
('602199', N'Otro tipo de transporte regular por vía terrestre n.c.p.', 'I'),
('602201', N'Servicio de Taxis', 'I'),
('602202', N'Servicio de limosinas y alquiler de vehiculos', 'I'),
('602203', N'Transporte por animales', 'I'),
('602299', N'Otros tipos de transporte no regular de pasajeros por vía terrestre N.C.P.', 'I'),
('602301', N'Transporte motorizado de carga por carretera', 'I'),
('602399', N'Transporte de carga por carretera n.c.p.', 'I'),
('603000', N'Transporte por tuberías', 'I'),
('611000', N'Transporte marítimo y de cabotaje', 'I'),
('612000', N'Transporte por vías de navegación interiores', 'I'),
('621000', N'Transporte regular por vía aérea', 'I'),
('622000', N'Transporte no regular por vía aérea', 'I'),
('630100', N'Manipulación de la carga', 'I'),
('630200', N'Almacenamiento y depósito', 'I'),
('630301', N'Servicio de Gruas', 'I'),
('630399', N'Otras actividades de transporte complementarias n.c.p.', 'I'),
('630400', N'Actividades de agencias de viajes y organizadores de viajes; actividades de asistencia a turistas n.c.p.', 'I'),
('630900', N'Actividades de otras agencias de transporte', 'I'),
('641100', N'Actividades postales nacionales', 'I'),
('641200', N'Actividades de correo distintas de las actividades postales nacionales', 'I'),
('642001', N'Telefonia fija', 'I'),
('642002', N'Telefonia celular', 'I'),
('642099', N'Otras telecomunicaciones n.c.p.', 'I'),
('651100', N'Banca central', 'J'),
('651901', N'Bancos Privados', 'J'),
('651902', N'Cajas de ahorro, institutciones de credito y cooperativas de ahorro y credito', 'J'),
('651999', N'Otros tipos de intermediaciòn monetaria n.c.p.', 'J'),
('659100', N'Arrendamiento financiero', 'J'),
('659200', N'Otros tipos de crédito', 'J'),
('659901', N'Intermediación financierarealizada por instituciones de credito distintas de los bancos n.c.p.', 'J'),
('659902', N'Distribución de fondos por medios distintos del otorgamiento de prestamos', 'J'),
('659999', N'Otros tipos de intermediación financiera n.c.p.', 'J'),
('660100', N'Planes de seguros de vida', 'J'),
('660200', N'Planes de pensiones', 'J'),
('660300', N'Planes de seguros generales', 'J'),
('671100', N'Administración de mercados financieros', 'J'),
('671200', N'Actividades bursátiles', 'J'),
('671900', N'Actividades auxiliares de la intermediación financiera n.c.p.', 'J'),
('672000', N'Actividades auxiliares de la financiación de planes de seguros y de pensiones', 'J'),
('701000', N'Actividades inmobiliarias realizadas con bienes propios o arrendados', 'K'),
('702000', N'Actividades inmobiliarias realizadas a cambio de una retribución o por contrata', 'K'),
('711100', N'Alquiler de equipo de transporte por vía terrestre', 'K'),
('711200', N'Alquiler de equipo de transporte por vía acuática', 'K'),
('711300', N'Alquiler de equipo de transporte por vía aérea', 'K'),
('712100', N'Alquiler de maquinaria y equipo agropecuario', 'K'),
('712200', N'Alquiler de maquinaria y equipo de construcción e ingeniería civil', 'K'),
('712300', N'Alquiler de maquinaria y equipo de oficina (incluso ordenadores)', 'K'),
('712900', N'Alquiler de otros tipos de maquinaria y equipo n.c.p.', 'K'),
('713000', N'Alquiler de efectos personales y enseres domésticos n.c.p.', 'K'),
('721000', N'Consultores en equipo de informática', 'K'),
('722100', N'Edición de programas de informática', 'K'),
('722900', N'Otras actividades de consultores en programas de informática y suministro de programas de informática', 'K'),
('723000', N'Procesamiento de datos', 'K'),
('724000', N'Actividades relacionadas con bases de datos y distribución en línea de contenidos electrónicos', 'K'),
('725000', N'Mantenimiento y reparación de maquinaria de oficina, contabilidad e informática', 'K'),
('729000', N'Otras actividades de informática', 'K'),
('731000', N'Investigaciones y desarrollo experimental en el campo de las ciencias naturales y la ingeniería', 'K'),
('732000', N'Investigaciones y desarrollo experimental en el campo de las ciencias sociales y las humanidades', 'K'),
('741101', N'Abogado', 'K'),
('741102', N'Notario', 'K'),
('741199', N'Otras Actividades jurídicas n.c.p.', 'K'),
('741201', N'Contador Público y Auditor', 'K'),
('741202', N'Perito Contador', 'K'),
('741299', N'Otras actividades de contabilidad, teneduría de libros y auditoría; asesoramiento en materia de impuestos', 'K'),
('741300', N'Investigación de mercados y realización de encuestas de opinión pública', 'K'),
('741401', N'Administrador de empresas', 'K'),
('741402', N'Economista', 'K'),
('741403', N'Actuario', 'K'),
('741499', N'Otras actividades de asesoramiento empresarial y en materia de gestión', 'K'),
('742101', N'Arquitecto', 'K'),
('742102', N'Ingeniero (en todas las ramas)', 'K'),
('742103', N'Constructores', 'K'),
('742104', N'Topografos', 'K'),
('742199', N'Otras actividades de arquitectura e ingeniería y actividades conexas de asesoramiento técnico', 'K'),
('742200', N'Ensayos y análisis técnicos', 'K'),
('743000', N'Publicidad', 'K'),
('749100', N'Obtención y dotación de personal', 'K'),
('749200', N'Actividades de investigación y seguridad', 'K'),
('749300', N'Actividades de limpieza de edificios y limpieza industrial', 'K'),
('749400', N'Actividades de fotografía (revelado e impresiòn de películas fotograficas, retratos etc. Y fotocopias)', 'K'),
('749500', N'Actividades de envase y empaque', 'K'),
('749901', N'Policia privada, traslado de valores , investigaciones privadas etc.', 'K'),
('749999', N'Otras actividades empresariales n.c.p.', 'K'),
('751101', N'Municipalidades', 'L'),
('751102', N'Tribunales, ministerio publico,  procuraduria de derechos humanos, etc.', 'L'),
('751103', N'Ministerios, Congreso Nacional,  Direcciones Generales,  Superintendencias, Contralorìa, aduanas,  fomento y desarrollo', 'L'),
('751199', N'Otras actividades de la administración pública en general n.c.p.', 'L'),
('751200', N'Regulación de las actividades de organismos que prestan servicios sanitarios, educativos, culturales y otros servicios sociales, excepto servicios de seguridad social', 'L'),
('751300', N'Regulación y facilitación de la actividad económica', 'L'),
('751400', N'Actividades de servicios de apoyo para la administración pública en general', 'L'),
('752100', N'Relaciones exteriores', 'L'),
('752200', N'Actividades de defensa', 'L'),
('752301', N'Policia nacional, Policia penitenciaria, etc.', 'L'),
('752399', N'Otras actividades de mantenimiento del orden público y de seguridad n.c.p.', 'L'),
('753000', N'Actividades de planes de seguridad social de afiliación obligatoria', 'L'),
('801000', N'Enseñanza primaria', 'M'),
('802100', N'Enseñanza secundaria de formación general', 'M'),
('802200', N'Enseñanza secundaria de formación técnica y profesional', 'M'),
('803001', N'Enseñanza superior (Universidad Nacional)', 'M'),
('803002', N'Enseñanza superior (Universidades Privadas)', 'M'),
('809000', N'Otros tipos de enseñanza', 'M'),
('851100', N'Actividades de hospitales', 'N'),
('851201', N'Médico cirujano o especialista', 'N'),
('851202', N'Oftalmologo y optometrista', 'N'),
('851203', N'Dentista y odontologo', 'N'),
('851204', N'Psiquiatra o Psicologo', 'N'),
('851205', N'Quimico Biologo o Farmaceutico', 'N'),
('851206', N'Fisioterapista, traumatologo, keynesiologo', 'N'),
('851299', N'Otras actividades de médicos y odontólogos n.c.p.', 'N'),
('851901', N'Enfermero y paramedio', 'N'),
('851902', N'Mecanico dental', 'N'),
('851903', N'Analista de laboratorio', 'N'),
('851999', N'Otras actividades relacionadas con la salud humana n.c.p.', 'N'),
('852000', N'Actividades veterinarias', 'N'),
('853100', N'Servicios sociales con alojamiento', 'N'),
('853200', N'Servicios sociales sin alojamiento', 'N'),
('900000', N'Eliminación de desperdicios y aguas residuales, saneamiento y actividades similares', 'O'),
('911100', N'Actividades de organizaciones empresariales y de empleadores', 'O'),
('911200', N'Actividades de organizaciones profesionales', 'O'),
('912000', N'Actividades de sindicatos', 'O'),
('919100', N'Actividades de organizaciones religiosas', 'O'),
('919200', N'Actividades de organizaciones políticas', 'O'),
('919901', N'Organizaciones no gubernamentales de asistencia social sin ánimo de lucro', 'O'),	-- la plantilla trae el código vacío; 919901 por la secuencia
('919902', N'Institucioes gubernamentales de asistencia social n.c.p.', 'O'),
('919999', N'Actividades de otras instituciones de bienestar a la comunidad  n.c.p.', 'O'),
('921100', N'Producción y distribución de filmes y videocintas', 'O'),
('921200', N'Exhibición de filmes y videocintas', 'O'),
('921300', N'Actividades de radio y televisión', 'O'),
('921401', N'Musicales', 'O'),
('921402', N'Pintura', 'O'),
('921403', N'Modelaje', 'O'),
('921404', N'Artistas', 'O'),
('921405', N'Tecnicos en sonido, video y luces', 'O'),
('921499', N'Otras ctividades de arte, teatro, musicales y artísticas n.c.p.', 'O'),
('921900', N'Otras actividades de entretenimiento n.c.p.', 'O'),
('922000', N'Actividades de agencias de noticias', 'O'),
('923100', N'Actividades de bibliotecas y archivos', 'O'),
('923200', N'Actividades de museos y preservación de lugares y edificios históricos', 'O'),
('923300', N'Actividades de jardines botánicos y zoológicos y de parques nacionales', 'O'),
('924100', N'Actividades deportivas', 'O'),
('924900', N'Otras actividades de esparcimiento', 'O'),
('930100', N'Lavado y limpieza de prendas de tela y de piel, incluso la limpieza en seco', 'O'),
('930201', N'Depilaciones, pedicuristas, peluqueros y otros tratamientos de belleza', 'O'),
('930202', N'Barbero', 'O'),
('930299', N'Otras actividades de Peluquería y  tratamientos de belleza n.c.p.', 'O'),
('930300', N'Pompas fúnebres y actividades conexas', 'O'),
('930900', N'Otras actividades de servicios n.c.p.', 'O'),
('950000', N'Actividades de hogares privados como empleadores de personal doméstico', 'P'),
('960000', N'Actividades no diferenciadas de hogares privados como productores de bienes para uso propio', 'P'),
('970000', N'Actividades no diferenciadas de hogares privados como productores de servicios para uso propio', 'P'),
('990000', N'Organizaciones y órganos extraterritoriales', 'Q')
) v (Codigo, Descripcion, Categoria)
WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssActividadEconomica t WHERE t.Codigo = v.Codigo);
GO
INSERT INTO dbo.rrhhIgssOcupacion (Codigo, Descripcion)
SELECT v.* FROM (VALUES
('0110', N'Miembros de las fuerzas armadas'),
('1110', N'Miembros del poder ejecutivo y de los cuerpos legislativos'),
('1120', N'Personal directivo de la administración pública'),
('1130', N'Jefes de pequeñas poblaciones'),
('1141', N'Dirigentes y administradores de partidos políticos'),
('1142', N'Dirigentes y administradores de organizaciones de empleadores, de trabajadores y de otras de interés socioeconómico'),
('1143', N'Dirigentes y administradores de organizaciones humanitarias y de otras organizaciones'),
('1210', N'Directores generales y gerentes generales de empresas'),
('1221', N'Directores de departamentos de producción y operaciones, agricultura, caza, silvicultura y pesca'),
('1222', N'Directores de departamentos de producción y operaciones, industrias manufactureras'),
('1223', N'Directores de departamentos de producción y operaciones, construcción y obras públicas'),
('1224', N'Directores de departamentos de producción y operaciones, comercio mayorista y minorista'),
('1225', N'Directores de departamentos de producción y operaciones, restauración y hostelería'),
('1226', N'Directores de departamentos de producción y operaciones, transporte, almacenamiento y comunicaciones'),
('1227', N'Directores de departamentos de producción y operaciones, empresas de intermediación y servicios a empresas'),
('1228', N'Directores de departamentos de producción y operaciones, servicios de cuidados personales, limpieza y servicios similares'),
('1229', N'Directores de departamentos de producción y operaciones no clasificados bajo otros epígrafes.'),
('1231', N'Directores de departamentos financieros y administrativos'),
('1232', N'Directores de departamentos de personal y de relaciones laborales'),
('1233', N'Directores de departamentos de ventas y comercialización'),
('1234', N'Directores de departamentos de publicidad y de relaciones públicas'),
('1235', N'Directores de departamentos de abastecimiento y distribución'),
('1236', N'Directores de departamentos de servicios de informática'),
('1237', N'Directores de departamento de investigaciones y desarrollo'),
('1239', N'Otros directores de departamentos, no clasificados bajo otros epígrafes'),
('1311', N'Gerentes de empresa de agricultura, caza, silvicultura y pesca'),
('1312', N'Gerentes de industrias manufactureras'),
('1313', N'Gerentes de empresas de construcción y obras públicas'),
('1314', N'Gerentes de comercios mayoristas y minoristas'),
('1315', N'Gerentes de empresas de restauración y hostelería'),
('1316', N'Gerentes de empresas de transporte, almacenamiento y comunicaciones'),
('1317', N'Gerentes de empresas de intermediación y servicios a empresas'),
('1318', N'Gerentes de empresas de servicios de cuidados personales, limpieza y servicios similares'),
('1319', N'Gerentes de empresas no clasificados bajo otros epígrafes'),
('2111', N'Físicos y astrónomos'),
('2112', N'Meteorólogos'),
('2113', N'Químicos'),
('2114', N'Geólogos y geofísicos'),
('2121', N'Matemáticos y afines'),
('2122', N'Estadísticos'),
('2131', N'Creadores y analistas de sistemas informáticos'),
('2132', N'Programadores informáticos y obras públicas'),
('2139', N'Profesionales de la informática no clasificados bajo otros epígrafes'),
('2141', N'Arquitectos, urbanistas e ingenieros de tránsito'),
('2142', N'Ingenieros civiles'),
('2143', N'Ingenieros electricistas'),
('2144', N'Ingenieros electronicistas y de telecomunicaciones'),
('2145', N'Ingenieros mecánicos'),
('2146', N'Ingenieros Químicos'),
('2147', N'Ingenieros de minas y metalúrgicos y afines'),
('2148', N'Cartógrafos y agrimensores'),
('2149', N'Arquitectos, ingenieros y afines no clasificados bajo otros epígrafes'),
('2211', N'Biólogos, botánicos, zoólogos y afines'),
('2212', N'Farmacólogos, patólogos y afines'),
('2213', N'Agrónomo y afines'),
('2221', N'Médicos'),
('2222', N'Odontólogos'),
('2223', N'Veterinarios'),
('2224', N'Farmacéuticos'),
('2229', N'Médicos y profesionales afines (excepto el personal de enfermería y partería) no clasificados bajo otros epígrafes'),
('2230', N'Personal de enfermería y partería a nivel superior'),
('2310', N'Profesores de universidades y otros establecimientos de la enseñanza superior'),
('2320', N'Profesores de la enseñanza secundaria'),
('2331', N'Maestros de nivel superior de la enseñanza primaria'),
('2332', N'Maestros de nivel superior de la enseñanza preescolar'),
('2340', N'Maestros e instructores de nivel superior de la enseñanza especial'),
('2351', N'Especialistas en métodos pedagógicos y material didáctico'),
('2352', N'Inspectores de la enseñanza'),
('2359', N'Otros profesionales de la enseñanza, no clasificados bajo otros epígrafes'),
('2411', N'Contadores'),
('2412', N'Especialistas en políticas y servicios de personal y afines'),
('2419', N'Especialistas en organización y administración de empresas afines, no clasificados bajo otros epígrafes'),
('2421', N'Abogados'),
('2422', N'Jueces'),
('2429', N'profesionales del derecho, no clasificados bajo otros epígrafes'),
('2431', N'Archiveros y conservadores de museos'),
('2432', N'Bibliotecarios, documentalistas y afines'),
('2441', N'Economistas'),
('2442', N'Sociólogos, antropólogos y afines'),
('2443', N'Filósofos, historiadores y especialistas en ciencias políticas'),
('2444', N'Traductores e intérpretes'),
('2445', N'Psicólogos'),
('2446', N'Profesionales del trabajo social'),
('2451', N'Autores, periodistas y otros escritores'),
('2452', N'Escultores, pintores y afines'),
('2453', N'Compositores, músicos y cantantes'),
('2454', N'Coreógrafos y bailarines'),
('2455', N'Actores y directores de cine, radio, teatro, televisión y afines'),
('2460', N'Sacerdotes de distintas religiones'),
('3111', N'Técnicos en ciencias físicas y Químicas'),
('3112', N'Técnicos en ingeniería civil'),
('3113', N'Electrotécnicos'),
('3114', N'Técnicos en electrónica y telecomunicaciones'),
('3115', N'Técnicos en mecánica y construcción mecánica'),
('3116', N'Técnicos en química industrial'),
('3117', N'Técnicos en ingeniería de minas y metalurgia'),
('3118', N'Delineantes y dibujantes técnicos'),
('3119', N'Técnicos en ciencias físicas y químicas y en ingeniería, no clasificados bajo otros epígrafes'),
('3121', N'Técnicos en programación informática'),
('3122', N'Técnicos en control de equipos informáticos'),
('3123', N'Técnicos en control de robots industriales'),
('3131', N'Fotógrafos y operadores de equipos de grabación de imagen y sonido'),
('3132', N'Operadores de equipos de radiodifusión, televisión y telecomunicaciones'),
('3133', N'Operadores de aparatos de diagnóstico y tratamiento médicos'),
('3139', N'Operadores de quipos ópticos y electrónicos, no clasificados bajo otros epígrafes'),
('3141', N'Oficiales maquinistas'),
('3142', N'Capitanes, oficiales de Cubierta y Prácticos'),
('3143', N'Pilotos de aviación y afines'),
('3144', N'Controladores de tráfico aéreo'),
('3145', N'Técnicos en seguridad aeronáutica'),
('3151', N'Inspectores de edificios y de prevención e investigación de incendios'),
('3152', N'Inspectores de seguridad y salud y control de calidad'),
('3211', N'Técnicos en ciencias biológicas y afines'),
('3212', N'Técnicos en agronomía, zootecnia y silvicultura'),
('3213', N'Consejeros agrícolas y forestales'),
('3221', N'Practicantes y asistentes médicos'),
('3222', N'Higienistas y otro personal sanitario'),
('3223', N'Técnicos en dietética y nutrición'),
('3224', N'Técnicos en optometría y ópticos'),
('3225', N'Dentistas auxiliares y ayudantes de odontología'),
('3226', N'Fisioterapeutas y afines'),
('3227', N'Técnicos y asistentes veterinarios'),
('3228', N'Técnicos y asistentes farmacéuticos'),
('3229', N'Profesionales de nivel medio de la medicina moderna y la salud (excepto el personal de enfermería y partería), no clasificados bajo otros epígrafes'),
('3231', N'Personal de enfermería de nivel medio'),
('3232', N'Personal de partería de nivel medio'),
('3241', N'Practicantes de la medicina tradicional'),
('3242', N'Curanderos'),
('3310', N'Maestros de nivel medio de la enseñanza primaria'),
('3320', N'Maestros de nivel medio de la enseñanza preescolar'),
('3330', N'Maestros de nivel medio de la enseñanza especial'),
('3340', N'Otros maestros e instructores de nivel medio'),
('3411', N'Agentes de bolsa, cambio y otros servicios financieros'),
('3412', N'Agentes de seguros'),
('3413', N'Agentes inmobiliarios'),
('3414', N'Agentes de viajes'),
('3415', N'Representantes comerciales y técnicos de ventas'),
('3416', N'Compradores'),
('3417', N'Tasadores y subastadores'),
('3419', N'Profesionales de nivel medio en operaciones financiera y comerciales, no clasificados bajo otros epígrafes'),
('3421', N'Agentes de comprar y consignatarios'),
('3422', N'Declarantes o gestores de aduana'),
('3423', N'Agentes públicos y privados de colocación y contratistas de mano de obra'),
('3429', N'Agentes comerciales y corredores, no clasificados bajo otros epígrafes'),
('3431', N'Profesionales de nivel medio de servicios administrativos afines'),
('3432', N'Profesionales de nivel medio del derecho y servicios legales o afines'),
('3433', N'Tenedores de libros'),
('3434', N'Profesionales de nivel medio de servicios estadísticos, matemáticos y afines'),
('3439', N'Profesionales de nivel medio de servicios de administración, no clasificados bajo otros epígrafes'),
('3441', N'Agentes de aduana e inspectores de fronteras'),
('3442', N'Funcionarios del fisco'),
('3443', N'Funcionarios de servicios de seguridad social'),
('3444', N'Funcionarios de servicios de expedición de licencias y permisos'),
('3449', N'Agentes de las administraciones públicas de aduanas, impuestos y afines, no clasificados bajo otros epígrafes'),
('3450', N'Inspectores de policía y detectives'),
('3460', N'Trabajadores asistentes sociales de nivel medio'),
('3471', N'Decoradores y diseñadores'),
('3472', N'Locutores de radio y televisión y afines'),
('3473', N'Músicos, cantantes y bailarines callejeros, de cabaret y afines'),
('3474', N'Payasos, prestidigitadores, acróbatas y afines'),
('3475', N'Atletas, deportistas y afines'),
('3480', N'Auxiliares laicos de los cultos'),
('4111', N'Taquígrafos y mecanógrafos'),
('4112', N'Operadores de máquinas de tratamiento de textos y afines'),
('4113', N'Operadores de entrada de datos'),
('4114', N'Operadores de calculadoras'),
('4115', N'Secretarios'),
('4121', N'Empleados de contabilidad y cálculo de costos'),
('4122', N'Empleados de servicios estadísticos y financieros'),
('4131', N'Empleados de control de abastecimientos e inventario'),
('4132', N'Empleados de servicios de apoyo a la producción'),
('4133', N'Empleados de servicios de transporte'),
('4141', N'Empleados de bibliotecas y archivos'),
('4142', N'Empleados de servicios de correos'),
('4143', N'Codificadores de datos, correctores de pruebas de imprenta y afines'),
('4144', N'Escribientes públicos y afines'),
('4190', N'Otros oficinistas'),
('4211', N'Cajeros y expendedores de billetes'),
('4212', N'Pegadores y cobradores de ventanilla y taquilleros'),
('4213', N'Receptores de apuestas y afines'),
('4214', N'Prestamistas'),
('4215', N'Cobradores y afines'),
('4221', N'Empleados de agencias de viajes'),
('4222', N'Recepcionistas y empleados de informaciones'),
('4223', N'telefonistas'),
('5111', N'Camareros y azafatas'),
('5112', N'Revisores, guardas y cobradores de los transportes públicos'),
('5113', N'Guías'),
('5121', N'Ecónomos, mayordomos y afines'),
('5122', N'Cocineros'),
('5123', N'Camareros y taberneros'),
('5131', N'Niñeras y celadoras infantiles'),
('5132', N'Ayudantes de enfermería en instituciones'),
('5133', N'Ayudantes de enfermería a domicilio'),
('5139', N'Trabajadores de los cuidados personales y afines, no clasificados bajo otros epígrafes'),
('5141', N'Peluqueros, especialistas en tratamiento de belleza y afines'),
('5142', N'Acompañantes y ayudas de cámara'),
('5143', N'Personal de pompas fúnebres y embalsamadores'),
('5149', N'Otros trabajadores de servicios personales a particulares, clasificados bajo otros epígrafes'),
('5151', N'Astrólogos y afines'),
('5152', N'Adivinadores, quirománticos y afines'),
('5161', N'Bomberos'),
('5162', N'Policías'),
('5163', N'Guardianes de prisión'),
('5169', N'Personal de los servicios de protección y seguridad, no clasificados en otros epígrafes'),
('5210', N'Modelos de modas, arte y publicidad'),
('5220', N'Vendedores y demostradores de tiendas y almacenes'),
('5230', N'Vendedores de kioscos y de puestos de mercado'),
('6111', N'Agricultores y trabajadores calificados de cultivos extensivos'),
('6112', N'Agricultores y trabajadores calificados de plantaciones de árboles y arbustos'),
('6113', N'Agricultores y trabajadores calificados de huertas, invernaderos y jardines'),
('6114', N'Agricultores y trabajadores calificados de cultivos mixtos'),
('6121', N'Criadores de ganado y otros animales domésticos, productores de leche y sus derivados'),
('6122', N'Avicultores y trabajadores calificados de la avicultura'),
('6123', N'Apicultores y sericicultores y trabajadores calificados de la apicultura y la sericicultura'),
('6124', N'Criadores y trabajadores calificados de la cría de animales domésticos diversos'),
('6129', N'Criadores y trabajadores pecuarios calificados de la cría de animales para el mercado y afines, no clasificados bajo otros epígrafes'),
('6130', N'Productores y trabajadores agropecuarios calificados cuya producción se destina al mercado'),
('6141', N'Taladores y otros trabajadores forestales'),
('6142', N'Carboneros de carbón vegetal y afines'),
('6151', N'Criadores de especies acuáticas'),
('6152', N'Pescadores de agua dulce y en aguas costeras'),
('6153', N'Pescadores de alta mar'),
('6154', N'Cazadores y tramperos'),
('6210', N'Trabajadores agropecuarios y pesqueros de subsistencia'),
('7111', N'Mineros y canteros'),
('7112', N'Pegadores'),
('7113', N'Trozadores, labrantes y grabadores de piedra'),
('7121', N'Constructores con técnicas y materiales tradicionales'),
('7122', N'Albañiles y mamposteros'),
('7123', N'Operarios en cemento armado, enfoscadores y afines'),
('7124', N'Carpinteros de armar y de banco'),
('7129', N'Oficiales y operarios de la construcción (obra gruesa) y afines, no clasificados bajo otros epígrafes'),
('7131', N'Techadores'),
('7132', N'Paqueteros y colocadores de suelos'),
('7133', N'Revocadores'),
('7134', N'Instaladores de material aislante y de insonorización'),
('7135', N'Cristaleros'),
('7136', N'Fontaneros e instaladores de tuberías'),
('7137', N'Electricistas de obras afines'),
('7141', N'Pintores y empapeladores'),
('7142', N'Barnizadores y afines'),
('7143', N'Limpiadores de fachadas y deshollinadores'),
('7211', N'Moldeadores y macheros'),
('7212', N'Soldadores y oxicortadores'),
('7213', N'Chapistas y calderos'),
('7214', N'Montadores de estructuras metálicas'),
('7215', N'Aparejadores y empalmadores de cables'),
('7216', N'Buzos'),
('7221', N'Herreros y forjadores'),
('7222', N'Herramentistas y afines'),
('7223', N'Reguladores y reguladores-operadores de máquinas herramientas'),
('7224', N'Pulidores de metales y afiladores de herramientas'),
('7231', N'Mecánicos y ajustadores de vehículos de motor'),
('7232', N'Mecánicos y ajustadores de motores de avión'),
('7233', N'Mecánicos y ajustadores de máquinas agrícolas e industriales'),
('7241', N'Mecánicos y ajustadores electricistas'),
('7242', N'Ajustadores electronicistas'),
('7243', N'Mecánicos y reparadores de aparatos electrónicos'),
('7244', N'Instaladores y reparadores de telégrafos y teléfonos'),
('7245', N'Instaladores y reparadores de líneas eléctricas'),
('7311', N'Mecánicos y reparadores de instrumentos de precisión'),
('7312', N'Constructores y afinadores de instrumentos musicales'),
('7313', N'Joyeros, orfebres y plateros'),
('7321', N'Alfareros y afines (barro, arcilla y abrasivos)'),
('7322', N'Sopladores, modeladores, laminadores, cortadores y pulidores de vidrio'),
('7323', N'Grabadores de vidrio'),
('7324', N'Pintores, decoradores de vidrio, cerámica y otros materiales'),
('7331', N'Artesanos de la madera y materiales similares'),
('7332', N'Artesanos de los tejidos, el cuero y materiales similares'),
('7341', N'Cajista, tipógrafos y afines'),
('7342', N'Estereotipistas y galvanotipistas'),
('7343', N'Grabadores de imprenta y fotograbadores'),
('7344', N'Operarios de la fotografía y afines'),
('7345', N'Encuadernadores y afines'),
('7346', N'Impresores de serigrafía y estampadores, plancha y en textiles'),
('7411', N'Carniceros, pescaderos y afines'),
('7412', N'Panaderos, pasteleros y confiteros'),
('7413', N'Operarios de la elaboración de productos lácteos'),
('7414', N'Operarios de la conservación de frutas, legumbres, verduras y afines'),
('7415', N'Catadores y clasificadores de alimentos y bebidas'),
('7416', N'Preparadores y elaboradores de tabaco y productos afines'),
('7421', N'Operarios en el tratamiento de la madera'),
('7422', N'Ebanistas y afines'),
('7423', N'Reguladores y reguladores-operadores de máquinas de labrar madera'),
('7424', N'Cesteros, bruceros y afines'),
('7431', N'Preparadores de fibras'),
('7432', N'Tejedores con telares o de tejidos de punto y afines'),
('7433', N'Sastres, modistos y sombrereros'),
('7434', N'Peleteros y afines'),
('7435', N'Patronistas y cortadores de tela, cuero y afines'),
('7436', N'Costureros, bordadores y afines'),
('7437', N'Tapiceros, colchoneros y afines'),
('7441', N'Apelambradores, pellejeros y curtidores'),
('7442', N'Zapateros y afines'),
('8111', N'Operadores de instalaciones mineras'),
('8112', N'Operadores de instalaciones de procesamiento de minerales y rocas'),
('8113', N'Perforadores y sondistas de pozos y afines'),
('8121', N'Operadores de hornos de minerales y de hornos de primera fusión de metales'),
('8122', N'Operadores de hornos de segunda fusión, máquinas de colar y moldear metales y trenes de laminación'),
('8123', N'Operadores de instalaciones de tratamiento térmico de metales'),
('8124', N'Operadores de máquinas trefiladoras y estiradoras de metales'),
('8131', N'Operadores de hornos de vidriería y cerámica y operadores de máquinas afines'),
('8139', N'operadores de instalaciones de vidriería, cerámica y afines, no clasificados bajo otros epígrafes'),
('8141', N'Operadores de instalaciones de procesamiento de la madera'),
('8142', N'Operadores de instalaciones para la preparación de la pasta para papel'),
('8143', N'Operadores de instalaciones para la fabricación de papel'),
('8151', N'Operadores de instalaciones quebrantadoras, trituradoras y mezcladoras de sustancias químicas'),
('8152', N'Operadores de instalaciones de tratamiento químico térmico'),
('8153', N'Operadores de equipos de filtración y separación de sustancias químicas'),
('8154', N'Operadores de equipos de destilación y de reacción química (excepto petróleo y gas natural)'),
('8155', N'Operadores de instalaciones de refinación de petróleo y gas natural'),
('8159', N'Operadores de instalaciones de tratamientos químicos, no clasificados bajo otros epígrafes'),
('8161', N'Operadores de instalaciones de producción de energía'),
('8162', N'Operadores de máquinas de vapor y calderas'),
('8163', N'Operadores de incineradores, instalaciones de tratamiento de agua y afines'),
('8171', N'Operadores de cadenas de montaje automatizadas'),
('8172', N'operadores de robots industriales'),
('8211', N'Operadores de maquinarias herramientas'),
('8212', N'Operadores de máquinas para fabricar cemento y otros productos minerales'),
('8221', N'Operadores de máquinas para fabricar productos farmacéuticos y cosméticos'),
('8222', N'Operadores de máquinas para fabricar municiones y explosivos'),
('8223', N'Operadores de máquinas pulidoras, galvanizadoras y recubridoras de metales'),
('8224', N'Operadores de máquinas para fabricar accesorios fotográficos'),
('8229', N'Operadores de máquinas para fabricar productos químicos, no clasificados bajo otros epígrafes'),
('8231', N'Operadores de máquinas para fabricar productos de caucho'),
('8232', N'Operadores de máquinas para fabricar productos de material plástico'),
('8240', N'Operadores de máquinas para fabricar productos de madera'),
('8251', N'Operadores de máquinas de imprenta'),
('8252', N'Operadores de máquinas de encuadernación'),
('8253', N'Operadores de máquinas para fabricar productos de papel'),
('8261', N'Operadores de máquinas de preparación de fibras, hilado y devanado'),
('8262', N'Operadores de telares y otras máquinas tejedoras'),
('8263', N'Operadores de máquinas para coser'),
('8264', N'Operadores de máquinas de blanqueo, teñido y tintura'),
('8265', N'Operadores de máquinas de tratamiento de pieles y cueros'),
('8266', N'Operadores de máquinas para la fabricación de calzado y afines'),
('8269', N'Operadores de máquinas para fabricar productos textiles y artículos de piel y cuero, no clasificados bajo otros epígrafes'),
('8271', N'Operadores de máquinas para elaborar carne de pescado y mariscos'),
('8272', N'Operadores de máquinas para elaborar productos lácteos'),
('7273', N'Operadores de máquinas para moler cereales y especies'),
('8274', N'Operadores de máquinas para elaborar cereales, productos de panadería, repostería y artículos de chocolate'),
('8275', N'Operadores de máquinas para elaborar frutos húmedos, secos y hortalizas'),
('8276', N'Operadores de máquinas para fabricar azúcares'),
('8277', N'Operadores de máquinas para elaborar té, café y cacao'),
('8278', N'Operadores de máquinas para elaborar cerveza, vinos y otras bebidas'),
('8279', N'Operadores de máquinas para elaborar productos de tabaco'),
('8281', N'Montadores de mecanismos y elementos mecánicos de máquinas'),
('8282', N'Montadores de equipos eléctricos'),
('8283', N'Montadores de equipos electrónicos'),
('8284', N'Montadores de productos metálicos, de caucho y de material plástico'),
('8285', N'Montadores de productos de madera y de materiales afines'),
('8286', N'Montadores de productos de cartón, textiles y materiales afines'),
('8290', N'Otros operadores de máquinas y montadores'),
('8311', N'Maquinista de locomotoras'),
('8312', N'Guardafrenos, guardagujas y agentes de maniobras'),
('8321', N'Conductores de motocicletas'),
('8322', N'Conductores de automóviles, taxis y camionetas'),
('8323', N'Conductores de autobuses y tranvías'),
('8324', N'Conductores de camiones pesados'),
('8331', N'Operadores de maquinaria agrícola y forestal motorizada'),
('8332', N'Operadores de máquinas de movimientos de tierras y afines'),
('8333', N'Operadores de grúas, de aparatos elevadores y afines'),
('8334', N'Conductores de camiones pesados (agrícolas)'),
('8340', N'Marineros de cubierta y afines'),
('9111', N'Vendedores ambulantes de productos comestibles'),
('9112', N'Vendedores ambulantes de productos no comestibles'),
('9113', N'Vendedores a domicilio y por teléfono'),
('9120', N'Limpiabotas y otros trabajadores callejeros'),
('9131', N'Personal doméstico'),
('9132', N'Limpiadores de oficinas, hoteles y otros establecimientos'),
('9133', N'Lavanderos y planchadores manuales'),
('9141', N'Conserjes'),
('9142', N'Lavadores de vehículos, ventanas y afines'),
('9151', N'Mensajeros, porteadores y repartidores'),
('9152', N'Porteros y guardianes y afines'),
('9153', N'Recolectores de dinero en aparatos de venta automática, lectores de medidores y afines'),
('9161', N'Recolectores de basura'),
('9162', N'Barrenderos y afines'),
('9211', N'Mozos de labranza y peones agropecuarios'),
('9212', N'Peones forestales'),
('9213', N'Peones de la pesca, la caza y la trampa'),
('9311', N'Peones de minas y canteras'),
('9312', N'Peones de obras públicas y mantenimiento de carreteras, presas y obras similares'),
('9313', N'Peones de la construcción de edificios'),
('9321', N'Peones de montaje'),
('9322', N'Embaladores manuales y otros peones de la industria manufacturera'),
('9331', N'Conductores de vehículos accionados a pedal o a brazo'),
('9332', N'Conductores de vehículos y máquinas de tracción animal'),
('9333', N'Peones de carga')
) v (Codigo, Descripcion)
WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssOcupacion t WHERE t.Codigo = v.Codigo);
GO
INSERT INTO dbo.rrhhIgssDepartamento (Departamento, Nombre)
SELECT v.* FROM (VALUES
('01', N'Guatemala'),
('02', N'El Progreso'),
('03', N'Sacatepéquez'),
('04', N'Chimaltenango'),
('05', N'Escuintla'),
('06', N'Santa Rosa'),
('07', N'Sololá'),
('08', N'Totonicapán'),
('09', N'Quezaltenango'),
('10', N'Suchitepéquez'),
('11', N'Retalhuleu'),
('12', N'San Marcos'),
('13', N'Huehuetenango'),
('14', N'Quiché'),
('15', N'Baja Verapáz'),
('16', N'Alta Verapáz'),
('17', N'Petén'),
('18', N'Izabal'),
('19', N'Zacapa'),
('20', N'Chiquimula'),
('21', N'Jalapa'),
('22', N'Jutiapa')
) v (Departamento, Nombre)
WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssDepartamento t WHERE t.Departamento = v.Departamento);
GO
INSERT INTO dbo.rrhhIgssMunicipio (Departamento, Municipio, Nombre)
SELECT v.* FROM (VALUES
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
('01', '17', N'Petapa'),
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
('04', '03', N'San Martín Jilotepéque'),
('04', '04', N'Comalapa'),
('04', '05', N'Santa Apolonia'),
('04', '06', N'Tecpán Guatemala'),
('04', '07', N'Patzún'),
('04', '08', N'Pochuta'),
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
('06', '01', N'Cuilapa'),
('06', '02', N'Barberena'),
('06', '03', N'Santa Rosa de Lima'),
('06', '04', N'Casillas'),
('06', '05', N'San Rafael Las Flores'),
('06', '06', N'Oratorio'),
('06', '07', N'San Juan Tecuaco'),
('06', '08', N'Chiquimulilla'),
('06', '09', N'Taxisco'),
('06', '10', N'Santa Maria Ixhuatán'),
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
('09', '01', N'Quezaltenango'),
('09', '02', N'Salcajá'),
('09', '03', N'Olintepéque'),
('09', '04', N'San Carlos Sija'),
('09', '05', N'Sibilia'),
('09', '06', N'Cabricán'),
('09', '07', N'Cajolá'),
('09', '08', N'San Miguel Sigüilá'),
('09', '09', N'Ostuncalco'),
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
('10', '17', N'Santo Tomas La Unión'),
('10', '18', N'Zunilito'),
('10', '19', N'Pueblo Nuevo'),
('10', '20', N'Río Bravo'),
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
('13', '01', N'Huehuetenango'),
('13', '02', N'Chiantla'),
('13', '03', N'Malacatancito'),
('13', '04', N'Cuilco'),
('13', '05', N'Nentón'),
('13', '06', N'San Pedro Necta'),
('13', '07', N'Jacaltenango'),
('13', '08', N'Soloma'),
('13', '09', N'Ixtahuacán'),
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
('13', '25', N'San Sebastian Coatán'),
('13', '26', N'Barillas'),
('13', '27', N'Aguacatán'),
('13', '28', N'San Rafael Petzal'),
('13', '29', N'San Gaspar Ixchil'),
('13', '30', N'Santiago Chimaltenango'),
('13', '31', N'Santa Ana Huista'),
('13', '32', N'La Unión Cantinil'),
('14', '01', N'Santa Cruz del Quiché'),
('14', '02', N'Chiché'),
('14', '03', N'Chinique'),
('14', '04', N'Zacualpa'),
('14', '05', N'Chajul'),
('14', '06', N'Chichicastenango'),
('14', '07', N'Patzité'),
('14', '08', N'San Antonio Ilotenango'),
('14', '09', N'San Pedro Jocopilas'),
('14', '10', N'Cunén'),
('14', '11', N'San Juan Cotzal'),
('14', '12', N'Joyabaj'),
('14', '13', N'Nebaj'),
('14', '14', N'San Andrés Sajcabajá'),
('14', '15', N'Uspantán'),
('14', '16', N'Sacapulas'),
('14', '17', N'San Bartolomé Jocotenango'),
('14', '18', N'Canillá'),
('14', '19', N'Chicamán'),
('14', '20', N'Ixcán Playa Grande'),
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
('16', '02', N'Santa Cruz Verapáz'),
('16', '03', N'San Cristóbal Verapáz'),
('16', '04', N'Tactic'),
('16', '05', N'Tamahú'),
('16', '06', N'Tucurú'),
('16', '07', N'Panzós'),
('16', '08', N'Senahú'),
('16', '09', N'San Pedro Carchá'),
('16', '10', N'San Juan Chamelco'),
('16', '11', N'Lanquín'),
('16', '12', N'Cahabón'),
('16', '13', N'Chisec'),
('16', '14', N'Chahal'),
('16', '15', N'Fray Bartolomé de las Casas'),
('16', '16', N'La Tinta'),
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
('22', '08', N'Jeréz'),
('22', '09', N'El Adelanto'),
('22', '10', N'Zapotitlán'),
('22', '11', N'Comapa'),
('22', '12', N'Jalpatagua'),
('22', '13', N'Conguaco'),
('22', '14', N'Moyuta'),
('22', '15', N'Pasaco'),
('22', '16', N'San José Acatempa'),
('22', '17', N'Quezada')
) v (Departamento, Municipio, Nombre)
WHERE NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssMunicipio t WHERE t.Departamento = v.Departamento AND t.Municipio = v.Municipio);
GO

------------------------------------------------------------
-- 2. Patrono y centros de trabajo
------------------------------------------------------------
IF COL_LENGTH('dbo.gen_compania', 'cia_igss_correo') IS NULL
	ALTER TABLE dbo.gen_compania ADD
		[cia_igss_correo]		VARCHAR(100)	NULL,	-- a donde el IGSS envía el resultado de la validación
		[cia_igss_actividad]	CHAR(6)			NULL;
GO
IF OBJECT_ID('dbo.FK_gen_compania_igss_actividad', 'F') IS NULL
	ALTER TABLE dbo.gen_compania ADD CONSTRAINT [FK_gen_compania_igss_actividad]
		FOREIGN KEY ([cia_igss_actividad]) REFERENCES dbo.rrhhIgssActividadEconomica ([Codigo]);
GO

IF COL_LENGTH('dbo.gen_sucursal', 'suc_igss_zona') IS NULL
	ALTER TABLE dbo.gen_sucursal ADD
		[suc_igss_zona]			TINYINT			NULL,
		[suc_igss_fax]			VARCHAR(60)		NULL,
		[suc_igss_contacto]		VARCHAR(100)	NULL,
		[suc_igss_email]		VARCHAR(60)		NULL,
		[suc_igss_departamento]	CHAR(2)			NULL,
		[suc_igss_municipio]	CHAR(2)			NULL,
		[suc_igss_actividad]	CHAR(6)			NULL;
GO
IF OBJECT_ID('dbo.FK_gen_sucursal_igss_municipio', 'F') IS NULL
	ALTER TABLE dbo.gen_sucursal ADD
		CONSTRAINT [FK_gen_sucursal_igss_municipio] FOREIGN KEY ([suc_igss_departamento], [suc_igss_municipio])
			REFERENCES dbo.rrhhIgssMunicipio ([Departamento], [Municipio]),
		CONSTRAINT [FK_gen_sucursal_igss_actividad] FOREIGN KEY ([suc_igss_actividad]) REFERENCES dbo.rrhhIgssActividadEconomica ([Codigo]),
		CONSTRAINT [CK_gen_sucursal_igss_zona] CHECK ([suc_igss_zona] IS NULL OR [suc_igss_zona] BETWEEN 0 AND 99);
GO

------------------------------------------------------------
-- 3. Tipos de planilla, ocupación y datos IGSS del empleado
------------------------------------------------------------
IF OBJECT_ID('dbo.rrhhIgssTipoPlanilla', 'U') IS NULL
CREATE TABLE [dbo].[rrhhIgssTipoPlanilla](
	[IdTipoPlanilla]	INT				IDENTITY(1, 1) NOT NULL,
	[cia_id]			INT				NOT NULL,
	[Codigo]			INT				NOT NULL,		-- identificador ante el IGSS (hasta 3 dígitos)
	[Nombre]			VARCHAR(100)	NOT NULL,
	[TipoAfiliado]		CHAR(1)			NOT NULL CONSTRAINT [DF_rrhhIgssTipoPlanilla_Afiliado] DEFAULT ('C'),
	[Periodo]			CHAR(1)			NOT NULL CONSTRAINT [DF_rrhhIgssTipoPlanilla_Periodo] DEFAULT ('M'),
	[Departamento]		CHAR(2)			NOT NULL,
	[Actividad]			CHAR(6)			NOT NULL,
	[Clase]				CHAR(1)			NOT NULL CONSTRAINT [DF_rrhhIgssTipoPlanilla_Clase] DEFAULT ('N'),
	[TiempoContrato]	CHAR(2)			NOT NULL CONSTRAINT [DF_rrhhIgssTipoPlanilla_Tiempo] DEFAULT ('TC'),
	[Estado]			CHAR(1)			NOT NULL CONSTRAINT [DF_rrhhIgssTipoPlanilla_Estado] DEFAULT ('A'),
	[InsUsuario]		INT				NULL,
	[InsFechaHora]		DATETIME2(0)	NULL CONSTRAINT [DF_rrhhIgssTipoPlanilla_Ins] DEFAULT (SYSDATETIME()),
	[UpdUsuario]		INT				NULL,
	[UpdFechaHora]		DATETIME2(0)	NULL,
	CONSTRAINT [PK_rrhhIgssTipoPlanilla] PRIMARY KEY ([IdTipoPlanilla]),
	CONSTRAINT [UQ_rrhhIgssTipoPlanilla_Codigo] UNIQUE ([cia_id], [Codigo]),
	CONSTRAINT [FK_rrhhIgssTipoPlanilla_Compania] FOREIGN KEY ([cia_id]) REFERENCES dbo.gen_compania ([cia_id]),
	CONSTRAINT [FK_rrhhIgssTipoPlanilla_Departamento] FOREIGN KEY ([Departamento]) REFERENCES dbo.rrhhIgssDepartamento ([Departamento]),
	CONSTRAINT [FK_rrhhIgssTipoPlanilla_Actividad] FOREIGN KEY ([Actividad]) REFERENCES dbo.rrhhIgssActividadEconomica ([Codigo]),
	CONSTRAINT [FK_rrhhIgssTipoPlanilla_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [FK_rrhhIgssTipoPlanilla_UpdUsuario] FOREIGN KEY ([UpdUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [CK_rrhhIgssTipoPlanilla_Valores] CHECK ([Codigo] BETWEEN 1 AND 999 AND [TipoAfiliado] IN ('C', 'S') AND [Periodo] IN ('M', 'C', 'S')
		AND [Clase] IN ('N', 'V') AND [TiempoContrato] IN ('TC', 'TP') AND [Estado] IN ('A', 'I'))
);
GO

IF COL_LENGTH('dbo.rrhhPuesto', 'IgssOcupacion') IS NULL
	ALTER TABLE dbo.rrhhPuesto ADD [IgssOcupacion] CHAR(4) NULL
		CONSTRAINT [FK_rrhhPuesto_IgssOcupacion] FOREIGN KEY REFERENCES dbo.rrhhIgssOcupacion ([Codigo]);
GO

IF COL_LENGTH('dbo.rrhhEmpleado', 'IdIgssTipoPlanilla') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD
		[IdIgssTipoPlanilla]	INT				NULL,
		[CondicionLaboral]		CHAR(1)			NOT NULL CONSTRAINT [DF_rrhhEmpleado_CondicionLaboral] DEFAULT ('P'),
		[IgssTipoSalario]		TINYINT			NULL,		-- vacío = 1, salario base mensual
		[HorasDiarias]			NUMERIC(4, 1)	NULL,		-- tiempo parcial: horas que trabaja al día
		[IgssOcupacion]			CHAR(4)			NULL;		-- si difiere de la del puesto
GO
-- Sin valor por defecto: 12_datos_sinteticos vacía todas las tablas (también
-- este catálogo) y 25_rrhh vuelve a crear empleados antes de que este script
-- repueble el catálogo; un 1 por defecto rompería la llave foránea.
IF OBJECT_ID('dbo.DF_rrhhEmpleado_IgssTipoSalario', 'D') IS NOT NULL
	ALTER TABLE dbo.rrhhEmpleado DROP CONSTRAINT [DF_rrhhEmpleado_IgssTipoSalario];
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.rrhhEmpleado') AND name = 'IgssTipoSalario' AND is_nullable = 0)
	ALTER TABLE dbo.rrhhEmpleado ALTER COLUMN [IgssTipoSalario] TINYINT NULL;
GO
IF OBJECT_ID('dbo.FK_rrhhEmpleado_IgssTipoPlanilla', 'F') IS NULL
	ALTER TABLE dbo.rrhhEmpleado ADD
		CONSTRAINT [FK_rrhhEmpleado_IgssTipoPlanilla] FOREIGN KEY ([IdIgssTipoPlanilla]) REFERENCES dbo.rrhhIgssTipoPlanilla ([IdTipoPlanilla]),
		CONSTRAINT [FK_rrhhEmpleado_IgssTipoSalario] FOREIGN KEY ([IgssTipoSalario]) REFERENCES dbo.rrhhIgssTipoSalario ([Codigo]),
		CONSTRAINT [FK_rrhhEmpleado_IgssOcupacion] FOREIGN KEY ([IgssOcupacion]) REFERENCES dbo.rrhhIgssOcupacion ([Codigo]),
		CONSTRAINT [CK_rrhhEmpleado_CondicionLaboral] CHECK ([CondicionLaboral] IN ('P', 'T')),
		CONSTRAINT [CK_rrhhEmpleado_HorasDiarias] CHECK ([HorasDiarias] IS NULL OR ([HorasDiarias] > 0 AND [HorasDiarias] <= 24));
GO

-- Suspensiones del IGSS (S) y licencias sin goce de salario (L).
IF OBJECT_ID('dbo.rrhhIgssAusencia', 'U') IS NULL
CREATE TABLE [dbo].[rrhhIgssAusencia](
	[IdAusencia]	INT				IDENTITY(1, 1) NOT NULL,
	[IdEmpleado]	INT				NOT NULL,
	[Tipo]			CHAR(1)			NOT NULL,
	[FechaInicio]	DATE			NOT NULL,
	[FechaFin]		DATE			NOT NULL,
	[Observacion]	VARCHAR(200)	NULL,
	[InsUsuario]	INT				NULL,
	[InsFechaHora]	DATETIME2(0)	NULL CONSTRAINT [DF_rrhhIgssAusencia_Ins] DEFAULT (SYSDATETIME()),
	CONSTRAINT [PK_rrhhIgssAusencia] PRIMARY KEY ([IdAusencia]),
	CONSTRAINT [FK_rrhhIgssAusencia_Empleado] FOREIGN KEY ([IdEmpleado]) REFERENCES dbo.rrhhEmpleado ([IdEmpleado]),
	CONSTRAINT [FK_rrhhIgssAusencia_InsUsuario] FOREIGN KEY ([InsUsuario]) REFERENCES dbo.gen_usuario ([usu_id]),
	CONSTRAINT [CK_rrhhIgssAusencia_Valores] CHECK ([Tipo] IN ('S', 'L') AND [FechaFin] >= [FechaInicio])
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_rrhhIgssAusencia_Empleado')
	CREATE INDEX [IX_rrhhIgssAusencia_Empleado] ON dbo.rrhhIgssAusencia ([IdEmpleado], [FechaInicio]) INCLUDE ([FechaFin], [Tipo]);
GO

------------------------------------------------------------
-- 4. Mantenimiento
------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[paRrhhIgssCatalogosConsultar]
AS
BEGIN
	SET NOCOUNT ON;
	SELECT Codigo, Descripcion, Categoria FROM dbo.rrhhIgssActividadEconomica ORDER BY Codigo;
	SELECT Codigo, Descripcion FROM dbo.rrhhIgssOcupacion ORDER BY Codigo;
	SELECT Departamento, Nombre FROM dbo.rrhhIgssDepartamento ORDER BY Departamento;
	SELECT Departamento, Municipio, Nombre FROM dbo.rrhhIgssMunicipio ORDER BY Departamento, Municipio;
	SELECT Codigo, Descripcion FROM dbo.rrhhIgssTipoSalario ORDER BY Codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaRrhhConsultar]
	@CiaId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT cia_id AS CiaId, cia_igss_numero_patronal AS IgssNumeroPatronal, cia_libro_salarios_autorizacion AS LibroSalariosAutorizacion,
		   cia_igss_correo AS IgssCorreo, cia_igss_actividad AS IgssActividad, cia_email AS CorreoCompania
	FROM dbo.gen_compania
	WHERE cia_id = @CiaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paCompaniaRrhhGuardar]
	@CiaId						INT,
	@IgssNumeroPatronal			VARCHAR(20) = NULL,
	@LibroSalariosAutorizacion	VARCHAR(60) = NULL,
	@IgssCorreo					VARCHAR(100) = NULL,
	@IgssActividad				CHAR(6) = NULL,
	@UsuId						INT
AS
BEGIN
	SET NOCOUNT ON;
	SET @IgssNumeroPatronal = NULLIF(LTRIM(RTRIM(@IgssNumeroPatronal)), '');
	SET @IgssCorreo = NULLIF(LTRIM(RTRIM(@IgssCorreo)), '');
	SET @IgssActividad = NULLIF(LTRIM(RTRIM(@IgssActividad)), '');
	IF @IgssNumeroPatronal IS NOT NULL AND (@IgssNumeroPatronal LIKE '%[^0-9]%' OR LEN(@IgssNumeroPatronal) > 10)
		THROW 54110, 'El número patronal del IGSS solo lleva dígitos (hasta 10).', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_id = @CiaId)
		THROW 54103, 'La compañía no existe.', 1;
	IF @IgssCorreo IS NOT NULL AND @IgssCorreo NOT LIKE '%_@_%._%'
		THROW 54701, 'El correo para el IGSS no es válido.', 1;
	IF @IgssActividad IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssActividadEconomica WHERE Codigo = @IgssActividad)
		THROW 54702, 'La actividad económica no está en el catálogo del IGSS.', 1;

	UPDATE dbo.gen_compania
	   SET cia_igss_numero_patronal = @IgssNumeroPatronal,
		   cia_libro_salarios_autorizacion = NULLIF(LTRIM(RTRIM(@LibroSalariosAutorizacion)), ''),
		   cia_igss_correo = @IgssCorreo, cia_igss_actividad = @IgssActividad,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE cia_id = @CiaId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paSucursalIgssConsultar]
	@CiaId	INT = NULL
AS
BEGIN
	SET NOCOUNT ON;
	SELECT sucu.suc_id AS SucId, sucu.cia_id AS CiaId, sucu.suc_codigo AS Codigo, sucu.suc_descripcion AS Descripcion,
		   sucu.suc_igss_centro_trabajo AS CentroTrabajo, sucu.suc_tasa_igss_patronal AS TasaIgssPatronal,
		   sucu.suc_tasa_igss_laboral AS TasaIgssLaboral, sucu.suc_tasa_irtra AS TasaIrtra, sucu.suc_tasa_intecap AS TasaIntecap,
		   sucu.suc_estado AS Estado, sucu.suc_direccion AS Direccion, sucu.suc_telefono AS Telefono,
		   sucu.suc_igss_zona AS Zona, sucu.suc_igss_fax AS Fax, sucu.suc_igss_contacto AS Contacto, sucu.suc_igss_email AS Email,
		   sucu.suc_igss_departamento AS Departamento, sucu.suc_igss_municipio AS Municipio, sucu.suc_igss_actividad AS Actividad
	FROM dbo.gen_sucursal sucu
	WHERE @CiaId IS NULL OR sucu.cia_id = @CiaId
	ORDER BY sucu.cia_id, sucu.suc_codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paSucursalIgssGuardar]
	@SucId				INT,
	@CentroTrabajo		VARCHAR(10) = NULL,
	@TasaIgssPatronal	NUMERIC(6, 3),
	@TasaIgssLaboral	NUMERIC(6, 3) = NULL,
	@TasaIrtra			NUMERIC(6, 3),
	@TasaIntecap		NUMERIC(6, 3),
	@Zona				TINYINT = NULL,
	@Fax				VARCHAR(60) = NULL,
	@Contacto			VARCHAR(100) = NULL,
	@Email				VARCHAR(60) = NULL,
	@Departamento		CHAR(2) = NULL,
	@Municipio			CHAR(2) = NULL,
	@Actividad			CHAR(6) = NULL,
	@UsuId				INT
AS
BEGIN
	SET NOCOUNT ON;
	SET @CentroTrabajo = NULLIF(LTRIM(RTRIM(@CentroTrabajo)), '');
	SELECT @Departamento = NULLIF(@Departamento, ''), @Municipio = NULLIF(@Municipio, ''), @Actividad = NULLIF(@Actividad, ''),
		   @Email = NULLIF(LTRIM(RTRIM(@Email)), '');
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_sucursal WHERE suc_id = @SucId)
		THROW 54111, 'La sucursal no existe.', 1;
	IF @CentroTrabajo IS NOT NULL AND (@CentroTrabajo LIKE '%[^0-9]%' OR LEN(@CentroTrabajo) > 5)
		THROW 54112, 'El número de centro de trabajo del IGSS solo lleva dígitos (hasta 5).', 1;
	IF @TasaIgssPatronal NOT BETWEEN 0 AND 100 OR @TasaIrtra NOT BETWEEN 0 AND 100 OR @TasaIntecap NOT BETWEEN 0 AND 100
	   OR (@TasaIgssLaboral IS NOT NULL AND @TasaIgssLaboral NOT BETWEEN 0 AND 100)
		THROW 54113, 'Las tasas son porcentajes entre 0 y 100.', 1;
	IF (@Departamento IS NULL AND @Municipio IS NOT NULL) OR (@Departamento IS NOT NULL AND @Municipio IS NULL)
		OR (@Departamento IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssMunicipio WHERE Departamento = @Departamento AND Municipio = @Municipio))
		THROW 54703, 'Elija el departamento y un municipio de ese departamento.', 1;
	IF @Email IS NOT NULL AND @Email NOT LIKE '%_@_%._%'
		THROW 54704, 'El correo del centro de trabajo no es válido.', 1;

	UPDATE dbo.gen_sucursal
	   SET suc_igss_centro_trabajo = @CentroTrabajo, suc_tasa_igss_patronal = @TasaIgssPatronal, suc_tasa_igss_laboral = @TasaIgssLaboral,
		   suc_tasa_irtra = @TasaIrtra, suc_tasa_intecap = @TasaIntecap,
		   suc_igss_zona = @Zona, suc_igss_fax = NULLIF(LTRIM(RTRIM(@Fax)), ''), suc_igss_contacto = NULLIF(LTRIM(RTRIM(@Contacto)), ''),
		   suc_igss_email = @Email, suc_igss_departamento = @Departamento, suc_igss_municipio = @Municipio, suc_igss_actividad = @Actividad,
		   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE suc_id = @SucId;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhIgssTipoPlanillaConsultar]
	@CiaId	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT tipo.IdTipoPlanilla, tipo.cia_id AS CiaId, tipo.Codigo, tipo.Nombre, tipo.TipoAfiliado, tipo.Periodo, tipo.Departamento,
		   tipo.Actividad, tipo.Clase, tipo.TiempoContrato, tipo.Estado,
		   (SELECT COUNT(*) FROM dbo.rrhhEmpleado empl WHERE empl.IdIgssTipoPlanilla = tipo.IdTipoPlanilla AND empl.Estado = 'A') AS Empleados
	FROM dbo.rrhhIgssTipoPlanilla tipo
	WHERE tipo.cia_id = @CiaId
	ORDER BY tipo.Codigo;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhIgssTipoPlanillaGuardar]
	@IdTipoPlanilla	INT = NULL,
	@CiaId			INT,
	@Codigo			INT,
	@Nombre			VARCHAR(100),
	@TipoAfiliado	CHAR(1),
	@Periodo		CHAR(1),
	@Departamento	CHAR(2),
	@Actividad		CHAR(6),
	@Clase			CHAR(1),
	@TiempoContrato	CHAR(2),
	@Estado			CHAR(1) = 'A',
	@UsuId			INT,
	@IdResultado	INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	IF ISNULL(LTRIM(RTRIM(@Nombre)), '') = '' OR @Codigo NOT BETWEEN 1 AND 999
		THROW 54705, 'Indique el código (1 a 999) y el nombre del tipo de planilla.', 1;
	IF EXISTS (SELECT 1 FROM dbo.rrhhIgssTipoPlanilla WHERE cia_id = @CiaId AND Codigo = @Codigo AND IdTipoPlanilla <> ISNULL(@IdTipoPlanilla, 0))
		THROW 54706, 'Ya existe un tipo de planilla con ese código en la compañía.', 1;
	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssActividadEconomica WHERE Codigo = @Actividad)
		OR NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssDepartamento WHERE Departamento = @Departamento)
		THROW 54707, 'Elija el departamento y la actividad económica del catálogo del IGSS.', 1;

	IF @IdTipoPlanilla IS NULL
	BEGIN
		INSERT INTO dbo.rrhhIgssTipoPlanilla (cia_id, Codigo, Nombre, TipoAfiliado, Periodo, Departamento, Actividad, Clase, TiempoContrato, Estado, InsUsuario)
		VALUES (@CiaId, @Codigo, UPPER(LTRIM(RTRIM(@Nombre))), @TipoAfiliado, @Periodo, @Departamento, @Actividad, @Clase, @TiempoContrato, @Estado, @UsuId);
		SET @IdResultado = SCOPE_IDENTITY();
	END
	ELSE
	BEGIN
		UPDATE dbo.rrhhIgssTipoPlanilla
		   SET Codigo = @Codigo, Nombre = UPPER(LTRIM(RTRIM(@Nombre))), TipoAfiliado = @TipoAfiliado, Periodo = @Periodo,
			   Departamento = @Departamento, Actividad = @Actividad, Clase = @Clase, TiempoContrato = @TiempoContrato, Estado = @Estado,
			   UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
		 WHERE IdTipoPlanilla = @IdTipoPlanilla AND cia_id = @CiaId;
		SET @IdResultado = @IdTipoPlanilla;
	END
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhPuestoConsultar]
	@SoloActivos BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SELECT pues.IdPuesto, pues.Descripcion, pues.SalarioMinimo, pues.SalarioMaximo, pues.Estado, pues.IgssOcupacion,
		   ocup.Descripcion AS IgssOcupacionDescripcion
	FROM dbo.rrhhPuesto pues
	LEFT JOIN dbo.rrhhIgssOcupacion ocup ON ocup.Codigo = pues.IgssOcupacion
	WHERE @SoloActivos = 0 OR pues.Estado = 'A'
	ORDER BY pues.Descripcion;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhPuestoOcupacionGuardar]
	@IdPuesto	INT,
	@Ocupacion	CHAR(4) = NULL,
	@UsuId		INT
AS
BEGIN
	SET NOCOUNT ON;
	SET @Ocupacion = NULLIF(LTRIM(RTRIM(@Ocupacion)), '');
	IF @Ocupacion IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssOcupacion WHERE Codigo = @Ocupacion)
		THROW 54708, 'La ocupación no está en el catálogo CIUO-88 del IGSS.', 1;
	UPDATE dbo.rrhhPuesto SET IgssOcupacion = @Ocupacion, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME() WHERE IdPuesto = @IdPuesto;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoIgssConsultar]
	@IdEmpleado	INT
AS
BEGIN
	SET NOCOUNT ON;
	SELECT empl.IdEmpleado, empl.IdIgssTipoPlanilla, empl.CondicionLaboral, ISNULL(empl.IgssTipoSalario, 1) AS IgssTipoSalario,
		   empl.HorasDiarias, empl.IgssOcupacion,
		   pues.IgssOcupacion AS OcupacionPuesto, ocup.Descripcion AS OcupacionPuestoDescripcion
	FROM dbo.rrhhEmpleado empl
	LEFT JOIN dbo.rrhhPlaza plaz ON plaz.IdPlaza = empl.IdPlaza
	LEFT JOIN dbo.rrhhDepartamentoPuesto depu ON depu.IdDepartamentoPuesto = plaz.IdDepartamentoPuesto
	LEFT JOIN dbo.rrhhPuesto pues ON pues.IdPuesto = depu.IdPuesto
	LEFT JOIN dbo.rrhhIgssOcupacion ocup ON ocup.Codigo = pues.IgssOcupacion
	WHERE empl.IdEmpleado = @IdEmpleado;

	SELECT IdAusencia, IdEmpleado, Tipo, FechaInicio, FechaFin, Observacion
	FROM dbo.rrhhIgssAusencia
	WHERE IdEmpleado = @IdEmpleado
	ORDER BY FechaInicio DESC;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhEmpleadoIgssGuardar]
	@IdEmpleado			INT,
	@IdIgssTipoPlanilla	INT = NULL,
	@CondicionLaboral	CHAR(1) = 'P',
	@IgssTipoSalario	TINYINT = 1,
	@HorasDiarias		NUMERIC(4, 1) = NULL,
	@IgssOcupacion		CHAR(4) = NULL,
	@UsuId				INT
AS
BEGIN
	SET NOCOUNT ON;
	SET @IgssOcupacion = NULLIF(LTRIM(RTRIM(@IgssOcupacion)), '');
	DECLARE @cia_id INT = (SELECT cia_id FROM dbo.rrhhEmpleado WHERE IdEmpleado = @IdEmpleado);
	IF @cia_id IS NULL
		THROW 54114, 'El empleado no existe.', 1;
	IF @IdIgssTipoPlanilla IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssTipoPlanilla WHERE IdTipoPlanilla = @IdIgssTipoPlanilla AND cia_id = @cia_id)
		THROW 54709, 'El tipo de planilla debe ser de la compañía del empleado.', 1;
	IF @IgssOcupacion IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssOcupacion WHERE Codigo = @IgssOcupacion)
		THROW 54708, 'La ocupación no está en el catálogo CIUO-88 del IGSS.', 1;
	UPDATE dbo.rrhhEmpleado
	   SET IdIgssTipoPlanilla = @IdIgssTipoPlanilla, CondicionLaboral = @CondicionLaboral, IgssTipoSalario = @IgssTipoSalario,
		   HorasDiarias = @HorasDiarias, IgssOcupacion = @IgssOcupacion, UpdUsuario = @UsuId, UpdFechaHora = SYSDATETIME()
	 WHERE IdEmpleado = @IdEmpleado;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhIgssAusenciaGuardar]
	@IdEmpleado		INT,
	@Tipo			CHAR(1),
	@FechaInicio	DATE,
	@FechaFin		DATE,
	@Observacion	VARCHAR(200) = NULL,
	@UsuId			INT
AS
BEGIN
	SET NOCOUNT ON;
	IF @Tipo NOT IN ('S', 'L') OR @FechaInicio IS NULL OR @FechaFin IS NULL OR @FechaFin < @FechaInicio
		THROW 54710, 'Indique si es suspensión o licencia y fechas válidas (la final no antes de la inicial).', 1;
	IF EXISTS (SELECT 1 FROM dbo.rrhhIgssAusencia WHERE IdEmpleado = @IdEmpleado AND FechaInicio <= @FechaFin AND FechaFin >= @FechaInicio)
		THROW 54710, 'Ya hay una suspensión o licencia del empleado en esas fechas.', 1;
	INSERT INTO dbo.rrhhIgssAusencia (IdEmpleado, Tipo, FechaInicio, FechaFin, Observacion, InsUsuario)
	VALUES (@IdEmpleado, @Tipo, @FechaInicio, @FechaFin, NULLIF(LTRIM(RTRIM(@Observacion)), ''), @UsuId);
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[paRrhhIgssAusenciaEliminar]
	@IdAusencia	INT
AS
BEGIN
	SET NOCOUNT ON;
	DELETE FROM dbo.rrhhIgssAusencia WHERE IdAusencia = @IdAusencia;
END;
GO

------------------------------------------------------------
-- 5. Datos del archivo de un mes
------------------------------------------------------------
-- Resultados: 1) patrono, 2) centros de trabajo, 3) tipos de planilla,
-- 4) liquidaciones, 5) empleados, 6) suspensiones y licencias,
-- 7) observaciones (E = impide generar el archivo, A = aviso).
CREATE OR ALTER PROCEDURE [dbo].[paRrhhPlanillaIgssArchivoConsultar]
	@CiaId	INT,
	@Anio	INT,
	@Mes	INT
AS
BEGIN
	SET NOCOUNT ON;
	IF NOT EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_id = @CiaId)
		THROW 54103, 'La compañía no existe.', 1;
	IF @Mes IS NULL OR @Mes NOT BETWEEN 1 AND 12 OR @Anio IS NULL OR @Anio NOT BETWEEN 2000 AND 2100
		THROW 54118, 'Indique un mes y un año válidos.', 1;

	DECLARE @del DATE = DATEFROMPARTS(@Anio, @Mes, 1);
	DECLARE @al DATE = EOMONTH(@del);
	DECLARE @obs TABLE (Orden INT IDENTITY, Nivel CHAR(1), Mensaje NVARCHAR(400));

	-- Cada empleado en cada nómina ordinaria aprobada del mes, con su liquidación.
	CREATE TABLE #pago (IdNomina INT, IdEmpleado INT, suc_id INT NULL, Dias NUMERIC(7, 2), Base NUMERIC(14, 2),
						IdTipoPlanilla INT NULL, Inicio DATE, Fin DATE);
	INSERT INTO #pago
	SELECT nemp.IdNomina, nemp.IdEmpleado, nemp.suc_id, nemp.DiasLaborados, nemp.BaseIgss, tipo.IdTipoPlanilla,
		   CASE WHEN tipo.Periodo IN ('C', 'S') THEN nomi.FechaDel ELSE @del END,
		   CASE WHEN tipo.Periodo IN ('C', 'S') THEN nomi.FechaAl ELSE @al END
	FROM dbo.rrhhNominaEmpleado nemp
	INNER JOIN dbo.rrhhNomina nomi ON nomi.IdNomina = nemp.IdNomina
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = nemp.IdEmpleado
	LEFT JOIN dbo.rrhhIgssTipoPlanilla tipo ON tipo.IdTipoPlanilla = empl.IdIgssTipoPlanilla
	WHERE nomi.cia_id = @CiaId AND nomi.Clase = 'O' AND nomi.Estado = 'A' AND nomi.FechaAl BETWEEN @del AND @al;

	CREATE TABLE #liq (Numero INT, IdTipoPlanilla INT, Codigo INT, Inicio DATE, Fin DATE);
	INSERT INTO #liq
	SELECT ROW_NUMBER() OVER (ORDER BY tipo.Codigo, pago.Inicio), pago.IdTipoPlanilla, tipo.Codigo, pago.Inicio, pago.Fin
	FROM (SELECT DISTINCT IdTipoPlanilla, Inicio, Fin FROM #pago WHERE IdTipoPlanilla IS NOT NULL) pago
	INNER JOIN dbo.rrhhIgssTipoPlanilla tipo ON tipo.IdTipoPlanilla = pago.IdTipoPlanilla;

	CREATE TABLE #empl (Liquidacion INT, IdEmpleado INT, suc_id INT NULL, Dias NUMERIC(9, 2), Base NUMERIC(14, 2), Inicio DATE, Fin DATE);
	INSERT INTO #empl
	SELECT liqu.Numero, pago.IdEmpleado, MAX(pago.suc_id), SUM(pago.Dias), SUM(pago.Base), liqu.Inicio, liqu.Fin
	FROM #pago pago
	INNER JOIN #liq liqu ON liqu.IdTipoPlanilla = pago.IdTipoPlanilla AND liqu.Inicio = pago.Inicio AND liqu.Fin = pago.Fin
	GROUP BY liqu.Numero, pago.IdEmpleado, liqu.Inicio, liqu.Fin;

	-- Observaciones.
	DECLARE @patronal VARCHAR(20), @nit VARCHAR(20), @correo VARCHAR(100), @actividad CHAR(6);
	SELECT @patronal = cia_igss_numero_patronal, @nit = cia_nit, @correo = COALESCE(cia_igss_correo, cia_email), @actividad = cia_igss_actividad
	FROM dbo.gen_compania WHERE cia_id = @CiaId;
	IF @patronal IS NULL INSERT INTO @obs VALUES ('E', N'La compañía no tiene número patronal del IGSS (pestaña Patrono y centros de trabajo).');
	IF ISNULL(@nit, '') = '' INSERT INTO @obs VALUES ('E', N'La compañía no tiene NIT.');
	IF @correo IS NULL INSERT INTO @obs VALUES ('E', N'Falta el correo electrónico al que el IGSS responde la validación.');
	IF NOT EXISTS (SELECT 1 FROM #pago)
		INSERT INTO @obs VALUES ('E', N'No hay nóminas ordinarias aprobadas cuya fecha final caiga en el mes.');
	IF EXISTS (SELECT 1 FROM dbo.rrhhNomina WHERE cia_id = @CiaId AND Clase = 'O' AND Estado IN ('B', 'C') AND FechaAl BETWEEN @del AND @al)
		INSERT INTO @obs VALUES ('A', N'Hay nóminas del mes sin aprobar: no entran en el archivo.');
	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssTipoPlanilla WHERE cia_id = @CiaId AND Estado = 'A')
		INSERT INTO @obs VALUES ('E', N'La compañía no tiene tipos de planilla del IGSS (pestaña Tipos de planilla).');

	INSERT INTO @obs (Nivel, Mensaje)
	SELECT 'E', CONCAT(N'Empleado ', empl.CodigoEmpleado, N' ', empl.PrimerNombre, N' ', empl.PrimerApellido, N': ',
		   STUFF(CONCAT(
			   IIF(ISNULL(empl.NumeroAfiliacionIGSS, '') = '', N', sin número de afiliación', ''),
			   IIF(empl.IdIgssTipoPlanilla IS NULL, N', sin tipo de planilla', ''),
			   IIF(COALESCE(empl.IgssOcupacion, pues.IgssOcupacion) IS NULL, N', sin ocupación (puesto o empleado)', ''),
			   IIF(sucu.suc_igss_centro_trabajo IS NULL, N', su sucursal no tiene número de centro de trabajo', '')), 1, 2, ''), N'.')
	FROM (SELECT IdEmpleado, MAX(suc_id) AS suc_id FROM #pago GROUP BY IdEmpleado) pago
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = pago.IdEmpleado
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_id = pago.suc_id
	LEFT JOIN dbo.rrhhPlaza plaz ON plaz.IdPlaza = empl.IdPlaza
	LEFT JOIN dbo.rrhhDepartamentoPuesto depu ON depu.IdDepartamentoPuesto = plaz.IdDepartamentoPuesto
	LEFT JOIN dbo.rrhhPuesto pues ON pues.IdPuesto = depu.IdPuesto
	WHERE ISNULL(empl.NumeroAfiliacionIGSS, '') = '' OR empl.IdIgssTipoPlanilla IS NULL
	   OR COALESCE(empl.IgssOcupacion, pues.IgssOcupacion) IS NULL OR sucu.suc_igss_centro_trabajo IS NULL;

	INSERT INTO @obs (Nivel, Mensaje)
	SELECT 'A', CONCAT(N'Empleado ', empl.CodigoEmpleado, N' ', empl.PrimerNombre, N' ', empl.PrimerApellido,
		   N': trabaja a tiempo parcial y no tiene horas diarias; las horas laboradas irán vacías.')
	FROM (SELECT DISTINCT IdEmpleado FROM #pago) pago
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = pago.IdEmpleado
	WHERE empl.TiempoContrato = 'TP' AND empl.HorasDiarias IS NULL;

	INSERT INTO @obs (Nivel, Mensaje)
	SELECT 'E', CONCAT(N'Centro de trabajo ', sucu.suc_descripcion, N': falta ',
		   STUFF(CONCAT(IIF(sucu.suc_igss_departamento IS NULL, N', departamento y municipio', ''),
						IIF(COALESCE(sucu.suc_igss_actividad, @actividad) IS NULL, N', actividad económica', ''),
						IIF(ISNULL(sucu.suc_direccion, '') = '', N', dirección', '')), 1, 2, ''), N'.')
	FROM dbo.gen_sucursal sucu
	WHERE sucu.suc_id IN (SELECT suc_id FROM #pago)
	  AND (sucu.suc_igss_departamento IS NULL OR COALESCE(sucu.suc_igss_actividad, @actividad) IS NULL OR ISNULL(sucu.suc_direccion, '') = '');

	-- 1) Patrono
	SELECT @patronal AS NumeroPatronal, comp.cia_nombre_comercial AS NombreComercial, comp.cia_nit AS Nit, @correo AS Correo,
		   @Anio AS Anio, @Mes AS Mes
	FROM dbo.gen_compania comp WHERE comp.cia_id = @CiaId;

	-- 2) Centros de trabajo: las sucursales activas con número de centro y las que tienen empleados en el mes.
	SELECT sucu.suc_igss_centro_trabajo AS Codigo, sucu.suc_descripcion AS Nombre, sucu.suc_direccion AS Direccion,
		   sucu.suc_igss_zona AS Zona, sucu.suc_telefono AS Telefono, sucu.suc_igss_fax AS Fax, sucu.suc_igss_contacto AS Contacto,
		   sucu.suc_igss_email AS Email, sucu.suc_igss_departamento AS Departamento, sucu.suc_igss_municipio AS Municipio,
		   COALESCE(sucu.suc_igss_actividad, @actividad) AS Actividad
	FROM dbo.gen_sucursal sucu
	WHERE sucu.cia_id = @CiaId AND sucu.suc_igss_centro_trabajo IS NOT NULL
	  AND (sucu.suc_estado = 'A' OR sucu.suc_id IN (SELECT suc_id FROM #pago))
	ORDER BY TRY_CAST(sucu.suc_igss_centro_trabajo AS INT);

	-- 3) Tipos de planilla: todos los activos de la compañía (el IGSS pide enviarlos todos) y los usados.
	SELECT tipo.Codigo, tipo.Nombre, tipo.TipoAfiliado, tipo.Periodo, tipo.Departamento, tipo.Actividad, tipo.Clase, tipo.TiempoContrato
	FROM dbo.rrhhIgssTipoPlanilla tipo
	WHERE tipo.cia_id = @CiaId AND (tipo.Estado = 'A' OR tipo.IdTipoPlanilla IN (SELECT IdTipoPlanilla FROM #liq))
	ORDER BY tipo.Codigo;

	-- 4) Liquidaciones
	SELECT Numero, Codigo AS TipoPlanilla, Inicio AS FechaInicio, Fin AS FechaFin FROM #liq ORDER BY Numero;

	-- 5) Empleados
	SELECT emps.Liquidacion, empl.CodigoEmpleado, empl.NumeroAfiliacionIGSS AS Afiliacion,
		   empl.PrimerNombre, empl.SegundoNombre, empl.PrimerApellido, empl.SegundoApellido, empl.ApellidoCasada,
		   emps.Base AS Sueldo,
		   CASE WHEN empl.FechaIngreso BETWEEN emps.Inicio AND emps.Fin THEN empl.FechaIngreso END AS FechaAlta,
		   CASE WHEN empl.FechaBaja BETWEEN emps.Inicio AND emps.Fin THEN empl.FechaBaja END AS FechaBaja,
		   sucu.suc_igss_centro_trabajo AS Centro, empl.Nit, COALESCE(empl.IgssOcupacion, pues.IgssOcupacion) AS Ocupacion,
		   empl.CondicionLaboral AS Condicion, ISNULL(empl.IgssTipoSalario, 1) AS TipoSalario,
		   CASE WHEN empl.TiempoContrato = 'TP' AND empl.HorasDiarias IS NOT NULL THEN CEILING(emps.Dias * empl.HorasDiarias) END AS Horas,
		   empl.TiempoContrato, emps.Dias
	FROM #empl emps
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = emps.IdEmpleado
	LEFT JOIN dbo.gen_sucursal sucu ON sucu.suc_id = emps.suc_id
	LEFT JOIN dbo.rrhhPlaza plaz ON plaz.IdPlaza = empl.IdPlaza
	LEFT JOIN dbo.rrhhDepartamentoPuesto depu ON depu.IdDepartamentoPuesto = plaz.IdDepartamentoPuesto
	LEFT JOIN dbo.rrhhPuesto pues ON pues.IdPuesto = depu.IdPuesto
	ORDER BY emps.Liquidacion, empl.PrimerApellido, empl.SegundoApellido, empl.PrimerNombre;

	-- 6) Suspensiones (S) y licencias (L) que caen en el período de cada liquidación (recortadas a él).
	SELECT ause.Tipo, emps.Liquidacion, empl.NumeroAfiliacionIGSS AS Afiliacion,
		   empl.PrimerNombre, empl.SegundoNombre, empl.PrimerApellido, empl.SegundoApellido, empl.ApellidoCasada,
		   IIF(ause.FechaInicio > emps.Inicio, ause.FechaInicio, emps.Inicio) AS FechaInicio,
		   IIF(ause.FechaFin < emps.Fin, ause.FechaFin, emps.Fin) AS FechaFin
	FROM #empl emps
	INNER JOIN dbo.rrhhEmpleado empl ON empl.IdEmpleado = emps.IdEmpleado
	INNER JOIN dbo.rrhhIgssAusencia ause ON ause.IdEmpleado = emps.IdEmpleado AND ause.FechaInicio <= emps.Fin AND ause.FechaFin >= emps.Inicio
	ORDER BY ause.Tipo, emps.Liquidacion, empl.PrimerApellido;

	-- 7) Observaciones
	SELECT Nivel, Mensaje FROM @obs ORDER BY CASE Nivel WHEN 'E' THEN 0 ELSE 1 END, Orden;
END;
GO

------------------------------------------------------------
-- 6. Valores iniciales de los datos de prueba (compañía demo 1234567-9)
------------------------------------------------------------
-- Solo completa lo que esté vacío; en una base real se capturan en RRHH.
IF EXISTS (SELECT 1 FROM dbo.gen_compania WHERE cia_nit = '1234567-9')
BEGIN
	DECLARE @cia INT = (SELECT cia_id FROM dbo.gen_compania WHERE cia_nit = '1234567-9');
	UPDATE dbo.gen_compania SET cia_igss_actividad = ISNULL(cia_igss_actividad, '515100') WHERE cia_id = @cia;
	-- Guatemala (01-01) zona 10, o Mixco (01-08) zona 4 si la sucursal es de Mixco.
	UPDATE dbo.gen_sucursal
	   SET suc_igss_departamento = '01',
		   suc_igss_municipio = IIF(suc_descripcion LIKE '%Mixco%' OR suc_direccion LIKE '%Mixco%', '08', '01'),
		   suc_igss_zona = ISNULL(suc_igss_zona, IIF(suc_descripcion LIKE '%Mixco%' OR suc_direccion LIKE '%Mixco%', 4, 10))
	 WHERE cia_id = @cia AND suc_igss_departamento IS NULL;
	UPDATE dbo.gen_sucursal SET suc_igss_centro_trabajo = CAST(suc_id AS VARCHAR(10))
	 WHERE cia_id = @cia AND suc_igss_centro_trabajo IS NULL AND suc_estado = 'A';
	IF NOT EXISTS (SELECT 1 FROM dbo.rrhhIgssTipoPlanilla WHERE cia_id = @cia)
		INSERT INTO dbo.rrhhIgssTipoPlanilla (cia_id, Codigo, Nombre, TipoAfiliado, Periodo, Departamento, Actividad, Clase, TiempoContrato)
		VALUES (@cia, 1, 'PLANILLA MENSUAL', 'C', 'M', '01', '515100', 'N', 'TC'),
			   (@cia, 2, 'PLANILLA SEMANAL', 'C', 'S', '01', '515100', 'N', 'TC');
	UPDATE empl
	   SET IdIgssTipoPlanilla = tipo.IdTipoPlanilla
	FROM dbo.rrhhEmpleado empl
	INNER JOIN dbo.rrhhIgssTipoPlanilla tipo ON tipo.cia_id = empl.cia_id AND tipo.Codigo = IIF(empl.TipoNomina = 'S', 2, 1)
	WHERE empl.cia_id = @cia AND empl.IdIgssTipoPlanilla IS NULL;
	UPDATE pues
	   SET IgssOcupacion = v.Ocupacion
	FROM dbo.rrhhPuesto pues
	INNER JOIN (VALUES ('Vendedor', '5220'), ('Cajero', '4211'), ('Contador', '2411'), ('Técnico de soporte', '3122'),
					   ('Desarrollador', '2131')) v (Puesto, Ocupacion) ON v.Puesto = pues.Descripcion
	WHERE pues.IgssOcupacion IS NULL;
END;
GO

PRINT '55_planilla_igss_archivo.sql aplicado.';
GO
