class Person
  module RemoteDemographics

    def self.included(base)
      base.send :include, InstanceMethods
      base.send :extend, ClassMethods
      base.send :attr_accessor, :update_from_remote_in_progress
      base.send :after_update, :save_remote, :unless => :update_from_remote_in_progress
    end

    module ClassMethods
      def find_remote(identifier)
        return nil unless self.remote_demographics_server
        result = self.remote_demographics_server.query(identifier)
        if result
          self.create_or_update_from_remote(result)
        end
      end
      alias find_remote_by_identifier find_remote

      def create_or_update_from_remote(params)
        # TODO: check whether needed keys are actually present
        person_params     = params['person']['data']['person']
        names_params      = person_params.delete('names')
        addresses_params  = person_params.delete('addresses')
        attributes_params = person_params.delete('attributes')
        identifier_params = person_params.delete('identifiers')
        person_params['gender'] = {'Female' => 'F', 'Male' => 'M', 'M' => 'M', 'F' => 'F'}[person_params['gender']]

        Person.transaction do
          if patient = Patient.find_by_national_id(params['npid']['value'])
            person = patient.person
          else
#             npid    = NationalId.find_or_create_by_national_id(params['npid']['value'])
            person  = Person.new
            patient = person.build_patient :national_id => npid
          end

          person.birthdate_from_params = person_params.delete('birth_date')
          person.attributes = person_params
          person.without_update_to_remote &:save

          attributes_params.each do |key, value|
            person.set_attribute key.titleize, value
          end

#           person.names.create_or_update names_params
#           person.addresses.create_or_update addresses_params

          # TODO handle the birthplace attribute

#           patient.update_attributes(params['patient'])
          person
        end

#       rescue => e
#         raise "somethig was not OK: #{e}; params:\n" + params.inspect
      end

      def remote_demographics_server
        @remote_demographics_server ||= RemoteDemographicsServer.new rescue nil
      end
    end # module ClassMethods

    module InstanceMethods
      # returns a hash representation of this user that can be sent to the dde server
      def remote_demographics
        { 'person' => {
            'data'            => self.demographics,
#             'version_number'  => self.remote_version_number,
            'created_at'      => self.created_at,
            'updated_at'      => self.updated_at,
#             'creator_id'      => self.creator_id,
#             'creator_site_id' => Site.current_id
          }
        }.merge(self.npid.try(:remote_attributes) || {}).merge(self.creator_site.try(:remote_attributes) || {})
      end

      def save_remote
        self.class.remote_demographics_server.push(self.national_id, self.demographics_from_local_db)
      end # def save_remote

      def without_update_to_remote
        unless self.update_from_remote_in_progress
          self.update_from_remote_in_progress = true
          yield self
          self.update_from_remote_in_progress = false
        end
      end

    end # module InstanceMethods
  end # module RemoteDemographics

end # class User
