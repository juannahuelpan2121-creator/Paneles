-- SOLICITUDES WORKFLOW: DATASET HISTORICO OPTIMIZADO
-- Amazon Athena / Trino. Una fila por solicitud.
-- Sin filtro fijo de periodo. Las propiedades se agregan sin importar su texto.
-- La sede visible se homologa contra STVCAMP; sede_workflow conserva el valor original.

WITH catalogo_campus AS (
    SELECT
        TRIM(stvcamp_code) AS codigo_campus,
        TRIM(stvcamp_desc) AS descripcion_campus,
        REGEXP_REPLACE(UPPER(TRIM(stvcamp_desc)), '[^A-Z0-9]+', '') AS descripcion_clave
    FROM uss_datalake_stage.banner_oracle_saturn_stvcamp
    WHERE NULLIF(TRIM(stvcamp_code), '') IS NOT NULL
),
sede_alias (alias_clave, codigo_campus) AS (
    VALUES
        ('CIUDADUNIVERSITARIA', 'CES'),
        ('OSORNOPILAUCO', 'PLO'),
        ('VALDIVIA', 'CVA'),
        ('DAFABES', 'BES'),
        ('DAFACES', 'CES')
),
campus_claves_candidatas AS (
    SELECT codigo_campus AS sede_clave, codigo_campus, descripcion_campus, 1 AS prioridad
    FROM catalogo_campus

    UNION ALL

    SELECT descripcion_clave AS sede_clave, codigo_campus, descripcion_campus, 2 AS prioridad
    FROM catalogo_campus

    UNION ALL

    SELECT a.alias_clave AS sede_clave, c.codigo_campus, c.descripcion_campus, 3 AS prioridad
    FROM sede_alias AS a
    INNER JOIN catalogo_campus AS c
        ON a.codigo_campus = c.codigo_campus
),
campus_claves AS (
    SELECT sede_clave, codigo_campus, descripcion_campus
    FROM (
        SELECT
            sede_clave,
            codigo_campus,
            descripcion_campus,
            ROW_NUMBER() OVER (
                PARTITION BY sede_clave
                ORDER BY prioridad, codigo_campus
            ) AS rn
        FROM campus_claves_candidatas
        WHERE NULLIF(sede_clave, '') IS NOT NULL
    ) AS ranked
    WHERE rn = 1
),
definiciones_base AS (
    SELECT
        id,
        name,
        description,
        version
    FROM (
        SELECT
            p.id,
            p.name,
            p.description,
            p.version,
            ROW_NUMBER() OVER (
                PARTITION BY p.id
                ORDER BY p.version DESC NULLS LAST, p.dt DESC NULLS LAST
            ) AS rn
        FROM uss_datalake_stage.banner_oracle_workflow_process_definition AS p
    ) AS ranked
    WHERE rn = 1
),
definiciones_clasificadas AS (
    SELECT
        id,
        name,
        description,
        version,
        CASE
            WHEN id = CAST(19994978 AS BIGINT) THEN 'Inscripción especial'
            WHEN LOWER(COALESCE(name, '')) LIKE '%reincorpor%' THEN 'Reincorporación'
            WHEN LOWER(COALESCE(name, '')) LIKE '%cambio de nota%'
              OR LOWER(COALESCE(name, '')) LIKE '%calific%' THEN 'Cambio de calificación'
            WHEN LOWER(COALESCE(name, '')) LIKE '%continuidad%' THEN 'Continuidad de estudios'
            WHEN REGEXP_LIKE(
                REGEXP_REPLACE(LOWER(COALESCE(name, '')), '[_-]+', ' '),
                'cambio( de)? carrera( sede)?'
            ) THEN 'Cambio de carrera/sede'
            WHEN LOWER(COALESCE(name, '')) LIKE '%suspensi%'
              OR LOWER(COALESCE(name, '')) LIKE '%suspension%' THEN 'Suspensión'
            WHEN REGEXP_LIKE(
                REGEXP_REPLACE(LOWER(COALESCE(name, '')), '[_-]+', ' '),
                'inscripci[oó]n especial'
            ) THEN 'Inscripción especial'
            WHEN LOWER(COALESCE(name, '')) LIKE '%retiro%' THEN 'Retiro'
            WHEN REGEXP_LIKE(
                REGEXP_REPLACE(LOWER(COALESCE(name, '')), '[_-]+', ' '),
                '(inscripci[oó]n|matr[ií]cula).*extraordin'
            ) THEN 'Inscripción especial'
            ELSE NULL
        END AS categoria_solicitud
    FROM definiciones_base
),
definiciones AS (
    SELECT
        *,
        CASE
            WHEN id = CAST(19994978 AS BIGINT) THEN 'Inscripción Extraordinaria'
            WHEN categoria_solicitud = 'Inscripción especial'
             AND REGEXP_LIKE(
                REGEXP_REPLACE(LOWER(COALESCE(name, '')), '[_-]+', ' '),
                '(inscripci[oó]n|matr[ií]cula).*extraordin'
            ) THEN 'Inscripción Extraordinaria'
            WHEN categoria_solicitud = 'Inscripción especial' THEN 'Inscripción Especial'
            ELSE categoria_solicitud
        END AS tipo_clasificacion
    FROM definiciones_clasificadas
    WHERE categoria_solicitud IS NOT NULL
),
workflows AS (
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
        tipo_clasificacion,
        ultima_actividad,
        origen,
        indicador_en_ejecucion,
        usuario_origen_id,
        rol_propietario_id,
        rol_administrador_id,
        descripcion_tipo_solicitud,
        version_workflow,
        particion_workflow,
        periodo_encabezado,
        rut_encabezado
    FROM (
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
            d.name AS tipo_solicitud,
            d.categoria_solicitud,
            d.tipo_clasificacion,
            w.last_state AS ultima_actividad,
            w.origin AS origen,
            w.running AS indicador_en_ejecucion,
            CAST(w.originating_user_id AS VARCHAR) AS usuario_origen_id,
            CAST(w.owner_role_id AS VARCHAR) AS rol_propietario_id,
            CAST(w.admin_role_id AS VARCHAR) AS rol_administrador_id,
            d.description AS descripcion_tipo_solicitud,
            d.version AS version_workflow,
            CAST(w.dt AS VARCHAR) AS particion_workflow,
            REGEXP_EXTRACT(
                TRIM(COALESCE(w.name, '')),
                '(20[0-9]{4})[ ]+[0-9]{8}[ ]+[0-9]{4}[ ]*$',
                1
            ) AS periodo_encabezado,
            COALESCE(
                REGEXP_EXTRACT(
                    UPPER(COALESCE(w.name, '')),
                    'RUT[^A-Z0-9]*(E?[0-9]{7,9}[0-9K]?)',
                    1
                ),
                REGEXP_EXTRACT(
                    UPPER(COALESCE(w.name, '')),
                    'SUSPENSI[^A-Z0-9]*(E?[0-9]{7,9}[0-9K]?)',
                    1
                ),
                REGEXP_EXTRACT(
                    TRIM(UPPER(COALESCE(w.name, ''))),
                    '(E?[0-9]{7,9}[0-9K]?)[ ]+20[0-9]{4}[ ]+[0-9]{8}[ ]+[0-9]{4}[ ]*$',
                    1
                )
            ) AS rut_encabezado,
            ROW_NUMBER() OVER (
                PARTITION BY w.id
                ORDER BY w.dt DESC NULLS LAST
            ) AS rn
        FROM uss_datalake_stage.banner_oracle_workflow_eng_workflow AS w
        INNER JOIN definiciones AS d
            ON w.pd_id = d.id
    ) AS ranked
    WHERE rn = 1
),
propiedades AS (
    SELECT
        id,
        name,
        type,
        seq,
        value,
        dt
    FROM (
        SELECT
            v.id,
            v.name,
            v.type,
            v.seq,
            v.value,
            v.dt,
            ROW_NUMBER() OVER (
                PARTITION BY v.id, v.name, v.seq
                ORDER BY v.dt DESC NULLS LAST
            ) AS rn
        FROM uss_datalake_stage.banner_oracle_workflow_eng_properties_values AS v
        INNER JOIN workflows AS w
            ON v.id = w.id
    ) AS ranked
    WHERE rn = 1
),
sede_candidatas AS (
    SELECT
        p.id,
        p.name AS nombre_propiedad_sede,
        p.value AS sede_workflow,
        REGEXP_REPLACE(UPPER(TRIM(p.value)), '[^A-Z0-9]+', '') AS sede_clave,
        c.codigo_campus,
        c.descripcion_campus,
        CASE
            WHEN REGEXP_LIKE(LOWER(COALESCE(p.name, '')), '(destino|nueva)') THEN 9
            WHEN UPPER(COALESCE(p.name, '')) IN (
                'C_CAMPUS_CODE', 'C_CODIGO_SEDE', 'C_COD_SEDE', 'C_SEDE'
            ) THEN 1
            ELSE 5
        END AS prioridad_propiedad
    FROM propiedades AS p
    LEFT JOIN campus_claves AS c
        ON REGEXP_REPLACE(UPPER(TRIM(p.value)), '[^A-Z0-9]+', '') = c.sede_clave
    WHERE REGEXP_LIKE(
        LOWER(COALESCE(p.name, '')),
        '(^|_)(sede|campus|cod_sede|nombre_sede)($|_)'
    )
),
sede_resuelta AS (
    SELECT
        id,
        sede_workflow,
        codigo_campus,
        descripcion_campus
    FROM (
        SELECT
            id,
            sede_workflow,
            codigo_campus,
            descripcion_campus,
            ROW_NUMBER() OVER (
                PARTITION BY id
                ORDER BY
                    CASE WHEN codigo_campus IS NOT NULL THEN 0 ELSE 1 END,
                    prioridad_propiedad,
                    CASE WHEN sede_clave = codigo_campus THEN 0 ELSE 1 END,
                    nombre_propiedad_sede,
                    sede_workflow
            ) AS rn
        FROM sede_candidatas
    ) AS ranked
    WHERE rn = 1
),
atributos AS (
    SELECT
        id,
        MAX(
            CASE WHEN UPPER(COALESCE(name, '')) = 'C_PERIODO'
                THEN REGEXP_EXTRACT(TRIM(value), '(20[0-9]{4})', 1)
            END
        ) AS periodo_principal,
        MAX(
            CASE WHEN UPPER(COALESCE(name, '')) IN (
                'C_TERM_CODE', 'FRM_PERIODO', 'P_PERIODO',
                'L_PERIODO', 'PERIODO', 'PERIODO_CONSULTA'
            ) THEN REGEXP_EXTRACT(TRIM(value), '(20[0-9]{4})', 1)
            END
        ) AS periodo_alternativo,
        MAX(
            CASE WHEN UPPER(COALESCE(name, '')) IN (
                'P_PERIODOADM', 'WF_PERIODOADM', 'PERIODO_ADM'
            ) THEN REGEXP_EXTRACT(TRIM(value), '(20[0-9]{4})', 1)
            END
        ) AS periodo_admision,
        MAX(
            CASE WHEN REGEXP_LIKE(
                LOWER(COALESCE(name, '')),
                '(^|_)(nivel|nivel_academico|nivel_estudiante)($|_)'
            ) THEN value END
        ) AS nivel_detectado,
        MAX(
            CASE
                WHEN UPPER(COALESCE(name, '')) = 'C_RUT'
                 AND NOT REGEXP_LIKE(UPPER(TRIM(value)), '^U')
                 AND REGEXP_LIKE(
                    REGEXP_REPLACE(UPPER(TRIM(value)), '[^A-Z0-9K]', ''),
                    '^(E[0-9]{8}|[0-9]{7,9}[0-9K])$'
                 )
                THEN REGEXP_REPLACE(UPPER(TRIM(value)), '[^A-Z0-9K]', '')
            END
        ) AS rut_c_rut,
        MAX(
            CASE
                WHEN UPPER(COALESCE(name, '')) IN (
                    'RUT', 'RUT_ALUMNO', 'RUT_ESTUDIANTE', 'RUTALUMNO',
                    'C_RUT_ALUMNO', 'C_RUT_ESTUDIANTE'
                )
                 AND NOT REGEXP_LIKE(UPPER(TRIM(value)), '^U')
                 AND REGEXP_LIKE(
                    REGEXP_REPLACE(UPPER(TRIM(value)), '[^A-Z0-9K]', ''),
                    '^(E[0-9]{8}|[0-9]{7,9}[0-9K])$'
                 )
                THEN REGEXP_REPLACE(UPPER(TRIM(value)), '[^A-Z0-9K]', '')
            END
        ) AS rut_alternativo,
        COUNT(*) AS cantidad_propiedades,
        MAX(CAST(dt AS VARCHAR)) AS particion_propiedad
    FROM propiedades
    GROUP BY id
),
atributos_homologados AS (
    SELECT
        a.*,
        s.sede_workflow,
        s.codigo_campus,
        s.descripcion_campus
    FROM atributos AS a
    LEFT JOIN sede_resuelta AS s
        ON a.id = s.id
)
SELECT
    w.id,
    w.pd_id,
    w.cabecera,
    w.estado_actual,
    w.estado_operacional,
    w.start_date,
    w.stop_date,
    w.tipo_solicitud,
    w.categoria_solicitud,
    w.tipo_clasificacion,
    COALESCE(
        NULLIF(w.periodo_encabezado, ''),
        a.periodo_principal,
        a.periodo_alternativo,
        a.periodo_admision,
        'Sin periodo'
    ) AS periodo,
    COALESCE(
        CONCAT(a.codigo_campus, ' - ', a.descripcion_campus),
        'Sin sede homologada'
    ) AS sede,
    COALESCE(a.sede_workflow, 'Sin sede informada') AS sede_workflow,
    COALESCE(a.nivel_detectado, 'Sin nivel') AS nivel,
    COALESCE(w.rut_encabezado, a.rut_c_rut, a.rut_alternativo) AS rut_estudiante,
    w.ultima_actividad,
    w.origen,
    w.indicador_en_ejecucion,
    w.usuario_origen_id,
    w.rol_propietario_id,
    w.rol_administrador_id,
    CAST(COALESCE(a.cantidad_propiedades, 0) AS BIGINT) AS cantidad_propiedades,
    w.descripcion_tipo_solicitud,
    w.version_workflow,
    w.particion_workflow,
    a.particion_propiedad
FROM workflows AS w
LEFT JOIN atributos_homologados AS a
    ON w.id = a.id;
