module AssociationCreateOrUpdate
  def create_or_update(attrs)
    if proxy_target.any?
      proxy_target.first.update_attributes(attrs)
    else
      proxy_reflection.build_association(attrs)
    end
  end
end

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
      :conditions  => {:voided => 0},
      :extend      => AssociationCreateOrUpdate

  has_many :addresses,
      :class_name  => 'PersonAddress',
      :foreign_key => :person_id,
      :dependent   => :destroy,
      :order       => 'person_address.preferred DESC',
      :conditions  => {:voided => 0},
      :extend      => AssociationCreateOrUpdate

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
      all(:include => :concept_name, :conditions => {:concept_name => {:name => name}})
    end
  end

  delegate :national_id,
      :to        => :patient,
      :allow_nil => true

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
    "#{self.addresses.first.city_village}" rescue nil
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
    birth_date = self.birthdate
    estimate   = self.birthdate_estimated == 1
    patient_age += (estimate and birth_date.month == 7 and birth_date.day == 1  and
                    today.month < birth_date.month and self.date_created.year == today.year) ? 1 : 0
  end

  def age_in_months(today = Date.today)
    years  = (today.year  - self.birthdate.year)
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

  def birthdate_to_params
    date = {}
    if self.birthdate_estimated == 1
      date['day'] = 'Unknown'
      if self.birthdate.month == 7 and self.birthdate.day == 1
        date['month'] = 'Unknown'
      else
        date['month'] = self.birthdate.month
      end
    else
      date['month'] = self.birthdate.month
      date['day']   = self.birthdate.day
    end
    date['year'] = self.birthdate.year

    return date
  end

  def birthdate_from_params=(hash)
    self.set_birthdate *hash.values_at('year', 'month', 'day')
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
    # make sure to fetch the latest demopgraphics from the server
    self.class.find_remote_by_identifier(self.national_id)
    # and return the updated demographics
    return self.demographics_from_local_db
  end

  def demographics_from_local_db
    return @demographics if @demographics

    name = self.names.first

    @demographics = {
      'person' => {
        'gender'     => self.gender,
        'birth_date' => self.birthdate_to_params,
        'birthdate_estimated' => 0, # FIXME
        'names' => {
          'given_name'   => name.given_name,
          'family_name'  => name.family_name,
          'family_name2' => name.family_name2
        },
        'addresses'    => [{
          'address1'        => self.current_address.address1,
          'address2'        => self.current_address.address2,
          'city_village'    => self.current_address.city_village,
          'county_district' => self.current_address.county_district,
        }],
        'attributes'   => {
          'occupation'          => self.get_attribute('Occupation'),
          'cell_phone_number'   => self.get_attribute('Cell Phone Number'),
          'home_phone_number'   => self.get_attribute('Home Phone Number'),
          'office_phone_number' => self.get_attribute('Office Phone Number')
        },
        'identifiers' => self.identifiers
      }
    }
  end

  def identifiers
    self.patient.patient_identifiers.inject({}) do |mem, identifier|
      mem[identifier.type.name] = identifier.identifier
      mem
    end
  end

  def self.occupations
    [ '', 'Driver', 'Housewife', 'Messenger', 'Business', 'Farmer', 'Salesperson', 'Teacher', 'Student',
      'Security guard', 'Domestic worker', 'Police', 'Office worker', 'Preschool child', 'Mechanic',
      'Prisoner', 'Craftsman', 'Healthcare Worker', 'Soldier'].sort + ['Other', 'Unknown']
  end

  # returns all users that have any identifier that matches the given value
  def self.search_by_identifier(identifier)
    unless identifier.blank?
      self.all(:include    => {:patient => :patient_identifiers},
               :conditions => {:patient_identifier => {:identifier => identifier}})
    end
  end

  # returns all users that match the given set of demographics data
  # the first search only uses the identifier(s) and if no results are found,
  # the second search includes gender, given and family name (literal and soundex)
  def self.search(params)
    people = self.search_by_identifier(params[:identifier]) || []

    case people.size
    when 0
      self.all(:include    => [{:names => :person_name_code}, :patient],
               :conditions => ['gender = ? AND
               (person_name.given_name  LIKE ? OR person_name_code.given_name_code  LIKE ?) AND
               (person_name.family_name LIKE ? OR person_name_code.family_name_code LIKE ?)',
                params[:gender], params[:given_name], (params[:given_name] || '').soundex,
                params[:family_name], (params[:family_name] || '').soundex])
    else
      people
    end
  end

  def self.find_by_demographics(demographics)
    person_demographics = demographics['person']
    national_id = person_demographics['identifiers']['National id'] rescue nil
    results     = self.search_by_identifier(national_id) unless national_id.nil?
    if results.any?
      return results
    else
      gender      = person_demographics['gender'] || nil
      given_name  = person_demographics['names']['given_name']  rescue nil
      family_name = person_demographics['names']['family_name'] rescue nil

      search_params = {:gender => gender, :given_name => given_name, :family_name => family_name}
      results       = self.search(search_params)
    end
  end

  def get_attribute(attr_name)
    get_attribute_object(attr_name).try(:value)
  end

  def get_attribute_object(attr_name)
    self.person_attributes.first(:conditions => {:person_attribute_type_id => PersonAttributeType[attr_name].id})
  end

  def set_attribute(attr_name, value)
    existing_person_attribute = self.get_attribute_object('Occupation')
    if existing_person_attribute
      existing_person_attribute.update_attributes(:value => value.to_s)
    else
      type_id = PersonAttributeType[attr_name].id
      self.person_attributes.create(:person_attribute_type_id => type_id, :value => value.to_s, :creator =>  1)
    end
    self.save
    value
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
