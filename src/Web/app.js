/* src/Web/app.js
 *
 * Lógica de la página. Los datos vienen incrustados en <script id="datos"> por
 * src/Web/construir.py (desde docs/datos.json): nada se pide a la red, así la página funciona
 * con doble clic. Ninguna cifra del texto se escribe a mano: todas se leen de `datos`,
 * incluidos los umbrales (datos.parametros), para que la página no pueda contradecir al análisis.
 */
(function () {
  "use strict";

  var datos = JSON.parse(document.getElementById("datos").textContent);
  var pares = datos.pares;

  // ------------------------------------------------------------- formato (es-CL)
  var fmtEntero = new Intl.NumberFormat("es-CL", { maximumFractionDigits: 0 });
  var fmtUno = new Intl.NumberFormat("es-CL", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

  function pct(valor) { return valor == null ? "—" : fmtUno.format(valor) + " %"; }
  function pctSigno(valor) {
    if (valor == null) return "—";
    return (valor > 0 ? "+" : valor < 0 ? "−" : "") + fmtUno.format(Math.abs(valor)) + " %";
  }
  function pesos(valor) { return valor == null ? "—" : "$" + fmtEntero.format(valor); }
  function pesosSigno(valor) {
    return (valor > 0 ? "+" : valor < 0 ? "−" : "") + "$" + fmtEntero.format(Math.abs(valor));
  }

  function el(etiqueta, clase, texto) {
    var nodo = document.createElement(etiqueta);
    if (clase) nodo.className = clase;
    if (texto != null) nodo.textContent = texto;
    return nodo;
  }

  function parametro(nombre) {
    for (var i = 0; i < datos.parametros.length; i++) {
      if (datos.parametros[i].nombre === nombre) return datos.parametros[i].valor;
    }
    throw new Error("Parámetro inexistente en datos.json: " + nombre);
  }

  function maximoPor(lista, clave) {
    return lista.reduce(function (mejor, x) { return mejor == null || clave(x) > clave(mejor) ? x : mejor; }, null);
  }

  // Sin tildes y en minúsculas: "enfermeria" encuentra "Enfermería".
  function normalizar(texto) {
    return texto.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  }

  var comparables = pares.filter(function (p) { return p.marcas.representativo; });
  var segmentoDe = {};
  datos.segmentos.forEach(function (s) { segmentoDe[s.tipo + "|" + s.nivel] = s; });

  // ------------------------------------------------------------- timbres (advertencias)
  // Una sola definición por timbre: el texto de la leyenda y el del title salen de aquí.
  var TIMBRES = [
    { id: "no_comparable", texto: "No comparable",
      aplica: function (p) { return !p.marcas.representativo; },
      explica: function () {
        return "Menos de " + parametro("min_inst_oferta") + " instituciones la ofrecen: su cifra nacional es en realidad la de una o dos instituciones. Aparece en la tabla, pero no en rankings ni comparaciones.";
      } },
    { id: "cohorte_atipica", texto: "Cohorte atípica",
      aplica: function (p) { return p.marcas.cohorte_atipica; },
      explica: function () {
        return "La empleabilidad de quienes se titularon en el año del P50 del primer año se aleja al menos " + parametro("min_desvio_atipico_pp") + " puntos de la de las cohortes anteriores: su sueldo del primer año viene de un año anómalo.";
      } },
    { id: "composicion_edad", texto: "Composición por edad",
      aplica: function (p) { return p.marcas.composicion_edad; },
      explica: function () {
        return "Entre los titulados recientes hay al menos " + parametro("min_cambio_edad_pp") + " puntos más de personas de 30 años o más que hace cinco años. Muchos ya trabajaban: la comparación entre el primer y el quinto año mezcla edades.";
      } },
    { id: "promedio_enganoso", texto: "Promedio engañoso",
      aplica: function (p) { return p.marcas.promedio_enganoso; },
      explica: function () {
        return "Las instituciones que la ofrecen difieren " + parametro("min_iqr_enganoso") + " puntos o más en empleabilidad (rango intercuartílico): el promedio nacional describe mal a cada una.";
      } },
    { id: "baja_cobertura", texto: "Baja cobertura",
      aplica: function (p) { return p.marcas.baja_cobertura; },
      explica: function () {
        return "MiFuturo publica programas que reúnen menos del " + fmtEntero.format(parametro("max_cobertura_baja") * 100) + " % de los titulados de este tipo de institución y nivel.";
      } },
    { id: "derecho", texto: "Cohortes +1 año",
      aplica: function (p) { return p.marcas.es_derecho; },
      explica: function () {
        return "Derecho se mide con las cohortes corridas un año, porque la titulación efectiva llega meses después del último trámite en la universidad.";
      } }
  ];

  function timbre(def) {
    var nodo = el("span", "timbre", def.texto);
    nodo.title = def.explica();
    return nodo;
  }

  function pintarLeyenda() {
    var dl = document.getElementById("leyenda");
    TIMBRES.forEach(function (def) {
      var dt = el("dt");
      dt.appendChild(timbre(def));
      dl.appendChild(dt);
      dl.appendChild(el("dd", null, def.explica()));
    });
  }

  // ------------------------------------------------------------- portada (N2)
  // Tesis y línea técnica, redactadas desde datos.json: la tesis usa las medianas por nivel de
  // analytics.hallazgo_edad (nunca una mediana que mezcle técnicas y profesionales).
  function nivelEdad(nombre) {
    return datos.hallazgos.edad.filter(function (x) { return x.nivel === nombre; })[0];
  }

  function pintarPortada() {
    var tec = nivelEdad("Carreras Técnicas"), pro = nivelEdad("Carreras Profesionales");
    var tesis = document.getElementById("portada-tesis");
    if (tec && pro) {
      // "más" / "menos" según el signo: con datos nuevos una mediana podría quedar bajo cero.
      var dif = function (v) { return [pct(Math.abs(v)), v < 0 ? " menos" : " más"]; };
      var dt = dif(tec.mediana_p50_pct), dp = dif(pro.mediana_p50_pct);
      parrafoEn(tesis, ["Compara a quienes se titularon hace un año con quienes se titularon hace cinco (MiFuturo y SIES). " +
        "En la técnica típica, los segundos ganan ", dt[0], dt[1] + "; en la profesional, ",
        dp[0], dp[1] + ". Hay tres resultados que conviene conocer antes de comparar carreras, y "]);
      // Termina en una acción: la Parte II, donde el lector busca su carrera.
      var ir = el("a", null, "puedes revisar tu carrera");
      ir.href = "#parte-carrera";
      tesis.appendChild(ir);
      tesis.appendChild(document.createTextNode("."));
    }
    var qa = datos.qa.resumen, qnd = datos.que_no_dice;
    var total = (qa.OK || 0) + (qa.EXENTO || 0);
    // El universo va en el antetítulo (una sola vez); la línea técnica queda como respaldo.
    document.getElementById("portada-eyebrow").textContent =
      fmtEntero.format(qnd.pares_total) + " carreras · universidades, IP y CFT · Chile";
    parrafoEn(document.getElementById("portada-tecnica"), [
      "", fmtEntero.format(qnd.pares_total - qnd.pares_no_representativos), " carreras comparables · ",
      fmtEntero.format(total), " controles de calidad · pesos de septiembre de 2025"]);
  }

  // ------------------------------------------------------------- títulos y cierre (N5)
  // Los títulos de los gráficos dicen lo que muestran (no qué son), con conteos de SQL. Si falta
  // un dato, queda el título descriptivo de la plantilla.
  function pintarTitulos() {
    var tec = nivelEdad("Carreras Técnicas"), pro = nivelEdad("Carreras Profesionales");
    if (tec && pro) {
      var neg = tec.n_negativos + pro.n_negativos;
      document.getElementById("t-peine").textContent = neg
        ? fmtEntero.format(neg) + " de " + fmtEntero.format(tec.n_comparables + pro.n_comparables) +
          " carreras ganan menos al quinto año" + (tec.n_negativos ? ", " + fmtEntero.format(tec.n_negativos) +
          (tec.n_negativos === 1 ? " de ellas técnica" : " de ellas técnicas") : "")
        : "Todas las carreras comparables ganan más al quinto año";
    }
    // Por nivel: el hallazgo es de las profesionales (en las técnicas no cambia ninguna).
    var b = datos.hallazgos.pct_pesos;
    if (b.n_cambian_pro) {
      document.getElementById("t-cuadrantes").textContent = fmtEntero.format(b.n_cambian_pro) +
        (b.n_cambian_pro === 1 ? " carrera profesional cambia" : " carreras profesionales cambian") +
        " de cuadrante si el crecimiento se mide en pesos";
    }
  }

  // Cierre de la Parte I: los tres resultados traducidos a cómo comparar. Sin cifras: ya están en
  // las tarjetas, y repetirlas una tercera vez solo alargaba la lectura (revisión design-is).
  function pintarCierre() {
    var ul = document.getElementById("llevar");
    var items = [
      ["Compara dentro del mismo nivel. ", "Las carreras técnicas y las profesionales crecen a ritmos muy distintos: un promedio de ambas no describe a ninguna."],
      ["Mira el aumento en pesos, no solo el porcentaje. ", "Una carrera que parte con un sueldo bajo puede crecer mucho en porcentaje y sumar poco a fin de mes."],
      ["Mira tu institución, no solo la cifra nacional. ", "En algunas carreras, la empleabilidad cambia mucho de una institución a otra."]
    ];
    items.forEach(function (it) {
      var li = el("li");
      li.appendChild(el("strong", null, it[0]));
      li.appendChild(document.createTextNode(it[1]));
      ul.appendChild(li);
    });
  }

  // ------------------------------------------------------------- hallazgos
  // Texto con cifras en <strong>: partes alternan texto y cifra ([texto, cifra, texto, ...]).
  function parrafoEn(nodo, partes) {
    partes.forEach(function (parte, i) {
      nodo.appendChild(i % 2 ? el("strong", null, parte) : document.createTextNode(parte));
    });
    return nodo;
  }
  function parrafo(partes) { return parrafoEn(el("p"), partes); }

  // Tarjeta de la grilla: la cifra grande con su unidad en la frase que sigue, un ejemplo
  // verificable y un enlace a la evidencia (gráfico o ficha). Se lee cifra → resultado → ejemplo.
  function hallazgo(t) {
    var li = el("li", "hallazgo");
    li.appendChild(el("p", "hallazgo__cifra", t.cifra));
    li.appendChild(el("p", "hallazgo__resultado", t.resultado));
    var ejemplo = el("div", "hallazgo__ejemplo");
    t.nodos.forEach(function (n) { ejemplo.appendChild(n); });
    li.appendChild(ejemplo);
    var accion;
    if (t.href) {
      accion = el("a", "hallazgo__accion", t.accion);
      accion.href = t.href;
      if (t.alClic) accion.addEventListener("click", t.alClic);
    } else {
      accion = el("button", "hallazgo__accion enlace-ficha", t.accion);
      accion.type = "button";
      accion.addEventListener("click", function () { abrirFicha(t.par, true); });
    }
    li.appendChild(accion);
    return li;
  }

  // Título propio de cada gráfico: métrica, unidad y universo, justo sobre el trazado. El título de
  // la sección dice la conclusión; este dice qué se está mirando (rúbrica Google + McCandless).
  function tituloGrafico(texto) { return el("p", "grafico__titulo", texto); }

  // Las cifras y los ejemplos de los hallazgos vienen calculados de la base
  // (src/Analisis/sql/analytics/06_hallazgos.sql, con controles qa): aquí solo se redactan.
  // Calcularlos aquí produjo errores que ningún control veía (una mediana de edad de 9
  // carreras atribuida a 7). Si un hallazgo no tiene ejemplo, se omite sin cortar los demás.
  // Cómo se llama cada tipo de institución en plural, dentro de una frase.
  var TIPO_PLURAL = { Universidad: "universidades", IP: "IP", CFT: "CFT" };
  var TIPO_ADJ = { Universidad: "universitarias", IP: "de IP", CFT: "de CFT" };

  // Grupo de comparación del hallazgo (b), en palabras: «las carreras universitarias de su área
  // (ingeniería, industria y construcción)» o, sin área, «las carreras profesionales universitarias».
  function grupoEnPalabras(g) {
    if (g.tipo_grupo === "celda") {
      return "las carreras " + TIPO_ADJ[g.tipo] + " de su área (" + g.area.toLowerCase() + ")";
    }
    return "las carreras " + nivelCorto({ nivel: g.nivel }) + " " + TIPO_ADJ[g.tipo];
  }

  function pintarHallazgos() {
    var ul = document.getElementById("hallazgos");
    var h = datos.hallazgos;

    // (a) por nivel: técnicas y profesionales nunca se resumen con una misma mediana. «Hace 5 y
    // hace 1 año»: son dos grupos de titulados, no las mismas personas en el tiempo.
    var tec = nivelEdad("Carreras Técnicas");
    if (tec && tec.n_negativos) {
      var unaA = tec.n_negativos === 1;
      var nodosA = [el("p", null, "No es que el sueldo baje: son grupos distintos de titulados." +
        (tec.n_con_edad ? " En " + fmtEntero.format(tec.n_con_edad) + " de esas carreras" +
          ", los recién titulados son mayores y muchos ya trabajaban antes de titularse." : ""))];
      ul.appendChild(hallazgo({
        cifra: fmtEntero.format(tec.n_negativos) + " de " + fmtEntero.format(tec.n_comparables),
        resultado: "carreras técnicas: quienes se titularon hace 5 años ganan menos que quienes se titularon hace 1.",
        nodos: nodosA, accion: unaA ? "Verla en el gráfico ↓" : "Ver esas " + fmtEntero.format(tec.n_negativos) + " carreras ↓",
        href: "#t-peine",
        alClic: function () { elegirNivelPeine("Carreras Técnicas"); }
      }));
    }

    // (b) los dos sueldos, el % y los pesos del ejemplo y de su grupo: sin ellos «sube 66,5 %» no
    // decía desde dónde ni contra qué. Del grupo solo el aumento (sus medianas del 1er y 5° año se
    // calculan por separado y su resta no da el aumento típico).
    var b = h.pct_pesos, eb = b.ejemplo;
    var pb = eb && parPorClave[eb.clave + "|" + eb.tipo];
    if (pb && eb.grupo) {
      var unaB = b.n_cambian_pro === 1;
      ul.appendChild(hallazgo({
        cifra: fmtEntero.format(b.n_cambian_pro),
        resultado: (unaB ? "carrera profesional crece" : "carreras profesionales crecen") +
          " más que su grupo en porcentaje, pero menos en pesos, o al revés." +
          (b.n_cambian_tec ? " También " + fmtEntero.format(b.n_cambian_tec) + (b.n_cambian_tec === 1 ? " técnica." : " técnicas.") : ""),
        nodos: [parrafo([eb.nombre + ": quienes llevan 1 año titulados ganan ", pesos(eb.p50_anio_1),
          " y quienes llevan 5 años, ", pesos(eb.p50_anio_5), ". Es un ", pct(eb.p50_pct_1_5),
          " más; en " + grupoEnPalabras(eb.grupo) + ", un ", pct(eb.ref_pct_q50),
          ". Pero son ", pesos(eb.p50_delta_1_5), " más al mes, contra ", pesos(eb.ref_delta_q50), " en ellas."])],
        accion: "Ver " + eb.nombre + " →", par: pb
      }));
    }

    // (c) se cita la mitad central de las instituciones (lo que mide el criterio).
    var c = h.dispersion, ec = c.ejemplo;
    var pc = ec && parPorClave[ec.clave + "|" + ec.tipo];
    if (pc) {
      ul.appendChild(hallazgo({
        cifra: fmtEntero.format(c.n_enganosos),
        resultado: (c.n_enganosos === 1 ? "carrera" : "carreras") + ": su empleabilidad (el % de titulados que gana al menos el sueldo mínimo al 1er año) difiere " +
          fmtEntero.format(c.umbral_pp) + " puntos o más según la institución.",
        nodos: [parrafo(["En " + ec.nombre + ", la mitad de las " + TIPO_PLURAL[ec.tipo] + " está entre ",
          pct(ec.q1), " y ", pct(ec.q3), "; la cifra nacional es ", pct(ec.nacional), "."])],
        accion: "Ver " + ec.nombre + " →", par: pc
      }));
    }
  }

  // ------------------------------------------------------------- a quiénes mira el análisis
  // Titulaciones SIES por año (06b_universo.sql). El color dice a qué grupo pertenece cada año,
  // con los mismos verdes de todo el sitio: oscuro = medidos al 5° año, claro = al 1er año; gris =
  // años fuera del análisis. Técnicas y profesionales se distinguen por trama (no por color), para
  // no gastar un color nuevo ni chocar con el significado de los verdes. Sumar ambos niveles está
  // bien aquí: son conteos de títulos, no medianas de sueldo.
  var universo = { activo: -1 };

  function rangoAnios(v) { return v[0] + "–" + v[1]; }
  function grupoDeAnio(a, ventanas, corto) {
    if (a.ventana === "5to") return corto ? "Al 5° año" : "Medidos al 5° año";
    if (a.ventana === "1er") return corto ? "Al 1er año" : "Medidos al 1er año";
    return corto ? "Fuera" : "Fuera del análisis";
  }

  function pintarUniversoTextos() {
    var u = datos.universo, v = u.ventanas, qnd = datos.que_no_dice;
    document.getElementById("t-universo").textContent = "El análisis compara a quienes se titularon en " +
      rangoAnios(v["5to"]) + " con quienes se titularon en " + rangoAnios(v["1er"]);
    document.getElementById("universo-titulo").textContent =
      "Titulaciones de pregrado por año · universidades, IP y CFT · SIES";
    var t1 = u.totales.filter(function (t) { return t.ventana === "1er"; })[0];
    var t5 = u.totales.filter(function (t) { return t.ventana === "5to"; })[0];
    var nComp = fmtEntero.format(qnd.pares_total - qnd.pares_no_representativos);
    pintarUniversoResumen(u, v);
    parrafoEn(document.getElementById("universo-embudo"), [
      "De esos títulos, el ", pct(t1.pct_comparables), " de " + rangoAnios(v["1er"]) + " y el ", pct(t5.pct_comparables),
      " de " + rangoAnios(v["5to"]) + " son de las " + nComp + " carreras que se comparan (" ,
      fmtEntero.format(t1.comparables), " y ", fmtEntero.format(t5.comparables), ")."]);
    var otros = u.embudo.filter(function (e) { return e.otro > 0; });
    var notaOtro = otros.map(function (e) {
      return fmtEntero.format(e.otro) + (e.otro === 1 ? " título" : " títulos") + " de " + rangoAnios(v[e.ventana]) +
        " (" + nivelCorto({ nivel: e.nivel }) + ")" + (e.otro === 1 ? " está registrado" : " están registrados") + " como no binario";
    }).join("; ");
    document.getElementById("universo-nota").textContent =
      "Se cuentan títulos, no personas: quien obtiene dos títulos cuenta dos veces. " +
      "Derecho se cuenta un año después, como en el resto del análisis, porque su titulación llega meses después del último trámite." +
      (notaOtro ? " " + notaOtro.charAt(0).toUpperCase() + notaOtro.slice(1) + " y no entra en los porcentajes por sexo." : "");

    var cuerpo = document.querySelector("#universo-tabla tbody");
    u.anual.forEach(function (a) {
      var tr = el("tr");
      [["Año", String(a.anio), "td--titulo"],
       ["Técnicas", fmtEntero.format(a.tecnicas), "num"],
       ["Profesionales", fmtEntero.format(a.profesionales), "num"],
       ["Total", fmtEntero.format(a.total), "num"],
       ["En el análisis", a.ventana ? grupoDeAnio(a) + " (" + rangoAnios(v[a.ventana]) + ")" : "No", ""]
      ].forEach(function (c) {
        var td = el("td", c[2] || null, c[1]);
        td.setAttribute("data-rotulo", c[0]);
        tr.appendChild(td);
      });
      cuerpo.appendChild(tr);
    });
  }

  // Total de cada grupo por nivel, con su barra mujeres / hombres (la misma de la ficha). El título
  // dice lo que muestran las cifras, armado desde ellas: si un dato nuevo lo contradice, cambia solo.
  function pintarUniversoResumen(u, v) {
    var cont = document.getElementById("universo-resumen");
    var filas = u.embudo, tec = filas.filter(function (e) { return e.nivel === "Carreras Técnicas"; });
    var pro = filas.filter(function (e) { return e.nivel === "Carreras Profesionales"; });
    var todasMuj = filas.every(function (e) { return e.pct_mujeres > 50; });
    var masEnTec = tec.every(function (t) {
      var par = pro.filter(function (p) { return p.ventana === t.ventana; })[0];
      return par && t.pct_mujeres > par.pct_mujeres;
    });
    document.getElementById("universo-resumen-titulo").textContent = todasMuj
      ? "En los dos grupos hay más mujeres que hombres" + (masEnTec ? ", sobre todo en las carreras técnicas" : "")
      : "Títulos por nivel y sexo en cada grupo";
    ["1er", "5to"].forEach(function (ven) {
      var total = u.totales.filter(function (t) { return t.ventana === ven; })[0];
      var grupo = el("section", "u-grupo");
      var cab = el("p", "u-grupo__titulo");
      cab.appendChild(el("strong", null, "Titulados " + rangoAnios(v[ven])));
      cab.appendChild(document.createTextNode(" · " + (ven === "1er" ? "medidos al 1er año" : "medidos al 5° año")));
      grupo.appendChild(cab);
      grupo.appendChild(el("p", "u-grupo__total", fmtEntero.format(total.sies) + " títulos"));
      ["Carreras Técnicas", "Carreras Profesionales"].forEach(function (nivel) {
        var e = filas.filter(function (x) { return x.ventana === ven && x.nivel === nivel; })[0];
        if (!e) return;
        var fila = el("div", "u-fila");
        var cabeza = el("p", "u-fila__cabeza");
        cabeza.appendChild(el("span", "u-fila__nivel", nivel.replace("Carreras ", "")));
        cabeza.appendChild(el("span", "u-fila__n", fmtEntero.format(e.sies)));
        fila.appendChild(cabeza);
        fila.appendChild(barraSexo({ pct_mujeres: e.pct_mujeres, pct_hombres: e.pct_hombres,
          mujeres: e.mujeres, hombres: e.hombres, sin_dato: 0 },
          "Titulados " + rangoAnios(v[ven]) + ", carreras " + nivelCorto({ nivel: nivel })));
        grupo.appendChild(fila);
      });
      cont.appendChild(grupo);
    });
  }

  function pintarUniverso() {
    var u = datos.universo, anual = u.anual;
    var lienzo = document.getElementById("universo-lienzo");
    var figura = document.getElementById("universo");
    var caja = document.getElementById("universo-tooltip");
    var W = lienzo.clientWidth || 800;
    var angosto = W < 600;
    var H = angosto ? 250 : 300;
    var m = { izq: angosto ? 58 : 66, der: 6, arriba: 40, abajo: 34 };
    var n = anual.length, banda = (W - m.izq - m.der) / n, ancho = Math.min(banda * 0.72, 64);
    var max = Math.max.apply(null, anual.map(function (a) { return a.total; }));
    var paso = angosto ? 100000 : 50000;
    var tope = Math.ceil(max / paso) * paso;
    function x(i) { return m.izq + banda * (i + 0.5); }
    function y(v) { return m.arriba + (1 - v / tope) * (H - m.arriba - m.abajo); }

    var svg = svgEl("svg", { viewBox: "0 0 " + W + " " + H, height: H, role: "img",
      "aria-label": "Titulaciones por año de " + anual[0].anio + " a " + anual[n - 1].anio +
        ". Detalle en la tabla «Ver las cifras por año»." });
    // Trama de las técnicas: líneas del color del papel sobre la columna (textura, no color).
    var defs = svgEl("defs", {}, null, svg);
    var trama = svgEl("pattern", { id: "u-trama", width: 5, height: 5, patternUnits: "userSpaceOnUse",
      patternTransform: "rotate(45)" }, null, defs);
    svgEl("line", { x1: 0, y1: 0, x2: 0, y2: 5 }, "u-trama-linea", trama);

    for (var v = 0; v <= tope; v += paso) {
      svgEl("line", { x1: m.izq, x2: W - m.der, y1: y(v), y2: y(v) }, "g-grilla", svg);
      svgEl("text", { x: m.izq - 6, y: y(v) + 4, "text-anchor": "end" }, "g-eje-texto", svg).textContent = fmtEntero.format(v);
    }
    var resalte = svgEl("rect", { x: 0, y: m.arriba - 4, width: banda, height: H - m.arriba - m.abajo + 4, rx: 2 }, "g-resalte", svg);
    resalte.style.display = "none";

    anual.forEach(function (a, i) {
      var clase = a.ventana === "5to" ? "u-col--5" : a.ventana === "1er" ? "u-col--1" : "u-col--fuera";
      var x0 = x(i) - ancho / 2;
      // Técnicas abajo, profesionales arriba, con 2 px de papel entre ambas (separación de relleno).
      var yTec = y(a.tecnicas), yTot = y(a.total);
      svgEl("rect", { x: x0, y: yTec, width: ancho, height: y(0) - yTec }, "u-col " + clase, svg);
      svgEl("rect", { x: x0, y: yTec, width: ancho, height: y(0) - yTec, fill: "url(#u-trama)" }, null, svg);
      svgEl("rect", { x: x0, y: yTot, width: ancho, height: Math.max(0, yTec - yTot - 2), rx: 2 }, "u-col " + clase, svg);
      svgEl("text", { x: x(i), y: H - m.abajo + 15, "text-anchor": "middle" }, "g-eje-texto", svg).textContent =
        angosto ? "’" + String(a.anio).slice(2) : String(a.anio);
    });

    // Rótulos directos de los grupos: una llave sobre cada tramo de años consecutivos del mismo grupo.
    var tramos = [];
    anual.forEach(function (a, i) {
      var g = a.ventana || "fuera";
      var ultimo = tramos[tramos.length - 1];
      if (ultimo && ultimo.g === g && ultimo.hasta === i - 1) ultimo.hasta = i;
      else tramos.push({ g: g, desde: i, hasta: i, a: a });
    });
    tramos.forEach(function (t) {
      // Un año suelto fuera del análisis (2020) no lleva llave: se explica bajo su año.
      if (t.g === "fuera" && t.desde === t.hasta) return;
      var x1 = x(t.desde) - ancho / 2, x2 = x(t.hasta) + ancho / 2, yl = m.arriba - 14;
      svgEl("polyline", { points: x1 + "," + (yl + 5) + " " + x1 + "," + yl + " " + x2 + "," + yl + " " + x2 + "," + (yl + 5),
        fill: "none" }, "g-guia", svg);
      svgEl("text", { x: (x1 + x2) / 2, y: yl - 6, "text-anchor": "middle" }, "g-rotulo", svg).textContent =
        grupoDeAnio(t.a, null, angosto);
    });
    // 2020 (o cualquier año suelto fuera del análisis): nota bajo el año, sin chocar con las columnas.
    anual.forEach(function (a, i) {
      var solo = !a.ventana && (i > 0 && anual[i - 1].ventana) && (i < n - 1 && anual[i + 1].ventana);
      if (solo) {
        svgEl("text", { x: x(i), y: H - m.abajo + 29, "text-anchor": "middle" }, "u-nota-anio", svg).textContent = "pandemia";
      }
    });

    // Zonas de puntero: toda la banda del año (más grande que la columna).
    var zonas = svgEl("g", {}, null, svg);
    anual.forEach(function (a, i) {
      svgEl("rect", { x: m.izq + banda * i, y: m.arriba - 4, width: banda, height: H - m.arriba - m.abajo + 4, fill: "transparent" }, null, zonas);
    });
    lienzo.replaceChildren(svg);
    lienzo.tabIndex = 0;
    lienzo.setAttribute("aria-label", "Gráfico de titulaciones por año: recórrelo con las flechas ← →");

    function mostrar(i) {
      universo.activo = i;
      if (i < 0) { caja.hidden = true; resalte.style.display = "none"; return; }
      var a = anual[i], v = u.ventanas;
      resalte.setAttribute("x", m.izq + banda * i);
      resalte.style.display = "";
      caja.replaceChildren();
      caja.appendChild(el("div", "tooltip__titulo", String(a.anio)));
      caja.appendChild(el("div", "tooltip__sub", a.ventana ? grupoDeAnio(a) + " · titulados " + rangoAnios(v[a.ventana])
        : (i > 0 && anual[i - 1].ventana && i < n - 1 && anual[i + 1].ventana ? "Fuera del análisis (pandemia)" : "Fuera del análisis")));
      var cifras = el("div", "tooltip__cifras");
      cifras.appendChild(el("div", null, "Profesionales " + fmtEntero.format(a.profesionales)));
      cifras.appendChild(el("div", null, "Técnicas " + fmtEntero.format(a.tecnicas)));
      cifras.appendChild(el("div", null, "Total " + fmtEntero.format(a.total)));
      caja.appendChild(cifras);
      ubicarTooltip(caja, figura, lienzo.offsetLeft + x(i) * lienzo.clientWidth / W, lienzo.offsetTop + y(a.total) * lienzo.clientWidth / W);
    }
    function desdePuntero(e) {
      var r = svg.getBoundingClientRect();
      var px = (e.clientX - r.left) * W / r.width;
      var i = Math.floor((px - m.izq) / banda);
      mostrar(i >= 0 && i < n ? i : -1);
    }
    svg.addEventListener("pointermove", desdePuntero);
    svg.addEventListener("pointerdown", desdePuntero);
    svg.addEventListener("pointerleave", function () { mostrar(-1); });
    lienzo.onkeydown = function (e) {
      if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
        e.preventDefault();
        var i = universo.activo < 0 ? (e.key === "ArrowRight" ? 0 : n - 1)
          : Math.max(0, Math.min(n - 1, universo.activo + (e.key === "ArrowRight" ? 1 : -1)));
        mostrar(i);
      } else if (e.key === "Escape") { mostrar(-1); }
    };
    lienzo.onblur = function () { mostrar(-1); };
  }

  // ------------------------------------------------------------- tabla de segmentos
  function pintarSegmentos() {
    var cuerpo = document.querySelector("#tabla-segmentos tbody");
    var defBaja = TIMBRES.filter(function (t) { return t.id === "baja_cobertura"; })[0];
    datos.segmentos.forEach(function (s) {
      var tr = el("tr");
      var celdas = [
        ["Tipo de institución", s.tipo, "td--titulo"],
        ["Nivel", s.nivel.replace("Carreras ", ""), ""],
        ["Carreras", fmtEntero.format(s.pares), "num"],
        ["Comparables", fmtEntero.format(s.representativos), "num"],
        ["Cobertura, titulados recientes", pct(s.cobertura[0]), "num"],
        ["Cobertura, hace cinco años", pct(s.cobertura[1]), "num"]
      ];
      celdas.forEach(function (c) {
        var td = el("td", c[2] || null, c[1]);
        td.setAttribute("data-rotulo", c[0]);
        tr.appendChild(td);
      });
      var adv = el("td");
      adv.setAttribute("data-rotulo", "Advertencias");
      if (s.baja_cobertura) adv.appendChild(timbre(defBaja));
      tr.appendChild(adv);
      cuerpo.appendChild(tr);
    });
  }

  // ------------------------------------------------------------- formatos de la Parte II
  var colador = new Intl.Collator("es", { sensitivity: "base" });

  // Todos los sueldos de la página van en pesos enteros ("$1.064.123"), en texto, tablas y ejes:
  // un solo formato, sin convertir "mil" o "M" para comparar (pedido del usuario, 17-11-26).

  // ------------------------------------------------------------- utilidades SVG y tooltip
  var NS = "http://www.w3.org/2000/svg";
  function svgEl(tipo, atributos, clase, padre) {
    var n = document.createElementNS(NS, tipo);
    Object.keys(atributos).forEach(function (k) { n.setAttribute(k, atributos[k]); });
    if (clase) n.setAttribute("class", clase);
    if (padre) padre.appendChild(n);
    return n;
  }


  // Marcas del eje cada 250 mil, 500 mil o 1 millón, según el rango (≈ 4 a 8 marcas).
  function marcasPesos(lo, hi) {
    var paso = (hi - lo) > 5e6 ? 1000000 : (hi - lo) > 2.5e6 ? 500000 : 250000;
    var ticks = [];
    for (var v = Math.ceil(lo / paso) * paso; v <= hi; v += paso) ticks.push(v);
    return ticks;
  }

  function nivelCorto(p) { return p.nivel.replace("Carreras ", "").toLowerCase(); }

  // Contenido del tooltip: nombre, tipo, cifras y timbres. Texto en tinta, nunca en color de serie.
  function llenarTooltip(caja, p, lineas) {
    caja.replaceChildren();
    caja.appendChild(el("div", "tooltip__titulo", p.nombre));
    caja.appendChild(el("div", "tooltip__sub", p.tipo + " · " + nivelCorto(p)));
    var cifras = el("div", "tooltip__cifras");
    lineas.forEach(function (l) { cifras.appendChild(el("div", null, l)); });
    caja.appendChild(cifras);
    var t = el("div", "timbres");
    TIMBRES.forEach(function (def) { if (def.aplica(p)) t.appendChild(timbre(def)); });
    if (t.childNodes.length) caja.appendChild(t);
  }

  // Ubica el tooltip junto al punto (x, y) relativo a la figura, sin salirse por los costados.
  function ubicarTooltip(caja, figura, x, y) {
    caja.hidden = false;
    var ancho = caja.offsetWidth, alto = caja.offsetHeight, max = figura.clientWidth;
    var izq = Math.min(Math.max(x - ancho / 2, 0), max - ancho);
    var arriba = y - alto - 12;
    if (arriba < 0) arriba = y + 16;
    caja.style.left = izq + "px";
    caja.style.top = arriba + "px";
  }

  function alCambiarAncho(nodo, fn) {
    var ultimo = 0;
    if (!window.ResizeObserver) { window.addEventListener("resize", fn); return; }
    new ResizeObserver(function (entradas) {
      var ancho = Math.round(entradas[0].contentRect.width);
      if (ancho !== ultimo) { ultimo = ancho; fn(); }
    }).observe(nodo);
  }

  // ------------------------------------------------------------- peine (portada)
  // Las carreras comparables de UN nivel (N3: técnicas y profesionales no comparten escala ni
  // mediana), cada una una línea del P50 del 1er año al del 5°, ordenadas por el P50 del 1er año.
  // Violeta = marca de composición por edad; ▼ = gana menos al 5° año. Los conteos del texto y
  // las carreras marcadas vienen de analytics.hallazgo_edad: aquí no se cuenta nada.
  var peine = { lista: [], activo: -1, nivel: "Carreras Técnicas" };

  function elegirNivelPeine(nivel) {
    peine.nivel = nivel;
    peine.activo = -1;
    document.getElementById("peine-nivel-tec").setAttribute("aria-pressed", String(nivel === "Carreras Técnicas"));
    document.getElementById("peine-nivel-pro").setAttribute("aria-pressed", String(nivel === "Carreras Profesionales"));
    pintarPeine();
  }

  function prepararPeine() {
    document.getElementById("peine-nivel-tec").addEventListener("click", function () { elegirNivelPeine("Carreras Técnicas"); });
    document.getElementById("peine-nivel-pro").addEventListener("click", function () { elegirNivelPeine("Carreras Profesionales"); });
  }

  function pintarPeine() {
    var lienzo = document.getElementById("peine-lienzo");
    var figura = document.getElementById("peine");
    var caja = document.getElementById("peine-tooltip");
    var nv = nivelEdad(peine.nivel);
    var nombreNivel = peine.nivel.replace("Carreras ", "").toLowerCase();
    var lista = comparables.filter(function (p) { return p.nivel === peine.nivel; }).sort(function (a, b) {
      return a.percentiles.anio_1.p50 - b.percentiles.anio_1.p50 || colador.compare(a.nombre, b.nombre);
    });
    peine.lista = lista;
    var bajan = Object.create(null);
    nv.claves_bajan.forEach(function (k) { bajan[k] = true; });

    var texto = "Las " + fmtEntero.format(nv.n_comparables) + " carreras " + nombreNivel +
      " comparables. Cada línea va del sueldo típico de quienes se titularon hace un año al de quienes se titularon hace cinco. " +
      (nv.n_negativos ? "De ellas, " + fmtEntero.format(nv.n_negativos) + " ganan menos al 5° año que al 1° (▼). " : "Todas suben. ");
    if (nv.n_marca_edad) {
      texto += "En violeta, " + (nv.n_marca_edad === 1 ? "la que tiene" : "las " + fmtEntero.format(nv.n_marca_edad) + " que tienen") +
        " titulados recientes mucho mayores que los de hace cinco años: ahí la comparación mezcla edades.";
    }
    document.getElementById("peine-bajada").textContent = texto;
    document.getElementById("peine-titulo").textContent = "Sueldo típico (P50) al 1er y al 5° año de las " +
      fmtEntero.format(nv.n_comparables) + " carreras " + nombreNivel + " comparables · pesos, ingresos " + aniosIngreso("percentiles_anio_1");

    var W = lienzo.clientWidth || 800;
    var angosto = W < 600;
    var H = angosto ? 260 : 340;
    var m = { izq: angosto ? 70 : 80, der: 8, arriba: 22, abajo: 18 };   // abajo: fila de ▼
    var n = lista.length;
    var paso = (W - m.izq - m.der) / n;
    var valores = [];
    lista.forEach(function (p) { valores.push(p.percentiles.anio_1.p50, p.percentiles.anio_5.p50); });
    var lo = Math.min.apply(null, valores) * 0.94, hi = Math.max.apply(null, valores) * 1.03;
    function x(i) { return m.izq + paso * (i + 0.5); }
    function y(v) { return m.arriba + (1 - (v - lo) / (hi - lo)) * (H - m.arriba - m.abajo); }

    var svg = svgEl("svg", { viewBox: "0 0 " + W + " " + H, height: H, role: "img",
      "aria-label": n + " carreras " + nombreNivel + " comparables. En " + nv.n_negativos +
        " el sueldo típico del 5° año es menor que el del 1er año." });
    marcasPesos(lo, hi).forEach(function (v) {
      svgEl("line", { x1: m.izq, x2: W - m.der, y1: y(v), y2: y(v) }, "g-grilla", svg);
      var t = svgEl("text", { x: m.izq - 6, y: y(v) + 4, "text-anchor": "end" }, "g-eje-texto", svg);
      t.textContent = pesos(v);
    });
    var resalte = svgEl("rect", { x: 0, y: m.arriba - 6, width: Math.max(paso, 4), height: H - m.arriba - m.abajo + 12, rx: 2 }, "g-resalte", svg);
    resalte.style.display = "none";

    var r = Math.max(1.2, Math.min(3, paso * 0.42));
    var grosor = Math.max(1, Math.min(2, paso * 0.4));
    lista.forEach(function (p, i) {
      var y1 = y(p.percentiles.anio_1.p50), y5 = y(p.percentiles.anio_5.p50);
      var edad = p.marcas.composicion_edad;
      svgEl("line", { x1: x(i), x2: x(i), y1: y1, y2: y5, "stroke-width": edad ? grosor + 1 : grosor },
            "g-linea" + (edad ? " g-linea--timbre" : ""), svg);
      svgEl("circle", { cx: x(i), cy: y1, r: r }, "g-anio1", svg);
      svgEl("circle", { cx: x(i), cy: y5, r: r }, "g-anio5", svg);
      if (bajan[p.clave + "|" + p.tipo]) {
        var tri = svgEl("text", { x: x(i), y: H - 3, "text-anchor": "middle" }, "g-marca-baja", svg);
        tri.textContent = "▼";
      }
    });

    lienzo.replaceChildren(svg);

    // Rótulos directos solo en los dos extremos (elegidos por regla, no a mano). Van en el
    // espacio vacío de arriba a la izquierda (sueldos bajos, sin líneas altas) con una guía
    // hasta su carrera: así no se montan sobre las líneas ni quedan ambiguos.
    var masSube = maximoPor(lista, function (p) { return p.percentiles.p50_pct_1_5; });
    var masBaja = maximoPor(lista, function (p) { return -p.percentiles.p50_pct_1_5; });
    [masSube, masBaja].forEach(function (p, k) {
      var i = lista.indexOf(p);
      var yRot = m.arriba + 10 + k * 18;
      var t = svgEl("text", { x: m.izq + 8, y: yRot }, "g-rotulo", svg);
      var nombre = p.nombre + (p.tipo !== "Universidad" ? " (" + p.tipo + ")" : "");
      var cifra = " " + pctSigno(p.percentiles.p50_pct_1_5);
      t.textContent = nombre + cifra;
      // En pantallas angostas el nombre se acorta con "…" (la cifra queda entera): si no, se cortaba
      // en el borde del gráfico (medido a 320 px con Técnico en Computación e Informática).
      var cabe = W - m.der - (m.izq + 8) - 12;
      while (t.getComputedTextLength() > cabe && nombre.length > 8) {
        nombre = nombre.slice(0, -2);
        t.textContent = nombre.replace(/[\s,(]+$/, "") + "…" + cifra;
      }
      var fin = m.izq + 8 + t.getComputedTextLength() + 6;
      var yDot = k === 0 ? Math.min(y(p.percentiles.anio_1.p50), y(p.percentiles.anio_5.p50))
                         : Math.max(y(p.percentiles.anio_1.p50), y(p.percentiles.anio_5.p50));
      svgEl("polyline", { points: fin + "," + (yRot - 4) + " " + (x(i) - 4) + "," + (yRot - 4) + " " + x(i) + "," + (yDot + (k === 0 ? -4 : 4)),
                          fill: "none" }, "g-guia", svg);
    });
    pintarPeineBajan(lista, bajan, nombreNivel);
    lienzo.tabIndex = 0;
    lienzo.setAttribute("aria-describedby", "peine-ayuda");

    function mostrar(i) {
      peine.activo = i;
      if (i < 0) { caja.hidden = true; resalte.style.display = "none"; return; }
      var p = lista[i];
      resalte.style.display = "";
      resalte.setAttribute("x", x(i) - Math.max(paso, 4) / 2);
      llenarTooltip(caja, p, [
        "1er año " + pesos(p.percentiles.anio_1.p50),
        "5° año  " + pesos(p.percentiles.anio_5.p50) + "  (" + pctSigno(p.percentiles.p50_pct_1_5) + ")"
      ]);
      var escala = lienzo.clientWidth / W;
      ubicarTooltip(caja, figura, x(i) * escala,
                    Math.min(y(p.percentiles.anio_1.p50), y(p.percentiles.anio_5.p50)) * escala);
    }
    function desdePuntero(e) {
      var caja2 = svg.getBoundingClientRect();
      var xx = (e.clientX - caja2.left) * (W / caja2.width);
      var i = Math.floor((xx - m.izq) / paso);
      mostrar(i >= 0 && i < n ? i : -1);
    }
    svg.addEventListener("pointermove", desdePuntero);
    svg.addEventListener("pointerdown", desdePuntero);   // un toque en pantallas táctiles
    svg.addEventListener("pointerleave", function () { mostrar(-1); });
    svg.addEventListener("click", function () { if (peine.activo >= 0) abrirFicha(lista[peine.activo], true); });
    svg.style.cursor = "pointer";
    lienzo.onkeydown = function (e) {
      if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
        e.preventDefault();
        var i = peine.activo < 0 ? 0 : peine.activo + (e.key === "ArrowRight" ? 1 : -1);
        mostrar(Math.max(0, Math.min(n - 1, i)));
      } else if (e.key === "Enter" && peine.activo >= 0) { abrirFicha(lista[peine.activo], true);
      } else if (e.key === "Escape") { mostrar(-1); }
    };
    lienzo.onblur = function () { mostrar(-1); };
  }

  // Las que bajan, por nombre y con su ficha: en el gráfico serían rótulos encimados (a 390 px hay
  // menos de 4 px por carrera), y como lista se leen también sin ver el gráfico.
  function pintarPeineBajan(lista, bajan, nombreNivel) {
    var caja = document.getElementById("peine-bajan");
    caja.replaceChildren();
    var marcadas = lista.filter(function (p) { return bajan[p.clave + "|" + p.tipo]; })
      .sort(function (a, b) { return a.percentiles.p50_pct_1_5 - b.percentiles.p50_pct_1_5; });
    if (!marcadas.length) return;
    caja.appendChild(el("p", "peine-bajan__titulo", "▼ Las " + fmtEntero.format(marcadas.length) + " " +
      nombreNivel + " que ganan menos al 5° año:"));
    var ul = el("ul", "peine-bajan__lista");
    marcadas.forEach(function (p) {
      var li = el("li");
      var b = el("button", "enlace-ficha", p.nombre + (p.tipo !== "Universidad" ? " (" + p.tipo + ")" : ""));
      b.type = "button";
      b.addEventListener("click", function () { abrirFicha(p, true); });
      li.appendChild(b);
      li.appendChild(el("span", "peine-bajan__cifra", pctSigno(p.percentiles.p50_pct_1_5)));
      ul.appendChild(li);
    });
    caja.appendChild(ul);
  }

  // ------------------------------------------------------------- cuadrantes (W4)
  // Ejes RELATIVOS a la referencia de cada carrera (decisión aprobada): x = P50 1er año ÷
  // mediana de su grupo (escala log: ×0,5 y ×2 equidistan de "típico"); y = crecimiento −
  // crecimiento típico del grupo, en pp o en pesos. Así el lado en que cae cada punto es
  // exactamente su clasificación en `posicion` (verificado: 0 discrepancias en 210).
  // Un nivel a la vez (como el peine): técnicas y profesionales tienen grupos, escalas y conteos
  // propios. Por defecto Profesionales, donde está el hallazgo (b).
  var cuad = { modo: "pct", nivel: "Carreras Profesionales", todos: [], puntos: [], activo: -1 };

  function refQ50(p, metrica) {
    for (var i = 0; i < datos.referencias.length; i++) {
      var r = datos.referencias[i];
      if (r.grupo === p.marcas.grupo_referencia && r.metrica === metrica) return r.q50;
    }
    throw new Error("Sin referencia para " + p.clave + " / " + metrica);
  }

  // "celda|Área|Tipo|Nivel" → "Área · Tipo profesionales"; "segmento|Tipo|Nivel" → "Tipo profesionales (todas las áreas)".
  function nombreGrupo(p) {
    var g = p.marcas.grupo_referencia.split("|");
    var tn = g[g.length - 2] + " " + g[g.length - 1].replace("Carreras ", "").toLowerCase();
    return g[0] === "celda" ? g[1] + " · " + tn : tn + " (todas las áreas)";
  }

  function esEjemploB(p) {
    var e = datos.hallazgos.pct_pesos.ejemplo;
    return !!e && p.clave === e.clave && p.tipo === e.tipo;
  }

  function prepararCuadrantes() {
    cuad.todos = comparables.map(function (p) {
      var r1 = refQ50(p, "p50_anio_1"), rp = refQ50(p, "p50_pct_1_5"), rd = refQ50(p, "p50_delta_1_5");
      return { p: p, razon: p.percentiles.anio_1.p50 / r1, ref1: r1, refPct: rp, refDelta: rd,
               yPct: p.percentiles.p50_pct_1_5 - rp, yPesos: p.percentiles.p50_delta_1_5 - rd };
    }).sort(function (a, b) { return a.razon - b.razon || colador.compare(a.p.nombre, b.p.nombre); });

    var botones = { pct: document.getElementById("c-modo-pct"), pesos: document.getElementById("c-modo-pesos") };
    Object.keys(botones).forEach(function (modo) {
      botones[modo].addEventListener("click", function () {
        cuad.modo = modo;
        botones.pct.setAttribute("aria-pressed", String(modo === "pct"));
        botones.pesos.setAttribute("aria-pressed", String(modo === "pesos"));
        pintarCuadrantes(true);
      });
    });
    [["c-nivel-tec", "Carreras Técnicas"], ["c-nivel-pro", "Carreras Profesionales"]].forEach(function (b) {
      document.getElementById(b[0]).addEventListener("click", function () { elegirNivelCuadrantes(b[1]); });
    });
    elegirNivelCuadrantes(cuad.nivel, true);
    alCambiarAncho(document.getElementById("cuadrantes-lienzo"), function () { pintarCuadrantes(false); });
  }

  function elegirNivelCuadrantes(nivel, sinPintar) {
    cuad.nivel = nivel;
    cuad.activo = -1;
    cuad.puntos = cuad.todos.filter(function (q) { return q.p.nivel === nivel; });
    document.getElementById("c-nivel-tec").setAttribute("aria-pressed", String(nivel === "Carreras Técnicas"));
    document.getElementById("c-nivel-pro").setAttribute("aria-pressed", String(nivel === "Carreras Profesionales"));
    pintarTablaCuadrantes();
    if (!sinPintar) pintarCuadrantes(false);
  }

  // Conteo de una zona (esquina o franja) desde el SQL (analytics.cuadrante_conteo).
  function conteoZona(medida, zona) {
    var c = datos.hallazgos.pct_pesos.conteos.filter(function (x) {
      return x.nivel === cuad.nivel && x.medida === medida && x.zona === zona;
    })[0];
    if (!c) throw new Error("Sin conteo para " + cuad.nivel + " / " + medida + " / " + zona);
    return c.n;
  }

  function pintarTablaCuadrantes() {
    var cuerpo = document.querySelector("#cuadrantes-tabla tbody");
    cuerpo.replaceChildren();
    var cambian = cuad.puntos.filter(function (q) { return q.p.posicion.cambia_cuadrante; });
    if (!cambian.length) {
      var tr0 = el("tr"), td0 = el("td", null, "Ninguna carrera " +
        cuad.nivel.replace("Carreras ", "").toLowerCase().replace(/s$/, "") + " cambia de cuadrante.");
      td0.colSpan = 5;
      tr0.appendChild(td0);
      cuerpo.appendChild(tr0);
      return;
    }
    cambian.sort(function (a, b) { return colador.compare(a.p.nombre, b.p.nombre); })
      .forEach(function (q) {
        var tr = el("tr");
        [["Carrera", q.p.nombre + " (" + q.p.tipo + ")", "td--titulo"],
         ["Crecimiento %", pctSigno(q.p.percentiles.p50_pct_1_5), "num"],
         ["Crecimiento $", pesosSigno(q.p.percentiles.p50_delta_1_5), "num"],
         ["Cuadrante en %", q.p.posicion.cuadrante_pct, ""],
         ["Cuadrante en pesos", q.p.posicion.cuadrante_pesos, ""]].forEach(function (c) {
          var td = el("td", c[2] || null, c[1]);
          td.setAttribute("data-rotulo", c[0]);
          tr.appendChild(td);
        });
        cuerpo.appendChild(tr);
      });
  }

  // Bajo el gráfico: qué muestra el conmutador % / pesos en el nivel elegido. Cifras del SQL.
  function pintarNotaCuadrantes() {
    var b = datos.hallazgos.pct_pesos;
    var tec = cuad.nivel === "Carreras Técnicas";
    var n = tec ? b.n_cambian_tec : b.n_cambian_pro;
    var nombre = tec ? "técnica" : "profesional", plural = tec ? "técnicas" : "profesionales";
    var margen = "±" + fmtEntero.format(b.margen_pp) + " pp o ±" + pesos(b.margen_pesos);
    document.getElementById("cuadrantes-nota").textContent = n
      ? fmtEntero.format(n) + (n === 1 ? " carrera " + nombre + " cambia" : " carreras " + plural + " cambian") +
        " de cuadrante (en color): crecen más que su grupo en porcentaje pero menos en pesos, o al revés. " +
        "No cuentan las que quedan en la franja del típico (a " + margen + "): ahí la diferencia es un empate."
      : "Ninguna carrera " + nombre + " cambia de cuadrante: en este nivel, medir en porcentaje o en pesos da la " +
        "misma lectura. Los conteos de las esquinas varían solo porque algunas carreras entran o salen de la " +
        "franja del típico (a " + margen + ").";
    document.getElementById("c-leyenda-cambia").hidden = !n;
  }

  function pintarCuadrantes(animar) {
    var lienzo = document.getElementById("cuadrantes-lienzo");
    var figura = document.getElementById("cuadrantes");
    var caja = document.getElementById("cuadrantes-tooltip");
    var puntos = cuad.puntos, modo = cuad.modo;
    var yDe = function (q) { return modo === "pct" ? q.yPct : q.yPesos; };
    var clave = modo === "pct" ? "cuadrante_pct" : "cuadrante_pesos";

    var W = lienzo.clientWidth || 800;
    var angosto = W < 600;
    var H = angosto ? Math.round(W * 1.05) : 460;
    var m = { izq: angosto ? 80 : 90, der: 10, arriba: 10, abajo: 40 };
    var razones = puntos.map(function (q) { return q.razon; });
    var lx0 = Math.log2(Math.min.apply(null, razones) * 0.92), lx1 = Math.log2(Math.max.apply(null, razones) * 1.06);
    var ys = puntos.map(yDe);
    var y0 = Math.min.apply(null, ys), y1 = Math.max.apply(null, ys);
    var holgura = (y1 - y0) * 0.04; y0 -= holgura; y1 += holgura;
    // Franjas reservadas arriba y abajo para los rótulos de los cuadrantes: los datos se dibujan
    // en el área interior, así ningún punto queda debajo de un rótulo.
    var franja = angosto ? 48 : 36;
    function x(r) { return m.izq + (Math.log2(r) - lx0) / (lx1 - lx0) * (W - m.izq - m.der); }
    function y(v) { return m.arriba + franja + (1 - (v - y0) / (y1 - y0)) * (H - m.arriba - m.abajo - 2 * franja); }
    // Rango de valores que cubre toda el área (incluidas las franjas), para la grilla.
    var yTope = y0 + (y1 - y0) * (H - m.arriba - m.abajo - franja) / (H - m.arriba - m.abajo - 2 * franja);
    var yPiso = y1 - (y1 - y0) * (H - m.arriba - m.abajo - franja) / (H - m.arriba - m.abajo - 2 * franja);

    // Reutiliza los puntos existentes para que el cambio de % a pesos se anime (transición CSS
    // del transform); solo se redibuja todo al cambiar el ancho.
    var svg = lienzo.querySelector("svg");
    var reusar = animar && svg && Number(svg.getAttribute("data-ancho")) === W && svg.getAttribute("data-nivel") === cuad.nivel;
    if (!reusar) {
      svg = svgEl("svg", { viewBox: "0 0 " + W + " " + H, height: H, role: "img", "data-ancho": W, "data-nivel": cuad.nivel });
      svgEl("g", {}, "c-fondo", svg);
      var capa = svgEl("g", {}, "c-puntos", svg);
      puntos.forEach(function (q, i) {
        var g = svgEl("g", { "data-i": i }, "c-punto" + (q.p.posicion.cambia_cuadrante ? " c-punto--cambia" : "") +
          (q.p.marcas.cohorte_atipica || q.p.marcas.composicion_edad ? " c-punto--aviso" : ""), capa);
        // Radio 4 (8 px, mínimo de la guía dataviz) para todos: "cambia" se distingue por el color.
        svgEl("circle", { cx: 0, cy: 0, r: 4 }, null, g);
        g.style.transition = "none";   // sin animación al aparecer
        // N3: el ejemplo del hallazgo (b) lleva anillo y nombre DENTRO de su grupo, así el rótulo
        // viaja con el punto al animar % ↔ $ y se ve que cambia de cuadrante.
        if (esEjemploB(q.p)) {
          g.classList.add("c-punto--ejemplo");
          svgEl("circle", { cx: 0, cy: 0, r: angosto ? 8 : 10 }, "c-anillo-ejemplo", g);
          var rot = svgEl("text", { y: angosto ? -12 : -15 }, "c-rotulo-ejemplo", g);
          rot.textContent = q.p.nombre;
        }
      });
      var ejemplo = capa.querySelector(".c-punto--ejemplo");
      if (ejemplo) capa.appendChild(ejemplo);   // al frente de los demás puntos
      svgEl("g", {}, "c-frente", svg);
      lienzo.replaceChildren(svg);
    }
    var nombreNivel = cuad.nivel.replace("Carreras ", "").toLowerCase();
    svg.setAttribute("aria-label", puntos.length + " carreras " + nombreNivel + " comparables según sueldo de entrada y crecimiento " +
      (modo === "pct" ? "en porcentaje" : "en pesos") + ", relativos a la carrera típica de su grupo.");

    // Fondo: grilla, ejes y rótulos (se redibuja en cada modo: la escala Y cambia).
    var fondo = svg.querySelector(".c-fondo");
    fondo.replaceChildren();
    [0.5, 0.75, 1, 1.5, 2, 2.5].forEach(function (r) {
      if (Math.log2(r) < lx0 || Math.log2(r) > lx1) return;
      svgEl("line", { x1: x(r), x2: x(r), y1: m.arriba, y2: H - m.abajo }, r === 1 ? "c-centro" : "g-grilla", fondo);
      var t = svgEl("text", { x: x(r), y: H - m.abajo + 16, "text-anchor": "middle" }, "g-eje-texto", fondo);
      // Hasta 2 decimales: con 1 decimal, ×0,75 se leía ×0,8.
      t.textContent = r === 1 ? "típico" : "×" + new Intl.NumberFormat("es-CL", { maximumFractionDigits: 2 }).format(r);
    });
    // Franja "progreso típico": ±margen de la mediana del grupo (0 en el eje relativo).
    var mg = modo === "pct" ? datos.hallazgos.pct_pesos.margen_pp : datos.hallazgos.pct_pesos.margen_pesos;
    svgEl("rect", { x: m.izq, width: W - m.der - m.izq, y: y(mg), height: Math.max(1, y(-mg) - y(mg)) }, "c-franja", fondo);
    var nTipico = conteoZona(modo, "progreso típico");
    document.getElementById("c-leyenda-franja").textContent = "Cerca del típico (±" +
      (modo === "pct" ? fmtEntero.format(mg) + " pp" : pesos(mg)) + "): " + fmtEntero.format(nTipico) +
      (nTipico === 1 ? " carrera" : " carreras") + ", fuera de las esquinas";
    document.getElementById("c-titulo").textContent = "Sueldo de entrada y crecimiento " +
      (modo === "pct" ? "en %" : "en pesos") + " frente a la típica de su grupo · " + fmtEntero.format(puntos.length) + " carreras " +
      puntos[0].p.nivel.replace("Carreras ", "").toLowerCase();
    document.getElementById("c-titulo-y").textContent = "↑ Crecimiento del sueldo típico (1er → 5° año) frente al típico de su grupo, " +
      (modo === "pct" ? "en puntos porcentuales (pp)" : "en pesos");
    pintarNotaCuadrantes();
    // En celular se centra en todo el ancho: el margen de los ejes en pesos enteros lo correría fuera.
    var tituloX = svgEl("text", { x: angosto ? W / 2 : (m.izq + W - m.der) / 2, y: H - 4, "text-anchor": "middle" }, "c-titulo-eje", fondo);
    tituloX.textContent = "Sueldo al 1er año respecto del típico de su grupo";
    var pasoY = modo === "pct" ? 20 : ((y1 - y0) > 1.2e6 ? 500000 : 250000);
    for (var v = Math.ceil(yPiso / pasoY) * pasoY; v <= yTope; v += pasoY) {
      svgEl("line", { x1: m.izq, x2: W - m.der, y1: y(v), y2: y(v) }, v === 0 ? "c-centro" : "g-grilla", fondo);
      var ty = svgEl("text", { x: m.izq - 6, y: y(v) + 4, "text-anchor": "end" }, "g-eje-texto", fondo);
      ty.textContent = v === 0 ? "típico" : modo === "pct" ? (v > 0 ? "+" : "−") + fmtEntero.format(Math.abs(v)) + " pp"
                                                         : (v > 0 ? "+" : "−") + pesos(Math.abs(v));
    }

    // Esquinas: nombre del cuadrante y conteo (desde `posicion`, la clasificación del análisis).
    var frente = svg.querySelector(".c-frente");
    frente.replaceChildren();
    // En pantallas angostas el rótulo va en dos líneas (si no, los de izquierda y derecha chocan).
    var abajoY = H - m.abajo - (angosto ? 36 : 22);
    [["entrada baja · progresa más", m.izq + 6, m.arriba + 12, "start"],
     ["entrada alta · progresa más", W - m.der - 6, m.arriba + 12, "end"],
     ["entrada baja · progresa menos", m.izq + 6, abajoY, "start"],
     ["entrada alta · progresa menos", W - m.der - 6, abajoY, "end"]].forEach(function (e) {
      var lineas = angosto ? e[0].split(" · ") : [e[0]];
      lineas.forEach(function (l, k) {
        var t = svgEl("text", { x: e[1], y: e[2] + k * 12, "text-anchor": e[3] }, "c-cuadrante", frente);
        t.textContent = l;
      });
      var c = svgEl("text", { x: e[1], y: e[2] + (lineas.length - 1) * 12 + 16, "text-anchor": e[3] }, "c-conteo", frente);
      var nz = conteoZona(modo, e[0]);   // del SQL; la franja no pertenece a ninguna esquina
      c.textContent = fmtEntero.format(nz) + (nz === 1 ? " carrera" : " carreras");
    });

    // Puntos: el transform lleva la posición; la transición CSS anima el cambio de modo.
    svg.querySelectorAll(".c-punto").forEach(function (g) {
      var q = puntos[Number(g.getAttribute("data-i"))];
      if (reusar) g.style.transition = "";
      g.style.transform = "translate(" + x(q.razon) + "px," + y(yDe(q)) + "px)";
      var rot = g.querySelector(".c-rotulo-ejemplo");
      if (rot) {
        // N5: se prueban posiciones alrededor del punto y, si la nube es densa (pantallas angostas),
        // más lejos con una guía; gana la que tapa menos puntos, sin salirse del área de datos ni
        // pisar las franjas de los rótulos de cuadrante. Usa las posiciones reales de este ancho y
        // este modo: una posición fija tapaba la nube densa a 390 px en pesos.
        var xp = x(q.razon), yp = y(yDe(q)), largo = rot.getComputedTextLength();
        var otros = puntos.filter(function (o) { return o !== q; })
          .map(function (o) { return [x(o.razon), y(yDe(o))]; });
        var techo = m.arriba + franja, piso = H - m.abajo - franja;
        var mejor = null;
        [-15, 22, -45, 50, -80, 85, -120, 125].forEach(function (dy) {
          [[0, "middle"], [14, "start"], [-14, "end"]].forEach(function (h) {
            var dx = Math.abs(dy) > 22 ? 0 : h[0];   // lejos, la guía es vertical
            var x0 = h[1] === "middle" ? xp - largo / 2 : h[1] === "start" ? xp + dx : xp + dx - largo;
            if (Math.abs(dy) > 22 && h[1] !== "middle") x0 = h[1] === "start" ? xp - 6 : xp + 6 - largo;
            var x1 = x0 + largo, y0 = yp + dy - 10, y1 = yp + dy + 3;
            if (x0 < m.izq || x1 > W - m.der || y0 < techo || y1 > piso) return;
            var tapados = otros.filter(function (o) { return o[0] > x0 - 4 && o[0] < x1 + 4 && o[1] > y0 - 4 && o[1] < y1 + 4; }).length;
            var costo = tapados * 10 + Math.abs(dy) / 10;   // a igual tapado, lo más cerca
            if (!mejor || costo < mejor.costo) mejor = { costo: costo, tapados: tapados, x: x0 - xp, dy: dy };
          });
        });
        if (!mejor) mejor = { tapados: -1, x: 14, dy: 4 };
        rot.setAttribute("x", mejor.x);
        rot.setAttribute("y", mejor.dy);
        rot.setAttribute("text-anchor", "start");
        rot.setAttribute("data-tapados", mejor.tapados);
        var guia = g.querySelector(".c-guia-ejemplo");
        if (Math.abs(mejor.dy) > 22) {
          if (!guia) { guia = svgEl("line", { x1: 0, y1: 0 }, "c-guia-ejemplo", g); g.insertBefore(guia, g.firstChild); }
          guia.setAttribute("x2", 0);
          guia.setAttribute("y2", mejor.dy > 0 ? mejor.dy - 11 : mejor.dy + 4);
          guia.setAttribute("y1", mejor.dy > 0 ? 10 : -10);
        } else if (guia) { guia.remove(); }
      }
    });

    function mostrar(i) {
      cuad.activo = i;
      svg.querySelectorAll(".c-punto--activo").forEach(function (g) { g.classList.remove("c-punto--activo"); });
      if (i < 0) { caja.hidden = true; return; }
      var q = puntos[i], p = q.p;
      var g = svg.querySelector('.c-punto[data-i="' + i + '"]');
      g.classList.add("c-punto--activo");
      g.parentNode.appendChild(g);   // al frente
      var lineas = [
        "Se compara con: " + nombreGrupo(p),
        "1er año " + pesos(p.percentiles.anio_1.p50) + (Math.abs(q.razon - 1) < 1e-9
          ? " (es la carrera típica de su grupo)"
          : " (×" + fmtUno.format(Math.round(q.razon * 100) / 100).replace(/,0$/, "") + " del típico, " + pesos(q.ref1) + ")"),
        "Crece " + pctSigno(p.percentiles.p50_pct_1_5) + " / " + pesosSigno(p.percentiles.p50_delta_1_5),
        "Típico del grupo: " + pctSigno(q.refPct) + " / " + pesosSigno(q.refDelta),
        p.posicion[clave]
      ];
      if (p.posicion.cambia_cuadrante) lineas.push("En " + (modo === "pct" ? "pesos" : "%") + ": " + p.posicion[modo === "pct" ? "cuadrante_pesos" : "cuadrante_pct"]);
      llenarTooltip(caja, p, lineas);
      var escala = lienzo.clientWidth / W;
      ubicarTooltip(caja, figura, x(q.razon) * escala, y(yDe(q)) * escala);
    }
    svg.onpointermove = svg.onpointerdown = function (e) {
      var rc = svg.getBoundingClientRect(), k = W / rc.width;
      var px = (e.clientX - rc.left) * k, py = (e.clientY - rc.top) * k;
      var mejor = -1, dmin = 22 * 22;   // zona sensible: 22 px alrededor del punto
      puntos.forEach(function (q, i) {
        var dx = x(q.razon) - px, dy = y(yDe(q)) - py, d = dx * dx + dy * dy;
        if (d < dmin) { dmin = d; mejor = i; }
      });
      mostrar(mejor);
    };
    svg.onpointerleave = function () { mostrar(-1); };
    svg.onclick = function () { if (cuad.activo >= 0) abrirFicha(puntos[cuad.activo].p, true); };
    svg.style.cursor = "pointer";
    lienzo.tabIndex = 0;
    lienzo.setAttribute("aria-describedby", "cuadrantes-ayuda");
    lienzo.onkeydown = function (e) {
      if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
        e.preventDefault();
        var i = cuad.activo < 0 ? 0 : cuad.activo + (e.key === "ArrowRight" ? 1 : -1);
        mostrar(Math.max(0, Math.min(puntos.length - 1, i)));
      } else if (e.key === "Enter" && cuad.activo >= 0) { abrirFicha(puntos[cuad.activo].p, true);
      } else if (e.key === "Escape") { mostrar(-1); }
    };
    lienzo.onblur = function () { mostrar(-1); };
    if (cuad.activo >= 0 && reusar) mostrar(cuad.activo);
  }

  // ------------------------------------------------------------- ficha por carrera (W5)
  // Una "liquidación" por carrera. Cada bloque aparece solo si hay datos para él: la ficha
  // tiene que funcionar en las 252 (también sin dispersión, sin posición o no comparables).
  function claveDe(p) { return p.clave + "|" + p.tipo; }
  // Sin prototipo: "#carrera=constructor" no debe encontrar una propiedad heredada de Object.
  var parPorClave = Object.create(null);
  pares.forEach(function (p) { parPorClave[claveDe(p)] = p; });
  var programasPor = {};
  datos.programas.forEach(function (g) {
    var k = g.clave + "|" + g.tipo;
    (programasPor[k] = programasPor[k] || []).push(g);
  });
  // Mismo formato que la lista del buscador («Carrera — Tipo»): el campo muestra lo que se eligió.
  function etiquetaPar(p) { return p.nombre + " — " + p.tipo; }

  function liq(dl, rotulo, valor, esTexto) {
    var fila = el("div", "liq__linea");
    fila.appendChild(el("dt", null, rotulo));
    fila.appendChild(el("span", "liq__guia"));
    fila.appendChild(el("dd", esTexto ? "liq__texto" : null, valor));
    dl.appendChild(fila);
  }

  // Barra 100 % mujeres / hombres de los titulados 2024. Los % vienen del SQL (enteros que suman
  // 100, analytics.sexo_titulados); los rótulos van arriba y en tinta, así se leen aunque un
  // segmento sea angosto o 0 % (22 carreras tienen un sexo bajo el 5 %) y el color no es la
  // única pista.
  function barraSexo(tt, etiqueta) {
    // Un entero 0 o 100 con personas del otro lado mentiría (Párvulos CFT: 2.495 mujeres y 6
    // hombres redondea a 100 / 0): se dice «menos de 1 %» o «más de 99 %».
    var tm = textoSexo(tt.pct_mujeres, tt.mujeres, tt.hombres), th = textoSexo(tt.pct_hombres, tt.hombres, tt.mujeres);
    var caja = el("div", "sexo");
    var rot = el("div", "sexo__rotulos");
    rot.appendChild(el("span", "sexo__rotulo sexo__rotulo--mujeres", "Mujeres " + tm));
    rot.appendChild(el("span", "sexo__rotulo sexo__rotulo--hombres", "Hombres " + th));
    caja.appendChild(rot);
    var barra = el("div", "sexo__barra");
    barra.setAttribute("role", "img");
    barra.setAttribute("aria-label", (etiqueta || "Titulados 2024") + " por sexo: " + tm + " mujeres (" +
      fmtEntero.format(tt.mujeres) + ") y " + th + " hombres (" + fmtEntero.format(tt.hombres) + ")");
    // Solo se omite el segmento sin personas; uno con personas pero bajo el 1 % queda como astilla
    // de 2 px (min-width), para que la barra no diga "nadie".
    [["mujeres", tt.pct_mujeres, tt.mujeres], ["hombres", tt.pct_hombres, tt.hombres]].forEach(function (s) {
      if (s[2] > 0) {
        var seg = el("span", "sexo__seg sexo__seg--" + s[0]);
        seg.style.flexGrow = String(Math.max(s[1], 0.01));
        barra.appendChild(seg);
      }
    });
    caja.appendChild(barra);
    if (tt.sin_dato) caja.appendChild(el("p", "ficha__nota", fmtEntero.format(tt.sin_dato) +
      (tt.sin_dato === 1 ? " titulado sin sexo informado (fuera de los %)." : " titulados sin sexo informado (fuera de los %).")));
    return caja;
  }

  // Tramo en pesos enteros, como el resto de la página: "$1.300.000–$1.400.000", "sobre $3.500.000".
  function tramoTexto(t) {
    if (!t) return "—";
    if (t[1] == null) return "sobre " + pesos(t[0]);
    return pesos(t[0]) + "–" + pesos(t[1]);
  }

  var CUARTO = ["el cuarto más bajo", "el segundo cuarto", "el tercer cuarto", "el cuarto más alto"];

  function avisosDe(p) {
    var frases = [];
    TIMBRES.forEach(function (def) { if (def.aplica(p)) frases.push(def.explica()); });
    if (p.marcas.cohorte_atipica && p.estabilidad) {
      frases.push("En esta carrera: la empleabilidad al primer año de la cohorte " + p.estabilidad.cohorte + " fue " +
        pct(p.estabilidad.empleabilidad) + ", frente a " + pct(p.estabilidad.media_previas) + " en promedio en las cohortes anteriores.");
    }
    if (p.marcas.composicion_edad) {
      frases.push("En esta carrera: quienes tienen 30 años o más pasan de " + pct(p.contexto.mayores30_cohorte_p5[1]) +
        " (titulados hace cinco años) a " + pct(p.contexto.mayores30_cohorte_p1[1]) + " (titulados recientes), en la cota alta del rango.");
    }
    return frases;
  }

  // Referencia del grupo de la carrera (03_referencia.sql): la misma para las cinco métricas, así
  // toda la ficha compara contra un solo grupo. null en las no representativas.
  function referenciaDe(p, metrica) {
    if (!p.marcas.grupo_referencia) return null;
    for (var i = 0; i < datos.referencias.length; i++) {
      var r = datos.referencias[i];
      if (r.grupo === p.marcas.grupo_referencia && r.metrica === metrica) return r;
    }
    throw new Error("Sin referencia para " + p.clave + " / " + metrica);
  }

  // Miembros del grupo de la carrera (datos.grupos, desde analytics.miembro_referencia).
  function miembrosDe(p) {
    var lista = datos.grupos[p.marcas.grupo_referencia];
    if (!lista) throw new Error("Sin miembros para " + p.marcas.grupo_referencia);
    return lista.map(function (m) {
      var q = parPorClave[m.clave + "|" + m.tipo];
      if (!q) throw new Error("Miembro desconocido: " + m.clave + " / " + m.tipo);
      return q;
    });
  }

  // Ventana de cohortes de un indicador ("2021–2023" o "2023"), desde modelo.cohorte.
  function ventana(indicador, corrimiento) {
    var c = datos.cohortes.filter(function (x) { return x.indicador === indicador; })[0];
    if (!c) throw new Error("Sin cohorte para " + indicador);
    var d = c.cohortes[0] + (corrimiento || 0), h = c.cohortes[1] + (corrimiento || 0);
    return d === h ? String(d) : d + "–" + h;
  }

  // Años de ingreso con que se mide un indicador ("2024" o "2022–2024").
  function aniosIngreso(indicador) {
    var c = datos.cohortes.filter(function (x) { return x.indicador === indicador; })[0];
    if (!c || c.anios_ingreso[0] == null) throw new Error("Sin años de ingreso para " + indicador);
    return c.anios_ingreso[0] === c.anios_ingreso[1] ? String(c.anios_ingreso[0]) : c.anios_ingreso[0] + "–" + c.anios_ingreso[1];
  }

  // Veredicto: traduce a palabras la posición que calcula el SQL (entrada > mediana del grupo;
  // progreso más / típico / menos con ±margen). No agrega cifras.
  var COMO = { "más": "más", "típico": "lo mismo", "menos": "menos" };
  function veredicto(p) {
    if (!p.posicion) {
      var n = p.conteos.n_inst_oferta, min = parametro("min_inst_oferta");
      return n < min
        ? "Sin comparación con otras carreras: la imparte" + (n === 1 ? " 1 institución" : "n " + fmtEntero.format(n) + " instituciones") +
          " y se necesitan " + min + " para que sus cifras representen a la carrera y no a una institución."
        : "Sin comparación con otras carreras: MiFuturo no publica todas sus cifras de ingreso.";
    }
    var d = p.dif_grupo.p50_anio_1;
    var texto = d === 0 ? "Es la carrera típica de su grupo al entrar"
      : "Entra ganando " + (p.posicion.entrada_alta ? "más" : "menos") + " que la carrera típica de su grupo";
    var a = p.posicion.progreso_pct, b = p.posicion.progreso_pesos;
    if (a === b) return texto + " y su sueldo crece " + COMO[a] + " que el de su grupo.";
    return texto + ". Su sueldo crece " + COMO[a] + " que el de su grupo en %, pero " + COMO[b] + " en pesos.";
  }

  // Bloque con título de acción (la conclusión, con su cifra del SQL) y subtítulo con la métrica
  // y el contexto (criterio McCandless / Google, aprobado por el usuario).
  function bloque(cont, titulo, subtitulo) {
    var b = el("section", "ficha__bloque");
    b.appendChild(el("h5", "ficha__accion", titulo));
    if (subtitulo) b.appendChild(el("p", "ficha__subtitulo", subtitulo));
    cont.appendChild(b);
    return b;
  }
  function subbloque(cont, titulo, subtitulo) {
    cont.appendChild(el("h6", "ficha__subaccion", titulo));
    if (subtitulo) cont.appendChild(el("p", "ficha__subtitulo", subtitulo));
  }

  // "Esta carrera" se dibuja siempre como rombo ocre (--acento) y el contexto en gris: forma y
  // color a la vez, así se distingue también sin color.
  function rombo(svg, cx, cy, r, clase) {
    return svgEl("path", { d: "M" + cx + " " + (cy - r) + " L" + (cx + r) + " " + cy + " L" + cx + " " + (cy + r) + " L" + (cx - r) + " " + cy + " Z" },
      clase || "g-acento g-anillo", svg);
  }

  // Texto centrado en x pero que no se sale del lienzo: cerca de un borde se ancla al borde.
  function textoEn(svg, x, y, texto, clase, W, margen) {
    var m = margen || 44;
    var anc = x < m ? "start" : x > W - m ? "end" : "middle";
    var t = svgEl("text", { x: anc === "start" ? Math.max(x - 6, 0) : anc === "end" ? Math.min(x + 6, W) : x, y: y, "text-anchor": anc }, clase, svg);
    t.textContent = texto;
    return t;
  }

  // Franja de su grupo para una cifra: cada carrera del grupo es un punto gris (al pasar, su
  // nombre; con clic, su ficha), la típica una línea con su rótulo y esta carrera un rombo ocre.
  function franjaGrupo(cont, p, miembros, cfg, tip, figura) {
    var fila = el("div", "grupo__fila");
    var rot = el("div", "grupo__rotulo");
    rot.appendChild(el("span", "grupo__metrica", cfg.rotulo));
    rot.appendChild(el("span", "grupo__valor", cfg.formato(cfg.valor(p))));
    fila.appendChild(rot);
    var lienzo = el("div", "grupo__svg");
    fila.appendChild(lienzo);
    cont.appendChild(fila);
    var W = lienzo.clientWidth || 480, H = 64;
    var vals = miembros.map(cfg.valor).concat([cfg.ref.q50]);
    var lo = Math.min.apply(null, vals), hi = Math.max.apply(null, vals), pad = (hi - lo) * 0.04 || 1;
    lo -= pad; hi += pad;
    function x(v) { return 10 + (v - lo) / (hi - lo) * (W - 20); }
    var propio = cfg.valor(p), esTipica = propio === cfg.ref.q50;
    var svg = svgEl("svg", { viewBox: "0 0 " + W + " " + H, role: "img",
      "aria-label": cfg.rotulo + ": " + cfg.formato(propio) + "; típica de su grupo " + cfg.formato(cfg.ref.q50) +
        "; el grupo va de " + cfg.formato(Math.min.apply(null, miembros.map(cfg.valor))) + " a " +
        cfg.formato(Math.max.apply(null, miembros.map(cfg.valor))) + "." });
    svgEl("line", { x1: 10, x2: W - 10, y1: 34, y2: 34 }, "g-grilla", svg);
    svgEl("line", { x1: x(cfg.ref.q50), x2: x(cfg.ref.q50), y1: 16, y2: 46 }, "g-tipica", svg);
    textoEn(svg, x(cfg.ref.q50), 11, (esTipica ? "es la típica: " : "típica ") + cfg.formato(cfg.ref.q50), "g-rotulo-suave", W);
    var otros = miembros.filter(function (m) { return m !== p; });
    otros.forEach(function (m, i) {
      // Desfase vertical leve en grupos grandes (hasta 91 carreras) para que no se tapen.
      var cy = 34 + (otros.length > 25 ? ((i % 3) - 1) * 5 : 0);
      var g = svgEl("g", {}, "g-vecina", svg);
      svgEl("circle", { cx: x(cfg.valor(m)), cy: cy, r: 4 }, "g-contexto g-anillo", g);
      svgEl("circle", { cx: x(cfg.valor(m)), cy: cy, r: 10 }, "g-blanco", g);   // blanco de toque más grande que la marca
      g.addEventListener("pointerenter", function () {
        tip.replaceChildren(el("div", "tooltip__titulo", m.nombre),
                            el("div", "tooltip__cifras", cfg.rotulo + ": " + cfg.formato(cfg.valor(m))),
                            el("div", "tooltip__sub", "Clic para ver su ficha"));
        var rf = figura.getBoundingClientRect(), rl = lienzo.getBoundingClientRect();
        ubicarTooltip(tip, figura, rl.left - rf.left + x(cfg.valor(m)) * rl.width / W, rl.top - rf.top + cy);
      });
      g.addEventListener("pointerleave", function () { tip.hidden = true; });
      g.addEventListener("click", function () { tip.hidden = true; abrirFicha(m, "vecina"); });
    });
    rombo(svg, x(propio), 34, 7);
    textoEn(svg, x(propio), 60, "esta carrera", "g-rotulo", W);
    lienzo.appendChild(svg);
  }

  function filaTabla(tb, celdas, actual, alClic) {
    var tr = el("tr", actual ? "fila--actual" : null);
    celdas.forEach(function (c, i) {
      var td = el("td", c[2] || null);
      td.setAttribute("data-rotulo", c[0]);
      if (i === 0 && !actual && alClic) {
        var b = el("button", "enlace-ficha", c[1]);
        b.type = "button";
        b.addEventListener("click", alClic);
        td.appendChild(b);
      } else {
        if (i === 0 && actual) td.appendChild(el("span", "marca-actual", "◆ "));
        td.appendChild(document.createTextNode(c[1]));
      }
      tr.appendChild(td);
    });
    tb.appendChild(tr);
    return tr;
  }

  function tablaCon(cont, caption, columnas) {
    // Compacta y no en "tarjetas": en celular cada fila era una caja de 5 a 7 líneas y las dos
    // tablas sumaban 5.400 px a 390 px de ancho.
    var tabla = el("table", "tabla tabla--compacta tabla--ficha");
    tabla.appendChild(el("caption", "solo-lectores", caption));
    var thead = el("thead"), trh = el("tr");
    columnas.forEach(function (c, i) { var th = el("th", i ? "num" : null, c); th.scope = "col"; trh.appendChild(th); });
    thead.appendChild(trh); tabla.appendChild(thead);
    var tb = el("tbody"); tabla.appendChild(tb);
    var envol = el("div", "tabla-desplazable"); envol.appendChild(tabla);
    cont.appendChild(envol);
    return tb;
  }

  // «Otras carreras de su área»: por INTERÉS, no por estadística. Usa el área del conocimiento de
  // MiFuturo (MINEDUC), la que ve quien busca carreras, del mismo nivel y en todos los tipos de
  // institución (con columna Tipo). Antes eran las ±4 más cercanas en sueldo dentro del grupo de
  // referencia, que en áreas chicas es todo el tipo × nivel: junto a Informática salía Pedagogía en
  // Filosofía y Religión (pedido del usuario, 18-11-26). Las franjas y «la típica» siguen usando el
  // grupo estadístico. Solo comparables (1–2 instituciones quedan fuera, como en todo ranking);
  // la carrera abierta siempre está, marcada.
  var AREA_COMPLETA = 25;       // hasta este tamaño se muestra el área entera
  var AREA_CERCA = 5;           // en áreas grandes, ±5 alrededor de la carrera (10 vecinas)

  function carrerasDeArea(cont, p) {
    var area = p.area.mineduc, nivel = nivelCorto(p);
    var orden = pares.filter(function (q) {
      return q.nivel === p.nivel && q.area.mineduc === area && (q.marcas.representativo || q === p);
    }).sort(function (a, b) {
      return b.percentiles.anio_1.p50 - a.percentiles.anio_1.p50 || colador.compare(a.nombre, b.nombre) || colador.compare(a.tipo, b.tipo);
    });
    // Las no comparables del área (1–2 instituciones) no entran al orden por sueldo (regla de todo
    // ranking), pero sí se nombran aparte: son parte del interés del lector (p. ej. Ingeniería en
    // Telecomunicaciones IP, con 2 instituciones, junto a Informática).
    var sinComparar = pares.filter(function (q) {
      return q.nivel === p.nivel && q.area.mineduc === area && !q.marcas.representativo && q !== p;
    }).sort(function (a, b) { return colador.compare(a.nombre, b.nombre) || colador.compare(a.tipo, b.tipo); });
    function pintarSinComparar() {
      if (!sinComparar.length) return;
      var nota = el("p", "ficha__nota", "Con menos de " + parametro("min_inst_oferta") + " instituciones, sin comparar: ");
      sinComparar.forEach(function (q, i) {
        var b = el("button", "enlace-ficha", q.nombre + " (" + q.tipo + ")");
        b.type = "button";
        b.addEventListener("click", function () { abrirFicha(q, "vecina"); });
        nota.appendChild(b);
        nota.appendChild(document.createTextNode(i < sinComparar.length - 1 ? ", " : "."));
      });
      cont.appendChild(nota);
    }
    var otras = orden.length - 1;
    if (!otras) {
      subbloque(cont, "Otras carreras de su área", "Es la única carrera " + nivel.replace(/es$/, "").replace(/s$/, "") +
        " del área «" + area + "» de MiFuturo con datos comparables.");
      pintarSinComparar();
      return;
    }
    var grande = orden.length > AREA_COMPLETA, todas = !grande;
    subbloque(cont, "Otras carreras de su área", (grande
      ? "Las " + AREA_CERCA * 2 + " más cercanas en sueldo de entrada, de las " + fmtEntero.format(orden.length)
      : "Las " + fmtEntero.format(orden.length)) +
      " carreras " + nivel + " del área «" + area + "» de MiFuturo, en todos los tipos de institución, de mayor a menor sueldo de entrada. Haz clic en una para ver su ficha.");
    var cols = ["Carrera", "Tipo", "Sueldo 1er año", "5° año", "Empleab."];
    var tb = tablaCon(cont, "Carreras " + nivel + " del área " + area + ", de mayor a menor sueldo típico al 1er año", cols);
    var i0 = orden.indexOf(p);
    function pintar() {
      tb.replaceChildren();
      var desde = Math.max(0, Math.min(i0 - AREA_CERCA, orden.length - AREA_CERCA * 2 - 1));
      var lista = todas ? orden : orden.slice(desde, desde + AREA_CERCA * 2 + 1);
      lista.forEach(function (v) {
        filaTabla(tb, [[cols[0], v.nombre, "td--titulo"], [cols[1], v.tipo, ""], [cols[2], pesos(v.percentiles.anio_1.p50), "num"],
                       [cols[3], pesos(v.percentiles.anio_5.p50), "num"], [cols[4], pct(v.empleabilidad_nacional[0]), "num"]],
                  v === p, function () { abrirFicha(v, "vecina"); });
      });
    }
    pintar();
    if (grande) {
      var bA = el("button", "boton boton--sutil tabla__mas");
      bA.type = "button";
      var rotular = function () {
        bA.textContent = todas ? "Mostrar solo las " + AREA_CERCA * 2 + " más cercanas" : "Ver las " + fmtEntero.format(orden.length) + " ↓";
        bA.setAttribute("aria-expanded", String(todas));
      };
      bA.addEventListener("click", function () { todas = !todas; pintar(); rotular(); });
      rotular();
      cont.appendChild(bA);
    }
    pintarSinComparar();
  }

  // Un solo gráfico de sueldo por año. Puntos sin línea: cada año es otra cohorte de titulados
  // (una línea sugeriría a las mismas personas en el tiempo). Esta carrera en ocre (rombo = P50,
  // barra = mitad central) en los años 1 y 5; el promedio de cada año en gris hueco; la típica
  // del grupo en trazo discontinuo. Rótulos directos a la derecha, sin leyenda aparte.
  function graficoSueldo(cont, p) {
    cont.appendChild(tituloGrafico("Sueldo típico y promedio por año desde la titulación · pesos"));
    var caja = el("div", "ficha__grafico ficha__grafico--sueldo");
    cont.appendChild(caja);
    var W = caja.clientWidth || 600, H = 200, arriba = 12, abajo = 26;
    var angosto = W < 520;
    var mIzq = 70, mDer = angosto ? 92 : 200, dentro = angosto ? 16 : 26;
    var a1 = p.percentiles.anio_1, a5 = p.percentiles.anio_5, v = p.media.anio;
    var ref1 = referenciaDe(p, "p50_anio_1"), ref5 = referenciaDe(p, "p50_anio_5");
    // Eje acotado a la mitad central, el promedio y la típica: con P10–P90 iba de $0 a $5.000
    // mil y aplastaba todo (P10–P90 queda en «Ver todas las cifras»).
    var todos = [a1.p25, a5.p25, a1.p75, a5.p75].concat(v);
    if (ref1) todos.push(ref1.q50, ref5.q50);
    var lo = Math.min.apply(null, todos), hi = Math.max.apply(null, todos);
    var paso = [100000, 250000, 500000, 1000000].filter(function (s) { return (Math.ceil(hi / s) - Math.floor(lo / s)) <= 4; })[0] || 1000000;
    lo = Math.floor(lo / paso) * paso; hi = Math.ceil(hi / paso) * paso;
    function x(i) { return mIzq + dentro + i * (W - mIzq - dentro - mDer) / 4; }
    function y(val) { return arriba + (1 - (val - lo) / (hi - lo)) * (H - arriba - abajo); }
    var svg = svgEl("svg", { viewBox: "0 0 " + W + " " + H, role: "img",
      "aria-label": "Sueldo típico (P50) al 1er año " + pesos(a1.p50) + " y al 5° año " + pesos(a5.p50) +
        (ref1 ? "; típica de su grupo " + pesos(ref1.q50) + " y " + pesos(ref5.q50) : "") +
        ". Promedio del año 1 al 5: " + v.map(pesos).join(", ") + "." });
    for (var g = lo; g <= hi; g += paso) {
      svgEl("line", { x1: mIzq - 4, x2: x(4) + 10, y1: y(g), y2: y(g) }, "g-grilla", svg);
      var tg = svgEl("text", { x: mIzq - 10, y: y(g) + 4, "text-anchor": "end" }, "g-eje-texto", svg);
      tg.textContent = pesos(g);
    }
    var anomalos = {};
    datos.hitos.forEach(function (h) { anomalos[h.anio] = h.incluye_caida || h.incluye_rebote; });
    v.forEach(function (val, i) {
      var et = svgEl("text", { x: x(i), y: H - 6, "text-anchor": "middle" }, "g-eje-texto", svg);
      et.textContent = (i + 1) + "°" + (anomalos[i + 1] ? "*" : "");
    });
    [[0, a1, ref1], [4, a5, ref5]].forEach(function (a) {
      var cx = x(a[0]), q = a[1];
      if (a[2]) svgEl("line", { x1: cx - 16, x2: cx + 16, y1: y(a[2].q50), y2: y(a[2].q50) }, "f-ref", svg);
      svgEl("line", { x1: cx, x2: cx, y1: y(q.p25), y2: y(q.p75) }, "f-caja", svg);
    });
    v.forEach(function (val, i) { svgEl("circle", { cx: x(i), cy: y(val), r: 4 }, "f-prom", svg); });
    rombo(svg, x(0), y(a1.p50), 7);
    rombo(svg, x(4), y(a5.p50), 7);

    // Rótulos directos junto al 5° año, separados al menos 17 px (la caja de un texto de 12 px mide ~15) (se empujan hacia abajo y,
    // si no caben, hacia arriba); una guía corta une el rótulo con su marca si se movió.
    var rotulos = [
      { y: y(a5.p50), t: angosto ? "Sueldo típico" : "Sueldo típico " + pesos(a5.p50), c: "g-rotulo" },
      { y: y(v[4]), t: angosto ? "Promedio" : "Promedio " + pesos(v[4]), c: "g-rotulo-suave" }
    ];
    if (ref5) rotulos.push({ y: y(ref5.q50), t: angosto ? "Típica grupo" : "Típica del grupo " + pesos(ref5.q50), c: "g-rotulo-suave" });
    rotulos.forEach(function (r) { r.marca = r.y; });
    rotulos.sort(function (a, b) { return a.y - b.y; });
    for (var k = 1; k < rotulos.length; k++) rotulos[k].y = Math.max(rotulos[k].y, rotulos[k - 1].y + 17);
    var exceso = rotulos[rotulos.length - 1].y - (H - abajo);
    if (exceso > 0) rotulos.forEach(function (r) { r.y -= exceso; });
    rotulos.forEach(function (r) {
      var x0 = x(4) + 12;
      if (Math.abs(r.y - r.marca) > 3) svgEl("line", { x1: x(4) + 9, x2: x0 + 2, y1: r.marca, y2: r.y }, "g-guia", svg);
      var t = svgEl("text", { x: x0 + 4, y: r.y + 4 }, r.c, svg);
      t.textContent = r.t;
    });
    caja.appendChild(svg);

    // Hover por año; la misma información está en «Ver todas las cifras» para teclado y lectores.
    var tip = el("div", "tooltip");
    tip.hidden = true;
    caja.appendChild(tip);
    var col = (W - mIzq - dentro - mDer) / 4;
    v.forEach(function (val, i) {
      var zona = svgEl("rect", { x: x(i) - col / 2, y: 0, width: col, height: H - abajo }, "f-zona", svg);
      zona.addEventListener("pointerenter", function () {
        var lineas = ["Promedio " + pesos(val)];
        var q = i === 0 ? a1 : i === 4 ? a5 : null, r = i === 0 ? ref1 : i === 4 ? ref5 : null;
        if (q) {
          lineas.unshift("Sueldo típico (P50) " + pesos(q.p50));
          lineas.push("Mitad central " + pesos(q.p25) + "–" + pesos(q.p75));
          if (r) lineas.push("Típica del grupo " + pesos(r.q50));
        }
        tip.replaceChildren(el("div", "tooltip__titulo", (i === 0 ? "1er año" : (i + 1) + "° año") + " desde la titulación"));
        var cifras = el("div", "tooltip__cifras");
        lineas.forEach(function (l) { cifras.appendChild(el("div", null, l)); });
        tip.appendChild(cifras);
        var escala = caja.clientWidth / W;
        ubicarTooltip(tip, caja, x(i) * escala, y(q ? q.p75 : val) * escala);
      });
      zona.addEventListener("pointerleave", function () { tip.hidden = true; });
    });
  }

  // Nombres de institución en formato título: la fuente los trae en mayúsculas ("UNIVERSIDAD DE
  // CHILE") y así no calzan con el resto de la ficha. Siglas, "de/del/y" y los artículos de
  // sustantivos comunes ("de la Región") se tratan aparte; la fuente no trae tildes y no se inventan.
  var SIGLAS = { CFT: 1, IP: 1, CEDUC: 1, UCN: 1, ENAC: 1, INACAP: 1, ICCE: 1, PUCV: 1, AIEP: 1, DUOC: 1, UC: 1,
                 EATRI: 1, ESUCOMEX: 1, IACC: 1, IPG: 1, IPLACEX: 1, UNIACC: 1, SEK: 1, CENCO: 1 };
  var MINUSCULA = { DE: 1, DEL: 1, Y: 1, E: 1 };
  var COMUNES = { REGION: 1, SANTISIMA: 1, EDUCACION: 1 };   // "de la Región", no "de La Región"
  function nombreInst(s) {
    var pal = s.split(" ");
    return pal.map(function (w, i) {
      if (SIGLAS[w.replace(/[^A-ZÑ]/g, "")] && /^[A-ZÑ]+$/.test(w)) return w;
      if (i > 0 && MINUSCULA[w]) return w.toLowerCase();
      if (i > 0 && /^(LA|LAS|LOS)$/.test(w) && pal[i - 1] === "DE" && COMUNES[pal[i + 1]]) return w.toLowerCase();
      // Mayúscula tras guion o apóstrofo: Bio-Bio, Lota-Arauco, O'Higgins.
      return w.toLowerCase().replace(/(^|[-'’.])([a-zñ])/g, function (_, a, b) { return a + b.toUpperCase(); });
    }).join(" ");
  }

  function difPuntos(v) {
    return v == null ? "—" : (v > 0 ? "+" : v < 0 ? "−" : "") + fmtUno.format(Math.abs(v)) + (Math.abs(v) === 1 ? " punto" : " puntos");
  }
  var TRAMO_VS = { sobre: "más alto que la típica", igual: "igual a la típica", bajo: "más bajo que la típica" };

  // Empleabilidad al 1er año por institución. Cada punto es una institución; la altura NO es un
  // eje: los puntos solo se apilan cuando se tocarían (enjambre), para que ninguno tape a otro sin
  // sugerir grupos (antes un zigzag por posición en la lista parecía tres niveles). Se puede
  // recorrer con el puntero o el teclado, y cada punto se enlaza con su fila de la tabla.
  // Devuelve { marcar(g) } para que la tabla resalte el punto de la fila bajo el puntero.
  function graficoInstituciones(cont, progs, d, nacional, alElegir) {
    cont.appendChild(tituloGrafico("Empleabilidad al 1er año en cada una de las " + fmtEntero.format(progs.length) +
      (progs.length === 1 ? " institución" : " instituciones") + " con datos"));
    cont.appendChild(el("p", "ficha__subtitulo", "Cada punto es una institución; se apilan cuando tienen valores parecidos. " +
      "Pasa el puntero o usa las flechas ← → para ver su nombre; con clic o Enter, se marca en la tabla."));
    var caja = el("div", "ficha__grafico ficha__grafico--franja ficha__grafico--inst");
    cont.appendChild(caja);
    var tip = el("div", "tooltip");
    tip.hidden = true;
    var anuncio = el("p", "solo-lectores");
    anuncio.setAttribute("aria-live", "polite");
    var W = caja.clientWidth || 600, m = 16, r = 4.5, PASO = 2 * r + 1.5;
    var vals = progs.map(function (g) { return g.emp1; }).concat([nacional]);
    var lo = Math.floor((Math.min.apply(null, vals) - 1) / 10) * 10, hi = Math.ceil((Math.max.apply(null, vals) + 1) / 10) * 10;
    function x(v) { return m + (v - lo) / (hi - lo) * (W - 2 * m); }

    // Enjambre: de izquierda a derecha, cada punto en el nivel libre más cercano al centro (0, +1, −1, +2…).
    var orden = progs.slice().sort(function (a, b) { return a.emp1 - b.emp1 || colador.compare(a.institucion, b.institucion); });
    var puestos = [], maxNivel = 0;
    orden.forEach(function (g) {
      var px = x(g.emp1);
      for (var k = 0; ; k++) {
        var nivel = k % 2 ? (k + 1) / 2 : -k / 2;
        var choca = puestos.some(function (q) { return q.nivel === nivel && Math.abs(q.x - px) < PASO; });
        if (!choca) { puestos.push({ g: g, x: px, nivel: nivel }); maxNivel = Math.max(maxNivel, Math.abs(nivel)); break; }
      }
    });
    var arriba = 22, centro = arriba + maxNivel * PASO + r, abajoBanda = centro + maxNivel * PASO + r;
    var H = abajoBanda + 44;
    var svg = svgEl("svg", { viewBox: "0 0 " + W + " " + H, role: "img",
      "aria-label": "Empleabilidad al primer año de " + progs.length + " instituciones: de " + pct(d.min) + " a " + pct(d.max) +
        "; institución típica " + pct(d.mediana) + "; cifra nacional " + pct(nacional) + ". La tabla siguiente tiene cada institución." });
    var salto = (hi - lo) / 10 > 6 && W < 420 ? 2 : 1;
    for (var t = lo, k = 0; t <= hi; t += 10, k++) {
      svgEl("line", { x1: x(t), x2: x(t), y1: arriba - 4, y2: abajoBanda + 2 }, "g-grilla", svg);
      if (k % salto === 0) {
        var tx = svgEl("text", { x: x(t), y: H - 2, "text-anchor": "middle" }, "g-eje-texto", svg);
        tx.textContent = fmtEntero.format(t) + " %";
      }
    }
    svgEl("line", { x1: x(d.mediana), x2: x(d.mediana), y1: arriba - 6, y2: abajoBanda + 2 }, "g-tipica", svg);
    textoEn(svg, x(d.mediana), 11, "institución típica " + pct(d.mediana), "g-rotulo-suave", W);
    var marcas = puestos.map(function (q) {
      q.y = centro - q.nivel * PASO;
      q.nodo = svgEl("circle", { cx: q.x, cy: q.y, r: r }, "g-contexto g-anillo g-inst", svg);
      return q;
    });
    svgEl("path", { d: "M" + x(nacional) + " " + (abajoBanda + 4) + " l-5 8 h10 z" }, "franja__nacional", svg);
    textoEn(svg, x(nacional), abajoBanda + 25, "▲ nacional " + pct(nacional), "g-rotulo-suave", W);
    caja.appendChild(svg);
    caja.appendChild(tip);
    caja.appendChild(anuncio);

    var activo = -1;
    function mostrar(i, anunciar) {
      if (activo >= 0) marcas[activo].nodo.classList.remove("g-inst--activa");
      activo = i;
      if (i < 0) { tip.hidden = true; return; }
      var q = marcas[i], g = q.g;
      q.nodo.classList.add("g-inst--activa");
      svg.appendChild(q.nodo);   // al frente
      var lineas = ["Empleabilidad 1er año: " + pct(g.emp1), "Empleabilidad 2° año: " + pct(g.emp2),
                    "Dif. 1er año con la institución típica: " + difPuntos(g.desvio_emp1),
                    "Continuidad de estudios: " + pct(g.continuidad)];
      if (g.tramo) lineas.push("Rango de ingreso al 4° año: " + tramoTexto(g.tramo));
      tip.replaceChildren(el("div", "tooltip__titulo", nombreInst(g.institucion)));
      var cifras = el("div", "tooltip__cifras");
      lineas.forEach(function (l) { cifras.appendChild(el("div", null, l)); });
      tip.appendChild(cifras);
      tip.appendChild(el("div", "tooltip__sub", "Clic o Enter: marcarla en la tabla"));
      var esc = svg.getBoundingClientRect().width / W;
      ubicarTooltip(tip, caja, q.x * esc, q.y * esc);
      if (anunciar) anuncio.textContent = nombreInst(g.institucion) + ": " + lineas.join("; ") + ".";
    }
    // El punto más cercano al puntero (hasta 14 px): con el enjambre, los blancos fijos se taparían.
    function desdePuntero(e) {
      var rc = svg.getBoundingClientRect(), esc = W / rc.width;
      var px = (e.clientX - rc.left) * esc, py = (e.clientY - rc.top) * esc, mejor = -1, dist = 14 * 14;
      marcas.forEach(function (q, i) { var dd = (q.x - px) * (q.x - px) + (q.y - py) * (q.y - py); if (dd < dist) { dist = dd; mejor = i; } });
      mostrar(mejor, false);
    }
    svg.addEventListener("pointermove", desdePuntero);
    svg.addEventListener("pointerdown", desdePuntero);
    svg.addEventListener("pointerleave", function () { mostrar(-1); });
    svg.addEventListener("click", function () { if (activo >= 0) alElegir(marcas[activo].g); });
    svg.style.cursor = "pointer";
    caja.tabIndex = 0;
    caja.setAttribute("aria-label", "Gráfico de instituciones: recórrelo con las flechas izquierda y derecha; Enter la marca en la tabla.");
    caja.addEventListener("keydown", function (e) {
      if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
        e.preventDefault();
        var i = activo < 0 ? (e.key === "ArrowRight" ? 0 : marcas.length - 1) : activo + (e.key === "ArrowRight" ? 1 : -1);
        mostrar(Math.max(0, Math.min(marcas.length - 1, i)), true);
      } else if (e.key === "Enter" && activo >= 0) { alElegir(marcas[activo].g);
      } else if (e.key === "Escape") { mostrar(-1); }
    });
    caja.addEventListener("blur", function () { mostrar(-1); });
    return {
      marcar: function (g) {
        if (activo >= 0) marcas[activo].nodo.classList.remove("g-inst--activa");
        activo = -1; tip.hidden = true;
        marcas.forEach(function (q, i) { if (q.g === g) { activo = i; q.nodo.classList.add("g-inst--activa"); svg.appendChild(q.nodo); } });
      }
    };
  }

  // «menos de 1 %» / «más de 99 %» cuando el entero redondea a 0 o 100 pero hay personas.
  function textoSexo(pctv, n, nOtro) {
    if (pctv === 0 && n > 0) return "menos de 1 %";
    if (pctv === 100 && nOtro > 0) return "más de 99 %";
    return fmtEntero.format(pctv) + " %";
  }

  // La ficha en pantalla: el paso inicial del historial la guarda aunque la dirección no tenga
  // "#carrera" (ficha de ejemplo), para que «Atrás» desde una vecina pueda volver a ella.
  var fichaActual = null;

  function pintarFicha(p) {
    fichaActual = p;
    var art = document.getElementById("ficha-contenido");
    art.replaceChildren();
    var corr = p.marcas.es_derecho ? 1 : 0;
    // Un solo tooltip para las franjas del grupo (el artículo es el marco de posición).
    var tipGrupo = el("div", "tooltip");
    tipGrupo.hidden = true;

    // Encabezado y veredicto
    art.appendChild(el("h4", "ficha__nombre", p.nombre)).id = "ficha-nombre";
    art.appendChild(el("p", "ficha__sub", p.tipo + " · " + nivelCorto(p) + " · " + p.area.cine13 +
      " (" + fmtEntero.format(p.area.pct_dominante) + " % de sus titulados)"));
    var t = el("div", "timbres");
    TIMBRES.forEach(function (def) { if (def.aplica(p)) t.appendChild(timbre(def)); });
    if (t.childNodes.length) art.appendChild(t);
    art.appendChild(el("p", "ficha__veredicto", veredicto(p)));
    var avisos = avisosDe(p);
    if (avisos.length) {
      var caja = el("div", "ficha__avisos");
      avisos.forEach(function (f) { caja.appendChild(el("p", null, f)); });
      art.appendChild(caja);
    }

    // 1. Frente a su grupo: franjas, vecinas y la misma carrera en otro tipo.
    var b1;
    if (p.posicion) {
      var miembros = miembrosDe(p), ref1 = referenciaDe(p, "p50_anio_1"), d = p.dif_grupo.p50_anio_1;
      b1 = bloque(art,
        d === 0 ? "Entra ganando lo mismo que la típica de su grupo: es ella"
                : "Entra ganando " + pesos(Math.abs(d)) + (d > 0 ? " más" : " menos") + " que la típica de su grupo",
        "Sueldo típico (P50) y empleabilidad nacional, frente a las " + fmtEntero.format(ref1.n_pares) + " carreras de su grupo (" +
          nombreGrupo(p) + "). La típica es la mediana ponderada por titulados: las carreras con más titulados pesan más.");
      b1.classList.add("grupo");
      b1.appendChild(tipGrupo);
      [{ rotulo: "Sueldo típico al 1er año", valor: function (q) { return q.percentiles.anio_1.p50; }, formato: pesos, ref: ref1 },
       { rotulo: "Sueldo típico al 5° año", valor: function (q) { return q.percentiles.anio_5.p50; }, formato: pesos, ref: referenciaDe(p, "p50_anio_5") },
       { rotulo: "Empleabilidad nacional al 1er año", valor: function (q) { return q.empleabilidad_nacional[0]; }, formato: pct, ref: referenciaDe(p, "emp1_nacional") }]
        .forEach(function (cfg) { franjaGrupo(b1, p, miembros, cfg, tipGrupo, b1); });
    } else {
      b1 = bloque(art, "Entra ganando " + pesos(p.percentiles.anio_1.p50) + " y llega a " + pesos(p.percentiles.anio_5.p50) + " al 5° año",
        "Sueldo típico (P50) y empleabilidad nacional. Sin grupo de comparación: " + veredicto(p).replace(/^Sin comparación con otras carreras: /, ""));
      var dl0 = el("dl", "liq");
      liq(dl0, "Sueldo típico al 1er año", pesos(p.percentiles.anio_1.p50));
      liq(dl0, "Sueldo típico al 5° año", pesos(p.percentiles.anio_5.p50));
      liq(dl0, "Empleabilidad nacional al 1er año", pct(p.empleabilidad_nacional[0]));
      b1.appendChild(dl0);
    }
    carrerasDeArea(b1, p);
    var otrosTipos = pares.filter(function (q) { return q.clave === p.clave && q.nivel === p.nivel && q.tipo !== p.tipo; });
    if (otrosTipos.length) {
      subbloque(b1, "La misma carrera en otro tipo de institución",
        "Cada tipo se compara con su propio grupo. Haz clic en un tipo para ver su ficha." +
          (otrosTipos.some(function (q) { return !q.marcas.representativo; }) ? " Sin grupo de comparación: " +
            otrosTipos.filter(function (q) { return !q.marcas.representativo; }).map(function (q) { return q.tipo; }).join(", ") +
            " (menos de " + parametro("min_inst_oferta") + " instituciones)." : ""));
      var colsT = ["Tipo", "Sueldo 1er año", "5° año", "Empleab."];
      var tbT = tablaCon(b1, p.nombre + " en cada tipo de institución", colsT);
      [p].concat(otrosTipos).sort(function (a, b) { return colador.compare(a.tipo, b.tipo); }).forEach(function (q) {
        filaTabla(tbT, [[colsT[0], q.tipo, "td--titulo"], [colsT[1], pesos(q.percentiles.anio_1.p50), "num"],
                        [colsT[2], pesos(q.percentiles.anio_5.p50), "num"], [colsT[3], pct(q.empleabilidad_nacional[0]), "num"]],
                  q === p, function () { abrirFicha(q, "vecina"); });
      });
    }

    // 2. Año a año
    var pc = p.percentiles.p50_pct_1_5;
    var b2 = bloque(art, "Su sueldo típico " + (pc >= 0 ? "sube " : "baja ") + fmtUno.format(Math.abs(pc)) + " % entre el 1er y el 5° año",
      "Ingresos " + aniosIngreso("percentiles_anio_1") + " en pesos (el promedio, " + aniosIngreso("ingreso_medio_1er_anio") +
        "). Cada año es otra cohorte de titulados, no las mismas personas.");
    graficoSueldo(b2, p);
    var med1 = p.percentiles.anio_1.p50, prom1 = p.media.anio[0];
    b2.appendChild(el("p", "ficha__explica", "El sueldo típico (mediana) es lo que gana el titulado del medio: la mitad gana menos. " +
      "El promedio suma también los sueldos más altos y junta tres cohortes de titulados; por eso al 1er año son " +
      pesos(med1) + " de sueldo típico y " + pesos(prom1) + " de promedio."));
    if (datos.hitos.some(function (h) { return h.incluye_caida || h.incluye_rebote; })) {
      b2.appendChild(el("p", "ficha__nota", "* Incluye titulados de " + parametro("anio_caida_titulacion") + " o " +
        parametro("anio_rebote_titulacion") + ", años de titulación anómalos por la pandemia."));
    }
    var todas = el("details", "plegable");
    todas.appendChild(el("summary", null, "Ver todas las cifras de sueldo"));
    var dl = el("dl", "liq");
    var a1 = p.percentiles.anio_1, a5 = p.percentiles.anio_5;
    liq(dl, "Sueldo típico (P50), 1er año", pesos(a1.p50));
    liq(dl, "Sueldo típico (P50), 5° año", pesos(a5.p50));
    liq(dl, "Crecimiento del sueldo típico", pctSigno(p.percentiles.p50_pct_1_5) + " · " + pesosSigno(p.percentiles.p50_delta_1_5));
    liq(dl, "Mitad central (P25–P75), 1er año", pesos(a1.p25) + "–" + pesos(a1.p75));
    liq(dl, "Mitad central (P25–P75), 5° año", pesos(a5.p25) + "–" + pesos(a5.p75));
    liq(dl, "P10–P90, 1er año", pesos(a1.p10) + "–" + pesos(a1.p90));
    liq(dl, "P10–P90, 5° año", pesos(a5.p10) + "–" + pesos(a5.p90));
    p.media.anio.forEach(function (val, i) { liq(dl, "Promedio, " + (i === 0 ? "1er" : (i + 1) + "°") + " año", pesos(val)); });
    liq(dl, "Crecimiento del promedio", pctSigno(p.media.pct_1_5) + " · " + pesosSigno(p.media.delta_1_5));
    if (p.posicion) {
      liq(dl, "Sueldo de entrada en su grupo", CUARTO[p.posicion.cuartil_p50_anio_1 - 1], true);
      liq(dl, "Crecimiento en su grupo, en %", CUARTO[p.posicion.cuartil_p50_pct_1_5 - 1], true);
      liq(dl, "Crecimiento en su grupo, en pesos", CUARTO[p.posicion.cuartil_p50_delta_1_5 - 1], true);
    }
    todas.appendChild(dl);
    b2.appendChild(todas);

    // 3. Dónde estudiarla
    var progs = (programasPor[claveDe(p)] || []).slice().sort(function (a, b) { return b.emp1 - a.emp1 || colador.compare(a.institucion, b.institucion); });
    var d1 = p.dispersion.emp1, nI = p.conteos.n_inst_oferta;
    var b3 = bloque(art,
      d1 ? "Según la institución, la empleabilidad al 1er año va de " + pct(d1.min) + " a " + pct(d1.max)
         : progs.length ? "MiFuturo publica " + fmtEntero.format(progs.length) + (progs.length === 1 ? " institución" : " instituciones") + " de esta carrera"
                        : "MiFuturo no publica esta carrera por institución",
      // Dos conteos con nombre propio (antes la tabla decía 41 y la ficha 38 con la misma palabra).
      "La imparte" + (nI === 1 ? " 1 institución" : "n " + fmtEntero.format(nI) + " instituciones") +
        " (con titulados en ambos períodos, SIES); MiFuturo publica datos de " + fmtEntero.format(progs.length) + ".");
    // La definición junto a la cifra, no solo en el pie: sin ella, un 65 % se lee como "35 % sin trabajo".
    b3.appendChild(el("p", "ficha__explica", "Empleabilidad: " + datos.meta.rotulo_empleabilidad.replace(">=", "≥") +
      ". No es la tasa de desempleo."));
    var dl3 = el("dl", "liq");
    liq(dl3, "Empleabilidad nacional, 1er año", pct(p.empleabilidad_nacional[0]));
    liq(dl3, "Empleabilidad nacional, 2° año", pct(p.empleabilidad_nacional[1]));
    if (d1) liq(dl3, "Institución típica, 1er año (mediana de " + d1.n_inst + ")", pct(d1.mediana));
    b3.appendChild(dl3);
    if (progs.length) {
      var grafI = null;
      if (d1) {
        // Clic o Enter en un punto: su fila se marca en la tabla (que se abre si estaba oculta).
        grafI = graficoInstituciones(b3, progs, d1, p.empleabilidad_nacional[0], function (g) {
          if (progs.indexOf(g) >= MAX_INST && !todasInst) { todasInst = true; pintarInst(); rotularInst(); }
          marcarFila(g, true);
        });
        // La explicación (población más amplia que las instituciones publicadas, A4) solo vale
        // cuando la cifra nacional queda sobre la institución típica; si no, se dice sin explicar.
        var dif = d1.nacional_menos_mediana;
        b3.appendChild(el("p", "ficha__nota", Math.abs(dif) < 1
          ? "La cifra nacional y la institución típica casi coinciden (" + fmtUno.format(Math.abs(dif)) + " puntos de diferencia)."
          : dif > 0
            ? "La cifra nacional queda " + fmtUno.format(dif) + " puntos sobre la institución típica: incluye titulados que no aparecen en ninguna institución publicada."
            : "La cifra nacional queda " + fmtUno.format(-dif) + " puntos bajo la institución típica: las instituciones más grandes de esta carrera tienen menor empleabilidad."));
      } else {
        b3.appendChild(el("p", "ficha__nota", "Con menos de " + parametro("min_inst_dispersion") +
          " instituciones con el dato, no se comparan entre sí: se listan sin comparación."));
      }
      var conTramo = !!p.dispersion.tramo;
      // Seis columnas siempre visibles, las dos empleabilidades juntas y la continuidad al lado (D3):
      // quien sigue estudiando puede no tener aún un ingreso sobre el mínimo. En los datos la relación
      // es débil (r −0,16 en total; positiva en técnicas), así que la nota no afirma que la baje. Sin acreditación: no
      // entra en el análisis (pedido del usuario, 18-11-26). El ingreso es un rango porque MiFuturo
      // lo publica así por institución; no se imputa una cifra. «Ver las N» solo suma filas.
      // El sueldo promedio de cada año existe solo nacional: está en el bloque «año a año».
      b3.appendChild(el("p", "ficha__nota", "MiFuturo no publica el sueldo de cada año por institución, solo un rango del 4° año. " +
        "El promedio nacional de cada año está más arriba, en el gráfico de sueldo por año."));
      var envolI = el("div");
      b3.appendChild(envolI);
      var MAX_INST = 10, todasInst = false, filasI = [];
      var COL_DIF = d1 ? "Dif. 1er año con la institución típica (" + pct(d1.mediana) + ")" : null;
      var COL_RANGO = "Rango de ingreso al 4° año";
      function pintarInst() {
        envolI.replaceChildren();
        filasI = [];
        var cols = ["Institución", "Empleabilidad 1er año", "Empleabilidad 2° año"].concat(d1 ? [COL_DIF] : [])
          .concat(["Continuidad de estudios", COL_RANGO]);
        var tbI = tablaCon(envolI, "Instituciones que publican " + p.nombre + " en MiFuturo, de mayor a menor empleabilidad", cols);
        tbI.parentNode.classList.add("tabla--inst");
        (todasInst ? progs : progs.slice(0, MAX_INST)).forEach(function (g) {
          var celdas = [["Institución", nombreInst(g.institucion), "td--titulo"], ["Empleabilidad 1er año", pct(g.emp1), "num"],
                        ["Empleabilidad 2° año", pct(g.emp2), "num"]];
          if (d1) celdas.push([COL_DIF, difPuntos(g.desvio_emp1), "num"]);
          celdas.push(["Continuidad de estudios", pct(g.continuidad), "num"]);
          // Espacio de ancho cero tras el guion: el rango puede partirse en dos líneas en vez de ensanchar la tabla.
          celdas.push([COL_RANGO, g.tramo ? tramoTexto(g.tramo).replace("–", "–\u200b") : "sin dato", "num td--tramo"]);
          var tr = filaTabla(tbI, celdas, false, null);
          // La comparación del tramo en palabras, bajo la cifra ("(sobre)" no decía sobre qué).
          if (conTramo && g.tramo && g.tramo_vs_par) tr.querySelector(".td--tramo").appendChild(el("span", "td__nota", TRAMO_VS[g.tramo_vs_par]));
          if (grafI) {
            tr.addEventListener("pointerenter", function () { grafI.marcar(g); });
            tr.addEventListener("pointerleave", function () { grafI.marcar(null); });
          }
          filasI.push({ g: g, tr: tr });
        });
      }
      function marcarFila(g, llevar) {
        filasI.forEach(function (f) { f.tr.classList.toggle("fila--marcada", f.g === g); });
        var f = filasI.filter(function (f) { return f.g === g; })[0];
        if (f && llevar) f.tr.scrollIntoView({ behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth", block: "center" });
      }
      pintarInst();
      var bI = el("button", "boton boton--sutil tabla__mas");
      bI.type = "button";
      function rotularInst() {
        bI.textContent = todasInst ? "Mostrar solo las " + MAX_INST + " primeras"
                                   : "Ver las " + fmtEntero.format(progs.length) + " instituciones ↓";
        bI.setAttribute("aria-expanded", String(todasInst));
      }
      bI.addEventListener("click", function () { todasInst = !todasInst; pintarInst(); rotularInst(); });
      rotularInst();
      // Con 10 o menos no hay filas ocultas: el botón no haría nada.
      if (progs.length > MAX_INST) b3.appendChild(bI);
      b3.appendChild(el("p", "ficha__nota", "Rango de ingreso al 4° año: ingreso promedio que MiFuturo publica por institución como rango, no como cifra exacta" +
        (conTramo ? "; se compara con el rango de la institución típica." : ".") +
        " Continuidad de estudios: titulados que al año siguiente siguen estudiando (por ejemplo, de una carrera técnica a una profesional); ayuda a leer una empleabilidad baja."));
    }

    // 4. Quiénes la estudian
    var tt = p.titulados_2024, anioTit = ventana("titulados_y_duracion");
    var b5 = bloque(art,
      tt.total && tt.pct_mujeres != null
        ? textoSexo(tt.pct_mujeres, tt.mujeres, tt.hombres).replace(/^m/, "M") + " de sus titulados " + anioTit + " son mujeres"
        : "Quiénes la estudian y cuánto dura",
      "Titulados por sexo y edad, y duración de la carrera.");
    if (tt.total) {
      var dlT = el("dl", "liq");
      liq(dlT, "Titulados " + anioTit, fmtEntero.format(tt.total));
      b5.appendChild(dlT);
      if (tt.pct_mujeres != null) b5.appendChild(barraSexo(tt));
    }
    var dl5 = el("dl", "liq");
    var w1 = ventana("ingreso_medio_1er_anio", corr), w5 = ventana("ingreso_medio_5to_anio", corr);
    var f30 = p.contexto.fuera30_rango;
    if (f30[0] != null) liq(dl5, "Con 30 años o más al titularse (titulados " + w1 + ")", "entre " + pct(f30[0]) + " y " + pct(f30[1]));
    var oj = p.contexto.oferta_joven;
    if (p.contexto.var_oferta_joven_pct != null) liq(dl5, "Titulados menores de 30 años",
      fmtEntero.format(oj[0]) + " (" + w5 + ") → " + fmtEntero.format(oj[1]) + " (" + w1 + "), " + pctSigno(p.contexto.var_oferta_joven_pct));
    if (p.duracion.formal != null) liq(dl5, "Duración en semestres", fmtUno.format(p.duracion.formal) + " formal · " +
      (p.duracion.real != null ? fmtUno.format(p.duracion.real) : "—") + " real");
    b5.appendChild(dl5);

    // Un solo pie con los años y las definiciones de toda la ficha.
    var pie = el("div", "ficha__pie");
    pie.appendChild(el("h5", "ficha__titulo", "Años y fuentes de esta ficha"));
    var ul = el("ul");
    [
      "Sueldo típico y percentiles: ingresos " + aniosIngreso("percentiles_anio_1") + " de los titulados " +
        ventana("percentiles_anio_1", corr) + " (1er año) y " + ventana("percentiles_anio_5", corr) + " (5° año).",
      "Promedio por año: cada año junta tres cohortes de titulados (del " + ventana("ingreso_medio_1er_anio", corr) + " al 1er año al " +
        ventana("ingreso_medio_5to_anio", corr) + " al 5°), medidas con los ingresos " + aniosIngreso("ingreso_medio_1er_anio") +
        ". No son las mismas personas en el tiempo." + (p.marcas.es_derecho ? " En Derecho las cohortes van corridas un año." : ""),
      "Empleabilidad: " + datos.meta.rotulo_empleabilidad.replace(">=", "≥") + "; titulados " + ventana("empleabilidad_1er_anio_nacional") +
        " (1er año) y " + ventana("empleabilidad_2do_anio_nacional") + " (2° año).",
      "Titulados, sexo y duración: SIES y MiFuturo, " + anioTit + ". Edad: titulaciones SIES de todas las instituciones de este tipo; es un rango porque el SIES agrupa de 30 a 34 años."
    ].forEach(function (f) { ul.appendChild(el("li", null, f)); });
    pie.appendChild(ul);
    var mas = el("p", "ficha__nota");
    mas.appendChild(document.createTextNode("Definiciones, límites y método: "));
    var a = el("a", null, "Cómo leerlo");
    a.href = "#parte-lectura";
    mas.appendChild(a);
    mas.appendChild(document.createTextNode("."));
    pie.appendChild(mas);
    art.appendChild(pie);
  }

  // ------------------------------------------------------------- ficha: apertura, regreso e historial (N1)
  // Abrir una ficha con un clic agrega un paso al historial (pushState): así «Atrás» del navegador
  // y el botón «Volver» llevan al punto de donde se salió. Antes era replaceState: el salto de
  // ~30 pantallas no tenía regreso y «Atrás» sacaba al lector de la página.
  // El estado guardado es serializable ({n, clave, origen: {y, titulo}}); el elemento que tenía el
  // foco no se puede guardar en el historial, así que vive en `focoDe`, indexado por n.
  var nav = { actual: null, n: 0, conHistorial: true };
  var focoDe = {};

  function suave() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth";
  }

  // De dónde se abrió la ficha: la sección del elemento con foco (clic o teclado) o, si no hay,
  // la que está al centro de la pantalla. Desde la propia ficha no hay a dónde volver.
  // Safari no enfoca un botón al hacer clic: el último elemento tocado sirve de respaldo para
  // saber desde qué sección se abrió la ficha (si no, se adivinaría por el centro de la pantalla).
  var ultimoToque = { el: null, t: 0 };
  document.addEventListener("pointerdown", function (e) { ultimoToque = { el: e.target, t: Date.now() }; }, true);

  function capturarOrigen() {
    var foco = document.activeElement;
    if (foco === document.body) foco = null;
    if (!foco && ultimoToque.el && Date.now() - ultimoToque.t < 2000) foco = ultimoToque.el;
    var seccion = foco && foco.closest ? foco.closest("section.bloque") : null;
    if (!seccion) {
      var centro = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
      seccion = centro && centro.closest ? centro.closest("section.bloque") : null;
    }
    if (seccion && seccion.id === "ficha") return null;
    var titulo = seccion ? seccion.querySelector(".bloque__titulo") : null;
    return { origen: { y: Math.round(window.scrollY), titulo: titulo ? titulo.textContent : null }, foco: foco };
  }

  function mostrarVolver(origen) {
    var caja = document.getElementById("ficha-volver");
    caja.hidden = !origen;
    if (origen) {
      document.getElementById("ficha-volver-boton").textContent =
        origen.titulo ? "← Volver a «" + origen.titulo + "»" : "← Volver a donde estabas";
    }
  }

  function volverA(origen, n) {
    window.scrollTo({ top: origen.y, behavior: suave() });
    var foco = focoDe[n];
    if (foco && document.contains(foco)) foco.focus({ preventScroll: true });
  }

  function mostrarFicha(p) {
    pintarFicha(p);
    document.getElementById("ficha-texto").value = etiquetaPar(p);
    document.getElementById("ficha-estado").textContent = "Mostrando la ficha de " + etiquetaPar(p) + ".";
  }

  function irAFicha() {
    document.getElementById("ficha").scrollIntoView({ behavior: suave() });
    document.getElementById("ficha-contenido").focus({ preventScroll: true });
  }

  // desplazar: true = desde otra parte de la página (guarda el origen para «Volver»); "vecina" =
  // desde la propia ficha (vecinas, franjas, otro tipo): un paso de historial para que «Atrás»
  // vuelva a la carrera anterior, sin perder el origen; false = búsqueda (reemplaza el paso).
  function abrirFicha(p, desplazar) {
    mostrarFicha(p);
    var direccion = "#carrera=" + encodeURIComponent(claveDe(p));
    if (desplazar === "vecina") {
      var previo = nav.actual || { n: nav.n, origen: null };
      var paso = { n: nav.n + 1, clave: claveDe(p), origen: previo.origen, vecina: true };
      try { history.pushState(paso, "", direccion); } catch (e) { nav.conHistorial = false; }
      if (focoDe[previo.n]) focoDe[paso.n] = focoDe[previo.n];
      nav.n = paso.n;
      nav.actual = paso;
      mostrarVolver(paso.origen);
      irAFicha();
    } else if (desplazar) {
      var o = capturarOrigen();
      var estado = { n: nav.n + 1, clave: claveDe(p), origen: o ? o.origen : null };
      try { history.pushState(estado, "", direccion); } catch (e) { nav.conHistorial = false; }
      nav.n = estado.n;
      nav.actual = estado;
      if (o) focoDe[estado.n] = o.foco;
      mostrarVolver(estado.origen);
      irAFicha();
    } else {
      // Búsqueda dentro de la ficha: cambia la carrera de este mismo paso, sin perder su regreso.
      var actual = nav.actual || { n: nav.n, origen: null };
      var reemplazo = { n: actual.n, clave: claveDe(p), origen: actual.origen };
      try { history.replaceState(reemplazo, "", direccion); } catch (e) { /* sin historial */ }
      nav.actual = reemplazo;
    }
  }

  function prepararHistorial() {
    // El paso inicial también lleva estado: así un popstate con estado null solo puede ser una
    // dirección escrita a mano (#carrera=… en la barra del navegador).
    // Sin esto el navegador restaura por su cuenta la posición al ir atrás, compite con volverA
    // y deja al lector en otro punto (medido: 5.911 px en vez de 7.691).
    if ("scrollRestoration" in history) history.scrollRestoration = "manual";
    var p0 = desdeDireccion();
    nav.actual = { n: 0, clave: p0 ? claveDe(p0) : fichaActual ? claveDe(fichaActual) : null, origen: null };
    try { history.replaceState(nav.actual, "", location.href); } catch (e) { nav.conHistorial = false; }

    // Con la restauración manual, «Atrás» tras un enlace interno (barra, «Saltar al contenido»)
    // ya no volvería solo a donde se estaba: se guarda la posición en el paso actual antes del salto.
    document.addEventListener("click", function (e) {
      var a = e.target.closest ? e.target.closest('a[href^="#"]') : null;
      if (!a || !nav.actual) return;
      nav.actual = Object.assign({}, nav.actual, { y: Math.round(window.scrollY) });
      try { history.replaceState(nav.actual, "", location.href); } catch (err) { /* sin historial */ }
    }, true);

    document.getElementById("ficha-volver-boton").addEventListener("click", function () {
      var actual = nav.actual;
      if (!actual || !actual.origen) return;
      // Tras pasar por vecinas, «Atrás» volvería a la carrera anterior: «Volver» va directo al origen.
      if (actual.vecina) { volverA(actual.origen, actual.n); mostrarVolver(null); }
      else if (nav.conHistorial && actual.n > 0) history.back();   // el popstate hace el regreso
      else { volverA(actual.origen, actual.n); mostrarVolver(null); }
    });

    // Al cambiar el "#", el navegador hace su propio paso de scroll DESPUÉS del popstate y corta
    // una animación iniciada aquí (medido: la ficha se pintaba pero la página no se movía). Por eso
    // el desplazamiento se posterga una vuelta del bucle de eventos.
    function despues(fn) { window.setTimeout(fn, 0); }

    window.addEventListener("popstate", function (e) {
      var dejado = nav.actual, destino = e.state, p = desdeDireccion();
      // La ficha a pintar: la de la dirección o, si la página se abrió sin "#carrera", la que
      // guardó ese paso (la de ejemplo). Sin esto, «Atrás» desde una vecina dejaba la vecina.
      var pPintar = p || (destino && destino.clave ? parPorClave[destino.clave] : null);
      if (!destino) {   // dirección escrita a mano: se abre esa ficha, sin regreso
        nav.n += 1;
        nav.actual = { n: nav.n, clave: p ? claveDe(p) : null, origen: null };
        try { history.replaceState(nav.actual, "", location.href); } catch (err) { /* sin historial */ }
        mostrarVolver(null);
        if (p) { mostrarFicha(p); despues(irAFicha); }
        return;
      }
      nav.actual = destino;
      if (pPintar) mostrarFicha(pPintar);
      mostrarVolver(destino.origen);
      if (dejado && destino.n < dejado.n) {   // atrás
        if (dejado.vecina) despues(irAFicha);   // de una vecina a la carrera anterior: se queda en la ficha
        else if (dejado.origen) despues(function () { volverA(dejado.origen, dejado.n); });   // de una ficha a su origen
        else if (destino.y != null) despues(function () { window.scrollTo({ top: destino.y, behavior: suave() }); });
      } else if (p) {                          // adelante: de nuevo a la ficha
        despues(irAFicha);
      } else {                                 // adelante a un enlace interno: a su destino
        var objetivo = location.hash.length > 1 ? document.getElementById(location.hash.slice(1)) : null;
        if (objetivo) despues(function () { objetivo.scrollIntoView({ behavior: suave() }); });
      }
    });
  }

  // La parte en pantalla queda marcada en la barra (aria-current), para saber dónde se está.
  // Parte activa = la última cuyo inicio ya pasó una línea de lectura cerca de arriba (bajo la
  // barra, a un 25 % de la pantalla), que es donde está leyendo la persona. Antes era la parte que
  // cruzaba el centro: con el cierre de la Parte I arriba, el centro ya caía en la Parte II y la
  // barra marcaba «Busca tu carrera» mientras se leía la Parte I. Al final de la página, la última.
  function marcarParteActiva() {
    var enlaces = document.querySelectorAll(".barra__partes a");
    var partes = Array.prototype.slice.call(document.querySelectorAll(".parte"));
    var barra = document.querySelector(".barra");
    var actual = null, pendiente = false;
    function calcular() {
      pendiente = false;
      var linea = (barra ? barra.offsetHeight : 0) + window.innerHeight * 0.25;
      var activa = null;
      partes.forEach(function (s) { if (s.getBoundingClientRect().top <= linea) activa = s.id; });
      var alFinal = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2;
      if (alFinal && partes.length) activa = partes[partes.length - 1].id;
      if (activa === actual) return;
      actual = activa;
      enlaces.forEach(function (a) {   // sobre la portada (ninguna parte pasó la línea) no hay activa
        if (a.getAttribute("data-parte") === activa) a.setAttribute("aria-current", "true");
        else a.removeAttribute("aria-current");
      });
    }
    function programar() { if (!pendiente) { pendiente = true; window.requestAnimationFrame(calcular); } }
    window.addEventListener("scroll", programar, { passive: true });
    window.addEventListener("resize", programar);
    calcular();
  }

  // Palabras de la búsqueda, sin tildes ni mayúsculas ("Téc  enfer" → ["tec", "enfer"]).
  function palabras(texto) { return normalizar(texto).split(/\s+/).filter(Boolean); }
  function coincide(nombreNorm, pals) { return pals.every(function (w) { return nombreNorm.indexOf(w) >= 0; }); }

  function buscarPar(texto) {
    var exacto = pares.filter(function (p) { return etiquetaPar(p) === texto; })[0];
    if (exacto) return exacto;
    var pals = palabras(texto);
    if (!pals.length) return null;
    // Todas las palabras, en cualquier parte del nombre y tipo; ante varias, la comparable con más titulados.
    var candidatos = pares.filter(function (p) { return coincide(normalizar(etiquetaPar(p)), pals); });
    return maximoPor(candidatos, function (p) { return (p.marcas.representativo ? 1e9 : 0) + p.conteos.peso; });
  }

  // ------------------------------------------------------------- buscador de la ficha (combobox)
  // Reemplaza al <datalist>: el desplegable nativo no seguía el estilo ni el modo oscuro, exigía
  // tildes y no abría la ficha al elegir. Patrón combobox de ARIA: el foco queda en el campo y la
  // opción activa se indica con aria-activedescendant.
  // Lista plana «Carrera — Tipo», una fila por ficha (pedido del usuario): con una fila por carrera
  // y los tipos como botones había que elegir dos veces. El tipo también se busca como palabra
  // («enfermeria ip»).
  var fichasBuscador = pares.map(function (p) {
    var rotulo = p.nombre + " — " + p.tipo;
    return { p: p, rotulo: rotulo, norm: normalizar(rotulo), nombreNorm: normalizar(p.nombre) };
  });

  // El nombre con las partes que coinciden en negrita. Se compara carácter por carácter sobre el
  // texto normalizado, así "enfermeria" marca "Enfermería" (cada letra normaliza a una sola).
  function nombreResaltado(nombre, pals) {
    var cont = el("span", "sugerencia__nombre");
    var norm = nombre.split("").map(function (c) { var n = normalizar(c); return n.length === 1 ? n : "\u0000"; }).join("");
    var marca = new Array(nombre.length).fill(false);
    pals.forEach(function (w) {
      var i = norm.indexOf(w);
      if (i >= 0) for (var k = i; k < i + w.length; k++) marca[k] = true;
    });
    var tramo = "", enMarca = false;
    function cerrar() { if (tramo) cont.appendChild(enMarca ? el("b", null, tramo) : document.createTextNode(tramo)); tramo = ""; }
    for (var i = 0; i < nombre.length; i++) {
      if (marca[i] !== enMarca) { cerrar(); enMarca = marca[i]; }
      tramo += nombre[i];
    }
    cerrar();
    return cont;
  }

  function prepararBuscador() {
    var campo = document.getElementById("ficha-texto");
    var caja = document.getElementById("ficha-sugerencias");
    var estado = document.getElementById("ficha-sugerencias-estado");
    var opciones = [], activa = -1;

    function cerrar() {
      caja.hidden = true;
      campo.setAttribute("aria-expanded", "false");
      campo.removeAttribute("aria-activedescendant");
      activa = -1;
    }
    function marcar(i) {
      if (activa >= 0 && opciones[activa]) opciones[activa].nodo.setAttribute("aria-selected", "false");
      activa = i;
      if (i < 0) { campo.removeAttribute("aria-activedescendant"); return; }
      var o = opciones[i];
      o.nodo.setAttribute("aria-selected", "true");
      campo.setAttribute("aria-activedescendant", o.nodo.id);
      o.nodo.scrollIntoView({ block: "nearest" });
    }
    function elegir(p) {
      campo.value = etiquetaPar(p);
      cerrar();
      abrirFicha(p, false);
    }
    function actualizar() {
      var pals = palabras(campo.value);
      opciones = [];
      activa = -1;
      caja.replaceChildren();
      if (!pals.length || pares.some(function (p) { return etiquetaPar(p) === campo.value; })) {
        cerrar();   // vacío, o el texto es la ficha ya elegida: no hay nada que sugerir
        return;
      }
      // Orden: el nombre empieza con la búsqueda → alguna palabra del nombre empieza con la
      // primera → el resto; dentro de cada grupo, la ficha con más titulados primero.
      var primera = pals[0], frase = pals.join(" ");
      var hallados = fichasBuscador.filter(function (f) { return coincide(f.norm, pals); }).map(function (f) {
        var rango = f.nombreNorm.indexOf(frase) === 0 ? 0 : (" " + f.nombreNorm).indexOf(" " + primera) >= 0 ? 1 : 2;
        return { f: f, rango: rango };
      }).sort(function (a, b) {
        return a.rango - b.rango || b.f.p.conteos.peso - a.f.p.conteos.peso || colador.compare(a.f.rotulo, b.f.rotulo);
      });

      if (!hallados.length) {
        caja.appendChild(el("p", "sugerencias__vacio", "Ninguna carrera contiene «" + campo.value.trim() + "». Prueba con una parte del nombre."));
        estado.textContent = "Sin resultados.";
      }
      // Todas las coincidencias (como mucho las 252 fichas): se ven ~8 y el resto con desplazamiento.
      hallados.forEach(function (h, i) {
        var p = h.f.p;
        var op = el("div", "sugerencia");
        op.id = "sug-" + i;
        op.setAttribute("role", "option");
        op.setAttribute("aria-selected", "false");
        op.appendChild(nombreResaltado(h.f.rotulo, pals));
        var n = p.conteos.n_inst_oferta;
        var meta = nivelCorto(p).replace(/es$/, "").replace(/s$/, "") +   // "profesionales" → "profesional", "técnicas" → "técnica"
          (p.marcas.representativo ? "" : " · " + n + " inst.");
        op.appendChild(el("span", "sugerencia__meta", meta));
        if (!p.marcas.representativo) op.setAttribute("aria-label", h.f.rotulo + ", sin comparación (" + n + (n === 1 ? " institución)" : " instituciones)"));
        // mousedown con preventDefault: el campo no pierde el foco antes del clic.
        op.addEventListener("mousedown", function (e) { e.preventDefault(); });
        op.addEventListener("click", function () { elegir(p); });
        caja.appendChild(op);
        opciones.push({ nodo: op, p: p });
      });
      if (hallados.length) {
        var n = hallados.length;
        caja.appendChild(el("p", "sugerencias__pie", n + (n === 1 ? " resultado" : " resultados") + " · ↑↓ para moverte · Enter abre la ficha"));
        estado.textContent = n + (n === 1 ? " resultado" : " resultados") + ". Usa las flechas para elegir y Enter para abrir la ficha.";
      }
      caja.hidden = false;
      campo.setAttribute("aria-expanded", "true");
    }

    campo.addEventListener("input", actualizar);
    // Al entrar al campo con la carrera actual escrita, se selecciona todo: escribir la reemplaza.
    campo.addEventListener("focus", function () { if (fichaActual && campo.value === etiquetaPar(fichaActual)) campo.select(); });
    campo.addEventListener("keydown", function (e) {
      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
        if (caja.hidden) { actualizar(); if (caja.hidden) return; }
        e.preventDefault();
        if (!opciones.length) return;
        var sig = e.key === "ArrowDown" ? (activa + 1) % opciones.length : (activa <= 0 ? opciones.length - 1 : activa - 1);
        marcar(sig);
      } else if (e.key === "Enter" && !caja.hidden && activa >= 0) {
        e.preventDefault();
        elegir(opciones[activa].p);
      } else if (e.key === "Escape" && !caja.hidden) {
        e.preventDefault();
        cerrar();
      }
    });
    campo.addEventListener("blur", function () { window.setTimeout(cerrar, 0); });
    document.getElementById("ficha-form").addEventListener("submit", cerrar);
  }

  function desdeDireccion() {
    var m = /#carrera=([^&]+)/.exec(location.hash);
    if (!m) return null;
    // Un enlace cortado al compartirlo trae un "%" incompleto: decodeURIComponent lanza URIError
    // y, sin el try, el arranque se detenía y dejaba vacías la ficha y las secciones siguientes.
    try { return parPorClave[decodeURIComponent(m[1])] || null; } catch (e) { return null; }
  }

  function prepararFicha() {
    prepararBuscador();
    document.getElementById("ficha-form").addEventListener("submit", function (e) {
      e.preventDefault();
      var p = buscarPar(document.getElementById("ficha-texto").value);
      if (p) abrirFicha(p, false);
      else document.getElementById("ficha-estado").textContent = "No hay una carrera con ese nombre. Prueba con una parte del nombre, por ejemplo «enfermería».";
    });
    document.getElementById("ficha-enlace").addEventListener("click", function () {
      var estado = document.getElementById("ficha-estado");
      var url = location.href;
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(url).then(function () { estado.textContent = "Enlace copiado."; },
          function () { estado.textContent = "Copia este enlace: " + url; });
      } else {
        estado.textContent = "Copia este enlace: " + url;
      }
    });
    // Ficha inicial: la de la dirección o, si no hay, la de ejemplo que elige el SQL (la comparable
    // con más titulados, meta.ficha_ejemplo) y se dice por qué está abierta.
    var ej = datos.meta.ficha_ejemplo;
    var inicial = desdeDireccion() || parPorClave[ej.clave + "|" + ej.tipo];
    if (!inicial) throw new Error("La ficha de ejemplo no está entre los pares: " + ej.clave + " / " + ej.tipo);
    pintarFicha(inicial);
    document.getElementById("ficha-texto").value = etiquetaPar(inicial);
    if (desdeDireccion()) document.getElementById("ficha").scrollIntoView();
    else document.getElementById("ficha-estado").textContent =
      "Ejemplo: " + etiquetaPar(inicial) + ", la carrera con más titulados que no es la típica de su grupo. Escribe la tuya arriba.";
    prepararHistorial();
  }

  // ------------------------------------------------------------- qué no dice, método y controles (W6)
  // Cifras desde datos.que_no_dice (armado en SQL) y desde los pares; ninguna escrita a mano.
  function textoConCifras(li, titulo, partes) {
    li.appendChild(el("strong", null, titulo));
    partes.forEach(function (parte, i) {
      li.appendChild(i % 2 ? el("span", "cifra", parte) : document.createTextNode(parte));
    });
  }

  function pintarLimites() {
    var q = datos.que_no_dice, ul = document.getElementById("limites");
    function item(titulo, partes) { var li = el("li"); textoConCifras(li, titulo, partes); ul.appendChild(li); }
    var anomalos = q.hitos_con_anomalia.map(function (a) { return a + "°"; });
    var atipSalud = pares.filter(function (p) { return p.marcas.cohorte_atipica && p.area.cine13 === "Salud y Bienestar"; }).length;
    // Números de analytics.brecha_nacional (antes se sacaban con un regex del texto del control qa).
    var brecha = q.brecha_nacional_instituciones || {};

    item("No dice por qué.", ["Describe cuánto ganan los titulados de cada carrera; no prueba que estudiar esa carrera cause ese sueldo. Pueden influir quién entra a estudiarla, en qué institución y dónde trabaja después."]);
    item("No sigue a las mismas personas.", ["El primer y el quinto año son grupos distintos de titulados medidos con los mismos ingresos de 2024: es una foto, no una trayectoria."]);
    item("No ve a todos.", ["Los programas que publica MiFuturo reúnen el ", pct(q.cobertura_titulaciones[0]),
      " de los titulados recientes y el ", pct(q.cobertura_titulaciones[1]),
      " de los de hace cinco años. Faltan programas chicos y los que cerraron; con baja cobertura: " +
      q.segmentos_baja_cobertura.map(function (s) { var x = s.split(" · "); return x[0] + " (" + x[1].replace("Carreras ", "").toLowerCase() + ")"; }).join(", ") + "."]);
    item("No compara lo que no se puede comparar.", ["", fmtEntero.format(q.pares_no_representativos), " de " + fmtEntero.format(q.pares_total) +
      " carreras tienen menos de " + parametro("min_inst_oferta") + " instituciones y quedan fuera de rankings y gráficos de comparación; solo ",
      fmtEntero.format(q.celdas_validas), " grupos de área tienen carreras suficientes para servir de referencia."]);
    item("No limpia los años raros.", ["Los años ", anomalos.join(", "), " del ingreso promedio incluyen titulados de " +
      parametro("anio_caida_titulacion") + " o " + parametro("anio_rebote_titulacion") + ". En ", fmtEntero.format(q.cohortes_atipicas),
      " carreras la cohorte del sueldo al primer año tuvo una empleabilidad atípica (" + fmtEntero.format(atipSalud) +
      " de salud), y en ", fmtEntero.format(q.pares_composicion_edad), " los titulados recientes son mucho mayores que los de hace cinco años."]);
    item("No mide todo el sueldo.", ["Solo cuenta a quienes ganan al menos el sueldo mínimo y tienen registro en el SII; por eso el P10 está truncado. No hay datos por sexo, edad ni región."]);
    if (brecha.emp_pp != null && brecha.tramo_pct != null) {
      item("La cifra nacional no es el promedio de las instituciones.", ["Queda ", fmtUno.format(brecha.emp_pp) + " puntos",
        " sobre ellas en empleabilidad al primer año y ", fmtUno.format(brecha.tramo_pct) + " %",
        " sobre ellas en el tramo de ingreso del cuarto año: incluye titulados que no aparecen en ninguna institución publicada. Por eso cada institución se compara con la institución típica de su carrera."]);
    }
    item("No incluye las carreras que MiFuturo no publica.", ["Suman el ", pct(q.pct_titulaciones_genericas_no_publicadas),
      " de las titulaciones recientes; entre ellas Física, Historia, Filosofía y Matemática, que MiFuturo omite porque una parte alta de sus titulados sigue estudiando."]);
    item("No tiene márgenes de error.", ["Son registros administrativos completos, no una muestra: las diferencias chicas entre carreras pueden ser reales y aun así poco relevantes."]);
  }

  var NOMBRE_COHORTE = {
    ingreso_medio_1er_anio: "Ingreso promedio, 1er año", ingreso_medio_2do_anio: "Ingreso promedio, 2° año",
    ingreso_medio_3er_anio: "Ingreso promedio, 3er año", ingreso_medio_4to_anio: "Ingreso promedio, 4° año",
    ingreso_medio_5to_anio: "Ingreso promedio, 5° año",
    percentiles_anio_1: "Percentiles (P10–P90), 1er año", percentiles_anio_5: "Percentiles (P10–P90), 5° año",
    empleabilidad_1er_anio_nacional: "Empleabilidad nacional, 1er año", empleabilidad_2do_anio_nacional: "Empleabilidad nacional, 2° año",
    empleabilidad_1er_anio_institucion: "Empleabilidad por institución, 1er año", empleabilidad_2do_anio_institucion: "Empleabilidad por institución, 2° año",
    tramo_ingreso_4to_anio_institucion: "Tramo de ingreso por institución, 4° año",
    continuidad_estudios_institucion: "Continuidad de estudios", duracion_real_institucion: "Duración real por institución",
    titulados_y_duracion: "Titulados y duración", titulados_sies: "Titulaciones SIES"
  };

  function pintarMetodo() {
    var div = document.getElementById("metodo");
    div.appendChild(el("p", null, "Fuentes: " + datos.meta.fuentes.join("; ") + ". Montos en " + datos.meta.unidad_ingresos.replace(">=", "≥") + "."));
    div.appendChild(el("p", null, "Una carrera es una carrera genérica de MiFuturo dentro de un tipo de institución (universidad, instituto profesional o centro de formación técnica). Cada carrera se compara con las de su misma área, tipo y nivel; si el área tiene pocas carreras o una sola domina el grupo, con todas las de su tipo y nivel."));
    div.appendChild(el("p", null, "Cómo se construye, de los archivos públicos a esta página (se reproduce con un solo comando, make todo):"));
    div.appendChild(el("p", "metodo__flujo", "CSV de MiFuturo y SIES → base PostgreSQL (raw → modelo → analytics) → " +
      fmtEntero.format(datos.qa.controles.length) + " controles de calidad → datos.json → esta página, un solo archivo sin dependencias"));

    var cuerpo = document.querySelector("#tabla-cohortes tbody");
    var FUENTE = { Estadisticas: "MiFuturo, Estadísticas por Carrera", Empleabilidad: "MiFuturo, Empleabilidad e Ingresos", Titulados: "SIES" };
    var ordenCohorte = Object.keys(NOMBRE_COHORTE);
    function posicionCohorte(c) { var i = ordenCohorte.indexOf(c.indicador); return i < 0 ? 999 : i; }
    datos.cohortes.filter(function (c) { return c.indicador.indexOf("serie_") !== 0; })
      .sort(function (a, b) { return posicionCohorte(a) - posicionCohorte(b); }).forEach(function (c) {
      var tr = el("tr");
      var rango = function (a) { return a[0] == null ? "—" : a[0] === a[1] ? String(a[0]) : a[0] + "–" + a[1]; };
      [["Cifra", NOMBRE_COHORTE[c.indicador] || c.indicador, "td--titulo"],
       ["Titulados en", rango(c.cohortes), ""],
       ["Ingresos de", rango(c.anios_ingreso), ""],
       ["Mínimo de casos", c.min_casos == null ? "—" : fmtEntero.format(c.min_casos), "num"],
       ["Fuente", FUENTE[c.fuente] || c.fuente, ""]].forEach(function (x) {
        var td = el("td", x[2] || null, x[1]); td.setAttribute("data-rotulo", x[0]); tr.appendChild(td);
      });
      cuerpo.appendChild(tr);
    });
    var nota = el("p", "nota", "Derecho usa en todas las cifras las cohortes corridas un año.");
    document.getElementById("tabla-cohortes").parentNode.parentNode.appendChild(nota);

    var cp = document.querySelector("#tabla-parametros tbody");
    datos.parametros.forEach(function (prm) {
      var tr = el("tr");
      // Proporciones (0–1) se muestran como %; años y conteos, tal cual.
      var valor = prm.valor > 0 && prm.valor < 1 ? fmtEntero.format(prm.valor * 100) + " %" : prm.valor > 1900 ? String(prm.valor) : fmtEntero.format(prm.valor);
      [["Regla", prm.descripcion, "td--titulo"], ["Valor", valor, "num"]].forEach(function (x) {
        var td = el("td", x[2], x[1]); td.setAttribute("data-rotulo", x[0]); tr.appendChild(td);
      });
      cp.appendChild(tr);
    });
  }

  var ESTADO = {
    OK: { clase: "estado--ok", icono: "✓", texto: "aprobado", plural: "aprobados" },
    EXENTO: { clase: "estado--exento", icono: "–", texto: "no aplica", plural: "no aplican" },
    FALLA: { clase: "estado--falla", icono: "✕", texto: "falla", plural: "fallas" }
  };

  function estadoNodo(estado, cantidad) {
    var e = ESTADO[estado], s = el("span", "estado " + e.clase);
    s.appendChild(el("span", "estado__icono", e.icono)).setAttribute("aria-hidden", "true");
    s.appendChild(el("span", "estado__texto", (cantidad != null ? fmtEntero.format(cantidad) + " " : "") +
      (cantidad != null && cantidad !== 1 ? e.plural : e.texto)));
    return s;
  }

  function pintarControles() {
    var r = datos.qa.resumen, p = document.getElementById("qa-resumen");
    ["OK", "EXENTO", "FALLA"].forEach(function (k) { p.appendChild(estadoNodo(k, r[k] || 0)); });
    var cuerpo = document.querySelector("#tabla-qa tbody");
    datos.qa.controles.forEach(function (c) {
      var tr = el("tr");
      var t1 = el("td", "td--titulo", c.control.replace(/_/g, " ") + " · " + c.objeto.replace(/_/g, " "));
      t1.setAttribute("data-rotulo", "Control");
      var t2 = el("td"); t2.setAttribute("data-rotulo", "Estado"); t2.appendChild(estadoNodo(c.estado));
      var t3 = el("td", null, c.detalle); t3.setAttribute("data-rotulo", "Resultado");
      t3.title = "Criterio: " + c.umbral;
      tr.appendChild(t1); tr.appendChild(t2); tr.appendChild(t3);
      cuerpo.appendChild(tr);
    });
  }

  // ------------------------------------------------------------- notas y pie
  function pintarNotas() {
    document.getElementById("pie-comparacion").textContent =
      "Comparación transversal: el primer y el quinto año son grupos distintos de titulados, no las mismas personas en el tiempo.";
    document.getElementById("pie-fuentes").textContent = "Fuentes: " + datos.meta.fuentes.join(" · ") + ".";
  }

  // ------------------------------------------------------------- tema claro / oscuro
  // La preferencia del sistema manda hasta que la persona elige; la elección se recuerda
  // en este navegador (si el almacenamiento no está disponible, la página funciona igual).
  function iniciarTema() {
    var boton = document.getElementById("boton-tema");
    var raiz = document.documentElement;
    var guardado = null;
    try { guardado = window.localStorage.getItem("tema"); } catch (e) { /* sin almacenamiento */ }
    if (guardado === "dark" || guardado === "light") raiz.setAttribute("data-theme", guardado);

    function esOscuro() {
      var elegido = raiz.getAttribute("data-theme");
      if (elegido) return elegido === "dark";
      return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
    }
    function rotular() {
      var oscuro = esOscuro();
      boton.querySelector(".boton-tema__texto").textContent = oscuro ? "Modo claro" : "Modo oscuro";
      boton.setAttribute("aria-pressed", String(oscuro));
    }
    boton.addEventListener("click", function () {
      var nuevo = esOscuro() ? "light" : "dark";
      raiz.setAttribute("data-theme", nuevo);
      try { window.localStorage.setItem("tema", nuevo); } catch (e) { /* sin almacenamiento */ }
      rotular();
    });
    rotular();
  }

  iniciarTema();
  pintarPortada();
  prepararPeine();
  pintarPeine();
  alCambiarAncho(document.getElementById("peine-lienzo"), pintarPeine);
  pintarHallazgos();
  pintarUniversoTextos();
  pintarUniverso();
  alCambiarAncho(document.getElementById("universo-lienzo"), pintarUniverso);
  pintarTitulos();
  pintarCierre();
  prepararCuadrantes();
  pintarCuadrantes(false);
  pintarSegmentos();
  pintarLeyenda();
  prepararFicha();
  marcarParteActiva();
  pintarLimites();
  pintarMetodo();
  pintarControles();
  pintarNotas();
})();
