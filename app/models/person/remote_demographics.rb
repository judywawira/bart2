class Person
  module RemoteDemographics

    def self.included(base)
      base.send :include, InstanceMethods
      base.send :extend, ClassMethods
    end

    module ClassMethods
      def find_remote_by_identifier(identifier)
        return nil unless self.remote_demographics_servers

        results = self.remote_demographics_servers.map do |server|
          server.query(identifier)
        end
        # TODO need better logic here to select the best result or merge them
        # Currently returning the longest result - assuming that it has the most information
        # Can't return multiple results because there will be redundant data from sites
        result = results.sort{|a,b| b.length <=> a.length}.first

        result ? JSON.parse(result) : nil
      end

      def find_remote(known_demographics)
        return nil unless self.remote_demographics_servers

        results = self.remote_demographics_servers.map do |server|
          server.query(known_demographics)
        end
        # TODO need better logic here to select the best result or merge them
        # Currently returning the longest result - assuming that it has the most information
        # Can't return multiple results because there will be redundant data from sites
        result = results.sort{|a,b| b.length <=> a.length}.first

        result ? JSON.parse(result) : nil
      end # def find_remote

      protected

      def remote_demographics_servers
        servers = GlobalProperty.find_by_property('remote_demographics_servers').try(:property_value)
        servers.blank? ? nil : servers.split(',').map{|name| RemoteDemographicsServer.new(name) }
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

