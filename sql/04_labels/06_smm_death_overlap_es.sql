-- ============================================================================
-- 04_labels / 06_smm_death_overlap_es.sql
-- Solapamiento entre la morbilidad materna grave (etiqueta revisada) y la muerte en la
-- misma admisión
-- ============================================================================
-- Por qué: para describir cómo se relaciona la morbilidad materna grave (SMM) con
--   la mortalidad materna.  El conteo previo (Q10) usó la etiqueta SMM v1.
--   Este script lo repite con las etiquetas revisadas (lista de los CDC, ICD-9-CM y
--   ICD-10-CM/PCS; muerte = hospital_expire_flag en la misma admisión) y en
--   los tres ámbitos usados en el análisis revisado, de modo que el suplemento pueda indicar
--   exactamente cuántas muertes llevan un indicador de SMM y cuántas admisiones con SMM
--   terminan en muerte.
--
-- Qué hace: solo lee.  No crea ninguna tabla ni vista y no cambia ninguna etiqueta.
--   Requiere mimiciv.predictors_24h_v2 (05_predictors/01_predictors_24h_es.sql).
--   Solo conteos agregados -- comparta los resultados de las cuatro consultas, nunca filas.
-- ============================================================================

-- Q-H1  SMM x muerte en la misma admisión, por ámbito
WITH s AS (
    SELECT 1 AS ord, 'All obstetric admissions'             AS scope, smm_any, died_same_admission
    FROM mimiciv.predictors_24h_v2
    UNION ALL
    SELECT 2, 'Delivery hospitalizations',                  smm_any, died_same_admission
    FROM mimiciv.predictors_24h_v2 WHERE is_delivery_v2
    UNION ALL
    SELECT 3, 'Eligible deliveries (24-h model)',           smm_any, died_same_admission
    FROM mimiciv.predictors_24h_v2 WHERE is_delivery_v2 AND eligible_24h
)
SELECT scope,
       COUNT(*)                                                                      AS n_admissions,
       COUNT(*) FILTER (WHERE NOT smm_any AND NOT died_same_admission)               AS neither,
       COUNT(*) FILTER (WHERE smm_any AND NOT died_same_admission)                   AS smm_only,
       COUNT(*) FILTER (WHERE NOT smm_any AND died_same_admission)                   AS death_only,
       COUNT(*) FILTER (WHERE smm_any AND died_same_admission)                       AS smm_and_death,
       COUNT(*) FILTER (WHERE smm_any)                                               AS n_smm,
       COUNT(*) FILTER (WHERE died_same_admission)                                   AS n_death
FROM s
GROUP BY ord, scope
ORDER BY ord;

-- Q-H2  Las muertes en la misma admisión, una fila por perfil
--       (parto o no, elegible para el modelo de 24 h o no, con o sin SMM)
SELECT is_delivery_v2,
       eligible_24h,
       smm_any,
       COUNT(*) AS n_deaths
FROM mimiciv.predictors_24h_v2
WHERE died_same_admission
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 2 DESC, 3 DESC;

-- Q-H3  Admisiones con SMM según el número de indicadores y cuántas terminan en muerte
--       (todas las admisiones obstétricas; smm_n_indicators está en cohort_obstetric_v2)
SELECT c.smm_n_indicators,
       COUNT(*)                                          AS n_smm_admissions,
       COUNT(*) FILTER (WHERE p.died_same_admission)     AS n_died_same_admission
FROM mimiciv.predictors_24h_v2 p
JOIN mimiciv.cohort_obstetric_v2 c ON c.hadm_id = p.hadm_id
WHERE p.smm_any
GROUP BY 1
ORDER BY 1;

-- Q-H4  Indicadores de SMM que llevan las admisiones que terminaron en muerte
--       (una admisión puede llevar varios indicadores; conteos de admisiones por indicador, versiones de ICD juntas)
SELECT h.indicator_name,
       COUNT(DISTINCT h.hadm_id) AS n_death_admissions_with_indicator
FROM mimiciv.smm_hits_v2 h
JOIN mimiciv.predictors_24h_v2 p ON p.hadm_id = h.hadm_id
WHERE p.died_same_admission
GROUP BY 1
ORDER BY 2 DESC, 1;
