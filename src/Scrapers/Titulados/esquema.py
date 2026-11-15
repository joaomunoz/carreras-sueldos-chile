"""
<src/Scrapers/Titulados/esquema.py>

Definición del esquema oficial para la tabla procesada de Titulados (SIES).
El orden de las claves ES el orden de columnas del CSV de salida (procesar.py lo toma de aquí).

Granularidad: una fila = un PROGRAMA en un año (llave única `anio, codigo_programa`).
El código de programa SIES distingue institución, sede, carrera, jornada y versión
(ej. 'I1S1C12J2V4'); sin él, programas distintos quedaban como filas idénticas.

Unidad de conteo: TITULACIONES, no personas. Una persona puede titularse más de una vez
(técnico + continuidad profesional, licenciatura no conducente + título). El filtro de
"título terminal" se decide aguas abajo con `carrera_clasificacion_nivel_1` y `tipo_plan`.

Edad: tramos de edad AL TITULARSE. Un vacío en el crudo significa 0 titulaciones
(verificado: los 7 tramos suman TOTAL TITULACIONES en el 100% de las filas), por eso los
conteos son int64 sin nulos. edad_promedio sí tiene nulos reales (Int64 no aplica: es decimal).
"""

from __future__ import annotations

# Diccionario de tipos de datos oficiales por columna (orden = orden de salida)
ESQUEMA_TITULADOS = {
    # --- Identificación del programa ---
    "anio": "int64",                          # año de titulación (marzo a febrero desde 2017)
    "codigo_programa": "object",
    "codigo_institucion": "int64",            # = id_institucion de MiFuturo: llave de cruce
    "institucion": "object",
    "clave_institucion": "object",
    "tipo_institucion": "object",             # canónico: Universidad | IP | CFT
    "subtipo_institucion": "object",          # Universidades CRUCH | Universidades Privadas | IP | CFT
    "carrera": "object",
    "carrera_generica": "object",
    "clave_carrera_generica": "object",
    "cine13_area": "object",
    "cine13_subarea": "object",
    # --- Clasificación del programa ---
    "nivel_carrera": "object",                # Carreras Técnicas | Carreras Profesionales
    "carrera_clasificacion_nivel_1": "object",
    "tipo_plan": "object",
    "modalidad": "object",
    "jornada": "object",
    "duracion_semestres": "float64",          # duración formal del plan de estudios
    # --- Titulaciones por sexo ---
    "total_titulaciones": "int64",
    "titulaciones_mujeres": "int64",
    "titulaciones_hombres": "int64",
    "titulaciones_nb": "int64",
    # --- Titulaciones por tramo de edad al titularse ---
    "titulados_15_19": "int64",
    "titulados_20_24": "int64",
    "titulados_25_29": "int64",
    "titulados_30_34": "int64",
    "titulados_35_39": "int64",
    "titulados_mayores_40": "int64",
    "titulados_edad_sin_info": "int64",
    "edad_promedio": "float64",
}
