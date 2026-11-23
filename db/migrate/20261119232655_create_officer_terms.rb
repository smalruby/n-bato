class CreateOfficerTerms < ActiveRecord::Migration[8.1]
  def change
    create_table :officer_terms do |t|
      t.references :person, null: false, foreign_key: true
      t.string :role, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.date :left_on
      t.boolean :remunerated, null: false, default: false
      t.string :appointed_by, null: false, default: ""
      t.text :notes, null: false, default: ""
      t.timestamps
    end
  end
end
