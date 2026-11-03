-- ============================================================================
-- Analysis-ready dataset (mortality model): mimiciv.cohort_maternal_dataset
-- ============================================================================
-- One row per admission of mimiciv.cohort_maternal, with administrative
-- attributes, the outcome, and the EARLIEST available value of 27 chart / lab
-- measurements (nested-query pattern X -> Y -> K):
--   * ICU-only (mimiciv.chartevents): heart rate, respiratory rate, O2 saturation,
--     mean / systolic / diastolic blood pressure, temperature, weight, height,
--     GCS (eye, verbal, motor), RASS, PEEP set.
--   * Laboratory (earliest of chartevents OR labevents, hospital-wide): glucose,
--     hemoglobin, sodium, potassium, calcium, magnesium, chloride, bicarbonate,
--     phosphorus, creatinine, hematocrit, lactate, anion gap.
--     labevents itemids: glucose 50931, hemoglobin 51222, sodium 50983,
--     potassium 50971, calcium 50893, magnesium 50960, chloride 50902,
--     bicarbonate 50882, phosphate 50970, creatinine 50912, hematocrit 51221,
--     lactate 50813, anion gap 50868.
-- Admissions without an ICU stay keep NULL in the ICU-only variables.
--
-- PREREQUISITE: maternal_cohort.sql (creates mimiciv.cohort_maternal).
-- NOTE: slow (correlated subqueries over chartevents / labevents). Run the whole
-- script at once. Expected size: 25,736 rows, 41 with outcome = 1.
-- ============================================================================

-- NOTE: plain CREATE TABLE (no DROP): it fails if mimiciv.cohort_maternal_dataset already exists.
-- Drop it yourself, deliberately, if you need to rebuild it.

CREATE TABLE mimiciv.cohort_maternal_dataset AS
SELECT K.*
FROM
(
	select Y.subject_id
	       , Y.hadm_id
	       , Y.stay_id
	       , Y.dob
	       , Y.age_at_admission
	       , Y.ethnicity
	       , Y.insurance
	       , Y.language
	       , Y.admission_type
	       , Y.admission_location
	       , Y.icu_stay
	       , Y.icu_stay_count
	       , Y.outcome
	   , (
		select max(c.valuenum)
		from   mimiciv.chartevents c
		where  c.subject_id = Y.subject_id
		and    c.hadm_id    = Y.hadm_id
		and    c.stay_id    = Y.stay_id
		and    c.itemid     = 220045
		and    c.valuenum is not null
		and    c.charttime = (
							 select min(c2.charttime)
							 from   mimiciv.chartevents c2
							 where  c2.subject_id = c.subject_id
							 and    c2.hadm_id    = c.hadm_id
							 and    c2.stay_id    = c.stay_id
							 and    c2.itemid     = 220045
							 and    c2.valuenum is not null
							)
	) as heart_rate
	   , (
		select max(c.valuenum)
		from   mimiciv.chartevents c
		where  c.subject_id = Y.subject_id
		and    c.hadm_id    = Y.hadm_id
		and    c.stay_id    = Y.stay_id
		and    c.itemid     = 220210
		and    c.valuenum is not null
		and    c.charttime = (
							 select min(c2.charttime)
							 from   mimiciv.chartevents c2
							 where  c2.subject_id = c.subject_id
							 and    c2.hadm_id    = c.hadm_id
							 and    c2.stay_id    = c.stay_id
							 and    c2.itemid     = 220210
							 and    c2.valuenum is not null
							)
	) as respiratory_rate
	   , (
		select max(c.valuenum)
		from   mimiciv.chartevents c
		where  c.subject_id = Y.subject_id
		and    c.hadm_id    = Y.hadm_id
		and    c.stay_id    = Y.stay_id
		and    c.itemid     = 220277
		and    c.valuenum is not null
		and    c.charttime = (
							 select min(c2.charttime)
							 from   mimiciv.chartevents c2
							 where  c2.subject_id = c.subject_id
							 and    c2.hadm_id    = c.hadm_id
							 and    c2.stay_id    = c.stay_id
							 and    c2.itemid     = 220277
							 and    c2.valuenum is not null
							)
	) as o2_saturation
	   , (
		select max(c.valuenum)
		from   mimiciv.chartevents c
		where  c.subject_id = Y.subject_id
		and    c.hadm_id    = Y.hadm_id
		and    c.stay_id    = Y.stay_id
		and    c.itemid     = 220181
		and    c.valuenum is not null
		and    c.charttime = (
							 select min(c2.charttime)
							 from   mimiciv.chartevents c2
							 where  c2.subject_id = c.subject_id
							 and    c2.hadm_id    = c.hadm_id
							 and    c2.stay_id    = c.stay_id
							 and    c2.itemid     = 220181
							 and    c2.valuenum is not null
							)
	) as pressure_blood_mean
	   , (
		select max(c.valuenum)
		from   mimiciv.chartevents c
		where  c.subject_id = Y.subject_id
		and    c.hadm_id    = Y.hadm_id
		and    c.stay_id    = Y.stay_id
		and    c.itemid     = 220179
		and    c.valuenum is not null
		and    c.charttime = (
							 select min(c2.charttime)
							 from   mimiciv.chartevents c2
							 where  c2.subject_id = c.subject_id
							 and    c2.hadm_id    = c.hadm_id
							 and    c2.stay_id    = c.stay_id
							 and    c2.itemid     = 220179
							 and    c2.valuenum is not null
							)
	) as pressure_blood_systolic
	   , (
		select max(c.valuenum)
		from   mimiciv.chartevents c
		where  c.subject_id = Y.subject_id
		and    c.hadm_id    = Y.hadm_id
		and    c.stay_id    = Y.stay_id
		and    c.itemid     = 220180
		and    c.valuenum is not null
		and    c.charttime = (
							 select min(c2.charttime)
							 from   mimiciv.chartevents c2
							 where  c2.subject_id = c.subject_id
							 and    c2.hadm_id    = c.hadm_id
							 and    c2.stay_id    = c.stay_id
							 and    c2.itemid     = 220180
							 and    c2.valuenum is not null
							)
	) as pressure_blood_diastolic
	   , (
		select max(c.valuenum)
		from   mimiciv.chartevents c
		where  c.subject_id = Y.subject_id
		and    c.hadm_id    = Y.hadm_id
		and    c.stay_id    = Y.stay_id
		and    c.itemid     = 223761
		and    c.valuenum is not null
		and    c.charttime = (
							 select min(c2.charttime)
							 from   mimiciv.chartevents c2
							 where  c2.subject_id = c.subject_id
							 and    c2.hadm_id    = c.hadm_id
							 and    c2.stay_id    = c.stay_id
							 and    c2.itemid     = 223761
							 and    c2.valuenum is not null
							)
	) as temperature_fahrenheit
	   , (
		select max(c.valuenum)
		from   mimiciv.chartevents c
		where  c.subject_id = Y.subject_id
		and    c.hadm_id    = Y.hadm_id
		and    c.stay_id    = Y.stay_id
		and    c.itemid     = 226512
		and    c.valuenum is not null
		and    c.charttime = (
							 select min(c2.charttime)
							 from   mimiciv.chartevents c2
							 where  c2.subject_id = c.subject_id
							 and    c2.hadm_id    = c.hadm_id
							 and    c2.stay_id    = c.stay_id
							 and    c2.itemid     = 226512
							 and    c2.valuenum is not null
							)
	) as weight_admission
	   , (
		-- earliest available value from EITHER chartevents (ICU-only) OR
		-- labevents (hospital-wide), so the lab is also recovered for admissions
		-- that never had an ICU stay
		select combined.valuenum
		from (
			select c.valuenum, c.charttime
			from   mimiciv.chartevents c
			where  c.subject_id = Y.subject_id
			and    c.hadm_id    = Y.hadm_id
			and    c.stay_id    = Y.stay_id
			and    c.itemid     = 220621
			and    c.valuenum is not null
			union all
			select le.valuenum, le.charttime
			from   mimiciv.labevents le
			where  le.subject_id = Y.subject_id
			and    le.hadm_id    = Y.hadm_id
			and    le.itemid     = 50931
			and    le.valuenum is not null
		) combined
		order by combined.charttime asc
		limit 1
	) as glucose
	   , (
		-- earliest available value from EITHER chartevents (ICU-only) OR
		-- labevents (hospital-wide), so the lab is also recovered for admissions
		-- that never had an ICU stay
		select combined.valuenum
		from (
			select c.valuenum, c.charttime
			from   mimiciv.chartevents c
			where  c.subject_id = Y.subject_id
			and    c.hadm_id    = Y.hadm_id
			and    c.stay_id    = Y.stay_id
			and    c.itemid     = 220228
			and    c.valuenum is not null
			union all
			select le.valuenum, le.charttime
			from   mimiciv.labevents le
			where  le.subject_id = Y.subject_id
			and    le.hadm_id    = Y.hadm_id
			and    le.itemid     = 51222
			and    le.valuenum is not null
		) combined
		order by combined.charttime asc
		limit 1
	) as hemoglobine
	   , (
		-- earliest available value from EITHER chartevents (ICU-only) OR
		-- labevents (hospital-wide), so the lab is also recovered for admissions
		-- that never had an ICU stay
		select combined.valuenum
		from (
			select c.valuenum, c.charttime
			from   mimiciv.chartevents c
			where  c.subject_id = Y.subject_id
			and    c.hadm_id    = Y.hadm_id
			and    c.stay_id    = Y.stay_id
			and    c.itemid     = 220645
			and    c.valuenum is not null
			union all
			select le.valuenum, le.charttime
			from   mimiciv.labevents le
			where  le.subject_id = Y.subject_id
			and    le.hadm_id    = Y.hadm_id
			and    le.itemid     = 50983
			and    le.valuenum is not null
		) combined
		order by combined.charttime asc
		limit 1
	) as sodium
	   , (
		-- earliest available value from EITHER chartevents (ICU-only) OR
		-- labevents (hospital-wide), so the lab is also recovered for admissions
		-- that never had an ICU stay
		select combined.valuenum
		from (
			select c.valuenum, c.charttime
			from   mimiciv.chartevents c
			where  c.subject_id = Y.subject_id
			and    c.hadm_id    = Y.hadm_id
			and    c.stay_id    = Y.stay_id
			and    c.itemid     = 227442
			and    c.valuenum is not null
			union all
			select le.valuenum, le.charttime
			from   mimiciv.labevents le
			where  le.subject_id = Y.subject_id
			and    le.hadm_id    = Y.hadm_id
			and    le.itemid     = 50971
			and    le.valuenum is not null
		) combined
		order by combined.charttime asc
		limit 1
	) as potassium
	   , (
		-- earliest available value from EITHER chartevents (ICU-only) OR
		-- labevents (hospital-wide), so the lab is also recovered for admissions
		-- that never had an ICU stay
		select combined.valuenum
		from (
			select c.valuenum, c.charttime
			from   mimiciv.chartevents c
			where  c.subject_id = Y.subject_id
			and    c.hadm_id    = Y.hadm_id
			and    c.stay_id    = Y.stay_id
			and    c.itemid     = 225625
			and    c.valuenum is not null
			union all
			select le.valuenum, le.charttime
			from   mimiciv.labevents le
			where  le.subject_id = Y.subject_id
			and    le.hadm_id    = Y.hadm_id
			and    le.itemid     = 50893
			and    le.valuenum is not null
		) combined
		order by combined.charttime asc
		limit 1
	) as noionized_calcium
	   , (
		-- earliest available value from EITHER chartevents (ICU-only) OR
		-- labevents (hospital-wide), so the lab is also recovered for admissions
		-- that never had an ICU stay
		select combined.valuenum
		from (
			select c.valuenum, c.charttime
			from   mimiciv.chartevents c
			where  c.subject_id = Y.subject_id
			and    c.hadm_id    = Y.hadm_id
			and    c.stay_id    = Y.stay_id
			and    c.itemid     = 220635
			and    c.valuenum is not null
			union all
			select le.valuenum, le.charttime
			from   mimiciv.labevents le
			where  le.subject_id = Y.subject_id
			and    le.hadm_id    = Y.hadm_id
			and    le.itemid     = 50960
			and    le.valuenum is not null
		) combined
		order by combined.charttime asc
		limit 1
	) as magnesium
	   , (
		-- earliest available value from EITHER chartevents (ICU-only) OR
		-- labevents (hospital-wide), so the lab is also recovered for admissions
		-- that never had an ICU stay
		select combined.valuenum
		from (
			select c.valuenum, c.charttime
			from   mimiciv.chartevents c
			where  c.subject_id = Y.subject_id
			and    c.hadm_id    = Y.hadm_id
			and    c.stay_id    = Y.stay_id
			and    c.itemid     = 220602
			and    c.valuenum is not null
			union all
			select le.valuenum, le.charttime
			from   mimiciv.labevents le
			where  le.subject_id = Y.subject_id
			and    le.hadm_id    = Y.hadm_id
			and    le.itemid     = 50902
			and    le.valuenum is not null
		) combined
		order by combined.charttime asc
		limit 1
	) as chloride
	   , (
		-- earliest available value from EITHER chartevents (ICU-only) OR
		-- labevents (hospital-wide), so the lab is also recovered for admissions
		-- that never had an ICU stay
		select combined.valuenum
		from (
			select c.valuenum, c.charttime
			from   mimiciv.chartevents c
			where  c.subject_id = Y.subject_id
			and    c.hadm_id    = Y.hadm_id
			and    c.stay_id    = Y.stay_id
			and    c.itemid     = 227443
			and    c.valuenum is not null
			union all
			select le.valuenum, le.charttime
			from   mimiciv.labevents le
			where  le.subject_id = Y.subject_id
			and    le.hadm_id    = Y.hadm_id
			and    le.itemid     = 50882
			and    le.valuenum is not null
		) combined
		order by combined.charttime asc
		limit 1
	) as bicarbonate
	   , (
		-- earliest available value from EITHER chartevents (ICU-only) OR
		-- labevents (hospital-wide), so the lab is also recovered for admissions
		-- that never had an ICU stay
		select combined.valuenum
		from (
			select c.valuenum, c.charttime
			from   mimiciv.chartevents c
			where  c.subject_id = Y.subject_id
			and    c.hadm_id    = Y.hadm_id
			and    c.stay_id    = Y.stay_id
			and    c.itemid     = 225677
			and    c.valuenum is not null
			union all
			select le.valuenum, le.charttime
			from   mimiciv.labevents le
			where  le.subject_id = Y.subject_id
			and    le.hadm_id    = Y.hadm_id
			and    le.itemid     = 50970
			and    le.valuenum is not null
		) combined
		order by combined.charttime asc
		limit 1
	) as phosphorus
	   , (
		-- earliest available value from EITHER chartevents (ICU-only) OR
		-- labevents (hospital-wide), so the lab is also recovered for admissions
		-- that never had an ICU stay
		select combined.valuenum
		from (
			select c.valuenum, c.charttime
			from   mimiciv.chartevents c
			where  c.subject_id = Y.subject_id
			and    c.hadm_id    = Y.hadm_id
			and    c.stay_id    = Y.stay_id
			and    c.itemid     = 220615
			and    c.valuenum is not null
			union all
			select le.valuenum, le.charttime
			from   mimiciv.labevents le
			where  le.subject_id = Y.subject_id
			and    le.hadm_id    = Y.hadm_id
			and    le.itemid     = 50912
			and    le.valuenum is not null
		) combined
		order by combined.charttime asc
		limit 1
	) as creatine
	   , (
		-- earliest available value from EITHER chartevents (ICU-only) OR
		-- labevents (hospital-wide), so the lab is also recovered for admissions
		-- that never had an ICU stay
		select combined.valuenum
		from (
			select c.valuenum, c.charttime
			from   mimiciv.chartevents c
			where  c.subject_id = Y.subject_id
			and    c.hadm_id    = Y.hadm_id
			and    c.stay_id    = Y.stay_id
			and    c.itemid     = 220545
			and    c.valuenum is not null
			union all
			select le.valuenum, le.charttime
			from   mimiciv.labevents le
			where  le.subject_id = Y.subject_id
			and    le.hadm_id    = Y.hadm_id
			and    le.itemid     = 51221
			and    le.valuenum is not null
		) combined
		order by combined.charttime asc
		limit 1
	) as hematrocit
	   , (
		-- earliest available value from EITHER chartevents (ICU-only) OR
		-- labevents (hospital-wide), so the lab is also recovered for admissions
		-- that never had an ICU stay
		select combined.valuenum
		from (
			select c.valuenum, c.charttime
			from   mimiciv.chartevents c
			where  c.subject_id = Y.subject_id
			and    c.hadm_id    = Y.hadm_id
			and    c.stay_id    = Y.stay_id
			and    c.itemid     = 225668
			and    c.valuenum is not null
			union all
			select le.valuenum, le.charttime
			from   mimiciv.labevents le
			where  le.subject_id = Y.subject_id
			and    le.hadm_id    = Y.hadm_id
			and    le.itemid     = 50813
			and    le.valuenum is not null
		) combined
		order by combined.charttime asc
		limit 1
	) as lactic_acid
	   , (
		select max(c.valuenum)
		from   mimiciv.chartevents c
		where  c.subject_id = Y.subject_id
		and    c.hadm_id    = Y.hadm_id
		and    c.stay_id    = Y.stay_id
		and    c.itemid     = 220739
		and    c.valuenum is not null
		and    c.charttime = (
							 select min(c2.charttime)
							 from   mimiciv.chartevents c2
							 where  c2.subject_id = c.subject_id
							 and    c2.hadm_id    = c.hadm_id
							 and    c2.stay_id    = c.stay_id
							 and    c2.itemid     = 220739
							 and    c2.valuenum is not null
							)
	) as gcs_eye_opening
	   , (
		select max(c.valuenum)
		from   mimiciv.chartevents c
		where  c.subject_id = Y.subject_id
		and    c.hadm_id    = Y.hadm_id
		and    c.stay_id    = Y.stay_id
		and    c.itemid     = 223900
		and    c.valuenum is not null
		and    c.charttime = (
							 select min(c2.charttime)
							 from   mimiciv.chartevents c2
							 where  c2.subject_id = c.subject_id
							 and    c2.hadm_id    = c.hadm_id
							 and    c2.stay_id    = c.stay_id
							 and    c2.itemid     = 223900
							 and    c2.valuenum is not null
							)
	) as gcs_verbal_response
	   , (
		select max(c.valuenum)
		from   mimiciv.chartevents c
		where  c.subject_id = Y.subject_id
		and    c.hadm_id    = Y.hadm_id
		and    c.stay_id    = Y.stay_id
		and    c.itemid     = 223901
		and    c.valuenum is not null
		and    c.charttime = (
							 select min(c2.charttime)
							 from   mimiciv.chartevents c2
							 where  c2.subject_id = c.subject_id
							 and    c2.hadm_id    = c.hadm_id
							 and    c2.stay_id    = c.stay_id
							 and    c2.itemid     = 223901
							 and    c2.valuenum is not null
							)
	) as gcs_motor_response
	   , (
		select max(c.valuenum)
		from   mimiciv.chartevents c
		where  c.subject_id = Y.subject_id
		and    c.hadm_id    = Y.hadm_id
		and    c.stay_id    = Y.stay_id
		and    c.itemid     = 228096
		and    c.valuenum is not null
		and    c.charttime = (
							 select min(c2.charttime)
							 from   mimiciv.chartevents c2
							 where  c2.subject_id = c.subject_id
							 and    c2.hadm_id    = c.hadm_id
							 and    c2.stay_id    = c.stay_id
							 and    c2.itemid     = 228096
							 and    c2.valuenum is not null
							)
	) as richmond_ras_scale
	   , (
		select max(c.valuenum)
		from   mimiciv.chartevents c
		where  c.subject_id = Y.subject_id
		and    c.hadm_id    = Y.hadm_id
		and    c.stay_id    = Y.stay_id
		and    c.itemid     = 220339
		and    c.valuenum is not null
		and    c.charttime = (
							 select min(c2.charttime)
							 from   mimiciv.chartevents c2
							 where  c2.subject_id = c.subject_id
							 and    c2.hadm_id    = c.hadm_id
							 and    c2.stay_id    = c.stay_id
							 and    c2.itemid     = 220339
							 and    c2.valuenum is not null
							)
	) as peep_set
	   , (
		select max(c.valuenum)
		from   mimiciv.chartevents c
		where  c.subject_id = Y.subject_id
		and    c.hadm_id    = Y.hadm_id
		and    c.stay_id    = Y.stay_id
		and    c.itemid     = 226730
		and    c.valuenum is not null
		and    c.charttime = (
							 select min(c2.charttime)
							 from   mimiciv.chartevents c2
							 where  c2.subject_id = c.subject_id
							 and    c2.hadm_id    = c.hadm_id
							 and    c2.stay_id    = c.stay_id
							 and    c2.itemid     = 226730
							 and    c2.valuenum is not null
							)
	) as height
	   , (
		-- earliest available value from EITHER chartevents (ICU-only) OR
		-- labevents (hospital-wide), so the lab is also recovered for admissions
		-- that never had an ICU stay
		select combined.valuenum
		from (
			select c.valuenum, c.charttime
			from   mimiciv.chartevents c
			where  c.subject_id = Y.subject_id
			and    c.hadm_id    = Y.hadm_id
			and    c.stay_id    = Y.stay_id
			and    c.itemid     = 227073
			and    c.valuenum is not null
			union all
			select le.valuenum, le.charttime
			from   mimiciv.labevents le
			where  le.subject_id = Y.subject_id
			and    le.hadm_id    = Y.hadm_id
			and    le.itemid     = 50868
			and    le.valuenum is not null
		) combined
		order by combined.charttime asc
		limit 1
	) as anion_gap
	FROM mimiciv.cohort_maternal Y
) K;

ALTER TABLE mimiciv.cohort_maternal_dataset ADD CONSTRAINT pk_cm_dataset PRIMARY KEY (subject_id, hadm_id);

-- Diagnostic-group indicator columns gdg_m01-gdg_m28. They are populated by
-- maternal_diagnoses_group_assign.sql (function
-- mimiciv.update_feature_diagnoses_cohort_maternal_dataset()).
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m01 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m02 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m03 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m04 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m05 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m06 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m07 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m08 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m09 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m10 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m11 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m12 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m13 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m14 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m15 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m16 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m17 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m18 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m19 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m20 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m21 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m22 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m23 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m24 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m25 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m26 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m27 boolean;
ALTER TABLE mimiciv.cohort_maternal_dataset ADD COLUMN gdg_m28 boolean;
