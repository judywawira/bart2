class PatientIdentifierType < ActiveRecord::Base
  set_table_name 'patient_identifier_type'
  set_primary_key 'patient_identifier_type_id'

  include Openmrs

  def next_identifier(options = {})
    return nil unless options[:patient]
    case self.name
    when 'National id'
      unless use_moh_national_id
        health_center_id    = Location.current_location.site_id
        national_id_version = '1'
        national_id_prefix  = "P#{national_id_version}#{health_center_id.rjust(3, '0')}"
        last_national_id    = PatientIdentifier.first(:order => 'identifier desc', :conditions => ['identifier_type = ? AND left(identifier, 5) = ?', self.patient_identifier_type_id, national_id_prefix])
        last_national_id_number = last_national_id.try(:identifier) || '0'

        next_number = (last_national_id_number[5..-2].to_i + 1).to_s.rjust(7, '0')
        new_national_id_no_check_digit = "#{national_id_prefix}#{next_number}"
        check_digit = PatientIdentifier.calculate_checkdigit(new_national_id_no_check_digit[1..-1])
        new_national_id = "#{new_national_id_no_check_digit}#{check_digit}"
      else
        new_national_id = NationalId.next_id(options[:patient].patient_id)
      end
      PatientIdentifier.create! \
          :type       =>  self,
          :identifier => new_national_id,
          :patient    => options[:patient]
    end
  end

  private

  def use_moh_national_id
    (GlobalProperty['use.moh.national.id'] == 'yes') || false
  end

end
