-- src/Analisis/sql/analytics/03_referencia.sql
--
-- A3 (Fase 2): referencias ponderadas (cuartiles y mediana) por grupo de comparación, y la
-- posición de cada par representativo en su referencia: cuartil y cuadrante.
--
-- Grupos de comparación (D2, T5):
--   - celda    = área cine13 × tipo × nivel válida (>= min_pares_celda pares representativos);
--   - segmento = tipo × nivel, con TODOS sus pares representativos (también los de celda válida).
-- Cada par representativo se compara con UNA referencia: su celda si es válida, si no su
-- segmento (analytics.par.referencia). Los no representativos no tienen posición ni cuadrante.
--
-- Métricas con referencia (decisión de cuadrantes aprobada):
--   p50_anio_1     eje x: con cuánto se entra (P50 del 1er año, ingresos 2024);
--   p50_pct_1_5    eje y: crecimiento del P50 1°→5° en %;
--   p50_delta_1_5  eje y alternativo (sensibilidad): crecimiento en pesos.
--
-- Cuantil ponderado: el menor valor cuyo peso acumulado (orden ascendente) alcanza q × peso
-- total del grupo; sin interpolación, así cada cuantil es el valor de una carrera real. Peso =
-- analytics.par.peso (titulaciones SIES de ambas ventanas). Empates de valor se ordenan por
-- clave para que el resultado sea determinista.
-- Requiere 01_par.sql y 02_brecha.sql.

-- --------------------------------------------------------------------------
-- Miembros de cada grupo de comparación (vista: la usan la tabla y los controles)
-- --------------------------------------------------------------------------
CREATE VIEW analytics.miembro_referencia AS
WITH valores AS (
    SELECT p.clave_carrera_generica, p.tipo_institucion, p.nivel_carrera, p.area_cine13,
           p.peso, p.celda_valida, m.metrica, m.valor
    FROM analytics.par p
    JOIN analytics.brecha b USING (clave_carrera_generica, tipo_institucion)
    JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
    CROSS JOIN LATERAL (VALUES
        ('p50_anio_1',    e.percentil_50_anio_1::numeric),
        ('p50_pct_1_5',   b.p50_pct_1_5),
        ('p50_delta_1_5', b.p50_delta_1_5)
    ) AS m (metrica, valor)
    WHERE p.representativo
)
SELECT 'segmento|' || tipo_institucion || '|' || nivel_carrera AS grupo_id,
       'segmento' AS tipo_grupo, NULL::text AS area_cine13, tipo_institucion, nivel_carrera,
       clave_carrera_generica, peso, metrica, valor
FROM valores
UNION ALL
SELECT 'celda|' || area_cine13 || '|' || tipo_institucion || '|' || nivel_carrera,
       'celda', area_cine13, tipo_institucion, nivel_carrera,
       clave_carrera_generica, peso, metrica, valor
FROM valores
WHERE celda_valida;

-- --------------------------------------------------------------------------
-- Referencias: cuartiles ponderados por grupo × métrica
-- --------------------------------------------------------------------------
CREATE TABLE analytics.referencia (
    grupo_id          text    NOT NULL,
    metrica           text    NOT NULL CHECK (metrica IN ('p50_anio_1', 'p50_pct_1_5', 'p50_delta_1_5')),
    tipo_grupo        text    NOT NULL CHECK (tipo_grupo IN ('celda', 'segmento')),
    area_cine13       text,                       -- NULL en los segmentos
    tipo_institucion  text    NOT NULL,
    nivel_carrera     text    NOT NULL,
    n_pares           integer NOT NULL,
    peso_total        bigint  NOT NULL,
    peso_max_share    numeric NOT NULL,           -- peso de la carrera más grande / total
    q25               numeric NOT NULL,
    q50               numeric NOT NULL,
    q75               numeric NOT NULL,
    PRIMARY KEY (grupo_id, metrica),
    CHECK ((tipo_grupo = 'celda') = (area_cine13 IS NOT NULL)),
    CHECK (q25 <= q50 AND q50 <= q75)
);
COMMENT ON COLUMN analytics.referencia.peso_max_share IS
    'Si es alto, la referencia está dominada por una sola carrera (su mediana ponderada tiende a ser el valor de esa carrera).';

INSERT INTO analytics.referencia
WITH acum AS (
    SELECT m.*,
           sum(peso) OVER (PARTITION BY grupo_id, metrica
                           ORDER BY valor, clave_carrera_generica
                           ROWS UNBOUNDED PRECEDING) AS peso_acum,
           sum(peso) OVER (PARTITION BY grupo_id, metrica) AS peso_total
    FROM analytics.miembro_referencia m
)
SELECT grupo_id, metrica, tipo_grupo, area_cine13, tipo_institucion, nivel_carrera,
       count(*), max(peso_total), max(peso)::numeric / max(peso_total),
       min(valor) FILTER (WHERE peso_acum >= 0.25 * peso_total),
       min(valor) FILTER (WHERE peso_acum >= 0.50 * peso_total),
       min(valor) FILTER (WHERE peso_acum >= 0.75 * peso_total)
FROM acum
GROUP BY grupo_id, metrica, tipo_grupo, area_cine13, tipo_institucion, nivel_carrera;

-- --------------------------------------------------------------------------
-- Posición de cada par representativo en su referencia
-- --------------------------------------------------------------------------
CREATE TABLE analytics.posicion (
    clave_carrera_generica  text     NOT NULL,
    tipo_institucion        text     NOT NULL,
    grupo_id                text     NOT NULL,   -- su referencia (celda o segmento)
    cuartil_p50_anio_1      smallint NOT NULL CHECK (cuartil_p50_anio_1 BETWEEN 1 AND 4),
    cuartil_p50_pct_1_5     smallint NOT NULL CHECK (cuartil_p50_pct_1_5 BETWEEN 1 AND 4),
    cuartil_p50_delta_1_5   smallint NOT NULL CHECK (cuartil_p50_delta_1_5 BETWEEN 1 AND 4),
    entrada_alta            boolean  NOT NULL,   -- P50 año 1 > mediana ponderada de la referencia
    progresa_mas_pct        boolean  NOT NULL,   -- crecimiento % > mediana
    progresa_mas_pesos      boolean  NOT NULL,   -- crecimiento $ > mediana
    cuadrante_pct           text     NOT NULL,
    cuadrante_pesos         text     NOT NULL,
    cambia_cuadrante        boolean  NOT NULL,   -- el % y los pesos lo ubican distinto
    PRIMARY KEY (clave_carrera_generica, tipo_institucion),
    FOREIGN KEY (clave_carrera_generica, tipo_institucion) REFERENCES analytics.par
);
COMMENT ON TABLE analytics.posicion IS
    'Solo pares representativos. Corte "> mediana": la carrera que ES la mediana queda en la mitad baja. cambia_cuadrante = el % alto se explica por una base baja (o al revés).';

INSERT INTO analytics.posicion
WITH par_ref AS (
    SELECT p.clave_carrera_generica, p.tipo_institucion,
           CASE p.referencia
               WHEN 'celda' THEN 'celda|' || p.area_cine13 || '|' || p.tipo_institucion || '|' || p.nivel_carrera
               ELSE 'segmento|' || p.tipo_institucion || '|' || p.nivel_carrera
           END AS grupo_id
    FROM analytics.par p
    WHERE p.representativo
),
pos AS (
    SELECT r.clave_carrera_generica, r.tipo_institucion, r.grupo_id, m.metrica,
           CASE WHEN m.valor <= ref.q25 THEN 1 WHEN m.valor <= ref.q50 THEN 2
                WHEN m.valor <= ref.q75 THEN 3 ELSE 4 END AS cuartil,
           m.valor > ref.q50 AS sobre_mediana
    FROM par_ref r
    JOIN analytics.miembro_referencia m
      ON m.grupo_id = r.grupo_id
     AND m.clave_carrera_generica = r.clave_carrera_generica
     AND m.tipo_institucion = r.tipo_institucion
    JOIN analytics.referencia ref ON ref.grupo_id = m.grupo_id AND ref.metrica = m.metrica
),
ancho AS (
    SELECT clave_carrera_generica, tipo_institucion, grupo_id,
           max(cuartil) FILTER (WHERE metrica = 'p50_anio_1')    AS c_x,
           max(cuartil) FILTER (WHERE metrica = 'p50_pct_1_5')   AS c_pct,
           max(cuartil) FILTER (WHERE metrica = 'p50_delta_1_5') AS c_delta,
           bool_or(sobre_mediana) FILTER (WHERE metrica = 'p50_anio_1')    AS x_alta,
           bool_or(sobre_mediana) FILTER (WHERE metrica = 'p50_pct_1_5')   AS y_pct,
           bool_or(sobre_mediana) FILTER (WHERE metrica = 'p50_delta_1_5') AS y_pesos
    FROM pos
    GROUP BY 1, 2, 3
)
SELECT clave_carrera_generica, tipo_institucion, grupo_id, c_x, c_pct, c_delta,
       x_alta, y_pct, y_pesos,
       CASE WHEN x_alta THEN 'entrada alta' ELSE 'entrada baja' END || ' · '
           || CASE WHEN y_pct THEN 'progresa más' ELSE 'progresa menos' END,
       CASE WHEN x_alta THEN 'entrada alta' ELSE 'entrada baja' END || ' · '
           || CASE WHEN y_pesos THEN 'progresa más' ELSE 'progresa menos' END,
       y_pct <> y_pesos
FROM ancho;

-- --------------------------------------------------------------------------
-- Controles qa
-- --------------------------------------------------------------------------
INSERT INTO qa.control (control, objeto, estado, metrica, umbral, detalle)
-- 1. Posición para todos los representativos y para nadie más.
SELECT 'analytics_referencia', 'posicion_filas', CASE WHEN n_pos = n_rep THEN 'OK' ELSE 'FALLA' END,
       n_pos, 'una posición por par representativo (los no representativos no tienen cuadrante)',
       format('%s posiciones; %s pares representativos', n_pos, n_rep)
FROM (SELECT (SELECT count(*) FROM analytics.posicion) AS n_pos,
             (SELECT count(*) FROM analytics.par WHERE representativo) AS n_rep) x
UNION ALL
-- 2. El peso de cada segmento = suma de pesos de sus pares representativos (calculado desde par).
SELECT 'analytics_referencia', 'peso_segmento', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'peso_total del segmento = Σ peso de sus representativos, en cada métrica',
       format('%s segmento × métrica con peso distinto', n)
FROM (SELECT count(*) AS n
      FROM analytics.referencia r
      JOIN (SELECT tipo_institucion, nivel_carrera, sum(peso) AS peso
            FROM analytics.par WHERE representativo GROUP BY 1, 2) s USING (tipo_institucion, nivel_carrera)
      WHERE r.tipo_grupo = 'segmento' AND r.peso_total <> s.peso) x
UNION ALL
-- 3. Cuantiles por un cálculo independiente (autounión, sin funciones de ventana):
--    q-cuantil = menor valor v con Σ peso(x <= v) >= q × peso total.
SELECT 'analytics_referencia', 'cuantil_directo', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'q25/q50/q75 = recálculo por autounión en todos los grupos y métricas',
       format('%s cuantiles distintos de %s', n, (SELECT 3 * count(*) FROM analytics.referencia))
FROM (
    WITH cand AS (
        SELECT a.grupo_id, a.metrica, a.valor,
               (SELECT sum(b.peso) FROM analytics.miembro_referencia b
                WHERE b.grupo_id = a.grupo_id AND b.metrica = a.metrica AND b.valor <= a.valor) AS peso_hasta
        FROM analytics.miembro_referencia a
    ),
    directo AS (
        SELECT c.grupo_id, c.metrica,
               min(c.valor) FILTER (WHERE c.peso_hasta >= 0.25 * r.peso_total) AS q25,
               min(c.valor) FILTER (WHERE c.peso_hasta >= 0.50 * r.peso_total) AS q50,
               min(c.valor) FILTER (WHERE c.peso_hasta >= 0.75 * r.peso_total) AS q75
        FROM cand c JOIN analytics.referencia r USING (grupo_id, metrica)
        GROUP BY 1, 2
    )
    SELECT count(*) FILTER (WHERE d.q25 <> r.q25) + count(*) FILTER (WHERE d.q50 <> r.q50)
         + count(*) FILTER (WHERE d.q75 <> r.q75) AS n
    FROM directo d JOIN analytics.referencia r USING (grupo_id, metrica)
) x
UNION ALL
-- 4. Los segmentos no tienen a dónde derivar (son la referencia de último recurso): si una
--    carrera domina el peso de un segmento, la mediana del segmento es esa carrera. Falla el
--    build para obligar a revisar, en vez de publicar una referencia engañosa.
SELECT 'analytics_referencia', 'segmento_no_dominado', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'ninguna carrera con > max_peso_dominante del peso de su segmento',
       format('%s segmentos dominados; máximo %s %% del peso', n, round(100 * mx, 1))
FROM (SELECT count(*) FILTER (WHERE peso_max_share > analytics.param('max_peso_dominante')) AS n,
             max(peso_max_share) AS mx
      FROM analytics.referencia WHERE tipo_grupo = 'segmento' AND metrica = 'p50_anio_1') x
UNION ALL
-- 5. La mediana divide: en cada grupo, el peso estrictamente sobre la mediana es <= 50 %.
SELECT 'analytics_referencia', 'mediana_divide', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'Σ peso(valor > q50) ≤ 0,5 × peso total en cada grupo × métrica',
       format('%s grupos donde más de la mitad del peso queda sobre la mediana', n)
FROM (SELECT count(*) AS n
      FROM analytics.referencia r
      WHERE (SELECT coalesce(sum(m.peso), 0) FROM analytics.miembro_referencia m
             WHERE m.grupo_id = r.grupo_id AND m.metrica = r.metrica AND m.valor > r.q50)
            > 0.5 * r.peso_total) x;
