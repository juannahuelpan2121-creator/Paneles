-- ============================================================================
-- MIGRACION AL NUEVO DATALAKE - 2026-07-21   (Lote 2: docencia / encuestas / VcM)
-- ----------------------------------------------------------------------------
-- Homologacion 1:1: solo se reemplazan las referencias de tabla banner9_prod.*
-- por uss_datalake_stage.banner_oracle_<modulo>_<tabla>. No se tocan columnas,
-- alias, filtros ni comentarios.
-- ============================================================================

WITH SeccionesTerminos AS (
    SELECT DISTINCT ssbsect_term_code, ssbsect_subj_code, ssbsect_crse_numb
    FROM uss_datalake_stage.banner_oracle_saturn_ssbsect
),
CursoEfectivo AS (
    SELECT
        st.ssbsect_term_code,
        st.ssbsect_subj_code,
        st.ssbsect_crse_numb,
        c.scbcrse_title,
        c.scbcrse_coll_code,
        ROW_NUMBER() OVER (
            PARTITION BY st.ssbsect_term_code, st.ssbsect_subj_code, st.ssbsect_crse_numb
            ORDER BY c.scbcrse_eff_term DESC
        ) as rn
    FROM SeccionesTerminos st
    INNER JOIN uss_datalake_stage.banner_oracle_saturn_scbcrse c
        ON st.ssbsect_subj_code = c.scbcrse_subj_code
       AND st.ssbsect_crse_numb = c.scbcrse_crse_numb
       AND c.scbcrse_eff_term <= st.ssbsect_term_code
),
NivelEfectivo AS (
    SELECT
        st.ssbsect_term_code,
        st.ssbsect_subj_code,
        st.ssbsect_crse_numb,
        l.scrlevl_levl_code,
        ROW_NUMBER() OVER (
            PARTITION BY st.ssbsect_term_code, st.ssbsect_subj_code, st.ssbsect_crse_numb
            ORDER BY l.scrlevl_eff_term DESC
        ) as rn
    FROM SeccionesTerminos st
    INNER JOIN uss_datalake_stage.banner_oracle_saturn_scrlevl l
        ON st.ssbsect_subj_code = l.scrlevl_subj_code
       AND st.ssbsect_crse_numb = l.scrlevl_crse_numb
       AND l.scrlevl_eff_term <= st.ssbsect_term_code
)

SELECT
    a.svbtesd_term_code                                    AS "periodo",
    k.stvterm_acyr_code                                    AS "año",
    a.svbtesd_crn                                          AS "nrc",
    a.svbtesd_tssc_code                                    AS "codigo_encuesta",
    e.svvtssc_desc                                         AS "nombre_encuesta",
    a.svbtesd_qcod_code                                    AS "codigo_pregunta",
    g.svbqcod_desc                                         AS "texto_pregunta",
    f.svvteqa_desc                                         AS "tipo_pregunta_area",
    a.svbtesd_sdef_seq_num                                 AS "secuencia",
    ce.scbcrse_title                                       AS "titulo_oficial_curso",
    b.ssbsect_seq_numb                                     AS "seccion",
    b.ssbsect_subj_code || b.ssbsect_crse_numb             AS "cod_asignatura", 

    CASE 
        WHEN SUBSTR(a.svbtesd_term_code, 5, 2) IN ('10', '20') 
             AND TRIM(UPPER(b.ssbsect_subj_code)) = 'IAGE' 
            THEN 'PREGRADO'
        WHEN SUBSTR(a.svbtesd_term_code, 5, 2) IN ('05', '15', '25') 
             OR TRIM(UPPER(stv.stvlevl_desc)) = 'TRIMESTRAL PREGRADO' 
            THEN 'ADVANCE'
        ELSE stv.stvlevl_desc 
    END AS "nivel",

    b.ssbsect_camp_code                                    AS "cod_campus",
    ce.scbcrse_coll_code                                   AS "cod_facultad",
    b.ssbsect_ssts_code                                    AS "estado_nrc",
    b.ssbsect_schd_code                                    AS "componente",
    b.ssbsect_enrl                                         AS "inscritos",
    b.ssbsect_gradable_ind                                 AS "calificable",
    a.svbtesd_faculty_pidm                                 AS "pidm_docente",
    fac.spriden_id                                         AS "cod_docente",
    fac.spriden_last_name                                  AS "apellido_docente",
    CONCAT(fac.spriden_first_name, ' ', COALESCE(fac.spriden_search_mi, '')) AS "nombre_docente",

    COUNT(*)                                               AS "total_respuestas",

    REPLACE(
        CAST(TRY_CAST(a.svbtesd_sdef_weight AS DECIMAL(10, 2)) AS VARCHAR),
        '.', ','
    )                                                      AS "ponderación_pregunta",

    SUM(CASE WHEN TRY_CAST(a.svbtesd_pvac_qpoints AS INTEGER) = 0 THEN 1 ELSE 0 END) AS "votos_nota_0",
    SUM(CASE WHEN TRY_CAST(a.svbtesd_pvac_qpoints AS INTEGER) = 1 THEN 1 ELSE 0 END) AS "votos_nota_1",
    SUM(CASE WHEN TRY_CAST(a.svbtesd_pvac_qpoints AS INTEGER) = 2 THEN 1 ELSE 0 END) AS "votos_nota_2",
    SUM(CASE WHEN TRY_CAST(a.svbtesd_pvac_qpoints AS INTEGER) = 3 THEN 1 ELSE 0 END) AS "votos_nota_3",
    SUM(CASE WHEN TRY_CAST(a.svbtesd_pvac_qpoints AS INTEGER) = 4 THEN 1 ELSE 0 END) AS "votos_nota_4",
    SUM(CASE WHEN TRY_CAST(a.svbtesd_pvac_qpoints AS INTEGER) = 5 THEN 1 ELSE 0 END) AS "votos_nota_5",
    SUM(CASE WHEN TRY_CAST(a.svbtesd_pvac_qpoints AS INTEGER) = 6 THEN 1 ELSE 0 END) AS "votos_nota_6",
    SUM(CASE WHEN TRY_CAST(a.svbtesd_pvac_qpoints AS INTEGER) = 7 THEN 1 ELSE 0 END) AS "votos_nota_7",

    SUM(CASE WHEN TRY_CAST(a.svbtesd_pvac_qpoints AS INTEGER) IN (1, 2) THEN 1 ELSE 0 END) AS "votos_1_y_2",
    SUM(CASE WHEN TRY_CAST(a.svbtesd_pvac_qpoints AS INTEGER) IN (4, 5) THEN 1 ELSE 0 END) AS "votos_4_y_5"

FROM uss_datalake_stage.banner_oracle_saturn_svbtesd  AS a
INNER JOIN uss_datalake_stage.banner_oracle_saturn_svbtesh AS h
    ON  a.svbtesd_term_code       = h.svbtesh_term_code
    AND a.svbtesd_crn             = h.svbtesh_crn
    AND a.svbtesd_esas_temp_pidm  = h.svbtesh_esas_temp_pidm
INNER JOIN uss_datalake_stage.banner_oracle_saturn_ssbsect AS b
    ON  a.svbtesd_term_code       = b.ssbsect_term_code
    AND a.svbtesd_crn             = b.ssbsect_crn

LEFT JOIN CursoEfectivo ce
    ON b.ssbsect_term_code = ce.ssbsect_term_code
   AND b.ssbsect_subj_code = ce.ssbsect_subj_code
   AND b.ssbsect_crse_numb = ce.ssbsect_crse_numb
   AND ce.rn = 1

LEFT JOIN NivelEfectivo ne
    ON b.ssbsect_term_code = ne.ssbsect_term_code
   AND b.ssbsect_subj_code = ne.ssbsect_subj_code
   AND b.ssbsect_crse_numb = ne.ssbsect_crse_numb
   AND ne.rn = 1

LEFT JOIN uss_datalake_stage.banner_oracle_saturn_stvlevl AS stv
    ON ne.scrlevl_levl_code = stv.stvlevl_code

LEFT JOIN uss_datalake_stage.banner_oracle_saturn_spriden  AS fac
    ON  a.svbtesd_faculty_pidm    = fac.spriden_pidm
    AND fac.spriden_change_ind IS NULL
LEFT JOIN uss_datalake_stage.banner_oracle_saturn_svvtssc  AS e
    ON  a.svbtesd_tssc_code       = e.svvtssc_code
LEFT JOIN uss_datalake_stage.banner_oracle_saturn_svvteqa  AS f
    ON  a.svbtesd_teqa_code       = f.svvteqa_code
LEFT JOIN uss_datalake_stage.banner_oracle_saturn_svbqcod  AS g
    ON  a.svbtesd_qcod_code       = g.svbqcod_code
LEFT JOIN uss_datalake_stage.banner_oracle_saturn_stvterm  AS k
    ON  a.svbtesd_term_code       = k.stvterm_code

-- ✅ FILTRO DE AÑO Y NIVEL
WHERE k.stvterm_acyr_code >= '2020'
--AND fac.spriden_id IN ('156821357','187198356')
  --AND b.ssbsect_subj_code in ('DCEX','INGE', 'DMAE', 'FIAD')
  and a.svbtesd_sdef_weight > 0
--  AND b.ssbsect_camp_code  in ('TPC','TP2')

GROUP BY
    a.svbtesd_term_code,
    k.stvterm_acyr_code,
    a.svbtesd_crn,
    a.svbtesd_tssc_code,
    e.svvtssc_desc,
    a.svbtesd_qcod_code,
    g.svbqcod_desc,
    f.svvteqa_desc,
    ce.scbcrse_coll_code,
    a.svbtesd_sdef_seq_num,
    ce.scbcrse_title,
    b.ssbsect_seq_numb,
    b.ssbsect_subj_code,
    b.ssbsect_crse_numb,

    CASE 
        WHEN SUBSTR(a.svbtesd_term_code, 5, 2) IN ('10', '20') 
             AND TRIM(UPPER(b.ssbsect_subj_code)) = 'IAGE' 
            THEN 'PREGRADO'
        WHEN SUBSTR(a.svbtesd_term_code, 5, 2) IN ('05', '15', '25') 
             OR TRIM(UPPER(stv.stvlevl_desc)) = 'TRIMESTRAL PREGRADO' 
            THEN 'ADVANCE'
        ELSE stv.stvlevl_desc 
    END,

    b.ssbsect_camp_code,
    b.ssbsect_ssts_code,
    b.ssbsect_schd_code,
    b.ssbsect_enrl,
    b.ssbsect_gradable_ind,
    a.svbtesd_faculty_pidm,
    fac.spriden_id,
    fac.spriden_last_name,
    fac.spriden_first_name,
    fac.spriden_search_mi,
    a.svbtesd_sdef_weight;