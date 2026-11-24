class CreateJournalEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :journal_entries do |t|
      t.references :siwake_import, foreign_key: true
      t.integer :position
      t.integer :fiscal_year, null: false
      t.date :entry_date, null: false
      t.integer :slip_number
      t.integer :line_number, null: false, default: 1

      %w[debit credit].each do |side|
        t.references :"#{side}_account", null: false, foreign_key: {to_table: :accounts}
        t.references :"#{side}_department", foreign_key: {to_table: :departments}
        t.integer :"#{side}_sub_code", null: false, default: 0
        t.string :"#{side}_sub_name", null: false, default: ""
        t.integer :"#{side}_tax_category_code", null: false, default: 0
        t.integer :"#{side}_business_category_code", null: false, default: 0
        t.integer :"#{side}_tax_treatment_code", null: false, default: 3
        t.integer :"#{side}_tax_rate", null: false, default: 10
        t.integer :"#{side}_amount", null: false
        t.integer :"#{side}_tax_amount", null: false, default: 0
      end

      t.string :summary, null: false, default: ""
      t.string :sub_summary, null: false, default: ""
      t.string :memo, null: false, default: ""
      t.integer :tag1, null: false, default: 0
      t.integer :tag2, null: false, default: 0
      t.timestamps
    end
    add_index :journal_entries, :fiscal_year
    add_index :journal_entries, :entry_date
    add_index :journal_entries, [:siwake_import_id, :position]
  end
end
