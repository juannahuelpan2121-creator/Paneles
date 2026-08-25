from __future__ import annotations

import copy
import json
import os
import re
import shutil
import stat
import sys
import uuid
import zipfile
from datetime import datetime
from pathlib import Path


TARGET = Path(
    r"C:\Users\juan.nahuelpan\OneDrive - Universidad San Sebastian\Desktop\Paneles"
    r"\Solicitudes\Solicitudes Operacionales"
)
REPO = Path(__file__).resolve().parents[1]
SQL_SOURCE = REPO / "Solicitudes" / "Queries" / "WORKFLOW_SOLICITUDES_TODAS_HISTORICO.sql"
INVENTORY_SOURCE = Path(
    r"C:\Users\juan.nahuelpan\Documents\Codex\2026-08-21"
    r"\select-sala-codigo-periodo-periodo-periodo\outputs\workflow_inventario_propiedades_athena.txt"
)
REFERENCE_THEME = Path(
    r"C:\Users\juan.nahuelpan\OneDrive - Universidad San Sebastian\Desktop\Paneles"
    r"\Panel Ejemplo\Kit Power BI Referencias\01_Ejemplo_Estrategico_MODUSS"
    r"\Modus.Report\StaticResources\RegisteredResources\moduss_unificado_uss.json"
)

REPORT = TARGET / "Solicitudes Operacionales.Report" / "definition"
MODEL = TARGET / "Solicitudes Operacionales.SemanticModel" / "definition"
PAGES = REPORT / "pages"
BOOKMARKS = REPORT / "bookmarks"
TABLES = MODEL / "tables"
QUERIES = TARGET / "Queries"

GENERIC_COLUMNS: list[tuple[str, str]] = [
    ("id", "int64"),
    ("pd_id", "int64"),
    ("cabecera", "string"),
    ("estado_actual", "string"),
    ("estado_operacional", "string"),
    ("start_date", "int64"),
    ("stop_date", "int64"),
    ("tipo_solicitud", "string"),
    ("categoria_solicitud", "string"),
    ("periodo", "string"),
    ("sede", "string"),
    ("nivel", "string"),
    ("rut_estudiante", "string"),
    ("ultima_actividad", "string"),
    ("origen", "string"),
    ("indicador_en_ejecucion", "string"),
    ("usuario_origen_id", "string"),
    ("rol_propietario_id", "string"),
    ("rol_administrador_id", "string"),
    ("nombre_propiedad", "string"),
    ("tipo_propiedad", "string"),
    ("secuencia_propiedad", "int64"),
    ("valor_propiedad", "string"),
    ("descripcion_tipo_solicitud", "string"),
    ("version_workflow", "int64"),
    ("particion_workflow", "string"),
    ("particion_propiedad", "string"),
]

NEW_TYPES = [
    {
        "id": "detalle_reincorporacion",
        "prefix": "rei",
        "display": "Reincorporación",
        "category": "Reincorporación",
        "header": "Encabezado Reincorporación",
        "subtitle": "Seguimiento de solicitudes de reincorporación académica.",
    },
    {
        "id": "detalle_continuidad",
        "prefix": "con",
        "display": "Continuidad de estudios",
        "category": "Continuidad de estudios",
        "header": "Encabezado Continuidad",
        "subtitle": "Seguimiento de solicitudes de continuidad de estudios.",
    },
    {
        "id": "detalle_cambio_carrera",
        "prefix": "car",
        "display": "Cambio de carrera/sede",
        "category": "Cambio de carrera/sede",
        "header": "Encabezado Cambio carrera",
        "subtitle": "Seguimiento de solicitudes de cambio de carrera o sede.",
    },
    {
        "id": "detalle_suspension",
        "prefix": "sus",
        "display": "Suspensión",
        "category": "Suspensión",
        "header": "Encabezado Suspensión",
        "subtitle": "Seguimiento de solicitudes de suspensión académica.",
    },
    {
        "id": "detalle_inscripcion_especial",
        "prefix": "esp",
        "display": "Inscripción especial",
        "category": "Inscripción especial",
        "header": "Encabezado Inscripción especial",
        "subtitle": "Seguimiento de solicitudes de inscripción especial.",
    },
    {
        "id": "detalle_retiro",
        "prefix": "ret",
        "display": "Retiro",
        "category": "Retiro",
        "header": "Encabezado Retiro",
        "subtitle": "Seguimiento de solicitudes de retiro académico.",
    },
]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8", newline="\n")


def read_json(path: Path):
    return json.loads(read_text(path))


def write_json(path: Path, value) -> None:
    write_text(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def lineage() -> str:
    return str(uuid.uuid4())


def make_backup() -> Path:
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = TARGET.parent / f"Solicitudes_Operacionales_backup_{stamp}.zip"
    with zipfile.ZipFile(backup, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in TARGET.rglob("*"):
            if path.is_file():
                archive.write(path, path.relative_to(TARGET.parent))
    return backup


def remove_tree(path: Path) -> None:
    if not path.exists():
        return

    def on_error(function, name, _exc):
        os.chmod(name, stat.S_IWRITE)
        function(name)

    shutil.rmtree(path, onexc=on_error)


def sql_to_m(sql: str) -> str:
    return sql.replace('"', '""').replace("\r\n", "#(lf)").replace("\n", "#(lf)")


def add_query_expression(sql: str) -> None:
    path = MODEL / "expressions.tmdl"
    text = read_text(path)
    name = "query_workflow_solicitudes_todas"
    if re.search(rf"^expression {name}\s*=", text, flags=re.M):
        return
    block = f'''\n\nexpression {name} = ```
let
    Query = "{sql_to_m(sql)}"
in
    Query
```

\tlineageTag: {lineage()}
\tqueryGroup: Queries

\tannotation PBI_NavigationStepName = Navigation

\tannotation PBI_ResultType = Text
'''
    write_text(path, text.rstrip() + block)


def generic_table_tmdl() -> str:
    lines = ["table solicitudes_workflow", f"\tlineageTag: {lineage()}", ""]
    for name, dtype in GENERIC_COLUMNS:
        lines.extend(
            [
                f"\tcolumn {name}",
                f"\t\tdataType: {dtype}",
                f"\t\tlineageTag: {lineage()}",
                "\t\tsummarizeBy: none",
                f"\t\tsourceColumn: {name}",
                "",
                "\t\tannotation SummarizationSetBy = Automatic",
                "",
            ]
        )
    for name, source in (("fecha_inicio", "start_date"), ("fecha_cierre", "stop_date")):
        lines.extend(
            [
                f"\tcolumn {name} =",
                f"\t\t\tVAR epoch = [{source}]",
                "\t\t\tVAR epoch_seconds = IF ( epoch > 9999999999, DIVIDE ( epoch, 1000 ), epoch )",
                "\t\t\tRETURN",
                "\t\t\t\tIF (",
                "\t\t\t\t\tISBLANK ( epoch ),",
                "\t\t\t\t\tBLANK (),",
                "\t\t\t\t\tDATE ( 1970, 1, 1 ) + DIVIDE ( epoch_seconds, 86400 )",
                "\t\t\t\t)",
                "\t\tdataType: dateTime",
                "\t\tformatString: General Date",
                f"\t\tlineageTag: {lineage()}",
                "\t\tsummarizeBy: none",
                "",
                "\t\tannotation SummarizationSetBy = Automatic",
                "",
            ]
        )
    lines.extend(
        [
            "\tpartition solicitudes_workflow = m",
            "\t\tmode: import",
            "\t\tqueryGroup: Datos",
            "\t\tsource =",
            "\t\t\t\tlet",
            '                    Origen = Odbc.Query("dsn=uss-athena-datalake-prod", query_workflow_solicitudes_todas)',
            "\t\t\t\tin",
            "\t\t\t\t    Origen",
            "",
            "\tannotation PBI_NavigationStepName = Navegación",
            "",
            "\tannotation PBI_ResultType = Table",
            "",
        ]
    )
    return "\n".join(lines)


def dimension_tmdl(name: str, column: str, source: str) -> str:
    return f'''table {name}
\tlineageTag: {lineage()}

\tcolumn {column}
\t\tdataType: string
\t\tlineageTag: {lineage()}
\t\tsummarizeBy: none
\t\tisNameInferred
\t\tsourceColumn: [{column}]

\tpartition {name} = calculated
\t\tmode: import
\t\tsource = DISTINCT ( SELECTCOLUMNS ( solicitudes_workflow, "{column}", solicitudes_workflow[{source}] ) )
'''


def update_model() -> None:
    write_text(TABLES / "solicitudes_workflow.tmdl", generic_table_tmdl())
    write_text(TABLES / "dim_periodo.tmdl", dimension_tmdl("dim_periodo", "periodo", "periodo"))
    write_text(TABLES / "dim_estado.tmdl", dimension_tmdl("dim_estado", "estado_operacional", "estado_operacional"))
    write_text(
        TABLES / "dim_tipo_solicitud.tmdl",
        dimension_tmdl("dim_tipo_solicitud", "tipo_solicitud", "categoria_solicitud"),
    )

    relationships = read_text(MODEL / "relationships.tmdl")
    if "relationship dim_periodo_workflow" not in relationships:
        relationships = relationships.rstrip() + '''

relationship dim_periodo_workflow
\tfromColumn: solicitudes_workflow.periodo
\ttoColumn: dim_periodo.periodo

relationship dim_estado_workflow
\tfromColumn: solicitudes_workflow.estado_operacional
\ttoColumn: dim_estado.estado_operacional

relationship dim_tipo_workflow
\tfromColumn: solicitudes_workflow.categoria_solicitud
\ttoColumn: dim_tipo_solicitud.tipo_solicitud
'''
    write_text(MODEL / "relationships.tmdl", relationships)

    model = read_text(MODEL / "model.tmdl")
    if "ref table solicitudes_workflow" not in model:
        marker = "ref table solicitudes_consolidadas"
        model = model.replace(marker, "ref table solicitudes_workflow\n" + marker)
    order_match = re.search(r"annotation PBI_QueryOrder = (\[[^\n]+\])", model)
    if order_match and "solicitudes_workflow" not in order_match.group(1):
        order = json.loads(order_match.group(1))
        order.insert(0, "query_workflow_solicitudes_todas")
        order.insert(1, "solicitudes_workflow")
        model = model[: order_match.start(1)] + json.dumps(order, ensure_ascii=False) + model[order_match.end(1) :]
    write_text(MODEL / "model.tmdl", model)


def measure_block(name: str, expression: str, fmt: str | None = None) -> str:
    block = [f"\tmeasure '{name}' = ```"]
    block.extend(f"\t\t{line}" for line in expression.strip().splitlines())
    block.append("\t\t```")
    if fmt:
        block.append(f"\t\tformatString: {fmt}")
    block.extend([f"\t\tlineageTag: {lineage()}", ""])
    return "\n".join(block)


def upsert_measure(text: str, name: str, expression: str, fmt: str | None = None) -> str:
    block = measure_block(name, expression, fmt)
    start_marker = f"\tmeasure '{name}' = ```"
    start = text.find(start_marker)
    if start >= 0:
        candidates = [p for p in (text.find("\n\tmeasure ", start + 1), text.find("\n\tcolumn ", start + 1)) if p >= 0]
        end = min(candidates) if candidates else len(text)
        return text[:start] + block + text[end + 1 :]
    insert = text.find("\n\tcolumn Marcador")
    if insert < 0:
        raise RuntimeError("No se encontró el punto de inserción de medidas")
    return text[:insert] + "\n" + block + text[insert:]


def header_dax(title: str, subtitle: str, raw: bool = False) -> str:
    type_chip = "" if raw else "<span class='chip' style='background:" + '" & cTipo & "' + "'>Tipo: <b>" + '" & vTipo & "' + "</b></span>"
    return f'''VAR vPeriodo = IF ( ISFILTERED ( solicitudes_workflow[periodo] ), CONCATENATEX ( VALUES ( solicitudes_workflow[periodo] ), solicitudes_workflow[periodo], ", " ), "Todos" )
VAR vEstado = IF ( ISFILTERED ( solicitudes_workflow[estado_operacional] ), CONCATENATEX ( VALUES ( solicitudes_workflow[estado_operacional] ), solicitudes_workflow[estado_operacional], ", " ), "Todos" )
VAR vTipo = IF ( ISFILTERED ( solicitudes_workflow[categoria_solicitud] ), CONCATENATEX ( VALUES ( solicitudes_workflow[categoria_solicitud] ), solicitudes_workflow[categoria_solicitud], ", " ), "Todos" )
VAR vNivel = IF ( ISFILTERED ( solicitudes_workflow[nivel] ), CONCATENATEX ( VALUES ( solicitudes_workflow[nivel] ), solicitudes_workflow[nivel], ", " ), "Todos" )
VAR vSede = IF ( ISFILTERED ( solicitudes_workflow[sede] ), CONCATENATEX ( VALUES ( solicitudes_workflow[sede] ), solicitudes_workflow[sede], ", " ), "Todos" )
VAR cPeriodo = IF ( ISFILTERED ( solicitudes_workflow[periodo] ), "#F3E7C4", "#EAF1FB" )
VAR cEstado = IF ( ISFILTERED ( solicitudes_workflow[estado_operacional] ), "#F3E7C4", "#EAF1FB" )
VAR cTipo = IF ( ISFILTERED ( solicitudes_workflow[categoria_solicitud] ), "#F3E7C4", "#EAF1FB" )
VAR cNivel = IF ( ISFILTERED ( solicitudes_workflow[nivel] ), "#F3E7C4", "#EAF1FB" )
VAR cSede = IF ( ISFILTERED ( solicitudes_workflow[sede] ), "#F3E7C4", "#EAF1FB" )
RETURN
"<style>html,body{{margin:0;padding:0;background:transparent;font-family:Arial,Segoe UI,sans-serif;overflow:hidden}}.hdr{{height:140px;box-sizing:border-box;background:#fff;border:1px solid #E1E6ED;border-radius:10px;box-shadow:0 4px 12px rgba(17,43,66,.08);position:relative;color:#112B42;overflow:hidden}}.divider{{position:absolute;left:230px;top:20px;width:2px;height:64px;background:#C6B27F}}.title{{position:absolute;left:255px;top:17px;font-size:23px;font-weight:700;display:flex;align-items:center;gap:7px}}.subtitle{{position:absolute;left:255px;top:51px;font-size:12px;color:#58616E}}.area{{position:absolute;left:255px;top:72px;font-size:10px;font-weight:600;color:#8A7440}}.chips{{position:absolute;left:18px;bottom:13px;display:flex;gap:7px;align-items:center;font-size:10px;color:#475569;max-width:1080px;white-space:nowrap;overflow:hidden}}.chip{{padding:4px 9px;border-radius:999px;color:#112B42}}.info{{position:static;display:block;font-size:11px}}.info>summary{{display:flex;align-items:center;justify-content:center;width:20px;height:20px;border-radius:50%;background:#C6B27F;color:#fff;list-style:none;cursor:pointer}}.info>summary::-webkit-details-marker{{display:none}}.info>summary::marker{{content:''}}.info[open]>summary{{position:fixed;left:936px;top:10px;z-index:10001;background:#F4F0E3;color:#112B42;font-size:0}}.info[open]>summary::after{{content:'×';font-size:14px;font-weight:700}}.tip{{display:none;position:fixed;left:270px;top:6px;width:700px;height:126px;z-index:9999;background:#fff;border:1px solid #D9DEE7;border-left:4px solid #C6B27F;border-radius:8px;box-shadow:0 6px 18px rgba(17,43,66,.16);padding:12px 16px 20px;box-sizing:border-box}}.info[open]>.tip{{display:block}}.tipgrid{{display:grid;grid-template-columns:1fr 1fr 1fr;height:86px}}.tipgrid>div{{padding:2px 15px;border-right:1px solid #E1E6ED}}.tipgrid>div:first-child{{padding-left:8px}}.tipgrid>div:last-child{{border-right:0}}.tip b{{display:block;color:#8A7440;font-size:10px;margin-bottom:6px}}.tip span{{display:block;color:#334155;font-size:9px;line-height:12px}}.source{{position:absolute;left:24px;right:24px;bottom:5px;padding-top:4px;border-top:1px solid #E1E6ED;color:#64748B;font-size:8px}}</style>" &
"<div class='hdr'><div class='divider'></div><div class='title'><span>{title}</span><details class='info'><summary title='Ver metodología'>i</summary><div class='tip'><div class='tipgrid'><div><b>Objetivo</b><span>Monitorear solicitudes académicas y su avance operacional a lo largo del tiempo.</span></div><div><b>Descriptor</b><span>Una solicitud corresponde a un id único. Las propiedades del formulario se conservan en formato largo para su descarga.</span></div><div><b>Fórmula de cálculo</b><span>Total: DISTINCTCOUNT(id). Finalizada, en curso y cancelada se obtienen del estado del workflow. La tasa divide finalizadas por total.</span></div></div><div class='source'>Fuente: Banner Workflow, Data Lake USS. Histórico completo sin filtro fijo de periodo.</div></div></details></div><div class='subtitle'>{subtitle}</div><div class='area'>Dirección General de Control de Gestión y Análisis Institucional</div>" &
"<div class='chips'><span>Filtros aplicados:</span><span class='chip' style='background:" & cPeriodo & "'>Periodo: <b>" & vPeriodo & "</b></span><span class='chip' style='background:" & cEstado & "'>Estado: <b>" & vEstado & "</b></span>{type_chip}<span class='chip' style='background:" & cNivel & "'>Nivel: <b>" & vNivel & "</b></span><span class='chip' style='background:" & cSede & "'>Sede: <b>" & vSede & "</b></span></div></div>"'''


KPI_SUMMARY = '''VAR total = [Solicitudes Total]
VAR fin = [Solicitudes Finalizadas]
VAR curso = [Solicitudes En Curso]
VAR cancel = [Solicitudes Canceladas]
VAR tasa = [% Solicitudes Finalizadas]
VAR dias = [Duración Promedio Días]
RETURN
"<style>html,body{margin:0!important;padding:0!important;width:100%;height:100%;overflow:hidden!important;background:transparent;font-family:Arial,Segoe UI,sans-serif}.wrap{height:100%;display:grid;grid-template-columns:repeat(3,1fr);grid-template-rows:repeat(2,1fr);gap:12px}.card{box-sizing:border-box;height:100%;display:flex;flex-direction:column;background:#fff;border:1px solid #D9DEE7;border-left:4px solid #C6B27F;border-radius:9px;padding:14px 18px;box-shadow:0 3px 10px rgba(17,43,66,.06)}.head{flex:0 0 44px}.title{font-size:13px;font-weight:700;color:#112B42}.desc{margin-top:3px;font-size:10px;color:#58616E}.value{flex:1;display:flex;align-items:center;font-size:29px;font-weight:700;color:#112B42}</style>" &
"<div class='wrap'><div class='card'><div class='head'><div class='title'>Solicitudes totales</div><div class='desc'>Workflows únicos registrados.</div></div><div class='value'>" & FORMAT(total,"#,##0") & "</div></div><div class='card'><div class='head'><div class='title'>Finalizadas</div><div class='desc'>Procesos con término registrado.</div></div><div class='value'>" & FORMAT(fin,"#,##0") & "</div></div><div class='card'><div class='head'><div class='title'>En curso</div><div class='desc'>Procesos actualmente activos.</div></div><div class='value'>" & FORMAT(curso,"#,##0") & "</div></div><div class='card'><div class='head'><div class='title'>Canceladas</div><div class='desc'>Procesos cancelados.</div></div><div class='value'>" & FORMAT(cancel,"#,##0") & "</div></div><div class='card'><div class='head'><div class='title'>Tasa de finalización</div><div class='desc'>Finalizadas respecto del total.</div></div><div class='value'>" & FORMAT(tasa,"0.0%") & "</div></div><div class='card'><div class='head'><div class='title'>Duración promedio</div><div class='desc'>Días entre inicio y cierre.</div></div><div class='value'>" & IF(ISBLANK(dias),"—",FORMAT(dias,"0.0") & " días") & "</div></div></div>"'''

KPI_DETAIL = '''VAR total = [Solicitudes Total]
VAR fin = [Solicitudes Finalizadas]
VAR curso = [Solicitudes En Curso]
VAR tasa = [% Solicitudes Finalizadas]
RETURN
"<style>html,body{margin:0!important;padding:0!important;width:100%;height:100%;overflow:hidden!important;background:transparent;font-family:Arial,Segoe UI,sans-serif}.wrap{height:100%;display:grid;grid-template-columns:repeat(4,1fr);gap:14px}.card{box-sizing:border-box;height:100%;display:flex;flex-direction:column;background:#fff;border:1px solid #D9DEE7;border-left:4px solid #C6B27F;border-radius:9px;padding:14px 18px;box-shadow:0 3px 10px rgba(17,43,66,.06)}.title{font-size:13px;font-weight:700;color:#112B42}.desc{margin-top:4px;font-size:10px;color:#58616E}.value{flex:1;display:flex;align-items:center;justify-content:center;font-size:31px;font-weight:700;color:#112B42}</style>" &
"<div class='wrap'><div class='card'><div class='title'>Solicitudes</div><div class='desc'>Workflows únicos según filtros.</div><div class='value'>" & FORMAT(total,"#,##0") & "</div></div><div class='card'><div class='title'>Finalizadas</div><div class='desc'>Procesos con término registrado.</div><div class='value'>" & FORMAT(fin,"#,##0") & "</div></div><div class='card'><div class='title'>En curso</div><div class='desc'>Procesos actualmente activos.</div><div class='value'>" & FORMAT(curso,"#,##0") & "</div></div><div class='card'><div class='title'>Tasa de finalización</div><div class='desc'>Finalizadas respecto del total.</div><div class='value'>" & FORMAT(tasa,"0.0%") & "</div></div></div>"'''

KPI_RAW = '''RETURN
"<style>html,body{margin:0;padding:0;background:transparent;font-family:Arial,Segoe UI,sans-serif}.box{height:100%;box-sizing:border-box;background:#fff;border:1px solid #D9DEE7;border-left:4px solid #C6B27F;border-radius:9px;padding:18px 22px;color:#112B42;box-shadow:0 3px 10px rgba(17,43,66,.06)}.t{font-size:15px;font-weight:700}.d{margin-top:8px;font-size:11px;line-height:16px;color:#58616E}.tag{display:inline-block;margin-top:9px;padding:5px 10px;border-radius:999px;background:#EAF1FB;font-size:10px;font-weight:700}</style><div class='box'><div class='t'>Descarga de datos en crudo</div><div class='d'>La tabla conserva una fila por solicitud y propiedad del formulario. Selecciona la tabla, abre el menú <b>…</b> del visual y elige <b>Exportar datos</b>. Usa los filtros para acotar la descarga si lo necesitas.</div><span class='tag'>Histórico completo</span></div>"'''


def update_measures() -> None:
    path = TABLES / "Medidas Solicitudes.tmdl"
    text = read_text(path)
    measures = [
        ("Solicitudes Total", "DISTINCTCOUNT ( solicitudes_workflow[id] )", "#,0"),
        ("Solicitudes Finalizadas", 'CALCULATE ( [Solicitudes Total], solicitudes_workflow[estado_operacional] = "FINALIZADA" )', "#,0"),
        ("Solicitudes En Curso", 'CALCULATE ( [Solicitudes Total], solicitudes_workflow[estado_operacional] = "EN CURSO" )', "#,0"),
        ("Solicitudes Canceladas", 'CALCULATE ( [Solicitudes Total], solicitudes_workflow[estado_operacional] = "CANCELADA" )', "#,0"),
        ("% Solicitudes Finalizadas", "DIVIDE ( [Solicitudes Finalizadas], [Solicitudes Total] )", "0.0%"),
        (
            "Duración Promedio Días",
            '''AVERAGEX (
    SUMMARIZE (
        solicitudes_workflow,
        solicitudes_workflow[id],
        "Inicio", MAX ( solicitudes_workflow[fecha_inicio] ),
        "Cierre", MAX ( solicitudes_workflow[fecha_cierre] )
    ),
    VAR inicio = [Inicio]
    VAR cierre = [Cierre]
    RETURN IF ( NOT ISBLANK ( inicio ) && NOT ISBLANK ( cierre ), DATEDIFF ( inicio, cierre, DAY ) )
)''',
            "0.0",
        ),
        ("Encabezado Resumen Workflow", header_dax("Solicitudes académicas", "Resumen operacional consolidado de workflows académicos."), None),
        ("HTML KPI Resumen Workflow", KPI_SUMMARY, None),
        ("HTML KPI Detalle Workflow", KPI_DETAIL, None),
        ("Encabezado Sábana", header_dax("Sábana completa de solicitudes", "Datos históricos en crudo para análisis y exportación.", raw=True), None),
        ("HTML KPI Sábana", KPI_RAW, None),
    ]
    for item in NEW_TYPES:
        measures.append((item["header"], header_dax(item["display"], item["subtitle"]), None))
    for name, expression, fmt in measures:
        text = upsert_measure(text, name, expression, fmt)
    write_text(path, text)


def recursive_replace(value, replacements: dict[str, str]):
    if isinstance(value, dict):
        return {k: recursive_replace(v, replacements) for k, v in value.items()}
    if isinstance(value, list):
        return [recursive_replace(v, replacements) for v in value]
    if isinstance(value, str):
        for old, new in replacements.items():
            value = value.replace(old, new)
        return value
    return value


def literal(value: str):
    return {"expr": {"Literal": {"Value": f"'{value}'"}}}


def categorical_filter(entity: str, prop: str, value: str, name: str):
    return {
        "filters": [
            {
                "name": name,
                "field": {"Column": {"Expression": {"SourceRef": {"Entity": entity}}, "Property": prop}},
                "type": "Categorical",
                "filter": {
                    "Version": 2,
                    "From": [{"Name": "w", "Entity": entity, "Type": 0}],
                    "Where": [
                        {
                            "Condition": {
                                "In": {
                                    "Expressions": [
                                        {
                                            "Column": {
                                                "Expression": {"SourceRef": {"Source": "w"}},
                                                "Property": prop,
                                            }
                                        }
                                    ],
                                    "Values": [[{"Literal": {"Value": f"'{value}'"}}]],
                                }
                            }
                        }
                    ],
                },
            }
        ]
    }


def projection(entity: str, prop: str, kind: str = "Column"):
    return {
        "field": {kind: {"Expression": {"SourceRef": {"Entity": entity}}, "Property": prop}},
        "queryRef": f"{entity}.{prop}",
        "nativeQueryRef": prop,
    }


def set_title(visual, title: str) -> None:
    title_objs = visual.get("visual", {}).get("visualContainerObjects", {}).get("title", [])
    if title_objs:
        title_objs[0].setdefault("properties", {})["text"] = literal(title)


def make_table(template, name: str, fields: list[tuple[str, str, str]], title: str, x: int, y: int, w: int, h: int):
    visual = copy.deepcopy(template)
    visual["name"] = name
    visual["position"].update({"x": x, "y": y, "width": w, "height": h, "z": 2100, "tabOrder": 2100})
    visual["visual"]["query"]["queryState"]["Values"]["projections"] = [projection(e, p, k) for e, p, k in fields]
    set_title(visual, title)
    return visual


def make_bar(template, name: str, category: str, title: str, x: int, y: int, w: int, h: int):
    visual = copy.deepcopy(template)
    visual["name"] = name
    visual["position"].update({"x": x, "y": y, "width": w, "height": h, "z": 2000, "tabOrder": 2000})
    qs = visual["visual"]["query"]["queryState"]
    qs["Category"]["projections"] = [projection("solicitudes_workflow", category)]
    qs["Y"]["projections"] = [projection("Medidas Solicitudes", "Solicitudes Total", "Measure")]
    visual["visual"]["query"]["sortDefinition"] = {
        "sort": [
            {
                "field": {
                    "Measure": {
                        "Expression": {"SourceRef": {"Entity": "Medidas Solicitudes"}},
                        "Property": "Solicitudes Total",
                    }
                },
                "direction": "Descending",
            }
        ]
    }
    set_title(visual, title)
    return visual


def make_page_button(name: str, text: str, target: str, x: int, y: int, w: int, h: int):
    return {
        "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.11.0/schema.json",
        "name": name,
        "position": {"x": x, "y": y, "z": 3500, "height": h, "width": w, "tabOrder": 3500},
        "visual": {
            "visualType": "actionButton",
            "objects": {
                "icon": [{"properties": {"show": {"expr": {"Literal": {"Value": "false"}}}}}],
                "text": [
                    {"properties": {"show": {"expr": {"Literal": {"Value": "true"}}}}},
                    {
                        "properties": {
                            "text": literal(text),
                            "fontColor": {"solid": {"color": literal("#FFFFFF")}},
                            "fontSize": {"expr": {"Literal": {"Value": "11D"}}},
                            "bold": {"expr": {"Literal": {"Value": "true"}}},
                            "fontFamily": literal("Arial"),
                            "horizontalAlignment": literal("center"),
                        },
                        "selector": {"id": "default"},
                    },
                ],
                "fill": [
                    {"properties": {"show": {"expr": {"Literal": {"Value": "true"}}}}},
                    {"properties": {"fillColor": {"solid": {"color": literal("#112B42")}}}, "selector": {"id": "default"}},
                ],
                "outline": [{"properties": {"show": {"expr": {"Literal": {"Value": "false"}}}}}],
                "shape": [{"properties": {"tileShape": literal("pill"), "rectangleRoundedCurve": {"expr": {"Literal": {"Value": "12L"}}}}, "selector": {"id": "default"}}],
            },
            "visualContainerObjects": {
                "visualLink": [
                    {
                        "properties": {
                            "show": {"expr": {"Literal": {"Value": "true"}}},
                            "type": literal("PageNavigation"),
                            "navigationSection": literal(target),
                        }
                    }
                ],
                "border": [{"properties": {"show": {"expr": {"Literal": {"Value": "false"}}}}}],
            },
            "drillFilterOtherVisuals": True,
        },
        "howCreated": "InsertVisualButton",
    }


def set_canvas(page_dir: Path, height: int = 1800) -> None:
    page = read_json(page_dir / "page.json")
    page["height"] = height
    page["width"] = 1280
    page["displayOption"] = "ActualSize"
    page["objects"] = {
        "background": [
            {
                "properties": {
                    "color": {
                        "solid": {
                            "color": literal("#FFFFFF")
                        }
                    }
                }
            }
        ]
    }
    write_json(page_dir / "page.json", page)
    for visual_path in (page_dir / "visuals").glob("*/visual.json"):
        visual = read_json(visual_path)
        name = visual.get("name", "")
        if name.endswith(("_filter_group", "_menu_group", "_overlay", "_menu_overlay", "_panel", "_menu_panel")):
            visual.setdefault("position", {})["height"] = height
        if name.endswith("_menu_pages"):
            visual["position"]["height"] = height - 140
        write_json(visual_path, visual)


def align_moduss_interface() -> None:
    """Alinea el proyecto con el tema y los patrones del ejemplo estratégico."""
    report_file = REPORT / "report.json"
    report_json = read_json(report_file)
    theme_name = "moduss_unificado_uss.json"
    theme_target = REPORT.parent / "StaticResources" / "RegisteredResources" / theme_name
    if not REFERENCE_THEME.exists():
        raise FileNotFoundError(f"No existe el tema MODUSS de referencia: {REFERENCE_THEME}")
    theme_target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(REFERENCE_THEME, theme_target)

    report_json.setdefault("themeCollection", {}).setdefault("customTheme", {}).update(
        {"name": theme_name, "type": "RegisteredResources"}
    )
    registered = next(
        package
        for package in report_json.setdefault("resourcePackages", [])
        if package.get("name") == "RegisteredResources"
    )
    registered["items"] = [
        item for item in registered.get("items", []) if item.get("type") != "CustomTheme"
    ]
    registered["items"].insert(
        0, {"name": theme_name, "path": theme_name, "type": "CustomTheme"}
    )
    write_json(report_file, report_json)

    for page_dir in PAGES.iterdir():
        if not page_dir.is_dir() or not (page_dir / "page.json").exists():
            continue
        set_canvas(page_dir)
        menu_button_path = next((page_dir / "visuals").glob("*_menu_open/visual.json"), None)
        menu_button = read_json(menu_button_path) if menu_button_path else None
        for visual_path in (page_dir / "visuals").glob("*/visual.json"):
            visual = read_json(visual_path)
            visual_def = visual.get("visual", {})
            visual_type = visual_def.get("visualType")

            if visual_type == "slicer" and str(visual.get("parentGroupName", "")).endswith("_filter_group"):
                visual["position"].update({"x": 944, "width": 312, "height": 80})

            if visual_type in {"clusteredBarChart", "clusteredColumnChart", "lineClusteredColumnComboChart", "tableEx", "matrix"}:
                containers = visual_def.setdefault("visualContainerObjects", {})
                border = containers.setdefault("border", [{"properties": {}}])
                border_props = border[0].setdefault("properties", {})
                border_props.update(
                    {
                        "show": {"expr": {"Literal": {"Value": "true"}}},
                        "color": {"solid": {"color": literal("#D9DEE2")}},
                        "radius": {"expr": {"Literal": {"Value": "6D"}}},
                    }
                )
                title = containers.get("title", [])
                if title:
                    title_props = title[0].setdefault("properties", {})
                    title_props.update(
                        {
                            "fontFamily": literal("Segoe UI"),
                            "fontColor": {"solid": {"color": literal("#001E61")}},
                            "fontSize": {"expr": {"Literal": {"Value": "11D"}}},
                        }
                    )

            if visual.get("name") == "res_descargar":
                visual["position"].update({"y": 418, "height": 38})
                if menu_button:
                    old_link = copy.deepcopy(
                        visual_def.get("visualContainerObjects", {}).get("visualLink", [])
                    )
                    visual_def["objects"] = copy.deepcopy(menu_button["visual"]["objects"])
                    text_objects = visual_def["objects"].get("text", [])
                    if len(text_objects) > 1:
                        text_objects[1].setdefault("properties", {})["text"] = literal(
                            "Descargar sábana completa"
                        )
                    visual_def["visualContainerObjects"] = copy.deepcopy(
                        menu_button["visual"].get("visualContainerObjects", {})
                    )
                    visual_def["visualContainerObjects"]["visualLink"] = old_link

            write_json(visual_path, visual)


def clone_page(item: dict) -> list[dict]:
    template_page = PAGES / "detalle_calificacion"
    target = PAGES / item["id"]
    if target.exists():
        remove_tree(target)
    target.mkdir(parents=True)
    page = read_json(template_page / "page.json")
    page["name"] = item["id"]
    page["displayName"] = item["display"]
    page["height"] = 1800
    page["width"] = 1280
    page["displayOption"] = "ActualSize"
    write_json(target / "page.json", page)

    table_template = read_json(PAGES / "resumen_solicitudes" / "visuals" / "res_tabla" / "visual.json")
    bar_template = read_json(PAGES / "resumen_solicitudes" / "visuals" / "res_tipo" / "visual.json")
    visuals: list[dict] = []
    for path in (template_page / "visuals").glob("*/visual.json"):
        visual = read_json(path)
        old_name = visual.get("name", "")
        if old_name == "cal_tabla":
            continue
        visual = recursive_replace(
            visual,
            {
                "cal_": f"{item['prefix']}_",
                "cal_filter": f"{item['prefix']}_filter",
                "cal_menu": f"{item['prefix']}_menu",
                "detalle_calificacion": item["id"],
                "solicitudes_calificacion": "solicitudes_workflow",
                "Encabezado Calificación": item["header"],
                "HTML KPI Calificación": "HTML KPI Detalle Workflow",
                "dim_periodo": "solicitudes_workflow",
                "dim_estado": "solicitudes_workflow",
            },
        )
        name = visual.get("name", "")
        if name.endswith(("_filter_group", "_menu_group", "_overlay", "_menu_overlay", "_panel", "_menu_panel")):
            visual["position"]["height"] = 1800
        if name.endswith("_menu_pages"):
            visual["position"]["height"] = 1660
        if name.endswith("_header"):
            visual["position"].update({"height": 145})
            visual["filterConfig"] = categorical_filter("solicitudes_workflow", "categoria_solicitud", item["category"], f"flt_{item['prefix']}_header")
        if name.endswith("_kpi"):
            visual["position"].update({"y": 170, "height": 165})
            visual["filterConfig"] = categorical_filter("solicitudes_workflow", "categoria_solicitud", item["category"], f"flt_{item['prefix']}_kpi")
        if visual.get("visual", {}).get("visualType") == "slicer":
            visual["filterConfig"] = categorical_filter("solicitudes_workflow", "categoria_solicitud", item["category"], f"flt_{item['prefix']}_{name}")
        visuals.append(visual)

    detail_fields = [
        ("solicitudes_workflow", "id", "Column"),
        ("solicitudes_workflow", "periodo", "Column"),
        ("solicitudes_workflow", "estado_operacional", "Column"),
        ("solicitudes_workflow", "estado_actual", "Column"),
        ("solicitudes_workflow", "fecha_inicio", "Column"),
        ("solicitudes_workflow", "fecha_cierre", "Column"),
        ("solicitudes_workflow", "sede", "Column"),
        ("solicitudes_workflow", "nivel", "Column"),
        ("solicitudes_workflow", "rut_estudiante", "Column"),
        ("solicitudes_workflow", "nombre_propiedad", "Column"),
        ("solicitudes_workflow", "valor_propiedad", "Column"),
    ]
    table = make_table(table_template, f"{item['prefix']}_tabla", detail_fields, f"Sábana histórica - {item['display']}", 24, 735, 1232, 1025)
    table["filterConfig"] = categorical_filter("solicitudes_workflow", "categoria_solicitud", item["category"], f"flt_{item['prefix']}_tabla")
    visuals.append(table)
    for suffix, category, title, x in (
        ("estado", "estado_operacional", "Solicitudes por estado", 24),
        ("periodo_chart", "periodo", "Solicitudes por periodo", 644),
    ):
        chart = make_bar(bar_template, f"{item['prefix']}_{suffix}", category, title, x, 355, 612, 350)
        chart["filterConfig"] = categorical_filter("solicitudes_workflow", "categoria_solicitud", item["category"], f"flt_{item['prefix']}_{suffix}")
        visuals.append(chart)

    visuals_dir = target / "visuals"
    for visual in visuals:
        write_json(visuals_dir / visual["name"] / "visual.json", visual)
    return make_bookmarks(item["id"], item["prefix"])


def make_bookmarks(page: str, prefix: str) -> list[dict]:
    items = []
    for panel in ("filter", "menu"):
        group = f"{prefix}_{panel}_group"
        for state, hidden in (("on", False), ("off", True)):
            name = f"{prefix}_{panel}_{state}"
            items.append(
                {
                    "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.1.0/schema.json",
                    "displayName": f"{prefix} - {panel} {state}",
                    "name": name,
                    "options": {"applyOnlyToTargetVisuals": True, "targetVisualNames": [group], "suppressData": True},
                    "explorationState": {
                        "version": "1.3",
                        "activeSection": page,
                        "sections": {page: {"visualContainers": {}, "visualContainerGroups": {group: {"isHidden": hidden}}}},
                        "objects": {},
                    },
                }
            )
    return items


def update_summary() -> None:
    page_dir = PAGES / "resumen_solicitudes"
    page = read_json(page_dir / "page.json")
    page.update({"height": 1800, "width": 1280, "displayOption": "ActualSize"})
    write_json(page_dir / "page.json", page)
    visuals_dir = page_dir / "visuals"
    header = read_json(visuals_dir / "res_header" / "visual.json")
    header = recursive_replace(header, {"Encabezado Resumen": "Encabezado Resumen Workflow"})
    header = json.loads(
        re.sub(
            r"Encabezado Resumen(?: Workflow)+",
            "Encabezado Resumen Workflow",
            json.dumps(header, ensure_ascii=False),
        )
    )
    header["position"]["height"] = 145
    write_json(visuals_dir / "res_header" / "visual.json", header)
    kpi = read_json(visuals_dir / "res_kpi" / "visual.json")
    kpi = recursive_replace(kpi, {"HTML KPI Resumen": "HTML KPI Resumen Workflow"})
    kpi = json.loads(
        re.sub(
            r"HTML KPI Resumen(?: Workflow)+",
            "HTML KPI Resumen Workflow",
            json.dumps(kpi, ensure_ascii=False),
        )
    )
    kpi["position"].update({"y": 170, "height": 245})
    write_json(visuals_dir / "res_kpi" / "visual.json", kpi)

    table_template = read_json(visuals_dir / "res_tabla" / "visual.json")
    summary_fields = [
        ("solicitudes_workflow", "periodo", "Column"),
        ("solicitudes_workflow", "categoria_solicitud", "Column"),
        ("solicitudes_workflow", "estado_operacional", "Column"),
        ("solicitudes_workflow", "estado_actual", "Column"),
        ("Medidas Solicitudes", "Solicitudes Total", "Measure"),
    ]
    summary = make_table(table_template, "res_tabla", summary_fields, "Solicitudes por periodo, tipo y estado técnico", 24, 455, 720, 360)
    write_json(visuals_dir / "res_tabla" / "visual.json", summary)
    raw_fields = [
        ("solicitudes_workflow", "id", "Column"),
        ("solicitudes_workflow", "periodo", "Column"),
        ("solicitudes_workflow", "categoria_solicitud", "Column"),
        ("solicitudes_workflow", "estado_operacional", "Column"),
        ("solicitudes_workflow", "fecha_inicio", "Column"),
        ("solicitudes_workflow", "sede", "Column"),
        ("solicitudes_workflow", "nivel", "Column"),
    ]
    preview = make_table(table_template, "res_preview", raw_fields, "Vista previa de solicitudes", 24, 1235, 1232, 525)
    write_json(visuals_dir / "res_preview" / "visual.json", preview)

    bar_source = visuals_dir / "res_sede" / "visual.json"
    if not bar_source.exists():
        bar_source = visuals_dir / "res_tipo" / "visual.json"
    bar_template = read_json(bar_source)
    charts = [
        make_bar(bar_template, "res_tipo", "categoria_solicitud", "Solicitudes por tipo", 764, 455, 492, 360),
        make_bar(bar_template, "res_estado", "estado_operacional", "Solicitudes por estado", 24, 835, 600, 370),
        make_bar(bar_template, "res_periodo_chart", "periodo", "Solicitudes por periodo", 644, 835, 612, 370),
    ]
    old_bar = visuals_dir / "res_sede"
    if old_bar.exists():
        remove_tree(old_bar)
    for chart in charts:
        write_json(visuals_dir / chart["name"] / "visual.json", chart)

    for slicer_name, old_entity, new_prop in (
        ("res_periodo", "dim_periodo", "periodo"),
        ("res_estado_operacional", "dim_estado", "estado_operacional"),
        ("res_tipo_solicitud", "dim_tipo_solicitud", "categoria_solicitud"),
    ):
        path = visuals_dir / slicer_name / "visual.json"
        visual = read_json(path)
        visual = recursive_replace(visual, {old_entity: "solicitudes_workflow", "tipo_solicitud": new_prop})
        write_json(path, visual)

    button = make_page_button("res_descargar", "Descargar sábana completa", "sabana_completa", 986, 420, 254, 36)
    write_json(visuals_dir / "res_descargar" / "visual.json", button)
    set_canvas(page_dir)


def create_raw_page() -> list[dict]:
    item = {
        "id": "sabana_completa",
        "prefix": "raw",
        "display": "Sábana completa",
        "category": None,
        "header": "Encabezado Sábana",
    }
    template_page = PAGES / "detalle_calificacion"
    target = PAGES / item["id"]
    if target.exists():
        remove_tree(target)
    target.mkdir(parents=True)
    page = read_json(template_page / "page.json")
    page.update({"name": item["id"], "displayName": item["display"], "height": 1800, "width": 1280, "displayOption": "ActualSize"})
    write_json(target / "page.json", page)
    visuals = []
    for path in (template_page / "visuals").glob("*/visual.json"):
        visual = read_json(path)
        if visual.get("name") == "cal_tabla":
            continue
        visual = recursive_replace(
            visual,
            {
                "cal_": "raw_",
                "cal_filter": "raw_filter",
                "cal_menu": "raw_menu",
                "detalle_calificacion": "sabana_completa",
                "solicitudes_calificacion": "solicitudes_workflow",
                "Encabezado Calificación": "Encabezado Sábana",
                "HTML KPI Calificación": "HTML KPI Sábana",
                "dim_periodo": "solicitudes_workflow",
                "dim_estado": "solicitudes_workflow",
            },
        )
        name = visual.get("name", "")
        if name.endswith(("_filter_group", "_menu_group", "_overlay", "_menu_overlay", "_panel", "_menu_panel")):
            visual["position"]["height"] = 1800
        if name.endswith("_menu_pages"):
            visual["position"]["height"] = 1660
        if name == "raw_header":
            visual["position"]["height"] = 145
        if name == "raw_kpi":
            visual["position"].update({"y": 170, "height": 145})
        visuals.append(visual)

    # Convertir el slicer de nivel existente en tipo y agregar nivel como copia.
    type_slicer = next(v for v in visuals if v.get("name") == "raw_nivel")
    level_slicer = copy.deepcopy(type_slicer)
    type_slicer = recursive_replace(type_slicer, {"nivel": "categoria_solicitud", "Nivel académico": "Tipo de solicitud"})
    type_slicer["name"] = "raw_categoria_solicitud"
    type_slicer["position"]["y"] = 274
    level_slicer["name"] = "raw_nivel"
    level_slicer["position"]["y"] = 366
    for index, visual in enumerate(visuals):
        if visual.get("name") == "raw_nivel":
            visuals[index] = type_slicer
            break
    visuals.append(level_slicer)
    for visual in visuals:
        if visual.get("name") == "raw_sede":
            visual["position"]["y"] = 458

    fields = [("solicitudes_workflow", name, "Column") for name, _ in GENERIC_COLUMNS]
    fields.extend(
        [
            ("solicitudes_workflow", "fecha_inicio", "Column"),
            ("solicitudes_workflow", "fecha_cierre", "Column"),
        ]
    )
    table_template = read_json(PAGES / "resumen_solicitudes" / "visuals" / "res_tabla" / "visual.json")
    table = make_table(table_template, "raw_tabla", fields, "Sábana completa - una fila por solicitud y propiedad", 24, 335, 1232, 1425)
    visuals.append(table)
    for visual in visuals:
        write_json(target / "visuals" / visual["name"] / "visual.json", visual)
    return make_bookmarks(item["id"], item["prefix"])


def extend_existing_pages() -> None:
    for page_id, prefix in (("detalle_inscripcion", "ins"), ("detalle_calificacion", "cal")):
        page_dir = PAGES / page_id
        page = read_json(page_dir / "page.json")
        page.update({"height": 1800, "width": 1280, "displayOption": "ActualSize"})
        write_json(page_dir / "page.json", page)
        table_path = page_dir / "visuals" / f"{prefix}_tabla" / "visual.json"
        table = read_json(table_path)
        table["position"]["height"] = 1425
        write_json(table_path, table)
        set_canvas(page_dir)


def update_pages_and_bookmarks() -> None:
    update_summary()
    extend_existing_pages()
    new_bookmarks: list[dict] = []
    for item in NEW_TYPES:
        new_bookmarks.extend(clone_page(item))
    new_bookmarks.extend(create_raw_page())

    meta_path = PAGES / "pages.json"
    meta = read_json(meta_path)
    meta["pageOrder"] = [
        "resumen_solicitudes",
        "detalle_inscripcion",
        "detalle_calificacion",
        *[item["id"] for item in NEW_TYPES],
        "sabana_completa",
    ]
    meta["activePageName"] = "resumen_solicitudes"
    write_json(meta_path, meta)

    bm_meta_path = BOOKMARKS / "bookmarks.json"
    bm_meta = read_json(bm_meta_path)
    existing = {item["name"] for item in bm_meta.get("items", [])}
    for bm in new_bookmarks:
        write_json(BOOKMARKS / f"{bm['name']}.bookmark.json", bm)
        if bm["name"] not in existing:
            bm_meta.setdefault("items", []).append({"name": bm["name"]})
            existing.add(bm["name"])
    write_json(bm_meta_path, bm_meta)


def update_readme() -> None:
    text = '''# Panel de Solicitudes Operacionales

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
'''
    write_text(TARGET / "README.md", text)


def main() -> None:
    if not TARGET.exists():
        raise SystemExit(f"No existe el proyecto: {TARGET}")
    backup = make_backup()
    QUERIES.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SQL_SOURCE, QUERIES / "workflow_solicitudes_todas_historico.sql")
    if INVENTORY_SOURCE.exists():
        shutil.copy2(INVENTORY_SOURCE, QUERIES / "workflow_inventario_propiedades_athena.sql")
    sql = read_text(SQL_SOURCE)
    add_query_expression(sql)
    update_model()
    update_measures()
    update_pages_and_bookmarks()
    align_moduss_interface()
    update_readme()
    print(f"Proyecto actualizado: {TARGET}")
    print(f"Respaldo: {backup}")
    print(f"Páginas: {len(read_json(PAGES / 'pages.json')['pageOrder'])}")
    print(f"Columnas workflow: {len(GENERIC_COLUMNS) + 2}")


if __name__ == "__main__":
    main()
