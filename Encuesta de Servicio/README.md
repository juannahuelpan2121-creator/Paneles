# Encuesta de Servicio - proyecto Power BI

Proyecto PBIP construido a partir del patrón estratégico del **Kit Power BI Referencias**.

## Apertura

Abra `Encuesta de Servicio.pbip` con Power BI Desktop. El proyecto se entrega sin datos importados; al actualizar solicitará acceso al DSN de Athena configurado en el parámetro `AthenaDSN` (`uss-athena-datalake-prod`).

## Alcance funcional

La query recibida contiene encuestas docentes y encuestas de servicio. El proyecto identifica el alcance mediante `nombre_encuesta` y conserva solamente registros cuya glosa contiene `SERVICIO` (comparación sin distinguir mayúsculas/minúsculas).

El panel implementa:

- total de respuestas;
- neto de evaluación: `(votos 4+5 - votos 1+2) / votos 1..5`;
- satisfacción: `votos 4+5 / votos 1..5`;
- promedio reconstruido en escala 0 a 7;
- tasa de respuesta: respondidas / estudiantes únicos inscritos con estado `RE` o `RW`;
- evolución por año y período;
- comparación por campus, facultad, encuesta, categoría y pregunta;
- detalle exportable por curso, encuesta, categoría y pregunta;
- apertura histórica P1-P13, satisfacción general P14, recomendación P15 y orgullo P16;
- supresión del neto desagregado cuando hay menos de 10 respuestas válidas.

Las categorías y preguntas de servicio se toman directamente de `tipo_pregunta_area` y `texto_pregunta`; no se codifican manualmente en DAX.

## Reglas y controles

- La query filtra `año >= 2020`, `ponderación > 0` y `UPPER(nombre_encuesta) LIKE '%SERVICIO%'`.
- El área de pregunta se normaliza en Power Query para reducir duplicados por mayúsculas/minúsculas.
- Las respuestas se deduplican por período, NRC y código de encuesta; el universo se cuenta como estudiantes únicos por período y NRC.
- La tabla de inscripción conserva todos los estados desde 202400 para auditoría y marca `RE/RW` como inscripción real, en concordancia con los tres maestros institucionales.
- Los maestros de Pregrado, Advance y Postgrado se incorporan desde 202400 con carrera, programa, sede, facultad y condición del estudiante.
- El identificador del estudiante se transforma a SHA-256 en Athena; no se cargan RUT, nombres ni correos al modelo semántico.
- La consulta agregada de respuestas todavía no expone el identificador del encuestado. Por ello los maestros describen el universo inscrito, pero no permiten atribuir una respuesta individual a un estudiante hasta ampliar esa consulta.
- Antes de publicar, valide con la Dirección de Docencia el mapeo de la escala 0-7 y los umbrales funcionales.

## Estructura

- `Encuesta de Servicio.Report`: definición visual PBIR y recursos del kit.
- `Encuesta de Servicio.SemanticModel`: modelo TMDL, consulta Athena y medidas DAX.
- `Documentacion/ENCUESTAS_PREGUNTAS_EVALUADAS.sql`: copia de la query fuente.
- `Documentacion/Fuentes/INSCRIPCIONES_CON_ESTADO_DESDE_202400.sql`: estudiantes por periodo, NRC y estado.
- `Documentacion/Fuentes/MAESTRO_ESTUDIANTES_*_DESDE_202400.sql`: maestros ajustados de Pregrado, Advance y Postgrado.
- `Documentacion/VALIDACION_FUNCIONAL.md`: controles previos a publicación.
- `Documentacion/INVENTARIO_PANEL_ANTIGUO.md`: tablas, fuentes, relaciones y observaciones técnicas del modelo legado.
- Hojas: Resumen y participación, Resultados y segmentación, Campus y contexto académico, Evolución y comparativos, Detalle de preguntas y Metodología.
- La estructura antigua de 22 hojas se consolidó en 6 páginas mediante filtros y matrices reutilizables.
- Los gráficos principales incluyen el campo `Tooltip Metodología` para explicar las fórmulas al pasar el cursor.
