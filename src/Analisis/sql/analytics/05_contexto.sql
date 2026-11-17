-- src/Analisis/sql/analytics/05_contexto.sql
--
-- A5 (Fase 2): contexto descriptivo del SIES por par y control de estabilidad de la cohorte.
-- Es CONTEXTO, no explicación causal: describe quiénes se titulan, no por qué ganan lo que ganan.
--
--   1. analytics.contexto (un registro por par; titulaciones de TODAS las instituciones del tipo):
--      - Choque de oferta joven: titulados < 30 años (tramos 15-19, 20-24, 25-29) en las cohortes
--        de la media del 5° año (2017-2019) vs del 1er año (2021-2023). SIN licenciaturas no
--        conducentes (una misma persona se contaría dos veces: T0/T4); los planes de continuidad
--        se marcan con su proporción, no se excluyen (decisión de la Fase 1).
--      - Quiénes (población de MiFuturo = todas las titulaciones, T4): % mujeres y % fuera del corte
--        de 30 años como RANGO, porque el tramo SIES 30-34 mezcla 30 (dentro) con 31-34 (fuera):
--        mínimo = (35-39 + 40 y más) / con edad; máximo = mínimo + 30-34 / con edad.
--      - Edad de las cohortes de los percentiles (2023 y 2019): mismo rango, para probar la
--        hipótesis de A2 (P50 1°→5° negativo en técnicas de IP/CFT: ¿titulados que ya trabajaban?).
--   2. analytics.estabilidad (D5): ¿la cohorte de los percentiles del 1er año (2023) fue atípica en
--      su serie de empleabilidad del 1er año (cohortes 2019-2022)? Se marca, no se excluye.
--
-- Ventanas desde modelo.cohorte (Derecho +1). La duración formal y real no se copia aquí: está
-- en modelo.mifuturo_estadistica y la exportación (A6) la toma de ahí.
-- Requiere 01_par.sql.

INSERT INTO analytics.parametro VALUES
    ('min_desvio_atipico_pp', 5, 'Desvío mínimo (puntos) de la empleabilidad de la cohorte de los percentiles respecto de sus cohortes previas para marcarla atípica', 'A5 (D5)'),
    ('min_z_atipico',         2, 'Desvío mínimo en desviaciones estándar de las cohortes previas para marcarla atípica (se exigen ambos umbrales)',                    'A5 (D5)');

-- --------------------------------------------------------------------------
-- 1. Contexto SIES por par
-- --------------------------------------------------------------------------
CREATE TABLE analytics.contexto (
    clave_carrera_generica   text    NOT NULL,
    tipo_institucion         text    NOT NULL,
    -- todas las titulaciones (población de MiFuturo)
    tit_ventana_1            integer NOT NULL,   -- cohortes de la media del 1er año
    tit_ventana_5            integer NOT NULL,   -- cohortes de la media del 5° año
    pct_mujeres_1            numeric,            -- proporciones 0-1
    pct_mujeres_5            numeric,
    fuera30_min_1            numeric,            -- % fuera del corte de 30 años (rango)
    fuera30_max_1            numeric,
    fuera30_min_5            numeric,
    fuera30_max_5            numeric,
    pct_plan_continuidad_1   numeric,            -- titulaciones de planes de continuidad
    -- oferta joven (< 30), sin licenciaturas no conducentes
    jovenes_5                integer NOT NULL,
    jovenes_1                integer NOT NULL,
    var_oferta_joven         numeric,            -- jovenes_1 / jovenes_5 − 1; NULL si jovenes_5 = 0
    -- edad de las cohortes de los percentiles (todas las titulaciones)
    mayores30_min_p1         numeric,            -- cohorte de los percentiles del 1er año (2023)
    mayores30_max_p1         numeric,
    mayores30_min_p5         numeric,            -- cohorte de los percentiles del 5° año (2019)
    mayores30_max_p5         numeric,
    PRIMARY KEY (clave_carrera_generica, tipo_institucion),
    FOREIGN KEY (clave_carrera_generica, tipo_institucion) REFERENCES analytics.par,
    CHECK (fuera30_min_1 <= fuera30_max_1 AND fuera30_min_5 <= fuera30_max_5),
    CHECK (mayores30_min_p1 <= mayores30_max_p1 AND mayores30_min_p5 <= mayores30_max_p5)
);
COMMENT ON TABLE analytics.contexto IS
    'Contexto SIES descriptivo por par. Rangos "fuera30" y "mayores30": el tramo 30-34 del SIES mezcla el corte de 30 años. Denominador de edad = titulaciones con edad informada.';

INSERT INTO analytics.contexto
WITH c AS (
    SELECT max(cohorte_desde) FILTER (WHERE indicador = 'ingreso_medio_1er_anio') AS d1,
           max(cohorte_hasta) FILTER (WHERE indicador = 'ingreso_medio_1er_anio') AS h1,
           max(cohorte_desde) FILTER (WHERE indicador = 'ingreso_medio_5to_anio') AS d5,
           max(cohorte_hasta) FILTER (WHERE indicador = 'ingreso_medio_5to_anio') AS h5,
           max(cohorte_desde) FILTER (WHERE indicador = 'percentiles_anio_1')     AS p1,
           max(cohorte_desde) FILTER (WHERE indicador = 'percentiles_anio_5')     AS p5
    FROM modelo.cohorte
),
t AS (  -- cada fila SIES con la ventana a la que pertenece (Derecho +1)
    SELECT i.tipo_institucion, x.*,
           x.anio - (x.clave_carrera_generica = 'DERECHO')::int AS anio_ref,
           x.carrera_clasificacion_nivel_1 = 'Licenciatura No Conducente a Título' AS es_lnc,
           x.titulados_15_19 + x.titulados_20_24 + x.titulados_25_29 AS jovenes,
           x.titulados_35_39 + x.titulados_mayores_40 AS mayores35,
           x.total_titulaciones - x.titulados_edad_sin_info AS con_edad
    FROM modelo.titulacion x
    JOIN modelo.institucion i USING (codigo_institucion)
),
agg AS (
    SELECT t.tipo_institucion, t.clave_carrera_generica,
           -- ventana 1er año
           sum(total_titulaciones)  FILTER (WHERE anio_ref BETWEEN c.d1 AND c.h1) AS tit_1,
           sum(titulaciones_mujeres) FILTER (WHERE anio_ref BETWEEN c.d1 AND c.h1) AS muj_1,
           sum(con_edad)            FILTER (WHERE anio_ref BETWEEN c.d1 AND c.h1) AS edad_1,
           sum(mayores35)           FILTER (WHERE anio_ref BETWEEN c.d1 AND c.h1) AS m35_1,
           sum(titulados_30_34)     FILTER (WHERE anio_ref BETWEEN c.d1 AND c.h1) AS m30_1,
           sum(total_titulaciones)  FILTER (WHERE anio_ref BETWEEN c.d1 AND c.h1
                                              AND tipo_plan = 'Plan Regular de Continuidad') AS cont_1,
           sum(jovenes)             FILTER (WHERE anio_ref BETWEEN c.d1 AND c.h1 AND NOT es_lnc) AS jov_1,
           -- ventana 5° año
           sum(total_titulaciones)  FILTER (WHERE anio_ref BETWEEN c.d5 AND c.h5) AS tit_5,
           sum(titulaciones_mujeres) FILTER (WHERE anio_ref BETWEEN c.d5 AND c.h5) AS muj_5,
           sum(con_edad)            FILTER (WHERE anio_ref BETWEEN c.d5 AND c.h5) AS edad_5,
           sum(mayores35)           FILTER (WHERE anio_ref BETWEEN c.d5 AND c.h5) AS m35_5,
           sum(titulados_30_34)     FILTER (WHERE anio_ref BETWEEN c.d5 AND c.h5) AS m30_5,
           sum(jovenes)             FILTER (WHERE anio_ref BETWEEN c.d5 AND c.h5 AND NOT es_lnc) AS jov_5,
           -- cohortes de los percentiles
           sum(con_edad)            FILTER (WHERE anio_ref = c.p1) AS edad_p1,
           sum(mayores35)           FILTER (WHERE anio_ref = c.p1) AS m35_p1,
           sum(titulados_30_34)     FILTER (WHERE anio_ref = c.p1) AS m30_p1,
           sum(con_edad)            FILTER (WHERE anio_ref = c.p5) AS edad_p5,
           sum(mayores35)           FILTER (WHERE anio_ref = c.p5) AS m35_p5,
           sum(titulados_30_34)     FILTER (WHERE anio_ref = c.p5) AS m30_p5
    FROM t CROSS JOIN c
    GROUP BY 1, 2
)
SELECT p.clave_carrera_generica, p.tipo_institucion,
       coalesce(a.tit_1, 0), coalesce(a.tit_5, 0),
       a.muj_1::numeric / nullif(a.tit_1, 0), a.muj_5::numeric / nullif(a.tit_5, 0),
       a.m35_1::numeric / nullif(a.edad_1, 0), (a.m35_1 + a.m30_1)::numeric / nullif(a.edad_1, 0),
       a.m35_5::numeric / nullif(a.edad_5, 0), (a.m35_5 + a.m30_5)::numeric / nullif(a.edad_5, 0),
       a.cont_1::numeric / nullif(a.tit_1, 0),
       coalesce(a.jov_5, 0), coalesce(a.jov_1, 0),
       a.jov_1::numeric / nullif(a.jov_5, 0) - 1,
       a.m35_p1::numeric / nullif(a.edad_p1, 0), (a.m35_p1 + a.m30_p1)::numeric / nullif(a.edad_p1, 0),
       a.m35_p5::numeric / nullif(a.edad_p5, 0), (a.m35_p5 + a.m30_p5)::numeric / nullif(a.edad_p5, 0)
FROM analytics.par p
LEFT JOIN agg a USING (tipo_institucion, clave_carrera_generica);

-- --------------------------------------------------------------------------
-- 2. Estabilidad de la cohorte de los percentiles del 1er año (D5)
-- --------------------------------------------------------------------------
CREATE TABLE analytics.estabilidad (
    clave_carrera_generica  text     NOT NULL,
    tipo_institucion        text     NOT NULL,
    cohorte                 smallint NOT NULL,   -- cohorte de los percentiles del 1er año
    empleabilidad_cohorte   numeric  NOT NULL,
    n_previas               integer  NOT NULL,   -- cohortes previas de la serie con dato
    media_previas           numeric  NOT NULL,
    sd_previas              numeric,             -- NULL con una sola previa
    desvio                  numeric  NOT NULL,   -- puntos: cohorte − media de las previas
    atipica                 boolean  NOT NULL,
    PRIMARY KEY (clave_carrera_generica, tipo_institucion),
    FOREIGN KEY (clave_carrera_generica, tipo_institucion) REFERENCES analytics.par
);
COMMENT ON TABLE analytics.estabilidad IS
    'D5: la serie de empleabilidad del 1er año solo sirve como control de estabilidad. Atípica = |desvío| >= min_desvio_atipico_pp Y >= min_z_atipico desviaciones estándar de las cohortes previas. Se marca; no se excluye.';

INSERT INTO analytics.estabilidad
WITH c AS (SELECT cohorte_desde AS p1 FROM modelo.cohorte WHERE indicador = 'percentiles_anio_1'),
s AS (
    SELECT s.clave_carrera_generica, s.tipo_institucion, c.p1,
           max(s.valor) FILTER (WHERE s.cohorte = c.p1) AS v,
           count(*)     FILTER (WHERE s.cohorte < c.p1) AS n,
           avg(s.valor) FILTER (WHERE s.cohorte < c.p1) AS m,
           stddev_samp(s.valor) FILTER (WHERE s.cohorte < c.p1) AS sd
    FROM modelo.mifuturo_serie s CROSS JOIN c
    WHERE s.indicador = 'serie_empleabilidad_1er_anio'
    GROUP BY 1, 2, 3
)
SELECT clave_carrera_generica, tipo_institucion, p1, v, n, m, sd, v - m,
       abs(v - m) >= analytics.param('min_desvio_atipico_pp')
       AND abs(v - m) >= analytics.param('min_z_atipico') * coalesce(sd, 0)
FROM s
WHERE v IS NOT NULL AND n >= 3;   -- con menos de 3 previas no hay base para hablar de atípica

-- --------------------------------------------------------------------------
-- Controles qa
-- --------------------------------------------------------------------------
INSERT INTO qa.control (control, objeto, estado, metrica, umbral, detalle)
-- 1. Un registro de contexto por par.
SELECT 'analytics_contexto', 'filas', CASE WHEN n_c = n_p THEN 'OK' ELSE 'FALLA' END,
       n_c, 'un registro de contexto por par',
       format('%s en analytics.contexto; %s pares', n_c, n_p)
FROM (SELECT (SELECT count(*) FROM analytics.contexto) AS n_c, (SELECT count(*) FROM analytics.par) AS n_p) x
UNION ALL
-- 2. Dos caminos, un resultado: las titulaciones por ventana de contexto (año corrido en `t`)
--    deben ser las mismas que calculó analytics.par (filtro de años con BETWEEN corrido).
SELECT 'analytics_contexto', 'titulaciones_vs_par', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'tit_ventana_1/5 de contexto = las de analytics.par',
       format('%s pares con titulaciones distintas entre contexto y par', n)
FROM (SELECT count(*) AS n FROM analytics.contexto c JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
      WHERE c.tit_ventana_1 <> p.tit_ventana_1 OR c.tit_ventana_5 <> p.tit_ventana_5) x
UNION ALL
-- 3. Proporciones en [0, 1].
SELECT 'analytics_contexto', 'proporciones', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'toda proporción de contexto en [0; 1]',
       format('%s pares con alguna proporción fuera de rango', n)
FROM (SELECT count(*) AS n FROM analytics.contexto
      WHERE greatest(pct_mujeres_1, pct_mujeres_5, fuera30_max_1, fuera30_max_5, pct_plan_continuidad_1,
                     mayores30_max_p1, mayores30_max_p5) > 1
         OR least(pct_mujeres_1, pct_mujeres_5, fuera30_min_1, fuera30_min_5, pct_plan_continuidad_1,
                  mayores30_min_p1, mayores30_min_p5) < 0) x
UNION ALL
-- 4. Marca de atípica exactamente según los dos umbrales.
SELECT 'analytics_contexto', 'estabilidad_atipica', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'atípica ⇔ |desvío| ≥ min_desvio_atipico_pp y ≥ min_z_atipico × sd',
       format('%s filas incoherentes; %s de %s cohortes atípicas', n,
              (SELECT count(*) FROM analytics.estabilidad WHERE atipica),
              (SELECT count(*) FROM analytics.estabilidad))
FROM (SELECT count(*) AS n FROM analytics.estabilidad
      WHERE atipica <> (abs(desvio) >= analytics.param('min_desvio_atipico_pp')
                        AND abs(desvio) >= analytics.param('min_z_atipico') * coalesce(sd_previas, 0))) x;
