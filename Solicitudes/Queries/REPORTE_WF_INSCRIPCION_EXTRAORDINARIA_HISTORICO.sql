-- Reporte WF Solicitud Extraordinaria de Inscripcion de Asignaturas
-- Version Data Lake optimizada para Amazon Athena / Trino.
--
-- Mejoras principales:
--   1. ENG_PROPERTIES_VALUES se lee de forma agregada en vez de ejecutar
--      una subconsulta correlacionada por cada columna.
--   2. Los NRC solicitados se normalizan en filas y se enriquecen una sola vez.
--   3. SCBCRSE se resuelve con la version vigente al periodo de la seccion.
--   4. La limpieza de HTML usa expresiones regulares en lugar de decenas de REPLACE.
--
-- La consulta no fija periodo y carga el historico completo del workflow.
-- Para cambiar el tipo de workflow, modificar solamente el pd_id del CTE parametros.

WITH parametros AS (
    SELECT CAST(19994978 AS BIGINT) AS pd_id
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

propiedades_base AS (
    SELECT
        epv.id,
        epv.name,
        epv.value
    FROM uss_datalake_stage.banner_oracle_workflow_eng_properties_values AS epv
    INNER JOIN workflow_base AS wf
        ON wf.id = epv.id
    WHERE epv.name IN (
        'C_RUT', 'C_FULL_NAME', 'C_CARRERA', 'WF_ESTPROGRAMA',
        'C_EMAIL_ALUMNO', 'WF_NIVEL', 'WF_PERIODOADM',
        'WF_TIENERETENCION', 'C_SEDE', 'C_SECPLAN', 'WF_PGA',
        'WF_ASIGAPROBADAS', 'C_FECHA_SOLICITUD', 'C_PERIODO',
        'C_CODIGO_SALICITUD', 'WF_COMENTARIOEST',
        'WF_OPCNRC1', 'WF_OPCNRC2', 'WF_OPCNRC3', 'WF_OPCNRC4',
        'WF_OPCNRC5', 'WF_OPCNRC6', 'WF_OPCNRC7', 'WF_OPCNRC8',
        'WF_OPCNRC9', 'WF_OPCNRC10', 'WF_OPCNRC11', 'WF_OPCNRC12',
        'WF_RESPNRC1', 'WF_RESPNRC2', 'WF_RESPNRC3', 'WF_RESPNRC4',
        'WF_RESPNRC5', 'WF_RESPNRC6', 'WF_RESPNRC7', 'WF_RESPNRC8',
        'WF_RESPNRC9', 'WF_RESPNRC10', 'WF_RESPNRC11', 'WF_RESPNRC12',
        'WF_NRCS_SOLICITADOS', 'C_LISTADO_NRCS_RECHAZADOS', 'WF_MENSAJE'
    )
),

propiedades AS (
    SELECT
        id,
        MAX(CASE WHEN name = 'C_RUT' THEN value END) AS rut_estudiante,
        MAX(CASE WHEN name = 'C_FULL_NAME' THEN value END) AS nombre_estudiante,
        MAX(CASE WHEN name = 'C_CARRERA' THEN value END) AS c_carrera,
        MAX(CASE WHEN name = 'WF_ESTPROGRAMA' THEN value END) AS estado_alumno,
        MAX(CASE WHEN name = 'C_EMAIL_ALUMNO' THEN value END) AS email_alumno,
        MAX(CASE WHEN name = 'WF_NIVEL' THEN value END) AS nivel,
        MAX(CASE WHEN name = 'WF_PERIODOADM' THEN value END) AS periodo_adm,
        MAX(CASE WHEN name = 'WF_TIENERETENCION' THEN value END) AS retencion,
        MAX(CASE WHEN name = 'C_SEDE' THEN value END) AS sede,
        MAX(CASE WHEN name = 'C_SECPLAN' THEN value END) AS secuencia_plan,
        MAX(CASE WHEN name = 'WF_PGA' THEN REPLACE(value, '.', ',') END) AS pga,
        ARRAY_JOIN(
            ARRAY_AGG(
                DISTINCT TRIM(REGEXP_REPLACE(value, '[\r\n\t]+', ' '))
            ) FILTER (WHERE name = 'WF_ASIGAPROBADAS'),
            ' | '
        ) AS asignaturas_aprobadas,
        MAX(CASE WHEN name = 'C_FECHA_SOLICITUD' THEN value END) AS fecha_solicitud,
        MAX(CASE WHEN name = 'C_PERIODO' THEN value END) AS periodo,
        MAX(CASE WHEN name = 'C_CODIGO_SALICITUD' THEN value END) AS c_codigo_solicitud,
        ARRAY_JOIN(
            ARRAY_AGG(
                DISTINCT TRIM(REGEXP_REPLACE(value, '[\r\n\t]+', ' '))
            ) FILTER (WHERE name = 'WF_COMENTARIOEST'),
            ' | '
        ) AS comentario,
        MAX(CASE WHEN name = 'WF_RESPNRC1' THEN value END) AS resp_nrc1,
        MAX(CASE WHEN name = 'WF_RESPNRC2' THEN value END) AS resp_nrc2,
        MAX(CASE WHEN name = 'WF_RESPNRC3' THEN value END) AS resp_nrc3,
        MAX(CASE WHEN name = 'WF_RESPNRC4' THEN value END) AS resp_nrc4,
        MAX(CASE WHEN name = 'WF_RESPNRC5' THEN value END) AS resp_nrc5,
        MAX(CASE WHEN name = 'WF_RESPNRC6' THEN value END) AS resp_nrc6,
        MAX(CASE WHEN name = 'WF_RESPNRC7' THEN value END) AS resp_nrc7,
        MAX(CASE WHEN name = 'WF_RESPNRC8' THEN value END) AS resp_nrc8,
        MAX(CASE WHEN name = 'WF_RESPNRC9' THEN value END) AS resp_nrc9,
        MAX(CASE WHEN name = 'WF_RESPNRC10' THEN value END) AS resp_nrc10,
        MAX(CASE WHEN name = 'WF_RESPNRC11' THEN value END) AS resp_nrc11,
        MAX(CASE WHEN name = 'WF_RESPNRC12' THEN value END) AS resp_nrc12,
        ARRAY_JOIN(
            ARRAY_AGG(
                DISTINCT TRIM(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REPLACE(
                                REPLACE(
                                    REPLACE(
                                        REPLACE(
                                            REPLACE(
                                                REPLACE(value, '&nbsp;', ' '),
                                                '&aacute;', 'á'
                                            ),
                                            '&eacute;', 'é'
                                        ),
                                        '&iacute;', 'í'
                                    ),
                                    '&oacute;', 'ó'
                                ),
                                '&uacute;', 'ú'
                            ),
                            '<[^>]*>',
                            ' '
                        ),
                        '\s+',
                        ' '
                    )
                )
            ) FILTER (WHERE name = 'WF_NRCS_SOLICITADOS'),
            ' | '
        ) AS nrcs_solicitados,
        ARRAY_JOIN(
            ARRAY_AGG(
                DISTINCT TRIM(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REPLACE(
                                REPLACE(
                                    REPLACE(
                                        REPLACE(
                                            REPLACE(
                                                REPLACE(value, '&nbsp;', ' '),
                                                '&aacute;', 'á'
                                            ),
                                            '&eacute;', 'é'
                                        ),
                                        '&iacute;', 'í'
                                    ),
                                    '&oacute;', 'ó'
                                ),
                                '&uacute;', 'ú'
                            ),
                            '<[^>]*>',
                            ' '
                        ),
                        '\s+',
                        ' '
                    )
                )
            ) FILTER (WHERE name = 'C_LISTADO_NRCS_RECHAZADOS'),
            ' | '
        ) AS nrcs_rechazado,
        MAX(CASE WHEN name = 'WF_MENSAJE' THEN value END) AS mensaje
    FROM propiedades_base
    GROUP BY id
),

periodos_reporte AS (
    SELECT DISTINCT periodo
    FROM propiedades
    WHERE NULLIF(TRIM(periodo), '') IS NOT NULL
),

nrc_solicitado AS (
    SELECT
        id,
        CAST(REGEXP_EXTRACT(name, '([0-9]+)$', 1) AS INTEGER) AS posicion,
        REGEXP_EXTRACT(TRIM(value), '([0-9]+)', 1) AS crn
    FROM propiedades_base
    WHERE REGEXP_LIKE(name, '^WF_OPCNRC([1-9]|1[0-2])$')
      AND NULLIF(TRIM(value), '') IS NOT NULL
),

seccion_curso AS (
    SELECT
        s.ssbsect_term_code AS periodo,
        CAST(s.ssbsect_crn AS VARCHAR) AS crn,
        s.ssbsect_subj_code AS materia,
        s.ssbsect_crse_numb AS curso,
        c.scbcrse_title AS nombre_curso,
        ROW_NUMBER() OVER (
            PARTITION BY s.ssbsect_term_code, s.ssbsect_crn
            ORDER BY c.scbcrse_eff_term DESC
        ) AS rn
    FROM uss_datalake_stage.banner_oracle_saturn_ssbsect AS s
    INNER JOIN periodos_reporte AS pr
        ON pr.periodo = s.ssbsect_term_code
    LEFT JOIN uss_datalake_stage.banner_oracle_saturn_scbcrse AS c
        ON c.scbcrse_subj_code = s.ssbsect_subj_code
       AND c.scbcrse_crse_numb = s.ssbsect_crse_numb
       AND c.scbcrse_eff_term <= s.ssbsect_term_code
),

nrc_detalle AS (
    SELECT
        n.id,
        n.posicion,
        CASE
            WHEN sc.crn IS NULL THEN NULL
            ELSE CONCAT(
                n.crn,
                ' ',
                COALESCE(sc.materia, ''),
                ' - ',
                COALESCE(sc.curso, ''),
                ' ',
                COALESCE(sc.nombre_curso, '')
            )
        END AS descripcion_nrc
    FROM nrc_solicitado AS n
    INNER JOIN propiedades AS p
        ON p.id = n.id
    LEFT JOIN seccion_curso AS sc
        ON sc.periodo = p.periodo
       AND sc.crn = n.crn
       AND sc.rn = 1
),

nrc_pivot AS (
    SELECT
        id,
        MAX(CASE WHEN posicion = 1 THEN descripcion_nrc END) AS nrc1,
        MAX(CASE WHEN posicion = 2 THEN descripcion_nrc END) AS nrc2,
        MAX(CASE WHEN posicion = 3 THEN descripcion_nrc END) AS nrc3,
        MAX(CASE WHEN posicion = 4 THEN descripcion_nrc END) AS nrc4,
        MAX(CASE WHEN posicion = 5 THEN descripcion_nrc END) AS nrc5,
        MAX(CASE WHEN posicion = 6 THEN descripcion_nrc END) AS nrc6,
        MAX(CASE WHEN posicion = 7 THEN descripcion_nrc END) AS nrc7,
        MAX(CASE WHEN posicion = 8 THEN descripcion_nrc END) AS nrc8,
        MAX(CASE WHEN posicion = 9 THEN descripcion_nrc END) AS nrc9,
        MAX(CASE WHEN posicion = 10 THEN descripcion_nrc END) AS nrc10,
        MAX(CASE WHEN posicion = 11 THEN descripcion_nrc END) AS nrc11,
        MAX(CASE WHEN posicion = 12 THEN descripcion_nrc END) AS nrc12
    FROM nrc_detalle
    GROUP BY id
)

SELECT
    wf.id,
    wf.pd_id,
    wf.workflow_name AS name,
    p.rut_estudiante,
    p.nombre_estudiante,
    p.c_carrera,
    p.estado_alumno,
    p.email_alumno,
    p.nivel,
    p.periodo_adm,
    p.retencion,
    p.sede,
    p.secuencia_plan,
    p.pga,
    p.asignaturas_aprobadas,
    p.fecha_solicitud,
    p.periodo,
    p.c_codigo_solicitud,
    p.comentario,
    n.nrc1,
    p.resp_nrc1,
    n.nrc2,
    p.resp_nrc2,
    n.nrc3,
    p.resp_nrc3,
    n.nrc4,
    p.resp_nrc4,
    n.nrc5,
    p.resp_nrc5,
    n.nrc6,
    p.resp_nrc6,
    n.nrc7,
    p.resp_nrc7,
    n.nrc8,
    p.resp_nrc8,
    n.nrc9,
    p.resp_nrc9,
    n.nrc10,
    p.resp_nrc10,
    n.nrc11,
    p.resp_nrc11,
    n.nrc12,
    p.resp_nrc12,
    p.nrcs_solicitados,
    p.nrcs_rechazado,
    p.mensaje,
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
    ON p.id = wf.id
LEFT JOIN nrc_pivot AS n
    ON n.id = wf.id;
