class UserController < ApplicationController

  def login
    if request.get?
      session[:user_id]=nil
    else
      @user=User.new(params[:user])
      logged_in_user=@user.try_to_login
      if logged_in_user
        reset_session
        session[:user_id] = logged_in_user.user_id
        session[:ip_address] = request.env['REMOTE_ADDR']         
        location = Location.find(params[:location]) rescue nil        
        location = Location.find_by_name(params[:location_name]) rescue nil unless params[:location_name].blank?
        flash[:error] = "Invalid Workstation Location" and return unless location
        #flash[:error] = "Location is not part of this health center" and return unless location.name.match(/Neno District Hospital/)
        session[:location_id] = nil
        session[:location_id] = location.id if location
        Location.current_location = location if location

        show_activites_property = CoreService.get_global_property_value("show_activities_after_login") rescue "false"
        if show_activites_property == "true"
          redirect_to(:action => "activities") 
        else                   
          redirect_to("/")
        end
      else
        flash[:error] = "Invalid username or password"
      end      
    end
  end          

  # List roles containing the string given in params[:value]
  def role
    valid_roles = CoreService.get_global_property_value("valid_roles") rescue nil
    role_conditions = ["role LIKE (?)", "%#{params[:value]}%"]
    role_conditions = ["role LIKE (?) AND role IN (?)",
                       "%#{params[:value]}%",
                       valid_roles.split(',')] if valid_roles
    roles = Role.find(:all,:conditions => role_conditions)
    roles = roles.map do |r|
      "<li value='#{r.role}'>#{r.role.gsub('_',' ').capitalize}</li>"
    end
    render :text => roles.join('') and return
  end

  def username
    users = User.find(:all,:conditions => ["username LIKE (?)","%#{params[:username]}%"])

    if params[:all_roles] and params[:all_roles] == '1'
      users = users.map{|u| "<li value='#{u.username}'>#{u.username}</li>" }
    else
      @users_with_provider_role = []
      users.each do |user|
        is_provider = UserRole.find_all_by_user_id(user.user_id).map(&:role).include?("Provider") rescue nil
        @users_with_provider_role << user if is_provider
      end
      users = @users_with_provider_role.map{| u | "<li value='#{u.username}'>#{u.username}</li>" }
    end

    render :text => users.join('') and return
  end
  
 def health_centres
     redirect_to(:controller => "patient", :action => "menu")
     @health_centres = Location.find(:all,  :order => "name").map{|r|[r.name, r.location_id]}
 end 
 
 def list_clinicians
 	@clinician_role = Role.find_by_role("clinician").id
 	@clinicians = UserRole.find_all_by_role_id(@clinician_role)
 end
  
  def logout
   #if time is 4 o'oclock then send report on logout. 
    reset_session
    redirect_to(:action => "login")
  end

  def signup
    render :text => "Please sign up"
  end

  def remind_password
  end

  def index
    @user=User.find(session[:user_id])
    @firstname=@user.first_name
    @secondName=@user.last_name
       
    list
    return render(:action => 'list')
  end
  
  # GETs should be safe (see http://www.w3.org/2001/tag/doc/whenToUseGet.html)
#  verify :method => :post, :only => [ :destroy, :create, :update ],
        # :redirect_to => { :action => :list }
        
  def voided_list
      session[:voided_list] = false 
    @user_pages, @users = paginate(:users, :per_page => 50,:conditions =>["voided=1"])
      render :view => 'list'
  end
  
  def list
    session[:voided_list] = true
    @user_pages, @users = paginate(:users, :per_page => 50,:conditions =>["voided=0"])
 end

  def show
    unless params[:id].blank?
     @user = User.find(params[:id])
    else
     @user = User.find(:first, :order => 'date_created DESC')
    end  
    render :layout => 'menu'
  end

  def new
    @user = User.new
  end

  def create
    session[:user_edit] = nil
    existing_user = User.find(:first, :conditions => {:username => params[:user][:username]}) rescue nil

    if existing_user
      flash[:notice] = 'Username already in use'
      redirect_to :action => 'new'
      return
    end
    if (params[:user][:password] != params[:user_confirm][:password])
      flash[:notice] = 'Password Mismatch'
      redirect_to :action => 'new'
      return
    #  flash[:notice] = nil
      @user_first_name = params[:person_name][:given_name]
#      @user_middle_name = params[:user][:middle_name]
      @user_last_name = params[:person_name][:family_name]
      @user_role = params[:user_role][:role_id]
      @user_admin_role = params[:user_role_admin][:role]
      @user_name = params[:user][:username]
    end

    person = Person.create()
    person.names.create(params[:person_name])
    params[:user][:user_id] = nil
    @user = User.new(params[:user])
    @user.person_id = person.id
    if @user.save
     # if params[:user_role_admin][:role] == "Yes"  
      #  @roles = Array.new.push params[:user_role][:role_id] 
       # @roles << "superuser"
       # @roles.each{|role|
       # user_role=UserRole.new
       # user_role.role_id = Role.find_by_role(role).role_id
       # user_role.user_id=@user.user_id
       # user_role.save
      #}
      #else
        user_role = UserRole.new
        user_role.role = Role.find_by_role(params[:user_role][:role_id])
        user_role.user_id = @user.user_id
        user_role.save
     # end
      @user.update_attributes(params[:user])
      flash[:notice] = 'User was successfully created.'
      redirect_to :action => 'show'
    else
      flash[:notice] = 'OOps! User was not created!.'
      render :action => 'new'
    end
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    #find_by_person_id(params[:id])
    @user = User.find(params[:id])

    username = params[:user]['username'] rescue current_user.username

    if username
      @user.update_attributes(:username => username)
    end

    PersonName.find(:all,:conditions =>["voided = 0 AND person_id = ?",@user.person_id]).each do | person_name |
      person_name.voided = 1
      person_name.voided_by = current_user.person_id
      person_name.date_voided = Time.now()
      person_name.void_reason = 'Edited name'
      person_name.save
    end rescue nil

    person_name = PersonName.new()
    person_name.family_name = params[:person_name]["family_name"]
    person_name.given_name = params[:person_name]["given_name"]
    person_name.person_id = @user.person_id
    person_name
    if person_name.save
      flash[:notice] = 'User was successfully updated.'
      redirect_to :action => 'show', :id => @user.id and return
    end rescue nil

    flash[:notice] = "OOps! User was not updated!."
    render :action => 'show', :id => @user.id
  end

  def destroy
   unless request.get?
   @user = User.find(params[:id])
    if @user.update_attributes(:voided => 1, :void_reason => params[:user][:void_reason],:voided_by => session[:user_id],:date_voided => Time.now.to_s)
      flash[:notice]='User has successfully been removed.'
      redirect_to :action => 'voided_list'
    else
      flash[:notice]='User was not successfully removed'
      redirect_to :action => 'destroy'
    end    
   end
  end

  def add_role
     @user = User.find(params[:id])
     unless request.get?
        user_role=UserRole.new
        user_role.role = Role.find_by_role(params[:user_role][:role_id])
        user_role.user_id=@user.user_id
        user_role.save
        flash[:notice] = "You have successfuly added the role of #{params[:user_role][:role_id]}"
        redirect_to :action => "show"
      else
      user_roles = UserRole.find_all_by_user_id(@user.user_id).collect{|ur|ur.role.role}
      all_roles = Role.find(:all).collect{|r|r.role}
      @roles = (all_roles - user_roles)
      @show_super_user = true if UserRole.find_all_by_user_id(@user.user_id).collect{|ur|ur.role.role != "superuser" }
   end
  end

  def delete_role
    @user = User.find(params[:id])
    unless request.post?
      @roles = UserRole.find_all_by_user_id(@user.user_id).collect{|ur|ur.role.role}
    else
      role = Role.find_by_role(params[:user_role][:role_id]).role
      user_role =  UserRole.find_by_role_and_user_id(role,@user.user_id)  
      user_role.destroy
      flash[:notice] = "You have successfuly removed the role of #{params[:user_role][:role_id]}"
      redirect_to :action =>"show"
    end
  end
  
  def user_menu
    render(:layout => "layouts/menu")
  end
 
  def search_user
   unless request.get?
     @user = User.find_by_username(params[:user][:username])
     redirect_to :action =>"show", :id => @user.id
   end
  end

  def change_password
    @user = User.find(params[:id])

    unless request.get? 
      if (params[:user][:password] != params[:user_confirm][:password])
        flash[:notice] = 'Password Mismatch'
        redirect_to :action => 'new'
        return
      else
        if @user.update_attributes(params[:user])
          flash[:notice] = "Password successfully changed"
          redirect_to :action => "show",:id => @user.id
          return
        else
          flash[:notice] = "Password change failed"
        end
      end
    end

  end

  def activities
    # Don't show tasks that have been disabled
    user_roles = UserRole.find(:all,:conditions =>["user_id = ?", current_user.id]).collect{|r|r.role}
    role_privileges = RolePrivilege.find(:all,:conditions => ["role IN (?)", user_roles])
    @privileges = Privilege.find(:all,:conditions => ["privilege IN (?)", role_privileges.collect{|r|r.privilege}])

    #raise @privileges.to_yaml

    @activities = current_user.activities.reject{|activity| 
      CoreService.get_global_property_value("disable_tasks").split(",").include?(activity)
    } rescue current_user.activities
   
    #raise @privileges.to_yaml
    encounter_privilege_hash = generate_encounter_privilege_map   
    @privileges = @privileges.collect do |privilege|
      if !encounter_privilege_hash[privilege.privilege.squish].nil?
          encounter_privilege_hash[privilege.privilege.squish].humanize
      else
          privilege.privilege
      end
    end
    
   #.gsub('Hiv','HIV') .gsub('Tb','TB').gsub('Art','ART').gsub('hiv','HIV')
   #.gsub('Hiv','HIV').gsub('Tb','TB').gsub('Art','ART').gsub('hiv','HIV')
    
    @encounter_types = EncounterType.find(:all).map{|enc|enc.name.gsub(/.*\//,"").gsub(/\..*/,"").humanize}
    @available_encounter_types = Dir.glob(RAILS_ROOT+"/app/views/encounters/*.rhtml").map{|file|file.gsub(/.*\//,"").gsub(/\..*/,"").humanize}
    @available_encounter_types -= @available_encounter_types - @encounter_types

    available_privileges_not_from_encounters_folder = []
    
    privileges_not_from_encounters_folder = ['Manage Prescriptions','Manage Appointments', 'Manage Drug Dispensations']
    
    available_privileges_not_from_encounters_folder += privileges_not_from_encounters_folder.select{|pri| @privileges.include?(pri)}

    @privileges =   @privileges - (@privileges - @available_encounter_types) + available_privileges_not_from_encounters_folder

    @activities = @activities.collect do |activity| 
      if !encounter_privilege_hash[activity].nil?
          encounter_privilege_hash[activity.squish].gsub('Hiv','HIV').gsub('Tb','TB').gsub('Art','ART').gsub('hiv','HIV')
      else
          activity.gsub('Hiv','HIV').gsub('Tb','TB').gsub('Art','ART').gsub('hiv','HIV')
      end
    end                            

    @privileges = @privileges.collect do |privilege|
        privilege.gsub('Hiv','HIV').gsub('Tb','TB').gsub('Art','ART').gsub('hiv','HIV')
    end
    #@privileges += ['Manage prescriptions','Manage appointments', 'Dispensation']  
    @privileges.sort!
    @patient_id = params[:patient_id]
  end
  
  def change_activities
    privilege_encounter_hash = generate_privilege_encounter_map
    
    params[:user][:activities] = params[:user][:activities].collect do |activity| 
      if !privilege_encounter_hash[activity.squish].nil?
          privilege_encounter_hash[activity.squish]
      else
          activity
      end
    end

    activities = params[:user][:activities]
    current_user.activities = params[:user][:activities]
    if params[:id]
      session_date = session[:datetime].to_date rescue Date.today
      redirect_to next_task(Patient.find(params[:id]))
      return 
    end
    redirect_to '/clinic'
  end
  
  def generate_encounter_privilege_map
      encounter_privilege_map = CoreService.get_global_property_value("encounter_privilege_map").to_s rescue ''
      encounter_privilege_map = encounter_privilege_map.split(",")
      encounter_privilege_hash = {}
      encounter_privilege_map.each do |encounter_privilege|
          encounter_privilege_hash[encounter_privilege.split(":").last.squish] = encounter_privilege.split(":").first.squish
      end
      encounter_privilege_hash
  end
  
  def generate_privilege_encounter_map
      encounter_privilege_map = CoreService.get_global_property_value("encounter_privilege_map").to_s rescue ''
      encounter_privilege_map = encounter_privilege_map.split(",")
      encounter_privilege_hash = {}
      encounter_privilege_map.each do |encounter_privilege|
          encounter_privilege_hash[encounter_privilege.split(":").first.squish.gsub('Hiv','HIV').gsub('Tb','TB').gsub('Art','ART').gsub('hiv','HIV')] = encounter_privilege.split(":").last.squish
      end
      encounter_privilege_hash
  end

  def properties
    if request.post?
      property = UserProperty.find(:first,                                                   
            :conditions =>["property = ? AND user_id = ?",'preferred.keyboard',       
            current_user.id])
      if property.blank?
        property = UserProperty.new()
        property.user_id = current_user.id
        property.property = 'preferred.keyboard'
        property.property_value = 'abc' if params[:property_value] == 'No'
        property.property_value = 'qwerty' if params[:property_value] == 'Yes'
        property.save
      else
        property.property_value = 'abc' if params[:property_value] == 'No'
        property.property_value = 'qwerty' if params[:property_value] == 'Yes'
        property.save
      end
      redirect_to '/clinic' and return
    end
  end
end
