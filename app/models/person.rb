class Person < ActiveRecord::Base
  set_table_name 'person'
  set_primary_key 'person_id'

  include Openmrs
  include Person::RemoteDemographics

  cattr_accessor :session_datetime
  cattr_accessor :migrated_datetime
  cattr_accessor :migrated_creator
  cattr_accessor :migrated_location

  has_one :patient,
      :foreign_key => :patient_id,
      :dependent   => :destroy,
      :conditions  => {:voided => 0}
  has_many :names,
      :class_name  => 'PersonName',
      :foreign_key => :person_id,
      :dependent   => :destroy,
      :order       => 'person_name.preferred DESC',
      :conditions  => {:voided => 0}
  has_many :addresses,
      :class_name  => 'PersonAddress',
      :foreign_key => :person_id,
      :dependent   => :destroy,
      :order       => 'person_address.preferred DESC',
      :conditions  => {:voided => 0}
  has_many :relationships,
      :class_name  => 'Relationship',
      :foreign_key => :person_a,
      :conditions  => {:voided => 0}
  has_many :person_attributes,
      :class_name  => 'PersonAttribute',
      :foreign_key => :person_id,
      :conditions  => {:voided => 0}
  has_many :observations,
      :class_name  => 'Observation',
      :foreign_key => :person_id,
      :dependent   => :destroy,
      :conditions  => {:voided => 0} do
    def find_by_concept_name(name)
      all(:conditions => {:concept_id => ConceptName[name].concept_id}) rescue []
    end
  end

  def after_void(reason = nil)
    self.patient.void(reason) rescue nil
    self.names.each{|row| row.void(reason) }
    self.addresses.each{|row| row.void(reason) }
    self.relationships.each{|row| row.void(reason) }
    self.person_attributes.each{|row| row.void(reason) }
    # We are going to rely on patient => encounter => obs to void those
  end

  def name
    "#{self.names.first.given_name} #{self.names.first.family_name}".titleize rescue nil
  end  

  def address
    "#{self.addresses.first.city_village}"  rescue nil
  end

  def current_address
    self.addresses.first || self.addresses.build
  end

  def age(today = Date.today)
    return nil if self.birthdate.nil?

    # This code which better accounts for leap years
    patient_age = (today.year - self.birthdate.year) + ((today.month - self.birthdate.month) + ((today.day - self.birthdate.day) < 0 ? -1 : 0) < 0 ? -1 : 0)

    # If the birthdate was estimated this year, we round up the age, that way if
    # it is March and the patient says they are 25, they stay 25 (not become 24)
    birth_date=self.birthdate
    estimate=self.birthdate_estimated==1
    patient_age += (estimate && birth_date.month == 7 && birth_date.day == 1  && 
      today.month < birth_date.month && self.date_created.year == today.year) ? 1 : 0
  end

  def age_in_months(today = Date.today)
    years = (today.year - self.birthdate.year)
    months = (today.month - self.birthdate.month)
    (years * 12) + months
  end
    
  def birthdate_formatted
    if self.birthdate_estimated == 1
      if self.birthdate.day == 1 and self.birthdate.month == 7
        self.birthdate.strftime('??/???/%Y')
      elsif self.birthdate.day == 15 
        self.birthdate.strftime('??/%b/%Y')
      elsif self.birthdate.day == 1 and self.birthdate.month == 1 
        self.birthdate.strftime('??/???/%Y')
      end
    else
      self.birthdate.strftime('%d/%b/%Y')
    end
  end

  def set_birthdate(year = nil, month = nil, day = nil)
    raise 'No year passed for estimated birthdate' if year.nil?

    # Handle months by name or number (split this out to a date method)    
    month_i = (month || 0).to_i
    month_i = Date::MONTHNAMES.index(month)      if month_i == 0 || month_i.blank?
    month_i = Date::ABBR_MONTHNAMES.index(month) if month_i == 0 || month_i.blank?
    
    if month_i == 0 or month == 'Unknown'
      self.birthdate = Date.new(year.to_i,7,1)
      self.birthdate_estimated = 1
    elsif day.blank? or day == 'Unknown' or day == 0
      self.birthdate = Date.new(year.to_i,month_i,15)
      self.birthdate_estimated = 1
    else
      self.birthdate = Date.new(year.to_i,month_i,day.to_i)
      self.birthdate_estimated = 0
    end
  end

  def set_birthdate_by_age(age, today = Date.today)
    self.birthdate = Date.new(today.year - age.to_i, 7, 1)
    self.birthdate_estimated = 1
  end

  def demographics
    if self.birthdate_estimated == 1
      birth_day = 'Unknown'
      if self.birthdate.month == 7 and self.birthdate.day == 1
        birth_month = 'Unknown'
      else
        birth_month = self.birthdate.month
      end
    else
      birth_month = self.birthdate.try :month
      birth_day   = self.birthdate.try :day
    end

    name = self.names.first

    demographics = {
      'person' => {
        'date_changed'  => self.date_changed.to_s,
        'gender'        => self.gender,
        'birth_year'    => self.birthdate.try(:year),
        'birth_month'   => birth_month,
        'birth_day'     => birth_day,
        'names'         => {
          'given_name'   => name.given_name,
          'family_name'  => name.family_name,
          'family_name2' => name.family_name2
        },
        'addresses'     => {
          'county_district' => self.current_address.county_district,
          'city_village'    => self.current_address.city_village,
          'address1'        => self.current_address.address1,
          'address2'        => self.current_address.address2
        },
        'attributes'    => {
          'occupation'        => self.get_attribute('Occupation'),
          'cell_phone_number' => self.get_attribute('Cell Phone Number')
        }
      }
    }
 
    demographics['person']['patient'] = {'identifiers' => {}}
    unless self.patient.try(:patient_identifiers).blank?
      self.patient.patient_identifiers.each do |identifier|
        demographics['person']['patient']['identifiers'][identifier.type.name] = identifier.identifier
      end
    end

    return demographics
  end

  def self.occupations
    [ '', 'Driver', 'Housewife', 'Messenger', 'Business', 'Farmer', 'Salesperson', 'Teacher', 'Student',
      'Security guard', 'Domestic worker', 'Police', 'Office worker', 'Preschool child', 'Mechanic',
      'Prisoner', 'Craftsman', 'Healthcare Worker', 'Soldier'].sort + ['Other', 'Unknown']
  end

  def self.search_by_identifier(identifier)
    PatientIdentifier.find_all_by_identifier(identifier).map{|id| id.patient.person} unless identifier.blank?
  rescue
    nil
  end

  def self.search(params)
    people = Person.search_by_identifier(params[:identifier]) || []

    case people.size
    when 1
      return people.first.id
    when 0
      return Person.all(:include => [{:names => [:person_name_code]}, :patient],
                        :conditions => ['gender = ? AND
                       (person_name.given_name LIKE ? OR person_name_code.given_name_code LIKE ?) AND
                       (person_name.family_name LIKE ? OR person_name_code.family_name_code LIKE ?)',
                        params[:gender], params[:given_name], (params[:given_name] || '').soundex,
                        params[:family_name], (params[:family_name] || '').soundex
                       ])
    else
      return people
    end

    # temp removed
    # AND (person_name.family_name2 LIKE ? OR person_name_code.family_name2_code LIKE ? OR person_name.family_name2 IS NULL )"    
    #  params[:family_name2],
    #  (params[:family_name2] || '').soundex,

# CODE below is TODO, untested and NOT IN USE
#    people = []
#    people = PatientIdentifier.find_all_by_identifier(params[:identifier]).map{|id| id.patient.person} unless params[:identifier].blank?
#    if people.size == 1
#      return people
#    elsif people.size >2
#      filtered_by_family_name_and_gender = []
#      filtered_by_family_name = []
#      filtered_by_gender = []
#      people.each{|person|
#        gender_match = person.gender == params[:gender] unless params[:gender].blank?
#        filtered_by_gender.push person if gender_match
#        family_name_match = person.first.names.collect{|name|name.family_name.soundex}.include? params[:family_name].soundex
#        filtered_by_family_name.push person if gender_match?
#        filtered_by_family_name_and_gender.push person if family_name_match? and gender_match?
#      }
#      return filtered_by_family_name_and_gender unless filtered_by_family_name_and_gender.empty?
#      return filtered_by_family_name unless filtered_by_family_name.empty?
#      return filtered_by_gender unless filtered_by_gender.empty?
#      return people
#    else
#    return people if people.size == 1
#    people = Person.find(:all, :include => [{:names => [:person_name_code]}, :patient], :conditions => [
#    "gender = ? AND \
#     (person_name.given_name LIKE ? OR person_name_code.given_name_code LIKE ?) AND \
#     (person_name.family_name LIKE ? OR person_name_code.family_name_code LIKE ?)",
#    params[:gender],
#    params[:given_name],
#    (params[:given_name] || '').soundex,
#    params[:family_name],
#    (params[:family_name] || '').soundex
#    ]) if people.blank?
#    
    # temp removed
    # AND (person_name.family_name2 LIKE ? OR person_name_code.family_name2_code LIKE ? OR person_name.family_name2 IS NULL )"    
    #  params[:family_name2],
    #  (params[:family_name2] || '').soundex,

  end

  def self.find_by_demographics(person_demographics)
    national_id = person_demographics['person']['patient']['identifiers']['National id'] rescue nil
    results     = Person.search_by_identifier(national_id) unless national_id.nil?
    unless results.blank?
      return results
    else
      gender      = person_demographics['person']['gender'] rescue nil
      given_name  = person_demographics['person']['names']['given_name'] rescue nil
      family_name = person_demographics['person']['names']['family_name'] rescue nil

      search_params = {:gender => gender, :given_name => given_name, :family_name => family_name}
      results       = Person.search(search_params)

=begin
    national_id = person_demographics["person"]["patient"]["identifiers"]["National id"] rescue nil
    person = Person.search_by_identifier(national_id) unless national_id.nil?
    return {} if person.blank? 

    #person_demographics = person.demographics
    results = {}
    result_hash = {}
    gender = person_demographics["person"]["gender"] rescue nil
    given_name = person_demographics["person"]["names"]["given_name"] rescue nil
    family_name = person_demographics["person"]["names"]["family_name"] rescue nil
   # raise"#{gender}"
    result_hash = {
      "gender" =>  person_demographics["person"]["gender"],
      "names" => {"given_name" =>  person_demographics["person"]["names"]["given_name"],
                  "family_name" =>  person_demographics["person"]["names"]["family_name"],
                  "family_name2" => person_demographics["person"]["names"]["family_name2"]
                  },
      "birth_year" => person_demographics['person']['birth_year'],
      "birth_month" => person_demographics['person']['birth_month'],
      "birth_day" => person_demographics['person']['birth_day'],
      "addresses" => {"city_village" => person_demographics['person']['addresses']['city_village'],
                      "address2" => nil,
                      "state_province" => nil,
                      "county_district" => nil
                      },
      "attributes" => {"occupation" => person_demographics['person']['occupation'],
                      "home_phone_number" => nil,
                      "office_phone_number" => nil,
                      "cell_phone_number" => nil
                      },
      "patient" => {"identifiers" => {"National id" => person_demographics['person']['patient']['identifiers']['National id'],
                                      "ARV Number" => ['person']['patient']['identifiers']['ARV Number']
                                      }
                   },
      "date_changed" => person_demographics['person']['date_changed']

    }
    results["person"] = result_hash
    return results
=end
    end
  end

  def get_attribute(attr_name)
    self.person_attributes.first(:conditions => {:person_attribute_type_id => PersonAttributeType[attr_name].id}).try(:value)
  end

  def set_attribute(attr_name, value)
    attribute = self.get_attribute('Occupation')
    if attribute
      existing_person_attribute.update_attributes(:value => value.to_s)
    else
      type_id = PersonAttributeType[attr_name].id
      self.person_attributes.create(:person_attribute_type_id => type_id, :value => value.to_s)
    end
  end

  def sex
    {'M' => 'Male', 'F' => 'Female'}[self.gender]
  end

  def phone_numbers
    @phone_numbers ||= {
      'Cell phone number'   => self.get_attribute('Cell Phone Number'),
      'Office phone number' => self.get_attribute('Office Phone Number'),
      'Home phone number'   => self.get_attribute('Home phone number')
    }
  end

  def update_demographics

  end

end
