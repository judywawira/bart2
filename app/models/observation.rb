class Observation < ActiveRecord::Base
  set_table_name 'obs'
  set_primary_key 'obs_id'

  include Openmrs

  belongs_to :encounter,
      :conditions => {:voided => 0}
  belongs_to :order,
      :conditions => {:voided => 0}
  belongs_to :concept,
      :conditions => {:retired => 0}
  belongs_to :concept_name,
      :class_name  => 'ConceptName',
      :foreign_key => 'concept_name',
      :conditions  => {:voided => 0}
  belongs_to :answer_concept,
      :class_name  => 'Concept',
      :foreign_key => 'value_coded',
      :conditions  => {:retired => 0}
  belongs_to :answer_concept_name,
      :class_name  => 'ConceptName',
      :foreign_key => 'value_coded_name_id',
      :conditions  => {:voided => 0}
  has_many :concept_names,
      :through => :concept

  named_scope :recent, lambda {|number|
    {:order => 'obs_datetime DESC, date_created DESC', :limit => number}
  }
  named_scope :old, lambda {|number|
    {:order => 'obs_datetime ASC, date_created ASC', :limit => number}
  }

  named_scope :on_date, lambda {|session_date|
    {:conditions => ['DATE(encounter.encounter_datetime) = DATE(?)', session_date]}
  }

  named_scope :with_concept, lambda {|concept|
    concept_id = concept.to_i || ConceptName[concept].concept_id
    {:conditions => {:concept_id => concept_id}}
  }

  named_scope :named, lambda{|name|
    { :include    => :concept_name,
      :conditions => {:concept_name => {:name => name}}}
  }

  def validate
    if (value_numeric != '0.0' and value_numeric != '0' and not value_numeric.blank?)
      value_numeric = value_numeric.to_f
      # TODO
      # value_numeric = nil if value_numeric == 0.0
    end

    if [value_numeric, value_boolean, value_coded, value_drug, value_datetime, value_modifier, value_text].all? &:blank?
      errors.add_to_base('Value cannot be blank')
    end
  end

  def patient_id=(patient_id)
    self.person_id=patient_id
  end
  
  def concept_name=(concept_name)
    self.concept_id = ConceptName.find_by_name(concept_name).concept_id
  rescue
    raise %Q("#{concept_name}" does not exist in the concept_name table)
  end

  def value_coded_or_text=(value_coded_or_text)
    return if value_coded_or_text.blank?
    
    value_coded_name = ConceptName.find_by_name(value_coded_or_text)
    if value_coded_name.nil?
      # TODO: this should not be done this way with a brittle hard ref to concept name
      #self.concept_name = "DIAGNOSIS, NON-CODED" if self.concept && self.concept.name && self.concept.fullname == "DIAGNOSIS"
      self.concept_name = 'DIAGNOSIS, NON-CODED' if self.concept and self.concept.fullname == 'DIAGNOSIS'
      self.value_text   = value_coded_or_text
    else
      self.value_coded_name_id = value_coded_name.concept_name_id
      self.value_coded         = value_coded_name.concept_id
    end
  end

  def self.find_most_common(concept_question, answer_string, limit = 10)
    self.all(
      :select => "COUNT(*) as count, concept_name.name as value", 
      :joins => "INNER JOIN concept_name ON concept_name.concept_name_id = value_coded_name_id AND concept_name.voided = 0", 
      :conditions => ["obs.concept_id = ? AND (concept_name.name LIKE ? OR concept_name.name IS NULL)", concept_question, "%#{answer_string}%"],
      :group => :value_coded_name_id, 
      :order => "COUNT(*) DESC",
      :limit => limit).map(&:value)
  end

  def self.find_most_common_location(concept_question, answer_string, limit = 10)
    self.all(
      :select => "COUNT(*) as count, location.name as value", 
      :joins => "INNER JOIN locations ON location.location_id = value_location AND location.retired = 0", 
      :conditions => ["obs.concept_id = ? AND location.name LIKE ?", concept_question, "%#{answer_string}%"],
      :group => :value_location, 
      :order => "COUNT(*) DESC",
      :limit => limit).map(&:value)
  end

  def self.find_most_common_value(concept_question, answer_string, value_column = :value_text, limit = 10)
    answer_string = "%#{answer_string}%" if value_column == :value_text
    self.all(
      :select => "COUNT(*) as count, #{value_column} as value", 
      :conditions => ["obs.concept_id = ? AND #{value_column} LIKE ?", concept_question, answer_string],
      :group => value_column, 
      :order => "COUNT(*) DESC",
      :limit => limit).map(&:value)
  end

  def to_s(tags=[])
    formatted_name   = self.concept_name.typed(tags).first.try(:name)
    formatted_name ||= self.concept_name.try(:name)
    formatted_name ||= self.concept.concept_names.typed(tags).first.name || self.concept.try(:fullname)
    formatted_name ||= self.concept.concept_names.first.try(:name) || 'Unknown concept name'
    "#{formatted_name}:  #{self.answer_string(tags)}"
  end

  def name(tags=[])
    formatted_name   = self.concept_name.tagged(tags).first.try(:name)
    formatted_name ||= self.concept_name.try(:name)
    formatted_name ||= self.concept.concept_names.tagged(tags).first.try(:name)
    formatted_name ||= self.concept.concept_names.first.try(:name) || 'Unknown concept name'
    "#{self.answer_string(tags)}"
  end

  def answer_string(tags=[])
    coded_answer_name   = self.answer_concept.concept_names.typed(tags).first.name rescue nil
    coded_answer_name ||= self.answer_concept.concept_names.first.name rescue nil
    coded_name = "#{coded_answer_name} #{self.value_modifier}#{self.value_text} #{self.value_numeric}#{self.value_datetime.strftime("%d/%b/%Y") rescue nil}#{self.value_boolean && (self.value_boolean ? 'Yes' : 'No' rescue nil)}#{" [#{order}]" if order_id and tags.include?('order')}"
    #the following code is a hack
    #we need to find a better way because value_coded can also be a location - not only a concept
    return coded_name unless coded_name.blank?
    Concept.find_by_concept_id(self.value_coded).concept_names.typed('SHORT').first.name || ConceptName.find_by_concept_id(self.value_coded).try(:name) || ''
  end

  def self.patients_with_multiple_start_reasons(start_date , end_date)
    art_eligibility_id      = ConceptName['REASON FOR ART ELIGIBILITY'].concept_id
    arv_number_id           = PatientIdentifierType['ARV Number'].id
    national_identifier_id  = PatientIdentifierType['National id'].id

    patients = self.find_by_sql(["SELECT person_id, concept_id, date_created, value_coded_name_id FROM obs
                                           WHERE (SELECT COUNT(*) FROM obs observation
                                                  WHERE observation.concept_id = ?
                                                    AND observation.person_id = obs.person_id) >= 1
                                                    AND date_created BETWEEN ? AND ?
                                                    AND obs.concept_id = ?", art_eligibility_id, start_date , end_date, art_eligibility_id])
    patients_data = []

    patients.each do |reason|
      arv_number   = PatientIdentifier.identifier(reason[:person_id], arv_number_id).try(:identifier)          || []
      national_id  = PatientIdentifier.identifier(reason[:person_id], national_identifier_id).try(:identifier) || []
      start_reason = ConceptName.find(reason[:value_coded_name_id]).name

      patients_data << [reason[:person_id].to_s, arv_number, national_id,
                 reason[:date_created].strftime('%Y-%m-%d %H:%M:%S') , start_reason]
    end

    patients_data
  end
  
  def self.new_accession_number
    last_accn_number = (Observation.last(:conditions => 'accession_number IS NOT NULL', :order => 'accession_number + 0'). try(:accession_number) || '00').to_s
    last_accn_number_with_no_chk_dgt = last_accn_number.chop.to_i
    new_accn_number_with_no_chk_dgt  = last_accn_number_with_no_chk_dgt + 1
    chk_dgt = PatientIdentifier.calculate_checkdigit(new_accn_number_with_no_chk_dgt)
    new_accn_number = "#{new_accn_number_with_no_chk_dgt}#{chk_dgt}"
    return new_accn_number.to_i
  end

  def to_s_location(tags=[])
    formatted_name = self.concept_name.tagged(tags).name rescue nil
    formatted_name ||= self.concept_name.name rescue nil
    formatted_name ||= self.concept.concept_names.tagged(tags).first.name rescue nil
    formatted_name ||= self.concept.concept_names.first.name rescue 'Unknown concept name'
    "#{formatted_name}:  #{Location.find(self.answer_string(tags)).name}"
  end

end
