-- ============================================================================
-- Diagnosis statistics of the maternal cohort: mimiciv.cohort_maternal_diagnoses
-- ============================================================================
-- One row per distinct ICD code (icd_code, icd_version) among the diagnoses
-- with seq_num <= 4 of the admissions in mimiciv.cohort_maternal, with the number
-- of admissions (diagnoses), without death (no_death) and with death (death).
-- It is the base of the diagnostic-group classification applied by
-- maternal_diagnoses_group_load.sql / maternal_diagnoses_group_assign.sql.
-- Expected size: 4,116 distinct ICD codes.
--
-- PREREQUISITE: maternal_cohort.sql (creates mimiciv.cohort_maternal).
-- ============================================================================

-- NOTE: plain CREATE TABLE (no DROP): it fails if mimiciv.cohort_maternal_diagnoses already exists.
-- Drop it yourself, deliberately, if you need to rebuild it.

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
