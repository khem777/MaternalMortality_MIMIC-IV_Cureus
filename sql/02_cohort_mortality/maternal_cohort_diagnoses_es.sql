-- ============================================================================
-- Estadísticas de diagnósticos de la cohorte materna: mimiciv.cohort_maternal_diagnoses
-- ============================================================================
-- Una fila por código ICD distinto (icd_code, icd_version) entre los diagnósticos
-- con seq_num <= 4 de las admisiones de mimiciv.cohort_maternal, con el número
-- de admisiones (diagnoses), sin muerte (no_death) y con muerte (death).
-- Es la base de la clasificación por grupos diagnósticos aplicada por
-- maternal_diagnoses_group_load_es.sql / maternal_diagnoses_group_assign_es.sql.
-- Tamaño esperado: 4,116 códigos ICD distintos.
--
-- PRERREQUISITO: maternal_cohort_es.sql (crea mimiciv.cohort_maternal).
-- ============================================================================

-- NOTA: CREATE TABLE simple (sin DROP): falla si mimiciv.cohort_maternal_diagnoses ya existe.
-- Elimínela usted mismo, de forma deliberada, si necesita reconstruirla.

CREATE TABLE mimiciv.cohort_maternal_diagnoses AS
SELECT di.icd_code
       , di.icd_version
       , did.long_title
       , count(1)                                          AS diagnoses
       , sum(CASE WHEN cm.outcome = 0 THEN 1 ELSE 0 END)    AS no_death
       , sum(CASE WHEN cm.outcome = 1 THEN 1 ELSE 0 END)    AS death
FROM   mimiciv.diagnoses_icd di
JOIN   mimiciv.d_icd_diagnoses did
  ON   di.icd_code = did.icd_code AND di.icd_version = did.icd_version
JOIN   mimiciv.cohort_maternal cm
  ON   cm.subject_id = di.subject_id AND cm.hadm_id = di.hadm_id
WHERE  di.seq_num <= 4
GROUP BY di.icd_code, di.icd_version, did.long_title;

ALTER TABLE mimiciv.cohort_maternal_diagnoses ADD COLUMN diagnoses_group     varchar(300);
ALTER TABLE mimiciv.cohort_maternal_diagnoses ADD COLUMN diagnoses_group_alt varchar(300);
ALTER TABLE mimiciv.cohort_maternal_diagnoses ADD COLUMN have_diagnoses      int4 DEFAULT 0;
ALTER TABLE mimiciv.cohort_maternal_diagnoses ADD CONSTRAINT pk_cm_diagnoses PRIMARY KEY (icd_code, icd_version);
