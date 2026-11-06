-- ============================================================================
-- 08_tables / 02_supplement_predictors_es.sql
-- Suplemento 2: diccionario de predictores y disponibilidad (% con valor en la ventana)
-- por predictor, en total y por SMM, ingreso a UCI antes de 24 h y versión de la CIE.
-- Framework: E7 Predictores; responde a los comentarios R1-7 y R2-20 de los revisores.
-- ============================================================================
-- Population: eligible delivery hospitalizations (19,383). Window: first value from
-- 24 h before to 24 h after admission; values outside the plausibility limits of the
-- dictionary count as missing. READ-ONLY; aggregates only. A percentage whose
-- numerator is between 1 and 9 is shown as '<10'; within each pair of strata
-- (SMM / no SMM, ICU / no ICU, ICD-9 / ICD-10) both cells are hidden if either is small,
-- so that no small count can be recovered by subtraction from the total.
-- Denominators: all 19,383; SMM 445 / no SMM 18,938; ICU before 24 h 115 / no 19,268;
-- ICD-9 10,519 / ICD-10 8,864.
-- Requires: mimiciv.predictors_24h_v2, mimiciv.predictor_dictionary_final_v2.
-- ============================================================================
SET max_parallel_workers_per_gather = 0;

-- Q-S2  One row per predictor
WITH base AS (
    SELECT p.hadm_id, p.smm_any, p.icu_in_24h,
           (SELECT MAX(d.icd_version) FROM mimiciv.diagnoses_icd d WHERE d.hadm_id = p.hadm_id) AS icd_version,
           v.variable, v.value
    FROM mimiciv.predictors_24h_v2 p
    CROSS JOIN LATERAL (VALUES
                 ('heart_rate', p.heart_rate),
                 ('respiratory_rate', p.respiratory_rate),
                 ('o2_saturation', p.o2_saturation),
                 ('pressure_blood_mean', p.pressure_blood_mean),
                 ('pressure_blood_systolic', p.pressure_blood_systolic),
                 ('pressure_blood_diastolic', p.pressure_blood_diastolic),
                 ('temperature_fahrenheit', p.temperature_fahrenheit),
                 ('weight_admission', p.weight_admission),
                 ('gcs_eye_opening', p.gcs_eye_opening),
                 ('gcs_verbal_response', p.gcs_verbal_response),
                 ('gcs_motor_response', p.gcs_motor_response),
                 ('richmond_ras_scale', p.richmond_ras_scale),
                 ('peep_set', p.peep_set),
                 ('height', p.height),
                 ('glucose', p.glucose),
                 ('hemoglobin', p.hemoglobin),
                 ('sodium', p.sodium),
                 ('potassium', p.potassium),
                 ('calcium_noionized', p.calcium_noionized),
                 ('magnesium', p.magnesium),
                 ('chloride', p.chloride),
                 ('bicarbonate', p.bicarbonate),
                 ('phosphorus', p.phosphorus),
                 ('creatinine', p.creatinine),
                 ('hematocrit', p.hematocrit),
                 ('lactate', p.lactate),
                 ('anion_gap', p.anion_gap)) AS v(variable, value)
    WHERE p.is_delivery_v2 AND p.eligible_24h
),
flag AS (
    SELECT b.*, (b.value IS NOT NULL
                 AND (dct.plausible_low  IS NULL OR b.value >= dct.plausible_low)
                 AND (dct.plausible_high IS NULL OR b.value <= dct.plausible_high)) AS measured
    FROM base b
    LEFT JOIN mimiciv.predictor_dictionary_final_v2 dct ON dct.variable = b.variable
)
SELECT f.variable, dct.model_role_final AS role, dct.unit, dct.source,
       dct.plausible_low, dct.plausible_high,
       CASE WHEN COUNT(*) FILTER (WHERE measured AND TRUE) BETWEEN 1 AND 9 THEN '<10'
                ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE measured AND TRUE) / NULLIF(COUNT(*) FILTER (WHERE TRUE), 0), 1)::text END AS pct_all,
       CASE WHEN (COUNT(*) FILTER (WHERE measured AND smm_any) BETWEEN 1 AND 9 OR COUNT(*) FILTER (WHERE measured AND NOT smm_any) BETWEEN 1 AND 9) THEN '<10 in pair'
                ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE measured AND smm_any) / NULLIF(COUNT(*) FILTER (WHERE smm_any), 0), 1)::text END AS pct_smm,
       CASE WHEN (COUNT(*) FILTER (WHERE measured AND smm_any) BETWEEN 1 AND 9 OR COUNT(*) FILTER (WHERE measured AND NOT smm_any) BETWEEN 1 AND 9) THEN '<10 in pair'
                ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE measured AND NOT smm_any) / NULLIF(COUNT(*) FILTER (WHERE NOT smm_any), 0), 1)::text END AS pct_no_smm,
       CASE WHEN (COUNT(*) FILTER (WHERE measured AND icu_in_24h) BETWEEN 1 AND 9 OR COUNT(*) FILTER (WHERE measured AND NOT icu_in_24h) BETWEEN 1 AND 9) THEN '<10 in pair'
                ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE measured AND icu_in_24h) / NULLIF(COUNT(*) FILTER (WHERE icu_in_24h), 0), 1)::text END AS pct_icu_24h,
       CASE WHEN (COUNT(*) FILTER (WHERE measured AND icu_in_24h) BETWEEN 1 AND 9 OR COUNT(*) FILTER (WHERE measured AND NOT icu_in_24h) BETWEEN 1 AND 9) THEN '<10 in pair'
                ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE measured AND NOT icu_in_24h) / NULLIF(COUNT(*) FILTER (WHERE NOT icu_in_24h), 0), 1)::text END AS pct_no_icu_24h,
       CASE WHEN (COUNT(*) FILTER (WHERE measured AND icd_version = 9) BETWEEN 1 AND 9 OR COUNT(*) FILTER (WHERE measured AND icd_version = 10) BETWEEN 1 AND 9) THEN '<10 in pair'
                ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE measured AND icd_version = 9) / NULLIF(COUNT(*) FILTER (WHERE icd_version = 9), 0), 1)::text END AS pct_icd9,
       CASE WHEN (COUNT(*) FILTER (WHERE measured AND icd_version = 9) BETWEEN 1 AND 9 OR COUNT(*) FILTER (WHERE measured AND icd_version = 10) BETWEEN 1 AND 9) THEN '<10 in pair'
                ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE measured AND icd_version = 10) / NULLIF(COUNT(*) FILTER (WHERE icd_version = 10), 0), 1)::text END AS pct_icd10
FROM flag f
LEFT JOIN mimiciv.predictor_dictionary_final_v2 dct ON dct.variable = f.variable
GROUP BY f.variable, dct.model_role_final, dct.unit, dct.source, dct.plausible_low, dct.plausible_high
ORDER BY dct.model_role_final, f.variable;
