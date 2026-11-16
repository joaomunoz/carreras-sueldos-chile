"""
<src/Scrapers/Empleabilidad/obtener.py>

Módulo de extracción de Empleabilidad e Ingresos desde mifuturo.cl
(Buscador de Empleabilidad e Ingresos).

Estrategia verificada (la tabla NO expone endpoint JSON propio, se extrae del HTML):

  Nivel 1 - Tabla base (obligatorio):
      3 POST al formulario `nameTab=empleabilidad` filtrando `tipo_institucionEmp`
      en {1=CFT, 2=IP, 3=Universidad}. Devuelve 176+324+1190 = 1690 filas con
      las 9 columnas visibles + `carrera_generica` y `id_institucion` extraídos
      de los atributos `onclick` de cada fila.

  Nivel 2 - Regiones (opcional, defecto activo):
      16 llamadas `dcms_ajax_all_filter(region=N)` -> mapa id_institución ->
      regiones donde tiene sedes. Cobertura 88/105 instituciones; el resto son
      planteles sin oferta vigente en el filtro regional.

  Ingresos y percentiles NACIONALES (carrera genérica x tipo) ya no se extraen aquí:
      vienen del Buscador de Estadísticas por Carrera, con su propio scraper
      (src/Scrapers/Estadisticas). Pegarlos a cada institución los repetía en 1.690 filas
      y perdía los pares sin ninguna institución publicada en este buscador.

Niveles descartados tras verificación empírica (no generan código):
  - `dcms_armado_tabla_empleabilidad(id)`: sus 4 campos están MAL ETIQUETADOS.
    Verificado con 177 muestras y coincidencia 100%:
        'desercion'           == retencion_1er_anio        (de la tabla base)
        'porcentaje_titulados'== empleabilidad_1er_anio    (de la tabla base)
        'subvencionado'       == pct_continuidad_estudios  (de la tabla base)
        'pro_arancel_...'     == '0' en 194/194 casos (sin valor)
    Por tanto NO aporta información nueva.
  - `dcms_armado_tabla_carrera(id)`: join de solo 12.8% contra la tabla base
    (nombres de carrera específicos vs. genéricos) -> descartado.

Límite conocido y documentado: la empleabilidad de MiFuturo es un indicador
NACIONAL por (institución, carrera). `regiones_sede` aporta el contexto
geográfico del plantel, no un corte regional de la empleabilidad.

Salida: Entrada/empleabilidad_mifuturo.csv  (separador ';', UTF-8)
"""

from __future__ import annotations

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
URL_BUSCADOR = "https://www.mifuturo.cl/buscador-de-empleabilidad-e-ingresos/"
URL_AJAX = "https://www.mifuturo.cl/wp-admin/admin-ajax.php"

DIR_ENTRADA = Path(__file__).parent / "Entrada"
NOMBRE_SALIDA = "empleabilidad_mifuturo.csv"

SEPARADOR_CSV = ";"

TIPOS_INSTITUCION = {1: "Centro de Formación Técnica", 2: "Instituto Profesional", 3: "Universidad"}
REGIONES = {
    15: "Arica y Parinacota", 1: "Tarapacá", 2: "Antofagasta", 3: "Atacama",
    4: "Coquimbo", 5: "Valparaíso", 13: "Metropolitana", 6: "O'Higgins",
    7: "Maule", 16: "Ñuble", 8: "Biobío", 9: "Araucanía", 14: "Los Ríos",
    10: "Los Lagos", 11: "Aysén", 12: "Magallanes",
}

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/124.0 Safari/537.36",
    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
}

def _sesion() -> requests.Session:
    """Sesión HTTP con headers compartidos."""
    s = requests.Session()
    s.headers.update(HEADERS)
    return s


def _texto_celda(td: str) -> str:
    """Texto visible de una celda, sin etiquetas HTML."""
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", td or "")).strip()


def _data_order(td_attrs: str) -> str | None:
    """Valor numérico crudo del atributo data-order (vive en la etiqueta <td ...>)."""
    m = re.search(r'data-order="([^"]*)"', td_attrs or "")
    return m.group(1) if m else None


# --------------------------------------------------------------------------- #
# Nivel 1 - Tabla base
# --------------------------------------------------------------------------- #
def _descargar_tabla(s: requests.Session, tipo: int | str) -> list[dict]:
    """POST al formulario del buscador y parseo de la tabla de resultados."""
    payload = {
        "nameTab": "empleabilidad",
        "tipo_institucionEmp": tipo,
        "institucionEmp": "",
        "carreraEmp": "",
    }
    resp = s.post(URL_BUSCADOR, data=payload, timeout=180)
    resp.raise_for_status()

    bloque = re.search(r'<table id="tablaEmpleabilidad".*?</table>', resp.text, re.S)
    if not bloque:
        raise RuntimeError("no se encontró <table id='tablaEmpleabilidad'> en la respuesta")

    filas: list[dict] = []
    for tr in re.findall(r'<tr[^>]*>(?!\s*<th)(.*?)</tr>', bloque.group(0), re.S):
        # Se capturan ATRIBUTOS y CONTENIDO por separado: data-order está en la
        # etiqueta de apertura <td data-order="...">texto</td>.
        celdas = re.findall(r"<td([^>]*)>(.*?)</td>", tr, re.S)
        if len(celdas) < 9:
            continue

        (a0, c0), (a1, c1), (a2, c2), (a3, c3), (a4, c4), \
            (a5, c5), (a6, c6), (a7, c7), (a8, c8) = celdas[:9]

        # onclick -> id de institución y carrera genérica
        m_inst = re.search(r"cambioabuscadorInstitucion\((\d+)\)", c0)
        m_gen = re.search(r"cambioabuscadorcarreras\(\d+,'([^']*)'\)", c2)
        if not m_inst:
            continue

        filas.append({
            "id_institucion": int(m_inst.group(1)),
            "institucion": _texto_celda(c0),
            "acreditacion_institucion": _texto_celda(c1),
            "acreditacion_anios": _data_order(a1),
            "carrera": _texto_celda(c2),
            "carrera_generica": m_gen.group(1) if m_gen else "",
            "pct_continuidad_estudios": _data_order(a3),
            "retencion_1er_anio": _data_order(a4),
            "duracion_real_semestres": _data_order(a5),
            "empleabilidad_1er_anio": _data_order(a6),
            "empleabilidad_2do_anio": _data_order(a7),
            "ingreso_prom_4to_anio": _texto_celda(c8),
            "ingreso_prom_4to_anio_tramo": _data_order(a8),
        })
    return filas


def _obtener_tabla_base(s: requests.Session) -> pd.DataFrame:
    """Une los 3 POST por tipo de institución -> etiqueta `tipo_institucion`."""
    registros: list[dict] = []
    for tipo, nombre in TIPOS_INSTITUCION.items():
        filas = _descargar_tabla(s, tipo)
        log.info("tipo_institucion=%s (%s): %d filas", tipo, nombre, len(filas))
        for f in filas:
            f["tipo_institucion"] = nombre
        registros.extend(filas)
        time.sleep(0.2)

    df = pd.DataFrame(registros)
    if df.empty:
        raise RuntimeError("la tabla base de empleabilidad llegó vacía")
    log.info("tabla base: %d filas, %d instituciones", len(df), df["id_institucion"].nunique())
    return df


# --------------------------------------------------------------------------- #
# Nivel 2 - Regiones por institución
# --------------------------------------------------------------------------- #
def _mapa_regiones(s: requests.Session) -> dict[int, list[str]]:
    """Regiones con presencia de cada institución (16 llamadas AJAX)."""
    mapa: dict[int, list[str]] = {}
    for cod, nombre in REGIONES.items():
        try:
            resp = s.post(URL_AJAX, data={"action": "dcms_ajax_all_filter", "region": cod}, timeout=60)
            data = resp.json()
        except Exception as exc:  # noqa: BLE001 - degradar sin tumbar el pipeline
            log.warning("región %s falló: %s", nombre, exc)
            continue
        # El JSON trae las claves cruzadas: rs_areas_del_conocimiento = instituciones.
        for item in data.get("rs_areas_del_conocimiento", []):
            mapa.setdefault(int(item["id"]), []).append(nombre)
        time.sleep(0.1)
    log.info("mapa regiones: %d instituciones mapeadas", len(mapa))
    return mapa


# --------------------------------------------------------------------------- #
# Orquestador
# --------------------------------------------------------------------------- #
def obtener_empleabilidad(con_region: bool = True) -> Path:
    """
    Descarga y arma el CSV de empleabilidad (institución x carrera) en Entrada/.

    Returns:
        Ruta del CSV generado.
    """
    DIR_ENTRADA.mkdir(parents=True, exist_ok=True)
    s = _sesion()

    df = _obtener_tabla_base(s)

    if con_region:
        mapa = _mapa_regiones(s)
        df["regiones_sede"] = (
            df["id_institucion"]
            .map(lambda i: "|".join(mapa.get(int(i), [])))
            .replace("", pd.NA)
        )
        log.info("regiones asignadas: %d/%d filas",
                 df["regiones_sede"].notna().sum(), len(df))

    destino = DIR_ENTRADA / NOMBRE_SALIDA
    df.to_csv(destino, sep=SEPARADOR_CSV, index=False, encoding="utf-8")
    log.info("CSV generado: %s (%d filas, %d columnas)", destino, len(df), len(df.columns))
    return destino


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    ruta = obtener_empleabilidad()
    df_final = pd.read_csv(ruta, sep=SEPARADOR_CSV)
    print("\n=== Empleabilidad MiFuturo ===")
    print(f"Archivo : {ruta}")
    print(f"Filas   : {len(df_final):,}")
    print(f"Columnas: {len(df_final.columns)}")
    print("Campos  :", ", ".join(df_final.columns))
