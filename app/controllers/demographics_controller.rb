class DemographicyController < ApplicationController
  before_filter :load_patient

  def show
    @national_id = @patient.national_id_with_dashes
    @first_name  = @person.names.first.given_name
    @last_name   = @person.names.first.family_name
    @birthdate   = @person.birthdate_formatted
    @gender      = @person.gender

    @current_village  = @person.current_address.city_village
    @current_ta       = @person.current_address.county_district
    @current_district = @person.current_address.state_province
    @home_district    = @person.current_address.address2
    @primary_phone    = @person.get_attribute('Cell phone number')
    @secondary_phone  = @person.get_attribute('Home phone number')
    @occupation       = @person.get_attribute('Occupation')

    render :layout => 'menu'
  end

  def edit
    @field = params[:field]
    render :action => 'edit', :field => @field, :layout => true
  end

  def update
    @patient.update_demographics(params[:demographics])
    redirect_to :action => 'show', :patient_id => params['person_id']
  end

  protected

  def load_patient
    @patient = Patient.find(params[:patient_id] || params[:id] || session[:patient_id])
    @person  = @patient.person
  end

end
