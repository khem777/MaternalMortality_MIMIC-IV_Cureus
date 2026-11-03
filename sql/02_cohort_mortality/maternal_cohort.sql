-- ============================================================================
-- Maternal cohort (mortality model): mimiciv.cohort_maternal
-- ============================================================================
-- One row per hospital admission of a woman aged 12-55 years with at least one
-- obstetric / pregnancy-related diagnosis.
--
-- Inclusion: gender = 'F'; diagnosis in mimiciv.pregnancy_diagnoses_expanded
-- (text match + ICD-9 630-679, V22-V24, V27, V28 + ICD-10 chapter O, Z33, Z34,
-- Z37, Z39); admission date within the date-shifted window YYYYMM 211001-221410 (see notes);
-- age at admission = anchor_age + (admission year - anchor_year) between 12 and 55.
-- No ICU stay is required (icu_stay and icu_stay_count are kept as features).
--
-- Outcome: outcome = 1 if the admission, or any later admission of the same
-- subject_id, has a recorded deathtime (person-level death flag).
--
-- Notes:
--   * The date condition is TO_CHAR(admittime, 'YYYYMM') >= '211001' AND <= '221410'. Month 14 does
--     not exist (probably meant '221031'), so the upper bound excludes almost nothing in practice.
--     It is kept as written because the validated cohort (25,736 admissions) was built with this
--     exact condition; changing it would change the cohort. maternal_cohort_expanded.sql applies no date filter.
--   * patients.dob is not populated for adults in this schema, so age is computed
--     from anchor_age / anchor_year. The column `dob` is kept as NULL only so that
--     libraries/database.py (which selects `dob`) keeps working.
--   * Expected size: 25,736 admissions, 41 with outcome = 1.
--
-- PREREQUISITE: sql/02_cohort_mortality/maternal_cohort_expanded.sql
--   (creates mimiciv.pregnancy_diagnoses_expanded).
-- NEXT: maternal_cohort_dataset.sql and maternal_cohort_diagnoses.sql.
-- ============================================================================

-- NOTE: plain CREATE TABLE (no DROP): it fails if mimiciv.cohort_maternal already exists.
-- Drop it yourself, deliberately, if you need to rebuild it.

CREATE TABLE mimiciv.cohort_maternal AS
WITH maternal_admissions AS (
    SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.deathtime,
           a.ethnicity, a.insurance, a.language, a.admission_type, a.admission_location,
           p.anchor_age, p.anchor_year, p.gender
    FROM   mimiciv.admissions a
    JOIN   mimiciv.patients p
      ON   p.subject_id = a.subject_id
    JOIN   mimiciv.diagnoses_icd di
      ON   di.subject_id = a.subject_id
     AND   di.hadm_id    = a.hadm_id
    JOIN   mimiciv.pregnancy_diagnoses_expanded de
      ON   de.icd_code    = di.icd_code
     AND   de.icd_version = di.icd_version
    WHERE  p.gender = 'F'
    AND    TO_CHAR(a.admittime, 'YYYYMM') >= '211001'
    AND    TO_CHAR(a.admittime, 'YYYYMM') <= '221410'
    AND    p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) BETWEEN 12 AND 55
),
maternal_icu AS (
    SELECT  ma.*
           , (SELECT MIN(i.stay_id)   FROM mimiciv.icustays i
               WHERE i.subject_id = ma.subject_id AND i.hadm_id = ma.hadm_id) AS stay_id
           , (SELECT COUNT(1)        FROM mimiciv.icustays i
               WHERE i.subject_id = ma.subject_id AND i.hadm_id = ma.hadm_id) AS icu_stay_count
    FROM   maternal_admissions ma
)
SELECT  mi.subject_id
       , mi.hadm_id
       , mi.stay_id
       , NULL::timestamp AS dob
       , mi.admittime
       , mi.ethnicity
       , mi.insurance
       , mi.language
       , mi.admission_type
       , mi.admission_location
       , mi.icu_stay_count
       , (CASE WHEN mi.icu_stay_count > 0 THEN 1 ELSE 0 END) AS icu_stay
       , mi.anchor_age + (DATE_PART('year', mi.admittime) - mi.anchor_year) AS age_at_admission
       , (
            CASE WHEN mi.deathtime IS NULL
                 THEN (CASE WHEN (SELECT MIN(a2.deathtime)
                                    FROM   mimiciv.admissions a2
                                   WHERE  a2.subject_id = mi.subject_id
                                     AND  a2.deathtime IS NOT NULL) IS NOT NULL
                            THEN 1 ELSE 0 END)
                 ELSE 1
            END
         ) AS outcome
FROM   maternal_icu mi;

ALTER TABLE mimiciv.cohort_maternal ADD CONSTRAINT pk_cohort_maternal PRIMARY KEY (subject_id, hadm_id);
