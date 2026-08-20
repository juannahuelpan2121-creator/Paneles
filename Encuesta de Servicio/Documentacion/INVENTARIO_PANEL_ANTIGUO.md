# Inventario técnico del panel antiguo de Encuesta de Servicio

## Origen del inventario

Modelo revisado:

`C:\Users\juan.nahuelpan\OneDrive - Universidad San Sebastian\Desktop\Nueva carpeta (3)\ES_Reporte_Encuesta_Servicio_Pregrado.pbip`

Este documento registra la estructura encontrada en el modelo legado para apoyar la trazabilidad y la migración al panel modernizado.

## Resumen

- Tablas del modelo semántico: **16**.
- Tablas funcionales o auxiliares: **13**.
- Tablas automáticas de fecha de Power BI: **3**.
- Relaciones activas: **11**.
- Tabla principal de respuestas: `NPS`.
- Tabla principal de estudiantes: `RA3_Alumnos`.

## Tablas funcionales

| Tabla | Tipo | Columnas | Medidas | Uso principal |
|---|---:|---:|---:|---|
| `NPS` | Power Query / Athena | 56 | 24 | Respuestas de encuesta, alumno, período, NRC, campus, carrera y preguntas P1-P20. |
| `NPS_TR` | Power Query / Athena | 24 | 4 | Versión transformada para tasa de respuesta y resultados agregados. |
| `RA3_Alumnos` | Power Query / Athena | 45 | 0 | Maestro académico de estudiantes. |
| `RA3_Alumnos_maxperiodo` | Derivada de `RA3_Alumnos` | 34 | 0 | Último período por estudiante, nivel y modalidad. |
| `Nuevos_202610` | Power Query / Excel | 18 | 0 | Identificación de estudiantes nuevos del período 202610. |
| `Cod_Encuestas` | Power Query / Excel | 8 | 0 | Catálogo de códigos de encuesta. |
| `Preguntas_Cod_En` | Power Query / Excel | 8 | 0 | Correspondencia entre encuesta y preguntas. |
| `Facultad` | Power Query / Excel | 9 | 0 | Homologación de carrera y facultad. |
| `dim_sedes` | Tabla interna | 5 | 0 | Catálogo de sede, campus y código de campus. |
| `Excepciones` | Tabla interna | 2 | 0 | Lista manual de RUT y excepciones. |
| `Actualización` | Tabla interna | 2 | 1 | Fecha y hora de actualización del informe. |
| `dim_calendario` | Tabla interna | 1 | 0 | Año utilizado como apoyo para filtros. |
| `Calendario` | Tabla calculada | 1 | 0 | Calendario utilizado por el modelo. |

## Tablas automáticas de fecha

Estas tablas fueron generadas por la inteligencia de tiempo automática de Power BI y no representan fuentes institucionales:

- `DateTableTemplate_dc7fa80e-9205-4854-ae41-fa22e1b6eb36`
- `LocalDateTable_03225eb2-90b5-4f10-89e4-01590ffb3f42`
- `LocalDateTable_209be21c-39fc-4678-a1fd-bdf8745eaf2a`

## Fuentes físicas consultadas

### Banner mediante Athena

Las consultas `NPS` y `NPS_TR` utilizan las siguientes tablas del esquema `banner9_prod`:

- `SVRESAF`
- `SVRESAS`
- `SVBTESD`
- `SPRIDEN`
- `SSBSECT`
- `STVCAMP`
- `SCBCRSE`
- `GOREMAL`
- `STVCOLL`
- `STVMAJR`

La consulta está configurada mediante el DSN `uss-athena` y considera encuestas como `ESSPRE24`, `NPSONL`, `NPSPRES`, `ESSONL24` y, en `NPS`, `ESSONL25`.

### Maestro académico

- `analytics_r_operacionales_academia.ra_3_alumnos`

### Archivos Excel

- `Codigos Encuestas.xlsx`: alimenta `Cod_Encuestas` y `Preguntas_Cod_En`.
- `Carrera-Facultades nuevas 2025.xlsx`: alimenta `Facultad`.
- `Nuevos_2026210.xlsx`: alimenta `Nuevos_202610`.

Las rutas originales están asociadas al OneDrive de una usuaria específica. Deben reemplazarse por una ubicación institucional administrada antes de reutilizar el modelo.

## Relaciones del modelo antiguo

| Desde | Hacia | Dirección |
|---|---|---|
| `Calendario[Date]` | `LocalDateTable_03225...[Date]` | Una dirección |
| `Actualización[Ultima Actualización]` | `LocalDateTable_209be...[Date]` | Una dirección |
| `NPS_TR[Codigo_campus]` | `dim_sedes[Codigo Campus]` | Una dirección |
| `NPS[llave rut_nivel_modalidad]` | `RA3_Alumnos_maxperiodo[llave (rut,nivel,modalidad)]` | Una dirección |
| `NPS[codigo_campus_final]` | `dim_sedes[Codigo Campus]` | Ambas direcciones |
| `NPS[llave_rut_periodo_nivel_modalidad]` | `RA3_Alumnos[llave (rut,periodo,nivel,modalidad)]` | Una dirección |
| `NPS[llave (cod en_preg)]` | `Preguntas_Cod_En[llave (codenc_preg)]` | Ambas direcciones |
| `Cod_Encuestas[Codigo]` | `Preguntas_Cod_En[Codigo_ENC]` | Ambas direcciones |
| `NPS[RUT_ALUMNO]` | `Nuevos_202610[RUT]` | Una dirección |
| `NPS[codigo_carrera_final]` | `Facultad[Cod_carrera]` | Ambas direcciones |
| `NPS_TR[PERIODO_ENCUESTA]` | `NPS[PERIODO_ENCUESTA]` | Ambas direcciones |

## Observaciones para la migración

1. El modelo antiguo contiene RUT, nombres y correos de estudiantes y docentes. El modelo modernizado debe mantener identificadores anonimizados.
2. Existen varias relaciones bidireccionales entre tablas de hechos o tablas de granularidad distinta. Esto puede producir ambigüedad, duplicidades y tasas superiores a 100 %.
3. `NPS` y `NPS_TR` repiten una consulta extensa a Banner. Conviene centralizar la extracción y reutilizar una sola fuente normalizada.
4. Las respuestas P1-P20 están presentadas como columnas. El modelo nuevo utiliza una estructura por pregunta, más apropiada para análisis y mantenimiento.
5. Los archivos Excel y las rutas personales son dependencias frágiles. Se recomienda trasladar los catálogos a Athena o a una ubicación institucional gobernada.
6. Las tablas automáticas de fechas pueden reemplazarse por una única dimensión calendario oficial.
7. `RA3_Alumnos_maxperiodo` elimina períodos `202600`, `202615` y `202620` antes de calcular el máximo; esta regla debe validarse funcionalmente antes de replicarla.
8. El modelo antiguo relaciona directamente respuestas con `RUT_ALUMNO`. La consulta agregada del panel nuevo no expone ese identificador, por lo que no permite atribuir una respuesta individual a un estudiante.

## Correspondencia general con el panel modernizado

| Modelo antiguo | Modelo modernizado |
|---|---|
| `NPS` / `NPS_TR` | `encuestas_docentes` y medidas de Encuesta de Servicio |
| `RA3_Alumnos` / `RA3_Alumnos_maxperiodo` | `maestro_estudiantes` |
| Inscritos incluidos en consultas agregadas | `inscripciones_estudiantes` |
| `Facultad` | `dim_carrera` y atributos normalizados del maestro |
| Nivel derivado mediante llaves del RA3 | `dim_nivel_academico` y asignación controlada por período-NRC |
| Tablas automáticas de fecha | Filtros explícitos de período del modelo nuevo |

