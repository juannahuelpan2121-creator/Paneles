# Hallazgos de validación estructural — Solicitudes Operacionales

**Fecha:** 26 de agosto de 2026
**Panel:** Solicitudes Operacionales (versión OneDrive)
**Ruta del panel:** `C:\Users\juan.nahuelpan\OneDrive - Universidad San Sebastian\Desktop\Paneles\Solicitudes\Solicitudes Operacionales`
**Validador:** `tools/validate_solicitudes_panel.py` (repo `Paneles`)
**Estado general:** 🟢 Panel conforme al estándar MODUSS. Los 2 errores reportados son **falsos positivos del validador** — no requieren cambios en el panel.

---

## 1. Resumen ejecutivo

| Ítem | Resultado |
|---|---|
| Interfaz MODUSS (10 páginas) | ✅ Completa y conforme |
| Tema `moduss_unificado_uss.json` | ✅ Coincide byte a byte con el ejemplo |
| Cifras estructurales | ✅ 292 JSON · 6 tablas · 33 medidas (igual al baseline) |
| Errores del validador | ⚠️ 2, **ambos falsos positivos** |
| Acción sobre el **panel** | ❌ Ninguna requerida |
| Acción sobre el **validador** | ✅ 1 corrección (Opción A, abajo) |

> **No modifiques el panel para cerrar estos hallazgos.** La corrección va en el script validador.

---

## 2. Cómo reproducir la validación

Desde la raíz del repositorio:

```bash
python tools/validate_solicitudes_panel.py "C:\Users\juan.nahuelpan\OneDrive - Universidad San Sebastian\Desktop\Paneles\Solicitudes\Solicitudes Operacionales"
```

Salida obtenida:

```text
JSON revisados: 292
Tablas: 6
Medidas: 33
ERRORES:
No se pudo localizar la expresión de HTML KPI Sábana
El resumen todavía contiene la tarjeta de solicitudes canceladas
```

---

## 3. Diagnóstico de los hallazgos

| # | Mensaje | Diagnóstico verificado | ¿Defecto real? |
|---|---|---|---|
| 1 | *No se pudo localizar la expresión de HTML KPI Sábana* | La medida **existe y está bien formada** (`VAR v_HTML = "…" RETURN v_HTML`). El validador exige que el cuerpo esté envuelto en comillas triples ` ``` `; esta medida quedó serializada en **formato plano**, por lo que el regex no la encuentra. | ❌ No |
| 2 | *El resumen todavía contiene la tarjeta de solicitudes canceladas* | No existe ninguna tarjeta de canceladas (`grep "cancel"` en las medidas = 0 coincidencias). El error se dispara **solo porque** el mismo regex ` ``` ` no ubicó `HTML KPI Resumen Workflow`; al no poder parsear el cuerpo, el script asume que hay tarjeta de canceladas. | ❌ No |

### Causa raíz

Al editar/guardar el modelo en Power BI, las medidas de la familia *Workflow* (`HTML KPI Sábana`, `HTML KPI Resumen Workflow`) se re-serializaron del formato **fenced** (` ``` `) al formato **plano indentado**. El validador (líneas ~269-290) usa un regex que **solo** reconoce el formato fenced, y falla al leerlas. Esto volverá a ocurrir cada vez que se editen estas medidas, por lo que la solución durable es corregir el validador.

### Evidencia

```bash
# El TMDL mezcla ambos formatos: la familia Inscripción/Calificación usa ```; la familia Workflow, plano.
grep -c '```' "…\Medidas Solicitudes.tmdl"      # → 24 (medidas fenced)

# No hay tarjeta de canceladas en ninguna medida:
grep -in "cancel" "…\Medidas Solicitudes.tmdl"  # → 0 coincidencias

# HTML KPI Resumen Workflow tiene 6 tarjetas: totales, finalizadas, en curso,
# tasa de finalización, duración promedio, fuera del promedio. Ninguna es "canceladas".
```

Prueba del regex (actual vs. corregido) contra el archivo real:

| Medida | Regex actual (solo fenced) | Helper corregido (fenced + plano) |
|---|---|---|
| `HTML KPI Sábana` | ❌ no encuentra | ✅ encuentra · sin RETURN inicial · sin texto técnico |
| `HTML KPI Resumen Workflow` | ❌ no encuentra | ✅ encuentra · sin "Canceladas" |
| `HTML KPI Inscripción` (control fenced) | ✅ | ✅ (retrocompatible) |

---

## 4. Acciones a ejecutar

### ✅ Opción A — Corregir el validador (recomendada, durable)

**Dónde:** `tools/validate_solicitudes_panel.py`. Existe una segunda copia en `work/validate_solicitudes_panel.py`; aplica el mismo cambio en ambas si se usan.

**Qué hacer:** reemplazar el bloque de las líneas ~269 a ~290 por una función auxiliar que acepte serialización *fenced* y *plana*.

**Reemplazar ESTO (bloque actual):**

```python
raw_html_match = re.search(
    r"measure 'HTML KPI Sábana'\s*=\s*```\s*(.*?)\s*```",
    measure_text,
    re.S,
)
if not raw_html_match:
    errors.append("No se pudo localizar la expresión de HTML KPI Sábana")
else:
    raw_html_expression = raw_html_match.group(1).lstrip()
    if raw_html_expression.upper().startswith("RETURN"):
        errors.append("HTML KPI Sábana no puede comenzar con RETURN sin declarar una variable")
    for technical_text in ("ATHENA", "WORKFLOW_PROPIEDADES_JSON.SQL", "DESCARGA OPERACIONAL OPTIMIZADA"):
        if technical_text in raw_html_expression.upper():
            errors.append(f"HTML KPI Sábana conserva texto técnico: {technical_text}")

summary_html_match = re.search(
    r"measure 'HTML KPI Resumen Workflow'\s*=\s*```\s*(.*?)\s*```",
    measure_text,
    re.S,
)
if not summary_html_match or "Canceladas" in summary_html_match.group(1):
    errors.append("El resumen todavía contiene la tarjeta de solicitudes canceladas")
```

**POR ESTO (corregido y verificado):**

```python
def _measure_body(measure_name):
    """Cuerpo de una medida aceptando serializacion TMDL fenced (```) o plana."""
    match = re.search(
        r"measure '" + re.escape(measure_name) + r"'\s*=\s*(.*?)\n\s*lineageTag:",
        measure_text,
        re.S,
    )
    if not match:
        return None
    body = match.group(1).strip()
    if body.startswith("```"):
        body = body.strip("`").strip()
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
if summary_html_expression is None or "Canceladas" in summary_html_expression:
    errors.append("El resumen todavía contiene la tarjeta de solicitudes canceladas")
```

> Nota técnica: el helper corta el cuerpo en la línea `lineageTag:` (presente al final de cada medida) y, si detecta comillas triples, las remueve. Funciona igual con medidas *fenced* y *planas*.

### 🟡 Opción B — Reserializar las medidas al formato fenced (no recomendada)

Volver a escribir `HTML KPI Sábana` y `HTML KPI Resumen Workflow` en el TMDL con comillas triples ` ``` ` para que el validador actual las reconozca. **Desventaja:** Power BI puede volver a aplanarlas en el próximo guardado, reintroduciendo el falso positivo. Es una solución temporal; preferir la Opción A.

---

## 5. Verificación de cierre

Tras aplicar la Opción A, re-ejecutar:

```bash
python tools/validate_solicitudes_panel.py "C:\Users\juan.nahuelpan\OneDrive - Universidad San Sebastian\Desktop\Paneles\Solicitudes\Solicitudes Operacionales"
```

**Salida esperada:**

```text
JSON revisados: 292
Tablas: 6
Medidas: 33
VALIDACIÓN ESTRUCTURAL OK
```

Criterio de cierre: el validador termina en `VALIDACIÓN ESTRUCTURAL OK` (código de salida 0) **sin** haber modificado el panel.

---

## 6. Checklist para el analista

- [ ] Confirmar que el panel es la versión vigente en OneDrive.
- [ ] **No** modificar medidas, páginas ni visuales del panel por estos hallazgos.
- [ ] Aplicar la Opción A en `tools/validate_solicitudes_panel.py` (y en `work/` si aplica).
- [ ] Re-ejecutar el validador y confirmar `VALIDACIÓN ESTRUCTURAL OK`.
- [ ] Registrar el cambio del validador en el commit correspondiente (no versionar el panel si no hubo cambios funcionales).
