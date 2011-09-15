class PersonAttributeType < ActiveRecord::Base
  set_table_name 'person_attribute_type'
  set_primary_key 'person_attribute_type_id'

  include Openmrs
  
  has_many :person_attributes,
      :conditions => {:voided => 0}

  def self.[](name)
    self.find_by_name name
  end

  def id
    self.person_attribute_type_id
  end

end
