-- src/Analisis/sql/analytics/04_dispersion.sql
--
-- A4 (Fase 2): dispersión entre instituciones (D1). MiFuturo no publica ingresos por
-- institución en los años 1 y 5, así que la dispersión se mide solo en la empleabilidad del
-- 1er y 2° año y en el tramo del ingreso promedio al 4° año.
-- Rótulo de empleabilidad (D3): "% con ingreso ≥ sueldo mínimo entre titulados con registro en
-- el SII"; entre instituciones va siempre junto a pct_continuidad_estudios, que la deprime.
--
-- REFERENCIA = MEDIANA DE LAS INSTITUCIONES PUBLICADAS DEL PAR (corrección de D1 aprobada en A4).
-- D1 decía comparar cada institución con la cifra NACIONAL de su par. Los datos lo desaconsejan:
-- la cifra nacional queda sistemáticamente sobre el promedio de las instituciones publicadas,
-- incluso ponderado por titulaciones, en la empleabilidad del 1er año y en el tramo del 4° año
-- (magnitud vigente: tabla analytics.brecha_nacional, más abajo, con su control qa), con las mismas
-- cohortes, moneda y filtro de sueldo mínimo según la metodología. La cifra nacional describe
-- una población más amplia que las filas por institución; no hay datos para saber cuál. Contra
-- ella, "bajo el promedio" quedaba inflado (715 tramos "bajo" vs 131 "sobre"). La mediana del
-- par compara poblaciones equivalentes y responde "¿esta institución está sobre o bajo la
-- institución típica de su carrera?". La cifra nacional se conserva como contexto y la brecha
-- nacional − instituciones se mide en cada build (control qa).
--
-- Reglas aprobadas:
--   - dispersión de un par e indicador solo con >= min_inst_dispersion instituciones con el dato;
--   - "promedio nacional engañoso" = IQR entre instituciones de la empleabilidad del 1er año
--     >= min_iqr_enganoso puntos (sensibilidad: 10 pp marca 63/104, 15 pp 19, 20 pp 5);
--   - tramo: por carrera donde haya >= 5 instituciones; resumen por segmento solo donde el
--     segmento tenga >= min_pares_resumen_tramo pares (hoy solo Universidad profesional: 47 vs 2-5).
-- Instituciones sin ponderar: para quien elige institución, cada una es una opción.
-- Cuartiles de empleabilidad con percentile_cont (interpolado), salvo la mediana, que es la
-- institución del medio real (percentile_disc, desde el 19-11-26). La mediana del tramo es el tramo
-- de la institución mediana (percentile_disc): un tramo es una categoría, no se interpola.
-- Requiere 01_par.sql.

INSERT INTO analytics.parametro VALUES
    ('min_iqr_enganoso',        15, 'IQR entre instituciones de la empleabilidad del 1er año (puntos) desde el cual la cifra nacional es engañosa', 'Plan Fase 2, decisión 2 (sensibilidad 10/15/20 revisada en A4)'),
    ('min_pares_resumen_tramo', 20, 'Pares con dispersión de tramo necesarios para resumir el tramo por segmento',                                   'T5, decisión 1');

-- --------------------------------------------------------------------------
-- Programa (institución × genérica) frente a la institución típica de su par
-- --------------------------------------------------------------------------
CREATE TABLE analytics.programa_vs_par (
    codigo_institucion          integer NOT NULL,
    clave_carrera_generica      text    NOT NULL,
    tipo_institucion            text    NOT NULL,
    empleabilidad_1er_anio      numeric NOT NULL,
    mediana_par_1er_anio        numeric NOT NULL,   -- mediana de las instituciones publicadas del par
    desvio_1er_anio             numeric NOT NULL,   -- puntos: institución − mediana del par
    empleabilidad_2do_anio      numeric,
    mediana_par_2do_anio        numeric,            -- NULL si ninguna institución del par lo publica
    desvio_2do_anio             numeric,
    pct_continuidad_estudios    numeric NOT NULL,   -- D3: siempre junto a la empleabilidad
    tramo_min                   integer,
    tramo_max                   integer,            -- NULL con tramo_min no nulo = tramo abierto "Sobre $X"
    mediana_par_tramo_min       integer,            -- cota inferior del tramo de la institución mediana
    tramo_vs_par                text CHECK (tramo_vs_par IN ('bajo', 'igual', 'sobre')),
    nacional_1er_anio           numeric NOT NULL,   -- contexto (población más amplia, ver cabecera)
    nacional_2do_anio           numeric NOT NULL,
    ingreso_medio_4to_nacional  integer NOT NULL,
    PRIMARY KEY (codigo_institucion, clave_carrera_generica),
    FOREIGN KEY (clave_carrera_generica, tipo_institucion) REFERENCES analytics.par
);
COMMENT ON TABLE analytics.programa_vs_par IS
    'Programas de MiFuturo cuyo par tiene estadística nacional. Desvíos y tramo_vs_par contra la mediana de las instituciones publicadas del par (no contra la cifra nacional). La comparación solo se muestra donde el par tiene dispersión (>= min_inst_dispersion).';

INSERT INTO analytics.programa_vs_par
WITH mediana AS (
    SELECT clave_carrera_generica, tipo_institucion,
           -- percentile_disc: la «institución del medio» es una institución real (19-11-26). Con
           -- percentile_cont, con un número par de instituciones era el promedio de dos y las
           -- diferencias de la tabla no cuadraban a la décima con la cifra mostrada (102 filas).
           percentile_disc(0.5) WITHIN GROUP (ORDER BY empleabilidad_1er_anio) AS med_1,
           percentile_disc(0.5) WITHIN GROUP (ORDER BY empleabilidad_2do_anio) AS med_2,  -- ignora NULL
           percentile_disc(0.5) WITHIN GROUP (ORDER BY ingreso_4to_anio_tramo_min) AS med_tramo
    FROM modelo.mifuturo_programa
    GROUP BY 1, 2
)
SELECT m.codigo_institucion, m.clave_carrera_generica, m.tipo_institucion,
       m.empleabilidad_1er_anio, md.med_1, m.empleabilidad_1er_anio - md.med_1,
       m.empleabilidad_2do_anio, md.med_2, m.empleabilidad_2do_anio - md.med_2,
       m.pct_continuidad_estudios,
       m.ingreso_4to_anio_tramo_min, m.ingreso_4to_anio_tramo_max, md.med_tramo,
       CASE WHEN m.ingreso_4to_anio_tramo_min IS NULL THEN NULL
            WHEN m.ingreso_4to_anio_tramo_min < md.med_tramo THEN 'bajo'
            WHEN m.ingreso_4to_anio_tramo_min > md.med_tramo THEN 'sobre'
            ELSE 'igual' END,
       e.empleabilidad_1er_anio, e.empleabilidad_2do_anio, e.ingreso_medio_4to_anio
FROM modelo.mifuturo_programa m
JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
JOIN mediana md USING (clave_carrera_generica, tipo_institucion);

-- --------------------------------------------------------------------------
-- Dispersión de la empleabilidad por par (1er y 2° año)
-- --------------------------------------------------------------------------
CREATE TABLE analytics.dispersion_empleabilidad (
    clave_carrera_generica  text     NOT NULL,
    tipo_institucion        text     NOT NULL,
    anio                    smallint NOT NULL CHECK (anio IN (1, 2)),
    n_inst                  integer  NOT NULL,
    minimo                  numeric  NOT NULL,
    q1                      numeric  NOT NULL,
    mediana                 numeric  NOT NULL,   -- la institución típica (referencia del par)
    q3                      numeric  NOT NULL,
    maximo                  numeric  NOT NULL,
    iqr                     numeric  NOT NULL,
    nacional                numeric  NOT NULL,   -- contexto
    nacional_menos_mediana  numeric  NOT NULL,   -- cuánto se aparta la cifra nacional de la institución típica
    promedio_enganoso       boolean,             -- solo año 1 (decisión); NULL en el año 2
    PRIMARY KEY (clave_carrera_generica, tipo_institucion, anio),
    FOREIGN KEY (clave_carrera_generica, tipo_institucion) REFERENCES analytics.par,
    CHECK (minimo <= q1 AND q1 <= mediana AND mediana <= q3 AND q3 <= maximo)
);

INSERT INTO analytics.dispersion_empleabilidad
SELECT v.clave_carrera_generica, v.tipo_institucion, v.anio, count(*),
       min(v.valor),
       percentile_cont(0.25) WITHIN GROUP (ORDER BY v.valor),
       percentile_disc(0.50) WITHIN GROUP (ORDER BY v.valor),   -- institución real (ver programa_vs_par)
       percentile_cont(0.75) WITHIN GROUP (ORDER BY v.valor),
       max(v.valor),
       percentile_cont(0.75) WITHIN GROUP (ORDER BY v.valor) - percentile_cont(0.25) WITHIN GROUP (ORDER BY v.valor),
       max(v.nacional),
       max(v.nacional) - percentile_disc(0.50) WITHIN GROUP (ORDER BY v.valor),
       CASE WHEN v.anio = 1 THEN
           percentile_cont(0.75) WITHIN GROUP (ORDER BY v.valor) - percentile_cont(0.25) WITHIN GROUP (ORDER BY v.valor)
           >= analytics.param('min_iqr_enganoso') END
FROM analytics.programa_vs_par pv
CROSS JOIN LATERAL (VALUES
    (pv.clave_carrera_generica, pv.tipo_institucion, 1, pv.empleabilidad_1er_anio, pv.nacional_1er_anio),
    (pv.clave_carrera_generica, pv.tipo_institucion, 2, pv.empleabilidad_2do_anio, pv.nacional_2do_anio)
) AS v (clave_carrera_generica, tipo_institucion, anio, valor, nacional)
WHERE v.valor IS NOT NULL
GROUP BY v.clave_carrera_generica, v.tipo_institucion, v.anio
HAVING count(*) >= analytics.param('min_inst_dispersion');

-- --------------------------------------------------------------------------
-- Dispersión del tramo del 4° año por par (por carrera)
-- --------------------------------------------------------------------------
CREATE TABLE analytics.dispersion_tramo (
    clave_carrera_generica  text    NOT NULL,
    tipo_institucion        text    NOT NULL,
    n_inst                  integer NOT NULL,
    tramo_min_inferior      integer NOT NULL,   -- cota inferior del tramo más bajo
    tramo_min_superior      integer NOT NULL,   -- cota inferior del tramo más alto
    tramo_max_superior      integer,            -- cota superior del tramo más alto; NULL = abierto
    amplitud                integer NOT NULL,   -- tramo_min_superior − tramo_min_inferior (pesos)
    mediana_tramo_min       integer NOT NULL,   -- tramo de la institución mediana
    n_tramos_distintos      integer NOT NULL,
    n_bajo                  integer NOT NULL,   -- instituciones en un tramo bajo el de la mediana
    n_igual                 integer NOT NULL,
    n_sobre                 integer NOT NULL,
    nacional_4to            integer NOT NULL,   -- contexto
    PRIMARY KEY (clave_carrera_generica, tipo_institucion),
    FOREIGN KEY (clave_carrera_generica, tipo_institucion) REFERENCES analytics.par,
    CHECK (n_bajo + n_igual + n_sobre = n_inst)
);

INSERT INTO analytics.dispersion_tramo
SELECT clave_carrera_generica, tipo_institucion, count(*),
       min(tramo_min), max(tramo_min),
       CASE WHEN bool_or(tramo_max IS NULL) THEN NULL ELSE max(tramo_max) END,
       max(tramo_min) - min(tramo_min),
       max(mediana_par_tramo_min),
       count(DISTINCT tramo_min),
       count(*) FILTER (WHERE tramo_vs_par = 'bajo'),
       count(*) FILTER (WHERE tramo_vs_par = 'igual'),
       count(*) FILTER (WHERE tramo_vs_par = 'sobre'),
       max(ingreso_medio_4to_nacional)
FROM analytics.programa_vs_par
WHERE tramo_min IS NOT NULL
GROUP BY clave_carrera_generica, tipo_institucion
HAVING count(*) >= analytics.param('min_inst_dispersion');

-- --------------------------------------------------------------------------
-- Resumen por segmento
-- --------------------------------------------------------------------------
CREATE TABLE analytics.dispersion_segmento (
    tipo_institucion         text    NOT NULL,
    nivel_carrera            text    NOT NULL,
    pares_emp1               integer NOT NULL,
    iqr_mediano_emp1         numeric,
    pares_enganosos          integer NOT NULL,
    pares_emp2               integer NOT NULL,
    iqr_mediano_emp2         numeric,
    pares_tramo              integer NOT NULL,
    resumen_tramo            boolean NOT NULL,   -- ¿alcanza para resumir el tramo en el segmento?
    amplitud_mediana_tramo   numeric,            -- solo si resumen_tramo: pesos entre tramo más bajo y más alto
    tramos_distintos_mediana numeric,            -- solo si resumen_tramo
    PRIMARY KEY (tipo_institucion, nivel_carrera),
    FOREIGN KEY (tipo_institucion, nivel_carrera) REFERENCES analytics.segmento
);

INSERT INTO analytics.dispersion_segmento
SELECT s.tipo_institucion, s.nivel_carrera,
       coalesce(e1.pares, 0), e1.iqr_mediano, coalesce(e1.enganosos, 0),
       coalesce(e2.pares, 0), e2.iqr_mediano,
       coalesce(t.pares, 0),
       coalesce(t.pares, 0) >= analytics.param('min_pares_resumen_tramo'),
       CASE WHEN coalesce(t.pares, 0) >= analytics.param('min_pares_resumen_tramo') THEN t.amplitud END,
       CASE WHEN coalesce(t.pares, 0) >= analytics.param('min_pares_resumen_tramo') THEN t.tramos END
FROM analytics.segmento s
LEFT JOIN (SELECT p.tipo_institucion, p.nivel_carrera, count(*) AS pares,
                  percentile_cont(0.5) WITHIN GROUP (ORDER BY d.iqr) AS iqr_mediano,
                  count(*) FILTER (WHERE d.promedio_enganoso) AS enganosos
           FROM analytics.dispersion_empleabilidad d JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
           WHERE d.anio = 1 GROUP BY 1, 2) e1 USING (tipo_institucion, nivel_carrera)
LEFT JOIN (SELECT p.tipo_institucion, p.nivel_carrera, count(*) AS pares,
                  percentile_cont(0.5) WITHIN GROUP (ORDER BY d.iqr) AS iqr_mediano
           FROM analytics.dispersion_empleabilidad d JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
           WHERE d.anio = 2 GROUP BY 1, 2) e2 USING (tipo_institucion, nivel_carrera)
LEFT JOIN (SELECT p.tipo_institucion, p.nivel_carrera, count(*) AS pares,
                  percentile_cont(0.5) WITHIN GROUP (ORDER BY d.amplitud) AS amplitud,
                  percentile_cont(0.5) WITHIN GROUP (ORDER BY d.n_tramos_distintos) AS tramos
           FROM analytics.dispersion_tramo d JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
           GROUP BY 1, 2) t USING (tipo_institucion, nivel_carrera);

-- Brecha cifra nacional − instituciones publicadas, ponderada por titulaciones SIES de las cohortes
-- de cada indicador, en los pares con dispersión. Es la razón de la corrección de D1 (cada
-- institución se compara con la típica de su carrera, no con la nacional). Antes vivía solo en el
-- detalle de texto de su control qa y la web la sacaba con un regex; como tabla, la web y el
-- README citan los mismos números (07_exportacion.sql → que_no_dice.brecha_nacional_instituciones).
CREATE TABLE analytics.brecha_nacional (
    unica      boolean PRIMARY KEY DEFAULT true CHECK (unica),   -- una sola fila
    med_emp    numeric,   -- pp de empleabilidad del 1er año, par mediano
    med_tramo  numeric,   -- proporción (0,062 = 6,2 %) en el punto medio del tramo del 4° año
    n_emp      integer NOT NULL,
    n_tramo    integer NOT NULL
);

INSERT INTO analytics.brecha_nacional (med_emp, med_tramo, n_emp, n_tramo)
SELECT med_emp, med_tramo, n_emp, n_tramo FROM (
    WITH c1 AS (SELECT cohorte_desde AS d, cohorte_hasta AS h FROM modelo.cohorte WHERE indicador = 'empleabilidad_1er_anio_institucion'),
         c4 AS (SELECT cohorte_desde AS d, cohorte_hasta AS h FROM modelo.cohorte WHERE indicador = 'tramo_ingreso_4to_anio_institucion'),
    peso AS (
        SELECT t.codigo_institucion, t.clave_carrera_generica,
               sum(t.total_titulaciones) FILTER (WHERE t.anio BETWEEN c1.d + (t.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int
                                                                  AND c1.h + (t.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int) AS w1,
               sum(t.total_titulaciones) FILTER (WHERE t.anio BETWEEN c4.d + (t.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int
                                                                  AND c4.h + (t.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int) AS w4
        FROM modelo.titulacion t CROSS JOIN c1 CROSS JOIN c4
        GROUP BY 1, 2
    ),
    emp AS (
        SELECT pv.clave_carrera_generica, pv.tipo_institucion,
               max(pv.nacional_1er_anio) - sum(pe.w1 * pv.empleabilidad_1er_anio) / nullif(sum(pe.w1), 0) AS brecha
        FROM analytics.programa_vs_par pv
        JOIN peso pe USING (codigo_institucion, clave_carrera_generica)
        JOIN analytics.dispersion_empleabilidad d
          ON d.clave_carrera_generica = pv.clave_carrera_generica AND d.tipo_institucion = pv.tipo_institucion AND d.anio = 1
        GROUP BY 1, 2
    ),
    tramo AS (
        SELECT pv.clave_carrera_generica, pv.tipo_institucion,
               max(pv.ingreso_medio_4to_nacional)
               / (sum(pe.w4 * (pv.tramo_min + coalesce(pv.tramo_max, pv.tramo_min)) / 2.0) / nullif(sum(pe.w4), 0)) - 1 AS brecha
        FROM analytics.programa_vs_par pv
        JOIN peso pe USING (codigo_institucion, clave_carrera_generica)
        JOIN analytics.dispersion_tramo d USING (clave_carrera_generica, tipo_institucion)
        WHERE pv.tramo_min IS NOT NULL
        GROUP BY 1, 2
    )
    SELECT (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY brecha) FROM emp)::numeric   AS med_emp,
           (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY brecha) FROM tramo)::numeric AS med_tramo,
           (SELECT count(*) FROM emp) AS n_emp, (SELECT count(*) FROM tramo) AS n_tramo
) x;

-- --------------------------------------------------------------------------
-- Controles qa
-- --------------------------------------------------------------------------
INSERT INTO qa.control (control, objeto, estado, metrica, umbral, detalle)
-- 1. Cada programa contra la mediana de SU par (recalculada desde modelo, por otro camino).
SELECT 'analytics_dispersion', 'mediana_de_su_par', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'mediana_par_1er_anio = mediana de las instituciones publicadas del propio par',
       format('%s programas con mediana ajena', n)
FROM (SELECT count(*) AS n
      FROM analytics.programa_vs_par pv
      -- ::numeric: percentile_cont devuelve double precision; comparado contra la columna
      -- numeric difiere en el último bit aunque el valor guardado sea el mismo (118 falsos
      -- positivos la primera vez).
      WHERE pv.mediana_par_1er_anio <> (
          SELECT percentile_disc(0.5) WITHIN GROUP (ORDER BY m.empleabilidad_1er_anio)
          FROM modelo.mifuturo_programa m
          WHERE m.clave_carrera_generica = pv.clave_carrera_generica
            AND m.tipo_institucion = pv.tipo_institucion)::numeric) x
UNION ALL
-- 1c. La institución del medio es una institución real del par y las diferencias que publica la
--     web cuadran a la décima con las cifras que muestra (empleabilidad − institución del medio, y
--     nacional − institución del medio): antes 102 filas diferían en 0,1.
SELECT 'analytics_dispersion', 'institucion_del_medio_real', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'mediana ∈ empleabilidades del par; round(valor,1) − round(mediana,1) = round(diferencia,1)',
       format('%s filas sin institución real o con diferencia que no cuadra', n)
FROM (SELECT (SELECT count(*) FROM analytics.dispersion_empleabilidad d
              WHERE NOT EXISTS (SELECT 1 FROM analytics.programa_vs_par pv
                                WHERE pv.clave_carrera_generica = d.clave_carrera_generica
                                  AND pv.tipo_institucion = d.tipo_institucion
                                  AND (CASE d.anio WHEN 1 THEN pv.empleabilidad_1er_anio ELSE pv.empleabilidad_2do_anio END) = d.mediana)
                 OR round(d.nacional, 1) - round(d.mediana, 1) <> round(d.nacional_menos_mediana, 1))
           + (SELECT count(*) FROM analytics.programa_vs_par pv
              WHERE round(pv.empleabilidad_1er_anio, 1) - round(pv.mediana_par_1er_anio, 1) <> round(pv.desvio_1er_anio, 1)
                 OR round(pv.empleabilidad_2do_anio, 1) - round(pv.mediana_par_2do_anio, 1) <> round(pv.desvio_2do_anio, 1)) AS n) x
UNION ALL
-- 2. Dispersión solo con suficientes instituciones (y para todos los pares que las tienen).
SELECT 'analytics_dispersion', 'min_instituciones', CASE WHEN n_mal = 0 AND n_falta = 0 THEN 'OK' ELSE 'FALLA' END,
       n_mal + n_falta, 'dispersión ⇔ ≥ min_inst_dispersion instituciones con el dato (n_pub_* de analytics.par)',
       format('%s filas con pocas instituciones; %s pares sin dispersión que debían tenerla', n_mal, n_falta)
FROM (SELECT
        (SELECT count(*) FROM analytics.dispersion_empleabilidad WHERE n_inst < analytics.param('min_inst_dispersion'))
      + (SELECT count(*) FROM analytics.dispersion_tramo WHERE n_inst < analytics.param('min_inst_dispersion')) AS n_mal,
        (SELECT count(*) FROM analytics.par p
         WHERE (p.n_pub_emp1 >= analytics.param('min_inst_dispersion')
                AND NOT EXISTS (SELECT 1 FROM analytics.dispersion_empleabilidad d
                                WHERE d.clave_carrera_generica = p.clave_carrera_generica
                                  AND d.tipo_institucion = p.tipo_institucion AND d.anio = 1))
            OR (p.n_pub_emp2 >= analytics.param('min_inst_dispersion')
                AND NOT EXISTS (SELECT 1 FROM analytics.dispersion_empleabilidad d
                                WHERE d.clave_carrera_generica = p.clave_carrera_generica
                                  AND d.tipo_institucion = p.tipo_institucion AND d.anio = 2))
            OR (p.n_pub_tramo >= analytics.param('min_inst_dispersion')
                AND NOT EXISTS (SELECT 1 FROM analytics.dispersion_tramo d
                                WHERE d.clave_carrera_generica = p.clave_carrera_generica
                                  AND d.tipo_institucion = p.tipo_institucion))) AS n_falta) x
UNION ALL
-- 3. Promedio engañoso: solo año 1 y exactamente según el umbral.
SELECT 'analytics_dispersion', 'promedio_enganoso', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'engañoso ⇔ año 1 e IQR ≥ min_iqr_enganoso; NULL en año 2',
       format('%s filas incoherentes; %s pares marcados', n,
              (SELECT count(*) FROM analytics.dispersion_empleabilidad WHERE promedio_enganoso))
FROM (SELECT count(*) AS n FROM analytics.dispersion_empleabilidad
      WHERE (anio = 1 AND promedio_enganoso IS DISTINCT FROM (iqr >= analytics.param('min_iqr_enganoso')))
         OR (anio = 2 AND promedio_enganoso IS NOT NULL)) x
UNION ALL
-- 4. Resumen del tramo por segmento solo donde alcanza (decisión 1 de T5).
SELECT 'analytics_dispersion', 'resumen_tramo', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'resumen del tramo ⇔ pares_tramo ≥ min_pares_resumen_tramo',
       format('%s segmentos incoherentes; con resumen: %s', n,
              (SELECT coalesce(string_agg(tipo_institucion || ' ' || nivel_carrera, ', '), 'ninguno')
               FROM analytics.dispersion_segmento WHERE resumen_tramo))
FROM (SELECT count(*) AS n FROM analytics.dispersion_segmento
      WHERE resumen_tramo <> (pares_tramo >= analytics.param('min_pares_resumen_tramo'))
         OR (NOT resumen_tramo AND (amplitud_mediana_tramo IS NOT NULL OR tramos_distintos_mediana IS NOT NULL))) x
UNION ALL
-- 5. Brecha cifra nacional − instituciones publicadas (calculada en analytics.brecha_nacional,
--    arriba). Falla si cambia de escala (> 5 pp o > 15 %), lo que indicaría un cambio de
--    definición en MiFuturo, o si se invierte el signo.
SELECT 'analytics_dispersion', 'brecha_nacional_instituciones',
       CASE WHEN med_emp BETWEEN 0 AND 5 AND med_tramo BETWEEN 0 AND 0.15 THEN 'OK' ELSE 'FALLA' END,
       round(med_emp, 2), 'mediana de (nacional − promedio ponderado de instituciones) en [0; 5] pp y [0; 15] % (tramo)',
       format('par mediano: empleabilidad 1er año %s pp; tramo 4° año (punto medio) %s %%; %s y %s pares',
              round(med_emp, 2), round(100 * med_tramo, 1), n_emp, n_tramo)
FROM analytics.brecha_nacional;
