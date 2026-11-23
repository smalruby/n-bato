class CreateDepartments < ActiveRecord::Migration[8.0]
  def change
    create_table :departments do |t|
      t.integer :code, null: false
      t.string :name, null: false
      t.timestamps
    end
    add_index :departments, :code, unique: true
  end
end
