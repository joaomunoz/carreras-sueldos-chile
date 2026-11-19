-- src/BD/04_qa.sql
--
-- Controles de calidad semánticos (T3). Corre dentro de la transacción única de
-- src/BD/build.py, después de 03_poblar_modelo.sql.
--
-- Diferencia con los DO de 03_poblar_modelo.sql: aquellos son SUPUESTOS sin los cuales no se
-- puede poblar el modelo y abortan en el acto. Estos controles verifican que los datos
-- SIGNIFICAN lo que creemos; se registran todos en qa.control y build.py falla al final si
-- alguno quedó en FALLA. Así un build roto muestra todos los problemas juntos, no solo el
-- primero, y un build sano deja la evidencia consultable en la base.
--
-- El tercer control de build.py (columnas de raw = los 3 esquema.py) se escribe desde Python,
-- porque los esquemas viven en Python y no en la base.

DROP SCHEMA IF EXISTS qa CASCADE;
CREATE SCHEMA qa;

CREATE TABLE qa.control (
    control  text    NOT NULL,   -- nombre del control
    objeto   text    NOT NULL,   -- tabla, indicador o serie evaluada
    estado   text    NOT NULL CHECK (estado IN ('OK', 'FALLA', 'EXENTO')),
    metrica  numeric,            -- valor medido (NULL si el control es solo sí/no)
    umbral   text    NOT NULL,   -- criterio de aprobación, legible
    detalle  text    NOT NULL,
    PRIMARY KEY (control, objeto)
);
COMMENT ON TABLE qa.control IS
    'Resultado de los controles del último build exitoso (src/BD/04_qa.sql y src/BD/build.py).';

-- --------------------------------------------------------------------------
-- 1. Cohortes de MiFuturo presentes en el SIES
-- --------------------------------------------------------------------------
-- El análisis cruza cada indicador con la oferta de titulados de SUS cohortes (n_inst_oferta,
-- choque de oferta joven). Si una cohorte no existe en el SIES, ese cruce saldría vacío o
-- parcial sin error. Las series quedan EXENTAS: por D5 son solo control de estabilidad y no se
-- cruzan con el SIES (la del ingreso al 4° año parte en 2016, antes del alcance 2017-2025).
INSERT INTO qa.control (control, objeto, estado, metrica, umbral, detalle)
SELECT 'cohorte_en_sies',
       c.indicador,
       CASE WHEN c.indicador LIKE 'serie\_%' THEN 'EXENTO'
            WHEN f.n_faltan = 0 THEN 'OK'
            ELSE 'FALLA' END,
       f.n_faltan,
       '0 años de cohorte sin titulaciones en modelo.titulacion',
       format('cohortes %s-%s%s%s', c.cohorte_desde, c.cohorte_hasta,
              CASE WHEN f.n_faltan > 0 THEN '; faltan en SIES: ' || f.faltan END,
              CASE WHEN c.indicador LIKE 'serie\_%' THEN '; las series de MiFuturo solo sirven para ver si la cohorte es estable y no se cruzan con el SIES' END)
FROM modelo.cohorte c
CROSS JOIN LATERAL (
    SELECT count(*) AS n_faltan, string_agg(y::text, ', ' ORDER BY y) AS faltan
    FROM generate_series(c.cohorte_desde::int, c.cohorte_hasta::int) AS y
    WHERE NOT EXISTS (SELECT 1 FROM modelo.titulacion t WHERE t.anio = y)
) f;

-- --------------------------------------------------------------------------
-- 2. Correspondencia ORIGEN de las series (src/Scrapers/Estadisticas/esquema.py)
-- --------------------------------------------------------------------------
-- La cohorte de cada punto de serie es una INFERENCIA: la API nombra los campos con años de un
-- esquema antiguo (emplea_1_2015 = cohorte 2019). Se verifica con la propia fuente: el
-- agregado publicado (p. ej. empleabilidad 1er año, cohortes 2021-2023 según modelo.cohorte)
-- debe parecerse al promedio simple de los 3 puntos de serie de ESAS cohortes, y bastante
-- menos al de las mismas ventanas corridas 1 o 2 años (que es lo que se vería si el desfase
-- estuviera mal). No es igualdad exacta: el agregado pondera por casos y el promedio simple no.
--
-- Criterios (calibrados en el build del 16-11-26: desfase 0 → mediana 0,28-0,38 %;
-- desfase -1 → 1,82-2,33 %):
--   a) mediana del |error relativo| con desfase 0 < 1 %;
--   b) esa mediana ≤ la mitad de la mejor alternativa (desfases -1 y -2);
--   c) ≥ 100 pares comparables (con los 3 puntos publicados); con menos, el control no prueba nada.
-- El desfase +1 no se puede probar (necesitaría la cohorte 2024), pero si el significado real
-- fuera +1, el desfase 0 se comportaría como hoy lo hace el -1 y fallaría (a).
INSERT INTO qa.control (control, objeto, estado, metrica, umbral, detalle)
WITH comparacion (serie, indicador_agregado) AS (VALUES
    ('serie_empleabilidad_1er_anio', 'empleabilidad_1er_anio_nacional'),
    ('serie_empleabilidad_2do_anio', 'empleabilidad_2do_anio_nacional'),
    ('serie_ingreso_medio_4to_anio', 'ingreso_medio_4to_anio')
),
agregado AS (
    SELECT e.clave_carrera_generica, e.tipo_institucion, cmp.serie,
           c.cohorte_desde, c.cohorte_hasta,
           CASE cmp.serie
               WHEN 'serie_empleabilidad_1er_anio' THEN e.empleabilidad_1er_anio
               WHEN 'serie_empleabilidad_2do_anio' THEN e.empleabilidad_2do_anio
               WHEN 'serie_ingreso_medio_4to_anio' THEN e.ingreso_medio_4to_anio
           END::numeric AS valor
    FROM modelo.mifuturo_estadistica e
    CROSS JOIN comparacion cmp
    JOIN modelo.cohorte c ON c.indicador = cmp.indicador_agregado
),
error_par AS (
    SELECT a.serie, d.desfase,
           abs(avg(s.valor) - a.valor) / a.valor AS error_rel
    FROM agregado a
    CROSS JOIN generate_series(-2, 0) AS d(desfase)
    JOIN modelo.mifuturo_serie s
      ON s.clave_carrera_generica = a.clave_carrera_generica
     AND s.tipo_institucion = a.tipo_institucion
     AND s.indicador = a.serie
     AND s.cohorte BETWEEN a.cohorte_desde + d.desfase AND a.cohorte_hasta + d.desfase
    WHERE a.valor > 0
    GROUP BY a.serie, a.clave_carrera_generica, a.tipo_institucion, a.valor, d.desfase
    HAVING count(*) = 3
),
por_desfase AS (
    SELECT serie, desfase, count(*) AS pares,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY error_rel) AS mediana
    FROM error_par
    GROUP BY serie, desfase
),
resumen AS (
    SELECT cmp.serie,
           max(p.mediana) FILTER (WHERE p.desfase = 0)  AS med_0,
           min(p.mediana) FILTER (WHERE p.desfase <> 0) AS med_alt,
           max(p.mediana) FILTER (WHERE p.desfase = -1) AS med_m1,
           max(p.mediana) FILTER (WHERE p.desfase = -2) AS med_m2,
           coalesce(max(p.pares) FILTER (WHERE p.desfase = 0), 0) AS pares_0
    FROM comparacion cmp
    LEFT JOIN por_desfase p USING (serie)
    GROUP BY cmp.serie
)
SELECT 'origen_series',
       serie,
       CASE WHEN med_0 < 0.01 AND med_0 <= 0.5 * med_alt AND pares_0 >= 100
            THEN 'OK' ELSE 'FALLA' END,
       round(100 * med_0::numeric, 2),
       'mediana |error| desfase 0 < 1 %, ≤ mitad de desfases -1/-2, ≥ 100 pares',
       -- n/d: ese desfase no tiene pares con los 3 puntos publicados.
       format('mediana |error relativo|: desfase 0 = %s %%, -1 = %s %%, -2 = %s %%; %s pares comparables',
              coalesce(round(100 * med_0::numeric, 2)::text, 'n/d'),
              coalesce(round(100 * med_m1::numeric, 2)::text, 'n/d'),
              coalesce(round(100 * med_m2::numeric, 2)::text, 'n/d'), pares_0)
FROM resumen;
