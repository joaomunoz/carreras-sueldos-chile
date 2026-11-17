"""
<src/Analisis/exportar.py>

Exporta los datos de la web a docs/datos.json desde la vista analytics.v_datos_json
(src/Analisis/sql/analytics/06_exportacion.sql). El armado del JSON y el redondeo viven en
SQL; este script solo verifica y escribe, para que el archivo no pueda contradecir a la base.

Uso (desde la raíz del proyecto, con la base ya construida por src/BD/build.py):

    python3 src/Analisis/exportar.py

Conexión: solo por variables de entorno de libpq (PGDATABASE); sin credenciales en el código.

Se niega a exportar (código 1, sin tocar docs/datos.json) si:
  - qa.control está vacío (la base no se construyó) o tiene algún control en FALLA;
  - los conteos del JSON no coinciden con las tablas de analytics.
Escritura atómica (archivo temporal + rename): un fallo a mitad no deja un JSON truncado.
Determinista: sin fecha de generación, claves en el orden de la vista y listas ordenadas en
SQL; dos exportaciones seguidas dan el mismo archivo (el SHA-256 impreso lo permite comprobar).
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path

import psycopg

RAIZ = Path(__file__).resolve().parents[2]
SALIDA = RAIZ / "docs" / "datos.json"

# clave del JSON -> consulta que da el número de elementos que debe tener.
CONTEOS = {
    "pares": "SELECT count(*) FROM analytics.par",
    "programas": "SELECT count(*) FROM analytics.programa_vs_par",
    "referencias": "SELECT count(*) FROM analytics.referencia",
    "segmentos": "SELECT count(*) FROM analytics.segmento",
    "parametros": "SELECT count(*) FROM analytics.parametro",
    "cohortes": "SELECT count(*) FROM modelo.cohorte",
}


def _verificar_qa(cur: psycopg.Cursor) -> None:
    cur.execute("SELECT count(*), count(*) FILTER (WHERE estado = 'FALLA') FROM qa.control")
    total, fallas = cur.fetchone()
    if total == 0:
        raise SystemExit("qa.control está vacío: correr primero python3 src/BD/build.py.")
    if fallas:
        raise SystemExit(f"{fallas} controles qa en FALLA: no se exporta.")


def _verificar_conteos(cur: psycopg.Cursor, datos: dict) -> None:
    errores = []
    for clave, sql in CONTEOS.items():
        cur.execute(sql)
        esperado = cur.fetchone()[0]
        if len(datos[clave]) != esperado:
            errores.append(f"{clave}: {len(datos[clave])} en el JSON, {esperado} en la base")
    if errores:
        raise SystemExit("Conteos del JSON no cuadran:\n  - " + "\n  - ".join(errores))


def exportar() -> str:
    if not os.environ.get("PGDATABASE"):
        raise SystemExit("Falta la variable PGDATABASE (p. ej. export PGDATABASE=carreras_sueldos).")
    with psycopg.connect("") as conn, conn.cursor() as cur:
        _verificar_qa(cur)
        cur.execute("SELECT datos FROM analytics.v_datos_json")
        datos = cur.fetchone()[0]   # psycopg ya entrega el json como dict
        _verificar_conteos(cur, datos)

    # indent=1: diff de git legible sin inflar demasiado el archivo; ensure_ascii=False: tildes tal cual.
    texto = json.dumps(datos, ensure_ascii=False, indent=1) + "\n"
    SALIDA.parent.mkdir(parents=True, exist_ok=True)
    temporal = SALIDA.with_suffix(".json.tmp")
    temporal.write_text(texto, encoding="utf-8")
    temporal.replace(SALIDA)
    return hashlib.sha256(texto.encode("utf-8")).hexdigest()


if __name__ == "__main__":
    try:
        huella = exportar()
    except psycopg.Error as exc:
        print(f"No se pudo leer la base: {exc}", file=sys.stderr)
        sys.exit(1)
    print(f"Exportado {SALIDA.relative_to(RAIZ)} ({SALIDA.stat().st_size / 1024:.0f} KB), sha256 {huella[:16]}…")
