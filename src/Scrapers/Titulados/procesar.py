"""
<src/Scrapers/Titulados/procesar.py>

Módulo de procesamiento de la base de Titulados SIES.

Entrada:  Entrada/titulados_2007_2025.xlsx   (42 columnas, 234.074 filas)
Salida:   Salida/titulados_procesado.csv     (columnas según esquema.py)

Alcance (decisión del proyecto "Trayectoria salarial por carrera"):
  - Solo NIVEL GLOBAL = Pregrado: MiFuturo publica empleabilidad e ingresos solo de pregrado.
    Posgrado y postítulo no tienen contraparte con la que cruzar.
  - Solo años 2017-2025: cubre todas las cohortes que usa MiFuturo 2025-2026 (ingreso al 5° año =
    2017-2019; empleabilidad al 1er año = 2021-2023) y 2025 como foto más reciente. Además, desde
    2017 el año de titulación es académico (marzo a febrero) en ambas fuentes.
  - Se conservan los niveles no terminales (Licenciatura No Conducente, planes de continuidad):
    el filtro de "título terminal" se decide aguas abajo, en SQL, donde queda documentado y testeado.

Transformaciones aplicadas:
  1. Año:                 'TIT_2025' → 2025.
  2. Llave:               se conserva CÓDIGO PROGRAMA, única por año. Sin ella, el procesado
                          anterior dejaba 99 filas idénticas que eran programas distintos
                          (otra jornada o sede de la misma comuna), no duplicados.
  3. Conteos:             vacío → 0 (en el crudo un vacío significa 0 titulaciones).
  4. Tipo institución:    canónico Universidad | IP | CFT (comun.normalizador), más el
                          subtipo CRUCH / Privadas, que separa riesgo dentro de Universidad.
  5. Claves de cruce:     `clave_institucion` y `clave_carrera_generica` normalizadas; los
                          nombres originales se conservan para visualización.
  6. Edad promedio:       1 decimal (antes se redondeaba a entero y se perdía precisión).
  7. Descartes:           región, comuna, provincia y sede (el proyecto no es regional; la
                          sede ya está codificada en el código de programa), CINE-F 97 y área
                          del conocimiento (se usa CINE-F 13), promedios de edad por sexo.
  8. Validaciones:        solo de FORMA (llave única, sumas de sexo y edad, rangos físicos).
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

import pandas as pd

# Agrega src/Scrapers al path para importar comun/ y esquema desde cualquier directorio.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from comun.normalizador import normalizar_texto, normalizar_tipo_institucion  # noqa: E402
from Titulados.esquema import ESQUEMA_TITULADOS  # noqa: E402

log = logging.getLogger(__name__)

# --------------------------------------------------------------------------- #
# Configuración
# --------------------------------------------------------------------------- #
DIR_ENTRADA = Path(__file__).parent / "Entrada"
DIR_SALIDA = Path(__file__).parent / "Salida"

ARCHIVO_ENTRADA = "titulados_2007_2025.xlsx"
HOJA_ENTRADA = "in"
ARCHIVO_SALIDA = "titulados_procesado.csv"
SEPARADOR_CSV = ";"

NIVEL_GLOBAL = "Pregrado"
ANIO_MIN, ANIO_MAX = 2017, 2025

COLUMNAS_SALIDA = list(ESQUEMA_TITULADOS)
LLAVE = ["anio", "codigo_programa"]

# Columnas crudas → nombre de salida (las que pasan sin transformación de contenido).
RENOMBRAR = {
    "CÓDIGO PROGRAMA": "codigo_programa",
    "CÓDIGO INSTITUCIÓN": "codigo_institucion",
    "NOMBRE INSTITUCIÓN": "institucion",
    "NOMBRE CARRERA": "carrera",
    "ÁREA CARRERA GENÉRICA": "carrera_generica",
    "CINE-F_13 ÁREA": "cine13_area",
    "CINE-F_13 SUBAREA": "cine13_subarea",
    "CARRERA CLASIFICACIÓN NIVEL 2": "nivel_carrera",
    "CARRERA CLASIFICACIÓN NIVEL 1": "carrera_clasificacion_nivel_1",
    "TIPO DE PLAN DE LA CARRERA": "tipo_plan",
    "MODALIDAD": "modalidad",
    "JORNADA": "jornada",
    "DURACIÓN ESTUDIO CARRERA": "duracion_semestres",
    "PROMEDIO EDAD PROGRAMA": "edad_promedio",
}

COLUMNAS_TEXTO = ["institucion", "carrera", "carrera_generica", "cine13_area", "cine13_subarea",
                  "nivel_carrera", "carrera_clasificacion_nivel_1", "tipo_plan", "modalidad",
                  "jornada", "codigo_programa"]

# Conteos: vacío en el crudo = 0 titulaciones.
CONTEOS = {
    "TOTAL TITULACIONES": "total_titulaciones",
    "TITULACIONES MUJERES POR PROGRAMA": "titulaciones_mujeres",
    "TITULACIONES HOMBRES POR PROGRAMA": "titulaciones_hombres",
    "TITULACIONES NB E INDEFINIDO POR PROGRAMA": "titulaciones_nb",
    "RANGO DE EDAD 15 A 19 AÑOS": "titulados_15_19",
    "RANGO DE EDAD 20 A 24 AÑOS": "titulados_20_24",
    "RANGO DE EDAD 25 A 29 AÑOS": "titulados_25_29",
    "RANGO DE EDAD 30 A 34 AÑOS": "titulados_30_34",
    "RANGO DE EDAD 35 A 39 AÑOS": "titulados_35_39",
    "RANGO DE EDAD 40 Y MÁS AÑOS": "titulados_mayores_40",
    "RANGO DE EDAD SIN INFORMACIÓN": "titulados_edad_sin_info",
}
SEXOS = ["titulaciones_mujeres", "titulaciones_hombres", "titulaciones_nb"]
TRAMOS_EDAD = [c for c in CONTEOS.values() if c.startswith("titulados_")]

EDAD_MIN, EDAD_MAX = 15, 80
DURACION_MAX_SEMESTRES = 30


# --------------------------------------------------------------------------- #
# Carga
# --------------------------------------------------------------------------- #
def cargar_entrada() -> pd.DataFrame:
    """Lee el Excel histórico de titulados."""
    ruta = DIR_ENTRADA / ARCHIVO_ENTRADA
    if not ruta.exists():
        raise FileNotFoundError(f"No se encontró {ruta}. Ejecutar primero obtener.py.")
    log.info("Leyendo %s (tarda ~1 minuto)", ruta.name)
    df = pd.read_excel(ruta, sheet_name=HOJA_ENTRADA)
    log.info("Cargado: %d filas × %d columnas", len(df), len(df.columns))
    return df


# --------------------------------------------------------------------------- #
# Transformaciones
# --------------------------------------------------------------------------- #
def filtrar_alcance(df: pd.DataFrame) -> pd.DataFrame:
    """Pregrado, años ANIO_MIN..ANIO_MAX (ver docstring del módulo)."""
    anio = df["AÑO"].astype(str).str.extract(r"(\d{4})", expand=False)
    if anio.isna().any():
        raise ValueError(f"AÑO no parseable en {anio.isna().sum()} filas")
    df = df.assign(anio=anio.astype("int64"))
    filtrado = df[(df["NIVEL GLOBAL"] == NIVEL_GLOBAL) & df["anio"].between(ANIO_MIN, ANIO_MAX)]
    log.info("Alcance %s %d-%d: %d → %d filas", NIVEL_GLOBAL, ANIO_MIN, ANIO_MAX, len(df), len(filtrado))
    return filtrado


def transformar(df: pd.DataFrame) -> pd.DataFrame:
    """Aplica todas las transformaciones y devuelve la tabla con el esquema de salida."""
    out = df[list(RENOMBRAR)].rename(columns=RENOMBRAR)
    out.insert(0, "anio", df["anio"])

    for col in COLUMNAS_TEXTO:
        texto = out[col].astype("string").str.replace(r"\s+", " ", regex=True).str.strip()
        out[col] = texto.replace("", pd.NA).astype(object)

    out["codigo_institucion"] = out["codigo_institucion"].astype("int64")
    out["clave_institucion"] = out["institucion"].map(normalizar_texto)
    out["clave_carrera_generica"] = out["carrera_generica"].map(normalizar_texto)
    out["tipo_institucion"] = df["CLASIFICACIÓN INSTITUCIÓN NIVEL 1"].map(normalizar_tipo_institucion)
    out["subtipo_institucion"] = df["CLASIFICACIÓN INSTITUCIÓN NIVEL 2"].astype(str).str.strip()

    for crudo, nombre in CONTEOS.items():
        out[nombre] = pd.to_numeric(df[crudo], errors="coerce").fillna(0).astype("int64")

    out["edad_promedio"] = pd.to_numeric(out["edad_promedio"], errors="coerce").round(1)
    out["duracion_semestres"] = pd.to_numeric(out["duracion_semestres"], errors="coerce")

    # Se falla si el esquema y las transformaciones divergen: una columna en uno solo
    # quedaría fuera del CSV sin aviso.
    sobrantes, faltantes = set(out) - set(COLUMNAS_SALIDA), set(COLUMNAS_SALIDA) - set(out)
    if sobrantes or faltantes:
        raise KeyError(f"Esquema y transformación divergen. Sin esquema: {sorted(sobrantes)}; "
                       f"faltan: {sorted(faltantes)}")
    return out[COLUMNAS_SALIDA].astype(ESQUEMA_TITULADOS).reset_index(drop=True)


# --------------------------------------------------------------------------- #
# Validaciones (solo de forma; fallan en vez de advertir)
# --------------------------------------------------------------------------- #
def validar(df: pd.DataFrame) -> None:
    """Controles de forma. Cualquier falla detiene el proceso: un CSV inválido no debe llegar a SQL."""
    errores: list[str] = []

    if (dup := df.duplicated(LLAVE).sum()):
        errores.append(f"{dup} duplicados en la llave {LLAVE}")
    if (n := (df[SEXOS].sum(axis=1) != df["total_titulaciones"]).sum()):
        errores.append(f"{n} filas donde la suma por sexo != total")
    if (n := (df[TRAMOS_EDAD].sum(axis=1) != df["total_titulaciones"]).sum()):
        errores.append(f"{n} filas donde la suma de tramos de edad != total")
    if (df[list(CONTEOS.values())] < 0).any().any():
        errores.append("conteos negativos")
    if (n := df["tipo_institucion"].isna().sum()):
        errores.append(f"{n} filas sin tipo de institución")
    if df["clave_carrera_generica"].eq("").any():
        errores.append("hay carreras genéricas vacías")

    edad = df["edad_promedio"].dropna()
    if ((edad < EDAD_MIN) | (edad > EDAD_MAX)).any():
        errores.append(f"edad_promedio fuera de [{EDAD_MIN}, {EDAD_MAX}]")
    dur = df["duracion_semestres"].dropna()
    if ((dur <= 0) | (dur > DURACION_MAX_SEMESTRES)).any():
        errores.append(f"duracion_semestres fuera de (0, {DURACION_MAX_SEMESTRES}]")

    if errores:
        raise ValueError("Validación de Titulados falló:\n  - " + "\n  - ".join(errores))

    log.info("Validaciones OK: %d filas, llave %s única, sumas de sexo y edad cuadran", len(df), LLAVE)
    for col in df.columns:
        pct = 100 * df[col].notna().mean()
        if pct < 100:
            log.info("  cobertura %-30s %6.1f%%", col, pct)


# --------------------------------------------------------------------------- #
# Orquestador
# --------------------------------------------------------------------------- #
def procesar_titulados() -> Path:
    """Pipeline completo. Devuelve la ruta del CSV generado en Salida/."""
    df = transformar(filtrar_alcance(cargar_entrada()))
    validar(df)

    DIR_SALIDA.mkdir(parents=True, exist_ok=True)
    destino = DIR_SALIDA / ARCHIVO_SALIDA
    df.to_csv(destino, sep=SEPARADOR_CSV, index=False, encoding="utf-8")
    log.info("CSV generado: %s (%d filas, %d columnas, %.1f MB)",
             destino, len(df), len(df.columns), destino.stat().st_size / 1024**2)
    return destino


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    procesar_titulados()
