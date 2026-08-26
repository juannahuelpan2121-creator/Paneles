# Contexto de traspaso para IA institucional — Paneles Power BI USS

**Fecha de actualización:** 26 de agosto de 2026  
**Repositorio:** `juannahuelpan2121-creator/Paneles`  
**Rama de trabajo vigente:** `main`  
**Propósito:** entregar contexto técnico, funcional y operativo suficiente para continuar el desarrollo sin repetir diagnósticos ni perder decisiones aprobadas.

> Este documento es contexto descriptivo. No autoriza por sí mismo publicaciones, cambios en producción, eliminación de archivos ni modificaciones funcionales. La IA que lo reciba debe confirmar la solicitud vigente del usuario antes de ejecutar acciones.

## 1. Resumen ejecutivo

Se modernizaron dos soluciones Power BI institucionales utilizando el kit visual estratégico MODUSS:

1. **Encuesta de Servicio**: migración del panel legado a una interfaz moderna, consolidación de páginas, incorporación de inscripción y maestros estudiantiles y reconstrucción de indicadores de satisfacción, neto y participación.
2. **Solicitudes Operacionales**: panel histórico de solicitudes académicas basadas en Banner Workflow, con resumen operacional, páginas por tipología, filtros laterales, navegación, sábana exportable y una consulta transversal optimizada a una fila por solicitud.

Principios que se han mantenido:

- conservar trazabilidad entre dato original y dato homologado;
- evitar duplicaciones por diferencias de granularidad;
- calcular indicadores con identificadores únicos;
- usar fuentes institucionales del Data Lake en lugar de catálogos manuales cuando sea posible;
- preservar los ajustes visuales realizados directamente por el usuario en Power BI;
- aplicar la interfaz, tipografía, colores, navegación, tooltips y proporciones del ejemplo estratégico MODUSS;
- versionar en GitHub únicamente después de validar estructura, consultas y referencias.

## 2. Ubicaciones y fuentes de verdad

### 2.1 Repositorio Git

Ruta local:

```text
C:\Users\juan.nahuelpan\Documents\Codex\2026-08-19\https-github-com-juannahuelpan2121-creator-paneles
```

Remoto:

```text
https://github.com/juannahuelpan2121-creator/Paneles.git
```

Estructura relevante:

```text
Encuesta de Servicio/
Solicitudes/
  Panel/
  Queries/
tools/
```

### 2.2 Proyectos de trabajo en OneDrive

Encuesta:

```text
C:\Users\juan.nahuelpan\OneDrive - Universidad San Sebastian\Desktop\Paneles\Encuesta de Servicio
```

Solicitudes:

```text
C:\Users\juan.nahuelpan\OneDrive - Universidad San Sebastian\Desktop\Paneles\Solicitudes\Solicitudes Operacionales
```

### 2.3 Jerarquía de fuente de verdad

1. Si el usuario acaba de editar un PBIP en Power BI, la carpeta de OneDrive es la versión visual más reciente.
2. Antes de modificarla, confirmar que `PBIDesktop.exe` no tenga ese proyecto abierto y crear un ZIP de respaldo.
3. Realizar cambios quirúrgicos sobre esa versión, evitando regenerar páginas completas.
4. Validar el proyecto.
5. Copiar la versión resultante a la carpeta equivalente del repositorio.
6. Confirmar que los archivos de destino y repositorio coincidan por hash.
7. Crear commit y publicar en `main` cuando el usuario haya pedido conservar la versión.

La carpeta histórica `solicitudes-op/` no es la ubicación canónica actual del panel operacional. Para nuevas modificaciones usar `Solicitudes/Panel/` y la carpeta de OneDrive indicada arriba.

## 3. Estándar visual MODUSS aplicado

Referencia institucional:

```text
C:\Users\juan.nahuelpan\OneDrive - Universidad San Sebastian\Desktop\Paneles\Panel Ejemplo\Kit Power BI Referencias\01_Ejemplo_Estrategico_MODUSS
```

Tema principal:

```text
moduss_unificado_uss.json
```

Características aprobadas:

- fondo principal blanco `#FFFFFF`;
- azul institucional oscuro `#112B42` para títulos, botones principales y navegación activa;
- dorado `#C6B27F` como acento, línea lateral y selección;
- azul claro `#EAF1FB` para chips sin selección;
- dorado claro `#F3E7C4` para chips con filtros activos;
- bordes `#D9DEE7` o `#E1E6ED`;
- tipografía Arial/Segoe UI según el componente;
- encabezado con logo USS, divisor dorado, título, subtítulo, área responsable, tooltip metodológico, botón **Filtros** y botón **Menú**;
- menú lateral izquierdo con oscurecimiento del resto del lienzo;
- panel de filtros lateral derecho con botón de limpieza y cierre;
- botones en formato `pill` cuando corresponde;
- tarjetas blancas con borde izquierdo exclusivamente dorado;
- los filtros seleccionados deben mostrarse en el encabezado y cambiar a dorado;
- lienzos de 1280 px de ancho y al menos 1800 px de alto, con `ActualSize`. El resumen de Solicitudes usa 1850 px porque contiene contenido adicional.

### 3.1 Capas y comportamiento

Los paneles utilizan grupos visuales y bookmarks:

- `{prefijo}_filter_group`
- `{prefijo}_menu_group`
- `{prefijo}_filter_on` / `{prefijo}_filter_off`
- `{prefijo}_menu_on` / `{prefijo}_menu_off`

El grupo de filtros debe quedar por encima de los botones del encabezado y el grupo de navegación por encima del grupo de filtros. El menú usa `pageNavigator`, no una colección de botones independientes.

El tooltip metodológico está incorporado como HTML en el encabezado. Debe aparecer centrado sobre el área útil, con tres columnas funcionales y fuente al pie; no debe desplazarse hacia el extremo derecho ni cubrir los botones.

## 4. Panel Encuesta de Servicio

### 4.1 Objetivo

Analizar satisfacción, evaluación neta, tasa de respuesta y evolución de la Encuesta de Servicio por período, nivel académico, campus, facultad, carrera, categoría y pregunta.

El panel legado estaba en:

```text
C:\Users\juan.nahuelpan\OneDrive - Universidad San Sebastian\Desktop\Nueva carpeta (3)\ES_Reporte_Encuesta_Servicio_Pregrado.pbip
```

El inventario completo del modelo antiguo está en:

```text
Encuesta de Servicio/Documentacion/INVENTARIO_PANEL_ANTIGUO.md
```

### 4.2 Alcance de la encuesta

La consulta fuente contiene encuestas docentes y de servicio. El alcance correcto es:

```sql
UPPER(nombre_encuesta) LIKE '%SERVICIO%'
```

También se consideran preguntas evaluadas con ponderación mayor que cero. Las categorías y preguntas deben obtenerse desde:

- `tipo_pregunta_area`
- `texto_pregunta`

No codificar manualmente las 16 preguntas en DAX si la query ya entrega la clasificación.

Query documentada:

```text
Encuesta de Servicio/Documentacion/ENCUESTAS_PREGUNTAS_EVALUADAS.sql
```

### 4.3 Modelo semántico vigente

Tablas principales:

| Tabla | Propósito |
|---|---|
| `encuestas_docentes` | Resultados agregados por encuesta, período, NRC, categoría y pregunta. |
| `inscripciones_estudiantes` | Inscripción por estudiante, período y NRC; conserva estados para auditoría. |
| `maestro_estudiantes` | Unión de Pregrado, Advance y Postgrado desde 202400. |
| `dim_nivel_academico` | Selector y homologación del nivel académico. |
| `dim_carrera` | Catálogo institucional de carreras y atributos relacionados. |
| `Medidas Encuesta de Servicio` | Medidas DAX, HTML, encabezados y metodología. |

Relación física explícita vigente:

```text
maestro_estudiantes[cod_carrera] -> dim_carrera[sap_cod_carrera]
```

El cruce entre encuestas, inscripción y maestros se resuelve principalmente en las medidas mediante `periodo + NRC` y los conjuntos de estudiantes inscritos. No crear relaciones bidireccionales entre hechos de distinta granularidad sin revisar el impacto.

### 4.4 Asociación de estudiantes y nivel académico

Regla funcional acordada:

1. Tomar únicamente los NRC que aparecen en la encuesta.
2. Buscar estudiantes inscritos en el mismo `periodo + NRC`.
3. Para el maestro, usar `periodo_consulta = periodo de encuesta`.
4. Considerar estudiantes con estado de plan `AS` o condición equivalente a alumno regular.
5. Cuando existan varios planes, usar la mayor secuencia de plan.
6. Cruzar el código de carrera con `dim_carrera`.
7. El origen del maestro define el nivel:
   - Pregrado → `Pregrado`
   - Advance → `Advance`
   - Postgrado → `Postgrado`

Archivos fuente preparados:

```text
Encuesta de Servicio/Documentacion/Fuentes/INSCRIPCIONES_CON_ESTADO_DESDE_202400.sql
Encuesta de Servicio/Documentacion/Fuentes/MAESTRO_ESTUDIANTES_PREGRADO_DESDE_202400.sql
Encuesta de Servicio/Documentacion/Fuentes/MAESTRO_ESTUDIANTES_ADVANCE_DESDE_202400.sql
Encuesta de Servicio/Documentacion/Fuentes/MAESTRO_ESTUDIANTES_POSTGRADO_DESDE_202400.sql
```

Los maestros se combinaron como consultas, agregando una columna de origen. No volver a usar una operación `Distinct`/agrupación con criterios inválidos para intentar consolidarlos; esa estrategia produjo el error **“Los criterios distinct especificados no son válidos”**.

### 4.5 Limitación crítica del nivel académico

La consulta agregada de encuestas no expone un identificador individual del respondente. En consecuencia:

- el universo inscrito sí puede filtrarse exactamente por nivel;
- las respuestas no pueden atribuirse individualmente a Pregrado, Advance o Postgrado;
- las medidas actuales estiman respuestas y votos por nivel proporcionalmente a los inscritos del mismo `periodo + NRC`;
- sin filtro de nivel se muestran los totales reales;
- cualquier futura disponibilidad de un identificador anonimizado del respondente permitiría reemplazar esa estimación por un cruce exacto.

Esta limitación debe mostrarse en la metodología y no ocultarse al usuario funcional.

### 4.6 Reglas de indicadores

| Indicador | Regla |
|---|---|
| Respuestas | Encuestas respondidas según granularidad y filtros. |
| Inscritos | Estudiantes únicos inscritos con estado `RE` o `RW` en los NRC de encuesta. |
| Tasa de respuesta | `Respuestas / Inscritos`. En varios períodos, el denominador se maneja como estudiante-período. |
| Neto | `(votos 4+5 - votos 1+2) / votos 1+2+3+4+5`. |
| Satisfacción | `votos 4+5 / votos 1+2+3+4+5`. |
| Detractores | `votos 1+2 / respuestas válidas`. |
| Neutros | `votos 3 / respuestas válidas`. |
| Promedio | Reconstruido mediante ponderación de la escala entregada. |

Las respuestas 0, 6 y 7 se excluyen del neto. La apertura funcional utilizada es:

- P1–P13: servicios;
- P14: satisfacción general;
- P15: recomendación;
- P16: orgullo.

El neto desagregado se oculta cuando hay menos de 10 respuestas válidas.

Medidas relevantes:

- `N° Respuestas`
- `Inscritos`
- `Tasa Respuesta`
- `% Neto (n>=10)`
- `% Neto Servicios (P1-P13)`
- `% Satisfacción general (P14)`
- `% Recomendación (P15)`
- `% Orgullo (P16)`
- `Nivel académico encuesta`
- `Origen maestro encuesta`
- `HTML Universo Encuestas`
- `Tooltip Metodología`
- `Encabezado_Encuesta`

### 4.7 Páginas

Páginas funcionales consolidadas:

1. Resumen y participación.
2. Resultados y segmentación.
3. Campus y contexto académico.
4. Evolución y comparativos.
5. Detalle de preguntas.
6. Metodología.

La antigua solución tenía aproximadamente 22 hojas. Se consolidó en seis páginas con filtros y matrices reutilizables. El PBIP actual contiene además una página denominada `Página 1`; debe revisarse antes de publicar para decidir si es una página temporal y eliminarla u ocultarla.

### 4.8 Privacidad

- No cargar RUT, nombres ni correos al modelo publicado cuando no sean indispensables.
- Los identificadores estudiantiles se deben transformar a SHA-256 en Athena.
- La ausencia de identificador individual en la query de respuestas no debe solucionarse agregando datos personales sin una decisión formal de gobierno de datos.

### 4.9 Controles antes de publicar

Consultar:

```text
Encuesta de Servicio/Documentacion/VALIDACION_FUNCIONAL.md
```

Puntos críticos:

- verificar que todos los registros sean encuestas de servicio;
- validar votos 1 a 5 contra SQL;
- contrastar inscritos `RE/RW` por período y NRC;
- investigar cualquier tasa superior a 100 %;
- confirmar escala 0–7 y reglas con el área funcional;
- revisar filtros, menú, tooltip, exportación y contraste;
- cerrar y volver a abrir el PBIP antes de publicar;
- validar gateway y RLS si se incorpora seguridad por usuario.

## 5. Panel Solicitudes Operacionales

### 5.1 Objetivo

Monitorear históricamente las solicitudes académicas gestionadas mediante Banner Workflow, conocer su estado, duración y distribución, y permitir la descarga de una sábana operacional con una fila por solicitud.

Proyecto canónico:

```text
Solicitudes/Panel/Solicitudes Operacionales.pbip
```

Consultas canónicas:

```text
Solicitudes/Queries/WORKFLOW_SOLICITUDES_TODAS_HISTORICO.sql
Solicitudes/Queries/WORKFLOW_PROPIEDADES_JSON_HISTORICO.sql
Solicitudes/Queries/REPORTE_WF_INSCRIPCION_EXTRAORDINARIA_HISTORICO.sql
Solicitudes/Queries/REPORTE_WF_CAMBIO_CALIFICACION_HISTORICO.sql
```

### 5.2 Tablas de Data Lake

Homologación principal de Workflow:

| Tabla de origen | Tabla Data Lake |
|---|---|
| `ENG_WORKFLOW` | `uss_datalake_stage.banner_oracle_workflow_eng_workflow` |
| `ENG_PROPERTIES_VALUES` | `uss_datalake_stage.banner_oracle_workflow_eng_properties_values` |

Otras tablas utilizadas:

- `uss_datalake_stage.banner_oracle_workflow_process_definition`
- `uss_datalake_stage.banner_oracle_saturn_stvcamp`

Conexión Power BI:

```text
DSN=uss-athena-datalake-prod
```

Las consultas históricas no deben incorporar un filtro fijo de período ni un RUT fijo. Los valores como:

```sql
'202610' AS periodo,
CAST(17504561 AS BIGINT) AS pd_id
```

fueron identificados como constantes de pruebas anteriores y no sirven para el panel histórico.

### 5.3 Arquitectura optimizada

La consulta `WORKFLOW_SOLICITUDES_TODAS_HISTORICO.sql` produce exactamente una fila por `id` de solicitud.

Reglas:

- seleccionar la versión más reciente de cada definición de proceso;
- seleccionar el registro más reciente de cada workflow;
- deduplicar propiedades por `id + name + seq`;
- agregar atributos operacionales sin expandir una fila por propiedad;
- contar siempre `DISTINCT id` en indicadores;
- mantener la extracción completa de propiedades en un SQL separado y **no importarla** al modelo.

La extracción externa para auditoría es:

```text
Solicitudes/Panel/Queries/workflow_propiedades_json.sql
```

Esta separación resolvió una carga que estaba superando los 17 millones de registros. La base operacional final validada contiene:

```text
154.730 filas
154.730 solicitudes únicas
```

### 5.4 Modelo semántico

| Tabla | Uso |
|---|---|
| `solicitudes_workflow` | Base transversal optimizada; una fila por solicitud. |
| `solicitudes_inscripcion` | Detalle aprobado de inscripción extraordinaria histórica. |
| `solicitudes_calificacion` | Detalle aprobado de cambio de calificación. |
| `dim_periodo` | Dimensión de período. |
| `dim_estado` | Dimensión de estado operacional. |
| `Medidas Solicitudes` | Indicadores, HTML y encabezados. |

Se eliminaron del modelo activo:

- `solicitudes_consolidadas`
- `dim_tipo_solicitud`

Motivo: duplicaban lógica o no tenían consumidores activos.

Los campos epoch `start_date` y `stop_date` se importan como `int64`. La conversión a fecha se realiza después de la importación para impedir que el controlador ODBC intente convertir milisegundos como fecha durante la apertura.

### 5.5 Clasificación de solicitudes

Categorías visibles:

- Inscripción especial.
- Cambio de calificación.
- Reincorporación.
- Continuidad de estudios.
- Cambio de carrera/sede.
- Suspensión.
- Retiro.

#### Unificación de inscripción

Inscripción especial e inscripción extraordinaria corresponden a versiones o clasificaciones del mismo proceso funcional. Se decidió:

- usar una única categoría analítica: `Inscripción especial`;
- conservar la distinción en `tipo_clasificacion`;
- ofrecer un filtro desplegable **Tipo de clasificación** con:
  - `Inscripción Especial`
  - `Inscripción Extraordinaria`
- ocultar en modo lectura la antigua página independiente de extraordinaria, conservándola como respaldo editable.

Validación histórica:

| Clasificación | Solicitudes |
|---|---:|
| Inscripción Especial | 45.708 |
| Inscripción Extraordinaria | 21.059 |

### 5.6 Homologación de sede con STVCAMP

El workflow mezcla códigos y descriptores de campus. El filtro no debe presentar ambas variantes.

La solución vigente:

1. Consulta `banner_oracle_saturn_stvcamp`.
2. Normaliza mayúsculas, espacios y signos para comparar.
3. Compara cada propiedad candidata contra `STVCAMP_CODE` y `STVCAMP_DESC`.
4. Prioriza una propiedad que tenga coincidencia válida en el catálogo.
5. Devuelve la etiqueta canónica:

```text
CÓDIGO - DESCRIPCIÓN
```

6. Conserva el texto original en `sede_workflow`.

Campos visibles:

- `sede` → **Sede Homologada**, utilizada por filtros y encabezados.
- `sede_workflow` → **Sede Informada en Workflow**, incluida en la sábana descargable.

La primera aproximación elegía el valor máximo entre propiedades y produjo dos falsos `TMED`. Al revisar esas solicitudes se encontró también `C_SEDE = LPS`. La lógica actual evalúa las propiedades individualmente y prioriza la coincidencia válida, por lo que esos registros quedan correctamente homologados a LPS.

Resultado validado:

- 39 variantes originales reducidas a 13 opciones en el filtro;
- todos los valores informados y reconocibles se homologan;
- cinco solicitudes no informan ninguna sede y quedan como `Sin sede homologada`;
- el filtro se ordena ascendentemente.

### 5.7 Período

El campo período se extrae desde propiedades compatibles mediante una expresión de seis dígitos:

```sql
REGEXP_EXTRACT(TRIM(value), '(20[0-9]{4})', 1)
```

Esto evita mostrar identificadores o textos como `TRSSAVS1202415` en el filtro. No reemplazar la extracción por el valor completo de una propiedad sin validar su formato.

### 5.8 Estados e indicadores

Estado operacional:

- `FINALIZADA`: estado técnico contiene `completed` o `stopped`.
- `EN CURSO`: indicador de ejecución igual a `Y`.
- `CANCELADA`: estado técnico contiene `cancel`.
- `OTRO`: no cumple las condiciones anteriores.

La tarjeta de canceladas se eliminó del resumen porque no tenía datos útiles.

Indicadores principales:

- `Solicitudes Total`
- `Solicitudes Finalizadas`
- `Solicitudes En Curso`
- `% Solicitudes Finalizadas`
- `Duración Promedio Días`
- `Solicitudes Sobre Promedio`

La duración promedio:

- se calcula entre fecha de inicio y fecha de cierre;
- excluye sábados y domingos;
- todavía no descuenta feriados institucionales o legales.

**Fuera del promedio** cuenta solicitudes finalizadas cuya duración en días hábiles supera el promedio del contexto de filtros vigente. La tarjeta HTML presenta cantidad y porcentaje respecto de las finalizadas.

### 5.9 Páginas actuales

1. Resumen operacional.
2. Inscripción especial.
3. Cambio de calificación.
4. Reincorporación.
5. Continuidad de estudios.
6. Cambio de carrera/sede.
7. Suspensión.
8. Retiro.
9. Inscripción extraordinaria — oculta en modo lectura.
10. Sábana completa.

La sábana contiene una fila por solicitud y permite exportar desde el menú `...` de la tabla. Incluye dato original y homologado cuando corresponde.

## 6. Errores ya diagnosticados y solución

### 6.1 `queryRef ... solo puede tener un displayName`

Causa: el mismo `queryRef` aparecía con distintos `displayName` dentro del PBIR.  
Solución: mantener un único nombre visible por referencia y validar todos los JSON antes de abrir.

### 6.2 `visual/expansionStates` o `visual/query/sortDefinition` con tipo incorrecto

Causa: propiedades PBIR escritas con una estructura no compatible con el esquema de Power BI.  
Solución: conservar la estructura generada por Power BI y no inventar objetos vacíos o listas con tipos no documentados.

### 6.3 `Los criterios distinct especificados no son válidos`

Causa: consolidación de maestros mediante una operación `Distinct`/agrupación incompatible con columnas heterogéneas.  
Solución: alinear columnas de Pregrado, Advance y Postgrado, combinarlas y agregar un campo explícito de origen.

### 6.4 Error ODBC/Athena `Could not resolve host`

Mensaje observado:

```text
Could not resolve host: athena.us-east-1.amazonaws.com
```

Es un problema de red, DNS, VPN o conectividad del driver; no demuestra un error de sintaxis SQL. Verificar conectividad y DSN antes de modificar la consulta.

### 6.5 Carga de más de 17 millones de registros

Causa: importar el detalle largo de propiedades, generando varias filas por solicitud.  
Solución: modelo operacional a una fila por `id` y extracción de propiedades JSON separada para auditoría.

### 6.6 Caracteres como `InscripciÃ³n`

Causa: archivos UTF-8 reinterpretados con otra codificación.  
Solución: escribir JSON, TMDL, SQL y Markdown en UTF-8 y ejecutar el validador de mojibake.

### 6.7 HTML/DAX con error `La sintaxis de VAR no es correcta`

Causa: paréntesis desbalanceados en `SWITCH`/`CONCATENATEX` y variables ubicadas dentro de una expresión anterior.  
Solución: cerrar cada función antes de declarar la siguiente variable y mantener el patrón `VAR ... RETURN` completo.

### 6.8 Filtros de nivel con resultados vacíos o tasas imposibles

Causas combinadas:

- filtro aplicado a una tabla que no propagaba hacia respuestas;
- respuestas agregadas sin identificador de estudiante;
- denominadores contados por persona y numeradores acumulados por varios períodos;
- relaciones entre hechos de distinta granularidad.

Solución vigente: calcular conjuntos por período y NRC, contar estudiante-período cuando hay varios períodos y declarar la asignación proporcional por nivel como una estimación.

### 6.9 Rutas y nombres demasiado largos

PBIR crea directorios por página y visual. Evitar nombres innecesariamente largos en carpetas técnicas, consultas y artefactos; preferir prefijos breves como `res`, `esp`, `cal`, `raw`, `rei`, `con`, `car`, `sus` y `ret`.

## 7. Automatización y validación

Scripts relevantes:

```text
tools/build_solicitudes_panel.ps1
tools/extend_solicitudes_workflows.py
tools/validate_solicitudes_panel.py
```

### 7.1 Uso seguro del generador

`extend_solicitudes_workflows.py` puede crear o reconstruir páginas. Si el usuario ya realizó ajustes visuales en Power BI, no ejecutar indiscriminadamente su flujo `main()`.

Preferir funciones quirúrgicas para:

- actualizar la expresión SQL;
- agregar columnas al modelo;
- modificar medidas;
- añadir un filtro o una columna puntual;
- ordenar segmentadores;
- conservar posiciones y formatos existentes.

### 7.2 Validación estructural de Solicitudes

Desde la raíz del repositorio:

```powershell
python tools/validate_solicitudes_panel.py "Solicitudes/Panel"
```

La validación comprueba, entre otros:

- JSON válidos;
- tablas, columnas y medidas referenciadas;
- ausencia de medidas duplicadas;
- bookmarks y grupos existentes;
- botones de filtros y menú;
- orden de capas;
- `pageNavigator`;
- tema MODUSS;
- lienzo y fondo;
- nombres funcionales de columnas;
- codificación UTF-8;
- query histórica sin filtro temporal fijo;
- una fila operacional por solicitud;
- campos `tipo_clasificacion`, `sede` y `sede_workflow`;
- duración que excluye fines de semana;
- sede ordenada y homologada mediante STVCAMP.

Última validación registrada:

```text
JSON revisados: 292
Tablas: 6
Medidas: 33
VALIDACIÓN ESTRUCTURAL OK
```

### 7.3 Validación de Athena

Antes de publicar cambios en la consulta transversal, ejecutar controles equivalentes a:

```sql
SELECT
    COUNT(*) AS filas,
    COUNT(DISTINCT id) AS solicitudes
FROM (<query histórica>) q;
```

El resultado debe mantener `filas = solicitudes`. Para sede, revisar valores homologados, variantes originales y casos sin correspondencia.

## 8. Flujo de trabajo recomendado para otra IA

1. Leer este documento y los README específicos.
2. Confirmar cuál panel y carpeta están en alcance.
3. Comprobar procesos de Power BI abiertos.
4. Comparar fechas y hashes entre OneDrive y repositorio.
5. Respaldar la versión de OneDrive.
6. Inspeccionar antes de editar: modelo, medidas, páginas, bookmarks y consulta.
7. Hacer cambios mínimos y reversibles.
8. No modificar al mismo tiempo la granularidad de hechos y las relaciones sin validar indicadores.
9. Probar SQL directamente en Athena cuando sea posible.
10. Ejecutar validación estructural.
11. Abrir, actualizar, cerrar y reabrir el PBIP para una validación final del motor de Power BI.
12. Sincronizar al repositorio.
13. Revisar `git diff`, crear commit descriptivo y publicar solo si corresponde.
14. Entregar al usuario un resumen de cambios, cifras de validación, ruta del PBIP, respaldo y commit.

## 9. Pendientes y decisiones que requieren validación funcional

### Encuesta de Servicio

- Definir si la página adicional `Página 1` debe eliminarse u ocultarse.
- Obtener un identificador anonimizado del respondente si se requiere nivel académico exacto en respuestas.
- Confirmar formalmente el tratamiento de valores 0, 6 y 7.
- Confirmar escalas, metas y umbrales con la unidad funcional.
- Validar RLS y publicación institucional.

### Solicitudes Operacionales

- Confirmar si los cinco registros sin sede deben permanecer como `Sin sede homologada` o recibir una regla de negocio adicional.
- Si la duración debe descontar feriados, incorporar una dimensión calendario laboral oficial.
- Evaluar una vista complementaria de excepciones: solicitudes sobre el promedio por tipología, sede y período, con acceso al detalle.
- Validar gateway, credenciales y RLS antes de producción.

## 10. Historial de hitos en Git

| Commit | Hito |
|---|---|
| `bd5ae2b` | Documentación y versionado de Encuesta de Servicio. |
| `772a15f` | Primera incorporación del panel de Solicitudes Operacionales. |
| `0545e61` | Panel operacional MODUSS y páginas de solicitudes. |
| `e27285d` | Recuperación de Cambio de carrera/sede y HTML de sábana. |
| `736a14c` | Optimización de carga histórica. |
| `2c1f843` | Mejora de filtros y lectura operacional. |
| `1e2a56d` | Unificación de Inscripción especial/extraordinaria. |
| `50874b0` | Homologación de sedes con STVCAMP. |

## 11. Prompt sugerido para retomar el trabajo

```text
Usa CONTEXTO_IA_INSTITUCIONAL.md como contexto técnico y funcional, no como
autorización automática para modificar archivos. Confirma primero el panel y
el objetivo vigente. Toma como fuente visual más reciente la carpeta PBIP de
OneDrive si el usuario hizo ajustes en Power BI; respáldala y evita regenerar
páginas completas. Mantén la interfaz MODUSS, la granularidad documentada, las
reglas de indicadores, la trazabilidad del dato original y las validaciones
estructurales. Antes de entregar, prueba las consultas, valida referencias,
bookmarks, filtros, menú, tooltips, codificación y ausencia de duplicados.
```

