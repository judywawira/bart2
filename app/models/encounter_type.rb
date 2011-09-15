class EncounterType < ActiveRecord::Base
  set_table_name 'encounter_type'
  set_primary_key 'encounter_type_id'

  include Openmrs

  has_many :encounters,
      :conditions => {:voided => 0}

  def self.[](key)
    self.find_by_name(key)
  end

end
