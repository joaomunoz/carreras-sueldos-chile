-- src/Analisis/sql/analytics/06b_universo.sql
--
-- A quiénes mira el análisis: titulaciones SIES por año (para el gráfico de la Parte I) y el
-- embudo de las dos ventanas comparadas, de todas las titulaciones a las de las carreras comparables.
--
-- Por qué un embudo por carrera y no por institución: las 210 comparables se pesan con
-- analytics.par.tit_ventana_* (todas las instituciones que ofrecen la carrera). La cobertura de
-- MiFuturo por institución (analytics.segmento.tit_publicadas_*) mide otra cosa y no es un
-- subconjunto (638.348 > 621.778 en el 1er año): mezclarlas daría un embudo que no cuadra.
-- Esa cobertura sigue en la Parte III.
--
-- Las ventanas siguen la regla del proyecto: las de modelo.cohorte, con Derecho corrido un año.
-- La serie anual, en cambio, va por año calendario (es lo que muestra el gráfico); por eso la suma
-- de sus barras en una ventana no es idéntica al paso 1 del embudo. El control 3 mide esa
-- diferencia y exige que sea solo Derecho.
--
-- Nombre 06b: corre después de 06_hallazgos y antes de 07_exportacion, que lo exporta.
-- Son titulaciones, no personas: quien obtiene dos títulos cuenta dos veces (la web lo dice).

-- --------------------------------------------------------------------------
-- Serie anual por nivel (2017-2025, todos los años del SIES cargados)
-- --------------------------------------------------------------------------
CREATE TABLE analytics.universo_anual (
    anio           smallint NOT NULL,
    nivel_carrera  text     NOT NULL,
    titulaciones   integer  NOT NULL,
    ventana        text     CHECK (ventana IN ('1er', '5to')),   -- NULL = año fuera del análisis
    PRIMARY KEY (anio, nivel_carrera)
);
COMMENT ON TABLE analytics.universo_anual IS
    'Titulaciones SIES por año calendario y nivel; ventana marca los años de las cohortes del 1er y 5° año.';

INSERT INTO analytics.universo_anual
WITH c1 AS (SELECT cohorte_desde AS desde, cohorte_hasta AS hasta FROM modelo.cohorte WHERE indicador = 'ingreso_medio_1er_anio'),
     c5 AS (SELECT cohorte_desde AS desde, cohorte_hasta AS hasta FROM modelo.cohorte WHERE indicador = 'ingreso_medio_5to_anio')
SELECT t.anio, g.nivel_carrera, sum(t.total_titulaciones),
       CASE WHEN t.anio BETWEEN c1.desde AND c1.hasta THEN '1er'
            WHEN t.anio BETWEEN c5.desde AND c5.hasta THEN '5to' END
FROM modelo.titulacion t
JOIN modelo.carrera_generica g USING (clave_carrera_generica)
CROSS JOIN c1 CROSS JOIN c5
GROUP BY t.anio, g.nivel_carrera, c1.desde, c1.hasta, c5.desde, c5.hasta;

-- --------------------------------------------------------------------------
-- Embudo por ventana y nivel: todas → con estadística nacional → comparables
-- --------------------------------------------------------------------------
CREATE TABLE analytics.universo_embudo (
    ventana            text    NOT NULL CHECK (ventana IN ('1er', '5to')),
    nivel_carrera      text    NOT NULL,
    tit_sies           integer NOT NULL,   -- todas las titulaciones SIES de la ventana
    tit_con_estadistica integer NOT NULL,  -- en carreras con estadística nacional de MiFuturo (los 252 pares)
    tit_comparables    integer NOT NULL,   -- en las carreras comparables (representativo)
    n_comparables      integer NOT NULL,
    -- Sexo de tit_sies (mismas ventanas, Derecho corrido). otro = no binario; con 1 título no
    -- lleva barra propia y la web lo nombra en una nota.
    mujeres            integer NOT NULL,
    hombres            integer NOT NULL,
    otro               integer NOT NULL,
    -- Enteros que suman 100 sobre mujeres + hombres (resto mayor, igual que la barra de la ficha
    -- en 05_contexto.sql): redondear ambos podía dar 101.
    pct_mujeres        smallint NOT NULL CHECK (pct_mujeres BETWEEN 0 AND 100),
    pct_hombres        smallint NOT NULL CHECK (pct_hombres BETWEEN 0 AND 100),
    CHECK (pct_mujeres + pct_hombres = 100),
    PRIMARY KEY (ventana, nivel_carrera)
);

INSERT INTO analytics.universo_embudo (ventana, nivel_carrera, tit_sies, tit_con_estadistica,
                                     tit_comparables, n_comparables, mujeres, hombres, otro,
                                     pct_mujeres, pct_hombres)
WITH c1 AS (SELECT cohorte_desde AS desde, cohorte_hasta AS hasta FROM modelo.cohorte WHERE indicador = 'ingreso_medio_1er_anio'),
     c5 AS (SELECT cohorte_desde AS desde, cohorte_hasta AS hasta FROM modelo.cohorte WHERE indicador = 'ingreso_medio_5to_anio'),
sexo AS (   -- directo de modelo.titulacion, con el mismo corrimiento de Derecho que analytics.segmento
    SELECT v.ventana, g.nivel_carrera,
           sum(t.titulaciones_mujeres) AS muj, sum(t.titulaciones_hombres) AS hom, sum(t.titulaciones_nb) AS otro
    FROM modelo.titulacion t
    JOIN modelo.institucion i USING (codigo_institucion)
    JOIN modelo.carrera_generica g USING (clave_carrera_generica)
    CROSS JOIN c1 CROSS JOIN c5
    CROSS JOIN LATERAL (SELECT CASE
        WHEN t.anio BETWEEN c1.desde + (t.clave_carrera_generica = 'DERECHO')::int
                        AND c1.hasta + (t.clave_carrera_generica = 'DERECHO')::int THEN '1er'
        WHEN t.anio BETWEEN c5.desde + (t.clave_carrera_generica = 'DERECHO')::int
                        AND c5.hasta + (t.clave_carrera_generica = 'DERECHO')::int THEN '5to' END AS ventana) v
    WHERE v.ventana IS NOT NULL
    GROUP BY 1, 2
),
sies AS (   -- mismo cálculo que analytics.segmento, sumado por nivel
    SELECT nivel_carrera, sum(tit_sies_1) AS t1, sum(tit_sies_5) AS t5
    FROM analytics.segmento GROUP BY 1
), par AS (
    SELECT nivel_carrera,
           sum(tit_ventana_1) AS e1, sum(tit_ventana_5) AS e5,
           sum(tit_ventana_1) FILTER (WHERE representativo) AS r1,
           sum(tit_ventana_5) FILTER (WHERE representativo) AS r5,
           count(*) FILTER (WHERE representativo) AS n
    FROM analytics.par GROUP BY 1
)
SELECT e.*, x.muj, x.hom, x.otro, pm, 100 - pm
FROM (SELECT '1er' AS ventana, s.nivel_carrera, s.t1, p.e1, p.r1, p.n FROM sies s JOIN par p USING (nivel_carrera)
      UNION ALL
      SELECT '5to', s.nivel_carrera, s.t5, p.e5, p.r5, p.n FROM sies s JOIN par p USING (nivel_carrera)) e
JOIN sexo x USING (ventana, nivel_carrera)
CROSS JOIN LATERAL (SELECT round(100.0 * x.muj / (x.muj + x.hom))::smallint AS pm) r;

-- --------------------------------------------------------------------------
-- Controles qa
-- --------------------------------------------------------------------------
INSERT INTO qa.control (control, objeto, estado, metrica, umbral, detalle)
-- 1. Embudo anidado: cada paso cabe en el anterior, en cada ventana y nivel.
SELECT 'analytics_universo', 'embudo_anidado', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END, n,
       'tit_sies >= tit_con_estadistica >= tit_comparables en las 4 filas',
       (SELECT string_agg(format('%s %s: %s ≥ %s ≥ %s', ventana, nivel_carrera, tit_sies, tit_con_estadistica, tit_comparables),
                          '; ' ORDER BY ventana, nivel_carrera) FROM analytics.universo_embudo)
FROM (SELECT count(*) AS n FROM analytics.universo_embudo
      WHERE NOT (tit_sies >= tit_con_estadistica AND tit_con_estadistica >= tit_comparables)) x
UNION ALL
-- 2. Las comparables del embudo son las mismas que publica la web (2 niveles, ninguna perdida ni repetida).
SELECT 'analytics_universo', 'embudo_comparables',
       CASE WHEN n_emb = n_par AND niveles = 2 THEN 'OK' ELSE 'FALLA' END, n_emb,
       'suma de n_comparables del embudo (una ventana) = pares representativos',
       format('embudo %s, par %s, niveles %s', n_emb, n_par, niveles)
FROM (SELECT (SELECT sum(n_comparables) FROM analytics.universo_embudo WHERE ventana = '1er') AS n_emb,
             (SELECT count(*) FROM analytics.par WHERE representativo) AS n_par,
             (SELECT count(*) FROM analytics.universo_embudo WHERE ventana = '1er') AS niveles) x
UNION ALL
-- 3. La serie anual y el embudo cuentan lo mismo salvo Derecho (corrido un año): se recalcula la
--    ventana por otro camino, directo de modelo.titulacion, y se compara con el paso 1.
SELECT 'analytics_universo', 'serie_vs_embudo', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END, n,
       'barras de la ventana − Derecho del año calendario + Derecho corrido = paso 1 del embudo',
       'diferencias por ventana y nivel distintas de 0: ' || n
FROM (SELECT count(*) AS n
      FROM analytics.universo_embudo e
      JOIN (SELECT a.ventana, a.nivel_carrera,
                   sum(a.titulaciones)
                   - coalesce((SELECT sum(t.total_titulaciones) FROM modelo.titulacion t
                               JOIN analytics.universo_anual b ON b.anio = t.anio AND b.ventana = a.ventana
                                    AND b.nivel_carrera = a.nivel_carrera
                               JOIN modelo.carrera_generica g USING (clave_carrera_generica)
                               WHERE t.clave_carrera_generica = 'DERECHO' AND g.nivel_carrera = a.nivel_carrera), 0)
                   + coalesce((SELECT sum(t.total_titulaciones) FROM modelo.titulacion t
                               JOIN analytics.universo_anual b ON b.anio + 1 = t.anio AND b.ventana = a.ventana
                                    AND b.nivel_carrera = a.nivel_carrera
                               JOIN modelo.carrera_generica g USING (clave_carrera_generica)
                               WHERE t.clave_carrera_generica = 'DERECHO' AND g.nivel_carrera = a.nivel_carrera), 0) AS total
            FROM analytics.universo_anual a WHERE a.ventana IS NOT NULL
            GROUP BY a.ventana, a.nivel_carrera) s USING (ventana, nivel_carrera)
      WHERE s.total <> e.tit_sies) x
UNION ALL
-- 3b. El sexo cuadra con el total, que viene por otro camino (analytics.segmento): ningún título
--     queda fuera ni se cuenta dos veces al separar por sexo.
SELECT 'analytics_universo', 'sexo_cuadra', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END, n,
       'mujeres + hombres + otro = tit_sies en las 4 filas',
       (SELECT string_agg(format('%s %s: %s %% mujeres, %s otro', ventana, nivel_carrera, pct_mujeres, otro),
                          '; ' ORDER BY ventana, nivel_carrera) FROM analytics.universo_embudo)
FROM (SELECT count(*) AS n FROM analytics.universo_embudo WHERE mujeres + hombres + otro <> tit_sies) x
UNION ALL
-- 4. La serie no pierde filas en el cruce con carrera_generica: total por año = modelo sin cruzar.
SELECT 'analytics_universo', 'serie_completa', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END, n,
       'por año, suma de niveles = suma de modelo.titulacion',
       'años con diferencia: ' || n
FROM (SELECT count(*) AS n
      FROM (SELECT anio, sum(titulaciones) AS a FROM analytics.universo_anual GROUP BY 1) s
      FULL JOIN (SELECT anio, sum(total_titulaciones) AS m FROM modelo.titulacion GROUP BY 1) m USING (anio)
      WHERE s.a IS DISTINCT FROM m.m) x;

