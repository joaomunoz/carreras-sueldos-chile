"""
<src/BD/build.py>

Build de la base `carreras_sueldos`: recrea `raw` y `modelo`, carga los CSV de los
scrapers y puebla el modelo. Uso (desde la raíz del proyecto):

    python3 src/BD/build.py

Conexión: solo por variables de entorno de libpq (PGDATABASE, y si hiciera falta PGHOST,
PGUSER...). No hay credenciales en el código; con auth `peer` basta PGDATABASE.

Todo el build corre en UNA transacción: si cualquier paso falla (un CHECK, una FK, un
supuesto roto), PostgreSQL revierte todo y la base queda como estaba antes del build.
Sin esto, un build fallido dejaría `raw` y `modelo` borrados o a medio cargar.

Pasos:
  1. src/BD/01_raw.sql          crea el esquema raw (vacío)
  2. src/BD/02_modelo.sql       crea el esquema modelo (vacío, salvo modelo.cohorte)
  3. COPY de los 3 CSV a raw    HEADER MATCH: el encabezado del CSV debe coincidir, en
                                nombre y orden, con las columnas de la tabla
  4. src/BD/03_poblar_modelo.sql  de raw a modelo
  5. Verificación de conteos    filas de cada CSV = raw = hecho en modelo
"""

from __future__ import annotations

import csv
import logging
import os
import sys
import time
from pathlib import Path

import psycopg

log = logging.getLogger(__name__)

# --------------------------------------------------------------------------- #
# Configuración
# --------------------------------------------------------------------------- #
RAIZ = Path(__file__).resolve().parents[2]
DIR_BD = RAIZ / "src" / "BD"
DIR_SCRAPERS = RAIZ / "src" / "Scrapers"

SCRIPTS_ESTRUCTURA = ["01_raw.sql", "02_modelo.sql"]
SCRIPT_POBLAR = "03_poblar_modelo.sql"

SEPARADOR_CSV = ";"

# tabla raw -> CSV de salida del scraper (fuente única: los CSV no se copian a src/BD).
CARGAS = {
    "raw.empleabilidad": DIR_SCRAPERS / "Empleabilidad" / "Salida" / "empleabilidad_procesado.csv",
    "raw.estadisticas": DIR_SCRAPERS / "Estadisticas" / "Salida" / "estadisticas_procesado.csv",
    "raw.titulados": DIR_SCRAPERS / "Titulados" / "Salida" / "titulados_procesado.csv",
}

# tabla raw -> tabla de hechos de modelo que debe tener exactamente las mismas filas.
HECHO_POR_RAW = {
    "raw.empleabilidad": "modelo.mifuturo_programa",
    "raw.estadisticas": "modelo.mifuturo_estadistica",
    "raw.titulados": "modelo.titulacion",
}

TABLAS_INFORMATIVAS = ["modelo.institucion", "modelo.carrera_generica", "modelo.cohorte", "modelo.mifuturo_serie"]

TAMANO_BLOQUE = 1 << 20  # 1 MB por escritura al COPY


# --------------------------------------------------------------------------- #
# Pasos
# --------------------------------------------------------------------------- #
def _conectar() -> psycopg.Connection:
    """Conexión por variables de entorno; mensaje claro si falta PGDATABASE."""
    if not os.environ.get("PGDATABASE"):
        raise SystemExit(
            "Falta la variable PGDATABASE (p. ej. export PGDATABASE=carreras_sueldos). "
            "Sin ella libpq intenta una base con el nombre del usuario."
        )
    return psycopg.connect("")


def _ejecutar_sql(cur: psycopg.Cursor, nombre: str) -> None:
    """Ejecuta un archivo .sql completo (varias sentencias, sin parámetros)."""
    ruta = DIR_BD / nombre
    t0 = time.perf_counter()
    cur.execute(ruta.read_text(encoding="utf-8"))
    log.info("%-24s OK (%.1f s)", nombre, time.perf_counter() - t0)


def _filas_csv(ruta: Path) -> int:
    """Registros del CSV sin el encabezado (csv.reader respeta campos entrecomillados con ';' o saltos)."""
    with ruta.open(encoding="utf-8", newline="") as f:
        return sum(1 for _ in csv.reader(f, delimiter=SEPARADOR_CSV)) - 1


def _copiar(cur: psycopg.Cursor, tabla: str, ruta: Path) -> None:
    """COPY del CSV a su tabla raw. Vacío sin comillas = NULL (así escribe pandas los nulos)."""
    if not ruta.exists():
        raise FileNotFoundError(f"No existe {ruta}. Ejecutar el procesar.py del scraper.")
    t0 = time.perf_counter()
    sentencia = (
        f"COPY {tabla} FROM STDIN "
        f"(FORMAT csv, HEADER MATCH, DELIMITER '{SEPARADOR_CSV}', NULL '', ENCODING 'UTF8')"
    )
    with ruta.open("rb") as f, cur.copy(sentencia) as copia:
        while bloque := f.read(TAMANO_BLOQUE):
            copia.write(bloque)
    log.info("COPY %-20s OK (%.1f s)", tabla, time.perf_counter() - t0)


def _contar(cur: psycopg.Cursor, tabla: str) -> int:
    cur.execute(f"SELECT count(*) FROM {tabla}")
    return cur.fetchone()[0]


def _verificar_conteos(cur: psycopg.Cursor) -> None:
    """Filas del CSV = filas en raw = filas del hecho en modelo. Falla (y revierte) si no."""
    errores = []
    log.info("%-30s %10s %10s %10s", "tabla", "CSV", "raw", "modelo")
    for tabla_raw, ruta in CARGAS.items():
        n_csv, n_raw = _filas_csv(ruta), _contar(cur, tabla_raw)
        hecho = HECHO_POR_RAW[tabla_raw]
        n_hecho = _contar(cur, hecho)
        log.info("%-30s %10d %10d %10d", f"{tabla_raw} → {hecho}", n_csv, n_raw, n_hecho)
        if not n_csv == n_raw == n_hecho:
            errores.append(f"{tabla_raw}: CSV {n_csv}, raw {n_raw}, {hecho} {n_hecho}")
    for tabla in TABLAS_INFORMATIVAS:
        log.info("%-30s %10s %10s %10d", tabla, "", "", _contar(cur, tabla))
    if errores:
        raise RuntimeError("Conteos no cuadran:\n  - " + "\n  - ".join(errores))


# --------------------------------------------------------------------------- #
# Orquestador
# --------------------------------------------------------------------------- #
def build() -> None:
    t0 = time.perf_counter()
    with _conectar() as conn:
        with conn.transaction(), conn.cursor() as cur:
            # Los avisos de DROP ... CASCADE no aportan; los errores siguen llegando como excepción.
            cur.execute("SET LOCAL client_min_messages = warning")
            for nombre in SCRIPTS_ESTRUCTURA:
                _ejecutar_sql(cur, nombre)
            for tabla, ruta in CARGAS.items():
                _copiar(cur, tabla, ruta)
            _ejecutar_sql(cur, SCRIPT_POBLAR)
            _verificar_conteos(cur)
    log.info("Build OK en %.1f s (base %s)", time.perf_counter() - t0, os.environ["PGDATABASE"])


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    try:
        build()
    except (psycopg.Error, RuntimeError, FileNotFoundError) as exc:
        log.error("Build fallido; la base quedó como estaba antes del build.\n%s", exc)
        sys.exit(1)
