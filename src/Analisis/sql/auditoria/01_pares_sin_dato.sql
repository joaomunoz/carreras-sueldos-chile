-- src/Analisis/sql/auditoria/01_pares_sin_dato.sql
--
-- Pregunta: ¿a quién dejan fuera los dos huecos de MiFuturo que afectan al análisis?
--   A. Programas cuyo par (genérica × tipo) no tiene estadística nacional publicada
--      (sin ingresos ni percentiles): no entran en la brecha 1°→5°.
--   B. Programas con empleabilidad de 2° año nula (< 25 casos en sus cohortes): no entran
--      en la dispersión del 2° año (D1).
-- Si los excluidos son chicos y parecidos al resto, el hueco es ruido; si se concentran en
-- un segmento o tienen peor empleabilidad, es un sesgo que va a "Qué no dice".
--
-- Tamaño de cada programa = titulaciones SIES de la institución × genérica en las cohortes
-- del indicador afectado (desde modelo.cohorte; Derecho corrido +1 año, metodología).
-- Solo lectura. Uso: psql -X -f src/Analisis/sql/auditoria/01_pares_sin_dato.sql

\echo '== A. Pares sin estadística nacional: resumen por segmento =='
WITH v AS (  -- cohortes del ingreso: de la más antigua (5° año) a la más reciente (1er año)
    SELECT min(cohorte_desde) AS desde, max(cohorte_hasta) AS hasta
    FROM modelo.cohorte WHERE indicador LIKE 'ingreso_medio_%'
),
tam AS (
    SELECT t.codigo_institucion, t.clave_carrera_generica, sum(t.total_titulaciones) AS tit
    FROM modelo.titulacion t, v
    WHERE t.anio BETWEEN v.desde + (t.clave_carrera_generica = 'DERECHO')::int
                     AND v.hasta + (t.clave_carrera_generica = 'DERECHO')::int
    GROUP BY 1, 2
),
prog AS (
    SELECT p.tipo_institucion, g.nivel_carrera, p.clave_carrera_generica,
           e.clave_carrera_generica IS NULL AS sin_estadistica,
           coalesce(tam.tit, 0) AS tit
    FROM modelo.mifuturo_programa p
    JOIN modelo.carrera_generica g USING (clave_carrera_generica)
    LEFT JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
    LEFT JOIN tam USING (codigo_institucion, clave_carrera_generica)
)
SELECT tipo_institucion AS tipo, nivel_carrera AS nivel,
       count(DISTINCT (clave_carrera_generica, tipo_institucion)) FILTER (WHERE sin_estadistica) AS pares_sin,
       count(DISTINCT (clave_carrera_generica, tipo_institucion))                                AS pares,
       count(*) FILTER (WHERE sin_estadistica)                               AS programas_sin,
       count(*)                                                              AS programas,
       round(100.0 * sum(tit) FILTER (WHERE sin_estadistica) / nullif(sum(tit), 0), 1) AS pct_titulaciones_sin
FROM prog
GROUP BY ROLLUP ((tipo_institucion, nivel_carrera))
ORDER BY tipo_institucion NULLS LAST, nivel_carrera;

\echo '== A. Los pares sin estadística, del más grande al más chico =='
-- titulaciones_sies_par = todas las instituciones del tipo en el SIES, publicadas o no.
WITH v AS (
    SELECT min(cohorte_desde) AS desde, max(cohorte_hasta) AS hasta
    FROM modelo.cohorte WHERE indicador LIKE 'ingreso_medio_%'
),
par_sies AS (
    SELECT i.tipo_institucion, t.clave_carrera_generica, sum(t.total_titulaciones) AS tit
    FROM modelo.titulacion t
    JOIN modelo.institucion i USING (codigo_institucion)
    CROSS JOIN v
    WHERE t.anio BETWEEN v.desde + (t.clave_carrera_generica = 'DERECHO')::int
                     AND v.hasta + (t.clave_carrera_generica = 'DERECHO')::int
    GROUP BY 1, 2
)
SELECT p.tipo_institucion AS tipo, g.nombre AS carrera_generica, g.nivel_carrera AS nivel,
       count(*) AS instituciones_publicadas,
       max(ps.tit) AS titulaciones_sies_par,
       round(avg(p.empleabilidad_1er_anio), 1) AS empleabilidad_1er_anio_prom
FROM modelo.mifuturo_programa p
JOIN modelo.carrera_generica g USING (clave_carrera_generica)
LEFT JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
LEFT JOIN par_sies ps USING (tipo_institucion, clave_carrera_generica)
WHERE e.clave_carrera_generica IS NULL
GROUP BY p.tipo_institucion, g.nombre, g.nivel_carrera
ORDER BY titulaciones_sies_par DESC NULLS LAST;

\echo '== B. Empleabilidad de 2° año nula: perfil por segmento =='
-- Tamaño = titulaciones en las cohortes de la empleabilidad de 2° año.
WITH v AS (
    SELECT cohorte_desde AS desde, cohorte_hasta AS hasta
    FROM modelo.cohorte WHERE indicador = 'empleabilidad_2do_anio_institucion'
),
tam AS (
    SELECT t.codigo_institucion, t.clave_carrera_generica, sum(t.total_titulaciones) AS tit
    FROM modelo.titulacion t, v
    WHERE t.anio BETWEEN v.desde + (t.clave_carrera_generica = 'DERECHO')::int
                     AND v.hasta + (t.clave_carrera_generica = 'DERECHO')::int
    GROUP BY 1, 2
),
prog AS (
    SELECT p.tipo_institucion, g.nivel_carrera, p.empleabilidad_1er_anio,
           p.empleabilidad_2do_anio IS NULL AS nulo, coalesce(tam.tit, 0) AS tit
    FROM modelo.mifuturo_programa p
    JOIN modelo.carrera_generica g USING (clave_carrera_generica)
    LEFT JOIN tam USING (codigo_institucion, clave_carrera_generica)
)
SELECT tipo_institucion AS tipo, nivel_carrera AS nivel,
       count(*) FILTER (WHERE nulo) AS nulos, count(*) AS programas,
       round(100.0 * count(*) FILTER (WHERE nulo) / count(*), 1) AS pct_nulos,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY tit) FILTER (WHERE nulo)     AS mediana_tit_nulos,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY tit) FILTER (WHERE NOT nulo) AS mediana_tit_resto,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY empleabilidad_1er_anio) FILTER (WHERE nulo)::numeric, 1)     AS mediana_emp1_nulos,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY empleabilidad_1er_anio) FILTER (WHERE NOT nulo)::numeric, 1) AS mediana_emp1_resto
FROM prog
GROUP BY ROLLUP ((tipo_institucion, nivel_carrera))
ORDER BY tipo_institucion NULLS LAST, nivel_carrera;
