# 記帳した仕訳の取消(イベント。docs/adr/0026)。取り消した仕訳は消さず、帳簿から外す。
# 取消のあとに作り直した提案が、どの提案のし直しかを残す(journal_proposals.reproposed_from_id)。
class CreateJournalEntryCancellations < ActiveRecord::Migration[8.1]
  def change
    create_table :journal_entry_cancellations do |t|
      t.references :journal_entry, null: false, foreign_key: true, index: { unique: true }
      t.references :canceller, foreign_key: { to_table: :users }
      t.text :reason, null: false
      t.datetime :cancelled_at, null: false
    end
    add_reference :journal_proposals, :reproposed_from, foreign_key: { to_table: :journal_proposals }
  end
end
