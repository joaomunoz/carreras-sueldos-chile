"""
<src/Scrapers/Estadisticas/obtener.py>

Módulo de extracción del Buscador de Estadísticas por Carrera desde mifuturo.cl.

Estrategia:
  1. Catálogo: 1 POST al formulario `nameTab=estadisticas` sin filtros. Devuelve la tabla
     de pares (tipo de institución, carrera genérica) con el id de cada ficha en el
     `onclick="verestadisticas('<id>')"`. La metodología 2025-2026 declara 252 pares.
  2. Detalle: 1 POST AJAX `detalleEstadisticas(id)` por par. Devuelve un JSON plano de
     ~73 campos (ingresos, percentiles, empleabilidad, series de 5 cohortes, titulados,
     duración, matrícula, retención).

Se guarda el JSON COMPLETO de cada par, como texto y sin interpretar: qué campo significa
qué cohorte se decide en esquema.py (ORIGEN), no aquí. Así el crudo sirve de evidencia
si MiFuturo cambia el significado de un campo.

Falla si algún par no se pudo descargar: un par ausente en silencio sesgaría la cobertura
por segmento, que es justamente lo que el análisis reporta.

Uso:
  python3 Estadisticas/obtener.py              # los 252 pares
  python3 Estadisticas/obtener.py --limite 3   # prueba con los 3 primeros (no sobrescribe)

Salida: Entrada/estadisticas_mifuturo.csv  (separador ';', UTF-8; prueba: *_prueba.csv)
"""

from __future__ import annotations

import argparse
import logging
import re
import time
from pathlib import Path

import pandas as pd
import requests

log = logging.getLogger(__name__)

# --------------------------------------------------------------------------- #
# Configuración
# --------------------------------------------------------------------------- #
URL_BUSCADOR = "https://www.mifuturo.cl/buscador-de-estadisticas-por-carrera/"
URL_AJAX = "https://www.mifuturo.cl/wp-admin/admin-ajax.php"

DIR_ENTRADA = Path(__file__).parent / "Entrada"
NOMBRE_SALIDA = "estadisticas_mifuturo.csv"
SEPARADOR_CSV = ";"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/124.0 Safari/537.36",
    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
}

INTENTOS = 3
PAUSA_ENTRE_LLAMADAS = 0.15   # segundos; el servidor corta conexiones si se le satura


def _sesion() -> requests.Session:
    """Sesión HTTP con headers compartidos."""
    s = requests.Session()
    s.headers.update(HEADERS)
    return s


def _texto_celda(td: str) -> str:
    """Texto visible de una celda, sin el link "Ver estadísticas" ni etiquetas HTML."""
    td = re.sub(r"<a\b.*?</a>", "", td or "", flags=re.S)
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", td)).strip()


# --------------------------------------------------------------------------- #
# Catálogo
# --------------------------------------------------------------------------- #
def obtener_catalogo(s: requests.Session) -> pd.DataFrame:
    """Pares publicados: id de ficha + tipo y carrera tal como los muestra el catálogo."""
    resp = s.post(
        URL_BUSCADOR,
        data={"nameTab": "estadisticas", "areaConocimiento_est": "",
              "tipo_institucion_est": "", "institucionEst": "", "carreraEst": ""},
        timeout=180,
    )
    resp.raise_for_status()
    bloque = re.search(r'<table id="table_id".*?</table>', resp.text, re.S)
    if not bloque:
        raise RuntimeError("no se encontró la tabla de estadísticas por carrera (¿cambió el HTML?)")

    filas = []
    for tr in re.findall(r"<tr[^>]*>(.*?)</tr>", bloque.group(0), re.S):
        tds = re.findall(r"<td[^>]*>(.*?)</td>", tr, re.S)
        m_id = re.search(r"verestadisticas\('(\d+)'\)", tr)
        if len(tds) >= 2 and m_id:
            filas.append({"id_catalogo": m_id.group(1),
                          "tipo_catalogo": _texto_celda(tds[0]),
                          "carrera_catalogo": _texto_celda(tds[1])})

    cat = pd.DataFrame(filas)
    if cat.empty:
        raise RuntimeError("el catálogo de estadísticas llegó vacío")
    if cat["id_catalogo"].duplicated().any():
        raise RuntimeError("el catálogo trae ids repetidos")
    log.info("catálogo: %d pares", len(cat))
    return cat


# --------------------------------------------------------------------------- #
# Detalle por par
# --------------------------------------------------------------------------- #
def obtener_detalle(s: requests.Session, id_est: str) -> dict:
    """JSON completo de una ficha. Lanza error si falla tras los reintentos."""
    ultimo_error: Exception | None = None
    for intento in range(1, INTENTOS + 1):
        try:
            resp = s.post(URL_AJAX, data={"action": "detalleEstadisticas", "id": id_est}, timeout=60)
            resp.raise_for_status()
            datos = resp.json()
            if not isinstance(datos, dict) or not datos:
                raise ValueError(f"respuesta vacía o no es un objeto: {resp.text[:80]!r}")
            return datos
        except Exception as exc:  # noqa: BLE001 - se reintenta y luego se propaga
            ultimo_error = exc
            espera = 2.0 * intento
            log.warning("detalle %s (intento %d/%d) falló: %s; espero %.0fs",
                        id_est, intento, INTENTOS, exc, espera)
            time.sleep(espera)
    raise RuntimeError(f"detalle {id_est} falló tras {INTENTOS} intentos: {ultimo_error}")


# --------------------------------------------------------------------------- #
# Orquestador
# --------------------------------------------------------------------------- #
def obtener_estadisticas(limite: int | None = None) -> Path:
    """
    Descarga catálogo + detalle de cada par y escribe el crudo en Entrada/.

    Args:
        limite: si se indica, solo los primeros N pares y a un archivo *_prueba.csv,
                para no pisar el crudo completo.
    """
    DIR_ENTRADA.mkdir(parents=True, exist_ok=True)
    s = _sesion()
    cat = obtener_catalogo(s)
    if limite is not None:
        cat = cat.head(limite)

    registros, fallidos = [], []
    for i, fila in enumerate(cat.itertuples(index=False), start=1):
        try:
            detalle = obtener_detalle(s, fila.id_catalogo)
        except RuntimeError as exc:
            log.error("%s", exc)
            fallidos.append(fila.id_catalogo)
            continue
        registros.append({**fila._asdict(), **detalle})
        if i % 25 == 0:
            log.info("  %d/%d pares descargados", i, len(cat))
        time.sleep(PAUSA_ENTRE_LLAMADAS)

    if fallidos:
        raise RuntimeError(f"{len(fallidos)} pares sin descargar (ids {fallidos}); no se escribe el crudo")

    df = pd.DataFrame(registros)
    nombre = NOMBRE_SALIDA if limite is None else NOMBRE_SALIDA.replace(".csv", "_prueba.csv")
    destino = DIR_ENTRADA / nombre
    df.to_csv(destino, sep=SEPARADOR_CSV, index=False, encoding="utf-8")
    log.info("CSV generado: %s (%d pares, %d columnas)", destino, len(df), len(df.columns))
    return destino


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    parser = argparse.ArgumentParser(description="Descarga el Buscador de Estadísticas por Carrera.")
    parser.add_argument("--limite", type=int, default=None, help="solo los primeros N pares (prueba)")
    obtener_estadisticas(parser.parse_args().limite)
