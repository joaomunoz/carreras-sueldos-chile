# 04 · Prompt de traspaso

```
/make-plan Redesign la Parte I («Lo que encontré») de docs/index.html (proyecto carreras_sueldos). Current design failed audit at 18/30 with critical gaps in principles #4 understandable (1), #10 as little design as possible (1), #9 environmentally friendly (1).

Verdict paragraph (quoted from 03-verdict.md):
> Con 18/30 y comprensibilidad (#4) en 1, la regla obliga a REDISEÑAR: la Parte I cuenta tres veces las mismas ideas en un lenguaje de analista y no muestra a quiénes cubre el análisis. El rediseño es de la estructura de lectura de la Parte I y de los textos, no de toda la web.

Why redesign and not refine: el principio #4 (comprensible), que sostiene la página, sacó 1 y el total quedó bajo 20; el problema es la estructura de la Parte I (la misma idea en tres lugares), no un detalle de estilo.

Preserve from current design:
- La ficha de carrera completa (src/Web/app.js, pintarFicha, con su gráfico de instituciones interactivo).
- El pipeline SQL → datos.json con controles qa (src/Analisis/sql/analytics/06_hallazgos.sql, 07_exportacion.sql); toda cifra nueva sale del SQL con su control qa.
- Los tokens de color y tipografía en src/Web/estilos.css (:root y modo oscuro).
- Los gráficos de líneas (#peine) y de cuadrantes (#cuadrantes), con sus títulos y la navegación por teclado.
- Las reglas: técnicas y profesionales no se mezclan en una mediana; nunca hablar de «evolución» (son cohortes distintas).

Discard:
- Las tarjetas de 54 a 88 palabras con jerga («peine», «cuadrante», «pp», «mediana de esas 6», «aun sin el cuarto más alto ni el más bajo»). Evidence: src/Web/app.js:260-325. Caused failure on principle #4.
- Las tres ideas repetidas en las tarjetas, en los h3 de los gráficos (plantilla.html:68,94) y en el cierre «Al comparar carreras» (plantilla.html:143-147). Caused failure on principle #10.
- La franja de la tarjeta (c), que duplica la ficha. Evidence: app.js:310-314. Caused failure on principle #10.
- El rótulo «Busca tu carrera y tu institución», que promete un buscador de institución inexistente. Evidence: plantilla.html:146. Caused failure on principle #6.

Top moves from the audit (verbatim):
1. #4 — comprensible: reescribir las 3 tarjetas en ≤ 30 palabras cada una (una frase de hallazgo con sujeto, cifra y unidad; una frase de ejemplo concreto; una acción con el nombre visible del destino); sin «peine», «cuadrante», «pp», «mediana» ni «intercuartil». Evidence: app.js:260-325.
2. #10 — lo menos posible: cada idea una sola vez; los h3 de los gráficos dicen qué se ve; el cierre se vuelve consejos sin cifras o se elimina; quitar la franja de la tarjeta (c). Evidence: plantilla.html:68,94,143-147.
3. #2/#4 — agregar «A quiénes mira este análisis»: columnas de titulaciones SIES por año 2017–2025, apiladas en técnicas y profesionales, con las ventanas 2017–2019 (5° año) y 2021–2023 (1er año) resaltadas, 2020 anotado (pandemia) y 2024–2025 en gris; una línea con el total en las 210 carreras comparables. Datos: 2021–2023 = 687.231 titulaciones SIES, 2017–2019 = 615.246; las 210 comparables suman 638.348 (1er año) y 569.372 (5° año) según analytics.par.tit_ventana_*, que no es un subconjunto de lo publicado por MiFuturo (621.778): definir en SQL un embudo coherente con su control qa antes de dibujarlo. Aclarar que son titulaciones, no personas.
4. #6 — honesto: «Busca tu carrera →» en vez de «…y tu institución». Evidence: plantilla.html:146.
5. #3/#5 — en las tarjetas, la idea ingenua sin tachado; las cifras en la tipografía del texto; la cifra grande con su unidad.

Redesign principles in priority order:
1. #4 Understandable — una persona sin formación estadística repite cada hallazgo con sus palabras tras leerlo una vez.
2. #10 As little design as possible — cada idea aparece una vez; la Parte I baja de 887 a ≤ 450 palabras.
3. #2 Useful — el lector sabe a cuántos titulados y de qué años cubre el análisis antes de leer los hallazgos.

Deliverables for the plan:
- Nueva arquitectura de la Parte I: universo → 3 hallazgos → gráficos de respaldo → acceso a la ficha.
- Textos finales de las 3 tarjetas y de los h3, comparados lado a lado con los actuales.
- SQL nuevo para la serie anual y el embudo, con su control qa; exportación a datos.json.
- Gráfico de titulados (rúbrica Google + McCandless: título de acción con subtítulo, rótulos directos, tabla accesible, modo claro y oscuro).
- Lista de estados: sin JS, foco, 320 px.
- Verificación con Puppeteer a 1366, 390 y 320 px, en claro y oscuro, sin desborde.

Anti-patterns to guard against:
- Cambiar solo el estilo de las tarjetas y mantener la misma estructura.
- Un embudo con cifras que no cuadran entre sí (638.348 > 621.778).
- Sumar técnicas y profesionales en una mediana; está permitido en los conteos de titulados, no en sueldos.
- Llamar «evolución» a la serie de titulados junto a los sueldos.
```
