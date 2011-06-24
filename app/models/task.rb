class Task < ActiveRecord::Base
  set_table_name :task
  set_primary_key :task_id
  include Openmrs

  # Try to find the next task for the patient at the given location
  def self.next_task(location, patient, session_date = Date.today)
    referred_by_tb_index = PersonAttribute.find(:first, :conditions => ["person_id =? and person_attribute_type_id =?",patient.id,PersonAttributeType.find(:first, :conditions => ["name = ?","Source of referral"]).id])

    todays_encounters = patient.encounters.find_by_date(session_date)
    todays_encounter_types = todays_encounters.map{|e| e.type.name rescue ''}.uniq rescue []
    

    return "/people/new_tb_index_person?patient_id=#{patient.id}" unless referred_by_tb_index
    return "/encounters/new/update_hiv_status?patient_id=#{patient.id}" unless todays_encounter_types.include?("UPDATE HIV STATUS")
    return "/encounters/new/lab_order?patient_id=#{patient.id}" unless todays_encounter_types.include?("LAB ORDERS")
=begin
    all_tasks = self.all(:order => 'sort_weight ASC')
    todays_encounters = patient.encounters.find_by_date(session_date)
    todays_encounter_types = todays_encounters.map{|e| e.type.name rescue ''}.uniq rescue []
    all_tasks.each do |task|

      # Is the task for this location?
      next unless task.location.blank? || task.location == '*' || location.name.match(/#{task.location}/)
      next if task.description == 'If a patient/guardian has skipped a station'

      # Have we already run this task?
      next if task.encounter_type.present? && todays_encounter_types.include?(task.encounter_type)

      # By default, we don't want to skip this task
      skip = false
 
      # Skip this task if this is a gender specific task and the gender does not match?
      # For example, if this is a female specific check and the patient is not female, we want to skip it
      skip = true if task.gender.present? && patient.person.gender != task.gender

      # Check for an observation made today with a specific value, skip this task unless that observation exists
      # For example, if this task is the art_clinician task we want to skip it unless REFER TO CLINICIAN = yes
      if task.has_obs_concept_id.present?
        if (task.has_obs_scope.blank? || task.has_obs_scope == 'TODAY')
          obs = Observation.first(:conditions => [
          'encounter_id IN (?) AND concept_id = ? AND (value_coded = ? OR value_drug = ? OR value_datetime = ? OR value_numeric = ? OR value_text = ?)',
          todays_encounters.map(&:encounter_id),
          task.has_obs_concept_id,
          task.has_obs_value_coded,
          task.has_obs_value_drug,
          task.has_obs_value_datetime,
          task.has_obs_value_numeric,
          task.has_obs_value_text])
        end
        
        # Only the most recent obs
        # For example, if there are mutliple REFER TO CLINICIAN = yes, than only take the most recent one
        if (task.has_obs_scope == 'RECENT')
          o = patient.person.observations.recent(1).first(:conditions => ['encounter_id IN (?) AND concept_id =?', todays_encounters.map(&:encounter_id), task.has_obs_concept_id])
          obs = 0 if (o.value_coded == task.has_obs_value_coded && o.value_drug == task.has_obs_value_drug &&
            o.value_datetime == task.has_obs_value_datetime && o.value_numeric == task.has_obs_value_numeric &&
            o.value_text == task.has_obs_value_text )
        end
          
        skip = true unless obs.present?
      end

      # Check for a particular current order type, skip this task unless the order exists
      # For example, if this task is /dispensation/new we want to skip it if there is not already a drug order
      if task.has_order_type_id.present?
        skip = true unless Order.unfinished.first(:conditions => {:order_type_id => task.has_order_type_id}).present?
      end

      # Check for a particular program at this location, skip this task if the patient is not in the required program
      # For example if this is the hiv_reception task, we want to skip it if the patient is not currently in the HIV PROGRAM
      if task.has_program_id.present? && (task.has_program_workflow_state_id.blank? || task.has_program_workflow_state_id == '*')
        patient_program = PatientProgram.current.first(:conditions => [
          'patient_program.patient_id = ? AND patient_program.location_id = ? AND patient_program.program_id = ?',
          patient.patient_id,
          Location.current_health_center.location_id,
          task.has_program_id])        
        skip = true unless patient_program.present?
      end

      # Check for a particular program state at this location, skip this task if the patient does not have the required program/state
      # For example if this is the art_followup task, we want to skip it if the patient is not currently in the HIV PROGRAM with the state FOLLOWING
      if task.has_program_id.present? && task.has_program_workflow_state_id.present?
        patient_state = PatientState.current.first(:conditions => [
          'patient_program.patient_id = ? AND patient_program.location_id = ? AND patient_program.program_id = ? AND patient_state.state = ?',
          patient.patient_id,
          Location.current_health_center.location_id,
          task.has_program_id,
          task.has_program_workflow_state_id], :include => :patient_program)        
        skip = true unless patient_state.present?
      end
      
      # Check for a particular relationship, skip this task if the patient does not have the relationship
      # For example, if there is a CHW training update, skip this task if the person is not a CHW
      if task.has_relationship_type_id.present?        
        skip = true unless patient.relationships.first(
          :conditions => ['relationship.relationship = ?', task.has_relationship_type_id])
      end
 
      # Check for a particular identifier at this location
      # For example, this patient can only get to the Pre-ART room if they already have a pre-ART number, otherwise they need to go back to registration
      if task.has_identifier_type_id.present?
        skip = true unless patient.patient_identifiers.first(
          :conditions => ['patient_identifier.identifier_type = ? AND patient_identifier.location_id = ?', task.has_identifier_type_id, Location.current_health_center.location_id])
      end
      
      if task.has_encounter_type_today.present?
        enc = nil
        todays_encounters.each do | e |
          if (e.name == task.has_encounter_type_today)
            enc = e
          end
        end
        skip = true unless enc.present?
      end
      
      # Reverse the condition if the task wants the negative (for example, if the patient doesn't have a specific program yet, then run this task)
      skip = !skip if task.skip_if_has == 1

      # We need to skip this task for some reason
      next if skip
      
      if location.name.match(/HIV|ART/i)
       task = self.validate_task(patient,task,session_date.to_date)
      end

      # Nothing failed, this is the next task, lets replace any macros
      task.url = task.url.gsub(/\{patient\}/, "#{patient.patient_id}")
      task.url = task.url.gsub(/\{person\}/, "#{patient.person.person_id rescue nil}")
      task.url = task.url.gsub(/\{location\}/, "#{location.location_id}")

      logger.debug "next_task: #{task.id} - #{task.description}"
      
      return task
    end
=end
  
  end

  
  def self.validate_task(patient,task,session_date = Date.today)
    #return task unless task.has_program_id == 1
    return task if task.encounter_type == 'REGISTRATION'
    art_encounters = ['ART_INITIAL','HIV RECEPTION','VITALS','HIV STAGING','ART VISIT','ART ADHERENCE','TREATMENT','DISPENSING']

    if patient.encounters.find_by_encounter_type(EncounterType.find_by_name(art_encounters[0]).id).blank? and task.encounter_type != art_encounters[0]
      t = Task.find_by_description("If a patient/guardian has skipped a station")
      t.url = t.url.gsub(/\{encounter_type\}/, "#{art_encounters[0].gsub(' ','_')}") 
      return t
    elsif patient.encounters.find_by_encounter_type(EncounterType.find_by_name(art_encounters[0]).id).blank? and task.encounter_type == art_encounters[0]
      return task
    end
    
    hiv_reception = Encounter.find(:first,
                                   :conditions =>["patient_id = ? AND encounter_type = ? AND DATE(encounter_datetime) = ?",
                                   patient.id,EncounterType.find_by_name(art_encounters[1]).id,session_date],
                                   :order =>'encounter_datetime DESC')

    if hiv_reception.blank? and task.encounter_type != art_encounters[1]
      t = Task.find_by_description("If a patient/guardian has skipped a station")
      t.url = t.url.gsub(/\{encounter_type\}/, "#{art_encounters[1].gsub(' ','_')}") 
      return t
    elsif hiv_reception.blank? and task.encounter_type == art_encounters[1]
      return task
    end

    vitals = Encounter.find(:first,
                            :conditions =>["patient_id = ? AND encounter_type = ? AND DATE(encounter_datetime) = ?",
                            patient.id,EncounterType.find_by_name(art_encounters[2]).id,session_date],
                            :order =>'encounter_datetime DESC')

    if vitals.blank? and task.encounter_type != art_encounters[2]
      t = Task.find_by_description("If a patient/guardian has skipped a station")
      t.url = t.url.gsub(/\{encounter_type\}/, "#{art_encounters[2].gsub(' ','_')}") 
      return t
    elsif vitals.blank? and task.encounter_type == art_encounters[2]
      return task
    end

    if patient.encounters.find_by_encounter_type(EncounterType.find_by_name(art_encounters[3]).id).blank? and task.encounter_type != art_encounters[3]
      t = Task.find_by_description("If a patient/guardian has skipped a station")
      t.url = t.url.gsub(/\{encounter_type\}/, "#{art_encounters[3].gsub(' ','_')}") 
      return t
    elsif patient.encounters.find_by_encounter_type(EncounterType.find_by_name(art_encounters[3]).id).blank? and task.encounter_type == art_encounters[3]
      return task
    end

    art_visit = Encounter.find(:first,
                                   :conditions =>["patient_id = ? AND encounter_type = ? AND DATE(encounter_datetime) = ?",
                                   patient.id,EncounterType.find_by_name(art_encounters[4]).id,session_date],
                                   :order =>'encounter_datetime DESC',:limit => 1)

    if art_visit.blank? and task.encounter_type != art_encounters[4]
      t = Task.find_by_description("If a patient/guardian has skipped a station")
      t.url = t.url.gsub(/\{encounter_type\}/, "#{art_encounters[4].gsub(' ','_')}") 
      return t
    elsif art_visit.blank? and task.encounter_type == art_encounters[4]
      return task
    end
=begin
    art_adherance = Encounter.find(:first,
                                   :conditions =>["patient_id = ? AND encounter_type = ? AND DATE(encounter_datetime) = ?",
                                   patient.id,EncounterType.find_by_name(art_encounters[5]).id,session_date],
                                   :order =>'encounter_datetime DESC',:limit => 1)

    if art_adherance.blank? and task.encounter_type != art_encounters[5]
      t = Task.find_by_description("If a patient/guardian has skipped a station")
      t.url = t.url.gsub(/\{encounter_type\}/, "#{art_encounters[5].gsub(' ','_')}") 
      return t
    elsif art_adherance.blank? and task.encounter_type == art_encounters[5]
      return task
    end
=end
    art_treatment = Encounter.find(:first,
                                   :conditions =>["patient_id = ? AND encounter_type = ? AND DATE(encounter_datetime) = ?",
                                   patient.id,EncounterType.find_by_name(art_encounters[6]).id,session_date],
                                   :order =>'encounter_datetime DESC',:limit => 1)

    if art_visit.blank? and task.encounter_type != art_encounters[6]
      t = Task.find_by_description("If a patient/guardian has skipped a station")
      t.url = t.url.gsub(/\{encounter_type\}/, "#{art_encounters[6].gsub(' ','_')}") 
      return t
    elsif art_visit.blank? and task.encounter_type == art_encounters[6]
      return task
    end


    task
  end 
end
