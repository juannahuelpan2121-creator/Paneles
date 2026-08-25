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
    measures[table] = set(re.findall(r"^\s*measure\s+'([^']+)'\s*=", text, re.M))

errors: list[str] = []
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

consolidated_text = (model / "tables" / "solicitudes_consolidadas.tmdl").read_text(encoding="utf-8")
for required_fragment in (
    "solicitudes_inscripcion[start_datetime]",
    "solicitudes_inscripcion[stop_datetime]",
    "solicitudes_calificacion[start_datetime]",
    "solicitudes_calificacion[stop_datetime]",
):
    if required_fragment not in consolidated_text:
        errors.append(f"Consolidado no usa la fecha convertida: {required_fragment}")

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

# Ampliación de workflows: el dataset está en formato largo, por lo que los
# indicadores deben contar ids únicos. También se exige una página histórica
# por tipología y una sábana de exportación.
workflow_required_columns = {
    "id", "pd_id", "estado_actual", "estado_operacional", "start_date", "stop_date",
    "tipo_solicitud", "categoria_solicitud", "periodo", "sede", "nivel",
    "rut_estudiante", "nombre_propiedad", "valor_propiedad", "fecha_inicio", "fecha_cierre",
}
missing_workflow_columns = workflow_required_columns - tables.get("solicitudes_workflow", set())
if missing_workflow_columns:
    errors.append(
        "solicitudes_workflow: faltan columnas " + ", ".join(sorted(missing_workflow_columns))
    )

measure_text = (model / "tables" / "Medidas Solicitudes.tmdl").read_text(encoding="utf-8")
if "DISTINCTCOUNT ( solicitudes_workflow[id] )" not in measure_text:
    errors.append("Solicitudes Total debe contar DISTINCT id en el dataset largo")
for required_measure in (
    "Solicitudes Canceladas",
    "Duración Promedio Días",
    "Encabezado Resumen Workflow",
    "HTML KPI Resumen Workflow",
    "HTML KPI Detalle Workflow",
    "Encabezado Sábana",
    "HTML KPI Sábana",
):
    if required_measure not in measures.get("Medidas Solicitudes", set()):
        errors.append(f"Medida workflow faltante: {required_measure}")

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
download_button = report / "pages" / "resumen_solicitudes" / "visuals" / "res_descargar" / "visual.json"
if not download_button.exists():
    errors.append("Falta el botón de acceso a la sábana completa")

for page in page_meta["pageOrder"]:
    page_payload = json.loads((report / "pages" / page / "page.json").read_text(encoding="utf-8"))
    if page_payload.get("width") != 1280 or page_payload.get("height") != 1800:
        errors.append(f"{page}: el lienzo debe ser 1280 x 1800")
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

generic_sql = root / "Queries" / "workflow_solicitudes_todas_historico.sql"
if not generic_sql.exists():
    errors.append("Falta la query histórica genérica dentro del proyecto")
else:
    sql_text = generic_sql.read_text(encoding="utf-8").upper()
    for forbidden in ("YEAR(CURRENT_DATE)", "BETWEEN YEAR(CURRENT_DATE)"):
        if forbidden in sql_text:
            errors.append(f"La query histórica conserva un filtro temporal fijo: {forbidden}")

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
