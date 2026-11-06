-- ============================================================================
-- 04_labels / 01_smm_codes_official.sql
-- Official CDC SMM code catalogue (ICD-9-CM + ICD-10-CM/PCS) -- v2
-- Framework: E3 Outcome definition: official CDC code list (outcome card), matched in the source (adapter).
-- ============================================================================
-- Purpose:
--   * The original catalogue (03_cohort_smm/smm_cohort.sql) deviated from
--     the official CDC list and had ICD-10 patterns only.  This script builds
--     a NEW table (smm_code_patterns_v2) -- the original is NOT touched.
--
-- Source (verified 2026-10-23): CDC, "Severe Maternal Morbidity Indicators and
--   Corresponding ICD Codes during Delivery Hospitalizations",
--   https://www.cdc.gov/maternal-infant-health/php/severe-maternal-morbidity/icd.html
--   (last published 2024-05-15).  20 active indicators; blood transfusion
--   (ICD-9 99.0x / PCS 302xxxx) is EXCLUDED, as on the CDC page ("excluded, but
--   could be examined separately").
--
-- Conventions
--   * MIMIC-IV stores codes WITHOUT dots (e.g. 'O881', '5845').  Patterns here
--     are PREFIXES (match_type='PREFIX': icd_code LIKE pattern || '%') unless
--     match_type='EXACT'.  Where the CDC page gives an 'x' wildcard the prefix
--     is used; where it gives explicit codes (e.g. trimester-specific O88.xxx,
--     O45.0xx) the explicit full codes are listed -- first-trimester codes
--     that the CDC page does not list are therefore NOT matched.
--   * icd_version is part of the key: ICD-9 and ICD-10 prefixes never mix.
--   * ICD-9 670.2x (sepsis) applies only to discharges after 2009-10-01 per CDC.
--     MIMIC shifts dates (anchor_year), so the exact cut-off cannot be applied;
--     code '6702' is kept and flagged in column era_note (limitation to declare).
--   * ICD-9 998.0 was used before 2012 although not a valid code: kept as an
--     EXACT '9980' row, as in the CDC footnote.
--   * ICD-10 codes are the CURRENT (FY2025) CDC codes.  Codes valid only in
--     earlier fiscal years are
--     NOT included; see Q-C7 in 03_labels_same_admission.sql to check whether
--     they occur in the data.
--
-- Differences versus the ORIGINAL table, found when comparing it to the CDC
-- list (counts of codes, not patient data):
--   missing: ARDS J96.9x/R06.03; DIC O45.0x/O46.0x/O67.0; cerebrovascular
--   G45/G46/A81.2/G93.49/H34.0/O22.50; pulmonary edema I50.81x/I50.82-.89;
--   anesthesia O29.x/T88.3XXA; sepsis I76/T81.12XA; embolism T80.0XXA;
--   hysterectomy 0UT90ZL/0UT97ZL.
--   extra: I64, O22.51, T80.211A, T81.4XXA, 0UT94ZZ/0UT98ZZ/0UT9FZZ,
--   0B110Z/0B113/0B114 (all tracheostomies, not only temporary).
-- ============================================================================

DROP TABLE IF EXISTS mimiciv.smm_code_patterns_v2;

CREATE TABLE mimiciv.smm_code_patterns_v2 (
    indicator_group  VARCHAR(60),
    indicator_name   VARCHAR(60),
    code_type        VARCHAR(2),    -- 'DX' (diagnoses_icd) | 'PR' (procedures_icd)
    icd_version      SMALLINT,      -- 9 | 10
    code_pattern     VARCHAR(10),   -- no dots, as stored in MIMIC-IV
    match_type       VARCHAR(6),    -- 'PREFIX' | 'EXACT'
    era_note         VARCHAR(120)
);

INSERT INTO mimiciv.smm_code_patterns_v2
    (indicator_group, indicator_name, code_type, icd_version, code_pattern, match_type, era_note) VALUES

-- ICD-10 | Acute myocardial infarction
('Cardiac', 'Acute myocardial infarction', 'DX', 10, 'I21', 'PREFIX', NULL),
('Cardiac', 'Acute myocardial infarction', 'DX', 10, 'I22', 'PREFIX', NULL),

-- ICD-10 | Aneurysm
('Cardiac', 'Aneurysm', 'DX', 10, 'I71', 'PREFIX', NULL),
('Cardiac', 'Aneurysm', 'DX', 10, 'I790', 'PREFIX', NULL),

-- ICD-10 | Acute renal failure
('Renal', 'Acute renal failure', 'DX', 10, 'N17', 'PREFIX', NULL),
('Renal', 'Acute renal failure', 'DX', 10, 'O904', 'PREFIX', NULL),

-- ICD-10 | ARDS
('Respiratory', 'ARDS', 'DX', 10, 'J80', 'PREFIX', NULL),
('Respiratory', 'ARDS', 'DX', 10, 'J951', 'PREFIX', NULL),
('Respiratory', 'ARDS', 'DX', 10, 'J952', 'PREFIX', NULL),
('Respiratory', 'ARDS', 'DX', 10, 'J953', 'PREFIX', NULL),
('Respiratory', 'ARDS', 'DX', 10, 'J9582', 'PREFIX', NULL),
('Respiratory', 'ARDS', 'DX', 10, 'J960', 'PREFIX', NULL),
('Respiratory', 'ARDS', 'DX', 10, 'J962', 'PREFIX', NULL),
('Respiratory', 'ARDS', 'DX', 10, 'J969', 'PREFIX', NULL),
('Respiratory', 'ARDS', 'DX', 10, 'R0603', 'PREFIX', NULL),
('Respiratory', 'ARDS', 'DX', 10, 'R092', 'PREFIX', NULL),

-- ICD-10 | Amniotic fluid embolism
('Other_Obstetric', 'Amniotic fluid embolism', 'DX', 10, 'O88112', 'PREFIX', NULL),
('Other_Obstetric', 'Amniotic fluid embolism', 'DX', 10, 'O88113', 'PREFIX', NULL),
('Other_Obstetric', 'Amniotic fluid embolism', 'DX', 10, 'O88119', 'PREFIX', NULL),
('Other_Obstetric', 'Amniotic fluid embolism', 'DX', 10, 'O8812', 'PREFIX', NULL),
('Other_Obstetric', 'Amniotic fluid embolism', 'DX', 10, 'O8813', 'PREFIX', NULL),

-- ICD-10 | Cardiac arrest/ventricular fibrillation
('Cardiac', 'Cardiac arrest/ventricular fibrillation', 'DX', 10, 'I46', 'PREFIX', NULL),
('Cardiac', 'Cardiac arrest/ventricular fibrillation', 'DX', 10, 'I490', 'PREFIX', NULL),

-- ICD-10 | Conversion of cardiac rhythm
('Cardiac', 'Conversion of cardiac rhythm', 'PR', 10, '5A12012', 'PREFIX', NULL),
('Cardiac', 'Conversion of cardiac rhythm', 'PR', 10, '5A2204Z', 'PREFIX', NULL),

-- ICD-10 | DIC
('Hemorrhage', 'DIC', 'DX', 10, 'D65', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'D688', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'D689', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O670', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O723', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O45002', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O45003', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O45009', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O45012', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O45013', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O45019', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O45022', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O45023', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O45029', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O45092', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O45093', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O45099', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O46002', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O46003', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O46009', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O46012', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O46013', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O46019', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O46022', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O46023', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O46029', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O46092', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O46093', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 10, 'O46099', 'PREFIX', NULL),

-- ICD-10 | Eclampsia
('Other_Obstetric', 'Eclampsia', 'DX', 10, 'O15', 'PREFIX', NULL),

-- ICD-10 | Heart failure/arrest during surgery or procedure
('Cardiac', 'Heart failure/arrest during surgery or procedure', 'DX', 10, 'I97120', 'PREFIX', NULL),
('Cardiac', 'Heart failure/arrest during surgery or procedure', 'DX', 10, 'I97121', 'PREFIX', NULL),
('Cardiac', 'Heart failure/arrest during surgery or procedure', 'DX', 10, 'I97130', 'PREFIX', NULL),
('Cardiac', 'Heart failure/arrest during surgery or procedure', 'DX', 10, 'I97131', 'PREFIX', NULL),
('Cardiac', 'Heart failure/arrest during surgery or procedure', 'DX', 10, 'I97710', 'PREFIX', NULL),
('Cardiac', 'Heart failure/arrest during surgery or procedure', 'DX', 10, 'I97711', 'PREFIX', NULL),

-- ICD-10 | Puerperal cerebrovascular disorders
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'A812', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'G45', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'G46', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'G9349', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'H340', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I60', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I61', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I62', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I6300', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I6301', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I631', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I632', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I633', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I634', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I635', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I636', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I638', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I639', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I65', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I66', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I67', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I68', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'O2250', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'O2252', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'O2253', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I97810', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I97811', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I97820', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'I97821', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 10, 'O873', 'PREFIX', NULL),

-- ICD-10 | Pulmonary edema/acute heart failure
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I501', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I5020', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I5021', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I5023', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I5030', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I5031', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I5033', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I5040', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I5041', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I5043', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I50810', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I50811', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I50813', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I50814', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I5082', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I5083', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I5084', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I5089', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'I509', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 10, 'J810', 'PREFIX', NULL),

-- ICD-10 | Severe anesthesia complications
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29112', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29113', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29119', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29122', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29123', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29129', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29192', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29193', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29199', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29212', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29213', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29219', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29292', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29293', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O29299', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O740', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O741', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O742', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O743', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O890', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O891', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'O892', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'T882XXA', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 10, 'T883XXA', 'PREFIX', NULL),

-- ICD-10 | Sepsis
('Sepsis', 'Sepsis', 'DX', 10, 'A327', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 10, 'A40', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 10, 'A41', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 10, 'I76', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 10, 'O85', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 10, 'O8604', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 10, 'R6520', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 10, 'R6521', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 10, 'T8112XA', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 10, 'T8144XA', 'PREFIX', NULL),

-- ICD-10 | Shock
('Hemorrhage', 'Shock', 'DX', 10, 'O751', 'PREFIX', NULL),
('Hemorrhage', 'Shock', 'DX', 10, 'R57', 'PREFIX', NULL),
('Hemorrhage', 'Shock', 'DX', 10, 'T782XXA', 'PREFIX', NULL),
('Hemorrhage', 'Shock', 'DX', 10, 'T8110XA', 'PREFIX', NULL),
('Hemorrhage', 'Shock', 'DX', 10, 'T8111XA', 'PREFIX', NULL),
('Hemorrhage', 'Shock', 'DX', 10, 'T8119XA', 'PREFIX', NULL),
('Hemorrhage', 'Shock', 'DX', 10, 'T886XXA', 'PREFIX', NULL),

-- ICD-10 | Sickle cell disease with crisis
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 10, 'D5700', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 10, 'D5701', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 10, 'D5702', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 10, 'D57211', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 10, 'D57212', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 10, 'D57219', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 10, 'D57411', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 10, 'D57412', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 10, 'D57419', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 10, 'D57811', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 10, 'D57812', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 10, 'D57819', 'PREFIX', NULL),

-- ICD-10 | Air and thrombotic embolism
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'I26', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O88012', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O88013', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O88019', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O8802', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O8803', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O88212', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O88213', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O88219', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O8822', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O8823', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O88312', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O88313', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O88319', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O8832', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O8833', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O88812', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O88813', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O88819', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O8882', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'O8883', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 10, 'T800XXA', 'PREFIX', NULL),

-- ICD-10 | Hysterectomy
('Hemorrhage', 'Hysterectomy', 'PR', 10, '0UT90ZL', 'PREFIX', NULL),
('Hemorrhage', 'Hysterectomy', 'PR', 10, '0UT90ZZ', 'PREFIX', NULL),
('Hemorrhage', 'Hysterectomy', 'PR', 10, '0UT97ZL', 'PREFIX', NULL),
('Hemorrhage', 'Hysterectomy', 'PR', 10, '0UT97ZZ', 'PREFIX', NULL),

-- ICD-10 | Temporary tracheostomy
('Respiratory', 'Temporary tracheostomy', 'PR', 10, '0B110F4', 'PREFIX', NULL),
('Respiratory', 'Temporary tracheostomy', 'PR', 10, '0B113F4', 'PREFIX', NULL),
('Respiratory', 'Temporary tracheostomy', 'PR', 10, '0B114F4', 'PREFIX', NULL),

-- ICD-10 | Ventilation
('Respiratory', 'Ventilation', 'PR', 10, '5A1935Z', 'PREFIX', NULL),
('Respiratory', 'Ventilation', 'PR', 10, '5A1945Z', 'PREFIX', NULL),
('Respiratory', 'Ventilation', 'PR', 10, '5A1955Z', 'PREFIX', NULL),

-- ICD-9 | Acute myocardial infarction
('Cardiac', 'Acute myocardial infarction', 'DX', 9, '410', 'PREFIX', NULL),

-- ICD-9 | Aneurysm
('Cardiac', 'Aneurysm', 'DX', 9, '441', 'PREFIX', NULL),

-- ICD-9 | Acute renal failure
('Renal', 'Acute renal failure', 'DX', 9, '5845', 'PREFIX', NULL),
('Renal', 'Acute renal failure', 'DX', 9, '5846', 'PREFIX', NULL),
('Renal', 'Acute renal failure', 'DX', 9, '5847', 'PREFIX', NULL),
('Renal', 'Acute renal failure', 'DX', 9, '5848', 'PREFIX', NULL),
('Renal', 'Acute renal failure', 'DX', 9, '5849', 'PREFIX', NULL),
('Renal', 'Acute renal failure', 'DX', 9, '6693', 'PREFIX', NULL),

-- ICD-9 | ARDS
('Respiratory', 'ARDS', 'DX', 9, '5185', 'PREFIX', NULL),
('Respiratory', 'ARDS', 'DX', 9, '51881', 'PREFIX', NULL),
('Respiratory', 'ARDS', 'DX', 9, '51882', 'PREFIX', NULL),
('Respiratory', 'ARDS', 'DX', 9, '51884', 'PREFIX', NULL),
('Respiratory', 'ARDS', 'DX', 9, '7991', 'PREFIX', NULL),

-- ICD-9 | Amniotic fluid embolism
('Other_Obstetric', 'Amniotic fluid embolism', 'DX', 9, '6731', 'PREFIX', NULL),

-- ICD-9 | Cardiac arrest/ventricular fibrillation
('Cardiac', 'Cardiac arrest/ventricular fibrillation', 'DX', 9, '42741', 'PREFIX', NULL),
('Cardiac', 'Cardiac arrest/ventricular fibrillation', 'DX', 9, '42742', 'PREFIX', NULL),
('Cardiac', 'Cardiac arrest/ventricular fibrillation', 'DX', 9, '4275', 'PREFIX', NULL),

-- ICD-9 | Conversion of cardiac rhythm
('Cardiac', 'Conversion of cardiac rhythm', 'PR', 9, '996', 'PREFIX', NULL),

-- ICD-9 | DIC
('Hemorrhage', 'DIC', 'DX', 9, '2866', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 9, '2869', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 9, '6413', 'PREFIX', NULL),
('Hemorrhage', 'DIC', 'DX', 9, '6663', 'PREFIX', NULL),

-- ICD-9 | Eclampsia
('Other_Obstetric', 'Eclampsia', 'DX', 9, '6426', 'PREFIX', NULL),

-- ICD-9 | Heart failure/arrest during surgery or procedure
('Cardiac', 'Heart failure/arrest during surgery or procedure', 'DX', 9, '9971', 'PREFIX', NULL),

-- ICD-9 | Puerperal cerebrovascular disorders
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 9, '0463', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 9, '34839', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 9, '36234', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 9, '430', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 9, '431', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 9, '432', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 9, '433', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 9, '434', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 9, '435', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 9, '436', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 9, '437', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 9, '6715', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 9, '6740', 'PREFIX', NULL),
('Other_Medical', 'Puerperal cerebrovascular disorders', 'DX', 9, '99702', 'PREFIX', NULL),

-- ICD-9 | Pulmonary edema/acute heart failure
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 9, '4280', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 9, '4281', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 9, '42820', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 9, '42821', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 9, '42823', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 9, '42830', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 9, '42831', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 9, '42833', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 9, '42840', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 9, '42841', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 9, '42843', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 9, '4289', 'PREFIX', NULL),
('Cardiac', 'Pulmonary edema/acute heart failure', 'DX', 9, '5184', 'PREFIX', NULL),

-- ICD-9 | Severe anesthesia complications
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 9, '6680', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 9, '6681', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 9, '6682', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 9, '9954', 'PREFIX', NULL),
('Other_Obstetric', 'Severe anesthesia complications', 'DX', 9, '99586', 'PREFIX', NULL),

-- ICD-9 | Sepsis
('Sepsis', 'Sepsis', 'DX', 9, '038', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 9, '449', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 9, '78552', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 9, '99591', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 9, '99592', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 9, '99802', 'PREFIX', NULL),
('Sepsis', 'Sepsis', 'DX', 9, '6702', 'PREFIX', 'CDC: only after 2009-10-01; date shift prevents exact cut-off'),

-- ICD-9 | Shock
('Hemorrhage', 'Shock', 'DX', 9, '6691', 'PREFIX', NULL),
('Hemorrhage', 'Shock', 'DX', 9, '78550', 'PREFIX', NULL),
('Hemorrhage', 'Shock', 'DX', 9, '78551', 'PREFIX', NULL),
('Hemorrhage', 'Shock', 'DX', 9, '78559', 'PREFIX', NULL),
('Hemorrhage', 'Shock', 'DX', 9, '9950', 'PREFIX', NULL),
('Hemorrhage', 'Shock', 'DX', 9, '99800', 'PREFIX', NULL),
('Hemorrhage', 'Shock', 'DX', 9, '99801', 'PREFIX', NULL),
('Hemorrhage', 'Shock', 'DX', 9, '99809', 'PREFIX', NULL),

-- ICD-9 | Sickle cell disease with crisis
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 9, '28242', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 9, '28262', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 9, '28264', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 9, '28269', 'PREFIX', NULL),
('Other_Medical', 'Sickle cell disease with crisis', 'DX', 9, '28952', 'PREFIX', NULL),

-- ICD-9 | Air and thrombotic embolism
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 9, '4150', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 9, '4151', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 9, '6730', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 9, '6732', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 9, '6733', 'PREFIX', NULL),
('Other_Obstetric', 'Air and thrombotic embolism', 'DX', 9, '6738', 'PREFIX', NULL),

-- ICD-9 | Hysterectomy
('Hemorrhage', 'Hysterectomy', 'PR', 9, '683', 'PREFIX', NULL),
('Hemorrhage', 'Hysterectomy', 'PR', 9, '684', 'PREFIX', NULL),
('Hemorrhage', 'Hysterectomy', 'PR', 9, '685', 'PREFIX', NULL),
('Hemorrhage', 'Hysterectomy', 'PR', 9, '686', 'PREFIX', NULL),
('Hemorrhage', 'Hysterectomy', 'PR', 9, '687', 'PREFIX', NULL),
('Hemorrhage', 'Hysterectomy', 'PR', 9, '689', 'PREFIX', NULL),

-- ICD-9 | Temporary tracheostomy
('Respiratory', 'Temporary tracheostomy', 'PR', 9, '311', 'PREFIX', NULL),

-- ICD-9 | Ventilation
('Respiratory', 'Ventilation', 'PR', 9, '9670', 'PREFIX', NULL),
('Respiratory', 'Ventilation', 'PR', 9, '9671', 'PREFIX', NULL),
('Respiratory', 'Ventilation', 'PR', 9, '9672', 'PREFIX', NULL),

-- ICD-9 | Shock
('Hemorrhage', 'Shock', 'DX', 9, '9980', 'EXACT', '998.0 not a valid code; used before 2012 (CDC footnote)');

-- Sanity checks -- aggregate only
SELECT icd_version, code_type, COUNT(*) AS n_patterns, COUNT(DISTINCT indicator_name) AS n_indicators
FROM mimiciv.smm_code_patterns_v2
GROUP BY icd_version, code_type ORDER BY icd_version, code_type;
-- expected: 20 active indicators in each ICD version (16 diagnosis-based + 4 procedure-based).
SELECT icd_version, COUNT(DISTINCT indicator_name) AS n_indicators
FROM mimiciv.smm_code_patterns_v2 GROUP BY icd_version;   -- expect 20 and 20
