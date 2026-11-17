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

  function mediana(valores) {
    var v = valores.slice().sort(function (a, b) { return a - b; });
    var m = Math.floor(v.length / 2);
    return v.length % 2 ? v[m] : (v[m - 1] + v[m]) / 2;
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

  // ------------------------------------------------------------- cifras de portada
  function pintarCifras() {
    var qa = datos.qa.resumen;
    var aprobados = qa.OK || 0;
    var exentos = qa.EXENTO || 0;
    var qnd = datos.que_no_dice;
    var filas = [
      ["Carreras por tipo de institución", fmtEntero.format(qnd.pares_total)],
      ["Comparables entre sí", fmtEntero.format(qnd.pares_total - qnd.pares_no_representativos)],
      ["Controles de calidad aprobados" + (exentos ? " (" + exentos + " no aplican)" : ""), fmtEntero.format(aprobados)],
      ["Ingresos en", "pesos de septiembre de 2025", true]
    ];
    var dl = document.getElementById("cifras");
    filas.forEach(function (f) {
      var bloque = el("div");
      bloque.appendChild(el("dt", null, f[0]));
      bloque.appendChild(el("dd", f[2] ? "cifras__texto" : null, f[1]));
      dl.appendChild(bloque);
    });
  }

  // ------------------------------------------------------------- hallazgos
  // Texto con cifras en <strong>: partes alternan texto y cifra ([texto, cifra, texto, ...]).
  function parrafo(partes) {
    var p = el("p");
    partes.forEach(function (parte, i) {
      p.appendChild(i % 2 ? el("strong", null, parte) : document.createTextNode(parte));
    });
    return p;
  }

  function hallazgo(parece, peroNodos) {
    var li = el("li", "hallazgo");
    var izq = el("div", "hallazgo__parece");
    izq.appendChild(el("p", "hallazgo__rotulo", "Parece que"));
    izq.appendChild(el("p", null, parece));
    var der = el("div", "hallazgo__pero");
    der.appendChild(el("p", "hallazgo__rotulo", "Pero"));
    peroNodos.forEach(function (n) { der.appendChild(n); });
    li.appendChild(izq);
    li.appendChild(der);
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

  function pintarHallazgos() {
    var ul = document.getElementById("hallazgos");

    // (a) Progresión típica y su trampa de composición por edad.
    var crecimientos = comparables.map(function (p) { return p.percentiles.p50_pct_1_5; });
    var negativos = comparables.filter(function (p) { return p.percentiles.p50_pct_1_5 < 0; });
    var conEdad = negativos.filter(function (p) { return p.marcas.composicion_edad; });
    // Sin carreras negativas el hallazgo (a) no aplica tal cual: se omite, sin cortar los demás.
    if (negativos.length) {
    var edad5 = mediana(negativos.map(function (p) { return p.contexto.mayores30_cohorte_p5[1]; }));
    var edad1 = mediana(negativos.map(function (p) { return p.contexto.mayores30_cohorte_p1[1]; }));
    ul.appendChild(hallazgo("Al quinto año siempre se gana más que al primero.", [
      parrafo(["En ", fmtEntero.format(negativos.length), " de las ", fmtEntero.format(comparables.length),
               " carreras comparables, el sueldo típico del quinto año es menor que el del primero. No es que bajen los sueldos: ambos se miden con los ingresos de 2024."]),
      parrafo(["En ", fmtEntero.format(conEdad.length), " de ellas, los titulados recientes son mucho mayores: quienes tienen 30 años o más pasan de ",
               fmtEntero.format(edad5) + " %", " a ", fmtEntero.format(edad1) + " %",
               ". Muchos ya trabajaban antes de titularse. La carrera típica sube ",
               pctSigno(mediana(crecimientos)), "."])
    ]));
    }

    // (b) El % engaña cuando la base es baja. Ejemplo por regla: el mayor % entre las carreras
    // cuyo aumento en pesos queda al menos un 20 % bajo la mediana de su referencia. Sin ese
    // margen el ejemplo puede ser la propia mediana (empate) o quedar a unos pocos miles: no
    // ilustraría nada.
    function refDeltaDe(p) {
      return datos.referencias.filter(function (r) {
        return r.grupo === p.marcas.grupo_referencia && r.metrica === "p50_delta_1_5";
      })[0];
    }
    var cambian = comparables.filter(function (p) { return p.posicion.cambia_cuadrante; });
    var pctAlto = cambian.filter(function (p) {
      return p.posicion.cuadrante_pct.indexOf("progresa más") >= 0
        && p.percentiles.p50_delta_1_5 <= 0.8 * refDeltaDe(p).q50;
    });
    var ej = maximoPor(pctAlto, function (p) { return p.percentiles.p50_pct_1_5; });
    // Con otros datos podría no haber ejemplo: se omite el hallazgo en vez de romper la página.
    if (ej) {
    var refDelta = refDeltaDe(ej);
    ul.appendChild(hallazgo("Crecer más en porcentaje es crecer más.", [
      parrafo(["", fmtEntero.format(cambian.length), " carreras cambian de lugar si el crecimiento se mide en pesos en vez de porcentaje."]),
      parrafo([ej.nombre + " (" + ej.tipo + ") sube ", pctSigno(ej.percentiles.p50_pct_1_5), ", pero parte de ",
               pesos(ej.percentiles.anio_1.p50), ": son ", pesosSigno(ej.percentiles.p50_delta_1_5),
               ", menos que el aumento típico de su grupo (", pesosSigno(refDelta.q50), ")."])
    ]));
    }

    // (c) El promedio nacional esconde diferencias entre instituciones. Ejemplo por regla: la
    // carrera engañosa con mayor IQR entre las que tienen al menos 20 instituciones (un ejemplo
    // con pocas instituciones sería anecdótico).
    var enganosos = pares.filter(function (p) { return p.marcas.promedio_enganoso; });
    var ejc = maximoPor(enganosos.filter(function (p) { return p.dispersion.emp1.n_inst >= 20; }),
                        function (p) { return p.dispersion.emp1.iqr; });
    if (!ejc) return;
    var d = ejc.dispersion.emp1;
    var nodosC = [
      parrafo(["En ", fmtEntero.format(enganosos.length), " carreras las instituciones difieren ",
               fmtEntero.format(parametro("min_iqr_enganoso")) + " puntos o más",
               " en empleabilidad, aun dejando fuera al cuarto más alto y al cuarto más bajo de ellas."]),
      parrafo([ejc.nombre + " (" + ejc.tipo + ", " + d.n_inst + " instituciones) va de ", pct(d.min), " a ", pct(d.max),
               "; la cifra nacional es ", pct(ejc.empleabilidad_nacional[0]), "."]),
      franja(d, ejc.empleabilidad_nacional[0])
    ];
    ul.appendChild(hallazgo("El promedio nacional describe a la carrera.", nodosC));
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
    var cuerpo = document.querySelector("#tabla-carreras tbody");
    var fragmento = document.createDocumentFragment();
    lista.forEach(function (p) {
      var tr = el("tr");
      var nombre = el("div");
      nombre.appendChild(el("span", "carrera__nombre", p.nombre));
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
    document.getElementById("conteo").textContent = lista.length
      ? "Mostrando " + fmtEntero.format(lista.length) + " de " + fmtEntero.format(pares.length) + " carreras."
      : "Ninguna carrera coincide con estos filtros. Prueba quitar alguno o desmarcar «Solo comparables».";
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
  // Las carreras comparables, cada una una línea del P50 del 1er año al del 5°, ordenadas por
  // el P50 del 1er año. Violeta = marca de composición por edad (en cualquier dirección).
  var peine = { lista: [], activo: -1 };

  function pintarPeine() {
    var lienzo = document.getElementById("peine-lienzo");
    var figura = document.getElementById("peine");
    var caja = document.getElementById("peine-tooltip");
    var lista = comparables.slice().sort(function (a, b) {
      return a.percentiles.anio_1.p50 - b.percentiles.anio_1.p50 || colador.compare(a.nombre, b.nombre);
    });
    peine.lista = lista;

    var bajan = lista.filter(function (p) { return p.percentiles.p50_pct_1_5 < 0; }).length;
    var conEdad = lista.filter(function (p) { return p.marcas.composicion_edad; }).length;
    document.getElementById("peine-bajada").textContent =
      "Las " + fmtEntero.format(lista.length) + " carreras comparables. Cada línea va del sueldo típico de quienes se titularon hace un año al de quienes se titularon hace cinco. Casi todas suben; " +
      fmtEntero.format(bajan) + " bajan. En violeta, las " + fmtEntero.format(conEdad) +
      " en que los titulados recientes son mucho mayores que los de hace cinco años: ahí la comparación mezcla edades.";

    var W = lienzo.clientWidth || 800;
    var angosto = W < 600;
    var H = angosto ? 260 : 340;
    var m = { izq: angosto ? 44 : 56, der: 8, arriba: 22, abajo: 8 };
    var n = lista.length;
    var paso = (W - m.izq - m.der) / n;
    var valores = [];
    lista.forEach(function (p) { valores.push(p.percentiles.anio_1.p50, p.percentiles.anio_5.p50); });
    var lo = Math.min.apply(null, valores) * 0.94, hi = Math.max.apply(null, valores) * 1.03;
    function x(i) { return m.izq + paso * (i + 0.5); }
    function y(v) { return m.arriba + (1 - (v - lo) / (hi - lo)) * (H - m.arriba - m.abajo); }

    var svg = svgEl("svg", { viewBox: "0 0 " + W + " " + H, height: H, role: "img",
      "aria-label": n + " carreras comparables. En " + bajan + " el sueldo típico del 5° año es menor que el del 1er año." });
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
      t.textContent = p.nombre + (p.tipo !== "Universidad" ? " (" + p.tipo + ")" : "") + " " + pctSigno(p.percentiles.p50_pct_1_5);
      var fin = m.izq + 8 + t.getComputedTextLength() + 6;
      var yDot = k === 0 ? Math.min(y(p.percentiles.anio_1.p50), y(p.percentiles.anio_5.p50))
                         : Math.max(y(p.percentiles.anio_1.p50), y(p.percentiles.anio_5.p50));
      svgEl("polyline", { points: fin + "," + (yRot - 4) + " " + (x(i) - 4) + "," + (yRot - 4) + " " + x(i) + "," + (yDot + (k === 0 ? -4 : 4)),
                          fill: "none" }, "g-guia", svg);
    });
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
    lienzo.onkeydown = function (e) {
      if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
        e.preventDefault();
        var i = peine.activo < 0 ? 0 : peine.activo + (e.key === "ArrowRight" ? 1 : -1);
        mostrar(Math.max(0, Math.min(n - 1, i)));
      } else if (e.key === "Escape") { mostrar(-1); }
    };
    lienzo.onblur = function () { mostrar(-1); };
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
  }

  function pintarMancuerna() {
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
      var svg = svgEl("svg", { viewBox: "0 0 " + anchoBarra + " 36", preserveAspectRatio: "none", "aria-hidden": "true" });
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
      cont.appendChild(svg);
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
      boton.textContent = oscuro ? "Modo claro" : "Modo oscuro";
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
  pintarCifras();
  pintarPeine();
  alCambiarAncho(document.getElementById("peine-lienzo"), pintarPeine);
  pintarHallazgos();
  prepararMancuerna();
  pintarMancuerna();
  pintarSegmentos();
  pintarLeyenda();
  prepararFiltros();
  pintarCarreras();
  pintarNotas();
})();
