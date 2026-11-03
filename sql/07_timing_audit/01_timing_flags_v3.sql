-- ============================================================================
-- 07_timing_audit / 01_timing_flags_v3.sql
-- Timing of SMM evidence relative to the prediction point (T = admittime + 24 h)
-- and an approximate calendar-year interval per admission.
-- ============================================================================
-- Questions addressed:
--   (1) SMM is defined for the whole admission; part of the events precede T.
--         -> classify every SMM admission as prevalent / indeterminate /
--            incident (documented) / untimed, using
--              * procedure indicators (calendar date, as in notebook 07),
--              * ICU admission before T,
--              * acute kidney injury (AKI) timed from serum creatinine
--                (labevents.charttime), the dominant SMM indicator.
--   (2) anchor_year_group is fixed per patient.
--         -> approximate real-year interval of EACH admission:
--            [group_start + D, group_end + D], D = year(admittime) - anchor_year.
--
-- AKI definition (creatinine criteria only; urine output is not available
-- outside the ICU). A creatinine value at time t meets the definition when ANY of:
--   (k1) KDIGO: value - min(previous values in [t - 48 h, t))      >= 0.3 mg/dL
--   (k2) KDIGO: value / min(previous values in [t - 7 days, t))    >= 1.5
--   (k3) absolute, pregnancy-specific: value > 1.1 mg/dL
--        (renal-insufficiency criterion of preeclampsia with severe features,
--         ACOG Practice Bulletin 222)
-- AKI onset = first time t that meets the definition, searched from
-- admittime - 24 h to dischtime.  The thresholds are parameters (Step 0) and
-- must be confirmed by the clinical co-author before the final run.
--
-- Requires: mimiciv.predictors_24h_v2, mimiciv.smm_hits_v2,
--           mimiciv.smm_code_patterns_v2 (scripts 04_labels and 05_predictors).
-- Creates new objects only (*_v3).  Count queries return aggregates only.
-- ============================================================================

-- Session setting: run without parallel workers. PostgreSQL in Docker has only
-- 64 MB of shared memory (/dev/shm) by default and parallel scans of labevents
-- fail with "could not resize shared memory segment ... No space left on device".
-- (Permanent fix: shm_size in docker-compose.yml.)  Only affects this session.
SET max_parallel_workers_per_gather = 0;

-- ----------------------------------------------------------------------------
-- Step 0 -- parameters
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.params_timing_v3;
CREATE TABLE mimiciv.params_timing_v3 AS
SELECT 0.3::numeric  AS k1_abs_rise,      -- mg/dL within 48 h
       1.5::numeric  AS k2_ratio,         -- x minimum of previous 7 days
       1.1::numeric  AS k3_abs_value,     -- mg/dL, value strictly above
       50912         AS creat_itemid;     -- labevents creatinine (same item as the predictor)

-- ----------------------------------------------------------------------------
-- Step 1 -- creatinine series for the whole hospitalization (eligible deliveries)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.creat_series_v3;
CREATE TABLE mimiciv.creat_series_v3 AS
SELECT DISTINCT p.hadm_id, le.charttime, le.valuenum
FROM mimiciv.predictors_24h_v2 p
JOIN mimiciv.labevents le
  ON le.subject_id = p.subject_id
 AND (le.hadm_id = p.hadm_id OR le.hadm_id IS NULL)
 AND le.itemid = (SELECT creat_itemid FROM mimiciv.params_timing_v3)
WHERE p.eligible_24h AND p.is_delivery_v2
  AND le.valuenum IS NOT NULL
  AND le.valuenum BETWEEN 0.1 AND 20            -- plausibility limits of the dictionary
  AND le.charttime >= p.admittime - INTERVAL '24 hours'
  AND le.charttime <= p.dischtime;
CREATE INDEX ON mimiciv.creat_series_v3 (hadm_id, charttime);

-- ----------------------------------------------------------------------------
-- Step 2 -- AKI onset per admission
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.aki_onset_v3;
CREATE TABLE mimiciv.aki_onset_v3 AS
WITH flagged AS (
    SELECT s.hadm_id, s.charttime, s.valuenum,
           (s.valuenum - m48.min48 >= prm.k1_abs_rise)      AS k1,
           (s.valuenum / NULLIF(m7.min7, 0) >= prm.k2_ratio) AS k2,
           (s.valuenum > prm.k3_abs_value)                   AS k3
    FROM mimiciv.creat_series_v3 s
    CROSS JOIN mimiciv.params_timing_v3 prm
    LEFT JOIN LATERAL (
        SELECT MIN(x.valuenum) AS min48 FROM mimiciv.creat_series_v3 x
        WHERE x.hadm_id = s.hadm_id
          AND x.charttime >= s.charttime - INTERVAL '48 hours' AND x.charttime < s.charttime) m48 ON TRUE
    LEFT JOIN LATERAL (
        SELECT MIN(x.valuenum) AS min7 FROM mimiciv.creat_series_v3 x
        WHERE x.hadm_id = s.hadm_id
          AND x.charttime >= s.charttime - INTERVAL '7 days' AND x.charttime < s.charttime) m7 ON TRUE
)
SELECT hadm_id,
       COUNT(*)                                                               AS n_creat_values,
       MIN(charttime) FILTER (WHERE COALESCE(k1,FALSE) OR COALESCE(k2,FALSE) OR k3) AS aki_onset,
       MIN(charttime) FILTER (WHERE COALESCE(k1,FALSE) OR COALESCE(k2,FALSE))       AS aki_onset_kdigo_only,
       BOOL_OR(COALESCE(k1,FALSE) OR COALESCE(k2,FALSE))                       AS any_kdigo,
       BOOL_OR(k3)                                                             AS any_abs
FROM flagged
GROUP BY hadm_id;
CREATE INDEX ON mimiciv.aki_onset_v3 (hadm_id);

-- ----------------------------------------------------------------------------
-- Step 3 -- timing flags, one row per eligible delivery hospitalization
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.timing_flags_v3;
CREATE TABLE mimiciv.timing_flags_v3 AS
WITH base AS (
    SELECT p.subject_id, p.hadm_id, p.admittime, p.admittime + INTERVAL '24 hours' AS t_pred,
           p.icu_in_24h, p.smm_any
    FROM mimiciv.predictors_24h_v2 p
    WHERE p.eligible_24h AND p.is_delivery_v2
),
pr AS (   -- procedure-based SMM indicators with their timing (same rule as notebook 07)
    SELECT b.hadm_id,
           BOOL_OR(CAST(r.chartdate AS TIMESTAMP) + INTERVAL '1 day' <= b.t_pred) AS proc_before,
           BOOL_OR(CAST(r.chartdate AS TIMESTAMP) + INTERVAL '1 day' >  b.t_pred
               AND CAST(r.chartdate AS TIMESTAMP) < b.t_pred)                       AS proc_ambiguous,
           BOOL_OR(CAST(r.chartdate AS TIMESTAMP) >= b.t_pred)                      AS proc_after
    FROM base b
    JOIN mimiciv.procedures_icd r ON r.hadm_id = b.hadm_id
    JOIN mimiciv.smm_code_patterns_v2 p
      ON p.code_type = 'PR' AND p.icd_version = r.icd_version
     AND ( (p.match_type = 'PREFIX' AND r.icd_code LIKE p.code_pattern || '%')
        OR (p.match_type = 'EXACT'  AND r.icd_code = p.code_pattern) )
    GROUP BY b.hadm_id
),
dx AS (   -- diagnosis-based indicators (no time), split renal vs other
    SELECT h.hadm_id,
           BOOL_OR(h.indicator_name = 'Acute renal failure')                         AS has_renal,
           COUNT(DISTINCT h.indicator_name) FILTER (
               WHERE h.indicator_name <> 'Acute renal failure'
                 AND h.indicator_name NOT IN (SELECT DISTINCT indicator_name
                                              FROM mimiciv.smm_code_patterns_v2
                                              WHERE code_type = 'PR'))               AS n_other_dx_ind
    FROM mimiciv.smm_hits_v2 h
    JOIN base b ON b.hadm_id = h.hadm_id
    GROUP BY h.hadm_id
),
yr AS (
    SELECT b.hadm_id,
           CAST(LEFT(pt.anchor_year_group, 4) AS int)  + (EXTRACT(YEAR FROM b.admittime)::int - pt.anchor_year) AS year_lo,
           CAST(RIGHT(pt.anchor_year_group, 4) AS int) + (EXTRACT(YEAR FROM b.admittime)::int - pt.anchor_year) AS year_hi
    FROM base b JOIN mimiciv.patients pt ON pt.subject_id = b.subject_id
),
j AS (
    SELECT b.*,
           COALESCE(pr.proc_before, FALSE)    AS proc_before,
           COALESCE(pr.proc_ambiguous, FALSE) AS proc_ambiguous,
           COALESCE(pr.proc_after, FALSE)     AS proc_after,
           COALESCE(dx.has_renal, FALSE)      AS smm_renal,
           COALESCE(dx.n_other_dx_ind, 0)     AS n_other_dx_ind,
           a.n_creat_values, a.aki_onset, a.any_kdigo, a.any_abs,
           (a.aki_onset IS NOT NULL AND a.aki_onset <= b.t_pred) AS aki_prevalent,
           (a.aki_onset IS NOT NULL AND a.aki_onset >  b.t_pred) AS aki_incident,
           yr.year_lo, yr.year_hi
    FROM base b
    LEFT JOIN pr ON pr.hadm_id = b.hadm_id
    LEFT JOIN dx ON dx.hadm_id = b.hadm_id
    LEFT JOIN mimiciv.aki_onset_v3 a ON a.hadm_id = b.hadm_id
    LEFT JOIN yr ON yr.hadm_id = b.hadm_id
)
SELECT j.*,
       CASE
         WHEN NOT j.smm_any THEN 'no SMM'
         WHEN j.proc_before OR j.icu_in_24h OR (j.smm_renal AND j.aki_prevalent)
              THEN '1 prevalent'
         WHEN j.proc_ambiguous
              THEN '2 indeterminate'
         WHEN j.proc_after OR (j.smm_renal AND j.aki_incident)
              THEN '3 incident (documented)'
         ELSE '4 untimed'
       END AS smm_timing_class,
       -- strict version: documented incident AND no untimed non-renal diagnosis indicator
       (j.smm_any AND NOT (j.proc_before OR j.icu_in_24h OR (j.smm_renal AND j.aki_prevalent) OR j.proc_ambiguous)
                  AND (j.proc_after OR (j.smm_renal AND j.aki_incident))
                  AND j.n_other_dx_ind = 0)                                AS smm_incident_strict
FROM j;
ALTER TABLE mimiciv.timing_flags_v3 ADD PRIMARY KEY (hadm_id);

-- ============================================================================
-- COUNT QUERIES (aggregate only) -- run each and paste the result
-- ============================================================================

-- Q-T0  Sanity: expected 19,383 rows and 445 SMM
SELECT COUNT(*) AS n, COUNT(*) FILTER (WHERE smm_any) AS n_smm,
       COUNT(*) FILTER (WHERE icu_in_24h) AS n_icu24
FROM mimiciv.timing_flags_v3;

-- Q-T1  SMM admissions by timing class (key table on the timing of the outcome)
SELECT smm_timing_class, COUNT(*) AS n,
       COUNT(*) FILTER (WHERE smm_renal)              AS with_renal,
       COUNT(*) FILTER (WHERE n_other_dx_ind > 0)     AS with_other_dx,
       COUNT(*) FILTER (WHERE smm_incident_strict)    AS strict_incident
FROM mimiciv.timing_flags_v3
GROUP BY 1 ORDER BY 1;

-- Q-T2  Renal-failure SMM: agreement of the code with laboratory AKI
SELECT CASE WHEN n_creat_values IS NULL        THEN 'a no creatinine in stay'
            WHEN aki_onset IS NULL             THEN 'b creatinine, no AKI by criteria'
            WHEN aki_onset <= admittime + INTERVAL '24 hours' THEN 'c AKI onset at or before T'
            ELSE 'd AKI onset after T' END AS renal_lab_status,
       COUNT(*) AS n_renal_smm,
       COUNT(*) FILTER (WHERE any_kdigo) AS by_kdigo_rise,
       COUNT(*) FILTER (WHERE any_abs)   AS by_absolute
FROM mimiciv.timing_flags_v3
WHERE smm_any AND smm_renal
GROUP BY 1 ORDER BY 1;

-- Q-T3  Laboratory AKI in admissions WITHOUT an SMM code (how specific the code is)
SELECT COUNT(*) FILTER (WHERE NOT smm_any)                       AS n_no_smm,
       COUNT(*) FILTER (WHERE NOT smm_any AND aki_prevalent)      AS aki_prev_no_smm,
       COUNT(*) FILTER (WHERE NOT smm_any AND aki_incident)       AS aki_inc_no_smm
FROM mimiciv.timing_flags_v3;

-- Q-T4  Approximate real-year interval: admissions that are unambiguously before /
--       after candidate cut years (for the revised temporal validation)
SELECT cut,
       COUNT(*) FILTER (WHERE year_hi <  cut) AS n_surely_before,
       COUNT(*) FILTER (WHERE year_lo >= cut) AS n_surely_after,
       COUNT(*) FILTER (WHERE year_lo < cut AND year_hi >= cut) AS n_straddling,
       COUNT(*) FILTER (WHERE year_hi <  cut AND smm_any) AS smm_before,
       COUNT(*) FILTER (WHERE year_lo >= cut AND smm_any) AS smm_after
FROM mimiciv.timing_flags_v3
CROSS JOIN (VALUES (2011), (2013), (2015), (2017), (2019)) c(cut)
GROUP BY cut ORDER BY cut;
