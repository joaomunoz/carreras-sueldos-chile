-- src/Analisis/sql/analytics/01_par.sql
--
-- A1 (Fase 2): el par (carrera genérica × tipo de institución) como tabla permanente, con las
-- marcas que deciden en qué análisis entra. Es la lógica de la vista temporal de
-- src/Analisis/sql/auditoria/06_cobertura_celdas.sql (T5, aprobada como gate), más el peso del
-- par y la cobertura por segmento.
--
-- Corre dentro de la transacción única de src/BD/build.py, después de src/BD/04_qa.sql (necesita
-- qa.control). Lee solo `modelo`. Recrea el esquema `analytics` completo: los archivos
-- siguientes de esta carpeta (NN_*.sql, en orden) agregan sus tablas.

DROP SCHEMA IF EXISTS analytics CASCADE;
CREATE SCHEMA analytics;

-- --------------------------------------------------------------------------
-- Parámetros: todos los umbrales del análisis en un solo lugar (también los lee la web)
-- --------------------------------------------------------------------------
CREATE TABLE analytics.parametro (
    nombre       text    PRIMARY KEY,
    valor        numeric NOT NULL,
    descripcion  text    NOT NULL,
    origen       text    NOT NULL      -- decisión que lo fija (pizarra / logfile)
);

-- Factor para llevar a 3 años una ventana que cae en parte fuera de los años del SIES: con Derecho
-- un año antes (ADR-003), su ventana del 5° año es 2016–2018 y el SIES empieza en 2017; sumar solo
-- 2 años la dejaba pesando 2/3 (evaluación del 19-11-26). NULL si ningún año de la ventana existe:
-- el NOT NULL del peso hace fallar el build en vez de inventar un dato.
CREATE FUNCTION analytics.factor_ventana(desde integer, hasta integer) RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT (hasta - desde + 1)::numeric
           / nullif(greatest(0, least(hasta, c.cohorte_hasta) - greatest(desde, c.cohorte_desde) + 1), 0)
    FROM modelo.cohorte c WHERE c.indicador = 'titulados_sies'
$$;

INSERT INTO analytics.parametro VALUES
    -- Años que se corren las ventanas SIES de Derecho respecto de modelo.cohorte (MiFuturo usa otra
    -- cohorte para esta carrera: 2020–2022 en vez de 2021–2023). Un solo lugar: antes un +1, en sentido
    -- contrario, estaba escrito en 10 consultas (corregido el 19-11-26, ADR-003).
    ('corrimiento_derecho', -1,   'Años de diferencia entre los titulados que usa Derecho y los de las demás carreras (−1: un año antes, como publica MiFuturo)', 'T4; parámetro desde el 19-11-26 (ADR-003)'),
    ('min_inst_oferta',     3,    'Instituciones necesarias para que una carrera sea comparable (con 1 o 2, la cifra nacional es la de esas instituciones)', 'T0 / D2: dos conteos de instituciones'),
    ('min_pares_celda',     5,    'Carreras comparables necesarias para que un área, dentro de un tipo y nivel, tenga carrera del medio propia',                     'D2'),
    ('min_share_area',      0.80, 'Parte mínima de las titulaciones en un área CINE (clasificación internacional) para asignarla a una carrera; solo contexto',                'T0 / T4'),
    ('min_inst_dispersion', 5,    'Instituciones con el dato necesarias para comparar las instituciones de una carrera',                  'D1'),
    ('max_cobertura_baja',  0.75, 'Si los programas que publica MiFuturo reúnen menos de esta parte de los titulados de un tipo y nivel, se avisa baja cobertura',       'T5, decisión 2'),
    ('max_peso_dominante',  0.50, 'Si una carrera reúne más de esta parte de los titulados de su grupo de área, el grupo no sirve de referencia',     'A3: celdas dominadas (aprobada por el usuario)');

-- Lectura de un parámetro que FALLA si el nombre no existe. Con un subselect simple, un nombre
-- mal escrito daría NULL y toda comparación contra NULL sería falsa en silencio (p. ej. ningún
-- par representativo, sin error).
CREATE FUNCTION analytics.param(p_nombre text) RETURNS numeric
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v numeric;
BEGIN
    SELECT valor INTO v FROM analytics.parametro WHERE nombre = p_nombre;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Parámetro inexistente: %', p_nombre;
    END IF;
    RETURN v;
END $$;

-- --------------------------------------------------------------------------
-- Segmento tipo × nivel: cobertura de MiFuturo sobre el SIES (auditoría 02)
-- --------------------------------------------------------------------------
CREATE TABLE analytics.segmento (
    tipo_institucion  text    NOT NULL,
    nivel_carrera     text    NOT NULL,
    tit_sies_1        integer NOT NULL,   -- titulaciones SIES, ventana del 1er año
    tit_publicadas_1  integer NOT NULL,   -- de institución × genérica publicadas en MiFuturo
    tit_sies_5        integer NOT NULL,   -- ídem, ventana del 5° año
    tit_publicadas_5  integer NOT NULL,
    cobertura_1       numeric NOT NULL,   -- proporción 0-1
    cobertura_5       numeric NOT NULL,
    baja_cobertura    boolean NOT NULL,
    PRIMARY KEY (tipo_institucion, nivel_carrera)
);
COMMENT ON TABLE analytics.segmento IS
    'Cobertura por titulaciones de los programas publicados por MiFuturo. Ventanas = cohortes de la media del 1er y 5° año (modelo.cohorte; Derecho corrido según corrimiento_derecho, ADR-003).';

INSERT INTO analytics.segmento
WITH c1 AS (SELECT cohorte_desde AS desde, cohorte_hasta AS hasta FROM modelo.cohorte WHERE indicador = 'ingreso_medio_1er_anio'),
     c5 AS (SELECT cohorte_desde AS desde, cohorte_hasta AS hasta FROM modelo.cohorte WHERE indicador = 'ingreso_medio_5to_anio'),
x AS (
    SELECT i.tipo_institucion, g.nivel_carrera,
           p.codigo_institucion IS NOT NULL AS publicado,
           sum(t.total_titulaciones) FILTER (
               WHERE t.anio BETWEEN c1.desde + (t.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int
                                AND c1.hasta + (t.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int) AS tit_1,
           sum(t.total_titulaciones) FILTER (
               WHERE t.anio BETWEEN c5.desde + (t.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int
                                AND c5.hasta + (t.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int) AS tit_5
    FROM modelo.titulacion t
    JOIN modelo.institucion i USING (codigo_institucion)
    JOIN modelo.carrera_generica g USING (clave_carrera_generica)
    LEFT JOIN modelo.mifuturo_programa p USING (codigo_institucion, clave_carrera_generica)
    CROSS JOIN c1 CROSS JOIN c5
    GROUP BY 1, 2, 3
)
SELECT tipo_institucion, nivel_carrera,
       coalesce(sum(tit_1), 0), coalesce(sum(tit_1) FILTER (WHERE publicado), 0),
       coalesce(sum(tit_5), 0), coalesce(sum(tit_5) FILTER (WHERE publicado), 0),
       sum(tit_1) FILTER (WHERE publicado)::numeric / sum(tit_1),
       sum(tit_5) FILTER (WHERE publicado)::numeric / sum(tit_5),
       least(sum(tit_1) FILTER (WHERE publicado)::numeric / sum(tit_1),
             sum(tit_5) FILTER (WHERE publicado)::numeric / sum(tit_5)) < analytics.param('max_cobertura_baja')
FROM x
GROUP BY 1, 2;

-- --------------------------------------------------------------------------
-- Par: una fila por par de la estadística nacional (252)
-- --------------------------------------------------------------------------
CREATE TABLE analytics.par (
    clave_carrera_generica  text     NOT NULL,
    tipo_institucion        text     NOT NULL,
    nombre                  text     NOT NULL,
    nivel_carrera           text     NOT NULL,
    -- Área de REFERENCIA: el área del conocimiento de MiFuturo (MINEDUC), la que ve quien busca
    -- carreras. Define la celda área × tipo × nivel (ADR-002, 18-11-26): la CINE separaba, p. ej.,
    -- Telecomunicaciones (ingeniería) de Informática (TIC), y las carreras de un área chica se
    -- comparaban con todas las de su tipo × nivel. Misma área en todos los tipos (control qa).
    area                    text     NOT NULL,
    -- Área CINE-F 2013 dominante por titulaciones SIES: solo contexto desde el ADR-002.
    area_cine13             text     NOT NULL,
    share_area              numeric  NOT NULL,   -- proporción 0-1 del área CINE dominante
    area_asignable          boolean  NOT NULL,   -- área CINE dominante ≥ min_share_area
    ingreso_completo        boolean  NOT NULL,   -- media 1°-5° y percentiles años 1 y 5
    n_inst_oferta           integer  NOT NULL,   -- con titulaciones SIES en ambas ventanas
    n_pub_emp1              integer  NOT NULL,   -- instituciones publicadas con el dato
    n_pub_emp2              integer  NOT NULL,
    n_pub_tramo             integer  NOT NULL,
    tit_ventana_1           integer  NOT NULL,   -- titulaciones SIES del par (todas las instituciones)
    tit_ventana_5           integer  NOT NULL,
    peso                    integer  NOT NULL,   -- tit_ventana_1 + tit_ventana_5, cada ventana llevada a 3 años si el SIES no la cubre entera (factor_ventana)
    representativo          boolean  NOT NULL,   -- entra en rankings, referencias y cuadrantes
    celda_valida            boolean  NOT NULL,   -- su celda área (MiFuturo) × tipo × nivel es referencia
    referencia              text     CHECK (referencia IN ('celda', 'segmento')),  -- NULL = no comparable
    baja_cobertura          boolean  NOT NULL,   -- heredada del segmento
    es_derecho              boolean  NOT NULL,   -- cohortes desplazadas corrimiento_derecho años
    PRIMARY KEY (clave_carrera_generica, tipo_institucion),
    FOREIGN KEY (clave_carrera_generica, tipo_institucion) REFERENCES modelo.mifuturo_estadistica,
    FOREIGN KEY (tipo_institucion, nivel_carrera) REFERENCES analytics.segmento
);
COMMENT ON COLUMN analytics.par.referencia IS
    'celda = se compara con su celda área × tipo × nivel; segmento = con su tipo × nivel; NULL = no representativo: solo ficha por carrera, rotulado "1-2 instituciones: no comparable".';

INSERT INTO analytics.par
WITH c1 AS (SELECT cohorte_desde AS desde, cohorte_hasta AS hasta FROM modelo.cohorte WHERE indicador = 'ingreso_medio_1er_anio'),
     c5 AS (SELECT cohorte_desde AS desde, cohorte_hasta AS hasta FROM modelo.cohorte WHERE indicador = 'ingreso_medio_5to_anio'),
-- Titulaciones por institución × genérica en cada ventana (Derecho corrido corrimiento_derecho años, ADR-003).
inst AS (
    SELECT i.tipo_institucion, t.clave_carrera_generica, t.codigo_institucion,
           coalesce(sum(t.total_titulaciones) FILTER (
               WHERE t.anio BETWEEN c1.desde + (t.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int
                                AND c1.hasta + (t.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int), 0) AS tit_1,
           coalesce(sum(t.total_titulaciones) FILTER (
               WHERE t.anio BETWEEN c5.desde + (t.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int
                                AND c5.hasta + (t.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int), 0) AS tit_5
    FROM modelo.titulacion t
    JOIN modelo.institucion i USING (codigo_institucion)
    CROSS JOIN c1 CROSS JOIN c5
    GROUP BY 1, 2, 3
),
oferta AS (
    SELECT tipo_institucion, clave_carrera_generica,
           count(*) FILTER (WHERE tit_1 > 0 AND tit_5 > 0) AS n_inst_oferta,
           sum(tit_1) AS tit_1, sum(tit_5) AS tit_5
    FROM inst GROUP BY 1, 2
),
-- Área dominante en todas las cohortes de los indicadores usados (sin series, D5).
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
           count(*) AS n_emp1, count(empleabilidad_2do_anio) AS n_emp2,
           count(ingreso_4to_anio_tramo_min) AS n_tramo
    FROM modelo.mifuturo_programa GROUP BY 1, 2
),
base AS (
    SELECT e.clave_carrera_generica, e.tipo_institucion, g.nombre, g.nivel_carrera,
           e.area_conocimiento_mineduc AS area_mf,
           a.area, a.share, a.share >= analytics.param('min_share_area') AS area_asignable,
           num_nonnulls(e.ingreso_medio_1er_anio, e.ingreso_medio_2do_anio, e.ingreso_medio_3er_anio,
                        e.ingreso_medio_4to_anio, e.ingreso_medio_5to_anio,
                        e.percentil_10_anio_1, e.percentil_25_anio_1, e.percentil_50_anio_1,
                        e.percentil_75_anio_1, e.percentil_90_anio_1,
                        e.percentil_10_anio_5, e.percentil_25_anio_5, e.percentil_50_anio_5,
                        e.percentil_75_anio_5, e.percentil_90_anio_5) = 15 AS ingreso_completo,
           coalesce(o.n_inst_oferta, 0) AS n_inst_oferta,
           coalesce(pu.n_emp1, 0) AS n_emp1, coalesce(pu.n_emp2, 0) AS n_emp2, coalesce(pu.n_tramo, 0) AS n_tramo,
           coalesce(o.tit_1, 0) AS tit_1, coalesce(o.tit_5, 0) AS tit_5,
           s.baja_cobertura,
           e.clave_carrera_generica = 'DERECHO' AS es_derecho
    FROM modelo.mifuturo_estadistica e
    JOIN modelo.carrera_generica g USING (clave_carrera_generica)
    JOIN area a USING (clave_carrera_generica)
    JOIN analytics.segmento s ON s.tipo_institucion = e.tipo_institucion AND s.nivel_carrera = g.nivel_carrera
    LEFT JOIN oferta o
           ON o.clave_carrera_generica = e.clave_carrera_generica AND o.tipo_institucion = e.tipo_institucion
    LEFT JOIN publicadas pu
           ON pu.clave_carrera_generica = e.clave_carrera_generica AND pu.tipo_institucion = e.tipo_institucion
),
marcado AS (
    SELECT b.*,
           b.ingreso_completo AND b.n_inst_oferta >= analytics.param('min_inst_oferta') AS representativo
    FROM base b
),
celda AS (
    -- Celda = área de MiFuturo × tipo × nivel (ADR-002). Toda carrera tiene área de MiFuturo, así
    -- que ya no se exige área asignable (eso era de la CINE, dominante por titulaciones).
    -- Una celda es referencia si tiene suficientes pares Y ninguna carrera domina su peso: con
    -- más de la mitad del peso, la mediana ponderada ES el valor de esa carrera y el resto de la
    -- celda se compararía con ella, no con su área (A3).
    SELECT m.*,
           count(*) FILTER (WHERE m.representativo) OVER w >= analytics.param('min_pares_celda')
           AND max(m.peso) FILTER (WHERE m.representativo) OVER w
               <= analytics.param('max_peso_dominante')
                  * sum(m.peso) FILTER (WHERE m.representativo) OVER w AS celda_valida
    -- Peso = titulaciones de ambas ventanas; una ventana incompleta en el SIES se lleva a 3 años
    -- (solo Derecho, 5° año: 2016–2018). tit_ventana_* quedan con los títulos reales (el embudo los suma).
    FROM (SELECT b.*, round(b.tit_1 * (SELECT analytics.factor_ventana(c1.desde + (b.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int, c1.hasta + (b.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int) FROM c1)
                          + b.tit_5 * (SELECT analytics.factor_ventana(c5.desde + (b.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int, c5.hasta + (b.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int) FROM c5))::integer AS peso
          FROM marcado b) m
    WINDOW w AS (PARTITION BY m.area_mf, m.tipo_institucion, m.nivel_carrera)
)
SELECT clave_carrera_generica, tipo_institucion, nombre, nivel_carrera,
       area_mf, area, share, area_asignable, ingreso_completo, n_inst_oferta,
       n_emp1, n_emp2, n_tramo, tit_1, tit_5, peso,
       representativo, celda_valida,
       CASE WHEN NOT representativo THEN NULL
            WHEN celda_valida THEN 'celda'
            ELSE 'segmento' END,
       baja_cobertura, es_derecho
FROM celda;

-- --------------------------------------------------------------------------
-- Controles qa (mismo mecanismo que src/BD/04_qa.sql; build.py falla si alguno queda en FALLA)
-- --------------------------------------------------------------------------
-- Son invariantes que deben sobrevivir a cambios futuros del SQL de arriba. La igualdad con
-- T5 (210 / 18 / 104-88-62) se verificó una vez al migrar (logfile), no se fija aquí: con
-- datos nuevos de MiFuturo esos números cambian legítimamente.
INSERT INTO qa.control (control, objeto, estado, metrica, umbral, detalle)
SELECT 'analytics_par', 'filas', CASE WHEN n_par = n_est THEN 'OK' ELSE 'FALLA' END,
       n_par, 'una fila por par de modelo.mifuturo_estadistica',
       format('%s pares en analytics.par; %s en modelo.mifuturo_estadistica', n_par, n_est)
FROM (SELECT (SELECT count(*) FROM analytics.par) AS n_par,
             (SELECT count(*) FROM modelo.mifuturo_estadistica) AS n_est) x
UNION ALL
SELECT 'analytics_par', 'representativo', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'representativo ⇔ ingreso completo y n_inst_oferta ≥ min_inst_oferta',
       format('%s pares incoherentes; %s representativos', n,
              (SELECT count(*) FROM analytics.par WHERE representativo))
FROM (SELECT count(*) AS n FROM analytics.par
      WHERE representativo IS DISTINCT FROM
            (ingreso_completo AND n_inst_oferta >= analytics.param('min_inst_oferta'))) x
UNION ALL
-- Recuento por GROUP BY, independiente de la función de ventana usada al poblar.
SELECT 'analytics_par', 'celda_valida', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'celda válida ⇔ ≥ min_pares_celda pares representativos en su área (MiFuturo) × tipo × nivel y ninguno con > max_peso_dominante del peso',
       format('%s pares incoherentes; %s celdas válidas', n,
              (SELECT count(DISTINCT (area, tipo_institucion, nivel_carrera))
               FROM analytics.par WHERE celda_valida))
FROM (SELECT count(*) AS n
      FROM analytics.par p
      LEFT JOIN (SELECT area, tipo_institucion, nivel_carrera, count(*) AS n_repr,
                        max(peso)::numeric / sum(peso) AS share_max
                 FROM analytics.par WHERE representativo
                 GROUP BY 1, 2, 3) c USING (area, tipo_institucion, nivel_carrera)
      WHERE p.celda_valida IS DISTINCT FROM
            (coalesce(c.n_repr, 0) >= analytics.param('min_pares_celda')
             AND coalesce(c.share_max, 1) <= analytics.param('max_peso_dominante'))) x
UNION ALL
-- ADR-002: el área de MiFuturo es de la carrera, no del tipo. Si MiFuturo clasificara una carrera
-- distinto en universidades, IP o CFT, la lista «Otras carreras de su área» y los grupos se
-- partirían sin aviso; además, el área de cada par debe ser la de su fila en MiFuturo.
SELECT 'analytics_par', 'area_mifuturo', CASE WHEN n_varias + n_distinta = 0 THEN 'OK' ELSE 'FALLA' END,
       n_varias + n_distinta, 'cada carrera tiene una sola área de MiFuturo y el par usa la de su fila',
       format('%s carreras con más de un área; %s pares con un área distinta a la de MiFuturo; %s áreas',
              n_varias, n_distinta, (SELECT count(DISTINCT area) FROM analytics.par))
FROM (SELECT (SELECT count(*) FROM (SELECT clave_carrera_generica FROM analytics.par
                                    GROUP BY 1 HAVING count(DISTINCT area) > 1) v) AS n_varias,
             (SELECT count(*) FROM analytics.par p
              JOIN modelo.mifuturo_estadistica e USING (clave_carrera_generica, tipo_institucion)
              WHERE p.area IS DISTINCT FROM e.area_conocimiento_mineduc) AS n_distinta) x
UNION ALL
SELECT 'analytics_par', 'referencia', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'referencia NULL ⇔ no representativo; celda ⇔ representativo y celda válida',
       format('%s pares incoherentes; celda %s, segmento %s, sin referencia %s', n,
              (SELECT count(*) FROM analytics.par WHERE referencia = 'celda'),
              (SELECT count(*) FROM analytics.par WHERE referencia = 'segmento'),
              (SELECT count(*) FROM analytics.par WHERE referencia IS NULL))
FROM (SELECT count(*) AS n FROM analytics.par
      WHERE (referencia IS NULL) <> (NOT representativo)
         -- coalesce: con referencia NULL, (referencia = 'celda') es NULL y no "falso".
         OR coalesce(referencia = 'celda', false) <> (representativo AND celda_valida)) x
UNION ALL
SELECT 'analytics_par', 'peso', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END,
       n, 'todo par representativo tiene peso > 0 en ambas ventanas',
       format('%s pares representativos sin titulaciones en alguna ventana', n)
FROM (SELECT count(*) AS n FROM analytics.par
      WHERE representativo AND (tit_ventana_1 = 0 OR tit_ventana_5 = 0)) x;

-- Ventanas fuera del SIES (19-11-26): ninguna ventana de titulaciones puede quedar sin años en el
-- SIES (factor NULL), y el peso de cada par es exactamente sus títulos llevados a 3 años. El
-- detalle nombra las ventanas que se escalan (hoy solo Derecho, 5° año).
-- Además, el factor se compara con los años que de verdad trae modelo.titulacion, no con el rango
-- declarado en modelo.cohorte que usa factor_ventana: si se cargara 2016 sin actualizar ese rango,
-- el peso se escalaría de más y el control antes pasaba igual (tercera evaluación, 19-11-26).
INSERT INTO qa.control (control, objeto, estado, metrica, umbral, detalle)
WITH anios AS (SELECT DISTINCT anio FROM modelo.titulacion),
c AS (SELECT indicador, cohorte_desde AS d, cohorte_hasta AS h FROM modelo.cohorte
           WHERE indicador IN ('ingreso_medio_1er_anio', 'ingreso_medio_5to_anio')),
v AS (
    SELECT p.clave_carrera_generica, p.tipo_institucion, p.peso, p.tit_ventana_1, p.tit_ventana_5,
           s.sh,
           analytics.factor_ventana(c1.d + s.sh, c1.h + s.sh) AS f1,
           analytics.factor_ventana(c5.d + s.sh, c5.h + s.sh) AS f5,
           (c5.d + s.sh) || '–' || (c5.h + s.sh) AS v5,
           (c1.h - c1.d + 1)::numeric / nullif((SELECT count(*) FROM anios WHERE anio BETWEEN c1.d + s.sh AND c1.h + s.sh), 0) AS f1_real,
           (c5.h - c5.d + 1)::numeric / nullif((SELECT count(*) FROM anios WHERE anio BETWEEN c5.d + s.sh AND c5.h + s.sh), 0) AS f5_real
    FROM analytics.par p
    CROSS JOIN LATERAL (SELECT (p.clave_carrera_generica = 'DERECHO')::int * analytics.param('corrimiento_derecho')::int AS sh) s
    JOIN c c1 ON c1.indicador = 'ingreso_medio_1er_anio'
    JOIN c c5 ON c5.indicador = 'ingreso_medio_5to_anio'
)
SELECT 'analytics_par', 'ventanas_en_sies', CASE WHEN n = 0 THEN 'OK' ELSE 'FALLA' END, n,
       'toda ventana tiene años en el SIES, su factor = años de la ventana ÷ años presentes en modelo.titulacion, y peso = round(tit_1·f1 + tit_5·f5)',
       coalesce((SELECT string_agg(DISTINCT format('%s %s: ventana 5° año %s escalada ×%s', clave_carrera_generica, tipo_institucion, v5, round(f5, 2)), '; ')
                 FROM v WHERE f5 <> 1 OR f1 <> 1), 'ninguna ventana escalada')
FROM (SELECT count(*) AS n FROM v
      WHERE f1 IS NULL OR f5 IS NULL OR peso <> round(tit_ventana_1 * f1 + tit_ventana_5 * f5)
         OR f1 IS DISTINCT FROM f1_real OR f5 IS DISTINCT FROM f5_real) x;
