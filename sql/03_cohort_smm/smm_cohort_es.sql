-- ============================================================================
-- ESTADO (2026-10-25): este script define las etiquetas de la primera versión del análisis (v1)
-- ============================================================================
-- Se ejecutó en la base de datos local y produjo las 475 admisiones con SMM de la
-- versión v1. Se conocen dos limitaciones de esa versión, corregidas en la
-- versión actual, por lo que no debe usarse este script para el análisis revisado:
--   (1) Códigos de SMM: solo ICD-10-CM/PCS. MIMIC-IV tiene diagnósticos y
--       procedimientos ICD-9-CM hasta 2015, por lo que las admisiones con ICD-9 se contaron como SMM-negativas.
--   (2) Bandera de parto: solo ICD-10 Z37/O80/O82; 8,857 partos, frente a 19,425
--       con la bandera revisada (diagnósticos, procedimientos y DRG, ICD-9 e ICD-10).
-- Definiciones revisadas (lista oficial de los CDC en ambas versiones de ICD, bandera de parto,
-- etiquetas de la misma admisión): véase sql/04_labels/. Conteos que comparan las
-- dos versiones: sql/06_audit_counts/.
-- En este archivo solo se editaron comentarios; no se modificó ninguna sentencia SQL.
-- ============================================================================

-- ============================================================================
-- COHORTE "NEAR-MISS" / MORBILIDAD MATERNA GRAVE (SMM) -- Modelo B
-- ============================================================================
-- Versión en inglés (original) de este script: smm_cohort.sql (misma carpeta).
--
-- Fuente de los 21 indicadores y códigos ICD-10-CM/PCS: CDC (2023), a través del
-- documento de recursos HRSA Federally Available Data (FAD) 2023, reproducido en el
-- Apéndice 1 del informe "Severe Maternal Morbidity Report
-- 2017-2021" del DHHS de Nebraska (Jul-2024). El indicador #18 (transfusión de sangre) se excluye
-- porque HRSA lo retiró oficialmente en 2023 ("no longer used") -- por lo que este
-- script usa los 20 indicadores actualmente activos, en concordancia con ese informe
-- estatal.
--
-- IMPORTANTE: la definición oficial de SMM de los CDC se mide sobre las "hospitalizaciones de parto",
-- no sobre cualquier admisión con un diagnóstico obstétrico.
-- Por eso este script calcula el indicador de SMM sobre DOS denominadores,
-- para que se puedan comparar:
--   (a) Solo hospitalizaciones de parto (un código de desenlace de parto Z37.x u
--       O80-O82.x) -- comparable con las tasas publicadas por los CDC/estados
--       (58-88 SMM por cada 10,000 partos).
--   (b) La cohorte obstétrica expandida completa
--       (maternal_cohort_expanded_es.sql) -- un denominador más amplio, más
--       casos absolutos, pero ya no comparable 1:1 con las tasas publicadas.
--
-- (Nota original, reemplazada por el bloque ESTADO al inicio: desde entonces este script
-- se ejecutó en la base de datos local, localhost:5433.)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Paso 1: catálogo de patrones ICD-10 para los 20 indicadores de SMM
-- actualmente activos
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.smm_code_patterns;

CREATE TABLE mimiciv.smm_code_patterns (
    indicator_group  VARCHAR(60),
    indicator_name   VARCHAR(60),
    code_type        VARCHAR(2),   -- 'DX' (diagnoses_icd) o 'PR' (procedures_icd)
    code_pattern     VARCHAR(10)   -- prefijo; se compara como icd_code LIKE pattern || '%'
);

INSERT INTO mimiciv.smm_code_patterns (indicator_group, indicator_name, code_type, code_pattern) VALUES
-- 1. Infarto agudo de miocardio
('Cardiac',  'Acute myocardial infarction', 'DX', 'I21'),
('Cardiac',  'Acute myocardial infarction', 'DX', 'I22'),
-- 2. Aneurisma
('Cardiac',  'Aneurysm', 'DX', 'I71'),
('Cardiac',  'Aneurysm', 'DX', 'I790'),
-- 3. Insuficiencia renal aguda
('Renal',    'Acute renal failure', 'DX', 'N17'),
('Renal',    'Acute renal failure', 'DX', 'O904'),
-- 4. Síndrome de dificultad respiratoria del adulto
('Respiratory', 'ARDS', 'DX', 'J80'),
('Respiratory', 'ARDS', 'DX', 'J951'),
('Respiratory', 'ARDS', 'DX', 'J952'),
('Respiratory', 'ARDS', 'DX', 'J953'),
('Respiratory', 'ARDS', 'DX', 'J9582'),
('Respiratory', 'ARDS', 'DX', 'J960'),
('Respiratory', 'ARDS', 'DX', 'J962'),
('Respiratory', 'ARDS', 'DX', 'R092'),
-- 5. Embolia de líquido amniótico
('Other_Obstetric', 'Amniotic fluid embolism', 'DX', 'O881'),
-- 6. Paro cardíaco / fibrilación ventricular
('Cardiac',  'Cardiac arrest/ventricular fibrillation', 'DX', 'I46'),
('Cardiac',  'Cardiac arrest/ventricular fibrillation', 'DX', 'I490'),
-- 7. Conversión del ritmo cardíaco (procedimiento, ICD-10-PCS)
('Cardiac',  'Conversion of cardiac rhythm', 'PR', '5A2204Z'),
('Cardiac',  'Conversion of cardiac rhythm', 'PR', '5A12012'),
-- 8. Coagulación intravascular diseminada
('Hemorrhage', 'DIC', 'DX', 'D65'),
('Hemorrhage', 'DIC', 'DX', 'D688'),
('Hemorrhage', 'DIC', 'DX', 'D689'),
('Hemorrhage', 'DIC', 'DX', 'O723'),
-- 9. Eclampsia
('Other_Obstetric', 'Eclampsia', 'DX', 'O15'),
-- 10. Insuficiencia/paro cardíaco durante cirugía o procedimiento
('Cardiac',  'Heart failure/arrest during surgery or procedure', 'DX', 'I9712'),
('Cardiac',  'Heart failure/arrest during surgery or procedure', 'DX', 'I9713'),
('Cardiac',  'Heart failure/arrest during surgery or procedure', 'DX', 'I97710'),
('Cardiac',  'Heart failure/arrest during surgery or procedure', 'DX', 'I97711'),
-- 11. Trastornos cerebrovasculares puerperales
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I60'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I61'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I62'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I63'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I64'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I65'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I66'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I67'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I68'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'O2251'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'O2252'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'O2253'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I9781'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'I9782'),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 'O873'),
-- 12. Edema pulmonar / Insuficiencia cardíaca aguda
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'J810'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I501'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5020'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5021'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5023'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5030'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5031'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5033'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5040'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5041'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I5043'),
('Cardiac',  'Pulmonary edema/acute heart failure', 'DX', 'I509'),
-- 13. Complicaciones graves de la anestesia
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 'O740'),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 'O741'),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 'O742'),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 'O743'),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 'O890'),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 'O891'),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 'O892'),
-- 14. Sepsis
('Sepsis',   'Sepsis', 'DX', 'O85'),
('Sepsis',   'Sepsis', 'DX', 'O8604'),
('Sepsis',   'Sepsis', 'DX', 'T80211A'),
('Sepsis',   'Sepsis', 'DX', 'T814XXA'),
('Sepsis',   'Sepsis', 'DX', 'T8144'),
('Sepsis',   'Sepsis', 'DX', 'R6520'),
('Sepsis',   'Sepsis', 'DX', 'A40'),
('Sepsis',   'Sepsis', 'DX', 'A41'),
('Sepsis',   'Sepsis', 'DX', 'A327'),
-- 15. Choque
('Hemorrhage', 'Shock', 'DX', 'O751'),
('Hemorrhage', 'Shock', 'DX', 'R57'),
('Hemorrhage', 'Shock', 'DX', 'R6521'),
('Hemorrhage', 'Shock', 'DX', 'T782XXA'),
('Hemorrhage', 'Shock', 'DX', 'T882XXA'),
('Hemorrhage', 'Shock', 'DX', 'T886XXA'),
('Hemorrhage', 'Shock', 'DX', 'T8110XA'),
('Hemorrhage', 'Shock', 'DX', 'T8111XA'),
('Hemorrhage', 'Shock', 'DX', 'T8119XA'),
-- 16. Enfermedad de células falciformes con crisis
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 'D570'),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 'D5721'),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 'D5741'),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 'D5781'),
-- 17. Embolia aérea y trombótica
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 'I26'),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 'O880'),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 'O882'),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 'O883'),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 'O888'),
-- 18. Transfusión de hemoderivados: EXCLUIDO (retirado por HRSA en 2023)
-- 19. Histerectomía (procedimiento, ICD-10-PCS)
('Hemorrhage', 'Hysterectomy', 'PR', '0UT90ZZ'),
('Hemorrhage', 'Hysterectomy', 'PR', '0UT94ZZ'),
('Hemorrhage', 'Hysterectomy', 'PR', '0UT97ZZ'),
('Hemorrhage', 'Hysterectomy', 'PR', '0UT98ZZ'),
('Hemorrhage', 'Hysterectomy', 'PR', '0UT9FZZ'),
-- 20. Traqueostomía temporal (procedimiento)
('Respiratory', 'Temporary tracheostomy', 'PR', '0B110Z'),
('Respiratory', 'Temporary tracheostomy', 'PR', '0B110F'),
('Respiratory', 'Temporary tracheostomy', 'PR', '0B113'),
('Respiratory', 'Temporary tracheostomy', 'PR', '0B114'),
-- 21. Ventilación (procedimiento)
('Respiratory', 'Ventilation', 'PR', '5A1935Z'),
('Respiratory', 'Ventilation', 'PR', '5A1945Z'),
('Respiratory', 'Ventilation', 'PR', '5A1955Z');

-- ----------------------------------------------------------------------------
-- Paso 2: hadm_id con al menos un indicador de SMM (solo ICD-10, como en la versión
-- v1). MIMIC-IV también tiene datos ICD-9-CM hasta 2015, que este paso no
-- considera; la versión actual aplica la lista de los CDC para ICD-9-CM en sql/04_labels/.
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS mimiciv.hadm_with_smm;

CREATE VIEW mimiciv.hadm_with_smm AS
SELECT DISTINCT d.subject_id, d.hadm_id, p.indicator_group, p.indicator_name
FROM mimiciv.diagnoses_icd d
JOIN mimiciv.smm_code_patterns p
  ON p.code_type = 'DX'
 AND d.icd_version = 10
 AND d.icd_code LIKE p.code_pattern || '%'
UNION
SELECT DISTINCT pr.subject_id, pr.hadm_id, p.indicator_group, p.indicator_name
FROM mimiciv.procedures_icd pr
JOIN mimiciv.smm_code_patterns p
  ON p.code_type = 'PR'
 AND pr.icd_version = 10
 AND pr.icd_code LIKE p.code_pattern || '%';

-- ----------------------------------------------------------------------------
-- Paso 3: identificar hospitalizaciones de parto (aproximación: código de desenlace de parto
-- Z37.x, o encuentro de parto O80.x/O82.x)
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS mimiciv.hadm_delivery_hospitalization;

CREATE VIEW mimiciv.hadm_delivery_hospitalization AS
SELECT DISTINCT d.subject_id, d.hadm_id
FROM mimiciv.diagnoses_icd d
WHERE d.icd_version = 10
  AND (d.icd_code LIKE 'Z37%' OR d.icd_code LIKE 'O80%' OR d.icd_code LIKE 'O82%');

-- ----------------------------------------------------------------------------
-- Paso 4: cohorte final que combina el universo obstétrico expandido (Paso 2 de
-- maternal_cohort_expanded_es.sql) + desenlace de SMM + bandera de parto
-- ----------------------------------------------------------------------------
WITH maternal_admissions AS (
    SELECT DISTINCT
        a.subject_id,
        a.hadm_id,
        p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) AS approx_age
    FROM mimiciv.admissions a
    JOIN mimiciv.patients p
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) BETWEEN 12 AND 55
      AND (a.subject_id, a.hadm_id) IN (
            SELECT d.subject_id, d.hadm_id
            FROM mimiciv.diagnoses_icd d
            JOIN mimiciv.pregnancy_diagnoses_expanded de
              ON d.icd_code = de.icd_code
             AND d.icd_version = de.icd_version
      )
)
SELECT
    COUNT(*)                                                              AS total_obstetric_admissions,
    COUNT(*) FILTER (WHERE dh.hadm_id IS NOT NULL)                        AS total_delivery_hospitalizations,
    COUNT(DISTINCT smm.hadm_id)                                           AS total_with_smm_any_admission,
    COUNT(DISTINCT smm.hadm_id) FILTER (WHERE dh.hadm_id IS NOT NULL)     AS total_with_smm_at_delivery
FROM maternal_admissions ma
LEFT JOIN mimiciv.hadm_delivery_hospitalization dh
  ON ma.subject_id = dh.subject_id AND ma.hadm_id = dh.hadm_id
LEFT JOIN mimiciv.hadm_with_smm smm
  ON ma.subject_id = smm.subject_id AND ma.hadm_id = smm.hadm_id;

-- Detalle por categoría de complicación (equivalente a la Tabla 6 del informe
-- de Nebraska), útil para una tabla comparativa en la tesis:
-- SELECT indicator_group, count(DISTINCT hadm_id) AS n
-- FROM mimiciv.hadm_with_smm
-- GROUP BY indicator_group
-- ORDER BY n DESC;
