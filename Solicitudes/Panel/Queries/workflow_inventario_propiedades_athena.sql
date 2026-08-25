-- INVENTARIO DE CAMPOS POR TIPO DE SOLICITUD
-- Ejecutar primero en Athena para conocer los nombres reales de las propiedades.
-- Una fila por tipo de solicitud y propiedad encontrada.

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
                ORDER BY
                    p.version DESC NULLS LAST,
                    p.dt DESC NULLS LAST
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
)
SELECT
    pd.name AS tipo_solicitud,
    pv.name AS nombre_propiedad,
    pv.type AS tipo_propiedad,
    COUNT(DISTINCT w.id) AS cantidad_solicitudes_con_propiedad,
    COUNT(*) AS cantidad_valores,
    MIN(pv.value) AS valor_ejemplo
FROM workflows AS w
LEFT JOIN definiciones AS pd
    ON w.pd_id = pd.id
LEFT JOIN propiedades AS pv
    ON w.id = pv.id
GROUP BY
    pd.name,
    pv.name,
    pv.type
ORDER BY
    tipo_solicitud,
    nombre_propiedad;
