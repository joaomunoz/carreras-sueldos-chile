-- src/Analisis/sql/auditoria/05_serie_anual_sies.sql
--
-- Pregunta: ¿cada año del SIES está completo y es comparable con los demás? En especial
-- 2025, el último archivo (TIT_2025): si fuera preliminar, faltarían instituciones o
-- programas y cualquier conteo de oferta que lo use quedaría bajo. También muestra 2020
-- (pandemia), que entra en las cohortes del 2°-4° año.
-- Señales de año incompleto: caída de instituciones que titulan, más programas que
-- "desaparecen" que en años anteriores, o un tipo de institución que cae solo.
-- No usa modelo.cohorte: recorre todos los años del SIES, sin elegir una ventana.
-- Solo lectura. Uso: psql -X -f src/Analisis/sql/auditoria/05_serie_anual_sies.sql

\echo '== Titulaciones, programas e instituciones por año =='
SELECT anio,
       sum(total_titulaciones) AS titulaciones,
       -- ::numeric antes de dividir: entre enteros PostgreSQL trunca (daría 0 o -100).
       round(100.0 * (sum(total_titulaciones)::numeric / lag(sum(total_titulaciones)) OVER (ORDER BY anio) - 1), 1) AS var_pct,
       count(*) AS programas,
       count(DISTINCT codigo_institucion) AS instituciones,
       round(100.0 * sum(total_titulaciones) FILTER (WHERE carrera_clasificacion_nivel_1 = 'Licenciatura No Conducente a Título')
             / sum(total_titulaciones), 1) AS pct_lnc,
       round(100.0 * sum(titulados_edad_sin_info) / sum(total_titulaciones), 1) AS pct_edad_sin_info
FROM modelo.titulacion
GROUP BY anio
ORDER BY anio;

\echo '== Titulaciones por tipo de institución y año (variación % anual) =='
WITH x AS (
    SELECT t.anio, i.tipo_institucion, sum(t.total_titulaciones) AS tit
    FROM modelo.titulacion t
    JOIN modelo.institucion i USING (codigo_institucion)
    GROUP BY 1, 2
)
SELECT anio,
       max(tit) FILTER (WHERE tipo_institucion = 'Universidad') AS universidad,
       max(tit) FILTER (WHERE tipo_institucion = 'IP')          AS ip,
       max(tit) FILTER (WHERE tipo_institucion = 'CFT')         AS cft,
       round(100.0 * (max(tit) FILTER (WHERE tipo_institucion = 'Universidad')::numeric
             / lag(max(tit) FILTER (WHERE tipo_institucion = 'Universidad')) OVER w - 1), 1) AS var_u,
       round(100.0 * (max(tit) FILTER (WHERE tipo_institucion = 'IP')::numeric
             / lag(max(tit) FILTER (WHERE tipo_institucion = 'IP')) OVER w - 1), 1) AS var_ip,
       round(100.0 * (max(tit) FILTER (WHERE tipo_institucion = 'CFT')::numeric
             / lag(max(tit) FILTER (WHERE tipo_institucion = 'CFT')) OVER w - 1), 1) AS var_cft
FROM x
GROUP BY anio
WINDOW w AS (ORDER BY anio)
ORDER BY anio;

\echo '== Rotación: institución × genérica que titula un año y no el siguiente =='
-- Si 2024→2025 muestra bastante más salidas que los pares de años anteriores, 2025 está
-- incompleto (o hubo cierres reales, que se distinguen mirando si reaparecen después).
WITH par AS (
    SELECT DISTINCT anio, codigo_institucion, clave_carrera_generica
    FROM modelo.titulacion
    WHERE total_titulaciones > 0
)
SELECT a.anio AS desde, a.anio + 1 AS hasta,
       count(*) AS pares_desde,
       count(*) FILTER (WHERE b.anio IS NULL) AS no_titulan_al_anio_siguiente,
       round(100.0 * count(*) FILTER (WHERE b.anio IS NULL) / count(*), 1) AS pct_salida
FROM par a
LEFT JOIN par b
  ON b.anio = a.anio + 1
 AND b.codigo_institucion = a.codigo_institucion
 AND b.clave_carrera_generica = a.clave_carrera_generica
WHERE a.anio < (SELECT max(anio) FROM modelo.titulacion)
GROUP BY a.anio
ORDER BY a.anio;
