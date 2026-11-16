"""
<src/Scrapers/Estadisticas/procesar.py>

Módulo de procesamiento del Buscador de Estadísticas por Carrera (MiFuturo).

Entrada:  Entrada/estadisticas_mifuturo.csv   (JSON completo de cada par, como texto)
Salida:   Salida/estadisticas_procesado.csv   (columnas según esquema.py, una fila por par)

Transformaciones aplicadas:
  1. Selección y nombres: esquema.ORIGEN fija qué campo de la API alimenta cada columna
     (ahí se documentan los nombres con años viejos). Falla si falta algún campo: un
     cambio de la API no debe convertirse en una columna vacía en silencio.
  2. Porcentajes:  fracción 0-1 → escala 0-100 con 1 decimal (igual que Empleabilidad).
  3. Montos:       ingresos y conteos a enteros; vienen como texto "699656.000".
  4. Tipo institución: canónico Universidad | IP | CFT (comun.normalizador).
  5. Clave de cruce: `clave_carrera_generica` con normalizar_texto, la misma regla que
     Empleabilidad y Titulados.
  6. Validaciones: solo de FORMA (llave única, rangos físicos, orden de percentiles).
     La correspondencia campo → cohorte se verifica en SQL `qa` (src/BD), porque es una
     regla de negocio que necesita los 252 pares a la vez.
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

import pandas as pd

# Agrega src/Scrapers al path para importar comun/ y esquema desde cualquier directorio.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from comun.normalizador import normalizar_texto, normalizar_tipo_institucion  # noqa: E402
from Estadisticas.esquema import ESQUEMA_ESTADISTICAS, ORIGEN  # noqa: E402

log = logging.getLogger(__name__)

# --------------------------------------------------------------------------- #
# Configuración
# --------------------------------------------------------------------------- #
DIR_ENTRADA = Path(__file__).parent / "Entrada"
DIR_SALIDA = Path(__file__).parent / "Salida"

ARCHIVO_ENTRADA = "estadisticas_mifuturo.csv"
ARCHIVO_SALIDA = "estadisticas_procesado.csv"
SEPARADOR_CSV = ";"

COLUMNAS_SALIDA = list(ESQUEMA_ESTADISTICAS)
LLAVE = ["clave_carrera_generica", "tipo_institucion"]

COLUMNAS_PORCENTAJE = [c for c in COLUMNAS_SALIDA if c.startswith("empleabilidad_")]
COLUMNAS_INGRESO = [c for c in COLUMNAS_SALIDA if c.startswith(("ingreso_medio_", "percentil_"))]
COLUMNAS_CONTEO = [c for c in COLUMNAS_SALIDA if c.startswith("titulados_")]
COLUMNAS_DURACION = ["duracion_formal_semestres", "duracion_real_semestres"]
PERCENTILES = (10, 25, 50, 75, 90)
DURACION_MAX_SEMESTRES = 30



# --------------------------------------------------------------------------- #
# Carga
# --------------------------------------------------------------------------- #
def cargar_entrada(ruta: Path | None = None) -> pd.DataFrame:
    """Lee el crudo como texto: la interpretación de tipos es responsabilidad de transformar()."""
    ruta = ruta or DIR_ENTRADA / ARCHIVO_ENTRADA
    if not ruta.exists():
        raise FileNotFoundError(f"No se encontró {ruta}. Ejecutar primero obtener.py.")
    df = pd.read_csv(ruta, sep=SEPARADOR_CSV, dtype=str, keep_default_na=False, na_values=[""])
    log.info("Cargado %s: %d filas × %d columnas", ruta.name, len(df), len(df.columns))
    return df


# --------------------------------------------------------------------------- #
# Transformaciones
# --------------------------------------------------------------------------- #
def transformar(df: pd.DataFrame) -> pd.DataFrame:
    """Aplica todas las transformaciones y devuelve la tabla con el esquema de salida."""
    faltantes = sorted(set(ORIGEN.values()) - set(df.columns))
    if faltantes:
        raise ValueError(f"La API ya no entrega estos campos de ORIGEN: {faltantes}")

    out = pd.DataFrame({col: df[campo] for col, campo in ORIGEN.items()})

    out["id_estadisticas"] = out["id_estadisticas"].astype("int64")
    out["tipo_institucion"] = out["tipo_institucion"].map(normalizar_tipo_institucion)
    out["carrera_generica"] = out["carrera_generica"].str.replace(r"\s+", " ", regex=True).str.strip()
    out["clave_carrera_generica"] = out["carrera_generica"].map(normalizar_texto)

    for col in COLUMNAS_PORCENTAJE:
        out[col] = (pd.to_numeric(out[col], errors="raise") * 100.0).round(1)
    for col in COLUMNAS_INGRESO + COLUMNAS_CONTEO:
        out[col] = pd.to_numeric(out[col], errors="raise").round().astype("Int64")
    for col in COLUMNAS_DURACION:
        out[col] = pd.to_numeric(out[col], errors="raise")

    return out[COLUMNAS_SALIDA].astype(ESQUEMA_ESTADISTICAS)


# --------------------------------------------------------------------------- #
# Validaciones (solo de forma; fallan en vez de advertir)
# --------------------------------------------------------------------------- #
def validar(df: pd.DataFrame, n_entrada: int) -> None:
    """Controles de forma. Cualquier falla detiene el proceso: un CSV inválido no debe llegar a SQL."""
    errores: list[str] = []

    if len(df) != n_entrada:
        errores.append(f"filas de salida ({len(df)}) != filas de entrada ({n_entrada})")
    if (dup := df.duplicated(LLAVE).sum()):
        errores.append(f"{dup} duplicados en la llave {LLAVE}")
    if df["id_estadisticas"].duplicated().any():
        errores.append("id_estadisticas repetido")
    if df["clave_carrera_generica"].eq("").any():
        errores.append("hay carreras genéricas vacías")

    for col in COLUMNAS_PORCENTAJE:
        s = df[col].dropna()
        if ((s < 0) | (s > 100)).any():
            errores.append(f"{col} fuera de [0, 100]")
    for col in COLUMNAS_INGRESO:
        if (df[col].dropna() <= 0).any():
            errores.append(f"{col} con valores <= 0 (¿la API usa 0 como 'sin dato'?)")
    for col in COLUMNAS_CONTEO:
        if (df[col].dropna() < 0).any():
            errores.append(f"{col} con valores negativos")
    for col in COLUMNAS_DURACION:
        s = df[col].dropna()
        if ((s <= 0) | (s > DURACION_MAX_SEMESTRES)).any():
            errores.append(f"{col} fuera de (0, {DURACION_MAX_SEMESTRES}]")

    # Un percentil menor que el anterior es imposible por definición: señal de columnas cruzadas.
    for anio in (1, 5):
        cols = [f"percentil_{p}_anio_{anio}" for p in PERCENTILES]
        bloque = df[cols].dropna()
        if (bloque.diff(axis=1).iloc[:, 1:] < 0).any().any():
            errores.append(f"percentiles del año {anio} no crecientes")

    suma_sexo = df["titulados_2024_mujeres"] + df["titulados_2024_hombres"]
    if (suma_sexo > df["titulados_2024"]).fillna(False).any():
        errores.append("titulados por sexo suman más que el total")

    if errores:
        raise ValueError("Validación de Estadísticas falló:\n  - " + "\n  - ".join(errores))

    log.info("Validaciones OK: %d pares, llave %s única, rangos válidos", len(df), LLAVE)
    for col in df.columns:
        pct = 100 * df[col].notna().mean()
        if pct < 100:
            log.info("  cobertura %-40s %6.1f%%", col, pct)


# --------------------------------------------------------------------------- #
# Orquestador
# --------------------------------------------------------------------------- #
def procesar_estadisticas() -> Path:
    """Pipeline completo. Devuelve la ruta del CSV generado en Salida/."""
    crudo = cargar_entrada()
    df = transformar(crudo)
    validar(df, len(crudo))

    DIR_SALIDA.mkdir(parents=True, exist_ok=True)
    destino = DIR_SALIDA / ARCHIVO_SALIDA
    df.to_csv(destino, sep=SEPARADOR_CSV, index=False, encoding="utf-8")
    log.info("CSV generado: %s (%d filas, %d columnas, %.2f MB)",
             destino, len(df), len(df.columns), destino.stat().st_size / 1024**2)
    return destino


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    procesar_estadisticas()
