# Panel de Solicitudes Operacionales

Proyecto Power BI con interfaz MODUSS estratégica y datos de Banner Workflow en Athena.

## Páginas

1. Resumen operacional.
2. Inscripción especial, con clasificación Especial/Extraordinaria.
3. Cambio de calificación (lógica aprobada).
4. Reincorporación.
5. Continuidad de estudios.
6. Cambio de carrera/sede.
7. Suspensión.
8. Retiro.
9. Sábana completa para exportación.

La página técnica anterior de inscripción extraordinaria se mantiene oculta en
modo lectura como respaldo, pero ya no aparece en el menú de navegación.

## Criterios

- La consulta genérica conserva el histórico sin filtro temporal fijo.
- La sábana del panel contiene una fila operacional por solicitud, sin duplicados.
- La extracción completa de propiedades se entrega en `Queries/workflow_propiedades_json.sql` y no se importa al modelo.
- Los indicadores cuentan `DISTINCT id`, evitando inflar los resultados por la cantidad de propiedades.
- `FINALIZADA`, `EN CURSO`, `CANCELADA` y `OTRO` se determinan a partir del estado y ejecución del workflow.
- El período se normaliza extrayendo un código académico de seis dígitos desde las propiedades del formulario.
- La duración promedio excluye sábados y domingos.
- `Solicitudes Sobre Promedio` cuenta procesos finalizados cuya duración en días
  hábiles supera el promedio del contexto de filtros vigente.
- Inscripción especial y extraordinaria comparten una sola categoría analítica;
  `tipo_clasificacion` conserva ambas opciones para el filtro funcional.
- Sede, nivel y RUT se detectan desde las propiedades disponibles en cada formulario.
- La sede del filtro se homologa contra `banner_oracle_saturn_stvcamp` y se
  presenta como `código - descripción`; `sede_workflow` conserva el texto
  original para la sábana descargable.

## Modelo optimizado

- `solicitudes_workflow`: base operacional transversal, una fila por solicitud; alimenta el resumen, la sábana y seis páginas de tipologías.
- `solicitudes_inscripcion` y `solicitudes_calificacion`: bases detalladas aprobadas para sus páginas específicas; no se suman entre sí ni con la base transversal.
- `dim_periodo` y `dim_estado`: dimensiones compartidas por las tres bases de solicitudes.
- `Medidas Solicitudes`: tabla técnica de medidas y HTML, sin datos operacionales duplicados.
- Se retiraron `solicitudes_consolidadas` y `dim_tipo_solicitud` porque no tenían consumidores en el informe.

## Exportación

En **Resumen operacional**, el botón **Descargar sábana completa** navega a la página de datos crudos. Para exportar: seleccionar la tabla, abrir `...` y elegir **Exportar datos**.

## Lienzo

Todas las páginas usan 1280 x 1800 px y `ActualSize`, siguiendo el ejemplo estratégico MODUSS.
