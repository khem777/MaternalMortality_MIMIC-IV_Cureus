-- ============================================================================
-- 07_timing_audit / 02_phenotype_audit_v3.sql
-- Code-level audit of the SMM phenotype
-- Framework: E3 and E4: code-level audit of the SMM phenotype.
-- ============================================================================
-- Questions answered (aggregates only, eligible delivery hospitalizations):
--   A1  Which specific codes did each pattern actually match, and how many
--       admissions does each one contribute?  Codes longer than their pattern
--       (prefix expansion) are flagged to be checked against the CDC page.
--   A2  Admissions whose SMM status depends on a single code (if that code
--       were dropped, the admission would become SMM-negative).
--   A3  Historically used codes that the current list excludes:
--       blood transfusion (ICD-9 99.0x, ICD-10-PCS 302 3/4 x...) and
--       T81.4XXA (infection following a procedure, used before FY2019).
--   A4  Label counts under alternative definitions: current 20 indicators,
--       21 indicators (+ transfusion), and 20 indicators with exact-only matching
--       of ICD-10 codes (no prefix expansion beyond the listed code).
-- Requires: mimiciv.timing_flags_v3 (01_timing_flags_v3.sql), mimiciv.smm_code_patterns_v2,
--           mimiciv.d_icd_diagnoses, mimiciv.d_icd_procedures.
-- ============================================================================

DROP TABLE IF EXISTS mimiciv.smm_code_hits_v3;
CREATE TABLE mimiciv.smm_code_hits_v3 AS
SELECT d.hadm_id, p.indicator_name, p.code_type, p.icd_version, p.code_pattern, p.match_type,
       d.icd_code, dd.long_title
FROM mimiciv.diagnoses_icd d
JOIN mimiciv.timing_flags_v3 t ON t.hadm_id = d.hadm_id
JOIN mimiciv.smm_code_patterns_v2 p
  ON p.code_type = 'DX' AND p.icd_version = d.icd_version
 AND ( (p.match_type = 'PREFIX' AND d.icd_code LIKE p.code_pattern || '%')
    OR (p.match_type = 'EXACT'  AND d.icd_code = p.code_pattern) )
LEFT JOIN mimiciv.d_icd_diagnoses dd ON dd.icd_code = d.icd_code AND dd.icd_version = d.icd_version
UNION ALL
SELECT r.hadm_id, p.indicator_name, p.code_type, p.icd_version, p.code_pattern, p.match_type,
       r.icd_code, dp.long_title
FROM mimiciv.procedures_icd r
JOIN mimiciv.timing_flags_v3 t ON t.hadm_id = r.hadm_id
JOIN mimiciv.smm_code_patterns_v2 p
  ON p.code_type = 'PR' AND p.icd_version = r.icd_version
 AND ( (p.match_type = 'PREFIX' AND r.icd_code LIKE p.code_pattern || '%')
    OR (p.match_type = 'EXACT'  AND r.icd_code = p.code_pattern) )
LEFT JOIN mimiciv.d_icd_procedures dp ON dp.icd_code = r.icd_code AND dp.icd_version = r.icd_version;
CREATE INDEX ON mimiciv.smm_code_hits_v3 (hadm_id);

-- A1  Matched codes per pattern (export this table to the supplement)
SELECT indicator_name, icd_version, code_type, code_pattern, match_type,
       icd_code, long_title,
       (icd_code <> code_pattern)            AS expanded_by_prefix,
       COUNT(DISTINCT hadm_id)               AS n_admissions
FROM mimiciv.smm_code_hits_v3
GROUP BY 1,2,3,4,5,6,7
ORDER BY indicator_name, icd_version, code_pattern, n_admissions DESC;

-- A2  Codes that are the ONLY qualifying code of an SMM admission
WITH per_adm AS (
    SELECT hadm_id, COUNT(DISTINCT icd_code) AS n_codes FROM mimiciv.smm_code_hits_v3 GROUP BY hadm_id
)
SELECT h.indicator_name, h.icd_version, h.icd_code, h.long_title,
       (h.icd_code <> h.code_pattern) AS expanded_by_prefix,
       COUNT(DISTINCT h.hadm_id)      AS n_admissions_depending_on_this_code
FROM mimiciv.smm_code_hits_v3 h
JOIN per_adm a ON a.hadm_id = h.hadm_id AND a.n_codes = 1
GROUP BY 1,2,3,4,5
ORDER BY n_admissions_depending_on_this_code DESC;

-- A3  Historically used codes not in the current list
WITH hist AS (
    SELECT r.hadm_id, 'Blood transfusion (historical 21st indicator)' AS item,
           CAST(r.chartdate AS TIMESTAMP) AS d
    FROM mimiciv.procedures_icd r JOIN mimiciv.timing_flags_v3 t ON t.hadm_id = r.hadm_id
    WHERE (r.icd_version = 9  AND r.icd_code LIKE '990%')
       OR (r.icd_version = 10 AND r.icd_code ~ '^302(30|33|40|43)[HKLMNPRTVW][01]$')
    UNION ALL
    SELECT d.hadm_id, 'T81.4XXA (sepsis, used before FY2019)', NULL
    FROM mimiciv.diagnoses_icd d JOIN mimiciv.timing_flags_v3 t ON t.hadm_id = d.hadm_id
    WHERE d.icd_version = 10 AND d.icd_code = 'T814XXA'
)
SELECT h.item,
       COUNT(DISTINCT h.hadm_id)                                  AS n_admissions,
       COUNT(DISTINCT h.hadm_id) FILTER (WHERE NOT t.smm_any)     AS n_would_become_new_smm
FROM hist h JOIN mimiciv.timing_flags_v3 t ON t.hadm_id = h.hadm_id
GROUP BY 1 ORDER BY 1;

-- A4  Label counts under alternative definitions
WITH transf AS (
    SELECT DISTINCT r.hadm_id FROM mimiciv.procedures_icd r
    JOIN mimiciv.timing_flags_v3 t ON t.hadm_id = r.hadm_id
    WHERE (r.icd_version = 9  AND r.icd_code LIKE '990%')
       OR (r.icd_version = 10 AND r.icd_code ~ '^302(30|33|40|43)[HKLMNPRTVW][01]$')
),
exact10 AS (   -- ICD-10 hits only when the code equals the listed pattern or is a
               -- 7th-character/laterality completion of a code the CDC lists in full
    SELECT DISTINCT hadm_id FROM mimiciv.smm_code_hits_v3
    WHERE icd_version = 9 OR icd_code = code_pattern
)
SELECT COUNT(*)                                                      AS n_eligible_deliveries,
       COUNT(*) FILTER (WHERE smm_any)                               AS smm_20_indicators,
       COUNT(*) FILTER (WHERE smm_any OR hadm_id IN (SELECT hadm_id FROM transf)) AS smm_21_with_transfusion,
       COUNT(*) FILTER (WHERE hadm_id IN (SELECT hadm_id FROM exact10)) AS smm_20_exact_icd10_only
FROM mimiciv.timing_flags_v3;
-- Note on A4: "exact" is deliberately conservative -- many CDC ICD-10 entries are
-- 3- or 4-character categories meant to include their subcodes, so this column is a
-- lower bound used only to show how much of the label rests on prefix expansion.
-- The authoritative check is A1, checked code by code against the CDC page.
