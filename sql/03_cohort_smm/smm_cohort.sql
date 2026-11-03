-- ============================================================================
-- STATUS (2026-10-25): this script defines the labels of the first version of the analysis (v1)
-- ============================================================================
-- It was run on the local database and produced the 475 SMM admissions of the
-- v1 version. Two limitations of that version are known and fixed in the
-- current version, so do not use this script for the revised analysis:
--   (1) SMM codes: ICD-10-CM/PCS only. MIMIC-IV has ICD-9-CM diagnoses and
--       procedures until 2015, so ICD-9 admissions were counted as SMM-negative.
--   (2) Delivery flag: ICD-10 Z37/O80/O82 only; 8,857 deliveries, against 19,425
--       with the revised flag (diagnoses, procedures and DRG, ICD-9 and ICD-10).
-- Revised definitions (official CDC list in both ICD versions, delivery flag,
-- same-admission labels): see sql/04_labels/. Counts that compare the
-- two versions: sql/06_audit_counts/.
-- Only comments were edited in this file; no SQL statement was changed.
-- ============================================================================

-- ============================================================================
-- "NEAR-MISS" / SEVERE MATERNAL MORBIDITY (SMM) COHORT -- Modelo B
-- ============================================================================
-- Spanish version of this script: smm_cohort_es.sql (same folder).
--
-- Source of the 21 indicators and ICD-10-CM/PCS codes: CDC (2023), via the
-- HRSA Federally Available Data (FAD) Resource Document 2023, reproduced in
-- Appendix 1 of the Nebraska DHHS "Severe Maternal Morbidity Report
-- 2017-2021" (Jul-2024). Indicator #18 (blood transfusion) is excluded
-- because HRSA officially retired it in 2023 ("no longer used") -- so this
-- script uses the 20 currently-active indicators, matching that state
-- report.
--
-- IMPORTANT: the CDC's official SMM definition is measured over "delivery
-- hospitalizations", not over any admission with an obstetric diagnosis.
-- That's why this script computes the SMM indicator over TWO denominators,
-- so you can compare:
--   (a) Delivery hospitalizations only (a delivery-outcome code Z37.x or
--       O80-O82.x) -- comparable with published CDC/state rates
--       (58-88 SMM per 10,000 deliveries).
--   (b) The full expanded obstetric cohort
--       (maternal_cohort_expanded.sql) -- a wider denominator, more
--       absolute cases, but no longer 1:1 comparable with published rates.
--
-- (Original note, superseded by the STATUS block at the top: this script has since
-- been run on the local database, localhost:5433.)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Step 1: catalogue of ICD-10 patterns for the 20 currently-active SMM
-- indicators
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.smm_code_patterns;

CREATE TABLE mimiciv.smm_code_patterns (
    indicator_group  VARCHAR(60),
    indicator_name   VARCHAR(60),
    code_type        VARCHAR(2),   -- 'DX' (diagnoses_icd) or 'PR' (procedures_icd)
    code_pattern     VARCHAR(10)   -- prefix; compared as icd_code LIKE pattern || '%'
);

INSERT INTO mimiciv.smm_code_patterns (indicator_group, indicator_name, code_type, code_pattern) VALUES
-- 1. Acute myocardial infarction
('Cardiac',  'Acute myocardial infarction', 'DX', 'I21'),
('Cardiac',  'Acute myocardial infarction', 'DX', 'I22'),
-- 2. Aneurysm
('Cardiac',  'Aneurysm', 'DX', 'I71'),
('Cardiac',  'Aneurysm', 'DX', 'I790'),
-- 3. Acute renal failure
('Renal',    'Acute renal failure', 'DX', 'N17'),
('Renal',    'Acute renal failure', 'DX', 'O904'),
-- 4. Adult respiratory distress syndrome
('Respiratory', 'ARDS', 'DX', 'J80'),
('Respiratory', 'ARDS', 'DX', 'J951'),
('Respiratory', 'ARDS', 'DX', 'J952'),
('Respiratory', 'ARDS', 'DX', 'J953'),
('Respiratory', 'ARDS', 'DX', 'J9582'),
('Respiratory', 'ARDS', 'DX', 'J960'),
('Respiratory', 'ARDS', 'DX', 'J962'),
('Respiratory', 'ARDS', 'DX', 'R092'),
-- 5. Amniotic fluid embolism
('Other_Obstetric', 'Amniotic fluid embolism', 'DX', 'O881'),
-- 6. Cardiac arrest / ventricular fibrillation
('Cardiac',  'Cardiac arrest/ventricular fibrillation', 'DX', 'I46'),
('Cardiac',  'Cardiac arrest/ventricular fibrillation', 'DX', 'I490'),
-- 7. Conversion of cardiac rhythm (procedure, ICD-10-PCS)
('Cardiac',  'Conversion of cardiac rhythm', 'PR', '5A2204Z'),
('Cardiac',  'Conversion of cardiac rhythm', 'PR', '5A12012'),
-- 8. Disseminated intravascular coagulation
('Hemorrhage', 'DIC', 'DX', 'D65'),
('Hemorrhage', 'DIC', 'DX', 'D688'),
('Hemorrhage', 'DIC', 'DX', 'D689'),
('Hemorrhage', 'DIC', 'DX', 'O723'),
-- 9. Eclampsia
('Other_Obstetric', 'Eclampsia', 'DX', 'O15'),
-- 10. Heart failure/arrest during surgery or procedure
('Cardiac',  'Heart failure/arrest during surgery or procedure', 'DX', 'I9712'),
('Cardiac',  'Heart failure/arrest during surgery or procedure', 'DX', 'I9713'),
('Cardiac',  'Heart failure/arrest during surgery or procedure', 'DX', 'I97710'),
('Cardiac',  'Heart failure/arrest during surgery or procedure', 'DX', 'I97711'),
-- 11. Puerperal cerebrovascular disorders
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I60'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I61'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I62'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I63'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I64'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I65'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I66'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I67'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I68'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'O2251'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'O2252'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'O2253'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I9781'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I9782'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'O873'),
-- 12. Pulmonary edema / Acute heart failure
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'J810'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I501'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5020'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5021'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5023'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5030'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5031'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5033'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5040'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5041'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5043'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I509'),
-- 13. Severe anesthesia complications
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 'O740'),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 'O741'),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 'O742'),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 'O743'),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 'O890'),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 'O891'),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 'O892'),
-- 14. Sepsis
('Sepsis',   'Sepsis', 'DX', 'O85'),
('Sepsis',   'Sepsis', 'DX', 'O8604'),
('Sepsis',   'Sepsis', 'DX', 'T80211A'),
('Sepsis',   'Sepsis', 'DX', 'T814XXA'),
('Sepsis',   'Sepsis', 'DX', 'T8144'),
('Sepsis',   'Sepsis', 'DX', 'R6520'),
('Sepsis',   'Sepsis', 'DX', 'A40'),
('Sepsis',   'Sepsis', 'DX', 'A41'),
('Sepsis',   'Sepsis', 'DX', 'A327'),
-- 15. Shock
('Hemorrhage', 'Shock', 'DX', 'O751'),
('Hemorrhage', 'Shock', 'DX', 'R57'),
('Hemorrhage', 'Shock', 'DX', 'R6521'),
('Hemorrhage', 'Shock', 'DX', 'T782XXA'),
('Hemorrhage', 'Shock', 'DX', 'T882XXA'),
('Hemorrhage', 'Shock', 'DX', 'T886XXA'),
('Hemorrhage', 'Shock', 'DX', 'T8110XA'),
('Hemorrhage', 'Shock', 'DX', 'T8111XA'),
('Hemorrhage', 'Shock', 'DX', 'T8119XA'),
-- 16. Sickle cell disease with crisis
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 'D570'),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 'D5721'),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 'D5741'),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 'D5781'),
-- 17. Air and thrombotic embolism
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 'I26'),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 'O880'),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 'O882'),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 'O883'),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 'O888'),
-- 18. Blood products transfusion: EXCLUDED (retired by HRSA in 2023)
-- 19. Hysterectomy (procedure, ICD-10-PCS)
('Hemorrhage', 'Hysterectomy', 'PR', '0UT90ZZ'),
('Hemorrhage', 'Hysterectomy', 'PR', '0UT94ZZ'),
('Hemorrhage', 'Hysterectomy', 'PR', '0UT97ZZ'),
('Hemorrhage', 'Hysterectomy', 'PR', '0UT98ZZ'),
('Hemorrhage', 'Hysterectomy', 'PR', '0UT9FZZ'),
-- 20. Temporary tracheostomy (procedure)
('Respiratory', 'Temporary tracheostomy', 'PR', '0B110Z'),
('Respiratory', 'Temporary tracheostomy', 'PR', '0B110F'),
('Respiratory', 'Temporary tracheostomy', 'PR', '0B113'),
('Respiratory', 'Temporary tracheostomy', 'PR', '0B114'),
-- 21. Ventilation (procedure)
('Respiratory', 'Ventilation', 'PR', '5A1935Z'),
('Respiratory', 'Ventilation', 'PR', '5A1945Z'),
('Respiratory', 'Ventilation', 'PR', '5A1955Z');

-- ----------------------------------------------------------------------------
-- Step 2: hadm_id with at least one SMM indicator (ICD-10 only, as in the v1
-- version). MIMIC-IV also has ICD-9-CM data until 2015, which this step does not
-- see; the current version applies the CDC ICD-9-CM list in sql/04_labels/.
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS mimiciv.hadm_with_smm;

CREATE VIEW mimiciv.hadm_with_smm AS
SELECT DISTINCT d.subject_id, d.hadm_id, p.indicator_group, p.indicator_name
FROM mimiciv.diagnoses_icd d
JOIN mimiciv.smm_code_patterns p
  ON p.code_type = 'DX'
 AND d.icd_version = 10
 AND d.icd_code LIKE p.code_pattern || '%'
UNION
SELECT DISTINCT pr.subject_id, pr.hadm_id, p.indicator_group, p.indicator_name
FROM mimiciv.procedures_icd pr
JOIN mimiciv.smm_code_patterns p
  ON p.code_type = 'PR'
 AND pr.icd_version = 10
 AND pr.icd_code LIKE p.code_pattern || '%';

-- ----------------------------------------------------------------------------
-- Step 3: identify delivery hospitalizations (proxy: delivery-outcome code
-- Z37.x, or delivery encounter O80.x/O82.x)
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS mimiciv.hadm_delivery_hospitalization;

CREATE VIEW mimiciv.hadm_delivery_hospitalization AS
SELECT DISTINCT d.subject_id, d.hadm_id
FROM mimiciv.diagnoses_icd d
WHERE d.icd_version = 10
  AND (d.icd_code LIKE 'Z37%' OR d.icd_code LIKE 'O80%' OR d.icd_code LIKE 'O82%');

-- ----------------------------------------------------------------------------
-- Step 4: final cohort combining the expanded obstetric universe (Step 2 of
-- maternal_cohort_expanded.sql) + SMM outcome + delivery flag
-- ----------------------------------------------------------------------------
WITH maternal_admissions AS (
    SELECT DISTINCT
        a.subject_id,
        a.hadm_id,
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
)
SELECT
    COUNT(*)                                                              AS total_obstetric_admissions,
    COUNT(*) FILTER (WHERE dh.hadm_id IS NOT NULL)                        AS total_delivery_hospitalizations,
    COUNT(DISTINCT smm.hadm_id)                                           AS total_with_smm_any_admission,
    COUNT(DISTINCT smm.hadm_id) FILTER (WHERE dh.hadm_id IS NOT NULL)     AS total_with_smm_at_delivery
FROM maternal_admissions ma
LEFT JOIN mimiciv.hadm_delivery_hospitalization dh
  ON ma.subject_id = dh.subject_id AND ma.hadm_id = dh.hadm_id
LEFT JOIN mimiciv.hadm_with_smm smm
  ON ma.subject_id = smm.subject_id AND ma.hadm_id = smm.hadm_id;

-- Detail per complication category (equivalent to Table 6 of the Nebraska
-- report), useful for a comparison table in the thesis:
-- SELECT indicator_group, count(DISTINCT hadm_id) AS n
-- FROM mimiciv.hadm_with_smm
-- GROUP BY indicator_group
-- ORDER BY n DESC;
