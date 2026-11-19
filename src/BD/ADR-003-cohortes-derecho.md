# ADR-003: Cohortes de Derecho, un año antes que las demás carreras

**Fecha:** 2026-11-19
**Estado:** Aceptado (corrige el +1 usado desde T4)
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

Ensayo con los mismos 74 controles en OK:

| | +1 (antes) | −1 (ahora) |
|---|---|---|
| Derecho: titulaciones que lo pesan | 24.264 | 18.510 |
| Derecho: instituciones en ambos períodos | 45 | 42 (sigue comparable) |
| Derecho: cohortes de la media / del sueldo típico | 2022–2024 / 2024 y 2020 | 2020–2022 / 2022 y 2018 |
| Derecho: entrada frente a la carrera del medio | +$414.925 | +$432.092 |
| Carrera del medio de las 91 profesionales universitarias (1er año) | Ing. en Construcción, $1.046.881 | Ing. en Medio Ambiente, $1.029.714 |
| Carrera del medio de las 91 profesionales universitarias (5° año) | Contador Auditor | Ing. en Construcción |
| Titulaciones del análisis (1er / 5° año) | 687.231 / 615.246 | 683.985 / 612.738 |
| Cuadrantes en pesos | — | Contador Auditor U: de «progreso típico» a «progresa más» |

**Sin cambios:**
- las cuatro tarjetas de hallazgos;
- las 13 carreras que cambian de cuadrante;
- la portada;
- las 14 áreas con carrera del medio propia y sus fichas.

En las 13 carreras que se comparan con el segmento de las 91 profesionales universitarias, las diferencias se mueven entre $17.000 y $28.000.

Las consultas de `src/Analisis/sql/auditoria/` son de solo lectura, del diagnóstico de T0–T5, y conservan el +1 de su época. No forman parte del build.

## Alternativas consideradas

- **Mantener +1 y solo corregir los rótulos:** dejaba pesos, conteos y edades medidos con titulados de dos años más tarde que los que usa MiFuturo.
- **Guardar el corrimiento en `modelo.cohorte`, con filas por carrera:** obligaba a unir esa tabla por carrera en todas las consultas. Un parámetro basta, porque Derecho es la única excepción.
- **No corregir Derecho:** contradice la metodología de la fuente.
