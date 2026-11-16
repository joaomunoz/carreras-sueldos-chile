-- src/Analisis/sql/auditoria/02_cobertura_mifuturo.sql
--
-- Pregunta: ¿qué parte de la oferta real (SIES) representan los programas que MiFuturo
-- publica por institución, y cambia entre la cohorte del 1er año y la del 5° año?
-- Mide el hallazgo A de T0 (sesgo de selección y supervivencia) por segmento tipo × nivel:
--   - selección: MiFuturo solo publica institución × genérica con >= 25 casos;
--   - supervivencia: publica los programas que hoy titulan; los que titularon en 2017-2019 y
--     ya cerraron no aparecen, así que la cobertura de la cohorte del 5° año debería ser menor.
-- Unidad SIES: titulaciones de todo tipo (decisión "ponderador = todas"; MiFuturo incluye
-- licenciaturas no conducentes). Las genéricas que MiFuturo no publica en absoluto (las 4
-- omitidas, "Otros/Otras") cuentan como no cubiertas, pero se informan aparte.
-- Ventanas desde modelo.cohorte (Derecho +1 año): 1er año = empleabilidad_1er_anio_institucion,
-- 5° año = ingreso_medio_5to_anio.
-- Solo lectura. Uso: psql -X -f src/Analisis/sql/auditoria/02_cobertura_mifuturo.sql

\echo '== Cobertura por ventana de cohorte y segmento =='
WITH ventana (ventana, indicador) AS (VALUES
    ('1er año', 'empleabilidad_1er_anio_institucion'),
    ('5° año',  'ingreso_medio_5to_anio')
),
oferta AS (  -- institución × genérica con titulaciones en la ventana
    SELECT w.ventana, i.tipo_institucion, g.nivel_carrera,
           t.codigo_institucion, t.clave_carrera_generica,
           sum(t.total_titulaciones) AS tit
    FROM ventana w
    JOIN modelo.cohorte c USING (indicador)
    JOIN modelo.titulacion t
      ON t.anio BETWEEN c.cohorte_desde + (t.clave_carrera_generica = 'DERECHO')::int
                    AND c.cohorte_hasta + (t.clave_carrera_generica = 'DERECHO')::int
    JOIN modelo.institucion i USING (codigo_institucion)
    JOIN modelo.carrera_generica g USING (clave_carrera_generica)
    GROUP BY 1, 2, 3, 4, 5
),
marcado AS (
    SELECT o.*,
           p.codigo_institucion IS NOT NULL AS publicado,
           EXISTS (SELECT 1 FROM modelo.mifuturo_programa x
                   WHERE x.clave_carrera_generica = o.clave_carrera_generica) AS generica_en_mifuturo
    FROM oferta o
    LEFT JOIN modelo.mifuturo_programa p USING (codigo_institucion, clave_carrera_generica)
)
SELECT ventana, tipo_institucion AS tipo, nivel_carrera AS nivel,
       count(*) FILTER (WHERE publicado) AS pares_pub,
       count(*)                          AS pares_sies,
       round(100.0 * count(*) FILTER (WHERE publicado) / count(*), 1) AS pct_pares,
       round(100.0 * sum(tit) FILTER (WHERE publicado) / sum(tit), 1) AS pct_tit,
       round(100.0 * sum(tit) FILTER (WHERE NOT generica_en_mifuturo) / sum(tit), 1) AS pct_tit_generica_no_publicada,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY tit) FILTER (WHERE publicado)     AS mediana_tit_pub,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY tit) FILTER (WHERE NOT publicado) AS mediana_tit_no_pub
FROM marcado
GROUP BY ventana, ROLLUP ((tipo_institucion, nivel_carrera))
ORDER BY ventana, tipo_institucion NULLS LAST, nivel_carrera;

\echo '== Supervivencia: programas publicados hoy que no titularon en la ventana del 5° año =='
-- Lado opuesto: un programa nuevo (sin titulados 2017-2019) entra en los datos por institución
-- pero no aporta a la cohorte del 5° año. Cuántos son, por segmento.
WITH c5 AS (SELECT cohorte_desde, cohorte_hasta FROM modelo.cohorte WHERE indicador = 'ingreso_medio_5to_anio')
SELECT p.tipo_institucion AS tipo, g.nivel_carrera AS nivel,
       count(*) FILTER (WHERE NOT EXISTS (
           SELECT 1 FROM modelo.titulacion t, c5
           WHERE t.codigo_institucion = p.codigo_institucion
             AND t.clave_carrera_generica = p.clave_carrera_generica
             AND t.anio BETWEEN c5.cohorte_desde + (t.clave_carrera_generica = 'DERECHO')::int
                            AND c5.cohorte_hasta + (t.clave_carrera_generica = 'DERECHO')::int)) AS sin_titulados_ventana_5,
       count(*) AS programas_publicados
FROM modelo.mifuturo_programa p
JOIN modelo.carrera_generica g USING (clave_carrera_generica)
GROUP BY ROLLUP ((p.tipo_institucion, g.nivel_carrera))
ORDER BY 1 NULLS LAST, 2;
