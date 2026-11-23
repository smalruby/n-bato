class AddResubmitToAnnualReports < ActiveRecord::Migration[8.1]
  def change
    add_column :annual_reports, :resubmit_needed_on, :date
    add_column :annual_reports, :resubmitted_on, :date
  end
end
