-- src/Analisis/sql/auditoria/03_titulados_vs_sies.sql
--
-- Pregunta doble, resuelta con un mismo cruce:
--   1. Título terminal: ¿qué titulaciones del SIES cuenta MiFuturo como "titulados"? La
--      metodología (Estadísticas por Carrera, línea 123) dice "personas que obtuvieron un
--      título profesional o técnico durante 2024", lo que sugiere excluir las licenciaturas
--      no conducentes; los planes de continuidad no se mencionan.
--   2. Confirmación del año: `anio` es el año de titulación (glosario SIES: "Año del proceso",
--      "titulaciones durante el año respectivo"; procesar.py convierte 'TIT_2025' en 2025).
--      Se compara además con los años vecinos porque sale de la misma consulta: anio = 2024
--      debería ser el que mejor calza con los "titulados 2024" de MiFuturo.
-- Método: para cada par (genérica × tipo) con titulados_2024 publicado, razón
-- MiFuturo / SIES bajo 3 filtros × 3 años. La combinación correcta debería dar una razón
-- cercana a 1 (algo menor: MiFuturo cuenta personas y el SIES titulaciones) y la mayor
-- proporción de pares dentro de ±10 %.
-- Solo lectura. Uso: psql -X -f src/Analisis/sql/auditoria/03_titulados_vs_sies.sql

\echo '== Razón MiFuturo / SIES por año y filtro (pares con titulados_2024 publicado) =='
WITH anio_mf AS (  -- año de "titulados" en MiFuturo (2024), desde modelo.cohorte
    SELECT cohorte_hasta AS anio FROM modelo.cohorte WHERE indicador = 'titulados_y_duracion'
),
filtro (filtro, orden) AS (VALUES
    ('todas', 1),
    ('sin licenciatura no conducente', 2),
    ('sin LNC ni plan de continuidad', 3)
),
sies AS (
    SELECT f.filtro, f.orden, t.anio, i.tipo_institucion, t.clave_carrera_generica,
           sum(t.total_titulaciones) AS tit
    FROM modelo.titulacion t
    JOIN modelo.institucion i USING (codigo_institucion)
    CROSS JOIN filtro f
    CROSS JOIN anio_mf a
    WHERE t.anio BETWEEN a.anio - 1 AND a.anio + 1   -- candidatos a ser el "2024" de MiFuturo
      AND (f.orden = 1
           OR (f.orden = 2 AND t.carrera_clasificacion_nivel_1 <> 'Licenciatura No Conducente a Título')
           OR (f.orden = 3 AND t.carrera_clasificacion_nivel_1 <> 'Licenciatura No Conducente a Título'
                           AND t.tipo_plan <> 'Plan Regular de Continuidad'))
    GROUP BY 1, 2, 3, 4, 5
),
par AS (
    SELECT s.filtro, s.orden, s.anio, e.titulados_2024::numeric / s.tit AS razon,
           e.titulados_2024, s.tit
    FROM modelo.mifuturo_estadistica e
    JOIN sies s USING (tipo_institucion, clave_carrera_generica)
    WHERE e.titulados_2024 IS NOT NULL AND s.tit > 0
)
SELECT anio, filtro, count(*) AS pares,
       round(sum(titulados_2024)::numeric / sum(tit), 3) AS razon_total,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY razon)::numeric, 3) AS razon_mediana,
       round(100.0 * count(*) FILTER (WHERE razon BETWEEN 0.9 AND 1.1) / count(*), 1) AS pct_pares_10pct
FROM par
GROUP BY anio, filtro, orden
ORDER BY anio, orden;

\echo '== Mismo cruce con el año de MiFuturo (2024), por tipo de institución =='
-- Si el filtro correcto difiere por tipo (p. ej. continuidad solo en universidades), se ve aquí.
WITH sies AS (
    SELECT i.tipo_institucion, t.clave_carrera_generica,
           sum(t.total_titulaciones) AS todas,
           sum(t.total_titulaciones) FILTER (WHERE t.carrera_clasificacion_nivel_1 <> 'Licenciatura No Conducente a Título') AS sin_lnc,
           sum(t.total_titulaciones) FILTER (WHERE t.carrera_clasificacion_nivel_1 <> 'Licenciatura No Conducente a Título'
                                               AND t.tipo_plan <> 'Plan Regular de Continuidad') AS sin_lnc_ni_cont
    FROM modelo.titulacion t
    JOIN modelo.institucion i USING (codigo_institucion)
    WHERE t.anio = (SELECT cohorte_hasta FROM modelo.cohorte WHERE indicador = 'titulados_y_duracion')
    GROUP BY 1, 2
)
SELECT e.tipo_institucion AS tipo, count(*) AS pares,
       round(sum(e.titulados_2024)::numeric / sum(s.todas), 3)           AS razon_todas,
       round(sum(e.titulados_2024)::numeric / sum(s.sin_lnc), 3)         AS razon_sin_lnc,
       round(sum(e.titulados_2024)::numeric / sum(s.sin_lnc_ni_cont), 3) AS razon_sin_lnc_ni_cont
FROM modelo.mifuturo_estadistica e
JOIN sies s USING (tipo_institucion, clave_carrera_generica)
WHERE e.titulados_2024 IS NOT NULL
GROUP BY ROLLUP (e.tipo_institucion)
ORDER BY 1 NULLS LAST;
