-- Reporte WF Solicitud de cambio de calificacion
-- Version Data Lake optimizada para Amazon Athena / Trino.
--
-- La tabla de propiedades se agrega una sola vez. Esto reemplaza las
-- subconsultas correlacionadas que consultaban ENG_PROPERTIES_VALUES por
-- separado para cada columna del resultado.
--
-- La consulta no fija periodo y carga el historico completo del workflow.
-- Para cambiar el tipo de workflow, modificar solamente el pd_id del CTE parametros.
-- 2026-08-21: se homologa la limpieza operacional de comentarios y se
-- reemplazan comas por punto para evitar cortes al exportar como CSV.

WITH parametros AS (
    SELECT CAST(17504561 AS BIGINT) AS pd_id
),

workflow_base AS (
    SELECT
        wf.id,
        wf.pd_id,
        wf.name AS workflow_name,
        wf.current_state,
        wf.start_date,
        wf.stop_date,
        wf.running,
        wf.last_state,
        wf.originating_user_id,
        wf.originating_event_id,
        wf.originating_process_id,
        wf.owner_role_id,
        wf.admin_role_id,
        wf.requires_execution_plan
    FROM uss_datalake_stage.banner_oracle_workflow_eng_workflow AS wf
    CROSS JOIN parametros AS par
    WHERE wf.pd_id = par.pd_id
),

propiedades AS (
    SELECT
        epv.id,
        MAX(CASE WHEN epv.name = 'C_DESC_ESTADO_ESTUDIANTE' THEN epv.value END) AS desc_estado_estudiante,
        MAX(CASE WHEN epv.name = 'C_PERIODO' THEN epv.value END) AS periodo,
        MAX(CASE WHEN epv.name = 'C_NRC' THEN epv.value END) AS nrc,
        MAX(CASE WHEN epv.name = 'C_CURSO' THEN epv.value END) AS curso,
        MAX(CASE WHEN epv.name = 'C_COD_SEDE' THEN epv.value END) AS cod_sede,
        MAX(CASE WHEN epv.name = 'C_SEDE' THEN epv.value END) AS sede,
        MAX(CASE WHEN epv.name = 'C_FECHA_SOLICITUD' THEN epv.value END) AS fecha_solicitud,
        MAX(CASE WHEN epv.name = 'C_CARRERA' THEN epv.value END) AS cod_carrera,
        MAX(CASE WHEN epv.name = 'C_NOMBRE_CARRERA' THEN epv.value END) AS nombre_carrera,
        MAX(CASE WHEN epv.name = 'C_NOMESCUELA' THEN epv.value END) AS nomescuela,
        MAX(CASE WHEN epv.name = 'C_OBSERVACION_SZARSOL' THEN epv.value END) AS observacion_szarsol,
        MAX(CASE WHEN epv.name = 'C_SEQPLAN' THEN epv.value END) AS seqplan,
        MAX(CASE WHEN epv.name = 'C_NIVEL' THEN epv.value END) AS nivel,
        MAX(CASE WHEN epv.name = 'C_CALIFICACION_ACTUAL' THEN REPLACE(epv.value, '.', ',') END) AS calificacion_actual,
        MAX(CASE WHEN epv.name = 'C_CALIFICACION_SOLICITADA' THEN REPLACE(epv.value, '.', ',') END) AS calificacion_solicitada,
        MAX(CASE WHEN epv.name = 'C_RUT_SOLICITANTE' THEN epv.value END) AS rut_solicitante,
        MAX(CASE WHEN epv.name = 'C_NOMBRE_SOLICITANTE' THEN epv.value END) AS nombre_solicitante,
        MAX(CASE WHEN epv.name = 'C_RUT_ESTUDIANTE' THEN epv.value END) AS rut_estudiante,
        MAX(CASE WHEN epv.name = 'C_NOMBRE_ESTUDIANTE' THEN epv.value END) AS nombre_estudiante,
        MAX(CASE WHEN epv.name = 'C_CORREO_ESTUDIANTE' THEN epv.value END) AS correo_estudiante,
        MAX(CASE WHEN epv.name = 'C_FONO_ESTUDIANTE' THEN epv.value END) AS fono_estudiante,
        MAX(CASE WHEN epv.name = 'C_RUT_DOCENTE' THEN epv.value END) AS rut_docente,
        MAX(CASE WHEN epv.name = 'C_NOMBRE_DOCENTE' THEN epv.value END) AS nombre_docente,
        MAX(CASE WHEN epv.name = 'C_CORREO_DOCENTE' THEN epv.value END) AS correo_docente,
        MAX(CASE WHEN epv.name = 'C_GLOSA' THEN epv.value END) AS glosa,
        MAX(CASE WHEN epv.name = 'C_RUT_DECANO' THEN epv.value END) AS rut_decano,
        MAX(CASE WHEN epv.name = 'C_NOMBRE_DECANO' THEN epv.value END) AS nombre_decano,
        MAX(CASE WHEN epv.name = 'C_CORREO_DECANO' THEN epv.value END) AS correo_decano,
        MAX(CASE WHEN epv.name = 'C_RUT_DIRECTOR_ACADEMICO' THEN epv.value END) AS rut_director_academico,
        MAX(CASE WHEN epv.name = 'C_NOMBRE_DIRECTOR_ACADEMICO' THEN epv.value END) AS nombre_director_academico,
        MAX(CASE WHEN epv.name = 'C_CORREO_DIRECTOR_ACADEMICO' THEN epv.value END) AS correo_director_academico,
        MAX(CASE WHEN epv.name = 'C_RUT_DC_O_DD' THEN epv.value END) AS rut_dc_o_dd,
        MAX(CASE WHEN epv.name = 'C_NOMBRE_DC_O_DD' THEN epv.value END) AS nombre_dc_o_dd,
        MAX(CASE WHEN epv.name = 'C_CORREO_DC_O_DD' THEN epv.value END) AS correo_dc_o_dd,
        MAX(CASE WHEN epv.name = 'C_RUT_REGISTRO_ACADEMICO' THEN epv.value END) AS rut_registro_academico,
        MAX(CASE WHEN epv.name = 'C_NOMBRE_REGISTRO_ACADEMICO' THEN epv.value END) AS nombre_registro_academico,
        MAX(CASE WHEN epv.name = 'C_CORREO_REGISTRO_ACADEMICO' THEN epv.value END) AS correo_registro_academico,
        MAX(CASE WHEN epv.name = 'C_NOMBRE_TITULOS_Y_GRADOS' THEN epv.value END) AS nombre_titulos_y_grados,
        MAX(CASE WHEN epv.name = 'C_CORREO_TITULOS_Y_GRADOS' THEN epv.value END) AS correo_titulos_y_grados,
        ARRAY_JOIN(
            ARRAY_AGG(
                DISTINCT REPLACE(TRIM(REGEXP_REPLACE(epv.value, '[\r\n\t]+', ' ')), ',', '.')
            ) FILTER (WHERE epv.name = 'C_COMETARIO_SOLICITANTE'),
            ' | '
        ) AS comentario_solicitante
    FROM uss_datalake_stage.banner_oracle_workflow_eng_properties_values AS epv
    INNER JOIN workflow_base AS wf
        ON wf.id = epv.id
    WHERE epv.name IN (
        'C_DESC_ESTADO_ESTUDIANTE', 'C_PERIODO', 'C_NRC', 'C_CURSO',
        'C_COD_SEDE', 'C_SEDE', 'C_FECHA_SOLICITUD', 'C_CARRERA',
        'C_NOMBRE_CARRERA', 'C_NOMESCUELA', 'C_OBSERVACION_SZARSOL',
        'C_SEQPLAN', 'C_NIVEL', 'C_CALIFICACION_ACTUAL',
        'C_CALIFICACION_SOLICITADA', 'C_RUT_SOLICITANTE',
        'C_NOMBRE_SOLICITANTE', 'C_RUT_ESTUDIANTE',
        'C_NOMBRE_ESTUDIANTE', 'C_CORREO_ESTUDIANTE',
        'C_FONO_ESTUDIANTE', 'C_RUT_DOCENTE', 'C_NOMBRE_DOCENTE',
        'C_CORREO_DOCENTE', 'C_GLOSA', 'C_RUT_DECANO', 'C_NOMBRE_DECANO',
        'C_CORREO_DECANO', 'C_RUT_DIRECTOR_ACADEMICO',
        'C_NOMBRE_DIRECTOR_ACADEMICO', 'C_CORREO_DIRECTOR_ACADEMICO',
        'C_RUT_DC_O_DD', 'C_NOMBRE_DC_O_DD', 'C_CORREO_DC_O_DD',
        'C_RUT_REGISTRO_ACADEMICO', 'C_NOMBRE_REGISTRO_ACADEMICO',
        'C_CORREO_REGISTRO_ACADEMICO', 'C_NOMBRE_TITULOS_Y_GRADOS',
        'C_CORREO_TITULOS_Y_GRADOS', 'C_COMETARIO_SOLICITANTE'
    )
    GROUP BY epv.id
)

SELECT
    wf.id,
    wf.pd_id,
    wf.workflow_name AS name,
    p.desc_estado_estudiante,
    p.periodo,
    p.nrc,
    p.curso,
    p.cod_sede,
    p.sede,
    p.fecha_solicitud,
    p.cod_carrera,
    p.nombre_carrera,
    p.nomescuela,
    p.observacion_szarsol,
    p.seqplan,
    p.nivel,
    p.calificacion_actual,
    p.calificacion_solicitada,
    p.rut_solicitante,
    p.nombre_solicitante,
    p.rut_estudiante,
    p.nombre_estudiante,
    p.correo_estudiante,
    p.fono_estudiante,
    p.rut_docente,
    p.nombre_docente,
    p.correo_docente,
    p.glosa,
    p.rut_decano,
    p.nombre_decano,
    p.correo_decano,
    p.rut_director_academico,
    p.nombre_director_academico,
    p.correo_director_academico,
    p.rut_dc_o_dd,
    p.nombre_dc_o_dd,
    p.correo_dc_o_dd,
    p.rut_registro_academico,
    p.nombre_registro_academico,
    p.correo_registro_academico,
    p.nombre_titulos_y_grados,
    p.correo_titulos_y_grados,
    p.comentario_solicitante,
    wf.current_state AS estado_actual,
    wf.start_date,
    wf.stop_date,
    CAST(wf.running AS VARCHAR) AS ejecutandose,
    wf.last_state AS ultimo_estado,
    CAST(wf.originating_user_id AS VARCHAR) AS originating_user_id,
    CAST(wf.originating_event_id AS VARCHAR) AS originating_event_id,
    CAST(wf.originating_process_id AS VARCHAR) AS originating_process_id,
    CAST(wf.owner_role_id AS VARCHAR) AS owner_role_id,
    CAST(wf.admin_role_id AS VARCHAR) AS admin_role_id,
    CAST(wf.requires_execution_plan AS VARCHAR) AS requires_execution_plan,
    CASE
        WHEN wf.stop_date IS NOT NULL THEN 'FINALIZADA'
        WHEN LOWER(CAST(wf.running AS VARCHAR)) = 'false' THEN 'FINALIZADA'
        ELSE 'EN CURSO'
    END AS estado_operacional
FROM workflow_base AS wf
INNER JOIN propiedades AS p
    ON p.id = wf.id;
