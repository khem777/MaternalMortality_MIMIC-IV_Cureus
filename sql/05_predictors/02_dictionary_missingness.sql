-- ============================================================================
-- 05_predictors / 02_dictionary_missingness.sql
-- Final predictor dictionary and missingness tables
--
-- ============================================================================
-- Why: the analysis needs a predictor dictionary (source table, item id,
--   units, window), the percentage of missing values per predictor and outcome,
--   the handling of implausible values and of measurements that do not exist
--   outside the ICU.
--
-- Decision applied (analysis decisions):
--   D11 A laboratory test enters the main model only if it has a value in at
--       least 10% of the delivery hospitalizations eligible for the 24-hour
--       model (rule based on availability only, not on the outcome).  The other
--       laboratory tests and the ICU-only variables go to sensitivity analyses
--       with missingness indicators.  Creatinine carries a missingness indicator
--       in the main model (its availability depends on the outcome, Q-F4).
--       The threshold is the parameter min_coverage_pct below.
--   D12 Hemoglobin and hematocrit are strongly correlated (Q-G2b); only hemoglobin enters the main
--       model and hematocrit goes to the laboratory sensitivity analysis.
--
-- What this script creates (new name only; nothing existing is modified):
--   mimiciv.predictor_dictionary_final_v2   one row per predictor
--
-- Requires: 04_cohort_obstetric_flags.sql and 05_predictors/01_predictors_24h.sql.
-- Run the whole script (DBeaver: Alt+X), then run each query Q-G0 .. Q-G6 and share
--   only the aggregate results, never row-level data.  Percentiles are reported
--   instead of minimum and maximum values, so that no single patient's extreme value is exposed.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Step 1 -- final dictionary
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.predictor_dictionary_final_v2;

CREATE TABLE mimiciv.predictor_dictionary_final_v2 AS
WITH params AS (
    SELECT 10.0::numeric AS min_coverage_pct            -- D11: threshold, in % of eligible deliveries
),
sc AS (
    SELECT * FROM mimiciv.predictors_24h_v2 WHERE is_delivery_v2 AND eligible_24h
),
cov AS (
    SELECT kv.key AS variable, COUNT(*) AS n_eligible_delivery, COUNT(kv.value) AS n_with_value
    FROM sc CROSS JOIN LATERAL jsonb_each_text(to_jsonb(sc)) kv
    WHERE kv.key IN (SELECT variable FROM mimiciv.predictor_dictionary_v2)
    GROUP BY kv.key
),
units (variable, unit) AS (VALUES
    ('heart_rate', 'beats/min'), ('respiratory_rate', 'breaths/min'), ('o2_saturation', '%'),
    ('pressure_blood_mean', 'mmHg'), ('pressure_blood_systolic', 'mmHg'), ('pressure_blood_diastolic', 'mmHg'),
    ('temperature_fahrenheit', 'deg F'), ('weight_admission', 'kg'), ('height', 'cm'),
    ('gcs_eye_opening', 'score'), ('gcs_verbal_response', 'score'), ('gcs_motor_response', 'score'),
    ('richmond_ras_scale', 'score'), ('peep_set', 'cmH2O'),
    ('glucose', 'mg/dL'), ('hemoglobin', 'g/dL'), ('hematocrit', '%'), ('creatinine', 'mg/dL'),
    ('sodium', 'mEq/L'), ('potassium', 'mEq/L'), ('chloride', 'mEq/L'), ('bicarbonate', 'mEq/L'),
    ('anion_gap', 'mEq/L'), ('calcium_noionized', 'mg/dL'), ('magnesium', 'mg/dL'),
    ('phosphorus', 'mg/dL'), ('lactate', 'mmol/L')
),
-- Plausibility limits are PROPOSALS for the three main-model laboratory tests, to be confirmed
-- by clinical review.  Q-G4 counts how many values fall outside them.
limits (variable, plausible_low, plausible_high) AS (VALUES
    ('hemoglobin', 3.0, 20.0), ('hematocrit', 10.0, 65.0), ('creatinine', 0.1, 20.0)
)
SELECT d.variable, d.previous_name, d.chart_itemid, d.lab_itemid, d.chart_label, d.lab_label,
       d.source, u.unit, d.window_rule,
       c.n_eligible_delivery, c.n_with_value,
       ROUND(100.0 * c.n_with_value / NULLIF(c.n_eligible_delivery, 0), 1)                AS coverage_pct,
       d.model_role                                                                         AS model_role_v1,
       CASE WHEN d.lab_itemid IS NULL THEN 'ICU sensitivity only'
            WHEN d.variable = 'hematocrit'
                 THEN 'laboratory sensitivity (redundant with hemoglobin, D12)'
            WHEN 100.0 * c.n_with_value / NULLIF(c.n_eligible_delivery, 0) >= p.min_coverage_pct
                 THEN 'main model'
            ELSE 'laboratory sensitivity (coverage below threshold)' END                    AS model_role_final,
       (d.variable = 'creatinine')                                                          AS missingness_indicator_main,
       l.plausible_low, l.plausible_high,
       CASE WHEN l.variable IS NOT NULL THEN 'proposed limits, pending clinical review' END AS limits_note
FROM mimiciv.predictor_dictionary_v2 d
CROSS JOIN params p
LEFT JOIN cov    c ON c.variable = d.variable
LEFT JOIN units  u ON u.variable = d.variable
LEFT JOIN limits l ON l.variable = d.variable;

ALTER TABLE mimiciv.predictor_dictionary_final_v2 ADD PRIMARY KEY (variable);

-- ============================================================================
-- COUNT QUERIES (aggregate only) -- run each and paste the result
-- Population: delivery hospitalizations eligible for the 24-hour model (main scope),
--   and, where stated, any obstetric admission eligible (sensitivity scope).
-- ============================================================================

-- Q-G0  Final dictionary: role, coverage and threshold result per predictor
SELECT variable, unit, source, coverage_pct, model_role_v1, model_role_final,
       missingness_indicator_main, plausible_low, plausible_high
FROM mimiciv.predictor_dictionary_final_v2
ORDER BY model_role_final, variable;

-- Q-G1  Availability of the three main-model laboratory tests by stratum (era, ICU, outcome)
WITH base AS (
    SELECT p.*, c.has_icd9_dx, c.has_icd10_dx, c.smm_only_renal, c.smm_n_indicators
    FROM mimiciv.predictors_24h_v2 p
    JOIN mimiciv.cohort_obstetric_v2 c ON c.hadm_id = p.hadm_id
    WHERE p.eligible_24h
),
scoped AS (
    SELECT b.*, s.scope
    FROM base b
    JOIN LATERAL (VALUES
            ('Delivery hospitalization (main)', COALESCE(b.is_delivery_v2, FALSE)),
            ('Any obstetric admission',         TRUE)
         ) AS s(scope, keep) ON s.keep
)
SELECT sc.scope, st.stratum,
       COUNT(*)                                                                          AS n_admissions,
       COUNT(sc.hemoglobin)                                                              AS n_hemoglobin,
       COUNT(sc.hematocrit)                                                              AS n_hematocrit,
       COUNT(sc.creatinine)                                                              AS n_creatinine,
       COUNT(*) FILTER (WHERE sc.hemoglobin IS NOT NULL AND sc.hematocrit IS NOT NULL
                          AND sc.creatinine IS NOT NULL)                                 AS n_all_three,
       COUNT(*) FILTER (WHERE sc.hemoglobin IS NULL AND sc.hematocrit IS NULL
                          AND sc.creatinine IS NULL)                                     AS n_none_of_three
FROM scoped sc
JOIN LATERAL (VALUES
        ('01 All',                                       TRUE),
        ('02 Admissions with an ICD-10 diagnosis',       COALESCE(sc.has_icd10_dx, FALSE)),
        ('03 ICD-9-only admissions',                     COALESCE(sc.has_icd9_dx, FALSE) AND NOT COALESCE(sc.has_icd10_dx, FALSE)),
        ('04 No ICU in the first 24 h',                  NOT COALESCE(sc.icu_in_24h, FALSE)),
        ('05 ICU in the first 24 h',                     COALESCE(sc.icu_in_24h, FALSE)),
        ('06 No SMM',                                    NOT COALESCE(sc.smm_any, FALSE)),
        ('07 SMM',                                       COALESCE(sc.smm_any, FALSE)),
        ('08 SMM, acute renal failure as the only indicator', COALESCE(sc.smm_only_renal, FALSE)),
        ('09 SMM, two or more indicators',               COALESCE(sc.smm_n_indicators, 0) >= 2),
        ('10 Died in the same admission',                COALESCE(sc.died_same_admission, FALSE))
     ) AS st(stratum, keep) ON st.keep
GROUP BY sc.scope, st.stratum
ORDER BY sc.scope DESC, st.stratum;

-- Q-G2  Missingness patterns of hemoglobin, hematocrit and creatinine (delivery, eligible)
SELECT (hemoglobin IS NOT NULL) AS has_hemoglobin,
       (hematocrit IS NOT NULL) AS has_hematocrit,
       (creatinine IS NOT NULL) AS has_creatinine,
       COUNT(*)                                       AS n_admissions,
       COUNT(*) FILTER (WHERE smm_any)                AS n_smm
FROM mimiciv.predictors_24h_v2
WHERE is_delivery_v2 AND eligible_24h
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 2 DESC, 3 DESC;

-- Q-G2b  Hemoglobin and hematocrit: how redundant are they? (correlation among admissions with both)
SELECT COUNT(*) FILTER (WHERE hemoglobin IS NOT NULL AND hematocrit IS NOT NULL)          AS n_pairs,
       ROUND(corr(hemoglobin, hematocrit)::numeric, 3)                                     AS corr_all,
       ROUND((corr(hemoglobin, hematocrit) FILTER (WHERE smm_any))::numeric, 3)            AS corr_smm,
       COUNT(*) FILTER (WHERE hemoglobin IS NOT NULL AND hematocrit IS NOT NULL AND smm_any) AS n_pairs_smm
FROM mimiciv.predictors_24h_v2
WHERE is_delivery_v2 AND eligible_24h;

-- Q-G3  Is creatinine measured because of the outcome? Availability by type of SMM (delivery, eligible)
SELECT CASE WHEN NOT COALESCE(c.smm_any, FALSE)        THEN '1 No SMM'
            WHEN COALESCE(c.smm_only_renal, FALSE)     THEN '2 SMM, acute renal failure as the only indicator'
            WHEN COALESCE(c.smm_n_indicators, 0) = 1   THEN '3 SMM, one non-renal indicator'
            ELSE                                            '4 SMM, two or more indicators' END AS smm_type,
       COUNT(*)                          AS n_admissions,
       COUNT(p.creatinine)               AS n_creatinine,
       COUNT(p.hemoglobin)               AS n_hemoglobin,
       COUNT(*) FILTER (WHERE p.icu_in_24h) AS n_icu_in_24h
FROM mimiciv.predictors_24h_v2 p
JOIN mimiciv.cohort_obstetric_v2 c ON c.hadm_id = p.hadm_id
WHERE p.is_delivery_v2 AND p.eligible_24h
GROUP BY 1 ORDER BY 1;

-- Q-G4  Distribution of the three main-model laboratory tests and values outside the proposed limits
WITH sc AS (
    SELECT * FROM mimiciv.predictors_24h_v2 WHERE is_delivery_v2 AND eligible_24h
),
v AS (
    SELECT 'hemoglobin'::text AS variable, hemoglobin AS value FROM sc
    UNION ALL SELECT 'hematocrit', hematocrit FROM sc
    UNION ALL SELECT 'creatinine', creatinine FROM sc
)
SELECT v.variable, d.unit,
       COUNT(v.value)                                                              AS n_values,
       ROUND(percentile_cont(0.01) WITHIN GROUP (ORDER BY v.value)::numeric, 2)    AS p01,
       ROUND(percentile_cont(0.05) WITHIN GROUP (ORDER BY v.value)::numeric, 2)    AS p05,
       ROUND(percentile_cont(0.25) WITHIN GROUP (ORDER BY v.value)::numeric, 2)    AS p25,
       ROUND(percentile_cont(0.50) WITHIN GROUP (ORDER BY v.value)::numeric, 2)    AS p50,
       ROUND(percentile_cont(0.75) WITHIN GROUP (ORDER BY v.value)::numeric, 2)    AS p75,
       ROUND(percentile_cont(0.95) WITHIN GROUP (ORDER BY v.value)::numeric, 2)    AS p95,
       ROUND(percentile_cont(0.99) WITHIN GROUP (ORDER BY v.value)::numeric, 2)    AS p99,
       d.plausible_low, d.plausible_high,
       COUNT(*) FILTER (WHERE v.value < d.plausible_low)                           AS n_below_low,
       COUNT(*) FILTER (WHERE v.value > d.plausible_high)                          AS n_above_high
FROM v
JOIN mimiciv.predictor_dictionary_final_v2 d ON d.variable = v.variable
GROUP BY v.variable, d.unit, d.plausible_low, d.plausible_high
ORDER BY v.variable;

-- Q-G5  When is the first value taken? Hours from the admission time (negative = before admission)
SELECT f.variable,
       COUNT(*)                                                                     AS n_values,
       ROUND(percentile_cont(0.10) WITHIN GROUP (ORDER BY f.hours_from_admission)::numeric, 1) AS p10_hours,
       ROUND(percentile_cont(0.50) WITHIN GROUP (ORDER BY f.hours_from_admission)::numeric, 1) AS p50_hours,
       ROUND(percentile_cont(0.90) WITHIN GROUP (ORDER BY f.hours_from_admission)::numeric, 1) AS p90_hours,
       COUNT(*) FILTER (WHERE f.hours_from_admission < 0)                           AS n_before_admission,
       COUNT(*) FILTER (WHERE f.hours_from_admission > 12)                          AS n_after_12h
FROM mimiciv.predictor_firsts_v2 f
JOIN mimiciv.predictors_24h_v2 p ON p.hadm_id = f.hadm_id
WHERE p.is_delivery_v2 AND p.eligible_24h
  AND f.variable IN ('hemoglobin', 'hematocrit', 'creatinine')
GROUP BY f.variable ORDER BY f.variable;

-- Q-G6  Units recorded for each laboratory test inside the window (all obstetric admissions)
SELECT d.variable, le.valueuom AS unit_recorded,
       COUNT(*)                     AS n_values,
       COUNT(DISTINCT c.hadm_id)    AS n_admissions
FROM mimiciv.cohort_obstetric_v2 c
JOIN mimiciv.labevents le
  ON le.subject_id = c.subject_id AND (le.hadm_id = c.hadm_id OR le.hadm_id IS NULL)
 AND le.charttime >= c.admittime - interval '24 hours'
 AND le.charttime <= c.admittime + interval '24 hours'
 AND le.valuenum IS NOT NULL
JOIN mimiciv.predictor_dictionary_v2 d ON d.lab_itemid = le.itemid
GROUP BY d.variable, le.valueuom
ORDER BY d.variable, n_values DESC;
