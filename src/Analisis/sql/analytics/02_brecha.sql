-- src/Analisis/sql/analytics/02_brecha.sql
--
-- A2 (Fase 2): progresión del ingreso entre el 1er y el 5° año por par, en dos familias que
-- NUNCA se combinan en una misma razón:
--   - Media: cada año k junta 3 cohortes (2022-k .. 2024-k) con ingresos 2022-2024.
--   - Percentiles: UNA cohorte por año (año 1 = 2023, año 5 = 2019), ingresos 2024.
-- Media y percentiles describen poblaciones distintas, así que `Media/P50` no existe aquí
-- (y un control lo impide por nombre de columna).
--
-- Es una comparación TRANSVERSAL: el "5° año" son otras personas (otras cohortes) que el
-- "1er año". Nunca se presenta como evolución de las mismas personas.
--
-- Valores sin redondear (numeric); el redondeo es de presentación (A6 / web).
-- Requiere 01_par.sql. Lee modelo.mifuturo_estadistica y modelo.cohorte.

-- Años con anomalía de titulación (auditoría T4, 05_serie_anual_sies.sql: 2020 −20 %, 2021 +42 %).
INSERT INTO analytics.parametro VALUES
    ('anio_caida_titulacion',  2020, 'Año de titulación con caída anómala (pandemia): marca los hitos cuyas cohortes lo incluyen', 'T4, auditoría 05'),
    ('anio_rebote_titulacion', 2021, 'Año de titulación con rebote anómalo (titulaciones atrasadas): ídem',                        'T4, auditoría 05');

-- --------------------------------------------------------------------------
-- Hitos de la media: qué cohortes entran en cada año k (para rotular los hitos en la web)
-- --------------------------------------------------------------------------
CREATE TABLE analytics.hito (
    anio_k            smallint PRIMARY KEY CHECK (anio_k BETWEEN 1 AND 5),
    indicador         text     NOT NULL REFERENCES modelo.cohorte,
    cohorte_desde     smallint NOT NULL,
    cohorte_hasta     smallint NOT NULL,
    incluye_caida     boolean  NOT NULL,   -- sus cohortes incluyen anio_caida_titulacion
    incluye_rebote    boolean  NOT NULL    -- ídem anio_rebote_titulacion
);
COMMENT ON TABLE analytics.hito IS
    'Cohortes de la media de cada año k (modelo.cohorte). Derecho usa cohortes corridas (corrimiento_derecho): su marca puede diferir (ver analytics.par.es_derecho).';

INSERT INTO analytics.hito
SELECT k, c.indicador, c.cohorte_desde, c.cohorte_hasta,
       analytics.param('anio_caida_titulacion')  BETWEEN c.cohorte_desde AND c.cohorte_hasta,
       analytics.param('anio_rebote_titulacion') BETWEEN c.cohorte_desde AND c.cohorte_hasta
FROM (VALUES (1, 'ingreso_medio_1er_anio'), (2, 'ingreso_medio_2do_anio'), (3, 'ingreso_medio_3er_anio'),
             (4, 'ingreso_medio_4to_anio'), (5, 'ingreso_medio_5to_anio')) AS h(k, indicador)
JOIN modelo.cohorte c USING (indicador);

-- --------------------------------------------------------------------------
-- Brecha por par
-- --------------------------------------------------------------------------
CREATE TABLE analytics.brecha (
    clave_carrera_generica  text    NOT NULL,
    tipo_institucion        text    NOT NULL,
    -- Familia MEDIA (3 cohortes por año)
    media_delta_1_5         numeric NOT NULL,   -- pesos: media 5° − media 1°
    media_razon_1_5         numeric NOT NULL,   -- media 5° / media 1°
    media_pct_1_5           numeric NOT NULL,   -- % de crecimiento 1° → 5°
    media_pct_1_2           numeric NOT NULL,   -- hitos: % de un año al siguiente
    media_pct_2_3           numeric NOT NULL,
    media_pct_3_4           numeric NOT NULL,
    media_pct_4_5           numeric NOT NULL,
    -- Familia PERCENTILES (una cohorte por año, ingresos 2024)
    p50_delta_1_5           numeric NOT NULL,   -- egresado típico
    p50_razon_1_5           numeric NOT NULL,
    p50_pct_1_5             numeric NOT NULL,
    p25_pct_1_5             numeric NOT NULL,   -- parte baja
    p75_pct_1_5             numeric NOT NULL,   -- cola alta
    p90_pct_1_5             numeric NOT NULL,
    iqr_1                   numeric NOT NULL,   -- P75 − P25 (dispersión interna principal)
    iqr_5                   numeric NOT NULL,
    iqr_delta_1_5           numeric NOT NULL,   -- > 0: la desigualdad interna se abre en pesos
    iqr_rel_1               numeric NOT NULL,   -- (P75 − P25) / P50: dispersión relativa al nivel
    iqr_rel_5               numeric NOT NULL,
    p90_p50_1               numeric NOT NULL,   -- cola alta relativa al típico
    p90_p50_5               numeric NOT NULL,
    asimetria_1             numeric,            -- (P75 − P50) / (P50 − P25); NULL si P50 = P25
    asimetria_5             numeric,
    PRIMARY KEY (clave_carrera_generica, tipo_institucion),
    FOREIGN KEY (clave_carrera_generica, tipo_institucion) REFERENCES analytics.par
);
COMMENT ON TABLE analytics.brecha IS
    'Comparación transversal 1° vs 5° año (cohortes distintas). Media y percentiles por separado: nunca Media/P50. P10 queda fuera de las métricas: la distribución está truncada en el sueldo mínimo.';

INSERT INTO analytics.brecha
SELECT e.clave_carrera_generica, e.tipo_institucion,
       m5 - m1, m5 / m1, 100 * (m5 / m1 - 1),
       100 * (m2 / m1 - 1), 100 * (m3 / m2 - 1), 100 * (m4 / m3 - 1), 100 * (m5 / m4 - 1),
       p50_5 - p50_1, p50_5 / p50_1, 100 * (p50_5 / p50_1 - 1),
       100 * (p25_5 / p25_1 - 1), 100 * (p75_5 / p75_1 - 1), 100 * (p90_5 / p90_1 - 1),
       p75_1 - p25_1, p75_5 - p25_5, (p75_5 - p25_5) - (p75_1 - p25_1),
       (p75_1 - p25_1) / p50_1, (p75_5 - p25_5) / p50_5,
       p90_1 / p50_1, p90_5 / p50_5,
       (p75_1 - p50_1) / nullif(p50_1 - p25_1, 0),
       (p75_5 - p50_5) / nullif(p50_5 - p25_5, 0)
FROM modelo.mifuturo_estadistica e
JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
CROSS JOIN LATERAL (SELECT
    e.ingreso_medio_1er_anio::numeric AS m1, e.ingreso_medio_2do_anio::numeric AS m2,
    e.ingreso_medio_3er_anio::numeric AS m3, e.ingreso_medio_4to_anio::numeric AS m4,
    e.ingreso_medio_5to_anio::numeric AS m5,
    e.percentil_25_anio_1::numeric AS p25_1, e.percentil_50_anio_1::numeric AS p50_1,
    e.percentil_75_anio_1::numeric AS p75_1, e.percentil_90_anio_1::numeric AS p90_1,
    e.percentil_25_anio_5::numeric AS p25_5, e.percentil_50_anio_5::numeric AS p50_5,
    e.percentil_75_anio_5::numeric AS p75_5, e.percentil_90_anio_5::numeric AS p90_5) v
WHERE p.ingreso_completo;

-- --------------------------------------------------------------------------
-- Controles qa
-- --------------------------------------------------------------------------
INSERT INTO qa.control (control, objeto, estado, metrica, umbral, detalle)
-- 1. Cobertura: un registro por par con ingreso completo.
SELECT 'analytics_brecha', 'filas', CASE WHEN n_b = n_p THEN 'OK' ELSE 'FALLA' END,
       n_b, 'una fila por par con ingreso completo',
       format('%s filas en analytics.brecha; %s pares con ingreso completo', n_b, n_p)
FROM (SELECT (SELECT count(*) FROM analytics.brecha) AS n_b,
             (SELECT count(*) FROM analytics.par WHERE ingreso_completo) AS n_p) x
UNION ALL
-- 2. Media y percentiles nunca en una misma columna (regla B4): por nombre de columna.
SELECT 'analytics_brecha', 'sin_media_sobre_percentil', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'ninguna columna combina media con percentiles',
       coalesce('columnas mixtas: ' || cols, 'ninguna columna mixta')
FROM (SELECT count(*) AS n, string_agg(column_name, ', ') AS cols
      FROM information_schema.columns
      WHERE table_schema = 'analytics' AND table_name = 'brecha'
        AND column_name LIKE '%media%' AND (column_name ~ 'p[0-9]{2}' OR column_name LIKE '%iqr%'
                                            OR column_name LIKE '%asimetria%' OR column_name LIKE '%percentil%')) x
UNION ALL
-- 3. Los hitos componen la brecha: (1+h12)(1+h23)(1+h34)(1+h45) = m5/m1. Detecta años
--    corridos o columnas intercambiadas en los hitos (con años bien puestos la igualdad es exacta
--    salvo redondeo numérico).
SELECT 'analytics_brecha', 'hitos_componen', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, '|∏(1 + hito) − razón 1→5| < 1e-9',
       format('%s pares donde los hitos no reproducen la razón 1°→5°', n)
FROM (SELECT count(*) AS n FROM analytics.brecha
      WHERE abs((1 + media_pct_1_2 / 100) * (1 + media_pct_2_3 / 100) * (1 + media_pct_3_4 / 100)
                * (1 + media_pct_4_5 / 100) - media_razon_1_5) >= 1e-9) x
UNION ALL
-- 4. Coherencia de signos y rangos (percentiles crecientes ya garantizados en raw y procesar.py).
SELECT 'analytics_brecha', 'signos_y_rangos', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'delta > 0 ⇔ razón > 1 ⇔ % > 0; IQR ≥ 0; P90/P50 ≥ 1; asimetría ≥ 0',
       format('%s pares con signos o rangos incoherentes', n)
FROM (SELECT count(*) AS n FROM analytics.brecha
      WHERE (media_delta_1_5 > 0) <> (media_razon_1_5 > 1) OR (media_razon_1_5 > 1) <> (media_pct_1_5 > 0)
         OR (p50_delta_1_5 > 0) <> (p50_razon_1_5 > 1) OR (p50_razon_1_5 > 1) <> (p50_pct_1_5 > 0)
         OR iqr_1 < 0 OR iqr_5 < 0 OR p90_p50_1 < 1 OR p90_p50_5 < 1
         OR coalesce(asimetria_1, 0) < 0 OR coalesce(asimetria_5, 0) < 0) x
UNION ALL
-- 5. Hitos: que modelo.cohorte tenga los 5 años de la media.
SELECT 'analytics_brecha', 'hitos_cohortes', CASE WHEN n = 5 THEN 'OK' ELSE 'FALLA' END,
       n, '5 hitos de la media con sus cohortes',
       (SELECT string_agg(format('año %s: %s-%s%s%s', anio_k, cohorte_desde, cohorte_hasta,
                                 CASE WHEN incluye_caida THEN ' (caída)' ELSE '' END,
                                 CASE WHEN incluye_rebote THEN ' (rebote)' ELSE '' END), '; ' ORDER BY anio_k)
        FROM analytics.hito)
FROM (SELECT count(*) AS n FROM analytics.hito) x;
