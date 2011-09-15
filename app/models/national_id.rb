class NationalId < ActiveRecord::Base
  set_table_name 'national_id'

  named_scope :active,
      :conditions => {:assigned => 0}

  def self.next_id
    id = self.active.first
    return if id.nil?
    return id.national_id
  end

  def self.next_ids_available_label(location_name = nil)
    id = self.active.first(:order => 'id DESC')
    return '' if id.blank?

    national_id = id.national_id[0..2] + '-' + id.national_id[3..-1]
    label = ZebraPrinter::StandardLabel.new
    label.draw_barcode(40, 210, 0, 1, 5, 10, 70, false, "#{id.national_id}")
    label.draw_text('Name:', 40, 30, 0, 2, 2, 2, false)
    label.draw_text("#{national_id}  dd__/mm__/____  (F/M)", 40, 110, 0, 2, 2, 2, false)
    label.draw_text('TA:', 40, 160, 0, 2, 2, 2, false)
    id.assigned = true
    id.date_issued = Time.now
    id.issued_to = location_name
    id.creator = User.current_user.id
    id.save
    label.print(1)
  end

  def assign_to!(patient)
    self.update_atributes! \
        :assigned    => true,
        :eds         => true,
        :date_issued => Time.now,
        :creator     => User.current_user_id
    self
  end

end
