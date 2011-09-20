class PatientIdentifier < ActiveRecord::Base
  set_table_name 'patient_identifier'
  set_primary_key 'patient_identifier_id'

  include Openmrs

  belongs_to :type,
      :class_name  => 'PatientIdentifierType',
      :foreign_key => :identifier_type,
      :conditions  => {:retired => 0}
  belongs_to :patient,
      :class_name  => 'Patient',
      :foreign_key => :patient_id,
      :conditions  => {:voided => 0}

  named_scope :typed,
      lambda{|*type_names| {:include => :type, :conditions => {'patient_identifier_type.name' => type_names.flatten}} }

  def self.calculate_checkdigit(number)
    # This is Luhn's algorithm for checksums
    # http://en.wikipedia.org/wiki/Luhn_algorithm
    # Same algorithm used by PIH (except they allow characters)
    number = number.to_s
    number = number.split(//).collect { |digit| digit.to_i }
    parity = number.length % 2

    sum = 0
    number.each_with_index do |digit, index|
      digit = digit * 2 if index % 2 == parity
      digit = digit - 9 if digit > 9
      sum  += digit
    end
    
    checkdigit = 0
    checkdigit += 1 while ((sum + checkdigit) % 10) != 0
    return checkdigit
  end

  def self.site_prefix
    GlobalProperty['site_prefix']
  end

  def self.next_available_arv_number
    current_arv_code = self.site_prefix
    type = PatientIdentifierType.find_by_name('ARV Number').id
    current_arv_number_identifiers = PatientIdentifier.all(:conditions => ['identifier_type = ? AND voided = 0', type])

    assigned_arv_ids = (current_arv_number_identifiers || []).collect do |identifier|
      $1.to_i if identifier.identifier.match(/#{current_arv_code} *(\d+)/)
    end.compact

    if assigned_arv_ids.empty?
      next_available_number = 1
    else
      # Check for unused ARV idsV
      # Suggest the next arv_id based on unused ARV ids that are within 10 of the current_highest arv id. This makes sure that we don't get holes unless we   really want them and also means that our suggestions aren't broken by holes
      #array_of_unused_arv_ids = (1..highest_arv_id).to_a - assigned_arv_ids
      assigned_numbers      = assigned_arv_ids.sort
      possible_number_range = GlobalProperty['arv_number_range', 100000].to_i
      possible_identifiers  = Array.new(possible_number_range){|i| i + 1 }
      next_available_number = (possible_identifiers - assigned_numbers).first
    end
    return "#{current_arv_code} #{next_available_number}"
  end

  # FIXME: remove this method and place its logic where it belongs -- in the patient model
  def self.identifier(patient_id, patient_identifier_type_id)
    self.first(:select      => 'identifier',
               :conditions  =>['patient_id = ? and identifier_type = ?', patient_id, patient_identifier_type_id])
  end

  def self.out_of_range_arv_numbers(arv_number_range, start_date , end_date)
    arv_number_id             = PatientIdentifierType['ARV Number'].id
    national_identifier_id    = PatientIdentifierType['National id'].id
    arv_start_number          = arv_number_range.first
    arv_end_number            = arv_number_range.last

    out_of_range_arv_numbers  = PatientIdentifier.find_by_sql([
        'SELECT patient_id, identifier, date_created FROM patient_identifier
          WHERE identifier_type = ? AND  identifier >= ?
          AND identifier <= ?
          AND (NOT EXISTS(SELECT * FROM patient_identifier
          WHERE identifier_type = ? AND date_created >= ? AND date_created <= ?))',
            arv_number_id,  arv_start_number,  arv_end_number,
            arv_number_id, start_date, end_date])

    out_of_range_arv_numbers.map do |arv_num_data|
      patient     = Person.find(arv_num_data[:patient_id].to_i)
      national_id = PatientIdentifier.identifier(arv_num_data[:patient_id], national_identifier_id).try(:identifier) || ''

      [ arv_num_data[:patient_id],
        arv_num_data[:identifier],
        patient.name,
        national_id,
        patient.gender,
        patient.age,
        patient.birthdate,
        arv_num_data[:date_created].strftime('%Y-%m-%d %H:%M:%S') ]
    end
  end

  def self.next_filing_number(type = 'Filing Number')
    type_id              = PatientIdentifierType.find_by_name(type).id
    available_numbers    = self.all(:conditions => ['identifier_type = ?', type_id]).map &:identifier
    filing_number_prefix = GlobalProperty['filing.number.prefix', 'FN101,FN102']
    case type
    when /filing/i
      prefix            = filing_number_prefix.split(',')[0][0..3]
      len_of_identifier = (filing_number_prefix.split(',')[0][-1..-1] + '00000').to_i
    when /Archived/i
      prefix = filing_number_prefix.split(',')[1][0..3]
      len_of_identifier = (filing_number_prefix.split(',')[1][-1..-1] + '00000').to_i
    end

    possible_identifiers_range = GlobalProperty['filing.number.range', 300000].to_i
    possible_identifiers       = Array.new(possible_identifiers_range){|i| prefix + (len_of_identifier + i + 1).to_s }

    (possible_identifiers - available_numbers.compact.uniq).first
  end

end
