# Cambios en las cifras y el método

Correcciones y cambios de método que alteraron cifras ya publicadas, del más nuevo al más antiguo. Los cambios de diseño y de código están en el historial de git.

## 19-11-26 · Cambio de método

Derecho se mide ahora con titulados de un año **antes** que las demás carreras (2020–2022 en vez de 2021–2023), como lo publica MiFuturo; antes se corría un año después ([ADR-003](src/BD/ADR-003-cohortes-derecho.md)). Cambian el peso y los datos de contexto de Derecho y la carrera del medio en el aumento en pesos de las profesionales universitarias (de Odontología a Publicidad); los hallazgos no cambian. Su ventana del 5° año (2016–2018) empieza antes que el SIES: en el peso y en la comparación de titulados jóvenes se lleva a tres años; los conteos de títulos quedan reales.

## 18-11-26 · Cambio de método

Los grupos de comparación usan ahora el área del conocimiento de MiFuturo en vez del área CINE ([ADR-002](src/BD/ADR-002-area-de-referencia.md)): quien busca una carrera piensa por interés, y la CINE separaba, por ejemplo, Telecomunicaciones de Informática. Siguen siendo 14 grupos con área propia; 27 carreras ganan uno y 17 pasan a compararse con todas las de su tipo y nivel. El hallazgo 2 pasó de 10 a 13 carreras profesionales; su ejemplo, Ingeniería en Alimentos, conserva sus cifras.

## 17-11-26 · Corrección

El hallazgo 1 daba una sola mediana de crecimiento para las 210 carreras comparables (+29,3 %), que mezclaba técnicas y profesionales y no describía a ninguno de los dos niveles. Ahora se informa por nivel.

## 16-11-26 · Corrección

La versión anterior decía que, en las carreras con cambio de edad, los titulados de 30 años o más pasaban de 28 % a 55 %. Esa mediana se calculaba sobre las 9 carreras que bajan y no sobre las 7 que nombraba la frase; la cifra correcta en esa versión era 32,5 % → 56,6 % (cambió después con los datos y el método actuales). Desde esta versión, las cifras de los hallazgos se calculan en SQL y tienen sus propios controles de calidad.
