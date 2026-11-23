class AddMasterFieldsToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :nature_code, :integer
    add_column :accounts, :group_name, :string
    add_column :accounts, :full_name, :string
  end
end
