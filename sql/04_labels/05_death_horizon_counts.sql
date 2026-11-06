-- ============================================================================
-- 04_labels / 05_death_horizon_counts.sql
-- How many deaths would a fixed follow-up horizon add? 
-- Framework: E3 and gate P3: maternal death (ladder rung 1) with fixed follow-up horizons; feasibility counts.
-- ============================================================================
-- Question: with the same-admission label there are 10 deaths (4 in delivery
--   hospitalizations).  A later-death outcome needs
--   a justified horizon.  The WHO definition of maternal death covers up to 42 days
--   after the end of pregnancy (late maternal deaths: up to 1 year).  This script
--   COUNTS how many obstetric admissions have a recorded death within 42, 90 and
--   365 days of ADMISSION (delivery admissions are short, so admission date
--   approximates the end of pregnancy).  It changes no label and no dataset.
--
-- Two possible sources of a death date:
--   (1) mimiciv.admissions.deathtime of ANY admission of the patient (in-hospital
--       deaths, including readmissions outside the obstetric cohort);
--   (2) mimiciv.patients.dod (state records, up to 1 year after the last discharge),
--       ONLY IF that column exists in your copy.  The schema script of this project
--       (mimic_create_database.sql) creates PATIENTS without it, so Q-E0 checks it.
--
-- Interpretation caveats (to be stated in the manuscript if this outcome is used):
--   * Deaths out of hospital are only visible through dod.  Without dod the count is
--     a lower bound for the horizon outcomes.
--   * Death within a horizon is ALL-CAUSE death, not maternal-cause death.
--   * Several admissions of one patient can fall within the same horizon of one death.
--
-- Requires 03 and 04 (mimiciv.cohort_obstetric_v2).  Creates one new view
--   (mimiciv.death_events_v2).  Aggregate counts only: share the results of the count
--   queries, never row-level data.
-- ============================================================================

-- Q-E0  Does patients.dod exist in this copy, and how populated is it?
SELECT EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'mimiciv' AND table_name = 'patients' AND column_name = 'dod') AS patients_has_dod;

-- ----------------------------------------------------------------------------
-- Step 1 -- one row per recorded death date, with its source
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS mimiciv.death_events_v2;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'mimiciv' AND table_name = 'patients' AND column_name = 'dod') THEN
        EXECUTE $v$
            CREATE VIEW mimiciv.death_events_v2 AS
            SELECT subject_id, deathtime::date AS death_date, 'admission deathtime'::text AS source
            FROM mimiciv.admissions WHERE deathtime IS NOT NULL
            UNION ALL
            SELECT subject_id, dod::date, 'patients.dod'
            FROM mimiciv.patients WHERE dod IS NOT NULL
        $v$;
    ELSE
        EXECUTE $v$
            CREATE VIEW mimiciv.death_events_v2 AS
            SELECT subject_id, deathtime::date AS death_date, 'admission deathtime'::text AS source
            FROM mimiciv.admissions WHERE deathtime IS NOT NULL
        $v$;
    END IF;
END $$;

-- ============================================================================
-- COUNT QUERIES (aggregate only) -- run each and paste the result
-- ============================================================================

-- Q-E1  Deaths recorded within a horizon of the admission date, obstetric admissions
--       (admissions counted once; a patient can have several admissions in the window)
WITH base AS (
    SELECT c.subject_id, c.hadm_id, c.is_delivery_v2, c.died_same_admission,
           a.admittime::date AS admit_date
    FROM mimiciv.cohort_obstetric_v2 c
    JOIN mimiciv.admissions a ON a.hadm_id = c.hadm_id
),
flag AS (
    SELECT b.*,
           h.horizon_days,
           EXISTS (SELECT 1 FROM mimiciv.death_events_v2 e
                   WHERE e.subject_id = b.subject_id
                     AND e.death_date BETWEEN b.admit_date AND b.admit_date + h.horizon_days) AS dead_in_horizon,
           EXISTS (SELECT 1 FROM mimiciv.death_events_v2 e
                   WHERE e.subject_id = b.subject_id AND e.source = 'admission deathtime'
                     AND e.death_date BETWEEN b.admit_date AND b.admit_date + h.horizon_days) AS dead_in_horizon_hospital_record
    FROM base b
    CROSS JOIN (VALUES (42), (90), (365)) AS h(horizon_days)
)
SELECT horizon_days,
       COUNT(*) FILTER (WHERE dead_in_horizon)                                           AS n_admissions_any_source,
       COUNT(DISTINCT subject_id) FILTER (WHERE dead_in_horizon)                         AS n_patients_any_source,
       COUNT(*) FILTER (WHERE dead_in_horizon AND is_delivery_v2)                        AS n_admissions_delivery,
       COUNT(DISTINCT subject_id) FILTER (WHERE dead_in_horizon AND is_delivery_v2)      AS n_patients_delivery,
       COUNT(*) FILTER (WHERE dead_in_horizon_hospital_record)                           AS n_admissions_hospital_record_only_source,
       COUNT(DISTINCT subject_id) FILTER (WHERE dead_in_horizon_hospital_record)         AS n_patients_hospital_record_only_source,
       COUNT(*) FILTER (WHERE dead_in_horizon AND NOT died_same_admission)               AS n_added_beyond_same_admission,
       COUNT(DISTINCT subject_id) FILTER (WHERE dead_in_horizon AND NOT died_same_admission) AS n_patients_added_beyond_same_adm
FROM flag
GROUP BY horizon_days ORDER BY horizon_days;

-- Q-E2  Reference row: the current label (death during the same admission)
SELECT COUNT(*)                                                    AS n_admissions_same_admission_death,
       COUNT(DISTINCT subject_id)                                  AS n_patients,
       COUNT(*) FILTER (WHERE is_delivery_v2)                      AS n_delivery
FROM mimiciv.cohort_obstetric_v2
WHERE died_same_admission;

-- Q-E3  Source of the death dates in the whole cohort (how much does dod add, if it exists)
SELECT e.source,
       COUNT(DISTINCT e.subject_id) AS n_patients_with_a_death_date
FROM mimiciv.death_events_v2 e
WHERE e.subject_id IN (SELECT subject_id FROM mimiciv.cohort_obstetric_v2)
GROUP BY e.source ORDER BY e.source;

-- Q-E4  Days from admission to death for the 365-day group: how the added deaths are spread
--       (any source; one row per patient, the first death after the admission, any admission)
WITH first_d AS (
    SELECT c.subject_id, c.hadm_id, c.is_delivery_v2, c.died_same_admission,
           MIN(e.death_date - a.admittime::date) AS days_to_death
    FROM mimiciv.cohort_obstetric_v2 c
    JOIN mimiciv.admissions a ON a.hadm_id = c.hadm_id
    JOIN mimiciv.death_events_v2 e
      ON e.subject_id = c.subject_id AND e.death_date >= a.admittime::date
    GROUP BY c.subject_id, c.hadm_id, c.is_delivery_v2, c.died_same_admission
)
SELECT CASE WHEN days_to_death <= 0   THEN '0 (same day as admission)'
            WHEN days_to_death <= 42  THEN '1-42'
            WHEN days_to_death <= 90  THEN '43-90'
            WHEN days_to_death <= 365 THEN '91-365'
            ELSE 'more than 365' END                    AS days_from_admission_to_death,
       COUNT(*)                                          AS n_admissions,
       COUNT(DISTINCT subject_id)                        AS n_patients
FROM first_d
GROUP BY 1 ORDER BY MIN(days_to_death);
