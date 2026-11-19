# ADR-003: Cohortes de Derecho, un año antes que las demás carreras

**Fecha:** 2026-11-19
**Estado:** Aceptado (corrige el +1 usado desde T4); corregido el mismo día por la ventana fuera del SIES (ver al final)
**Archivos:**
- `src/Analisis/sql/analytics/01_par.sql`: parámetro `corrimiento_derecho`.
- `04_dispersion.sql`, `05_contexto.sql`, `06_hallazgos.sql` y `06b_universo.sql`: usan el parámetro.
- `src/Web/app.js`: rótulos de cohortes y textos, mediante `corrDerechoTexto`.

## Contexto

MiFuturo mide Derecho con otras cohortes que el resto de las carreras. Su título lo entrega la Corte Suprema meses después del último trámite en la universidad, así que el primer año de trabajo empieza más tarde. El proyecto aplicaba la excepción a todo lo que cruza Derecho con el SIES:
- las ventanas de titulaciones que pesan cada carrera;
- el conteo de instituciones con titulados en ambos períodos;
- el universo de titulaciones;
- la edad, el sexo y la oferta joven;
- los rótulos de cohortes.

Lo hacía **corriendo esas ventanas un año después**: 2022–2024 en vez de 2021–2023. Ese +1 estaba escrito a mano en 10 consultas.

En la evaluación de navegación del 19-11-26, el revisor de datos notó que la ficha de Derecho decía «sueldo típico de los titulados 2024 (1er año)». Una cohorte titulada en 2024 no puede tener un primer año completo de ingresos en 2024.

## Evidencia

1. **La metodología lo dice de forma explícita** (`datos externos/EMPLEABILIDAD/Metodologia-Estadisticas-por-Carrera_2025-2026.md`, l. 115): en Derecho, el 1er año usa «las cohortes 2020, 2021 y 2022», con ingresos 2022–2024. Las demás carreras usan 2021–2023. El corrimiento es **un año antes**.
2. **Las fuentes cuentan el año igual:** los titulados de Derecho de 2024 son 4.923 en MiFuturo y 4.970 en el SIES (2023: 4.713; 2025: 5.062). Por eso el corrimiento de MiFuturo se aplica tal cual a los años del SIES.
3. **La serie por cohorte no sirve para decidir.** MiFuturo también corre Derecho dentro de la serie (l. 119), así que no prueba ni descarta el cambio.

## Decisión

- El corrimiento vive en un solo lugar: el parámetro `analytics.parametro.corrimiento_derecho` = **−1**. El SQL lo multiplica donde antes sumaba `1`, y la web lo lee para sus rótulos.
- El cambio se hizo en dos pasos:
  1. **Parámetro con +1:** el único cambio en `docs/datos.json` fue el parámetro nuevo; el resto quedó idéntico byte a byte.
  2. **Valor −1:** se ensayó en una base aparte (`carreras_ensayo`) antes de adoptarlo.

## Consecuencias

Ensayo con los mismos 74 controles en OK (sin el escalado de la ventana incompleta; ver la corrección al final):

| | +1 (antes) | −1 sin escalar (ensayo; superado por la corrección del final) |
|---|---|---|
| Derecho: titulaciones que lo pesan | 24.264 | 18.510 |
| Derecho: instituciones en ambos períodos | 45 | 42 (sigue comparable) |
| Derecho: cohortes de la media / del sueldo típico | 2022–2024 / 2024 y 2020 | 2020–2022 / 2022 y 2018 |
| Derecho: entrada frente a la carrera del medio | +$414.925 | +$432.092 |
| Carrera del medio de las 91 profesionales universitarias (1er año) | Ing. en Construcción, $1.046.881 | Ing. en Medio Ambiente, $1.029.714 |
| Carrera del medio de las 91 profesionales universitarias (5° año) | Contador Auditor | Ing. en Construcción |
| Titulaciones del análisis (1er / 5° año) | 687.231 / 615.246 | 683.985 / 612.738 |
| Cuadrantes en pesos | — | Contador Auditor U: de crecimiento parecido a crecimiento mayor |

**Sin cambios:**
- las cuatro tarjetas de hallazgos;
- las 13 carreras que cambian de cuadrante;
- la portada;
- las 14 áreas con carrera del medio propia y sus fichas.

En las 13 carreras que se comparan con el segmento de las 91 profesionales universitarias, las diferencias se mueven entre $17.000 y $28.000.

Las consultas de diagnóstico de la Fase 1 (`src/Analisis/sql/auditoria/`) usaban el +1 de su época. No formaban parte del build y se retiraron del repo al preparar la entrega; quedan en el historial de git hasta el commit `7f56023`.

## Corrección del mismo día: la ventana del 5° año queda fuera del SIES

La segunda evaluación (19-11-26) encontró un efecto que el ensayo no vio. Con −1, la ventana del 5° año de Derecho es **2016–2018**, pero el SIES empieza en 2017. Esa ventana sumaba solo dos años:
- Derecho pesaba 18.510 titulaciones en vez de unas 22.600.
- La ficha comparaba dos años contra tres en «Titulados menores de 30»: decía +26,3 %, cuando el cambio por año es **−15,8 %**.

**Decisión (aprobada por el usuario):** llevar a tres años toda ventana que el SIES no cubre entera.
- La función `analytics.factor_ventana(desde, hasta)` calcula el factor: aquí, ×1,5.
- Se aplica al peso del par (`analytics.par.peso`) y a la comparación de titulados jóvenes (`analytics.contexto`, con la marca `oferta_joven_estimada`, que la web muestra como «estimado»).
- Los conteos reales de títulos (`tit_ventana_*`, universo y embudo) no se escalan: escalarlos inventaría títulos y rompería el embudo.
- El control `ventanas_en_sies` falla si una ventana no tiene ningún año en el SIES y nombra las que se escalan.

**Efecto real de pasar de +1 a −1, ya con el escalado:**

| | +1 (antes) | −1 escalado (ahora) |
|---|---|---|
| Derecho: peso | 24.264 | 22.610 |
| Derecho: instituciones en ambos períodos | 45 | 42 |
| Derecho: cohortes y edad, sexo y oferta joven | 2022–2024 | 2020–2022 (titulados menores de 30: −15,8 %, estimado) |
| Las 91 profesionales universitarias: carrera del medio al 1er año / 5° año / en % | Ing. en Construcción / Contador Auditor / Ing. Civil Industrial | **iguales** |
| Las 91: carrera del medio en el aumento en pesos | Odontología ($573.466) | Publicidad ($560.948) |
| Contador Auditor U, en pesos | crecimiento parecido al de la del medio | crecimiento mayor que el de la del medio |
| Titulaciones del análisis (1er / 5° año) | 687.231 / 615.246 | 683.985 / 612.738 (reales, sin escalar) |

Los cambios de la carrera del medio al 1er y al 5° año que mostraba la tabla de «Consecuencias» venían del año faltante, no del corrimiento. Hallazgos, portada y conteos de cuadrantes: sin cambios.

## Alternativas consideradas

- **Mantener +1 y solo corregir los rótulos:** dejaba pesos, conteos y edades medidos con titulados de dos años más tarde que los que usa MiFuturo.
- **Guardar el corrimiento en `modelo.cohorte`, con filas por carrera:** obligaba a unir esa tabla por carrera en todas las consultas. Un parámetro basta, porque Derecho es la única excepción.
- **No corregir Derecho:** contradice la metodología de la fuente.
- **Para la ventana incompleta, usar solo los años disponibles y decirlo:** dejaba a Derecho con 2/3 de su peso y una comparación de jóvenes de signo invertido.
