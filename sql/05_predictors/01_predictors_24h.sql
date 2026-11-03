-- ============================================================================
-- 05_predictors / 01_predictors_24h.sql
-- Predictors restricted to the first 24 hours of the hospitalization
--
-- ============================================================================
-- Why: in the v1 datasets (sql/03_cohort_smm/smm_dataset.sql and the
--   equivalent mortality dataset) every laboratory value and chart value is the
--   FIRST value of the whole hospitalization, with no time limit; chart values
--   come only from the first ICU stay; icu_stay and icu_stay_count use the whole
--   hospitalization; and the 28 gdg_m* indicators come from the first four
--   DISCHARGE diagnoses (seq_num <= 4).  None of these is known at a fixed
--   prediction time.
--
-- Decisions applied (analysis decisions):
--   D3  Prediction point = 24 hours after the hospital admission time (admittime + 24 h).
--   D10 Predictor window = from 24 hours BEFORE admittime up to the prediction point (admittime + 24 h).  Values from the
--       triage or emergency visit that precede the admission time are available at the prediction
--       point, so they are not leakage; the lower bound of 24 h before admission keeps them within
--       the same episode.  (Q-F5 of the first run showed that with a window starting at admittime,
--       4,830 delivery hospitalizations lost a haemoglobin that was measured only in that period.)
--   D8  Admissions that end (discharge or death) before 24 h are NOT eligible
--       for the 24-hour model (eligible_24h = false); they are kept in the table
--       so that their events can be reported separately.
--   The gdg_m* indicators are NOT built here (discharge diagnoses).
--   icu_stay_count is replaced by icu_in_24h (ICU admission before admittime + 24 h).  ICU-only
--   variables (vital signs, Glasgow, RASS, PEEP, weight, height) and icu_in_24h are kept in the
--   table but marked model_role = 'ICU sensitivity only' in the dictionary: they do not exist
--   outside the ICU (Q-F4) and icu_in_24h is closely tied to the outcome (Q-F3).
--
-- What this script creates (new names only; nothing existing is modified):
--   mimiciv.predictor_dictionary_v2   one row per predictor: item ids, labels, previous name
--   mimiciv.predictor_firsts_v2       first value of each predictor inside the window (long)
--   mimiciv.predictors_24h_v2         one row per obstetric admission (wide), with
--                                     eligibility, ICU timing, outcome flags and the 27 predictors
--
-- Requires: 04_cohort_obstetric_flags.sql (mimiciv.cohort_obstetric_v2).
-- Laboratory values are matched by patient and time (hadm_id equal to the admission
--   OR missing), so a laboratory value taken inside the window with no hadm_id is not lost.
-- Run the whole script (DBeaver: Alt+X).  It reads chartevents and labevents only for the
--   patients of the cohort (indexed by subject_id).  Share only the aggregate results of
--   the count queries (Q-F0 .. Q-F5), never row-level data.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Step 1 -- predictor dictionary (same 27 chart/laboratory variables as the v1 datasets)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.predictors_24h_v2;
DROP TABLE IF EXISTS mimiciv.predictor_firsts_v2;
DROP TABLE IF EXISTS mimiciv.predictor_dictionary_v2;

CREATE TABLE mimiciv.predictor_dictionary_v2 (
    variable        text PRIMARY KEY,   -- name used from now on (corrected spelling)
    previous_name   text NOT NULL,      -- name in the v1 dataset and manuscript
    chart_itemid    integer,            -- chartevents.itemid (ICU)
    lab_itemid      integer,            -- labevents.itemid (hospital-wide)
    chart_label     text,
    lab_label       text,
    source          text,
    model_role      text,               -- 'main model' or 'ICU sensitivity only'
    window_rule     text DEFAULT 'first value with admittime - 24 h <= charttime <= admittime + 24 h'
);

INSERT INTO mimiciv.predictor_dictionary_v2 (variable, previous_name, chart_itemid, lab_itemid) VALUES
    ('heart_rate', 'heart_rate', 220045, NULL),
    ('respiratory_rate', 'respiratory_rate', 220210, NULL),
    ('o2_saturation', 'o2_saturation', 220277, NULL),
    ('pressure_blood_mean', 'pressure_blood_mean', 220181, NULL),
    ('pressure_blood_systolic', 'pressure_blood_systolic', 220179, NULL),
    ('pressure_blood_diastolic', 'pressure_blood_diastolic', 220180, NULL),
    ('temperature_fahrenheit', 'temperature_fahrenheit', 223761, NULL),
    ('weight_admission', 'weight_admission', 226512, NULL),
    ('gcs_eye_opening', 'gcs_eye_opening', 220739, NULL),
    ('gcs_verbal_response', 'gcs_verbal_response', 223900, NULL),
    ('gcs_motor_response', 'gcs_motor_response', 223901, NULL),
    ('richmond_ras_scale', 'richmond_ras_scale', 228096, NULL),
    ('peep_set', 'peep_set', 220339, NULL),
    ('height', 'height', 226730, NULL),
    ('glucose', 'glucose', 220621, 50931),
    ('hemoglobin', 'hemoglobine', 220228, 51222),
    ('sodium', 'sodium', 220645, 50983),
    ('potassium', 'potassium', 227442, 50971),
    ('calcium_noionized', 'noionized_calcium', 225625, 50893),
    ('magnesium', 'magnesium', 220635, 50960),
    ('chloride', 'chloride', 220602, 50902),
    ('bicarbonate', 'bicarbonate', 227443, 50882),
    ('phosphorus', 'phosphorus', 225677, 50970),
    ('creatinine', 'creatine', 220615, 50912),
    ('hematocrit', 'hematrocit', 220545, 51221),
    ('lactate', 'lactic_acid', 225668, 50813),
    ('anion_gap', 'anion_gap', 227073, 50868);

UPDATE mimiciv.predictor_dictionary_v2 d SET chart_label = i.label
FROM mimiciv.d_items i WHERE i.itemid = d.chart_itemid;
UPDATE mimiciv.predictor_dictionary_v2 d SET lab_label = l.label
FROM mimiciv.d_labitems l WHERE l.itemid = d.lab_itemid;
UPDATE mimiciv.predictor_dictionary_v2
SET source     = CASE WHEN lab_itemid IS NULL THEN 'chartevents (ICU)' ELSE 'chartevents (ICU) or labevents' END,
    model_role = CASE WHEN lab_itemid IS NULL THEN 'ICU sensitivity only' ELSE 'main model' END;

-- ----------------------------------------------------------------------------
-- Step 2 -- first value of each predictor inside the window (admittime - 24 h to admittime + 24 h; long format)
-- ----------------------------------------------------------------------------
CREATE TABLE mimiciv.predictor_firsts_v2 AS
WITH w AS (
    SELECT c.subject_id, c.hadm_id, c.admittime,
           c.admittime - interval '24 hours' AS t_start,
           c.admittime + interval '24 hours' AS t_end
    FROM mimiciv.cohort_obstetric_v2 c
),
chart AS (
    SELECT w.hadm_id, w.admittime, d.variable, 'chartevents'::text AS source, ce.charttime, ce.valuenum
    FROM w
    JOIN mimiciv.chartevents ce
      ON ce.subject_id = w.subject_id AND ce.hadm_id = w.hadm_id
    JOIN mimiciv.predictor_dictionary_v2 d ON d.chart_itemid = ce.itemid
    WHERE ce.valuenum IS NOT NULL
      AND ce.charttime >= w.t_start AND ce.charttime <= w.t_end
),
lab AS (
    SELECT w.hadm_id, w.admittime, d.variable, 'labevents'::text AS source, le.charttime, le.valuenum
    FROM w
    JOIN mimiciv.labevents le
      ON le.subject_id = w.subject_id AND (le.hadm_id = w.hadm_id OR le.hadm_id IS NULL)
    JOIN mimiciv.predictor_dictionary_v2 d ON d.lab_itemid = le.itemid
    WHERE le.valuenum IS NOT NULL
      AND le.charttime >= w.t_start AND le.charttime <= w.t_end
),
allv AS (
    SELECT * FROM chart UNION ALL SELECT * FROM lab
)
SELECT DISTINCT ON (hadm_id, variable)
       hadm_id, variable, source, charttime, valuenum,
       ROUND((EXTRACT(EPOCH FROM (charttime - admittime)) / 3600.0)::numeric, 2) AS hours_from_admission
FROM allv
ORDER BY hadm_id, variable, charttime ASC, valuenum DESC, source;

CREATE INDEX ON mimiciv.predictor_firsts_v2 (hadm_id);

-- ----------------------------------------------------------------------------
-- Step 3 -- one row per obstetric admission (wide)
-- ----------------------------------------------------------------------------
CREATE TABLE mimiciv.predictors_24h_v2 AS
WITH base AS (
    SELECT c.subject_id, c.hadm_id, c.admittime, a.dischtime, a.deathtime,
           c.admittime - interval '24 hours'                          AS t_start,
           c.admittime + interval '24 hours'                          AS t_end,
           c.approx_age                                               AS age_at_admission,
           a.ethnicity, a.insurance, a.language, a.admission_type, a.admission_location,
           c.is_delivery_v2, c.has_structured_obst, c.smm_any, c.died_same_admission,
           (SELECT MIN(i.intime) FROM mimiciv.icustays i WHERE i.hadm_id = c.hadm_id) AS first_icu_intime
    FROM mimiciv.cohort_obstetric_v2 c
    JOIN mimiciv.admissions a ON a.hadm_id = c.hadm_id
),
wide AS (
    SELECT f.hadm_id,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'heart_rate') AS heart_rate,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'respiratory_rate') AS respiratory_rate,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'o2_saturation') AS o2_saturation,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'pressure_blood_mean') AS pressure_blood_mean,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'pressure_blood_systolic') AS pressure_blood_systolic,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'pressure_blood_diastolic') AS pressure_blood_diastolic,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'temperature_fahrenheit') AS temperature_fahrenheit,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'weight_admission') AS weight_admission,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'gcs_eye_opening') AS gcs_eye_opening,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'gcs_verbal_response') AS gcs_verbal_response,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'gcs_motor_response') AS gcs_motor_response,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'richmond_ras_scale') AS richmond_ras_scale,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'peep_set') AS peep_set,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'height') AS height,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'glucose') AS glucose,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'hemoglobin') AS hemoglobin,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'sodium') AS sodium,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'potassium') AS potassium,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'calcium_noionized') AS calcium_noionized,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'magnesium') AS magnesium,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'chloride') AS chloride,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'bicarbonate') AS bicarbonate,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'phosphorus') AS phosphorus,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'creatinine') AS creatinine,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'hematocrit') AS hematocrit,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'lactate') AS lactate,
       MAX(f.valuenum) FILTER (WHERE f.variable = 'anion_gap') AS anion_gap,
           COUNT(*) AS n_predictors_in_window
    FROM mimiciv.predictor_firsts_v2 f
    GROUP BY f.hadm_id
)
SELECT b.subject_id, b.hadm_id, b.admittime, b.dischtime, b.deathtime, b.t_start, b.t_end,
       ROUND((EXTRACT(EPOCH FROM (b.dischtime - b.admittime)) / 3600.0)::numeric, 2)        AS los_hours,
       ROUND((EXTRACT(EPOCH FROM (b.deathtime - b.admittime)) / 3600.0)::numeric, 2)        AS hours_to_death,
       (b.dischtime >= b.t_end AND (b.deathtime IS NULL OR b.deathtime > b.t_end))          AS eligible_24h,
       b.first_icu_intime,
       ROUND((EXTRACT(EPOCH FROM (b.first_icu_intime - b.admittime)) / 3600.0)::numeric, 2) AS hours_to_first_icu,
       (b.first_icu_intime IS NOT NULL AND b.first_icu_intime <= b.t_end)                   AS icu_in_24h,
       b.age_at_admission, b.ethnicity, b.insurance, b.language, b.admission_type, b.admission_location,
       b.is_delivery_v2, b.has_structured_obst, b.smm_any, b.died_same_admission,
       COALESCE(w.n_predictors_in_window, 0) AS n_predictors_in_window,
       w.heart_rate, w.respiratory_rate, w.o2_saturation, w.pressure_blood_mean, w.pressure_blood_systolic,
       w.pressure_blood_diastolic, w.temperature_fahrenheit, w.weight_admission, w.gcs_eye_opening,
       w.gcs_verbal_response, w.gcs_motor_response, w.richmond_ras_scale, w.peep_set, w.height,
       w.glucose, w.hemoglobin, w.sodium, w.potassium, w.calcium_noionized, w.magnesium, w.chloride,
       w.bicarbonate, w.phosphorus, w.creatinine, w.hematocrit, w.lactate, w.anion_gap
FROM base b
LEFT JOIN wide w ON w.hadm_id = b.hadm_id;

ALTER TABLE mimiciv.predictors_24h_v2 ADD PRIMARY KEY (hadm_id);
CREATE INDEX ON mimiciv.predictors_24h_v2 (subject_id);

-- ============================================================================
-- COUNT QUERIES (aggregate only) -- run each and paste the result
-- Scopes (same as D5/D6): Delivery = primary; Structured obstetric code = sensitivity;
--   Any obstetric admission = universe.
-- ============================================================================

-- Q-F0  Sanity: same rows as the cohort; rows of the long table; eligible admissions
SELECT (SELECT COUNT(*) FROM mimiciv.cohort_obstetric_v2)                   AS n_cohort,
       COUNT(*)                                                             AS n_rows,
       COUNT(DISTINCT hadm_id)                                              AS n_distinct_hadm,
       COUNT(*) FILTER (WHERE eligible_24h)                                 AS n_eligible_24h,
       (SELECT COUNT(*) FROM mimiciv.predictor_firsts_v2)                   AS n_values_in_window
FROM mimiciv.predictors_24h_v2;

-- Q-F1  Who is eligible for a 24-hour model, and which events are lost
SELECT s.scope,
       COUNT(*)                                                                         AS n_admissions,
       COUNT(*) FILTER (WHERE p.eligible_24h)                                           AS n_eligible,
       COUNT(DISTINCT p.subject_id) FILTER (WHERE p.eligible_24h)                       AS n_patients_eligible,
       COUNT(*) FILTER (WHERE NOT p.eligible_24h AND NOT COALESCE(p.died_same_admission, FALSE)) AS n_discharged_alive_before_24h,
       COUNT(*) FILTER (WHERE p.smm_any)                                                AS n_smm,
       COUNT(*) FILTER (WHERE p.smm_any AND p.eligible_24h)                             AS n_smm_eligible,
       COUNT(*) FILTER (WHERE p.died_same_admission)                                    AS n_died,
       COUNT(*) FILTER (WHERE p.died_same_admission AND p.eligible_24h)                 AS n_died_eligible,
       COUNT(*) FILTER (WHERE p.died_same_admission AND NOT p.eligible_24h)             AS n_died_before_24h
FROM mimiciv.predictors_24h_v2 p
JOIN LATERAL (VALUES
        ('Delivery hospitalization',                    COALESCE(p.is_delivery_v2, FALSE)),
        ('Structured obstetric code, any position',     COALESCE(p.has_structured_obst, FALSE)),
        ('Any obstetric admission',                     TRUE)
     ) AS s(scope, keep) ON s.keep
GROUP BY s.scope ORDER BY s.scope;

-- Q-F2  Hours from admission to death (admissions with death in the same admission)
SELECT CASE WHEN hours_to_death <= 6  THEN '0-6 h'
            WHEN hours_to_death <= 12 THEN '6-12 h'
            WHEN hours_to_death <= 24 THEN '12-24 h'
            WHEN hours_to_death <= 48 THEN '24-48 h'
            ELSE 'more than 48 h' END               AS hours_to_death_bucket,
       MIN(hours_to_death)                          AS sort_key,
       COUNT(*)                                     AS n_admissions,
       COUNT(*) FILTER (WHERE is_delivery_v2)       AS n_delivery,
       COUNT(*) FILTER (WHERE icu_in_24h)           AS n_icu_in_24h
FROM mimiciv.predictors_24h_v2
WHERE died_same_admission
GROUP BY 1 ORDER BY 2;

-- Q-F3  Timing of the first ICU admission and how it relates to the outcomes (ICU as a predictor)
SELECT CASE WHEN first_icu_intime IS NULL       THEN '1 no ICU stay'
            WHEN hours_to_first_icu <= 0        THEN '2 ICU at or before admission time'
            WHEN hours_to_first_icu <= 24       THEN '3 first ICU admission within 24 h'
            WHEN hours_to_first_icu <= 72       THEN '4 first ICU admission 24-72 h'
            ELSE                                     '5 first ICU admission after 72 h' END AS first_icu_timing,
       COUNT(*)                                                        AS n_admissions,
       COUNT(*) FILTER (WHERE is_delivery_v2)                          AS n_delivery,
       COUNT(*) FILTER (WHERE smm_any)                                 AS n_smm,
       COUNT(*) FILTER (WHERE smm_any AND is_delivery_v2)              AS n_smm_delivery,
       COUNT(*) FILTER (WHERE died_same_admission)                     AS n_died
FROM mimiciv.predictors_24h_v2
GROUP BY 1 ORDER BY 1;

-- Q-F4  Availability of each predictor inside the window: delivery hospitalizations eligible for the 24-hour model
--       (counts; overall, by ICU admission within 24 h, and by SMM)
WITH sc AS (
    SELECT * FROM mimiciv.predictors_24h_v2 WHERE is_delivery_v2 AND eligible_24h
),
long AS (
    SELECT sc.hadm_id, sc.icu_in_24h, sc.smm_any, kv.key AS variable, kv.value
    FROM sc CROSS JOIN LATERAL jsonb_each_text(to_jsonb(sc)) kv
    WHERE kv.key IN (SELECT variable FROM mimiciv.predictor_dictionary_v2)
)
SELECT long.variable, dd.model_role,
       COUNT(*)                                                          AS n_eligible_delivery,
       COUNT(value)                                                      AS n_with_value,
       COUNT(*) FILTER (WHERE icu_in_24h)                                AS n_icu_24h,
       COUNT(value) FILTER (WHERE icu_in_24h)                            AS n_icu_24h_with_value,
       COUNT(*) FILTER (WHERE NOT icu_in_24h)                            AS n_no_icu_24h,
       COUNT(value) FILTER (WHERE NOT icu_in_24h)                        AS n_no_icu_24h_with_value,
       COUNT(*) FILTER (WHERE smm_any)                                   AS n_smm,
       COUNT(value) FILTER (WHERE smm_any)                               AS n_smm_with_value
FROM long
JOIN mimiciv.predictor_dictionary_v2 dd ON dd.variable = long.variable
GROUP BY long.variable, dd.model_role ORDER BY dd.model_role, long.variable;

-- Q-F5  Laboratory timing in delivery hospitalizations (labs only): where the first value falls
--       relative to the window.  "before admission" = first value in the 24 h before admittime (kept);
--       "after 24 h" = the patient has values only after the prediction point (excluded);
--       "no value" = no value from 24 h before admittime until discharge.
WITH cohort AS (
    SELECT c.subject_id, c.hadm_id, c.admittime, a.dischtime,
           c.admittime - interval '24 hours' AS t_start, c.admittime + interval '24 hours' AS t_end
    FROM mimiciv.cohort_obstetric_v2 c
    JOIN mimiciv.admissions a ON a.hadm_id = c.hadm_id
    WHERE c.is_delivery_v2
),
lab_any AS (
    SELECT c.hadm_id, d.variable, MIN(le.charttime) AS first_time
    FROM cohort c
    JOIN mimiciv.labevents le
      ON le.subject_id = c.subject_id AND (le.hadm_id = c.hadm_id OR le.hadm_id IS NULL)
     AND le.charttime >= c.t_start AND le.charttime <= c.dischtime
     AND le.valuenum IS NOT NULL
    JOIN mimiciv.predictor_dictionary_v2 d ON d.lab_itemid = le.itemid
    GROUP BY c.hadm_id, d.variable
)
SELECT d.variable,
       (SELECT COUNT(*) FROM cohort)                                                          AS n_delivery,
       COUNT(*) FILTER (WHERE x.first_time <= cohort.t_end)                                   AS n_first_value_in_window,
       COUNT(*) FILTER (WHERE x.first_time <  cohort.admittime)                               AS n_of_them_before_admission,
       COUNT(*) FILTER (WHERE x.first_time >  cohort.t_end)                                   AS n_first_value_after_24h,
       COUNT(*) FILTER (WHERE x.hadm_id IS NULL)                                              AS n_no_value
FROM cohort
CROSS JOIN mimiciv.predictor_dictionary_v2 d
LEFT JOIN lab_any x ON x.hadm_id = cohort.hadm_id AND x.variable = d.variable
WHERE d.lab_itemid IS NOT NULL
GROUP BY d.variable ORDER BY d.variable;
