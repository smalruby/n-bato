require "test_helper"
require Rails.root.join("db/migrate/20261125100000_create_procedure_and_resolution_events")

# マイグレーション 20261125100000(手続き・決議・提出をイベントへ。docs/adr/0038)。
# テストのデータベースとは別の、使い捨ての SQLite に、いまのスキーマを写して down で移す前の形に戻し、
# 移す前の形の行(架空)を入れてから up で移す。
class CreateProcedureAndResolutionEventsMigrationTest < ActiveSupport::TestCase
  # 使い捨てのデータベースは、テストのトランザクションに入れない(テストのデータベースには書かない)
  self.use_transactional_tests = false

  class Scratch < ActiveRecord::Base
    self.abstract_class = true
  end

  setup do
    @dir = Dir.mktmpdir
    Scratch.establish_connection(adapter: "sqlite3", database: File.join(@dir, "migration.sqlite3"))
    @conn = Scratch.connection
    ActiveRecord::Base.connection.select_values("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY rowid").each { @conn.execute(it) }
    migrate(:down)
    @person = insert(:people, name: "架空の人")
    @other = insert(:people, name: "架空の人2")
  end

  teardown do
    Scratch.remove_connection
    FileUtils.remove_entry(@dir)
  end

  def migrate(direction)
    verbose, ActiveRecord::Migration.verbose = ActiveRecord::Migration.verbose, false
    CreateProcedureAndResolutionEvents.new.exec_migration(@conn, direction)
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  def insert(table, attrs)
    now = "2026-11-20 01:00:00"
    attrs = { "created_at" => now, "updated_at" => now }.merge(attrs.transform_keys(&:to_s)) if @conn.column_exists?(table, :updated_at)
    @conn.execute("INSERT INTO #{table} (#{attrs.keys.join(', ')}) VALUES (#{attrs.values.map { @conn.quote(it) }.join(', ')})")
    @conn.select_value("SELECT last_insert_rowid()")
  end

  def rows(sql) = @conn.select_all(sql).to_a

  def operation(kind: "do", state: "active", redoable: false, changes: [])
    id = insert(:audit_operations, user_id: nil, scope: "procedure:1", kind:, state:, redoable:)
    changes.each { |type, event| insert(:audit_changes, audit_operation_id: id, auditable_type: type, auditable_id: 1, event:, changeset: "{}") }
    id
  end

  def resolution = insert(:resolutions, body: "board", title: "架空の決議", proposed_on: "2026-05-01", proposer_id: @person)

  test "いまの列からイベントを作る(おかしな行も)" do
    run = insert(:procedure_runs, kind: "annual_report", period: 2025)
    step = ->(key, status, **rest) { insert(:procedure_steps, procedure_run_id: run, key:, status:, **rest) }
    open = step.("close_books", "open", note: "メモ")
    done = step.("business_report", "done", completed_on: "2026-05-10", updated_at: "2026-05-10 03:00:00")
    # 日本時間では 11/24 の 1:30(UTC では 11/23)
    no_day = step.("audit", "done", completed_on: nil, updated_at: "2026-11-23 16:30:00")
    skipped = step.("corporate_tax", "skipped", completed_on: "2026-05-01", note: "収益事業なし")
    reopened = step.("board", "open", completed_on: "2026-05-02")
    odd = step.("print", "doing")

    report = insert(:annual_reports, fiscal_year: 2025, approved_on: "2026-06-20", submitted_on: "2026-06-28", resubmit_needed_on: "2026-07-01",
                                     updated_at: "2026-07-01 00:00:00")
    plain = insert(:annual_reports, fiscal_year: 2024)

    r = resolution
    applied = insert(:resolution_items, resolution_id: r, kind: "officer_election", title: "選任", applied_on: "2026-05-05")
    insert(:resolution_items, resolution_id: r, kind: "general", title: "一般")
    consent = insert(:consents, resolution_id: r, person_id: @person, consented_on: "2026-05-03", via: "email")

    migrate(:up)

    changes = rows("SELECT procedure_step_id, status, completed_on, note FROM procedure_step_status_changes ORDER BY procedure_step_id").index_by { it["procedure_step_id"] }
    assert_equal [ done, no_day, skipped ], changes.keys
    assert_equal [ "done", "2026-05-10", "" ], changes[done].values_at("status", "completed_on", "note")
    assert_equal [ "done", "2026-11-24" ], changes[no_day].values_at("status", "completed_on"), "済みで日付の無いものは、日本時間の更新した日"
    assert_equal [ "skipped", "2026-05-01", "収益事業なし" ], changes[skipped].values_at("status", "completed_on", "note")
    steps = rows("SELECT id, status, completed_on FROM procedure_steps").index_by { it["id"] }
    assert_equal [ "open", nil ], steps[reopened].values_at("status", "completed_on"), "open で日付が残ったものは日付を消す"
    assert_equal [ "open", nil ], steps[odd].values_at("status", "completed_on"), "決まった値でない状態は open"
    assert_equal [ "open", nil ], steps[open].values_at("status", "completed_on")
    assert_equal "2026-11-24", steps[no_day]["completed_on"]

    milestones = rows("SELECT annual_report_id, kind, dated_on, automatic FROM annual_report_milestones ORDER BY kind")
    assert_equal [ [ report, "approved", "2026-06-20", 0 ], [ report, "resubmit_needed", "2026-07-01", 1 ], [ report, "submitted", "2026-06-28", 0 ] ],
                 milestones.map(&:values)
    assert_not milestones.any? { it["annual_report_id"] == plain }

    assert_equal [ [ applied, "2026-05-05" ] ], @conn.select_rows("SELECT resolution_item_id, applied_on FROM resolution_item_applications")
    assert_not @conn.column_exists?(:resolution_items, :applied_on)
    assert_not @conn.column_exists?(:consents, :created_at)
    assert_equal [ consent ], @conn.select_values("SELECT id FROM consents")
    # 取り消したあとに同じ人の同意を記録し直せる(一意の索引を外した)
    insert(:consent_cancellations, consent_id: consent, cancelled_at: "2026-05-04 00:00:00")
    insert(:consents, resolution_id: r, person_id: @person, consented_on: "2026-05-04", via: "paper")
    assert_equal 2, @conn.select_value("SELECT COUNT(*) FROM consents")
  end

  test "手続き・決議・提出に触れたこれまでの操作は、元に戻せない操作にする(作成・削除も)" do
    final = {
      "手順の変更" => operation(changes: [ %w[ProcedureStep update] ]),
      "手順の作成" => operation(changes: [ %w[ProcedureStep create] ]),
      "手続きの作成" => operation(changes: [ %w[ProcedureRun create] ]),
      "事業報告の変更" => operation(changes: [ %w[AnnualReport update] ]),
      "決議の削除" => operation(changes: [ %w[Resolution destroy] ]),
      "議案の変更" => operation(changes: [ %w[ResolutionItem update] ]),
      "同意の削除(元に戻した操作。やり直せる)" => operation(state: "undone", redoable: true, changes: [ %w[Consent destroy] ]),
      "ほかの記録と一緒に" => operation(changes: [ %w[JournalEntry update], %w[Consent create] ])
    }
    kept = {
      "ほかの記録だけ" => [ operation(changes: [ %w[ProgramActivity update] ]), "do" ],
      "元に戻した記録" => [ operation(kind: "undo", changes: [ %w[ProcedureStep update] ]), "undo" ],
      "変更の無い操作" => [ operation, "do" ]
    }

    migrate(:up)

    kinds = rows("SELECT id, kind FROM audit_operations").to_h { [ it["id"], it["kind"] ] }
    final.each { |name, id| assert_equal "final", kinds[id], name }
    kept.each { |name, (id, kind)| assert_equal kind, kinds[id], name }
  end

  test "down: 議案の反映日・同意の列と一意の索引を戻し、イベントの表を消す(取り消した同意は消す)" do
    r = resolution
    item = insert(:resolution_items, resolution_id: r, kind: "officer_election", title: "選任", applied_on: "2026-05-05")
    run = insert(:procedure_runs, kind: "annual_report", period: 2025)
    insert(:procedure_steps, procedure_run_id: run, key: "audit", status: "done", completed_on: "2026-05-10")
    insert(:annual_reports, fiscal_year: 2025, submitted_on: "2026-06-28")
    migrate(:up)
    cancelled = insert(:consents, resolution_id: r, person_id: @person, consented_on: "2026-05-03", via: "email")
    insert(:consent_cancellations, consent_id: cancelled, cancelled_at: "2026-05-04 00:00:00")
    kept = insert(:consents, resolution_id: r, person_id: @person, consented_on: "2026-05-04", via: "paper")
    migrate(:down)

    %w[procedure_step_status_changes annual_report_milestones resolution_item_applications consent_cancellations].each do
      assert_not @conn.table_exists?(it), it
    end
    assert_equal "2026-05-05", @conn.select_value("SELECT applied_on FROM resolution_items WHERE id = #{item}")
    assert_equal [ kept ], @conn.select_values("SELECT id FROM consents")
    assert_match "2026-05-04", @conn.select_value("SELECT created_at FROM consents")
    assert @conn.indexes(:consents).find { it.columns == %w[resolution_id person_id] }.unique
    assert_equal [ "done", "2026-05-10" ], @conn.select_rows("SELECT status, completed_on FROM procedure_steps").first
    assert_equal "2026-06-28", @conn.select_value("SELECT submitted_on FROM annual_reports")

    migrate(:up)
    assert_equal 1, @conn.select_value("SELECT COUNT(*) FROM resolution_item_applications"), "移し直せる"
    assert_equal 1, @conn.select_value("SELECT COUNT(*) FROM annual_report_milestones")
  end
end
