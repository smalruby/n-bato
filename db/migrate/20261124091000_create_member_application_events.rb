# 入会申込(長いイベント)の「認めた」「認めない」を、詳細のイベントに分ける(見直し第20回、docs/adr/0030)。
# 申込の status・fiscal_year・joined_on・decided_on・reason・person_id は「いまの状態」として残し、
# 入口(MemberApplication::Approval.approve!・MemberApplication::Rejection.reject!)だけが書き換える。照合は model:verify。
class CreateMemberApplicationEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :member_application_approvals do |t|
      t.references :member_application, null: false, foreign_key: true, index: {unique: true}
      t.references :approver, foreign_key: {to_table: :users}
      t.references :person, null: false, foreign_key: true
      t.integer :fiscal_year, null: false
      t.date :joined_on, null: false
      t.datetime :approved_at, null: false
    end
    create_table :member_application_rejections do |t|
      t.references :member_application, null: false, foreign_key: true, index: {unique: true}
      t.references :rejecter, foreign_key: {to_table: :users}
      t.text :reason, null: false
      t.datetime :rejected_at, null: false
    end
    execute <<~SQL
      INSERT INTO member_application_approvals (member_application_id, person_id, fiscal_year, joined_on, approved_at)
      SELECT id, person_id, fiscal_year, joined_on, COALESCE(decided_on, updated_at) FROM member_applications
      WHERE status = 'approved' AND person_id IS NOT NULL AND fiscal_year IS NOT NULL AND joined_on IS NOT NULL
    SQL
    execute <<~SQL
      INSERT INTO member_application_rejections (member_application_id, reason, rejected_at)
      SELECT id, COALESCE(reason, ''), COALESCE(decided_on, updated_at) FROM member_applications WHERE status = 'rejected'
    SQL
  end

  def down
    drop_table :member_application_rejections
    drop_table :member_application_approvals
  end
end
