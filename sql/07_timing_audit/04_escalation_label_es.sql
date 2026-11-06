-- ============================================================================
-- 07_timing_audit / 04_escalation_label_es.sql
-- Etiqueta por admisión del desenlace con tiempo del retorno R2:
-- escalamiento de la atención DESPUÉS del punto de predicción (T = admittime + 24 h).
-- Framework: Retorno R2 (vuelta a E3): etiqueta por admisión del desenlace con tiempo (columna label_timed del contrato).
-- ============================================================================
-- Misma definición que 03_escalation_counts.sql (que solo devuelve conteos):
--   (e1) ingreso a UCI con intime después de T              (icustays.intime, hora exacta)
--   (e2) ventilación mecánica invasiva iniciada después de T  (procedureevents itemid 225792, hora exacta; solo UCI)
--   (e3) indicador de SMM por procedimiento fechado después de T (procedures_icd.chartdate >= T, misma regla del notebook 07)
--   (e4) muerte intrahospitalaria después de T (admissions.deathtime)
-- Población: hospitalizaciones de parto elegibles SIN ingreso a UCI antes de T
-- (ya están escaladas en el punto de predicción).
--
-- Crea UNA tabla nueva (no modifica nada existente):
--   mimiciv.escalation_v3   una fila por admisión de la población, con las cuatro
--                           marcas de componente y el compuesto (escalation_any).
-- Esperado (Q-E1 de 03_escalation_counts.sql): 19.268 admisiones, 101 con escalamiento.
-- La lee notebooks/08_landmark_incident_smm.ipynb, sección 11.
-- Ejecutar después de 01_timing_flags_v3.sql.  La consulta de control devuelve solo agregados.
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

-- Q-E2  Control contra Q-E1 (esperado: 19.268 admisiones y 101 con escalamiento)
SELECT COUNT(*)                                   AS n_population,
       COUNT(*) FILTER (WHERE icu_after)          AS icu_after,
       COUNT(*) FILTER (WHERE vent_after)         AS vent_after,
       COUNT(*) FILTER (WHERE smm_proc_after)     AS smm_proc_after,
       COUNT(*) FILTER (WHERE death_after)        AS death_after,
       COUNT(*) FILTER (WHERE escalation_any)     AS escalation_any
FROM mimiciv.escalation_v3;
