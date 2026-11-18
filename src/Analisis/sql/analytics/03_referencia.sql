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
-- Métricas solo de contexto (ficha de carrera: "típico de su grupo"; no entran en la posición):
--   p50_anio_5     P50 del 5° año, ingresos 2024;
--   emp1_nacional  empleabilidad nacional al 1er año (MiFuturo, agregado de la carrera genérica).
-- Mismo método y mismos grupos que las demás, para que la ficha compare todo contra una sola
-- referencia en vez de una distinta por bloque.
--
-- Cuantil ponderado: el menor valor cuyo peso acumulado (orden ascendente) alcanza q × peso
-- total del grupo; sin interpolación, así cada cuantil es el valor de una carrera real. Peso =
-- analytics.par.peso (titulaciones SIES de ambas ventanas). Empates de valor se ordenan por
-- clave para que el resultado sea determinista.
-- Requiere 01_par.sql y 02_brecha.sql.
--
-- Progreso en tres valores (más / típico / menos): la mediana ponderada es siempre el valor de
-- una carrera real, así que con un corte binario esa carrera (y las que quedan a centésimas)
-- "cambiaba de cuadrante" solo por el desempate. Con ±margen_tipico_* de la mediana el progreso
-- es "típico" y no cuenta como cambio. Sensibilidad (profesionales / técnicas que cambian):
-- sin margen 18/1; ±1 pp o $10 mil 11/0; ±2 pp o $20 mil 10/0; ±3 pp o $30 mil 9/0.
-- El eje x (entrada) conserva el corte "> mediana": sus empates no varían entre % y pesos.

INSERT INTO analytics.parametro VALUES
    ('margen_tipico_pp',    2,     'Distancia a la mediana del grupo (puntos porcentuales de crecimiento) dentro de la cual el progreso es "típico"', 'Rediseño de cuadrantes: empates en la mediana (aprobado por el usuario)'),
    ('margen_tipico_pesos', 20000, 'Ídem en pesos de aumento del P50; equivale a ~2 pp sobre una entrada típica de ~$900 mil',                         'Rediseño de cuadrantes: empates en la mediana (aprobado por el usuario)');

-- --------------------------------------------------------------------------
-- Miembros de cada grupo de comparación (vista: la usan la tabla y los controles)
-- --------------------------------------------------------------------------
CREATE VIEW analytics.miembro_referencia AS
WITH valores AS (
    SELECT p.clave_carrera_generica, p.tipo_institucion, p.nivel_carrera, p.area,
           p.peso, p.celda_valida, m.metrica, m.valor
    FROM analytics.par p
    JOIN analytics.brecha b USING (clave_carrera_generica, tipo_institucion)
    JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
    CROSS JOIN LATERAL (VALUES
        ('p50_anio_1',    e.percentil_50_anio_1::numeric),
        ('p50_pct_1_5',   b.p50_pct_1_5),
        ('p50_delta_1_5', b.p50_delta_1_5),
        ('p50_anio_5',    e.percentil_50_anio_5::numeric),
        ('emp1_nacional', e.empleabilidad_1er_anio)
    ) AS m (metrica, valor)
    WHERE p.representativo
)
SELECT 'segmento|' || tipo_institucion || '|' || nivel_carrera AS grupo_id,
       'segmento' AS tipo_grupo, NULL::text AS area, tipo_institucion, nivel_carrera,
       clave_carrera_generica, peso, metrica, valor
FROM valores
UNION ALL
SELECT 'celda|' || area || '|' || tipo_institucion || '|' || nivel_carrera,
       'celda', area, tipo_institucion, nivel_carrera,
       clave_carrera_generica, peso, metrica, valor
FROM valores
WHERE celda_valida;

-- --------------------------------------------------------------------------
-- Referencias: cuartiles ponderados por grupo × métrica
-- --------------------------------------------------------------------------
CREATE TABLE analytics.referencia (
    grupo_id          text    NOT NULL,
    metrica           text    NOT NULL CHECK (metrica IN ('p50_anio_1', 'p50_pct_1_5', 'p50_delta_1_5', 'p50_anio_5', 'emp1_nacional')),
    tipo_grupo        text    NOT NULL CHECK (tipo_grupo IN ('celda', 'segmento')),
    area              text,                       -- área de MiFuturo (ADR-002); NULL en los segmentos
    tipo_institucion  text    NOT NULL,
    nivel_carrera     text    NOT NULL,
    n_pares           integer NOT NULL,
    peso_total        bigint  NOT NULL,
    peso_max_share    numeric NOT NULL,           -- peso de la carrera más grande / total
    q25               numeric NOT NULL,
    q50               numeric NOT NULL,
    q75               numeric NOT NULL,
    PRIMARY KEY (grupo_id, metrica),
    CHECK ((tipo_grupo = 'celda') = (area IS NOT NULL)),
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
SELECT grupo_id, metrica, tipo_grupo, area, tipo_institucion, nivel_carrera,
       count(*), max(peso_total), max(peso)::numeric / max(peso_total),
       min(valor) FILTER (WHERE peso_acum >= 0.25 * peso_total),
       min(valor) FILTER (WHERE peso_acum >= 0.50 * peso_total),
       min(valor) FILTER (WHERE peso_acum >= 0.75 * peso_total)
FROM acum
GROUP BY grupo_id, metrica, tipo_grupo, area, tipo_institucion, nivel_carrera;

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
    dif_pct                 numeric  NOT NULL,   -- crecimiento % − mediana del grupo (pp)
    dif_pesos               numeric  NOT NULL,   -- crecimiento $ − mediana del grupo
    progreso_pct            text     NOT NULL CHECK (progreso_pct   IN ('más', 'típico', 'menos')),
    progreso_pesos          text     NOT NULL CHECK (progreso_pesos IN ('más', 'típico', 'menos')),
    cuadrante_pct           text     NOT NULL,
    cuadrante_pesos         text     NOT NULL,
    cambia_cuadrante        boolean  NOT NULL,   -- el % y los pesos lo ubican en lados opuestos
    PRIMARY KEY (clave_carrera_generica, tipo_institucion),
    FOREIGN KEY (clave_carrera_generica, tipo_institucion) REFERENCES analytics.par,
    -- Un empate ("típico") en cualquiera de las dos medidas nunca es un cambio de cuadrante.
    CHECK (cambia_cuadrante = (progreso_pct <> 'típico' AND progreso_pesos <> 'típico'
                               AND progreso_pct <> progreso_pesos))
);
COMMENT ON TABLE analytics.posicion IS
    'Solo pares representativos. Entrada: corte "> mediana" (la carrera que ES la mediana queda en la mitad baja). Progreso: "típico" a ±margen_tipico_* de la mediana. cambia_cuadrante = el % alto se explica por una base baja (o al revés), fuera del margen en ambas medidas.';

INSERT INTO analytics.posicion
WITH par_ref AS (
    SELECT p.clave_carrera_generica, p.tipo_institucion,
           CASE p.referencia
               WHEN 'celda' THEN 'celda|' || p.area || '|' || p.tipo_institucion || '|' || p.nivel_carrera
               ELSE 'segmento|' || p.tipo_institucion || '|' || p.nivel_carrera
           END AS grupo_id
    FROM analytics.par p
    WHERE p.representativo
),
pos AS (
    SELECT r.clave_carrera_generica, r.tipo_institucion, r.grupo_id, m.metrica,
           CASE WHEN m.valor <= ref.q25 THEN 1 WHEN m.valor <= ref.q50 THEN 2
                WHEN m.valor <= ref.q75 THEN 3 ELSE 4 END AS cuartil,
           m.valor > ref.q50 AS sobre_mediana,
           m.valor - ref.q50 AS dif
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
           max(dif) FILTER (WHERE metrica = 'p50_pct_1_5')   AS d_pct,
           max(dif) FILTER (WHERE metrica = 'p50_delta_1_5') AS d_pesos
    FROM pos
    GROUP BY 1, 2, 3
),
progreso AS (
    SELECT a.*,
           CASE WHEN d_pct   >  analytics.param('margen_tipico_pp')    THEN 'más'
                WHEN d_pct   < -analytics.param('margen_tipico_pp')    THEN 'menos' ELSE 'típico' END AS y_pct,
           CASE WHEN d_pesos >  analytics.param('margen_tipico_pesos') THEN 'más'
                WHEN d_pesos < -analytics.param('margen_tipico_pesos') THEN 'menos' ELSE 'típico' END AS y_pesos
    FROM ancho a
)
SELECT clave_carrera_generica, tipo_institucion, grupo_id, c_x, c_pct, c_delta,
       x_alta, d_pct, d_pesos, y_pct, y_pesos,
       CASE WHEN x_alta THEN 'entrada alta' ELSE 'entrada baja' END || ' · '
           || CASE y_pct WHEN 'típico' THEN 'progreso típico' ELSE 'progresa ' || y_pct END,
       CASE WHEN x_alta THEN 'entrada alta' ELSE 'entrada baja' END || ' · '
           || CASE y_pesos WHEN 'típico' THEN 'progreso típico' ELSE 'progresa ' || y_pesos END,
       y_pct <> 'típico' AND y_pesos <> 'típico' AND y_pct <> y_pesos
FROM progreso;

-- --------------------------------------------------------------------------
-- Conteos del gráfico de cuadrantes: nivel × medida × zona (las cuatro esquinas y la franja
-- "progreso típico", que no pertenece a ninguna esquina). Incluye los ceros: la web dibuja
-- exactamente estas cifras, sin contar puntos.
-- --------------------------------------------------------------------------
CREATE TABLE analytics.cuadrante_conteo (
    nivel_carrera  text    NOT NULL,
    medida         text    NOT NULL CHECK (medida IN ('pct', 'pesos')),
    zona           text    NOT NULL CHECK (zona IN ('entrada baja · progresa más', 'entrada alta · progresa más',
                                                    'entrada baja · progresa menos', 'entrada alta · progresa menos',
                                                    'progreso típico')),
    n              integer NOT NULL CHECK (n >= 0),
    PRIMARY KEY (nivel_carrera, medida, zona)
);

INSERT INTO analytics.cuadrante_conteo
WITH zonas AS (
    SELECT p.nivel_carrera, m.medida,
           CASE WHEN m.progreso = 'típico' THEN 'progreso típico'
                ELSE CASE WHEN po.entrada_alta THEN 'entrada alta' ELSE 'entrada baja' END
                     || ' · progresa ' || m.progreso END AS zona
    FROM analytics.posicion po
    JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
    CROSS JOIN LATERAL (VALUES ('pct', po.progreso_pct), ('pesos', po.progreso_pesos)) AS m (medida, progreso)
),
celdas AS (
    SELECT n.nivel_carrera, m.medida, z.zona
    FROM (SELECT DISTINCT nivel_carrera FROM analytics.par WHERE representativo) n
    CROSS JOIN (VALUES ('pct'), ('pesos')) AS m (medida)
    CROSS JOIN (VALUES ('entrada baja · progresa más'), ('entrada alta · progresa más'),
                       ('entrada baja · progresa menos'), ('entrada alta · progresa menos'),
                       ('progreso típico')) AS z (zona)
)
SELECT c.nivel_carrera, c.medida, c.zona, count(z.zona)
FROM celdas c
LEFT JOIN zonas z USING (nivel_carrera, medida, zona)
GROUP BY 1, 2, 3;

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
            > 0.5 * r.peso_total) x
UNION ALL
-- 6. Progreso y cambio de cuadrante recalculados desde los valores y la referencia (no desde
--    dif_*): la distancia a la mediana, el margen y el "típico" coinciden en cada carrera.
SELECT 'analytics_referencia', 'progreso_por_margen', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'progreso = más / típico / menos según ±margen_tipico_pp y ±margen_tipico_pesos; cambia solo fuera del margen en ambas',
       format('%s carreras con progreso o cambio distinto del recálculo; %s cambian (margen ±%s pp / ±$%s)', n,
              (SELECT count(*) FROM analytics.posicion WHERE cambia_cuadrante),
              analytics.param('margen_tipico_pp'), analytics.param('margen_tipico_pesos'))
FROM (
    WITH r AS (
        SELECT po.*,
               b.p50_pct_1_5 - rp.q50 AS d1, b.p50_delta_1_5 - rd.q50 AS d2
        FROM analytics.posicion po
        JOIN analytics.brecha b USING (clave_carrera_generica, tipo_institucion)
        JOIN analytics.referencia rp ON rp.grupo_id = po.grupo_id AND rp.metrica = 'p50_pct_1_5'
        JOIN analytics.referencia rd ON rd.grupo_id = po.grupo_id AND rd.metrica = 'p50_delta_1_5'
    )
    SELECT count(*) AS n FROM r
    WHERE d1 <> dif_pct OR d2 <> dif_pesos
       OR (abs(d1) <= analytics.param('margen_tipico_pp'))    <> (progreso_pct = 'típico')
       OR (abs(d2) <= analytics.param('margen_tipico_pesos')) <> (progreso_pesos = 'típico')
       OR (progreso_pct <> 'típico' AND (d1 > 0) <> (progreso_pct = 'más'))
       OR (progreso_pesos <> 'típico' AND (d2 > 0) <> (progreso_pesos = 'más'))
       OR cambia_cuadrante <> (abs(d1) > analytics.param('margen_tipico_pp')
                               AND abs(d2) > analytics.param('margen_tipico_pesos')
                               AND sign(d1) <> sign(d2))
) x
UNION ALL
-- 7. Conteos del gráfico: cada nivel × medida suma el total de representativos del nivel, y
--    cada zona coincide con un recuento directo desde posicion.
SELECT 'analytics_referencia', 'cuadrante_conteo', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'Σ zonas = representativos del nivel en cada medida; cada zona = recuento desde posicion',
       format('%s celdas o totales distintos; %s celdas', n, (SELECT count(*) FROM analytics.cuadrante_conteo))
FROM (
    SELECT (SELECT count(*) FROM (
                SELECT c.nivel_carrera, c.medida, sum(c.n) AS s,
                       (SELECT count(*) FROM analytics.par p WHERE p.representativo AND p.nivel_carrera = c.nivel_carrera) AS tot
                FROM analytics.cuadrante_conteo c GROUP BY 1, 2) t WHERE s <> tot)
         + (SELECT count(*) FROM analytics.cuadrante_conteo c
            WHERE c.n <> (SELECT count(*) FROM analytics.posicion po
                          JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
                          WHERE p.nivel_carrera = c.nivel_carrera
                            AND CASE WHEN c.medida = 'pct' THEN po.cuadrante_pct ELSE po.cuadrante_pesos END
                                = CASE WHEN c.zona = 'progreso típico'
                                       THEN CASE WHEN po.entrada_alta THEN 'entrada alta' ELSE 'entrada baja' END || ' · progreso típico'
                                       ELSE c.zona END)) AS n
) x
UNION ALL
-- 8. La ficha compara cada representativo con su grupo en las cinco métricas: si faltara una,
--    la web mostraría una tarjeta sin "típico de su grupo".
SELECT 'analytics_referencia', 'referencia_completa', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'cada par representativo tiene referencia en sus 5 métricas',
       format('%s pares con menos de 5 métricas de referencia', n)
FROM (SELECT count(*) AS n
      FROM analytics.posicion po
      WHERE (SELECT count(*) FROM analytics.referencia r WHERE r.grupo_id = po.grupo_id) <> 5) x;

-- --------------------------------------------------------------------------
-- Posición en su área, para la ficha (18-11-26)
-- --------------------------------------------------------------------------
-- Las franjas de la ficha muestran las mismas carreras que la tabla «Otras carreras de su área»:
-- comparables del mismo nivel y área de MiFuturo, de TODOS los tipos. Como mezclan tipos, no llevan
-- «típica» (sería una mediana entre universidades, IP y CFT); el título dice la posición dentro del
-- área. La típica del grupo estadístico (celda o segmento, la de los cuadrantes) se informa aparte,
-- y cuando no hay celda se dice por qué: pocas carreras o una que domina el peso.
-- Antes las franjas mostraban el grupo estadístico, y con celda inválida eso era todo el tipo × nivel:
-- junto a Ingeniería Comercial aparecían Fonoaudiología y Traducción.
CREATE TABLE analytics.area_ficha (
    clave_carrera_generica  text     NOT NULL,
    tipo_institucion        text     NOT NULL,
    n_area                  integer  NOT NULL,   -- comparables del área × nivel (todos los tipos), incluida ella
    mas_que_p50_1           integer  NOT NULL,   -- de las otras, cuántas tienen un P50 del 1er año MENOR
    motivo                  text     NOT NULL CHECK (motivo IN ('celda', 'pocas', 'dominada')),
    n_celda                 integer  NOT NULL,   -- comparables de su área × tipo × nivel
    domina_clave            text,                -- la de más peso en la celda (si motivo = 'dominada')
    domina_pct              numeric,             -- su % del peso de la celda
    PRIMARY KEY (clave_carrera_generica, tipo_institucion),
    FOREIGN KEY (clave_carrera_generica, tipo_institucion) REFERENCES analytics.par,
    CHECK (mas_que_p50_1 BETWEEN 0 AND n_area - 1),
    CHECK ((motivo = 'dominada') = (domina_clave IS NOT NULL))
);

INSERT INTO analytics.area_ficha
WITH r AS (
    SELECT p.clave_carrera_generica, p.tipo_institucion, p.area, p.nivel_carrera, p.peso, p.celda_valida,
           e.percentil_50_anio_1 AS p50
    FROM analytics.par p
    JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
    WHERE p.representativo
), celda AS (
    SELECT area, tipo_institucion, nivel_carrera, count(*) AS n,
           max(peso)::numeric / sum(peso) AS share_max,
           (array_agg(clave_carrera_generica ORDER BY peso DESC, clave_carrera_generica))[1] AS mayor
    FROM r GROUP BY 1, 2, 3
)
SELECT a.clave_carrera_generica, a.tipo_institucion,
       (SELECT count(*) FROM r b WHERE b.area = a.area AND b.nivel_carrera = a.nivel_carrera),
       (SELECT count(*) FROM r b WHERE b.area = a.area AND b.nivel_carrera = a.nivel_carrera AND b.p50 < a.p50),
       CASE WHEN a.celda_valida THEN 'celda'
            WHEN c.n < analytics.param('min_pares_celda') THEN 'pocas'
            ELSE 'dominada' END,
       c.n,
       CASE WHEN NOT a.celda_valida AND c.n >= analytics.param('min_pares_celda') THEN c.mayor END,
       CASE WHEN NOT a.celda_valida AND c.n >= analytics.param('min_pares_celda') THEN 100 * c.share_max END
FROM r a
JOIN celda c USING (area, tipo_institucion, nivel_carrera);

INSERT INTO qa.control (control, objeto, estado, metrica, umbral, detalle)
-- 9. La posición por otro camino: rank() sobre el área × nivel (rank − 1 = cuántas tienen un P50
--    estrictamente menor, también con empates) y n_area = tamaño de la partición.
SELECT 'analytics_referencia', 'area_ficha_posicion', CASE WHEN n = 0 AND faltan = 0 THEN 'OK' ELSE 'FALLA' END,
       n + faltan, 'mas_que_p50_1 = rank() − 1 y n_area = count() en área (MiFuturo) × nivel; una fila por representativo',
       format('%s filas distintas; %s representativos sin fila', n, faltan)
FROM (SELECT (SELECT count(*) FROM analytics.area_ficha f
              JOIN (SELECT p.clave_carrera_generica, p.tipo_institucion,
                           rank() OVER w - 1 AS mas_que, count(*) OVER (PARTITION BY p.area, p.nivel_carrera) AS n
                    FROM analytics.par p
                    JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
                    WHERE p.representativo
                    WINDOW w AS (PARTITION BY p.area, p.nivel_carrera ORDER BY e.percentil_50_anio_1)) k
                USING (clave_carrera_generica, tipo_institucion)
              WHERE f.mas_que_p50_1 <> k.mas_que OR f.n_area <> k.n) AS n,
             (SELECT count(*) FROM analytics.par p WHERE p.representativo
                AND NOT EXISTS (SELECT 1 FROM analytics.area_ficha f
                                WHERE f.clave_carrera_generica = p.clave_carrera_generica
                                  AND f.tipo_institucion = p.tipo_institucion)) AS faltan) x
UNION ALL
-- 10. El motivo que dice la ficha es el de la regla de celda (01_par.sql): 'celda' ⇔ celda válida;
--     'pocas' ⇔ < min_pares_celda; 'dominada' ⇔ suficientes pero la mayor pesa > max_peso_dominante.
SELECT 'analytics_referencia', 'area_ficha_motivo', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'motivo coherente con celda_valida, min_pares_celda y max_peso_dominante',
       (SELECT string_agg(format('%s: %s', motivo, k), ', ' ORDER BY motivo)
        FROM (SELECT motivo, count(*) AS k FROM analytics.area_ficha GROUP BY 1) t)
FROM (SELECT count(*) AS n
      FROM analytics.area_ficha f
      JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
      WHERE (f.motivo = 'celda') <> p.celda_valida
         OR (f.motivo = 'pocas') <> (NOT p.celda_valida AND f.n_celda < analytics.param('min_pares_celda'))
         OR (f.motivo = 'dominada') <> (NOT p.celda_valida AND f.n_celda >= analytics.param('min_pares_celda')
                                         AND f.domina_pct > 100 * analytics.param('max_peso_dominante'))) x;
