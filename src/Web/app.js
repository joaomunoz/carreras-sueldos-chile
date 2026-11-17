/* src/Web/app.js
 *
 * Lógica de la página. Los datos vienen incrustados en <script id="datos"> por
 * src/Web/construir.py (desde docs/datos.json): nada se pide a la red, así la página funciona
 * con doble clic. Ninguna cifra del texto se escribe a mano: todas se leen de `datos`.
 */
(function () {
  "use strict";

  var datos = JSON.parse(document.getElementById("datos").textContent);

  // ------------------------------------------------------------- formato (es-CL)
  var fmtEntero = new Intl.NumberFormat("es-CL", { maximumFractionDigits: 0 });
  var fmtPct = new Intl.NumberFormat("es-CL", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

  function pct(valor) { return valor == null ? "—" : fmtPct.format(valor) + " %"; }

  function el(etiqueta, clase, texto) {
    var nodo = document.createElement(etiqueta);
    if (clase) nodo.className = clase;
    if (texto != null) nodo.textContent = texto;
    return nodo;
  }

  function timbre(texto, descripcion) {
    var nodo = el("span", "timbre", texto);
    if (descripcion) nodo.title = descripcion;
    return nodo;
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

  function parametro(nombre) {
    for (var i = 0; i < datos.parametros.length; i++) {
      if (datos.parametros[i].nombre === nombre) return datos.parametros[i].valor;
    }
    throw new Error("Parámetro inexistente en datos.json: " + nombre);
  }

  // ------------------------------------------------------------- tabla de segmentos
  function pintarSegmentos() {
    var cuerpo = document.querySelector("#tabla-segmentos tbody");
    var umbralCobertura = fmtEntero.format(parametro("max_cobertura_baja") * 100) + " %";
    datos.segmentos.forEach(function (s) {
      var tr = el("tr");
      tr.appendChild(el("td", null, s.tipo));
      tr.appendChild(el("td", null, s.nivel.replace("Carreras ", "")));
      tr.appendChild(el("td", "num", fmtEntero.format(s.pares)));
      tr.appendChild(el("td", "num", fmtEntero.format(s.representativos)));
      tr.appendChild(el("td", "num", pct(s.cobertura[0])));
      tr.appendChild(el("td", "num", pct(s.cobertura[1])));
      var adv = el("td");
      if (s.baja_cobertura) {
        adv.appendChild(timbre("Baja cobertura",
          "MiFuturo publica programas que reúnen menos del " + umbralCobertura + " de los titulados de este grupo"));
      }
      tr.appendChild(adv);
      cuerpo.appendChild(tr);
    });
  }

  // ------------------------------------------------------------- pie
  function pintarPie() {
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
  pintarSegmentos();
  pintarPie();
})();
