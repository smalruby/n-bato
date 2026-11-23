class AddClosedAtToFiscalPeriods < ActiveRecord::Migration[8.1]
  def change
    add_column :fiscal_periods, :closed_at, :datetime
  end
end
