-- src/BD/03_poblar_modelo.sql
--
-- Puebla el esquema `modelo` desde `raw` (requiere 01_raw.sql, 02_modelo.sql y la carga COPY
-- de src/BD/build.py). Las reglas de transformación viven aquí, en SQL, y no en los
-- scrapers: así `raw` sigue siendo la copia fiel de la fuente y cada regla queda en un
-- solo lugar, revisable.
--
-- Supuestos verificados en T0 que el modelo necesita. Se re-verifican aquí y abortan la
-- carga si dejan de cumplirse, porque si fallan no existe una tabla de referencia limpia:
--   1. Cada codigo_institucion tiene un solo tipo de institución en todos los años.
--   2. Cada carrera genérica tiene un solo nivel y un solo nombre.
--
-- Sin BEGIN/COMMIT propios: corre dentro de la transacción única de src/BD/build.py.

-- --------------------------------------------------------------------------
-- 0. Supuestos
-- --------------------------------------------------------------------------
DO $$
DECLARE
    n integer;
BEGIN
    SELECT count(*) INTO n FROM (
        SELECT codigo_institucion FROM raw.titulados
        GROUP BY 1 HAVING count(DISTINCT tipo_institucion) > 1) x;
    IF n > 0 THEN
        RAISE EXCEPTION 'Supuesto roto: % instituciones con más de un tipo en raw.titulados', n;
    END IF;

    SELECT count(*) INTO n FROM (
        SELECT clave_carrera_generica FROM raw.titulados
        GROUP BY 1 HAVING count(DISTINCT nivel_carrera) > 1 OR count(DISTINCT carrera_generica) > 1) x;
    IF n > 0 THEN
        RAISE EXCEPTION 'Supuesto roto: % carreras genéricas con más de un nivel o nombre en raw.titulados', n;
    END IF;
END $$;

-- --------------------------------------------------------------------------
-- 1. Referencias
-- --------------------------------------------------------------------------

-- Nombre canónico = el del año más reciente, sin el sufijo de convenio. Así UNICYT y Del
-- Pacífico (que desde 2018 y 2020 titulan en convenio con USACH y UTEM) conservan su nombre
-- propio; el convenio queda como atributo del programa (titulacion.es_convenio).
INSERT INTO modelo.institucion (codigo_institucion, nombre, tipo_institucion)
SELECT DISTINCT ON (codigo_institucion)
       codigo_institucion,
       regexp_replace(institucion, '\s*\(\*CARRERA EN CONVENIO[^)]*\)\s*$', ''),
       tipo_institucion
FROM raw.titulados
ORDER BY codigo_institucion, anio DESC, institucion;

-- El SIES cubre todas las genéricas de MiFuturo y usa el mismo nombre (verificado 165/165).
INSERT INTO modelo.carrera_generica (clave_carrera_generica, nombre, nivel_carrera)
SELECT DISTINCT clave_carrera_generica, carrera_generica, nivel_carrera
FROM raw.titulados;

-- --------------------------------------------------------------------------
-- 2. Hechos
-- --------------------------------------------------------------------------
-- Columnas destino explícitas: con INSERT posicional, dos columnas del mismo tipo
-- intercambiadas (p. ej. mujeres/hombres) se cargarían cruzadas sin error.
INSERT INTO modelo.titulacion (
       anio, codigo_programa, codigo_institucion, clave_carrera_generica, carrera,
       subtipo_institucion, es_convenio,
       cine13_area, cine13_subarea, carrera_clasificacion_nivel_1, tipo_plan, modalidad, jornada,
       duracion_semestres, total_titulaciones, titulaciones_mujeres, titulaciones_hombres,
       titulaciones_nb, titulados_15_19, titulados_20_24, titulados_25_29, titulados_30_34,
       titulados_35_39, titulados_mayores_40, titulados_edad_sin_info, edad_promedio)
SELECT anio, codigo_programa, codigo_institucion, clave_carrera_generica, carrera,
       subtipo_institucion,
       institucion ~ '\(\*CARRERA EN CONVENIO',
       cine13_area, cine13_subarea, carrera_clasificacion_nivel_1, tipo_plan, modalidad, jornada,
       duracion_semestres, total_titulaciones, titulaciones_mujeres, titulaciones_hombres,
       titulaciones_nb, titulados_15_19, titulados_20_24, titulados_25_29, titulados_30_34,
       titulados_35_39, titulados_mayores_40, titulados_edad_sin_info, edad_promedio
FROM raw.titulados;

INSERT INTO modelo.mifuturo_programa (
       codigo_institucion, tipo_institucion, clave_carrera_generica, carrera, acreditacion_anios,
       pct_continuidad_estudios, duracion_real_semestres, empleabilidad_1er_anio,
       empleabilidad_2do_anio, ingreso_4to_anio_tramo_min, ingreso_4to_anio_tramo_max)
SELECT id_institucion, tipo_institucion, clave_carrera_generica, carrera, acreditacion_anios,
       pct_continuidad_estudios, duracion_real_semestres, empleabilidad_1er_anio,
       empleabilidad_2do_anio, ingreso_4to_anio_tramo_min, ingreso_4to_anio_tramo_max
FROM raw.empleabilidad;

INSERT INTO modelo.mifuturo_estadistica (
       clave_carrera_generica, tipo_institucion, id_estadisticas, area_conocimiento_mineduc,
       ingreso_medio_1er_anio, ingreso_medio_2do_anio, ingreso_medio_3er_anio,
       ingreso_medio_4to_anio, ingreso_medio_5to_anio,
       percentil_10_anio_1, percentil_25_anio_1, percentil_50_anio_1, percentil_75_anio_1, percentil_90_anio_1,
       percentil_10_anio_5, percentil_25_anio_5, percentil_50_anio_5, percentil_75_anio_5, percentil_90_anio_5,
       empleabilidad_1er_anio, empleabilidad_2do_anio,
       titulados_2024, titulados_2024_mujeres, titulados_2024_hombres,
       duracion_formal_semestres, duracion_real_semestres)
SELECT clave_carrera_generica, tipo_institucion, id_estadisticas, area_conocimiento_mineduc,
       ingreso_medio_1er_anio, ingreso_medio_2do_anio, ingreso_medio_3er_anio,
       ingreso_medio_4to_anio, ingreso_medio_5to_anio,
       percentil_10_anio_1, percentil_25_anio_1, percentil_50_anio_1, percentil_75_anio_1, percentil_90_anio_1,
       percentil_10_anio_5, percentil_25_anio_5, percentil_50_anio_5, percentil_75_anio_5, percentil_90_anio_5,
       empleabilidad_1er_anio, empleabilidad_2do_anio,
       titulados_2024, titulados_2024_mujeres, titulados_2024_hombres,
       duracion_formal_semestres, duracion_real_semestres
FROM raw.estadisticas;

-- Series: de 15 columnas anchas a formato largo. La cohorte de cada columna es la que fija
-- ORIGEN en src/Scrapers/Estadisticas/esquema.py; los puntos no publicados (NULL) no generan fila.
INSERT INTO modelo.mifuturo_serie (clave_carrera_generica, tipo_institucion, indicador, cohorte, valor)
SELECT e.clave_carrera_generica, e.tipo_institucion, s.indicador, s.cohorte, s.valor
FROM raw.estadisticas e
CROSS JOIN LATERAL (VALUES
    ('serie_empleabilidad_1er_anio', 2019, e.empleabilidad_1er_anio_cohorte_2019),
    ('serie_empleabilidad_1er_anio', 2020, e.empleabilidad_1er_anio_cohorte_2020),
    ('serie_empleabilidad_1er_anio', 2021, e.empleabilidad_1er_anio_cohorte_2021),
    ('serie_empleabilidad_1er_anio', 2022, e.empleabilidad_1er_anio_cohorte_2022),
    ('serie_empleabilidad_1er_anio', 2023, e.empleabilidad_1er_anio_cohorte_2023),
    ('serie_empleabilidad_2do_anio', 2018, e.empleabilidad_2do_anio_cohorte_2018),
    ('serie_empleabilidad_2do_anio', 2019, e.empleabilidad_2do_anio_cohorte_2019),
    ('serie_empleabilidad_2do_anio', 2020, e.empleabilidad_2do_anio_cohorte_2020),
    ('serie_empleabilidad_2do_anio', 2021, e.empleabilidad_2do_anio_cohorte_2021),
    ('serie_empleabilidad_2do_anio', 2022, e.empleabilidad_2do_anio_cohorte_2022),
    ('serie_ingreso_medio_4to_anio', 2016, e.ingreso_medio_4to_anio_cohorte_2016),
    ('serie_ingreso_medio_4to_anio', 2017, e.ingreso_medio_4to_anio_cohorte_2017),
    ('serie_ingreso_medio_4to_anio', 2018, e.ingreso_medio_4to_anio_cohorte_2018),
    ('serie_ingreso_medio_4to_anio', 2019, e.ingreso_medio_4to_anio_cohorte_2019),
    ('serie_ingreso_medio_4to_anio', 2020, e.ingreso_medio_4to_anio_cohorte_2020)
) AS s (indicador, cohorte, valor)
WHERE s.valor IS NOT NULL;

-- --------------------------------------------------------------------------
-- 3. Coherencia serie ↔ tabla cohorte
-- --------------------------------------------------------------------------
-- Si alguien cambia los años en modelo.cohorte sin cambiar ORIGEN (o al revés), la serie
-- quedaría con cohortes fuera de su rango declarado. Se aborta en vez de publicarla.
DO $$
DECLARE
    n integer;
BEGIN
    SELECT count(*) INTO n
    FROM modelo.mifuturo_serie s JOIN modelo.cohorte c USING (indicador)
    WHERE s.cohorte NOT BETWEEN c.cohorte_desde AND c.cohorte_hasta;
    IF n > 0 THEN
        RAISE EXCEPTION 'Incoherencia: % puntos de serie fuera del rango de modelo.cohorte', n;
    END IF;
END $$;
