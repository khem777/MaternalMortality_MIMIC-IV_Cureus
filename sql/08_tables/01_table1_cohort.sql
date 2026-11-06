-- ============================================================================
-- 08_tables / 01_table1_cohort.sql
-- Table 1 of the manuscript: characteristics of the eligible delivery
-- hospitalizations (main analysis), overall and by SMM status.
-- Framework: E11 Reporting (descriptive table of the population fixed at gates P1 and P2).
-- ============================================================================
-- Population: eligible delivery hospitalizations (is_delivery_v2 AND eligible_24h):
--   expected 19,383 admissions, 13,710 patients, 445 with SMM.
-- READ-ONLY: SELECTs only. Every cell is an aggregate; counts from 1 to 9 are
-- shown as '<10' and their percentage is left blank (small-cell suppression).
-- Predictor values use the same plausibility limits as the dictionary
-- (hemoglobin 3-20 g/dL, creatinine 0.1-20 mg/dL); no eligible value falls outside.
-- Requires: mimiciv.predictors_24h_v2 (05_predictors) and mimiciv.timing_flags_v3
-- (07_timing_audit/01_timing_flags_v3.sql).
-- Run each query (Q-T1a, Q-T1b, Q-T1c) and share the result grids.
-- Sparse categories are grouped so that no cell below 10 can be recovered by
-- subtraction; in-hospital death (three events) is reported in the text, not in Table 1.
-- ============================================================================
SET max_parallel_workers_per_gather = 0;

-- ----------------------------------------------------------------------------
-- Q-T1a  Categorical characteristics: n (%) overall, with SMM and without SMM
-- ----------------------------------------------------------------------------
WITH base AS (
    SELECT p.hadm_id, p.subject_id, p.smm_any, p.age_at_admission,
           p.ethnicity, p.insurance, p.language, p.admission_type, p.admission_location,
           p.icu_in_24h, p.died_same_admission,
           CASE WHEN p.hemoglobin BETWEEN 3 AND 20 THEN p.hemoglobin END   AS hgb,
           CASE WHEN p.creatinine BETWEEN 0.1 AND 20 THEN p.creatinine END AS creat,
           t.year_lo, t.year_hi, t.smm_timing_class,
           (SELECT MAX(d.icd_version) FROM mimiciv.diagnoses_icd d WHERE d.hadm_id = p.hadm_id) AS icd_version
    FROM mimiciv.predictors_24h_v2 p
    LEFT JOIN mimiciv.timing_flags_v3 t ON t.hadm_id = p.hadm_id
    WHERE p.is_delivery_v2 AND p.eligible_24h
),
long AS (
    SELECT hadm_id, smm_any, '01 Age group, years' AS variable,
           CASE WHEN age_at_admission < 25 THEN '<25' WHEN age_at_admission < 35 THEN '25-34'
                WHEN age_at_admission < 40 THEN '35-39' ELSE '>=40' END AS category FROM base
    UNION ALL
    SELECT hadm_id, smm_any, '02 Race and ethnicity',
           CASE WHEN UPPER(COALESCE(ethnicity, '')) LIKE 'WHITE%' THEN 'White'
                WHEN UPPER(COALESCE(ethnicity, '')) LIKE 'BLACK%' THEN 'Black'
                WHEN UPPER(COALESCE(ethnicity, '')) LIKE 'HISPANIC%' OR UPPER(COALESCE(ethnicity, '')) LIKE 'SOUTH AMERICAN%' THEN 'Hispanic/Latina'
                WHEN UPPER(COALESCE(ethnicity, '')) LIKE 'ASIAN%' THEN 'Asian'
                WHEN UPPER(COALESCE(ethnicity, '')) IN ('', 'UNKNOWN', 'UNABLE TO OBTAIN', 'PATIENT DECLINED TO ANSWER') THEN 'Unknown or declined'
                ELSE 'Other' END FROM base
    UNION ALL
    SELECT hadm_id, smm_any, '03 Insurance',
           CASE WHEN insurance = 'Private' THEN 'Private' WHEN insurance = 'Medicaid' THEN 'Medicaid'
                ELSE 'Medicare, other or missing' END FROM base
    UNION ALL
    SELECT hadm_id, smm_any, '04 Language',
           CASE WHEN UPPER(COALESCE(language, '')) = 'ENGLISH' THEN 'English' ELSE 'Other or missing' END FROM base
    UNION ALL
    SELECT hadm_id, smm_any, '05 Admission type',
           CASE WHEN admission_type = 'URGENT' THEN 'Urgent'
                WHEN admission_type IN ('DIRECT EMER.', 'EW EMER.') THEN 'Emergency'
                ELSE 'Observation, elective or other' END FROM base
    UNION ALL
    SELECT hadm_id, smm_any, '06 Admission location',
           CASE WHEN admission_location = 'PHYSICIAN REFERRAL' THEN 'Physician referral'
                WHEN admission_location IN ('EMERGENCY ROOM', 'TRANSFER FROM HOSPITAL') THEN 'Emergency room or transfer from another hospital'
                ELSE 'Other or not available' END FROM base
    UNION ALL
    SELECT hadm_id, smm_any, '07 ICD version of the admission', COALESCE('ICD-' || icd_version::text, 'Missing') FROM base
    UNION ALL
    SELECT hadm_id, smm_any, '08 Approximate calendar period',
           CASE WHEN year_hi < 2017 THEN 'Before 2017' WHEN year_lo >= 2017 THEN '2017 or later'
                WHEN year_lo IS NULL THEN 'Missing' ELSE 'Interval straddles 2017' END FROM base
    UNION ALL
    SELECT hadm_id, smm_any, '09 ICU admission before 24 h', CASE WHEN icu_in_24h THEN 'Yes' ELSE 'No' END FROM base
    UNION ALL
    SELECT hadm_id, smm_any, '10 Hemoglobin measured by 24 h', CASE WHEN hgb IS NOT NULL THEN 'Yes' ELSE 'No' END FROM base
    UNION ALL
    SELECT hadm_id, smm_any, '11 Creatinine measured by 24 h', CASE WHEN creat IS NOT NULL THEN 'Yes' ELSE 'No' END FROM base
    UNION ALL
    SELECT hadm_id, smm_any, '13 SMM timing class (SMM only)', COALESCE(smm_timing_class, 'Missing') FROM base WHERE smm_any
),
tot AS (
    SELECT COUNT(*) AS n_all, COUNT(*) FILTER (WHERE smm_any) AS n_smm, COUNT(*) FILTER (WHERE NOT smm_any) AS n_no FROM base
),
agg AS (
    SELECT variable, category,
           COUNT(*)                              AS n_all,
           COUNT(*) FILTER (WHERE smm_any)       AS n_smm,
           COUNT(*) FILTER (WHERE NOT smm_any)   AS n_no
    FROM long GROUP BY variable, category
)
SELECT a.variable, a.category,
       CASE WHEN a.n_all BETWEEN 1 AND 9 THEN '<10' ELSE a.n_all::text END AS all_n,
       CASE WHEN a.n_all BETWEEN 1 AND 9 THEN '' ELSE ROUND(100.0 * a.n_all / t.n_all, 1)::text END AS all_pct,
       CASE WHEN a.n_smm BETWEEN 1 AND 9 THEN '<10' ELSE a.n_smm::text END AS smm_n,
       CASE WHEN a.n_smm BETWEEN 1 AND 9 THEN '' ELSE ROUND(100.0 * a.n_smm / t.n_smm, 1)::text END AS smm_pct,
       CASE WHEN a.n_no  BETWEEN 1 AND 9 THEN '<10' ELSE a.n_no::text  END AS no_smm_n,
       CASE WHEN a.n_no  BETWEEN 1 AND 9 THEN '' ELSE ROUND(100.0 * a.n_no / t.n_no, 1)::text END AS no_smm_pct,
       CASE WHEN a.n_all > 0 AND a.n_smm >= 10 THEN ROUND(100.0 * a.n_smm / a.n_all, 2)::text ELSE '' END AS smm_rate_pct_in_category,
       -- complementary check: a suppressed cell can be recovered by subtraction if its row partner is shown
       CASE WHEN (a.n_smm BETWEEN 1 AND 9 OR a.n_no BETWEEN 1 AND 9 OR a.n_all BETWEEN 1 AND 9)
            THEN 'CHECK: small cell, regroup' ELSE 'ok' END AS disclosure_check
FROM agg a CROSS JOIN tot t
ORDER BY a.variable, a.n_all DESC;

-- ----------------------------------------------------------------------------
-- Q-T1b  Continuous characteristics: median [IQR] overall, with and without SMM
-- (laboratory values among admissions with the test measured)
-- ----------------------------------------------------------------------------
WITH base AS (
    SELECT p.smm_any, p.age_at_admission::numeric AS age,
           CASE WHEN p.hemoglobin BETWEEN 3 AND 20 THEN p.hemoglobin END   AS hgb,
           CASE WHEN p.creatinine BETWEEN 0.1 AND 20 THEN p.creatinine END AS creat,
           p.los_hours / 24.0 AS los_days
    FROM mimiciv.predictors_24h_v2 p
    WHERE p.is_delivery_v2 AND p.eligible_24h
),
v AS (
    SELECT '1 Age, years' AS variable, smm_any, age AS x FROM base
    UNION ALL SELECT '2 Hemoglobin, g/dL (first value by 24 h)', smm_any, hgb FROM base WHERE hgb IS NOT NULL
    UNION ALL SELECT '3 Creatinine, mg/dL (first value by 24 h)', smm_any, creat FROM base WHERE creat IS NOT NULL
    UNION ALL SELECT '4 Length of stay, days', smm_any, los_days FROM base
)
SELECT variable, grp,
       COUNT(*) AS n,
       ROUND(percentile_cont(0.50) WITHIN GROUP (ORDER BY x)::numeric, 2) AS median,
       ROUND(percentile_cont(0.25) WITHIN GROUP (ORDER BY x)::numeric, 2) AS q1,
       ROUND(percentile_cont(0.75) WITHIN GROUP (ORDER BY x)::numeric, 2) AS q3
FROM (SELECT variable, 'All' AS grp, x FROM v
      UNION ALL SELECT variable, CASE WHEN smm_any THEN 'SMM' ELSE 'No SMM' END, x FROM v) s
GROUP BY variable, grp
ORDER BY variable, grp;

-- ----------------------------------------------------------------------------
-- Q-T1c  Check against the reference counts (expected 19,383 / 13,710 / 445)
-- ----------------------------------------------------------------------------
SELECT COUNT(*)                         AS admissions,
       COUNT(DISTINCT subject_id)       AS patients,
       COUNT(*) FILTER (WHERE smm_any)  AS smm
FROM mimiciv.predictors_24h_v2
WHERE is_delivery_v2 AND eligible_24h;
