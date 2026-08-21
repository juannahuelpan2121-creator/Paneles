# Panel de Solicitudes Operacionales

Proyecto Power BI construido con la interfaz del Kit Power BI Referencias USS.

## Páginas

1. **Resumen operacional**: solicitudes totales, finalizadas, en curso, tasa de finalización y distribución consolidada por periodo, tipo y estado.
2. **Inscripción extraordinaria**: indicadores y sábana histórica completa del workflow `19994978`.
3. **Cambio de calificación**: indicadores y sábana histórica completa del workflow `17504561`.

## Regla de estado

- `FINALIZADA`: `stop_date` informado o `running = false`.
- `EN CURSO`: cualquier otro caso.
- `estado_actual` y `ultimo_estado` se mantienen para análisis técnico detallado.

## Datos y actualización

- Conexión: `dsn=uss-athena-datalake-prod`.
- Las queries no contienen filtro de periodo y cargan el histórico completo disponible.
- Los `pd_id` identifican el tipo de workflow; no corresponden al RUT del estudiante.
- Para una carga productiva de gran volumen se recomienda configurar actualización incremental en Power BI Service.

## Exportación

Las páginas de detalle contienen todas las columnas de cada query. Para descargar la sábana: seleccionar la tabla, abrir `...` y elegir **Exportar datos**.

## Apertura

Abrir el archivo `.pbip` ubicado en esta carpeta con Power BI Desktop y actualizar las credenciales del DSN Athena si fueran solicitadas.