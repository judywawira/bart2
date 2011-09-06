require 'rest_client'

class RemoteDemographicsServer

  attr_accessor :base_resource

  def initialize(url)
    self.base_resource = RestClient::Resource.new(url)
  end

  def query(id_or_attributes)
    case id_or_attributes
    when String
      self.base_resource['people'][id_or_attributes].get(:accept => :json)
    when Hash
      raise NotImplementedError
    else
      raise ArgumentError, 'argument to RemoteDemographicsServer#query must be an ID (String) or a valid attribute Hash'
    end
  end

end
