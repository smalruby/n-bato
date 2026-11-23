class CreateAnnualReports < ActiveRecord::Migration[8.1]
  def change
    create_table :annual_reports do |t|
      t.integer :fiscal_year, null: false
      t.text :achievements, null: false, default: ""
      t.text :other_business, null: false, default: ""
      t.text :board_meetings, null: false, default: ""
      t.text :general_meetings, null: false, default: ""
      t.text :members_note, null: false, default: ""
      t.json :member_counts
      t.date :letter_date
      t.date :approved_on
      t.date :submitted_on
      t.date :bs_published_on
      t.string :bs_publication_place
      t.timestamps
    end
    add_index :annual_reports, :fiscal_year, unique: true
  end
end
