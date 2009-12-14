class ApplicationController < ActionController::Base
  include AuthenticatedSystem

  helper :all
  helper_method :next_task
  helper_method :next_task_encounter_type
  filter_parameter_logging :password
  before_filter :login_required, :except => ['login', 'logout','demographics']
  before_filter :location_required, :except => ['login', 'logout', 'location','demographics']
  
  def rescue_action_in_public(exception)
    @message = exception.message
    @backtrace = exception.backtrace.join("\n") unless exception.nil?
    render :file => "#{RAILS_ROOT}/app/views/errors/error.rhtml", :layout=> false, :status => 404
  end if RAILS_ENV == 'development' || RAILS_ENV == 'test'

  def rescue_action(exception)
    @message = exception.message
    @backtrace = exception.backtrace.join("\n") unless exception.nil?
    render :file => "#{RAILS_ROOT}/app/views/errors/error.rhtml", :layout=> false, :status => 404
  end if RAILS_ENV == 'production'

  def next_task(patient)
    current_location_name = Location.current_location.name
    todays_encounters = patient.encounters.current.active.find(:all, :include => [:type]).map{|e| e.type.name}
    # Registration clerk needs to do registration if it hasn't happened yet
    return "/encounters/new/registration?patient_id=#{patient.id}" if current_location_name.match(/Registration/) && !todays_encounters.include?("REGISTRATION")
    # Everyone needs to do registration if it hasn't happened yet (this may be temporary)
    return "/encounters/new/registration?patient_id=#{patient.id}" if !todays_encounters.include?("REGISTRATION")
    # Sometimes we won't have a vitals stage, when we do we need to do it        
    return "/encounters/new/vitals?patient_id=#{patient.id}" if current_location_name.match(/Vitals/) && !todays_encounters.include?("VITALS")
    # Outpatient diagnosis needs outpatient diagnosis to be done!        
    return "/encounters/new/outpatient_diagnosis?patient_id=#{patient.id}" if current_location_name.match(/Outpatient/) && !todays_encounters.include?("OUTPATIENT DIAGNOSIS")
    # There may not be a treatment location, can we make this automatic for the clinic room?
    return "/encounters/new/treatment?patient_id=#{patient.id}" if current_location_name.match(/Treatment/) && !todays_encounters.include?("TREATMENT")
    # Everything seems to be done... show the dashboard
    return "/patients/show/#{patient.id}" 
  end

  def next_task_encounter_type(patient)
    current_location_name = Location.current_location.name
    todays_encounters = patient.encounters.current.active.find(:all, :include => [:type]).map{|e| e.type.name}
    # Registration clerk needs to do registration if it hasn't happened yet
    return EncounterType.find_by_name("REGISTRATION") if current_location_name.match(/Registration/) && !todays_encounters.include?("REGISTRATION")
    # Everyone needs to do registration if it hasn't happened yet (this may be temporary)
    return EncounterType.find_by_name("REGISTRATION") if !todays_encounters.include?("REGISTRATION")
    # Sometimes we won't have a vitals stage, when we do we need to do it        
    return EncounterType.find_by_name("VITALS") if current_location_name.match(/Vitals/) && !todays_encounters.include?("VITALS")
    # Outpatient diagnosis needs outpatient diagnosis to be done!        
    return EncounterType.find_by_name("DIAGNOSIS") if current_location_name.match(/Outpatient/) && !todays_encounters.include?("OUTPATIENT DIAGNOSIS")
    # There may not be a treatment location, can we make this automatic for the clinic room?
    return EncounterType.find_by_name("TREATMENT") if current_location_name.match(/Treatment/) && !todays_encounters.include?("TREATMENT")
    # Everything seems to be done... show the dashboard
    return nil 
  end

  def print_and_redirect(print_url, redirect_url, message = "Printing, please wait...")
    @print_url = print_url
    @redirect_url = redirect_url
    @message = message
    render :template => 'print/print', :layout => nil
  end
  
private

  def find_patient
    @patient = Patient.find(params[:patient_id] || session[:patient_id]) rescue nil
  end
  
end
