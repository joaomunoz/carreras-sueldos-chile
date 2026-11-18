# 01 · Evidencia

## E1 · Estructura
- La página tiene 44 elementos interactivos (a, button, input, [tabindex=0]) y mide 10.771 px de alto a 1366 px y 15.353 px a 390 px.
- Palabras por parte: I = 887, II = 1.019, III = 704 (2.763 en total).
- **Las tres ideas se dicen tres veces:** en las tarjetas (`app.js:260-325`), en los h3 de los gráficos (`plantilla.html:68,94`, por ejemplo «9 de 210 carreras ganan menos…») y en el cierre «Al comparar carreras» (`plantilla.html:143-147`).
- La tarjeta (c) trae un minigráfico de franja (`app.js:310-314`) que repite la ficha de Trabajo Social.
- Existe el enlace para saltar al contenido.

## E2 · Visual (capturas en scratchpad: aud_hall_1366.png y aud_hall_390.png)
- Hay un sistema visible: tokens en `:root`, modo oscuro y una cifra grande en monoespaciada.
- El texto de la tarjeta mezcla monoespaciada en negrita («32,3 %», «$891.077») con texto corrido, lo que hace la lectura entrecortada.
- Las tarjetas miden 84, 54 y 88 palabras. La cifra grande «10» y «19» no tiene unidad visible hasta leer el rótulo.
- Estados: el foco es visible y la ficha sin gráfico tiene un mensaje (Kinesiología IP). No hay estado sin JavaScript: la página queda vacía.

## E3 · Textos y honestidad
- **Jerga visible para el público general** (conteo en el texto renderizado):
  - «peine» ×1, en la tarjeta (a): «Verlas en el peine ↓» (`app.js:279`), un nombre interno que el lector nunca ve rotulado;
  - «pp» ×8, «P50» ×3, «mediana» ×5, «cuadrante» ×5, «ponderada» ×3, «cohorte» ×9.
- **Tarjeta (a):** «En 6 de ellas, quienes tienen 30 años o más pasan de 32,3 % a 55,6 % de los titulados (mediana de esas 6)…». Combina tres conceptos (subconjunto, edad, mediana) en una frase.
- **Tarjeta (b):** el rótulo dice «cambian de cuadrante si el crecimiento se mide en pesos». Usa «cuadrante» antes de que el lector haya visto el gráfico de cuadrantes.
- **Tarjeta (c):** «…difieren 15 puntos o más en empleabilidad, aun sin el cuarto más alto ni el más bajo». Es la definición de rango intercuartil en palabras, pero se lee como un enigma.
- **El encabezado «Parece que» va tachado.** El tachado dificulta leer justo la frase que hay que leer primero.
- **Rótulo que no coincide con lo que hace:** «Busca tu carrera y tu institución →» (`plantilla.html:146`). No hay un buscador de institución: la institución se encuentra dentro de la tabla de la ficha.
- **No hay inflaciones ni patrones oscuros.** Los límites («No sigue a las mismas personas») son visibles en la portada.

## E4 · Peso
- El HTML pesa 1,43 MB, con `datos.json`, fuentes y JS embebidos. Hay 1 petición más el favicon.
- No hay animaciones en reposo y se respeta `prefers-reduced-motion`. El modo oscuro está implementado.

## E5 · Universo de titulados (base de datos, para el gráfico pedido)
- **SIES, titulaciones por año** (`modelo.titulacion`):
  - 2017: 206.554 · 2018: 209.022 · 2019: 201.142 · 2020: 160.891 (caída por pandemia);
  - 2021: 228.693 · 2022: 225.942 · 2023: 231.203 · 2024: 226.341 · 2025: 238.716.
- **Ventana del 1er año (titulados 2021–2023):**
  - 687.231 titulaciones SIES y 621.778 en programas publicados por MiFuturo (90,5 %), según `analytics.segmento`;
  - 27,3 % de titulados de 30 años o más y 57,1 % de mujeres.
- **Ventana del 5° año (titulados 2017–2019):**
  - 615.246 titulaciones SIES y 520.073 publicadas (84,5 %);
  - 25,1 % de 30 años o más y 56,6 % de mujeres.
- **Las 210 carreras comparables:**
  - abarcan 638.348 titulaciones en la ventana del 1er año (técnicas 231.114 y profesionales 407.234) y 569.372 en la del 5° año;
  - se calcularon con `analytics.par.tit_ventana_*`, que cuenta todas las instituciones con oferta y no solo las publicadas, así que **no es un subconjunto de las 621.778**.
- **La web no muestra hoy el volumen de titulados.** Solo publica la cobertura en % (Parte III).
- **Precaución:** el SIES cuenta titulaciones, no personas (una persona puede tener dos títulos).
