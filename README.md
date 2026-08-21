# Paneles Power BI USS

Repositorio de paneles Power BI en formato PBIP, consultas de Data Lake y
utilidades de validación.

## Solicitudes Operacionales

La última versión está en:

`solicitudes-op/Solicitudes Operacionales.pbip`

El panel contiene:

- resumen operacional consolidado;
- detalle histórico de inscripción extraordinaria;
- detalle histórico de cambio de calificación;
- menú y filtros basados en el kit estratégico MODUSS;
- tooltip metodológico en el encabezado;
- consultas históricas sin filtro fijo de período.

Las consultas SQL independientes están en `Solicitudes/Queries`.

## Validación

Desde la raíz del repositorio:

```powershell
python tools/validate_solicitudes_panel.py "Solicitudes/Solicitudes Operacionales"
```

La validación revisa JSON, referencias de tablas y medidas, bookmarks, grupos,
recursos, navegación MODUSS, tipos de fechas y problemas de codificación.

## Generación

`tools/build_solicitudes_panel.ps1` conserva el proceso utilizado para generar
la solución. El script espera que el kit de referencia y el directorio local de
paneles estén disponibles bajo la carpeta institucional configurada en el
encabezado del archivo.
