-- src/Analisis/sql/analytics/06_hallazgos.sql
--
-- Cifras y ejemplos de los tres hallazgos de portada ("Parece que… / Pero…"). La web y el README
-- solo los redactan: ninguna cifra de un hallazgo se calcula fuera de este archivo.
--
-- Por qué en SQL: hasta la revisión del 16-11-26 los calculaba src/Web/app.js, la única capa sin
-- controles qa, y ahí aparecieron los errores de contenido (la mediana de edad del hallazgo (a) se
-- calculaba sobre las 9 carreras que bajan y la frase la atribuía a 7). Aquí cada cifra se calcula
-- sobre el mismo conjunto que nombra la frase, y un control lo verifica por otro camino.
--
-- Los ejemplos se eligen por regla, no a dedo (la misma regla que tenía la web):
--   (b) entre las carreras que cambian de cuadrante y progresan más en %, la de mayor %, siempre
--       que su aumento en pesos quede al menos margen_ejemplo_pesos bajo la mediana de su grupo;
--   (c) entre las de promedio engañoso con >= min_inst_ejemplo instituciones, la de mayor IQR.
-- Empates: por tipo y clave, el mismo orden del JSON. Requiere 01 a 05.

-- Antes eran números escritos en app.js (0.8 y 20): ahora viven con el resto de los umbrales.
INSERT INTO analytics.parametro VALUES
    ('margen_ejemplo_pesos', 0.20, 'Hallazgo (b): el ejemplo crece en pesos al menos esta proporción menos que la mediana de su grupo (sin margen podría ser la propia mediana)', 'W3; movido de app.js a SQL en la revisión del 16-11-26'),
    ('min_inst_ejemplo',     20,   'Hallazgo (c): instituciones mínimas para que una carrera sirva de ejemplo (con pocas sería anecdótico)',                                  'W3; ídem');

-- --------------------------------------------------------------------------
-- (a) Al quinto año no siempre se gana más
-- --------------------------------------------------------------------------
CREATE TABLE analytics.hallazgo_edad (
    n_comparables    integer NOT NULL,
    mediana_p50_pct  numeric NOT NULL,   -- mediana SIMPLE (no ponderada) del crecimiento del P50 1°→5°
    n_negativos      integer NOT NULL,   -- comparables cuyo P50 del 5° año es menor que el del 1°
    n_con_edad       integer NOT NULL,   -- de ellas, con la marca de composición por edad
    n_base_edad      integer NOT NULL,   -- carreras sobre las que se calculan las dos medianas de edad
    mayores30_p5     numeric,            -- mediana de la cota alta de 30+ (0-1), cohorte del 5° año
    mayores30_p1     numeric,            -- ídem, cohorte del 1er año
    -- La frase dice "en N de ellas… pasan de X a Y": X e Y deben describir a esas N.
    CHECK (n_base_edad = n_con_edad),
    CHECK (n_con_edad <= n_negativos AND n_negativos <= n_comparables),
    CHECK ((n_con_edad = 0) = (mayores30_p5 IS NULL))
);

INSERT INTO analytics.hallazgo_edad
WITH comp AS (
    SELECT b.p50_pct_1_5, c.composicion_edad, c.mayores30_max_p5, c.mayores30_max_p1
    FROM analytics.par p
    JOIN analytics.brecha b   USING (clave_carrera_generica, tipo_institucion)
    JOIN analytics.contexto c USING (clave_carrera_generica, tipo_institucion)
    WHERE p.representativo
),
edad AS (SELECT * FROM comp WHERE p50_pct_1_5 < 0 AND composicion_edad)
SELECT (SELECT count(*) FROM comp),
       (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY p50_pct_1_5) FROM comp)::numeric,
       (SELECT count(*) FROM comp WHERE p50_pct_1_5 < 0),
       (SELECT count(*) FROM comp WHERE p50_pct_1_5 < 0 AND composicion_edad),
       count(*),
       percentile_cont(0.5) WITHIN GROUP (ORDER BY mayores30_max_p5)::numeric,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY mayores30_max_p1)::numeric
FROM edad;

-- --------------------------------------------------------------------------
-- (b) Crecer más en % no es crecer más
-- --------------------------------------------------------------------------
CREATE TABLE analytics.hallazgo_pct_pesos (
    n_cambian               integer NOT NULL,   -- cambian de cuadrante entre % y pesos
    clave_carrera_generica  text,               -- ejemplo; NULL si ninguna cumple la regla
    tipo_institucion        text,
    p50_anio_1              integer,
    p50_pct_1_5             numeric,
    p50_delta_1_5           numeric,
    ref_delta_q50           numeric,            -- mediana PONDERADA del aumento en pesos de su grupo
    FOREIGN KEY (clave_carrera_generica, tipo_institucion) REFERENCES analytics.par
);

INSERT INTO analytics.hallazgo_pct_pesos
WITH cand AS (
    SELECT po.clave_carrera_generica, po.tipo_institucion, e.percentil_50_anio_1,
           b.p50_pct_1_5, b.p50_delta_1_5, r.q50
    FROM analytics.posicion po
    JOIN analytics.brecha b USING (clave_carrera_generica, tipo_institucion)
    JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
    JOIN analytics.referencia r ON r.grupo_id = po.grupo_id AND r.metrica = 'p50_delta_1_5'
    WHERE po.cambia_cuadrante AND po.progresa_mas_pct
      AND b.p50_delta_1_5 <= (1 - analytics.param('margen_ejemplo_pesos')) * r.q50
)
SELECT (SELECT count(*) FROM analytics.posicion WHERE cambia_cuadrante),
       ej.clave_carrera_generica, ej.tipo_institucion, ej.percentil_50_anio_1,
       ej.p50_pct_1_5, ej.p50_delta_1_5, ej.q50
FROM (VALUES (1)) AS uno (x)
LEFT JOIN LATERAL (SELECT * FROM cand
                   ORDER BY p50_pct_1_5 DESC, tipo_institucion, clave_carrera_generica
                   LIMIT 1) ej ON true;

-- --------------------------------------------------------------------------
-- (c) El promedio nacional esconde diferencias entre instituciones
-- --------------------------------------------------------------------------
CREATE TABLE analytics.hallazgo_dispersion (
    n_enganosos             integer NOT NULL,
    clave_carrera_generica  text,
    tipo_institucion        text,
    n_inst                  integer,
    q1                      numeric,   -- la frase cita la mitad central (q1–q3): es lo que mide el criterio
    q3                      numeric,
    iqr                     numeric,
    nacional                numeric,
    FOREIGN KEY (clave_carrera_generica, tipo_institucion) REFERENCES analytics.par
);

INSERT INTO analytics.hallazgo_dispersion
SELECT (SELECT count(*) FROM analytics.dispersion_empleabilidad WHERE anio = 1 AND promedio_enganoso),
       ej.clave_carrera_generica, ej.tipo_institucion, ej.n_inst, ej.q1, ej.q3, ej.iqr, ej.nacional
FROM (VALUES (1)) AS uno (x)
LEFT JOIN LATERAL (
    SELECT clave_carrera_generica, tipo_institucion, n_inst, q1, q3, iqr, nacional
    FROM analytics.dispersion_empleabilidad
    WHERE anio = 1 AND promedio_enganoso AND n_inst >= analytics.param('min_inst_ejemplo')
    ORDER BY iqr DESC, tipo_institucion, clave_carrera_generica
    LIMIT 1) ej ON true;

-- --------------------------------------------------------------------------
-- Controles qa
-- --------------------------------------------------------------------------
INSERT INTO qa.control (control, objeto, estado, metrica, umbral, detalle)
-- 1. (a) por otro camino: P50 desde modelo (no desde brecha) y la marca con su fórmula (no la columna).
SELECT 'analytics_hallazgos', 'edad_mismo_grupo',
       CASE WHEN h.n_con_edad = x.n AND h.mayores30_p5 IS NOT DISTINCT FROM x.p5
                 AND h.mayores30_p1 IS NOT DISTINCT FROM x.p1 THEN 'OK' ELSE 'FALLA' END,
       x.n, 'medianas de edad = recálculo sobre las carreras que bajan y tienen la marca de edad',
       format('%s de %s carreras que bajan; 30+ pasa de %s %% a %s %%', h.n_con_edad, h.n_negativos,
              round(100 * h.mayores30_p5, 1), round(100 * h.mayores30_p1, 1))
FROM analytics.hallazgo_edad h,
     (SELECT count(*) AS n,
             percentile_cont(0.5) WITHIN GROUP (ORDER BY c.mayores30_max_p5)::numeric AS p5,
             percentile_cont(0.5) WITHIN GROUP (ORDER BY c.mayores30_max_p1)::numeric AS p1
      FROM analytics.par p
      JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
      JOIN analytics.contexto c USING (clave_carrera_generica, tipo_institucion)
      WHERE p.representativo AND e.percentil_50_anio_5 < e.percentil_50_anio_1
        AND (c.mayores30_max_p1 - c.mayores30_max_p5) * 100 >= analytics.param('min_cambio_edad_pp')) x
UNION ALL
-- 2. (b) el ejemplo cumple la regla y su referencia es la de SU grupo.
SELECT 'analytics_hallazgos', 'ejemplo_pct_pesos', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'cambia de cuadrante, progresa más en % y crece en pesos ≤ (1 − margen) × mediana de su grupo',
       (SELECT coalesce(format('%s (%s): %s %% y %s pesos frente a %s', clave_carrera_generica, tipo_institucion,
                               round(p50_pct_1_5, 1), round(p50_delta_1_5), round(ref_delta_q50)),
                        'sin ejemplo: la web omite el hallazgo')
        FROM analytics.hallazgo_pct_pesos)
FROM (SELECT count(*) AS n
      FROM analytics.hallazgo_pct_pesos h
      JOIN analytics.posicion po USING (clave_carrera_generica, tipo_institucion)
      JOIN analytics.referencia r ON r.grupo_id = po.grupo_id AND r.metrica = 'p50_delta_1_5'
      WHERE NOT (po.cambia_cuadrante AND po.progresa_mas_pct
                 AND h.p50_delta_1_5 <= (1 - analytics.param('margen_ejemplo_pesos')) * r.q50)
         OR h.ref_delta_q50 <> r.q50) x
UNION ALL
-- 3. (c) el ejemplo cumple el criterio que enuncia la frase: lo citado (q1–q3) ES el IQR del umbral.
SELECT 'analytics_hallazgos', 'ejemplo_dispersion', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'q3 − q1 = iqr ≥ min_iqr_enganoso y n_inst ≥ min_inst_ejemplo',
       (SELECT coalesce(format('%s (%s, %s instituciones): mitad central %s–%s %%', clave_carrera_generica,
                               tipo_institucion, n_inst, round(q1, 1), round(q3, 1)),
                        'sin ejemplo: la web omite el hallazgo')
        FROM analytics.hallazgo_dispersion)
FROM (SELECT count(*) AS n FROM analytics.hallazgo_dispersion
      WHERE clave_carrera_generica IS NOT NULL
        AND (iqr < analytics.param('min_iqr_enganoso') OR abs((q3 - q1) - iqr) > 1e-9
             OR n_inst < analytics.param('min_inst_ejemplo'))) x;
