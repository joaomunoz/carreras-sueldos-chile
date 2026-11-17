-- src/Analisis/sql/analytics/06_exportacion.sql
--
-- A6 (Fase 2): todo lo que la web necesita, armado como UN documento JSON en la base
-- (vista analytics.v_datos_json). src/Analisis/exportar.py solo lo valida y lo escribe en
-- docs/datos.json: la lógica y el redondeo de presentación viven en SQL, junto al resto del
-- análisis, y el JSON no puede contradecir a las tablas.
--
-- Redondeo (solo presentación; las tablas guardan valores sin redondear):
--   pesos → enteros; porcentajes y puntos → 1 decimal; razones → 3 decimales; asimetría → 2.
-- Orden: todo json_agg lleva ORDER BY, para que dos exportaciones seguidas sean idénticas.
-- json_build_object (no jsonb) conserva el orden de las claves tal como se escriben.
--
-- Agrega además la marca de COMPOSICIÓN POR EDAD (hallazgo de A5): la cohorte de los
-- percentiles del 1er año (2023) tiene >= min_cambio_edad_pp puntos más de titulados de 30 años o
-- más que la del 5° año (2019), cota alta del rango. Sensibilidad revisada en A6: 10 pp marca 50
-- pares, 15 pp 27 (≈ decil superior; capta 7 de los 13 con P50 1→5 negativo), 20 pp 10.
-- Requiere 01 a 05.

INSERT INTO analytics.parametro VALUES
    ('min_cambio_edad_pp', 15, 'Aumento (puntos) de titulados de 30+ entre la cohorte de los percentiles del 5° año y la del 1er año para marcar la comparación 1°→5° como sesgada por composición', 'A6 (hallazgo de A5)');

-- --------------------------------------------------------------------------
-- Un objeto por par, con todo lo que muestra la ficha por carrera
-- --------------------------------------------------------------------------
CREATE VIEW analytics.v_par_json AS
SELECT p.clave_carrera_generica, p.tipo_institucion,
       json_build_object(
    'clave', p.clave_carrera_generica,
    'nombre', p.nombre,
    'tipo', p.tipo_institucion,
    'nivel', p.nivel_carrera,
    'area', json_build_object('cine13', p.area_cine13, 'pct_dominante', round(100 * p.share_area, 1),
                              'asignable', p.area_asignable),
    'marcas', json_build_object(
        'representativo', p.representativo,
        'referencia', p.referencia,
        'grupo_referencia', po.grupo_id,
        'baja_cobertura', p.baja_cobertura,
        'es_derecho', p.es_derecho,
        'cohorte_atipica', coalesce(es.atipica, false),
        'composicion_edad', coalesce((c.mayores30_max_p1 - c.mayores30_max_p5) * 100
                                     >= analytics.param('min_cambio_edad_pp'), false),
        'promedio_enganoso', coalesce(de1.promedio_enganoso, false)),
    'conteos', json_build_object('n_inst_oferta', p.n_inst_oferta, 'n_pub_emp1', p.n_pub_emp1,
                                 'n_pub_emp2', p.n_pub_emp2, 'n_pub_tramo', p.n_pub_tramo,
                                 'peso', p.peso),
    'media', json_build_object(
        'anio', json_build_array(e.ingreso_medio_1er_anio, e.ingreso_medio_2do_anio, e.ingreso_medio_3er_anio,
                                 e.ingreso_medio_4to_anio, e.ingreso_medio_5to_anio),
        'delta_1_5', round(b.media_delta_1_5), 'razon_1_5', round(b.media_razon_1_5, 3),
        'pct_1_5', round(b.media_pct_1_5, 1),
        'pct_hitos', json_build_array(round(b.media_pct_1_2, 1), round(b.media_pct_2_3, 1),
                                      round(b.media_pct_3_4, 1), round(b.media_pct_4_5, 1))),
    'percentiles', json_build_object(
        'anio_1', json_build_object('p10', e.percentil_10_anio_1, 'p25', e.percentil_25_anio_1,
                                    'p50', e.percentil_50_anio_1, 'p75', e.percentil_75_anio_1,
                                    'p90', e.percentil_90_anio_1),
        'anio_5', json_build_object('p10', e.percentil_10_anio_5, 'p25', e.percentil_25_anio_5,
                                    'p50', e.percentil_50_anio_5, 'p75', e.percentil_75_anio_5,
                                    'p90', e.percentil_90_anio_5),
        'p50_delta_1_5', round(b.p50_delta_1_5), 'p50_razon_1_5', round(b.p50_razon_1_5, 3),
        'p50_pct_1_5', round(b.p50_pct_1_5, 1),
        'p25_pct_1_5', round(b.p25_pct_1_5, 1), 'p75_pct_1_5', round(b.p75_pct_1_5, 1),
        'p90_pct_1_5', round(b.p90_pct_1_5, 1),
        'iqr', json_build_array(round(b.iqr_1), round(b.iqr_5)),
        'iqr_rel', json_build_array(round(b.iqr_rel_1, 3), round(b.iqr_rel_5, 3)),
        'p90_p50', json_build_array(round(b.p90_p50_1, 3), round(b.p90_p50_5, 3)),
        'asimetria', json_build_array(round(b.asimetria_1, 2), round(b.asimetria_5, 2))),
    'posicion', CASE WHEN po.clave_carrera_generica IS NULL THEN NULL ELSE json_build_object(
        'cuartil_p50_anio_1', po.cuartil_p50_anio_1, 'cuartil_p50_pct_1_5', po.cuartil_p50_pct_1_5,
        'cuartil_p50_delta_1_5', po.cuartil_p50_delta_1_5,
        'cuadrante_pct', po.cuadrante_pct, 'cuadrante_pesos', po.cuadrante_pesos,
        'cambia_cuadrante', po.cambia_cuadrante) END,
    'empleabilidad_nacional', json_build_array(e.empleabilidad_1er_anio, e.empleabilidad_2do_anio),
    'duracion', json_build_object('formal', e.duracion_formal_semestres, 'real', e.duracion_real_semestres),
    'titulados_2024', json_build_object('total', e.titulados_2024, 'mujeres', e.titulados_2024_mujeres,
                                        'hombres', e.titulados_2024_hombres),
    'contexto', json_build_object(
        'pct_mujeres', json_build_array(round(100 * c.pct_mujeres_1, 1), round(100 * c.pct_mujeres_5, 1)),
        'fuera30_rango', json_build_array(round(100 * c.fuera30_min_1, 1), round(100 * c.fuera30_max_1, 1)),
        'pct_plan_continuidad', round(100 * c.pct_plan_continuidad_1, 1),
        'oferta_joven', json_build_array(c.jovenes_5, c.jovenes_1),
        'var_oferta_joven_pct', round(100 * c.var_oferta_joven, 1),
        'mayores30_cohorte_p5', json_build_array(round(100 * c.mayores30_min_p5, 1), round(100 * c.mayores30_max_p5, 1)),
        'mayores30_cohorte_p1', json_build_array(round(100 * c.mayores30_min_p1, 1), round(100 * c.mayores30_max_p1, 1))),
    'estabilidad', CASE WHEN es.clave_carrera_generica IS NULL THEN NULL ELSE json_build_object(
        'cohorte', es.cohorte, 'empleabilidad', es.empleabilidad_cohorte,
        'media_previas', round(es.media_previas, 1), 'desvio', round(es.desvio, 1)) END,
    'dispersion', json_build_object(
        'emp1', (SELECT json_build_object('n_inst', d.n_inst, 'min', d.minimo, 'q1', round(d.q1::numeric, 1),
                                          'mediana', round(d.mediana::numeric, 1), 'q3', round(d.q3::numeric, 1),
                                          'max', d.maximo, 'iqr', round(d.iqr::numeric, 1),
                                          'nacional_menos_mediana', round(d.nacional_menos_mediana::numeric, 1))
                 FROM analytics.dispersion_empleabilidad d
                 WHERE d.clave_carrera_generica = p.clave_carrera_generica
                   AND d.tipo_institucion = p.tipo_institucion AND d.anio = 1),
        'emp2', (SELECT json_build_object('n_inst', d.n_inst, 'min', d.minimo, 'q1', round(d.q1::numeric, 1),
                                          'mediana', round(d.mediana::numeric, 1), 'q3', round(d.q3::numeric, 1),
                                          'max', d.maximo, 'iqr', round(d.iqr::numeric, 1),
                                          'nacional_menos_mediana', round(d.nacional_menos_mediana::numeric, 1))
                 FROM analytics.dispersion_empleabilidad d
                 WHERE d.clave_carrera_generica = p.clave_carrera_generica
                   AND d.tipo_institucion = p.tipo_institucion AND d.anio = 2),
        'tramo', (SELECT json_build_object('n_inst', t.n_inst, 'min_inferior', t.tramo_min_inferior,
                                           'min_superior', t.tramo_min_superior, 'max_superior', t.tramo_max_superior,
                                           'amplitud', t.amplitud, 'mediana_min', t.mediana_tramo_min,
                                           'tramos_distintos', t.n_tramos_distintos,
                                           'bajo_igual_sobre', json_build_array(t.n_bajo, t.n_igual, t.n_sobre),
                                           'nacional_4to', t.nacional_4to)
                  FROM analytics.dispersion_tramo t
                  WHERE t.clave_carrera_generica = p.clave_carrera_generica
                    AND t.tipo_institucion = p.tipo_institucion))
       ) AS datos
FROM analytics.par p
JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
LEFT JOIN analytics.brecha b USING (clave_carrera_generica, tipo_institucion)
LEFT JOIN analytics.posicion po USING (clave_carrera_generica, tipo_institucion)
LEFT JOIN analytics.contexto c USING (clave_carrera_generica, tipo_institucion)
LEFT JOIN analytics.estabilidad es USING (clave_carrera_generica, tipo_institucion)
LEFT JOIN analytics.dispersion_empleabilidad de1
       ON de1.clave_carrera_generica = p.clave_carrera_generica
      AND de1.tipo_institucion = p.tipo_institucion AND de1.anio = 1;

-- --------------------------------------------------------------------------
-- El documento completo
-- --------------------------------------------------------------------------
CREATE VIEW analytics.v_datos_json AS
SELECT json_build_object(
    'meta', json_build_object(
        'proyecto', 'Trayectoria salarial y riesgo institucional por carrera en Chile (1er vs. 5° año de titulación)',
        'fuentes', json_build_array(
            'MiFuturo: Buscador de Empleabilidad e Ingresos y Buscador de Estadísticas por Carrera (metodologías 2025-2026)',
            'SIES: Titulados 2017-2025'),
        'unidad_ingresos', 'pesos de septiembre de 2025; ingreso bruto mensual; solo titulados con ingreso >= sueldo mínimo',
        'comparacion', 'transversal: el 1er y el 5° año son cohortes distintas, no las mismas personas',
        'rotulo_empleabilidad', '% con ingreso >= sueldo mínimo entre titulados con registro en el SII'),
    'parametros', (SELECT json_agg(json_build_object('nombre', nombre, 'valor', valor,
                                                     'descripcion', descripcion, 'origen', origen) ORDER BY nombre)
                   FROM analytics.parametro),
    'cohortes', (SELECT json_agg(json_build_object('indicador', indicador, 'fuente', fuente,
                                                   'cohortes', json_build_array(cohorte_desde, cohorte_hasta),
                                                   'anios_ingreso', json_build_array(anio_ingreso_desde, anio_ingreso_hasta),
                                                   'min_casos', min_casos, 'referencia', referencia) ORDER BY indicador)
                 FROM modelo.cohorte),
    'hitos', (SELECT json_agg(json_build_object('anio', anio_k, 'cohortes', json_build_array(cohorte_desde, cohorte_hasta),
                                                'incluye_caida', incluye_caida, 'incluye_rebote', incluye_rebote) ORDER BY anio_k)
              FROM analytics.hito),
    'qa', json_build_object(
        'resumen', (SELECT json_object_agg(estado, n ORDER BY estado)
                    FROM (SELECT estado, count(*) AS n FROM qa.control GROUP BY 1) x),
        'controles', (SELECT json_agg(json_build_object('control', control, 'objeto', objeto, 'estado', estado,
                                                        'umbral', umbral, 'detalle', detalle) ORDER BY control, objeto)
                      FROM qa.control)),
    'segmentos', (SELECT json_agg(json_build_object(
                      'tipo', s.tipo_institucion, 'nivel', s.nivel_carrera,
                      'cobertura', json_build_array(round(100 * s.cobertura_1, 1), round(100 * s.cobertura_5, 1)),
                      'baja_cobertura', s.baja_cobertura,
                      'pares', (SELECT count(*) FROM analytics.par p WHERE p.tipo_institucion = s.tipo_institucion AND p.nivel_carrera = s.nivel_carrera),
                      'representativos', (SELECT count(*) FROM analytics.par p WHERE p.tipo_institucion = s.tipo_institucion AND p.nivel_carrera = s.nivel_carrera AND p.representativo),
                      'dispersion', json_build_object(
                          'pares_emp1', ds.pares_emp1, 'iqr_mediano_emp1', round(ds.iqr_mediano_emp1::numeric, 1),
                          'pares_enganosos', ds.pares_enganosos,
                          'pares_emp2', ds.pares_emp2, 'iqr_mediano_emp2', round(ds.iqr_mediano_emp2::numeric, 1),
                          'pares_tramo', ds.pares_tramo, 'resumen_tramo', ds.resumen_tramo,
                          'amplitud_mediana_tramo', ds.amplitud_mediana_tramo,
                          'tramos_distintos_mediana', ds.tramos_distintos_mediana))
                      ORDER BY s.tipo_institucion, s.nivel_carrera)
                  FROM analytics.segmento s JOIN analytics.dispersion_segmento ds USING (tipo_institucion, nivel_carrera)),
    'referencias', (SELECT json_agg(json_build_object(
                        'grupo', grupo_id, 'metrica', metrica, 'tipo_grupo', tipo_grupo, 'area', area_cine13,
                        'tipo', tipo_institucion, 'nivel', nivel_carrera, 'n_pares', n_pares,
                        'peso_max_pct', round(100 * peso_max_share, 1),
                        'q25', round(q25, CASE WHEN metrica = 'p50_pct_1_5' THEN 1 ELSE 0 END),
                        'q50', round(q50, CASE WHEN metrica = 'p50_pct_1_5' THEN 1 ELSE 0 END),
                        'q75', round(q75, CASE WHEN metrica = 'p50_pct_1_5' THEN 1 ELSE 0 END))
                        ORDER BY grupo_id, metrica)
                    FROM analytics.referencia),
    'pares', (SELECT json_agg(datos ORDER BY tipo_institucion, clave_carrera_generica) FROM analytics.v_par_json),
    'programas', (SELECT json_agg(json_build_object(
                      'institucion', i.nombre, 'codigo_institucion', pv.codigo_institucion,
                      'clave', pv.clave_carrera_generica, 'tipo', pv.tipo_institucion, 'carrera', m.carrera,
                      'acreditacion_anios', m.acreditacion_anios,
                      'emp1', pv.empleabilidad_1er_anio, 'desvio_emp1', round(pv.desvio_1er_anio::numeric, 1),
                      'emp2', pv.empleabilidad_2do_anio, 'desvio_emp2', round(pv.desvio_2do_anio::numeric, 1),
                      'continuidad', pv.pct_continuidad_estudios,
                      'tramo', CASE WHEN pv.tramo_min IS NULL THEN NULL
                                    ELSE json_build_array(pv.tramo_min, pv.tramo_max) END,
                      'tramo_vs_par', pv.tramo_vs_par)
                      ORDER BY pv.tipo_institucion, pv.clave_carrera_generica, i.nombre, pv.codigo_institucion)
                  FROM analytics.programa_vs_par pv
                  JOIN modelo.institucion i USING (codigo_institucion)
                  JOIN modelo.mifuturo_programa m USING (codigo_institucion, clave_carrera_generica)),
    'que_no_dice', json_build_object(
        'cobertura_titulaciones', (SELECT json_build_array(round(100.0 * sum(tit_publicadas_1) / sum(tit_sies_1), 1),
                                                           round(100.0 * sum(tit_publicadas_5) / sum(tit_sies_5), 1))
                                   FROM analytics.segmento),
        'segmentos_baja_cobertura', (SELECT json_agg(tipo_institucion || ' · ' || nivel_carrera ORDER BY 1)
                                     FROM analytics.segmento WHERE baja_cobertura),
        'pares_no_representativos', (SELECT count(*) FROM analytics.par WHERE NOT representativo),
        'pares_total', (SELECT count(*) FROM analytics.par),
        'celdas_validas', (SELECT count(DISTINCT (area_cine13, tipo_institucion, nivel_carrera)) FROM analytics.par WHERE celda_valida),
        'hitos_con_anomalia', (SELECT json_agg(anio_k ORDER BY anio_k) FROM analytics.hito WHERE incluye_caida OR incluye_rebote),
        'cohortes_atipicas', (SELECT count(*) FROM analytics.estabilidad WHERE atipica),
        'pares_composicion_edad', (SELECT count(*) FROM analytics.contexto
                                   WHERE (mayores30_max_p1 - mayores30_max_p5) * 100 >= analytics.param('min_cambio_edad_pp')),
        'brecha_nacional_instituciones', (SELECT detalle FROM qa.control
                                          WHERE control = 'analytics_dispersion' AND objeto = 'brecha_nacional_instituciones'),
        'pct_titulaciones_genericas_no_publicadas', (
            SELECT round(100.0 * sum(t.total_titulaciones) FILTER (
                       WHERE NOT EXISTS (SELECT 1 FROM modelo.mifuturo_programa m
                                         WHERE m.clave_carrera_generica = t.clave_carrera_generica))
                   / sum(t.total_titulaciones), 1)
            FROM modelo.titulacion t, modelo.cohorte c
            WHERE c.indicador = 'ingreso_medio_1er_anio' AND t.anio BETWEEN c.cohorte_desde AND c.cohorte_hasta))
) AS datos;

-- --------------------------------------------------------------------------
-- Controles qa
-- --------------------------------------------------------------------------
INSERT INTO qa.control (control, objeto, estado, metrica, umbral, detalle)
SELECT 'analytics_exportacion', 'pares_json', CASE WHEN n_json = n_par THEN 'OK' ELSE 'FALLA' END,
       n_json, 'un objeto JSON por par',
       format('%s objetos en v_par_json; %s pares', n_json, n_par)
FROM (SELECT (SELECT count(*) FROM analytics.v_par_json) AS n_json,
             (SELECT count(*) FROM analytics.par) AS n_par) x;
