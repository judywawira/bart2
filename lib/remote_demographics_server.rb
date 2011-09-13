require 'rest_client'

class RemoteDemographicsServer

  attr_accessor :base_resource

  def initialize
    url      = GlobalProperty['remote_demographics.server']
    username = GlobalProperty['remote_demographics.user']
    password = GlobalProperty['remote_demographics.password']
    self.base_resource = RestClient::Resource.new(url, :user => username, :password => password)['people']
  end

  def query(id_or_attributes)
    case id_or_attributes
    when String
      resource = self.base_resource[id_or_attributes]
      result   = resource.get(:accept => :json)
      Rails.logger.info "GET #{resource} resulted in #{result}"
      result.blank? ? nil : JSON.parse(result)
    when Hash
      raise NotImplementedError
    else
      raise ArgumentError, 'Argument to RemoteDemographicsServer#query must be an ID (String) or a valid attribute Hash'
    end
  rescue RestClient::ResourceNotFound => e
    Rails.logger.error "FAILED fetching demographics data from remote: #{e}"
    nil
  rescue RestClient::InternalServerError => e
    Rails.logger.error "FAILED fetching demographics data from remote: #{e}"
    nil
  end

end
