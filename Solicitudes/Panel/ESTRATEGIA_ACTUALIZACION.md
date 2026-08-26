# Estrategia de actualización — Solicitudes Operacionales

## Estado del modelo

El modelo mantiene seis tablas y todas tienen referencias activas en el informe o
en el modelo semántico:

- `solicitudes_workflow`: fuente consolidada para el resumen, la sábana y las
  vistas operacionales por tipo de solicitud.
- `solicitudes_inscripcion`: detalle aprobado de inscripción extraordinaria.
- `solicitudes_calificacion`: detalle aprobado de cambio de calificación.
- `dim_periodo` y `dim_estado`: dimensiones calculadas utilizadas por páginas de
  detalle.
- `Medidas Solicitudes`: tabla técnica que centraliza las medidas DAX.

No se elimina ninguna de estas tablas porque hacerlo rompería visuales vigentes.
Tampoco se duplica la carga consolidada: `solicitudes_workflow` conserva una fila
por solicitud.

## Actualización recomendada

1. Actualizar `solicitudes_workflow` cuando cambie la extracción consolidada de
   Workflow o se requiera renovar el resumen y la sábana.
2. Actualizar `solicitudes_inscripcion` y `solicitudes_calificacion` cuando se
   necesite renovar sus páginas de detalle aprobadas.
3. Las dimensiones calculadas y la tabla de medidas se recalculan con el modelo;
   no ejecutan consultas adicionales en Athena.
4. Mantener el plegado de consulta: la selección, homologación y deduplicación
   deben resolverse en las consultas Athena antes de importar los datos.
5. En Power BI Service, programar la actualización fuera del horario operacional
   y supervisar duración, filas importadas y consumo de capacidad.

## Actualización incremental

La actualización incremental no se activa automáticamente en este PBIP. Para
habilitarla se deben crear los parámetros `RangeStart` y `RangeEnd`, aplicar el
filtro a una columna de fecha que preserve query folding y definir la política de
retención en Power BI Desktop o Fabric. Esta configuración debe validarse primero
con el historial real disponible y la capacidad asignada para no excluir
solicitudes antiguas todavía activas.

## Recursos visuales

El logotipo USS está incrustado como recurso registrado dentro del informe. Esto
evita dependencias de rutas locales. Una URL de OneLake solo debe incorporarse
cuando exista una ubicación institucional estable, autenticada y aprobada.

## Mejoras incorporadas

- Filtros de rango para fecha de ingreso y fecha de cierre en Resumen operacional
  y Sábana completa.
- Los nuevos filtros conservan la interfaz neutra del kit, sin colores agregados.
- Matriz operacional jerárquica por tipo de solicitud, sede y estado.
- Indicadores de volumen, duración hábil promedio y solicitudes fuera del
  promedio dentro de la matriz.
- Los encabezados muestran los rangos de fecha únicamente cuando están filtrados.
- Tema institucional conservado exactamente según
  `01_Ejemplo_Estrategico_MODUSS`.
