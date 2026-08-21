import json
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

# Recursos registrados referenciados por el reporte.
report_json = json.loads((report / "report.json").read_text(encoding="utf-8"))
report_root = report.parent
for package in report_json.get("resourcePackages", []):
    package_name = package.get("name")
    for item in package.get("items", []):
        resource = report_root / "StaticResources" / package_name / item.get("path", "")
        if not resource.exists():
            errors.append(f"Recurso registrado faltante: {resource}")

print(f"JSON revisados: {json_count}")
print(f"Tablas: {len(tables)}")
print(f"Medidas: {sum(map(len, measures.values()))}")
if errors:
    print("ERRORES:")
    print("\n".join(errors))
    raise SystemExit(1)
print("VALIDACIÓN ESTRUCTURAL OK")
