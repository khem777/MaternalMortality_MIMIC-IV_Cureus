-- ============================================================================
-- 04_labels / 06_smm_death_overlap.sql
-- Overlap between severe maternal morbidity (revised label) and death in the
-- same admission
-- ============================================================================
-- Why: to describe how severe maternal morbidity (SMM) relates to
--   maternal mortality.  The earlier count (Q10) used the v1 SMM label.
--   This script repeats it with the revised labels (CDC list, ICD-9-CM and
--   ICD-10-CM/PCS; death = hospital_expire_flag in the same admission) and in
--   the three scopes used in the revised analysis, so the supplement can state
--   exactly how many deaths carry an SMM indicator and how many SMM admissions
--   end in death.
--
-- What it does: only reads.  It creates no table or view and changes no label.
--   Requires mimiciv.predictors_24h_v2 (05_predictors/01_predictors_24h.sql).
--   Aggregate counts only -- share the results of the four queries, never rows.
-- ============================================================================

-- Q-H1  SMM x death in the same admission, by scope
WITH s AS (
    SELECT 1 AS ord, 'All obstetric admissions'             AS scope, smm_any, died_same_admission
    FROM mimiciv.predictors_24h_v2
    UNION ALL
    SELECT 2, 'Delivery hospitalizations',                  smm_any, died_same_admission
    FROM mimiciv.predictors_24h_v2 WHERE is_delivery_v2
    UNION ALL
    SELECT 3, 'Eligible deliveries (24-h model)',           smm_any, died_same_admission
    FROM mimiciv.predictors_24h_v2 WHERE is_delivery_v2 AND eligible_24h
)
SELECT scope,
       COUNT(*)                                                                      AS n_admissions,
       COUNT(*) FILTER (WHERE NOT smm_any AND NOT died_same_admission)               AS neither,
       COUNT(*) FILTER (WHERE smm_any AND NOT died_same_admission)                   AS smm_only,
       COUNT(*) FILTER (WHERE NOT smm_any AND died_same_admission)                   AS death_only,
       COUNT(*) FILTER (WHERE smm_any AND died_same_admission)                       AS smm_and_death,
       COUNT(*) FILTER (WHERE smm_any)                                               AS n_smm,
       COUNT(*) FILTER (WHERE died_same_admission)                                   AS n_death
FROM s
GROUP BY ord, scope
ORDER BY ord;

-- Q-H2  The deaths in the same admission, one row per profile
--       (delivery or not, eligible for the 24-h model or not, with or without SMM)
SELECT is_delivery_v2,
       eligible_24h,
       smm_any,
       COUNT(*) AS n_deaths
FROM mimiciv.predictors_24h_v2
WHERE died_same_admission
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 2 DESC, 3 DESC;

-- Q-H3  SMM admissions by number of indicators and how many end in death
--       (all obstetric admissions; smm_n_indicators lives in cohort_obstetric_v2)
SELECT c.smm_n_indicators,
       COUNT(*)                                          AS n_smm_admissions,
       COUNT(*) FILTER (WHERE p.died_same_admission)     AS n_died_same_admission
FROM mimiciv.predictors_24h_v2 p
JOIN mimiciv.cohort_obstetric_v2 c ON c.hadm_id = p.hadm_id
WHERE p.smm_any
GROUP BY 1
ORDER BY 1;

-- Q-H4  SMM indicators carried by the admissions that ended in death
--       (one admission can carry several indicators; counts of admissions per indicator, ICD versions together)
SELECT h.indicator_name,
       COUNT(DISTINCT h.hadm_id) AS n_death_admissions_with_indicator
FROM mimiciv.smm_hits_v2 h
JOIN mimiciv.predictors_24h_v2 p ON p.hadm_id = h.hadm_id
WHERE p.died_same_admission
GROUP BY 1
ORDER BY 2 DESC, 1;
