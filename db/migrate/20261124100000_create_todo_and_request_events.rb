# やること・依頼を、イミュータブルデータモデルに移す(docs/adr/0002〜0008・0034)。
#
# - やること(Todo・長いイベント)の状態の変化を、Todo::StatusChange(イベント。日時は changed_at)に分ける。
#   todos の status・waiting_on・done_at・done_by・done_note は「いまの状態」として残し、入口だけが書き換える(照合は model:verify)。
# - 依頼(IncomingRequest・長いイベント)の「解決にした」を IncomingRequest::Settlement(日付は settled_on)に分ける。
#   incoming_requests の status・resolved_on は「いまの状態」として残す。
# - 依頼の対話の発言(IncomingRequestMessage)をイベントにする(日時は written_at = もとの created_at)。
#   「AI に送った」(sent_at・masked_body・send_attachments)は IncomingRequestMessage::Delivery、
#   「この案で決める」(applied_at)は IncomingRequestMessage::Adoption に分ける。
# - いまある行の値から、イベントを作る(backfill)。値は消さずに移す。
# - これまでの操作のうち、やること・依頼・発言に触れたもの(作成・変更・削除)は、元に戻す・やり直すと
#   イベントと食い違うか失敗するので、元に戻せない操作にする(会計を移したときと同じ。docs/adr/0003)。
class CreateTodoAndRequestEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :todo_status_changes do |t|
      t.references :todo, null: false, foreign_key: true
      t.string :status, null: false
      t.string :waiting_on, default: "", null: false
      t.text :note, default: "", null: false
      t.boolean :automatic, default: false, null: false
      t.references :changed_by, foreign_key: { to_table: :users }
      t.datetime :changed_at, null: false
    end
    create_table :incoming_request_settlements do |t|
      t.references :incoming_request, null: false, foreign_key: true, index: { unique: true }
      t.references :settled_by, foreign_key: { to_table: :users }
      t.date :settled_on, null: false
    end
    create_table :incoming_request_message_deliveries do |t|
      t.references :message, null: false, foreign_key: { to_table: :incoming_request_messages }, index: { unique: true }
      t.text :masked_body, default: "", null: false
      t.boolean :send_attachments, default: false, null: false
      t.datetime :delivered_at, null: false
    end
    create_table :incoming_request_message_adoptions do |t|
      t.references :message, null: false, foreign_key: { to_table: :incoming_request_messages }, index: { unique: true }
      t.references :adopted_by, foreign_key: { to_table: :users }
      t.datetime :adopted_at, null: false
    end

    # やること: 未着手(もとの値)でないものに、いまの状態を表す変化を 1 つ作る。済みで日時の無いものは、更新した日時で埋める。
    execute "UPDATE todos SET done_at = updated_at WHERE status = 'done' AND done_at IS NULL"
    execute <<~SQL
      INSERT INTO todo_status_changes (todo_id, status, waiting_on, note, automatic, changed_at)
      SELECT id, status,
             CASE WHEN status = 'wait' THEN waiting_on ELSE '' END,
             CASE WHEN status = 'done' THEN done_note ELSE '' END,
             CASE WHEN status = 'done' AND done_by = 'auto' THEN 1 ELSE 0 END,
             CASE WHEN status = 'done' THEN done_at ELSE updated_at END
      FROM todos WHERE status <> 'todo'
    SQL

    # 依頼: 解決したものに「解決にした」を作る。解決した日の無いものは、更新した日で埋める。
    # updated_at は UTC で入っているので、日本時間(+9 時間。夏時間は無い)の日付にする
    execute "UPDATE incoming_requests SET resolved_on = date(updated_at, '+9 hours') WHERE status = 'resolved' AND resolved_on IS NULL"
    execute <<~SQL
      INSERT INTO incoming_request_settlements (incoming_request_id, settled_on)
      SELECT id, resolved_on FROM incoming_requests WHERE status = 'resolved'
    SQL

    # 発言: 送ったもの・決めたもの
    execute <<~SQL
      INSERT INTO incoming_request_message_deliveries (message_id, masked_body, send_attachments, delivered_at)
      SELECT id, masked_body, send_attachments, sent_at FROM incoming_request_messages WHERE sent_at IS NOT NULL
    SQL
    execute <<~SQL
      INSERT INTO incoming_request_message_adoptions (message_id, adopted_at)
      SELECT id, applied_at FROM incoming_request_messages WHERE applied_at IS NOT NULL
    SQL

    # これまでの操作のうち、やること・依頼・発言に触れたものは、作成・変更・削除のどれでも元に戻せない操作にする。
    # - 変更: 元に戻すと、いまの状態の列がイベントと食い違う。
    # - 作成・削除: やり直す・元に戻すで、移す前の形の行(状態の列だけを持つやること・解決した依頼、written_at の無い発言)が
    #   イベントなしに戻る。発言は written_at が NOT NULL なので、書けずに失敗する。
    # 変化の中身(changeset)は暗号化してあり SQL では読めないので、記録の種類だけで決める。
    execute <<~SQL
      UPDATE audit_operations SET kind = 'final'
      WHERE kind = 'do' AND id IN (
        SELECT audit_operation_id FROM audit_changes
        WHERE auditable_type IN ('Todo', 'IncomingRequest', 'IncomingRequestMessage')
      )
    SQL

    rename_column :incoming_request_messages, :created_at, :written_at
    remove_column :incoming_request_messages, :updated_at
    remove_column :incoming_request_messages, :sent_at
    remove_column :incoming_request_messages, :applied_at
    remove_column :incoming_request_messages, :masked_body
    remove_column :incoming_request_messages, :send_attachments
  end

  # 戻さないもの:
  # - up で元に戻せない操作(final)にした、これまでの操作。どれを final にしたかは残していない。
  # - up のあとにできた操作の変化(AuditChange)のうち、Todo::StatusChange・IncomingRequest::Settlement・
  #   IncomingRequestMessage::Delivery・Adoption のもの。表を消すので、その操作を元に戻す・やり直すと Conflict になる。
  # - up で埋めた done_at・resolved_on(済みで日時の無いやること・解決した日の無い依頼)。
  def down
    add_column :incoming_request_messages, :send_attachments, :boolean, default: false, null: false
    add_column :incoming_request_messages, :masked_body, :text, default: "", null: false
    add_column :incoming_request_messages, :applied_at, :datetime
    add_column :incoming_request_messages, :sent_at, :datetime
    add_column :incoming_request_messages, :updated_at, :datetime
    rename_column :incoming_request_messages, :written_at, :created_at
    execute "UPDATE incoming_request_messages SET updated_at = created_at"
    execute <<~SQL
      UPDATE incoming_request_messages SET
        sent_at = (SELECT delivered_at FROM incoming_request_message_deliveries d WHERE d.message_id = incoming_request_messages.id),
        masked_body = COALESCE((SELECT masked_body FROM incoming_request_message_deliveries d WHERE d.message_id = incoming_request_messages.id), ''),
        send_attachments = COALESCE((SELECT send_attachments FROM incoming_request_message_deliveries d WHERE d.message_id = incoming_request_messages.id), 0),
        applied_at = (SELECT adopted_at FROM incoming_request_message_adoptions a WHERE a.message_id = incoming_request_messages.id)
    SQL
    change_column_null :incoming_request_messages, :updated_at, false
    # todos と incoming_requests の「いまの状態」の列は、イベントを分けたあとも同じ値を持っているので戻さなくてよい
    drop_table :incoming_request_message_adoptions
    drop_table :incoming_request_message_deliveries
    drop_table :incoming_request_settlements
    drop_table :todo_status_changes
  end
end
