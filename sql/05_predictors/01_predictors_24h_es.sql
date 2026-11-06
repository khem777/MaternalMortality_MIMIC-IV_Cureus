-- ============================================================================
-- 05_predictors / 01_predictors_24h_es.sql
-- Predictores restringidos a las primeras 24 horas de la hospitalización
--
-- Framework: E6 Punto de predicción y ventana (tiempo cero, punto de predicción, elegibilidad) y E7 Predictores: construye la tabla del contrato.
-- ============================================================================
-- Por qué: en los conjuntos de datos v1 (sql/03_cohort_smm/smm_dataset_es.sql y el
--   conjunto de datos de mortalidad equivalente) cada valor de laboratorio y cada valor de chart es el
--   PRIMER valor de toda la hospitalización, sin límite de tiempo; los valores de chart
--   provienen solo de la primera estancia en UCI; icu_stay e icu_stay_count usan toda la
--   hospitalización; y los 28 indicadores gdg_m* provienen de los primeros cuatro
--   diagnósticos de EGRESO (seq_num <= 4).  Ninguno de estos se conoce en un momento
--   fijo de predicción.
--
-- Decisiones aplicadas (véase el plan, hoja Decisiones):
--   D3  Punto de predicción = 24 horas después de la hora de admisión hospitalaria (admittime + 24 h).
--   D10 Ventana de predictores = desde 24 horas ANTES de admittime hasta el punto de predicción (admittime + 24 h).  Los valores de la
--       visita de triaje o de urgencias que preceden a la hora de admisión están disponibles en el punto
--       de predicción, por lo que no son fuga de información; el límite inferior de 24 h antes de la admisión los mantiene dentro
--       del mismo episodio.  (Q-F5 de la primera ejecución mostró que con una ventana que comienza en admittime,
--       4,830 hospitalizaciones de parto perdían una hemoglobina que se midió solo en ese período.)
--   D8  Las admisiones que terminan (egreso o muerte) antes de las 24 h NO son elegibles
--       para el modelo de 24 horas (eligible_24h = false); se conservan en la tabla
--       para poder reportar sus eventos por separado.
--   Los indicadores gdg_m* NO se construyen aquí (diagnósticos de egreso).
--   icu_stay_count se reemplaza por icu_in_24h (ingreso a UCI antes de admittime + 24 h).  Las variables
--   exclusivas de UCI (signos vitales, Glasgow, RASS, PEEP, peso, talla) e icu_in_24h se conservan en la
--   tabla pero se marcan como model_role = 'ICU sensitivity only' en el diccionario: no existen
--   fuera de la UCI (Q-F4) e icu_in_24h está estrechamente ligada al desenlace (Q-F3).
--
-- Qué crea este script (solo nombres nuevos; no se modifica nada existente):
--   mimiciv.predictor_dictionary_v2   una fila por predictor: ids de ítem, etiquetas, nombre anterior
--   mimiciv.predictor_firsts_v2       primer valor de cada predictor dentro de la ventana (formato largo)
--   mimiciv.predictors_24h_v2         una fila por admisión obstétrica (formato ancho), con
--                                     elegibilidad, momento de UCI, banderas de desenlace y los 27 predictores
--
-- Requiere: 04_cohort_obstetric_flags_es.sql (mimiciv.cohort_obstetric_v2).
-- Los valores de laboratorio se emparejan por paciente y tiempo (hadm_id igual al de la admisión
--   O faltante), de modo que un valor de laboratorio tomado dentro de la ventana sin hadm_id no se pierda.
-- Ejecute el script completo (DBeaver: Alt+X).  Lee chartevents y labevents solo para los
--   pacientes de la cohorte (indexados por subject_id).  Comparta solo los resultados agregados de
--   las consultas de conteo (Q-F0 .. Q-F5), nunca datos a nivel de fila.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Paso 1 -- diccionario de predictores (las mismas 27 variables de chart/laboratorio que los conjuntos de datos v1)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.predictors_24h_v2;
DROP TABLE IF EXISTS mimiciv.predictor_firsts_v2;
DROP TABLE IF EXISTS mimiciv.predictor_dictionary_v2;

CREATE TABLE mimiciv.predictor_dictionary_v2 (
    variable        text PRIMARY KEY,   -- nombre usado de aquí en adelante (ortografía corregida)
    previous_name   text NOT NULL,      -- nombre en el conjunto de datos v1 y en el manuscrito
    chart_itemid    integer,            -- chartevents.itemid (UCI)
    lab_itemid      integer,            -- labevents.itemid (en todo el hospital)
    chart_label     text,
    lab_label       text,
    source          text,
    model_role      text,               -- 'main model' o 'ICU sensitivity only'
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
-- Paso 2 -- primer valor de cada predictor dentro de la ventana (admittime - 24 h a admittime + 24 h; formato largo)
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
-- Paso 3 -- una fila por admisión obstétrica (formato ancho)
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
-- CONSULTAS DE CONTEO (solo agregados) -- ejecute cada una y pegue el resultado
-- Ámbitos (los mismos de D5/D6): Parto = primario; Código obstétrico estructurado = sensibilidad;
--   Cualquier admisión obstétrica = universo.
-- ============================================================================

-- Q-F0  Verificación de cordura: mismas filas que la cohorte; filas de la tabla larga; admisiones elegibles
SELECT (SELECT COUNT(*) FROM mimiciv.cohort_obstetric_v2)                   AS n_cohort,
       COUNT(*)                                                             AS n_rows,
       COUNT(DISTINCT hadm_id)                                              AS n_distinct_hadm,
       COUNT(*) FILTER (WHERE eligible_24h)                                 AS n_eligible_24h,
       (SELECT COUNT(*) FROM mimiciv.predictor_firsts_v2)                   AS n_values_in_window
FROM mimiciv.predictors_24h_v2;

-- Q-F1  Quién es elegible para un modelo de 24 horas y qué eventos se pierden
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

-- Q-F2  Horas desde la admisión hasta la muerte (admisiones con muerte en la misma admisión)
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

-- Q-F3  Momento del primer ingreso a UCI y su relación con los desenlaces (UCI como predictor)
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

-- Q-F4  Disponibilidad de cada predictor dentro de la ventana: hospitalizaciones de parto elegibles para el modelo de 24 horas
--       (conteos; global, por ingreso a UCI dentro de 24 h y por SMM)
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

-- Q-F5  Momento de los laboratorios en hospitalizaciones de parto (solo laboratorios): dónde cae el primer valor
--       respecto de la ventana.  "before admission" = primer valor en las 24 h previas a admittime (se conserva);
--       "after 24 h" = la paciente tiene valores solo después del punto de predicción (se excluye);
--       "no value" = ningún valor desde 24 h antes de admittime hasta el egreso.
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
