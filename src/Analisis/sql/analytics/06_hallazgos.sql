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
--   (b) entre las carreras que cambian de cuadrante (fuera del margen de empate en % y en pesos,
--       ver 03_referencia.sql) y progresan más en %, la de mayor %, siempre
--       que su aumento en pesos quede al menos margen_ejemplo_pesos bajo la mediana de su grupo;
--   (c) entre las de promedio engañoso con >= min_inst_ejemplo instituciones, la de mayor IQR.
-- Empates: por tipo y clave, el mismo orden del JSON. Requiere 01 a 05.

-- Antes eran números escritos en app.js (0.8 y 20): ahora viven con el resto de los umbrales.
INSERT INTO analytics.parametro VALUES
    ('margen_ejemplo_pesos', 0.20, 'Hallazgo (b): el ejemplo crece en pesos al menos esta proporción menos que la mediana de su grupo (sin margen podría ser la propia mediana)', 'W3; movido de app.js a SQL en la revisión del 16-11-26'),
    ('min_inst_ejemplo',     20,   'Hallazgo (c): instituciones mínimas para que una carrera sirva de ejemplo (con pocas sería anecdótico)',                                  'W3; ídem');

-- --------------------------------------------------------------------------
-- (a) Al quinto año no siempre se gana más — POR NIVEL
-- --------------------------------------------------------------------------
-- Una fila por nivel: técnicas y profesionales nunca se mezclan en una mediana (regla de
-- segmentación). La primera versión daba una sola mediana de las 210 comparables (+29,3 %), que
-- quedaba a mitad de camino entre los dos niveles y no describía a ninguno.
CREATE TABLE analytics.hallazgo_edad (
    nivel_carrera    text    PRIMARY KEY,
    n_comparables    integer NOT NULL,
    mediana_p50_pct  numeric NOT NULL,   -- mediana SIMPLE del crecimiento del P50 1°→5°, dentro del nivel
    -- Comparables del nivel cuyo P50 del 5° año es menor que el del 1° por MÁS que margen_tipico_pp
    -- (19-11-26, aprobado por el usuario): el mismo empate de ±2 pp de los cuadrantes; antes contaba
    -- caídas de −0,3 % como «ganan menos».
    n_negativos      integer NOT NULL,
    claves_bajan     text[]  NOT NULL,   -- 'CLAVE|tipo' de esas carreras: el peine las destaca sin volver a filtrar
    n_con_edad       integer NOT NULL,   -- de ellas, con la marca de composición por edad
    n_base_edad      integer NOT NULL,   -- carreras sobre las que se calculan las dos medianas de edad
    mayores30_p5     numeric,            -- mediana de la cota alta de 30+ (0-1), cohorte del 5° año
    mayores30_p1     numeric,            -- ídem, cohorte del 1er año
    n_marca_edad     integer NOT NULL,   -- comparables del nivel con marca de edad (suban o bajen): el violeta del peine
    -- La frase dice "en N de ellas… pasan de X a Y": X e Y deben describir a esas N.
    CHECK (n_base_edad = n_con_edad),
    CHECK (cardinality(claves_bajan) = n_negativos),
    CHECK (n_con_edad <= n_negativos AND n_negativos <= n_comparables),
    CHECK ((n_con_edad = 0) = (mayores30_p5 IS NULL)),
    CHECK (n_con_edad <= n_marca_edad AND n_marca_edad <= n_comparables)
);

INSERT INTO analytics.hallazgo_edad
WITH comp AS (
    SELECT p.nivel_carrera, p.clave_carrera_generica || '|' || p.tipo_institucion AS clave,
           b.p50_pct_1_5, c.composicion_edad, c.mayores30_max_p5, c.mayores30_max_p1
    FROM analytics.par p
    JOIN analytics.brecha b   USING (clave_carrera_generica, tipo_institucion)
    JOIN analytics.contexto c USING (clave_carrera_generica, tipo_institucion)
    WHERE p.representativo
)
SELECT nivel_carrera,
       count(*),
       (percentile_cont(0.5) WITHIN GROUP (ORDER BY p50_pct_1_5))::numeric,
       count(*) FILTER (WHERE p50_pct_1_5 < -analytics.param('margen_tipico_pp')),
       coalesce(array_agg(clave ORDER BY clave) FILTER (WHERE p50_pct_1_5 < -analytics.param('margen_tipico_pp')), '{}'),
       count(*) FILTER (WHERE p50_pct_1_5 < -analytics.param('margen_tipico_pp') AND composicion_edad),
       count(*) FILTER (WHERE p50_pct_1_5 < -analytics.param('margen_tipico_pp') AND composicion_edad),
       (percentile_cont(0.5) WITHIN GROUP (ORDER BY mayores30_max_p5)
            FILTER (WHERE p50_pct_1_5 < -analytics.param('margen_tipico_pp') AND composicion_edad))::numeric,
       (percentile_cont(0.5) WITHIN GROUP (ORDER BY mayores30_max_p1)
            FILTER (WHERE p50_pct_1_5 < -analytics.param('margen_tipico_pp') AND composicion_edad))::numeric,
       count(*) FILTER (WHERE composicion_edad)
FROM comp
GROUP BY nivel_carrera;

-- --------------------------------------------------------------------------
-- (b) Crecer más en % no es crecer más
-- --------------------------------------------------------------------------
CREATE TABLE analytics.hallazgo_pct_pesos (
    -- Por nivel: el fenómeno es casi solo de las profesionales y un total mezclado lo escondía.
    n_cambian_tec           integer NOT NULL,   -- técnicas que cambian de cuadrante entre % y pesos
    n_cambian_pro           integer NOT NULL,   -- profesionales ídem
    clave_carrera_generica  text,               -- ejemplo; NULL si ninguna cumple la regla
    tipo_institucion        text,
    p50_anio_1              integer,
    p50_pct_1_5             numeric,
    p50_delta_1_5           numeric,
    ref_delta_q50           numeric,            -- mediana PONDERADA del aumento en pesos de su grupo
    -- La tarjeta da los dos sueldos y el % del grupo: sin ellos, «sube 66,5 %» no decía desde dónde
    -- ni contra qué (revisión design-is del 18-11-26). Solo el aumento del grupo, no su 1er y 5° año:
    -- esas medianas se calculan por separado y su resta no da ref_delta_q50.
    p50_anio_5              integer,
    ref_pct_q50             numeric,            -- mediana PONDERADA del crecimiento en % de su grupo
    grupo_id                text,               -- para nombrar el grupo (área, tipo y nivel)
    FOREIGN KEY (clave_carrera_generica, tipo_institucion) REFERENCES analytics.par
);

INSERT INTO analytics.hallazgo_pct_pesos
WITH cand AS (
    SELECT po.clave_carrera_generica, po.tipo_institucion, e.percentil_50_anio_1,
           b.p50_pct_1_5, b.p50_delta_1_5, r.q50, e.percentil_50_anio_5, rp.q50 AS q50_pct, po.grupo_id
    FROM analytics.posicion po
    JOIN analytics.brecha b USING (clave_carrera_generica, tipo_institucion)
    JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
    JOIN analytics.referencia r ON r.grupo_id = po.grupo_id AND r.metrica = 'p50_delta_1_5'
    JOIN analytics.referencia rp ON rp.grupo_id = po.grupo_id AND rp.metrica = 'p50_pct_1_5'
    WHERE po.cambia_cuadrante AND po.progreso_pct = 'más'
      AND b.p50_delta_1_5 <= (1 - analytics.param('margen_ejemplo_pesos')) * r.q50
)
SELECT (SELECT count(*) FROM analytics.posicion po JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
        WHERE po.cambia_cuadrante AND p.nivel_carrera = 'Carreras Técnicas'),
       (SELECT count(*) FROM analytics.posicion po JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
        WHERE po.cambia_cuadrante AND p.nivel_carrera = 'Carreras Profesionales'),
       ej.clave_carrera_generica, ej.tipo_institucion, ej.percentil_50_anio_1,
       ej.p50_pct_1_5, ej.p50_delta_1_5, ej.q50, ej.percentil_50_anio_5, ej.q50_pct, ej.grupo_id
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
-- 1. (a) por otro camino, nivel por nivel: P50 desde modelo (no desde brecha) y la marca con su
--    fórmula (no la columna). FULL JOIN: un nivel que falte de un lado también cuenta como diferencia.
SELECT 'analytics_hallazgos', 'edad_mismo_grupo', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'conteos y medianas de edad = recálculo por nivel sobre las carreras que bajan con marca de edad',
       (SELECT string_agg(format('%s: %s de %s bajan, %s con edad; %s con marca de edad', nivel_carrera, n_negativos, n_comparables, n_con_edad, n_marca_edad),
                          '; ' ORDER BY nivel_carrera)
        FROM analytics.hallazgo_edad)
FROM (SELECT count(*) AS n
      FROM analytics.hallazgo_edad h
      FULL JOIN (SELECT p.nivel_carrera,
                        count(*) FILTER (WHERE 100.0 * (e.percentil_50_anio_5 - e.percentil_50_anio_1) / e.percentil_50_anio_1 < -analytics.param('margen_tipico_pp')) AS neg,
                        count(*) FILTER (WHERE 100.0 * (e.percentil_50_anio_5 - e.percentil_50_anio_1) / e.percentil_50_anio_1 < -analytics.param('margen_tipico_pp')
                                           AND (c.mayores30_max_p1 - c.mayores30_max_p5) * 100
                                               >= analytics.param('min_cambio_edad_pp')) AS edad,
                        (percentile_cont(0.5) WITHIN GROUP (ORDER BY c.mayores30_max_p5)
                             FILTER (WHERE 100.0 * (e.percentil_50_anio_5 - e.percentil_50_anio_1) / e.percentil_50_anio_1 < -analytics.param('margen_tipico_pp')
                                       AND (c.mayores30_max_p1 - c.mayores30_max_p5) * 100
                                           >= analytics.param('min_cambio_edad_pp')))::numeric AS p5,
                        (percentile_cont(0.5) WITHIN GROUP (ORDER BY c.mayores30_max_p1)
                             FILTER (WHERE 100.0 * (e.percentil_50_anio_5 - e.percentil_50_anio_1) / e.percentil_50_anio_1 < -analytics.param('margen_tipico_pp')
                                       AND (c.mayores30_max_p1 - c.mayores30_max_p5) * 100
                                           >= analytics.param('min_cambio_edad_pp')))::numeric AS p1,
                        count(*) FILTER (WHERE (c.mayores30_max_p1 - c.mayores30_max_p5) * 100
                                                   >= analytics.param('min_cambio_edad_pp')) AS marca
                 FROM analytics.par p
                 JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
                 JOIN analytics.contexto c USING (clave_carrera_generica, tipo_institucion)
                 WHERE p.representativo
                 GROUP BY p.nivel_carrera) x USING (nivel_carrera)
      WHERE h.n_negativos IS DISTINCT FROM x.neg OR h.n_con_edad IS DISTINCT FROM x.edad
         OR h.mayores30_p5 IS DISTINCT FROM x.p5 OR h.mayores30_p1 IS DISTINCT FROM x.p1
         OR h.n_marca_edad IS DISTINCT FROM x.marca) x
UNION ALL
-- 1a. La cifra de portada (mediana SIMPLE del crecimiento del P50 de las carreras de cada nivel,
--     con los tipos de institución juntos; así la rotula la web desde el 19-11-26) por otro camino:
--     P50 desde modelo, carreras ordenadas y valor central (o promedio de los dos centrales), sin
--     percentile_cont.
SELECT 'analytics_hallazgos', 'mediana_portada', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'mediana_p50_pct = valor central de las comparables del nivel ordenadas (recálculo sin percentile_cont)',
       (SELECT string_agg(format('%s: %s %%', nivel_carrera, round(mediana_p50_pct, 1)), '; ' ORDER BY nivel_carrera)
        FROM analytics.hallazgo_edad)
FROM (SELECT count(*) AS n
      FROM analytics.hallazgo_edad h
      FULL JOIN (SELECT nivel_carrera, avg(v) AS med
                 FROM (SELECT p.nivel_carrera,
                              100.0 * (e.percentil_50_anio_5 - e.percentil_50_anio_1) / e.percentil_50_anio_1 AS v,
                              row_number() OVER (PARTITION BY p.nivel_carrera
                                                 ORDER BY (e.percentil_50_anio_5::numeric / e.percentil_50_anio_1)) AS i,
                              count(*) OVER (PARTITION BY p.nivel_carrera) AS n
                       FROM analytics.par p
                       JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
                       WHERE p.representativo) o
                 WHERE i IN ((n + 1) / 2, (n + 2) / 2)
                 GROUP BY nivel_carrera) x USING (nivel_carrera)
      WHERE x.med IS NULL OR abs(h.mediana_p50_pct - x.med) > 0.0001) x
UNION ALL
-- 1b. Los niveles cubren a todas las comparables, sin perder ni repetir pares (p. ej. un nivel nuevo).
SELECT 'analytics_hallazgos', 'edad_niveles',
       CASE WHEN n_niveles = 2 AND n_suma = n_rep THEN 'OK' ELSE 'FALLA' END,
       n_niveles, '2 niveles (técnicas y profesionales) que suman todas las comparables',
       format('%s niveles; %s comparables en los niveles, %s en analytics.par', n_niveles, n_suma, n_rep)
FROM (SELECT (SELECT count(*) FROM analytics.hallazgo_edad) AS n_niveles,
             (SELECT coalesce(sum(n_comparables), 0) FROM analytics.hallazgo_edad) AS n_suma,
             (SELECT count(*) FROM analytics.par WHERE representativo) AS n_rep) x
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
      WHERE NOT (po.cambia_cuadrante AND po.progreso_pct = 'más'
                 AND h.p50_delta_1_5 <= (1 - analytics.param('margen_ejemplo_pesos')) * r.q50)
         OR h.ref_delta_q50 <> r.q50) x
UNION ALL
-- 2b. (b) las cifras nuevas de la tarjeta cuadran: 1er año + aumento = 5° año (desde modelo, no desde
--     brecha) y el % citado del grupo es el de SU grupo, el mismo de su referencia en pesos.
SELECT 'analytics_hallazgos', 'ejemplo_pct_pesos_cifras', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'p50_anio_1 + p50_delta_1_5 = p50_anio_5 y ref_pct_q50 = referencia p50_pct_1_5 del grupo',
       (SELECT coalesce(format('%s + %s = %s; grupo %s: %s %%', p50_anio_1, round(p50_delta_1_5), p50_anio_5,
                               grupo_id, round(ref_pct_q50, 1)), 'sin ejemplo')
        FROM analytics.hallazgo_pct_pesos)
FROM (SELECT count(*) AS n
      FROM analytics.hallazgo_pct_pesos h
      JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
      JOIN analytics.posicion po USING (clave_carrera_generica, tipo_institucion)
      JOIN analytics.referencia rp ON rp.grupo_id = po.grupo_id AND rp.metrica = 'p50_pct_1_5'
      WHERE round(h.p50_anio_1 + h.p50_delta_1_5) <> e.percentil_50_anio_5
         OR h.p50_anio_5 <> e.percentil_50_anio_5
         OR h.ref_pct_q50 <> rp.q50 OR h.grupo_id <> po.grupo_id) x
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

-- --------------------------------------------------------------------------
-- (d) Seguir estudiando es cosa de las carreras técnicas — POR NIVEL (18-11-26)
-- --------------------------------------------------------------------------
-- % de titulados que al año siguiente sigue estudiando (pct_continuidad_estudios de MiFuturo, por
-- programa), PONDERADO por las titulaciones SIES del programa en las cohortes del indicador (Derecho
-- corrido un año, como en todo el análisis): así la cifra se lee «de cada 100 titulados» y no
-- «el programa típico» (la mediana por programa da 13,6–31,1 % en técnicas).
-- Lo que NO se publica: una correlación con la empleabilidad. En bruto es positiva en técnicas
-- (r 0,24–0,32), pero dentro de cada carrera desaparece o cambia de signo (mezcla de carreras) y no
-- resiste la corrección por 5 pruebas. La frase de «Qué no dice» que lo afirma la vigila el
-- control continuidad_sin_relacion: si un dato nuevo muestra relación, el build falla.
INSERT INTO analytics.parametro VALUES
    ('min_prog_ejemplo_cont', 5,   'Hallazgo (d): programas mínimos de una carrera técnica para servir de ejemplo de continuidad', 'Hallazgo (d), 18-11-26'),
    ('max_t_continuidad',     2.6, 'Hallazgo (d): |t| máximo de la correlación continuidad–empleabilidad dentro de cada carrera para afirmar que no la explica (0,05 / 5 pruebas, dos colas)', 'Hallazgo (d), 18-11-26'),
    ('min_prog_par_cont',     5,   'Hallazgo (d): programas mínimos de un par para entrar en la prueba dentro de cada carrera', 'Hallazgo (d), 18-11-26');

-- Peso de cada programa: titulaciones SIES de su institución y carrera en las cohortes del indicador.
CREATE VIEW analytics.v_continuidad_programa AS
WITH c AS (SELECT cohorte_desde AS desde, cohorte_hasta AS hasta FROM modelo.cohorte
           WHERE indicador = 'continuidad_estudios_institucion')
SELECT p.codigo_institucion, p.clave_carrera_generica, p.tipo_institucion, g.nivel_carrera,
       p.pct_continuidad_estudios AS cont, p.empleabilidad_1er_anio AS emp1,
       coalesce((SELECT sum(t.total_titulaciones) FROM modelo.titulacion t
                 WHERE t.codigo_institucion = p.codigo_institucion
                   AND t.clave_carrera_generica = p.clave_carrera_generica
                   AND t.anio BETWEEN c.desde + (p.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int
                                  AND c.hasta + (p.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int), 0) AS peso
FROM modelo.mifuturo_programa p
JOIN modelo.carrera_generica g USING (clave_carrera_generica)
CROSS JOIN c;

CREATE TABLE analytics.hallazgo_continuidad (
    nivel_carrera  text    PRIMARY KEY,
    n_programas    integer NOT NULL,
    peso_total     integer NOT NULL,
    pct_pond       numeric NOT NULL CHECK (pct_pond BETWEEN 0 AND 100),   -- de cada 100 titulados
    de_cada_100    integer NOT NULL                                        -- lo que dice la tarjeta
);
INSERT INTO analytics.hallazgo_continuidad
SELECT nivel_carrera, count(*), sum(peso), sum(cont * peso) / sum(peso), round(sum(cont * peso) / sum(peso))
FROM analytics.v_continuidad_programa GROUP BY 1;

-- Ejemplos por regla, entre las técnicas COMPARABLES con >= min_prog_ejemplo_cont programas: la de
-- más titulados sobre el promedio de su nivel ('alto') y la de más titulados bajo él ('bajo').
CREATE TABLE analytics.hallazgo_continuidad_ejemplo (
    lado                    text    PRIMARY KEY CHECK (lado IN ('alto', 'bajo')),
    clave_carrera_generica  text    NOT NULL,
    tipo_institucion        text    NOT NULL,
    n_programas             integer NOT NULL,
    peso                    integer NOT NULL,
    pct_pond                numeric NOT NULL,
    de_cada_100             integer NOT NULL,
    FOREIGN KEY (clave_carrera_generica, tipo_institucion) REFERENCES analytics.par
);
INSERT INTO analytics.hallazgo_continuidad_ejemplo
WITH carrera AS (
    SELECT v.clave_carrera_generica, v.tipo_institucion, count(*) AS n, sum(v.peso) AS peso,
           sum(v.cont * v.peso) / nullif(sum(v.peso), 0) AS pct
    FROM analytics.v_continuidad_programa v
    JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
    WHERE p.representativo AND p.nivel_carrera = 'Carreras Técnicas'
    GROUP BY 1, 2
    HAVING count(*) >= analytics.param('min_prog_ejemplo_cont') AND sum(v.peso) > 0
), nivel AS (SELECT pct_pond FROM analytics.hallazgo_continuidad WHERE nivel_carrera = 'Carreras Técnicas')
SELECT lado, clave_carrera_generica, tipo_institucion, n, peso, pct, round(pct)
FROM (SELECT DISTINCT ON (lado) CASE WHEN c.pct > n.pct_pond THEN 'alto' ELSE 'bajo' END AS lado, c.*
      FROM carrera c, nivel n
      ORDER BY lado, c.peso DESC, c.tipo_institucion, c.clave_carrera_generica) x;

-- Prueba dentro de cada carrera, por tipo × nivel: se resta el promedio del par a continuidad y
-- empleabilidad y se correlacionan los desvíos (pares con >= min_prog_par_cont programas).
CREATE TABLE analytics.continuidad_relacion (
    tipo_institucion  text    NOT NULL,
    nivel_carrera     text    NOT NULL,
    n                 integer NOT NULL,
    r_dentro          numeric,
    t                 numeric,
    PRIMARY KEY (tipo_institucion, nivel_carrera)
);
INSERT INTO analytics.continuidad_relacion
WITH b AS (
    SELECT tipo_institucion, nivel_carrera, clave_carrera_generica, cont, emp1,
           count(*) OVER (PARTITION BY clave_carrera_generica, tipo_institucion) AS n_par
    FROM analytics.v_continuidad_programa
), d AS (
    SELECT tipo_institucion, nivel_carrera,
           cont - avg(cont) OVER (PARTITION BY clave_carrera_generica, tipo_institucion) AS dc,
           emp1 - avg(emp1) OVER (PARTITION BY clave_carrera_generica, tipo_institucion) AS de
    FROM b WHERE n_par >= analytics.param('min_prog_par_cont')
), r AS (SELECT tipo_institucion, nivel_carrera, count(*) AS n, corr(dc, de)::numeric AS r FROM d GROUP BY 1, 2)
SELECT tipo_institucion, nivel_carrera, n, r, r * sqrt((n - 2) / nullif(1 - r ^ 2, 0)) FROM r;

INSERT INTO qa.control (control, objeto, estado, metrica, umbral, detalle)
-- 4. (d) los pesos cubren lo mismo que la cobertura publicada por otro camino: la suma de pesos por
--    nivel = titulaciones de programas publicados en analytics.segmento (misma ventana 2021-2023,
--    mismo Derecho +1; se exige que la cohorte de la continuidad sea la de la media del 1er año).
SELECT 'analytics_hallazgos', 'continuidad_pesos', CASE WHEN n = 0 AND misma_ventana THEN 'OK' ELSE 'FALLA' END,
       n, 'peso_total por nivel = tit_publicadas_1 de analytics.segmento; ventana de continuidad = la del 1er año',
       (SELECT string_agg(format('%s: %s de cada 100 (%s programas)', nivel_carrera, round(pct_pond, 1), n_programas),
                          '; ' ORDER BY nivel_carrera) FROM analytics.hallazgo_continuidad)
FROM (SELECT (SELECT count(*) FROM analytics.hallazgo_continuidad h
              FULL JOIN (SELECT nivel_carrera, sum(tit_publicadas_1) AS t FROM analytics.segmento GROUP BY 1) s USING (nivel_carrera)
              WHERE h.peso_total IS DISTINCT FROM s.t::integer) AS n,
             (SELECT (a.cohorte_desde, a.cohorte_hasta) = (b.cohorte_desde, b.cohorte_hasta)
              FROM modelo.cohorte a, modelo.cohorte b
              WHERE a.indicador = 'continuidad_estudios_institucion' AND b.indicador = 'ingreso_medio_1er_anio') AS misma_ventana) x
UNION ALL
-- 5. (d) los ejemplos cumplen la regla: 'alto' sobre el promedio y 'bajo' bajo él, cada uno el de más
--    titulados de su lado, y ambos técnicos comparables con programas suficientes.
SELECT 'analytics_hallazgos', 'continuidad_ejemplos', CASE WHEN n = 0 AND k = 2 THEN 'OK' ELSE 'FALLA' END,
       n, 'alto > promedio técnicas > bajo; técnicas comparables con >= min_prog_ejemplo_cont programas',
       (SELECT string_agg(format('%s: %s (%s) %s de cada 100', lado, clave_carrera_generica, tipo_institucion, round(pct_pond, 1)),
                          '; ' ORDER BY lado) FROM analytics.hallazgo_continuidad_ejemplo)
FROM (SELECT count(*) FILTER (WHERE NOT (p.representativo AND p.nivel_carrera = 'Carreras Técnicas'
                                        AND e.n_programas >= analytics.param('min_prog_ejemplo_cont')
                                        AND CASE e.lado WHEN 'alto' THEN e.pct_pond > h.pct_pond ELSE e.pct_pond <= h.pct_pond END)) AS n,
             count(*) AS k
      FROM analytics.hallazgo_continuidad_ejemplo e
      JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
      CROSS JOIN (SELECT pct_pond FROM analytics.hallazgo_continuidad WHERE nivel_carrera = 'Carreras Técnicas') h) x
UNION ALL
-- 6. (d) «Qué no dice» afirma que la continuidad no explica la empleabilidad entre instituciones de
--    una carrera: ningún segmento puede superar max_t_continuidad. Si falla, hay que reescribir la frase.
SELECT 'analytics_hallazgos', 'continuidad_sin_relacion',
       CASE WHEN max_t < analytics.param('max_t_continuidad') THEN 'OK' ELSE 'FALLA' END,
       round(max_t, 2), '|t| dentro de cada carrera < max_t_continuidad en todos los segmentos',
       (SELECT string_agg(format('%s %s: r %s, t %s (n %s)', tipo_institucion, nivel_carrera, round(r_dentro, 2), round(t, 1), n),
                          '; ' ORDER BY tipo_institucion, nivel_carrera) FROM analytics.continuidad_relacion)
FROM (SELECT max(abs(t)) AS max_t FROM analytics.continuidad_relacion) x;
