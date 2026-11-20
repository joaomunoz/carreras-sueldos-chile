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
  0. Base de este proyecto      vacía o de un build anterior; si no, se detiene sin borrar
  1. src/BD/01_raw.sql         crea el esquema raw (vacío)
  2. src/BD/02_modelo.sql       crea el esquema modelo (vacío, salvo modelo.cohorte)
  3. COPY de los 3 CSV a raw    HEADER MATCH: el encabezado del CSV debe coincidir, en
                                nombre y orden, con las columnas de la tabla
  4. src/BD/03_poblar_modelo.sql  de raw a modelo
  5. src/BD/04_qa.sql           controles semánticos → tabla qa.control
  6. Contrato de esquemas       columnas de raw = los 3 esquema.py (nombre, orden, tipo)
                                → qa.control
  7. src/Analisis/sql/analytics/*.sql  esquema analytics (Fase 2), en orden de nombre;
                                cada archivo registra sus controles en qa.control
  8. Verificación               conteos CSV = raw = modelo, y ningún control en FALLA

Por qué analytics va en este mismo build y transacción: con un build aparte, un cambio en
modelo podría quedar publicado con un analytics calculado sobre los datos anteriores.
"""

from __future__ import annotations

import csv
import logging
import os
import sys
import time
from pathlib import Path

import psycopg

# Los esquema.py son la fuente de verdad de las columnas de raw; se importan igual que en
# los procesar.py (Scrapers/ en el path, carpeta del scraper como paquete).
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scrapers"))
from Empleabilidad.esquema import ESQUEMA_EMPLEABILIDAD  # noqa: E402
from Estadisticas.esquema import ESQUEMA_ESTADISTICAS  # noqa: E402
from Titulados.esquema import ESQUEMA_TITULADOS  # noqa: E402

log = logging.getLogger(__name__)

# --------------------------------------------------------------------------- #
# Configuración
# --------------------------------------------------------------------------- #
RAIZ = Path(__file__).resolve().parents[2]
DIR_BD = RAIZ / "src" / "BD"
DIR_SCRAPERS = RAIZ / "src" / "Scrapers"
DIR_ANALYTICS = RAIZ / "src" / "Analisis" / "sql" / "analytics"

SCRIPTS_ESTRUCTURA = ["01_raw.sql", "02_modelo.sql"]
SCRIPT_POBLAR = "03_poblar_modelo.sql"
SCRIPT_QA = "04_qa.sql"

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

# tabla raw -> esquema.py que la define.
ESQUEMAS = {
    "raw.empleabilidad": ESQUEMA_EMPLEABILIDAD,
    "raw.estadisticas": ESQUEMA_ESTADISTICAS,
    "raw.titulados": ESQUEMA_TITULADOS,
}

# dtype de pandas -> tipos PostgreSQL aceptables. Un entero de pandas puede ser smallint o
# integer (el DDL elige el ancho); lo que no puede pasar es, p. ej., un float64 en integer.
TIPOS_COMPATIBLES = {
    "object": {"text"},
    "string": {"text"},
    "int64": {"smallint", "integer", "bigint"},
    "Int64": {"smallint", "integer", "bigint"},
    "float64": {"numeric"},
    "bool": {"boolean"},
    "boolean": {"boolean"},
}

TABLAS_INFORMATIVAS = ["modelo.institucion", "modelo.carrera_generica", "modelo.cohorte", "modelo.mifuturo_serie",
                       "analytics.segmento", "analytics.par"]

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


ESQUEMAS_PROPIOS = ("raw", "modelo", "analytics", "qa")


def _verificar_base(cur: psycopg.Cursor) -> None:
    """Se niega a construir en una base que no es de este proyecto.

    El build hace DROP SCHEMA ... CASCADE de los 4 esquemas propios: con PGDATABASE apuntando
    a otra base existente («raw» es un nombre común en proyectos de datos) borraría datos
    ajenos. No se exige el nombre carreras_sueldos porque los ensayos de método usan una base
    aparte (área de MiFuturo, cohortes de Derecho). Una base es aceptable si está vacía o si es
    de un build anterior (tiene qa.control y nada fuera de los 4 esquemas).
    """
    cur.execute("SELECT current_database()")
    base = cur.fetchone()[0]
    if base in ("postgres", "template0", "template1"):
        raise RuntimeError(f"PGDATABASE={base} es una base del sistema; crea una propia: createdb carreras_sueldos")
    cur.execute(
        """SELECT n.nspname || '.' || c.relname
             FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f')
              AND n.nspname <> ALL (%s)
              AND n.nspname NOT IN ('pg_catalog', 'information_schema')
              AND n.nspname NOT LIKE 'pg\\_%%'
            ORDER BY 1 LIMIT 5""",
        (list(ESQUEMAS_PROPIOS),),
    )
    ajenas = [fila[0] for fila in cur.fetchall()]
    cur.execute("SELECT array_agg(nspname ORDER BY nspname) FROM pg_namespace WHERE nspname = ANY (%s)",
                (list(ESQUEMAS_PROPIOS),))
    existentes = cur.fetchone()[0] or []
    cur.execute("SELECT to_regclass('qa.control') IS NOT NULL")
    de_un_build = cur.fetchone()[0]
    if ajenas or (existentes and not de_un_build):
        motivo = (f"tiene tablas fuera de {', '.join(ESQUEMAS_PROPIOS)} ({', '.join(ajenas)}…)" if ajenas
                  else f"tiene los esquemas {', '.join(existentes)} sin la firma de un build (qa.control)")
        raise RuntimeError(
            f"La base «{base}» no parece de este proyecto: {motivo}. El build borra y recrea esos "
            "esquemas; usa una base vacía (createdb carreras_sueldos) o revisa PGDATABASE."
        )


def _ejecutar_sql(cur: psycopg.Cursor, nombre: str, directorio: Path = DIR_BD) -> None:
    """Ejecuta un archivo .sql completo (varias sentencias, sin parámetros) y analiza lo que creó."""
    ruta = directorio / nombre
    t0 = time.perf_counter()
    cur.execute(ruta.read_text(encoding="utf-8"))
    _analizar(cur)
    log.info("%-24s OK (%.1f s)", nombre, time.perf_counter() - t0)


def _analizar(cur: psycopg.Cursor) -> None:
    """Estadísticas de las tablas del proyecto, dentro de la misma transacción.

    Las tablas se crean y se llenan en esta transacción, así que el autovacuum nunca alcanza a
    analizarlas: sin estadísticas, el planificador supone tablas casi vacías y elige planes malos
    para las consultas siguientes (07_exportacion.sql tardaba ~100 s; auditoría del 19-11-26).
    ANALYZE sí ve las filas no confirmadas de su propia transacción. No cambia ningún resultado.
    """
    cur.execute("SELECT format('%I.%I', schemaname, tablename) FROM pg_tables "
                "WHERE schemaname IN ('raw', 'modelo', 'analytics', 'qa')")
    tablas = [t for (t,) in cur.fetchall()]
    if tablas:
        cur.execute("ANALYZE " + ", ".join(tablas))


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


def _controlar_esquemas(cur: psycopg.Cursor) -> None:
    """Columnas de cada tabla raw = su esquema.py, en nombre, orden y tipo compatible.

    Por qué además de COPY ... HEADER MATCH: HEADER MATCH compara el CSV con la tabla. Si
    alguien cambia un esquema.py y el DDL pero no vuelve a correr procesar.py (o al revés),
    CSV y tabla pueden coincidir entre sí y estar desalineados con el esquema vigente.
    """
    for tabla, esquema in ESQUEMAS.items():
        nombre_esquema, nombre_tabla = tabla.split(".")
        cur.execute(
            "SELECT column_name, data_type FROM information_schema.columns "
            "WHERE table_schema = %s AND table_name = %s ORDER BY ordinal_position",
            (nombre_esquema, nombre_tabla),
        )
        en_base = cur.fetchall()
        en_esquema = list(esquema.items())
        problemas = []
        if [c for c, _ in en_base] != [c for c, _ in en_esquema]:
            faltan = sorted(set(esquema) - {c for c, _ in en_base})
            sobran = sorted({c for c, _ in en_base} - set(esquema))
            problemas.append(f"nombres u orden distintos (faltan en raw: {faltan or '-'}; "
                             f"sobran en raw: {sobran or '-'})")
        else:
            for (col, tipo_pg), (_, dtype) in zip(en_base, en_esquema):
                if tipo_pg not in TIPOS_COMPATIBLES.get(dtype, set()):
                    problemas.append(f"{col}: {dtype} en esquema.py vs {tipo_pg} en raw")
        cur.execute(
            "INSERT INTO qa.control (control, objeto, estado, metrica, umbral, detalle) "
            "VALUES ('contrato_esquema', %s, %s, %s, %s, %s)",
            (tabla, "FALLA" if problemas else "OK", len(problemas),
             "columnas de raw = esquema.py en nombre, orden y tipo",
             "; ".join(problemas) or f"{len(en_base)} columnas coinciden"),
        )


def _verificar_qa(cur: psycopg.Cursor) -> None:
    """Muestra todo qa.control y falla (revierte) si algún control quedó en FALLA."""
    cur.execute("SELECT control, objeto, estado, detalle FROM qa.control ORDER BY control, objeto")
    fallas = []
    for control, objeto, estado, detalle in cur.fetchall():
        nivel = logging.ERROR if estado == "FALLA" else logging.INFO
        log.log(nivel, "qa %-17s %-36s %-6s %s", control, objeto, estado, detalle)
        if estado == "FALLA":
            fallas.append(f"{control} / {objeto}: {detalle}")
    if fallas:
        raise RuntimeError("Controles qa en FALLA:\n  - " + "\n  - ".join(fallas))


# --------------------------------------------------------------------------- #
# Orquestador
# --------------------------------------------------------------------------- #
def build() -> None:
    t0 = time.perf_counter()
    with _conectar() as conn:
        with conn.transaction(), conn.cursor() as cur:
            # Los avisos de DROP ... CASCADE no aportan; los errores siguen llegando como excepción.
            cur.execute("SET LOCAL client_min_messages = warning")
            _verificar_base(cur)
            for nombre in SCRIPTS_ESTRUCTURA:
                _ejecutar_sql(cur, nombre)
            for tabla, ruta in CARGAS.items():
                _copiar(cur, tabla, ruta)
            _ejecutar_sql(cur, SCRIPT_POBLAR)
            _ejecutar_sql(cur, SCRIPT_QA)
            _controlar_esquemas(cur)
            # Orden por nombre (01_, 02_, ...): cada archivo depende de los anteriores.
            for ruta in sorted(DIR_ANALYTICS.glob("*.sql")):
                _ejecutar_sql(cur, ruta.name, DIR_ANALYTICS)
            _verificar_conteos(cur)
            _verificar_qa(cur)
    log.info("Build OK en %.1f s (base %s)", time.perf_counter() - t0, os.environ["PGDATABASE"])


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    try:
        build()
    except (psycopg.Error, RuntimeError, FileNotFoundError) as exc:
        log.error("Build fallido; la base quedó como estaba antes del build.\n%s", exc)
        sys.exit(1)
