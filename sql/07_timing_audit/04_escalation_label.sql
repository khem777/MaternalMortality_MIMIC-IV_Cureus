-- ============================================================================
-- 07_timing_audit / 04_escalation_label.sql
-- Admission-level label for the timed outcome of return R2:
-- escalation of care AFTER the prediction point (T = admittime + 24 h).
-- Framework: Return R2 (back to E3): admission-level label of the timed outcome (contract column label_timed).
-- ============================================================================
-- Same definition as 03_escalation_counts.sql (which returns counts only):
--   (e1) ICU admission with intime after T                (icustays.intime, exact time)
--   (e2) invasive mechanical ventilation started after T  (procedureevents itemid 225792, exact time; ICU only)
--   (e3) procedure-based SMM indicator dated after T      (procedures_icd.chartdate >= T, same rule as notebook 07)
--   (e4) in-hospital death after T                        (admissions.deathtime)
-- Population: eligible delivery hospitalizations WITHOUT an ICU admission before T
-- (they are already escalated at the prediction point).
--
-- Creates one NEW table (nothing existing is modified):
--   mimiciv.escalation_v3   one row per admission of the population, with the four
--                           component flags and the composite (escalation_any).
-- Expected (Q-E1 of 03_escalation_counts.sql): 19,268 admissions, 101 with escalation.
-- Read by notebooks/08_landmark_incident_smm.ipynb, section 11.
-- Run after 01_timing_flags_v3.sql.  The check query returns aggregates only.
-- ============================================================================
SET max_parallel_workers_per_gather = 0;

DROP TABLE IF EXISTS mimiciv.escalation_v3;
CREATE TABLE mimiciv.escalation_v3 AS
WITH base AS (
    SELECT p.hadm_id, p.admittime + INTERVAL '24 hours' AS t_pred, a.deathtime
    FROM mimiciv.predictors_24h_v2 p
    JOIN mimiciv.admissions a ON a.hadm_id = p.hadm_id
    WHERE p.eligible_24h AND p.is_delivery_v2 AND NOT COALESCE(p.icu_in_24h, FALSE)
),
e1 AS (SELECT DISTINCT b.hadm_id FROM base b JOIN mimiciv.icustays i ON i.hadm_id = b.hadm_id
       WHERE i.intime > b.t_pred),
e2 AS (SELECT DISTINCT b.hadm_id FROM base b JOIN mimiciv.procedureevents pe ON pe.hadm_id = b.hadm_id
       WHERE pe.itemid = 225792 AND pe.starttime > b.t_pred),
e3 AS (SELECT DISTINCT b.hadm_id FROM base b
       JOIN mimiciv.procedures_icd r ON r.hadm_id = b.hadm_id
       JOIN mimiciv.smm_code_patterns_v2 p
         ON p.code_type = 'PR' AND p.icd_version = r.icd_version
        AND ( (p.match_type = 'PREFIX' AND r.icd_code LIKE p.code_pattern || '%')
           OR (p.match_type = 'EXACT'  AND r.icd_code = p.code_pattern) )
       WHERE CAST(r.chartdate AS TIMESTAMP) >= b.t_pred),
e4 AS (SELECT hadm_id FROM base WHERE deathtime > t_pred)
SELECT b.hadm_id,
       (e1.hadm_id IS NOT NULL) AS icu_after,
       (e2.hadm_id IS NOT NULL) AS vent_after,
       (e3.hadm_id IS NOT NULL) AS smm_proc_after,
       (e4.hadm_id IS NOT NULL) AS death_after,
       (e1.hadm_id IS NOT NULL OR e2.hadm_id IS NOT NULL OR e3.hadm_id IS NOT NULL OR e4.hadm_id IS NOT NULL) AS escalation_any
FROM base b
LEFT JOIN e1 ON e1.hadm_id = b.hadm_id
LEFT JOIN e2 ON e2.hadm_id = b.hadm_id
LEFT JOIN e3 ON e3.hadm_id = b.hadm_id
LEFT JOIN e4 ON e4.hadm_id = b.hadm_id;

CREATE UNIQUE INDEX ON mimiciv.escalation_v3 (hadm_id);

-- Q-E2  Check against Q-E1 (expected 19,268 admissions and 101 with escalation)
SELECT COUNT(*)                                   AS n_population,
       COUNT(*) FILTER (WHERE icu_after)          AS icu_after,
       COUNT(*) FILTER (WHERE vent_after)         AS vent_after,
       COUNT(*) FILTER (WHERE smm_proc_after)     AS smm_proc_after,
       COUNT(*) FILTER (WHERE death_after)        AS death_after,
       COUNT(*) FILTER (WHERE escalation_any)     AS escalation_any
FROM mimiciv.escalation_v3;
