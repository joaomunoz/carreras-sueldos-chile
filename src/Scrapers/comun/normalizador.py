"""
<src/Scrapers/comun/normalizador.py>

Reglas únicas de normalización compartidas por los scrapers (Empleabilidad, Estadisticas,
Titulados). Viven en un solo lugar porque las claves de cruce entre fuentes
(`clave_institucion`, `clave_carrera_generica`, `tipo_institucion`) solo coinciden si
todas las fuentes aplican exactamente la misma regla.
"""

import re
import unicodedata


def normalizar_texto(texto: str) -> str:
    """
    Limpia y normaliza cadenas de texto eliminando tildes, espacios excesivos
    y convirtiendo a mayúsculas para facilitar cruces (matching).
    """
    if not isinstance(texto, str):
        return ""
    # Eliminar acentos y diacríticos
    nfkd = unicodedata.normalize('NFKD', texto)
    sin_tildes = "".join([c for c in nfkd if not unicodedata.combining(c)])
    # Mayúsculas y limpieza de espacios
    return re.sub(r'\s+', ' ', sin_tildes).strip().upper()


# Tipo de institución canónico. MiFuturo usa singular ("Universidad") y SIES plural
# ("Universidades"); si cada scraper lo dejara como viene, el cruce entre fuentes
# perdería todas las filas sin error. Las etiquetas cortas son las del análisis.
TIPOS_INSTITUCION: dict[str, str] = {
    "UNIVERSIDAD": "Universidad", "UNIVERSIDADES": "Universidad",
    "INSTITUTO PROFESIONAL": "IP", "INSTITUTOS PROFESIONALES": "IP",
    "CENTRO DE FORMACION TECNICA": "CFT", "CENTROS DE FORMACION TECNICA": "CFT",
}


def normalizar_tipo_institucion(tipo: str) -> str:
    """
    Devuelve 'Universidad', 'IP' o 'CFT'. Falla ante un tipo desconocido: asignarle un
    valor por defecto haría desaparecer esas filas de los cruces sin aviso.
    """
    clave = normalizar_texto(tipo)
    if clave not in TIPOS_INSTITUCION:
        raise ValueError(f"Tipo de institución no reconocido: {tipo!r}")
    return TIPOS_INSTITUCION[clave]
