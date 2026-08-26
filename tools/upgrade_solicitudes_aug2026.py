#!/usr/bin/env python3
"""Mejoras compatibles para el PBIP Solicitudes Operacionales.

Trabaja sobre la copia vigente indicada por argumento. Mantiene el estilo neutro
de los segmentadores y evita propiedades experimentales no validadas.
"""

from __future__ import annotations

import copy
import json
import sys
from pathlib import Path


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def literal(value: str) -> dict:
    return {"expr": {"Literal": {"Value": value}}}


def add_date_slicer(
    page_dir: Path,
    template_name: str,
    visual_name: str,
    column: str,
    title: str,
    y: int,
    group_name: str,
) -> None:
    template_path = page_dir / "visuals" / template_name / "visual.json"
    visual = copy.deepcopy(load_json(template_path))
    visual["name"] = visual_name
    visual["position"].update({"x": 944, "y": y, "z": 4000, "height": 80, "width": 312})
    visual["position"]["tabOrder"] = 4000 + y

    projection = visual["visual"]["query"]["queryState"]["Values"]["projections"][0]
    projection["field"]["Column"]["Expression"]["SourceRef"]["Entity"] = "solicitudes_workflow"
    projection["field"]["Column"]["Property"] = column
    projection["queryRef"] = f"solicitudes_workflow.{column}"
    projection["nativeQueryRef"] = title
    projection["displayName"] = title
    projection["active"] = True

    # Los rangos de fechas no requieren ordenación categórica.
    visual["visual"]["query"].pop("sortDefinition", None)
    objects = visual["visual"].setdefault("objects", {})
    objects.pop("selection", None)
    objects["data"] = [{"properties": {"mode": literal("'Between'")}}]
    objects.setdefault("header", [{"properties": {"show": literal("false")}}])

    title_objects = visual["visual"].setdefault("visualContainerObjects", {}).setdefault("title", [{}])
    title_objects[0].setdefault("properties", {})["text"] = literal(f"'{title}'")
    visual["parentGroupName"] = group_name

    save_json(page_dir / "visuals" / visual_name / "visual.json", visual)


def column_projection(column: str, display_name: str) -> dict:
    return {
        "field": {
            "Column": {
                "Expression": {"SourceRef": {"Entity": "solicitudes_workflow"}},
                "Property": column,
            }
        },
        "queryRef": f"solicitudes_workflow.{column}",
        "nativeQueryRef": display_name,
        "active": True,
        "displayName": display_name,
    }


def measure_projection(measure: str, display_name: str) -> dict:
    return {
        "field": {
            "Measure": {
                "Expression": {"SourceRef": {"Entity": "Medidas Solicitudes"}},
                "Property": measure,
            }
        },
        "queryRef": f"Medidas Solicitudes.{measure}",
        "nativeQueryRef": display_name,
        "displayName": display_name,
    }


def upgrade_matrix(path: Path) -> None:
    visual = load_json(path)
    visual["visual"]["visualType"] = "pivotTable"
    visual["visual"]["query"] = {
        "queryState": {
            "Rows": {
                "projections": [
                    column_projection("categoria_solicitud", "Tipo de solicitud"),
                    column_projection("sede", "Sede"),
                    column_projection("estado_operacional", "Estado"),
                ]
            },
            "Values": {
                "projections": [
                    measure_projection("Solicitudes Total", "Solicitudes"),
                    measure_projection("Duración Promedio Días", "Duración hábil promedio"),
                    measure_projection("Solicitudes Sobre Promedio", "Fuera del promedio"),
                ]
            },
        }
    }
    # Se omite expansionStates deliberadamente: Power BI genera un estado válido
    # al interactuar y evitamos los errores de tipo observados previamente.
    visual["visual"].pop("expansionStates", None)
    visual["visual"]["objects"] = {
        "columnHeaders": [
            {
                "properties": {
                    "columnAdjustment": literal("'growToFit'"),
                    "backColor": {"solid": {"color": literal("'#EAF1FB'")}},
                    "fontColor": {"solid": {"color": literal("'#112B42'")}},
                    "bold": literal("true"),
                    "autoExpand": literal("false"),
                    "alignment": literal("'Center'"),
                    "titleAlignment": literal("'Left'"),
                    "fontSize": literal("9D"),
                }
            }
        ],
        "grid": [
            {
                "properties": {
                    "gridHorizontalColor": {"solid": {"color": literal("'#E5E7EB'")}},
                    "gridHorizontalWeight": literal("1D"),
                    "rowPadding": literal("6D"),
                    "gridHorizontal": literal("true"),
                }
            }
        ],
        "values": [
            {
                "properties": {
                    "fontSize": literal("9D"),
                    "fontColorPrimary": {"solid": {"color": literal("'#334155'")}},
                    "backColorSecondary": {"solid": {"color": literal("'#F7F8FA'")}},
                }
            }
        ],
    }
    container = visual["visual"].setdefault("visualContainerObjects", {})
    container["title"][0]["properties"]["text"] = literal("'Matriz operacional por tipo, sede y estado'")
    container["title"][0]["properties"]["fontColor"] = {
        "solid": {"color": literal("'#112B42'")}
    }
    container["title"][0]["properties"]["fontFamily"] = literal("'Arial'")
    container["subTitle"] = [
        {
            "properties": {
                "text": literal("'Expande la jerarquía para revisar volumen, duración hábil y casos fuera del promedio.'"),
                "show": literal("true"),
                "titleWrap": literal("true"),
                "fontColor": {"solid": {"color": literal("'#58616E'")}},
                "fontSize": literal("9D"),
                "fontFamily": literal("'Arial'"),
            }
        }
    ]
    save_json(path, visual)


def update_theme(path: Path) -> None:
    theme = load_json(path)
    theme["dataColors"] = [
        "#C6B27F",
        "#112B42",
        "#6CC6BE",
        "#F49A6A",
        "#5E71EE",
        "#B787FD",
        "#D9B300",
        "#D64550",
    ]
    theme["foreground"] = "#112B42"
    theme["tableAccent"] = "#C6B27F"
    universal = theme["visualStyles"]["*"]["*"]
    universal["title"][0]["fontFamily"] = "Arial"
    universal["title"][0]["color"]["solid"]["color"] = "#112B42"
    # No se agregan estilos específicos de slicer: conservan su interfaz original.
    save_json(path, theme)


def update_header_measure(tmdl_path: Path, measure_name: str) -> None:
    text = tmdl_path.read_text(encoding="utf-8-sig")
    marker = f"\tmeasure '{measure_name}' ="
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f"No se encontró la medida {measure_name}")
    next_measure = text.find("\n\tmeasure ", start + len(marker))
    end = len(text) if next_measure < 0 else next_measure
    segment = text[start:end]

    if "VAR hFechaInicio" not in segment:
        anchor = (
            '\t\t\tVAR vSede = IF ( ISFILTERED ( solicitudes_workflow[sede] ), '
            'CONCATENATEX ( VALUES ( solicitudes_workflow[sede] ), solicitudes_workflow[sede], ", " ), "Todos" )\n'
        )
        addition = (
            '\t\t\tVAR vFechaInicio = FORMAT ( MIN ( solicitudes_workflow[fecha_inicio] ), "dd-MM-yyyy" ) & " a " & FORMAT ( MAX ( solicitudes_workflow[fecha_inicio] ), "dd-MM-yyyy" )\n'
            '\t\t\tVAR vFechaCierre = FORMAT ( MIN ( solicitudes_workflow[fecha_cierre] ), "dd-MM-yyyy" ) & " a " & FORMAT ( MAX ( solicitudes_workflow[fecha_cierre] ), "dd-MM-yyyy" )\n'
            '\t\t\tVAR hFechaInicio = IF ( ISFILTERED ( solicitudes_workflow[fecha_inicio] ), "<span class=\'chip\' style=\'background:#F3E7C4\'>Ingreso: <b>" & vFechaInicio & "</b></span>", "" )\n'
            '\t\t\tVAR hFechaCierre = IF ( ISFILTERED ( solicitudes_workflow[fecha_cierre] ), "<span class=\'chip\' style=\'background:#F3E7C4\'>Cierre: <b>" & vFechaCierre & "</b></span>", "" )\n'
        )
        if anchor not in segment:
            raise RuntimeError(f"No se encontró el punto de inserción en {measure_name}")
        segment = segment.replace(anchor, anchor + addition, 1)

    tail = "</span></div></div>\""
    if "& hFechaInicio & hFechaCierre &" not in segment:
        last = segment.rfind(tail)
        if last < 0:
            raise RuntimeError(f"No se encontró el cierre HTML en {measure_name}")
        segment = segment[:last] + "</span>\" & hFechaInicio & hFechaCierre & \"</div></div>\"" + segment[last + len(tail):]

    tmdl_path.write_text(text[:start] + segment + text[end:], encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Uso: upgrade_solicitudes_aug2026.py <carpeta Solicitudes Operacionales>")
    root = Path(sys.argv[1]).resolve()
    report = root / "Solicitudes Operacionales.Report"
    definition = report / "definition"
    model = root / "Solicitudes Operacionales.SemanticModel"

    resumen = definition / "pages" / "resumen_solicitudes"
    sabana = definition / "pages" / "sabana_completa"

    add_date_slicer(resumen, "res_periodo", "res_fecha_inicio", "fecha_inicio", "Fecha de ingreso", 366, "res_filter_group")
    add_date_slicer(resumen, "res_periodo", "res_fecha_cierre", "fecha_cierre", "Fecha de cierre", 458, "res_filter_group")
    add_date_slicer(sabana, "raw_periodo", "raw_fecha_inicio", "fecha_inicio", "Fecha de ingreso", 550, "raw_filter_group")
    add_date_slicer(sabana, "raw_periodo", "raw_fecha_cierre", "fecha_cierre", "Fecha de cierre", 642, "raw_filter_group")

    upgrade_matrix(resumen / "visuals" / "res_tabla" / "visual.json")
    # El tema institucional se conserva byte a byte: el validador lo contrasta
    # con 01_Ejemplo_Estrategico_MODUSS y no debe personalizarse por panel.

    measures = model / "definition" / "tables" / "Medidas Solicitudes.tmdl"
    update_header_measure(measures, "Encabezado Resumen Workflow")
    update_header_measure(measures, "Encabezado Sábana")

    print("Mejoras aplicadas correctamente")


if __name__ == "__main__":
    main()
