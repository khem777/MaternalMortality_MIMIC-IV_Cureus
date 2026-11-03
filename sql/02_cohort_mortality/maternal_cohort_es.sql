-- ============================================================================
-- Cohorte materna (modelo de mortalidad): mimiciv.cohort_maternal
-- ============================================================================
-- Una fila por admisión hospitalaria de una mujer de 12 a 55 años con al menos un
-- diagnóstico obstétrico / relacionado con el embarazo.
--
-- Inclusión: gender = 'F'; diagnóstico en mimiciv.pregnancy_diagnoses_expanded
-- (coincidencia de texto + ICD-9 630-679, V22-V24, V27, V28 + ICD-10 capítulo O, Z33, Z34,
-- Z37, Z39); fecha de admisión dentro de la ventana con fechas desplazadas YYYYMM 211001-221410 (véanse las notas);
-- edad al momento de la admisión = anchor_age + (año de admisión - anchor_year) entre 12 y 55.
-- No se exige una estancia en UCI (icu_stay e icu_stay_count se conservan como variables predictoras).
--
-- Desenlace: outcome = 1 si la admisión, o cualquier admisión posterior del mismo
-- subject_id, tiene un deathtime registrado (bandera de muerte a nivel de persona).
--
-- Notas:
--   * La condición de fecha es TO_CHAR(admittime, 'YYYYMM') >= '211001' AND <= '221410'. El mes 14 no
--     existe (probablemente se quiso '221031'), por lo que en la práctica el límite superior casi no excluye nada.
--     Se conserva tal como está porque la cohorte validada (25,736 admisiones) se construyó con esta
--     condición exacta; cambiarla cambiaría la cohorte. maternal_cohort_expanded_es.sql no aplica ningún filtro de fecha.
--   * patients.dob no está poblada para adultos en este esquema, por lo que la edad se calcula
--     a partir de anchor_age / anchor_year. La columna `dob` se conserva como NULL únicamente para que
--     libraries/database.py (que selecciona `dob`) siga funcionando.
--   * Tamaño esperado: 25,736 admisiones, 41 con outcome = 1.
--
-- PRERREQUISITO: sql/02_cohort_mortality/maternal_cohort_expanded_es.sql
--   (crea mimiciv.pregnancy_diagnoses_expanded).
-- SIGUIENTE: maternal_cohort_dataset_es.sql y maternal_cohort_diagnoses_es.sql.
-- ============================================================================

-- NOTA: CREATE TABLE simple (sin DROP): falla si mimiciv.cohort_maternal ya existe.
-- Elimínela usted mismo, de forma deliberada, si necesita reconstruirla.

CREATE TABLE mimiciv.cohort_maternal AS
WITH maternal_admissions AS (
    SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.deathtime,
           a.ethnicity, a.insurance, a.language, a.admission_type, a.admission_location,
           p.anchor_age, p.anchor_year, p.gender
    FROM   mimiciv.admissions a
    JOIN   mimiciv.patients p
      ON   p.subject_id = a.subject_id
    JOIN   mimiciv.diagnoses_icd di
      ON   di.subject_id = a.subject_id
     AND   di.hadm_id    = a.hadm_id
    JOIN   mimiciv.pregnancy_diagnoses_expanded de
      ON   de.icd_code    = di.icd_code
     AND   de.icd_version = di.icd_version
    WHERE  p.gender = 'F'
    AND    TO_CHAR(a.admittime, 'YYYYMM') >= '211001'
    AND    TO_CHAR(a.admittime, 'YYYYMM') <= '221410'
    AND    p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) BETWEEN 12 AND 55
),
maternal_icu AS (
    SELECT  ma.*
           , (SELECT MIN(i.stay_id)   FROM mimiciv.icustays i
               WHERE i.subject_id = ma.subject_id AND i.hadm_id = ma.hadm_id) AS stay_id
           , (SELECT COUNT(1)        FROM mimiciv.icustays i
               WHERE i.subject_id = ma.subject_id AND i.hadm_id = ma.hadm_id) AS icu_stay_count
    FROM   maternal_admissions ma
)
SELECT  mi.subject_id
       , mi.hadm_id
       , mi.stay_id
       , NULL::timestamp AS dob
       , mi.admittime
       , mi.ethnicity
       , mi.insurance
       , mi.language
       , mi.admission_type
       , mi.admission_location
       , mi.icu_stay_count
       , (CASE WHEN mi.icu_stay_count > 0 THEN 1 ELSE 0 END) AS icu_stay
       , mi.anchor_age + (DATE_PART('year', mi.admittime) - mi.anchor_year) AS age_at_admission
       , (
            CASE WHEN mi.deathtime IS NULL
                 THEN (CASE WHEN (SELECT MIN(a2.deathtime)
                                    FROM   mimiciv.admissions a2
                                   WHERE  a2.subject_id = mi.subject_id
                                     AND  a2.deathtime IS NOT NULL) IS NOT NULL
                            THEN 1 ELSE 0 END)
                 ELSE 1
            END
         ) AS outcome
FROM   maternal_icu mi;

ALTER TABLE mimiciv.cohort_maternal ADD CONSTRAINT pk_cohort_maternal PRIMARY KEY (subject_id, hadm_id);
