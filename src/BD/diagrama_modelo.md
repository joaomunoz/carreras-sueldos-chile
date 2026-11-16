# Diagrama ER — base `carreras_sueldos`

> Generado desde el catálogo de PostgreSQL por `src/BD/diagrama.py`; no editar a mano.
> Regenerar con `python3 src/BD/diagrama.py` tras cambiar `src/BD/01_raw.sql` o `src/BD/02_modelo.sql`.

Lectura: línea sólida = FK (una fila de la tabla referida, cero o muchas que la referencian),
rotulada con sus columnas · línea punteada = la tabla `raw` desde la que se puebla
(`src/BD/03_poblar_modelo.sql`) · `"NULL"` = la columna admite nulos.
Detalle de cada columna en [`diccionario_datos.md`](diccionario_datos.md).

```mermaid
erDiagram
    carrera_generica {
        text clave_carrera_generica PK
        text nombre
        text nivel_carrera
    }
    cohorte {
        text indicador PK
        text fuente
        smallint cohorte_desde
        smallint cohorte_hasta
        smallint anio_ingreso_desde "NULL"
        smallint anio_ingreso_hasta "NULL"
        smallint min_casos "NULL"
        text referencia
    }
    institucion {
        int codigo_institucion PK
        text nombre
        text tipo_institucion
    }
    mifuturo_estadistica {
        text clave_carrera_generica PK, FK
        text tipo_institucion PK
        int id_estadisticas
        text area_conocimiento_mineduc
        int ingreso_medio_1er_anio
        int ingreso_medio_2do_anio
        int ingreso_medio_3er_anio
        int ingreso_medio_4to_anio
        int ingreso_medio_5to_anio
        int percentil_10_anio_1
        int percentil_25_anio_1
        int percentil_50_anio_1
        int percentil_75_anio_1
        int percentil_90_anio_1
        int percentil_10_anio_5
        int percentil_25_anio_5
        int percentil_50_anio_5
        int percentil_75_anio_5
        int percentil_90_anio_5
        numeric empleabilidad_1er_anio
        numeric empleabilidad_2do_anio
        int titulados_2024
        int titulados_2024_mujeres
        int titulados_2024_hombres
        numeric duracion_formal_semestres "NULL"
        numeric duracion_real_semestres "NULL"
    }
    mifuturo_programa {
        int codigo_institucion PK, FK
        text tipo_institucion FK
        text clave_carrera_generica PK, FK
        text carrera
        smallint acreditacion_anios
        numeric pct_continuidad_estudios
        numeric duracion_real_semestres "NULL"
        numeric empleabilidad_1er_anio
        numeric empleabilidad_2do_anio "NULL"
        int ingreso_4to_anio_tramo_min "NULL"
        int ingreso_4to_anio_tramo_max "NULL"
    }
    mifuturo_serie {
        text clave_carrera_generica PK, FK
        text tipo_institucion PK, FK
        text indicador PK, FK
        smallint cohorte PK
        numeric valor
    }
    titulacion {
        smallint anio PK
        text codigo_programa PK
        int codigo_institucion FK
        text clave_carrera_generica FK
        text carrera
        text subtipo_institucion
        bool es_convenio
        text cine13_area
        text cine13_subarea
        text carrera_clasificacion_nivel_1
        text tipo_plan
        text modalidad
        text jornada
        numeric duracion_semestres
        int total_titulaciones
        int titulaciones_mujeres
        int titulaciones_hombres
        int titulaciones_nb
        int titulados_15_19
        int titulados_20_24
        int titulados_25_29
        int titulados_30_34
        int titulados_35_39
        int titulados_mayores_40
        int titulados_edad_sin_info
        numeric edad_promedio "NULL"
    }
    raw_empleabilidad {
        int id_institucion PK
        text clave_carrera_generica PK
        text otras_12_columnas "ver esquema.py"
    }
    raw_estadisticas {
        text tipo_institucion PK
        text clave_carrera_generica PK
        text otras_40_columnas "ver esquema.py"
    }
    raw_titulados {
        smallint anio PK
        text codigo_programa PK
        text otras_28_columnas "ver esquema.py"
    }

    carrera_generica ||--o{ mifuturo_estadistica : "clave_carrera_generica"
    carrera_generica ||--o{ mifuturo_programa : "clave_carrera_generica"
    institucion ||--o{ mifuturo_programa : "codigo_institucion, tipo_institucion"
    cohorte ||--o{ mifuturo_serie : "indicador"
    mifuturo_estadistica ||--o{ mifuturo_serie : "clave_carrera_generica, tipo_institucion"
    carrera_generica ||--o{ titulacion : "clave_carrera_generica"
    institucion ||--o{ titulacion : "codigo_institucion"
    raw_titulados ||..|{ institucion : "puebla"
    raw_titulados ||..|{ carrera_generica : "puebla"
    raw_titulados ||..|{ titulacion : "puebla"
    raw_empleabilidad ||..|{ mifuturo_programa : "puebla"
    raw_estadisticas ||..|{ mifuturo_estadistica : "puebla"
    raw_estadisticas ||..|{ mifuturo_serie : "puebla"
```
