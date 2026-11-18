# ADR-002: Área de referencia de los grupos de comparación

**Fecha:** 2026-11-18
**Estado:** Aceptado (reemplaza el uso del área CINE para formar grupos)
**Archivos:** `src/Analisis/sql/analytics/01_par.sql` (columna `analytics.par.area`, celda y control `area_mifuturo`), `03_referencia.sql`, `07_exportacion.sql`, `src/Web/app.js` («Otras carreras de su área»)

## Contexto

Cada carrera (carrera genérica × tipo de institución) se compara con «la típica de su grupo»: la mediana ponderada por titulados de su **celda** área × tipo × nivel. Si la celda tiene menos de 5 carreras comparables o una carrera pesa más del 50 % de ella, se usa su **segmento** (todas las de su tipo × nivel). Esa referencia alimenta las franjas de la ficha, los cuadrantes, el hallazgo 2 y la frase «Entra ganando $X más que la típica de su grupo».

Hasta esta decisión, el área era la **CINE-F 2013 dominante** por titulaciones SIES, y el área del conocimiento de MiFuturo (MINEDUC) se guardaba solo como etiqueta. En la revisión del usuario (18-11-26) aparecieron dos problemas:

- **El lector piensa por interés, y la CINE no siempre agrupa así.** Telecomunicaciones queda en «Ingeniería, Industria y Construcción» e Informática en «TIC». Ni el área ni la subárea CINE las juntan; en TIC, área y subárea son la misma categoría.
- **Las áreas chicas caen a «todas las áreas».** TIC tiene 2 carreras profesionales universitarias, así que Ingeniería en Computación e Informática se comparaba con las 91 profesionales universitarias. Sus «vecinas» en la ficha incluían Pedagogía en Filosofía y Religión.

El área de MiFuturo es la que ve quien busca carreras en ese buscador. Junta Informática, Redes, Telecomunicaciones y Electrónica en «Tecnología». Cada carrera tiene una sola área en todos los tipos de institución (0 excepciones en los datos de esta versión).

## Decisión

El área de los grupos de comparación pasa a ser el **área del conocimiento de MiFuturo** (`analytics.par.area`). No cambia nada más:

- las reglas siguen iguales: al menos `min_pares_celda` = 5 carreras comparables y ninguna con más de `max_peso_dominante` = 50 % del peso;
- la celda sigue siendo área × tipo × nivel, porque los tipos de institución nunca se mezclan en una mediana;
- si la celda no es válida, la carrera se compara con su segmento.

La CINE queda en `area_cine13`, `share_area` y `area_asignable` como dato de contexto. El control `area_mifuturo` hace fallar el build si una carrera tuviera más de un área de MiFuturo o si un par no usara la de su fila.

En la ficha, «Sus vecinas» (las ±4 más cercanas en sueldo dentro del grupo estadístico) se reemplaza por «Otras carreras de su área». Esa lista muestra las carreras comparables del mismo nivel y área de MiFuturo en todos los tipos, y aparte las no comparables del área.

## Consecuencias

Ensayo en una base separada antes de adoptarla, con los mismos 67 controles en OK:

| | Área CINE | Área MiFuturo |
|---|---|---|
| Celdas válidas | 14 | 14 |
| Carreras comparadas con su área / con su segmento | 139 / 71 | 149 / 61 |
| Ganan celda / la pierden | — | 27 / 17 |
| Cambian de cuadrante (en % / en pesos) | — | 48 / 50 de 210 |
| Hallazgo 2 (cambian de cuadrante al medir en pesos) | 10 profesionales | 13 profesionales |
| Ejemplo del hallazgo 2 | Ing. en Alimentos | Ing. en Alimentos, con las mismas cifras |
| Ficha que abre la Parte II | Enfermería (Universidad) | Ingeniería Comercial (Universidad) |

- **Quién gana:** las carreras de informática y tecnología en los tres tipos (Ing. en Computación e Informática U pasa de «entrada alta» frente a 91 profesionales a «entrada baja» frente a las 28 de Tecnología), Ciencias Sociales universitaria (6, entre ellas Psicología) y Administración en CFT (7).
- **Quién pierde:** Administración y Comercio universitaria queda dominada por Ingeniería Comercial (53 % del peso), así que sus 7 carreras se comparan con todas las profesionales universitarias. Su ficha lo dice al nombrar el grupo, y la lista «Otras carreras de su área» sigue mostrando sus pares.
- **Sin cambios:** los hallazgos de edad, de dispersión entre instituciones y de continuidad.
- **Más amplio:** «Tecnología» reúne toda la ingeniería y la informática, así que la típica de Informática incluye carreras como Minas o Civil Industrial.

## Alternativas consideradas

- **Mantener la CINE y aclarar los títulos.** Dejaba la ficha con dos ideas de área (la lista por MiFuturo y las franjas por CINE).
- **Subárea CINE.** No junta Telecomunicaciones con Informática, y deja muchas listas de 1–2 carreras.
- **Cascada MiFuturo → CINE → segmento.** Rescataba las 7 de Administración universitaria, pero obligaba a explicar dos clasificaciones en la misma página.
- **Relajar la regla de dominancia o el mínimo de 5 carreras para salvar a Administración.** Sería ajustar el método al resultado. Esas reglas protegen la calidad de la típica.
- **Usar los puntos del área en las franjas con la típica del grupo estadístico.** La línea y los puntos hablarían de conjuntos distintos.
