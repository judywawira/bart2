class PeopleController < ApplicationController
  def index
    redirect_to '/clinic'
  end

  def new
    @occupations = Person.occupations
  end

  def identifiers
  end

  def create_remote
    person_params = {
      'gender'            => params[:patient][:gender],
      'occupation'        => params[:occupation],
      'age_estimate'      => params[:patient_age][:age_estimate],
      'cell_phone_number' => params[:cell_phone][:identifier],
      'birth_year'        => params[:patient_year],
      'birth_month'       => params[:patient_month],
      'birth_day'         => params[:patient_day],
      'addresses'         => {
        'address1'        => params[:p_address][:identifier],
        'address2'        => params[:p_address]['identifier'],
        'city_village'    => params[:patientaddress][:city_village],
        'county_district' => params[:birthplace]
      },
      'names'             => {
        'family_name'     => params[:patient_name][:family_name],
        'family_name2'    => 'Unknown',
        'given_name'      => params[:patient_name][:given_name]
      }
    }

    #raise person_params.to_yaml
    if User.current_user.blank?
      User.current_user = User.find(1) rescue []
    end

    if Location.current_location.blank?
      Location.current_location = Location.find(GlobalProperty.find_by_property('current_health_center_id').property_value) rescue []
    end

    person = Person.create_from_remote(person_params)
    if person
      patient = Patient.new
      patient.patient_id = person.id
      patient.save
      patient.national_id_label
    end
    #render :text => person.demographics.to_json
    render :text => person.remote_demographics.to_json
  end

  def demographics
    # Search by the demographics that were passed in and then return demographics
    people = Person.find_by_demographics(params)
    result = people.empty? ? {} : people.first.demographics
    render :text => result.to_json
  end
  
  def art_information
    national_id = params['person']['patient']['identifiers']['National id'] rescue nil
    art_info    = Patient.art_info_for_remote(national_id)
    render :text => art_info.to_json
  end
 
  def search
    found_person = nil

    if params[:identifier]
      local_results = Person.search_by_identifier(params[:identifier])
      if local_results.length > 1
        @people = Person.search(params)
      elsif local_results.length == 1
        found_person = local_results.first
      else
        # TODO - figure out how to write a test for this
        # This is sloppy - creating something as the result of a GET
        found_person = Person.find_remote_by_identifier(params[:identifier].split(' ').last)
      end

      if found_person
        #redirect_to search_complete_url(found_person.id, params[:relation]) and return
        redirect_to :action => 'confirm', :found_person_id => found_person.id, :relation => params[:relation] and return
      end
    end
    @people = Person.search(params)
  end
  
  def confirm
    if request.post?
      redirect_to search_complete_url(params[:found_person_id], params[:relation])
    else
      @found_person_id, @relation = params.values_at :found_person_id, :relation
      @person = Person.find(@found_person_id) rescue nil
      render :layout => 'menu'
    end
  end
 
  # This method is just to allow the select box to submit, we could probably do this better
  def select
    if params[:person] != '0' and Person.find(params[:person]).dead == 1
      redirect_to :controller => :patients, :action => :show, :id => params[:person]
    elsif params[:person].blank? or params[:person] == '0'
      redirect_to params.slice(:gender, :given_name, :family_name, :family_name2, :address2, :identifier, :relation).merge(:action => :new)
    else
      redirect_to search_complete_url(params[:person], params[:relation])
    end
  end
 
  def create
    Person.session_datetime = session[:datetime].to_date rescue Date.today
    person = Person.create_from_remote(params[:person])
    if params[:person][:patient]
      person.patient.national_id_label
      unless params[:relation].blank?
        redirect_to search_complete_url(person.id, params[:relation])
      else
        tb_session = (User.current_user.activities & ['Manage Lab Orders', 'Manage Lab Results', 'Manage Sputum Submissions', 'Manage TB Clinic Visits', 'Manage TB Reception Visits', 'Manage TB Registration Visits', 'Manage HIV Status Visits']).any?

        if use_filing_number and not tb_session
          person.patient.set_filing_number
          archived_patient = person.patient.patient_to_be_archived
          message = Patient.printing_message(person.patient, archived_patient, creating_new_patient = true)
          unless message.blank?
            print_and_redirect '/patients/filing_number_and_national_id?patient_id=%s' % person.id, next_task(person.patient), message, true, person.id
          else
            print_and_redirect '/patients/filing_number_and_national_id?patient_id=%s' % person.id, next_task(person.patient)
          end
        else
          print_and_redirect '/patients/national_id_label?patient_id=%s' % person.id, next_task(person.patient)
        end
      end
    else
      # Does this ever get hit?
      redirect_to :action => 'index'
    end
  end

  def set_datetime
    if request.post?
      unless [params[:set_day], params[:set_month], params[:set_year]].any?(&:blank?)
        # set for 1 second after midnight to designate it as a retrospective date
        date_of_encounter = Time.mktime(params[:set_year].to_i,
                                        params[:set_month].to_i,
                                        params[:set_day].to_i, 0, 0, 1)
        session[:datetime] = date_of_encounter #if date_of_encounter.to_date != Date.today
      end

      unless params[:id].blank?
        redirect_to next_task(Patient.find(params[:id])) 
      else
        redirect_to :action => 'index'
      end
    end
    @patient_id = params[:id]
  end

  def reset_datetime
    session[:datetime] = nil
    if params[:id].blank?
      redirect_to :action => 'index'
    else
      redirect_to "/patients/show/#{params[:id]}"
    end
  end

  def find_by_arv_number
    if request.post?
      redirect_to :action => 'search',
          :identifier => "#{PatientIdentifier.site_prefix} #{params[:arv_number]}"
    end
  end
  
  # List traditional authority containing the string given in params[:value]
  def traditional_authority
    district_id = District.find_by_name("#{params[:filter_value]}").id
    traditional_authority_conditions = ["name LIKE (?) AND district_id = ?", "#{params[:search_string]}%", district_id]

    traditional_authorities = TraditionalAuthority.all(:conditions => traditional_authority_conditions, :order => 'name')
    traditional_authorities = traditional_authorities.map do |t_a|
      "<li value='#{t_a.name}'>#{t_a.name}</li>"
    end
    render :text => traditional_authorities.join
  end

  # Regions containing the string given in params[:value]
  def region
    region_conditions = ['name LIKE (?)', "#{params[:value]}%"]

    regions = Region.all(:conditions => region_conditions, :order => 'name')
    regions = regions.map do |r|
      "<li value='#{r.name}'>#{r.name}</li>"
    end
    render :text => regions.join
  end

    # Districts containing the string given in params[:value]
  def district
    region_id = Region.find_by_name("#{params[:filter_value]}").id
    region_conditions = ['name LIKE (?) AND region_id = ?', "#{params[:search_string]}%", region_id]

    districts = District.all(:conditions => region_conditions, :order => 'name')
    districts = districts.map do |d|
      "<li value='#{d.name}'>#{d.name}</li>"
    end
    render :text => districts.join
  end

  def tb_initialization_district
    districts = District.find(:all, :order => 'name')
    districts = districts.map do |d|
      "<li value='#{d.name}'>#{d.name}</li>"
    end
    render :text => districts.join('') and return
  end

    # Villages containing the string given in params[:value]
  def village
    traditional_authority_id = TraditionalAuthority.find_by_name("#{params[:filter_value]}").id
    village_conditions = ['name LIKE (?) AND traditional_authority_id = ?', "#{params[:search_string]}%", traditional_authority_id]

    villages = Village.all(:conditions => village_conditions, :order => 'name')
    villages = villages.map do |v|
      "<li value='#{v.name}'>#{v.name}</li>"
    end
    render :text => villages.join
  end
  
  # Landmark containing the string given in params[:value]
  def landmark
    landmarks = PersonAddress.all(:select => 'DISTINCT address1' , :conditions => ['city_village = (?) AND address1 LIKE (?)', "#{params[:filter_value]}", "#{params[:search_string]}%"])
    landmarks = landmarks.map do |v|
      "<li value='#{v.address1}'>#{v.address1}</li>"
    end
    render :text => landmarks.join
  end

  private
  
  def search_complete_url(found_person_id, primary_person_id)
    unless (primary_person_id.blank?)
      # Notice this swaps them!
      new_relationship_url(:patient_id => primary_person_id, :relation => found_person_id)
    else
      url_for(:controller => :encounters, :action => :new, :patient_id => found_person_id)
    end
  end

end
 
