"""
<src/Web/construir.py>

Arma docs/index.html: un único archivo autónomo a partir de
  src/Web/plantilla.html  (estructura, con marcadores),
  src/Web/estilos.css     → @ESTILOS@,
  src/Web/app.js          → @APP@,
  src/Web/fuentes/*.woff2 → @FUENTE@ (como data URI; licencia OFL en src/Web/fuentes/),
  docs/datos.json         → @DATOS@ (salida de src/Analisis/exportar.py).
Además regenera en README.md el bloque "Hallazgos" (entre los marcadores HALLAZGOS:INICIO y
HALLAZGOS:FIN) desde datos.json["hallazgos"]: así el README y la web citan las mismas cifras, que
se calculan en SQL con controles qa (src/Analisis/sql/analytics/06_hallazgos.sql). Copiarlas a mano
fue como un error de la web llegó también al README. Por la misma razón regenera el conteo de
controles (entre CONTROLES:INICIO y CONTROLES:FIN) desde datos.json["qa"]["resumen"]: escrito a
mano, ya se había desactualizado una vez. Y la brecha cifra nacional − instituciones (dos pares
BRECHA:INICIO/FIN) desde datos.json["que_no_dice"]["brecha_nacional_instituciones"].

Por qué incrustar todo: abierta con doble clic (file://), la página no puede leer un JSON
externo (el navegador lo bloquea), y el requisito es cero dependencias externas.

Uso (desde la raíz del proyecto; no necesita la base de datos):

    python3 src/Web/construir.py

Se niega a construir (código 1, sin tocar docs/index.html) si falta algún insumo, si un
marcador no aparece exactamente una vez, o si el `qa` incrustado en datos.json tiene algún
control en FALLA. Determinista y con escritura atómica, como src/Analisis/exportar.py.
"""

from __future__ import annotations

import base64
import hashlib
import json
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
DIR_WEB = RAIZ / "src" / "Web"
DATOS = RAIZ / "docs" / "datos.json"
SALIDA = RAIZ / "docs" / "index.html"
FUENTE = DIR_WEB / "fuentes" / "ArchivoNarrow-600-latin.woff2"
README = RAIZ / "README.md"
INICIO = "<!-- HALLAZGOS:INICIO · generado por src/Web/construir.py desde docs/datos.json; no editar a mano -->"
FIN = "<!-- HALLAZGOS:FIN -->"
# Marcadores en línea: el conteo vive dentro de una viñeta del README, no en un bloque propio.
CONTROLES_INICIO = "<!-- CONTROLES:INICIO -->"
CONTROLES_FIN = "<!-- CONTROLES:FIN -->"
# La brecha cifra nacional − instituciones aparece dos veces en el README (viñeta y tabla de decisiones).
BRECHA_INICIO = "<!-- BRECHA:INICIO -->"
BRECHA_FIN = "<!-- BRECHA:FIN -->"


def _leer(ruta: Path) -> str:
    if not ruta.exists():
        raise SystemExit(f"Falta {ruta.relative_to(RAIZ)}.")
    return ruta.read_text(encoding="utf-8")


def _verificar_qa(datos: dict) -> None:
    controles = datos.get("qa", {}).get("controles") or []
    if not controles:
        raise SystemExit("datos.json no trae controles qa: exportar de nuevo (src/Analisis/exportar.py).")
    fallas = [f"{c['control']} / {c['objeto']}" for c in controles if c["estado"] == "FALLA"]
    if fallas:
        raise SystemExit("datos.json trae controles en FALLA: " + ", ".join(fallas))


def _json_para_script(datos: dict) -> str:
    # Compacto (la página pesa menos) y con "<" escapado: así ningún texto de los datos puede
    # cerrar el <script> que lo contiene (p. ej. una cadena con "</script>").
    texto = json.dumps(datos, ensure_ascii=False, separators=(",", ":"))
    return texto.replace("<", "\\u003c")


def _fuente_css() -> str:
    if not FUENTE.exists():
        raise SystemExit(f"Falta {FUENTE.relative_to(RAIZ)}.")
    b64 = base64.b64encode(FUENTE.read_bytes()).decode("ascii")
    # Solo el subconjunto latino que contiene el archivo: fuera de ese rango cae a la fuente siguiente.
    return ("@font-face{font-family:\"Archivo Narrow\";font-style:normal;font-weight:600;"
            "font-display:swap;src:url(data:font/woff2;base64," + b64 + ") format(\"woff2\");"
            "unicode-range:U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,"
            "U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD;}")


def _reemplazar(plantilla: str, marcador: str, contenido: str) -> str:
    if plantilla.count(marcador) != 1:
        raise SystemExit(f"El marcador {marcador} debe aparecer exactamente una vez en plantilla.html.")
    return plantilla.replace(marcador, contenido)


def _num(valor: float, decimales: int = 0) -> str:
    # Formato es-CL (1.234,5) sin depender del locale del sistema, que haría el build no determinista.
    texto = f"{abs(valor):,.{decimales}f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return ("−" if valor < 0 else "") + texto


def _hallazgos_readme(h: dict) -> str:
    b, c = h["pct_pesos"], h["dispersion"]
    # (a) por nivel: técnicas y profesionales nunca se resumen con una misma mediana.
    nivel = {x["nivel"]: x for x in h["edad"]}
    tec, pro = nivel.get("Carreras Técnicas"), nivel.get("Carreras Profesionales")
    if tec is None or pro is None:
        raise SystemExit("datos.json no trae el hallazgo (a) para técnicas y profesionales: exportar de nuevo.")
    items = []
    if tec["n_negativos"] or pro["n_negativos"]:
        t = (f"**Al quinto año no siempre se gana más.** El sueldo típico (P50) sube {_num(tec['mediana_p50_pct'], 1)} % "
             f"entre el primer y el quinto año en las carreras técnicas y {_num(pro['mediana_p50_pct'], 1)} % en las "
             f"profesionales (medianas de cada nivel), pero baja en {tec['n_negativos']} de {tec['n_comparables']} técnicas "
             f"y en {pro['n_negativos']} de {pro['n_comparables']} profesionales.")
        if tec["n_con_edad"]:
            t += (f" No es que caigan los sueldos: en {tec['n_con_edad']} de esas {tec['n_negativos']} técnicas, quienes se "
                  f"titularon hace poco son mucho mayores (los de 30 años o más pasan de {_num(tec['mayores30'][0], 1)} % "
                  f"a {_num(tec['mayores30'][1], 1)} %, mediana de esas {tec['n_con_edad']}), y muchos ya trabajaban "
                  f"antes de titularse.")
        items.append(t)
    if b["ejemplo"]:
        e = b["ejemplo"]
        # Por nivel: el fenómeno es de las profesionales; con un total mezclado no se veía.
        tec_txt = ("ninguna técnica" if b["n_cambian_tec"] == 0 else
                   f"{b['n_cambian_tec']} técnica{'s' if b['n_cambian_tec'] > 1 else ''}")
        items.append(f"**Crecer más en porcentaje no es crecer más.** {b['n_cambian_pro']} carreras profesionales "
                     f"({tec_txt}) cambian de cuadrante si el crecimiento se mide en pesos en vez de en porcentaje "
                     f"(sin contar las que quedan a ±{_num(b['margen_pp'])} pp o ±${_num(b['margen_pesos'])} de la "
                     f"carrera del medio de su grupo). {e['nombre']} ({e['tipo']}) sube "
                     f"{_num(e['p50_pct_1_5'], 1)} %, pero eso son +${_num(e['p50_delta_1_5'])}, frente a "
                     f"+${_num(e['ref_delta_q50'])} de la carrera del medio de su grupo (mediana ponderada por titulados).")
    if c["ejemplo"]:
        e = c["ejemplo"]
        items.append(f"**El promedio nacional esconde diferencias entre instituciones.** En {c['n_enganosos']} carreras las "
                     f"instituciones difieren {_num(c['umbral_pp'])} puntos o más en empleabilidad, aun dejando fuera al "
                     f"cuarto más alto y al cuarto más bajo. En {e['nombre']} ({e['tipo']}, {e['n_inst']} instituciones) "
                     f"la mitad central va de {_num(e['q1'], 1)} % a {_num(e['q3'], 1)} %, con una cifra nacional de "
                     f"{_num(e['nacional'], 1)} %.")
    # (d) continuidad de estudios por nivel, ponderada por titulados (06_hallazgos.sql).
    d = h.get("continuidad") or {}
    niv = {x["nivel"]: x for x in d.get("niveles") or []}
    ej = d.get("ejemplos") or {}
    if "Carreras Técnicas" in niv and "Carreras Profesionales" in niv and "alto" in ej and "bajo" in ej:
        t, p, a, b_ = niv["Carreras Técnicas"], niv["Carreras Profesionales"], ej["alto"], ej["bajo"]
        items.append(f"**Seguir estudiando es cosa de las carreras técnicas.** Al año siguiente de titularse sigue "
                     f"estudiando el {_num(t['pct'], 1)} % de los titulados de carreras técnicas y el {_num(p['pct'], 1)} % "
                     f"de los de carreras profesionales (promedio ponderado por titulados). Depende de la carrera: "
                     f"{_num(a['pct'], 1)} % en {a['nombre']} ({a['tipo']}) y {_num(b_['pct'], 1)} % en {b_['nombre']} "
                     f"({b_['tipo']}). No explica las diferencias de empleabilidad entre instituciones de una misma carrera.")
    return "\n".join(f"{i}. {t}" for i, t in enumerate(items, 1))


def _controles_readme(qa: dict) -> str:
    resumen = qa["resumen"]
    if set(resumen) - {"OK", "EXENTO"}:   # _verificar_qa ya descarta FALLA; otro estado sería nuevo
        raise SystemExit(f"Estados qa inesperados para el README: {sorted(resumen)}")
    ok, exentos = resumen.get("OK", 0), resumen.get("EXENTO", 0)
    return (f"**{ok + exentos} controles de calidad**: {ok} hacen fallar el build y "
            f"{exentos} están exentos por diseño (documentados)")


def _brecha_readme(qnd: dict) -> str:
    b = qnd["brecha_nacional_instituciones"]
    # 1 decimal, como la web ("Qué no dice"): el README y la página citan la misma cifra.
    return (f"+{_num(b['emp_pp'], 1)} puntos de empleabilidad y "
            f"+{_num(b['tramo_pct'], 1)} % en el rango de ingreso al 4° año")


def _reemplazar_bloque(texto: str, inicio: str, fin: str, contenido: str, veces: int = 1) -> str:
    if texto.count(inicio) != veces or texto.count(fin) != veces:
        raise SystemExit(f"README.md debe tener {veces} vez/veces cada marcador {inicio} / {fin}.")
    partes = texto.split(inicio)
    salida = partes[0]
    for parte in partes[1:]:
        _, despues = parte.split(fin, 1)
        salida += inicio + contenido + fin + despues
    return salida


def _actualizar_readme(datos: dict) -> None:
    texto = _leer(README)
    nuevo = _reemplazar_bloque(texto, INICIO, FIN, "\n" + _hallazgos_readme(datos["hallazgos"]) + "\n")
    nuevo = _reemplazar_bloque(nuevo, CONTROLES_INICIO, CONTROLES_FIN, _controles_readme(datos["qa"]))
    nuevo = _reemplazar_bloque(nuevo, BRECHA_INICIO, BRECHA_FIN, _brecha_readme(datos["que_no_dice"]), veces=2)
    if nuevo != texto:   # sin cambios no se reescribe: git no ve diferencias falsas
        temporal = README.with_suffix(".md.tmp")
        temporal.write_text(nuevo, encoding="utf-8")
        temporal.replace(README)


def construir() -> str:
    plantilla = _leer(DIR_WEB / "plantilla.html")
    estilos = _leer(DIR_WEB / "estilos.css")
    app = _leer(DIR_WEB / "app.js")
    # Un "</style" o "</script" literal dentro del CSS o JS cortaría la página en silencio.
    for nombre, texto, cierre in (("estilos.css", estilos, "</style"), ("app.js", app, "</script")):
        if cierre in texto.lower():
            raise SystemExit(f"{nombre} contiene '{cierre}': rompería la página incrustada.")

    datos = json.loads(_leer(DATOS))
    _verificar_qa(datos)
    if "hallazgos" not in datos:
        raise SystemExit("datos.json no trae 'hallazgos': exportar de nuevo (src/Analisis/exportar.py).")

    html = plantilla
    html = _reemplazar(html, "/*@FUENTE@*/", _fuente_css())
    html = _reemplazar(html, "/*@ESTILOS@*/", estilos)
    html = _reemplazar(html, "@DATOS@", _json_para_script(datos))
    html = _reemplazar(html, "/*@APP@*/", app)

    SALIDA.parent.mkdir(parents=True, exist_ok=True)
    temporal = SALIDA.with_suffix(".html.tmp")
    temporal.write_text(html, encoding="utf-8")
    temporal.replace(SALIDA)
    _actualizar_readme(datos)   # después de index.html: si la web no se construye, el README no cambia
    return hashlib.sha256(html.encode("utf-8")).hexdigest()


if __name__ == "__main__":
    huella = construir()
    print(f"Construido {SALIDA.relative_to(RAIZ)} ({SALIDA.stat().st_size / 1024:.0f} KB), sha256 {huella[:16]}…")
    sys.exit(0)
