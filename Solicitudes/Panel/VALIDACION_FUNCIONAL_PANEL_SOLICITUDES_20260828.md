# Validación funcional — Solicitudes Operacionales

Fecha de preparación: 28-08-2026  
Objetivo: documentar la equivalencia funcional entre los reportes históricos y el nuevo panel unificado, y entregar una pauta de validación previa al visto bueno productivo.

## 1. Criterio de diseño aplicado

El panel nuevo conserva la capacidad de análisis de los reportes anteriores, pero no replica literalmente su distribución. La información se organiza para reducir saturación visual y facilitar la lectura:

- resumen compacto por campus a la izquierda;
- evolución por período a la derecha;
- detalle exportable bajo los elementos de síntesis;
- filtros dentro de un panel lateral desplegable;
- encabezado, navegación, tipografía y colores institucionales del kit MODUSS;
- lienzo vertical ampliado en las hojas que requieren mayor detalle.

La matriz histórica `Campus × Ejecución/Finalizada` se conserva conceptualmente mediante una matriz por campus con tres medidas: total, en curso y finalizadas. Esto agrega el total sin perder los dos estados que utilizaba el reporte anterior.

## 2. Equivalencia de filtros por hoja

| Hoja | Filtros del panel anterior | Filtros disponibles en el panel nuevo | Observación |
|---|---|---|---|
| Resumen operacional | Período, tipo de solicitud, estatus, sede | Período, tipo/categoría, estado operacional, sede, fecha de inicio y fecha de cierre | Se agregan fechas para análisis histórico y se utiliza sede normalizada. |
| Reincorporación | Período, estatus, código campus, código carrera, RUT alumno, última actividad | Período, estado operacional, estado actual, sede, nivel, RUT, última actividad, fecha de inicio y fecha de cierre | Carrera no está disponible como atributo homogéneo en la tabla optimizada de workflows. |
| Continuidad de estudios | Estatus, estado workflow, campus, carrera, período, RUT, última actividad | Período, estado operacional, estado actual, sede, nivel, RUT, última actividad, fecha de inicio y fecha de cierre | Estado operacional reemplaza la agrupación técnica Ejecución/Finalizada; estado actual conserva el detalle del workflow. |
| Cambio de carrera/sede | Estatus, estado workflow, campus origen, carrera destino, período, RUT, última actividad | Período, estado operacional, estado actual, sede normalizada, nivel, RUT, última actividad, fecha de inicio y fecha de cierre | Campus/carrera de destino requieren homologación de propiedades si se exigen como filtros separados. |
| Suspensión | Período, estatus, campus, carrera, RUT, última actividad | Período, estado operacional, estado actual, sede, nivel, RUT, última actividad, fecha de inicio y fecha de cierre | Mantiene el análisis operativo y agrega rango de fechas. |
| Retiro | Filtros equivalentes a las solicitudes generales | Período, estado operacional, estado actual, sede, nivel, RUT, última actividad, fecha de inicio y fecha de cierre | Nueva hoja integrada al mismo modelo y navegación. |
| Inscripción especial | Período, estatus, campus, carrera, RUT y campos propios de inscripción | Período, clasificación, estado operacional, estado actual, sede, nivel, RUT, última actividad, fecha de inicio y fecha de cierre | La clasificación permite distinguir Especial y Extraordinaria dentro de la familia de inscripción. |
| Inscripción extraordinaria | Período, estatus, campus, carrera, RUT, NRC y antecedentes de inscripción | Período, estado operacional, estado actual, sede, carrera, nivel, RUT, última actividad, NRC solicitados, fecha de inicio y fecha de cierre | La tabla de inscripción conserva el detalle de NRC solicitado. |
| Cambio de calificación | Período, estatus, campus, carrera, RUT, NRC, materia y curso | Período, estado operacional, estado actual, campus, carrera, nivel, RUT, última actividad, NRC, curso, fecha de inicio y fecha de cierre | `Materia` no existe como columna independiente en la fuente aprobada; no se crea un valor inferido. |
| Sábana completa | Descarga de tabla completa | Período, categoría, estado operacional, estado actual, sede, nivel, RUT, última actividad, fechas y tabla a una fila por solicitud | Preparada para exportación y conciliación. |

## 3. Diferencias principales entre el panel antiguo y el nuevo

| Aspecto | Panel anterior | Panel nuevo |
|---|---|---|
| Arquitectura | Un PBIX separado por proceso | Un PBIP unificado con navegación entre hojas |
| Modelo | Consultas y lógicas repetidas por informe | Modelo semántico común y medidas reutilizadas |
| Campus/sede | Códigos y descripciones mezclados | Sede normalizada mediante catálogo STVCAMP, conservando el dato original en la sábana |
| Estados | Ejecución y Finalizada | Total, En curso y Finalizadas, más estado técnico cuando corresponde |
| Período | Incluía valores no académicos en algunos reportes | Período académico validado; las fechas se analizan por filtros específicos |
| Visual principal | Tabla pequeña con gran espacio vacío | Matriz compacta por campus + tendencia temporal + detalle |
| Navegación | Cambio entre informes independientes | Menú lateral dentro del mismo panel |
| Filtros | Slicers permanentes en la cabecera | Panel lateral desplegable y chips en el encabezado |
| Exportación | Botón por reporte | Sábana completa consolidada y tablas de detalle exportables |
| Duración | Sin indicador homogéneo | Duración en días hábiles, excluyendo sábado y domingo |
| Calidad de datos | Riesgo de duplicación por propiedades del workflow | Grano de una fila por solicitud en la tabla optimizada |
| Identificación del estudiante | Algunos identificadores se interpretaban como número | Identificador tratado como texto; conserva prefijos alfanuméricos y ceros iniciales, por ejemplo `E00004890` |
| Seguimiento | Principalmente conteos | KPIs, tasa de finalización, duración y solicitudes fuera del promedio |

## 4. Pauta de validación funcional

Validar al menos un período reciente y uno histórico.

1. Comparar solicitudes totales por tipo y período contra el reporte productivo.
2. Comparar En curso y Finalizadas por sede/campus.
3. Revisar una muestra de identificadores de solicitud en ambas fuentes.
4. Confirmar que el filtro de sede muestre una sola versión normalizada por campus.
5. Confirmar que Estado actual permita revisar el detalle técnico sin alterar la clasificación operacional.
6. Probar filtros de RUT y última actividad en las hojas de proceso.
7. Verificar casos con identificador alfanumérico, confirmando que el valor de la columna coincida con la cabecera de la solicitud (por ejemplo `E00004890`).
8. Probar NRC y curso en Cambio de calificación, y NRC solicitados en Inscripción extraordinaria.
9. Probar el rango de fechas en todas las hojas.
10. Abrir y cerrar Filtros y Menú, verificando que los bookmarks no oculten visuales incorrectos.
11. Exportar la tabla de una hoja y la sábana completa; validar que exista una fila por solicitud.
12. Confirmar que los totales del resumen respondan a todos los filtros aplicados.
13. Revisar rendimiento de apertura, filtrado y exportación con el histórico completo.

## 5. Pendientes que requieren definición funcional

- Confirmar si `Carrera` debe ser obligatoria como filtro en todas las familias de workflow. Actualmente no existe como columna normalizada transversal.
- Confirmar si `Campus origen` y `Carrera destino` de Cambio de carrera/sede deben exponerse por separado; requeriría homologar propiedades específicas del workflow.
- Confirmar si `Materia` es obligatoria en Cambio de calificación. La fuente vigente entrega NRC y curso, pero no una columna independiente de materia.
- Confirmar si el nombre visible debe ser `Inscripción especial`, `Inscripción extraordinaria` o una única familia con clasificación interna. El modelo permite esta última opción.

## 6. Registro de visto bueno

| Validación | Responsable | Resultado | Observación |
|---|---|---|---|
| Totales y estados |  | Pendiente |  |
| Filtros por proceso |  | Pendiente |  |
| Navegación y diseño |  | Pendiente |  |
| Sábana y exportación |  | Pendiente |  |
| Rendimiento |  | Pendiente |  |
| Aprobación para productivo |  | Pendiente |  |
