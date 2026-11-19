-- src/Analisis/sql/analytics/07_exportacion.sql
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
-- La marca de COMPOSICIÓN POR EDAD se define en 05_contexto.sql (analytics.contexto.composicion_edad);
-- aquí solo se exporta. Las cifras de los hallazgos de portada vienen de 06_hallazgos.sql.
-- Requiere 01 a 06.

-- --------------------------------------------------------------------------
-- Diferencia de cada par representativo con la típica de su grupo (ficha unificada)
-- --------------------------------------------------------------------------
CREATE VIEW analytics.v_dif_grupo AS
SELECT po.clave_carrera_generica, po.tipo_institucion,
       max(m.valor - r.q50) FILTER (WHERE m.metrica = 'p50_anio_1')    AS p50_anio_1,
       max(m.valor - r.q50) FILTER (WHERE m.metrica = 'p50_anio_5')    AS p50_anio_5,
       max(m.valor - r.q50) FILTER (WHERE m.metrica = 'emp1_nacional') AS emp1_nacional,
       -- «×1,25 de la del medio» de la ayuda de los cuadrantes: antes lo calculaba app.js (19-11-26).
       max(m.valor / r.q50) FILTER (WHERE m.metrica = 'p50_anio_1')    AS razon_entrada
FROM analytics.posicion po
JOIN analytics.miembro_referencia m
  ON m.grupo_id = po.grupo_id
 AND m.clave_carrera_generica = po.clave_carrera_generica
 AND m.tipo_institucion = po.tipo_institucion
JOIN analytics.referencia r ON r.grupo_id = m.grupo_id AND r.metrica = m.metrica
GROUP BY 1, 2;

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
                              'asignable', p.area_asignable,
                              -- Área del conocimiento de MiFuturo (MINEDUC): la de referencia de los grupos
                              -- y de «Otras carreras de su área» (ADR-002); cine13 queda como contexto.
                              'mineduc', p.area),
    'marcas', json_build_object(
        'representativo', p.representativo,
        'referencia', p.referencia,
        'grupo_referencia', po.grupo_id,
        'baja_cobertura', p.baja_cobertura,
        'es_derecho', p.es_derecho,
        'cohorte_atipica', coalesce(es.atipica, false),
        'composicion_edad', coalesce(c.composicion_edad, false),
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
        'cuartil_p50_delta_1_5', po.cuartil_p50_delta_1_5, 'entrada_alta', po.entrada_alta,
        'cuadrante_pct', po.cuadrante_pct, 'cuadrante_pesos', po.cuadrante_pesos,
        'progreso_pct', po.progreso_pct, 'progreso_pesos', po.progreso_pesos,
        'cambia_cuadrante', po.cambia_cuadrante) END,
    -- Diferencia con la típica de su grupo (valor − mediana ponderada) en las tres cifras de la
    -- ficha; la web la usa en el título de acción ("entra ganando $96 mil más que la típica").
    'dif_grupo', CASE WHEN po.clave_carrera_generica IS NULL THEN NULL ELSE (
        SELECT json_build_object('p50_anio_1', round(dg.p50_anio_1), 'p50_anio_5', round(dg.p50_anio_5),
                                 'emp1_nacional', round(dg.emp1_nacional, 1),
                                 'razon_entrada', round(dg.razon_entrada, 2))
        FROM analytics.v_dif_grupo dg
        WHERE dg.clave_carrera_generica = p.clave_carrera_generica AND dg.tipo_institucion = p.tipo_institucion) END,
    -- Posición en su área de MiFuturo (todas las carreras del nivel, todos los tipos) y, si no tiene
    -- celda propia, por qué (03_referencia.sql, analytics.area_ficha).
    'area_ficha', (SELECT json_build_object('n_area', af.n_area, 'mas_que', af.mas_que_p50_1, 'motivo', af.motivo,
                                            'mas_que_pct', af.mas_que_pct, 'mas_que_pesos', af.mas_que_pesos,
                                            'n_celda', af.n_celda, 'domina', af.domina_clave,
                                            'domina_pct', round(af.domina_pct))
                   FROM analytics.area_ficha af
                   WHERE af.clave_carrera_generica = p.clave_carrera_generica AND af.tipo_institucion = p.tipo_institucion),
    'empleabilidad_nacional', json_build_array(e.empleabilidad_1er_anio, e.empleabilidad_2do_anio),
    'duracion', json_build_object('formal', e.duracion_formal_semestres, 'real', e.duracion_real_semestres),
    'titulados_2024', json_build_object('total', sx.total, 'mujeres', sx.mujeres, 'hombres', sx.hombres,
                                        'sin_dato', sx.sin_dato,
                                        'pct_mujeres', sx.pct_mujeres, 'pct_hombres', sx.pct_hombres),
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
JOIN analytics.sexo_titulados sx USING (clave_carrera_generica, tipo_institucion)
LEFT JOIN analytics.estabilidad es USING (clave_carrera_generica, tipo_institucion)
LEFT JOIN analytics.dispersion_empleabilidad de1
       ON de1.clave_carrera_generica = p.clave_carrera_generica
      AND de1.tipo_institucion = p.tipo_institucion AND de1.anio = 1;

-- --------------------------------------------------------------------------
-- Ficha de ejemplo de la Parte II: la carrera representativa con más titulados (peso SIES de
-- ambas ventanas), con típica propia en su área (celda válida), que NO es la mediana de su grupo
-- en ninguna de las tres cifras de la ficha.
-- Si fuera la mediana (Ingeniería Comercial pesa el 40 % de su grupo), la primera ficha que se
-- ve diría "es la típica" tres veces y no mostraría ninguna comparación.
-- Desempate por clave y tipo: determinista.
-- --------------------------------------------------------------------------
CREATE VIEW analytics.v_ficha_ejemplo AS
SELECT p.clave_carrera_generica, p.tipo_institucion, p.peso
FROM analytics.par p
JOIN analytics.v_dif_grupo d USING (clave_carrera_generica, tipo_institucion)
WHERE p.representativo
  -- Con típica propia en su área (celda válida): la primera ficha que se ve debe mostrar la
  -- comparación completa; sin ella la ficha solo da la posición en el área (18-11-26).
  AND p.celda_valida
  AND d.p50_anio_1 <> 0 AND d.p50_anio_5 <> 0 AND d.emp1_nacional <> 0
ORDER BY p.peso DESC, p.clave_carrera_generica, p.tipo_institucion
LIMIT 1;

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
        'rotulo_empleabilidad', '% con ingreso >= sueldo mínimo entre titulados con registro en el SII',
        -- Ficha que abre la Parte II (regla en analytics.v_ficha_ejemplo); la web dice por qué.
        'ficha_ejemplo', (SELECT json_build_object('clave', clave_carrera_generica, 'tipo', tipo_institucion)
                          FROM analytics.v_ficha_ejemplo)),
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
                        'grupo', grupo_id, 'metrica', metrica, 'tipo_grupo', tipo_grupo, 'area', area,
                        'tipo', tipo_institucion, 'nivel', nivel_carrera, 'n_pares', n_pares,
                        'peso_max_pct', round(100 * peso_max_share, 1),
                        'q25', round(q25, CASE WHEN metrica IN ('p50_pct_1_5', 'emp1_nacional') THEN 1 ELSE 0 END),
                        'q50', round(q50, CASE WHEN metrica IN ('p50_pct_1_5', 'emp1_nacional') THEN 1 ELSE 0 END),
                        'q75', round(q75, CASE WHEN metrica IN ('p50_pct_1_5', 'emp1_nacional') THEN 1 ELSE 0 END),
                        'q50_clave', q50_clave)
                        ORDER BY grupo_id, metrica)
                    FROM analytics.referencia),
    -- Cifras y ejemplos de los hallazgos de portada (06_hallazgos.sql): la web y el README solo redactan.
    'hallazgos', json_build_object(
        -- Un objeto por nivel (técnicas, profesionales): nunca una mediana que mezcle ambos.
        'edad', (SELECT json_agg(json_build_object(
                     'nivel', nivel_carrera,
                     'n_comparables', n_comparables, 'mediana_p50_pct', round(mediana_p50_pct, 1),
                     'n_negativos', n_negativos, 'claves_bajan', to_json(claves_bajan), 'n_con_edad', n_con_edad,
                     'n_marca_edad', n_marca_edad,
                     'mayores30', json_build_array(round(100 * mayores30_p5, 1), round(100 * mayores30_p1, 1)))
                     ORDER BY nivel_carrera DESC)   -- técnicas primero: ahí está el hallazgo
                 FROM analytics.hallazgo_edad),
        'pct_pesos', (SELECT json_build_object(
                     'n_cambian_tec', h.n_cambian_tec, 'n_cambian_pro', h.n_cambian_pro,
                     'margen_pp', analytics.param('margen_tipico_pp'), 'margen_pesos', analytics.param('margen_tipico_pesos'),
                     -- Conteos de las esquinas y de la franja "progreso típico" (03_referencia.sql):
                     -- la web los dibuja tal cual, sin contar puntos.
                     'conteos', (SELECT json_agg(json_build_object('nivel', nivel_carrera, 'medida', medida, 'zona', zona, 'n', n)
                                                 ORDER BY nivel_carrera, medida, zona)
                                 FROM analytics.cuadrante_conteo),
                     'ejemplo', CASE WHEN h.clave_carrera_generica IS NULL THEN NULL ELSE json_build_object(
                         'clave', h.clave_carrera_generica, 'tipo', h.tipo_institucion, 'nombre', p.nombre,
                         'p50_anio_1', h.p50_anio_1, 'p50_pct_1_5', round(h.p50_pct_1_5, 1),
                         'p50_delta_1_5', round(h.p50_delta_1_5), 'ref_delta_q50', round(h.ref_delta_q50),
                         'p50_anio_5', h.p50_anio_5, 'ref_pct_q50', round(h.ref_pct_q50, 1),
                         -- El grupo con el que se compara, para nombrarlo en la tarjeta.
                         'grupo', (SELECT json_build_object('tipo_grupo', r.tipo_grupo, 'area', r.area,
                                                            'tipo', r.tipo_institucion, 'nivel', r.nivel_carrera,
                                                            'n_pares', r.n_pares)
                                   FROM analytics.referencia r
                                   WHERE r.grupo_id = h.grupo_id AND r.metrica = 'p50_pct_1_5')) END)
                 FROM analytics.hallazgo_pct_pesos h
                 LEFT JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)),
        'dispersion', (SELECT json_build_object(
                     'n_enganosos', h.n_enganosos, 'umbral_pp', analytics.param('min_iqr_enganoso'),
                     'ejemplo', CASE WHEN h.clave_carrera_generica IS NULL THEN NULL ELSE json_build_object(
                         'clave', h.clave_carrera_generica, 'tipo', h.tipo_institucion, 'nombre', p.nombre,
                         'n_inst', h.n_inst, 'q1', round(h.q1, 1), 'q3', round(h.q3, 1),
                         'iqr', round(h.iqr, 1), 'nacional', h.nacional) END)
                 FROM analytics.hallazgo_dispersion h
                 LEFT JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)),
        -- (d) continuidad de estudios por nivel, ponderada por titulados, y sus dos ejemplos.
        'continuidad', json_build_object(
            'niveles', (SELECT json_agg(json_build_object('nivel', nivel_carrera, 'pct', round(pct_pond, 1),
                                                          'de_cada_100', de_cada_100, 'n_programas', n_programas)
                                        ORDER BY nivel_carrera DESC)
                        FROM analytics.hallazgo_continuidad),
            'ejemplos', (SELECT json_object_agg(e.lado, json_build_object('clave', e.clave_carrera_generica,
                                    'tipo', e.tipo_institucion, 'nombre', p.nombre, 'pct', round(e.pct_pond, 1),
                                    'de_cada_100', e.de_cada_100))
                         FROM analytics.hallazgo_continuidad_ejemplo e
                         JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)))),
    -- A quiénes mira el análisis (06b_universo.sql): serie anual del SIES y embudo de las dos ventanas.
    'universo', json_build_object(
        -- Una fila por año con el total ya sumado: la web no suma cifras que publica.
        'anual', (SELECT json_agg(json_build_object('anio', anio, 'ventana', ventana,
                                                    'tecnicas', tec, 'profesionales', pro, 'total', tec + pro)
                                  ORDER BY anio)
                  FROM (SELECT anio, max(ventana) AS ventana,
                               coalesce(sum(titulaciones) FILTER (WHERE nivel_carrera = 'Carreras Técnicas'), 0) AS tec,
                               coalesce(sum(titulaciones) FILTER (WHERE nivel_carrera = 'Carreras Profesionales'), 0) AS pro
                        FROM analytics.universo_anual GROUP BY anio) a),
        -- Embudo por ventana, ambos niveles sumados (son conteos de títulos, no medianas de sueldo).
        'totales', (SELECT json_agg(json_build_object('ventana', ventana, 'sies', sies, 'comparables', comp,
                                                      'pct_comparables', round(100.0 * comp / sies, 1))
                                    ORDER BY ventana)
                    FROM (SELECT ventana, sum(tit_sies) AS sies, sum(tit_comparables) AS comp
                          FROM analytics.universo_embudo GROUP BY ventana) t),
        'ventanas', (SELECT json_object_agg(ventana, json_build_array(desde, hasta))
                     FROM (SELECT CASE indicador WHEN 'ingreso_medio_1er_anio' THEN '1er' ELSE '5to' END AS ventana,
                                  cohorte_desde AS desde, cohorte_hasta AS hasta
                           FROM modelo.cohorte
                           WHERE indicador IN ('ingreso_medio_1er_anio', 'ingreso_medio_5to_anio')) c),
        'embudo', (SELECT json_agg(json_build_object('ventana', ventana, 'nivel', nivel_carrera,
                                                     'sies', tit_sies, 'con_estadistica', tit_con_estadistica,
                                                     'comparables', tit_comparables, 'n_comparables', n_comparables,
                                                     'mujeres', mujeres, 'hombres', hombres, 'otro', otro,
                                                     'pct_mujeres', pct_mujeres, 'pct_hombres', pct_hombres)
                                   ORDER BY ventana, nivel_carrera DESC)
                   FROM analytics.universo_embudo)),
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
        -- Conteos que antes sumaba o filtraba app.js (19-11-26); control totales_exportados.
        'pares_comparables', (SELECT count(*) FROM analytics.par WHERE representativo),
        'bajan_total', (SELECT json_build_object('n_negativos', sum(n_negativos), 'n_comparables', sum(n_comparables))
                        FROM analytics.hallazgo_edad),
        'cohortes_atipicas_salud', (SELECT count(*) FROM analytics.estabilidad es
                                    JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
                                    WHERE es.atipica AND p.area = 'Salud'),
        'celdas_validas', (SELECT count(DISTINCT (area, tipo_institucion, nivel_carrera)) FROM analytics.par WHERE celda_valida),
        'hitos_con_anomalia', (SELECT json_agg(anio_k ORDER BY anio_k) FROM analytics.hito WHERE incluye_caida OR incluye_rebote),
        'cohortes_atipicas', (SELECT count(*) FROM analytics.estabilidad WHERE atipica),
        -- Universos de esos conteos, para que «Qué no dice» diga «de cuántas» (19-11-26).
        'pares_estabilidad', (SELECT count(*) FROM analytics.estabilidad),
        'pares_composicion_edad_comparables', (SELECT count(*) FROM analytics.contexto c
                                               JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
                                               WHERE c.composicion_edad AND p.representativo),
        'pares_composicion_edad', (SELECT count(*) FROM analytics.contexto WHERE composicion_edad),
        -- Vigilada por el control continuidad_sin_relacion: si fallara, el build no llega aquí.
        'continuidad_sin_relacion', json_build_object(
            'max_t', (SELECT round(max(abs(t)), 1) FROM analytics.continuidad_relacion),
            'umbral_t', analytics.param('max_t_continuidad')),
        'brecha_nacional_instituciones', (SELECT json_build_object(
                                              -- Un decimal desde el valor exacto: redondear a 2 y luego a 1 daba 1,65 → «1,6» en
                                              -- Python y «1,7» en la web (el exacto es 1,652…).
                                              'emp_pp', round(med_emp, 1), 'tramo_pct', round(100 * med_tramo, 1),
                                              'n_emp', n_emp, 'n_tramo', n_tramo)
                                          FROM analytics.brecha_nacional),
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
             (SELECT count(*) FROM analytics.par) AS n_par) x
UNION ALL
-- La ficha de ejemplo cumple su regla, recalculada sin ORDER BY/LIMIT y sin v_dif_grupo:
-- representativa con típica propia en su área (celda válida), distinta de la mediana en las tres
-- cifras y sin otra así con más titulados.
SELECT 'analytics_exportacion', 'ficha_ejemplo', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'ficha de ejemplo = representativa con celda válida, de mayor peso, que no es la mediana de su grupo en ninguna de las 3 cifras',
       format('%s problemas; ejemplo: %s (%s), peso %s', n,
              (SELECT clave_carrera_generica FROM analytics.v_ficha_ejemplo),
              (SELECT tipo_institucion FROM analytics.v_ficha_ejemplo),
              (SELECT peso FROM analytics.v_ficha_ejemplo))
FROM (
    WITH es_mediana AS (
        SELECT po.clave_carrera_generica, po.tipo_institucion,
               bool_or(m.valor = r.q50) AS alguna
        FROM analytics.posicion po
        JOIN analytics.miembro_referencia m
          ON m.grupo_id = po.grupo_id AND m.clave_carrera_generica = po.clave_carrera_generica
         AND m.tipo_institucion = po.tipo_institucion
         AND m.metrica IN ('p50_anio_1', 'p50_anio_5', 'emp1_nacional')
        JOIN analytics.referencia r ON r.grupo_id = m.grupo_id AND r.metrica = m.metrica
        GROUP BY 1, 2
    ),
    candidatas AS (
        SELECT p.* FROM analytics.par p JOIN es_mediana e USING (clave_carrera_generica, tipo_institucion)
        WHERE p.representativo AND p.celda_valida AND NOT e.alguna
    )
    SELECT (SELECT count(*) FROM analytics.v_ficha_ejemplo f
            WHERE NOT EXISTS (SELECT 1 FROM candidatas c
                              WHERE c.clave_carrera_generica = f.clave_carrera_generica
                                AND c.tipo_institucion = f.tipo_institucion)
               OR EXISTS (SELECT 1 FROM candidatas c WHERE c.peso > f.peso))
         + (1 - (SELECT count(*) FROM analytics.v_ficha_ejemplo)) AS n
) x
UNION ALL
-- Vecinas: cada grupo exportado tiene exactamente n_pares miembros distintos.
SELECT 'analytics_exportacion', 'grupos_miembros', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'miembros distintos de cada grupo = n_pares de su referencia',
       format('%s grupos con miembros distintos de n_pares; %s grupos', n,
              (SELECT count(DISTINCT grupo_id) FROM analytics.referencia))
FROM (SELECT count(*) AS n
      FROM (SELECT grupo_id, count(DISTINCT (clave_carrera_generica, tipo_institucion)) AS miembros
            FROM analytics.miembro_referencia GROUP BY 1) g
      JOIN analytics.referencia r ON r.grupo_id = g.grupo_id AND r.metrica = 'p50_anio_1'
      WHERE g.miembros <> r.n_pares) x
UNION ALL
-- Diferencia con la típica: una por representativo en las 3 cifras, y su signo en la entrada
-- coincide con entrada_alta (calculada aparte en 03_referencia.sql como valor > mediana).
SELECT 'analytics_exportacion', 'dif_grupo', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'una diferencia no nula por representativo y métrica; dif. de entrada > 0 ⇔ entrada_alta',
       format('%s problemas; %s representativos', n, (SELECT count(*) FROM analytics.posicion))
FROM (SELECT (SELECT count(*) FROM analytics.posicion po
              LEFT JOIN analytics.v_dif_grupo d USING (clave_carrera_generica, tipo_institucion)
              WHERE d.p50_anio_1 IS NULL OR d.p50_anio_5 IS NULL OR d.emp1_nacional IS NULL
                 OR (d.p50_anio_1 > 0) <> po.entrada_alta) AS n) x
UNION ALL
-- Totales que la web antes calculaba: las comparables y las que bajan, por otro camino (desde
-- brecha y no desde hallazgo_edad), y la razón de entrada = P50 ÷ carrera del medio.
SELECT 'analytics_exportacion', 'totales_exportados', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'comparables = Σ niveles de hallazgo_edad; bajan = recuento desde brecha con el margen; razón > 1 ⇔ entrada_alta',
       format('%s diferencias', n)
FROM (SELECT ((SELECT count(*) FROM analytics.par WHERE representativo)
               <> (SELECT sum(n_comparables) FROM analytics.hallazgo_edad)
           OR (SELECT sum(n_negativos) FROM analytics.hallazgo_edad)
               <> (SELECT count(*) FROM analytics.par p JOIN analytics.brecha b USING (clave_carrera_generica, tipo_institucion)
                   WHERE p.representativo AND b.p50_pct_1_5 < -analytics.param('margen_tipico_pp'))
        OR (SELECT count(*) FROM analytics.contexto c JOIN analytics.par p USING (clave_carrera_generica, tipo_institucion)
            WHERE c.composicion_edad AND p.representativo) <> (SELECT sum(n_marca_edad) FROM analytics.hallazgo_edad)
     ) ::int
     + (SELECT count(*) FROM analytics.posicion po
        JOIN analytics.v_dif_grupo d USING (clave_carrera_generica, tipo_institucion)
        WHERE (d.razon_entrada > 1) <> po.entrada_alta) AS n) x;
