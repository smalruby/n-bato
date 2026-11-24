class CreateJournalProposals < ActiveRecord::Migration[8.1]
  def change
    create_table :journal_proposals do |t|
      t.references :voucher, null: false, foreign_key: true
      t.date :entry_date, null: false
      t.references :debit_account, null: false, foreign_key: {to_table: :accounts}
      t.references :debit_department, foreign_key: {to_table: :departments}
      t.references :credit_account, null: false, foreign_key: {to_table: :accounts}
      t.references :credit_department, foreign_key: {to_table: :departments}
      t.integer :amount, null: false
      t.string :summary, null: false, default: ""
      t.string :sub_summary, null: false, default: ""
      t.text :rationale, null: false, default: ""
      t.string :confidence, null: false, default: "medium"
      t.string :status, null: false, default: "proposed"
      t.string :ai_model
      t.references :journal_entry, foreign_key: true
      t.references :reviewed_by, foreign_key: {to_table: :users}
      t.datetime :reviewed_at
      t.timestamps
    end
  end
end
