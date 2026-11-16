-- src/BD/01_raw.sql
--
-- Esquema `raw`: copia FIEL de las 3 salidas de los scrapers (src/Scrapers/*/Salida/*.csv).
-- Mismas columnas y mismo orden que cada esquema.py, para que COPY cargue el CSV tal cual
-- y el control `qa` de contrato (B3) pueda comparar columna por columna.
--
-- Qué se exige aquí y qué no:
--   - Sí: llave primaria (un duplicado no debe entrar), NOT NULL donde la fuente siempre
--     informa, y CHECK de rango físico (porcentajes 0-100, montos > 0, conteos >= 0, sumas
--     que deben cuadrar). Son imposibles, no opiniones: si fallan, el CSV está roto.
--   - No: reglas de negocio ni dominios de categorías; eso vive en `modelo` y en `qa`.
--
-- Decimales como `numeric` sin precisión fija: numeric(4,1) redondearía en silencio un
-- 6,15 a 6,2 al cargar, y `raw` no debe alterar el dato.
--
-- Idempotente: recrea el esquema desde cero en cada ejecución (borra solo `raw`).
-- Ejecutar con: psql -v ON_ERROR_STOP=1 -f src/BD/01_raw.sql

BEGIN;

DROP SCHEMA IF EXISTS raw CASCADE;
CREATE SCHEMA raw;
COMMENT ON SCHEMA raw IS 'Copia fiel de src/Scrapers/*/Salida/*.csv; se recrea en cada build.';

-- --------------------------------------------------------------------------
-- Empleabilidad: institución × carrera genérica (src/Scrapers/Empleabilidad/esquema.py)
-- --------------------------------------------------------------------------
CREATE TABLE raw.empleabilidad (
    id_institucion              integer  NOT NULL,
    institucion                 text     NOT NULL,
    clave_institucion           text     NOT NULL,
    tipo_institucion            text     NOT NULL,
    carrera                     text     NOT NULL,
    carrera_generica            text     NOT NULL,
    clave_carrera_generica      text     NOT NULL,
    acreditacion_anios          smallint NOT NULL CHECK (acreditacion_anios BETWEEN 0 AND 7),
    pct_continuidad_estudios    numeric  NOT NULL CHECK (pct_continuidad_estudios BETWEEN 0 AND 100),
    duracion_real_semestres     numeric           CHECK (duracion_real_semestres > 0),
    -- MiFuturo solo publica la combinación si tiene empleabilidad de 1er año: nunca nula.
    empleabilidad_1er_anio      numeric  NOT NULL CHECK (empleabilidad_1er_anio BETWEEN 0 AND 100),
    empleabilidad_2do_anio      numeric           CHECK (empleabilidad_2do_anio BETWEEN 0 AND 100),
    ingreso_4to_anio_tramo_min  integer           CHECK (ingreso_4to_anio_tramo_min > 0),
    ingreso_4to_anio_tramo_max  integer           CHECK (ingreso_4to_anio_tramo_max > 0),
    PRIMARY KEY (id_institucion, clave_carrera_generica),
    CHECK (ingreso_4to_anio_tramo_max > ingreso_4to_anio_tramo_min),
    -- Un tramo con techo y sin piso no existe ("Sobre $X" tiene piso y no techo).
    CHECK (NOT (ingreso_4to_anio_tramo_min IS NULL AND ingreso_4to_anio_tramo_max IS NOT NULL))
);

-- --------------------------------------------------------------------------
-- Estadísticas por Carrera: carrera genérica × tipo (src/Scrapers/Estadisticas/esquema.py)
-- --------------------------------------------------------------------------
CREATE TABLE raw.estadisticas (
    id_estadisticas                       integer NOT NULL UNIQUE,
    tipo_institucion                      text    NOT NULL,
    carrera_generica                      text    NOT NULL,
    clave_carrera_generica                text    NOT NULL,
    area_conocimiento_mineduc             text    NOT NULL,
    -- La fuente solo publica el par con ingresos (>= 50 casos por año): nunca nulos.
    ingreso_medio_1er_anio                integer NOT NULL CHECK (ingreso_medio_1er_anio > 0),
    ingreso_medio_2do_anio                integer NOT NULL CHECK (ingreso_medio_2do_anio > 0),
    ingreso_medio_3er_anio                integer NOT NULL CHECK (ingreso_medio_3er_anio > 0),
    ingreso_medio_4to_anio                integer NOT NULL CHECK (ingreso_medio_4to_anio > 0),
    ingreso_medio_5to_anio                integer NOT NULL CHECK (ingreso_medio_5to_anio > 0),
    percentil_10_anio_1                   integer NOT NULL CHECK (percentil_10_anio_1 > 0),
    percentil_25_anio_1                   integer NOT NULL,
    percentil_50_anio_1                   integer NOT NULL,
    percentil_75_anio_1                   integer NOT NULL,
    percentil_90_anio_1                   integer NOT NULL,
    percentil_10_anio_5                   integer NOT NULL CHECK (percentil_10_anio_5 > 0),
    percentil_25_anio_5                   integer NOT NULL,
    percentil_50_anio_5                   integer NOT NULL,
    percentil_75_anio_5                   integer NOT NULL,
    percentil_90_anio_5                   integer NOT NULL,
    empleabilidad_1er_anio                numeric NOT NULL CHECK (empleabilidad_1er_anio BETWEEN 0 AND 100),
    empleabilidad_2do_anio                numeric NOT NULL CHECK (empleabilidad_2do_anio BETWEEN 0 AND 100),
    empleabilidad_1er_anio_cohorte_2019   numeric CHECK (empleabilidad_1er_anio_cohorte_2019 BETWEEN 0 AND 100),
    empleabilidad_1er_anio_cohorte_2020   numeric CHECK (empleabilidad_1er_anio_cohorte_2020 BETWEEN 0 AND 100),
    empleabilidad_1er_anio_cohorte_2021   numeric CHECK (empleabilidad_1er_anio_cohorte_2021 BETWEEN 0 AND 100),
    empleabilidad_1er_anio_cohorte_2022   numeric CHECK (empleabilidad_1er_anio_cohorte_2022 BETWEEN 0 AND 100),
    empleabilidad_1er_anio_cohorte_2023   numeric CHECK (empleabilidad_1er_anio_cohorte_2023 BETWEEN 0 AND 100),
    empleabilidad_2do_anio_cohorte_2018   numeric CHECK (empleabilidad_2do_anio_cohorte_2018 BETWEEN 0 AND 100),
    empleabilidad_2do_anio_cohorte_2019   numeric CHECK (empleabilidad_2do_anio_cohorte_2019 BETWEEN 0 AND 100),
    empleabilidad_2do_anio_cohorte_2020   numeric CHECK (empleabilidad_2do_anio_cohorte_2020 BETWEEN 0 AND 100),
    empleabilidad_2do_anio_cohorte_2021   numeric CHECK (empleabilidad_2do_anio_cohorte_2021 BETWEEN 0 AND 100),
    empleabilidad_2do_anio_cohorte_2022   numeric CHECK (empleabilidad_2do_anio_cohorte_2022 BETWEEN 0 AND 100),
    ingreso_medio_4to_anio_cohorte_2016   integer CHECK (ingreso_medio_4to_anio_cohorte_2016 > 0),
    ingreso_medio_4to_anio_cohorte_2017   integer CHECK (ingreso_medio_4to_anio_cohorte_2017 > 0),
    ingreso_medio_4to_anio_cohorte_2018   integer CHECK (ingreso_medio_4to_anio_cohorte_2018 > 0),
    ingreso_medio_4to_anio_cohorte_2019   integer CHECK (ingreso_medio_4to_anio_cohorte_2019 > 0),
    ingreso_medio_4to_anio_cohorte_2020   integer CHECK (ingreso_medio_4to_anio_cohorte_2020 > 0),
    titulados_2024                        integer NOT NULL CHECK (titulados_2024 >= 0),
    titulados_2024_mujeres                integer NOT NULL CHECK (titulados_2024_mujeres >= 0),
    titulados_2024_hombres                integer NOT NULL CHECK (titulados_2024_hombres >= 0),
    duracion_formal_semestres             numeric CHECK (duracion_formal_semestres > 0),
    duracion_real_semestres               numeric CHECK (duracion_real_semestres > 0),
    PRIMARY KEY (clave_carrera_generica, tipo_institucion),
    -- Un percentil menor que el anterior es imposible: señal de columnas cruzadas en la fuente.
    CHECK (percentil_10_anio_1 <= percentil_25_anio_1 AND percentil_25_anio_1 <= percentil_50_anio_1
       AND percentil_50_anio_1 <= percentil_75_anio_1 AND percentil_75_anio_1 <= percentil_90_anio_1),
    CHECK (percentil_10_anio_5 <= percentil_25_anio_5 AND percentil_25_anio_5 <= percentil_50_anio_5
       AND percentil_50_anio_5 <= percentil_75_anio_5 AND percentil_75_anio_5 <= percentil_90_anio_5),
    -- <= y no =: la fuente no informa titulados no binarios por separado.
    CHECK (titulados_2024_mujeres + titulados_2024_hombres <= titulados_2024)
);

-- --------------------------------------------------------------------------
-- Titulados SIES: programa × año (src/Scrapers/Titulados/esquema.py)
-- --------------------------------------------------------------------------
CREATE TABLE raw.titulados (
    anio                           smallint NOT NULL CHECK (anio BETWEEN 2007 AND 2100),
    codigo_programa                text     NOT NULL,
    codigo_institucion             integer  NOT NULL,
    institucion                    text     NOT NULL,
    clave_institucion              text     NOT NULL,
    tipo_institucion               text     NOT NULL,
    subtipo_institucion            text     NOT NULL,
    carrera                        text     NOT NULL,
    carrera_generica               text     NOT NULL,
    clave_carrera_generica         text     NOT NULL,
    cine13_area                    text     NOT NULL,
    cine13_subarea                 text     NOT NULL,
    nivel_carrera                  text     NOT NULL,
    carrera_clasificacion_nivel_1  text     NOT NULL,
    tipo_plan                      text     NOT NULL,
    modalidad                      text     NOT NULL,
    jornada                        text     NOT NULL,
    duracion_semestres             numeric  NOT NULL CHECK (duracion_semestres > 0 AND duracion_semestres <= 30),
    total_titulaciones             integer  NOT NULL CHECK (total_titulaciones >= 0),
    titulaciones_mujeres           integer  NOT NULL CHECK (titulaciones_mujeres >= 0),
    titulaciones_hombres           integer  NOT NULL CHECK (titulaciones_hombres >= 0),
    titulaciones_nb                integer  NOT NULL CHECK (titulaciones_nb >= 0),
    titulados_15_19                integer  NOT NULL CHECK (titulados_15_19 >= 0),
    titulados_20_24                integer  NOT NULL CHECK (titulados_20_24 >= 0),
    titulados_25_29                integer  NOT NULL CHECK (titulados_25_29 >= 0),
    titulados_30_34                integer  NOT NULL CHECK (titulados_30_34 >= 0),
    titulados_35_39                integer  NOT NULL CHECK (titulados_35_39 >= 0),
    titulados_mayores_40           integer  NOT NULL CHECK (titulados_mayores_40 >= 0),
    titulados_edad_sin_info        integer  NOT NULL CHECK (titulados_edad_sin_info >= 0),
    edad_promedio                  numeric           CHECK (edad_promedio BETWEEN 15 AND 80),
    PRIMARY KEY (anio, codigo_programa),
    -- Verificado en el 100% de las filas del crudo: si no cuadra, la lectura del CSV falló.
    CHECK (titulaciones_mujeres + titulaciones_hombres + titulaciones_nb = total_titulaciones),
    CHECK (titulados_15_19 + titulados_20_24 + titulados_25_29 + titulados_30_34
         + titulados_35_39 + titulados_mayores_40 + titulados_edad_sin_info = total_titulaciones)
);

COMMIT;
