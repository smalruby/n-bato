class CreateAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :accounts do |t|
      t.integer :code, null: false
      t.string :name, null: false
      t.string :category, null: false
      t.timestamps
    end
    add_index :accounts, :code, unique: true
  end
end
