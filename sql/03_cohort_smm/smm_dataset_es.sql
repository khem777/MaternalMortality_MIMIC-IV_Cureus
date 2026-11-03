-- ============================================================================
-- Modelo B (SMM / near-miss): construir mimiciv.cohort_smm_dataset
-- ============================================================================
-- Agregado el 2026-10-08. Hasta ahora esta tabla solo estaba ESBOZADA en el notebook
-- (maternal_smm_models.ipynb, Sección 2.8, con el nivel K "omitido por
-- brevedad"), por lo que ningún script ejecutable la creaba con las 27 columnas de chart/lab
-- -- razón por la cual get_smm_cohort_query() fallaba con
--   UndefinedColumn: column "heart_rate" does not exist.
--
-- Este script es la versión completa y ejecutable. Mismo patrón de tres niveles que
-- mimiciv.cohort_maternal_dataset (maternal_mortality_models.ipynb, 2.4),
-- las mismas 27 variables / itemids (incl. la equivalencia de labevents del 2026-09-17), pero
-- obtenida a partir de la cohorte obstétrica EXPANDIDA + el desenlace SMM en lugar de
-- mimiciv.cohort_maternal.
--
-- REQUISITOS PREVIOS (ejecutar en este orden, una vez cada uno):
--   1. sql/02_cohort_mortality/maternal_cohort_expanded_es.sql
--        -> mimiciv.pregnancy_diagnoses_expanded
--   2. sql/03_cohort_smm/smm_cohort_es.sql (Pasos 1-3)
--        -> mimiciv.smm_code_patterns, hadm_with_smm, hadm_delivery_hospitalization
--   3. sql/02_cohort_mortality/maternal_diagnoses_group_load_es.sql y
--      maternal_diagnoses_group_assign_es.sql (catalog + propagación de gdg)
--
-- NOTA: esto ejecuta DROP y reconstruye la tabla. Puede ser lento (subconsultas correlacionadas
-- sobre chartevents/labevents para cada admisión, como en el Modelo A).
-- Ejecútelo como un script completo (DBeaver: Alt+X).
-- ============================================================================

DROP TABLE IF EXISTS mimiciv.cohort_smm_dataset;

CREATE TABLE mimiciv.cohort_smm_dataset AS
SELECT K.*
FROM
(
    SELECT Y.subject_id, Y.hadm_id, Y.stay_id, Y.dob, Y.age_at_admission
           , Y.ethnicity, Y.insurance, Y.language, Y.admission_type, Y.admission_location
           , Y.icu_stay, Y.icu_stay_count
           , Y.outcome_smm, Y.is_delivery_hospitalization
           , Y.cardiac_count, Y.renal_count, Y.respiratory_count, Y.hemorrhage_count
           , Y.sepsis_count, Y.other_obstetric_count, Y.other_medical_count
           , Y.primary_smm_category
       , (
        select max(c.valuenum)
        from   mimiciv.chartevents c
        where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
        and    c.stay_id    = Y.stay_id    and c.itemid  = 220045
        and    c.valuenum is not null
        and    c.charttime = (select min(c2.charttime) from mimiciv.chartevents c2
                              where  c2.subject_id = c.subject_id and c2.hadm_id = c.hadm_id
                              and    c2.stay_id    = c.stay_id    and c2.itemid  = 220045
                              and    c2.valuenum is not null)
       ) AS heart_rate
       , (
        select max(c.valuenum)
        from   mimiciv.chartevents c
        where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
        and    c.stay_id    = Y.stay_id    and c.itemid  = 220210
        and    c.valuenum is not null
        and    c.charttime = (select min(c2.charttime) from mimiciv.chartevents c2
                              where  c2.subject_id = c.subject_id and c2.hadm_id = c.hadm_id
                              and    c2.stay_id    = c.stay_id    and c2.itemid  = 220210
                              and    c2.valuenum is not null)
       ) AS respiratory_rate
       , (
        select max(c.valuenum)
        from   mimiciv.chartevents c
        where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
        and    c.stay_id    = Y.stay_id    and c.itemid  = 220277
        and    c.valuenum is not null
        and    c.charttime = (select min(c2.charttime) from mimiciv.chartevents c2
                              where  c2.subject_id = c.subject_id and c2.hadm_id = c.hadm_id
                              and    c2.stay_id    = c.stay_id    and c2.itemid  = 220277
                              and    c2.valuenum is not null)
       ) AS o2_saturation
       , (
        select max(c.valuenum)
        from   mimiciv.chartevents c
        where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
        and    c.stay_id    = Y.stay_id    and c.itemid  = 220181
        and    c.valuenum is not null
        and    c.charttime = (select min(c2.charttime) from mimiciv.chartevents c2
                              where  c2.subject_id = c.subject_id and c2.hadm_id = c.hadm_id
                              and    c2.stay_id    = c.stay_id    and c2.itemid  = 220181
                              and    c2.valuenum is not null)
       ) AS pressure_blood_mean
       , (
        select max(c.valuenum)
        from   mimiciv.chartevents c
        where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
        and    c.stay_id    = Y.stay_id    and c.itemid  = 220179
        and    c.valuenum is not null
        and    c.charttime = (select min(c2.charttime) from mimiciv.chartevents c2
                              where  c2.subject_id = c.subject_id and c2.hadm_id = c.hadm_id
                              and    c2.stay_id    = c.stay_id    and c2.itemid  = 220179
                              and    c2.valuenum is not null)
       ) AS pressure_blood_systolic
       , (
        select max(c.valuenum)
        from   mimiciv.chartevents c
        where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
        and    c.stay_id    = Y.stay_id    and c.itemid  = 220180
        and    c.valuenum is not null
        and    c.charttime = (select min(c2.charttime) from mimiciv.chartevents c2
                              where  c2.subject_id = c.subject_id and c2.hadm_id = c.hadm_id
                              and    c2.stay_id    = c.stay_id    and c2.itemid  = 220180
                              and    c2.valuenum is not null)
       ) AS pressure_blood_diastolic
       , (
        select max(c.valuenum)
        from   mimiciv.chartevents c
        where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
        and    c.stay_id    = Y.stay_id    and c.itemid  = 223761
        and    c.valuenum is not null
        and    c.charttime = (select min(c2.charttime) from mimiciv.chartevents c2
                              where  c2.subject_id = c.subject_id and c2.hadm_id = c.hadm_id
                              and    c2.stay_id    = c.stay_id    and c2.itemid  = 223761
                              and    c2.valuenum is not null)
       ) AS temperature_fahrenheit
       , (
        select max(c.valuenum)
        from   mimiciv.chartevents c
        where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
        and    c.stay_id    = Y.stay_id    and c.itemid  = 226512
        and    c.valuenum is not null
        and    c.charttime = (select min(c2.charttime) from mimiciv.chartevents c2
                              where  c2.subject_id = c.subject_id and c2.hadm_id = c.hadm_id
                              and    c2.stay_id    = c.stay_id    and c2.itemid  = 226512
                              and    c2.valuenum is not null)
       ) AS weight_admission
       , (
        -- primer valor de chartevents (solo UCI) O de labevents (todo el hospital)
        select combined.valuenum
        from (
            select c.valuenum, c.charttime from mimiciv.chartevents c
            where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
            and    c.stay_id    = Y.stay_id    and c.itemid  = 220621 and c.valuenum is not null
            union all
            select le.valuenum, le.charttime from mimiciv.labevents le
            where  le.subject_id = Y.subject_id and le.hadm_id = Y.hadm_id
            and    le.itemid     = 50931        and le.valuenum is not null
        ) combined
        order by combined.charttime asc
        limit 1
       ) AS glucose
       , (
        -- primer valor de chartevents (solo UCI) O de labevents (todo el hospital)
        select combined.valuenum
        from (
            select c.valuenum, c.charttime from mimiciv.chartevents c
            where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
            and    c.stay_id    = Y.stay_id    and c.itemid  = 220228 and c.valuenum is not null
            union all
            select le.valuenum, le.charttime from mimiciv.labevents le
            where  le.subject_id = Y.subject_id and le.hadm_id = Y.hadm_id
            and    le.itemid     = 51222        and le.valuenum is not null
        ) combined
        order by combined.charttime asc
        limit 1
       ) AS hemoglobine
       , (
        -- primer valor de chartevents (solo UCI) O de labevents (todo el hospital)
        select combined.valuenum
        from (
            select c.valuenum, c.charttime from mimiciv.chartevents c
            where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
            and    c.stay_id    = Y.stay_id    and c.itemid  = 220645 and c.valuenum is not null
            union all
            select le.valuenum, le.charttime from mimiciv.labevents le
            where  le.subject_id = Y.subject_id and le.hadm_id = Y.hadm_id
            and    le.itemid     = 50983        and le.valuenum is not null
        ) combined
        order by combined.charttime asc
        limit 1
       ) AS sodium
       , (
        -- primer valor de chartevents (solo UCI) O de labevents (todo el hospital)
        select combined.valuenum
        from (
            select c.valuenum, c.charttime from mimiciv.chartevents c
            where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
            and    c.stay_id    = Y.stay_id    and c.itemid  = 227442 and c.valuenum is not null
            union all
            select le.valuenum, le.charttime from mimiciv.labevents le
            where  le.subject_id = Y.subject_id and le.hadm_id = Y.hadm_id
            and    le.itemid     = 50971        and le.valuenum is not null
        ) combined
        order by combined.charttime asc
        limit 1
       ) AS potassium
       , (
        -- primer valor de chartevents (solo UCI) O de labevents (todo el hospital)
        select combined.valuenum
        from (
            select c.valuenum, c.charttime from mimiciv.chartevents c
            where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
            and    c.stay_id    = Y.stay_id    and c.itemid  = 225625 and c.valuenum is not null
            union all
            select le.valuenum, le.charttime from mimiciv.labevents le
            where  le.subject_id = Y.subject_id and le.hadm_id = Y.hadm_id
            and    le.itemid     = 50893        and le.valuenum is not null
        ) combined
        order by combined.charttime asc
        limit 1
       ) AS noionized_calcium
       , (
        -- primer valor de chartevents (solo UCI) O de labevents (todo el hospital)
        select combined.valuenum
        from (
            select c.valuenum, c.charttime from mimiciv.chartevents c
            where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
            and    c.stay_id    = Y.stay_id    and c.itemid  = 220635 and c.valuenum is not null
            union all
            select le.valuenum, le.charttime from mimiciv.labevents le
            where  le.subject_id = Y.subject_id and le.hadm_id = Y.hadm_id
            and    le.itemid     = 50960        and le.valuenum is not null
        ) combined
        order by combined.charttime asc
        limit 1
       ) AS magnesium
       , (
        -- primer valor de chartevents (solo UCI) O de labevents (todo el hospital)
        select combined.valuenum
        from (
            select c.valuenum, c.charttime from mimiciv.chartevents c
            where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
            and    c.stay_id    = Y.stay_id    and c.itemid  = 220602 and c.valuenum is not null
            union all
            select le.valuenum, le.charttime from mimiciv.labevents le
            where  le.subject_id = Y.subject_id and le.hadm_id = Y.hadm_id
            and    le.itemid     = 50902        and le.valuenum is not null
        ) combined
        order by combined.charttime asc
        limit 1
       ) AS chloride
       , (
        -- primer valor de chartevents (solo UCI) O de labevents (todo el hospital)
        select combined.valuenum
        from (
            select c.valuenum, c.charttime from mimiciv.chartevents c
            where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
            and    c.stay_id    = Y.stay_id    and c.itemid  = 227443 and c.valuenum is not null
            union all
            select le.valuenum, le.charttime from mimiciv.labevents le
            where  le.subject_id = Y.subject_id and le.hadm_id = Y.hadm_id
            and    le.itemid     = 50882        and le.valuenum is not null
        ) combined
        order by combined.charttime asc
        limit 1
       ) AS bicarbonate
       , (
        -- primer valor de chartevents (solo UCI) O de labevents (todo el hospital)
        select combined.valuenum
        from (
            select c.valuenum, c.charttime from mimiciv.chartevents c
            where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
            and    c.stay_id    = Y.stay_id    and c.itemid  = 225677 and c.valuenum is not null
            union all
            select le.valuenum, le.charttime from mimiciv.labevents le
            where  le.subject_id = Y.subject_id and le.hadm_id = Y.hadm_id
            and    le.itemid     = 50970        and le.valuenum is not null
        ) combined
        order by combined.charttime asc
        limit 1
       ) AS phosphorus
       , (
        -- primer valor de chartevents (solo UCI) O de labevents (todo el hospital)
        select combined.valuenum
        from (
            select c.valuenum, c.charttime from mimiciv.chartevents c
            where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
            and    c.stay_id    = Y.stay_id    and c.itemid  = 220615 and c.valuenum is not null
            union all
            select le.valuenum, le.charttime from mimiciv.labevents le
            where  le.subject_id = Y.subject_id and le.hadm_id = Y.hadm_id
            and    le.itemid     = 50912        and le.valuenum is not null
        ) combined
        order by combined.charttime asc
        limit 1
       ) AS creatine
       , (
        -- primer valor de chartevents (solo UCI) O de labevents (todo el hospital)
        select combined.valuenum
        from (
            select c.valuenum, c.charttime from mimiciv.chartevents c
            where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
            and    c.stay_id    = Y.stay_id    and c.itemid  = 220545 and c.valuenum is not null
            union all
            select le.valuenum, le.charttime from mimiciv.labevents le
            where  le.subject_id = Y.subject_id and le.hadm_id = Y.hadm_id
            and    le.itemid     = 51221        and le.valuenum is not null
        ) combined
        order by combined.charttime asc
        limit 1
       ) AS hematrocit
       , (
        -- primer valor de chartevents (solo UCI) O de labevents (todo el hospital)
        select combined.valuenum
        from (
            select c.valuenum, c.charttime from mimiciv.chartevents c
            where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
            and    c.stay_id    = Y.stay_id    and c.itemid  = 225668 and c.valuenum is not null
            union all
            select le.valuenum, le.charttime from mimiciv.labevents le
            where  le.subject_id = Y.subject_id and le.hadm_id = Y.hadm_id
            and    le.itemid     = 50813        and le.valuenum is not null
        ) combined
        order by combined.charttime asc
        limit 1
       ) AS lactic_acid
       , (
        select max(c.valuenum)
        from   mimiciv.chartevents c
        where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
        and    c.stay_id    = Y.stay_id    and c.itemid  = 220739
        and    c.valuenum is not null
        and    c.charttime = (select min(c2.charttime) from mimiciv.chartevents c2
                              where  c2.subject_id = c.subject_id and c2.hadm_id = c.hadm_id
                              and    c2.stay_id    = c.stay_id    and c2.itemid  = 220739
                              and    c2.valuenum is not null)
       ) AS gcs_eye_opening
       , (
        select max(c.valuenum)
        from   mimiciv.chartevents c
        where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
        and    c.stay_id    = Y.stay_id    and c.itemid  = 223900
        and    c.valuenum is not null
        and    c.charttime = (select min(c2.charttime) from mimiciv.chartevents c2
                              where  c2.subject_id = c.subject_id and c2.hadm_id = c.hadm_id
                              and    c2.stay_id    = c.stay_id    and c2.itemid  = 223900
                              and    c2.valuenum is not null)
       ) AS gcs_verbal_response
       , (
        select max(c.valuenum)
        from   mimiciv.chartevents c
        where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
        and    c.stay_id    = Y.stay_id    and c.itemid  = 223901
        and    c.valuenum is not null
        and    c.charttime = (select min(c2.charttime) from mimiciv.chartevents c2
                              where  c2.subject_id = c.subject_id and c2.hadm_id = c.hadm_id
                              and    c2.stay_id    = c.stay_id    and c2.itemid  = 223901
                              and    c2.valuenum is not null)
       ) AS gcs_motor_response
       , (
        select max(c.valuenum)
        from   mimiciv.chartevents c
        where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
        and    c.stay_id    = Y.stay_id    and c.itemid  = 228096
        and    c.valuenum is not null
        and    c.charttime = (select min(c2.charttime) from mimiciv.chartevents c2
                              where  c2.subject_id = c.subject_id and c2.hadm_id = c.hadm_id
                              and    c2.stay_id    = c.stay_id    and c2.itemid  = 228096
                              and    c2.valuenum is not null)
       ) AS richmond_ras_scale
       , (
        select max(c.valuenum)
        from   mimiciv.chartevents c
        where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
        and    c.stay_id    = Y.stay_id    and c.itemid  = 220339
        and    c.valuenum is not null
        and    c.charttime = (select min(c2.charttime) from mimiciv.chartevents c2
                              where  c2.subject_id = c.subject_id and c2.hadm_id = c.hadm_id
                              and    c2.stay_id    = c.stay_id    and c2.itemid  = 220339
                              and    c2.valuenum is not null)
       ) AS peep_set
       , (
        select max(c.valuenum)
        from   mimiciv.chartevents c
        where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
        and    c.stay_id    = Y.stay_id    and c.itemid  = 226730
        and    c.valuenum is not null
        and    c.charttime = (select min(c2.charttime) from mimiciv.chartevents c2
                              where  c2.subject_id = c.subject_id and c2.hadm_id = c.hadm_id
                              and    c2.stay_id    = c.stay_id    and c2.itemid  = 226730
                              and    c2.valuenum is not null)
       ) AS height
       , (
        -- primer valor de chartevents (solo UCI) O de labevents (todo el hospital)
        select combined.valuenum
        from (
            select c.valuenum, c.charttime from mimiciv.chartevents c
            where  c.subject_id = Y.subject_id and c.hadm_id = Y.hadm_id
            and    c.stay_id    = Y.stay_id    and c.itemid  = 227073 and c.valuenum is not null
            union all
            select le.valuenum, le.charttime from mimiciv.labevents le
            where  le.subject_id = Y.subject_id and le.hadm_id = Y.hadm_id
            and    le.itemid     = 50868        and le.valuenum is not null
        ) combined
        order by combined.charttime asc
        limit 1
       ) AS anion_gap
    FROM
    (
        SELECT am.subject_id, am.hadm_id
               , (SELECT MIN(i.stay_id) FROM mimiciv.icustays i
                   WHERE i.subject_id = am.subject_id AND i.hadm_id = am.hadm_id) AS stay_id
               , p.dob
               , am.approx_age AS age_at_admission
               , a.ethnicity, a.insurance, a.language, a.admission_type, a.admission_location
               , (EXISTS (SELECT 1 FROM mimiciv.icustays i
                           WHERE i.subject_id = am.subject_id AND i.hadm_id = am.hadm_id))::int AS icu_stay
               , (SELECT COUNT(1) FROM mimiciv.icustays i
                   WHERE i.subject_id = am.subject_id AND i.hadm_id = am.hadm_id) AS icu_stay_count
               , (CASE WHEN smm.hadm_id IS NOT NULL THEN 1 ELSE 0 END)  AS outcome_smm
               , (CASE WHEN dh.hadm_id  IS NOT NULL THEN 1 ELSE 0 END)  AS is_delivery_hospitalization
               , COALESCE(cat.cardiac_count, 0)         AS cardiac_count
               , COALESCE(cat.renal_count, 0)           AS renal_count
               , COALESCE(cat.respiratory_count, 0)     AS respiratory_count
               , COALESCE(cat.hemorrhage_count, 0)      AS hemorrhage_count
               , COALESCE(cat.sepsis_count, 0)          AS sepsis_count
               , COALESCE(cat.other_obstetric_count, 0) AS other_obstetric_count
               , COALESCE(cat.other_medical_count, 0)   AS other_medical_count
               , CASE WHEN smm.hadm_id IS NULL THEN 'No_SMM'
                      ELSE cat.primary_category END      AS primary_smm_category
        FROM (
                -- maternal_admissions (cohorte obstétrica expandida)
                SELECT DISTINCT a.subject_id, a.hadm_id,
                       p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) AS approx_age
                FROM mimiciv.admissions a
                JOIN mimiciv.patients p ON a.subject_id = p.subject_id
                WHERE p.gender = 'F'
                  AND p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) BETWEEN 12 AND 55
                  AND (a.subject_id, a.hadm_id) IN (
                        SELECT d.subject_id, d.hadm_id FROM mimiciv.diagnoses_icd d
                        JOIN mimiciv.pregnancy_diagnoses_expanded de
                          ON d.icd_code = de.icd_code AND d.icd_version = de.icd_version)
             ) am
        JOIN mimiciv.admissions a ON a.subject_id = am.subject_id AND a.hadm_id = am.hadm_id
        JOIN mimiciv.patients   p ON p.subject_id = am.subject_id
        LEFT JOIN mimiciv.hadm_delivery_hospitalization dh
               ON dh.subject_id = am.subject_id AND dh.hadm_id = am.hadm_id
        LEFT JOIN ( SELECT DISTINCT subject_id, hadm_id FROM mimiciv.hadm_with_smm ) smm
               ON smm.subject_id = am.subject_id AND smm.hadm_id = am.hadm_id
        LEFT JOIN (
                SELECT subject_id, hadm_id
                       , COUNT(DISTINCT indicator_name) FILTER (WHERE indicator_group = 'Cardiac')          AS cardiac_count
                       , COUNT(DISTINCT indicator_name) FILTER (WHERE indicator_group = 'Renal')            AS renal_count
                       , COUNT(DISTINCT indicator_name) FILTER (WHERE indicator_group = 'Respiratory')      AS respiratory_count
                       , COUNT(DISTINCT indicator_name) FILTER (WHERE indicator_group = 'Hemorrhage')       AS hemorrhage_count
                       , COUNT(DISTINCT indicator_name) FILTER (WHERE indicator_group = 'Sepsis')           AS sepsis_count
                       , COUNT(DISTINCT indicator_name) FILTER (WHERE indicator_group = 'Other_Obstetric')  AS other_obstetric_count
                       , COUNT(DISTINCT indicator_name) FILTER (WHERE indicator_group = 'Other_Medical')    AS other_medical_count
                       , MODE() WITHIN GROUP (ORDER BY indicator_group)                                     AS primary_category
                FROM mimiciv.hadm_with_smm
                GROUP BY subject_id, hadm_id
        ) cat ON cat.subject_id = am.subject_id AND cat.hadm_id = am.hadm_id
    ) Y
) K;

ALTER TABLE mimiciv.cohort_smm_dataset ADD CONSTRAINT pk_cohort_smm_dataset PRIMARY KEY (subject_id, hadm_id);

-- Columnas indicadoras de grupos diagnósticos (las mismas 28 del Modelo A)
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m01 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m02 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m03 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m04 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m05 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m06 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m07 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m08 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m09 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m10 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m11 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m12 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m13 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m14 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m15 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m16 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m17 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m18 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m19 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m20 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m21 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m22 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m23 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m24 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m25 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m26 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m27 boolean;
ALTER TABLE mimiciv.cohort_smm_dataset ADD COLUMN gdg_m28 boolean;

-- Propagación de las banderas gdg_m* (misma lógica que la función del Modelo A, apuntando
-- a cohort_smm_dataset; lee las mismas tablas de catalog/mapeo).
CREATE OR REPLACE FUNCTION mimiciv.update_feature_diagnoses_cohort_smm_dataset()
RETURNS void AS $$
DECLARE
    g RECORD;
BEGIN
    FOR g IN SELECT group_code FROM mimiciv.maternal_diagnoses_group_catalog ORDER BY display_order
    LOOP
        EXECUTE format('UPDATE mimiciv.cohort_smm_dataset SET %I = FALSE', lower(g.group_code));
        EXECUTE format($f$
            UPDATE mimiciv.cohort_smm_dataset ds
            SET    %I = TRUE
            WHERE  EXISTS (
                SELECT 1
                FROM   mimiciv.diagnoses_icd di
                JOIN   mimiciv.cohort_maternal_diagnoses cmd
                  ON   di.icd_code = cmd.icd_code AND di.icd_version = cmd.icd_version
                WHERE  di.subject_id      = ds.subject_id
                AND    di.hadm_id         = ds.hadm_id
                AND    di.seq_num       <= 4
                AND    cmd.diagnoses_group = %L
            )
        $f$, lower(g.group_code), g.group_code);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Poblar las banderas (ejecutar después de que el CREATE TABLE anterior haya terminado):
SELECT mimiciv.update_feature_diagnoses_cohort_smm_dataset();

-- Verificaciones de consistencia -- compartir estos resultados:
-- SELECT COUNT(*) AS n_rows, SUM(outcome_smm) AS n_smm,
--        SUM(is_delivery_hospitalization) AS n_delivery,
--        COUNT(heart_rate) AS n_heart_rate, COUNT(glucose) AS n_glucose
-- FROM mimiciv.cohort_smm_dataset;
