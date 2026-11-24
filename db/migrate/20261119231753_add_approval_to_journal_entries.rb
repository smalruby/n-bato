class AddApprovalToJournalEntries < ActiveRecord::Migration[8.1]
  def change
    add_reference :journal_entries, :approved_by, foreign_key: {to_table: :users}
    add_column :journal_entries, :approved_at, :datetime
  end
end
