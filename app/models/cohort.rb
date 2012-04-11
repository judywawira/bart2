class Cohort

  attr_accessor :start_date, :end_date

  @@first_registration_date = nil
  @@program_id = nil

  # Initialize class
  def initialize(start_date, end_date)
    @start_date = start_date #"#{start_date} 00:00:00"
    @end_date = "#{end_date} 23:59:59"

    @@first_registration_date = PatientProgram.find(
      :first,
      :conditions =>["program_id = ? AND voided = 0",1],
      :order => 'date_enrolled ASC'
    ).date_enrolled.to_date rescue nil

    @@program_id = Program.find_by_name('HIV PROGRAM').program_id
  end

  # Get patients reinitiated on art count
  def patients_reinitiated_on_art_ever
    Observation.find(:all, :joins => [:encounter], :conditions => ["concept_id = ? AND value_coded IN (?) AND encounter.voided = 0 \
        AND DATE_FORMAT(obs_datetime, '%Y-%m-%d') <= ?", ConceptName.find_by_name("EVER RECEIVED ART").concept_id,
        ConceptName.find(:all, :conditions => ["name = 'YES'"]).collect{|c| c.concept_id},
        @end_date.to_date.strftime("%Y-%m-%d")]).length rescue 0
  end

  def patients_reinitiated_on_arts
    Observation.find(:all, :joins => [:encounter], :conditions => ["concept_id = ? AND value_coded IN (?) AND encounter.voided = 0 \
        AND DATE_FORMAT(obs_datetime, '%Y-%m-%d') >= ? AND DATE_FORMAT(obs_datetime, '%Y-%m-%d') <= ?",
        ConceptName.find_by_name("EVER RECEIVED ART").concept_id,
        ConceptName.find(:all, :conditions => ["name = 'YES'"]).collect{|c| c.concept_id},
        @start_date.to_date.strftime("%Y-%m-%d"), @end_date.to_date.strftime("%Y-%m-%d")]).length rescue 0
  end

  def patients_reinitiated_on_arts_ids
    Observation.find(:all, :joins => [:encounter], :conditions => ["concept_id = ? AND value_coded IN (?) AND encounter.voided = 0 \
        AND DATE_FORMAT(obs_datetime, '%Y-%m-%d') >= ? AND DATE_FORMAT(obs_datetime, '%Y-%m-%d') <= ?",
        ConceptName.find_by_name("EVER RECEIVED ART").concept_id,
        ConceptName.find(:all, :conditions => ["name = 'YES'"]).collect{|c| c.concept_id},
        @start_date.to_date.strftime("%Y-%m-%d"), @end_date.to_date.strftime("%Y-%m-%d")]).map{|patient| patient.person_id}
  end

  def outcomes(start_date=@start_date, end_date=@end_date, outcome_end_date=@end_date, program_id = @@program_id, min_age=nil, max_age=nil,states = [])

    if min_age or max_age
      conditions = "AND TRUNCATE(DATEDIFF(p.date_enrolled, person.birthdate)/365,0) >= #{min_age}
                    AND TRUNCATE(DATEDIFF(p.date_enrolled, person.birthdate)/365,0) <= #{max_age}"
    end

    PatientState.find_by_sql("SELECT * FROM (
        SELECT s.patient_program_id, patient_id,patient_state_id,start_date,
               n.name name,state
        FROM patient_state s
        INNER JOIN patient_program p ON p.patient_program_id =
                                        s.patient_program_id
        INNER JOIN program_workflow pw ON pw.program_id = p.program_id
        INNER JOIN program_workflow_state w ON w.program_workflow_id =
                                               pw.program_workflow_id
                   AND w.program_workflow_state_id = s.state
        INNER JOIN concept_name n ON w.concept_id = n.concept_id
        INNER JOIN person ON person.person_id = p.patient_id
        WHERE p.voided = 0 AND s.voided = 0 #{conditions}
        AND (patient_start_date(patient_id) >= '#{start_date}'
        AND patient_start_date(patient_id) <= '#{end_date}')
        AND p.program_id = #{program_id}
        AND s.start_date <= '#{outcome_end_date}'
        ORDER BY patient_id DESC, patient_state_id DESC, start_date DESC
      ) K
      GROUP BY patient_id
      ORDER BY K.patient_state_id DESC , K.start_date DESC").map do |state|
        states << [state.patient_id , state.name]
      end
  end

  def total_registered(start_date = @start_date, end_date = @end_date)
    PatientProgram.find_by_sql("SELECT patient_id FROM patient_program p
                                INNER JOIN patient_state s USING (patient_program_id)
                                WHERE p.voided = 0 AND s.voided = 0 AND program_id = #{@@program_id}
                                AND patient_start_date(patient_id) >= '#{start_date}' AND patient_start_date(patient_id) <= '#{end_date}'
                                GROUP BY patient_id ORDER BY date_enrolled")#.length rescue 0

  end

  def transferred_in_patients(start_date = @start_date, end_date = @end_date)
    ever_received_concept_id = ConceptName.find_by_name("EVER RECEIVED ART").concept_id
    yes_concept_id = ConceptName.find_by_name("YES").concept_id

    PatientProgram.find_by_sql("SELECT p.patient_id FROM patient_program p
                                INNER JOIN patient_state s ON p.patient_program_id = s.patient_program_id
                                INNER JOIN obs ON obs.person_id = p.patient_id 
                                WHERE p.voided = 0
                                AND s.voided = 0
                                AND program_id = 1
                                AND obs.voided = 0
                                AND patient_start_date(p.patient_id) >= '#{start_date}'
                                AND patient_start_date(p.patient_id) <= '#{end_date}'
                                AND obs.concept_id = #{ever_received_concept_id}
                                AND value_coded = #{yes_concept_id}
                                GROUP BY patient_id") rescue 0
  end

  def total_registered_by_gender_age(start_date = @start_date, end_date = @end_date, sex = nil, min_age = nil, max_age = nil)
    yes_concept_id = ConceptName.find_by_name("YES").concept_id
    conditions = ''

    if min_age or max_age
      conditions = "AND TRUNCATE(DATEDIFF(date_enrolled, person.birthdate)/365,0) >= #{min_age}
                    AND TRUNCATE(DATEDIFF(date_enrolled, person.birthdate)/365,0) <= #{max_age}"
    end

    if sex
      conditions += " AND person.gender = '#{sex}'"
    end

    PatientProgram.find_by_sql("SELECT patient_id,program_id,count(*) FROM patient_program p
                                INNER JOIN patient_state s ON p.patient_program_id = s.patient_program_id
                                INNER JOIN obs ON obs.person_id = p.patient_id 
                                INNER JOIN person ON person.person_id = p.patient_id 
                                WHERE p.voided = 0
                                AND s.voided = 0
                                AND program_id = 1
                                AND obs.voided = 0
                                AND patient_start_date(p.patient_id) >= '#{start_date}'
                                AND patient_start_date(p.patient_id) <= '#{end_date}'
                                #{conditions} GROUP BY patient_id")
  end
  
  def pregnant_women(start_date = @start_date, end_date = @end_date)
    pregnant_concept_id = ConceptName.find_by_name("IS PATIENT PREGNANT?").concept_id
    pmtct_concept_id = ConceptName.find_by_name("REFERRED BY PMTCT").concept_id
    yes_concept_id = ConceptName.find_by_name("YES").concept_id

    PatientProgram.find_by_sql("SELECT patient_id,date_enrolled,obs.concept_id FROM obs 
                                INNER JOIN patient_program p ON p.patient_id = obs.person_id
                                INNER JOIN patient_state s ON p.patient_program_id = s.patient_program_id
                                INNER JOIN person ON person.person_id = p.patient_id
                                WHERE p.program_id = 1
                                AND gender ='F' 
                                AND patient_start_date(patient_id) >= '#{start_date}'
                                AND patient_start_date(patient_id) <= '#{end_date}' 
                                AND ((obs.concept_id = #{pregnant_concept_id}
                                AND obs.value_coded = #{yes_concept_id} )) 
                                AND (DATEDIFF(DATE(obs.obs_datetime), date_enrolled) >= 0) 
                                AND DATEDIFF(DATE(obs.obs_datetime),date_enrolled) <= 30
                                GROUP BY patient_id")
  end

  def non_pregnant_women(start_date = @start_date, end_date = @end_date)
    all_women =  self.total_registered_by_gender_age(start_date,end_date,'F').map{|patient| patient.patient_id}
    non_pregnant_women = (all_women - self.pregnant_women(start_date,end_date).map{|patient| patient.patient_id})
  end
  
  def first_registration_date
    @@first_registration_date
  end
  
  def report
    return {} if @@first_registration_date.blank?
    cohort_report = {}
    cohort_report['Total registrated'] = self.total_registered(@@first_registration_date).length
    cohort_report['Newly total registrated'] = self.total_registered.length
    cohort_report['Total transferred in patients'] = self.transferred_in_patients(@@first_registration_date).length
    cohort_report['Newly transferred in patients'] = self.transferred_in_patients.length

    cohort_report['Newly registrated male'] = self.total_registered_by_gender_age(@start_date,@end_date,'M').length
    cohort_report['Total registrated male'] = self.total_registered_by_gender_age(@@first_registration_date,@end_date,'M').length

    cohort_report['Newly registrated women (non-pregnant)'] = self.non_pregnant_women(@start_date,@end_date).length
    cohort_report['Total registrated women (non-pregnant)'] = self.non_pregnant_women(@@first_registration_date,@end_date).length

    cohort_report['Newly registrated women (pregnant)'] = self.pregnant_women(@start_date,@end_date).length
    cohort_report['Total registrated women (pregnant)'] = self.pregnant_women(@@first_registration_date,@end_date).length

    cohort_report['Newly registrated infants'] = self.total_registered_by_gender_age(@start_date,@end_date,nil,0,1.5).length
    cohort_report['Total registrated infants'] = self.total_registered_by_gender_age(@@first_registration_date,@end_date,nil,0,1.5).length

    cohort_report['Newly registrated children'] = self.total_registered_by_gender_age(@start_date,@end_date,nil,1.5,14).length
    cohort_report['Total registrated children'] = self.total_registered_by_gender_age(@@first_registration_date,@end_date,nil,1.5,14).length

    cohort_report['Newly registrated adults'] = self.total_registered_by_gender_age(@start_date,@end_date,nil,14,300).length
    cohort_report['Total registrated adults'] = self.total_registered_by_gender_age(@@first_registration_date,@end_date,nil,14,300).length

    cohort_report['Presumed severe HIV disease in infants'] = 0
    cohort_report['Confirmed HIV infection in infants (PCR)'] = 0
    cohort_report['WHO stage 1 or 2, CD4 below threshold'] = 0
    cohort_report['WHO stage 2, total lymphocytes'] = 0
    cohort_report['Unknown reason'] = 0
    cohort_report['WHO stage 3'] = 0
    cohort_report['WHO stage 4'] = 0
    cohort_report['Patient pregnant'] = 0
    cohort_report['Patient breastfeeding'] = 0
    cohort_report['HIV infected'] = 0

    ( self.start_reason || [] ).each do | reason | 
      if reason.name.match(/Presumed/i)
        cohort_report['Presumed severe HIV disease in infants'] += 1
      elsif reason.name.match(/Confirmed/i)
        cohort_report['Confirmed HIV infection in infants (PCR)'] += 1
      elsif reason.name[0..11].strip.upcase == 'WHO STAGE I' or reason.name.match(/CD/i)
        cohort_report['WHO stage 1 or 2, CD4 below threshold'] += 1
      elsif reason.name[0..12].strip.upcase == 'WHO STAGE II' or reason.name.match(/lymphocytes/i) or reason.name.match(/LYMPHOCYTE/i)
        cohort_report['WHO stage 2, total lymphocytes'] += 1
      elsif reason.name[0..13].strip.upcase == 'WHO STAGE III'
        cohort_report['WHO stage 3'] += 1
      elsif reason.name[0..11].strip.upcase == 'WHO STAGE IV'
        cohort_report['WHO stage 4'] += 1
      elsif reason.name.strip.humanize == 'Patient pregnant'
        cohort_report['Patient pregnant'] += 1
      elsif reason.name.match(/Breastfeeding/i)
        cohort_report['Patient breastfeeding'] += 1
      elsif reason.name.strip.upcase == 'HIV INFECTED'
        cohort_report['HIV infected'] += 1
      else 
        cohort_report['Unknown reason'] += 1
      end
    end
    
    cohort_report['Total Presumed severe HIV disease in infants'] = 0
    cohort_report['Total Confirmed HIV infection in infants (PCR)'] = 0
    cohort_report['Total WHO stage 1 or 2, CD4 below threshold'] = 0
    cohort_report['Total WHO stage 2, total lymphocytes'] = 0
    cohort_report['Total Unknown reason'] = 0
    cohort_report['Total WHO stage 3'] = 0
    cohort_report['Total WHO stage 4'] = 0
    cohort_report['Total Patient pregnant'] = 0
    cohort_report['Total Patient breastfeeding'] = 0
    cohort_report['Total HIV infected'] = 0

    ( self.start_reason(@@first_registration_date,@end_date) || [] ).each do | reason | 
      if reason.name.match(/Presumed/i)
        cohort_report['Total Presumed severe HIV disease in infants'] += 1
      elsif reason.name.match(/Confirmed/i)
        cohort_report['Total Confirmed HIV infection in infants (PCR)'] += 1
      elsif reason.name[0..11].strip.upcase == 'WHO STAGE I' or reason.name.match(/CD/i)
        cohort_report['Total WHO stage 1 or 2, CD4 below threshold'] += 1
      elsif reason.name[0..12].strip.upcase == 'WHO STAGE II' or reason.name.match(/lymphocytes/i) or reason.name.match(/LYMPHOCYTE/i)
        cohort_report['Total WHO stage 2, total lymphocytes'] += 1
      elsif reason.name[0..13].strip.upcase == 'WHO STAGE III'
        cohort_report['Total WHO stage 3'] += 1
      elsif reason.name[0..11].strip.upcase == 'WHO STAGE IV'
        cohort_report['Total WHO stage 4'] += 1
      elsif reason.name.strip.humanize == 'Patient pregnant'
        cohort_report['Total Patient pregnant'] += 1
      elsif reason.name.match(/Breastfeeding/i)
        cohort_report['Total Patient breastfeeding'] += 1
      elsif reason.name.strip.upcase == 'HIV INFECTED'
        cohort_report['Total HIV infected'] += 1
      else 
        cohort_report['Total Unknown reason'] += 1
      end
    end

    cohort_report['TB within the last 2 years'] = self.tb_within_the_last_2_yrs.length
    cohort_report['Total TB within the last 2 years'] = self.tb_within_the_last_2_yrs(@@first_registration_date,@end_date).length

    cohort_report['Current episode of TB'] = self.current_espisode_of_tb.length
    cohort_report['Total Current episode of TB'] = self.current_espisode_of_tb(@@first_registration_date,@end_date).length

    cohort_report['Kaposis Sarcoma'] = self.kaposis_sarcoma.length
    cohort_report['Total Kaposis Sarcoma'] = self.kaposis_sarcoma(@@first_registration_date,@end_date).length

    cohort_report['No TB'] = (cohort_report['Newly total registrated'] - (cohort_report['Current episode of TB'] + cohort_report['TB within the last 2 years']))
    cohort_report['Total No TB'] = (cohort_report['Total registrated'] - (cohort_report['Total Current episode of TB'] + cohort_report['Total TB within the last 2 years']))

    cohort_report['Total alive and on ART'] = self.total_alive_and_on_art.length
    cohort_report['Died total'] = self.total_number_of_dead_patients

    death_dates_array = self.death_dates(@@first_registration_date,@start_date)
    cohort_report['Died within the 1st month after ART initiation'] = death_dates_array[0].length
    cohort_report['Died within the 2nd month after ART initiation'] = death_dates_array[1].length
    cohort_report['Died within the 3rd month after ART initiation'] = death_dates_array[2].length
    cohort_report['Died after the end of the 3rd month after ART initiation'] = death_dates_array[3].length
    
    death_dates_array = self.death_dates(@@first_registration_date,@end_date)
    cohort_report['Total Died within the 1st month after ART initiation'] = death_dates_array[0].length
    cohort_report['Total Died within the 2nd month after ART initiation'] = death_dates_array[1].length
    cohort_report['Total Died within the 3rd month after ART initiation'] = death_dates_array[2].length
    cohort_report['Total Died after the end of the 3rd month after ART initiation'] = death_dates_array[3].length

    cohort_report['Transferred out'] = self.transferred_out_patients
    cohort_report['Stopped taking ARVs'] = self.art_stopped_patients
    cohort_report['Defaulted'] = self.art_defaulted_patients

    tb_status_outcomes = self.tb_status
    cohort_report['TB suspected'] = tb_status_outcomes['TB STATUS']['Suspected']
    cohort_report['TB not suspected'] = tb_status_outcomes['TB STATUS']['Not Suspected']
    cohort_report['TB confirmed not treatment'] = tb_status_outcomes['TB STATUS']['Not on treatment']
    cohort_report['TB confirmed on treatment'] = tb_status_outcomes['TB STATUS']['On Treatment']
    cohort_report['TB Unknown'] = tb_status_outcomes['TB STATUS']['Unknown']

    cohort_report['Regimens'] = self.regimens(@@first_registration_date)
    cohort_report['Patients reinitiated on ART'] = self.patients_reinitiated_on_art.length
    cohort_report['Total Patients reinitiated on ART'] = self.patients_reinitiated_on_art(@@first_registration_date).length
  
    cohort_report['Patients initiated on ART'] = self.patients_initiated_on_art_first_time.length
    cohort_report['Total Patients initiated on ART'] = self.patients_initiated_on_art_first_time(@@first_registration_date).length
   
    cohort_report
  end

  def regimens(start_date = @start_date, end_date = @end_date)
    regimens = []
    regimen_hash = {}
#(birthdate varchar(10),visit_date varchar(10),date_created varchar(10),est int)
    regimem_given_concept = ConceptName.find_by_name('ARV REGIMENS RECEIVED ABSTRACTED CONSTRUCT')
    PatientProgram.find_by_sql("SELECT patient_id , value_coded regimen_id, value_text regimen ,
                                age(LEFT(person.birthdate,10),LEFT(obs.obs_datetime,10),
                                LEFT(person.date_created,10),person.birthdate_estimated) person_age_at_drug_dispension  
                                FROM obs 
                                INNER JOIN patient_program p ON p.patient_id = obs.person_id
                                INNER JOIN patient_state s ON p.patient_program_id = s.patient_program_id
                                INNER JOIN person ON person.person_id = p.patient_id
                                WHERE p.program_id = #{@@program_id} AND obs.concept_id = #{regimem_given_concept.concept_id}
                                AND patient_start_date(patient_id) >= '#{start_date}' AND patient_start_date(patient_id) <= '#{end_date}' 
                                GROUP BY patient_id 
                                ORDER BY obs.obs_datetime DESC").each do | value | 
                                  regimens << [value.regimen_id, 
                                               value.regimen,
                                               value.person_age_at_drug_dispension
                                              ]
                                end
    ( regimens || [] ).each do | regimen_id, regimen , patient_age |
      age = patient_age.to_i 
      regimen_name = ConceptName.find_by_concept_id(regimen_id).concept.shortname rescue nil
      if regimen_name.blank?
        regimen_name = ConceptName.find_by_concept_id(regimen_id).concept.fullname 
      end

      regimen_name = cohort_regimen_name(regimen_name,age)

      if regimen_hash[regimen_name].blank?
        regimen_hash[regimen_name] = 0
      end
      regimen_hash[regimen_name]+=1
    end
    regimen_hash
  end
  
  def regimens_with_patient_ids(start_date = @start_date, end_date = @end_date)
    regimens = []
    regimen_hash = {}
#(birthdate varchar(10),visit_date varchar(10),date_created varchar(10),est int)
    regimem_given_concept = ConceptName.find_by_name('ARV REGIMENS RECEIVED ABSTRACTED CONSTRUCT')
    PatientProgram.find_by_sql("SELECT patient_id , value_coded regimen_id, value_text regimen ,
                                age(LEFT(person.birthdate,10),LEFT(obs.obs_datetime,10),
                                LEFT(person.date_created,10),person.birthdate_estimated) person_age_at_drug_dispension  
                                FROM obs 
                                INNER JOIN patient_program p ON p.patient_id = obs.person_id
                                INNER JOIN patient_state s ON p.patient_program_id = s.patient_program_id
                                INNER JOIN person ON person.person_id = p.patient_id
                                WHERE p.program_id = #{@@program_id} AND obs.concept_id = #{regimem_given_concept.concept_id}
                                AND patient_start_date(patient_id) >= '#{start_date}' AND patient_start_date(patient_id) <= '#{end_date}' 
                                GROUP BY patient_id 
                                ORDER BY obs.obs_datetime DESC").each do | value | 
                                  regimens << [value.regimen_id, 
                                               value.regimen,
                                               value.person_age_at_drug_dispension
                                              ]
                                end
  end

  def patients_reinitiated_on_art(start_date = @start_date, end_date = @end_date)
    patients = []
    no_concept = ConceptName.find_by_name('NO').concept_id
    date_art_last_taken_concept = ConceptName.find_by_name('DATE ART LAST TAKEN').concept_id

    taken_arvs_concept = ConceptName.find_by_name('HAS THE PATIENT TAKEN ART IN THE LAST TWO MONTHS').concept_id
    PatientProgram.find_by_sql("SELECT 
                                patient_id , value_datetime date_art_last_taken,obs_datetime visit_date,value_coded,obs.concept_id concept_id  
                                FROM obs 
                                INNER JOIN patient_program p ON p.patient_id = obs.person_id
                                INNER JOIN patient_state s ON p.patient_program_id = s.patient_program_id
                                WHERE p.program_id = #{@@program_id} 
                                AND (obs.concept_id = #{date_art_last_taken_concept}
                                OR obs.concept_id = #{taken_arvs_concept})
                                AND patient_start_date(patient_id) >= '#{start_date}'
                                AND patient_start_date(patient_id) <= '#{end_date}'
                                GROUP BY patient_id
                                ORDER BY obs.obs_datetime DESC").map do | ob |
                                  if ob.concept_id.to_s == date_art_last_taken_concept.to_s

                                    unless 4 >= ((ob.visit_date.to_date -
                                                  (ob.date_art_last_taken.to_date rescue ob.visit_date.to_date)) / 7).to_i
                                      patients << ob.patient_id
                                    end
                                  else
                                    patients << ob.patient_id if ob.value_coded.to_s == no_concept.to_s
                                  end
                                end
    patients
  end

  def patients_initiated_on_art_first_time(start_date = @start_date, end_date = @end_date)
    yes_concept = ConceptName.find_by_name('YES')
    ever_received_concept_id = ConceptName.find_by_name("EVER RECEIVED ART").concept_id
    PatientProgram.find_by_sql("SELECT 
                                patient_id ,obs_datetime visit_date,value_coded,obs.concept_id concept_id  
                                FROM obs 
                                INNER JOIN patient_program p ON p.patient_id = obs.person_id
                                INNER JOIN patient_state s ON p.patient_program_id = s.patient_program_id
                                WHERE p.program_id = #{@@program_id} AND obs.value_coded <> #{yes_concept.concept_id}
                                AND obs.concept_id = #{ever_received_concept_id}
                                AND patient_start_date(patient_id) >= '#{start_date}' AND patient_start_date(patient_id) <= '#{end_date}' 
                                GROUP BY patient_id 
                                ORDER BY obs.obs_datetime DESC") rescue 0
  end

  def death_dates(start_date = @start_date, end_date = @end_date)
    start_date_death_date = [] 
    first_month = [] ; second_month = [] ; third_month = [] ; after_third_month = []
    first_month_date = [start_date.to_date,(start_date.to_date + 1.month)]
    second_month_date = [first_month_date[1],first_month_date[1] + 1.month]
    third_month_date = [second_month_date[1],second_month_date[1] + 1.month]

    ( self.died_total || [] ).each do | state |
      if (state.date_enrolled.to_datetime >= first_month_date[0]  and state.date_enrolled.to_datetime <= first_month_date[1] )
          first_month << state
      elsif (state.date_enrolled.to_datetime >= second_month_date[0]  and state.date_enrolled.to_datetime <= second_month_date[1] )
          second_month << state
      elsif (state.date_enrolled.to_datetime >= third_month_date[0]  and state.date_enrolled.to_datetime <= third_month_date[1] )
          third_month << state
      elsif (state.date_enrolled.to_datetime > third_month_date[1])
          after_third_month << state
      end
    end

    [first_month, second_month, third_month, after_third_month]
  end

  def total_outcomes(outcome_name = 'PATIENT DIED')
    start_date_death_date = []
    PatientState.find_by_sql("SELECT * FROM (
        SELECT s.patient_program_id, patient_id,patient_state_id,start_date,
               n.name name,state,p.date_enrolled date_enrolled
        FROM patient_state s
        INNER JOIN patient_program p ON p.patient_program_id =
                                        s.patient_program_id
        INNER JOIN program_workflow pw ON pw.program_id = p.program_id
        INNER JOIN program_workflow_state w ON w.program_workflow_id =
                                               pw.program_workflow_id
                   AND w.program_workflow_state_id = s.state
        INNER JOIN concept_name n ON w.concept_id = n.concept_id
        WHERE p.voided = 0 AND s.voided = 0
        AND (patient_start_date(patient_id) >= '#{@@first_registration_date}'
        AND patient_start_date(patient_id) <= '#{@end_date}')
        AND p.program_id = #{@@program_id}
        ORDER BY patient_state_id DESC,
        start_date DESC
      ) K
      GROUP BY K.patient_program_id HAVING (name = '#{outcome_name}')
      ORDER BY K.patient_state_id , K.start_date").map do |state|
        start_date_death_date << [state.date_enrolled , state.start_date]
      end
    start_date_death_date
  end

  def art_defaulted_patients
    self.outcomes_total('DEFAULTED').length
  end

  def art_stopped_patients
    self.outcomes_total('TREATMENT STOPPED').length
  end

  def transferred_out_patients
    self.outcomes_total('PATIENT TRANSFERRED OUT').length
  end

  def died_total
    self.outcomes_total('PATIENT DIED')
  end
  
  def total_number_of_dead_patients
    self.outcomes_total('PATIENT DIED').length
  end

  def total_alive_and_on_art
    on_art_concept_name = ConceptName.find_all_by_name('On antiretrovirals')
    state = ProgramWorkflowState.find(
      :first,
      :conditions => ["concept_id IN (?)",
                      on_art_concept_name.map{|c|c.concept_id}]
    ).program_workflow_state_id

    PatientState.find_by_sql("SELECT * FROM (
        SELECT s.patient_program_id, patient_id,patient_state_id,start_date,
               n.name name,state
        FROM patient_state s
        INNER JOIN patient_program p ON p.patient_program_id =
                                        s.patient_program_id
        INNER JOIN program_workflow pw ON pw.program_id = p.program_id
        INNER JOIN program_workflow_state w ON w.program_workflow_id =
                                               pw.program_workflow_id
        AND w.program_workflow_state_id = s.state
        INNER JOIN concept_name n ON w.concept_id = n.concept_id
        WHERE p.voided = 0 AND s.voided = 0
        AND (patient_start_date(patient_id) >= '#{@@first_registration_date}'
        AND patient_start_date(patient_id) <= '#{@end_date}')
        AND p.program_id = #{@@program_id}
        ORDER BY patient_state_id DESC, start_date DESC
      ) K
      GROUP BY K.patient_id HAVING (state = #{state})
      ORDER BY K.patient_state_id DESC, K.start_date DESC")
  end
  
  def outcomes_total(outcome)
    on_art_concept_name = ConceptName.find_all_by_name(outcome)
    state = ProgramWorkflowState.find(
      :first,
      :conditions => ["concept_id IN (?)",
                      on_art_concept_name.map{|c|c.concept_id}]
    ).program_workflow_state_id

    PatientState.find_by_sql("SELECT * FROM (
        SELECT s.patient_program_id, patient_id,patient_state_id,start_date,
               n.name name,state,p.date_enrolled date_enrolled
        FROM patient_state s
        INNER JOIN patient_program p ON p.patient_program_id =
                                        s.patient_program_id
        INNER JOIN program_workflow pw ON pw.program_id = p.program_id
        INNER JOIN program_workflow_state w ON w.program_workflow_id =
                                               pw.program_workflow_id
        AND w.program_workflow_state_id = s.state
        INNER JOIN concept_name n ON w.concept_id = n.concept_id
        WHERE p.voided = 0 AND s.voided = 0
        AND (patient_start_date(patient_id) >= '#{@@first_registration_date}'
        AND patient_start_date(patient_id) <= '#{@end_date}')
        AND p.program_id = #{@@program_id}
        ORDER BY patient_state_id DESC, start_date DESC
      ) K
      GROUP BY K.patient_id HAVING (state = #{state})
      ORDER BY K.patient_state_id DESC, K.start_date DESC")
  end


  def tb_within_the_last_2_yrs(start_date = @start_date, end_date = @end_date)
    tb_concept_id = ConceptName.find_by_name("PULMONARY TUBERCULOSIS WITHIN THE LAST 2 YEARS").concept_id
    self.patients_with_start_cause(start_date,end_date,tb_concept_id)
  end

  def patients_with_start_cause(start_date = @start_date,end_date = @end_date, tb_concept_id = nil)
    return if tb_concept_id.blank?
    cause_concept_id = ConceptName.find_by_name("WHO STG CRIT").concept_id

    PatientProgram.find_by_sql("SELECT patient_id,name,date_enrolled FROM obs
                                INNER JOIN patient_program p ON p.patient_id = obs.person_id
                                INNER JOIN patient_state s ON p.patient_program_id = s.patient_program_id
                                INNER JOIN concept_name n ON n.concept_id = obs.value_coded
                                WHERE patient_start_date(patient_id) >='#{start_date}' AND patient_start_date(patient_id) <= '#{end_date}' 
                                AND obs.concept_id = #{cause_concept_id} AND p.program_id = #{@@program_id}
                                AND obs.value_coded = #{tb_concept_id} GROUP BY patient_id")#.length
  end

  def kaposis_sarcoma(start_date = @start_date, end_date = @end_date)
    tb_concept_id = ConceptName.find_by_name("KAPOSIS SARCOMA").concept_id
    self.patients_with_start_cause(start_date,end_date,tb_concept_id)
  end

  def current_espisode_of_tb(start_date = @start_date, end_date = @end_date)
    tb_concept_id = ConceptName.find_by_name("EXTRAPULMONARY TUBERCULOSIS (EPTB)").concept_id
    self.patients_with_start_cause(start_date,end_date,tb_concept_id)
  end

  def start_reason(start_date = @start_date, end_date = @end_date)
    start_reason_hash = Hash.new(0)
    reason_concept_id = ConceptName.find_by_name("REASON FOR ART ELIGIBILITY").concept_id

    PatientProgram.find_by_sql("SELECT patient_id,name,date_enrolled FROM obs
                                INNER JOIN patient_program p ON p.patient_id = obs.person_id
                                INNER JOIN patient_state s ON p.patient_program_id = s.patient_program_id
                                INNER JOIN concept_name n ON n.concept_id = obs.value_coded
                                WHERE patient_start_date(patient_id) >='#{start_date}'
                                AND patient_start_date(patient_id) <= '#{end_date}' 
                                AND obs.concept_id = #{reason_concept_id}
                                AND p.program_id = #{@@program_id}
                                AND n.name != ''
                                GROUP BY patient_id")
  end

  def tb_status
    tb_status_hash = {} ; status = []
    tb_status_hash['TB STATUS'] = {'Unknown' => 0,'Suspected' => 0,'Not Suspected' => 0,'On Treatment' => 0,'Not on treatment' => 0} 
    tb_status_concept_id = ConceptName.find_by_name('TB STATUS').concept_id
    hiv_clinic_consultation_encounter_id = EncounterType.find_by_name('HIV CLINIC CONSULTATION').id

    status = PatientState.find_by_sql("SELECT * FROM (
                          SELECT e.patient_id,n.name tbstatus,obs_datetime,e.encounter_datetime,s.state
                          FROM patient_state s
                          INNER JOIN patient_program p ON p.patient_program_id = s.patient_program_id   
                          INNER JOIN encounter e ON e.patient_id = p.patient_id
                          INNER JOIN obs ON obs.encounter_id = e.encounter_id
                          INNER JOIN concept_name n ON obs.value_coded = n.concept_id
                          WHERE p.voided = 0
                          AND s.voided = 0
                          AND obs.obs_datetime = e.encounter_datetime
                          AND (patient_start_date(e.patient_id) >= '#{@@first_registration_date}'
                          AND patient_start_date(e.patient_id) <= '#{@end_date}')
                          AND obs.concept_id = #{tb_status_concept_id}
                          AND e.encounter_type = #{hiv_clinic_consultation_encounter_id}
                          AND p.program_id = #{@@program_id}
                          ORDER BY e.encounter_datetime DESC, patient_state_id DESC , start_date DESC) K
                          GROUP BY K.patient_id
                          ORDER BY K.encounter_datetime DESC , K.obs_datetime DESC").map(&:tbstatus)

    ( status || [] ).each do | state |
      if state == 'TB NOT SUSPECTED' or state == 'noSusp' or state == 'noSup' or state == 'TB not suspected' or state == 'TB NOT suspected' or state == 'Nosup'
        tb_status_hash['TB STATUS']['Not Suspected'] += 1
      elsif state == 'TB SUSPECTED' or state == 'susp' or state == 'sup' or state == 'TB suspected' or state == 'Tb suspected'
        tb_status_hash['TB STATUS']['Suspected'] += 1
      elsif state == 'RX' or state == 'CONFIRMED TB ON TREATMENT' or state == 'Rx' or state == 'CONFIRMED TB ON TREATMENT' or state == 'Confirmed TB on treatment' or state == 'Confirmed TB on treatment' or state == 'Norx'
        tb_status_hash['TB STATUS']['On Treatment'] += 1
      elsif state == 'noRX' or state == 'CONFIRMED TB NOT ON TREATMENT' or state =='Confirmed TB not on treatment' or state == 'Confirmed TB NOT on treatment'
        tb_status_hash['TB STATUS']['Not on treatment'] += 1
      else
        tb_status_hash['TB STATUS']['Unknown'] += 1
      end
    end
    tb_status_hash
  end
  
  def tb_status_with_patient_ids
    tb_status_hash = {} ; status = []
    tb_status_hash['TB STATUS'] = {'Unknown' => 0,'Suspected' => 0,'Not Suspected' => 0,'On Treatment' => 0,'Not on treatment' => 0} 
    tb_status_concept_id = ConceptName.find_by_name('TB STATUS').concept_id
    hiv_clinic_consultation_encounter_id = EncounterType.find_by_name('HIV CLINIC CONSULTATION').id

    status = PatientState.find_by_sql("SELECT * FROM (
                          SELECT e.patient_id,n.name tbstatus,obs_datetime,e.encounter_datetime,s.state
                          FROM patient_state s
                          INNER JOIN patient_program p ON p.patient_program_id = s.patient_program_id   
                          INNER JOIN encounter e ON e.patient_id = p.patient_id
                          INNER JOIN obs ON obs.encounter_id = e.encounter_id
                          INNER JOIN concept_name n ON obs.value_coded = n.concept_id
                          WHERE p.voided = 0
                          AND s.voided = 0
                          AND obs.obs_datetime = e.encounter_datetime
                          AND (patient_start_date(e.patient_id) >= '#{@@first_registration_date}'
                          AND patient_start_date(e.patient_id) <= '#{@end_date}')
                          AND obs.concept_id = #{tb_status_concept_id}
                          AND e.encounter_type = #{hiv_clinic_consultation_encounter_id}
                          AND p.program_id = #{@@program_id}
                          ORDER BY e.encounter_datetime DESC, patient_state_id DESC , start_date DESC) K
                          GROUP BY K.patient_id
                          ORDER BY K.encounter_datetime DESC , K.obs_datetime DESC")
  end

  def side_effect_patients(start_date = @start_date, end_date = @end_date)
    side_effect_concept_ids =[ConceptName.find_by_name('PERIPHERAL NEUROPATHY').concept_id,
                              ConceptName.find_by_name('HEPATITIS').concept_id,
                              ConceptName.find_by_name('SKIN RASH').concept_id,
                              ConceptName.find_by_name('JAUNDICE').concept_id]

    encounter_type = EncounterType.find_by_name('HIV CLINIC CONSULTATION')
    concept_id = ConceptName.find_by_name('SYMPTOM PRESENT').concept_id

    encounter_ids = Encounter.find(:all,:conditions => ["encounter_type = ? 
                    AND (patient_start_date(patient_id) >= '#{start_date}'
                    AND patient_start_date(patient_id) <= '#{end_date}')
                    AND (encounter_datetime >= '#{start_date}'
                    AND encounter_datetime <= '#{end_date}')",
                    encounter_type.id],:group => 'patient_id',:order => 'encounter_datetime DESC').map{| e | e.encounter_id }

    Observation.find(:all,
                     :conditions => ["encounter_id IN (#{encounter_ids.join(',')})
                     AND concept_id = ? 
                     AND value_coded IN (#{side_effect_concept_ids.join(',')})",concept_id],
                     :group =>'person_id').length
  end

  private

  def cohort_regimen_name(name , age)
    case name
      when 'd4T/3TC/NVP'
        return 'A1' if age > 14
        return 'P1'
      when 'd4T/3TC + d4T/3TC/NVP (Starter pack)'
        return 'A1' if age > 14
        return 'P1'
      when 'AZT/3TC/NVP'
        return 'A2' if age > 14
        return 'P2'
      when 'AZT/3TC + AZT/3TC/NVP (Starter pack)'
        return 'A2' if age > 14
        return 'P2'
      when 'd4T/3TC/EFV'
        return 'A3' if age > 14
        return 'P3'
      when 'AZT/3TC+EFV'
        return 'A4' if age > 14
        return 'P4'
      when 'TDF/3TC/EFV'
        return 'A5' if age > 14
        return 'P5'
      when 'TDF/3TC+NVP'
        return 'A6' if age > 14
        return 'P6'
      when 'TDF/3TC+LPV/r'
        return 'A7' if age > 14
        return 'P7'
      when 'AZT/3TC+LPV/r'
        return 'A8' if age > 14
        return 'P8'
      when 'ABC/3TC+LPV/r'
        return 'A9' if age > 14
        return 'P9'
      else
        return 'UNKNOWN ANTIRETROVIRAL DRUG'
    end
  end
end
