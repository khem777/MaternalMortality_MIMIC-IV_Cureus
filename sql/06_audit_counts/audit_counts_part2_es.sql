-- ============================================================================
-- AUDITORÍA DE CONTEOS, PARTE 2 -- SOLO LECTURA
-- Framework: E4 Auditoría de conteos, parte 2; conteos de referencia para la puerta P1.
-- ============================================================================
-- Seguimiento de audit_counts_es.sql tras los primeros resultados (Q1-Q11). Mismas reglas:
-- solo tablas temporales + SELECT, salida agregada, nunca publicar subject_id/hadm_id.
--   Q15  Casos de SMM por grupo de indicadores, en general y en hospitalizaciones de parto
--   Q16  perfil de las muertes intrahospitalarias de la misma admisión (celdas pequeñas agregadas)
--   Q17  año de admisión aproximado (límite inferior de la ventana ancla + desfase) vs. versión de ICD (anchor_year_group es
--        la ventana ancla del paciente, NO la fecha de cada admisión)
--   Q18  Casos de SMM por grupo de indicadores y anchor_year_group (qué impulsa el aumento por era)
-- Prerrequisitos: mimiciv.cohort_smm_dataset, mimiciv.hadm_with_smm,
--                mimiciv.hadm_delivery_hospitalization, mimiciv.pregnancy_diagnoses_expanded
-- ============================================================================
SET search_path TO mimiciv, public;

DROP TABLE IF EXISTS tmp_audit2;
CREATE TEMP TABLE tmp_audit2 AS
SELECT s.subject_id, s.hadm_id, s.outcome_smm, s.is_delivery_hospitalization, s.icu_stay,
       a.admittime, a.deathtime, a.hospital_expire_flag,
       p.anchor_year, p.anchor_year_group,
       CAST(LEFT(p.anchor_year_group, 4) AS int) + (EXTRACT(YEAR FROM a.admittime)::int - p.anchor_year) AS approx_year_low,
       COALESCE(BOOL_OR(d.icd_version = 9),  FALSE) AS has_icd9,
       COALESCE(BOOL_OR(d.icd_version = 10), FALSE) AS has_icd10
FROM   mimiciv.cohort_smm_dataset s
JOIN   mimiciv.admissions a ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
JOIN   mimiciv.patients   p ON p.subject_id = s.subject_id
LEFT JOIN mimiciv.diagnoses_icd d ON d.subject_id = s.subject_id AND d.hadm_id = s.hadm_id
GROUP  BY s.subject_id, s.hadm_id, s.outcome_smm, s.is_delivery_hospitalization, s.icu_stay,
          a.admittime, a.deathtime, a.hospital_expire_flag, p.anchor_year, p.anchor_year_group;

-- Q15. SMM por grupo de indicadores (una admisión puede tener varios indicadores, por lo que las filas se solapan)
SELECT 'Q15 SMM by indicator group' AS q, w.indicator_group,
       COUNT(DISTINCT w.hadm_id)                                                     AS n_admissions_with_indicator,
       COUNT(DISTINCT w.hadm_id) FILTER (WHERE c.is_delivery_hospitalization = 1)    AS n_in_delivery_hosp,
       COUNT(DISTINCT w.hadm_id) FILTER (WHERE c.is_delivery_hospitalization = 0)    AS n_in_non_delivery_hosp
FROM   mimiciv.hadm_with_smm w
JOIN   tmp_audit2 c ON c.subject_id = w.subject_id AND c.hadm_id = w.hadm_id
GROUP  BY w.indicator_group ORDER BY n_admissions_with_indicator DESC;

-- Q15b. Lo mismo, por indicador individual (los 25 principales)
SELECT 'Q15b SMM by indicator' AS q, w.indicator_group, w.indicator_name,
       COUNT(DISTINCT w.hadm_id) AS n_admissions
FROM   mimiciv.hadm_with_smm w
JOIN   tmp_audit2 c ON c.subject_id = w.subject_id AND c.hadm_id = w.hadm_id
GROUP  BY 2, 3 ORDER BY n_admissions DESC LIMIT 25;

-- Q16. Las muertes intrahospitalarias de la misma admisión (unas 10): perfil, solo agregado
SELECT 'Q16 same-admission deaths profile' AS q,
       CASE WHEN has_icd9 AND has_icd10 THEN 'both' WHEN has_icd9 THEN 'ICD-9 only' ELSE 'ICD-10 only' END AS icd_version,
       is_delivery_hospitalization AS delivery_flag_icd10,
       outcome_smm,
       icu_stay,
       EXISTS (SELECT 1 FROM mimiciv.diagnoses_icd d
               JOIN mimiciv.pregnancy_diagnoses_expanded de ON de.icd_code = d.icd_code AND de.icd_version = d.icd_version
               WHERE d.subject_id = t.subject_id AND d.hadm_id = t.hadm_id AND d.seq_num = 1) AS obstetric_dx_is_principal,
       COUNT(*) AS n_deaths
FROM   tmp_audit2 t
WHERE  hospital_expire_flag = 1
GROUP  BY 2, 3, 4, 5, 6 ORDER BY n_deaths DESC;

-- Q17. Año de admisión aproximado (límite inferior de la ventana + desplazamiento) vs. versión de ICD
SELECT 'Q17 approx year vs ICD version' AS q, approx_year_low,
       COUNT(*)                                                  AS n_admissions,
       COUNT(*) FILTER (WHERE has_icd9  AND NOT has_icd10)       AS n_icd9_only,
       COUNT(*) FILTER (WHERE has_icd10 AND NOT has_icd9)        AS n_icd10_only,
       COUNT(*) FILTER (WHERE outcome_smm = 1)                   AS n_smm,
       COUNT(*) FILTER (WHERE is_delivery_hospitalization = 1)   AS n_delivery_icd10_flag
FROM   tmp_audit2
GROUP  BY approx_year_low ORDER BY approx_year_low;

-- Q18. Admisiones con SMM por grupo de indicadores y anchor_year_group
SELECT 'Q18 SMM group by era' AS q, w.indicator_group,
       COUNT(DISTINCT w.hadm_id) FILTER (WHERE c.anchor_year_group = '2008 - 2010') AS g_2008_2010,
       COUNT(DISTINCT w.hadm_id) FILTER (WHERE c.anchor_year_group = '2011 - 2013') AS g_2011_2013,
       COUNT(DISTINCT w.hadm_id) FILTER (WHERE c.anchor_year_group = '2014 - 2016') AS g_2014_2016,
       COUNT(DISTINCT w.hadm_id) FILTER (WHERE c.anchor_year_group = '2017 - 2019') AS g_2017_2019,
       COUNT(DISTINCT w.hadm_id) FILTER (WHERE c.anchor_year_group = '2020 - 2022') AS g_2020_2022
FROM   mimiciv.hadm_with_smm w
JOIN   tmp_audit2 c ON c.subject_id = w.subject_id AND c.hadm_id = w.hadm_id
GROUP  BY w.indicator_group ORDER BY 3 + 4 + 5 + 6 + 7 DESC;
