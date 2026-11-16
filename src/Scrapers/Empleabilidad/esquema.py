"""
<src/Scrapers/Empleabilidad/esquema.py>

Definición del esquema oficial para la tabla procesada de Empleabilidad e Ingresos (MiFuturo).
El orden de las claves ES el orden de columnas del CSV de salida (procesar.py lo toma de aquí).

Fuente: Buscador de Empleabilidad e Ingresos.
Metodología: datos externos/EMPLEABILIDAD/Metodologia-Buscador-Empleabilidad-e-Ingresos_2025-2026.md

Granularidad: una fila = INSTITUCIÓN x CARRERA GENÉRICA (llave `id_institucion,
clave_carrera_generica`; 1.690 filas). Acreditación, continuidad de estudios, duración
real, empleabilidad 1er/2do año y tramo de ingreso al 4° año: es la única señal de
ingreso por institución. Los ingresos y percentiles NACIONALES por carrera genérica x
tipo viven en otra tabla (src/Scrapers/Estadisticas), para no repetirlos en cada fila.

Empleabilidad: % con ingreso >= sueldo mínimo ENTRE los titulados con registro de
ingresos en el SII (el denominador no son todos los titulados).

Unidades: porcentajes en escala 0-100 (float); montos en pesos de septiembre de 2025
(enteros). El tramo solo considera titulados con ingreso >= sueldo mínimo.

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
}
