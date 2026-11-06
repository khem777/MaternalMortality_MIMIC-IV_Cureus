-- ============================================================================
-- 04_labels / 03_labels_same_admission.sql
-- Admission-level labels for the revised analysis (both models)
-- Framework: E3 Outcome definition: admission-level labels (contract columns label_main and alternatives).
-- ============================================================================
-- Purpose (decisions D1, D4(a), D5(a)):
--   * Model A (mortality): label = death DURING THE SAME ADMISSION
--     (admissions.hospital_expire_flag = 1), not "any recorded death of the
--     patient at any time".  deathtime IS NOT NULL is kept as a cross-check.
--   * Model B (SMM): indicators from the official CDC catalogue
--     (smm_code_patterns_v2: ICD-9-CM AND ICD-10-CM/PCS), computed per admission.
--   * Delivery flag from 02_delivery_flag.sql (is_delivery_v2).
--   Everything is created under NEW names (*_v2).  The original tables/views are
--   NOT modified.  Run order: 01 -> 02 -> 03.
--
-- UNIVERSE: the same universe as the original SMM script -- female, approx. age
--   12-55 (anchor_age + admission year - anchor_year), at least one diagnosis in
--   mimiciv.pregnancy_diagnoses_expanded, ANY diagnosis position.
--   The diagnosis-position rule differs between the two
--   original cohort scripts and is resolved in the next script (04), after both
--   are reconciled.  This script therefore only labels; it does not define the
--   final cohort.
--
-- Nothing here writes subject_id/hadm_id outside the database.  The count
-- queries at the end return aggregates only -- share those, never row-level data.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Step 1 -- SMM hits per admission and indicator (ICD-version aware)
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS mimiciv.smm_by_admission_v2 CASCADE;
DROP VIEW IF EXISTS mimiciv.smm_hits_v2 CASCADE;

CREATE VIEW mimiciv.smm_hits_v2 AS
SELECT DISTINCT d.hadm_id, p.indicator_name, p.icd_version
FROM mimiciv.diagnoses_icd d
JOIN mimiciv.smm_code_patterns_v2 p
  ON p.code_type = 'DX'
 AND p.icd_version = d.icd_version
 AND ( (p.match_type = 'PREFIX' AND d.icd_code LIKE p.code_pattern || '%')
    OR (p.match_type = 'EXACT'  AND d.icd_code = p.code_pattern) )
UNION
SELECT DISTINCT pr.hadm_id, p.indicator_name, p.icd_version
FROM mimiciv.procedures_icd pr
JOIN mimiciv.smm_code_patterns_v2 p
  ON p.code_type = 'PR'
 AND p.icd_version = pr.icd_version
 AND ( (p.match_type = 'PREFIX' AND pr.icd_code LIKE p.code_pattern || '%')
    OR (p.match_type = 'EXACT'  AND pr.icd_code = p.code_pattern) );

CREATE VIEW mimiciv.smm_by_admission_v2 AS
SELECT hadm_id,
       COUNT(DISTINCT indicator_name)                                        AS n_indicators,
       BOOL_AND(indicator_name = 'Acute renal failure')                      AS only_renal,
       BOOL_OR(icd_version = 9)                                              AS hit_icd9,
       BOOL_OR(icd_version = 10)                                             AS hit_icd10
FROM mimiciv.smm_hits_v2
GROUP BY hadm_id;

-- ----------------------------------------------------------------------------
-- Step 2 -- label table (one row per admission of the obstetric universe)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.label_admission_v2;

CREATE TABLE mimiciv.label_admission_v2 AS
WITH universe AS (
    SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.deathtime, a.hospital_expire_flag,
           p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) AS approx_age
    FROM mimiciv.admissions a
    JOIN mimiciv.patients p ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) BETWEEN 12 AND 55
      AND a.hadm_id IN (
            SELECT d.hadm_id
            FROM mimiciv.diagnoses_icd d
            JOIN mimiciv.pregnancy_diagnoses_expanded de
              ON d.icd_code = de.icd_code AND d.icd_version = de.icd_version)
),
era AS (
    SELECT hadm_id,
           BOOL_OR(icd_version = 9)  AS has_icd9_dx,
           BOOL_OR(icd_version = 10) AS has_icd10_dx
    FROM mimiciv.diagnoses_icd
    GROUP BY hadm_id
)
SELECT u.subject_id,
       u.hadm_id,
       u.admittime,
       u.approx_age,
       -- Model A label (same-admission death)
       (u.hospital_expire_flag = 1)                     AS died_same_admission,
       (u.deathtime IS NOT NULL)                        AS deathtime_recorded,
       -- Delivery flag
       dv.is_delivery_v2,
       dv.has_stillbirth_code,
       -- Model B label
       COALESCE(s.n_indicators, 0)                      AS smm_n_indicators,
       (COALESCE(s.n_indicators, 0) >= 1)               AS smm_any,
       COALESCE(s.only_renal, FALSE)                    AS smm_only_renal,
       (COALESCE(s.n_indicators, 0) >= 2)               AS smm_ge2,
       COALESCE(s.hit_icd9, FALSE)                      AS smm_hit_icd9,
       COALESCE(s.hit_icd10, FALSE)                     AS smm_hit_icd10,
       -- coding era
       COALESCE(e.has_icd9_dx, FALSE)                   AS has_icd9_dx,
       COALESCE(e.has_icd10_dx, FALSE)                  AS has_icd10_dx
FROM universe u
LEFT JOIN mimiciv.hadm_delivery_v2   dv ON dv.hadm_id = u.hadm_id
LEFT JOIN mimiciv.smm_by_admission_v2 s ON s.hadm_id  = u.hadm_id
LEFT JOIN era                          e ON e.hadm_id  = u.hadm_id;

CREATE INDEX ON mimiciv.label_admission_v2 (hadm_id);
CREATE INDEX ON mimiciv.label_admission_v2 (subject_id);

-- ============================================================================
-- COUNT QUERIES (aggregate only) -- run each and paste the result
-- ============================================================================

-- Q-C1  Universe, delivery flag and labels
SELECT COUNT(*)                                              AS n_admissions,
       COUNT(DISTINCT subject_id)                            AS n_patients,
       COUNT(*) FILTER (WHERE is_delivery_v2)                AS n_delivery_v2,
       COUNT(*) FILTER (WHERE smm_any)                       AS n_smm_any_admission,
       COUNT(*) FILTER (WHERE smm_any AND is_delivery_v2)    AS n_smm_at_delivery,
       COUNT(*) FILTER (WHERE died_same_admission)           AS n_died_same_admission,
       COUNT(*) FILTER (WHERE died_same_admission AND is_delivery_v2) AS n_died_same_adm_at_delivery,
       COUNT(*) FILTER (WHERE died_same_admission <> deathtime_recorded) AS n_flag_vs_deathtime_discordant
FROM mimiciv.label_admission_v2;

-- Q-C2  Coding era of delivery admissions and SMM rate (decision D4: if SMM at
--       ICD-9 deliveries is wildly different from ICD-10, reconsider option (b))
SELECT CASE WHEN has_icd9_dx AND NOT has_icd10_dx THEN 'ICD-9 only'
            WHEN has_icd10_dx AND NOT has_icd9_dx THEN 'ICD-10 only'
            WHEN has_icd9_dx AND has_icd10_dx     THEN 'both'
            ELSE 'none' END                                  AS coding,
       COUNT(*)                                              AS n_delivery_admissions,
       COUNT(*) FILTER (WHERE smm_any)                       AS n_smm,
       ROUND(100.0 * COUNT(*) FILTER (WHERE smm_any) / NULLIF(COUNT(*),0), 2) AS pct_smm,
       COUNT(*) FILTER (WHERE died_same_admission)           AS n_died
FROM mimiciv.label_admission_v2
WHERE is_delivery_v2
GROUP BY 1 ORDER BY 1;

-- Q-C3  SMM by indicator and ICD version (delivery admissions, v2 flag)
SELECT h.indicator_name, h.icd_version, COUNT(DISTINCT h.hadm_id) AS n_admissions
FROM mimiciv.smm_hits_v2 h
JOIN mimiciv.label_admission_v2 l ON l.hadm_id = h.hadm_id AND l.is_delivery_v2
GROUP BY 1, 2 ORDER BY 3 DESC, 1, 2;

-- Q-C4  New vs ORIGINAL SMM label (same universe, any admission)
SELECT COUNT(*) FILTER (WHERE smm_any AND old.hadm_id IS NOT NULL)     AS smm_both,
       COUNT(*) FILTER (WHERE smm_any AND old.hadm_id IS NULL)         AS smm_only_new,
       COUNT(*) FILTER (WHERE NOT smm_any AND old.hadm_id IS NOT NULL) AS smm_only_old
FROM mimiciv.label_admission_v2 l
LEFT JOIN (SELECT DISTINCT hadm_id FROM mimiciv.hadm_with_smm) old ON old.hadm_id = l.hadm_id;

-- Q-C5  Definition sensitivities: all / without renal-only / >=2 indicators,
--       delivery admissions only
SELECT COUNT(*) FILTER (WHERE smm_any)                              AS smm_any,
       COUNT(*) FILTER (WHERE smm_any AND NOT smm_only_renal)       AS smm_excl_renal_only,
       COUNT(*) FILTER (WHERE smm_ge2)                              AS smm_ge2_indicators
FROM mimiciv.label_admission_v2
WHERE is_delivery_v2;

-- Q-C6  Patients with >1 admission and their labels (grouped-split relevance)
SELECT COUNT(*) FILTER (WHERE n_adm > 1)                    AS patients_multi_admission,
       COUNT(*)                                             AS patients,
       MAX(n_adm)                                           AS max_adm_per_patient
FROM (SELECT subject_id, COUNT(*) AS n_adm FROM mimiciv.label_admission_v2 GROUP BY subject_id) t;

-- Q-C7  Are legacy / non-official codes present?  (aggregate counts of admissions
--       in the obstetric universe; informs whether pre-FY2019 codes matter)
SELECT d.icd_code, d.icd_version, COUNT(DISTINCT d.hadm_id) AS n_admissions
FROM mimiciv.diagnoses_icd d
JOIN mimiciv.label_admission_v2 l ON l.hadm_id = d.hadm_id
WHERE (d.icd_version = 10 AND d.icd_code IN ('T814XXA','T811XXA','T80211A','I64','O2251','0UT94ZZ','0UT98ZZ','0UT9FZZ'))
   OR (d.icd_version = 9  AND d.icd_code = '9980')
GROUP BY 1, 2 ORDER BY 3 DESC;
