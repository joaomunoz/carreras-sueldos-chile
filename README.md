# Sueldos y empleabilidad por carrera en Chile al primer y quinto año de titulación

Análisis independiente de datos públicos del Ministerio de Educación (MiFuturo y SIES) sobre 252 carreras de universidades, institutos profesionales (IP) y centros de formación técnica (CFT). Muestra qué cambia en el sueldo y la empleabilidad entre el primer y el quinto año de titulación, y cuándo la cifra nacional no basta para comparar. Cada cifra se calcula con reglas fijas y pasa controles de calidad.

**Ver la web:** [joaomunoz.github.io/carreras-sueldos-chile](https://joaomunoz.github.io/carreras-sueldos-chile/). También funciona sin conexión: abre [`docs/index.html`](docs/index.html) con doble clic; es un solo archivo (≈ 1,4 MB) con los datos incluidos.

![Portada de la web: título, qué es el proyecto, qué muestra y las cuatro tarjetas de hallazgos](docs/captura.png)

> Es una comparación transversal: quienes llevan un año titulados y quienes llevan cinco son grupos distintos, no las mismas personas en el tiempo.

---

## Hallazgos principales

*Lo genera `make web` desde `docs/datos.json`: son las mismas cifras de la web, calculadas en SQL con controles de calidad.*

<!-- HALLAZGOS:INICIO · generado por src/Web/construir.py desde docs/datos.json; no editar a mano -->
1. **Al quinto año no siempre se gana más.** En la mitad de las carreras técnicas, quienes llevan cinco años titulados ganan al menos 15,7 % más que quienes llevan uno; en las profesionales, al menos 43,2 % más. Pero en 7 de las 85 técnicas ganan menos, y en ninguna de las 125 profesionales. En 6 de esas 7, quienes se titularon hace poco son mucho mayores: no es que caigan los sueldos.
2. **Un crecimiento mayor en porcentaje puede ser menor en pesos.** 13 carreras profesionales (ninguna técnica) cambian de cuadrante según se mida el crecimiento en porcentaje o en pesos. En Ingeniería en Alimentos (Universidad), quienes llevan cinco años titulados ganan 66,5 % más que quienes llevan uno, pero son +$592.205, frente a +$805.627 de la carrera del medio de su grupo.
3. **La cifra nacional esconde diferencias entre instituciones.** En 19 carreras, la empleabilidad varía 15 puntos o más entre las instituciones del rango del medio. En Trabajo Social (Universidad), ese rango va de 52,5 % a 74,2 %, con una cifra nacional de 66,9 %.
4. **Seguir estudiando es cosa de las carreras técnicas.** Al año siguiente de titularse sigue estudiando el 21,7 % de los titulados de carreras técnicas y el 4,2 % de los de carreras profesionales. Depende de la carrera: 37,4 % en Técnico en Administración de Empresas (IP) y 6,8 % en Técnico en Enfermería (IP).

<details>
<summary>Precisiones de los hallazgos</summary>

- **Al quinto año no siempre se gana más:** compara el sueldo típico (la mediana o P50: la mitad gana menos) y da la mediana de las carreras de cada nivel, con los tipos de institución juntos. «Ganan menos» es más de 2 % menos; una diferencia menor se cuenta como empate. En esas 6 carreras, los de 30 años o más son el 32,3 % de los titulados de hace cinco años y el 55,6 % de los recientes (mediana de las 6).
- **Porcentaje y pesos:** no se cuentan las carreras que quedan a ±2 pp (puntos porcentuales) o ±$20.000 de la carrera del medio de su grupo. La carrera del medio es la mediana del grupo, ponderada por titulados.
- **Diferencias entre instituciones:** el rango del medio es la mitad central de las instituciones de la carrera, sin el cuarto más alto ni el cuarto más bajo (Trabajo Social: 32 instituciones).
- **Seguir estudiando:** promedio ponderado por titulados. No explica las diferencias de empleabilidad entre instituciones de una misma carrera.

</details>
<!-- HALLAZGOS:FIN -->

<details>
<summary>Qué no dice este análisis</summary>

- No prueba causas: describe diferencias entre grupos de titulados.
- MiFuturo cubre el 90,5 % de los titulados recientes y el 84,5 % de los de hace cinco años. Faltan programas chicos y programas cerrados.
- Solo cuenta ingresos sobre el sueldo mínimo con registro en el Servicio de Impuestos Internos (SII); no hay datos por sexo, edad ni región.
- Los años 1 a 4 del ingreso promedio incluyen titulados de 2020–2021 (pandemia; en Derecho, que usa titulados de un año antes, solo los años 1 a 3), y en 15 carreras los titulados de 2023 tuvieron una empleabilidad atípica (6 de ellas de salud).

La lista completa, con sus cifras, está en la sección **«Qué no dice este análisis»** de la web.

</details>

---

## Arquitectura y calidad de datos

- **Cuatro capas en PostgreSQL:** `raw` (copia fiel de los CSV) → `modelo` (relacional, con PK, FK y `CHECK`) → `analytics` (métricas) → `qa` (controles), construidas en **una sola transacción**: si algo falla, la base queda como estaba.
- <!-- CONTROLES:INICIO -->**81 controles de calidad**: 78 hacen fallar el build y 3 no aplican por diseño (documentados en la web)<!-- CONTROLES:FIN -->. Si uno falla, **el exportador se niega a escribir los datos** y la web no se puede regenerar.
- **Determinista:** reconstruir la base y volver a exportar da el mismo archivo, con el mismo SHA-256.
- **Ninguna cifra de la web está escrita a mano:** textos, umbrales y ejemplos se calculan desde los datos, y los ejemplos se eligen por una regla, no a dedo.
- **Web autónoma:** HTML, CSS, JavaScript y SVG sin librerías; modo claro y oscuro, usable con teclado y lector de pantalla, sin desplazamiento horizontal a 320 px y con contraste ≥ 4,5:1 en todo el texto.

<details>
<summary>Qué verifican los controles</summary>

- El contrato de columnas contra los esquemas de los scrapers.
- Que cada cohorte exista en el SIES (Servicio de Información de Educación Superior).
- La cohorte de cada punto de las series, validada contra la propia fuente: error mediano de 0,3 % frente a 1,8–2,3 % con la cohorte corrida un año.
- Que los cuantiles ponderados coincidan con un cálculo independiente.

</details>

<details>
<summary>Estructura del repositorio y modelo de datos</summary>

```
src/
├── Scrapers/          obtener.py → Entrada/ (crudo) · procesar.py → Salida/ (CSV) · esquema.py (contrato)
│   ├── Empleabilidad/   MiFuturo, por institución (1.690 programas)
│   ├── Estadisticas/    MiFuturo, nacional por carrera y tipo de institución (252)
│   └── Titulados/       SIES, titulaciones 2017–2025 (94.579 programa-año)
├── BD/                el modelo: DDL, carga, controles, build.py, diagrama y diccionario
├── Analisis/
│   ├── sql/analytics/   las métricas (par, brecha, referencias, dispersión, contexto, exportación)
│   └── exportar.py
└── Web/               plantilla, estilos, app.js y construir.py
docs/                  index.html (la web), datos.json y captura.png
```

Modelo de datos: [diagrama ER](src/BD/diagrama_modelo.md) · [diccionario de datos](src/BD/diccionario_datos.md).

</details>

---

## Decisiones metodológicas clave

- **La media y los percentiles nunca se combinan.** La media de cada año junta tres cohortes con ingresos 2022–2024; los percentiles usan una sola cohorte con ingresos 2024. *Descartado:* `Media / P50`, que mezclaría poblaciones.
- **Derecho se mide con titulados de un año antes.** Así lo publica MiFuturo: el título de abogado lo entrega la Corte Suprema meses después de terminar la carrera. El proyecto aplica la misma regla a las cifras del SIES con un solo parámetro (`corrimiento_derecho`). *Descartado:* correrlo un año después, que daba un «1er año» con titulados que aún no tenían un año completo de ingresos.
- **Una carrera es comparable si la ofrecen 3 o más instituciones.** Con 1 o 2, la «cifra nacional» es en realidad la de una institución. *Descartado:* comparar todas (42 de 252 carreras serían anécdotas).
- **Cada carrera se compara con las de su área en MiFuturo, no con la clasificación internacional CINE.** Quien busca una carrera piensa por interés y ve esa clasificación en MiFuturo; la CINE separaba Telecomunicaciones de Informática. *Descartado:* mantener la CINE (dejaba Informática contra las 91 profesionales universitarias) o usar ambas en cascada (dos clasificaciones en una misma página).
- **Un grupo de área deja de ser referencia si una carrera pesa más del 50 %.** Con pesos por titulados, la mediana del grupo sería el valor de esa carrera. *Descartado:* avisarlo sin cambiar la referencia, o una mediana sin ponderar (mezcla criterios).
- **Cada institución se compara con la institución del medio de su carrera** (la mediana de las publicadas). La cifra nacional queda <!-- BRECHA:INICIO -->+1,7 puntos de empleabilidad y +6,2 % en el rango de ingreso al 4° año<!-- BRECHA:FIN --> sobre las instituciones publicadas, porque describe una población más amplia. *Descartado:* compararla con la cifra nacional (inflaba «bajo el promedio»: 715 contra 131).
- **Cuadrantes con ejes relativos al grupo de cada carrera.** Cada carrera se clasifica contra su propio grupo; con ejes absolutos, el gráfico contradiría la clasificación. *Descartado:* ejes absolutos por segmento.
- **El JSON se arma en SQL y la web es un solo archivo.** El archivo no puede contradecir a las tablas, y abierto con doble clic el navegador no permite leer un JSON externo. *Descartado:* armar el JSON en Python o leerlo con `fetch` (exige un servidor).

<details>
<summary>Dos decisiones que corrigieron los datos</summary>

- Con la ponderación, algunos grupos de área quedaban dominados por una sola carrera (con el área CINE, Psicología pesaba el 70 % de su grupo; con la de MiFuturo, Técnico en Enfermería pesa el 73–75 % de Salud técnica e Ingeniería Comercial el 53 % de Administración universitaria). De ahí la regla del 50 %.
- La cifra nacional queda sistemáticamente sobre el promedio de las instituciones publicadas (<!-- BRECHA:INICIO -->+1,7 puntos de empleabilidad y +6,2 % en el rango de ingreso al 4° año<!-- BRECHA:FIN -->). De ahí la comparación con la institución del medio.

</details>

---

## Cómo reproducirlo

**Requisitos:** PostgreSQL 15 o superior (usa `COPY … HEADER MATCH`; probado con 18.4), Python 3 (probado con 3.13) y `make`.

```bash
pip install -r requirements.txt

# Base vacía y conexión sin contraseña (autenticación peer); sin credenciales en el código.
createdb carreras_sueldos
export PGDATABASE=carreras_sueldos

make todo        # base de datos → docs/datos.json → docs/index.html  (≈ 50 s)
```

<details>
<summary>Cada paso de <code>make</code> por separado</summary>

- `make base` — `src/BD/build.py`: crea `raw`, `modelo`, `analytics` y `qa`, carga los CSV y corre los controles, todo en una transacción.
- `make datos` — `src/Analisis/exportar.py`: escribe `docs/datos.json` (no exporta si algún control falla).
- `make web` — `src/Web/construir.py`: arma `docs/index.html` con todo incluido (no necesita la base) y regenera en este README los hallazgos, el conteo de controles y la brecha de la cifra nacional.

</details>

<details>
<summary>Rehacer los CSV desde las fuentes</summary>

Los CSV procesados están versionados en `src/Scrapers/*/Salida/`, así que no hace falta descargar nada. Para rehacerlos:

```bash
cd src/Scrapers
python3 Empleabilidad/obtener.py && python3 Empleabilidad/procesar.py
python3 Estadisticas/obtener.py  && python3 Estadisticas/procesar.py
python3 Titulados/obtener.py     && python3 Titulados/procesar.py    # descarga el Excel del SIES (≈ 39 MB)
```

</details>

---

## Fuentes, licencias y autoría

- **Datos:** [MiFuturo](https://www.mifuturo.cl) (Buscador de Empleabilidad e Ingresos y Buscador de Estadísticas por Carrera, metodologías 2025–2026) y SIES ([bases de datos de titulados](https://www.mifuturo.cl/bases-de-datos-titulados/): base histórica 2007–2025, versión del 27-05-2026, con su [glosario](https://www.mifuturo.cl/wp-content/uploads/2026/05/GLOSARIO_DE_TITULADO_2007_2025_E.pdf); el análisis usa 2017–2025), ambos del Ministerio de Educación de Chile. `src/Scrapers/Titulados/obtener.py` busca en esa página el enlace vigente al Excel, cuyo nombre cambia con cada versión. Rigen las condiciones de uso de sus fuentes; este repositorio no los relicencia.
- **Fuente tipográfica:** Archivo Narrow (SIL Open Font License 1.1, ver `src/Web/fuentes/`).
- **Código:** licencia [MIT](LICENSE).
- **Autoría:** análisis de [Joao Muñoz](https://joaomunoz.github.io).
