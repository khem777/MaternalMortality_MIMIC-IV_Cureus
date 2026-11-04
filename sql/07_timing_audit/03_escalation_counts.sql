-- ============================================================================
-- 07_timing_audit / 03_escalation_counts.sql
-- Candidate timed outcome: escalation of care AFTER the prediction point
-- (T = admittime + 24 h), independent of laboratory testing.
-- ============================================================================
-- Components (each with its own time stamp):
--   (e1) ICU admission with intime after T                (icustays.intime, exact time)
--   (e2) invasive mechanical ventilation started after T  (procedureevents itemid 225792, exact time; ICU only)
--   (e3) procedure-based SMM indicator dated after T      (procedures_icd.chartdate >= T, same rule as notebook 07)
--   (e4) in-hospital death after T                        (admissions.deathtime)
-- Population: eligible delivery hospitalizations WITHOUT an ICU admission before T
-- (they are already escalated at the prediction point).
-- READ-ONLY: SELECTs only, aggregate counts only.  Run after 01_timing_flags_v3.sql.
-- ============================================================================
SET max_parallel_workers_per_gather = 0;

WITH base AS (
    SELECT p.hadm_id, p.admittime + INTERVAL '24 hours' AS t_pred, p.smm_any, a.deathtime
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
e4 AS (SELECT hadm_id FROM base WHERE deathtime > t_pred),
flags AS (
    SELECT b.hadm_id, b.smm_any,
           (e1.hadm_id IS NOT NULL) AS icu_after,
           (e2.hadm_id IS NOT NULL) AS vent_after,
           (e3.hadm_id IS NOT NULL) AS smm_proc_after,
           (e4.hadm_id IS NOT NULL) AS death_after
    FROM base b
    LEFT JOIN e1 ON e1.hadm_id = b.hadm_id
    LEFT JOIN e2 ON e2.hadm_id = b.hadm_id
    LEFT JOIN e3 ON e3.hadm_id = b.hadm_id
    LEFT JOIN e4 ON e4.hadm_id = b.hadm_id
)
-- Q-E1  Events per component and for the composite, overall and by SMM label
SELECT COUNT(*)                                                                AS n_population,
       COUNT(*) FILTER (WHERE icu_after)                                       AS icu_after,
       COUNT(*) FILTER (WHERE vent_after)                                      AS vent_after,
       COUNT(*) FILTER (WHERE smm_proc_after)                                  AS smm_proc_after,
       COUNT(*) FILTER (WHERE death_after)                                     AS death_after,
       COUNT(*) FILTER (WHERE icu_after OR vent_after OR smm_proc_after OR death_after) AS escalation_any,
       COUNT(*) FILTER (WHERE (icu_after OR vent_after OR smm_proc_after OR death_after) AND smm_any)     AS escalation_with_smm_label,
       COUNT(*) FILTER (WHERE (icu_after OR vent_after OR smm_proc_after OR death_after) AND NOT smm_any) AS escalation_without_smm_label,
       COUNT(*) FILTER (WHERE smm_any)                                         AS smm_label_in_population
FROM flags;
