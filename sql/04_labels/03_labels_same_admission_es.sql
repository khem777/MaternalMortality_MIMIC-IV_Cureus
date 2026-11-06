-- ============================================================================
-- 04_labels / 03_labels_same_admission_es.sql
-- Etiquetas a nivel de admisión para el análisis revisado (ambos modelos)
-- Framework: E3 Definición del desenlace: etiquetas por admisión (columnas label_main y alternativas del contrato).
-- ============================================================================
-- Propósito (decisiones D1, D4(a), D5(a)):
--   * Modelo A (mortalidad): etiqueta = muerte DURANTE LA MISMA ADMISIÓN
--     (admissions.hospital_expire_flag = 1), no "cualquier muerte registrada de la
--     paciente en cualquier momento".  deathtime IS NOT NULL se conserva como verificación cruzada.
--   * Modelo B (SMM): indicadores del catálogo oficial de los CDC
--     (smm_code_patterns_v2: ICD-9-CM E ICD-10-CM/PCS), calculados por admisión.
--   * Bandera de parto de 02_delivery_flag_es.sql (is_delivery_v2).
--   Todo se crea con nombres NUEVOS (*_v2).  Las tablas/vistas originales NO se
--   modifican.  Orden de ejecución: 01 -> 02 -> 03.
--
-- UNIVERSO: el mismo universo que el script original de SMM -- mujeres, edad aprox.
--   12-55 (anchor_age + año de admisión - anchor_year), al menos un diagnóstico en
--   mimiciv.pregnancy_diagnoses_expanded, en CUALQUIER posición de diagnóstico.
--   La regla de posición del diagnóstico difiere entre los dos
--   scripts de cohorte originales y se resuelve en el siguiente script (04), después de
--   conciliar ambos.  Por lo tanto, este script solo etiqueta; no define la
--   cohorte final.
--
-- Nada aquí escribe subject_id/hadm_id fuera de la base de datos.  Las consultas de
-- conteo al final devuelven solo agregados -- comparta esos, nunca datos a nivel de fila.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Paso 1 -- aciertos de SMM por admisión e indicador (según la versión de ICD)
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS mimiciv.smm_by_admission_v2 CASCADE;
DROP VIEW IF EXISTS mimiciv.smm_hits_v2 CASCADE;

CREATE VIEW mimiciv.smm_hits_v2 AS
SELECT DISTINCT d.hadm_id, p.indicator_name, p.icd_version
FROM mimiciv.diagnoses_icd d
JOIN mimiciv.smm_code_patterns_v2 p
  ON p.code_type = 'DX'
 AND p.icd_version = d.icd_version
 AND ( (p.match_type = 'PREFIX' AND d.icd_code LIKE p.code_pattern || '%')
    OR (p.match_type = 'EXACT'  AND d.icd_code = p.code_pattern) )
UNION
SELECT DISTINCT pr.hadm_id, p.indicator_name, p.icd_version
FROM mimiciv.procedures_icd pr
JOIN mimiciv.smm_code_patterns_v2 p
  ON p.code_type = 'PR'
 AND p.icd_version = pr.icd_version
 AND ( (p.match_type = 'PREFIX' AND pr.icd_code LIKE p.code_pattern || '%')
    OR (p.match_type = 'EXACT'  AND pr.icd_code = p.code_pattern) );

CREATE VIEW mimiciv.smm_by_admission_v2 AS
SELECT hadm_id,
       COUNT(DISTINCT indicator_name)                                        AS n_indicators,
       BOOL_AND(indicator_name = 'Acute renal failure')                      AS only_renal,
       BOOL_OR(icd_version = 9)                                              AS hit_icd9,
       BOOL_OR(icd_version = 10)                                             AS hit_icd10
FROM mimiciv.smm_hits_v2
GROUP BY hadm_id;

-- ----------------------------------------------------------------------------
-- Paso 2 -- tabla de etiquetas (una fila por admisión del universo obstétrico)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.label_admission_v2;

CREATE TABLE mimiciv.label_admission_v2 AS
WITH universe AS (
    SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.deathtime, a.hospital_expire_flag,
           p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) AS approx_age
    FROM mimiciv.admissions a
    JOIN mimiciv.patients p ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) BETWEEN 12 AND 55
      AND a.hadm_id IN (
            SELECT d.hadm_id
            FROM mimiciv.diagnoses_icd d
            JOIN mimiciv.pregnancy_diagnoses_expanded de
              ON d.icd_code = de.icd_code AND d.icd_version = de.icd_version)
),
era AS (
    SELECT hadm_id,
           BOOL_OR(icd_version = 9)  AS has_icd9_dx,
           BOOL_OR(icd_version = 10) AS has_icd10_dx
    FROM mimiciv.diagnoses_icd
    GROUP BY hadm_id
)
SELECT u.subject_id,
       u.hadm_id,
       u.admittime,
       u.approx_age,
       -- Etiqueta del modelo A (muerte en la misma admisión)
       (u.hospital_expire_flag = 1)                     AS died_same_admission,
       (u.deathtime IS NOT NULL)                        AS deathtime_recorded,
       -- Bandera de parto
       dv.is_delivery_v2,
       dv.has_stillbirth_code,
       -- Etiqueta del modelo B
       COALESCE(s.n_indicators, 0)                      AS smm_n_indicators,
       (COALESCE(s.n_indicators, 0) >= 1)               AS smm_any,
       COALESCE(s.only_renal, FALSE)                    AS smm_only_renal,
       (COALESCE(s.n_indicators, 0) >= 2)               AS smm_ge2,
       COALESCE(s.hit_icd9, FALSE)                      AS smm_hit_icd9,
       COALESCE(s.hit_icd10, FALSE)                     AS smm_hit_icd10,
       -- era de codificación
       COALESCE(e.has_icd9_dx, FALSE)                   AS has_icd9_dx,
       COALESCE(e.has_icd10_dx, FALSE)                  AS has_icd10_dx
FROM universe u
LEFT JOIN mimiciv.hadm_delivery_v2   dv ON dv.hadm_id = u.hadm_id
LEFT JOIN mimiciv.smm_by_admission_v2 s ON s.hadm_id  = u.hadm_id
LEFT JOIN era                          e ON e.hadm_id  = u.hadm_id;

CREATE INDEX ON mimiciv.label_admission_v2 (hadm_id);
CREATE INDEX ON mimiciv.label_admission_v2 (subject_id);

-- ============================================================================
-- CONSULTAS DE CONTEO (solo agregados) -- ejecute cada una y pegue el resultado
-- ============================================================================

-- Q-C1  Universo, bandera de parto y etiquetas
SELECT COUNT(*)                                              AS n_admissions,
       COUNT(DISTINCT subject_id)                            AS n_patients,
       COUNT(*) FILTER (WHERE is_delivery_v2)                AS n_delivery_v2,
       COUNT(*) FILTER (WHERE smm_any)                       AS n_smm_any_admission,
       COUNT(*) FILTER (WHERE smm_any AND is_delivery_v2)    AS n_smm_at_delivery,
       COUNT(*) FILTER (WHERE died_same_admission)           AS n_died_same_admission,
       COUNT(*) FILTER (WHERE died_same_admission AND is_delivery_v2) AS n_died_same_adm_at_delivery,
       COUNT(*) FILTER (WHERE died_same_admission <> deathtime_recorded) AS n_flag_vs_deathtime_discordant
FROM mimiciv.label_admission_v2;

-- Q-C2  Era de codificación de las admisiones de parto y tasa de SMM (decisión D4: si la SMM en
--       los partos ICD-9 es muy distinta de la de ICD-10, reconsidere la opción (b))
SELECT CASE WHEN has_icd9_dx AND NOT has_icd10_dx THEN 'ICD-9 only'
            WHEN has_icd10_dx AND NOT has_icd9_dx THEN 'ICD-10 only'
            WHEN has_icd9_dx AND has_icd10_dx     THEN 'both'
            ELSE 'none' END                                  AS coding,
       COUNT(*)                                              AS n_delivery_admissions,
       COUNT(*) FILTER (WHERE smm_any)                       AS n_smm,
       ROUND(100.0 * COUNT(*) FILTER (WHERE smm_any) / NULLIF(COUNT(*),0), 2) AS pct_smm,
       COUNT(*) FILTER (WHERE died_same_admission)           AS n_died
FROM mimiciv.label_admission_v2
WHERE is_delivery_v2
GROUP BY 1 ORDER BY 1;

-- Q-C3  SMM por indicador y versión de ICD (admisiones de parto, bandera v2)
SELECT h.indicator_name, h.icd_version, COUNT(DISTINCT h.hadm_id) AS n_admissions
FROM mimiciv.smm_hits_v2 h
JOIN mimiciv.label_admission_v2 l ON l.hadm_id = h.hadm_id AND l.is_delivery_v2
GROUP BY 1, 2 ORDER BY 3 DESC, 1, 2;

-- Q-C4  Etiqueta de SMM nueva vs ORIGINAL (mismo universo, cualquier admisión)
SELECT COUNT(*) FILTER (WHERE smm_any AND old.hadm_id IS NOT NULL)     AS smm_both,
       COUNT(*) FILTER (WHERE smm_any AND old.hadm_id IS NULL)         AS smm_only_new,
       COUNT(*) FILTER (WHERE NOT smm_any AND old.hadm_id IS NOT NULL) AS smm_only_old
FROM mimiciv.label_admission_v2 l
LEFT JOIN (SELECT DISTINCT hadm_id FROM mimiciv.hadm_with_smm) old ON old.hadm_id = l.hadm_id;

-- Q-C5  Sensibilidades de la definición: todas / sin solo renal / >=2 indicadores,
--       solo admisiones de parto
SELECT COUNT(*) FILTER (WHERE smm_any)                              AS smm_any,
       COUNT(*) FILTER (WHERE smm_any AND NOT smm_only_renal)       AS smm_excl_renal_only,
       COUNT(*) FILTER (WHERE smm_ge2)                              AS smm_ge2_indicators
FROM mimiciv.label_admission_v2
WHERE is_delivery_v2;

-- Q-C6  Pacientes con >1 admisión y sus etiquetas (relevancia de la partición agrupada)
SELECT COUNT(*) FILTER (WHERE n_adm > 1)                    AS patients_multi_admission,
       COUNT(*)                                             AS patients,
       MAX(n_adm)                                           AS max_adm_per_patient
FROM (SELECT subject_id, COUNT(*) AS n_adm FROM mimiciv.label_admission_v2 GROUP BY subject_id) t;

-- Q-C7  ¿Hay códigos heredados / no oficiales?  (conteos agregados de admisiones
--       en el universo obstétrico; indica si los códigos previos al FY2019 importan)
SELECT d.icd_code, d.icd_version, COUNT(DISTINCT d.hadm_id) AS n_admissions
FROM mimiciv.diagnoses_icd d
JOIN mimiciv.label_admission_v2 l ON l.hadm_id = d.hadm_id
WHERE (d.icd_version = 10 AND d.icd_code IN ('T814XXA','T811XXA','T80211A','I64','O2251','0UT94ZZ','0UT98ZZ','0UT9FZZ'))
   OR (d.icd_version = 9  AND d.icd_code = '9980')
GROUP BY 1, 2 ORDER BY 3 DESC;
