require "test_helper"
require Rails.root.join("db/migrate/20261124100000_create_todo_and_request_events")

# マイグレーション 20261124100000(やること・依頼をイベントへ。docs/adr/0034)。
# テストのデータベースとは別の、使い捨ての SQLite に、いまのスキーマを写して down で移す前の形に戻し、
# 移す前の形の行(架空)を入れてから up で移す。
class CreateTodoAndRequestEventsMigrationTest < ActiveSupport::TestCase
  # 使い捨てのデータベースは、テストのトランザクションに入れない(テストのデータベースには書かない)
  self.use_transactional_tests = false

  # 使い捨ての SQLite につなぐので、アプリの接続(ApplicationRecord)とは分ける
  class Scratch < ActiveRecord::Base # standard:disable Rails/ApplicationRecord
    self.abstract_class = true
  end

  setup do
    @dir = Dir.mktmpdir
    Scratch.establish_connection(adapter: "sqlite3", database: File.join(@dir, "migration.sqlite3"))
    @conn = Scratch.connection
    ActiveRecord::Base.connection.select_values("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY rowid").each { @conn.execute(it) }
    migrate(:down)
  end

  teardown do
    Scratch.remove_connection
    FileUtils.remove_entry(@dir)
  end

  def migrate(direction)
    verbose, ActiveRecord::Migration.verbose = ActiveRecord::Migration.verbose, false
    CreateTodoAndRequestEvents.new.exec_migration(@conn, direction)
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  def insert(table, attrs)
    now = "2026-11-20 01:00:00"
    attrs = {"created_at" => now, "updated_at" => now}.merge(attrs.transform_keys(&:to_s)) if @conn.column_exists?(table, :updated_at)
    @conn.execute("INSERT INTO #{table} (#{attrs.keys.join(", ")}) VALUES (#{attrs.values.map { @conn.quote(it) }.join(", ")})")
    @conn.select_value("SELECT last_insert_rowid()")
  end

  def rows(sql) = @conn.select_all(sql).to_a

  def operation(kind: "do", state: "active", redoable: false, changes: [])
    id = insert(:audit_operations, user_id: nil, scope: "todos", kind:, state:, redoable:)
    changes.each { |type, event| insert(:audit_changes, audit_operation_id: id, auditable_type: type, auditable_id: 1, event:, changeset: "{}") }
    id
  end

  test "いまの列からイベントを作る(おかしな行も)" do
    todo = ->(status, **rest) { insert(:todos, title: "架空のやること", status:, **rest) }
    plain = todo.call("todo", waiting_on: "残り")
    doing = todo.call("doing", waiting_on: "前の待ち", done_note: "前のひとこと", updated_at: "2026-11-21 02:00:00")
    wait = todo.call("wait", waiting_on: "監事の返事")
    done = todo.call("done", done_at: "2026-11-22 03:00:00", done_by: "auto", done_note: "決まりで")
    no_time = todo.call("done", done_at: nil, done_by: "user", updated_at: "2026-11-23 04:00:00")

    open = insert(:incoming_requests, title: "進行中")
    resolved = insert(:incoming_requests, title: "解決", status: "resolved", resolved_on: "2026-11-10")
    # 日本時間では 11/24 の 1:30(UTC では 11/23)
    no_day = insert(:incoming_requests, title: "解決した日が無い", status: "resolved", resolved_on: nil, updated_at: "2026-11-23 16:30:00")

    draft = insert(:incoming_request_messages, incoming_request_id: open, role: "user", body: "下書き", created_at: "2026-11-19 00:00:00")
    sent = insert(:incoming_request_messages, incoming_request_id: open, role: "user", body: "送った", masked_body: "伏せた", send_attachments: true, sent_at: "2026-11-19 01:00:00")
    adopted = insert(:incoming_request_messages, incoming_request_id: open, role: "assistant", body: "案", applied_at: "2026-11-19 02:00:00")
    insert(:incoming_request_messages, incoming_request_id: open, role: "assistant", body: "決めていない案")

    migrate(:up)

    changes = rows("SELECT todo_id, status, waiting_on, note, automatic, changed_at FROM todo_status_changes ORDER BY todo_id").index_by { it["todo_id"] }
    assert_equal [doing, wait, done, no_time], changes.keys
    assert_nil changes[plain]
    assert_equal ["doing", "", "", 0], changes[doing].values_at("status", "waiting_on", "note", "automatic"), "作業中には、前の待ち・ひとことを持ち込まない"
    assert_match "2026-11-21 02:00:00", changes[doing]["changed_at"]
    assert_equal ["wait", "監事の返事"], changes[wait].values_at("status", "waiting_on")
    assert_equal ["done", "決まりで", 1], changes[done].values_at("status", "note", "automatic")
    assert_match "2026-11-22 03:00:00", changes[done]["changed_at"]
    assert_match "2026-11-23 04:00:00", changes[no_time]["changed_at"], "済みで日時の無いものは更新した日時"
    assert_match "2026-11-23 04:00:00", @conn.select_value("SELECT done_at FROM todos WHERE id = #{no_time}")

    settled = rows("SELECT incoming_request_id, settled_on FROM incoming_request_settlements").to_h { [it["incoming_request_id"], it["settled_on"]] }
    assert_equal({resolved => "2026-11-10", no_day => "2026-11-24"}, settled, "解決した日の無いものは、日本時間の更新した日")
    assert_equal "2026-11-24", @conn.select_value("SELECT resolved_on FROM incoming_requests WHERE id = #{no_day}")

    assert_equal [[sent, "伏せた", 1]], @conn.select_rows("SELECT message_id, masked_body, send_attachments FROM incoming_request_message_deliveries")
    assert_equal [adopted], @conn.select_values("SELECT message_id FROM incoming_request_message_adoptions")
    assert_match "2026-11-19 00:00:00", @conn.select_value("SELECT written_at FROM incoming_request_messages WHERE id = #{draft}")
    assert_equal %w[id incoming_request_id role body proposal written_at].sort, @conn.columns(:incoming_request_messages).map(&:name).sort
  end

  test "やること・依頼・発言に触れたこれまでの操作は、元に戻せない操作にする(作成・削除も)" do
    final = {
      "やることの変更" => operation(changes: [%w[Todo update]]),
      "やることの作成" => operation(changes: [%w[Todo create]]),
      "やることの削除" => operation(changes: [%w[Todo destroy]]),
      "依頼の作成" => operation(changes: [%w[IncomingRequest create]]),
      "依頼の削除" => operation(changes: [%w[IncomingRequest destroy]]),
      "発言の作成" => operation(changes: [%w[IncomingRequestMessage create]]),
      "下書きを消した(元に戻した操作。やり直せる)" => operation(state: "undone", redoable: true, changes: [%w[IncomingRequestMessage destroy]]),
      "ほかの記録と一緒に" => operation(changes: [%w[JournalEntry update], %w[Todo update]])
    }
    kept = {
      "ほかの記録だけ" => [operation(changes: [%w[JournalEntry update]]), "do"],
      "元に戻した記録" => [operation(kind: "undo", changes: [%w[Todo update]]), "undo"],
      "変更の無い操作" => [operation, "do"]
    }

    migrate(:up)

    kinds = rows("SELECT id, kind FROM audit_operations").to_h { [it["id"], it["kind"]] }
    final.each { |name, id| assert_equal "final", kinds[id], name }
    kept.each { |name, (id, kind)| assert_equal kind, kinds[id], name }
  end

  test "down: 発言の列を戻し、イベントの表を消す(やること・依頼の列はそのまま)" do
    req = insert(:incoming_requests, title: "解決", status: "resolved", resolved_on: "2026-11-10")
    todo = insert(:todos, title: "架空のやること", status: "wait", waiting_on: "返事")
    sent = insert(:incoming_request_messages, incoming_request_id: req, role: "user", body: "送った", masked_body: "伏せた", send_attachments: true,
      sent_at: "2026-11-19 01:00:00", created_at: "2026-11-19 00:00:00")
    adopted = insert(:incoming_request_messages, incoming_request_id: req, role: "assistant", body: "案", applied_at: "2026-11-19 02:00:00")
    migrate(:up)
    migrate(:down)

    %w[todo_status_changes incoming_request_settlements incoming_request_message_deliveries incoming_request_message_adoptions].each do
      assert_not @conn.table_exists?(it), it
    end
    m = rows("SELECT * FROM incoming_request_messages ORDER BY id").index_by { it["id"] }
    assert_equal ["伏せた", 1], m[sent].values_at("masked_body", "send_attachments")
    assert_match "2026-11-19 01:00:00", m[sent]["sent_at"]
    assert_match "2026-11-19 00:00:00", m[sent]["created_at"]
    assert_equal m[sent]["created_at"], m[sent]["updated_at"]
    assert_match "2026-11-19 02:00:00", m[adopted]["applied_at"]
    assert_equal ["", 0, nil], m[adopted].values_at("masked_body", "send_attachments", "sent_at")
    assert_equal ["wait", "返事"], @conn.select_rows("SELECT status, waiting_on FROM todos WHERE id = #{todo}").first
    assert_equal ["resolved", "2026-11-10"], @conn.select_rows("SELECT status, resolved_on FROM incoming_requests WHERE id = #{req}").first

    migrate(:up)
    assert_equal 1, @conn.select_value("SELECT COUNT(*) FROM incoming_request_message_deliveries"), "移し直せる"
  end
end
