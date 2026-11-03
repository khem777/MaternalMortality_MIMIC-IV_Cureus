-- ============================================================================
-- COUNT AUDIT, PART 2 -- READ-ONLY
-- ============================================================================
-- Follow-up to audit_counts.sql after the first results (Q1-Q11). Same rules:
-- only temporary tables + SELECTs, aggregated output, never publish subject_id/hadm_id.
--   Q15  SMM cases by indicator group, overall and in delivery hospitalizations
--   Q16  profile of the in-hospital deaths of the same admission (small aggregated cells)
--   Q17  approximate admission year (lower bound of the anchor window + offset) vs. ICD version (anchor_year_group is
--        the patient's anchor window, NOT the date of each admission)
--   Q18  SMM cases per indicator group and anchor_year_group (what drives the rise per era)
-- Prerequisites: mimiciv.cohort_smm_dataset, mimiciv.hadm_with_smm,
--                mimiciv.hadm_delivery_hospitalization, mimiciv.pregnancy_diagnoses_expanded
-- ============================================================================
SET search_path TO mimiciv, public;

DROP TABLE IF EXISTS tmp_audit2;
CREATE TEMP TABLE tmp_audit2 AS
SELECT s.subject_id, s.hadm_id, s.outcome_smm, s.is_delivery_hospitalization, s.icu_stay,
       a.admittime, a.deathtime, a.hospital_expire_flag,
       p.anchor_year, p.anchor_year_group,
       CAST(LEFT(p.anchor_year_group, 4) AS int) + (EXTRACT(YEAR FROM a.admittime)::int - p.anchor_year) AS approx_year_low,
       COALESCE(BOOL_OR(d.icd_version = 9),  FALSE) AS has_icd9,
       COALESCE(BOOL_OR(d.icd_version = 10), FALSE) AS has_icd10
FROM   mimiciv.cohort_smm_dataset s
JOIN   mimiciv.admissions a ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
JOIN   mimiciv.patients   p ON p.subject_id = s.subject_id
LEFT JOIN mimiciv.diagnoses_icd d ON d.subject_id = s.subject_id AND d.hadm_id = s.hadm_id
GROUP  BY s.subject_id, s.hadm_id, s.outcome_smm, s.is_delivery_hospitalization, s.icu_stay,
          a.admittime, a.deathtime, a.hospital_expire_flag, p.anchor_year, p.anchor_year_group;

-- Q15. SMM by indicator group (an admission can have several indicators, so rows overlap)
SELECT 'Q15 SMM by indicator group' AS q, w.indicator_group,
       COUNT(DISTINCT w.hadm_id)                                                     AS n_admissions_with_indicator,
       COUNT(DISTINCT w.hadm_id) FILTER (WHERE c.is_delivery_hospitalization = 1)    AS n_in_delivery_hosp,
       COUNT(DISTINCT w.hadm_id) FILTER (WHERE c.is_delivery_hospitalization = 0)    AS n_in_non_delivery_hosp
FROM   mimiciv.hadm_with_smm w
JOIN   tmp_audit2 c ON c.subject_id = w.subject_id AND c.hadm_id = w.hadm_id
GROUP  BY w.indicator_group ORDER BY n_admissions_with_indicator DESC;

-- Q15b. Same, by individual indicator (top 25)
SELECT 'Q15b SMM by indicator' AS q, w.indicator_group, w.indicator_name,
       COUNT(DISTINCT w.hadm_id) AS n_admissions
FROM   mimiciv.hadm_with_smm w
JOIN   tmp_audit2 c ON c.subject_id = w.subject_id AND c.hadm_id = w.hadm_id
GROUP  BY 2, 3 ORDER BY n_admissions DESC LIMIT 25;

-- Q16. The in-hospital deaths of the same admission (about 10): profile, aggregated only
SELECT 'Q16 same-admission deaths profile' AS q,
       CASE WHEN has_icd9 AND has_icd10 THEN 'both' WHEN has_icd9 THEN 'ICD-9 only' ELSE 'ICD-10 only' END AS icd_version,
       is_delivery_hospitalization AS delivery_flag_icd10,
       outcome_smm,
       icu_stay,
       EXISTS (SELECT 1 FROM mimiciv.diagnoses_icd d
               JOIN mimiciv.pregnancy_diagnoses_expanded de ON de.icd_code = d.icd_code AND de.icd_version = d.icd_version
               WHERE d.subject_id = t.subject_id AND d.hadm_id = t.hadm_id AND d.seq_num = 1) AS obstetric_dx_is_principal,
       COUNT(*) AS n_deaths
FROM   tmp_audit2 t
WHERE  hospital_expire_flag = 1
GROUP  BY 2, 3, 4, 5, 6 ORDER BY n_deaths DESC;

-- Q17. Approximate admission year (lower bound of the window + offset) vs. ICD version
SELECT 'Q17 approx year vs ICD version' AS q, approx_year_low,
       COUNT(*)                                                  AS n_admissions,
       COUNT(*) FILTER (WHERE has_icd9  AND NOT has_icd10)       AS n_icd9_only,
       COUNT(*) FILTER (WHERE has_icd10 AND NOT has_icd9)        AS n_icd10_only,
       COUNT(*) FILTER (WHERE outcome_smm = 1)                   AS n_smm,
       COUNT(*) FILTER (WHERE is_delivery_hospitalization = 1)   AS n_delivery_icd10_flag
FROM   tmp_audit2
GROUP  BY approx_year_low ORDER BY approx_year_low;

-- Q18. SMM admissions per indicator group and anchor_year_group
SELECT 'Q18 SMM group by era' AS q, w.indicator_group,
       COUNT(DISTINCT w.hadm_id) FILTER (WHERE c.anchor_year_group = '2008 - 2010') AS g_2008_2010,
       COUNT(DISTINCT w.hadm_id) FILTER (WHERE c.anchor_year_group = '2011 - 2013') AS g_2011_2013,
       COUNT(DISTINCT w.hadm_id) FILTER (WHERE c.anchor_year_group = '2014 - 2016') AS g_2014_2016,
       COUNT(DISTINCT w.hadm_id) FILTER (WHERE c.anchor_year_group = '2017 - 2019') AS g_2017_2019,
       COUNT(DISTINCT w.hadm_id) FILTER (WHERE c.anchor_year_group = '2020 - 2022') AS g_2020_2022
FROM   mimiciv.hadm_with_smm w
JOIN   tmp_audit2 c ON c.subject_id = w.subject_id AND c.hadm_id = w.hadm_id
GROUP  BY w.indicator_group ORDER BY 3 + 4 + 5 + 6 + 7 DESC;
