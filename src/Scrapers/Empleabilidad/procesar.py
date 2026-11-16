"""
<src/Scrapers/Empleabilidad/procesar.py>

Módulo de procesamiento de la base de Empleabilidad e Ingresos (MiFuturo).

Entrada:  Entrada/empleabilidad_mifuturo.csv   (30 columnas, 1.690 filas)
Salida:   Salida/empleabilidad_procesado.csv   (columnas según esquema.py, 1.690 filas)

Transformaciones aplicadas:
  1. Selección:           se descartan `regiones_sede` (el proyecto no es regional),
                          `retencion_1er_anio` (mide matriculados 2024, no titulados) y
                          `ingreso_prom_4to_anio_tramo` (ver punto 4).
  2. Porcentajes:         fracción 0-1 → escala 0-100 con 1 decimal.
  3. Acreditación:        años desde la etiqueta de texto ("5 años" → 5, "No" → 0).
                          El campo numérico crudo tiene 103 nulos donde la etiqueta dice "No".
  4. Tramo ingreso 4° año: se parsea la ETIQUETA a cotas en pesos. El campo numérico crudo
                          (data-order del HTML) NO es ordinal: agrupa "s/i" con los tramos
                          ≥ $2,5 millones bajo el mismo código y desordena el resto.
                          La etiqueta no se publica: es biyectiva con (min, max) y sobra
                          (el texto original queda en Entrada/). Se guarda como intervalo,
                          nunca como punto medio: el tramo "Sobre ..." no tiene cota superior.
                          Los "s/i" quedan NULL y NO se imputan: MiFuturo no publica bajo 11
                          casos SII, y rellenar con el ingreso nacional del par copiaría el
                          promedio del centro y achicaría la dispersión entre instituciones.
  5. Tipo institución:    canónico Universidad | IP | CFT (comun.normalizador).
  6. Claves de cruce:     `clave_institucion` y `clave_carrera_generica` normalizadas; los
                          nombres originales se conservan para visualización.
  7. Validaciones:        solo de FORMA (columnas, rangos físicos, llave única). Las reglas
                          de negocio (constancia por par, cobertura de cruces) viven en SQL `qa`.
"""

from __future__ import annotations

import logging
import re
import sys
from pathlib import Path

import pandas as pd

# Agrega src/Scrapers al path para importar comun/ y esquema desde cualquier directorio.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from comun.normalizador import normalizar_texto, normalizar_tipo_institucion  # noqa: E402
from Empleabilidad.esquema import ESQUEMA_EMPLEABILIDAD  # noqa: E402

log = logging.getLogger(__name__)

# --------------------------------------------------------------------------- #
# Configuración
# --------------------------------------------------------------------------- #
DIR_ENTRADA = Path(__file__).parent / "Entrada"
DIR_SALIDA = Path(__file__).parent / "Salida"

ARCHIVO_ENTRADA = "empleabilidad_mifuturo.csv"
ARCHIVO_SALIDA = "empleabilidad_procesado.csv"
SEPARADOR_CSV = ";"

COLUMNAS_SALIDA = list(ESQUEMA_EMPLEABILIDAD)
# PK del modelo en BD: MiFuturo publica una fila por institución × carrera genérica (T0).
# El nombre de `carrera` no sirve de llave: es texto libre que cambia entre publicaciones.
LLAVE = ["id_institucion", "clave_carrera_generica"]

COLUMNAS_PORCENTAJE = [
    "pct_continuidad_estudios",
    "empleabilidad_1er_anio",
    "empleabilidad_2do_anio",
]

COLUMNAS_INGRESOS = [c for c in COLUMNAS_SALIDA if c.startswith(("ingreso_medio_", "percentil_"))]

ETIQUETA_SIN_INFO = "s/i"


# --------------------------------------------------------------------------- #
# Carga
# --------------------------------------------------------------------------- #
def cargar_entrada() -> pd.DataFrame:
    """Lee el CSV crudo de empleabilidad MiFuturo."""
    ruta = DIR_ENTRADA / ARCHIVO_ENTRADA
    if not ruta.exists():
        raise FileNotFoundError(f"No se encontró {ruta}. Ejecutar primero obtener.py.")
    df = pd.read_csv(ruta, sep=SEPARADOR_CSV)
    log.info("Cargado %s: %d filas × %d columnas", ruta.name, len(df), len(df.columns))
    return df


# --------------------------------------------------------------------------- #
# Transformaciones
# --------------------------------------------------------------------------- #
def _monto_en_pesos(texto: str) -> int:
    """'$1 millón 100 mil' → 1_100_000; '$900 mil' → 900_000; '$2 millones' → 2_000_000."""
    m = re.fullmatch(r"\$\s*(?:(\d+)\s*mill(?:ón|ones))?\s*(?:(\d+)\s*mil)?", texto.strip())
    if not m or not any(m.groups()):
        raise ValueError(f"Monto no reconocido en tramo de ingreso: {texto!r}")
    millones, miles = (int(g) if g else 0 for g in m.groups())
    return millones * 1_000_000 + miles * 1_000


def parsear_tramo(etiqueta: str) -> tuple[int | None, int | None]:
    """
    Etiqueta del tramo → (cota_min, cota_max) en pesos.
    Falla ante un formato nuevo: un tramo mal leído movería instituciones de posición sin aviso.
    """
    texto = (etiqueta or "").strip()
    if texto == ETIQUETA_SIN_INFO:
        return None, None
    if m := re.fullmatch(r"(?:De|Desde)\s+(\$.+?)\s+a\s+(\$.+)", texto):
        return _monto_en_pesos(m.group(1)), _monto_en_pesos(m.group(2))
    if m := re.fullmatch(r"Sobre\s+(\$.+)", texto):
        return _monto_en_pesos(m.group(1)), None
    raise ValueError(f"Tramo de ingreso no reconocido: {etiqueta!r}")


def _acreditacion_anios(etiqueta: str) -> int:
    """'5 años' → 5; 'No' → 0."""
    texto = normalizar_texto(etiqueta)
    if texto == "NO":
        return 0
    if m := re.fullmatch(r"(\d+) ANOS?", texto):
        return int(m.group(1))
    raise ValueError(f"Acreditación no reconocida: {etiqueta!r}")


def transformar(df: pd.DataFrame) -> pd.DataFrame:
    """Aplica todas las transformaciones y devuelve la tabla con el esquema de salida."""
    out = pd.DataFrame()
    out["id_institucion"] = df["id_institucion"].astype("int64")

    # Texto: se colapsan espacios; las claves de cruce se normalizan aparte.
    for col in ["institucion", "carrera", "carrera_generica"]:
        out[col] = df[col].astype(str).str.replace(r"\s+", " ", regex=True).str.strip()
    out["clave_institucion"] = out["institucion"].map(normalizar_texto)
    out["clave_carrera_generica"] = out["carrera_generica"].map(normalizar_texto)
    out["tipo_institucion"] = df["tipo_institucion"].map(normalizar_tipo_institucion)

    out["acreditacion_anios"] = df["acreditacion_institucion"].map(_acreditacion_anios).astype("int64")
    out["duracion_real_semestres"] = pd.to_numeric(df["duracion_real_semestres"], errors="coerce")

    for col in COLUMNAS_PORCENTAJE:
        out[col] = (pd.to_numeric(df[col], errors="coerce") * 100.0).round(1)

    etiquetas = df["ingreso_prom_4to_anio"].astype(str).str.strip()
    cotas = etiquetas.map(parsear_tramo)
    out["ingreso_4to_anio_tramo_min"] = pd.array([c[0] for c in cotas], dtype="Int64")
    out["ingreso_4to_anio_tramo_max"] = pd.array([c[1] for c in cotas], dtype="Int64")

    for col in COLUMNAS_INGRESOS:
        out[col] = pd.to_numeric(df[col], errors="coerce").round().astype("Int64")

    return out[COLUMNAS_SALIDA].astype(ESQUEMA_EMPLEABILIDAD)


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
    if df["clave_carrera_generica"].eq("").any():
        errores.append("hay carreras genéricas vacías")

    for col in COLUMNAS_PORCENTAJE:
        s = df[col].dropna()
        if ((s < 0) | (s > 100)).any():
            errores.append(f"{col} fuera de [0, 100]")
    for col in COLUMNAS_INGRESOS + ["ingreso_4to_anio_tramo_min", "ingreso_4to_anio_tramo_max"]:
        if (df[col].dropna() <= 0).any():
            errores.append(f"{col} con valores <= 0")
    if (df["ingreso_4to_anio_tramo_max"] <= df["ingreso_4to_anio_tramo_min"]).fillna(False).any():
        errores.append("tramo de ingreso con cota máxima <= mínima")

    if errores:
        raise ValueError("Validación de Empleabilidad falló:\n  - " + "\n  - ".join(errores))

    log.info("Validaciones OK: %d filas, llave %s única, rangos válidos", len(df), LLAVE)
    for col in df.columns:
        pct = 100 * df[col].notna().mean()
        if pct < 100:
            log.info("  cobertura %-28s %6.1f%%", col, pct)


# --------------------------------------------------------------------------- #
# Orquestador
# --------------------------------------------------------------------------- #
def procesar_empleabilidad() -> Path:
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
    procesar_empleabilidad()
