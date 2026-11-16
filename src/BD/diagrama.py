"""
<src/BD/diagrama.py>

Genera el diagrama entidad-relación de la base `carreras_sueldos` en Mermaid (`erDiagram`)
a partir del catálogo de PostgreSQL, no a mano: si cambia el DDL, basta con volver a
ejecutar este script y el diagrama no puede quedar desalineado con la base real.

Mermaid y no una imagen: es texto (el diff de git muestra qué cambió en el modelo), GitHub y
VS Code lo dibujan sin instalar nada, y no depende de Graphviz.

Uso (desde la raíz del proyecto, con la base ya construida por src/BD/build.py):

    python3 src/BD/diagrama.py

Salida: src/BD/diagrama_modelo.md

Qué muestra:
  - Esquema `modelo` completo: columnas con tipo, PK, FK y "NULL" donde se admite;
    líneas sólidas = FK reales (1 a muchos, rotuladas con sus columnas).
  - Esquema `raw` resumido (llave): sus tablas no tienen FK entre sí.
  - Líneas punteadas raw → modelo: de qué tabla raw se puebla cada tabla del modelo
    (linaje de src/BD/03_poblar_modelo.sql, que el catálogo no registra).
"""

from __future__ import annotations

import os
import sys
from collections import defaultdict
from pathlib import Path

import psycopg

DIR_BD = Path(__file__).resolve().parent
SALIDA = DIR_BD / "diagrama_modelo.md"

# Linaje de 03_poblar_modelo.sql. Vive aquí, a mano, porque PostgreSQL no guarda de dónde
# se cargó una tabla; si cambia 03_poblar_modelo.sql hay que actualizar este mapa.
LINAJE = {
    "titulados": ["institucion", "carrera_generica", "titulacion"],
    "empleabilidad": ["mifuturo_programa"],
    "estadisticas": ["mifuturo_estadistica", "mifuturo_serie"],
}

SQL_COLUMNAS = """
SELECT c.table_schema, c.table_name, c.column_name, c.data_type, c.is_nullable = 'NO'
FROM information_schema.columns c
JOIN information_schema.tables t USING (table_schema, table_name)
WHERE c.table_schema IN ('raw', 'modelo') AND t.table_type = 'BASE TABLE'
ORDER BY c.table_schema, c.table_name, c.ordinal_position
"""

# Columnas de PK y FK por tabla, y cada FK con su tabla destino.
SQL_LLAVES = """
SELECT n.nspname, cl.relname, k.contype, a.attname, rc.relname AS ref_tabla, k.conname,
       u.ord
FROM pg_constraint k
JOIN pg_class cl ON cl.oid = k.conrelid
JOIN pg_namespace n ON n.oid = cl.relnamespace
JOIN LATERAL unnest(k.conkey) WITH ORDINALITY AS u(attnum, ord) ON true
JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = u.attnum
LEFT JOIN pg_class rc ON rc.oid = k.confrelid
WHERE n.nspname IN ('raw', 'modelo') AND k.contype IN ('p', 'f')
ORDER BY k.conname, u.ord
"""

# Paleta fija (tema `base`) en vez del tema del visor: MarkText, VS Code y GitHub eligen
# 'default' o 'dark' según su propio criterio, y con un tema oscuro no mapeado las líneas
# quedaban oscuras sobre fondo oscuro. Con colores explícitos el diagrama se ve igual en todos:
#   - cajas y rótulos con fondo propio claro y texto oscuro → legibles sobre cualquier fondo;
#   - líneas blancas y gruesas (2,5 px): elegidas para el visor de trabajo, MarkText con
#     tema oscuro, donde el gris medio se notaba poco. Costo asumido: en un visor con fondo
#     blanco (GitHub claro, VS Code claro) las líneas no se verán; para ese caso basta
#     cambiar COLOR_LINEA (p. ej. "#7d8da3", legible en ambos fondos) y regenerar.
# Descartado: tema 'dark' fijo (se vería mal en visores claros) y CSS propio (los visores
# de Markdown no lo aplican dentro del SVG de Mermaid).
COLOR_LINEA = "#ffffff"
GROSOR_LINEA = "2.5px"
TEMA_MERMAID = (
    "%%{init: {'theme': 'base', 'themeVariables': {"
    "'primaryColor': '#eef2f7', 'primaryTextColor': '#1f2937', 'primaryBorderColor': '#5b6b7f', "
    f"'lineColor': '{COLOR_LINEA}', 'relationColor': '{COLOR_LINEA}', "
    "'relationLabelBackground': '#eef2f7', 'relationLabelColor': '#1f2937', "
    "'edgeLabelBackground': '#eef2f7', 'textColor': '#1f2937', "
    "'attributeBackgroundColorOdd': '#ffffff', 'attributeBackgroundColorEven': '#f3f6fa', "
    "'tertiaryColor': '#eef2f7'}, "
    # Mermaid 11 pinta el fondo de los rótulos al 50 % de opacidad (fijo, no es variable):
    # sobre fondo oscuro queda gris con texto gris. themeCSS va dentro del SVG y lo hace opaco.
    "'themeCSS': '.labelBkg, .edgeLabel { background-color: #eef2f7 !important; } "
    ".edgeLabel rect, .relationshipLabelBox, .relationshipLabelBox rect { opacity: 1 !important; fill: #eef2f7 !important; } "
    # Mermaid dibuja las relaciones a 1 px (fijo en su CSS); se engrosan para verlas de lejos.
    f".relationshipLine {{ stroke-width: {GROSOR_LINEA} !important; }}'"
    "}}%%"
)

ABREVIATURA_TIPO = {"integer": "int", "smallint": "smallint", "text": "text",
                    "numeric": "numeric", "boolean": "bool"}


def _leer_catalogo(cur: psycopg.Cursor):
    columnas = defaultdict(list)
    cur.execute(SQL_COLUMNAS)
    for esquema, tabla, col, tipo, not_null in cur.fetchall():
        columnas[(esquema, tabla)].append((col, ABREVIATURA_TIPO.get(tipo, tipo), not_null))

    pk, fk_cols = defaultdict(list), defaultdict(set)
    fks = {}  # conname -> (tabla origen, tabla destino, [columnas])
    cur.execute(SQL_LLAVES)
    for esquema, tabla, tipo, col, ref_tabla, conname, _ in cur.fetchall():
        if tipo == "p":
            pk[(esquema, tabla)].append(col)
        else:
            fk_cols[(esquema, tabla)].add(col)
            fks.setdefault(conname, (tabla, ref_tabla, []))[2].append(col)
    return columnas, pk, fk_cols, fks


def _entidad_modelo(tabla: str, cols, pk: list, fk: set) -> list[str]:
    lineas = [f"    {tabla} {{"]
    for col, tipo, not_null in cols:
        llaves = ", ".join(m for m, ok in (("PK", col in pk), ("FK", col in fk)) if ok)
        partes = [tipo, col] + ([llaves] if llaves else []) + ([] if not_null else ['"NULL"'])
        lineas.append("        " + " ".join(partes))
    lineas.append("    }")
    return lineas


def _entidad_raw(tabla: str, cols, pk: list) -> list[str]:
    # Mermaid exige al menos tipo y nombre por atributo: se listan solo las columnas de la llave.
    lineas = [f"    raw_{tabla} {{"]
    for col, tipo, _ in cols:
        if col in pk:
            lineas.append(f"        {tipo} {col} PK")
    lineas.append(f'        text otras_{len(cols) - len(pk)}_columnas "ver esquema.py"')
    lineas.append("    }")
    return lineas


def generar_mermaid(cur: psycopg.Cursor) -> str:
    columnas, pk, fk_cols, fks = _leer_catalogo(cur)
    cuerpo = [TEMA_MERMAID, "erDiagram"]
    for (esquema, tabla), cols in sorted(columnas.items()):
        if esquema == "modelo":
            cuerpo += _entidad_modelo(tabla, cols, pk[(esquema, tabla)], fk_cols[(esquema, tabla)])
    for (esquema, tabla), cols in sorted(columnas.items()):
        if esquema == "raw":
            cuerpo += _entidad_raw(tabla, cols, pk[(esquema, tabla)])
    cuerpo.append("")
    # FK: la tabla referida (1) tiene cero o muchas filas que la referencian.
    for origen, destino, cols in sorted(fks.values()):
        cuerpo.append(f'    {destino} ||--o{{ {origen} : "{", ".join(cols)}"')
    # Linaje: línea punteada (relación no identificadora en Mermaid).
    for raw, destinos in LINAJE.items():
        for d in destinos:
            cuerpo.append(f'    raw_{raw} ||..|{{ {d} : "puebla"')

    return "\n".join([
        "# Diagrama ER — base `carreras_sueldos`",
        "",
        "> Generado desde el catálogo de PostgreSQL por `src/BD/diagrama.py`; no editar a mano.",
        "> Regenerar con `python3 src/BD/diagrama.py` tras cambiar `src/BD/01_raw.sql` o `src/BD/02_modelo.sql`.",
        "",
        "Lectura: línea sólida = FK (una fila de la tabla referida, cero o muchas que la referencian),",
        "rotulada con sus columnas · línea punteada = la tabla `raw` desde la que se puebla",
        "(`src/BD/03_poblar_modelo.sql`) · `\"NULL\"` = la columna admite nulos.",
        "Detalle de cada columna en [`diccionario_datos.md`](diccionario_datos.md).",
        "",
        "```mermaid",
        *cuerpo,
        "```",
        "",
    ])


def main() -> None:
    if not os.environ.get("PGDATABASE"):
        raise SystemExit("Falta la variable PGDATABASE (p. ej. export PGDATABASE=carreras_sueldos).")
    with psycopg.connect("") as conn, conn.cursor() as cur:
        SALIDA.write_text(generar_mermaid(cur), encoding="utf-8")
    print(f"Diagrama generado: {SALIDA}")


if __name__ == "__main__":
    try:
        main()
    except psycopg.Error as exc:
        print(f"No se pudo leer el catálogo: {exc}", file=sys.stderr)
        sys.exit(1)
