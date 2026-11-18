# 00 · Alcance de la auditoría (Dieter Rams, skill design-is)

- **Qué se audita:** la navegación completa de `docs/index.html` (portada, Parte I «Lo que encontré», Parte II «Busca tu carrera», Parte III «Cómo leerlo»), servida en local en 127.0.0.1:8765 a 1366 px y 390 px. Fuentes: `src/Web/plantilla.html`, `src/Web/app.js`, `src/Web/estilos.css`, `docs/datos.json` y la base `carreras_sueldos`.
- **Usuario principal:** una persona sin formación estadística (estudiante, apoderado o titulado) que quiere saber cuánto se gana en una carrera y si el promedio la representa.
- **Tarea principal:** entender en menos de un minuto las tres ideas centrales y llegar a la ficha de su carrera.
- **Restricciones:** HTML/CSS/JS/SVG sin dependencias. Toda cifra sale del SQL con un control qa. Técnicas y profesionales no se mezclan en una misma mediana. Nunca se presenta como «evolución»: son dos cohortes distintas.
- **Observaciones del usuario (entrada):**
  1. «Lo que encontré» es confuso; debe ser específico y resumido, para lectores no expertos.
  2. Falta un gráfico del total de titulados que muestre el universo del análisis.
- **Método:** la evidencia se reunió en esta sesión con Puppeteer, grep y psql, sin subagentes; el usuario no los pidió.
