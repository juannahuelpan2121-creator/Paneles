-- ============================================================================
-- MIGRACION AL NUEVO DATALAKE - 2026-07-21   (VARIANTE, no version de produccion)
-- ----------------------------------------------------------------------------
--   Esta variante usa la tabla SOVLCUR (CTE 'matric_ranked' -> campo
--   "PERIODO_MATRICULACION"). CONFIRMADO en el inventario ESTADO_ACTUAL_DL_21072026:
--   sovlcur SI esta cargada, con nombre real 'banner_oracle_baninst1_sovlcur'
--   (modulo baninst1, NO saturn como se habia inferido el 2026-07-17). 43 columnas.
--   => Query estructuralmente ejecutable.
--
-- La vista mongodb_dev.vw_sam_matricula_preprocesada fue sustituida por el CTE
-- 'sam_matricula' (ver nota tecnica de sustitucion del 2026-07-17).
--
-- NOTA DE DATOS (barrido de sanidad 21/07): esta query hereda las brechas de
-- carga aun no corregidas de spriden (duplicada x3.00) y sam (2.4% de
-- completitud). La validacion reflejara esas desviaciones hasta que el equipo
-- DL corrija dichas tablas; no son defectos de la migracion.
-- ============================================================================
--####### QUERY MAESTRO ESTUDIANTES ADVANCE ######

WITH sam_matricula AS (
    SELECT
        rut,
        academicperiod,
        careercode,
        reportdata_campuscode,
        studentstatus,
        isold
    FROM uss_datalake_stage.sam_mongodb_retenciones_studentpostulants
    WHERE studentstatus = 'MATRICULADO'
),
RankedCurriculum AS (
    SELECT 
        x.*,
        ROW_NUMBER() OVER (
            PARTITION BY x.sorlcur_pidm, x.sorlcur_key_seqno, x.sorlcur_term_code
            ORDER BY x.sorlcur_activity_date DESC, x.sorlcur_seqno DESC
        ) as ranking
    FROM uss_datalake_stage.banner_oracle_saturn_sorlcur x
    WHERE x.sorlcur_lmod_code = 'LEARNER'
      AND x.sorlcur_cact_code = 'ACTIVE'
),

RankedAddress AS (
    SELECT
        spraddr_pidm,
        spraddr_cnty_code,
        ROW_NUMBER() OVER (
            PARTITION BY spraddr_pidm
            ORDER BY spraddr_activity_date DESC, spraddr_from_date DESC
        ) as addr_ranking
    FROM uss_datalake_stage.banner_oracle_saturn_spraddr
    WHERE spraddr_status_ind IS NULL
),

RankedMajor AS (
    SELECT
        sobcurr.sobcurr_program,
        sobcurr.sobcurr_curr_rule,
        sorcmjr.sorcmjr_majr_code,
        sorcmjr.sorcmjr_term_code_eff,
        ROW_NUMBER() OVER (
            PARTITION BY sobcurr.sobcurr_program
            ORDER BY sorcmjr.sorcmjr_term_code_eff DESC, sorcmjr.sorcmjr_cmjr_rule DESC
        ) as major_ranking
    FROM uss_datalake_stage.banner_oracle_saturn_sobcurr sobcurr
    INNER JOIN uss_datalake_stage.banner_oracle_saturn_sorcmjr sorcmjr
        ON sobcurr.sobcurr_curr_rule = sorcmjr.sorcmjr_curr_rule
),

-- =====================================================
-- Catálogos disponibles por programa (smbpgen)
-- =====================================================
catalogos_programa AS (
    SELECT DISTINCT
        smbpgen_program,
        smbpgen_term_code_eff AS catalogo
    FROM uss_datalake_stage.banner_oracle_saturn_smbpgen
),

-- =====================================================
-- Todas las asignaturas de todos los catálogos por programa
-- Cadena: smrpaap -> smbagen -> smracaa -> smbarul -> smrarul
-- =====================================================
catalogo_asignaturas AS (
    SELECT DISTINCT
        paap.smrpaap_program,
        paap.smrpaap_term_code_eff AS version_catalogo,
        paap.smrpaap_area,
        paap.smrpaap_area_priority,
        arul.smrarul_subj_code,
        arul.smrarul_crse_numb_low
    FROM uss_datalake_stage.banner_oracle_saturn_smrpaap paap

    INNER JOIN catalogos_programa cp
        ON cp.smbpgen_program = paap.smrpaap_program
        AND cp.catalogo = paap.smrpaap_term_code_eff

    INNER JOIN uss_datalake_stage.banner_oracle_saturn_smbagen agen
        ON agen.smbagen_area = paap.smrpaap_area

    INNER JOIN uss_datalake_stage.banner_oracle_saturn_smracaa acaa
        ON acaa.smracaa_area = agen.smbagen_area

    INNER JOIN uss_datalake_stage.banner_oracle_saturn_smbarul barul
        ON barul.smbarul_area = acaa.smracaa_area
        AND barul.smbarul_key_rule = acaa.smracaa_rule

    INNER JOIN uss_datalake_stage.banner_oracle_saturn_smrarul arul
        ON arul.smrarul_area = barul.smbarul_area
        AND arul.smrarul_key_rule = barul.smbarul_key_rule
),

-- =====================================================
-- Cruce: inscripciones del estudiante vs catálogo
-- Búsqueda espiral por distancia al catálogo del estudiante
-- =====================================================
asig_con_nivel AS (
    SELECT
        c.sorlcur_pidm,
        c.sorlcur_program,
        c.sorlcur_term_code,
        c.sorlcur_term_code_ctlg,
        cat.smrpaap_area_priority,
        cat.version_catalogo,
        sect.ssbsect_subj_code,
        sect.ssbsect_crse_numb,
        ROW_NUMBER() OVER (
            PARTITION BY c.sorlcur_pidm, c.sorlcur_program, c.sorlcur_term_code,
                         sect.ssbsect_subj_code, sect.ssbsect_crse_numb
            ORDER BY
                ABS(CAST(cat.version_catalogo AS INTEGER) - CAST(c.sorlcur_term_code_ctlg AS INTEGER)) ASC,
                cat.version_catalogo DESC
        ) AS rn_version
    FROM RankedCurriculum c

    INNER JOIN uss_datalake_stage.banner_oracle_saturn_sfrstcr fcr
        ON fcr.sfrstcr_pidm = c.sorlcur_pidm
        AND fcr.sfrstcr_term_code = c.sorlcur_term_code
        AND fcr.sfrstcr_rsts_code IN ('RE', 'RW')

    INNER JOIN uss_datalake_stage.banner_oracle_saturn_ssbsect sect
        ON sect.ssbsect_crn = fcr.sfrstcr_crn
        AND sect.ssbsect_term_code = fcr.sfrstcr_term_code

    INNER JOIN catalogo_asignaturas cat
        ON cat.smrpaap_program = c.sorlcur_program
        AND cat.smrarul_subj_code = sect.ssbsect_subj_code
        AND cat.smrarul_crse_numb_low = sect.ssbsect_crse_numb

    WHERE c.ranking = 1
),

asig_version_correcta AS (
    SELECT
        sorlcur_pidm,
        sorlcur_program,
        sorlcur_term_code,
        sorlcur_term_code_ctlg,
        smrpaap_area_priority,
        ssbsect_subj_code,
        ssbsect_crse_numb,
        ROW_NUMBER() OVER (
            PARTITION BY sorlcur_pidm, sorlcur_program, sorlcur_term_code
            ORDER BY smrpaap_area_priority DESC
        ) AS rn_final
    FROM asig_con_nivel
    WHERE rn_version = 1
),

-- =====================================================
-- CTE: Conteo de asignaturas en malla (bloque principal)
-- Filtro de periodos independiente, igual que v3
-- =====================================================
asig_en_malla AS (
    SELECT
        sorlcur_pidm,
        sorlcur_program,
        sorlcur_term_code,
        COUNT(DISTINCT ssbsect_subj_code || '-' || ssbsect_crse_numb) AS total_asignaturas
    FROM asig_version_correcta
    WHERE sorlcur_term_code >='202300'     --------->>> PERIODO CATALOGO
    GROUP BY sorlcur_pidm, sorlcur_program, sorlcur_term_code
),

-- =====================================================
-- CTE: Solo el registro con max nivel por estudiante
-- =====================================================
max_nivel_asig AS (
    SELECT
        sorlcur_pidm,
        sorlcur_program,
        sorlcur_term_code,
        smrpaap_area_priority AS max_nivel_asignatura,
        ssbsect_subj_code || ' ' || ssbsect_crse_numb AS asignatura_max_nivel
    FROM asig_version_correcta
    WHERE rn_final = 1
      AND sorlcur_term_code  >='202300'     --------->>> PERIODO CATALOGO
),

-- =====================================================
-- CTE: Nivel predominante del estudiante (bloque principal)
-- Agrupa por pidm+programa+periodo+area_priority y elige el
-- nivel con MAS asignaturas inscritas (cantidad).
-- Desempate: prioridad MENOR gana.
-- =====================================================
nivel_predominante AS (
    SELECT
        sorlcur_pidm,
        sorlcur_program,
        sorlcur_term_code,
        smrpaap_area_priority AS nivel_estudiante
    FROM (
        SELECT
            sorlcur_pidm,
            sorlcur_program,
            sorlcur_term_code,
            smrpaap_area_priority,
            COUNT(DISTINCT ssbsect_subj_code || '-' || ssbsect_crse_numb) AS qty_asig,
            ROW_NUMBER() OVER (
                PARTITION BY sorlcur_pidm, sorlcur_program, sorlcur_term_code
                ORDER BY
                    COUNT(DISTINCT ssbsect_subj_code || '-' || ssbsect_crse_numb) DESC,
                    smrpaap_area_priority ASC
            ) AS rn_predominante
        FROM asig_version_correcta
        WHERE sorlcur_term_code >= '201700'     --------->>> PERIODO CATALOGO
        GROUP BY
            sorlcur_pidm,
            sorlcur_program,
            sorlcur_term_code,
            smrpaap_area_priority
    ) sub
    WHERE rn_predominante = 1
),

-- =====================================================
-- CTE: Programa anterior
-- =====================================================
programa_anterior AS (
    SELECT
        curr.sorlcur_pidm,
        curr.sorlcur_program AS programa_actual,
        curr.sorlcur_term_code AS periodo_consulta,
        prev.sorlcur_program AS programa_previo,
        prev.sorlcur_term_code AS periodo_previo,
        ROW_NUMBER() OVER (
            PARTITION BY curr.sorlcur_pidm, curr.sorlcur_program, curr.sorlcur_term_code
            ORDER BY prev.sorlcur_term_code DESC
        ) AS rn
    FROM RankedCurriculum curr
    INNER JOIN RankedCurriculum prev
        ON prev.sorlcur_pidm = curr.sorlcur_pidm
        AND prev.sorlcur_term_code < curr.sorlcur_term_code
        AND prev.sorlcur_program != curr.sorlcur_program
        AND prev.ranking = 1
    WHERE curr.ranking = 1
),

-- =====================================================
-- CTE: Reingreso
-- =====================================================
RankedReingreso AS (
    SELECT
        s.sgrstsp_pidm,
        s.sgrstsp_term_code_eff,
        s.sgrstsp_key_seqno,
        s.sgrstsp_stsp_code,
        c.sorlcur_pidm,
        c.sorlcur_key_seqno,
        c.sorlcur_term_code,
        c.sorlcur_program,
        c.sorlcur_term_code_ctlg,
        c.sorlcur_term_code_admit,
        c.sorlcur_camp_code,
        c.sorlcur_levl_code,
        c.sorlcur_activity_date,
        c.sorlcur_seqno,
        ROW_NUMBER() OVER (
            PARTITION BY s.sgrstsp_pidm, c.sorlcur_program, s.sgrstsp_term_code_eff
            ORDER BY s.sgrstsp_key_seqno DESC
        ) AS rn_reingreso
    FROM uss_datalake_stage.banner_oracle_saturn_sgrstsp s
    INNER JOIN RankedCurriculum c
        ON s.sgrstsp_pidm = c.sorlcur_pidm
        AND CAST(s.sgrstsp_key_seqno AS VARCHAR) = CAST(c.sorlcur_key_seqno AS VARCHAR)
        AND CAST(s.sgrstsp_term_code_eff AS VARCHAR) = CAST(c.sorlcur_term_code AS VARCHAR)
        AND c.ranking = 1
    WHERE s.sgrstsp_term_code_eff >= '201700'     ------> PERIODO MALLA (DEBE SER SIEMPRE EL MENOR)
      AND c.sorlcur_term_code_admit IS NOT NULL
      AND TRIM(c.sorlcur_term_code_admit) != ''
      and c.sorlcur_levl_code = 'AV'              ------> FILTRO NIVEL ACADÉMICO
),

-- =====================================================
-- CTE: Periodos auxiliares
-- =====================================================
periodos_inscripcion AS (
    SELECT DISTINCT
        sfrstcr_pidm,
        CAST(sfrstcr_term_code AS VARCHAR) AS periodo_inscripcion
    FROM uss_datalake_stage.banner_oracle_saturn_sfrstcr
    WHERE sfrstcr_rsts_code IN ('RE', 'RW')
),

auxiliares_plan_cercano AS (
    SELECT
        s.sgrstsp_pidm,
        s.sgrstsp_term_code_eff,
        s.sgrstsp_key_seqno,
        s.sgrstsp_stsp_code,
        s.sorlcur_program,
        s.sorlcur_term_code_ctlg,
        s.sorlcur_term_code_admit,
        s.sorlcur_camp_code,
        s.sorlcur_levl_code,
        s.sorlcur_activity_date,
        pi.periodo_inscripcion,
        ROW_NUMBER() OVER (
            PARTITION BY s.sgrstsp_pidm, s.sorlcur_program, pi.periodo_inscripcion
            ORDER BY s.sgrstsp_term_code_eff DESC
        ) AS rn_plan_cercano
    FROM RankedReingreso s
    INNER JOIN periodos_inscripcion pi
        ON pi.sfrstcr_pidm = s.sgrstsp_pidm
        AND pi.periodo_inscripcion != CAST(s.sgrstsp_term_code_eff AS VARCHAR)
        AND pi.periodo_inscripcion > CAST(s.sgrstsp_term_code_eff AS VARCHAR)
        AND NOT EXISTS (
            SELECT 1 FROM RankedReingreso r2
            WHERE r2.sgrstsp_pidm = s.sgrstsp_pidm
              AND r2.sorlcur_program = s.sorlcur_program
              AND CAST(r2.sgrstsp_term_code_eff AS VARCHAR) = CAST(pi.periodo_inscripcion AS VARCHAR)
              AND r2.rn_reingreso = 1
        )
    WHERE s.rn_reingreso = 1
),

-- =====================================================
-- CTE: Conteo de asignaturas en malla (bloque auxiliar)
-- Filtro de periodos independiente igual que v3
-- =====================================================
asig_en_malla_aux AS (
    SELECT
        fcr.sfrstcr_pidm,
        rr.sorlcur_program,
        CAST(fcr.sfrstcr_term_code AS VARCHAR) AS periodo_inscripcion,
        COUNT(DISTINCT sect.ssbsect_subj_code || '-' || sect.ssbsect_crse_numb) AS total_asignaturas
    FROM RankedReingreso rr
    INNER JOIN uss_datalake_stage.banner_oracle_saturn_sfrstcr fcr
        ON fcr.sfrstcr_pidm = rr.sgrstsp_pidm
        AND fcr.sfrstcr_rsts_code IN ('RE', 'RW')
        AND fcr.sfrstcr_term_code >= '202400'          ------> PERIODO INSCRIPCIÓN A REVISAR
        AND CAST(fcr.sfrstcr_term_code AS VARCHAR) > CAST(rr.sgrstsp_term_code_eff AS VARCHAR)
    INNER JOIN uss_datalake_stage.banner_oracle_saturn_ssbsect sect
        ON sect.ssbsect_crn = fcr.sfrstcr_crn
        AND sect.ssbsect_term_code = fcr.sfrstcr_term_code
    INNER JOIN (
        SELECT
            rr2.sgrstsp_pidm,
            rr2.sorlcur_program,
            rr2.sorlcur_term_code_ctlg,
            fcr2.sfrstcr_term_code,
            sect2.ssbsect_subj_code,
            sect2.ssbsect_crse_numb,
            ROW_NUMBER() OVER (
                PARTITION BY rr2.sgrstsp_pidm, rr2.sorlcur_program, fcr2.sfrstcr_term_code,
                             sect2.ssbsect_subj_code, sect2.ssbsect_crse_numb
                ORDER BY
                    ABS(CAST(cat2.version_catalogo AS INTEGER) - CAST(rr2.sorlcur_term_code_ctlg AS INTEGER)) ASC,
                    cat2.version_catalogo DESC
            ) AS rn_version
        FROM RankedReingreso rr2
        INNER JOIN uss_datalake_stage.banner_oracle_saturn_sfrstcr fcr2
            ON fcr2.sfrstcr_pidm = rr2.sgrstsp_pidm
            AND fcr2.sfrstcr_rsts_code IN ('RE', 'RW')
            AND fcr2.sfrstcr_term_code >= '202400'      ------> PERIODO INSCRIPCIÓN A REVISAR
            AND CAST(fcr2.sfrstcr_term_code AS VARCHAR) > CAST(rr2.sgrstsp_term_code_eff AS VARCHAR)
        INNER JOIN uss_datalake_stage.banner_oracle_saturn_ssbsect sect2
            ON sect2.ssbsect_crn = fcr2.sfrstcr_crn
            AND sect2.ssbsect_term_code = fcr2.sfrstcr_term_code
        INNER JOIN catalogo_asignaturas cat2
            ON cat2.smrpaap_program = rr2.sorlcur_program
            AND cat2.smrarul_subj_code = sect2.ssbsect_subj_code
            AND cat2.smrarul_crse_numb_low = sect2.ssbsect_crse_numb
        WHERE rr2.rn_reingreso = 1
    ) espiral
        ON espiral.sgrstsp_pidm = rr.sgrstsp_pidm
        AND espiral.sorlcur_program = rr.sorlcur_program
        AND espiral.sfrstcr_term_code = fcr.sfrstcr_term_code
        AND espiral.ssbsect_subj_code = sect.ssbsect_subj_code
        AND espiral.ssbsect_crse_numb = sect.ssbsect_crse_numb
        AND espiral.rn_version = 1
    WHERE rr.rn_reingreso = 1
    GROUP BY
        fcr.sfrstcr_pidm,
        rr.sorlcur_program,
        CAST(fcr.sfrstcr_term_code AS VARCHAR)
),

-- =====================================================
-- CTE: Inscripciones eliminadas
-- =====================================================
eliminadas AS (
    SELECT DISTINCT
        sfrstca_pidm,
        CAST(sfrstca_term_code AS VARCHAR)         AS sfrstca_term_code,
        CAST(sfrstca_stsp_key_sequence AS VARCHAR) AS sfrstca_stsp_key_sequence
    FROM uss_datalake_stage.banner_oracle_saturn_sfrstca
),

-- =====================================================
-- CTE: Solicitudes de retiro y suspensión
-- =====================================================
solicitudes AS (
    SELECT
        wf.pd_id,
        wf.id                                                         AS wf_id,
        CASE 
            WHEN pd.name IN ('S_SOLICITUD_DE_RETIRO', 'SOLICITUD_DE_RETIRO_B9_REV3') 
                THEN 'RETIRO'
            WHEN pd.name IN ('S_SOLICITUD_DE_SUSPENSION', 'SOLICITUD_DE_SUSPENSION_B9') 
                THEN 'SUSPENSION'
        END                                                           AS tipo_solicitud,
        DATE_FORMAT(
            FROM_UNIXTIME(CAST(wf.start_date AS BIGINT) / 1000),
            '%d-%m-%Y'
        )                                                             AS start_date,
        CAST(wf.start_date AS BIGINT)                                 AS start_date_ts,
        MAX(CASE WHEN UPPER(epv.name) IN ('PIDM', 'C_PIDM')
            THEN epv.value END)                                       AS pidm_alumno,
        MAX(CASE WHEN UPPER(epv.name) IN ('COD_CARRERA', 'CARRERA', 'C_COD_CARRERA', 'FRMCODCARRERA',
                                          'C_CARRERA', 'CARRE', 'C_CODIGO_CARRERA', 'FRMCARRERA')
                 AND LENGTH(epv.value) = 4
            THEN epv.value END)                                       AS cod_carrera,
        MAX(CASE WHEN UPPER(epv.name) IN ('C_CAMPUS_CODE', 'C_CODIGO_SEDE', 'C_COD_SEDE', 'C_SEDE')
                 AND LENGTH(epv.value) = 3
            THEN epv.value END)                                       AS cod_campus,
        MAX(CASE WHEN UPPER(epv.name) IN ('C_PERIODO', 'C_TERM_CODE', 'FRM_PERIODO',
                                          'P_PERIODO', 'P_PERIODOADM', 'L_PERIODO', 'PERIODO')
            THEN epv.value END)                                       AS periodo
    FROM uss_datalake_stage.banner_oracle_workflow_eng_workflow wf
    INNER JOIN uss_datalake_stage.banner_oracle_workflow_process_definition pd
        ON wf.pd_id = pd.id
        AND pd.name IN (
            'S_SOLICITUD_DE_RETIRO',
            'S_SOLICITUD_DE_SUSPENSION',
            'SOLICITUD_DE_RETIRO_B9_REV3',
            'SOLICITUD_DE_SUSPENSION_B9'
        )
    INNER JOIN uss_datalake_stage.banner_oracle_workflow_eng_properties_values epv
        ON epv.id = wf.id
    GROUP BY
        wf.pd_id,
        wf.id,
        pd.name,
        wf.start_date
),

solicitudes_dedup AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY pidm_alumno, cod_carrera, periodo
            ORDER BY start_date_ts ASC
        ) AS rn
    FROM solicitudes
),

-- =====================================================
-- CTE: Matriculación desde SOVLCUR (deduplicada)
-- Fuente del campo PERIODO_MATRICULACION.
-- Una fila por (pidm, program, term_code): se conserva
-- la version mas reciente segun activity_date/seqno.
-- Filtro lmod_code='LEARNER': el campo term_code_matric
-- solo se puebla en filas LEARNER.
-- Piso 201700 alineado con PERIODO MALLA del Advance.
-- =====================================================
matric_ranked AS (
    SELECT
        sovlcur_pidm,
        sovlcur_program,
        CAST(sovlcur_term_code AS VARCHAR)         AS sovlcur_term_code,
        CAST(sovlcur_term_code AS INTEGER)         AS sovlcur_term_code_int,
        CAST(sovlcur_term_code_matric AS VARCHAR)  AS sovlcur_term_code_matric
    FROM (
        SELECT
            v.sovlcur_pidm,
            v.sovlcur_program,
            v.sovlcur_term_code,
            v.sovlcur_term_code_matric,
            ROW_NUMBER() OVER (
                PARTITION BY v.sovlcur_pidm, v.sovlcur_program, v.sovlcur_term_code
                ORDER BY v.sovlcur_activity_date DESC, v.sovlcur_seqno DESC
            ) AS rn_matric
        FROM uss_datalake_stage.banner_oracle_baninst1_sovlcur v   -- sovlcur cargada en modulo baninst1 (confirmado inventario 21/07)
        WHERE v.sovlcur_lmod_code = 'LEARNER'
          AND v.sovlcur_cact_code = 'ACTIVE'
          AND v.sovlcur_term_code >= '201700'   ------> PERIODO MATRICULACION (piso, alinear con PERIODO MALLA)
    )
    WHERE rn_matric = 1
),

-- =====================================================
-- CTE: Spiral de matriculacion - BLOQUE PRINCIPAL
-- Para cada (pidm, program, periodo_consulta) del bloque
-- principal, selecciona el term_code_matric cuyo term_code
-- gana el spiral bidireccional contra sorlcur_term_code:
--   1. Match exacto (distancia 0) gana siempre.
--   2. Menor distancia ABS().
--   3. Empate de distancia: hacia ATRAS primero (term menor).
-- Presto no soporta correlated subqueries -> se resuelve
-- con CROSS JOIN acotado por pidm+program + ROW_NUMBER().
-- =====================================================
matric_spiral_principal AS (
    SELECT
        sgrstsp_pidm,
        sorlcur_program,
        periodo_consulta,
        sovlcur_term_code_matric
    FROM (
        SELECT
            rr.sgrstsp_pidm,
            rr.sorlcur_program,
            CAST(rr.sorlcur_term_code AS VARCHAR)      AS periodo_consulta,
            mr.sovlcur_term_code_matric,
            ROW_NUMBER() OVER (
                PARTITION BY rr.sgrstsp_pidm, rr.sorlcur_program, rr.sorlcur_term_code
                ORDER BY
                    CASE WHEN mr.sovlcur_term_code_int = CAST(rr.sorlcur_term_code AS INTEGER)
                         THEN 0 ELSE 1 END ASC,
                    ABS(mr.sovlcur_term_code_int - CAST(rr.sorlcur_term_code AS INTEGER)) ASC,
                    CASE WHEN mr.sovlcur_term_code_int <= CAST(rr.sorlcur_term_code AS INTEGER)
                         THEN 0 ELSE 1 END ASC
            ) AS rn_spiral
        FROM RankedReingreso rr
        INNER JOIN matric_ranked mr
            ON mr.sovlcur_pidm = rr.sgrstsp_pidm
            AND mr.sovlcur_program = rr.sorlcur_program
        WHERE rr.rn_reingreso = 1
    )
    WHERE rn_spiral = 1
),

-- =====================================================
-- CTE: Spiral de matriculacion - BLOQUE AUXILIAR
-- Misma logica que matric_spiral_principal, pero el
-- periodo_consulta aqui es periodo_inscripcion (no el
-- term_code del plan), coherente con el bloque auxiliar
-- del UNION ALL.
-- =====================================================
matric_spiral_aux AS (
    SELECT
        sgrstsp_pidm,
        sorlcur_program,
        periodo_inscripcion,
        sovlcur_term_code_matric
    FROM (
        SELECT
            ac.sgrstsp_pidm,
            ac.sorlcur_program,
            CAST(ac.periodo_inscripcion AS VARCHAR)    AS periodo_inscripcion,
            mr.sovlcur_term_code_matric,
            ROW_NUMBER() OVER (
                PARTITION BY ac.sgrstsp_pidm, ac.sorlcur_program, ac.periodo_inscripcion
                ORDER BY
                    CASE WHEN mr.sovlcur_term_code_int = CAST(ac.periodo_inscripcion AS INTEGER)
                         THEN 0 ELSE 1 END ASC,
                    ABS(mr.sovlcur_term_code_int - CAST(ac.periodo_inscripcion AS INTEGER)) ASC,
                    CASE WHEN mr.sovlcur_term_code_int <= CAST(ac.periodo_inscripcion AS INTEGER)
                         THEN 0 ELSE 1 END ASC
            ) AS rn_spiral
        FROM auxiliares_plan_cercano ac
        INNER JOIN matric_ranked mr
            ON mr.sovlcur_pidm = ac.sgrstsp_pidm
            AND mr.sovlcur_program = ac.sorlcur_program
        WHERE ac.rn_plan_cercano = 1
    )
    WHERE rn_spiral = 1
)

-- =====================================================
-- SELECT PRINCIPAL: registros del periodo del plan
-- =====================================================
SELECT DISTINCT
    to_hex(sha256(to_utf8(cast(i.spriden_id AS varchar)))) AS "ID_ESTUDIANTE",
    i.spriden_last_name       AS "apellido",
    i.spriden_first_name      AS "nombre",
    s.sgrstsp_pidm            AS "pidm",
    s.sgrstsp_term_code_eff   AS "periodo_plan",
    s.sgrstsp_key_seqno       AS "secuencia_plan",
    s.sgrstsp_stsp_code       AS "estado_plan",
    vs.stvstsp_desc           AS "desc_estado_plan",
    s.sorlcur_term_code       AS "periodo_consulta",
    s.sorlcur_levl_code       AS "nivel_academico",
    s.sorlcur_program         AS "programa",
    sobcurr.sobcurr_coll_code AS "cod_facultad",
    vc.stvcoll_desc           AS "desc_facultad",
    rmajor.sorcmjr_majr_code  AS "cod_carrera",
    s.sorlcur_term_code_ctlg  AS "periodo_catalogo",
    s.sorlcur_term_code_admit AS "periodo_admision",
    msp.sovlcur_term_code_matric AS "PERIODO_MATRICULACION",
    s.sorlcur_camp_code       AS "sede",
    vcamp.stvcamp_desc        AS "desc_sede",
    s.sorlcur_activity_date   AS "ultima_fecha_actividad",
    YEAR(CURRENT_DATE) - YEAR(pers.spbpers_birth_date) AS "edad",
    pers.spbpers_sex          AS "genero",
    pers.spbpers_citz_code    AS "nacionalidad",
    vcnty.stvcnty_desc        AS "comuna",
    CASE 
        WHEN s.sorlcur_term_code_admit = s.sorlcur_term_code THEN 'NUEVO'
        ELSE 'ANTIGUO'
    END AS "condicion_estudiante",
    CASE 
        WHEN asig.total_asignaturas > 0 THEN 'SI'
        ELSE 'NO'
    END AS "asignaturas_inscritas",
    mna.max_nivel_asignatura  AS "max_nivel_asignatura",
    mna.asignatura_max_nivel  AS "asignatura_max_nivel",
    npe.nivel_estudiante      AS "NIVEL_ESTUDIANTE",
    COALESCE(pa.programa_previo, s.sorlcur_program) AS "programa_anterior",
    CASE 
        WHEN conv.shrtrce_pidm IS NOT NULL THEN 'SI'
        ELSE 'NO'
    END AS "ec_convalidaciones",
    CASE 
        WHEN sust.shrtrce_pidm IS NOT NULL THEN 'SI'
        ELSE 'NO'
    END AS "ec_sustitucion",
    CASE 
        WHEN sam.isold IS NOT NULL AND CAST(sam.isold AS VARCHAR) = 'false' THEN 'NUEVO'
        WHEN sam.isold IS NOT NULL AND CAST(sam.isold AS VARCHAR) = 'true' THEN 'ANTIGUO'
        ELSE CASE 
            WHEN s.sorlcur_term_code_admit = s.sorlcur_term_code THEN 'NUEVO'
            ELSE 'ANTIGUO'
        END
    END AS "condicion_sam",
    CASE
        WHEN elim.sfrstca_pidm IS NOT NULL THEN 'SI'
        ELSE 'NO'
    END AS "inscripcion_eliminada",
    COALESCE(sol.tipo_solicitud, 'SS_RE_SE') AS "tipo_solicitud",
    COALESCE(sol.start_date, '')             AS "fecha_solicitud"

FROM
    RankedReingreso s

INNER JOIN
    uss_datalake_stage.banner_oracle_saturn_spriden i
    ON s.sgrstsp_pidm = i.spriden_pidm
    AND i.spriden_change_ind IS NULL

LEFT JOIN
    uss_datalake_stage.banner_oracle_saturn_sobcurr sobcurr
    ON s.sorlcur_program = sobcurr.sobcurr_program
    AND s.sorlcur_camp_code = sobcurr.sobcurr_camp_code

LEFT JOIN
    RankedMajor rmajor
    ON s.sorlcur_program = rmajor.sobcurr_program
    AND rmajor.major_ranking = 1

LEFT JOIN
    uss_datalake_stage.banner_oracle_saturn_spbpers pers
    ON i.spriden_pidm = pers.spbpers_pidm

LEFT JOIN
    RankedAddress addr
    ON i.spriden_pidm = addr.spraddr_pidm
    AND addr.addr_ranking = 1

LEFT JOIN
    uss_datalake_stage.banner_oracle_saturn_stvstsp vs
    ON s.sgrstsp_stsp_code = vs.stvstsp_code

LEFT JOIN
    uss_datalake_stage.banner_oracle_saturn_stvcoll vc
    ON sobcurr.sobcurr_coll_code = vc.stvcoll_code

LEFT JOIN
    uss_datalake_stage.banner_oracle_saturn_stvcamp vcamp
    ON s.sorlcur_camp_code = vcamp.stvcamp_code

LEFT JOIN
    uss_datalake_stage.banner_oracle_saturn_stvcnty vcnty
    ON addr.spraddr_cnty_code = vcnty.stvcnty_code

LEFT JOIN asig_en_malla asig
    ON asig.sorlcur_pidm = s.sgrstsp_pidm
    AND asig.sorlcur_program = s.sorlcur_program
    AND asig.sorlcur_term_code = s.sorlcur_term_code

LEFT JOIN max_nivel_asig mna
    ON mna.sorlcur_pidm = s.sgrstsp_pidm
    AND mna.sorlcur_program = s.sorlcur_program
    AND CAST(mna.sorlcur_term_code AS VARCHAR) = CAST(s.sorlcur_term_code AS VARCHAR)

LEFT JOIN nivel_predominante npe
    ON npe.sorlcur_pidm = s.sgrstsp_pidm
    AND npe.sorlcur_program = s.sorlcur_program
    AND CAST(npe.sorlcur_term_code AS VARCHAR) = CAST(s.sorlcur_term_code AS VARCHAR)

LEFT JOIN programa_anterior pa
    ON pa.sorlcur_pidm = s.sgrstsp_pidm
    AND pa.programa_actual = s.sorlcur_program
    AND CAST(pa.periodo_consulta AS VARCHAR) = CAST(s.sorlcur_term_code AS VARCHAR)
    AND pa.rn = 1

LEFT JOIN matric_spiral_principal msp
    ON msp.sgrstsp_pidm = s.sgrstsp_pidm
    AND msp.sorlcur_program = s.sorlcur_program
    AND CAST(msp.periodo_consulta AS VARCHAR) = CAST(s.sorlcur_term_code AS VARCHAR)

LEFT JOIN (
    SELECT DISTINCT
        tr.shrtrce_pidm,
        tr.shrtrce_subj_code
    FROM uss_datalake_stage.banner_oracle_saturn_shrtrce tr
    INNER JOIN (
        SELECT
            scbcrse_subj_code,
            scbcrse_crse_numb,
            scbcrse_dept_code,
            ROW_NUMBER() OVER (
                PARTITION BY scbcrse_subj_code, scbcrse_crse_numb
                ORDER BY scbcrse_eff_term DESC
            ) AS rn
        FROM uss_datalake_stage.banner_oracle_saturn_scbcrse
    ) crse
        ON crse.scbcrse_subj_code = tr.shrtrce_subj_code
        AND crse.scbcrse_crse_numb = tr.shrtrce_crse_numb
        AND crse.rn = 1
        AND (crse.scbcrse_dept_code IS NULL
             OR TRIM(crse.scbcrse_dept_code) = ''
             OR crse.scbcrse_dept_code != 'FORM')
) conv
    ON conv.shrtrce_pidm = s.sgrstsp_pidm

LEFT JOIN (
    SELECT DISTINCT
        tr.shrtrce_pidm,
        cat.smrpaap_program,
        cat.version_catalogo
    FROM uss_datalake_stage.banner_oracle_saturn_shrtrit trit
    INNER JOIN uss_datalake_stage.banner_oracle_saturn_shrtrce tr
        ON tr.shrtrce_pidm = trit.shrtrit_pidm
        AND tr.shrtrce_trit_seq_no = trit.shrtrit_seq_no
    INNER JOIN catalogo_asignaturas cat
        ON cat.smrarul_subj_code = tr.shrtrce_subj_code
        AND cat.smrarul_crse_numb_low = tr.shrtrce_crse_numb
    WHERE trit.shrtrit_sbgi_code = 'ES39'
) sust
    ON sust.shrtrce_pidm = s.sgrstsp_pidm
    AND sust.smrpaap_program = s.sorlcur_program
    AND CAST(sust.version_catalogo AS VARCHAR) = CAST(s.sorlcur_term_code_ctlg AS VARCHAR)

LEFT JOIN sam_matricula sam
    ON CAST(sam.academicperiod AS VARCHAR) = CAST(s.sgrstsp_term_code_eff AS VARCHAR)
    AND sam.careercode = rmajor.sorcmjr_majr_code
    AND sam.reportdata_campuscode = s.sorlcur_camp_code
    AND sam.rut = i.spriden_id
    AND sam.studentstatus = 'MATRICULADO'

LEFT JOIN eliminadas elim
    ON elim.sfrstca_pidm = s.sgrstsp_pidm
    AND elim.sfrstca_term_code = CAST(s.sorlcur_term_code AS VARCHAR)
    AND elim.sfrstca_stsp_key_sequence = CAST(s.sgrstsp_key_seqno AS VARCHAR)

LEFT JOIN solicitudes_dedup sol
    ON CAST(sol.pidm_alumno AS VARCHAR) = CAST(s.sgrstsp_pidm AS VARCHAR)
    AND sol.cod_carrera = rmajor.sorcmjr_majr_code
    AND CAST(sol.periodo AS VARCHAR) = CAST(s.sorlcur_term_code AS VARCHAR)
    AND sol.rn = 1

WHERE
    s.rn_reingreso = 1

UNION ALL

-- =====================================================
-- FILAS AUXILIARES: periodos de inscripción distintos
-- al periodo_plan, con datos del plan original
-- =====================================================
SELECT DISTINCT
    to_hex(sha256(to_utf8(cast(i2.spriden_id AS varchar)))) AS "ID_ESTUDIANTE",
    i2.spriden_last_name       AS "apellido",
    i2.spriden_first_name      AS "nombre",
    s2.sgrstsp_pidm            AS "pidm",
    s2.sgrstsp_term_code_eff   AS "periodo_plan",
    s2.sgrstsp_key_seqno       AS "secuencia_plan",
    s2.sgrstsp_stsp_code       AS "estado_plan",
    vs2.stvstsp_desc           AS "desc_estado_plan",
    s2.periodo_inscripcion     AS "periodo_consulta",
    s2.sorlcur_levl_code       AS "nivel_academico",
    s2.sorlcur_program         AS "programa",
    sobcurr2.sobcurr_coll_code AS "cod_facultad",
    vc2.stvcoll_desc           AS "desc_facultad",
    rmajor2.sorcmjr_majr_code  AS "cod_carrera",
    s2.sorlcur_term_code_ctlg  AS "periodo_catalogo",
    s2.sorlcur_term_code_admit AS "periodo_admision",
    msa.sovlcur_term_code_matric AS "PERIODO_MATRICULACION",
    s2.sorlcur_camp_code       AS "sede",
    vcamp2.stvcamp_desc        AS "desc_sede",
    s2.sorlcur_activity_date   AS "ultima_fecha_actividad",
    YEAR(CURRENT_DATE) - YEAR(pers2.spbpers_birth_date) AS "edad",
    pers2.spbpers_sex          AS "genero",
    pers2.spbpers_citz_code    AS "nacionalidad",
    vcnty2.stvcnty_desc        AS "comuna",
    CASE
        WHEN s2.sorlcur_term_code_admit = s2.periodo_inscripcion THEN 'NUEVO'
        ELSE 'ANTIGUO'
    END AS "condicion_estudiante",
    CASE
        WHEN asig2.total_asignaturas > 0 THEN 'SI'
        ELSE 'NO'
    END AS "asignaturas_inscritas",
    mna2.max_nivel_asignatura  AS "max_nivel_asignatura",
    mna2.asignatura_max_nivel  AS "asignatura_max_nivel",
    npe2.nivel_estudiante      AS "NIVEL_ESTUDIANTE",
    COALESCE(pa2.programa_previo, s2.sorlcur_program) AS "programa_anterior",
    CASE
        WHEN conv2.shrtrce_pidm IS NOT NULL THEN 'SI'
        ELSE 'NO'
    END AS "ec_convalidaciones",
    CASE
        WHEN sust2.shrtrce_pidm IS NOT NULL THEN 'SI'
        ELSE 'NO'
    END AS "ec_sustitucion",
    CASE
        WHEN sam2.isold IS NOT NULL AND CAST(sam2.isold AS VARCHAR) = 'false' THEN 'NUEVO'
        WHEN sam2.isold IS NOT NULL AND CAST(sam2.isold AS VARCHAR) = 'true' THEN 'ANTIGUO'
        ELSE CASE
            WHEN s2.sorlcur_term_code_admit = s2.periodo_inscripcion THEN 'NUEVO'
            ELSE 'ANTIGUO'
        END
    END AS "condicion_sam",
    CASE
        WHEN elim2.sfrstca_pidm IS NOT NULL THEN 'SI'
        ELSE 'NO'
    END AS "inscripcion_eliminada",
    COALESCE(sol2.tipo_solicitud, 'SS_RE_SE') AS "tipo_solicitud",
    COALESCE(sol2.start_date, '')             AS "fecha_solicitud"

FROM
    auxiliares_plan_cercano s2

INNER JOIN
    uss_datalake_stage.banner_oracle_saturn_spriden i2
    ON s2.sgrstsp_pidm = i2.spriden_pidm
    AND i2.spriden_change_ind IS NULL

LEFT JOIN
    uss_datalake_stage.banner_oracle_saturn_sobcurr sobcurr2
    ON s2.sorlcur_program = sobcurr2.sobcurr_program
    AND s2.sorlcur_camp_code = sobcurr2.sobcurr_camp_code

LEFT JOIN
    RankedMajor rmajor2
    ON s2.sorlcur_program = rmajor2.sobcurr_program
    AND rmajor2.major_ranking = 1

LEFT JOIN
    uss_datalake_stage.banner_oracle_saturn_spbpers pers2
    ON i2.spriden_pidm = pers2.spbpers_pidm

LEFT JOIN
    RankedAddress addr2
    ON i2.spriden_pidm = addr2.spraddr_pidm
    AND addr2.addr_ranking = 1

LEFT JOIN
    uss_datalake_stage.banner_oracle_saturn_stvstsp vs2
    ON s2.sgrstsp_stsp_code = vs2.stvstsp_code

LEFT JOIN
    uss_datalake_stage.banner_oracle_saturn_stvcoll vc2
    ON sobcurr2.sobcurr_coll_code = vc2.stvcoll_code

LEFT JOIN
    uss_datalake_stage.banner_oracle_saturn_stvcamp vcamp2
    ON s2.sorlcur_camp_code = vcamp2.stvcamp_code

LEFT JOIN
    uss_datalake_stage.banner_oracle_saturn_stvcnty vcnty2
    ON addr2.spraddr_cnty_code = vcnty2.stvcnty_code

LEFT JOIN asig_en_malla_aux asig2
    ON asig2.sfrstcr_pidm = s2.sgrstsp_pidm
    AND asig2.sorlcur_program = s2.sorlcur_program
    AND asig2.periodo_inscripcion = CAST(s2.periodo_inscripcion AS VARCHAR)

LEFT JOIN (
    SELECT
        sub2.sfrstcr_pidm,
        sub2.smrpaap_program,
        sub2.sfrstcr_term_code,
        sub2.sorlcur_term_code_ctlg,
        sub2.smrpaap_area_priority AS max_nivel_asignatura,
        sub2.ssbsect_subj_code || ' ' || sub2.ssbsect_crse_numb AS asignatura_max_nivel
    FROM (
        SELECT
            sub1.*,
            ROW_NUMBER() OVER (
                PARTITION BY sub1.sfrstcr_pidm, sub1.smrpaap_program, sub1.sfrstcr_term_code
                ORDER BY sub1.smrpaap_area_priority DESC
            ) AS rn_nivel
        FROM (
            SELECT
                fcr.sfrstcr_pidm,
                cat.smrpaap_program,
                fcr.sfrstcr_term_code,
                rr.sorlcur_term_code_ctlg,
                cat.smrpaap_area_priority,
                sect.ssbsect_subj_code,
                sect.ssbsect_crse_numb,
                ROW_NUMBER() OVER (
                    PARTITION BY fcr.sfrstcr_pidm, cat.smrpaap_program, fcr.sfrstcr_term_code,
                                 sect.ssbsect_subj_code, sect.ssbsect_crse_numb
                    ORDER BY
                        ABS(CAST(cat.version_catalogo AS INTEGER) - CAST(rr.sorlcur_term_code_ctlg AS INTEGER)) ASC,
                        cat.version_catalogo DESC
                ) AS rn_version
            FROM RankedReingreso rr
            INNER JOIN uss_datalake_stage.banner_oracle_saturn_sfrstcr fcr
                ON fcr.sfrstcr_pidm = rr.sgrstsp_pidm
                AND fcr.sfrstcr_rsts_code IN ('RE', 'RW')
                AND fcr.sfrstcr_term_code >= '202400'     ------> PERIODO INSCRIPCIÓN A REVISAR
                AND CAST(fcr.sfrstcr_term_code AS VARCHAR) > CAST(rr.sgrstsp_term_code_eff AS VARCHAR)
            INNER JOIN uss_datalake_stage.banner_oracle_saturn_ssbsect sect
                ON sect.ssbsect_crn = fcr.sfrstcr_crn
                AND sect.ssbsect_term_code = fcr.sfrstcr_term_code
            INNER JOIN catalogo_asignaturas cat
                ON cat.smrpaap_program = rr.sorlcur_program
                AND cat.smrarul_subj_code = sect.ssbsect_subj_code
                AND cat.smrarul_crse_numb_low = sect.ssbsect_crse_numb
            WHERE rr.rn_reingreso = 1
        ) sub1
        WHERE sub1.rn_version = 1
    ) sub2
    WHERE sub2.rn_nivel = 1
) mna2
    ON mna2.sfrstcr_pidm = s2.sgrstsp_pidm
    AND mna2.smrpaap_program = s2.sorlcur_program
    AND CAST(mna2.sfrstcr_term_code AS VARCHAR) = CAST(s2.periodo_inscripcion AS VARCHAR)
    AND CAST(mna2.sorlcur_term_code_ctlg AS VARCHAR) = CAST(s2.sorlcur_term_code_ctlg AS VARCHAR)

-- =====================================================
-- Subquery: Nivel predominante (bloque auxiliar)
-- Agrupa por pidm+programa+periodo_inscripcion+area_priority
-- Espiral por catalogo del plan original (sorlcur_term_code_ctlg)
-- Cantidad DESC, prioridad ASC para empate
-- =====================================================
LEFT JOIN (
    SELECT
        sub3.sfrstcr_pidm,
        sub3.smrpaap_program,
        sub3.sfrstcr_term_code,
        sub3.sorlcur_term_code_ctlg,
        sub3.smrpaap_area_priority AS nivel_estudiante
    FROM (
        SELECT
            sub2.*,
            ROW_NUMBER() OVER (
                PARTITION BY sub2.sfrstcr_pidm, sub2.smrpaap_program, sub2.sfrstcr_term_code,
                             sub2.sorlcur_term_code_ctlg
                ORDER BY sub2.qty_asig DESC, sub2.smrpaap_area_priority ASC
            ) AS rn_predominante
        FROM (
            SELECT
                sub1.sfrstcr_pidm,
                sub1.smrpaap_program,
                sub1.sfrstcr_term_code,
                sub1.sorlcur_term_code_ctlg,
                sub1.smrpaap_area_priority,
                COUNT(DISTINCT sub1.ssbsect_subj_code || '-' || sub1.ssbsect_crse_numb) AS qty_asig
            FROM (
                SELECT
                    fcr.sfrstcr_pidm,
                    cat.smrpaap_program,
                    fcr.sfrstcr_term_code,
                    rr.sorlcur_term_code_ctlg,
                    cat.smrpaap_area_priority,
                    sect.ssbsect_subj_code,
                    sect.ssbsect_crse_numb,
                    ROW_NUMBER() OVER (
                        PARTITION BY fcr.sfrstcr_pidm, cat.smrpaap_program, fcr.sfrstcr_term_code,
                                     sect.ssbsect_subj_code, sect.ssbsect_crse_numb
                        ORDER BY
                            ABS(CAST(cat.version_catalogo AS INTEGER) - CAST(rr.sorlcur_term_code_ctlg AS INTEGER)) ASC,
                            cat.version_catalogo DESC
                    ) AS rn_version
                FROM RankedReingreso rr
                INNER JOIN uss_datalake_stage.banner_oracle_saturn_sfrstcr fcr
                    ON fcr.sfrstcr_pidm = rr.sgrstsp_pidm
                    AND fcr.sfrstcr_rsts_code IN ('RE', 'RW')
                    AND fcr.sfrstcr_term_code >= '202400'     ------> PERIODO INSCRIPCIÓN A REVISAR
                    AND CAST(fcr.sfrstcr_term_code AS VARCHAR) > CAST(rr.sgrstsp_term_code_eff AS VARCHAR)
                INNER JOIN uss_datalake_stage.banner_oracle_saturn_ssbsect sect
                    ON sect.ssbsect_crn = fcr.sfrstcr_crn
                    AND sect.ssbsect_term_code = fcr.sfrstcr_term_code
                INNER JOIN catalogo_asignaturas cat
                    ON cat.smrpaap_program = rr.sorlcur_program
                    AND cat.smrarul_subj_code = sect.ssbsect_subj_code
                    AND cat.smrarul_crse_numb_low = sect.ssbsect_crse_numb
                WHERE rr.rn_reingreso = 1
            ) sub1
            WHERE sub1.rn_version = 1
            GROUP BY
                sub1.sfrstcr_pidm,
                sub1.smrpaap_program,
                sub1.sfrstcr_term_code,
                sub1.sorlcur_term_code_ctlg,
                sub1.smrpaap_area_priority
        ) sub2
    ) sub3
    WHERE sub3.rn_predominante = 1
) npe2
    ON npe2.sfrstcr_pidm = s2.sgrstsp_pidm
    AND npe2.smrpaap_program = s2.sorlcur_program
    AND CAST(npe2.sfrstcr_term_code AS VARCHAR) = CAST(s2.periodo_inscripcion AS VARCHAR)
    AND CAST(npe2.sorlcur_term_code_ctlg AS VARCHAR) = CAST(s2.sorlcur_term_code_ctlg AS VARCHAR)

LEFT JOIN programa_anterior pa2
    ON pa2.sorlcur_pidm = s2.sgrstsp_pidm
    AND pa2.programa_actual = s2.sorlcur_program
    AND CAST(pa2.periodo_consulta AS VARCHAR) = CAST(s2.periodo_inscripcion AS VARCHAR)
    AND pa2.rn = 1

LEFT JOIN matric_spiral_aux msa
    ON msa.sgrstsp_pidm = s2.sgrstsp_pidm
    AND msa.sorlcur_program = s2.sorlcur_program
    AND CAST(msa.periodo_inscripcion AS VARCHAR) = CAST(s2.periodo_inscripcion AS VARCHAR)

LEFT JOIN (
    SELECT DISTINCT
        tr.shrtrce_pidm,
        tr.shrtrce_subj_code
    FROM uss_datalake_stage.banner_oracle_saturn_shrtrce tr
    INNER JOIN (
        SELECT
            scbcrse_subj_code,
            scbcrse_crse_numb,
            scbcrse_dept_code,
            ROW_NUMBER() OVER (
                PARTITION BY scbcrse_subj_code, scbcrse_crse_numb
                ORDER BY scbcrse_eff_term DESC
            ) AS rn
        FROM uss_datalake_stage.banner_oracle_saturn_scbcrse
    ) crse
        ON crse.scbcrse_subj_code = tr.shrtrce_subj_code
        AND crse.scbcrse_crse_numb = tr.shrtrce_crse_numb
        AND crse.rn = 1
        AND (crse.scbcrse_dept_code IS NULL
             OR TRIM(crse.scbcrse_dept_code) = ''
             OR crse.scbcrse_dept_code != 'FORM')
) conv2
    ON conv2.shrtrce_pidm = s2.sgrstsp_pidm

LEFT JOIN (
    SELECT DISTINCT
        tr.shrtrce_pidm,
        cat.smrpaap_program,
        cat.version_catalogo
    FROM uss_datalake_stage.banner_oracle_saturn_shrtrit trit
    INNER JOIN uss_datalake_stage.banner_oracle_saturn_shrtrce tr
        ON tr.shrtrce_pidm = trit.shrtrit_pidm
        AND tr.shrtrce_trit_seq_no = trit.shrtrit_seq_no
    INNER JOIN catalogo_asignaturas cat
        ON cat.smrarul_subj_code = tr.shrtrce_subj_code
        AND cat.smrarul_crse_numb_low = tr.shrtrce_crse_numb
    WHERE trit.shrtrit_sbgi_code = 'ES39'
) sust2
    ON sust2.shrtrce_pidm = s2.sgrstsp_pidm
    AND sust2.smrpaap_program = s2.sorlcur_program
    AND CAST(sust2.version_catalogo AS VARCHAR) = CAST(s2.sorlcur_term_code_ctlg AS VARCHAR)

LEFT JOIN sam_matricula sam2
    ON CAST(sam2.academicperiod AS VARCHAR) = CAST(s2.periodo_inscripcion AS VARCHAR)
    AND sam2.careercode = rmajor2.sorcmjr_majr_code
    AND sam2.reportdata_campuscode = s2.sorlcur_camp_code
    AND sam2.rut = i2.spriden_id
    AND sam2.studentstatus = 'MATRICULADO'

LEFT JOIN eliminadas elim2
    ON elim2.sfrstca_pidm = s2.sgrstsp_pidm
    AND elim2.sfrstca_term_code = CAST(s2.periodo_inscripcion AS VARCHAR)
    AND elim2.sfrstca_stsp_key_sequence = CAST(s2.sgrstsp_key_seqno AS VARCHAR)

LEFT JOIN solicitudes_dedup sol2
    ON CAST(sol2.pidm_alumno AS VARCHAR) = CAST(s2.sgrstsp_pidm AS VARCHAR)
    AND sol2.cod_carrera = rmajor2.sorcmjr_majr_code
    AND CAST(sol2.periodo AS VARCHAR) = CAST(s2.periodo_inscripcion AS VARCHAR)
    AND sol2.rn = 1

WHERE
    s2.rn_plan_cercano = 1

ORDER BY
    "apellido",
    "nombre",
    "periodo_plan",
    "periodo_consulta";
