-- ============================================================================
-- 04_labels / 03b_reconcile_old_labels_es.sql
-- Conciliar la etiqueta de SMM del conjunto de datos v1 con la vista original
-- ============================================================================
-- Por qué: antes de reportar el cambio "de 475 a 848", las 475 admisiones con SMM
--   del conjunto de datos v1 (mimiciv.cohort_smm_dataset, outcome_smm = 1) deben
--   conciliarse con la vista original (mimiciv.hadm_with_smm) y con la nueva
--   etiqueta.  Q-C4 divide las dos listas en 459 admisiones en ambas, 389 solo en la
--   lista oficial y 16 solo en la original (original = 459 + 16 = 475).
--   Resultado (Q23): los 475 positivos del conjunto de datos provienen
--   de la vista original (459 también en la nueva etiqueta, 16 solo en la original),
--   por lo que no hay ninguna brecha entre el conjunto de datos y la vista que explicar.  (Una versión anterior
--   de esta nota decía "405 admisiones (389 + 16)" y una brecha de 70 admisiones;
--   eso fue un error aritmético, corregido el 2026-10-25.)
--   Solo lectura: únicamente SELECT, solo conteos agregados.
-- ============================================================================

-- Q23a  ¿El conjunto de datos es el mismo universo que label_admission_v2?
SELECT COUNT(*)                                                         AS n_dataset_rows,
       COUNT(*) FILTER (WHERE l.hadm_id IS NULL)                        AS dataset_rows_not_in_label_table,
       COUNT(*) FILTER (WHERE d.outcome_smm = 1)                        AS n_dataset_smm
FROM mimiciv.cohort_smm_dataset d
LEFT JOIN mimiciv.label_admission_v2 l ON l.hadm_id = d.hadm_id;

-- Q23b  ¿De dónde provienen los positivos de SMM del conjunto de datos?
SELECT COUNT(*) FILTER (WHERE old.hadm_id IS NOT NULL AND l.smm_any)         AS in_view_and_in_new,
       COUNT(*) FILTER (WHERE old.hadm_id IS NOT NULL AND NOT l.smm_any)     AS in_view_not_new,
       COUNT(*) FILTER (WHERE old.hadm_id IS NULL     AND l.smm_any)         AS not_in_view_but_in_new,
       COUNT(*) FILTER (WHERE old.hadm_id IS NULL     AND NOT l.smm_any)     AS in_dataset_only
FROM mimiciv.cohort_smm_dataset d
JOIN mimiciv.label_admission_v2 l ON l.hadm_id = d.hadm_id
LEFT JOIN (SELECT DISTINCT hadm_id FROM mimiciv.hadm_with_smm) old ON old.hadm_id = d.hadm_id
WHERE d.outcome_smm = 1;

-- Q23c  ¿Qué indicadores asigna la vista original a las admisiones que el conjunto de datos
--       v1 marca pero la vista no?  (agregado)
-- Ejecute esto solo si in_dataset_only > 0 o not_in_view_but_in_new > 0; compare la
-- definición de outcome_smm en sql/03_cohort_smm/smm_dataset_es.sql.
SELECT COUNT(*) FILTER (WHERE d.outcome_smm = 1 AND l.smm_only_renal)   AS dataset_smm_renal_only_new,
       COUNT(*) FILTER (WHERE d.outcome_smm = 1 AND NOT l.is_delivery_v2) AS dataset_smm_not_delivery_v2
FROM mimiciv.cohort_smm_dataset d
JOIN mimiciv.label_admission_v2 l ON l.hadm_id = d.hadm_id;
