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
        birthday_params = params['birth_date']
        person_params   = params['gender']

        birtdate_estimated = params.delete('birtdate_estimated').to_i

        person_params['gender'] = {'Female' => 'F', 'Male' => 'M'}[person_params['gender']]

        person = Person.create(person_params)

        if birthday_params['year'] == 'Unknown'
#           person.set_birthdate_by_age(birthday_params['birtdate_estimated'], self.session_datetime || Date.today)
#         else
          person.set_birthdate *birthday_params.values_at('year', 'month', 'day')
        end
        person.save
        person.names.create names_params
        person.addresses.create address_params

        { 'Occupation'          => 'occupation',
          'Cell Phone Number'   => 'cell_phone_number',
          'Office Phone Number' => 'office_phone_number',
          'Home Phone Number'   => 'home_phone_number'}.each_pair do |prop, attr|
          person.set_attribute(prop, params['attributes'][attr]) unless params['attributes'][attr].blank?
        end

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
