require 'factory_girl'
Dir[File.join(RAILS_ROOT, 'test', 'factories', '**', '*')].each {|f| require f }

Before do
  # We need to load the shared metadata set of data
  database =  ActiveRecord::Base.connection.instance_variable_get("@config")[:database]
  `mysql -u root #{database} < #{File.join(RAILS_ROOT, 'db', 'openmrs_metadata.sql')}`
  `mysql -u root #{database} < #{File.join(RAILS_ROOT, 'db', 'data', 'nno', 'nno.sql')}`
  @user = Factory.create(:user, :username => 'admin', :plain_password => 'admin')
  @user.user_roles.create(:role => 'Informatics Manager')
end