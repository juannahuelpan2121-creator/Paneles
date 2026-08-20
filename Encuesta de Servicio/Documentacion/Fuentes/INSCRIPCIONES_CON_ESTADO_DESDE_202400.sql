SELECT DISTINCT
    CAST(sfrstcr.sfrstcr_term_code AS VARCHAR) AS PERIODO,
    to_hex(sha256(to_utf8(cast(spriden.spriden_id AS varchar)))) AS ID_ESTUDIANTE,
    CAST(sfrstcr.sfrstcr_crn AS VARCHAR) AS NRC,
    ssbsect.ssbsect_subj_code AS MATERIA,
    ssbsect.ssbsect_crse_numb AS CURSO,
    ssbsect.ssbsect_schd_code AS COMPONENTE,
    ssbsect.ssbsect_camp_code AS CAMPUS,
    sfrstcr.sfrstcr_rsts_code AS ESTADO_NRC
FROM uss_datalake_stage.banner_oracle_saturn_sfrstcr sfrstcr
LEFT JOIN uss_datalake_stage.banner_oracle_saturn_spriden spriden
    ON spriden.spriden_pidm = sfrstcr.sfrstcr_pidm
   AND spriden.spriden_change_ind IS NULL
LEFT JOIN uss_datalake_stage.banner_oracle_saturn_ssbsect ssbsect
    ON ssbsect.ssbsect_crn = sfrstcr.sfrstcr_crn
   AND ssbsect.ssbsect_term_code = sfrstcr.sfrstcr_term_code
WHERE CAST(sfrstcr.sfrstcr_term_code AS VARCHAR) >= '202400'
