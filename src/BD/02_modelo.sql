-- src/BD/02_modelo.sql
--
-- Esquema `modelo`: modelo relacional aprobado en T0 (pizarra, log 15-11-26 21:51), ajustado
-- con la salida de Estadísticas (log 16-11-26 00:43). Solo estructura y datos de referencia
-- fijos (`cohorte`); las tablas se pueblan desde `raw` en un paso posterior (T2).
--
-- Principios:
--   - Tablas de referencia compartidas (`institucion`, `carrera_generica`): las fuentes no
--     calzan 1 a 1 (164 vs. 105 instituciones; 272 vs. 190 y 165 genéricas), así que una FK
--     directa entre fuentes perdería filas.
--   - Cada hecho en su granularidad: los valores nacionales por carrera × tipo viven en
--     `mifuturo_estadistica` (252 filas), nunca repetidos por institución.
--   - Lo que cambia entre años (subtipo, plan, cine13, nombre del programa) vive en
--     `titulacion`, no en las referencias.
--   - Dominios de categorías como CHECK: una categoría nueva en la fuente debe romper la
--     carga, no colarse en un segmento que nadie definió.
--
-- Idempotente: recrea el esquema desde cero (borra solo `modelo`).
-- Ejecutar con: psql -v ON_ERROR_STOP=1 -f src/BD/02_modelo.sql

BEGIN;

DROP SCHEMA IF EXISTS modelo CASCADE;
CREATE SCHEMA modelo;
COMMENT ON SCHEMA modelo IS 'Modelo relacional poblado desde raw; fuente de las consultas de src/Analisis/sql.';

-- --------------------------------------------------------------------------
-- Referencias
-- --------------------------------------------------------------------------
CREATE TABLE modelo.institucion (
    codigo_institucion  integer PRIMARY KEY,   -- = id_institucion MiFuturo (verificado 105/105)
    nombre              text    NOT NULL,      -- nombre SIES del año más reciente, sin sufijo de convenio
    tipo_institucion    text    NOT NULL CHECK (tipo_institucion IN ('Universidad', 'IP', 'CFT')),
    -- Destino de las FK compuestas: garantiza que el tipo declarado en cada hecho sea el de
    -- la institución, sin depender de un control posterior.
    UNIQUE (codigo_institucion, tipo_institucion)
);

CREATE TABLE modelo.carrera_generica (
    clave_carrera_generica  text PRIMARY KEY,  -- normalizar_texto(); misma regla en las 3 fuentes
    nombre                  text NOT NULL,     -- nombre con tildes para mostrar
    -- Verificado: cada genérica tiene un solo nivel (272/272), por eso es atributo de la genérica.
    nivel_carrera           text NOT NULL CHECK (nivel_carrera IN ('Carreras Profesionales', 'Carreras Técnicas'))
);

-- Años de cada indicador en UN solo lugar: MiFuturo corre sus cohortes cada año y un año
-- escrito fijo en una consulta quedaría desalineado sin error.
CREATE TABLE modelo.cohorte (
    indicador           text     PRIMARY KEY,
    fuente              text     NOT NULL CHECK (fuente IN ('Empleabilidad', 'Estadisticas', 'Titulados')),
    cohorte_desde       smallint NOT NULL,
    cohorte_hasta       smallint NOT NULL,
    anio_ingreso_desde  smallint,              -- NULL: el indicador no se mide sobre ingresos SII
    anio_ingreso_hasta  smallint,
    min_casos           smallint,              -- umbral de publicación declarado por la fuente
    referencia          text     NOT NULL,     -- documento y líneas de datos externos/
    CHECK (cohorte_desde <= cohorte_hasta),
    CHECK (anio_ingreso_desde <= anio_ingreso_hasta),
    CHECK ((anio_ingreso_desde IS NULL) = (anio_ingreso_hasta IS NULL))
);
COMMENT ON TABLE modelo.cohorte IS
    'Derecho usa en todos los indicadores MiFuturo la cohorte de titulación + 1 año (metodologías 2025-2026).';

INSERT INTO modelo.cohorte VALUES
    -- Buscador de Estadísticas por Carrera (nacional, carrera genérica × tipo)
    ('ingreso_medio_1er_anio',        'Estadisticas', 2021, 2023, 2022, 2024, 50, 'Metodologia-Estadisticas-por-Carrera, líneas 89 y 93'),
    ('ingreso_medio_2do_anio',        'Estadisticas', 2020, 2022, 2022, 2024, 50, 'Metodologia-Estadisticas-por-Carrera, líneas 89 y 93'),
    ('ingreso_medio_3er_anio',        'Estadisticas', 2019, 2021, 2022, 2024, 50, 'Metodologia-Estadisticas-por-Carrera, líneas 89 y 93'),
    ('ingreso_medio_4to_anio',        'Estadisticas', 2018, 2020, 2022, 2024, 50, 'Metodologia-Estadisticas-por-Carrera, líneas 89 y 93'),
    ('ingreso_medio_5to_anio',        'Estadisticas', 2017, 2019, 2022, 2024, 50, 'Metodologia-Estadisticas-por-Carrera, líneas 89 y 93'),
    ('percentiles_anio_1',            'Estadisticas', 2023, 2023, 2024, 2024, 11, 'Metodologia-Estadisticas-por-Carrera, línea 97'),
    ('percentiles_anio_5',            'Estadisticas', 2019, 2019, 2024, 2024, 11, 'Metodologia-Estadisticas-por-Carrera, línea 97'),
    ('empleabilidad_1er_anio_nacional','Estadisticas', 2021, 2023, 2022, 2024, 50, 'Metodologia-Estadisticas-por-Carrera, líneas 111 y 113'),
    -- La línea 111 dice "2020, 2021 y 2021": errata; la serie y el Buscador de Empleabilidad dan 2020-2022.
    ('empleabilidad_2do_anio_nacional','Estadisticas', 2020, 2022, 2022, 2024, 50, 'Metodologia-Estadisticas-por-Carrera, líneas 111 y 113 (errata corregida)'),
    ('serie_empleabilidad_1er_anio',  'Estadisticas', 2019, 2023, 2020, 2024, 25, 'Metodologia-Estadisticas-por-Carrera, líneas 117 y 119'),
    ('serie_empleabilidad_2do_anio',  'Estadisticas', 2018, 2022, 2020, 2024, 25, 'Metodologia-Estadisticas-por-Carrera, líneas 117 y 119'),
    ('serie_ingreso_medio_4to_anio',  'Estadisticas', 2016, 2020, 2020, 2024, 25, 'Metodologia-Estadisticas-por-Carrera, líneas 101 y 103'),
    ('titulados_y_duracion',          'Estadisticas', 2024, 2024, NULL, NULL, 25, 'Metodologia-Estadisticas-por-Carrera, líneas 123, 129 y 131'),
    -- Buscador de Empleabilidad e Ingresos (institución × carrera genérica)
    ('empleabilidad_1er_anio_institucion','Empleabilidad', 2021, 2023, 2022, 2024, 25, 'Metodologia-Buscador-Empleabilidad-e-Ingresos, línea 86'),
    ('empleabilidad_2do_anio_institucion','Empleabilidad', 2020, 2022, 2022, 2024, 25, 'Metodologia-Buscador-Empleabilidad-e-Ingresos, línea 97'),
    ('tramo_ingreso_4to_anio_institucion','Empleabilidad', 2018, 2020, 2022, 2024, 11, 'Metodologia-Buscador-Empleabilidad-e-Ingresos, líneas 103 y 105'),
    ('continuidad_estudios_institucion',  'Empleabilidad', 2021, 2023, NULL, NULL, NULL, 'Metodologia-Buscador-Empleabilidad-e-Ingresos, línea 74'),
    ('duracion_real_institucion',         'Empleabilidad', 2024, 2024, NULL, NULL, 25, 'Metodologia-Buscador-Empleabilidad-e-Ingresos, línea 82'),
    -- Titulados SIES (años disponibles en raw.titulados)
    ('titulados_sies',                'Titulados',    2017, 2025, NULL, NULL, NULL, 'src/Scrapers/Titulados/procesar.py (alcance pregrado 2017-2025)');

-- --------------------------------------------------------------------------
-- Hechos
-- --------------------------------------------------------------------------

-- SIES: un programa en un año. Cuenta TITULACIONES, no personas.
CREATE TABLE modelo.titulacion (
    anio                           smallint NOT NULL,
    codigo_programa                text     NOT NULL,
    codigo_institucion             integer  NOT NULL REFERENCES modelo.institucion,
    clave_carrera_generica         text     NOT NULL REFERENCES modelo.carrera_generica,
    carrera                        text     NOT NULL,
    -- Cambia entre años (3 universidades pasan a CRUCH en 2019-2020): es del año, no de la institución.
    subtipo_institucion            text     NOT NULL CHECK (subtipo_institucion IN
        ('Universidades CRUCH', 'Universidades Privadas', 'Institutos Profesionales', 'Centros de Formación Técnica')),
    es_convenio                    boolean  NOT NULL,   -- nombre SIES con "(*CARRERA EN CONVENIO ...)"
    -- Atributo del programa: 13 genéricas caen en más de un área (decisión de área en Analisis/sql).
    cine13_area                    text     NOT NULL,
    cine13_subarea                 text     NOT NULL,
    carrera_clasificacion_nivel_1  text     NOT NULL CHECK (carrera_clasificacion_nivel_1 IN
        ('Técnico de Nivel Superior', 'Profesional Con Licenciatura', 'Profesional Sin Licenciatura',
         'Licenciatura No Conducente a Título')),
    tipo_plan                      text     NOT NULL CHECK (tipo_plan IN ('Plan Regular', 'Plan Especial', 'Plan Regular de Continuidad')),
    modalidad                      text     NOT NULL CHECK (modalidad IN ('Presencial', 'Semipresencial', 'No Presencial')),
    jornada                        text     NOT NULL CHECK (jornada IN ('Diurna', 'Vespertina', 'Semipresencial', 'A Distancia', 'Otra')),
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
    CHECK (titulaciones_mujeres + titulaciones_hombres + titulaciones_nb = total_titulaciones),
    CHECK (titulados_15_19 + titulados_20_24 + titulados_25_29 + titulados_30_34
         + titulados_35_39 + titulados_mayores_40 + titulados_edad_sin_info = total_titulaciones)
);
-- Las consultas de cobertura y oferta agregan por genérica y cohorte, y por institución.
CREATE INDEX ON modelo.titulacion (clave_carrera_generica, anio);
CREATE INDEX ON modelo.titulacion (codigo_institucion);

-- MiFuturo, Buscador de Empleabilidad: institución × carrera genérica (1.690).
-- Única fuente de resultados por institución (empleabilidad y tramo del 4° año).
CREATE TABLE modelo.mifuturo_programa (
    codigo_institucion          integer  NOT NULL,
    tipo_institucion            text     NOT NULL,
    clave_carrera_generica      text     NOT NULL REFERENCES modelo.carrera_generica,
    carrera                     text     NOT NULL,
    acreditacion_anios          smallint NOT NULL CHECK (acreditacion_anios BETWEEN 0 AND 7),
    pct_continuidad_estudios    numeric  NOT NULL CHECK (pct_continuidad_estudios BETWEEN 0 AND 100),
    duracion_real_semestres     numeric           CHECK (duracion_real_semestres > 0),
    -- % con ingreso >= sueldo mínimo ENTRE titulados con registro en el SII.
    empleabilidad_1er_anio      numeric  NOT NULL CHECK (empleabilidad_1er_anio BETWEEN 0 AND 100),
    empleabilidad_2do_anio      numeric           CHECK (empleabilidad_2do_anio BETWEEN 0 AND 100),
    -- Intervalo, nunca punto medio; NULL = no publicado (< 11 casos SII), sin imputar.
    ingreso_4to_anio_tramo_min  integer           CHECK (ingreso_4to_anio_tramo_min > 0),
    ingreso_4to_anio_tramo_max  integer,
    PRIMARY KEY (codigo_institucion, clave_carrera_generica),
    FOREIGN KEY (codigo_institucion, tipo_institucion)
        REFERENCES modelo.institucion (codigo_institucion, tipo_institucion),
    CHECK (ingreso_4to_anio_tramo_max > ingreso_4to_anio_tramo_min),
    CHECK (NOT (ingreso_4to_anio_tramo_min IS NULL AND ingreso_4to_anio_tramo_max IS NOT NULL))
);
-- Sin FK hacia mifuturo_estadistica a propósito: 48 pares de programa no tienen estadística
-- publicada y 3 pares de estadística no tienen institución. La cobertura se mide en `qa`.

-- MiFuturo, Buscador de Estadísticas por Carrera: carrera genérica × tipo (252). Nacional.
CREATE TABLE modelo.mifuturo_estadistica (
    clave_carrera_generica  text    NOT NULL REFERENCES modelo.carrera_generica,
    tipo_institucion        text    NOT NULL CHECK (tipo_institucion IN ('Universidad', 'IP', 'CFT')),
    id_estadisticas         integer NOT NULL UNIQUE,   -- trazabilidad hacia MiFuturo; no es llave
    area_conocimiento_mineduc text  NOT NULL,          -- etiqueta CINE-97 de MiFuturo; NO es cine13
    -- Media: 3 cohortes por año (ver modelo.cohorte). Percentiles: UNA cohorte, ingresos 2024.
    -- Poblaciones distintas: no se combinan en una misma razón (p. ej. Media/P50).
    ingreso_medio_1er_anio  integer NOT NULL CHECK (ingreso_medio_1er_anio > 0),
    ingreso_medio_2do_anio  integer NOT NULL CHECK (ingreso_medio_2do_anio > 0),
    ingreso_medio_3er_anio  integer NOT NULL CHECK (ingreso_medio_3er_anio > 0),
    ingreso_medio_4to_anio  integer NOT NULL CHECK (ingreso_medio_4to_anio > 0),
    ingreso_medio_5to_anio  integer NOT NULL CHECK (ingreso_medio_5to_anio > 0),
    percentil_10_anio_1     integer NOT NULL CHECK (percentil_10_anio_1 > 0),
    percentil_25_anio_1     integer NOT NULL,
    percentil_50_anio_1     integer NOT NULL,
    percentil_75_anio_1     integer NOT NULL,
    percentil_90_anio_1     integer NOT NULL,
    percentil_10_anio_5     integer NOT NULL CHECK (percentil_10_anio_5 > 0),
    percentil_25_anio_5     integer NOT NULL,
    percentil_50_anio_5     integer NOT NULL,
    percentil_75_anio_5     integer NOT NULL,
    percentil_90_anio_5     integer NOT NULL,
    empleabilidad_1er_anio  numeric NOT NULL CHECK (empleabilidad_1er_anio BETWEEN 0 AND 100),
    empleabilidad_2do_anio  numeric NOT NULL CHECK (empleabilidad_2do_anio BETWEEN 0 AND 100),
    titulados_2024          integer NOT NULL CHECK (titulados_2024 >= 0),   -- PERSONAS, no titulaciones
    titulados_2024_mujeres  integer NOT NULL CHECK (titulados_2024_mujeres >= 0),
    titulados_2024_hombres  integer NOT NULL CHECK (titulados_2024_hombres >= 0),
    duracion_formal_semestres numeric CHECK (duracion_formal_semestres > 0),  -- plan + titulación
    duracion_real_semestres   numeric CHECK (duracion_real_semestres > 0),
    PRIMARY KEY (clave_carrera_generica, tipo_institucion),
    CHECK (percentil_10_anio_1 <= percentil_25_anio_1 AND percentil_25_anio_1 <= percentil_50_anio_1
       AND percentil_50_anio_1 <= percentil_75_anio_1 AND percentil_75_anio_1 <= percentil_90_anio_1),
    CHECK (percentil_10_anio_5 <= percentil_25_anio_5 AND percentil_25_anio_5 <= percentil_50_anio_5
       AND percentil_50_anio_5 <= percentil_75_anio_5 AND percentil_75_anio_5 <= percentil_90_anio_5),
    CHECK (titulados_2024_mujeres + titulados_2024_hombres <= titulados_2024)
);

-- Series de 5 cohortes en formato largo: una fila por par × indicador × cohorte. En `raw`
-- son 15 columnas; aquí se normalizan para comparar cohortes con funciones de ventana.
-- Un punto no publicado (< 25 casos) no tiene fila: la ausencia es el dato.
CREATE TABLE modelo.mifuturo_serie (
    clave_carrera_generica  text     NOT NULL,
    tipo_institucion        text     NOT NULL,
    indicador               text     NOT NULL REFERENCES modelo.cohorte,
    cohorte                 smallint NOT NULL,
    valor                   numeric  NOT NULL CHECK (valor > 0),
    PRIMARY KEY (clave_carrera_generica, tipo_institucion, indicador, cohorte),
    FOREIGN KEY (clave_carrera_generica, tipo_institucion)
        REFERENCES modelo.mifuturo_estadistica (clave_carrera_generica, tipo_institucion),
    CHECK (indicador IN ('serie_empleabilidad_1er_anio', 'serie_empleabilidad_2do_anio', 'serie_ingreso_medio_4to_anio')),
    CHECK (indicador = 'serie_ingreso_medio_4to_anio' OR valor <= 100)
);

COMMIT;
