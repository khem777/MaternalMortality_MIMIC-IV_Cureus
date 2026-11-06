-- ============================================================================
-- COUNT AUDIT, PART 3 -- READ-ONLY
-- Framework: E4 Count audit, part 3: dependence of the label on non-delivery admissions and on the renal indicator.
-- ============================================================================
-- Follow-up to Q15/Q16: 47% of the SMM admissions are NOT delivery hospitalizations and
-- acute renal failure is the largest indicator. These queries measure how much the
-- SMM label depends on (a) non-delivery admissions and (b) the renal indicator, and
-- what the non-delivery admissions are. Aggregated output only.
--   Q19  number of distinct SMM indicators per SMM admission, delivery vs non-delivery
--   Q20  alternative SMM definitions: admissions / patients / ICU / ICD-10 deliveries
--   Q21  obstetric code chapters present in non-delivery SMM admissions
-- Prerequisites: mimiciv.cohort_smm_dataset, mimiciv.hadm_with_smm
-- ============================================================================
SET search_path TO mimiciv, public;

DROP TABLE IF EXISTS tmp_smm_ind;
CREATE TEMP TABLE tmp_smm_ind AS
SELECT s.subject_id, s.hadm_id, s.is_delivery_hospitalization AS is_delivery, s.icu_stay,
       COUNT(DISTINCT w.indicator_name)                                          AS n_ind,
       BOOL_AND(w.indicator_name = 'Acute renal failure')                        AS only_renal
FROM   mimiciv.cohort_smm_dataset s
JOIN   mimiciv.hadm_with_smm w ON w.subject_id = s.subject_id AND w.hadm_id = s.hadm_id
WHERE  s.outcome_smm = 1
GROUP  BY s.subject_id, s.hadm_id, s.is_delivery_hospitalization, s.icu_stay;

-- Q19
SELECT 'Q19 indicators per SMM admission' AS q, n_ind AS n_distinct_indicators,
       COUNT(*)                                  AS n_admissions,
       COUNT(*) FILTER (WHERE is_delivery = 1)   AS n_delivery,
       COUNT(*) FILTER (WHERE is_delivery = 0)   AS n_non_delivery
FROM   tmp_smm_ind GROUP BY n_ind ORDER BY n_ind;

-- Q20
SELECT 'Q20 alternative SMM definitions' AS q, definition, n_admissions, n_patients, n_with_icu
FROM (
  SELECT 1 AS o, 'A. Current label (any indicator, any admission)' AS definition,
         COUNT(*) AS n_admissions, COUNT(DISTINCT subject_id) AS n_patients, COUNT(*) FILTER (WHERE icu_stay = 1) AS n_with_icu
  FROM tmp_smm_ind
  UNION ALL
  SELECT 2, 'B. Delivery hospitalizations only (ICD-10 flag)', COUNT(*), COUNT(DISTINCT subject_id), COUNT(*) FILTER (WHERE icu_stay = 1)
  FROM tmp_smm_ind WHERE is_delivery = 1
  UNION ALL
  SELECT 3, 'C. Any admission, excluding admissions whose only indicator is acute renal failure', COUNT(*), COUNT(DISTINCT subject_id), COUNT(*) FILTER (WHERE icu_stay = 1)
  FROM tmp_smm_ind WHERE NOT only_renal
  UNION ALL
  SELECT 4, 'D. Delivery hospitalizations, excluding renal-only', COUNT(*), COUNT(DISTINCT subject_id), COUNT(*) FILTER (WHERE icu_stay = 1)
  FROM tmp_smm_ind WHERE is_delivery = 1 AND NOT only_renal
  UNION ALL
  SELECT 5, 'E. Two or more distinct indicators', COUNT(*), COUNT(DISTINCT subject_id), COUNT(*) FILTER (WHERE icu_stay = 1)
  FROM tmp_smm_ind WHERE n_ind >= 2
  UNION ALL
  SELECT 6, 'Renal-only admissions (any admission)', COUNT(*), COUNT(DISTINCT subject_id), COUNT(*) FILTER (WHERE icu_stay = 1)
  FROM tmp_smm_ind WHERE only_renal
) t ORDER BY o;

-- Q21. Obstetric chapters present in the NON-delivery SMM admissions (ICD-10; overlapping flags)
WITH nd AS (SELECT subject_id, hadm_id FROM tmp_smm_ind WHERE is_delivery = 0),
codes AS (
  SELECT nd.hadm_id, LEFT(d.icd_code, 3) AS c3
  FROM nd JOIN mimiciv.diagnoses_icd d ON d.subject_id = nd.subject_id AND d.hadm_id = nd.hadm_id
  WHERE d.icd_version = 10
)
SELECT 'Q21 non-delivery SMM: obstetric chapters' AS q,
       (SELECT COUNT(*) FROM nd)                                                                          AS n_non_delivery_smm,
       COUNT(DISTINCT hadm_id) FILTER (WHERE c3 BETWEEN 'O00' AND 'O08')                                  AS o00_o08_abortive_outcome,
       COUNT(DISTINCT hadm_id) FILTER (WHERE c3 BETWEEN 'O09' AND 'O48')                                  AS o09_o48_antepartum,
       COUNT(DISTINCT hadm_id) FILTER (WHERE c3 BETWEEN 'O60' AND 'O77')                                  AS o60_o77_labour_delivery,
       COUNT(DISTINCT hadm_id) FILTER (WHERE c3 BETWEEN 'O85' AND 'O92')                                  AS o85_o92_puerperium,
       COUNT(DISTINCT hadm_id) FILTER (WHERE c3 BETWEEN 'O94' AND 'O9A' OR c3 BETWEEN 'O98' AND 'O99')    AS o94_o9a_other,
       COUNT(DISTINCT hadm_id) FILTER (WHERE c3 IN ('Z33','Z34','Z39'))                                   AS z33_z34_z39_pregnancy_state_or_postpartum_care
FROM codes;
