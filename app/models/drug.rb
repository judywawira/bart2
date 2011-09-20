class Drug < ActiveRecord::Base
  set_table_name 'drug'
  set_primary_key 'drug_id'

  include Openmrs

  belongs_to :concept,
      :conditions => {:retired => 0}
  belongs_to :form,
      :foreign_key => 'dosage_form',
      :class_name  => 'Concept',
      :conditions  => {:retired => 0}
  
  def arv?
    self.class.arv_drugs.map(&:concept_id).include?(self.concept_id)
  end

  def self.arv_drugs
    ConceptSet.named('ANTIRETROVIRAL DRUGS').all
  end
  
  def tb_medication?
    Drug.tb_drugs.map(&:concept_id).include?(self.concept_id)
  end
  
  def self.tb_drugs
    ConceptSet.named('Tuberculosis treatment drugs').all
  end

  # Need to make this a lot more generic
  # FIXME: ever thought about how inefficient this method is?!
  # This method gets all generic drugs in the database
  def self.generic
    generics = []
    preferred = Concept.named('Maternity Prescriptions').concept_members.collect(&:concept_id) rescue []
    self.all.each do |drug|
    # FIXME: exception driven flow control
      Concept.find(drug.concept_id, :conditions => {:retired => false, :concept_id => preferred}).concept_names.each do |conceptname|
        generics << [conceptname.name, drug.concept_id] rescue nil
      end.compact.uniq rescue []
    end
    generics.uniq
  end

  # For a selected generic drug, this method gets all corresponding drug combinations
  def self.drugs(generic_drug_concept_id)
    frequencies = ConceptName.drug_frequency
    collection = []

    # FIXME: exception driven flow control
    self.all(:conditions => {:concept_id => generic_drug_concept_id}).each do |d|
      frequencies.each do |freq|
        collection << ["#{d.dose_strength.to_i rescue 1}#{d.units.upcase rescue ""}", "#{freq}"]
      end
    end.uniq.compact rescue []

    collection.uniq
  end

  def self.dosages(generic_drug_concept_id)
    # FIXME: exception driven flow control

    self.all(:conditions => {:concept_id => generic_drug_concept_id}).collect do |d|
      [ "#{(d.dose_strength||1).to_i}#{(d.units||'').upcase}",
        "#{(d.dose_strength||1).to_i}",
        "#{(d.units||'').upcase}" ]
    end.uniq.compact

  end

  def self.frequencies
    ConceptName.drug_frequency
  end

end
