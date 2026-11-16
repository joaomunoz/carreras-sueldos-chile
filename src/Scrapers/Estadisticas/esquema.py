"""
<src/Scrapers/Estadisticas/esquema.py>

Definición del esquema oficial para la tabla procesada de Estadísticas por Carrera (MiFuturo).
El orden de las claves ES el orden de columnas del CSV de salida (procesar.py lo toma de aquí).

Fuente: Buscador de Estadísticas por Carrera (endpoint AJAX `detalleEstadisticas`).
Metodología: datos externos/EMPLEABILIDAD/Metodologia-Estadisticas-por-Carrera_2025-2026.md

Granularidad: una fila = un par (carrera genérica × tipo de institución), NACIONAL.
Llave única: (clave_carrera_generica, tipo_institucion). La fuente publica 252 pares.
Es otra tabla que Empleabilidad (institución × carrera): no se mezclan, para que los
valores nacionales no se repitan en cada institución ni se pierdan pares sin institución.

Cohortes por indicador (metodología, líneas 89, 97, 101, 111 y 117):
  - Ingreso medio año k:  cohortes (2022-k)..(2024-k), ingresos 2022-2024, >= 50 casos.
  - Percentiles:          UNA cohorte, ingresos 2024, >= 11 casos (año 1 = 2023; año 5 = 2019).
                          Media y percentiles son poblaciones distintas: nunca en una misma razón.
  - Empleabilidad nacional: 1er año cohortes 2021-2023; 2° año cohortes 2020-2022; >= 50 casos.
  - Series de 5 cohortes: empleabilidad 1er año 2019-2023, 2° año 2018-2022 e ingreso al
    4° año 2016-2020; cada punto es UNA cohorte (>= 25 casos), ingresos 2020-2024.
  - Derecho: cohorte de titulación + 1 año en todos los indicadores.

ADVERTENCIA sobre ORIGEN: la API arrastra nombres de campo con años de un esquema antiguo
(`cohorte_2005_a` es la empleabilidad 1er año actual; `emplea_1_2015` es la cohorte 2019).
La correspondencia campo -> cohorte es una INFERENCIA verificada en 1 par por consistencia
(promedio de los 3 últimos puntos de cada serie ≈ agregado publicado). Un control `qa` en
src/BD la verifica en los 252 pares; si MiFuturo cambia el significado de un campo, el
build falla en vez de publicar una serie corrida.

Unidades: porcentajes 0-100 (la API entrega fracción 0-1); ingresos en pesos de septiembre
de 2025, enteros. Los ingresos solo consideran titulados con ingreso >= sueldo mínimo.

Campos de la API que NO se guardan: `es_tecnico` (verificado: vale 1 en todo CFT e IP y 0 en
toda Universidad, es decir "no universitaria", no el nivel de la carrera; redundante con
tipo_institucion; el nivel real viene de Titulados), y fuera del alcance: matrícula 2025,
retención, establecimiento de origen, y los campos vacíos en la fuente (`ingreso_ano_1..10`,
`menor_a_500000` .. `mayor_a_3000000`). obtener.py los conserva igual en el crudo de Entrada/.
"""

from __future__ import annotations

# Diccionario de tipos de datos oficiales por columna (orden = orden de salida)
ESQUEMA_ESTADISTICAS = {
    # --- Identificación del par ---
    "id_estadisticas": "int64",                 # id interno de MiFuturo; solo trazabilidad, no llave
    "tipo_institucion": "object",               # canónico: Universidad | IP | CFT
    "carrera_generica": "object",
    "clave_carrera_generica": "object",         # = clave de Empleabilidad y Titulados (normalizar_texto)
    # Área del Conocimiento MINEDUC (base CINE-97, glosario SIES registro 16), NO CINE-F 2013:
    # coincide con el área CINE-13 dominante en 21/252 pares. Solo para mostrar la etiqueta de
    # MiFuturo; la segmentación por área usa CINE-13 desde Titulados.
    "area_conocimiento_mineduc": "object",
    # --- Ingreso medio (3 cohortes por año, ingresos 2022-2024) ---
    "ingreso_medio_1er_anio": "Int64",          # cohortes 2021-2023
    "ingreso_medio_2do_anio": "Int64",          # cohortes 2020-2022
    "ingreso_medio_3er_anio": "Int64",          # cohortes 2019-2021
    "ingreso_medio_4to_anio": "Int64",          # cohortes 2018-2020
    "ingreso_medio_5to_anio": "Int64",          # cohortes 2017-2019
    # --- Percentiles (una cohorte, ingresos 2024) ---
    "percentil_10_anio_1": "Int64",             # cohorte 2023
    "percentil_25_anio_1": "Int64",
    "percentil_50_anio_1": "Int64",
    "percentil_75_anio_1": "Int64",
    "percentil_90_anio_1": "Int64",
    "percentil_10_anio_5": "Int64",             # cohorte 2019
    "percentil_25_anio_5": "Int64",
    "percentil_50_anio_5": "Int64",
    "percentil_75_anio_5": "Int64",
    "percentil_90_anio_5": "Int64",
    # --- Empleabilidad nacional del par (reemplaza la reconstrucción ponderada) ---
    "empleabilidad_1er_anio": "float64",        # cohortes 2021-2023
    "empleabilidad_2do_anio": "float64",        # cohortes 2020-2022
    # --- Series de 5 cohortes (misma antigüedad, distinta cohorte: aíslan el efecto cohorte) ---
    "empleabilidad_1er_anio_cohorte_2019": "float64",
    "empleabilidad_1er_anio_cohorte_2020": "float64",
    "empleabilidad_1er_anio_cohorte_2021": "float64",
    "empleabilidad_1er_anio_cohorte_2022": "float64",
    "empleabilidad_1er_anio_cohorte_2023": "float64",
    "empleabilidad_2do_anio_cohorte_2018": "float64",
    "empleabilidad_2do_anio_cohorte_2019": "float64",
    "empleabilidad_2do_anio_cohorte_2020": "float64",
    "empleabilidad_2do_anio_cohorte_2021": "float64",
    "empleabilidad_2do_anio_cohorte_2022": "float64",
    "ingreso_medio_4to_anio_cohorte_2016": "Int64",
    "ingreso_medio_4to_anio_cohorte_2017": "Int64",
    "ingreso_medio_4to_anio_cohorte_2018": "Int64",
    "ingreso_medio_4to_anio_cohorte_2019": "Int64",
    "ingreso_medio_4to_anio_cohorte_2020": "Int64",
    # --- Titulados 2024 (PERSONAS, no titulaciones) ---
    "titulados_2024": "Int64",
    "titulados_2024_mujeres": "Int64",
    "titulados_2024_hombres": "Int64",
    # --- Duración (programas regulares, titulados 2024) ---
    "duracion_formal_semestres": "float64",     # plan de estudios + proceso de titulación
    "duracion_real_semestres": "float64",       # desde el ingreso hasta la titulación; >= 25 casos
}

# Columna de salida -> campo de la respuesta de `detalleEstadisticas`.
# Vive junto al esquema porque fija el SIGNIFICADO de cada columna (ver ADVERTENCIA arriba).
ORIGEN = {
    "id_estadisticas": "id_estadisticas",
    "tipo_institucion": "tipo_institucion",
    "carrera_generica": "carrera_estandar",
    "area_conocimiento_mineduc": "area_cineunesco",
    "ingreso_medio_1er_anio": "primer_ano",
    "ingreso_medio_2do_anio": "segundo_ano",
    "ingreso_medio_3er_anio": "tercer_ano",
    "ingreso_medio_4to_anio": "cuarto_ano",
    "ingreso_medio_5to_anio": "quinto_ano",
    **{f"percentil_{p}_anio_1": f"percentil{p}_a" for p in (10, 25, 50, 75, 90)},
    **{f"percentil_{p}_anio_5": f"percentil{p}_b" for p in (10, 25, 50, 75, 90)},
    "empleabilidad_1er_anio": "cohorte_2005_a",
    "empleabilidad_2do_anio": "cohorte_2006_a",
    # Desfase inferido: emplea_1_<a> = cohorte a+4; emplea_2_<a> = cohorte a+3; ingresos_4_<a> = cohorte a+1
    **{f"empleabilidad_1er_anio_cohorte_{a + 4}": f"emplea_1_{a}" for a in range(2015, 2020)},
    **{f"empleabilidad_2do_anio_cohorte_{a + 3}": f"emplea_2_{a}" for a in range(2015, 2020)},
    **{f"ingreso_medio_4to_anio_cohorte_{a + 1}": f"ingresos_4_{a}" for a in range(2015, 2020)},
    "titulados_2024": "n_de_titulados_2010",
    "titulados_2024_mujeres": "n_de_titulados_femenino_2010",
    "titulados_2024_hombres": "n_de_titulados_masculino_2010",
    "duracion_formal_semestres": "duracion_esperada_del_plan_de_estudios_semestres",
    "duracion_real_semestres": "duracion_real_de_la_carrera_semestres",
}
