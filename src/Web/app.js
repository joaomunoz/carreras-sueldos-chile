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
      parrafoEn(tesis, ["En la carrera técnica típica, quienes se titularon hace cinco años ganan ",
        dt[0], dt[1] + " que los recién titulados; en la profesional típica, ",
        dp[0], dp[1] + ". Tres lecturas comunes de esas cifras fallan."]);
    }
    var qa = datos.qa.resumen, qnd = datos.que_no_dice;
    var total = (qa.OK || 0) + (qa.EXENTO || 0);
    parrafoEn(document.getElementById("portada-tecnica"), [
      "", fmtEntero.format(qnd.pares_total), " carreras por tipo de institución · ",
      fmtEntero.format(qnd.pares_total - qnd.pares_no_representativos), " comparables · ",
      fmtEntero.format(total), " controles de calidad · pesos de septiembre de 2025"]);
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

  // Tarjeta de la grilla: la lectura ingenua tachada (<s>: contenido que ya no es exacto), la
  // corrección con una cifra grande y un enlace a la evidencia (gráfico o ficha).
  function hallazgo(t) {
    var li = el("li", "hallazgo");
    li.appendChild(el("p", "hallazgo__rotulo", "Parece que"));
    var parece = el("p", "hallazgo__parece");
    parece.appendChild(el("s", null, t.parece));
    li.appendChild(parece);
    li.appendChild(el("p", "hallazgo__rotulo", "Pero"));
    var cifra = el("p", "hallazgo__cifra");
    cifra.appendChild(el("strong", null, t.cifra));
    cifra.appendChild(el("span", null, t.rotulo));
    li.appendChild(cifra);
    var cuerpo = el("div", "hallazgo__pero");
    t.nodos.forEach(function (n) { cuerpo.appendChild(n); });
    li.appendChild(cuerpo);
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

  // Franja del hallazgo (c): rango de empleabilidad entre instituciones, mitad central,
  // mediana y cifra nacional. SVG con escala propia (mínimo a máximo de esa carrera).
  function franja(disp, nacional) {
    var ns = "http://www.w3.org/2000/svg";
    var ancho = 300, alto = 36, m = 4;
    var lo = Math.min(disp.min, nacional), hi = Math.max(disp.max, nacional);
    function x(v) { return m + (v - lo) / (hi - lo) * (ancho - 2 * m); }
    var svg = document.createElementNS(ns, "svg");
    svg.setAttribute("viewBox", "0 0 " + ancho + " " + alto);
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", "Empleabilidad entre instituciones: de " + pct(disp.min) + " a " + pct(disp.max) +
      "; la mitad central entre " + pct(disp.q1) + " y " + pct(disp.q3) + "; cifra nacional " + pct(nacional) + ".");
    function forma(tipo, atributos, clase) {
      var n = document.createElementNS(ns, tipo);
      Object.keys(atributos).forEach(function (k) { n.setAttribute(k, atributos[k]); });
      n.setAttribute("class", clase);
      svg.appendChild(n);
    }
    forma("line", { x1: x(disp.min), x2: x(disp.max), y1: 14, y2: 14 }, "franja__rango");
    forma("rect", { x: x(disp.q1), y: 7, width: x(disp.q3) - x(disp.q1), height: 14, rx: 1 }, "franja__caja");
    forma("line", { x1: x(disp.mediana), x2: x(disp.mediana), y1: 7, y2: 21 }, "franja__mediana");
    var xn = x(nacional);
    forma("path", { d: "M" + xn + " 24 l-5 8 h10 z" }, "franja__nacional");
    var cont = el("div", "franja");
    cont.appendChild(svg);
    cont.appendChild(el("p", "franja__leyenda",
      "Línea: de la institución más baja a la más alta · bloque: la mitad central · ▲ cifra nacional"));
    return cont;
  }

  // Las cifras y los ejemplos de los hallazgos vienen calculados de la base
  // (src/Analisis/sql/analytics/06_hallazgos.sql, con controles qa): aquí solo se redactan.
  // Calcularlos aquí produjo errores que ningún control veía (una mediana de edad de 9
  // carreras atribuida a 7). Si un hallazgo no tiene ejemplo, se omite sin cortar los demás.
  function pintarHallazgos() {
    var ul = document.getElementById("hallazgos");
    var h = datos.hallazgos;

    // (a) por nivel: técnicas y profesionales nunca se resumen con una misma mediana.
    var tec = nivelEdad("Carreras Técnicas"), pro = nivelEdad("Carreras Profesionales");
    if (tec && pro && tec.n_negativos) {
      var nodosA = [parrafo(["No es que bajen los sueldos: ambos años se miden con los ingresos de 2024."])];
      if (tec.n_con_edad) {
        nodosA.push(parrafo(["En ", fmtEntero.format(tec.n_con_edad), " de ellas, quienes tienen 30 años o más pasan de ",
          pct(tec.mayores30[0]), " a ", pct(tec.mayores30[1]),
          " de los titulados (mediana de esas " + fmtEntero.format(tec.n_con_edad) + "): muchos ya trabajaban antes de titularse."]));
      }
      nodosA.push(parrafo(["En las profesionales pasa en ",
        fmtEntero.format(pro.n_negativos) + " de " + fmtEntero.format(pro.n_comparables), "."]));
      ul.appendChild(hallazgo({
        parece: "Al quinto año siempre se gana más que al primero.",
        cifra: fmtEntero.format(tec.n_negativos) + " de " + fmtEntero.format(tec.n_comparables),
        rotulo: "carreras técnicas ganan menos al quinto año que al primero",
        nodos: nodosA, accion: "Verlas en el peine ↓", href: "#t-peine",
        alClic: function () { elegirNivelPeine("Carreras Técnicas"); }
      }));
    }

    var b = h.pct_pesos, eb = b.ejemplo;
    var pb = eb && parPorClave[eb.clave + "|" + eb.tipo];
    if (pb) {
      ul.appendChild(hallazgo({
        parece: "Crecer más en porcentaje es crecer más.",
        cifra: fmtEntero.format(b.n_cambian),
        rotulo: "carreras cambian de cuadrante si el crecimiento se mide en pesos",
        nodos: [parrafo([eb.nombre + " (" + eb.tipo + ") sube ", pctSigno(eb.p50_pct_1_5), ", pero parte de ",
          pesos(eb.p50_anio_1), ": suma ", pesosSigno(eb.p50_delta_1_5),
          ", menos que la carrera típica de su grupo, ponderada por titulados (", pesosSigno(eb.ref_delta_q50), ")."])],
        accion: "Ver su ficha →", par: pb
      }));
    }

    var c = h.dispersion, ec = c.ejemplo;
    var pc = ec && parPorClave[ec.clave + "|" + ec.tipo];
    if (pc) {
      ul.appendChild(hallazgo({
        parece: "El promedio nacional describe a la carrera.",
        cifra: fmtEntero.format(c.n_enganosos),
        rotulo: "carreras donde las instituciones difieren " + fmtEntero.format(c.umbral_pp) +
          " puntos o más en empleabilidad, aun sin el cuarto más alto ni el más bajo",
        // Se cita la mitad central (lo que mide el criterio); el mínimo y el máximo quedan en la franja.
        nodos: [parrafo([ec.nombre + " (" + ec.tipo + ", " + ec.n_inst + " instituciones): la mitad central va de ",
            pct(ec.q1), " a ", pct(ec.q3), "; la cifra nacional es ", pct(ec.nacional), "."]),
          franja(pc.dispersion.emp1, ec.nacional)],
        accion: "Ver su ficha →", par: pc
      }));
    }
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

  // ------------------------------------------------------------- tabla de carreras
  var COLUMNAS = {
    nombre: { rotulo: "Carrera", valor: function (p) { return p.nombre; }, texto: true },
    tipo:   { rotulo: "Tipo", valor: function (p) { return p.tipo; }, texto: true },
    p50_1:  { rotulo: "P50 1er año", valor: function (p) { return p.percentiles.anio_1.p50; } },
    p50_5:  { rotulo: "P50 5° año", valor: function (p) { return p.percentiles.anio_5.p50; } },
    crec:   { rotulo: "Crecimiento P50", valor: function (p) { return p.percentiles.p50_pct_1_5; } },
    emp1:   { rotulo: "Empleabilidad 1er año", valor: function (p) { return p.empleabilidad_nacional[0]; } },
    inst:   { rotulo: "Instituciones", valor: function (p) { return p.conteos.n_inst_oferta; } }
  };
  var orden = { col: "crec", desc: true };
  // N4: sin filtros la tabla muestra las primeras FILAS_TABLA según el orden elegido (el orden se
  // aplica antes de cortar: ordenar por P50 5° año muestra las 20 que más ganan).
  var FILAS_TABLA = 20;
  var tablaCompleta = false;
  var colador = new Intl.Collator("es", { sensitivity: "base" });

  function llenarSelect(id, valores) {
    var sel = document.getElementById(id);
    valores.forEach(function (v) {
      var op = el("option", null, v[1]);
      op.value = v[0];
      sel.appendChild(op);
    });
  }

  function unicos(f) {
    var vistos = {};
    pares.forEach(function (p) { vistos[f(p)] = true; });
    return Object.keys(vistos).sort(colador.compare);
  }

  function prepararFiltros() {
    llenarSelect("f-tipo", unicos(function (p) { return p.tipo; }).map(function (v) { return [v, v]; }));
    llenarSelect("f-nivel", unicos(function (p) { return p.nivel; }).map(function (v) { return [v, v.replace("Carreras ", "")]; }));
    llenarSelect("f-area", unicos(function (p) { return p.area.cine13; }).map(function (v) { return [v, v]; }));
    var opcionesOrden = [];
    Object.keys(COLUMNAS).forEach(function (k) {
      var c = COLUMNAS[k];
      if (c.texto) opcionesOrden.push([k + "|asc", c.rotulo + " (A–Z)"]);
      else {
        opcionesOrden.push([k + "|desc", c.rotulo + " (mayor primero)"]);
        opcionesOrden.push([k + "|asc", c.rotulo + " (menor primero)"]);
      }
    });
    llenarSelect("f-orden", opcionesOrden);
    document.getElementById("f-orden").value = orden.col + "|" + (orden.desc ? "desc" : "asc");

    var form = document.getElementById("filtros");
    form.addEventListener("input", pintarCarreras);
    form.addEventListener("change", pintarCarreras);
    form.addEventListener("submit", function (e) { e.preventDefault(); });
    document.getElementById("tabla-mas").addEventListener("click", function (e) {
      tablaCompleta = !tablaCompleta;
      pintarCarreras();
      // Al plegar, la tabla se acorta bajo el lector: se vuelve al botón para no perderse.
      if (!tablaCompleta) e.currentTarget.scrollIntoView({ block: "center", behavior: suave() });
    });
    document.getElementById("f-orden").addEventListener("change", function (e) {
      var partes = e.target.value.split("|");
      orden = { col: partes[0], desc: partes[1] === "desc" };
      pintarCarreras();
    });
    document.querySelectorAll("#tabla-carreras thead th").forEach(function (th) {
      th.querySelector("button").addEventListener("click", function () {
        var col = th.getAttribute("data-col");
        // Primer clic: texto de A a Z; cifras de mayor a menor (lo que se busca primero).
        orden = orden.col === col ? { col: col, desc: !orden.desc } : { col: col, desc: !COLUMNAS[col].texto };
        document.getElementById("f-orden").value = orden.col + "|" + (orden.desc ? "desc" : "asc");
        pintarCarreras();
      });
    });
  }

  // "Crecimiento P50" → "crecimiento P50", pero "P50 5° año" queda igual (sigla o cifra al inicio).
  function enMinuscula(rotulo) {
    return /^.[A-Z0-9]/.test(rotulo) ? rotulo : rotulo.charAt(0).toLowerCase() + rotulo.slice(1);
  }

  // "Solo comparables" no cuenta como filtro: viene marcado y no busca una carrera concreta.
  function hayFiltro() {
    return !!(document.getElementById("f-texto").value.trim() || document.getElementById("f-tipo").value ||
              document.getElementById("f-nivel").value || document.getElementById("f-area").value);
  }

  function filtrar() {
    var texto = normalizar(document.getElementById("f-texto").value.trim());
    var tipo = document.getElementById("f-tipo").value;
    var nivel = document.getElementById("f-nivel").value;
    var area = document.getElementById("f-area").value;
    var soloComparables = document.getElementById("f-comparables").checked;
    return pares.filter(function (p) {
      return (!texto || normalizar(p.nombre).indexOf(texto) >= 0)
        && (!tipo || p.tipo === tipo)
        && (!nivel || p.nivel === nivel)
        && (!area || p.area.cine13 === area)
        && (!soloComparables || p.marcas.representativo);
    });
  }

  function ordenar(lista) {
    var c = COLUMNAS[orden.col];
    var signo = orden.desc ? -1 : 1;
    return lista.slice().sort(function (a, b) {
      var va = c.valor(a), vb = c.valor(b);
      // Los vacíos siempre al final, en cualquier sentido.
      if (va == null && vb == null) return 0;
      if (va == null) return 1;
      if (vb == null) return -1;
      var r = c.texto ? colador.compare(va, vb) : va - vb;
      return r !== 0 ? signo * r : colador.compare(a.nombre, b.nombre);
    });
  }

  function celda(tr, rotulo, contenido, clase) {
    var td = el("td", clase || null);
    td.setAttribute("data-rotulo", rotulo);
    if (typeof contenido === "string") td.textContent = contenido;
    else td.appendChild(contenido);
    tr.appendChild(td);
    return td;
  }

  function pintarCarreras() {
    var lista = ordenar(filtrar());
    var recortada = !hayFiltro() && lista.length > FILAS_TABLA;
    var visibles = recortada && !tablaCompleta ? lista.slice(0, FILAS_TABLA) : lista;
    var cuerpo = document.querySelector("#tabla-carreras tbody");
    var fragmento = document.createDocumentFragment();
    visibles.forEach(function (p) {
      var tr = el("tr");
      var nombre = el("div");
      var boton = el("button", "carrera__nombre enlace-ficha", p.nombre);
      boton.type = "button";
      boton.addEventListener("click", function () { abrirFicha(p, true); });
      nombre.appendChild(boton);
      var timbres = el("div", "timbres");
      TIMBRES.forEach(function (def) { if (def.aplica(p)) timbres.appendChild(timbre(def)); });
      if (timbres.childNodes.length) nombre.appendChild(timbres);
      celda(tr, "Carrera", nombre, "td--titulo");
      celda(tr, "Tipo", p.tipo + " · " + p.nivel.replace("Carreras ", "").toLowerCase());
      celda(tr, "P50 1er año", pesos(p.percentiles.anio_1.p50), "num");
      celda(tr, "P50 5° año", pesos(p.percentiles.anio_5.p50), "num");
      celda(tr, "Crecimiento P50", pctSigno(p.percentiles.p50_pct_1_5),
            "num" + (p.percentiles.p50_pct_1_5 < 0 ? " negativo" : ""));
      celda(tr, "Empleabilidad 1er año", pct(p.empleabilidad_nacional[0]), "num");
      celda(tr, "Instituciones", fmtEntero.format(p.conteos.n_inst_oferta), "num");
      fragmento.appendChild(tr);
    });
    cuerpo.replaceChildren(fragmento);

    document.querySelectorAll("#tabla-carreras thead th").forEach(function (th) {
      if (th.getAttribute("data-col") === orden.col) th.setAttribute("aria-sort", orden.desc ? "descending" : "ascending");
      else th.removeAttribute("aria-sort");
    });
    var c = COLUMNAS[orden.col];
    var sentido = c.texto ? (orden.desc ? "Z–A" : "A–Z") : (orden.desc ? "mayor primero" : "menor primero");
    document.getElementById("conteo").textContent = !lista.length
      ? "Ninguna carrera coincide con estos filtros. Prueba quitar alguno o desmarcar «Solo comparables»."
      : visibles.length < lista.length
        ? "Mostrando las " + fmtEntero.format(visibles.length) + " primeras de " + fmtEntero.format(lista.length) +
          ", ordenadas por " + enMinuscula(c.rotulo) + " (" + sentido + ")."
        : "Mostrando " + fmtEntero.format(lista.length) + " de " + fmtEntero.format(pares.length) + " carreras.";
    var mas = document.getElementById("tabla-mas");
    mas.hidden = !recortada;
    mas.setAttribute("aria-expanded", String(recortada && tablaCompleta));
    mas.textContent = tablaCompleta ? "Mostrar solo las " + FILAS_TABLA + " primeras"
                                    : "Ver las " + fmtEntero.format(lista.length) + " carreras ↓";
  }

  // ------------------------------------------------------------- utilidades SVG y tooltip
  var NS = "http://www.w3.org/2000/svg";
  function svgEl(tipo, atributos, clase, padre) {
    var n = document.createElementNS(NS, tipo);
    Object.keys(atributos).forEach(function (k) { n.setAttribute(k, atributos[k]); });
    if (clase) n.setAttribute("class", clase);
    if (padre) padre.appendChild(n);
    return n;
  }

  // Pesos abreviados para ejes: $800 mil, $1 M, $1,5 M.
  function pesosCorto(v) {
    if (v >= 1e6) return "$" + fmtUno.format(v / 1e6).replace(",0", "") + " M";
    return "$" + fmtEntero.format(v / 1e3) + " mil";
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

    var W = lienzo.clientWidth || 800;
    var angosto = W < 600;
    var H = angosto ? 260 : 340;
    var m = { izq: angosto ? 44 : 56, der: 8, arriba: 22, abajo: 18 };   // abajo: fila de ▼
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
      t.textContent = pesosCorto(v);
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
  var cuad = { modo: "pct", puntos: [], activo: -1 };

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
    cuad.puntos = comparables.map(function (p) {
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

    var cuerpo = document.querySelector("#cuadrantes-tabla tbody");
    cuad.puntos.filter(function (q) { return q.p.posicion.cambia_cuadrante; })
      .sort(function (a, b) { return colador.compare(a.p.nombre, b.p.nombre); })
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
    alCambiarAncho(document.getElementById("cuadrantes-lienzo"), function () { pintarCuadrantes(false); });
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
    var m = { izq: angosto ? 50 : 66, der: 10, arriba: 10, abajo: 40 };
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
    var reusar = animar && svg && Number(svg.getAttribute("data-ancho")) === W;
    if (!reusar) {
      svg = svgEl("svg", { viewBox: "0 0 " + W + " " + H, height: H, role: "img", "data-ancho": W });
      svgEl("g", {}, "c-fondo", svg);
      var capa = svgEl("g", {}, "c-puntos", svg);
      puntos.forEach(function (q, i) {
        var g = svgEl("g", { "data-i": i }, "c-punto" + (q.p.posicion.cambia_cuadrante ? " c-punto--cambia" : "") +
          (q.p.marcas.cohorte_atipica || q.p.marcas.composicion_edad ? " c-punto--aviso" : ""), capa);
        svgEl("circle", { cx: 0, cy: 0, r: q.p.posicion.cambia_cuadrante ? (angosto ? 4 : 5) : (angosto ? 2.8 : 3.5) }, null, g);
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
    svg.setAttribute("aria-label", puntos.length + " carreras comparables según sueldo de entrada y crecimiento " +
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
    var tituloX = svgEl("text", { x: (m.izq + W - m.der) / 2, y: H - 4, "text-anchor": "middle" }, "c-titulo-eje", fondo);
    tituloX.textContent = "Sueldo al 1er año respecto del típico de su grupo";
    var pasoY = modo === "pct" ? 20 : ((y1 - y0) > 1.2e6 ? 500000 : 250000);
    for (var v = Math.ceil(yPiso / pasoY) * pasoY; v <= yTope; v += pasoY) {
      svgEl("line", { x1: m.izq, x2: W - m.der, y1: y(v), y2: y(v) }, v === 0 ? "c-centro" : "g-grilla", fondo);
      var ty = svgEl("text", { x: m.izq - 6, y: y(v) + 4, "text-anchor": "end" }, "g-eje-texto", fondo);
      ty.textContent = v === 0 ? "típico" : modo === "pct" ? (v > 0 ? "+" : "−") + fmtEntero.format(Math.abs(v)) + " pp"
                                                         : (v > 0 ? "+" : "−") + pesosCorto(Math.abs(v));
    }

    // Esquinas: nombre del cuadrante y conteo (desde `posicion`, la clasificación del análisis).
    var frente = svg.querySelector(".c-frente");
    frente.replaceChildren();
    var conteo = {};
    puntos.forEach(function (q) { conteo[q.p.posicion[clave]] = (conteo[q.p.posicion[clave]] || 0) + 1; });
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
      c.textContent = fmtEntero.format(conteo[e[0]] || 0) + " carreras";
    });

    // Puntos: el transform lleva la posición; la transición CSS anima el cambio de modo.
    svg.querySelectorAll(".c-punto").forEach(function (g) {
      var q = puntos[Number(g.getAttribute("data-i"))];
      if (reusar) g.style.transition = "";
      g.style.transform = "translate(" + x(q.razon) + "px," + y(yDe(q)) + "px)";
      var rot = g.querySelector(".c-rotulo-ejemplo");
      if (rot) {
        // Encima del punto (al lado tapaba a un vecino en el modo %), centrado; cerca de un
        // borde se ancla hacia adentro para no salirse del gráfico.
        var xp = x(q.razon), mitad = rot.getComputedTextLength() / 2 + 4;
        var ancla = xp - mitad < m.izq ? "start" : xp + mitad > W - m.der ? "end" : "middle";
        rot.setAttribute("x", ancla === "start" ? -8 : ancla === "end" ? 8 : 0);
        rot.setAttribute("text-anchor", ancla);
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

  // ------------------------------------------------------------- mancuerna con bandas
  // Un segmento a la vez (decisión de diseño). Eje común en pesos para todas las filas del
  // segmento, de P10 mínimo a P90 máximo de las carreras mostradas.
  function prepararMancuerna() {
    var sel = document.getElementById("m-segmento");
    datos.segmentos.forEach(function (s) {
      var op = el("option", null, s.tipo + " · " + s.nivel.replace("Carreras ", "").toLowerCase());
      op.value = s.tipo + "|" + s.nivel;
      sel.appendChild(op);
    });
    // Por defecto, el segmento con más carreras comparables (hoy Universidad profesional).
    var mayor = maximoPor(datos.segmentos, function (s) { return s.representativos; });
    sel.value = mayor.tipo + "|" + mayor.nivel;
    var form = document.getElementById("mancuerna-filtros");
    form.addEventListener("change", pintarMancuerna);
    form.addEventListener("submit", function (e) { e.preventDefault(); });
    alCambiarAncho(document.getElementById("mancuerna"), pintarMancuerna);
    document.getElementById("mancuerna-plegable").addEventListener("toggle", pintarMancuerna);
  }

  // Dos filas (1er año / 5° año) de P10–P90, P25–P75 y P50 sobre un eje de lo a hi pesos.
  // La usan la sección "Sueldo típico y dispersión" y la ficha por carrera.
  function svgMancuerna(p, lo, hi, ancho) {
    var mIzq = 20, mDer = 8;
    function x(v) { return mIzq + (v - lo) / (hi - lo) * (ancho - mIzq - mDer); }
    var svg = svgEl("svg", { viewBox: "0 0 " + ancho + " 36", preserveAspectRatio: "none", "aria-hidden": "true" });
    marcasPesos(lo, hi).forEach(function (v) {
      svgEl("line", { x1: x(v), x2: x(v), y1: 0, y2: 36 }, "g-grilla", svg);
    });
    [["anio1", p.percentiles.anio_1, 11, "1°"], ["anio5", p.percentiles.anio_5, 26, "5°"]].forEach(function (a) {
      var q = a[1], yy = a[2];
      var e = svgEl("text", { x: 2, y: yy + 4 }, "m-etiqueta", svg); e.textContent = a[3];
      svgEl("line", { x1: x(q.p10), x2: x(q.p90), y1: yy, y2: yy }, "m-rango m-rango--" + a[0], svg);
      svgEl("line", { x1: x(q.p25), x2: x(q.p75), y1: yy, y2: yy }, "m-caja m-caja--" + a[0], svg);
      svgEl("circle", { cx: x(q.p50), cy: yy, r: 5 }, "g-" + a[0] + " g-anillo", svg);
    });
    return svg;
  }

  function pintarMancuerna() {
    if (!document.getElementById("mancuerna-plegable").open) return;   // N4: se dibuja al abrir
    var partes = document.getElementById("m-segmento").value.split("|");
    var criterio = document.getElementById("m-orden").value;
    var incluir = document.getElementById("m-no-comparables").checked;
    var valor = {
      p50_5: function (p) { return p.percentiles.anio_5.p50; },
      p50_1: function (p) { return p.percentiles.anio_1.p50; },
      crec: function (p) { return p.percentiles.p50_pct_1_5; }
    }[criterio];
    var lista = pares.filter(function (p) {
      return p.tipo === partes[0] && p.nivel === partes[1] && (incluir || p.marcas.representativo);
    }).sort(function (a, b) { return valor(b) - valor(a) || colador.compare(a.nombre, b.nombre); });

    var ol = document.getElementById("mancuerna-filas");
    var ejeCont = document.getElementById("mancuerna-eje");
    var figura = document.getElementById("mancuerna");
    var caja = document.getElementById("mancuerna-tooltip");
    var cuerpoTabla = document.querySelector("#mancuerna-tabla tbody");
    ol.replaceChildren();
    cuerpoTabla.replaceChildren();
    if (!lista.length) {
      ejeCont.replaceChildren();
      ol.appendChild(el("li", "mancuerna__vacio", "No hay carreras comparables en este grupo. Marca «Incluir no comparables» para verlas."));
      return;
    }

    var lo = Infinity, hi = -Infinity;
    lista.forEach(function (p) {
      lo = Math.min(lo, p.percentiles.anio_1.p10, p.percentiles.anio_5.p10);
      hi = Math.max(hi, p.percentiles.anio_1.p90, p.percentiles.anio_5.p90);
    });
    lo = Math.floor(lo / 250000) * 250000;
    hi = Math.ceil(hi / 250000) * 250000;
    var anchoBarra = Math.max(200, ejeCont.clientWidth || 600);
    var mIzq = 20, mDer = 8;
    function x(v) { return mIzq + (v - lo) / (hi - lo) * (anchoBarra - mIzq - mDer); }

    var eje = svgEl("svg", { viewBox: "0 0 " + anchoBarra + " 24", preserveAspectRatio: "none" });
    marcasPesos(lo, hi).forEach(function (v, i, arr) {
      // En pantallas angostas, una marca de por medio para que los rótulos no choquen.
      if (anchoBarra < 420 && i % 2 && i !== arr.length - 1) return;
      var t = svgEl("text", { x: x(v), y: 16, "text-anchor": "middle" }, "g-eje-texto", eje);
      t.textContent = pesosCorto(v);
    });
    ejeCont.replaceChildren(eje);

    lista.forEach(function (p) {
      var li = el("li", "mancuerna__fila");
      li.tabIndex = 0;
      var rot = el("div", "mancuerna__rotulo");
      rot.appendChild(el("span", null, p.nombre));
      var t = el("div", "timbres");
      TIMBRES.forEach(function (def) {
        if (def.aplica(p) && def.id !== "baja_cobertura") t.appendChild(timbre(def)); // la baja cobertura es del segmento entero
      });
      if (t.childNodes.length) rot.appendChild(t);
      li.appendChild(rot);

      var cont = el("div", "mancuerna__svg");
      cont.appendChild(svgMancuerna(p, lo, hi, anchoBarra));
      li.appendChild(cont);

      var lineas = [
        "1er año  P50 " + pesos(p.percentiles.anio_1.p50),
        "   mitad central " + pesos(p.percentiles.anio_1.p25) + "–" + pesos(p.percentiles.anio_1.p75),
        "5° año   P50 " + pesos(p.percentiles.anio_5.p50) + " (" + pctSigno(p.percentiles.p50_pct_1_5) + ")",
        "   mitad central " + pesos(p.percentiles.anio_5.p25) + "–" + pesos(p.percentiles.anio_5.p75)
      ];
      function mostrar() {
        llenarTooltip(caja, p, lineas);
        var rf = figura.getBoundingClientRect(), rs = cont.getBoundingClientRect();
        ubicarTooltip(caja, figura, rs.left - rf.left + rs.width * (x(p.percentiles.anio_5.p50) / anchoBarra), rs.top - rf.top);
      }
      li.addEventListener("pointerenter", mostrar);
      li.addEventListener("click", function () { abrirFicha(p, true); });
      li.addEventListener("keydown", function (e) { if (e.key === "Enter") abrirFicha(p, true); });
      li.style.cursor = "pointer";
      li.addEventListener("focus", mostrar);
      li.addEventListener("pointerleave", function () { caja.hidden = true; });
      li.addEventListener("blur", function () { caja.hidden = true; });
      li.setAttribute("aria-label", p.nombre + ". " + lineas.join(". ").replace(/\s+/g, " "));
      ol.appendChild(li);

      [["1er año", p.percentiles.anio_1], ["5° año", p.percentiles.anio_5]].forEach(function (a, k) {
        var tr = el("tr");
        tr.appendChild(el("td", null, k === 0 ? p.nombre : ""));
        tr.appendChild(el("td", null, a[0]));
        ["p10", "p25", "p50", "p75", "p90"].forEach(function (c) { tr.appendChild(el("td", "num", pesos(a[1][c]))); });
        cuerpoTabla.appendChild(tr);
      });
    });
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
  function etiquetaPar(p) { return p.nombre + " · " + p.tipo; }

  function liq(dl, rotulo, valor, esTexto) {
    var fila = el("div", "liq__linea");
    fila.appendChild(el("dt", null, rotulo));
    fila.appendChild(el("span", "liq__guia"));
    fila.appendChild(el("dd", esTexto ? "liq__texto" : null, valor));
    dl.appendChild(fila);
  }

  function bloque(cont, titulo) {
    var b = el("section", "ficha__bloque");
    b.appendChild(el("h5", "ficha__titulo", titulo));
    cont.appendChild(b);
    return b;
  }

  // Tramo compacto con una sola unidad: "$2,5–3 M", "$800–900 mil", "sobre $3,5 M".
  function tramoTexto(t) {
    if (!t) return "—";
    if (t[1] == null) return "sobre " + pesosCorto(t[0]);
    var enM = t[0] >= 1e6;
    function n(v) { return enM ? fmtUno.format(v / 1e6).replace(",0", "") : fmtEntero.format(v / 1e3); }
    return "$" + n(t[0]) + "–" + n(t[1]) + (enM ? " M" : " mil");
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

  function graficoMedia(cont, p) {
    var caja = el("div", "ficha__grafico ficha__grafico--media");
    cont.appendChild(caja);
    var W = Math.max(280, caja.clientWidth || 600), H = 96, mx = 46, arriba = 22, abajo = 22;
    var v = p.media.anio, lo = Math.min.apply(null, v), hi = Math.max.apply(null, v);
    var pad = (hi - lo) * 0.15 || hi * 0.05; lo -= pad; hi += pad;
    function x(i) { return mx + i * (W - 2 * mx) / 4; }
    function y(val) { return arriba + (1 - (val - lo) / (hi - lo)) * (H - arriba - abajo); }
    var svg = svgEl("svg", { viewBox: "0 0 " + W + " " + H, role: "img",
      "aria-label": "Ingreso promedio del año 1 al 5: " + v.map(pesos).join(", ") + "." });
    svgEl("polyline", { points: v.map(function (val, i) { return x(i) + "," + y(val); }).join(" ") }, "f-media-linea", svg);
    var anomalos = {};
    datos.hitos.forEach(function (h) { anomalos[h.anio] = h.incluye_caida || h.incluye_rebote; });
    v.forEach(function (val, i) {
      svgEl("circle", { cx: x(i), cy: y(val), r: 4.5 }, "f-media-punto" + (i === 0 || i === 4 ? " f-media-punto--extremo" : "") + " g-anillo", svg);
      var et = svgEl("text", { x: x(i), y: H - 4, "text-anchor": "middle" }, "f-media-pct", svg);
      et.textContent = (i + 1) + "°" + (anomalos[i + 1] ? "*" : "");
      if (i === 0 || i === 4) {
        var t = svgEl("text", { x: x(i) + (i === 0 ? -8 : 8), y: y(val) + 4, "text-anchor": i === 0 ? "end" : "start" }, "f-media-texto", svg);
        t.textContent = pesosCorto(val);
      }
      if (i < 4) {
        var h = svgEl("text", { x: (x(i) + x(i + 1)) / 2, y: Math.min(y(val), y(v[i + 1])) - 8, "text-anchor": "middle" }, "f-media-pct", svg);
        h.textContent = pctSigno(p.media.pct_hitos[i]);
      }
    });
    caja.appendChild(svg);
    var conAnomalia = datos.hitos.filter(function (h) { return h.incluye_caida || h.incluye_rebote; })
      .map(function (h) { return h.anio + "°"; });
    var nota = "Cada año junta tres cohortes de titulados, todas medidas con los ingresos 2022–2024 (no son las mismas personas)." +
      (conAnomalia.length ? " * Incluye titulados de " + parametro("anio_caida_titulacion") + " o " + parametro("anio_rebote_titulacion") +
        ", años de titulación anómalos por la pandemia." : "") +
      (p.marcas.es_derecho ? " En Derecho las cohortes van corridas un año." : "");
    cont.appendChild(el("p", "ficha__nota", nota));
  }

  function graficoInstituciones(cont, progs, d, nacional) {
    var caja = el("div", "ficha__grafico ficha__grafico--franja");
    cont.appendChild(caja);
    var W = Math.max(280, caja.clientWidth || 600), H = 40, m = 10;
    var vals = progs.map(function (g) { return g.emp1; }).concat([nacional]);
    var lo = Math.min.apply(null, vals) - 2, hi = Math.max.apply(null, vals) + 2;
    function x(v) { return m + (v - lo) / (hi - lo) * (W - 2 * m); }
    var svg = svgEl("svg", { viewBox: "0 0 " + W + " " + H, role: "img",
      "aria-label": "Empleabilidad al primer año de " + progs.length + " instituciones: de " + pct(d.min) + " a " + pct(d.max) +
        "; institución típica " + pct(d.mediana) + "; cifra nacional " + pct(nacional) + "." });
    svgEl("line", { x1: x(d.mediana), x2: x(d.mediana), y1: 0, y2: 28 }, "f-tipica", svg);
    progs.forEach(function (g, i) {
      svgEl("circle", { cx: x(g.emp1), cy: 8 + (i % 3) * 6, r: 3.5 }, "f-inst g-anillo", svg);
    });
    svgEl("path", { d: "M" + x(nacional) + " 29 l-5 8 h10 z" }, "franja__nacional", svg);
    caja.appendChild(svg);
    cont.appendChild(el("p", "franja__leyenda", "Cada punto es una institución · línea: la institución típica (" + pct(d.mediana) + ") · ▲ cifra nacional (" + pct(nacional) + ")"));
  }

  function pintarFicha(p) {
    var art = document.getElementById("ficha-contenido");
    art.replaceChildren();

    // Encabezado
    art.appendChild(el("h4", "ficha__nombre", p.nombre)).id = "ficha-nombre";
    art.appendChild(el("p", "ficha__sub", p.tipo + " · " + nivelCorto(p) + " · " + p.area.cine13 +
      " (" + fmtEntero.format(p.area.pct_dominante) + " % de sus titulados)"));
    var t = el("div", "timbres");
    TIMBRES.forEach(function (def) { if (def.aplica(p)) t.appendChild(timbre(def)); });
    if (t.childNodes.length) art.appendChild(t);
    var avisos = avisosDe(p);
    if (avisos.length) {
      var caja = el("div", "ficha__avisos");
      avisos.forEach(function (f) { caja.appendChild(el("p", null, f)); });
      art.appendChild(caja);
    }

    // Sueldo típico
    var b1 = bloque(art, "Sueldo típico (P50), ingresos 2024");
    var dl = el("dl", "liq");
    var c1 = datos.cohortes.filter(function (c) { return c.indicador === "percentiles_anio_1"; })[0].cohortes[0];
    var c5 = datos.cohortes.filter(function (c) { return c.indicador === "percentiles_anio_5"; })[0].cohortes[0];
    var corr = p.marcas.es_derecho ? 1 : 0;
    liq(dl, "Al 1er año (titulados " + (c1 + corr) + ")", pesos(p.percentiles.anio_1.p50));
    liq(dl, "Al 5° año (titulados " + (c5 + corr) + ")", pesos(p.percentiles.anio_5.p50));
    liq(dl, "Crecimiento", pctSigno(p.percentiles.p50_pct_1_5) + " · " + pesosSigno(p.percentiles.p50_delta_1_5));
    if (p.posicion) {
      liq(dl, "Se compara con", nombreGrupo(p), true);
      liq(dl, "Sueldo de entrada en su grupo", CUARTO[p.posicion.cuartil_p50_anio_1 - 1], true);
      liq(dl, "Crecimiento en su grupo (%)", CUARTO[p.posicion.cuartil_p50_pct_1_5 - 1], true);
      liq(dl, "Cuadrante (en % / en pesos)", p.posicion.cuadrante_pct +
        (p.posicion.cambia_cuadrante ? " / " + p.posicion.cuadrante_pesos : " (igual en pesos)"), true);
    }
    b1.appendChild(dl);
    var lo = Math.floor(Math.min(p.percentiles.anio_1.p10, p.percentiles.anio_5.p10) / 250000) * 250000;
    var hi = Math.ceil(Math.max(p.percentiles.anio_1.p90, p.percentiles.anio_5.p90) / 250000) * 250000;
    var gm = el("div", "ficha__grafico");
    b1.appendChild(gm);
    gm.appendChild(svgMancuerna(p, lo, hi, Math.max(280, gm.clientWidth || 600)));
    b1.appendChild(el("p", "ficha__nota", "Punto: P50 · barra: mitad central (P25–P75) · línea: P10–P90 (" +
      pesosCorto(p.percentiles.anio_5.p10) + "–" + pesosCorto(p.percentiles.anio_5.p90) + " al 5° año). El P10 está truncado en el sueldo mínimo."));

    // Promedio por año
    graficoMedia(bloque(art, "Ingreso promedio por año desde la titulación"), p);

    // Empleabilidad
    var b3 = bloque(art, "Empleabilidad");
    b3.appendChild(el("p", "ficha__nota", datos.meta.rotulo_empleabilidad.replace(">=", "≥") + "."));
    var dl3 = el("dl", "liq");
    liq(dl3, "Nacional, 1er año", pct(p.empleabilidad_nacional[0]));
    liq(dl3, "Nacional, 2° año", pct(p.empleabilidad_nacional[1]));
    var d1 = p.dispersion.emp1;
    if (d1) liq(dl3, "Institución típica, 1er año (mediana de " + d1.n_inst + ")", pct(d1.mediana));
    b3.appendChild(dl3);
    if (d1) {
      // La explicación (población más amplia que las instituciones publicadas, A4) solo vale
      // cuando la cifra nacional queda sobre la institución típica; si no, se dice sin explicar.
      var dif = d1.nacional_menos_mediana;
      var frase = Math.abs(dif) < 1
        ? "La cifra nacional y la institución típica casi coinciden (" + fmtUno.format(Math.abs(dif)) + " puntos de diferencia)."
        : dif > 0
          ? "La cifra nacional queda " + fmtUno.format(dif) + " puntos sobre la institución típica: incluye titulados que no aparecen en ninguna institución publicada."
          : "La cifra nacional queda " + fmtUno.format(-dif) + " puntos bajo la institución típica: las instituciones más grandes de esta carrera tienen menor empleabilidad.";
      b3.appendChild(el("p", "ficha__nota", frase));
    }

    // Instituciones
    var progs = (programasPor[claveDe(p)] || []).slice().sort(function (a, b) { return b.emp1 - a.emp1 || colador.compare(a.institucion, b.institucion); });
    var b4 = bloque(art, "Instituciones que la ofrecen (" + progs.length + " publicadas en MiFuturo)");
    if (!progs.length) {
      b4.appendChild(el("p", "ficha__nota", "MiFuturo no publica esta carrera por institución."));
    } else {
      if (d1) graficoInstituciones(b4, progs, d1, p.empleabilidad_nacional[0]);
      else b4.appendChild(el("p", "ficha__nota", "Con menos de " + parametro("min_inst_dispersion") +
        " instituciones con el dato, no se comparan entre sí: se listan sin comparación."));
      var conTramo = !!p.dispersion.tramo;
      var tabla = el("table", "tabla tabla--tarjetas");
      tabla.appendChild(el("caption", "solo-lectores", "Instituciones que ofrecen " + p.nombre));
      var thead = el("thead"), trh = el("tr");
      var cols = ["Institución", "Empleab. 1er año"].concat(d1 ? ["vs. típica"] : [])
        .concat(["2° año", "Continuidad", conTramo ? "Tramo 4° año (vs. típica)" : "Tramo 4° año", "Acreditación"]);
      cols.forEach(function (c, i) { var th = el("th", i ? "num" : null, c); th.scope = "col"; trh.appendChild(th); });
      thead.appendChild(trh); tabla.appendChild(thead);
      var tb = el("tbody");
      progs.forEach(function (g) {
        var tr = el("tr");
        var celdas = [["Institución", g.institucion, "td--titulo"], ["Empleab. 1er año", pct(g.emp1), "num"]];
        if (d1) celdas.push(["vs. típica", g.desvio_emp1 == null ? "—" : (g.desvio_emp1 > 0 ? "+" : g.desvio_emp1 < 0 ? "−" : "") + fmtUno.format(Math.abs(g.desvio_emp1)) + " pts", "num"]);
        // Tramo y su comparación en una sola celda: con columnas separadas la tabla no cabía.
        celdas.push(["2° año", pct(g.emp2), "num"], ["Continuidad", pct(g.continuidad), "num"],
                    ["Tramo 4° año", tramoTexto(g.tramo) + (conTramo && g.tramo_vs_par ? " (" + g.tramo_vs_par + ")" : ""), "num"]);
        celdas.push(["Acreditación", g.acreditacion_anios ? g.acreditacion_anios + " años" : "no acreditada", "num"]);
        celdas.forEach(function (c) { var td = el("td", c[2], c[1]); td.setAttribute("data-rotulo", c[0]); tr.appendChild(td); });
        tb.appendChild(tr);
      });
      tabla.appendChild(tb);
      var envol = el("div", "tabla-desplazable");
      envol.appendChild(tabla);
      b4.appendChild(envol);
      b4.appendChild(el("p", "ficha__nota", "Continuidad: titulados que al año siguiente siguen estudiando; baja la empleabilidad, por eso van juntas. Tramo: ingreso promedio al 4° año de la institución" +
        (conTramo ? ", comparado con el tramo de la institución típica." : ".")));
    }

    // Quiénes se titulan
    var b5 = bloque(art, "Quiénes se titulan");
    var dl5 = el("dl", "liq");
    var tt = p.titulados_2024;
    if (tt.total) liq(dl5, "Titulados 2024", fmtEntero.format(tt.total) + (tt.mujeres != null ? " (" + fmtEntero.format(100 * tt.mujeres / tt.total) + " % mujeres)" : ""));
    var f30 = p.contexto.fuera30_rango;
    if (f30[0] != null) liq(dl5, "Con 30 años o más al titularse (recientes)", "entre " + pct(f30[0]) + " y " + pct(f30[1]));
    if (p.contexto.var_oferta_joven_pct != null) liq(dl5, "Titulados menores de 30, hace cinco años → recientes", pctSigno(p.contexto.var_oferta_joven_pct));
    if (p.duracion.formal != null) liq(dl5, "Duración formal / real (semestres)", fmtUno.format(p.duracion.formal) + " / " + (p.duracion.real != null ? fmtUno.format(p.duracion.real) : "—"));
    b5.appendChild(dl5);
    b5.appendChild(el("p", "ficha__nota", "Fuente: titulaciones SIES de todas las instituciones de este tipo. El rango de edad existe porque el SIES agrupa de 30 a 34 años."));
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

  function abrirFicha(p, desplazar) {
    mostrarFicha(p);
    var direccion = "#carrera=" + encodeURIComponent(claveDe(p));
    if (desplazar) {
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
    nav.actual = { n: 0, clave: p0 ? claveDe(p0) : null, origen: null };
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
      if (nav.conHistorial && actual.n > 0) history.back();   // el popstate hace el regreso
      else { volverA(actual.origen, actual.n); mostrarVolver(null); }
    });

    // Al cambiar el "#", el navegador hace su propio paso de scroll DESPUÉS del popstate y corta
    // una animación iniciada aquí (medido: la ficha se pintaba pero la página no se movía). Por eso
    // el desplazamiento se posterga una vuelta del bucle de eventos.
    function despues(fn) { window.setTimeout(fn, 0); }

    window.addEventListener("popstate", function (e) {
      var dejado = nav.actual, destino = e.state, p = desdeDireccion();
      if (!destino) {   // dirección escrita a mano: se abre esa ficha, sin regreso
        nav.n += 1;
        nav.actual = { n: nav.n, clave: p ? claveDe(p) : null, origen: null };
        try { history.replaceState(nav.actual, "", location.href); } catch (err) { /* sin historial */ }
        mostrarVolver(null);
        if (p) { mostrarFicha(p); despues(irAFicha); }
        return;
      }
      nav.actual = destino;
      if (p) mostrarFicha(p);
      mostrarVolver(destino.origen);
      if (dejado && destino.n < dejado.n) {   // atrás
        if (dejado.origen) despues(function () { volverA(dejado.origen, dejado.n); });   // de una ficha a su origen
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
  function marcarParteActiva() {
    if (!window.IntersectionObserver) return;
    var enlaces = document.querySelectorAll(".barra__partes a");
    var observador = new IntersectionObserver(function (entradas) {
      entradas.forEach(function (en) {
        if (!en.isIntersecting) return;
        enlaces.forEach(function (a) {
          if (a.getAttribute("data-parte") === en.target.id) a.setAttribute("aria-current", "true");
          else a.removeAttribute("aria-current");
        });
      });
    }, { rootMargin: "-45% 0px -50% 0px" });   // la parte que cruza el centro de la pantalla
    document.querySelectorAll(".parte").forEach(function (s) { observador.observe(s); });
    // Sobre la portada no hay parte activa.
    new IntersectionObserver(function (entradas) {
      if (entradas[0].isIntersecting) enlaces.forEach(function (a) { a.removeAttribute("aria-current"); });
    }, { rootMargin: "-45% 0px -50% 0px" }).observe(document.getElementById("inicio"));
  }

  function buscarPar(texto) {
    var exacto = pares.filter(function (p) { return etiquetaPar(p) === texto; })[0];
    if (exacto) return exacto;
    var n = normalizar(texto.trim());
    if (!n) return null;
    // Sin tildes; ante varias coincidencias, la comparable con más titulados.
    var candidatos = pares.filter(function (p) { return normalizar(etiquetaPar(p)).indexOf(n) >= 0; });
    return maximoPor(candidatos, function (p) { return (p.marcas.representativo ? 1e9 : 0) + p.conteos.peso; });
  }

  function desdeDireccion() {
    var m = /#carrera=([^&]+)/.exec(location.hash);
    if (!m) return null;
    // Un enlace cortado al compartirlo trae un "%" incompleto: decodeURIComponent lanza URIError
    // y, sin el try, el arranque se detenía y dejaba vacías la ficha y las secciones siguientes.
    try { return parPorClave[decodeURIComponent(m[1])] || null; } catch (e) { return null; }
  }

  function prepararFicha() {
    var lista = document.getElementById("ficha-opciones");
    pares.slice().sort(function (a, b) { return colador.compare(etiquetaPar(a), etiquetaPar(b)); })
      .forEach(function (p) { var op = el("option"); op.value = etiquetaPar(p); lista.appendChild(op); });
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
    // Ficha inicial: la de la dirección, o por regla la comparable con más titulados.
    var inicial = desdeDireccion() || maximoPor(comparables, function (p) { return p.conteos.peso; });
    pintarFicha(inicial);
    document.getElementById("ficha-texto").value = etiquetaPar(inicial);
    if (desdeDireccion()) document.getElementById("ficha").scrollIntoView();
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

  // El detalle del control qa trae las cifras en texto con punto decimal: "empleabilidad 1er
  // año 1.65 pp; tramo 4° año (punto medio) 6.2 %". Se buscan por su contexto (un regex de
  // "cualquier número" tomaría el 1 de "1er" y el 4 de "4°").
  function brechaDe(texto) {
    var e = /([-\d.]+) pp/.exec(texto), t = /\(punto medio\) ([-\d.]+) %/.exec(texto);
    return e && t ? [Number(e[1]), Number(t[1])] : [];
  }

  function pintarLimites() {
    var q = datos.que_no_dice, ul = document.getElementById("limites");
    function item(titulo, partes) { var li = el("li"); textoConCifras(li, titulo, partes); ul.appendChild(li); }
    var anomalos = q.hitos_con_anomalia.map(function (a) { return a + "°"; });
    var atipSalud = pares.filter(function (p) { return p.marcas.cohorte_atipica && p.area.cine13 === "Salud y Bienestar"; }).length;
    var brecha = brechaDe(q.brecha_nacional_instituciones);

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
    if (brecha.length >= 2) {
      item("La cifra nacional no es el promedio de las instituciones.", ["Queda ", fmtUno.format(brecha[0]) + " puntos",
        " sobre ellas en empleabilidad al primer año y ", fmtUno.format(brecha[1]) + " %",
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
    document.getElementById("nota-carreras").textContent =
      "P50: sueldo bruto mensual de la persona del medio (la mitad gana menos). Empleabilidad: " +
      datos.meta.rotulo_empleabilidad + " (cifra nacional de MiFuturo). Instituciones: las que titularon en la carrera en ambos periodos comparados.";
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
  prepararCuadrantes();
  pintarCuadrantes(false);
  prepararMancuerna();
  pintarMancuerna();
  pintarSegmentos();
  pintarLeyenda();
  prepararFiltros();
  pintarCarreras();
  prepararFicha();
  marcarParteActiva();
  pintarLimites();
  pintarMetodo();
  pintarControles();
  pintarNotas();
})();
