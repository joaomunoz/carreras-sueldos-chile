# 03 · Veredicto: REDESIGN (rediseño), acotado a la arquitectura de la Parte I

Con 18/30 y comprensibilidad (#4) en 1, la regla obliga a REDISEÑAR: la Parte I cuenta tres veces las mismas ideas en un lenguaje de analista, y no muestra a quiénes cubre el análisis.

**Alcance.** El rediseño es de la estructura de lectura de la Parte I y de los textos, no de toda la web. Se conservan la ficha, el modelo de datos, el pipeline SQL con qa, los tokens visuales y los gráficos de líneas y de cuadrantes.

## Movimientos de mayor impacto
1. **#4, comprensible.** Reescribir las 3 tarjetas en ≤ 30 palabras cada una:
   - una frase de hallazgo con sujeto, cifra y unidad;
   - una frase de ejemplo concreto;
   - una acción con el nombre visible del destino.

   Quitar «peine», «cuadrante», «pp», «mediana» e «intercuartil» de las tarjetas. Evidencia: E3, `app.js:260-325`.
2. **#10, lo menos posible.** Decir cada idea una sola vez:
   - las tarjetas son el resumen;
   - los h3 de los gráficos dicen qué se ve, no repiten la cifra;
   - el cierre «Al comparar carreras» se convierte en consejos sin repetir cifras, o se elimina;
   - se quita la franja de la tarjeta (c).

   Evidencia: E1.
3. **#2, útil, y #4.** Agregar «A quiénes mira este análisis», un gráfico de titulaciones por año 2017–2025, separado en técnicas y profesionales, con las dos ventanas (2017–2019 y 2021–2023) resaltadas, 2020 anotado y 2024–2025 en gris. Debajo, una línea con el total incluido. Evidencia: E5.
4. **#6, honesto.** Cambiar «Busca tu carrera y tu institución» por «Busca tu carrera →», o implementar la búsqueda de institución. Evidencia: `plantilla.html:146`.
5. **#3 y #5.** En las tarjetas:
   - la idea ingenua se lee sin tachado (se marca con un rótulo, no con `<s>`);
   - las cifras van en la tipografía del texto, no en monoespaciada;
   - la cifra grande lleva su unidad («7 de 85 carreras técnicas»).
