# AI の提案(JournalProposal)の 1 行に入っていた「確認の日時・確認した人・状態・できた仕訳」を、
# 承認・却下・取り下げの 3 つのイベントに分ける(docs/adr/0002・0003)。
# 提案そのものもイベントにし、日時は提案した日時(proposed_at)1 つだけにする。
class SplitJournalProposalEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :journal_proposal_approvals do |t|
      t.references :journal_proposal, null: false, foreign_key: true, index: { unique: true }
      t.references :approver, foreign_key: { to_table: :users }
      t.references :journal_entry, foreign_key: true
      t.datetime :approved_at, null: false
    end
    create_table :journal_proposal_rejections do |t|
      t.references :journal_proposal, null: false, foreign_key: true, index: { unique: true }
      t.references :rejecter, foreign_key: { to_table: :users }
      t.datetime :rejected_at, null: false
    end
    create_table :journal_proposal_withdrawals do |t|
      t.references :journal_proposal, null: false, foreign_key: true, index: { unique: true }
      t.datetime :withdrawn_at, null: false
    end

    execute <<~SQL
      INSERT INTO journal_proposal_approvals (journal_proposal_id, approver_id, journal_entry_id, approved_at)
      SELECT id, reviewed_by_id, journal_entry_id, COALESCE(reviewed_at, updated_at) FROM journal_proposals WHERE status = 'approved'
    SQL
    execute <<~SQL
      INSERT INTO journal_proposal_rejections (journal_proposal_id, rejecter_id, rejected_at)
      SELECT id, reviewed_by_id, COALESCE(reviewed_at, updated_at) FROM journal_proposals WHERE status = 'rejected'
    SQL
    # これまでの承認・却下の操作は、行を書き戻す「元に戻す」ができない形になったので、元に戻せない操作にする
    execute <<~SQL
      UPDATE audit_operations SET kind = 'final'
      WHERE id IN (SELECT audit_operation_id FROM audit_changes WHERE auditable_type = 'JournalProposal')
    SQL

    rename_column :journal_proposals, :created_at, :proposed_at
    remove_column :journal_proposals, :updated_at
    remove_reference :journal_proposals, :journal_entry, index: true
    remove_reference :journal_proposals, :reviewed_by, index: true
    remove_column :journal_proposals, :reviewed_at
    remove_column :journal_proposals, :status
  end

  def down
    add_column :journal_proposals, :status, :string, default: "proposed", null: false
    add_column :journal_proposals, :reviewed_at, :datetime
    add_reference :journal_proposals, :reviewed_by, index: true
    add_reference :journal_proposals, :journal_entry, index: true
    add_column :journal_proposals, :updated_at, :datetime
    rename_column :journal_proposals, :proposed_at, :created_at
    execute "UPDATE journal_proposals SET updated_at = created_at"
    execute <<~SQL
      UPDATE journal_proposals SET status = 'approved',
        reviewed_by_id = (SELECT approver_id FROM journal_proposal_approvals a WHERE a.journal_proposal_id = journal_proposals.id),
        reviewed_at = (SELECT approved_at FROM journal_proposal_approvals a WHERE a.journal_proposal_id = journal_proposals.id),
        journal_entry_id = (SELECT journal_entry_id FROM journal_proposal_approvals a WHERE a.journal_proposal_id = journal_proposals.id)
      WHERE id IN (SELECT journal_proposal_id FROM journal_proposal_approvals)
    SQL
    execute <<~SQL
      UPDATE journal_proposals SET status = 'rejected',
        reviewed_by_id = (SELECT rejecter_id FROM journal_proposal_rejections r WHERE r.journal_proposal_id = journal_proposals.id),
        reviewed_at = (SELECT rejected_at FROM journal_proposal_rejections r WHERE r.journal_proposal_id = journal_proposals.id)
      WHERE id IN (SELECT journal_proposal_id FROM journal_proposal_rejections)
    SQL
    execute "DELETE FROM journal_proposals WHERE id IN (SELECT journal_proposal_id FROM journal_proposal_withdrawals)"
    change_column_null :journal_proposals, :updated_at, false
    drop_table :journal_proposal_withdrawals
    drop_table :journal_proposal_rejections
    drop_table :journal_proposal_approvals
  end
end
