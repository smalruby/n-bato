class CreateRegistrations < ActiveRecord::Migration[8.1]
  def change
    create_table :registrations do |t|
      t.string :kind, null: false
      t.date :cause_on, null: false
      t.date :due_on, null: false
      t.date :registered_on
      t.text :note, null: false, default: ""
      t.references :officer_term, foreign_key: true
      t.timestamps
    end
  end
end
