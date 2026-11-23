class CreateConsents < ActiveRecord::Migration[8.1]
  def change
    create_table :consents do |t|
      t.references :resolution, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.date :consented_on, null: false
      t.string :via, null: false, default: "paper" # paper / email
      t.string :note, null: false, default: ""
      t.timestamps
    end
    add_index :consents, [ :resolution_id, :person_id ], unique: true
  end
end
