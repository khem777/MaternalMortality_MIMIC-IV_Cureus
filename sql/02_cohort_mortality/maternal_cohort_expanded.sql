-- ============================================================================
-- STATUS (2026-10-25): obstetric cohort of the first version of the analysis (v1)
-- ============================================================================
-- The header below was written before this script was run. It was later run on
-- the local database: the v1 manuscript (25,736 obstetric admissions,
-- 15,084 patients) and the audit in sql/06_audit_counts/ are based on it. The
-- current analysis keeps this cohort and does not apply a position rule (D6); delivery
-- hospitalizations are identified with sql/04_labels/02_delivery_flag.sql.
-- The date filter below is commented out and was never applied to this cohort.
-- Only comments were edited in this file; no SQL statement was changed.
-- ============================================================================

-- ============================================================================
-- EXPANDED MATERNAL COHORT -- candidates to increase the N of deaths
-- ============================================================================
-- Spanish version of this script: maternal_cohort_expanded_es.sql (same folder).
--
-- Goal: expand the original cohort (23,474 admissions with an obstetric text match,
-- 23,471 after keeping women only, 36 deaths) by applying 3 of the 4 levers discussed
-- while debugging the neonatal cohort. The 4th (a composite "near-miss"
-- outcome) is handled separately -- see sql/03_cohort_smm/smm_cohort.sql
-- -- because it changes the research question and needed its own agreed-upon
-- indicator list.
--
-- Levers applied here:
--   (1) Drop the mandatory JOIN with icustays -> use EVERY hospital
--       admission (hosp module), not only ones that went through the ICU.
--       An "had_icu_stay" flag is kept so this can still be filtered/
--       compared afterward.
--   (2) Drop the 2021-10 to 2022-10 date restriction (inherited from the
--       neonatal model, with no known justification for the maternal
--       cohort). Left as an optional, commented-out filter in case your
--       MIMIC-IV demo/access environment only has data in a certain range.
--   (3) Expand obstetric-diagnosis detection: in addition to the ILIKE text
--       match (PREGNANCY/OBSTETRIC/FETAL/DELIVERY), also match by ICD
--       chapter/range (ICD-9: 630-679, V22-V24, V27, V28; ICD-10: chapter
--       O00-O9A, Z33/Z34/Z37/Z39), which can catch obstetric codes whose
--       long title doesn't contain those words.
--
-- (Original note, superseded by the STATUS block at the top: the script has since
-- been run on the local database.)
--
-- KNOWN POSSIBLE BUG to check in the original exploratory script: the
-- condition "TO_CHAR(a.admittime,'YYYYMM') <= '221410'" has month '14',
-- which doesn't exist. It was probably meant to be '221031' (31-Oct-2022).
-- It no longer applies here because the date filter was removed, but if
-- you re-enable it, double check that value.
--
-- CORRECTION (v2, from a finding of the exploratory analysis): the PATIENTS table in this
-- schema defines `dob` explicitly as "This is a NaN column" (see
-- sql/01_load_mimic_iv_schema/mimic_create_database.sql) -- it was only
-- ever populated for the cases the neonatal pipeline updated with a
-- synthetic "baby's date of birth", not as a real demographic field for
-- each adult patient. Using it to compute the mother's age filters the
-- cohort incorrectly: the age condition evaluates to NULL for every mother
-- whose `dob` was never populated, so those admissions are silently excluded
-- (in the maternal cohort this removed essentially all rows).
--
-- The correct way to estimate age in MIMIC-IV is ANCHOR_AGE / ANCHOR_YEAR
-- (populated for every patient -- it's MIMIC-IV's official
-- de-identification mechanism): ANCHOR_AGE is the patient's age during
-- ANCHOR_YEAR, and every date for that patient is shifted consistently
-- relative to that year. So:
--   age_at_admission = anchor_age + (year(admittime) - anchor_year)
-- (Known limitation: patients who were ever older than 89 are capped at
-- anchor_age = 91 for de-identification; this doesn't meaningfully affect
-- the 12-55 range we care about here.)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Step 1: expanded universe of obstetric diagnoses (text + ICD range)
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS mimiciv.pregnancy_diagnoses_expanded;

CREATE VIEW mimiciv.pregnancy_diagnoses_expanded AS
SELECT DISTINCT icd_code, icd_version, long_title
FROM mimiciv.d_icd_diagnoses
WHERE
    -- (a) Original text match on the long title (either ICD version)
    long_title ILIKE '%PREGNAN%'
    OR long_title ILIKE '%OBSTETRIC%'
    OR long_title ILIKE '%FETAL%'
    OR long_title ILIKE '%DELIVERY%'
    OR long_title ILIKE '%PUERPERIUM%'
    OR long_title ILIKE '%POSTPARTUM%'
    OR long_title ILIKE '%GESTATION%'

    -- (b) ICD-9 chapter range: pregnancy/delivery/puerperium complications
    --     (630-679) and V-codes for pregnancy/delivery supervision
    --     (V22-V24, V27, V28)
    OR (
        icd_version = 9
        AND icd_code ~ '^[0-9]'
        AND LEFT(icd_code, 3)::int BETWEEN 630 AND 679
    )
    OR (
        icd_version = 9
        AND LEFT(icd_code, 3) IN ('V22', 'V23', 'V24', 'V27', 'V28')
    )

    -- (c) Full ICD-10 obstetric chapter (O00-O9A) + Z-codes for pregnancy
    --     state / delivery outcome / postpartum care
    OR (
        icd_version = 10
        AND LEFT(icd_code, 1) = 'O'
    )
    OR (
        icd_version = 10
        AND (icd_code LIKE 'Z33%' OR icd_code LIKE 'Z34%'
             OR icd_code LIKE 'Z37%' OR icd_code LIKE 'Z39%')
    );

-- Quick check: number of codes in the expanded view
-- SELECT count(*) FROM mimiciv.pregnancy_diagnoses_expanded;

-- ----------------------------------------------------------------------------
-- Step 2: expanded cohort (no ICU stay required, no date restriction)
-- ----------------------------------------------------------------------------
WITH maternal_admissions AS (
    SELECT DISTINCT
        a.subject_id,
        a.hadm_id,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        a.admittime,
        a.dischtime,
        a.deathtime            AS admission_deathtime,
        a.hospital_expire_flag,
        -- Real age at the time of admission (do not use p.dob, see note above)
        p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) AS approx_age
    FROM mimiciv.admissions a
    JOIN mimiciv.patients p
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) BETWEEN 12 AND 55
      AND (a.subject_id, a.hadm_id) IN (
            SELECT d.subject_id, d.hadm_id
            FROM mimiciv.diagnoses_icd d
            JOIN mimiciv.pregnancy_diagnoses_expanded de
              ON d.icd_code = de.icd_code
             AND d.icd_version = de.icd_version
      )
      -- Original date filter, commented out. Uncomment only if your
      -- MIMIC-IV instance requires narrowing the range:
      -- AND a.admittime BETWEEN '2021-10-01' AND '2022-10-31'
),
final_cohort AS (
    SELECT
        ma.subject_id,
        ma.hadm_id,
        ma.gender,
        ma.admittime,
        ma.approx_age,
        EXISTS (
            SELECT 1 FROM mimiciv.icustays i
            WHERE i.subject_id = ma.subject_id AND i.hadm_id = ma.hadm_id
        ) AS had_icu_stay,
        -- outcome: same logic as the original script -> died during this
        -- admission or during any later admission with a recorded deathtime
        (
            CASE
                WHEN ma.admission_deathtime IS NOT NULL THEN ma.admission_deathtime
                ELSE (
                    SELECT MIN(a5.deathtime)
                    FROM mimiciv.admissions a5
                    WHERE a5.subject_id = ma.subject_id
                      AND a5.deathtime IS NOT NULL
                )
            END
        ) AS resolved_deathtime
    FROM maternal_admissions ma
)
SELECT
    COUNT(*)                                                   AS total_admissions,
    COUNT(*) FILTER (WHERE had_icu_stay)                       AS with_icu,
    COUNT(*) FILTER (WHERE NOT had_icu_stay)                   AS without_icu,
    COUNT(*) FILTER (WHERE resolved_deathtime IS NOT NULL)     AS total_deaths,
    COUNT(*) FILTER (WHERE resolved_deathtime IS NOT NULL
                      AND had_icu_stay)                        AS deaths_with_icu,
    COUNT(*) FILTER (WHERE resolved_deathtime IS NOT NULL
                      AND NOT had_icu_stay)                    AS deaths_without_icu
FROM final_cohort;

-- For the row-by-row detail (to inspect before deciding), run this instead
-- of the SELECT above:
-- SELECT * FROM final_cohort ORDER BY resolved_deathtime NULLS LAST;
