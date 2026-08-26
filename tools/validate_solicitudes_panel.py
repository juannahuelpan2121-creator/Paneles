import json
import hashlib
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
model_dirs = list(root.glob("*.SemanticModel"))
report_dirs = list(root.glob("*.Report"))
if len(model_dirs) != 1 or len(report_dirs) != 1:
    raise SystemExit("Se esperaba exactamente un .SemanticModel y un .Report")
model = model_dirs[0] / "definition"
report = report_dirs[0] / "definition"

pbip_files = list(root.glob("*.pbip"))
if len(pbip_files) != 1:
    raise SystemExit("Se esperaba exactamente un archivo .pbip")
required_artifacts = [
    model_dirs[0] / "definition.pbism",
    report_dirs[0] / "definition.pbir",
    pbip_files[0],
]
for artifact in required_artifacts:
    if not artifact.exists():
        raise SystemExit(f"Artefacto obligatorio faltante: {artifact}")

tables: dict[str, set[str]] = {}
measures: dict[str, set[str]] = {}
measure_name_lists: dict[str, list[str]] = {}
for path in (model / "tables").glob("*.tmdl"):
    text = path.read_text(encoding="utf-8")
    match = re.search(r"^table\s+(?:'([^']+)'|(\S+))", text, re.M)
    if not match:
        continue
    table = match.group(1) or match.group(2)
    tables[table] = {
        m.group(1) or m.group(2)
        for m in re.finditer(r"^\s*column\s+(?:'([^']+)'|(\S+?))(?:\s*=.*)?$", text, re.M)
    }
    measure_names = re.findall(r"^\s*measure\s+'([^']+)'\s*=", text, re.M)
    measure_name_lists[table] = measure_names
    measures[table] = set(measure_names)

errors: list[str] = []
for table_name, measure_names in measure_name_lists.items():
    duplicates = sorted({name for name in measure_names if measure_names.count(name) > 1})
    if duplicates:
        errors.append(f"Medidas duplicadas en {table_name}: {', '.join(duplicates)}")

json_count = 0
page_visuals: dict[str, set[str]] = {}
page_groups: dict[str, set[str]] = {}

def walk(value, path):
    if isinstance(value, dict):
        for kind in ("Column", "Measure"):
            if kind in value and isinstance(value[kind], dict):
                ref = value[kind]
                entity = (
                    ref.get("Expression", {})
                    .get("SourceRef", {})
                    .get("Entity")
                )
                prop = ref.get("Property")
                if entity and prop:
                    catalog = measures if kind == "Measure" else tables
                    if entity not in catalog or prop not in catalog[entity]:
                        errors.append(f"{path}: {kind} inexistente {entity}.{prop}")
        for child in value.values():
            walk(child, path)
    elif isinstance(value, list):
        for child in value:
            walk(child, path)

for path in report.rglob("*.json"):
    json_count += 1
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"{path}: JSON inválido: {exc}")
        continue
    walk(payload, path)

# Evitar texto mojibake producido por Windows PowerShell 5.1 al interpretar
# scripts UTF-8 sin BOM (por ejemplo: "calificaciÃ³n" o "MenÃº").
for path in list(report.rglob("*.json")) + list(model.rglob("*.tmdl")):
    text_content = path.read_text(encoding="utf-8")
    for marker in ("Ã", "Â", "â€", "â–", "âœ", "�"):
        if marker in text_content:
            errors.append(f"{path}: texto con codificación dañada ({marker})")
            break

# Validar que los epoch Unix se carguen como enteros y se conviertan recién
# después de la importación. Así el controlador ODBC no intenta interpretar
# milisegundos como DateTime durante la apertura del proyecto.
expressions_text = (model / "expressions.tmdl").read_text(encoding="utf-8").upper()
if expressions_text.count("EXPRESSION QUERY_WORKFLOW_SOLICITUDES_TODAS") != 1:
    errors.append("Debe existir exactamente una expresión query_workflow_solicitudes_todas")
if "FROM_UNIXTIME" in expressions_text:
    errors.append("Las queries no deben convertir epoch en SQL: el ODBC lo vuelve a exponer como número")
if expressions_text.count("WF.START_DATE") < 2 or expressions_text.count("WF.STOP_DATE") < 2:
    errors.append("Las dos queries deben conservar start_date y stop_date de Workflow")
for table_name in ("solicitudes_inscripcion", "solicitudes_calificacion"):
    table_text = (model / "tables" / f"{table_name}.tmdl").read_text(encoding="utf-8")
    for required_fragment in (
        "column start_date\n\t\tdataType: int64",
        "column stop_date\n\t\tdataType: int64",
        "column start_datetime =",
        "column stop_datetime =",
        "DIVIDE ( epoch_ms, 86400000 )",
        "dataType: dateTime",
    ):
        if required_fragment not in table_text:
            errors.append(f"{table_name}: falta conversión segura de epoch: {required_fragment}")

for obsolete_table in ("solicitudes_consolidadas.tmdl", "dim_tipo_solicitud.tmdl"):
    if (model / "tables" / obsolete_table).exists():
        errors.append(f"Tabla calculada sin uso todavía cargada: {obsolete_table}")
model_text = (model / "model.tmdl").read_text(encoding="utf-8")
relationships_text = (model / "relationships.tmdl").read_text(encoding="utf-8")
for obsolete_reference in (
    "solicitudes_consolidadas",
    "dim_tipo_solicitud",
    "dim_periodo_consolidado",
    "dim_estado_consolidado",
    "dim_tipo_consolidado",
    "dim_tipo_workflow",
):
    if obsolete_reference in model_text or obsolete_reference in relationships_text:
        errors.append(f"Referencia obsoleta en el modelo: {obsolete_reference}")

page_meta = json.loads((report / "pages" / "pages.json").read_text(encoding="utf-8"))
for page in page_meta["pageOrder"]:
    if not (report / "pages" / page / "page.json").exists():
        errors.append(f"Página faltante: {page}")
        continue
    visuals_dir = report / "pages" / page / "visuals"
    page_visuals[page] = set()
    page_groups[page] = set()
    for visual_path in visuals_dir.glob("*/visual.json"):
        payload = json.loads(visual_path.read_text(encoding="utf-8"))
        name = payload.get("name")
        if name:
            page_visuals[page].add(name)
        if "visualGroup" in payload and name:
            page_groups[page].add(name)
        parent = payload.get("parentGroupName")
        if parent and not (visuals_dir / parent / "visual.json").exists():
            errors.append(f"{visual_path}: grupo padre inexistente {parent}")
        link_props = (
            payload.get("visual", {})
            .get("visualContainerObjects", {})
            .get("visualLink", [])
        )
        for link in link_props:
            props = link.get("properties", {})
            link_type = props.get("type", {}).get("expr", {}).get("Literal", {}).get("Value", "")
            target_page = props.get("navigationSection", {}).get("expr", {}).get("Literal", {}).get("Value", "").strip("'")
            if link_type == "'PageNavigation'" and target_page not in page_meta["pageOrder"]:
                errors.append(f"{visual_path}: página destino inexistente {target_page}")

# El kit MODUSS usa pageNavigator y grupos por encima de los botones del
# encabezado. Esto evita estilos grises de botones independientes y que Menú/
# Filtros permanezcan visibles al abrir otro panel.
page_prefix = {
    "resumen_solicitudes": "res",
    "detalle_inscripcion": "ins",
    "detalle_calificacion": "cal",
    "detalle_reincorporacion": "rei",
    "detalle_continuidad": "con",
    "detalle_cambio_carrera": "car",
    "detalle_suspension": "sus",
    "detalle_inscripcion_especial": "esp",
    "detalle_retiro": "ret",
    "sabana_completa": "raw",
}
for page, prefix in page_prefix.items():
    visuals_dir = report / "pages" / page / "visuals"
    nav_path = visuals_dir / f"{prefix}_menu_pages" / "visual.json"
    if not nav_path.exists():
        errors.append(f"{page}: falta el pageNavigator del menú MODUSS")
    else:
        nav = json.loads(nav_path.read_text(encoding="utf-8"))
        if nav.get("visual", {}).get("visualType") != "pageNavigator":
            errors.append(f"{page}: el menú no usa pageNavigator")
    layer_names = (
        f"{prefix}_open",
        f"{prefix}_menu_open",
        f"{prefix}_filter_group",
        f"{prefix}_menu_group",
    )
    layers = {}
    for layer_name in layer_names:
        layer_path = visuals_dir / layer_name / "visual.json"
        if layer_path.exists():
            layer = json.loads(layer_path.read_text(encoding="utf-8"))
            layers[layer_name] = layer.get("position", {}).get("z", -1)
    filter_z = layers.get(f"{prefix}_filter_group", -1)
    menu_z = layers.get(f"{prefix}_menu_group", -1)
    base_z = max(
        layers.get(f"{prefix}_open", -1),
        layers.get(f"{prefix}_menu_open", -1),
    )
    if filter_z <= base_z:
        errors.append(f"{page}: el panel de filtros debe quedar sobre los botones del encabezado")
    if menu_z <= filter_z:
        errors.append(f"{page}: el panel de navegación debe quedar sobre el panel de filtros")
    for obsolete in (
        f"{prefix}_menu_resumen",
        f"{prefix}_menu_inscripcion",
        f"{prefix}_menu_calificacion",
        f"{prefix}_menu_title",
    ):
        if (visuals_dir / obsolete).exists():
            errors.append(f"{page}: quedó un visual de menú antiguo: {obsolete}")

    expected_actions = {
        f"{prefix}_open": f"{prefix}_filter_on",
        f"{prefix}_close": f"{prefix}_filter_off",
        f"{prefix}_menu_open": f"{prefix}_menu_on",
        f"{prefix}_menu_close": f"{prefix}_menu_off",
    }
    for visual_name, expected_bookmark in expected_actions.items():
        action_path = visuals_dir / visual_name / "visual.json"
        if not action_path.exists():
            errors.append(f"{page}: falta el botón funcional {visual_name}")
            continue
        action = json.loads(action_path.read_text(encoding="utf-8"))
        links = action.get("visual", {}).get("visualContainerObjects", {}).get("visualLink", [])
        bookmark = None
        if links:
            bookmark = (
                links[0].get("properties", {}).get("bookmark", {})
                .get("expr", {}).get("Literal", {}).get("Value", "").strip("'")
            )
        if bookmark != expected_bookmark:
            errors.append(
                f"{action_path}: apunta a {bookmark!r}; se esperaba {expected_bookmark!r}"
            )

# Ampliación de workflows: el dataset importado tiene una fila por solicitud y
# los indicadores cuentan ids únicos. También se exige una página histórica
# por tipología y una sábana operacional de exportación.
workflow_required_columns = {
    "id", "pd_id", "estado_actual", "estado_operacional", "start_date", "stop_date",
    "tipo_solicitud", "categoria_solicitud", "tipo_clasificacion", "periodo", "sede", "sede_workflow", "nivel",
    "rut_estudiante", "cantidad_propiedades", "fecha_inicio", "fecha_cierre",
}
missing_workflow_columns = workflow_required_columns - tables.get("solicitudes_workflow", set())
if missing_workflow_columns:
    errors.append(
        "solicitudes_workflow: faltan columnas " + ", ".join(sorted(missing_workflow_columns))
    )

measure_text = (model / "tables" / "Medidas Solicitudes.tmdl").read_text(encoding="utf-8")
if "DISTINCTCOUNT ( solicitudes_workflow[id] )" not in measure_text:
    errors.append("Solicitudes Total debe contar DISTINCT id en el dataset operacional")
for required_measure in (
    "Duración Promedio Días",
    "Solicitudes Sobre Promedio",
    "Encabezado Resumen Workflow",
    "HTML KPI Resumen Workflow",
    "HTML KPI Detalle Workflow",
    "Encabezado Sábana",
    "HTML KPI Sábana",
):
    if required_measure not in measures.get("Medidas Solicitudes", set()):
        errors.append(f"Medida workflow faltante: {required_measure}")


def _measure_body(measure_name):
    """Extrae una medida TMDL serializada en formato cercado o plano."""
    match = re.search(
        r"measure '" + re.escape(measure_name) + r"'\s*=\s*(.*?)\n\s*lineageTag:",
        measure_text,
        re.S,
    )
    if not match:
        return None

    body = match.group(1).strip()
    if body.startswith("```") and body.endswith("```"):
        body = body[3:-3].strip()
    return body


raw_html_expression = _measure_body("HTML KPI Sábana")
if raw_html_expression is None:
    errors.append("No se pudo localizar la expresión de HTML KPI Sábana")
else:
    if raw_html_expression.upper().startswith("RETURN"):
        errors.append("HTML KPI Sábana no puede comenzar con RETURN sin declarar una variable")
    for technical_text in ("ATHENA", "WORKFLOW_PROPIEDADES_JSON.SQL", "DESCARGA OPERACIONAL OPTIMIZADA"):
        if technical_text in raw_html_expression.upper():
            errors.append(f"HTML KPI Sábana conserva texto técnico: {technical_text}")

summary_html_expression = _measure_body("HTML KPI Resumen Workflow")
if summary_html_expression is None:
    errors.append("No se pudo localizar la expresión de HTML KPI Resumen Workflow")
elif "Canceladas" in summary_html_expression:
    errors.append("El resumen todavía contiene la tarjeta de solicitudes canceladas")
if "GENERATESERIES ( 1, dias_calendario, 1 )" not in measure_text or "WEEKDAY ( inicio + [Value], 2 ) <= 5" not in measure_text:
    errors.append("Duración Promedio Días no excluye sábados y domingos")
if "[DiasHabiles] > promedio" not in measure_text:
    errors.append("Solicitudes Sobre Promedio no compara cada solicitud con el promedio filtrado")

old_inscription_page = report / "pages" / "detalle_inscripcion" / "page.json"
if old_inscription_page.exists():
    old_page_payload = json.loads(old_inscription_page.read_text(encoding="utf-8"))
    if old_page_payload.get("visibility") != "HiddenInViewMode":
        errors.append("La página anterior de inscripción extraordinaria debe permanecer oculta en modo lectura")
if page_meta.get("pageOrder", [])[:2] != ["resumen_solicitudes", "detalle_inscripcion_especial"]:
    errors.append("Inscripción especial unificada debe ser la segunda página del panel")

classification_slicer = (
    report / "pages" / "detalle_inscripcion_especial" / "visuals"
    / "esp_tipo_clasificacion" / "visual.json"
)
if not classification_slicer.exists():
    errors.append("Falta el filtro desplegable Tipo de clasificación en Inscripción especial")
else:
    classification_payload = json.loads(classification_slicer.read_text(encoding="utf-8"))
    classification_text = json.dumps(classification_payload, ensure_ascii=False)
    if "solicitudes_workflow.tipo_clasificacion" not in classification_text:
        errors.append("El filtro Tipo de clasificación no usa solicitudes_workflow[tipo_clasificacion]")
    if "Tipo de clasificación" not in classification_text:
        errors.append("El filtro unificado no muestra el título Tipo de clasificación")
    if classification_payload.get("parentGroupName") != "esp_filter_group":
        errors.append("El filtro Tipo de clasificación no pertenece al panel de filtros MODUSS")

expected_workflow_pages = {
    "detalle_reincorporacion": "rei",
    "detalle_continuidad": "con",
    "detalle_cambio_carrera": "car",
    "detalle_suspension": "sus",
    "detalle_inscripcion_especial": "esp",
    "detalle_retiro": "ret",
}
for page, prefix in expected_workflow_pages.items():
    visuals_dir = report / "pages" / page / "visuals"
    for suffix in ("header", "kpi", "tabla", "estado", "periodo_chart"):
        visual_path = visuals_dir / f"{prefix}_{suffix}" / "visual.json"
        if not visual_path.exists():
            errors.append(f"{page}: falta visual {prefix}_{suffix}")
            continue
        payload = json.loads(visual_path.read_text(encoding="utf-8"))
        filters = payload.get("filterConfig", {}).get("filters", [])
        if not filters:
            errors.append(f"{visual_path}: falta filtro fijo de categoría")

raw_table = report / "pages" / "sabana_completa" / "visuals" / "raw_tabla" / "visual.json"
if not raw_table.exists():
    errors.append("Falta la tabla de la sábana completa")
elif "solicitudes_workflow.sede_workflow" not in raw_table.read_text(encoding="utf-8"):
    errors.append("La sábana no conserva la sede original informada por Workflow")
download_button = report / "pages" / "resumen_solicitudes" / "visuals" / "res_descargar" / "visual.json"
if not download_button.exists():
    errors.append("Falta el botón de acceso a la sábana completa")

for page in page_meta["pageOrder"]:
    page_payload = json.loads((report / "pages" / page / "page.json").read_text(encoding="utf-8"))
    if page_payload.get("width") != 1280 or page_payload.get("height", 0) < 1800:
        errors.append(f"{page}: el lienzo debe mantener 1280 px de ancho y al menos 1800 px de alto")
    if page_payload.get("displayOption") != "ActualSize":
        errors.append(f"{page}: debe usar ActualSize como el ejemplo estratégico")
    page_color = (
        page_payload.get("objects", {})
        .get("background", [{}])[0]
        .get("properties", {})
        .get("color", {})
        .get("solid", {})
        .get("color", {})
        .get("expr", {})
        .get("Literal", {})
        .get("Value")
    )
    if page_color != "'#FFFFFF'":
        errors.append(f"{page}: el fondo del lienzo debe ser #FFFFFF como el ejemplo estratégico")

    prefix = page_prefix.get(page)
    if prefix:
        visuals_dir = report / "pages" / page / "visuals"
        for visual_path in visuals_dir.glob("*/visual.json"):
            payload = json.loads(visual_path.read_text(encoding="utf-8"))
            if payload.get("visual", {}).get("visualType") != "slicer":
                continue
            if payload.get("parentGroupName") != f"{prefix}_filter_group":
                continue
            position = payload.get("position", {})
            if (position.get("x"), position.get("width"), position.get("height")) != (944, 312, 80):
                errors.append(f"{visual_path}: el segmentador debe medir 312 x 80 y comenzar en x=944")
            projections = (
                payload.get("visual", {}).get("query", {}).get("queryState", {})
                .get("Values", {}).get("projections", [])
            )
            if any(item.get("queryRef") == "solicitudes_workflow.sede" for item in projections):
                directions = {
                    item.get("direction")
                    for item in payload.get("visual", {}).get("query", {})
                    .get("sortDefinition", {}).get("sort", [])
                }
                if directions != {"Ascending"}:
                    errors.append(f"{visual_path}: el filtro de sede debe ordenarse ascendentemente")

generic_sql = root / "Queries" / "workflow_solicitudes_todas_historico.sql"
if not generic_sql.exists():
    errors.append("Falta la query histórica genérica dentro del proyecto")
else:
    sql_text = generic_sql.read_text(encoding="utf-8").upper()
    for forbidden in ("YEAR(CURRENT_DATE)", "BETWEEN YEAR(CURRENT_DATE)"):
        if forbidden in sql_text:
            errors.append(f"La query histórica conserva un filtro temporal fijo: {forbidden}")
    for required_fragment in (
        "REGEXP_REPLACE(",
        "REGEXP_EXTRACT(TRIM(VALUE), '(20[0-9]{4})', 1)",
        "'[_-]+'",
        "'CAMBIO( DE)? CARRERA( SEDE)?'",
        "THEN 'CAMBIO DE CARRERA/SEDE'",
        "WHEN ID = CAST(19994978 AS BIGINT) THEN 'INSCRIPCIÓN ESPECIAL'",
        "THEN 'INSCRIPCIÓN EXTRAORDINARIA'",
        "END AS TIPO_CLASIFICACION",
        "BANNER_ORACLE_SATURN_STVCAMP",
        "SEDE_RESUELTA AS",
        "CASE WHEN CODIGO_CAMPUS IS NOT NULL THEN 0 ELSE 1 END",
        "AS SEDE_WORKFLOW",
        "CONCAT(A.CODIGO_CAMPUS, ' - ', A.DESCRIPCION_CAMPUS)",
        "WHERE CATEGORIA_SOLICITUD IS NOT NULL",
        "COUNT(*) AS CANTIDAD_PROPIEDADES",
        "LEFT JOIN ATRIBUTOS_HOMOLOGADOS AS A",
    ):
        if required_fragment not in sql_text:
            errors.append(
                "La query histórica no contiene la optimización u homologación requerida: "
                + required_fragment
            )
    for forbidden_fragment in ("BASE_LARGA AS", "FROM ENRIQUECIDA"):
        if forbidden_fragment in sql_text:
            errors.append(
                "La query volvió al formato largo que multiplica las solicitudes: "
                + forbidden_fragment
            )
    if "'CAMBIO( DE)? CARRERA( SEDE)?'" not in expressions_text:
        errors.append(
            "La query externa fue corregida, pero expressions.tmdl conserva la homologación antigua"
        )
    if "MAP_AGG(" in expressions_text or "AS PROPIEDADES_JSON" in expressions_text:
        errors.append(
            "La query importada conserva el JSON masivo de propiedades"
        )
    properties_sql = root / "Queries" / "workflow_propiedades_json.sql"
    if not properties_sql.exists():
        errors.append("Falta la extracción externa de propiedades completas")
    else:
        properties_text = properties_sql.read_text(encoding="utf-8").upper()
        for required_fragment in ("MAP_AGG(", "AS PROPIEDADES_JSON", "NO IMPORTAR"):
            if required_fragment not in properties_text:
                errors.append(
                    "Extracción externa de propiedades incompleta: " + required_fragment
                )

# Los nombres físicos pueden conservarse para no romper el modelo, pero todas
# las columnas visibles en tablas deben presentar una etiqueta funcional.
for visual_path in report.rglob("visual.json"):
    payload = json.loads(visual_path.read_text(encoding="utf-8"))
    visual = payload.get("visual", {})
    if visual.get("visualType") not in {"tableEx", "pivotTable"}:
        continue
    for role in visual.get("query", {}).get("queryState", {}).values():
        for projection in role.get("projections", []):
            column = projection.get("field", {}).get("Column")
            if not column:
                continue
            display_name = projection.get("displayName", "")
            if not display_name or "_" in display_name or not display_name[:1].isupper():
                errors.append(
                    f"{visual_path}: encabezado de tabla no funcional para {column.get('Property')}"
                )

bookmark_meta = json.loads((report / "bookmarks" / "bookmarks.json").read_text(encoding="utf-8"))
for item in bookmark_meta["items"]:
    bookmark_path = report / "bookmarks" / f"{item['name']}.bookmark.json"
    if not bookmark_path.exists():
        errors.append(f"Bookmark faltante: {item['name']}")
        continue
    bookmark = json.loads(bookmark_path.read_text(encoding="utf-8"))
    active_page = bookmark.get("explorationState", {}).get("activeSection")
    if active_page not in page_meta["pageOrder"]:
        errors.append(f"{bookmark_path}: página activa inexistente {active_page}")
    sections = bookmark.get("explorationState", {}).get("sections", {})
    for section_name, section in sections.items():
        if section_name not in page_meta["pageOrder"]:
            errors.append(f"{bookmark_path}: sección inexistente {section_name}")
        for group_name in section.get("visualContainerGroups", {}):
            if group_name not in page_groups.get(section_name, set()):
                errors.append(f"{bookmark_path}: grupo objetivo inexistente {group_name}")

for page, prefix in page_prefix.items():
    for panel, group in (("filter", f"{prefix}_filter_group"), ("menu", f"{prefix}_menu_group")):
        for suffix, expected_hidden in (("on", False), ("off", True)):
            bookmark_path = report / "bookmarks" / f"{prefix}_{panel}_{suffix}.bookmark.json"
            if not bookmark_path.exists():
                errors.append(f"Falta bookmark funcional: {bookmark_path.name}")
                continue
            bookmark = json.loads(bookmark_path.read_text(encoding="utf-8"))
            state = (
                bookmark.get("explorationState", {}).get("sections", {})
                .get(page, {}).get("visualContainerGroups", {}).get(group, {})
                .get("isHidden")
            )
            if state is not expected_hidden:
                errors.append(
                    f"{bookmark_path}: isHidden={state!r}; se esperaba {expected_hidden!r}"
                )

# Recursos registrados referenciados por el reporte.
report_json = json.loads((report / "report.json").read_text(encoding="utf-8"))
report_root = report.parent
theme_name = report_json.get("themeCollection", {}).get("customTheme", {}).get("name")
if theme_name != "moduss_unificado_uss.json":
    errors.append(f"Tema incorrecto: {theme_name!r}; se esperaba moduss_unificado_uss.json")
for package in report_json.get("resourcePackages", []):
    package_name = package.get("name")
    for item in package.get("items", []):
        resource = report_root / "StaticResources" / package_name / item.get("path", "")
        if not resource.exists():
            errors.append(f"Recurso registrado faltante: {resource}")

theme_path = report_root / "StaticResources" / "RegisteredResources" / "moduss_unificado_uss.json"
reference_theme = pathlib.Path(
    r"C:\Users\juan.nahuelpan\OneDrive - Universidad San Sebastian\Desktop\Paneles"
    r"\Panel Ejemplo\Kit Power BI Referencias\01_Ejemplo_Estrategico_MODUSS"
    r"\Modus.Report\StaticResources\RegisteredResources\moduss_unificado_uss.json"
)
if theme_path.exists() and reference_theme.exists():
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    if digest(theme_path) != digest(reference_theme):
        errors.append("El tema MODUSS del panel no coincide byte a byte con el ejemplo estratégico")

if download_button.exists():
    payload = json.loads(download_button.read_text(encoding="utf-8"))
    if payload.get("position", {}).get("height") != 38:
        errors.append("El botón de descarga debe usar la altura de 38 px del kit")
    shape = payload.get("visual", {}).get("objects", {}).get("shape", [])
    tile = (
        shape[0].get("properties", {}).get("tileShape", {})
        .get("expr", {}).get("Literal", {}).get("Value")
        if shape else None
    )
    if tile != "'pill'":
        errors.append("El botón de descarga debe usar la forma pill del kit")

print(f"JSON revisados: {json_count}")
print(f"Tablas: {len(tables)}")
print(f"Medidas: {sum(map(len, measures.values()))}")
if errors:
    print("ERRORES:")
    print("\n".join(errors))
    raise SystemExit(1)
print("VALIDACIÓN ESTRUCTURAL OK")
