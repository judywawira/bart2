class CohortToolController < ApplicationController

  def select
    @cohort_quarters  = [""]
    @report_type      = params[:report_type]
    @header 	        = params[:report_type] rescue ""
    @page_destination = ("/" + params[:dashboard].gsub("_", "/")) rescue ""

    if @report_type == "in_arv_number_range"
      @arv_number_start = params[:arv_number_start]
      @arv_number_end   = params[:arv_number_end]
    end

    start_date  = PatientService.initial_encounter.encounter_datetime rescue Date.today

    end_date    = Date.today

    @cohort_quarters  += Report.generate_cohort_quarters(start_date, end_date)
  end

  def reports
    session[:list_of_patients] = nil
    if params[:report]
      case  params[:report_type]
        when "visits_by_day"
          redirect_to :action   => "visits_by_day",
                      :name     => params[:report],
                      :pat_name => "Visits by day",
                      :quarter  => params[:report].gsub("_"," ")
        return

        when "non_eligible_patients_in_cohort"
          date = Report.generate_cohort_date_range(params[:report])

          redirect_to :action       => "non_eligible_patients_in_art",
                      :controller   => "report",
                      :start_date   => date.first.to_s,
                      :end_date     => date.last.to_s,
                      :id           => "start_reason_other",
                      :report_type  => "non_eligible patients in: #{params[:report]}"
        return

        when "out_of_range_arv_number"
          redirect_to :action           => "out_of_range_arv_number",
                      :arv_end_number   => params[:arv_end_number],
                      :arv_start_number => params[:arv_start_number],
                      :quarter          => params[:report].gsub("_"," "),
                      :report_type      => params[:report_type]
        return

        when "data_consistency_check"
          redirect_to :action       => "data_consistency_check",
                      :quarter      => params[:report],
                      :report_type  => params[:report_type]
        return

        when "summary_of_records_that_were_updated"
          redirect_to :action   => "records_that_were_updated",
                      :quarter  => params[:report].gsub("_"," ")
        return

        when "adherence_histogram_for_all_patients_in_the_quarter"
          redirect_to :action   => "adherence",
                      :quarter  => params[:report].gsub("_"," ")
        return

        when "patients_with_adherence_greater_than_hundred"
          redirect_to :action  => "patients_with_adherence_greater_than_hundred",
                      :quarter => params[:report].gsub("_"," ")
        return

        when "patients_with_multiple_start_reasons"
          redirect_to :action       => "patients_with_multiple_start_reasons",
                      :quarter      => params[:report],
                      :report_type  => params[:report_type]
        return

        when "dispensations_without_prescriptions"
          redirect_to :action       => "dispensations_without_prescriptions",
                      :quarter      => params[:report],
                      :report_type  => params[:report_type]
        return

        when "prescriptions_without_dispensations"
          redirect_to :action       => "prescriptions_without_dispensations",
                      :quarter      => params[:report],
                      :report_type  => params[:report_type]
        return

        when "drug_stock_report"
          start_date  = "#{params[:start_year]}-#{params[:start_month]}-#{params[:start_day]}"
          end_date    = "#{params[:end_year]}-#{params[:end_month]}-#{params[:end_day]}"

          if end_date.to_date < start_date.to_date
            redirect_to :controller   => "cohort_tool",
                        :action       => "select",
                        :report_type  =>"drug_stock_report" and return
          end rescue nil

          redirect_to :controller => "drug",
                      :action     => "report",
                      :start_date => start_date,
                      :end_date   => end_date,
                      :quarter    => params[:report].gsub("_"," ")
        return
      end
    end
  end

  def records_that_were_updated
    @quarter    = params[:quarter]

    date_range  = Report.generate_cohort_date_range(@quarter)
    @start_date = date_range.first
    @end_date   = date_range.last

    @encounters = records_that_were_corrected(@quarter)

    render :layout => false
  end

  def records_that_were_corrected(quarter)

    date        = Report.generate_cohort_date_range(quarter)
    start_date  = (date.first.to_s  + " 00:00:00")
    end_date    = (date.last.to_s   + " 23:59:59")

    voided_records = {}

    other_encounters = Encounter.find_by_sql("SELECT encounter.* FROM encounter
                        INNER JOIN obs ON encounter.encounter_id = obs.encounter_id
                        WHERE ((encounter.encounter_datetime BETWEEN '#{start_date}' AND '#{end_date}'))
                        GROUP BY encounter.encounter_id
                        ORDER BY encounter.encounter_type, encounter.patient_id")

    drug_encounters = Encounter.find_by_sql("SELECT encounter.* as duration FROM encounter
                        INNER JOIN orders ON encounter.encounter_id = orders.encounter_id
                        WHERE ((encounter.encounter_datetime BETWEEN '#{start_date}' AND '#{end_date}'))
                        ORDER BY encounter.encounter_type")

    voided_encounters = []
    other_encounters.delete_if { |encounter| voided_encounters << encounter if (encounter.voided == 1)}

    voided_encounters.map do |encounter|
      patient           = Patient.find(encounter.patient_id)
      patient_bean = PatientService.get_patient(patient.person)

      new_encounter  = other_encounters.reduce([])do |result, e|
        result << e if( e.encounter_datetime.strftime("%d-%m-%Y") == encounter.encounter_datetime.strftime("%d-%m-%Y")&&
                        e.patient_id      == encounter.patient_id &&
                        e.encounter_type  == encounter. encounter_type)
        result
      end

      new_encounter = new_encounter.last

      next if new_encounter.nil?

      voided_observations = voided_observations(encounter)
      changed_to    = changed_to(new_encounter)
      changed_from  = changed_from(voided_observations)

      if( voided_observations && !voided_observations.empty?)
          voided_records[encounter.id] = {
              "id"              => patient.patient_id,
              "arv_number"      => patient_bean.arv_number,
              "name"            => patient_bean.name,
              "national_id"     => patient_bean.national_id,
              "encounter_name"  => encounter.name,
              "voided_date"     => encounter.date_voided,
              "reason"          => encounter.void_reason,
              "change_from"     => changed_from,
              "change_to"       => changed_to
            }
      end
    end

    voided_treatments = []
    drug_encounters.delete_if { |encounter| voided_treatments << encounter if (encounter.voided == 1)}

    voided_treatments.each do |encounter|

      patient           = Patient.find(encounter.patient_id)
      patient_bean = PatientService.get_patient(patient.person)
      
      orders            = encounter.orders
      changed_from      = ''
      changed_to        = ''

     new_encounter  =  drug_encounters.reduce([])do |result, e|
        result << e if( e.encounter_datetime.strftime("%d-%m-%Y") == encounter.encounter_datetime.strftime("%d-%m-%Y")&&
                        e.patient_id      == encounter.patient_id &&
                        e.encounter_type  == encounter. encounter_type)
          result
        end

      new_encounter = new_encounter.last

      next if new_encounter.nil?
      changed_from  += "Treatment: #{voided_orders(new_encounter).to_s.gsub!(":", " =>")}</br>"
      changed_to    += "Treatment: #{encounter.to_s.gsub!(":", " =>") }</br>"

      if( orders && !orders.empty?)
        voided_records[encounter.id]= {
            "id"              => patient.patient_id,
            "arv_number"      => patient_bean.arv_number,
            "name"            => patient_bean.name,
            "national_id"     => patient_bean.national_id,
            "encounter_name"  => encounter.name,
            "voided_date"     => encounter.date_voided,
            "reason"          => encounter.void_reason,
            "change_from"     => changed_from,
            "change_to"       => changed_to
        }
      end

    end

    show_tabuler_format(voided_records)
  end

   def show_tabuler_format(records)

    patients = {}

    records.each do |key,value|

      sorted_values = sort(value)

      patients["#{key},#{value['id']}"] = sorted_values
    end

    patients
  end

  def sort(values)
    name              = ''
    patient_id        = ''
    arv_number        = ''
    national_id       = ''
    encounter_name    = ''
    voided_date       = ''
    reason            = ''
    obs_names         = ''
    changed_from_obs  = {}
    changed_to_obs    = {}
    changed_data      = {}

    values.each do |value|
      value_name =  value.first
      value_data =  value.last

      case value_name
        when "id"
          patient_id = value_data
        when "arv_number"
          arv_number = value_data
        when "name"
          name = value_data
        when "national_id"
          national_id = value_data
        when "encounter_name"
          encounter_name = value_data
        when "voided_date"
          voided_date = value_data
        when "reason"
          reason = value_data
        when "change_from"
          value_data.split("</br>").each do |obs|
            obs_name  = obs.split(':')[0].strip
            obs_value = obs.split(':')[1].strip rescue ''

            changed_from_obs[obs_name] = obs_value
          end unless value_data.blank?
        when "change_to"

          value_data.split("</br>").each do |obs|
            obs_name  = obs.split(':')[0].strip
            obs_value = obs.split(':')[1].strip rescue ''

            changed_to_obs[obs_name] = obs_value
          end unless value_data.blank?
      end
    end

    changed_from_obs.each do |a,b|
      changed_to_obs.each do |x,y|

        if (a == x)
          next if b == y
          changed_data[a] = "#{b} to #{y}"

          changed_from_obs.delete(a)
          changed_to_obs.delete(x)
        end
      end
    end

    changed_to_obs.each do |a,b|
      changed_from_obs.each do |x,y|
        if (a == x)
          next if b == y
          changed_data[a] = "#{b} to #{y}"

          changed_to_obs.delete(a)
          changed_from_obs.delete(x)
        end
      end
    end

    changed_data.each do |k,v|
      from  = v.split("to")[0].strip rescue ''
      to    = v.split("to")[1].strip rescue ''

      if obs_names.blank?
        obs_names = "#{k}||#{from}||#{to}||#{voided_date}||#{reason}"
      else
        obs_names += "</br>#{k}||#{from}||#{to}||#{voided_date}||#{reason}"
      end
    end

    results = {
        "id"              => patient_id,
        "arv_number"      => arv_number,
        "name"            => name,
        "national_id"     => national_id,
        "encounter_name"  => encounter_name,
        "voided_date"     => voided_date,
        "obs_name"        => obs_names,
        "reason"          => reason
      }

    results
  end

  def changed_from(observations)
    changed_obs = ''

    observations.collect do |obs|
      ["value_coded","value_datetime","value_modifier","value_numeric","value_text"].each do |value|
        case value
          when "value_coded"
            next if obs.value_coded.blank?
            changed_obs += "#{obs.to_s}</br>"
          when "value_datetime"
            next if obs.value_datetime.blank?
            changed_obs += "#{obs.to_s}</br>"
          when "value_numeric"
            next if obs.value_numeric.blank?
            changed_obs += "#{obs.to_s}</br>"
          when "value_text"
            next if obs.value_text.blank?
            changed_obs += "#{obs.to_s}</br>"
          when "value_modifier"
            next if obs.value_modifier.blank?
            changed_obs += "#{obs.to_s}</br>"
        end
      end
    end

    changed_obs.gsub("00:00:00 +0200","")[0..-6]
  end

  def changed_to(enc)
    encounter_type = enc.encounter_type

    encounter = Encounter.find(:first,
                 :joins       => "INNER JOIN obs ON encounter.encounter_id=obs.encounter_id",
                 :conditions  => ["encounter_type=? AND encounter.patient_id=? AND Date(encounter.encounter_datetime)=?",
                                  encounter_type,enc.patient_id, enc.encounter_datetime.to_date],
                 :group       => "encounter.encounter_type",
                 :order       => "encounter.encounter_datetime DESC")

    observations = encounter.observations rescue nil
    return if observations.blank?

    changed_obs = ''
    observations.collect do |obs|
      ["value_coded","value_datetime","value_modifier","value_numeric","value_text"].each do |value|
        case value
          when "value_coded"
            next if obs.value_coded.blank?
            changed_obs += "#{obs.to_s}</br>"
          when "value_datetime"
            next if obs.value_datetime.blank?
            changed_obs += "#{obs.to_s}</br>"
          when "value_numeric"
            next if obs.value_numeric.blank?
            changed_obs += "#{obs.to_s}</br>"
          when "value_text"
            next if obs.value_text.blank?
            changed_obs += "#{obs.to_s}</br>"
          when "value_modifier"
            next if obs.value_modifier.blank?
            changed_obs += "#{obs.to_s}</br>"
        end
      end
    end

    changed_obs.gsub("00:00:00 +0200","")[0..-6]
  end

  def visits_by_day
    @quarter    = params[:quarter]

    date_range          = Report.generate_cohort_date_range(@quarter)
    @start_date         = date_range.first
    @end_date           = date_range.last
    visits              = get_visits_by_day(@start_date.beginning_of_day, @end_date.end_of_day)
    @patients           = visiting_patients_by_day(visits)
    @visits_by_day      = visits_by_week(visits)
    @visits_by_week_day = visits_by_week_day(visits)

    render :layout => false
  end

  def visits_by_week(visits)

    visits_by_week = visits.inject({}) do |week, visit|

      day       = visit.encounter_datetime.strftime("%a")
      beginning = visit.encounter_datetime.beginning_of_week.to_date

      # add a new week
      week[beginning] = {day => []} if week[beginning].nil?

      #add a new visit to the week
      (week[beginning][day].nil?) ? week[beginning][day] = [visit] : week[beginning][day].push(visit)

      week
    end

    return visits_by_week
  end

  def visits_by_week_day(visits)
    week_day_visits = {}
    visits          = visits_by_week(visits)
    weeks           = visits.keys.sort
    week_days       = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    week_days.each_with_index do |day, index|
      weeks.map do  |week|
        visits_number = 0
        visit_date    = week.to_date.strftime("%d-%b-%Y")
        js_date       = week.to_time.to_i * 1000
        this_day      = visits[week][day]


        unless this_day.nil?
          visits_number = this_day.count
          visit_date    = this_day.first.encounter_datetime.to_date.strftime("%d-%b-%Y")
          js_date       = this_day.first.encounter_datetime.to_time.to_i * 1000
        else
        this_day      = (week.to_date + index.days)
        visit_date    = this_day.strftime("%d-%b-%Y")
        js_date       = this_day.to_time.to_i * 1000
        end

        (week_day_visits[day].nil?) ? week_day_visits[day] = [[js_date, visits_number, visit_date]] : week_day_visits[day].push([js_date, visits_number, visit_date])
      end
    end
    week_day_visits
  end

  def visiting_patients_by_day(visits)

    patients = visits.inject({}) do |patient, visit|

      visit_date = visit.encounter_datetime.strftime("%d-%b-%Y")

	  patient_bean = PatientService.get_patient(visit.patient.person)
	  
      # get a patient of a given visit
      new_patient   = { :patient_id   => (visit.patient.patient_id || ""),
                        :arv_number   => (patient_bean.arv_number || ""),
                        :name         => (patient_bean.name || ""),
                        :national_id  => (patient_bean.national_id || ""),
                        :gender       => (patient_bean.sex || ""),
                        :age          => (patient_bean.age || ""),
                        :birthdate    => (patient_bean.birth_date || ""),
                        :phone_number => (PatientService.phone_numbers(visit.patient) || ""),
                        :start_date   => (visit.patient.encounters.last.encounter_datetime.strftime("%d-%b-%Y") || "")
      }

      #add a patient to the day
      (patient[visit_date].nil?) ? patient[visit_date] = [new_patient] : patient[visit_date].push(new_patient)

      patient
    end

    patients
  end

  def get_visits_by_day(start_date,end_date)
    required_encounters = ["ART ADHERENCE", "ART_FOLLOWUP",   "ART_INITIAL",
                           "ART VISIT",     "HIV RECEPTION",  "HIV STAGING",
                           "PART_FOLLOWUP", "PART_INITIAL",   "VITALS"]

    required_encounters_ids = required_encounters.inject([]) do |encounters_ids, encounter_type|
      encounters_ids << EncounterType.find_by_name(encounter_type).id rescue nil
      encounters_ids
    end

    required_encounters_ids.sort!

    Encounter.find(:all,
      :joins      => ["INNER JOIN obs     ON obs.encounter_id    = encounter.encounter_id",
                      "INNER JOIN patient ON patient.patient_id  = encounter.patient_id"],
      :conditions => ["obs.voided = 0 AND encounter_type IN (?) AND encounter_datetime >=? AND encounter_datetime <=?",required_encounters_ids,start_date,end_date],
      :group      => "encounter.patient_id,DATE(encounter_datetime)",
      :order      => "encounter.encounter_datetime ASC")
  end

  def prescriptions_without_dispensations
      include_url_params_for_back_button

      date_range  = Report.generate_cohort_date_range(params[:quarter])
      start_date  = date_range.first.beginning_of_day.strftime("%Y-%m-%d %H:%M:%S")
      end_date    = date_range.last.end_of_day.strftime("%Y-%m-%d %H:%M:%S")
      @report     = report_prescriptions_without_dispensations_data(start_date , end_date)

      render :layout => 'report'
  end
  
  def  dispensations_without_prescriptions
       include_url_params_for_back_button

      date_range  = Report.generate_cohort_date_range(params[:quarter])
      start_date  = date_range.first.beginning_of_day.strftime("%Y-%m-%d %H:%M:%S")
      end_date    = date_range.last.end_of_day.strftime("%Y-%m-%d %H:%M:%S")
      @report     = report_dispensations_without_prescriptions_data(start_date , end_date)

       render :layout => 'report'
  end
  
  def  patients_with_multiple_start_reasons
       include_url_params_for_back_button

      date_range  = Report.generate_cohort_date_range(params[:quarter])
      start_date  = date_range.first.beginning_of_day.strftime("%Y-%m-%d %H:%M:%S")
      end_date    = date_range.last.end_of_day.strftime("%Y-%m-%d %H:%M:%S")
      @report     = report_patients_with_multiple_start_reasons(start_date , end_date)

      render :layout => 'report'
  end
  
  def out_of_range_arv_number

      include_url_params_for_back_button

      date_range        = Report.generate_cohort_date_range(params[:quarter])
      start_date  = date_range.first.beginning_of_day.strftime("%Y-%m-%d %H:%M:%S")
      end_date    = date_range.last.end_of_day.strftime("%Y-%m-%d %H:%M:%S")
      arv_number_range  = [params[:arv_start_number].to_s.gsub(/[^0-9]/,'').to_i, params[:arv_end_number].to_s.gsub(/[^0-9]/,'').to_i]

      @report = report_out_of_range_arv_numbers(arv_number_range, start_date, end_date)

      render :layout => 'report'
  end
  
  def data_consistency_check
      include_url_params_for_back_button
      date_range  = Report.generate_cohort_date_range(params[:quarter])
      start_date  = date_range.first.beginning_of_day.strftime("%Y-%m-%d %H:%M:%S")
      end_date    = date_range.last.end_of_day.strftime("%Y-%m-%d %H:%M:%S")

      @dead_patients_with_visits       = report_dead_with_visits(start_date, end_date)
      @males_allegedly_pregnant        = report_males_allegedly_pregnant(start_date, end_date)
      @move_from_second_line_to_first =  report_patients_who_moved_from_second_to_first_line_drugs(start_date, end_date)
      @patients_with_wrong_start_dates = report_with_drug_start_dates_less_than_program_enrollment_dates(start_date, end_date)
      session[:data_consistency_check] = { :dead_patients_with_visits => @dead_patients_with_visits,
                                           :males_allegedly_pregnant  => @males_allegedly_pregnant,
                                           :patients_with_wrong_start_dates => @patients_with_wrong_start_dates,
                                           :move_from_second_line_to_first =>  @move_from_second_line_to_first
                                         }
      @checks = [['Dead patients with visits', @dead_patients_with_visits.length],
                 ['Male patients with a pregnant observation', @males_allegedly_pregnant.length],
                 ['Patients who moved from 2nd to 1st line drugs', @move_from_second_line_to_first.length],
                 ['patients with start dates > first receive drug dates', @patients_with_wrong_start_dates.length]]
      render :layout => 'report'
  end
  
  def list
    @report = []
    include_url_params_for_back_button

    case params[:check_type]
       when 'Dead patients with visits' then
            @report  =  session[:data_consistency_check][:dead_patients_with_visits]
       when 'Patients who moved from 2nd to 1st line drugs'then
             @report =  session[:data_consistency_check][:move_from_second_line_to_first]
       when 'Male patients with a pregnant observation' then
             @report =  session[:data_consistency_check][:males_allegedly_pregnant]
       when 'patients with start dates > first receive drug dates' then
             @report =  session[:data_consistency_check][:patients_with_wrong_start_dates]
       else

    end

    render :layout => 'report'
  end
  
  def list_patients_details
    @report = []
    include_url_params_for_back_button

    @quarter = params[:quarter]
    start_date,end_date = Report.generate_cohort_date_range(@quarter)
    cohort = Cohort.new(start_date,end_date)

    @first_registration_date = cohort.first_registration_date

    #populating start regimens
    regimens = []
    regimens = cohort.regimens_with_patient_ids(@first_registration_date)

    @regimen_1_a = []; @regimen_1_p = []; @regimen_2_a = []; @regimen_2_p = []
    @regimen_3_a = []; @regimen_3_p = []; @regimen_4_a = []; @regimen_4_p = []
    @regimen_5_a = []; @regimen_5_p = []; @regimen_6_a = []; @regimen_6_p = []
    @regimen_7_a = []; @regimen_7_p = []; @regimen_8_a = []; @regimen_8_p = []
    @regimen_9_a = []; @regimen_9_p = []; @unknown_arv_regimen = []

    regimens.map do |regimen|
      if regimen.regimen.include?('d4T/3TC/NVP')
        if regimen.person_age_at_drug_dispension.to_i > 14
          @regimen_1_a << regimen.patient_id
        else
          @regimen_1_p << regimen.patient_id
        end
      elsif regimen.regimen.include?('d4T/3TC + d4T/3TC/NVP (Starter pack)')
        if regimen.person_age_at_drug_dispension.to_i > 14
          @regimen_1_a << regimen.patient_id
        else
          @regimen_1_p << regimen.patient_id
        end
      elsif regimen.regimen.include?('AZT/3TC/NVP')
        if regimen.person_age_at_drug_dispension.to_i > 14
          @regimen_2_a << regimen.patient_id
        else
          @regimen_2_p << regimen.patient_id
        end
      elsif regimen.regimen.include?('AZT/3TC + AZT/3TC/NVP (Starter pack)')
        if regimen.person_age_at_drug_dispension.to_i > 14
          @regimen_2_a << regimen.patient_id
        else
          @regimen_2_p << regimen.patient_id
        end
      elsif regimen.regimen.include?("d4T/3TC/EFV")
        if regimen.person_age_at_drug_dispension.to_i > 14
          @regimen_3_a << regimen.patient_id
        else
          @regimen_3_p << regimen.patient_id
        end
      elsif regimen.regimen.include?('AZT/3TC+EFV')
        if regimen.person_age_at_drug_dispension.to_i > 14
          @regimen_4_a << regimen.patient_id
        else
          @regimen_4_p << regimen.patient_id
        end
      elsif regimen.regimen.include?('TDF/3TC/EFV')
        if regimen.person_age_at_drug_dispension.to_i > 14
          @regimen_5_a << regimen.patient_id
        else
          @regimen_5_p << regimen.patient_id
        end
      elsif regimen.regimen.include?('TDF/3TC+NVP')
        if regimen.person_age_at_drug_dispension.to_i > 14
          @regimen_6_a << regimen.patient_id
        else
          @regimen_6_p << regimen.patient_id
        end
      elsif regimen.regimen.include?('TDF/3TC+LPV/r')
        if regimen.person_age_at_drug_dispension.to_i > 14
          @regimen_7_a << regimen.patient_id
        else
          @regimen_7_p << regimen.patient_id
        end
      elsif regimen.regimen.include?('AZT/3TC+LPV/r')
        if regimen.person_age_at_drug_dispension.to_i > 14
          @regimen_8_a << regimen.patient_id
        else
          @regimen_8_p << regimen.patient_id
        end
      elsif regimen.regimen.include?('ABC/3TC+LPV/r')
        if regimen.person_age_at_drug_dispension.to_i > 14
          @regimen_9_a << regimen.patient_id
        else
          @regimen_9_p << regimen.patient_id
        end
      else
        @unknown_arv_regimen << regimen.patient_id
      end
    end

    #populating tb_status
    tb_status = []
    tb_status = cohort.tb_status_with_patient_ids

    @tb_not_suspected = []; @tb_suspected = []; @confirmed_tb_on_treatment = []
    @confirmed_tb_not_on_treatment = []; @unknown_tb_status = []

    tb_status = []
    tb_status = cohort.tb_status_with_patient_ids

    tb_status.each do  |status|
      if status.tbstatus == 'TB NOT SUSPECTED' or status.tbstatus == 'noSusp' or status.tbstatus == 'noSup' or status.tbstatus == 'TB not suspected' or status.tbstatus == 'TB NOT suspected' or status.tbstatus == 'Nosup'
        @tb_not_suspected << status.patient_id
      
      elsif status.tbstatus == 'TB SUSPECTED' or status.tbstatus == 'susp' or status.tbstatus == 'sup' or status.tbstatus == 'TB suspected' or status.tbstatus == 'Tb suspected'
        @tb_suspected << status.patient_id
      
      elsif status.tbstatus == 'RX' or status.tbstatus == 'CONFIRMED TB ON TREATMENT' or status.tbstatus == 'Rx' or status.tbstatus == 'CONFIRMED TB ON TREATMENT' or status.tbstatus == 'Confirmed TB on treatment' or status.tbstatus == 'Confirmed TB on treatment' or status.tbstatus == 'Norx'
        @confirmed_tb_on_treatment << status.patient_id
      
      elsif status.tbstatus == 'noRX' or status.tbstatus == 'CONFIRMED TB NOT ON TREATMENT' or status.tbstatus =='Confirmed TB not on treatment' or status.tbstatus == 'Confirmed TB NOT on treatment'
        @confirmed_tb_not_on_treatment << status.patient_id
      
      else
        @unknown_tb_status << status.patient_id
      end
    end

    #populating start reasons
    newly_registered_start_reasons = []
    total_registered_start_reasons = []
    
    newly_registered_start_reasons = cohort.start_reason(start_date,end_date)

    @presumed_severe_HIV_disease_in_infants = []; @confirmed_HIV_infection_in_infants = []
    @who_stage_1_or_2_cd4_below_threshold = []; @who_stage_2_total_lymphocytes = []
    @who_stage_3 = []; @who_stage_4 = []; @patient_pregnant = []; @patient_breastfeeding = []
    @hiv_infected = []; @Unknown_reason = []

    newly_registered_start_reasons.each do  |reason|
      if reason.name.include?('Presumed')
        @presumed_severe_HIV_disease_in_infants << reason.patient_id
      elsif reason.name.include?('Confirmed')
        @confirmed_HIV_infection_in_infants << reason.patient_id
      elsif reason.name[0..11].strip.upcase == 'WHO STAGE I' or reason.name.match(/CD/i)
        @who_stage_1_or_2_cd4_below_threshold << reason.patient_id
      elsif reason.name[0..12].strip.upcase == 'WHO STAGE II' or reason.name.match(/lymphocytes/i) or reason.name.match(/LYMPHOCYTE/i)
        @who_stage_2_total_lymphocytes << reason.patient_id
      elsif reason.name[0..13].strip.upcase == 'WHO STAGE III'
        @who_stage_3 << reason.patient_id
      elsif reason.name[0..11].strip.upcase == 'WHO STAGE IV'
        @who_stage_4 << reason.patient_id
      elsif reason.name.strip.humanize == 'Patient pregnant'
        @patient_pregnant << reason.patient_id
     elsif reason.name.match(/Breastfeeding/i)
        @patient_breastfeeding << reason.patient_id
      elsif reason.name.strip.upcase == 'HIV INFECTED'
        @hiv_infected << reason.patient_id
      else 
        @Unknown_reason << reason.patient_id
      end
    end

    @total_presumed_severe_HIV_disease_in_infants = []
    @total_confirmed_HIV_infection_in_infants = []
    @total_who_stage_1_or_2_cd4_below_threshold = []
    @total_who_stage_2_total_lymphocytes = []
    @total_who_stage_3 = []
    @total_who_stage_4 = []
    @total_patient_pregnant = []
    @total_patient_breastfeeding = []
    @total_hiv_infected = [] 
    @total_unknown_reason = []

    total_registered_start_reasons = cohort.start_reason(@first_registration_date,end_date)

    total_registered_start_reasons.each do  |reason|
      if reason.name.include?('Presumed')
        @total_presumed_severe_HIV_disease_in_infants << reason.patient_id
      elsif reason.name.include?('Confirmed')
        @total_confirmed_HIV_infection_in_infants << reason.patient_id
      elsif reason.name[0..11].strip.upcase == 'WHO STAGE I' or reason.name.match(/CD/i)
        @total_who_stage_1_or_2_cd4_below_threshold << reason.patient_id
      elsif reason.name[0..12].strip.upcase == 'WHO STAGE II' or reason.name.match(/lymphocytes/i) or reason.name.match(/LYMPHOCYTE/i)
        @total_who_stage_2_total_lymphocytes << reason.patient_id
      elsif reason.name[0..13].strip.upcase == 'WHO STAGE III'
        @total_who_stage_3 << reason.patient_id
      elsif reason.name[0..11].strip.upcase == 'WHO STAGE IV'
        @total_who_stage_4 << reason.patient_id
      elsif reason.name.strip.humanize == 'Patient pregnant'
        @total_patient_pregnant << reason.patient_id
      elsif reason.name.match(/Breastfeeding/i)
        @total_patient_breastfeeding << reason.patient_id
      elsif reason.name.strip.upcase == 'HIV INFECTED'
        @total_hiv_infected << reason.patient_id
      else 
        @total_unknown_reason << reason.patient_id
      end
    end

    #populating the death_dates
    @first_month = [] ; @second_month = [] ; @third_month = [] ; @after_third_month = []
    @death_dates = []
    @death_dates = cohort.death_dates(@first_registration_date, start_date)

    if !@death_dates[0].empty?
      @death_dates[0].each do |patient|
        @first_month << patient
      end
    end

    if !@death_dates[1].empty?
      @death_dates[1].each do |patient|
        @second_month << patient
      end
    end

    if !@death_dates[2].empty?
      @death_dates[2].each do |patient|
        @third_month << patient
      end
    end

    if !@death_dates[3].empty?
      @death_dates[3].each do |patient|
        @after_third_month << patient
      end
    end

    @total_first_month = [] ; @total_second_month = [] ; @total_third_month = [] ; @total_after_third_month = []
    @total_death_dates = []
    @death_dates = cohort.death_dates(@first_registration_date, end_date)

    if !@death_dates[0].empty?
      @death_dates[0].each do |patient|
        @total_first_month << patient
      end
    end

    if !@death_dates[1].empty?
      @death_dates[1].each do |patient|
        @total_second_month << patient
      end
    end

    if !@death_dates[2].empty?
      @death_dates[2].each do |patient|
        @total_third_month << patient
      end
    end

    if !@death_dates[3].empty?
      @death_dates[3].each do |patient|
        @total_after_third_month << patient
      end
    end

    #populating the @report with patient's details on each and every link
    case params[:field]
      when 'newly_total_registered' then
        newly_registered_patients = []

        newly_registered_patients = cohort.total_registered_patient_ids
        
        newly_registered_patients.each do |patient_id|
          patient = Patient.find_by_patient_id(patient_id.patient_id)
          @report << PatientService.get_patient(patient.person) 
        end
      when 'total_registered' then
        total_registered_patients = []

        total_registered_patients = cohort.total_registered_patient_ids(@first_registration_date)

        total_registered_patients.each do |patient_id|
          patient = Patient.find_by_patient_id(patient_id.patient_id)
          @report << PatientService.get_patient(patient.person) 
        end
      when 'newly_registered_patients_initiated_on_art_first_time' then
        patients_initiated_on_art_first_time = []
    
        patients_initiated_on_art_first_time = cohort.patients_initiated_on_art_first_time
        
        patients_initiated_on_art_first_time.each do |patient_id|
          patient = Patient.find_by_patient_id(patient_id.patient_id)
          @report << PatientService.get_patient(patient.person) 
        end
      when 'total_registered_patients_initiated_on_art_first_time' then
        patients_initiated_on_art_first_time = []

        patients_initiated_on_art_first_time = cohort.patients_initiated_on_art_first_time(@first_registration_date)
        
        patients_initiated_on_art_first_time.each do |patient_id|
          patient = Patient.find_by_patient_id(patient_id.patient_id)
          @report << PatientService.get_patient(patient.person) 
        end     
      when 'newly_registered_male_all_ages' then
        men_all_ages = []

        men_all_ages = cohort.total_registered_by_gender_age(start_date,end_date,"M")
        men_all_ages.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_registered_male_all_ages' then
        men_all_ages = []

        men_all_ages = cohort.total_registered_by_gender_age(@first_registration_date,end_date,'M')

        men_all_ages.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'newly_registered_pregnant_females_all_ages' then
        pregnant_women_all_ages = []
        pregnant_women_all_ages = cohort.pregnant_women(start_date,end_date)

        pregnant_women_all_ages.each do |patient_id|
          patient = Patient.find_by_patient_id(patient_id.patient_id)
          @report << PatientService.get_patient(patient.person) 
        end
      when 'total_registered_pregnant_females_all_ages' then
        pregnant_women_all_ages = []
        pregnant_women_all_ages = cohort.pregnant_women(@first_registration_date,end_date)

        pregnant_women_all_ages.each do |patient_id|
          patient = Patient.find_by_patient_id(patient_id.patient_id)
          @report << PatientService.get_patient(patient.person) 
        end
      when 'newly_registered_non_pregnant_females_all_ages' then
        non_pregnant_women_all_ages = []

        non_pregnant_women_all_ages = cohort.non_pregnant_women(start_date,end_date)
        non_pregnant_women_all_ages.each do |patient_id|
          patient = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient.person) 
        end
      when 'total_registered_non_pregnant_females_all_ages' then
        non_pregnant_women_all_ages = []

        non_pregnant_women_all_ages = cohort.non_pregnant_women(@first_registration_date,end_date)
        non_pregnant_women_all_ages.each do |patient_id|
          patient = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient.person) 
        end
      when 'newly_registered_infants' then
        newly_registered_infants = []

        newly_registered_infants = cohort.total_registered_by_gender_age(start_date,end_date,nil,0,1.5)
        newly_registered_infants.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_registered_infants' then
        total_registered_infants = []

        total_registered_infants = cohort.total_registered_by_gender_age(@first_registration_date,end_date,nil,0,1.5)
        total_registered_infants.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'newly_registered_children' then
        newly_registered_children = []

        newly_registered_children = cohort.total_registered_by_gender_age(start_date,end_date,nil,1.5,14)
        newly_registered_children.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_registered_children' then
        total_registered_children = []

        total_registered_children = cohort.total_registered_by_gender_age(@first_registration_date,end_date,nil,1.5,14)
        total_registered_children.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'newly_registered_adults' then
        newly_registered_adults = []

        newly_registered_adults = cohort.total_registered_by_gender_age(start_date,end_date,nil,14,300)
        newly_registered_adults.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_registered_adults' then
        total_registered_adults = []

        total_registered_adults = cohort.total_registered_by_gender_age(start_date,end_date,nil,14,300)
        total_registered_adults.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'presumed_severe_hiv_disease_in_infants' then
         @presumed_severe_HIV_disease_in_infants.each do |patient_id|
           patient_obj = Patient.find_by_patient_id(patient_id)
           @report << PatientService.get_patient(patient_obj.person) 
         end
      when 'total_presumed_severe_hiv_disease_in_infants' then
         @total_presumed_severe_HIV_disease_in_infants.each do |patient_id|
           patient_obj = Patient.find_by_patient_id(patient_id)
           @report << PatientService.get_patient(patient_obj.person) 
         end
      when 'confirmed_hiv_infection_in_infants' then
        @confirmed_HIV_infection_in_infants.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_confirmed_hiv_infection_in_infants' then
        @total_confirmed_HIV_infection_in_infants.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'who_stage_1_or_2_cd4_below_threshold' then
        @who_stage_1_or_2_cd4_below_threshold.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_who_stage_1_or_2_cd4_below_threshold' then
        @total_who_stage_1_or_2_cd4_below_threshold.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'who_stage_2_total_lymphocytes' then
        @who_stage_2_total_lymphocytes.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_who_stage_2_total_lymphocytes' then
        @total_who_stage_2_total_lymphocytes.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'who_stage_3' then
        @who_stage_3.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_who_stage_3' then
        @total_who_stage_3.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'who_stage_4' then
        @who_stage_4.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_who_stage_4' then
        @total_who_stage_4.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'patient_pregnant' then
        @patient_pregnant.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_patient_pregnant' then
        @total_patient_pregnant.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'patient_breastfeeding' then
        @patient_breastfeeding.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_patient_breastfeeding' then
        @total_patient_breastfeeding.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_hiv_infected' then
        @total_hiv_infected.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'unknown_reason' then
        @Unknown_reason.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'tb_not_suspected' then
        @tb_not_suspected.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'tb_suspected' then
        @tb_suspected.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'confirmed_tb_on_treatment' then
        @confirmed_tb_on_treatment.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'confirmed_tb_not_on_treatment' then
        @confirmed_tb_not_on_treatment.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'unknown_tb_status' then
        @unknown_tb_status.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'ARV_regimen_1A' then
        @regimen_1_a.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'ARV_regimen_1P' then
        @regimen_1_p.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'ARV_regimen_2P' then
        @regimen_2_p.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'ARV_regimen_2A' then
        @regimen_2_a.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'ARV_regimen_3A' then
        @regimen_3_a.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'ARV_regimen_3P' then
        @regimen_3_p.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'ARV_regimen_4P' then
        @regimen_4_p.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'ARV_regimen_4A' then
        @regimen_4_a.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'ARV_regimen_5A' then
        @regimen_5_a.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'ARV_regimen_6A' then
        @regimen_6_a.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'ARV_regimen_7A' then
        @regimen_7_a.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'ARV_regimen_8A' then
        @regimen_8_a.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'ARV_regimen_9P' then
        @regimen_9_p.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'patients_on_any_other_regimens' then
        @unknown_arv_regimen.each do |patient_id|
          patient_obj = Patient.find_by_patient_id(patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'newly_registered_patients_reinitiated_on_art' then
        patients_re_initiated_on_art = []
        patients_re_initiated_on_art = cohort.patients_reinitiated_on_art
        patients_re_initiated_on_art.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_registered_patients_reinitiated_on_art' then
        patients_re_initiated_on_art = []
        patients_re_initiated_on_art = cohort.patients_reinitiated_on_art(@first_registration_date,end_date)
        patients_re_initiated_on_art.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'newly_registered_patients_transfered_in_on_art' then
        patients_transfered_in_on_art = []
        patients_transfered_in_on_art = cohort.transferred_in_patients
        patients_transfered_in_on_art.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_registered_patients_transfered_in_on_art' then
        patients_transfered_in_on_art = []
        patients_transfered_in_on_art = cohort.transferred_in_patients(@first_registration_date,end_date)
        patients_transfered_in_on_art.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_alive_and_on_art' then
        total_alive_and_on_art = []
        total_alive_and_on_art = cohort.total_alive_and_on_art
        total_alive_and_on_art.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'current_episode_of_tb' then
        current_espisode_of_tb = []
        current_espisode_of_tb = cohort.current_espisode_of_tb
        current_espisode_of_tb.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_current_episode_of_tb' then
        total_current_episode_of_tb = []
        total_current_episode_of_tb = cohort.current_espisode_of_tb(@first_registration_date,end_date)
        total_current_episode_of_tb.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'kaposis_sarcoma' then
        kaposis_sarcoma = []
        kaposis_sarcoma = cohort.kaposis_sarcoma
        kaposis_sarcoma.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_kaposis_sarcoma' then
        total_kaposis_sarcoma = []
        total_kaposis_sarcoma = cohort.kaposis_sarcoma(@first_registration_date,end_date)
        total_kaposis_sarcoma.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end 
      when 'TB_within_the_last_2_years' then
        tb_within_the_last_2_years = []
        tb_within_the_last_2_years = cohort.tb_within_the_last_2_yrs
        tb_within_the_last_2_years.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'total_TB_within_the_last_2_years' then
        total_tb_within_the_last_2_years = []
        total_tb_within_the_last_2_years = cohort.tb_within_the_last_2_yrs(@first_registration_date,end_date)
        total_tb_within_the_last_2_years.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'never_TB_or_TB_over_2_years_ago' then
        total_registered = cohort.total_registered_patient_ids.map{|patient| patient.patient_id}
        current_episode_of_tb = cohort.current_espisode_of_tb.map{|patient| patient.patient_id}
        tb_with_2_years = cohort.tb_within_the_last_2_yrs.map{|patient| patient.patient_id}

        no_tb = (total_registered - (current_episode_of_tb + tb_with_2_years))
        no_tb.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient)
          @report << PatientService.get_patient(patient_obj.person)
        end
      when 'total_never_TB_or_TB_over_2_years_ago' then
        total_registered = cohort.total_registered_patient_ids(@first_registration_date).map{|patient| patient.patient_id}
        current_episode_of_tb = cohort.current_espisode_of_tb(@first_registration_date,end_date).map{|patient| patient.patient_id}
        tb_with_2_years = cohort.tb_within_the_last_2_yrs(@first_registration_date,end_date).map{|patient| patient.patient_id}
        no_tb = (total_registered - (current_episode_of_tb + tb_with_2_years))
        no_tb.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient)
          @report << PatientService.get_patient(patient_obj.person)
        end
      when 'total_patients_died' then
        total_patients_died = []
        total_patients_died = cohort.outcomes_total('PATIENT DIED')
        total_patients_died.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person)
        end
      when 'total_art_defaulted_patients' then
        total_art_defaulted_patients = []
        
        total_art_defaulted_patients = cohort.outcomes_total('PATIENT DEFAULTED')
        total_art_defaulted_patients.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person)
        end
      when 'total_patients_who_stopped_treatment' then
        total_patients_who_stopped_treatment = []
        
        total_patients_who_stopped_treatment = cohort.outcomes_total('TREATMENT STOPPED')
        total_patients_who_stopped_treatment.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person)
        end
      when 'total_patients_transfered_out' then
        total_patients_transfered_out = []
        total_patients_transfered_out = cohort.outcomes_total('PATIENT TRANSFERRED OUT')
        total_patients_transfered_out.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person)
        end
      when 'died_within_the_first_month_of_ART_initiation' then
        @first_month.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person)
        end
      when 'total_died_within_the_first_month_of_ART_initiation' then
        @total_first_month.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person) 
        end
      when 'died_within_the_second_month_of_ART_initiation' then
        @second_month.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person)
        end
      when 'total_died_within_the_second_month_of_ART_initiation' then
        @total_second_month.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person)
        end
      when 'died_within_the_third_month_of_ART_initiation' then
        @third_month.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person)
        end
      when 'total_died_within_the_third_month_of_ART_initiation' then
        @total_third_month.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person)
        end
      when 'died_after_the_third_month_of_ART_initiation' then
        @after_third_month.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person)
        end
      when 'total_died_after_the_third_month_of_ART_initiation' then
        @total_after_third_month.each do |patient|
          patient_obj = Patient.find_by_patient_id(patient.patient_id)
          @report << PatientService.get_patient(patient_obj.person)
        end
      else
    end

    render :layout => 'report'
  end

  def include_url_params_for_back_button
       @report_quarter = params[:quarter]
       @report_type = params[:report_type]
  end
  
  def cohort
    @quarter = params[:quarter]
    start_date,end_date = Report.generate_cohort_date_range(@quarter)
    cohort = Cohort.new(start_date,end_date)
    @cohort = cohort.report
    @survival_analysis = SurvivalAnalysis.report(cohort)
    render :layout => 'cohort'
  end

  def cohort_menu
  end

  def adherence
    adherences = get_adherence(params[:quarter])
    @quarter = params[:quarter]
    type = "patients_with_adherence_greater_than_hundred"
    @report_type = "Adherence Histogram for all patients"
    @adherence_summary = "&nbsp;&nbsp;<button onclick='adhSummary();'>Summary</button>" unless adherences.blank?
    @adherence_summary+="<input class='test_name' type=\"button\" onmousedown=\"document.location='/cohort_tool/reports?report=#{@quarter}&report_type=#{type}';\" value=\"Over 100% Adherence\"/>"  unless adherences.blank?
    @adherence_summary_hash = Hash.new(0)
    adherences.each{|adherence,value|
      adh_value = value.to_i
      current_adh = adherence.to_i
      if current_adh <= 94
        @adherence_summary_hash["0 - 94"]+= adh_value
      elsif current_adh >= 95 and current_adh <= 100
        @adherence_summary_hash["95 - 100"]+= adh_value
      else current_adh > 100
        @adherence_summary_hash["> 100"]+= adh_value
      end
    }
    @adherence_summary_hash['missing'] = CohortTool.missing_adherence(@quarter).length rescue 0
    @adherence_summary_hash.values.each{|n|@adherence_summary_hash["total"]+=n}

    data = ""
    adherences.each{|x,y|data+="#{x}:#{y}:"}
    @id = data[0..-2] || ''

    @results = @id
    @results = @results.split(':').enum_slice(2).map
    @results = @results.each {|result| result[0] = result[0]}.sort_by{|result| result[0]}
    @results.each{|result| @graph_max = result[1].to_f if result[1].to_f > (@graph_max || 0)}
    @graph_max ||= 0
    render :layout => false
  end

  def patients_with_adherence_greater_than_hundred

      min_range = params[:min_range]
      max_range = params[:max_range]
      missing_adherence = false
      missing_adherence = true if params[:show_missing_adherence] == "yes"
      session[:list_of_patients] = nil

      @patients = adherence_over_hundred(params[:quarter],min_range,max_range,missing_adherence)
      cohort.regimens_with_patient_ids(@first_registration_date)
      @quarter = params[:quarter] + ": (#{@patients.length})" rescue  params[:quarter]
      if missing_adherence
        @report_type = "Patient(s) with missing adherence"
      elsif max_range.blank? and min_range.blank?
        @report_type = "Patient(s) with adherence greater than 100%"
      else
        @report_type = "Patient(s) with adherence starting from  #{min_range}% to #{max_range}%"
      end
      render :layout => 'report'
      return
  end

  def report_patients_with_multiple_start_reasons(start_date , end_date)

    art_eligibility_id = ConceptName.find_by_name('REASON FOR ART ELIGIBILITY').concept_id    
    patients = Observation.find_by_sql(
                ["SELECT person_id, concept_id, date_created, obs_datetime, value_coded_name_id
                 FROM obs
                 WHERE (SELECT COUNT(*)
                        FROM obs observation
                        WHERE   observation.concept_id = ?
                                AND observation.person_id = obs.person_id) > 1                               
                                AND date_created >= ? AND date_created <= ?
                                AND obs.concept_id = ?
                                AND obs.voided = 0 
               	 ORDER BY person_id ASC", art_eligibility_id, start_date, end_date, art_eligibility_id])

    patients_data = []

    patients.each do |reason|
      patient = Patient.find(reason[:person_id])
      patient_bean = PatientService.get_patient(patient.person)
      patients_data << {'person_id' => patient.id,
                        'arv_number' => patient_bean.arv_number,
                        'national_id' => patient_bean.national_id,
                        'date_created' => reason[:date_created].strftime("%Y-%m-%d %H:%M:%S"),
                        'start_reason' => (ConceptName.find(reason[:value_coded_name_id]).name rescue '')
                       }
    end
   patients_data
  end

  def voided_observations(encounter)
    voided_obs = Observation.find_by_sql("SELECT * FROM obs WHERE obs.encounter_id = #{encounter.encounter_id} AND obs.voided = 1")
    (!voided_obs.empty?) ? voided_obs : nil
  end

  def voided_orders(new_encounter)
    voided_orders = Order.find_by_sql("SELECT * FROM orders WHERE orders.encounter_id = #{new_encounter.encounter_id} AND orders.voided = 1")
    (!voided_orders.empty?) ? voided_orders : nil
  end

  def report_out_of_range_arv_numbers(arv_number_range, start_date , end_date)
    arv_number_id = PatientIdentifierType.find_by_name('ARV Number').patient_identifier_type_id
    arv_start_number = arv_number_range.first.to_s.gsub(/[^0-9]/,'').to_i
    arv_end_number = arv_number_range.last.to_s.gsub(/[^0-9]/,'').to_i
    
    arv_number_suffix = PatientIdentifier.find_by_identifier_type(arv_number_id).identifier.gsub(/[0-9]/, '')

    out_of_range_arv_numbers  = PatientIdentifier.find_by_sql(["SELECT patient_id, identifier, date_created FROM patient_identifier
                                   WHERE identifier_type = ? AND (REPLACE(identifier, '#{arv_number_suffix}', '')+0) >= ?
                                   AND (REPLACE(identifier, '#{arv_number_suffix}', '')+0) <= ?
                                   AND voided = 0
                                   AND (NOT EXISTS(SELECT * FROM patient_identifier
                                   WHERE identifier_type = ? AND date_created >= ? AND date_created <= ?))
                                   ORDER BY (REPLACE(identifier, '#{arv_number_suffix}', '')+0) ASC",
                                   arv_number_id,  arv_start_number,  arv_end_number, arv_number_id, start_date, end_date])

    out_of_range_arv_numbers_data = []
    out_of_range_arv_numbers.each do |arv_num_data|
      patient     = Patient.find(arv_num_data[:patient_id].to_i)
      patient_bean = PatientService.get_patient(patient.person)

      out_of_range_arv_numbers_data <<{'person_id' => patient.id,
                                       'arv_number' => patient_bean.arv_number,
                                       'name' => patient_bean.name,
                                       'national_id' => patient_bean.national_id,
                                       'gender' => patient_bean.sex,
                                       'age' => patient_bean.age,
                                       'birthdate' => patient_bean.birth_date,
                                       'date_created' => arv_num_data[:date_created].strftime("%Y-%m-%d %H:%M:%S")
                                       }
    end
    out_of_range_arv_numbers_data
  end
  
  def report_dispensations_without_prescriptions_data(start_date , end_date)
    pills_dispensed_id      = ConceptName.find_by_name('PILLS DISPENSED').concept_id

    missed_prescriptions_data = Observation.find(:all, :select =>  "person_id, value_drug, date_created",
                                              :conditions =>["order_id IS NULL
                                                AND date_created >= ? AND date_created <= ? AND
                                                    concept_id = ? AND voided = 0" ,start_date , end_date, pills_dispensed_id])
    dispensations_without_prescriptions = []

    missed_prescriptions_data.each do |dispensation|
        patient = Patient.find(dispensation[:person_id])
        patient_bean = PatientService.get_patient(patient.person)
        drug_name    = Drug.find(dispensation[:value_drug]).name

        dispensations_without_prescriptions << { 'person_id' => patient.id,
                                              'arv_number' => patient_bean.arv_number,
                                              'national_id' => patient_bean.national_id,
                                              'date_created' => dispensation[:date_created].strftime("%Y-%m-%d %H:%M:%S"),
                                              'drug_name' => drug_name
                                             }
    end

    dispensations_without_prescriptions
  end
  
  def report_prescriptions_without_dispensations_data(start_date , end_date)
    pills_dispensed_id      = ConceptName.find_by_name('PILLS DISPENSED').concept_id

    missed_dispensations_data = Observation.find_by_sql(["SELECT order_id, patient_id, date_created from orders 
              WHERE NOT EXISTS (SELECT * FROM obs
               WHERE orders.order_id = obs.order_id AND obs.concept_id = ?)
                AND date_created >= ? AND date_created <= ? AND orders.voided = 0", pills_dispensed_id, start_date , end_date ])

    prescriptions_without_dispensations = []

    missed_dispensations_data.each do |prescription|
        patient      = Patient.find(prescription[:patient_id])
        drug_id      = DrugOrder.find(prescription[:order_id]).drug_inventory_id
        drug_name    = Drug.find(drug_id).name

        prescriptions_without_dispensations << {'person_id' => patient.id,
                                                'arv_number' => PatientService.get_patient_identifier(patient, 'ARV Number'),
                                                'national_id' => PatientService.get_national_id(patient),
                                                'date_created' => prescription[:date_created].strftime("%Y-%m-%d %H:%M:%S"),
                                                'drug_name' => drug_name
                                                }
    end
    prescriptions_without_dispensations
  end

  def report_dead_with_visits(start_date, end_date)
    patient_died_concept    = ConceptName.find_by_name('PATIENT DIED').concept_id

    all_dead_patients_with_visits = "SELECT * 
    FROM (SELECT observation.person_id AS patient_id, DATE(p.death_date) AS date_of_death, DATE(observation.date_created) AS date_started
          FROM person p right join obs observation ON p.person_id = observation.person_id
          WHERE p.dead = 1 AND DATE(p.death_date) < DATE(observation.date_created) AND observation.voided = 0
          ORDER BY observation.date_created ASC) AS dead_patients_visits
    WHERE DATE(date_of_death) >= DATE('#{start_date}') AND DATE(date_of_death) <= DATE('#{end_date}')
    GROUP BY patient_id"
    patients = Patient.find_by_sql([all_dead_patients_with_visits])
    
    patients_data  = []
    patients.each do |patient_data_row|
      person = Person.find(patient_data_row[:patient_id].to_i)
      patient_bean = PatientService.get_patient(person)
      patients_data <<{ 'person_id' => person.id,
                        'arv_number' => patient_bean.arv_number,
                        'name' => patient_bean.name,
                        'national_id' => patient_bean.national_id,
                        'gender' => patient_bean.sex,
                        'age' => patient_bean.age,
                        'birthdate' => patient_bean.birth_date,
                        'phone' => PatientService.phone_numbers(person), 
                        'date_created' => patient_data_row[:date_started]
                       }
    end
    patients_data
  end
  
  def report_males_allegedly_pregnant(start_date, end_date)
    pregnant_patient_concept_id = ConceptName.find_by_name('IS PATIENT PREGNANT?').concept_id
    patients = PatientIdentifier.find_by_sql(["
                                   SELECT person.person_id,obs.obs_datetime
                                       FROM obs INNER JOIN person ON obs.person_id = person.person_id
                                           WHERE person.gender = 'M' AND
                                           obs.concept_id = ? AND obs.obs_datetime >= ? AND obs.obs_datetime <= ? AND obs.voided = 0",
        pregnant_patient_concept_id, '2008-12-23 00:00:00', end_date])

        patients_data  = []
        patients.each do |patient_data_row|
          person = Person.find(patient_data_row[:person_id].to_i)
		  patient_bean = PatientService.get_patient(person)
          patients_data <<{ 'person_id' => person.id,
                            'arv_number' => patient_bean.arv_number,
                            'name' => patient_bean.name,
                            'national_id' => patient_bean.national_id,
                            'gender' => patient_bean.sex,
                            'age' => patient_bean.age,
                            'birthdate' => patient_bean.birth_date,
                            'phone' => PatientService.phone_numbers(person),
                            'date_created' => patient_data_row[:obs_datetime]
                           }
        end
        patients_data
  end

  def report_patients_who_moved_from_second_to_first_line_drugs(start_date, end_date)
  
    first_line_regimen = "('D4T+3TC+NVP', 'd4T 3TC + d4T 3TC NVP')"
    second_line_regimen = "('AZT+3TC+NVP', 'D4T+3TC+EFV', 'AZT+3TC+EFV', 'TDF+3TC+EFV', 'TDF+3TC+NVP', 'TDF/3TC+LPV/r', 'AZT+3TC+LPV/R', 'ABC/3TC+LPV/r')"
    
    patients_who_moved_from_nd_to_st_line_drugs = "SELECT * FROM (
        SELECT patient_on_second_line_drugs.* , DATE(patient_on_first_line_drugs.date_created) AS date_started FROM (
        SELECT person_id, date_created
        FROM obs
        WHERE value_drug IN (
        SELECT drug_id 
        FROM drug 
        WHERE concept_id IN (SELECT concept_id FROM concept_name 
        WHERE name IN #{second_line_regimen}))
        ) AS patient_on_second_line_drugs inner join

        (SELECT person_id, date_created
        FROM obs
        WHERE value_drug IN (
        SELECT drug_id 
        FROM drug 
        WHERE concept_id IN (SELECT concept_id FROM concept_name 
        WHERE name IN #{first_line_regimen}))
        ) AS patient_on_first_line_drugs
        ON patient_on_first_line_drugs.person_id = patient_on_second_line_drugs.person_id
        WHERE DATE(patient_on_first_line_drugs.date_created) > DATE(patient_on_second_line_drugs.date_created) AND
              DATE(patient_on_first_line_drugs.date_created) >= DATE('#{start_date}') AND DATE(patient_on_first_line_drugs.date_created) <= DATE('#{end_date}')
        ORDER BY patient_on_first_line_drugs.date_created ASC) AS patients
        GROUP BY person_id"

    patients = Patient.find_by_sql([patients_who_moved_from_nd_to_st_line_drugs])
    
    patients_data  = []
    patients.each do |patient_data_row|
      person = Person.find(patient_data_row[:person_id].to_i)
      patient_bean = PatientService.get_patient(person)
      patients_data <<{ 'person_id' => person.id,
                        'arv_number' => patient_bean.arv_number,
                        'name' => patient_bean.name,
                        'national_id' => patient_bean.national_id,
                        'gender' => patient_bean.sex,
                        'age' => patient_bean.age,
                        'birthdate' => patient_bean.birth_date,
                        'phone' => PatientService.phone_numbers(person),
                        'date_created' => patient_data_row[:date_started]
                       }
    end
    patients_data
  end
  
  def report_with_drug_start_dates_less_than_program_enrollment_dates(start_date, end_date)

    arv_drugs_concepts      = MedicationService.arv_drugs.inject([]) {|result, drug| result << drug.concept_id}
    on_arv_concept_id       = ConceptName.find_by_name('ON ANTIRETROVIRALS').concept_id
    hvi_program_id          = Program.find_by_name('HIV PROGRAM').program_id
    national_identifier_id  = PatientIdentifierType.find_by_name('National id').patient_identifier_type_id
    arv_number_id           = PatientIdentifierType.find_by_name('ARV Number').patient_identifier_type_id

    patients_on_antiretrovirals_sql = "
         (SELECT p.patient_id, s.date_created as Date_Started_ARV
          FROM patient_program p INNER JOIN patient_state s
          ON  p.patient_program_id = s.patient_program_id
          WHERE s.state IN (SELECT program_workflow_state_id
                            FROM program_workflow_state g
                            WHERE g.concept_id = #{on_arv_concept_id})
                            AND p.program_id = #{hvi_program_id}
         ) patients_on_antiretrovirals"

    antiretrovirals_obs_sql = "
         (SELECT * FROM obs
          WHERE  value_drug IN (SELECT drug_id FROM drug
          WHERE concept_id IN ( #{arv_drugs_concepts.join(', ')} ) )
         ) antiretrovirals_obs"

    drug_start_dates_less_than_program_enrollment_dates_sql= "
      SELECT * FROM (
                  SELECT patients_on_antiretrovirals.patient_id, DATE(patients_on_antiretrovirals.date_started_ARV) AS date_started_ARV,
                         antiretrovirals_obs.obs_datetime, antiretrovirals_obs.value_drug
                  FROM #{patients_on_antiretrovirals_sql}, #{antiretrovirals_obs_sql}
                  WHERE patients_on_antiretrovirals.Date_Started_ARV > antiretrovirals_obs.obs_datetime
                        AND patients_on_antiretrovirals.patient_id = antiretrovirals_obs.person_id
                        AND patients_on_antiretrovirals.Date_Started_ARV >='#{start_date}' AND patients_on_antiretrovirals.Date_Started_ARV <= '#{end_date}'
                  ORDER BY patients_on_antiretrovirals.date_started_ARV ASC) AS patient_select
      GROUP BY patient_id"


    patients       = Patient.find_by_sql(drug_start_dates_less_than_program_enrollment_dates_sql)
    patients_data  = []
    patients.each do |patient_data_row|
      person = Person.find(patient_data_row[:patient_id])
	  patient_bean = PatientService.get_patient(person)
      patients_data <<{ 'person_id' => person.id,
                        'arv_number' => patient_bean.arv_number,
                        'name' => patient_bean.name,
                        'national_id' => patient_bean.national_id,
                        'gender' => patient_bean.sex,
                        'age' => patient_bean.age,
                        'birthdate' => patient_bean.birth_date,
                        'phone' => PatientService.phone_numbers(person), 
                        'date_created' => patient_data_row[:date_started_ARV]
                       }
    end
    patients_data
  end
  
  def get_adherence(quarter="Q1 2009")
  date = Report.generate_cohort_date_range(quarter)

  start_date  = date.first.beginning_of_day.strftime("%Y-%m-%d %H:%M:%S")
  end_date    = date.last.end_of_day.strftime("%Y-%m-%d %H:%M:%S")
  adherences  = Hash.new(0)
  adherence_concept_id = ConceptName.find_by_name("WHAT WAS THE PATIENTS ADHERENCE FOR THIS DRUG ORDER").concept_id

 adherence_sql_statement= " SELECT worse_adherence_dif, pat_ad.person_id as patient_id, pat_ad.value_numeric AS adherence_rate_worse
                            FROM (SELECT ABS(100 - Abs(value_numeric)) as worse_adherence_dif, obs_id, person_id, concept_id, encounter_id, order_id, obs_datetime, location_id, value_numeric
                                  FROM obs q
                                  WHERE concept_id = #{adherence_concept_id} AND order_id IS NOT NULL
                                  ORDER BY q.obs_datetime DESC, worse_adherence_dif DESC, person_id ASC)pat_ad
                            WHERE pat_ad.obs_datetime >= '#{start_date}' AND pat_ad.obs_datetime<= '#{end_date}'
                            GROUP BY patient_id "

  adherence_rates = Observation.find_by_sql(adherence_sql_statement)

  adherence_rates.each{|adherence|

    rate = adherence.adherence_rate_worse.to_i

    if rate >= 91 and rate <= 94
      cal_adherence = 94
    elsif  rate >= 95 and rate <= 100
      cal_adherence = 100
    else
      cal_adherence = rate + (5- rate%5)%5
    end
    adherences[cal_adherence]+=1
  }
  adherences
  end

  def adherence_over_hundred(quarter="Q1 2009",min_range = nil,max_range=nil,missing_adherence=false)
    date_range                 = Report.generate_cohort_date_range(quarter)
    start_date                 = date_range.first.beginning_of_day.strftime("%Y-%m-%d %H:%M:%S")
    end_date                   = date_range.last.end_of_day.strftime("%Y-%m-%d %H:%M:%S")
    adherence_range_filter     = " (adherence_rate_worse >= #{min_range} AND adherence_rate_worse <= #{max_range}) "
    adherence_concept_id       = ConceptName.find_by_name("WHAT WAS THE PATIENTS ADHERENCE FOR THIS DRUG ORDER").concept_id
    brought_drug_concept_id    = ConceptName.find_by_name("AMOUNT OF DRUG BROUGHT TO CLINIC").concept_id

    patients = {}

    if (min_range.blank? or max_range.blank?) and !missing_adherence
        adherence_range_filter = " (adherence_rate_worse > 100) "
    elsif missing_adherence

       adherence_range_filter = " (adherence_rate_worse IS NULL) "

    end

    patients_with_adherences =  " (SELECT   oders.start_date, obs_inner_order.obs_datetime, obs_inner_order.adherence_rate AS adherence_rate,
                                        obs_inner_order.id, obs_inner_order.patient_id, obs_inner_order.drug_inventory_id AS drug_id,
                                        ROUND(DATEDIFF(obs_inner_order.obs_datetime, oders.start_date)* obs_inner_order.equivalent_daily_dose, 0) AS expected_remaining,
                                        obs_inner_order.quantity AS quantity, obs_inner_order.encounter_id, obs_inner_order.order_id
                               FROM (SELECT latest_adherence.obs_datetime, latest_adherence.adherence_rate, latest_adherence.id, latest_adherence.patient_id, latest_adherence.order_id, drugOrder.drug_inventory_id, drugOrder.equivalent_daily_dose, drugOrder.quantity, latest_adherence.encounter_id
                                    FROM (SELECT all_adherences.obs_datetime, all_adherences.value_numeric AS adherence_rate, all_adherences.obs_id as id, all_adherences.person_id as patient_id,all_adherences.order_id, all_adherences.encounter_id
                                          FROM (SELECT obs_id, person_id, concept_id, encounter_id, order_id, obs_datetime, location_id, value_numeric
                                                FROM obs Observations
                                                WHERE concept_id = #{adherence_concept_id}
                                                ORDER BY person_id ASC , Observations.obs_datetime DESC )all_adherences
                                          WHERE all_adherences.obs_datetime >= '#{start_date}' AND all_adherences.obs_datetime<= '#{end_date}'
                                          GROUP BY order_id, patient_id) latest_adherence
                                    INNER JOIN
                                          drug_order drugOrder
                                    On    drugOrder.order_id = latest_adherence.order_id) obs_inner_order
                               INNER JOIN
                                    orders oders
                               On     oders.order_id = obs_inner_order.order_id) patients_with_adherence  "

      worse_adherence_per_patient =" (SELECT worse_adherence_dif, pat_ad.person_id as patient_id, pat_ad.value_numeric AS adherence_rate_worse
                                FROM (SELECT ABS(100 - Abs(value_numeric)) as worse_adherence_dif, obs_id, person_id, concept_id, encounter_id, order_id, obs_datetime, location_id, value_numeric
                                      FROM obs q
                                      WHERE concept_id = #{adherence_concept_id} AND order_id IS NOT NULL
                                      ORDER BY q.obs_datetime DESC, worse_adherence_dif DESC, person_id ASC)pat_ad
                                WHERE pat_ad.obs_datetime >= '#{start_date}' AND pat_ad.obs_datetime<= '#{end_date}'
                                GROUP BY patient_id ) worse_adherence_per_patient   "

     patient_adherences_sql =  " SELECT *
                                 FROM   #{patients_with_adherences} INNER JOIN #{worse_adherence_per_patient}
                                 ON patients_with_adherence.patient_id = worse_adherence_per_patient.patient_id
                                 WHERE  #{adherence_range_filter} "

      rates = Observation.find_by_sql(patient_adherences_sql)

      patients_rates = []
      rates.each{|rate|
        patients_rates << rate
      }
      adherence_rates = patients_rates

    arv_number_id = PatientIdentifierType.find_by_name('ARV Number').patient_identifier_type_id
    adherence_rates.each{|rate|

      patient    = Patient.find(rate.patient_id)
      person     = patient.person
      patient_bean = PatientService.get_patient(person)
      drug       = Drug.find(rate.drug_id)
      pill_count = Observation.find(:first, :conditions => "order_id = #{rate.order_id} AND encounter_id = #{rate.encounter_id} AND concept_id = #{brought_drug_concept_id} ").value_numeric rescue ""
      if !patients[patient.patient_id] then

          patients[patient.patient_id]={"id" =>patient.id,
                                        "arv_number" => patient_bean.arv_number,
                                        "name" => patient_bean.name,
                                        "national_id" => patient_bean.national_id,
                                        "visit_date" =>rate.obs_datetime,
                                        "gender" =>patient_bean.sex,
                                        "age" => PatientService.patient_age_at_initiation(patient, rate.start_date.to_date),
                                        "birthdate" => patient_bean.birth_date,
                                        "pill_count" => pill_count.to_i.to_s,
                                        "adherence" => rate. adherence_rate_worse,
                                        "start_date" => rate.start_date.to_date,
                                        "expected_count" =>rate.expected_remaining,
                                        "drug" => drug.name}
   elsif  patients[patient.patient_id] then

          patients[patient.patient_id]["age"].to_i < PatientService.patient_age_at_initiation(patient, rate.start_date.to_date).to_i ? patients[patient.patient_id]["age"] = patient.age_at_initiation(rate.start_date.to_date).to_s : ""

          patients[patient.patient_id]["drug"] = patients[patient.patient_id]["drug"].to_s + "<br>#{drug.name}"

          patients[patient.patient_id]["pill_count"] << "<br>#{pill_count.to_i.to_s}"

          patients[patient.patient_id]["expected_count"] << "<br>#{rate.expected_remaining.to_i.to_s}"

          patients[patient.patient_id]["start_date"].to_date > rate.start_date.to_date ?
          patients[patient.patient_id]["start_date"] = rate.start_date.to_date : ""

    end
    }

    patients.sort { |a,b| a[1]['adherence'].to_i <=> b[1]['adherence'].to_i }
  end
end

