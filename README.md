# Del primer al quinto año

> Cuánto progresa el ingreso de cada carrera en Chile entre el primer y el quinto año desde la titulación, y dónde el promedio engaña. Análisis en PostgreSQL y Python, con una web autónoma.

![Portada de la web: cada línea es una carrera, del sueldo típico al primer año al del quinto](docs/captura.png)

**Ver la web:** abre [`docs/index.html`](docs/index.html) con doble clic. Es un solo archivo (≈ 1,1 MB) con los datos incluidos, sin servidor ni conexión a internet.

---

## Qué encontré

*Este bloque lo genera `make web` desde `docs/datos.json`: son las mismas cifras de la web, calculadas en SQL con controles de calidad.*

<!-- HALLAZGOS:INICIO · generado por src/Web/construir.py desde docs/datos.json; no editar a mano -->
1. **Al quinto año no siempre se gana más.** El sueldo típico (P50) sube 15,7 % entre el primer y el quinto año en las carreras técnicas y 43,2 % en las profesionales (medianas de cada nivel), pero baja en 7 de 85 técnicas y en 2 de 125 profesionales. No es que caigan los sueldos: en 6 de esas 7 técnicas, quienes se titularon hace poco son mucho mayores (los de 30 años o más pasan de 32,3 % a 55,6 %, mediana de esas 6), y muchos ya trabajaban antes de titularse.
2. **Crecer más en porcentaje no es crecer más.** 10 carreras profesionales (ninguna técnica) cambian de cuadrante si el crecimiento se mide en pesos en vez de en porcentaje (sin contar las que quedan a ±2 pp o ±$20.000 de la carrera típica de su grupo). Ingeniería en Alimentos (Universidad) sube 66,5 %, pero eso son +$592.205, frente a +$805.627 de la carrera típica de su grupo (mediana ponderada por titulados).
3. **El promedio nacional esconde diferencias entre instituciones.** En 19 carreras las instituciones difieren 15 puntos o más en empleabilidad, aun dejando fuera al cuarto más alto y al cuarto más bajo. En Trabajo Social (Universidad, 32 instituciones) la mitad central va de 52,5 % a 74,2 %, con una cifra nacional de 66,9 %.
<!-- HALLAZGOS:FIN -->

> **Corrección (16-11-26).** La versión anterior decía que, en las carreras con cambio de edad, los titulados de 30 años o más pasaban de 28 % a 55 %. Esa mediana se calculaba sobre las 9 carreras que bajan y no sobre las 7 que nombraba la frase; la cifra correcta es 32,5 % → 56,6 %. Desde esta versión, las cifras de los hallazgos se calculan en SQL y tienen sus propios controles de calidad.
>
> **Corrección (17-11-26).** El hallazgo 1 daba una sola mediana de crecimiento para las 210 carreras comparables (+29,3 %), que mezclaba técnicas y profesionales y no describía a ninguno de los dos niveles. Ahora se informa por nivel.

---

## Por qué confiar en las cifras

- **Cuatro capas en PostgreSQL:** `raw` (copia fiel de los CSV) → `modelo` (relacional, con PK, FK y `CHECK`) → `analytics` (métricas) → `qa` (controles). Todo se construye en **una sola transacción**: si algo falla, la base queda como estaba.
- <!-- CONTROLES:INICIO -->**56 controles de calidad**: 53 hacen fallar el build y 3 están exentos por diseño (documentados)<!-- CONTROLES:FIN -->. Entre ellos: el contrato de columnas contra los esquemas de los scrapers, que cada cohorte exista en el SIES, la cohorte de cada punto de las series (validada contra la propia fuente: error mediano de 0,3 % frente a 1,8–2,3 % con la cohorte corrida un año) y que los cuantiles ponderados coincidan con un cálculo independiente. Si un control falla, **el exportador se niega a escribir los datos** y la web no se puede regenerar.
- **Determinista:** reconstruir la base y volver a exportar da el mismo archivo, con el mismo SHA-256.
- **Los datos corrigieron dos decisiones del plan** y quedaron documentadas:
  - Con la ponderación, 4 grupos de área estaban dominados por una sola carrera (Psicología pesaba el 70 % de su grupo). Se agregó una regla: un grupo deja de ser referencia si una carrera supera el 50 % de su peso.
  - La cifra nacional queda sistemáticamente sobre el promedio de las instituciones publicadas (<!-- BRECHA:INICIO -->+1,7 puntos de empleabilidad y +6,2 % en el tramo de ingreso<!-- BRECHA:FIN -->). Por eso cada institución se compara con la institución típica de su carrera, no con la cifra nacional.
- **Ninguna cifra de la web está escrita a mano:** textos, umbrales y ejemplos se calculan desde los datos, y los ejemplos se eligen por una regla, no a dedo.

---

## Cómo reproducirlo

**Requisitos:** PostgreSQL 15 o superior (usa `COPY … HEADER MATCH`; probado con 18.4), Python 3 (probado con 3.13) y `make`.

```bash
pip install -r requirements.txt

# Base vacía y conexión sin contraseña (autenticación peer); sin credenciales en el código.
createdb carreras_sueldos
export PGDATABASE=carreras_sueldos

make todo        # base de datos → docs/datos.json → docs/index.html  (≈ 13 s)
```

| Comando | Qué hace |
|---|---|
| `make base` | `src/BD/build.py`: crea `raw`, `modelo`, `analytics` y `qa`, carga los CSV y corre los controles, todo en una transacción |
| `make datos` | `src/Analisis/exportar.py`: escribe `docs/datos.json` (no exporta si algún control falla) |
| `make web` | `src/Web/construir.py`: arma `docs/index.html` con todo incluido (no necesita la base) y regenera en este README el bloque «Qué encontré» y el conteo de controles |

Los CSV procesados están versionados en `src/Scrapers/*/Salida/`, así que no hace falta descargar nada. Para rehacerlos desde las fuentes:

```bash
cd src/Scrapers
python3 Empleabilidad/obtener.py && python3 Empleabilidad/procesar.py
python3 Estadisticas/obtener.py  && python3 Estadisticas/procesar.py
python3 Titulados/obtener.py     && python3 Titulados/procesar.py    # descarga el Excel del SIES (≈ 39 MB)
```

---

## Cómo está hecho

```
src/
├── Scrapers/          obtener.py → Entrada/ (crudo) · procesar.py → Salida/ (CSV) · esquema.py (contrato)
│   ├── Empleabilidad/   MiFuturo, por institución (1.690 programas)
│   ├── Estadisticas/    MiFuturo, nacional por carrera y tipo de institución (252)
│   └── Titulados/       SIES, titulaciones 2017–2025 (94.579 programa-año)
├── BD/                el modelo: DDL, carga, controles, build.py, diagrama y diccionario
├── Analisis/
│   ├── sql/auditoria/   auditoría de la Fase 1 (cobertura, sesgos, completitud)
│   ├── sql/analytics/   las métricas (par, brecha, referencias, dispersión, contexto, exportación)
│   └── exportar.py
└── Web/               plantilla, estilos, app.js y construir.py
docs/                  index.html (la web), datos.json y captura.png
```

- Modelo de datos: [diagrama ER](src/BD/diagrama_modelo.md) · [diccionario de datos](src/BD/diccionario_datos.md) · [ADR del modelo relacional](src/BD/ADR-001-modelo-relacional.md).
- La web es HTML, CSS, JavaScript y SVG sin librerías: modo claro y oscuro, usable con teclado y lector de pantalla, sin desplazamiento horizontal a 320 px, con contraste ≥ 4,5:1 en todo el texto.

---

## Decisiones clave

| Decisión | Contexto | Alternativa descartada |
|---|---|---|
| **La media y los percentiles nunca se combinan** | La media de cada año junta tres cohortes con ingresos 2022–2024; los percentiles usan una sola cohorte con ingresos 2024. Son poblaciones distintas | `Media / P50` (mezclaría poblaciones) |
| **Comparable = 3 o más instituciones la ofrecen** | Con 1 o 2, la "cifra nacional" es en realidad la de una institución | Comparar todas (42 de 252 carreras serían anécdotas) |
| **Un grupo de área deja de ser referencia si una carrera pesa más del 50 %** | Con pesos por titulados, la mediana del grupo sería el valor de esa carrera | Avisarlo sin cambiar la referencia; mediana sin ponderar (mezcla criterios) |
| **Cada institución se compara con la institución típica de su carrera** | La cifra nacional queda <!-- BRECHA:INICIO -->+1,7 puntos de empleabilidad y +6,2 % en el tramo de ingreso<!-- BRECHA:FIN --> sobre las instituciones publicadas: describe una población más amplia | Compararla con la cifra nacional (inflaba "bajo el promedio": 715 contra 131) |
| **Cuadrantes con ejes relativos al grupo de cada carrera** | Cada carrera se clasifica contra su propio grupo; con ejes absolutos el gráfico contradiría la clasificación | Ejes absolutos por segmento |
| **El JSON se arma en SQL y la web es un solo archivo** | El archivo no puede contradecir a las tablas, y abierto con doble clic el navegador no permite leer un JSON externo | Armar el JSON en Python; leerlo con `fetch` (exige un servidor) |

---

## Qué no dice

Es una **comparación transversal**: el primer y el quinto año son grupos distintos de titulados, no las mismas personas en el tiempo, y no prueba causas.

- MiFuturo cubre el 90,5 % de los titulados recientes y el 84,5 % de los de hace cinco años. Faltan programas chicos y programas cerrados.
- Solo cuenta ingresos sobre el sueldo mínimo con registro en el SII; no hay datos por sexo, edad ni región.
- Los años 1 a 4 del ingreso promedio incluyen titulados de 2020–2021 (pandemia), y en 15 carreras la cohorte 2023 tuvo una empleabilidad atípica (sobre todo en salud).

La lista completa, con sus cifras, está en la sección **«Qué no dice este análisis»** de la web.

---

## Fuentes y licencias

- **Datos:** [MiFuturo](https://www.mifuturo.cl) (Buscador de Empleabilidad e Ingresos y Buscador de Estadísticas por Carrera, metodologías 2025–2026) y SIES (Titulados 2007–2025), ambos del Ministerio de Educación de Chile. Rigen las condiciones de uso de sus fuentes; este repositorio no los relicencia.
- **Fuente tipográfica:** Archivo Narrow (SIL Open Font License 1.1, ver `src/Web/fuentes/`).
- **Código:** licencia [MIT](LICENSE).

## Autoría

<!-- PENDIENTE: completar con nombre y enlaces (GitHub, LinkedIn). También en LICENSE y en el pie de src/Web/plantilla.html. -->
_Pendiente: nombre y enlaces._
