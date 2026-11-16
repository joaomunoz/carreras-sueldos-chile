-- src/Analisis/sql/auditoria/04_area_dominante.sql
--
-- Pregunta: ¿se puede asignar a cada carrera genérica UNA área cine13 sin forzar los datos?
-- Decisión aprobada en T0: área = la dominante por titulaciones, con umbral de 80 %; bajo el
-- umbral la genérica se marca y no sirve de referencia del área (D2). Esta consulta muestra
-- qué genéricas quedan bajo el umbral y si están en MiFuturo, separando dónde: con estadística
-- nacional (afecta la brecha 1°→5°) o solo con programas por institución (afecta D1).
-- Ventana: todas las cohortes de los indicadores de MiFuturo usados en el análisis (sin las
-- series, por D5), desde modelo.cohorte.
-- La dominancia se calcula por genérica (no por par genérica × tipo) porque el área es un
-- atributo de la carrera; la segunda consulta revisa si cambia por tipo de institución.
-- Solo lectura. Uso: psql -X -f src/Analisis/sql/auditoria/04_area_dominante.sql

\echo '== Genéricas con más de un área cine13 (umbral 80 %) =='
WITH v AS (
    SELECT min(cohorte_desde) AS desde, max(cohorte_hasta) AS hasta
    FROM modelo.cohorte
    WHERE fuente IN ('Empleabilidad', 'Estadisticas') AND indicador NOT LIKE 'serie\_%'
),
por_area AS (
    SELECT t.clave_carrera_generica, t.cine13_area, sum(t.total_titulaciones) AS tit
    FROM modelo.titulacion t, v
    WHERE t.anio BETWEEN v.desde AND v.hasta
    GROUP BY 1, 2
),
dominante AS (
    SELECT clave_carrera_generica,
           count(*) AS n_areas,
           (array_agg(cine13_area ORDER BY tit DESC, cine13_area))[1] AS area_dominante,
           max(tit)::numeric / sum(tit) AS share
    FROM por_area
    GROUP BY 1
)
SELECT g.nombre AS carrera_generica, d.n_areas, d.area_dominante,
       round(100 * d.share, 1) AS pct_dominante,
       CASE WHEN d.share >= 0.8 THEN 'asignable' ELSE 'BAJO UMBRAL' END AS regla_80,
       EXISTS (SELECT 1 FROM modelo.mifuturo_estadistica e
               WHERE e.clave_carrera_generica = d.clave_carrera_generica) AS con_estadistica,
       EXISTS (SELECT 1 FROM modelo.mifuturo_programa p
               WHERE p.clave_carrera_generica = d.clave_carrera_generica) AS con_programas
FROM dominante d
JOIN modelo.carrera_generica g USING (clave_carrera_generica)
WHERE d.n_areas > 1
ORDER BY con_estadistica DESC, con_programas DESC, d.share;

\echo '== Genéricas de MiFuturo cuya área dominante cambia según el tipo de institución =='
WITH v AS (
    SELECT min(cohorte_desde) AS desde, max(cohorte_hasta) AS hasta
    FROM modelo.cohorte
    WHERE fuente IN ('Empleabilidad', 'Estadisticas') AND indicador NOT LIKE 'serie\_%'
),
por_area AS (
    SELECT i.tipo_institucion, t.clave_carrera_generica, t.cine13_area, sum(t.total_titulaciones) AS tit
    FROM modelo.titulacion t
    JOIN modelo.institucion i USING (codigo_institucion)
    CROSS JOIN v
    WHERE t.anio BETWEEN v.desde AND v.hasta
    GROUP BY 1, 2, 3
),
dominante_tipo AS (
    SELECT tipo_institucion, clave_carrera_generica,
           (array_agg(cine13_area ORDER BY tit DESC, cine13_area))[1] AS area
    FROM por_area
    GROUP BY 1, 2
)
SELECT g.nombre AS carrera_generica,
       string_agg(dt.tipo_institucion || ': ' || dt.area, ' | ' ORDER BY dt.tipo_institucion) AS area_por_tipo
FROM dominante_tipo dt
JOIN modelo.carrera_generica g USING (clave_carrera_generica)
JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
GROUP BY g.nombre
HAVING count(DISTINCT dt.area) > 1
ORDER BY 1;
