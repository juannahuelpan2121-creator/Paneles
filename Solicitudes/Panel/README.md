# Panel de Solicitudes Operacionales

Proyecto Power BI con interfaz MODUSS estratégica y datos de Banner Workflow en Athena.

## Páginas

1. Resumen operacional.
2. Inscripción extraordinaria (lógica aprobada).
3. Cambio de calificación (lógica aprobada).
4. Reincorporación.
5. Continuidad de estudios.
6. Cambio de carrera/sede.
7. Suspensión.
8. Inscripción especial.
9. Retiro.
10. Sábana completa para exportación.

## Criterios

- La consulta genérica conserva el histórico sin filtro temporal fijo.
- El formato largo contiene una fila por solicitud y propiedad.
- Los indicadores cuentan `DISTINCT id`, evitando inflar los resultados por la cantidad de propiedades.
- `FINALIZADA`, `EN CURSO`, `CANCELADA` y `OTRO` se determinan a partir del estado y ejecución del workflow.
- Periodo, sede, nivel y RUT se detectan desde las propiedades disponibles en cada formulario.

## Exportación

En **Resumen operacional**, el botón **Descargar sábana completa** navega a la página de datos crudos. Para exportar: seleccionar la tabla, abrir `...` y elegir **Exportar datos**.

## Lienzo

Todas las páginas usan 1280 x 1800 px y `ActualSize`, siguiendo el ejemplo estratégico MODUSS.
