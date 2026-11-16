# ADR-001: Modelo relacional de la base `carreras_sueldos`

**Fecha:** 2026-11-16
**Estado:** Aceptado
**Archivos:** `src/BD/01_raw.sql`, `src/BD/02_modelo.sql` · diccionario: `src/BD/diccionario_datos.md`

## Contexto

El proyecto cruza tres fuentes con granularidades distintas:

| Fuente | Scraper | Grano | Filas |
|---|---|---|---|
| MiFuturo, Buscador de Empleabilidad e Ingresos | `src/Scrapers/Empleabilidad/` | institución × carrera genérica | 1.690 |
| MiFuturo, Buscador de Estadísticas por Carrera | `src/Scrapers/Estadisticas/` | carrera genérica × tipo de institución (nacional) | 252 |
| SIES, base de titulados | `src/Scrapers/Titulados/` | programa × año | 94.579 |

La revisión relacional previa al DDL (T0) encontró:

- Las fuentes no calzan 1 a 1: el SIES tiene 164 instituciones y 272 carreras genéricas, MiFuturo 105 instituciones y 190 genéricas (Empleabilidad) o 165 (Estadísticas). Todas las de MiFuturo existen en el SIES.
- MiFuturo publica valores **nacionales** por carrera × tipo (ingresos, percentiles, empleabilidad nacional). Pegarlos a cada institución los repetía en hasta 44 filas y perdía 3 pares sin ninguna institución publicada.
- Algunos atributos cambian entre años: subtipo de institución (Diego Portales y Alberto Hurtado pasan a CRUCH en 2019, Los Andes en 2020), tipo de plan (108 programas), área CINE-13 (13 genéricas caen en más de un área).
- Cada carrera genérica tiene un solo nivel (técnico o profesional): 272/272.
- Media y percentiles de ingreso vienen de cohortes distintas (media: 3 cohortes, ingresos 2022–2024; percentiles: una cohorte, ingresos 2024).
- MiFuturo corre sus cohortes cada año.

## Decisión

Dos esquemas, recreados desde cero en cada build:

1. **`raw`**: copia fiel de los 3 CSV. Mismas columnas y orden que cada `esquema.py`, PK, `NOT NULL` donde la fuente siempre informa y `CHECK` de rango físico. Sin reglas de negocio.
2. **`modelo`**: modelo relacional poblado desde `raw`:
   - **Referencias compartidas** `institucion` (164) y `carrera_generica` (272, con su nivel), a las que apuntan todas las tablas de hechos.
   - **`cohorte`**: los años, umbral y referencia documental de cada indicador, en un solo lugar (19 indicadores).
   - **Un hecho por granularidad:** `titulacion` (programa × año), `mifuturo_programa` (institución × genérica), `mifuturo_estadistica` (genérica × tipo, nacional) y `mifuturo_serie` (series de 5 cohortes en formato largo).
   - Lo que cambia entre años vive en `titulacion`, no en las referencias.
   - **FK compuesta** `mifuturo_programa (codigo_institucion, tipo_institucion) → institucion`: la base impide que un programa declare un tipo distinto al de su institución.
   - **Sin FK entre `mifuturo_programa` y `mifuturo_estadistica`**: 48 programas no tienen estadística publicada y 3 estadísticas no tienen institución publicada. La cobertura se mide en `qa`.
   - **Dominios cerrados** (`CHECK ... IN`) en las categorías: una categoría nueva en la fuente rompe la carga.

## Consecuencias

- La regla "nunca promediar ingresos sobre las 1.690 filas" queda impuesta por el diseño: los ingresos no existen a nivel institución.
- Un cambio de cohortes de MiFuturo se corrige en una tabla (`cohorte`), no en cada consulta.
- `raw` permite el control de contrato contra los `esquema.py` (T3) y aísla la carga de las transformaciones: si falla `modelo`, `raw` sigue siendo inspeccionable.
- Cada build borra y recrea `raw` y `modelo`: no hay datos manuales que se pierdan, porque todo viene de `Salida/` y de `02_modelo.sql`.
- Las consultas de análisis (`src/Analisis/sql/`) leen solo `modelo`.
- Costo: más tablas y más joins que una tabla ancha; se acepta porque cada join expresa una granularidad real.

## Alternativas consideradas

| Alternativa | Por qué se descartó |
|---|---|
| Tabla única de 1.690 filas con todo | Repite los valores nacionales por institución, invita a promediarlos y pierde 3 pares |
| FK directa entre fuentes (MiFuturo → SIES) | Las fuentes no calzan 1 a 1; perdería filas o exigiría FK nulas |
| `cine13`, subtipo o plan como atributo de la referencia | Cambian entre años o por programa; obligaría a elegir un valor y ocultar el resto |
| Series de 5 cohortes como 15 columnas en `modelo` | Cada consulta debería nombrar 15 columnas; el formato largo permite funciones de ventana y la ausencia de fila expresa "no publicado" |
| Control `qa` para el tipo de institución del programa | La FK compuesta lo garantiza en la estructura, sin depender de que alguien corra el control |
| Generar el DDL desde los `esquema.py` | Los tipos de pandas no expresan PK, FK ni `CHECK` (decisión B3: DDL a mano + control `qa` de columnas) |
| Decimales como `numeric(p,s)` en `raw` | Redondearían en silencio al cargar; `raw` no debe alterar el dato |
