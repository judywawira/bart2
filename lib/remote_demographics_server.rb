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
  rescue => e
    Rails.logger.error "FAILED fetching demographics data from remote: #{e}"
    nil
  end

  def push(national_id, demographics)
    payload = {
      'person' => {
            'data'            => demographics,
#             'version_number'  => self.remote_version_number,
#             'created_at'      => self.created_at,
#             'updated_at'      => self.updated_at,
#             'creator_id'      => self.creator_id,
#             'creator_site_id' => Site.current_id
      },
      'npid' => {
        'value' => national_id
      },
      'site' => {
        'id'   => 1,
        'code' => 'DUMMY',
        'name' => 'DUMMY'
      }
    }
    self.base_resource[id].put(payload, :accept => :json) do |response, request, status|
      case status
      when Net::HTTPOK
        true
      else
        raise status.inspect
      end
    end
#   rescue => e
#     Rails.logger.error "FAILED pushing demographics data to remote: #{e}"
#     false
  end

end
