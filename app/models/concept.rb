class Concept < ActiveRecord::Base
  set_table_name 'concept'
  set_primary_key 'concept_id'

  include Openmrs

  belongs_to :concept_class,
      :conditions => {:retired => 0}
  belongs_to :concept_datatype,
      :conditions => {:retired => 0}
  has_one :concept_numeric,
      :foreign_key => :concept_id,
      :dependent => :destroy
  #has_one :name, :class_name => 'ConceptName'
  has_many :answer_concept_names,
      :class_name => 'ConceptName',
      :conditions => {:voided => 0}
  has_many :concept_names,
      :conditions => {:voided => 0}
  has_many :concept_maps # no default scope
  has_many :concept_sets  # no default scope
  has_many :concept_answers do # no default scope
    def limit(search_string)
      return self if search_string.blank?
      reject {|concept_answer| not concept_answer.name.match(search_string) }
    end
  end

  has_many :drugs,
      :conditions => {:retired => 0}
  has_many :concept_members,
      :class_name  => 'ConceptSet',
      :foreign_key => :concept_set

  def self.find_by_name(concept_name)
    self.first(:include    => :concept_names,
               :conditions => {'concept.retired' => 0, 'concept_name.voided' => 0, 'concept_name.name' => concept_name})
  end

  def shortname
    name = self.concept_names.typed('SHORT').first.name
    name.blank? ? self.concept_names.first.try(:name) : name
  end

  def fullname
    name = self.concept_names.typed('FULLY_SPECIFIED').first.name
    name.blank? ? self.concept_names.first.try(:name) : name
  end

  def self.[](key)
    self.find_by_name key
  end

  def id
    self.concept_id
  end

end
