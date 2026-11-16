-- src/Analisis/sql/auditoria/06_cobertura_celdas.sql
--
-- T5, gate a la Fase 2. Pregunta: ¿cuántos pares (carrera genérica × tipo) y cuántas celdas
-- de segmentación soportan cada análisis con las reglas aprobadas?
--   - Representatividad (decisión "dos conteos"): un par entra en rankings, referencias y
--     cuadrantes si n_inst_oferta >= 3 = instituciones del tipo con titulaciones SIES de esa
--     genérica en AMBAS ventanas comparadas (cohortes de la media del 1er año y del 5° año).
--   - Brecha 1°→5°: además, ingreso completo (media 1°-5° y percentiles de los años 1 y 5).
--   - Referencia por área (D2): celda cine13_area × tipo × nivel válida con >= 5 pares
--     representativos; si no, sus pares se comparan con su segmento tipo × nivel.
--     Área = la dominante de la genérica por titulaciones, asignable si >= 80 % (T0, T4).
--   - Dispersión entre instituciones (D1): n_inst_publicadas >= 5 = instituciones con el dato
--     en MiFuturo, contado por indicador (empleabilidad 1er año, 2° año y tramo del 4° año),
--     porque los nulos difieren entre ellos.
-- Umbrales en el CTE `param` de la vista: se cambian en un solo lugar.
-- Ventanas desde modelo.cohorte (Derecho +1 año).
--
-- Crea una vista TEMPORAL (vive solo en esta sesión de psql; no modifica la base) para no
-- repetir la definición del par en las 4 consultas. En la Fase 2 esta lógica pasa a
-- `analytics` como tabla permanente con su control qa.
-- Uso: psql -X -f src/Analisis/sql/auditoria/06_cobertura_celdas.sql

CREATE TEMP VIEW par_cobertura AS
WITH param AS (
    SELECT 3 AS min_inst_oferta, 5 AS min_inst_dispersion, 0.80 AS min_share_area, 5 AS min_pares_celda
),
c1 AS (SELECT cohorte_desde AS desde, cohorte_hasta AS hasta FROM modelo.cohorte WHERE indicador = 'ingreso_medio_1er_anio'),
c5 AS (SELECT cohorte_desde AS desde, cohorte_hasta AS hasta FROM modelo.cohorte WHERE indicador = 'ingreso_medio_5to_anio'),
-- Institución × genérica con titulaciones en las dos ventanas (Derecho corrido +1).
oferta AS (
    SELECT i.tipo_institucion, t.clave_carrera_generica, t.codigo_institucion
    FROM modelo.titulacion t
    JOIN modelo.institucion i USING (codigo_institucion)
    CROSS JOIN c1 CROSS JOIN c5
    GROUP BY 1, 2, 3
    HAVING sum(t.total_titulaciones) FILTER (
               WHERE t.anio BETWEEN c1.desde + (t.clave_carrera_generica = 'DERECHO')::int
                                AND c1.hasta + (t.clave_carrera_generica = 'DERECHO')::int) > 0
       AND sum(t.total_titulaciones) FILTER (
               WHERE t.anio BETWEEN c5.desde + (t.clave_carrera_generica = 'DERECHO')::int
                                AND c5.hasta + (t.clave_carrera_generica = 'DERECHO')::int) > 0
),
-- Área dominante de la genérica en todas las cohortes de los indicadores usados (sin series, D5).
v AS (
    SELECT min(cohorte_desde) AS desde, max(cohorte_hasta) AS hasta FROM modelo.cohorte
    WHERE fuente IN ('Empleabilidad', 'Estadisticas') AND indicador NOT LIKE 'serie\_%'
),
por_area AS (
    SELECT t.clave_carrera_generica, t.cine13_area, sum(t.total_titulaciones) AS tit
    FROM modelo.titulacion t, v
    WHERE t.anio BETWEEN v.desde AND v.hasta
    GROUP BY 1, 2
),
area AS (
    SELECT clave_carrera_generica,
           (array_agg(cine13_area ORDER BY tit DESC, cine13_area))[1] AS area,
           max(tit)::numeric / sum(tit) AS share
    FROM por_area GROUP BY 1
),
publicadas AS (
    SELECT clave_carrera_generica, tipo_institucion,
           count(*)                                          AS n_emp1,
           count(empleabilidad_2do_anio)                     AS n_emp2,
           count(ingreso_4to_anio_tramo_min)                 AS n_tramo
    FROM modelo.mifuturo_programa GROUP BY 1, 2
)
SELECT e.clave_carrera_generica, g.nombre, e.tipo_institucion, g.nivel_carrera,
       a.area, round(100 * a.share, 1) AS pct_area,
       a.share >= p.min_share_area AS area_asignable,
       num_nonnulls(e.ingreso_medio_1er_anio, e.ingreso_medio_2do_anio, e.ingreso_medio_3er_anio,
                    e.ingreso_medio_4to_anio, e.ingreso_medio_5to_anio,
                    e.percentil_10_anio_1, e.percentil_25_anio_1, e.percentil_50_anio_1,
                    e.percentil_75_anio_1, e.percentil_90_anio_1,
                    e.percentil_10_anio_5, e.percentil_25_anio_5, e.percentil_50_anio_5,
                    e.percentil_75_anio_5, e.percentil_90_anio_5) = 15 AS ingreso_completo,
       (SELECT count(*) FROM oferta o
        WHERE o.tipo_institucion = e.tipo_institucion
          AND o.clave_carrera_generica = e.clave_carrera_generica) AS n_inst_oferta,
       coalesce(pu.n_emp1, 0)  AS n_pub_emp1,
       coalesce(pu.n_emp2, 0)  AS n_pub_emp2,
       coalesce(pu.n_tramo, 0) AS n_pub_tramo,
       p.min_inst_oferta, p.min_inst_dispersion, p.min_pares_celda,
       e.clave_carrera_generica = 'DERECHO' AS es_derecho
FROM modelo.mifuturo_estadistica e
JOIN modelo.carrera_generica g USING (clave_carrera_generica)
JOIN area a USING (clave_carrera_generica)
LEFT JOIN publicadas pu USING (clave_carrera_generica, tipo_institucion)
CROSS JOIN param p;

\echo '== 1. Embudo por segmento tipo × nivel (pares de la estadística nacional) =='
SELECT tipo_institucion AS tipo, nivel_carrera AS nivel,
       count(*)                                                        AS pares,
       count(*) FILTER (WHERE ingreso_completo)                        AS con_ingreso,
       count(*) FILTER (WHERE ingreso_completo AND n_inst_oferta >= min_inst_oferta) AS representativos,
       count(*) FILTER (WHERE ingreso_completo AND n_inst_oferta >= min_inst_oferta
                          AND area_asignable)                          AS repr_area_asignable,
       count(*) FILTER (WHERE n_pub_emp1  >= min_inst_dispersion)      AS disp_emp1,
       count(*) FILTER (WHERE n_pub_emp2  >= min_inst_dispersion)      AS disp_emp2,
       count(*) FILTER (WHERE n_pub_tramo >= min_inst_dispersion)      AS disp_tramo
FROM par_cobertura
GROUP BY ROLLUP ((tipo_institucion, nivel_carrera))
ORDER BY tipo_institucion NULLS LAST, nivel_carrera;

\echo '== 2. Celdas área × tipo × nivel: válidas como referencia (D2) =='
SELECT area, tipo_institucion AS tipo, nivel_carrera AS nivel,
       count(*) FILTER (WHERE ingreso_completo AND n_inst_oferta >= min_inst_oferta) AS pares_repr,
       count(*) AS pares_total,
       CASE WHEN count(*) FILTER (WHERE ingreso_completo AND n_inst_oferta >= min_inst_oferta) >= max(min_pares_celda)
            THEN 'válida' ELSE 'usa segmento' END AS celda
FROM par_cobertura
WHERE area_asignable
GROUP BY area, tipo_institucion, nivel_carrera
ORDER BY tipo_institucion, nivel_carrera, pares_repr DESC, area;

\echo '== 3. Resumen de celdas por segmento =='
WITH celda AS (
    SELECT tipo_institucion, nivel_carrera, area,
           count(*) FILTER (WHERE ingreso_completo AND n_inst_oferta >= min_inst_oferta) AS pares_repr,
           max(min_pares_celda) AS min_pares_celda
    FROM par_cobertura WHERE area_asignable
    GROUP BY 1, 2, 3
)
SELECT tipo_institucion AS tipo, nivel_carrera AS nivel,
       count(*) AS celdas,
       count(*) FILTER (WHERE pares_repr >= min_pares_celda) AS celdas_validas,
       sum(pares_repr) FILTER (WHERE pares_repr >= min_pares_celda) AS pares_en_celda_valida,
       sum(pares_repr) AS pares_repr
FROM celda
GROUP BY ROLLUP ((tipo_institucion, nivel_carrera))
ORDER BY tipo_institucion NULLS LAST, nivel_carrera;

\echo '== 4. Pares con ingreso completo fuera por representatividad (n_inst_oferta < 3) =='
SELECT tipo_institucion AS tipo, nivel_carrera AS nivel, nombre AS carrera_generica,
       n_inst_oferta, n_pub_emp1 AS inst_publicadas, es_derecho
FROM par_cobertura
WHERE ingreso_completo AND n_inst_oferta < min_inst_oferta
ORDER BY tipo_institucion, nivel_carrera, n_inst_oferta, nombre;
