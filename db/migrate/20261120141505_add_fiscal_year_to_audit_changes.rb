class AddFiscalYearToAuditChanges < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_changes, :fiscal_year, :integer
    add_index :audit_changes, :fiscal_year
  end
end
