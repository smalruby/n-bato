class AddFullNameToDepartments < ActiveRecord::Migration[8.0]
  def change
    add_column :departments, :full_name, :string
  end
end
