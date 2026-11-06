-- ============================================================================
-- COUNT AUDIT -- v1 data compared with the current definitions
-- Framework: E4 Count audit (first version against the current definitions); reference counts for gate P1.
-- ============================================================================
-- Purpose: measure, on the data the v1 models were trained on, counts
-- that the v1 manuscript did not report. READ-ONLY: it only
-- creates temporary tables and runs SELECTs. No patient-level output is produced
-- except aggregated counts; do NOT publish result rows that list subject_id/hadm_id.
--
-- Prerequisites (already built for the v1 analyses):
--   mimiciv.cohort_maternal        (Model A table; column `outcome`)
--   mimiciv.cohort_smm_dataset     (Model B table; columns outcome_smm, is_delivery_hospitalization,
--                                   icu_stay, heart_rate, creatine, lactic_acid, ...; the column is spelled `creatine`, as in the table)
--   mimiciv.pregnancy_diagnoses_expanded (view)
-- Run the whole script (DBeaver: Alt+X) and copy each result set into the
-- results spreadsheet.
-- Each result set starts with a label column `q`.
-- ============================================================================

SET search_path TO mimiciv, public;

-- ----------------------------------------------------------------------------
-- 0. Working tables
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_audit_cohort;
CREATE TEMP TABLE tmp_audit_cohort AS
SELECT s.subject_id, s.hadm_id, s.outcome_smm, s.is_delivery_hospitalization, s.icu_stay,
       a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag,
       p.anchor_year_group,
       m.outcome AS outcome_a_v1
FROM   mimiciv.cohort_smm_dataset s
JOIN   mimiciv.admissions a ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
JOIN   mimiciv.patients   p ON p.subject_id = s.subject_id
LEFT JOIN mimiciv.cohort_maternal m ON m.subject_id = s.subject_id AND m.hadm_id = s.hadm_id;

-- ICD version actually present in each admission's diagnoses
DROP TABLE IF EXISTS tmp_audit_icdver;
CREATE TEMP TABLE tmp_audit_icdver AS
SELECT d.subject_id, d.hadm_id,
       BOOL_OR(d.icd_version = 9)  AS has_icd9,
       BOOL_OR(d.icd_version = 10) AS has_icd10
FROM   mimiciv.diagnoses_icd d
JOIN   tmp_audit_cohort c ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
GROUP  BY d.subject_id, d.hadm_id;

-- ----------------------------------------------------------------------------
-- Q1. Cohort size and repeated patients (manuscript: 25,736 / 15,084 / 6,793)
-- ----------------------------------------------------------------------------
SELECT 'Q1 cohort' AS q,
       COUNT(*)                                AS n_admissions,
       COUNT(DISTINCT subject_id)              AS n_patients,
       (SELECT COUNT(*) FROM (SELECT subject_id FROM tmp_audit_cohort
                              GROUP BY subject_id HAVING COUNT(*) > 1) t) AS n_patients_multi_admission
FROM tmp_audit_cohort;

-- ----------------------------------------------------------------------------
-- Q2. Model A as in v1: positives, and how they relate to the actual death
--     Label = any admission of the patient (any time, obstetric or not) has a deathtime
--     (see CASE ... MIN(a2.deathtime) in the cohort_maternal CREATE TABLE).
-- ----------------------------------------------------------------------------
SELECT 'Q2 modelA positives' AS q,
       COUNT(*) FILTER (WHERE outcome_a_v1 = 1)                        AS n_positive_admissions,
       COUNT(DISTINCT subject_id) FILTER (WHERE outcome_a_v1 = 1)      AS n_distinct_deceased_patients
FROM tmp_audit_cohort;

WITH pos AS (
    SELECT subject_id, hadm_id, admittime FROM tmp_audit_cohort WHERE outcome_a_v1 = 1
),
death AS (
    SELECT DISTINCT ON (a.subject_id) a.subject_id, a.hadm_id AS death_hadm_id,
           a.admittime AS death_admittime, a.deathtime
    FROM   mimiciv.admissions a
    WHERE  a.deathtime IS NOT NULL
    ORDER  BY a.subject_id, a.deathtime
),
x AS (
    SELECT p.subject_id, p.hadm_id,
           CASE WHEN d.death_hadm_id = p.hadm_id        THEN '1 same admission'
                WHEN d.death_admittime > p.admittime    THEN '2 later admission'
                ELSE                                         '3 earlier/other' END AS death_relation,
           EXISTS (SELECT 1 FROM tmp_audit_cohort c WHERE c.hadm_id = d.death_hadm_id) AS death_adm_in_cohort,
           EXISTS (SELECT 1 FROM mimiciv.icustays i WHERE i.hadm_id = d.death_hadm_id) AS death_adm_had_icu,
           EXISTS (SELECT 1 FROM mimiciv.icustays i WHERE i.hadm_id = p.hadm_id)       AS this_adm_had_icu,
           EXTRACT(EPOCH FROM (d.deathtime - p.admittime)) / 86400.0                   AS days_to_death
    FROM   pos p JOIN death d ON d.subject_id = p.subject_id
)
SELECT 'Q3 relation of positive admission to the death admission' AS q,
       death_relation,
       COUNT(*)                                          AS n_admissions,
       COUNT(DISTINCT subject_id)                        AS n_patients,
       COUNT(*) FILTER (WHERE death_adm_in_cohort)       AS death_admission_is_in_obstetric_cohort,
       COUNT(*) FILTER (WHERE death_adm_had_icu)         AS death_admission_had_icu,
       COUNT(*) FILTER (WHERE this_adm_had_icu)          AS this_admission_had_icu,
       ROUND(CAST(percentile_cont(0.5) WITHIN GROUP (ORDER BY days_to_death) AS numeric), 1) AS median_days_to_death,
       ROUND(CAST(MIN(days_to_death) AS numeric), 1)     AS min_days_to_death,
       ROUND(CAST(MAX(days_to_death) AS numeric), 1)     AS max_days_to_death
FROM   x
GROUP  BY death_relation
ORDER  BY death_relation;

-- Q4. Positive admissions generated by each deceased patient
SELECT 'Q4 positives per deceased patient' AS q, n_pos AS positive_admissions_per_patient, COUNT(*) AS n_patients
FROM (SELECT subject_id, COUNT(*) AS n_pos FROM tmp_audit_cohort
      WHERE outcome_a_v1 = 1 GROUP BY subject_id) t
GROUP  BY n_pos ORDER BY n_pos;

-- ----------------------------------------------------------------------------
-- Q5. Proposed redefinition of Model A: death in the SAME admission
-- ----------------------------------------------------------------------------
SELECT 'Q5 in-hospital death, same admission' AS q,
       COUNT(*) FILTER (WHERE hospital_expire_flag = 1)                                 AS n_events,
       COUNT(DISTINCT subject_id) FILTER (WHERE hospital_expire_flag = 1)               AS n_patients_with_event,
       COUNT(*) FILTER (WHERE hospital_expire_flag = 1 AND icu_stay = 1)                AS events_with_icu,
       COUNT(*) FILTER (WHERE hospital_expire_flag = 1 AND icu_stay = 0)                AS events_without_icu,
       COUNT(*) FILTER (WHERE hospital_expire_flag = 1
                         AND deathtime <= admittime + INTERVAL '24 hours')              AS events_within_first_24h,
       COUNT(*) FILTER (WHERE hospital_expire_flag = 1 AND outcome_a_v1 = 1)     AS also_positive_in_v1_label
FROM   tmp_audit_cohort;

-- ----------------------------------------------------------------------------
-- Q6. ICD version and era. SMM codes in smm_cohort.sql are matched
--     with icd_version = 10 only.
-- ----------------------------------------------------------------------------
SELECT 'Q6 icd version' AS q,
       CASE WHEN v.has_icd9 AND v.has_icd10 THEN 'both'
            WHEN v.has_icd9                 THEN 'ICD-9 only'
            WHEN v.has_icd10                THEN 'ICD-10 only'
            ELSE 'no diagnoses' END                                AS icd_version_in_admission,
       COUNT(*)                                                    AS n_admissions,
       COUNT(*) FILTER (WHERE c.outcome_smm = 1)                   AS n_smm_positive_v1_label,
       COUNT(*) FILTER (WHERE c.outcome_a_v1 = 1)           AS n_modelA_positive_v1_label,
       COUNT(*) FILTER (WHERE c.is_delivery_hospitalization = 1)   AS n_delivery_hospitalizations
FROM   tmp_audit_cohort c
LEFT JOIN tmp_audit_icdver v ON v.subject_id = c.subject_id AND v.hadm_id = c.hadm_id
GROUP  BY 2 ORDER BY 2;

SELECT 'Q7 era (anchor_year_group)' AS q, c.anchor_year_group,
       COUNT(*)                                                  AS n_admissions,
       COUNT(*) FILTER (WHERE v.has_icd9)                        AS n_with_icd9,
       COUNT(*) FILTER (WHERE v.has_icd10)                       AS n_with_icd10,
       COUNT(*) FILTER (WHERE c.outcome_smm = 1)                 AS n_smm,
       COUNT(*) FILTER (WHERE c.is_delivery_hospitalization = 1) AS n_delivery_icd10_flag,
       COUNT(*) FILTER (WHERE c.is_delivery_hospitalization = 1 AND c.outcome_smm = 1) AS n_smm_in_delivery,
       ROUND(10000.0 * COUNT(*) FILTER (WHERE c.is_delivery_hospitalization = 1 AND c.outcome_smm = 1)
             / NULLIF(COUNT(*) FILTER (WHERE c.is_delivery_hospitalization = 1), 0), 1) AS smm_per_10000_deliveries
FROM   tmp_audit_cohort c
LEFT JOIN tmp_audit_icdver v ON v.subject_id = c.subject_id AND v.hadm_id = c.hadm_id
GROUP  BY c.anchor_year_group ORDER BY c.anchor_year_group;

-- Q8. Proxy for ICD-9 delivery admissions (the delivery flag only looks at ICD-10 Z37/O80/O82):
--     ICD-9 650 (normal delivery) or V27.x (outcome of delivery). Descriptive proxy, not a validated list.
SELECT 'Q8 ICD-9 delivery proxy' AS q, COUNT(DISTINCT c.hadm_id) AS n_admissions_icd9_delivery_proxy
FROM   tmp_audit_cohort c
JOIN   mimiciv.diagnoses_icd d ON d.subject_id = c.subject_id AND d.hadm_id = c.hadm_id
WHERE  d.icd_version = 9 AND (d.icd_code LIKE '650%' OR d.icd_code LIKE 'V27%');

-- ----------------------------------------------------------------------------
-- Q9. SMM outcome: patients, repetition, overlap with in-hospital death
-- ----------------------------------------------------------------------------
SELECT 'Q9 smm patients' AS q,
       COUNT(*) FILTER (WHERE outcome_smm = 1)                     AS n_smm_admissions,
       COUNT(DISTINCT subject_id) FILTER (WHERE outcome_smm = 1)   AS n_patients_with_smm
FROM   tmp_audit_cohort;

SELECT 'Q10 smm x in-hospital death (same admission)' AS q, outcome_smm, hospital_expire_flag, COUNT(*) AS n
FROM   tmp_audit_cohort GROUP BY 2, 3 ORDER BY 2, 3;

SELECT 'Q11 smm x v1 mortality label' AS q, outcome_smm, outcome_a_v1, COUNT(*) AS n
FROM   tmp_audit_cohort GROUP BY 2, 3 ORDER BY 2, 3;

-- ----------------------------------------------------------------------------
-- Q12. Cohort inclusion rule: the manuscript says obstetric diagnosis in position <= 4,
--      the SQL has no position restriction. How much does it matter?
-- ----------------------------------------------------------------------------
WITH pos4 AS (
    SELECT DISTINCT d.subject_id, d.hadm_id
    FROM   mimiciv.diagnoses_icd d
    JOIN   mimiciv.pregnancy_diagnoses_expanded de
           ON de.icd_code = d.icd_code AND de.icd_version = d.icd_version
    WHERE  d.seq_num <= 4
)
SELECT 'Q12 obstetric dx in position <= 4' AS q,
       COUNT(*)                                              AS n_admissions_all_rule,
       COUNT(p.hadm_id)                                      AS n_admissions_if_position_le_4,
       COUNT(*) FILTER (WHERE c.outcome_smm = 1)             AS smm_all_rule,
       COUNT(p.hadm_id) FILTER (WHERE c.outcome_smm = 1)     AS smm_if_position_le_4,
       COUNT(*) FILTER (WHERE c.hospital_expire_flag = 1)         AS deaths_all_rule,
       COUNT(p.hadm_id) FILTER (WHERE c.hospital_expire_flag = 1) AS deaths_if_position_le_4
FROM   tmp_audit_cohort c
LEFT JOIN pos4 p ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id;

-- ----------------------------------------------------------------------------
-- Q13. Structural availability of ICU-charted variables
--      Vitals come from chartevents of the first ICU stay only; labs from hospital-wide labevents.
-- ----------------------------------------------------------------------------
SELECT 'Q13 availability by ICU status and SMM' AS q,
       s.icu_stay, s.outcome_smm,
       COUNT(*)                                           AS n_admissions,
       ROUND(100.0 * COUNT(s.heart_rate)  / COUNT(*), 1)  AS pct_heart_rate_present,
       ROUND(100.0 * COUNT(s.creatine)    / COUNT(*), 1)  AS pct_creatinine_present,
       ROUND(100.0 * COUNT(s.glucose)     / COUNT(*), 1)  AS pct_glucose_present,
       ROUND(100.0 * COUNT(s.lactic_acid) / COUNT(*), 1)  AS pct_lactate_present,
       ROUND(100.0 * COUNT(s.hemoglobine) / COUNT(*), 1)  AS pct_hemoglobin_present
FROM   mimiciv.cohort_smm_dataset s
GROUP  BY s.icu_stay, s.outcome_smm ORDER BY s.icu_stay, s.outcome_smm;

-- ----------------------------------------------------------------------------
-- Q14. Timing of the earliest lab/charted value relative to admission
--      Hours from admittime to the earliest creatinine (itemids 50912 lab / 220615 chart).
-- ----------------------------------------------------------------------------
WITH first_creat AS (
    SELECT c.hadm_id, MIN(t.charttime) AS first_time
    FROM   tmp_audit_cohort c
    JOIN  (SELECT hadm_id, charttime FROM mimiciv.labevents   WHERE itemid = 50912  AND valuenum IS NOT NULL
           UNION ALL
           SELECT hadm_id, charttime FROM mimiciv.chartevents WHERE itemid = 220615 AND valuenum IS NOT NULL) t
           ON t.hadm_id = c.hadm_id
    GROUP  BY c.hadm_id
)
SELECT 'Q14 hours to earliest creatinine' AS q,
       COUNT(*)                                                                         AS n_with_creatinine,
       ROUND(CAST(percentile_cont(0.5)  WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (f.first_time - c.admittime))/3600.0) AS numeric), 1) AS median_hours,
       ROUND(CAST(percentile_cont(0.9)  WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (f.first_time - c.admittime))/3600.0) AS numeric), 1) AS p90_hours,
       COUNT(*) FILTER (WHERE f.first_time >  c.admittime + INTERVAL '24 hours')        AS n_first_value_after_24h
FROM   first_creat f JOIN tmp_audit_cohort c ON c.hadm_id = f.hadm_id;

-- ============================================================================
-- PATIENT OVERLAP BETWEEN TRAIN AND TEST -- run in the NOTEBOOK, in a NEW cell
-- placed right after the train_test_split cell (do not edit existing cells). The split
-- cannot be reproduced from SQL, because df is re-sorted in pandas.
--
--   ids = (df_scaled.sort_values('subject_id').reset_index(drop=True)['subject_id'])
--   tr_ids, te_ids = set(ids.loc[X_train.index]), set(ids.loc[X_test.index])
--   ev_ids = set(ids[y == 1])
--   print("patients train / test:", len(tr_ids), len(te_ids))
--   print("patients in BOTH:", len(tr_ids & te_ids))
--   print("test admissions whose patient is also in train:",
--         int(ids.loc[X_test.index].isin(tr_ids).sum()), "of", len(X_test))
--   print("event patients total / in test:", len(ev_ids), len(ev_ids & te_ids))
--   print("test events whose patient also has an event admission in train:",
--         int(ids.loc[X_test.index][y_test == 1].isin(ids.loc[X_train.index][y_train == 1]).sum()))
--
-- NOTE: in the Model A notebook the same cells exist with outcome_smm replaced by outcome.
-- ============================================================================
