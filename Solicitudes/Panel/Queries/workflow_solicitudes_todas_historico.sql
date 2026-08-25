-- SOLICITUDES WORKFLOW: DATASET HISTORICO PARA TODAS LAS TIPOLOGIAS
-- Amazon Athena / Trino. Una fila por solicitud y propiedad del formulario.
-- Sin filtro fijo de periodo. Los indicadores deben contar DISTINCT id.

WITH workflows AS (
    SELECT *
    FROM (
        SELECT
            w.*,
            ROW_NUMBER() OVER (
                PARTITION BY w.id
                ORDER BY w.dt DESC NULLS LAST
            ) AS rn
        FROM uss_datalake_stage.banner_oracle_workflow_eng_workflow AS w
    ) AS ranked
    WHERE rn = 1
),
definiciones AS (
    SELECT *
    FROM (
        SELECT
            p.*,
            ROW_NUMBER() OVER (
                PARTITION BY p.id
                ORDER BY p.version DESC NULLS LAST, p.dt DESC NULLS LAST
            ) AS rn
        FROM uss_datalake_stage.banner_oracle_workflow_process_definition AS p
    ) AS ranked
    WHERE rn = 1
),
propiedades AS (
    SELECT *
    FROM (
        SELECT
            v.*,
            ROW_NUMBER() OVER (
                PARTITION BY v.id, v.name, v.seq
                ORDER BY v.dt DESC NULLS LAST
            ) AS rn
        FROM uss_datalake_stage.banner_oracle_workflow_eng_properties_values AS v
    ) AS ranked
    WHERE rn = 1
),
base_larga AS (
    SELECT
        w.id,
        w.pd_id,
        w.name AS cabecera,
        w.current_state AS estado_actual,
        CASE
            WHEN LOWER(COALESCE(w.current_state, '')) LIKE '%cancel%' THEN 'CANCELADA'
            WHEN LOWER(COALESCE(w.current_state, '')) LIKE '%completed%'
              OR LOWER(COALESCE(w.current_state, '')) LIKE '%stopped%' THEN 'FINALIZADA'
            WHEN UPPER(COALESCE(w.running, '')) = 'Y' THEN 'EN CURSO'
            ELSE 'OTRO'
        END AS estado_operacional,
        w.start_date,
        w.stop_date,
        pd.name AS tipo_solicitud,
        CASE
            WHEN LOWER(COALESCE(pd.name, '')) LIKE '%reincorpor%' THEN 'Reincorporación'
            WHEN LOWER(COALESCE(pd.name, '')) LIKE '%cambio de nota%'
              OR LOWER(COALESCE(pd.name, '')) LIKE '%calific%' THEN 'Cambio de calificación'
            WHEN LOWER(COALESCE(pd.name, '')) LIKE '%continuidad%' THEN 'Continuidad de estudios'
            WHEN REGEXP_LIKE(
                REGEXP_REPLACE(
                    LOWER(COALESCE(pd.name, '')),
                    '[_-]+',
                    ' '
                ),
                'cambio( de)? carrera( sede)?'
            ) THEN 'Cambio de carrera/sede'
            WHEN LOWER(COALESCE(pd.name, '')) LIKE '%suspensi%'
              OR LOWER(COALESCE(pd.name, '')) LIKE '%suspension%' THEN 'Suspensión'
            WHEN LOWER(COALESCE(pd.name, '')) LIKE '%inscripcion especial%'
              OR LOWER(COALESCE(pd.name, '')) LIKE '%inscripción especial%' THEN 'Inscripción especial'
            WHEN LOWER(COALESCE(pd.name, '')) LIKE '%retiro%' THEN 'Retiro'
            WHEN LOWER(COALESCE(pd.name, '')) LIKE '%inscripci%extraordin%'
              OR LOWER(COALESCE(pd.name, '')) LIKE '%inscripcion extraordinaria%' THEN 'Inscripción extraordinaria'
            ELSE COALESCE(pd.name, 'Sin clasificación')
        END AS categoria_solicitud,
        w.last_state AS ultima_actividad,
        w.origin AS origen,
        w.running AS indicador_en_ejecucion,
        CAST(w.originating_user_id AS VARCHAR) AS usuario_origen_id,
        CAST(w.owner_role_id AS VARCHAR) AS rol_propietario_id,
        CAST(w.admin_role_id AS VARCHAR) AS rol_administrador_id,
        pv.name AS nombre_propiedad,
        pv.type AS tipo_propiedad,
        pv.seq AS secuencia_propiedad,
        pv.value AS valor_propiedad,
        pd.description AS descripcion_tipo_solicitud,
        pd.version AS version_workflow,
        CAST(w.dt AS VARCHAR) AS particion_workflow,
        CAST(pv.dt AS VARCHAR) AS particion_propiedad
    FROM workflows AS w
    LEFT JOIN definiciones AS pd
        ON w.pd_id = pd.id
    LEFT JOIN propiedades AS pv
        ON w.id = pv.id
),
enriquecida AS (
    SELECT
        b.*,
        MAX(
            CASE WHEN REGEXP_LIKE(
                LOWER(COALESCE(b.nombre_propiedad, '')),
                '(^|_)(periodo|periodo_adm|periodo_academico|periodo_consulta|term|term_code)($|_)'
            ) THEN b.valor_propiedad END
        ) OVER (PARTITION BY b.id) AS periodo_detectado,
        MAX(
            CASE WHEN REGEXP_LIKE(
                LOWER(COALESCE(b.nombre_propiedad, '')),
                '(^|_)(sede|campus|cod_sede|nombre_sede)($|_)'
            ) THEN b.valor_propiedad END
        ) OVER (PARTITION BY b.id) AS sede_detectada,
        MAX(
            CASE WHEN REGEXP_LIKE(
                LOWER(COALESCE(b.nombre_propiedad, '')),
                '(^|_)(nivel|nivel_academico|nivel_estudiante)($|_)'
            ) THEN b.valor_propiedad END
        ) OVER (PARTITION BY b.id) AS nivel_detectado,
        MAX(
            CASE WHEN REGEXP_LIKE(
                LOWER(COALESCE(b.nombre_propiedad, '')),
                '(^|_)(rut|rut_estudiante|rut_alumno|rutalumno)($|_)'
            ) THEN b.valor_propiedad END
        ) OVER (PARTITION BY b.id) AS rut_estudiante_detectado
    FROM base_larga AS b
)
SELECT
    id,
    pd_id,
    cabecera,
    estado_actual,
    estado_operacional,
    start_date,
    stop_date,
    tipo_solicitud,
    categoria_solicitud,
    COALESCE(periodo_detectado, 'Sin periodo') AS periodo,
    COALESCE(sede_detectada, 'Sin sede') AS sede,
    COALESCE(nivel_detectado, 'Sin nivel') AS nivel,
    rut_estudiante_detectado AS rut_estudiante,
    ultima_actividad,
    origen,
    indicador_en_ejecucion,
    usuario_origen_id,
    rol_propietario_id,
    rol_administrador_id,
    nombre_propiedad,
    tipo_propiedad,
    secuencia_propiedad,
    valor_propiedad,
    descripcion_tipo_solicitud,
    version_workflow,
    particion_workflow,
    particion_propiedad
FROM enriquecida;
