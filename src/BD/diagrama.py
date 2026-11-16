"""
<src/BD/diagrama.py>

Genera el diagrama entidad-relación de la base `carreras_sueldos` a partir del catálogo de
PostgreSQL (no a mano): si cambia el DDL, basta con volver a ejecutar este script y el
diagrama no puede quedar desalineado con la base real.

Uso (desde la raíz del proyecto, con la base ya construida por src/BD/build.py):

    python3 src/BD/diagrama.py

Salida: src/BD/diagrama_modelo.svg (se abre con cualquier navegador). Requiere Graphviz (`dot`).

Qué muestra:
  - Esquema `modelo` completo: columnas con tipo, PK, FK y NOT NULL; flechas = FK reales.
  - Esquema `raw` resumido (nombre, columnas, llave): sus tablas no tienen FK entre sí.
  - Flechas punteadas raw → modelo: de qué tabla raw se puebla cada tabla del modelo
    (linaje de src/BD/03_poblar_modelo.sql, que el catálogo no registra).
"""

from __future__ import annotations

import html
import os
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

import psycopg

DIR_BD = Path(__file__).resolve().parent
SALIDA_SVG = DIR_BD / "diagrama_modelo.svg"

# Linaje de 03_poblar_modelo.sql. Vive aquí, a mano, porque PostgreSQL no guarda de dónde
# se cargó una tabla; si cambia 03_poblar_modelo.sql hay que actualizar este mapa.
LINAJE = {
    "raw.titulados": ["institucion", "carrera_generica", "titulacion"],
    "raw.empleabilidad": ["mifuturo_programa"],
    "raw.estadisticas": ["mifuturo_estadistica", "mifuturo_serie"],
}

COLOR = {"ref": "#E8F1FB", "hecho": "#FFF4E0", "raw": "#F2F2F2", "cab": "#33415C"}
REFERENCIAS = {"institucion", "carrera_generica", "cohorte"}

SQL_COLUMNAS = """
SELECT c.table_schema, c.table_name, c.column_name, c.data_type, c.is_nullable = 'NO'
FROM information_schema.columns c
JOIN information_schema.tables t USING (table_schema, table_name)
WHERE c.table_schema IN ('raw', 'modelo') AND t.table_type = 'BASE TABLE'
ORDER BY c.table_schema, c.table_name, c.ordinal_position
"""

# Columnas de PK y FK por tabla, y FK como pares (tabla origen, tabla destino, columnas).
SQL_LLAVES = """
SELECT n.nspname, cl.relname, k.contype, a.attname,
       rn.nspname AS ref_esquema, rc.relname AS ref_tabla, k.conname
FROM pg_constraint k
JOIN pg_class cl ON cl.oid = k.conrelid
JOIN pg_namespace n ON n.oid = cl.relnamespace
JOIN LATERAL unnest(k.conkey) AS u(attnum) ON true
JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = u.attnum
LEFT JOIN pg_class rc ON rc.oid = k.confrelid
LEFT JOIN pg_namespace rn ON rn.oid = rc.relnamespace
WHERE n.nspname IN ('raw', 'modelo') AND k.contype IN ('p', 'f')
"""

ABREVIATURA_TIPO = {
    "integer": "int", "smallint": "smallint", "text": "text", "numeric": "numeric",
    "boolean": "bool",
}


def _leer_catalogo(cur: psycopg.Cursor):
    columnas = defaultdict(list)
    cur.execute(SQL_COLUMNAS)
    for esquema, tabla, col, tipo, not_null in cur.fetchall():
        columnas[(esquema, tabla)].append((col, ABREVIATURA_TIPO.get(tipo, tipo), not_null))

    pk, fk_cols = defaultdict(set), defaultdict(set)
    fks = {}  # conname -> (origen, destino, [columnas])
    cur.execute(SQL_LLAVES)
    for esquema, tabla, tipo, col, ref_esq, ref_tabla, conname in cur.fetchall():
        if tipo == "p":
            pk[(esquema, tabla)].add(col)
        else:
            fk_cols[(esquema, tabla)].add(col)
            fks.setdefault(conname, ((esquema, tabla), (ref_esq, ref_tabla), []))[2].append(col)
    return columnas, pk, fk_cols, fks


def _nodo_modelo(tabla: str, cols, pk: set, fk: set) -> str:
    fondo = COLOR["ref"] if tabla in REFERENCIAS else COLOR["hecho"]
    filas = []
    for col, tipo, not_null in cols:
        marcas = " ".join(m for m, ok in (("PK", col in pk), ("FK", col in fk)) if ok)
        nombre = f"<B>{html.escape(col)}</B>" if col in pk else html.escape(col)
        nulo = "" if not_null else " ?"
        # Graphviz rechaza un <FONT> vacío: sin marcas, la celda va sin etiqueta de fuente.
        celda_marcas = f'<FONT COLOR="#A23B2A">{marcas}</FONT>' if marcas else " "
        filas.append(
            f'<TR><TD ALIGN="LEFT">{nombre}</TD><TD ALIGN="LEFT"><FONT COLOR="#555555">{tipo}{nulo}</FONT></TD>'
            f'<TD ALIGN="LEFT">{celda_marcas}</TD></TR>'
        )
    return (
        f'"modelo.{tabla}" [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="3" BGCOLOR="{fondo}">'
        f'<TR><TD COLSPAN="3" BGCOLOR="{COLOR["cab"]}"><FONT COLOR="white"><B>modelo.{tabla}</B></FONT></TD></TR>'
        + "".join(filas) + "</TABLE>>];"
    )


def _nodo_raw(tabla: str, cols, pk: set) -> str:
    llave = ", ".join(c for c, _, _ in cols if c in pk)
    return (
        f'"raw.{tabla}" [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="4" BGCOLOR="{COLOR["raw"]}">'
        f'<TR><TD BGCOLOR="#777777"><FONT COLOR="white"><B>raw.{tabla}</B></FONT></TD></TR>'
        f"<TR><TD>{len(cols)} columnas (= esquema.py)</TD></TR>"
        f"<TR><TD>PK: {html.escape(llave)}</TD></TR></TABLE>>];"
    )


def generar_dot(cur: psycopg.Cursor) -> str:
    columnas, pk, fk_cols, fks = _leer_catalogo(cur)
    lineas = [
        "digraph modelo {",
        # splines=ortho: con tablas altas, el ruteo curvo de Graphviz 2.42 falla ("lost edge").
        # Las aristas ortogonales no admiten `label`, por eso las FK usan `xlabel`.
        '  graph [rankdir=LR, splines=ortho, forcelabels=true, fontname="Helvetica", fontsize=11, nodesep=0.4, ranksep=1.0, '
        'label="Base carreras_sueldos — generado desde el catálogo por src/BD/diagrama.py. '
        '? = admite NULL · flecha sólida = FK · punteada = se puebla desde (03_poblar_modelo.sql)", labelloc=t];',
        '  node [shape=plaintext, fontname="Helvetica", fontsize=10];',
        '  edge [fontname="Helvetica", fontsize=9, color="#33415C"];',
        '  subgraph cluster_raw { label="raw (copia fiel de los CSV)"; style=dashed; color="#999999";',
    ]
    for (esquema, tabla), cols in sorted(columnas.items()):
        if esquema == "raw":
            lineas.append("    " + _nodo_raw(tabla, cols, pk[(esquema, tabla)]))
    lineas.append("  }")
    lineas.append('  subgraph cluster_modelo { label="modelo"; style=rounded; color="#33415C";')
    for (esquema, tabla), cols in sorted(columnas.items()):
        if esquema == "modelo":
            lineas.append("    " + _nodo_modelo(tabla, cols, pk[(esquema, tabla)], fk_cols[(esquema, tabla)]))
    lineas.append("  }")
    for origen, destino, cols in sorted(fks.values()):
        lineas.append(f'  "{origen[0]}.{origen[1]}" -> "{destino[0]}.{destino[1]}" [xlabel="{", ".join(cols)}"];')
    for raw, destinos in LINAJE.items():
        for d in destinos:
            lineas.append(f'  "{raw}" -> "modelo.{d}" [style=dashed, color="#999999", arrowhead=empty];')
    lineas.append("}")
    return "\n".join(lineas)


def main() -> None:
    if not os.environ.get("PGDATABASE"):
        raise SystemExit("Falta la variable PGDATABASE (p. ej. export PGDATABASE=carreras_sueldos).")
    if not shutil.which("dot"):
        raise SystemExit("Falta Graphviz (`dot`). Instalar con: sudo apt install graphviz")
    with psycopg.connect("") as conn, conn.cursor() as cur:
        dot = generar_dot(cur)
    subprocess.run(["dot", "-Tsvg", "-o", str(SALIDA_SVG)], input=dot.encode("utf-8"), check=True)
    print(f"Diagrama generado: {SALIDA_SVG}")


if __name__ == "__main__":
    try:
        main()
    except (psycopg.Error, subprocess.CalledProcessError) as exc:
        print(f"No se pudo generar el diagrama: {exc}", file=sys.stderr)
        sys.exit(1)
