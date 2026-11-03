-- ============================================================================
-- AUDITORÍA DE CONTEOS -- datos v1 frente a las definiciones actuales
-- ============================================================================
-- Propósito: medir, sobre los datos con los que se entrenaron los modelos v1, conteos
-- que el manuscrito v1 no reportaba. SOLO LECTURA: únicamente
-- crea tablas temporales y ejecuta SELECT. No se produce salida a nivel de paciente
-- salvo conteos agregados; NO publique filas de resultados que listen subject_id/hadm_id.
--
-- Prerrequisitos (ya construidos para los análisis v1):
--   mimiciv.cohort_maternal        (tabla del Modelo A; columna `outcome`)
--   mimiciv.cohort_smm_dataset     (tabla del Modelo B; columnas outcome_smm, is_delivery_hospitalization,
--                                   icu_stay, heart_rate, creatine, lactic_acid, ...; la columna se escribe `creatine`, igual que en la tabla)
--   mimiciv.pregnancy_diagnoses_expanded (vista)
-- Ejecute el script completo (DBeaver: Alt+X) y copie cada conjunto de resultados en la hoja
-- de resultados.
-- Cada conjunto de resultados comienza con una columna de etiqueta `q`.
-- ============================================================================

SET search_path TO mimiciv, public;

-- ----------------------------------------------------------------------------
-- 0. Tablas de trabajo
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_audit_cohort;
CREATE TEMP TABLE tmp_audit_cohort AS
SELECT s.subject_id, s.hadm_id, s.outcome_smm, s.is_delivery_hospitalization, s.icu_stay,
       a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag,
       p.anchor_year_group,
       m.outcome AS outcome_a_v1
FROM   mimiciv.cohort_smm_dataset s
JOIN   mimiciv.admissions a ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
JOIN   mimiciv.patients   p ON p.subject_id = s.subject_id
LEFT JOIN mimiciv.cohort_maternal m ON m.subject_id = s.subject_id AND m.hadm_id = s.hadm_id;

-- Versión de ICD realmente presente en los diagnósticos de cada admisión
DROP TABLE IF EXISTS tmp_audit_icdver;
CREATE TEMP TABLE tmp_audit_icdver AS
SELECT d.subject_id, d.hadm_id,
       BOOL_OR(d.icd_version = 9)  AS has_icd9,
       BOOL_OR(d.icd_version = 10) AS has_icd10
FROM   mimiciv.diagnoses_icd d
JOIN   tmp_audit_cohort c ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
GROUP  BY d.subject_id, d.hadm_id;

-- ----------------------------------------------------------------------------
-- Q1. Tamaño de la cohorte y pacientes repetidos (manuscrito: 25,736 / 15,084 / 6,793)
-- ----------------------------------------------------------------------------
SELECT 'Q1 cohort' AS q,
       COUNT(*)                                AS n_admissions,
       COUNT(DISTINCT subject_id)              AS n_patients,
       (SELECT COUNT(*) FROM (SELECT subject_id FROM tmp_audit_cohort
                              GROUP BY subject_id HAVING COUNT(*) > 1) t) AS n_patients_multi_admission
FROM tmp_audit_cohort;

-- ----------------------------------------------------------------------------
-- Q2. Modelo A tal como se envió: positivos y su relación con el fallecimiento real
--     Etiqueta = cualquier admisión del paciente (en cualquier momento, obstétrica o no) tiene un deathtime
--     (véase CASE ... MIN(a2.deathtime) en el CREATE TABLE de cohort_maternal).
-- ----------------------------------------------------------------------------
SELECT 'Q2 modelA positives' AS q,
       COUNT(*) FILTER (WHERE outcome_a_v1 = 1)                        AS n_positive_admissions,
       COUNT(DISTINCT subject_id) FILTER (WHERE outcome_a_v1 = 1)      AS n_distinct_deceased_patients
FROM tmp_audit_cohort;

WITH pos AS (
    SELECT subject_id, hadm_id, admittime FROM tmp_audit_cohort WHERE outcome_a_v1 = 1
),
death AS (
    SELECT DISTINCT ON (a.subject_id) a.subject_id, a.hadm_id AS death_hadm_id,
           a.admittime AS death_admittime, a.deathtime
    FROM   mimiciv.admissions a
    WHERE  a.deathtime IS NOT NULL
    ORDER  BY a.subject_id, a.deathtime
),
x AS (
    SELECT p.subject_id, p.hadm_id,
           CASE WHEN d.death_hadm_id = p.hadm_id        THEN '1 same admission'
                WHEN d.death_admittime > p.admittime    THEN '2 later admission'
                ELSE                                         '3 earlier/other' END AS death_relation,
           EXISTS (SELECT 1 FROM tmp_audit_cohort c WHERE c.hadm_id = d.death_hadm_id) AS death_adm_in_cohort,
           EXISTS (SELECT 1 FROM mimiciv.icustays i WHERE i.hadm_id = d.death_hadm_id) AS death_adm_had_icu,
           EXISTS (SELECT 1 FROM mimiciv.icustays i WHERE i.hadm_id = p.hadm_id)       AS this_adm_had_icu,
           EXTRACT(EPOCH FROM (d.deathtime - p.admittime)) / 86400.0                   AS days_to_death
    FROM   pos p JOIN death d ON d.subject_id = p.subject_id
)
SELECT 'Q3 relation of positive admission to the death admission' AS q,
       death_relation,
       COUNT(*)                                          AS n_admissions,
       COUNT(DISTINCT subject_id)                        AS n_patients,
       COUNT(*) FILTER (WHERE death_adm_in_cohort)       AS death_admission_is_in_obstetric_cohort,
       COUNT(*) FILTER (WHERE death_adm_had_icu)         AS death_admission_had_icu,
       COUNT(*) FILTER (WHERE this_adm_had_icu)          AS this_admission_had_icu,
       ROUND(CAST(percentile_cont(0.5) WITHIN GROUP (ORDER BY days_to_death) AS numeric), 1) AS median_days_to_death,
       ROUND(CAST(MIN(days_to_death) AS numeric), 1)     AS min_days_to_death,
       ROUND(CAST(MAX(days_to_death) AS numeric), 1)     AS max_days_to_death
FROM   x
GROUP  BY death_relation
ORDER  BY death_relation;

-- Q4. Admisiones positivas generadas por cada paciente fallecido
SELECT 'Q4 positives per deceased patient' AS q, n_pos AS positive_admissions_per_patient, COUNT(*) AS n_patients
FROM (SELECT subject_id, COUNT(*) AS n_pos FROM tmp_audit_cohort
      WHERE outcome_a_v1 = 1 GROUP BY subject_id) t
GROUP  BY n_pos ORDER BY n_pos;

-- ----------------------------------------------------------------------------
-- Q5. Redefinición propuesta del Modelo A: fallecimiento en la MISMA admisión
-- ----------------------------------------------------------------------------
SELECT 'Q5 in-hospital death, same admission' AS q,
       COUNT(*) FILTER (WHERE hospital_expire_flag = 1)                                 AS n_events,
       COUNT(DISTINCT subject_id) FILTER (WHERE hospital_expire_flag = 1)               AS n_patients_with_event,
       COUNT(*) FILTER (WHERE hospital_expire_flag = 1 AND icu_stay = 1)                AS events_with_icu,
       COUNT(*) FILTER (WHERE hospital_expire_flag = 1 AND icu_stay = 0)                AS events_without_icu,
       COUNT(*) FILTER (WHERE hospital_expire_flag = 1
                         AND deathtime <= admittime + INTERVAL '24 hours')              AS events_within_first_24h,
       COUNT(*) FILTER (WHERE hospital_expire_flag = 1 AND outcome_a_v1 = 1)     AS also_positive_in_v1_label
FROM   tmp_audit_cohort;

-- ----------------------------------------------------------------------------
-- Q6. Versión de ICD y era. Los códigos de SMM en smm_cohort_es.sql se emparejan
--     solo con icd_version = 10.
-- ----------------------------------------------------------------------------
SELECT 'Q6 icd version' AS q,
       CASE WHEN v.has_icd9 AND v.has_icd10 THEN 'both'
            WHEN v.has_icd9                 THEN 'ICD-9 only'
            WHEN v.has_icd10                THEN 'ICD-10 only'
            ELSE 'no diagnoses' END                                AS icd_version_in_admission,
       COUNT(*)                                                    AS n_admissions,
       COUNT(*) FILTER (WHERE c.outcome_smm = 1)                   AS n_smm_positive_v1_label,
       COUNT(*) FILTER (WHERE c.outcome_a_v1 = 1)           AS n_modelA_positive_v1_label,
       COUNT(*) FILTER (WHERE c.is_delivery_hospitalization = 1)   AS n_delivery_hospitalizations
FROM   tmp_audit_cohort c
LEFT JOIN tmp_audit_icdver v ON v.subject_id = c.subject_id AND v.hadm_id = c.hadm_id
GROUP  BY 2 ORDER BY 2;

SELECT 'Q7 era (anchor_year_group)' AS q, c.anchor_year_group,
       COUNT(*)                                                  AS n_admissions,
       COUNT(*) FILTER (WHERE v.has_icd9)                        AS n_with_icd9,
       COUNT(*) FILTER (WHERE v.has_icd10)                       AS n_with_icd10,
       COUNT(*) FILTER (WHERE c.outcome_smm = 1)                 AS n_smm,
       COUNT(*) FILTER (WHERE c.is_delivery_hospitalization = 1) AS n_delivery_icd10_flag,
       COUNT(*) FILTER (WHERE c.is_delivery_hospitalization = 1 AND c.outcome_smm = 1) AS n_smm_in_delivery,
       ROUND(10000.0 * COUNT(*) FILTER (WHERE c.is_delivery_hospitalization = 1 AND c.outcome_smm = 1)
             / NULLIF(COUNT(*) FILTER (WHERE c.is_delivery_hospitalization = 1), 0), 1) AS smm_per_10000_deliveries
FROM   tmp_audit_cohort c
LEFT JOIN tmp_audit_icdver v ON v.subject_id = c.subject_id AND v.hadm_id = c.hadm_id
GROUP  BY c.anchor_year_group ORDER BY c.anchor_year_group;

-- Q8. Proxy de las admisiones de parto con ICD-9 (la bandera de parto solo considera Z37/O80/O82 de ICD-10):
--     ICD-9 650 (parto normal) o V27.x (resultado del parto). Proxy descriptivo, no una lista validada.
SELECT 'Q8 ICD-9 delivery proxy' AS q, COUNT(DISTINCT c.hadm_id) AS n_admissions_icd9_delivery_proxy
FROM   tmp_audit_cohort c
JOIN   mimiciv.diagnoses_icd d ON d.subject_id = c.subject_id AND d.hadm_id = c.hadm_id
WHERE  d.icd_version = 9 AND (d.icd_code LIKE '650%' OR d.icd_code LIKE 'V27%');

-- ----------------------------------------------------------------------------
-- Q9. Resultado SMM: pacientes, repetición, solapamiento con la muerte intrahospitalaria
-- ----------------------------------------------------------------------------
SELECT 'Q9 smm patients' AS q,
       COUNT(*) FILTER (WHERE outcome_smm = 1)                     AS n_smm_admissions,
       COUNT(DISTINCT subject_id) FILTER (WHERE outcome_smm = 1)   AS n_patients_with_smm
FROM   tmp_audit_cohort;

SELECT 'Q10 smm x in-hospital death (same admission)' AS q, outcome_smm, hospital_expire_flag, COUNT(*) AS n
FROM   tmp_audit_cohort GROUP BY 2, 3 ORDER BY 2, 3;

SELECT 'Q11 smm x v1 mortality label' AS q, outcome_smm, outcome_a_v1, COUNT(*) AS n
FROM   tmp_audit_cohort GROUP BY 2, 3 ORDER BY 2, 3;

-- ----------------------------------------------------------------------------
-- Q12. Regla de cohorte de inclusión: el manuscrito dice diagnóstico obstétrico en posición <= 4,
--      el SQL no tiene restricción de posición. ¿Cuánto importa?
-- ----------------------------------------------------------------------------
WITH pos4 AS (
    SELECT DISTINCT d.subject_id, d.hadm_id
    FROM   mimiciv.diagnoses_icd d
    JOIN   mimiciv.pregnancy_diagnoses_expanded de
           ON de.icd_code = d.icd_code AND de.icd_version = d.icd_version
    WHERE  d.seq_num <= 4
)
SELECT 'Q12 obstetric dx in position <= 4' AS q,
       COUNT(*)                                              AS n_admissions_all_rule,
       COUNT(p.hadm_id)                                      AS n_admissions_if_position_le_4,
       COUNT(*) FILTER (WHERE c.outcome_smm = 1)             AS smm_all_rule,
       COUNT(p.hadm_id) FILTER (WHERE c.outcome_smm = 1)     AS smm_if_position_le_4,
       COUNT(*) FILTER (WHERE c.hospital_expire_flag = 1)         AS deaths_all_rule,
       COUNT(p.hadm_id) FILTER (WHERE c.hospital_expire_flag = 1) AS deaths_if_position_le_4
FROM   tmp_audit_cohort c
LEFT JOIN pos4 p ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id;

-- ----------------------------------------------------------------------------
-- Q13. Disponibilidad estructural de las variables registradas en UCI
--      Los signos vitales provienen de chartevents solo de la primera estancia en UCI; los laboratorios, de labevents de todo el hospital.
-- ----------------------------------------------------------------------------
SELECT 'Q13 availability by ICU status and SMM' AS q,
       s.icu_stay, s.outcome_smm,
       COUNT(*)                                           AS n_admissions,
       ROUND(100.0 * COUNT(s.heart_rate)  / COUNT(*), 1)  AS pct_heart_rate_present,
       ROUND(100.0 * COUNT(s.creatine)    / COUNT(*), 1)  AS pct_creatinine_present,
       ROUND(100.0 * COUNT(s.glucose)     / COUNT(*), 1)  AS pct_glucose_present,
       ROUND(100.0 * COUNT(s.lactic_acid) / COUNT(*), 1)  AS pct_lactate_present,
       ROUND(100.0 * COUNT(s.hemoglobine) / COUNT(*), 1)  AS pct_hemoglobin_present
FROM   mimiciv.cohort_smm_dataset s
GROUP  BY s.icu_stay, s.outcome_smm ORDER BY s.icu_stay, s.outcome_smm;

-- ----------------------------------------------------------------------------
-- Q14. Momento del valor de laboratorio/registrado más temprano respecto a la admisión
--      Horas desde admittime hasta la creatinina más temprana (itemids 50912 laboratorio / 220615 registro).
-- ----------------------------------------------------------------------------
WITH first_creat AS (
    SELECT c.hadm_id, MIN(t.charttime) AS first_time
    FROM   tmp_audit_cohort c
    JOIN  (SELECT hadm_id, charttime FROM mimiciv.labevents   WHERE itemid = 50912  AND valuenum IS NOT NULL
           UNION ALL
           SELECT hadm_id, charttime FROM mimiciv.chartevents WHERE itemid = 220615 AND valuenum IS NOT NULL) t
           ON t.hadm_id = c.hadm_id
    GROUP  BY c.hadm_id
)
SELECT 'Q14 hours to earliest creatinine' AS q,
       COUNT(*)                                                                         AS n_with_creatinine,
       ROUND(CAST(percentile_cont(0.5)  WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (f.first_time - c.admittime))/3600.0) AS numeric), 1) AS median_hours,
       ROUND(CAST(percentile_cont(0.9)  WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (f.first_time - c.admittime))/3600.0) AS numeric), 1) AS p90_hours,
       COUNT(*) FILTER (WHERE f.first_time >  c.admittime + INTERVAL '24 hours')        AS n_first_value_after_24h
FROM   first_creat f JOIN tmp_audit_cohort c ON c.hadm_id = f.hadm_id;

-- ============================================================================
-- SOLAPAMIENTO DE PACIENTES ENTRE ENTRENAMIENTO Y PRUEBA -- ejecutar en el NOTEBOOK, en una celda NUEVA
-- colocada justo después de la celda train_test_split (no edite las celdas existentes). La partición
-- no se puede reproducir desde SQL, porque df se reordena en pandas.
--
--   ids = (df_scaled.sort_values('subject_id').reset_index(drop=True)['subject_id'])
--   tr_ids, te_ids = set(ids.loc[X_train.index]), set(ids.loc[X_test.index])
--   ev_ids = set(ids[y == 1])
--   print("patients train / test:", len(tr_ids), len(te_ids))
--   print("patients in BOTH:", len(tr_ids & te_ids))
--   print("test admissions whose patient is also in train:",
--         int(ids.loc[X_test.index].isin(tr_ids).sum()), "of", len(X_test))
--   print("event patients total / in test:", len(ev_ids), len(ev_ids & te_ids))
--   print("test events whose patient also has an event admission in train:",
--         int(ids.loc[X_test.index][y_test == 1].isin(ids.loc[X_train.index][y_train == 1]).sum()))
--
-- NOTA: en el notebook del Modelo A existen las mismas celdas con outcome_smm reemplazado por outcome.
-- ============================================================================
