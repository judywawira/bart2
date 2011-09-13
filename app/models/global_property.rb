class GlobalProperty < ActiveRecord::Base
  set_table_name "global_property"
  set_primary_key "property"
  include Openmrs

  def to_s
    return "#{property}: #{property_value}"
  end  

  def self.use_user_selected_activities
    self.find_by_property('use.user.selected.activities').property_value == 'yes' rescue false
  end

  def self.[](key, default=nil)
    self.find_by_property(key).try(:property_value) || default
  end

end
