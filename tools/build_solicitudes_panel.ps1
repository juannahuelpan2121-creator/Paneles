param([string]$ProjectName = 'Solicitudes Operacionales')

$ErrorActionPreference = 'Stop'

$repo = 'C:\Users\juan.nahuelpan\OneDrive - Universidad San Sebastian\Desktop\Paneles'
$solution = Join-Path $repo "Solicitudes\$ProjectName"
$report = Join-Path $solution "$ProjectName.Report"
$model = Join-Path $solution "$ProjectName.SemanticModel"
$definition = Join-Path $model 'definition'
$tablesDir = Join-Path $definition 'tables'
$pagesDir = Join-Path $report 'definition\pages'
$bookmarksDir = Join-Path $report 'definition\bookmarks'
$queriesDir = Join-Path $repo 'Solicitudes\Queries'
$sourceOutputs = 'C:\Users\juan.nahuelpan\Documents\Codex\2026-08-19\https-github-com-juannahuelpan2121-creator-paneles\outputs'
$templateReport = Join-Path $repo 'Panel Ejemplo\Kit Power BI Referencias\02_Ejemplo_Operativo_Carga_Real\Carga Real.Report'
$strategicVisuals = Join-Path $repo 'Panel Ejemplo\Kit Power BI Referencias\01_Ejemplo_Estrategico_MODUSS\Modus.Report\definition\pages\da579c96d09850281cec\visuals'

function Write-Utf8([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent) { [System.IO.Directory]::CreateDirectory($parent) | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Write-Json([string]$Path, $Object) {
    Write-Utf8 $Path ($Object | ConvertTo-Json -Depth 100)
}

function New-StrategicVisual([string]$SourceName,[string]$Name,[string]$Parent='') {
    $source = Join-Path $strategicVisuals "$SourceName\visual.json"
    $obj = Get-Content -LiteralPath $source -Raw -Encoding utf8 | ConvertFrom-Json
    $obj.name = $Name
    if($Parent){
        $obj | Add-Member -NotePropertyName parentGroupName -NotePropertyValue $Parent -Force
    } elseif($obj.PSObject.Properties.Name -contains 'parentGroupName') {
        $obj.PSObject.Properties.Remove('parentGroupName')
    }
    return $obj
}

function Set-BookmarkTarget($Visual,[string]$Bookmark) {
    $Visual.visual.visualContainerObjects.visualLink[0].properties.bookmark.expr.Literal.Value = "'$Bookmark'"
}

function New-LineageTag { return [guid]::NewGuid().ToString() }

foreach($folder in @($solution,$report,$model,$definition,$tablesDir,$pagesDir,$bookmarksDir,$queriesDir,(Join-Path $report 'definition'))){
    [System.IO.Directory]::CreateDirectory($folder) | Out-Null
}

Copy-Item -LiteralPath (Join-Path $sourceOutputs 'REPORTE_WF_INSCRIPCION_EXTRAORDINARIA_DATALAKE.sql') -Destination (Join-Path $queriesDir 'REPORTE_WF_INSCRIPCION_EXTRAORDINARIA_HISTORICO.sql') -Force
Copy-Item -LiteralPath (Join-Path $sourceOutputs 'REPORTE_WF_CAMBIO_CALIFICACION_DATALAKE.sql') -Destination (Join-Path $queriesDir 'REPORTE_WF_CAMBIO_CALIFICACION_HISTORICO.sql') -Force
Copy-Item -LiteralPath (Join-Path $sourceOutputs 'NOTAS_MIGRACION_QUERIES_WORKFLOW.md') -Destination (Join-Path $queriesDir 'NOTAS_MIGRACION.md') -Force

$insSql = Get-Content -LiteralPath (Join-Path $queriesDir 'REPORTE_WF_INSCRIPCION_EXTRAORDINARIA_HISTORICO.sql') -Raw
$calSql = Get-Content -LiteralPath (Join-Path $queriesDir 'REPORTE_WF_CAMBIO_CALIFICACION_HISTORICO.sql') -Raw

function Convert-ToMText([string]$Sql) {
    return ($Sql.Replace('"','""').Replace("`r`n", '#(lf)').Replace("`n", '#(lf)'))
}

$insM = Convert-ToMText $insSql
$calM = Convert-ToMText $calSql

$expressions = @"
expression query_solicitudes_inscripcion = __TMDL_FENCE__
let
    Query = "$insM"
in
    Query
__TMDL_FENCE__

	lineageTag: $(New-LineageTag)
	queryGroup: Queries

	annotation PBI_NavigationStepName = Navigation

	annotation PBI_ResultType = Text

expression query_solicitudes_calificacion = __TMDL_FENCE__
let
    Query = "$calM"
in
    Query
__TMDL_FENCE__

	lineageTag: $(New-LineageTag)
	queryGroup: Queries

	annotation PBI_NavigationStepName = Navigation

	annotation PBI_ResultType = Text
"@
$expressions = $expressions.Replace('__TMDL_FENCE__', '```')
Write-Utf8 (Join-Path $definition 'expressions.tmdl') $expressions

$insColumns = @(
    @{n='id';t='int64'}, @{n='pd_id';t='int64'}, @{n='name';t='string'},
    @{n='rut_estudiante';t='string'}, @{n='nombre_estudiante';t='string'}, @{n='c_carrera';t='string'},
    @{n='estado_alumno';t='string'}, @{n='email_alumno';t='string'}, @{n='nivel';t='string'},
    @{n='periodo_adm';t='string'}, @{n='retencion';t='string'}, @{n='sede';t='string'},
    @{n='secuencia_plan';t='string'}, @{n='pga';t='string'}, @{n='asignaturas_aprobadas';t='string'},
    @{n='fecha_solicitud';t='string'}, @{n='periodo';t='string'}, @{n='c_codigo_solicitud';t='string'},
    @{n='comentario';t='string'}
)
for($i=1;$i -le 12;$i++){
    $insColumns += @{n="nrc$i";t='string'}
    $insColumns += @{n="resp_nrc$i";t='string'}
}
$insColumns += @(
    @{n='nrcs_solicitados';t='string'}, @{n='nrcs_rechazado';t='string'}, @{n='mensaje';t='string'},
    @{n='estado_actual';t='string'}, @{n='start_date';t='int64'}, @{n='stop_date';t='int64'},
    @{n='ejecutandose';t='string'}, @{n='ultimo_estado';t='string'}, @{n='originating_user_id';t='string'},
    @{n='originating_event_id';t='string'}, @{n='originating_process_id';t='string'}, @{n='owner_role_id';t='string'},
    @{n='admin_role_id';t='string'}, @{n='requires_execution_plan';t='string'}, @{n='estado_operacional';t='string'}
)

$calColumns = @(
    @{n='id';t='int64'}, @{n='pd_id';t='int64'}, @{n='name';t='string'},
    @{n='desc_estado_estudiante';t='string'}, @{n='periodo';t='string'}, @{n='nrc';t='string'},
    @{n='curso';t='string'}, @{n='cod_sede';t='string'}, @{n='sede';t='string'},
    @{n='fecha_solicitud';t='string'}, @{n='cod_carrera';t='string'}, @{n='nombre_carrera';t='string'},
    @{n='nomescuela';t='string'}, @{n='observacion_szarsol';t='string'}, @{n='seqplan';t='string'},
    @{n='nivel';t='string'}, @{n='calificacion_actual';t='string'}, @{n='calificacion_solicitada';t='string'},
    @{n='rut_solicitante';t='string'}, @{n='nombre_solicitante';t='string'}, @{n='rut_estudiante';t='string'},
    @{n='nombre_estudiante';t='string'}, @{n='correo_estudiante';t='string'}, @{n='fono_estudiante';t='string'},
    @{n='rut_docente';t='string'}, @{n='nombre_docente';t='string'}, @{n='correo_docente';t='string'},
    @{n='glosa';t='string'}, @{n='rut_decano';t='string'}, @{n='nombre_decano';t='string'},
    @{n='correo_decano';t='string'}, @{n='rut_director_academico';t='string'}, @{n='nombre_director_academico';t='string'},
    @{n='correo_director_academico';t='string'}, @{n='rut_dc_o_dd';t='string'}, @{n='nombre_dc_o_dd';t='string'},
    @{n='correo_dc_o_dd';t='string'}, @{n='rut_registro_academico';t='string'}, @{n='nombre_registro_academico';t='string'},
    @{n='correo_registro_academico';t='string'}, @{n='nombre_titulos_y_grados';t='string'}, @{n='correo_titulos_y_grados';t='string'},
    @{n='comentario_solicitante';t='string'}, @{n='estado_actual';t='string'}, @{n='start_date';t='int64'},
    @{n='stop_date';t='int64'}, @{n='ejecutandose';t='string'}, @{n='ultimo_estado';t='string'},
    @{n='originating_user_id';t='string'}, @{n='originating_event_id';t='string'}, @{n='originating_process_id';t='string'},
    @{n='owner_role_id';t='string'}, @{n='admin_role_id';t='string'}, @{n='requires_execution_plan';t='string'},
    @{n='estado_operacional';t='string'}
)

function New-ImportedTableTmdl([string]$TableName, $Columns, [string]$QueryExpression) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("table $TableName")
    $lines.Add("`tlineageTag: $(New-LineageTag)")
    $lines.Add('')
    foreach($col in $Columns){
        $lines.Add("`tcolumn $($col.n)")
        $lines.Add("`t`tdataType: $($col.t)")
        if($col.t -eq 'dateTime') { $lines.Add("`t`tformatString: General Date") }
        $lines.Add("`t`tlineageTag: $(New-LineageTag)")
        $lines.Add("`t`tsummarizeBy: none")
        $lines.Add("`t`tsourceColumn: $($col.n)")
        $lines.Add('')
        $lines.Add("`t`tannotation SummarizationSetBy = Automatic")
        $lines.Add('')
    }
    foreach($dateCol in @(@{n='start_datetime';source='start_date'}, @{n='stop_datetime';source='stop_date'})){
        $lines.Add("`tcolumn $($dateCol.n) =")
        $lines.Add("`t`t`tVAR epoch_ms = [$($dateCol.source)]")
        $lines.Add("`t`t`tRETURN")
        $lines.Add("`t`t`t`tIF (")
        $lines.Add("`t`t`t`t`tISBLANK ( epoch_ms ),")
        $lines.Add("`t`t`t`t`tBLANK (),")
        $lines.Add("`t`t`t`t`tDATE ( 1970, 1, 1 ) + DIVIDE ( epoch_ms, 86400000 )")
        $lines.Add("`t`t`t`t)")
        $lines.Add("`t`tdataType: dateTime")
        $lines.Add("`t`tformatString: General Date")
        $lines.Add("`t`tlineageTag: $(New-LineageTag)")
        $lines.Add("`t`tsummarizeBy: none")
        $lines.Add('')
        $lines.Add("`t`tannotation SummarizationSetBy = Automatic")
        $lines.Add('')
    }
    $lines.Add("`tpartition $TableName = m")
    $lines.Add("`t`tmode: import")
    $lines.Add("`t`tqueryGroup: Datos")
    $lines.Add("`t`tsource =")
    $lines.Add("`t`t`t`tlet")
    $lines.Add("`t`t`t`t    Origen = Odbc.Query(`"dsn=uss-athena-datalake-prod`", $QueryExpression)")
    $lines.Add("`t`t`t`tin")
    $lines.Add("`t`t`t`t    Origen")
    $lines.Add('')
    $lines.Add("`tannotation PBI_NavigationStepName = Navegación")
    $lines.Add('')
    $lines.Add("`tannotation PBI_ResultType = Table")
    return ($lines -join "`r`n")
}

Write-Utf8 (Join-Path $tablesDir 'solicitudes_inscripcion.tmdl') (New-ImportedTableTmdl 'solicitudes_inscripcion' $insColumns 'query_solicitudes_inscripcion')
Write-Utf8 (Join-Path $tablesDir 'solicitudes_calificacion.tmdl') (New-ImportedTableTmdl 'solicitudes_calificacion' $calColumns 'query_solicitudes_calificacion')

$consolidated = @"
table solicitudes_consolidadas
	lineageTag: $(New-LineageTag)

	column id_solicitud
		dataType: int64
		lineageTag: $(New-LineageTag)
		summarizeBy: none
		isNameInferred
		sourceColumn: [id_solicitud]

	column periodo
		dataType: string
		lineageTag: $(New-LineageTag)
		summarizeBy: none
		isNameInferred
		sourceColumn: [periodo]

	column tipo_solicitud
		dataType: string
		lineageTag: $(New-LineageTag)
		summarizeBy: none
		isNameInferred
		sourceColumn: [tipo_solicitud]

	column estado_operacional
		dataType: string
		lineageTag: $(New-LineageTag)
		summarizeBy: none
		isNameInferred
		sourceColumn: [estado_operacional]

	column estado_actual
		dataType: string
		lineageTag: $(New-LineageTag)
		summarizeBy: none
		isNameInferred
		sourceColumn: [estado_actual]

	column sede
		dataType: string
		lineageTag: $(New-LineageTag)
		summarizeBy: none
		isNameInferred
		sourceColumn: [sede]

	column fecha_inicio
		dataType: dateTime
		formatString: General Date
		lineageTag: $(New-LineageTag)
		summarizeBy: none
		isNameInferred
		sourceColumn: [fecha_inicio]

	column fecha_termino
		dataType: dateTime
		formatString: General Date
		lineageTag: $(New-LineageTag)
		summarizeBy: none
		isNameInferred
		sourceColumn: [fecha_termino]

	partition solicitudes_consolidadas = calculated
		mode: import
		source =
				UNION (
				    SELECTCOLUMNS (
				        solicitudes_inscripcion,
				        "id_solicitud", solicitudes_inscripcion[id],
				        "periodo", solicitudes_inscripcion[periodo],
				        "tipo_solicitud", "Inscripción extraordinaria",
				        "estado_operacional", solicitudes_inscripcion[estado_operacional],
				        "estado_actual", solicitudes_inscripcion[estado_actual],
				        "sede", COALESCE ( solicitudes_inscripcion[sede], "Sin sede" ),
				        "fecha_inicio", solicitudes_inscripcion[start_datetime],
				        "fecha_termino", solicitudes_inscripcion[stop_datetime]
				    ),
				    SELECTCOLUMNS (
				        solicitudes_calificacion,
				        "id_solicitud", solicitudes_calificacion[id],
				        "periodo", solicitudes_calificacion[periodo],
				        "tipo_solicitud", "Cambio de calificación",
				        "estado_operacional", solicitudes_calificacion[estado_operacional],
				        "estado_actual", solicitudes_calificacion[estado_actual],
				        "sede", COALESCE ( solicitudes_calificacion[sede], "Sin sede" ),
				        "fecha_inicio", solicitudes_calificacion[start_datetime],
				        "fecha_termino", solicitudes_calificacion[stop_datetime]
				    )
				)
"@
Write-Utf8 (Join-Path $tablesDir 'solicitudes_consolidadas.tmdl') $consolidated

function New-DimensionTmdl([string]$Name, [string]$Column, [string]$SourceColumn) {
@"
table $Name
	lineageTag: $(New-LineageTag)

	column $Column
		dataType: string
		lineageTag: $(New-LineageTag)
		summarizeBy: none
		isNameInferred
		sourceColumn: [$Column]

	partition $Name = calculated
		mode: import
		source = DISTINCT ( SELECTCOLUMNS ( solicitudes_consolidadas, "$Column", solicitudes_consolidadas[$SourceColumn] ) )
"@
}
Write-Utf8 (Join-Path $tablesDir 'dim_periodo.tmdl') (New-DimensionTmdl 'dim_periodo' 'periodo' 'periodo')
Write-Utf8 (Join-Path $tablesDir 'dim_estado.tmdl') (New-DimensionTmdl 'dim_estado' 'estado_operacional' 'estado_operacional')
Write-Utf8 (Join-Path $tablesDir 'dim_tipo_solicitud.tmdl') (New-DimensionTmdl 'dim_tipo_solicitud' 'tipo_solicitud' 'tipo_solicitud')

function New-HeaderDax([string]$Title, [string]$Subtitle, [string]$Mode) {
$extraVars = if($Mode -eq 'Resumen') {
@'
VAR vExtra1 = IF ( ISFILTERED ( dim_tipo_solicitud[tipo_solicitud] ), CONCATENATEX ( VALUES ( dim_tipo_solicitud[tipo_solicitud] ), dim_tipo_solicitud[tipo_solicitud], ", " ), "Todos" )
VAR cExtra1 = IF ( ISFILTERED ( dim_tipo_solicitud[tipo_solicitud] ), "#F3E7C4", "#EAF1FB" )
VAR vExtra2 = ""
VAR cExtra2 = "#EAF1FB"
'@
} elseif($Mode -eq 'Inscripcion') {
@'
VAR vExtra1 = IF ( ISFILTERED ( solicitudes_inscripcion[nivel] ), CONCATENATEX ( VALUES ( solicitudes_inscripcion[nivel] ), solicitudes_inscripcion[nivel], ", " ), "Todos" )
VAR cExtra1 = IF ( ISFILTERED ( solicitudes_inscripcion[nivel] ), "#F3E7C4", "#EAF1FB" )
VAR vExtra2 = IF ( ISFILTERED ( solicitudes_inscripcion[sede] ), CONCATENATEX ( VALUES ( solicitudes_inscripcion[sede] ), solicitudes_inscripcion[sede], ", " ), "Todos" )
VAR cExtra2 = IF ( ISFILTERED ( solicitudes_inscripcion[sede] ), "#F3E7C4", "#EAF1FB" )
'@
} else {
@'
VAR vExtra1 = IF ( ISFILTERED ( solicitudes_calificacion[nivel] ), CONCATENATEX ( VALUES ( solicitudes_calificacion[nivel] ), solicitudes_calificacion[nivel], ", " ), "Todos" )
VAR cExtra1 = IF ( ISFILTERED ( solicitudes_calificacion[nivel] ), "#F3E7C4", "#EAF1FB" )
VAR vExtra2 = IF ( ISFILTERED ( solicitudes_calificacion[sede] ), CONCATENATEX ( VALUES ( solicitudes_calificacion[sede] ), solicitudes_calificacion[sede], ", " ), "Todos" )
VAR cExtra2 = IF ( ISFILTERED ( solicitudes_calificacion[sede] ), "#F3E7C4", "#EAF1FB" )
'@
}
$extraChips = if($Mode -eq 'Resumen') {
'<span class=''chip'' style=''background:" & cExtra1 & "''>Tipo: <b>" & vExtra1 & "</b></span>'
} else {
'<span class=''chip'' style=''background:" & cExtra1 & "''>Nivel: <b>" & vExtra1 & "</b></span><span class=''chip'' style=''background:" & cExtra2 & "''>Sede: <b>" & vExtra2 & "</b></span>'
}
return @"
VAR vPeriodo = IF ( ISFILTERED ( dim_periodo[periodo] ), CONCATENATEX ( VALUES ( dim_periodo[periodo] ), dim_periodo[periodo], ", " ), "Todos" )
VAR vEstado = IF ( ISFILTERED ( dim_estado[estado_operacional] ), CONCATENATEX ( VALUES ( dim_estado[estado_operacional] ), dim_estado[estado_operacional], ", " ), "Todos" )
VAR cPeriodo = IF ( ISFILTERED ( dim_periodo[periodo] ), "#F3E7C4", "#EAF1FB" )
VAR cEstado = IF ( ISFILTERED ( dim_estado[estado_operacional] ), "#F3E7C4", "#EAF1FB" )
$extraVars
RETURN
"<style>html,body{margin:0;padding:0;background:transparent;font-family:Arial,Segoe UI,sans-serif;overflow:hidden}.hdr{height:122px;box-sizing:border-box;background:#fff;border:1px solid #E1E6ED;border-radius:10px;box-shadow:0 4px 12px rgba(17,43,66,.08);position:relative;color:#112B42;overflow:hidden}.divider{position:absolute;left:230px;top:20px;width:2px;height:58px;background:#C6B27F}.title{position:absolute;left:255px;top:16px;font-size:23px;font-weight:700;display:flex;align-items:center;gap:7px}.subtitle{position:absolute;left:255px;top:49px;font-size:12px;color:#58616E}.area{position:absolute;left:255px;top:69px;font-size:10px;font-weight:600;color:#8A7440}.chips{position:absolute;left:18px;bottom:12px;display:flex;gap:7px;align-items:center;font-size:10px;color:#475569;max-width:1070px;white-space:nowrap;overflow:hidden}.chip{padding:3px 8px;border-radius:999px;color:#112B42}.info{position:static;display:block;font-size:11px}.info>summary{display:flex;align-items:center;justify-content:center;width:20px;height:20px;border-radius:50%;background:#C6B27F;color:#fff;font-size:11px;line-height:20px;list-style:none;cursor:pointer}.info>summary::-webkit-details-marker{display:none}.info>summary::marker{content:''}.info[open]>summary{position:fixed;left:931px;top:10px;z-index:10001;background:#F4F0E3;color:#112B42;font-size:0}.info[open]>summary::after{content:'×';font-size:14px;font-weight:700}.tip{display:none;position:fixed;left:270px;top:5px;width:690px;height:112px;z-index:9999;background:#fff;border:1px solid #D9DEE7;border-left:4px solid #C6B27F;border-radius:8px;box-shadow:0 6px 18px rgba(17,43,66,.16);padding:10px 15px 18px;box-sizing:border-box}.info[open]>.tip{display:block}.tipgrid{display:grid;grid-template-columns:1fr 1fr 1fr;height:76px}.tipgrid>div{padding:2px 15px;border-right:1px solid #E1E6ED}.tipgrid>div:first-child{padding-left:8px}.tipgrid>div:last-child{border-right:0}.tip b{display:block;color:#8A7440;font-size:9px;margin-bottom:5px}.tip span{display:block;color:#334155;font-size:8px;line-height:11px}.source{position:absolute;left:23px;right:23px;bottom:5px;padding-top:4px;border-top:1px solid #E1E6ED;color:#64748B;font-size:7px}</style>" &
"<div class='hdr'><div class='divider'></div><div class='title'><span>$Title</span><details class='info'><summary title='Haz clic para ver la metodología'>i</summary><div class='tip'><div class='tipgrid'><div><b>Objetivo</b><span>Consolidar y monitorear las solicitudes académicas registradas en los workflows institucionales.</span></div><div><b>Descriptor</b><span>Cantidad de solicitudes según período, tipo, estado operacional, nivel académico y sede.</span></div><div><b>Fórmula de cálculo</b><span>Finalizada: posee fecha de término o running es falso. En curso: resto de solicitudes. La tasa divide finalizadas por solicitudes totales.</span></div></div><div class='source'>Fuente: Banner Workflow en Data Lake USS. Actualización según programación del modelo.</div></div></details></div><div class='subtitle'>$Subtitle</div><div class='area'>Dirección General de Control de Gestión y Análisis Institucional</div>" &
"<div class='chips'><span>Filtros aplicados:</span><span class='chip' style='background:" & cPeriodo & "'>Periodo: <b>" & vPeriodo & "</b></span><span class='chip' style='background:" & cEstado & "'>Estado: <b>" & vEstado & "</b></span>$extraChips</div></div>"
"@
}

$headerResumen = New-HeaderDax 'Solicitudes académicas' 'Resumen operacional consolidado de workflows académicos.' 'Resumen'
$headerIns = New-HeaderDax 'Inscripción extraordinaria' 'Seguimiento histórico de solicitudes extraordinarias de inscripción de asignaturas.' 'Inscripcion'
$headerCal = New-HeaderDax 'Cambio de calificación' 'Seguimiento histórico de solicitudes de modificación de calificaciones.' 'Calificacion'

$kpiResumen = @"
VAR total = [Solicitudes Total]
VAR fin = [Solicitudes Finalizadas]
VAR curso = [Solicitudes En Curso]
VAR tasa = [% Solicitudes Finalizadas]
VAR ins = [Solicitudes Inscripción]
VAR cal = [Solicitudes Calificación]
RETURN
"<style>html,body{margin:0!important;padding:0!important;width:100%;height:100%;overflow:hidden!important;background:transparent;font-family:Arial,Segoe UI,sans-serif}.wrap{height:100%;display:grid;grid-template-columns:repeat(3,1fr);grid-template-rows:repeat(2,1fr);gap:12px}.card{box-sizing:border-box;height:100%;display:flex;flex-direction:column;background:#fff;border:1px solid #D9DEE7;border-left:4px solid #C6B27F;border-radius:9px;padding:11px 16px 10px 18px;box-shadow:0 3px 10px rgba(17,43,66,.06)}.head{flex:0 0 37px;min-height:37px}.title{font-size:12px;font-weight:700;line-height:15px;color:#112B42}.desc{margin-top:2px;font-size:9px;line-height:11px;color:#58616E;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.value{flex:1;display:flex;align-items:center;font-size:27px;font-weight:700;line-height:1;color:#112B42}</style>" &
"<div class='wrap'><div class='card'><div class='head'><div class='title'>Solicitudes totales</div><div class='desc'>Total de workflows registrados.</div></div><div class='value'>" & FORMAT(total,"#,##0") & "</div></div><div class='card'><div class='head'><div class='title'>Finalizadas</div><div class='desc'>Procesos con término registrado.</div></div><div class='value'>" & FORMAT(fin,"#,##0") & "</div></div><div class='card'><div class='head'><div class='title'>En curso</div><div class='desc'>Procesos actualmente activos.</div></div><div class='value'>" & FORMAT(curso,"#,##0") & "</div></div><div class='card'><div class='head'><div class='title'>Tasa de finalización</div><div class='desc'>Finalizadas respecto del total.</div></div><div class='value'>" & FORMAT(tasa,"0.0%") & "</div></div><div class='card'><div class='head'><div class='title'>Inscripción extraordinaria</div><div class='desc'>Solicitudes extraordinarias de asignaturas.</div></div><div class='value'>" & FORMAT(ins,"#,##0") & "</div></div><div class='card'><div class='head'><div class='title'>Cambio de calificación</div><div class='desc'>Solicitudes de modificación de nota.</div></div><div class='value'>" & FORMAT(cal,"#,##0") & "</div></div></div>"
"@

function New-DetailKpiDax([string]$TotalMeasure,[string]$FinalMeasure,[string]$CourseMeasure,[string]$RateMeasure) {
return @"
VAR total = [$TotalMeasure]
VAR fin = [$FinalMeasure]
VAR curso = [$CourseMeasure]
VAR tasa = [$RateMeasure]
RETURN
"<style>html,body{margin:0!important;padding:0!important;width:100%;height:100%;overflow:hidden!important;background:transparent;font-family:Arial,Segoe UI,sans-serif}.wrap{height:100%;display:grid;grid-template-columns:repeat(4,1fr);gap:14px}.card{box-sizing:border-box;height:100%;display:flex;flex-direction:column;background:#fff;border:1px solid #D9DEE7;border-left:4px solid #C6B27F;border-radius:9px;padding:14px 18px 12px 20px;box-shadow:0 3px 10px rgba(17,43,66,.06)}.head{flex:0 0 55px;min-height:55px}.title{font-size:14px;font-weight:700;line-height:17px;color:#112B42}.desc{margin-top:4px;font-size:11px;line-height:14px;color:#58616E}.value{flex:1;display:flex;align-items:center;justify-content:center;font-size:32px;font-weight:700;line-height:1;color:#112B42}</style>" &
"<div class='wrap'><div class='card'><div class='head'><div class='title'>Solicitudes</div><div class='desc'>Total registrado según filtros.</div></div><div class='value'>" & FORMAT(total,"#,##0") & "</div></div><div class='card'><div class='head'><div class='title'>Finalizadas</div><div class='desc'>Procesos con término registrado.</div></div><div class='value'>" & FORMAT(fin,"#,##0") & "</div></div><div class='card'><div class='head'><div class='title'>En curso</div><div class='desc'>Procesos actualmente activos.</div></div><div class='value'>" & FORMAT(curso,"#,##0") & "</div></div><div class='card'><div class='head'><div class='title'>Tasa de finalización</div><div class='desc'>Finalizadas respecto del total.</div></div><div class='value'>" & FORMAT(tasa,"0.0%") & "</div></div></div>"
"@
}
$kpiIns = New-DetailKpiDax 'Inscripción Total' 'Inscripción Finalizadas' 'Inscripción En Curso' '% Inscripción Finalizadas'
$kpiCal = New-DetailKpiDax 'Calificación Total' 'Calificación Finalizadas' 'Calificación En Curso' '% Calificación Finalizadas'

function Add-MeasureBlock([System.Collections.Generic.List[string]]$Lines,[string]$Name,[string]$Expression,[string]$Format='') {
    $Lines.Add("`tmeasure '$Name' = " + '```')
    foreach($line in ($Expression -split "`r?`n")){ $Lines.Add("`t`t$line") }
    $Lines.Add("`t" + '```')
    if($Format){ $Lines.Add("`t`tformatString: $Format") }
    $Lines.Add("`t`tlineageTag: $(New-LineageTag)")
    $Lines.Add('')
}

$measureLines = [System.Collections.Generic.List[string]]::new()
$measureLines.Add("table 'Medidas Solicitudes'")
$measureLines.Add("`tlineageTag: $(New-LineageTag)")
$measureLines.Add('')
Add-MeasureBlock $measureLines 'Solicitudes Total' 'COUNTROWS ( solicitudes_consolidadas )' '#,0'
Add-MeasureBlock $measureLines 'Solicitudes Finalizadas' 'CALCULATE ( [Solicitudes Total], solicitudes_consolidadas[estado_operacional] = "FINALIZADA" )' '#,0'
Add-MeasureBlock $measureLines 'Solicitudes En Curso' 'CALCULATE ( [Solicitudes Total], solicitudes_consolidadas[estado_operacional] = "EN CURSO" )' '#,0'
Add-MeasureBlock $measureLines '% Solicitudes Finalizadas' 'DIVIDE ( [Solicitudes Finalizadas], [Solicitudes Total] )' '0.0%'
Add-MeasureBlock $measureLines 'Solicitudes Inscripción' 'CALCULATE ( [Solicitudes Total], solicitudes_consolidadas[tipo_solicitud] = "Inscripción extraordinaria" )' '#,0'
Add-MeasureBlock $measureLines 'Solicitudes Calificación' 'CALCULATE ( [Solicitudes Total], solicitudes_consolidadas[tipo_solicitud] = "Cambio de calificación" )' '#,0'
Add-MeasureBlock $measureLines 'Inscripción Total' 'COUNTROWS ( solicitudes_inscripcion )' '#,0'
Add-MeasureBlock $measureLines 'Inscripción Finalizadas' 'CALCULATE ( [Inscripción Total], solicitudes_inscripcion[estado_operacional] = "FINALIZADA" )' '#,0'
Add-MeasureBlock $measureLines 'Inscripción En Curso' 'CALCULATE ( [Inscripción Total], solicitudes_inscripcion[estado_operacional] = "EN CURSO" )' '#,0'
Add-MeasureBlock $measureLines '% Inscripción Finalizadas' 'DIVIDE ( [Inscripción Finalizadas], [Inscripción Total] )' '0.0%'
Add-MeasureBlock $measureLines 'Calificación Total' 'COUNTROWS ( solicitudes_calificacion )' '#,0'
Add-MeasureBlock $measureLines 'Calificación Finalizadas' 'CALCULATE ( [Calificación Total], solicitudes_calificacion[estado_operacional] = "FINALIZADA" )' '#,0'
Add-MeasureBlock $measureLines 'Calificación En Curso' 'CALCULATE ( [Calificación Total], solicitudes_calificacion[estado_operacional] = "EN CURSO" )' '#,0'
Add-MeasureBlock $measureLines '% Calificación Finalizadas' 'DIVIDE ( [Calificación Finalizadas], [Calificación Total] )' '0.0%'
Add-MeasureBlock $measureLines 'Encabezado Resumen' $headerResumen
Add-MeasureBlock $measureLines 'Encabezado Inscripción' $headerIns
Add-MeasureBlock $measureLines 'Encabezado Calificación' $headerCal
Add-MeasureBlock $measureLines 'HTML KPI Resumen' $kpiResumen
Add-MeasureBlock $measureLines 'HTML KPI Inscripción' $kpiIns
Add-MeasureBlock $measureLines 'HTML KPI Calificación' $kpiCal
$measureLines.Add("`tcolumn Marcador")
$measureLines.Add("`t`tdataType: string")
$measureLines.Add("`t`tlineageTag: $(New-LineageTag)")
$measureLines.Add("`t`tsummarizeBy: none")
$measureLines.Add("`t`tsourceColumn: Marcador")
$measureLines.Add('')
$measureLines.Add("`tpartition 'Medidas Solicitudes' = calculated")
$measureLines.Add("`t`tmode: import")
$measureLines.Add("`t`tsource = DATATABLE ( `"Marcador`", STRING, { { `"Medidas`" } } )")
Write-Utf8 (Join-Path $tablesDir 'Medidas Solicitudes.tmdl') ($measureLines -join "`r`n")

$relationships = @"
relationship dim_periodo_inscripcion
	fromColumn: solicitudes_inscripcion.periodo
	toColumn: dim_periodo.periodo

relationship dim_periodo_calificacion
	fromColumn: solicitudes_calificacion.periodo
	toColumn: dim_periodo.periodo

relationship dim_periodo_consolidado
	fromColumn: solicitudes_consolidadas.periodo
	toColumn: dim_periodo.periodo

relationship dim_estado_inscripcion
	fromColumn: solicitudes_inscripcion.estado_operacional
	toColumn: dim_estado.estado_operacional

relationship dim_estado_calificacion
	fromColumn: solicitudes_calificacion.estado_operacional
	toColumn: dim_estado.estado_operacional

relationship dim_estado_consolidado
	fromColumn: solicitudes_consolidadas.estado_operacional
	toColumn: dim_estado.estado_operacional

relationship dim_tipo_consolidado
	fromColumn: solicitudes_consolidadas.tipo_solicitud
	toColumn: dim_tipo_solicitud.tipo_solicitud
"@
Write-Utf8 (Join-Path $definition 'relationships.tmdl') $relationships

$modelTmdl = @"
model Model
	culture: es-ES
	defaultPowerBIDataSourceVersion: powerBI_V3
	sourceQueryCulture: es-CL
	dataAccessOptions
		legacyRedirects
		returnErrorValuesAsNull

queryGroup Datos

	annotation PBI_QueryGroupOrder = 0

queryGroup Queries

	annotation PBI_QueryGroupOrder = 1

queryGroup Medidas

	annotation PBI_QueryGroupOrder = 2

annotation __PBI_TimeIntelligenceEnabled = 0

annotation PBI_QueryOrder = ["query_solicitudes_inscripcion","solicitudes_inscripcion","query_solicitudes_calificacion","solicitudes_calificacion","solicitudes_consolidadas","dim_periodo","dim_estado","dim_tipo_solicitud","Medidas Solicitudes"]

annotation PBI_ProTooling = ["TMDLView_Desktop","DevMode"]

ref table solicitudes_inscripcion
ref table solicitudes_calificacion
ref table solicitudes_consolidadas
ref table dim_periodo
ref table dim_estado
ref table dim_tipo_solicitud
ref table 'Medidas Solicitudes'

ref cultureInfo es-ES
"@
Write-Utf8 (Join-Path $definition 'model.tmdl') $modelTmdl
Write-Utf8 (Join-Path $definition 'database.tmdl') "database`r`n`tcompatibilityLevel: 1606`r`n"
$pbism = [ordered]@{
    '$schema'='https://developer.microsoft.com/json-schemas/fabric/item/semanticModel/definitionProperties/1.0.0/schema.json'
    version='4.2'
    settings=@{}
}
Write-Json (Join-Path $model 'definition.pbism') $pbism

$pbip = [ordered]@{
    '$schema'='https://developer.microsoft.com/json-schemas/fabric/pbip/pbipProperties/1.0.0/schema.json'
    version='1.0'
    artifacts=@(@{report=@{path="$ProjectName.Report"}})
    settings=@{enableAutoRecovery=$true}
}
Write-Json (Join-Path $solution "$ProjectName.pbip") $pbip
$pbir = [ordered]@{
    '$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definitionProperties/2.0.0/schema.json'
    version='4.0'
    datasetReference=@{byPath=@{path="../$ProjectName.SemanticModel"}}
}
Write-Json (Join-Path $report 'definition.pbir') $pbir
Copy-Item -LiteralPath (Join-Path $templateReport 'definition\report.json') -Destination (Join-Path $report 'definition\report.json') -Force
Copy-Item -LiteralPath (Join-Path $templateReport 'definition\version.json') -Destination (Join-Path $report 'definition\version.json') -Force
Copy-Item -LiteralPath (Join-Path $templateReport 'StaticResources') -Destination $report -Recurse -Force

function New-Page([string]$Name,[string]$DisplayName) {
    return [ordered]@{
        '$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json'
        name=$Name
        displayName=$DisplayName
        displayOption='FitToPage'
        height=900
        width=1280
        objects=@{background=@(@{properties=@{color=@{solid=@{color=@{expr=@{Literal=@{Value="'#F7F9FC'"}}}}}}})}
        visualInteractions=@()
    }
}

function New-HtmlVisual([string]$Name,[string]$Measure,[double]$X,[double]$Y,[double]$W,[double]$H,[int]$Tab=0) {
    return [ordered]@{
        '$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.11.0/schema.json'
        name=$Name
        position=@{x=$X;y=$Y;z=1000;height=$H;width=$W;tabOrder=$Tab}
        visual=@{
            visualType='htmlContent443BE3AD55E043BF878BED274D3A6855'
            query=@{queryState=@{content=@{projections=@(@{field=@{Measure=@{Expression=@{SourceRef=@{Entity='Medidas Solicitudes'}};Property=$Measure}};queryRef="Medidas Solicitudes.$Measure";nativeQueryRef=$Measure})}}}
            visualContainerObjects=@{background=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}}});title=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}}});visualHeader=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}}})}
            drillFilterOtherVisuals=$true
        }
    }
}

function New-Slicer([string]$Name,[string]$Entity,[string]$Property,[string]$Title,[double]$X,[double]$Y,[double]$W,[double]$H,[string]$Parent='') {
    $obj = [ordered]@{
        '$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.11.0/schema.json'
        name=$Name
        position=@{x=$X;y=$Y;z=7000;height=$H;width=$W;tabOrder=7000}
        visual=@{
            visualType='slicer'
            query=@{queryState=@{Values=@{projections=@(@{field=@{Column=@{Expression=@{SourceRef=@{Entity=$Entity}};Property=$Property}};queryRef="$Entity.$Property";nativeQueryRef=$Property;active=$true})}};sortDefinition=@{sort=@(@{field=@{Column=@{Expression=@{SourceRef=@{Entity=$Entity}};Property=$Property}};direction='Descending'})}}
            objects=@{data=@(@{properties=@{mode=@{expr=@{Literal=@{Value="'Dropdown'"}}}}});selection=@(@{properties=@{singleSelect=@{expr=@{Literal=@{Value='false'}}};selectAllCheckboxEnabled=@{expr=@{Literal=@{Value='true'}}}}});header=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}}})}
            visualContainerObjects=@{title=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}};text=@{expr=@{Literal=@{Value="'$Title'"}}};fontColor=@{solid=@{color=@{expr=@{Literal=@{Value="'#112B42'"}}}}};fontSize=@{expr=@{Literal=@{Value='12D'}}};bold=@{expr=@{Literal=@{Value='true'}}};fontFamily=@{expr=@{Literal=@{Value="'Arial'"}}}}});visualHeader=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}}});background=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}};color=@{solid=@{color=@{expr=@{Literal=@{Value="'#FFFFFF'"}}}}}}})}
            drillFilterOtherVisuals=$true
        }
    }
    if($Parent){$obj.parentGroupName=$Parent}
    return $obj
}

function New-TableVisual([string]$Name,[string]$Entity,$Fields,[string]$Title,[double]$X,[double]$Y,[double]$W,[double]$H) {
    $projections=@()
    foreach($f in $Fields){
        if($f.kind -eq 'Measure'){
            $projections += @{field=@{Measure=@{Expression=@{SourceRef=@{Entity='Medidas Solicitudes'}};Property=$f.property}};queryRef="Medidas Solicitudes.$($f.property)";nativeQueryRef=$f.property}
        } else {
            $projections += @{field=@{Column=@{Expression=@{SourceRef=@{Entity=$Entity}};Property=$f.property}};queryRef="$Entity.$($f.property)";nativeQueryRef=$f.property}
        }
    }
    return [ordered]@{
        '$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.11.0/schema.json'
        name=$Name
        position=@{x=$X;y=$Y;z=2000;height=$H;width=$W;tabOrder=2000}
        visual=@{
            visualType='tableEx'
            query=@{queryState=@{Values=@{projections=$projections}}}
            objects=@{
                columnHeaders=@(@{properties=@{fontColor=@{solid=@{color=@{expr=@{Literal=@{Value="'#112B42'"}}}}};backColor=@{solid=@{color=@{expr=@{Literal=@{Value="'#EAF1FB'"}}}}};fontSize=@{expr=@{Literal=@{Value='9D'}}};bold=@{expr=@{Literal=@{Value='true'}}}}})
                values=@(@{properties=@{fontColorPrimary=@{solid=@{color=@{expr=@{Literal=@{Value="'#334155'"}}}}};fontSize=@{expr=@{Literal=@{Value='9D'}}}}})
            }
            visualContainerObjects=@{
                background=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}};color=@{solid=@{color=@{expr=@{Literal=@{Value="'#FFFFFF'"}}}}};transparency=@{expr=@{Literal=@{Value='0D'}}}}})
                border=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}};color=@{solid=@{color=@{expr=@{Literal=@{Value="'#D9DEE7'"}}}}};radius=@{expr=@{Literal=@{Value='8D'}}}}})
                title=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}};text=@{expr=@{Literal=@{Value="'$Title'"}}};fontSize=@{expr=@{Literal=@{Value='11D'}}};bold=@{expr=@{Literal=@{Value='true'}}};fontColor=@{solid=@{color=@{expr=@{Literal=@{Value="'#112B42'"}}}}}}})
            }
            drillFilterOtherVisuals=$true
        }
    }
}

function New-Shape([string]$Name,[string]$Color,[int]$Transparency,[double]$X,[double]$Y,[double]$W,[double]$H,[string]$Parent='') {
    $obj=[ordered]@{
        '$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.11.0/schema.json'
        name=$Name
        position=@{x=$X;y=$Y;z=6000;height=$H;width=$W;tabOrder=6000}
        visual=@{visualType='shape';objects=@{shape=@(@{properties=@{tileShape=@{expr=@{Literal=@{Value="'rectangle'"}}}};selector=@{id='default'}});fill=@(@{properties=@{fillColor=@{solid=@{color=@{expr=@{Literal=@{Value="'$Color'"}}}}};transparency=@{expr=@{Literal=@{Value="${Transparency}D"}}}};selector=@{id='default'}});outline=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}};selector=@{id='default'}})};drillFilterOtherVisuals=$true}
    }
    if($Parent){$obj.parentGroupName=$Parent}
    return $obj
}

function New-PageButton([string]$Name,[string]$Text,[string]$TargetPage,[double]$X,[double]$Y,[double]$W,[double]$H,[bool]$Active=$false,[string]$Parent='') {
    $fill = if($Active){'#112B42'}else{'#FFFFFF'}
    $font = if($Active){'#FFFFFF'}else{'#112B42'}
    $obj=[ordered]@{
        '$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.11.0/schema.json'
        name=$Name
        position=@{x=$X;y=$Y;z=9000;height=$H;width=$W;tabOrder=9000}
        visual=@{
            visualType='actionButton'
            objects=@{
                icon=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}}})
                text=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}}}},@{properties=@{text=@{expr=@{Literal=@{Value="'$Text'"}}};fontColor=@{solid=@{color=@{expr=@{Literal=@{Value="'$font'"}}}}};fontSize=@{expr=@{Literal=@{Value='11D'}}};bold=@{expr=@{Literal=@{Value='true'}}};fontFamily=@{expr=@{Literal=@{Value="'Arial'"}}};horizontalAlignment=@{expr=@{Literal=@{Value="'center'"}}}};selector=@{id='default'}})
                fill=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}}}},@{properties=@{fillColor=@{solid=@{color=@{expr=@{Literal=@{Value="'$fill'"}}}}}};selector=@{id='default'}})
                outline=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}};selector=@{id='default'}})
                shape=@(@{properties=@{tileShape=@{expr=@{Literal=@{Value="'rectangle'"}}};rectangleRoundedCurve=@{expr=@{Literal=@{Value='14L'}}}};selector=@{id='default'}})
            }
            visualContainerObjects=@{visualLink=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}};type=@{expr=@{Literal=@{Value="'PageNavigation'"}}};navigationSection=@{expr=@{Literal=@{Value="'$TargetPage'"}}}}});border=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}}})}
            drillFilterOtherVisuals=$true
        }
        howCreated='InsertVisualButton'
    }
    if($Parent){$obj.parentGroupName=$Parent}
    return $obj
}

function New-BarChart([string]$Name,[string]$Entity,[string]$Category,[string]$Measure,[string]$Title,[double]$X,[double]$Y,[double]$W,[double]$H) {
    return [ordered]@{
        '$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.11.0/schema.json'
        name=$Name
        position=@{x=$X;y=$Y;z=2000;height=$H;width=$W;tabOrder=2000}
        visual=@{
            visualType='clusteredBarChart'
            query=@{
                queryState=@{
                    Category=@{projections=@(@{field=@{Column=@{Expression=@{SourceRef=@{Entity=$Entity}};Property=$Category}};queryRef="$Entity.$Category";nativeQueryRef=$Category})}
                    Y=@{projections=@(@{field=@{Measure=@{Expression=@{SourceRef=@{Entity='Medidas Solicitudes'}};Property=$Measure}};queryRef="Medidas Solicitudes.$Measure";nativeQueryRef=$Measure})}
                }
                sortDefinition=@{sort=@(@{field=@{Measure=@{Expression=@{SourceRef=@{Entity='Medidas Solicitudes'}};Property=$Measure}};direction='Descending'})}
            }
            objects=@{
                dataPoint=@(
                    @{properties=@{fillTransparency=@{expr=@{Literal=@{Value='0D'}}};borderShow=@{expr=@{Literal=@{Value='false'}}}}},
                    @{properties=@{fill=@{solid=@{color=@{expr=@{Literal=@{Value="'#CFB47C'"}}}}}};selector=@{metadata="Medidas Solicitudes.$Measure"}}
                )
                labels=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}};color=@{solid=@{color=@{expr=@{Literal=@{Value="'#334155'"}}}}};fontSize=@{expr=@{Literal=@{Value='9D'}}}}})
                categoryAxis=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}};fontSize=@{expr=@{Literal=@{Value='9D'}}};fontColor=@{solid=@{color=@{expr=@{Literal=@{Value="'#58616E'"}}}}}}})
                valueAxis=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}}})
            }
            visualContainerObjects=@{
                background=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}};color=@{solid=@{color=@{expr=@{Literal=@{Value="'#FFFFFF'"}}}}};transparency=@{expr=@{Literal=@{Value='0D'}}}}})
                border=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}};color=@{solid=@{color=@{expr=@{Literal=@{Value="'#D9DEE7'"}}}}};radius=@{expr=@{Literal=@{Value='8D'}}}}})
                title=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}};text=@{expr=@{Literal=@{Value="'$Title'"}}};fontSize=@{expr=@{Literal=@{Value='11D'}}};bold=@{expr=@{Literal=@{Value='true'}}};fontColor=@{solid=@{color=@{expr=@{Literal=@{Value="'#112B42'"}}}}}}})
            }
            drillFilterOtherVisuals=$true
        }
    }
}

function New-Textbox([string]$Name,[string]$Text,[double]$X,[double]$Y,[double]$W,[double]$H,[string]$Parent='') {
    $obj=[ordered]@{
        '$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.11.0/schema.json'
        name=$Name
        position=@{x=$X;y=$Y;z=8000;height=$H;width=$W;tabOrder=8000}
        visual=@{visualType='textbox';objects=@{general=@(@{properties=@{paragraphs=@(@{textRuns=@(@{value=$Text;textStyle=@{fontWeight='bold';fontSize='17pt';color='#112B42';fontFamily='Arial'}})})}})};drillFilterOtherVisuals=$true}
    }
    if($Parent){$obj.parentGroupName=$Parent}
    return $obj
}

function New-Button([string]$Name,[string]$Text,[string]$Bookmark,[double]$X,[double]$Y,[double]$W,[double]$H,[string]$Parent='') {
    $obj=[ordered]@{
        '$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.11.0/schema.json'
        name=$Name
        position=@{x=$X;y=$Y;z=9000;height=$H;width=$W;tabOrder=9000}
        visual=@{
            visualType='actionButton'
            objects=@{icon=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}}});text=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}}}},@{properties=@{text=@{expr=@{Literal=@{Value="'$Text'"}}};fontColor=@{solid=@{color=@{expr=@{Literal=@{Value="'#112B42'"}}}}};fontSize=@{expr=@{Literal=@{Value='11D'}}};bold=@{expr=@{Literal=@{Value='true'}}};fontFamily=@{expr=@{Literal=@{Value="'Arial'"}}};horizontalAlignment=@{expr=@{Literal=@{Value="'center'"}}}};selector=@{id='default'}});fill=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}}}},@{properties=@{fillColor=@{solid=@{color=@{expr=@{Literal=@{Value="'#FFFFFF'"}}}}}};selector=@{id='default'}});outline=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}}})}
            visualContainerObjects=@{visualLink=@(@{properties=@{show=@{expr=@{Literal=@{Value='true'}}};type=@{expr=@{Literal=@{Value="'Bookmark'"}}};bookmark=@{expr=@{Literal=@{Value="'$Bookmark'"}}}}});border=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}}})}
            drillFilterOtherVisuals=$true
        }
        howCreated='InsertVisualButton'
    }
    if($Parent){$obj.parentGroupName=$Parent}
    return $obj
}

function New-Image([string]$Name) {
    $source = Join-Path $templateReport 'definition\pages\e274000c5980b0a02062\visuals\62b84ec44485b90381d0\visual.json'
    $obj = Get-Content -LiteralPath $source -Raw | ConvertFrom-Json
    $obj.name=$Name
    $obj.position.x=42
    $obj.position.y=22
    $obj.position.width=180
    $obj.position.height=65
    return $obj
}

function New-FilterGroup([string]$Page,[string]$Prefix,$Slicers) {
    $group="${Prefix}_filter_group"
    $on="${Prefix}_filter_on"
    $off="${Prefix}_filter_off"
    $visuals=@()
    $visuals += [ordered]@{'$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.11.0/schema.json';name=$group;position=@{x=0;y=0;z=18000;height=900;width=1280;tabOrder=11000};visualGroup=@{displayName='Filtros';groupMode='ScaleMode';objects=@{background=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}}})}};isHidden=$true}
    $overlay = New-StrategicVisual '1d05d0b57df216b1f870' "${Prefix}_overlay" $group
    $overlay.position.height=900
    Set-BookmarkTarget $overlay $off
    $visuals += $overlay
    $panel=New-StrategicVisual '305f1d4fa40216afd53c' "${Prefix}_panel" $group
    $panel.position.height=900
    $visuals += $panel
    $visuals += New-StrategicVisual 'fa4c5a12ba2af683aec2' "${Prefix}_title" $group
    $close=New-StrategicVisual 'b37269006cc31111aa50' "${Prefix}_close" $group
    Set-BookmarkTarget $close $off
    $visuals += $close
    $visuals += New-StrategicVisual '3d756450d5031c2f16a8' "${Prefix}_clear" $group
    $openButton = New-StrategicVisual '0316d1a4c703b07c151a' "${Prefix}_open"
    Set-BookmarkTarget $openButton $on
    $visuals += $openButton
    $y=90
    foreach($s in $Slicers){
        $visuals += New-Slicer "${Prefix}_$($s.property)" $s.entity $s.property $s.title 944 $y 312 72 $group
        $y += 92
    }
    $bmOn=[ordered]@{'$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.1.0/schema.json';displayName="$Prefix - Filtros abiertos";name=$on;options=@{applyOnlyToTargetVisuals=$true;targetVisualNames=@($group);suppressData=$true};explorationState=@{version='1.3';activeSection=$Page;sections=@{$Page=@{visualContainers=@{};visualContainerGroups=@{$group=@{isHidden=$false}}}};objects=@{}}}
    $bmOff=[ordered]@{'$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.1.0/schema.json';displayName="$Prefix - Filtros cerrados";name=$off;options=@{applyOnlyToTargetVisuals=$true;targetVisualNames=@($group);suppressData=$true};explorationState=@{version='1.3';activeSection=$Page;sections=@{$Page=@{visualContainers=@{};visualContainerGroups=@{$group=@{isHidden=$true}}}};objects=@{}}}
    return @{visuals=$visuals;bookmarks=@($bmOn,$bmOff)}
}

function New-MenuGroup([string]$Page,[string]$Prefix) {
    $group="${Prefix}_menu_group"
    $on="${Prefix}_menu_on"
    $off="${Prefix}_menu_off"
    $visuals=@()
    $visuals += [ordered]@{'$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.11.0/schema.json';name=$group;position=@{x=0;y=0;z=19000;height=900;width=1280;tabOrder=12000};visualGroup=@{displayName='Navegación';groupMode='ScaleMode';objects=@{background=@(@{properties=@{show=@{expr=@{Literal=@{Value='false'}}}}})}};isHidden=$true}
    $overlay=New-StrategicVisual 'fi_mat_nav_overlay' "${Prefix}_menu_overlay" $group
    $overlay.position.height=900
    Set-BookmarkTarget $overlay $off
    $visuals += $overlay
    $panel=New-StrategicVisual 'fi_mat_nav_panel' "${Prefix}_menu_panel" $group
    $panel.position.height=900
    $visuals += $panel
    $logo=New-Image "${Prefix}_menu_logo"
    $logo.position.x=32; $logo.position.y=28; $logo.position.width=190; $logo.position.height=55; $logo.position.z=3000
    $logo | Add-Member -NotePropertyName parentGroupName -NotePropertyValue $group -Force
    $visuals += $logo
    $closeButton=New-StrategicVisual 'fi_mat_nav_close' "${Prefix}_menu_close" $group
    Set-BookmarkTarget $closeButton $off
    $visuals += $closeButton
    $navigator=New-StrategicVisual 'fi_mat_nav_pages' "${Prefix}_menu_pages" $group
    $navigator.position.height=500
    $visuals += $navigator
    $openButton=New-StrategicVisual 'fi_mat_menubtn' "${Prefix}_menu_open"
    Set-BookmarkTarget $openButton $on
    $visuals += $openButton
    $bmOn=[ordered]@{'$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.1.0/schema.json';displayName="$Prefix - Menú abierto";name=$on;options=@{applyOnlyToTargetVisuals=$true;targetVisualNames=@($group);suppressData=$true};explorationState=@{version='1.3';activeSection=$Page;sections=@{$Page=@{visualContainers=@{};visualContainerGroups=@{$group=@{isHidden=$false}}}};objects=@{}}}
    $bmOff=[ordered]@{'$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.1.0/schema.json';displayName="$Prefix - Menú cerrado";name=$off;options=@{applyOnlyToTargetVisuals=$true;targetVisualNames=@($group);suppressData=$true};explorationState=@{version='1.3';activeSection=$Page;sections=@{$Page=@{visualContainers=@{};visualContainerGroups=@{$group=@{isHidden=$true}}}};objects=@{}}}
    return @{visuals=$visuals;bookmarks=@($bmOn,$bmOff)}
}

$pages=@(
    @{id='resumen_solicitudes';display='Resumen operacional';header='Encabezado Resumen';kpi='HTML KPI Resumen';prefix='res'},
    @{id='detalle_inscripcion';display='Inscripción extraordinaria';header='Encabezado Inscripción';kpi='HTML KPI Inscripción';prefix='ins'},
    @{id='detalle_calificacion';display='Cambio de calificación';header='Encabezado Calificación';kpi='HTML KPI Calificación';prefix='cal'}
)
$bookmarkItems=@()

foreach($p in $pages){
    $pageDir=Join-Path $pagesDir $p.id
    $visualDir=Join-Path $pageDir 'visuals'
    $resolvedSolution=[System.IO.Path]::GetFullPath($solution).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $resolvedVisualDir=[System.IO.Path]::GetFullPath($visualDir)
    if(-not $resolvedVisualDir.StartsWith($resolvedSolution,[System.StringComparison]::OrdinalIgnoreCase)){
        throw "Directorio visual fuera del proyecto: $resolvedVisualDir"
    }
    if(Test-Path -LiteralPath $resolvedVisualDir){
        Remove-Item -LiteralPath $resolvedVisualDir -Recurse -Force
    }
    [System.IO.Directory]::CreateDirectory($visualDir) | Out-Null
    Write-Json (Join-Path $pageDir 'page.json') (New-Page $p.id $p.display)
    $visuals=@()
    $visuals += New-HtmlVisual "$($p.prefix)_header" $p.header 24 12 1232 125 0
    $visuals += New-Image "$($p.prefix)_logo"
    if($p.id -eq 'resumen_solicitudes'){
        $visuals += New-HtmlVisual 'res_kpi' $p.kpi 24 155 1232 215 100
        $summaryFields=@(
            @{kind='Column';property='periodo'},@{kind='Column';property='tipo_solicitud'},
            @{kind='Column';property='estado_operacional'},@{kind='Column';property='estado_actual'},
            @{kind='Measure';property='Solicitudes Total'}
        )
        $visuals += New-TableVisual 'res_tabla' 'solicitudes_consolidadas' $summaryFields 'Solicitudes por periodo, tipo y estado técnico' 24 390 600 465
        $visuals += New-BarChart 'res_sede' 'solicitudes_consolidadas' 'sede' 'Solicitudes Total' 'Solicitudes por sede' 644 390 612 465
        $slicers=@(
            @{entity='dim_periodo';property='periodo';title='Periodo'},
            @{entity='dim_estado';property='estado_operacional';title='Estado operacional'},
            @{entity='dim_tipo_solicitud';property='tipo_solicitud';title='Tipo de solicitud'}
        )
    } elseif($p.id -eq 'detalle_inscripcion'){
        $visuals += New-HtmlVisual 'ins_kpi' $p.kpi 24 155 1232 160 100
        $fields=@(); foreach($c in $insColumns){$fields += @{kind='Column';property=$c.n}}
        $fields += @{kind='Column';property='start_datetime'},@{kind='Column';property='stop_datetime'}
        $visuals += New-TableVisual 'ins_tabla' 'solicitudes_inscripcion' $fields 'Sábana histórica - Inscripción extraordinaria' 24 335 1232 520
        $slicers=@(
            @{entity='dim_periodo';property='periodo';title='Periodo'},
            @{entity='dim_estado';property='estado_operacional';title='Estado operacional'},
            @{entity='solicitudes_inscripcion';property='nivel';title='Nivel académico'},
            @{entity='solicitudes_inscripcion';property='sede';title='Sede'}
        )
    } else {
        $visuals += New-HtmlVisual 'cal_kpi' $p.kpi 24 155 1232 160 100
        $fields=@(); foreach($c in $calColumns){$fields += @{kind='Column';property=$c.n}}
        $fields += @{kind='Column';property='start_datetime'},@{kind='Column';property='stop_datetime'}
        $visuals += New-TableVisual 'cal_tabla' 'solicitudes_calificacion' $fields 'Sábana histórica - Cambio de calificación' 24 335 1232 520
        $slicers=@(
            @{entity='dim_periodo';property='periodo';title='Periodo'},
            @{entity='dim_estado';property='estado_operacional';title='Estado operacional'},
            @{entity='solicitudes_calificacion';property='nivel';title='Nivel académico'},
            @{entity='solicitudes_calificacion';property='sede';title='Sede'}
        )
    }
    $filter = New-FilterGroup $p.id $p.prefix $slicers
    $visuals += $filter.visuals
    $bookmarkItems += $filter.bookmarks
    $menu = New-MenuGroup $p.id $p.prefix
    $visuals += $menu.visuals
    $bookmarkItems += $menu.bookmarks
    foreach($v in $visuals){
        $vDir=Join-Path $visualDir $v.name
        [System.IO.Directory]::CreateDirectory($vDir) | Out-Null
        Write-Json (Join-Path $vDir 'visual.json') $v
    }
}

$pagesMetadata=[ordered]@{'$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/pagesMetadata/1.1.0/schema.json';pageOrder=@($pages.id);activePageName='resumen_solicitudes'}
Write-Json (Join-Path $pagesDir 'pages.json') $pagesMetadata

$bookmarkMetaItems=@()
foreach($bm in $bookmarkItems){
    Write-Json (Join-Path $bookmarksDir "$($bm.name).bookmark.json") $bm
    $bookmarkMetaItems += @{name=$bm.name}
}
$bookmarksMetadata=[ordered]@{'$schema'='https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmarksMetadata/1.0.0/schema.json';items=$bookmarkMetaItems}
Write-Json (Join-Path $bookmarksDir 'bookmarks.json') $bookmarksMetadata

$readme=@'
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
'@
Write-Utf8 (Join-Path $solution 'README.md') $readme

Write-Output "Panel generado en: $solution"
Write-Output "Paginas: $($pages.Count)"
Write-Output "Bookmarks: $($bookmarkItems.Count)"
Write-Output "Columnas inscripcion: $($insColumns.Count)"
Write-Output "Columnas calificacion: $($calColumns.Count)"
