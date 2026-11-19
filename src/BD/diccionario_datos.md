# Diccionario de datos — base `carreras_sueldos`

**Última revisión:** 2026-11-16 · **DDL:** `src/BD/01_raw.sql`, `src/BD/02_modelo.sql` · **Decisiones:** `src/BD/ADR-001-modelo-relacional.md`

Convenciones para toda la base:

- **Porcentajes** en escala 0–100 con 1 decimal.
- **Montos** en pesos de septiembre de 2025, enteros. Los ingresos de MiFuturo solo consideran titulados con ingreso ≥ sueldo mínimo, así que las distribuciones están truncadas abajo.
- **`clave_*`**: texto normalizado con `normalizar_texto()` de `src/Scrapers/comun/normalizador.py` (sin tildes, mayúsculas, espacios simples). Es la llave de cruce entre fuentes.
- **`tipo_institucion`**: `Universidad` | `IP` | `CFT`, vía `normalizar_tipo_institucion()` del mismo archivo.
- **`NULL`** significa "la fuente no publica el dato" (bajo su umbral de casos). Nunca se imputa.
- **Cohortes**: los años de cada indicador están en `modelo.cohorte`, no en este documento ni en las consultas.

---

## Esquema `raw`

Copia fiel de los CSV de los scrapers. Columnas, orden y significado son los de su `esquema.py`; no se repiten aquí para no tener dos fuentes de verdad.

| Tabla | Origen (CSV) | Definición de columnas | Llave | Filas |
|---|---|---|---|---|
| `raw.empleabilidad` | `src/Scrapers/Empleabilidad/Salida/empleabilidad_procesado.csv` | `src/Scrapers/Empleabilidad/esquema.py` | `(id_institucion, clave_carrera_generica)` | 1.690 |
| `raw.estadisticas` | `src/Scrapers/Estadisticas/Salida/estadisticas_procesado.csv` | `src/Scrapers/Estadisticas/esquema.py` | `(clave_carrera_generica, tipo_institucion)` | 252 |
| `raw.titulados` | `src/Scrapers/Titulados/Salida/titulados_procesado.csv` | `src/Scrapers/Titulados/esquema.py` | `(anio, codigo_programa)` | 94.579 |

---

## Esquema `modelo`

### `modelo.institucion` — referencia
**Grano:** una institución. **Llave:** `codigo_institucion`. **Filas esperadas:** 164. **Origen:** `raw.titulados` (el SIES incluye a todas las de MiFuturo).

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `codigo_institucion` | integer | no | Código SIES. Igual al `id_institucion` de MiFuturo (verificado 105/105) |
| `nombre` | text | no | Nombre SIES del año más reciente, sin el sufijo "(*CARRERA EN CONVENIO …)" |
| `tipo_institucion` | text | no | `Universidad` \| `IP` \| `CFT`; constante en los años (verificado) |

### `modelo.carrera_generica` — referencia
**Grano:** una carrera genérica. **Llave:** `clave_carrera_generica`. **Filas esperadas:** 272. **Origen:** `raw.titulados` (incluye las 190 de Empleabilidad y las 165 de Estadísticas).

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `clave_carrera_generica` | text | no | Clave normalizada de cruce |
| `nombre` | text | no | Nombre con tildes para mostrar |
| `nivel_carrera` | text | no | `Carreras Profesionales` \| `Carreras Técnicas`. Un solo nivel por genérica (verificado 272/272) |

### `modelo.cohorte` — referencia
**Grano:** un indicador. **Llave:** `indicador`. **Filas:** 19, cargadas en `02_modelo.sql`.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `indicador` | text | no | Nombre del indicador (p. ej. `percentiles_anio_5`) |
| `fuente` | text | no | `Empleabilidad` \| `Estadisticas` \| `Titulados` |
| `cohorte_desde`, `cohorte_hasta` | smallint | no | Años de titulación que entran en el indicador |
| `anio_ingreso_desde`, `anio_ingreso_hasta` | smallint | sí | Años tributarios del SII; `NULL` si el indicador no se mide sobre ingresos |
| `min_casos` | smallint | sí | Umbral de publicación declarado por la fuente |
| `referencia` | text | no | Documento y líneas de `datos externos/` que respaldan la fila |

Derecho usa en todos los indicadores de MiFuturo cohortes de un año antes en años del SIES (MiFuturo lo describe como «cohorte de titulación + 1 año»; su 1er año usa 2020–2022). El análisis lo aplica con el parámetro `corrimiento_derecho` = −1 ([ADR-003](ADR-003-cohortes-derecho.md)).

### `modelo.titulacion` — hecho SIES
**Grano:** un programa en un año. **Llave:** `(anio, codigo_programa)`. **Filas esperadas:** 94.579. **Origen:** `raw.titulados`. **Unidad:** titulaciones, no personas.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `anio` | smallint | no | Año académico de titulación (marzo a febrero) |
| `codigo_programa` | text | no | Código SIES del programa (institución, sede, carrera, jornada, versión) |
| `codigo_institucion` | integer | no | FK → `institucion` |
| `clave_carrera_generica` | text | no | FK → `carrera_generica` |
| `carrera` | text | no | Nombre del programa ese año (cambia entre años en 800 programas) |
| `subtipo_institucion` | text | no | `Universidades CRUCH` \| `Universidades Privadas` \| `Institutos Profesionales` \| `Centros de Formación Técnica`; puede cambiar entre años |
| `es_convenio` | boolean | no | El nombre SIES de la institución trae "(*CARRERA EN CONVENIO …)" |
| `cine13_area`, `cine13_subarea` | text | no | Clasificación CINE-F 2013 del programa |
| `carrera_clasificacion_nivel_1` | text | no | Técnico de Nivel Superior \| Profesional Con/Sin Licenciatura \| Licenciatura No Conducente a Título |
| `tipo_plan` | text | no | Plan Regular \| Plan Especial \| Plan Regular de Continuidad |
| `modalidad`, `jornada` | text | no | Dominios cerrados del glosario SIES |
| `duracion_semestres` | numeric | no | Duración del plan de estudios (sin proceso de titulación) |
| `total_titulaciones` | integer | no | = mujeres + hombres + nb = suma de tramos de edad |
| `titulaciones_mujeres`, `_hombres`, `_nb` | integer | no | Por sexo |
| `titulados_15_19` … `titulados_mayores_40`, `titulados_edad_sin_info` | integer | no | Por tramo de edad al titularse. El tramo `30_34` mezcla el corte ≤ 30 de MiFuturo |
| `edad_promedio` | numeric | sí | Edad promedio al titularse |

### `modelo.mifuturo_programa` — hecho MiFuturo por institución
**Grano:** una institución × carrera genérica. **Llave:** `(codigo_institucion, clave_carrera_generica)`. **Filas esperadas:** 1.690. **Origen:** `raw.empleabilidad`. **Única fuente de resultados por institución.**

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `codigo_institucion` | integer | no | FK compuesta con `tipo_institucion` → `institucion` |
| `tipo_institucion` | text | no | Debe coincidir con el de la institución (garantizado por la FK) |
| `clave_carrera_generica` | text | no | FK → `carrera_generica` |
| `carrera` | text | no | Nombre de la carrera en MiFuturo |
| `acreditacion_anios` | smallint | no | Años de acreditación institucional; 0 = no acreditada |
| `pct_continuidad_estudios` | numeric | no | % de titulados matriculados al año siguiente en otro programa |
| `duracion_real_semestres` | numeric | sí | Duración real promedio de los titulados 2024 |
| `empleabilidad_1er_anio` | numeric | no | % con ingreso ≥ sueldo mínimo **entre titulados con registro en el SII** |
| `empleabilidad_2do_anio` | numeric | sí | Ídem al 2° año |
| `ingreso_4to_anio_tramo_min`, `_max` | integer | sí | Tramo del ingreso promedio al 4° año, como intervalo. `_max` nulo = tramo abierto "Sobre $X"; ambos nulos = no publicado |

### `modelo.mifuturo_estadistica` — hecho MiFuturo nacional
**Grano:** una carrera genérica × tipo de institución. **Llave:** `(clave_carrera_generica, tipo_institucion)`. **Filas esperadas:** 252. **Origen:** `raw.estadisticas`. **Valores nacionales**: nunca se asignan a una institución.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `clave_carrera_generica` | text | no | FK → `carrera_generica` |
| `tipo_institucion` | text | no | `Universidad` \| `IP` \| `CFT` |
| `id_estadisticas` | integer | no | Id interno de MiFuturo; solo trazabilidad |
| `area_conocimiento_mineduc` | text | no | Área del Conocimiento MINEDUC (CINE-97). **No** es `cine13_area` |
| `ingreso_medio_1er_anio` … `_5to_anio` | integer | no | Media de 3 cohortes por año (ver `cohorte`) |
| `percentil_{10,25,50,75,90}_anio_1` | integer | no | Una cohorte (2023), ingresos 2024 |
| `percentil_{10,25,50,75,90}_anio_5` | integer | no | Una cohorte (2019), ingresos 2024 |
| `empleabilidad_1er_anio`, `_2do_anio` | numeric | no | Empleabilidad nacional publicada del par |
| `titulados_2024`, `_mujeres`, `_hombres` | integer | no | **Personas** tituladas en 2024 |
| `duracion_formal_semestres` | numeric | sí | Plan de estudios + proceso de titulación |
| `duracion_real_semestres` | numeric | sí | Desde el ingreso hasta la titulación |

Media y percentiles describen poblaciones distintas: no se combinan en una misma razón.

### `modelo.mifuturo_serie` — hecho MiFuturo, series de 5 cohortes
**Grano:** un par × indicador × cohorte. **Llave:** `(clave_carrera_generica, tipo_institucion, indicador, cohorte)`. **Origen:** las 15 columnas `*_cohorte_*` de `raw.estadisticas`. Un punto no publicado (< 25 casos) no tiene fila.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `clave_carrera_generica`, `tipo_institucion` | text | no | FK compuesta → `mifuturo_estadistica` |
| `indicador` | text | no | `serie_empleabilidad_1er_anio` \| `serie_empleabilidad_2do_anio` \| `serie_ingreso_medio_4to_anio`; FK → `cohorte` |
| `cohorte` | smallint | no | Año de titulación del punto |
| `valor` | numeric | no | % (empleabilidad) o pesos (ingreso) |

Cohorte y año de ingreso están confundidos en cada punto (cada cohorte se mide en otro año): las series sirven como control de estabilidad, no para separar el efecto de cohorte.

---

## Esquema `qa`

### `qa.control` — resultado de los controles del último build
**Grano:** un control × objeto evaluado. **Llave:** `(control, objeto)`. **Origen:** `src/BD/04_qa.sql` y `_controlar_esquemas()` de `src/BD/build.py`. Si algún control queda en `FALLA` el build se revierte, así que en la base solo hay resultados `OK` o `EXENTO`; las fallas se ven en el log del build.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| `control` | text | no | `contrato_esquema` \| `cohorte_en_sies` \| `origen_series` |
| `objeto` | text | no | Tabla `raw`, indicador de `modelo.cohorte` o serie evaluada |
| `estado` | text | no | `OK` \| `FALLA` \| `EXENTO` (no aplica, con el motivo en `detalle`) |
| `metrica` | numeric | sí | Valor medido: n.º de problemas, años faltantes o mediana del error en % |
| `umbral` | text | no | Criterio de aprobación, legible |
| `detalle` | text | no | Evidencia (columnas, años faltantes, errores por desfase) |

| Control | Aprueba si |
|---|---|
| `contrato_esquema` | Las columnas de la tabla `raw` coinciden con su `esquema.py` en nombre, orden y tipo compatible |
| `cohorte_en_sies` | Cada año de cohorte del indicador tiene titulaciones en `modelo.titulacion`; las series quedan `EXENTO` (D5) |
| `origen_series` | Mediana del \|error relativo\| entre el agregado publicado y el promedio de los 3 puntos de sus cohortes < 1 %, ≤ la mitad de la de las ventanas corridas −1/−2 años, con ≥ 100 pares |

---

## Relaciones

Diagrama completo con columnas, PK, FK y linaje desde `raw`: [`diagrama_modelo.md`](diagrama_modelo.md) (Mermaid), generado desde el catálogo de la base con `python3 src/BD/diagrama.py`.

```
institucion ──< titulacion >── carrera_generica
     │                              │  │
     └──< mifuturo_programa >───────┘  │
                                       │
              mifuturo_estadistica >───┘
                     │
                     └──< mifuturo_serie >── cohorte
```

`mifuturo_programa` y `mifuturo_estadistica` se unen por `(clave_carrera_generica, tipo_institucion)` sin FK: 48 programas no tienen estadística publicada y 3 estadísticas no tienen institución publicada.
