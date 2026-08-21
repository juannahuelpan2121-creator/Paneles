# Migracion de queries Workflow al Data Lake

## Homologaciones aplicadas

| Tabla de origen | Tabla Data Lake |
|---|---|
| `ENG_WORKFLOW` | `uss_datalake_stage.banner_oracle_workflow_eng_workflow` |
| `ENG_PROPERTIES_VALUES` | `uss_datalake_stage.banner_oracle_workflow_eng_properties_values` |
| `SSBSECT` | `uss_datalake_stage.banner_oracle_saturn_ssbsect` |
| `SCBCRSE` | `uss_datalake_stage.banner_oracle_saturn_scbcrse` |

Las dos primeras homologaciones fueron entregadas por el usuario. Las de `SSBSECT`
y `SCBCRSE` se validaron contra las consultas vigentes del proyecto y el Diccionario
de Datos Maestro.

## Optimizaciones

1. Se reemplazaron las subconsultas correlacionadas repetidas por agregacion
   condicional (`MAX(CASE WHEN...)`) sobre una lectura acotada de propiedades.
2. La consulta de inscripcion transforma temporalmente los 12 NRC en filas,
   realiza un solo enriquecimiento contra `SSBSECT`/`SCBCRSE` y luego recupera
   el formato ancho original.
3. La vigencia del nombre del curso se determina con la mayor
   `scbcrse_eff_term` menor o igual al periodo consultado.
4. La limpieza de textos y HTML se simplifico con `REGEXP_REPLACE`.
5. Periodo y `pd_id` quedaron centralizados en el CTE `parametros`.
6. Se reconciliaron las versiones operacionales entregadas el 21-08-2026. En
   cambio de calificacion se conserva el reemplazo de comas por punto en el
   comentario para evitar cortes al exportar CSV.
7. `start_date` y `stop_date` se preservan como epoch Unix en milisegundos para
   evitar conversiones implícitas del controlador ODBC. El modelo crea las
   columnas de fecha `start_datetime` y `stop_datetime` después de cargar los
   enteros, con una conversión DAX estable y verificable.

## Consideraciones antes de produccion

- Las consultas estan escritas para Amazon Athena / Trino.
- Se preservaron los nombres y el orden funcional de las columnas originales.
- `MAX(CASE...)` supone que las propiedades escalares tienen un solo valor por
  workflow y nombre. Si existen duplicados historicos, se debe identificar una
  columna de fecha o secuencia en `ENG_PROPERTIES_VALUES` y reemplazar `MAX` por
  `MAX_BY(value, columna_orden)`.
- La limpieza de HTML es deliberadamente general. Conviene comparar una muestra
  de `NRCS_SOLICITADOS` y `NRCS_RECHAZADO` contra la salida antigua.
- No existe filtro fijo de periodo: ambas consultas cargan el historico completo
  disponible para el tipo de workflow.
- Los filtros `202610` presentes en las consultas operacionales adjuntas se
  eliminaron deliberadamente para conservar el requerimiento de analisis
  historico y descarga completa.
- Se mantienen los `pd_id` originales porque identifican el proceso, no al
  estudiante: `19994978` para inscripcion extraordinaria y `17504561` para
  cambio de calificacion.
- Se agrego `estado_operacional`: una solicitud se considera `FINALIZADA` si
  posee `stop_date` o si `running` es falso; en caso contrario queda `EN CURSO`.
