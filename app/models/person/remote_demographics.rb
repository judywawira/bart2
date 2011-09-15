class Person
  module RemoteDemographics

    def self.included(base)
      base.send :include, InstanceMethods
      base.send :extend, ClassMethods
    end

    module ClassMethods
      def find_remote_by_identifier(identifier)
        return nil unless self.remote_demographics_server
        result = self.remote_demographics_server.query(identifier)
        if result
          Person.create_from_remote(result['person']['data']['person'])
        end
      end

      def find_remote(known_demographics)
        return nil unless self.remote_demographics_server
        self.remote_demographics_server.query(known_demographics)
      end # def find_remote

      def create_from_remote(params)
        address_params  = params['addresses']
        names_params    = params['names']
        patient_params  = params['patient']
        birthday_params = params.slice('birth_day', 'birth_month', 'birth_year', 'age_estimate')
        person_params   = params.slice('gender')
#         reject{|key, value| key.match(/addresses|patient|names|relation|cell_phone_number|home_phone_number|office_phone_number|agrees_to_be_visited_for_TB_therapy|agrees_phone_text_for_TB_therapy/) }
#         birthday_params   = params_to_process.reject{|key, value| key.match(/gender/) }
#         person_params     = params_to_process.reject{|key, value| key.match(/birth_|age_estimate|occupation/) }

        person_params['gender'] = {'Female' => 'F', 'Male' => 'M'}[person_params['gender']]

        person = Person.create(person_params)

        if birthday_params['birth_year'] == 'Unknown'
          person.set_birthdate_by_age(birthday_params['age_estimate'], self.session_datetime || Date.today)
        else
          person.set_birthdate *birthday_params.values_at('birth_year', 'birth_month', 'birth_day')
        end
        person.save
        person.names.create names_params
        person.addresses.create address_params

        { 'Occupation'          => 'occupation',
          'Cell Phone Number'   => 'cell_phone_number',
          'Office Phone Number' => 'office_phone_number',
          'Home Phone Number'   => 'home_phone_number'}.each_pair do |prop, attr|
          person.set_attribute(prop, params[attr]) unless params[attr].blank? rescue nil
        end

#         person.person_attributes.create(
#           :person_attribute_type_id => PersonAttributeType.find_by_name("Landmark Or Plot Number").person_attribute_type_id,
#           :value => params["landmark"]) unless params["landmark"].blank? rescue nil

        # TODO handle the birthplace attribute

        if (!patient_params.nil?)
          patient = person.create_patient

          (patient_params['identifiers'] || []).each do |identifier_type_name, identifier|
            identifier_type = PatientIdentifierType.find_by_name(identifier_type_name) || PatientIdentifierType.find_by_name('Unknown id')
            patient.patient_identifiers.create('identifier' => identifier, 'identifier_type' => identifier_type.patient_identifier_type_id)
          end

          # This might actually be a national id, but currently we wouldn't know
          #patient.patient_identifiers.create("identifier" => patient_params["identifier"], "identifier_type" => PatientIdentifierType.find_by_name("Unknown id")) unless params["identifier"].blank?
        end

        return person

#       rescue => e
#         raise "somethig was not OK: #{e}; params:\n" + params.inspect
      end

      protected

      def remote_demographics_server
        @remote_demographics_server ||= RemoteDemographicsServer.new rescue nil
      end

    end # module ClassMethods
    
    module InstanceMethods

      # returns a hash representation of this user that can be sent to the dde server
      def remote_demographics
        self.demographics
      end # def remote_demographics

    end # module InstanceMethods
  end # module RemoteDemographics

end # class User
