"""
<src/Scrapers/Empleabilidad/esquema.py>

Definición del esquema oficial para la tabla procesada de Empleabilidad e Ingresos (MiFuturo).
El orden de las claves ES el orden de columnas del CSV de salida (procesar.py lo toma de aquí).

Granularidad mixta, por diseño de la fuente (no corregible aquí):
  - Nivel INSTITUCIÓN x CARRERA (una fila = un programa publicado): acreditación,
    continuidad de estudios, duración real, empleabilidad 1er/2do año y tramo de
    ingreso al 4° año. Es la única señal de ingreso a nivel institución.
  - Nivel NACIONAL x TIPO DE INSTITUCIÓN x CARRERA GENÉRICA (valor repetido en cada
    fila del par): ingreso medio 1°..5° año y percentiles 10/25/50/75/90 de año 1 y 5.
    Nunca se promedian sobre filas: se consolidan primero al par (aguas abajo, en SQL).

Cohortes (Metodología Buscador Estadísticas por Carrera 2025-2026, líneas 89 y 97):
  - Ingreso medio año k: 3 cohortes (2022-k .. 2024-k) con ingresos 2022-2024; >= 50 casos
    por año de ingreso. Año 1 = cohortes 2021-2023; año 5 = cohortes 2017-2019.
  - Percentiles: UNA sola cohorte, ingresos 2024; >= 11 casos. Año 1 = cohorte 2023;
    año 5 = cohorte 2019. Media y percentiles NO describen la misma población: no se
    combinan en una misma razón (p. ej. Media/P50 es inválida).
  - Derecho: cohorte de titulación + 1 año en ambos casos.

Unidades: porcentajes en escala 0-100 (float); ingresos en pesos de septiembre de 2025
(enteros). Los ingresos solo consideran titulados con ingreso >= sueldo mínimo (metodología
MiFuturo 2025-2026), así que los percentiles describen una distribución truncada abajo.

Claves de cruce: `clave_institucion` y `clave_carrera_generica` son el texto normalizado
con comun.normalizador.normalizar_texto (mismo criterio que Titulados). Las columnas
originales se conservan para mostrar nombres con tildes.
"""

from __future__ import annotations

# Diccionario de tipos de datos oficiales por columna (orden = orden de salida)
ESQUEMA_EMPLEABILIDAD = {
    # --- Identificación del programa (nivel institución x carrera) ---
    "id_institucion": "int64",             # = codigo_institucion SIES (verificado 105/105): llave de cruce
    "institucion": "object",
    "clave_institucion": "object",
    "tipo_institucion": "object",          # canónico: Universidad | IP | CFT
    "carrera": "object",
    "carrera_generica": "object",
    "clave_carrera_generica": "object",
    # --- Indicadores a nivel institución x carrera ---
    "acreditacion_anios": "int64",         # 0 = institución no acreditada
    "pct_continuidad_estudios": "float64", # cohortes 2021-2023, mismas que empleabilidad 1er año
    "duracion_real_semestres": "float64",  # titulados 2024
    "empleabilidad_1er_anio": "float64",   # cohortes 2021-2023
    "empleabilidad_2do_anio": "float64",   # cohortes 2020-2022
    # Tramo de ingreso al 4° año (cohortes 2018-2020) como intervalo; NULL = no publicado (< 11 casos SII)
    "ingreso_4to_anio_tramo_min": "Int64", # cota inferior del tramo, en pesos
    "ingreso_4to_anio_tramo_max": "Int64", # cota superior; nula en el tramo abierto "Sobre ..."
    # --- Indicadores a nivel nacional x tipo x carrera genérica ---
    # Ingreso medio: año k = cohortes (2022-k)..(2024-k), ingresos 2022-2024
    "ingreso_medio_1er_anio": "Int64",     # cohortes 2021-2023; Int64 nullable para tolerar nulos
    "ingreso_medio_2do_anio": "Int64",
    "ingreso_medio_3er_anio": "Int64",
    "ingreso_medio_4to_anio": "Int64",
    "ingreso_medio_5to_anio": "Int64",     # cohortes 2017-2019
    # Percentiles: una sola cohorte con ingresos 2024 (año 1 = cohorte 2023)
    "percentil_10_anio_1": "Int64",
    "percentil_25_anio_1": "Int64",
    "percentil_50_anio_1": "Int64",
    "percentil_75_anio_1": "Int64",
    "percentil_90_anio_1": "Int64",
    # Año 5 = cohorte 2019 (ingresos 2024)
    "percentil_10_anio_5": "Int64",
    "percentil_25_anio_5": "Int64",
    "percentil_50_anio_5": "Int64",
    "percentil_75_anio_5": "Int64",
    "percentil_90_anio_5": "Int64",
}
