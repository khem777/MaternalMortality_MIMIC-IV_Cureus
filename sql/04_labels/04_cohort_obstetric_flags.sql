-- ============================================================================
-- 04_labels / 04_cohort_obstetric_flags.sql
-- Diagnosis-position rule and cohort definition
-- ============================================================================
-- Background: the v1 manuscript described the cohort as admissions with an
--   obstetric diagnosis in position <= 4, but the SQL that built both datasets has NO
--   position restriction (a diagnosis in ANY position qualifies).  This script measures
--   what a position rule would change, so that the cohort rule could be chosen with data.
--
-- Decision (D6): NO position rule is applied.  The cohort keeps every admission with an
--   obstetric diagnosis in any position, and the manuscript text was aligned with the SQL.
--   A rule of position <= 4 would remove 38 of the 848 SMM admissions and 3 of the 10
--   same-admission deaths (Q-D5, rule R1): severe admissions whose obstetric code is listed
--   after other complications.  As a sensitivity analysis, the cohort can be restricted to
--   admissions with at least one STRUCTURED obstetric code (Q-D5, rule R2).
--
-- What this script does (it applies no rule to the cohort):
--   1. Adds, per admission of the obstetric universe, the obstetric-diagnosis
--      features needed to apply ANY of the candidate rules with a WHERE clause:
--      lowest diagnosis position, number of obstetric diagnoses, whether any
--      obstetric diagnosis is a STRUCTURED code (ICD-10 chapter O, Z33/Z34/Z37/Z39,
--      ICD-9 630-679, ICD-9 V22-V28) or only a TEXT match on the long title
--      (e.g. "weeks of gestation", "pregnancy test"), ICU stay flag.
--   2. Returns aggregate counts only (Q-D0 .. Q-D5, including Q-D4b) that document the
--      effect of each candidate rule.
--
-- Run order: 01 -> 02 -> 03 -> 04.  Everything is created under NEW names (*_v2);
--   no existing table or view is modified.  Share only the aggregate results of
--   the count queries, never row-level data.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Step 1 -- obstetric diagnoses per admission, with position and type of code
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.cohort_obstetric_v2;
DROP VIEW  IF EXISTS mimiciv.obstetric_dx_v2;

CREATE VIEW mimiciv.obstetric_dx_v2 AS
SELECT d.hadm_id,
       d.seq_num,
       d.icd_code,
       d.icd_version,
       CASE
         WHEN d.icd_version = 10 AND LEFT(d.icd_code, 1) = 'O'                        THEN 'ICD-10 chapter O'
         WHEN d.icd_version = 10 AND (d.icd_code LIKE 'Z33%' OR d.icd_code LIKE 'Z34%'
                                   OR d.icd_code LIKE 'Z37%' OR d.icd_code LIKE 'Z39%') THEN 'ICD-10 Z33/Z34/Z37/Z39'
         WHEN d.icd_version = 9  AND d.icd_code ~ '^6[3-7][0-9]'                       THEN 'ICD-9 630-679'
         WHEN d.icd_version = 9  AND LEFT(d.icd_code, 3) IN ('V22','V23','V24','V27','V28') THEN 'ICD-9 V22-V28'
         ELSE 'Text match only'
       END AS code_group
FROM mimiciv.diagnoses_icd d
JOIN mimiciv.pregnancy_diagnoses_expanded de
  ON de.icd_code = d.icd_code AND de.icd_version = d.icd_version;

-- ----------------------------------------------------------------------------
-- Step 2 -- one row per admission: labels (script 03) + obstetric-diagnosis features
-- ----------------------------------------------------------------------------
CREATE TABLE mimiciv.cohort_obstetric_v2 AS
WITH feat AS (
    SELECT hadm_id,
           MIN(seq_num)                                              AS min_obst_seq,
           COUNT(*)                                                  AS n_obst_dx,
           BOOL_OR(code_group <> 'Text match only')                  AS has_structured_obst,
           MIN(seq_num) FILTER (WHERE code_group <> 'Text match only') AS min_structured_seq
    FROM mimiciv.obstetric_dx_v2
    GROUP BY hadm_id
),
first_dx AS (
    SELECT DISTINCT ON (hadm_id) hadm_id, code_group AS first_obst_group
    FROM mimiciv.obstetric_dx_v2
    ORDER BY hadm_id, seq_num, icd_code
)
SELECT l.*,
       f.min_obst_seq,
       f.n_obst_dx,
       f.has_structured_obst,
       f.min_structured_seq,
       (f.min_obst_seq <= 4)                                        AS obst_in_first4,
       x.first_obst_group,
       EXISTS (SELECT 1 FROM mimiciv.icustays i WHERE i.hadm_id = l.hadm_id) AS had_icu_stay
FROM mimiciv.label_admission_v2 l
LEFT JOIN feat     f ON f.hadm_id = l.hadm_id
LEFT JOIN first_dx x ON x.hadm_id = l.hadm_id;

CREATE INDEX ON mimiciv.cohort_obstetric_v2 (hadm_id);
CREATE INDEX ON mimiciv.cohort_obstetric_v2 (subject_id);

-- ============================================================================
-- COUNT QUERIES (aggregate only) -- run each and paste the result
-- ============================================================================

-- Q-D0  Sanity: the table has the same rows as the label table and every row has features
SELECT COUNT(*)                                             AS n_rows,
       COUNT(*) FILTER (WHERE min_obst_seq IS NULL)         AS n_without_obstetric_dx,
       (SELECT COUNT(*) FROM mimiciv.label_admission_v2)    AS n_label_table
FROM mimiciv.cohort_obstetric_v2;

-- Q-D1  Lowest position of an obstetric diagnosis (all admissions of the universe)
SELECT CASE WHEN min_obst_seq <= 1  THEN '1'
            WHEN min_obst_seq <= 2  THEN '2'
            WHEN min_obst_seq <= 3  THEN '3'
            WHEN min_obst_seq <= 4  THEN '4'
            WHEN min_obst_seq <= 6  THEN '5-6'
            WHEN min_obst_seq <= 10 THEN '7-10'
            ELSE '11 or more' END                                         AS lowest_position,
       MIN(min_obst_seq)                                                  AS sort_key,
       COUNT(*)                                                           AS n_admissions,
       COUNT(*) FILTER (WHERE is_delivery_v2)                             AS n_delivery,
       COUNT(*) FILTER (WHERE smm_any)                                    AS n_smm_any,
       COUNT(*) FILTER (WHERE smm_any AND is_delivery_v2)                 AS n_smm_delivery,
       COUNT(*) FILTER (WHERE died_same_admission)                        AS n_died_same_adm,
       COUNT(*) FILTER (WHERE had_icu_stay)                               AS n_with_icu
FROM mimiciv.cohort_obstetric_v2
GROUP BY 1 ORDER BY 2;

-- Q-D2  Admissions that the "position <= 4" rule would remove, by delivery flag
SELECT is_delivery_v2,
       COUNT(*)                                       AS n_admissions,
       COUNT(DISTINCT subject_id)                     AS n_patients,
       COUNT(*) FILTER (WHERE smm_any)                AS n_smm_any,
       COUNT(*) FILTER (WHERE died_same_admission)    AS n_died_same_adm,
       COUNT(*) FILTER (WHERE had_icu_stay)           AS n_with_icu,
       ROUND(AVG(n_obst_dx), 1)                       AS mean_n_obstetric_dx
FROM mimiciv.cohort_obstetric_v2
WHERE NOT obst_in_first4
GROUP BY 1 ORDER BY 1;

-- Q-D3  What kind of obstetric code do those admissions carry?
--       (group of the diagnosis with the lowest position, by rule status)
SELECT first_obst_group,
       obst_in_first4,
       COUNT(*)                                       AS n_admissions,
       COUNT(*) FILTER (WHERE is_delivery_v2)         AS n_delivery,
       COUNT(*) FILTER (WHERE smm_any)                AS n_smm_any,
       COUNT(*) FILTER (WHERE died_same_admission)    AS n_died_same_adm
FROM mimiciv.cohort_obstetric_v2
GROUP BY 1, 2 ORDER BY 1, 2;

-- Q-D4  Admissions whose only obstetric evidence is a text match on the long title
--       (no structured obstetric code, not a delivery by the v2 flag)
SELECT COUNT(*)                                       AS n_admissions,
       COUNT(DISTINCT subject_id)                     AS n_patients,
       COUNT(*) FILTER (WHERE smm_any)                AS n_smm_any,
       COUNT(*) FILTER (WHERE died_same_admission)    AS n_died_same_adm,
       COUNT(*) FILTER (WHERE had_icu_stay)           AS n_with_icu
FROM mimiciv.cohort_obstetric_v2
WHERE NOT has_structured_obst AND NOT is_delivery_v2;

-- Q-D4b The codes behind those admissions (up to 15 most frequent; counts of admissions)
SELECT o.icd_code, o.icd_version, COUNT(DISTINCT o.hadm_id) AS n_admissions
FROM mimiciv.obstetric_dx_v2 o
JOIN mimiciv.cohort_obstetric_v2 c ON c.hadm_id = o.hadm_id
WHERE NOT c.has_structured_obst AND NOT c.is_delivery_v2
GROUP BY 1, 2 ORDER BY 3 DESC, 1 LIMIT 15;

-- Q-D5  Decision table: effect of each candidate cohort rule on the REVISED labels
--       R0 any position (current SQL) | R1 position <= 4 (manuscript text)
--       R2 structured obstetric code, any position | R3 delivery hospitalization only (v2 flag)
SELECT r.rule,
       COUNT(*)                                       AS n_admissions,
       COUNT(DISTINCT c.subject_id)                   AS n_patients,
       COUNT(*) FILTER (WHERE c.is_delivery_v2)       AS n_delivery,
       COUNT(*) FILTER (WHERE c.smm_any)              AS n_smm_any,
       COUNT(*) FILTER (WHERE c.smm_any AND c.is_delivery_v2) AS n_smm_delivery,
       COUNT(*) FILTER (WHERE c.died_same_admission)  AS n_died_same_adm,
       COUNT(*) FILTER (WHERE c.died_same_admission AND c.is_delivery_v2) AS n_died_delivery
FROM mimiciv.cohort_obstetric_v2 c
JOIN LATERAL (VALUES
        ('R0 any position',              TRUE),
        ('R1 position <= 4',             COALESCE(c.obst_in_first4, FALSE)),
        ('R2 structured code, any position', COALESCE(c.has_structured_obst, FALSE)),
        ('R3 delivery flag only',        COALESCE(c.is_delivery_v2, FALSE))
     ) AS r(rule, keep) ON r.keep
GROUP BY r.rule ORDER BY r.rule;
