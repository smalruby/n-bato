require "test_helper"

# 手続き・決議・提出のイベント(docs/adr/0038)。データは架空。
class ProcedureResolutionEventsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @run = ProcedureRun.create!(kind: "annual_report", period: 2025)
    @report = AnnualReport.create!(fiscal_year: 2025)
  end

  def op(scope = "procedure:#{@run.id}", &) = Audit.operation(user: @user, scope:) { ApplicationRecord.transaction(&) }
  def change!(key, status, **) = ProcedureStep::StatusChange.change!(@run.step(key), status:, by: @user, **)

  def board_resolution(*names)
    people = names.map { Person.create!(name: it) }
    people.each { OfficerTerm.create!(person: it, role: "director", starts_on: Date.new(2026, 4, 1), ends_on: Date.new(2028, 3, 31)) }
    resolution = Resolution.create!(body: "board", voting_method: "written", title: "架空の理事会", proposed_on: Date.new(2026, 5, 1), proposer: people.first)
    [ resolution, people ]
  end

  # --- 手順 ---

  test "手順の保存する状態は、最後の状態の変化から決まる。直接は書き換えられない" do
    change!("close_books", "done", on: Date.new(2026, 4, 10))
    step = @run.procedure_steps.find_by!(key: "close_books")
    assert_equal [ "done", Date.new(2026, 4, 10) ], [ step[:status], step.completed_on ]
    assert_equal @user, step.status_changes.last.changed_by
    assert_equal 2025, step.status_changes.last.audit_fiscal_year

    assert_raises(ActiveRecord::RecordInvalid) { step.update!(status: "open") }
    error = assert_raises(ActiveRecord::RecordInvalid) { ProcedureStep.create!(procedure_run: @run, key: "audit", status: "done") }
    assert_match "ProcedureStep::StatusChange.change!", error.message
    step.reload.update!(note: "メモは直せる", checks: { "通帳を記帳した" => "2026-04-10" })
    assert_empty ModelVerification.mismatches

    step.update_column(:completed_on, Date.new(2026, 4, 11))
    assert_match "手順 ##{step.id}", ModelVerification.mismatches.join
  end

  test "同じ状態なら何もしない。取り消せない手順は取り消さない" do
    assert_nil change!("close_books", "open")
    change!("close_books", "done")
    assert_nil change!("close_books", "done")
    assert_equal 1, ProcedureStep::StatusChange.count

    create_annual_report!(2026)
    run = ProcedureRun.create!(kind: "annual_report", period: 2026)
    AnnualReport::Milestone.record!(AnnualReport.find_by!(fiscal_year: 2026), "submitted", on: Date.new(2027, 6, 1))
    ProcedureStep::StatusChange.change!(run.step("submit"), status: "done")
    error = assert_raises(ArgumentError) { ProcedureStep::StatusChange.change!(run.step("submit"), status: "open") }
    assert_equal "この手順は取り消せません", error.message
    assert_raises(ArgumentError) { change!("close_books", "unknown") }
  end

  test "操作の外で呼んでも、手順の列・イベント・効き目を 1 つの操作にする" do
    assert_difference -> { AuditOperation.count }, 1 do
      ProcedureStep::StatusChange.change!(@run.step("publish_bs"), status: "done", on: Date.new(2026, 6, 10))
    end
    op = AuditOperation.last
    assert_equal %w[ProcedureStep ProcedureStep::StatusChange AnnualReport AnnualReport::Milestone], op.audit_changes.map(&:auditable_type)
    assert_equal "済みにした: 貸借対照表を公告する", op.label
    assert_equal Date.new(2026, 6, 10), @report.reload.bs_published_on
  end

  test "final の手順を済みにするのは元に戻せない操作" do
    AnnualReport::Milestone.record!(@report, "submitted", on: Date.new(2026, 6, 1))
    op { change!("submit", "done", on: Date.new(2026, 6, 1)) }
    assert_equal "final", AuditOperation.last.kind
  end

  test "元に戻すと、状態の変化と事業報告の節目も消え、前の状態に戻る。やり直すと戻る" do
    step = @run.step("publish_bs").tap { it.update!(note: "先にメモを書いた") }
    op { change!("publish_bs", "done", on: Date.new(2026, 6, 10)) }
    Audit.undo!(@user, "procedure:#{@run.id}")
    assert_equal [ "open", nil ], [ step.reload[:status], @report.reload.bs_published_on ]
    assert_empty step.status_changes
    assert_empty @report.milestones
    assert_empty ModelVerification.mismatches
    Audit.redo!(@user, "procedure:#{@run.id}")
    assert_equal [ "done", Date.new(2026, 6, 10) ], [ step.reload[:status], @report.reload.bs_published_on ]
    assert_empty ModelVerification.mismatches
  end

  test "別の操作で同じ状態に戻ったあと(A → B → A)に古い操作を元に戻すと、Conflict で止める" do
    step = @run.step("close_books").tap { it.update!(note: "先にメモを書いた") }
    op { change!("close_books", "done", on: Date.new(2026, 4, 10)) }
    # 運用のスクリプト(範囲なし)で、取り消してまた済みにした
    ProcedureStep::StatusChange.change!(step, status: "open")
    ProcedureStep::StatusChange.change!(step.reload, status: "done", on: Date.new(2026, 4, 10))
    error = assert_raises(Audit::Conflict) { Audit.undo!(@user, "procedure:#{@run.id}") }
    assert_match "手続きの手順(##{step.id})のstatus", error.message
    assert_equal "done", step.reload[:status]
    assert_empty ModelVerification.mismatches
  end

  test "手順の記録を作った操作を、あとで別の操作が変えていたら、元に戻すは Conflict(500 にしない)" do
    op { change!("close_books", "done") }
    ProcedureStep::StatusChange.change!(@run.procedure_steps.find_by!(key: "close_books"), status: "open")
    assert_raises(Audit::Conflict) { Audit.undo!(@user, "procedure:#{@run.id}") }
  end

  test "二度押しで、まだ無かった手順をもう一方が先に作っていても、2 つ目は何もしない" do
    first = ProcedureRun.find(@run.id).step("close_books")
    second = ProcedureRun.find(@run.id).step("close_books")
    ProcedureStep::StatusChange.change!(first, status: "done")
    assert_nil ProcedureStep::StatusChange.change!(second, status: "done")
    assert_equal 1, ProcedureStep::StatusChange.count
  end

  test "手続きを始める: もう始めてあれば同じ手続き(二度押しでも 1 つ)" do
    run = ProcedureRun.start!(kind: "officer_election", period: 2026)
    assert_equal run, ProcedureRun.start!(kind: "officer_election", period: 2026)
    # 二度押しで、もう一方が先に作った(一意の索引で止まる)ときも、作ってあった手続きを返す
    overriding(ProcedureRun, :find_by, ->(*, **) {}) do
      overriding(ProcedureRun, :create!, ->(*, **) { raise ActiveRecord::RecordNotUnique, "UNIQUE constraint failed" }) do
        assert_equal run, ProcedureRun.start!(kind: "officer_election", period: 2026)
      end
    end
    assert_equal 1, ProcedureRun.where(kind: "officer_election").count
  end

  # 二度押しの競り合い(古い記録を読んでいた)を作るため、クラスメソッドを一時的に差し替える
  def overriding(klass, name, impl)
    klass.singleton_class.alias_method(:"__orig_#{name}", name)
    klass.define_singleton_method(name, &impl)
    yield
  ensure
    klass.singleton_class.alias_method(name, :"__orig_#{name}")
    klass.singleton_class.remove_method(:"__orig_#{name}")
  end

  test "二度押しで、まだ無かった手順の記録を作る競り合いになっても 500 にしない(一意の索引)" do
    ProcedureStep::StatusChange.change!(@run.step("close_books"), status: "done")
    late = ProcedureRun.find(@run.id).procedure_steps.build(key: "close_books")
    overriding(ProcedureStep, :find_by, ->(*) {}) do
      late.define_singleton_method(:valid?) { |*| true }
      error = assert_raises(ArgumentError) { ProcedureStep::StatusChange.change!(late, status: "skipped") }
      assert_equal "もう対象外にしてあります", error.message
    end
    assert_equal 1, ProcedureStep::StatusChange.count
  end

  # --- 事業報告 ---

  test "事業報告の日付は、節目の種類ごとに最後の記録から決まる。同じ日付なら記録しない。空にもできる" do
    AnnualReport::Milestone.record!(@report, "submitted", on: "2026-06-01", by: @user)
    assert_nil AnnualReport::Milestone.record!(@report, "submitted", on: Date.new(2026, 6, 1))
    AnnualReport::Milestone.record!(@report, "submitted", on: "", by: @user)
    assert_nil @report.reload.submitted_on
    assert_equal [ Date.new(2026, 6, 1), nil ], @report.milestones.map(&:dated_on)
    assert_equal "2025年度の事業報告: 所轄庁への提出日を消した", AuditOperation.last.label

    assert_raises(ActiveRecord::RecordInvalid) { @report.update!(approved_on: Date.current) }
    assert_raises(ActiveRecord::RecordInvalid) { AnnualReport.create!(fiscal_year: 2030, submitted_on: Date.current) }
    @report.reload.update!(achievements: "中身は直せる")
    assert_empty ModelVerification.mismatches
    @report.update_column(:approved_on, Date.current)
    assert_match "事業報告 2025年度: approved_on", ModelVerification.mismatches.join
  end

  test "締めた年度を直すと、決まりで「出し直しが要る」を付ける。直したのを元に戻すと印も外れる" do
    AnnualReport::Milestone.record!(@report, "submitted", on: Date.new(2026, 6, 1))
    FiscalPeriod.create!(year: 2025, closed_on: Date.new(2026, 6, 2))
    Audit.operation(user: @user, scope: "journal_entries", label: "締めた年度を直した") do
      @report.update!(achievements: "直した")
      FiscalPeriod.changed_after_close!(2025)
    end
    op = AuditOperation.last
    assert_equal "締めた年度を直した", op.label, "決まりの節目は、包んだ操作の名前を変えない"
    assert_equal Date.current, @report.reload.resubmit_needed_on
    milestone = @report.milestones.last
    assert milestone.automatic
    assert_nil milestone.recorded_by

    Audit.undo!(@user, "journal_entries")
    assert_nil @report.reload.resubmit_needed_on
    assert_empty ModelVerification.mismatches
  end

  test "事業報告の画面の保存: 日付が変わった欄だけ記録し、保存できなければ記録しない" do
    assert @report.save_with_dates("submitted_on" => "2026-06-01", "approved_on" => "", "bs_published_on" => nil)
    assert_equal [ "submitted" ], @report.milestones.map(&:kind)

    other = AnnualReport.new(fiscal_year: 2025)
    assert_not other.save_with_dates("submitted_on" => "2026-06-02")
    assert_equal "2026-06-02", other.submitted_on.to_s, "画面に戻すときは入れた日付を出す"
    assert_equal 1, AnnualReport::Milestone.count
  end

  # --- 決議 ---

  test "同意: 取り消しても消さず、成立に数えない。記録し直せる。二重には記録しない" do
    resolution, (a, b) = board_resolution("理事A", "理事B")
    first = Consent.record!(resolution, person: a, consented_on: Date.new(2026, 5, 2), via: "email")
    Consent.record!(resolution, person: b, consented_on: Date.new(2026, 5, 3))
    assert_equal Date.new(2026, 5, 3), resolution.reload.established_on
    error = assert_raises(ActiveRecord::RecordInvalid) { Consent.record!(resolution, person: a, consented_on: Date.new(2026, 5, 4)) }
    assert_match "もう記録してあります", error.message

    assert_difference -> { AuditOperation.count }, 1 do
      Consent::Cancellation.cancel!(first, by: @user)
    end
    assert_not resolution.reload.established?
    assert_equal 2, resolution.all_consents.count
    assert_equal "もう取り消してあります", assert_raises(ArgumentError) { Consent::Cancellation.cancel!(first.reload) }.message
    # 古い記録を読んでいた二度押し(一意の制約)も、500 にせず伝える
    stale = Consent.find(first.id).tap { it.cancellation }
    stale.association(:cancellation).target = nil
    assert_equal "もう取り消してあります", assert_raises(ArgumentError) { Consent::Cancellation.cancel!(stale) }.message

    Consent.record!(resolution, person: a, consented_on: Date.new(2026, 5, 5))
    assert_equal Date.new(2026, 5, 5), resolution.reload.established_on
    assert_empty ModelVerification.mismatches

    error = assert_raises(ActiveRecord::RecordNotDestroyed) { resolution.destroy! }
    assert_match "同意を記録した決議は消せません", error.record.errors.full_messages.join
  end

  test "取り消していない同意が 2 つあれば model:verify が知らせる" do
    resolution, (a, _) = board_resolution("理事A")
    Consent.record!(resolution, person: a, consented_on: Date.new(2026, 5, 2))
    Consent.insert!({ resolution_id: resolution.id, person_id: a.id, consented_on: Date.new(2026, 5, 3), via: "paper", note: "" })
    assert_match "取り消していない同意が 2 つ", ModelVerification.mismatches.join
  end

  test "議案の反映: 1 つの操作で元に戻せない。二度押しは「もう反映してあります」" do
    resolution, (a, _) = board_resolution("理事A")
    item = resolution.items.create!(kind: "officer_mutual_election", title: "互選", payload: { "appointments" => [ { "person_id" => a.id, "role" => "chair" } ] })
    assert_equal "決議が成立していません", assert_raises(ArgumentError) { ResolutionItem::Application.apply!(item) }.message
    Consent.record!(resolution, person: a, consented_on: Date.new(2026, 5, 2))

    stale = ResolutionItem.find(item.id).tap(&:application) # まだ反映していないと読んだ
    assert_difference -> { AuditOperation.count }, 1 do
      ResolutionItem::Application.apply!(item.reload, by: @user)
    end
    op = AuditOperation.last
    assert_equal "final", op.kind
    assert_includes op.audit_changes.map(&:auditable_type), "Registration"
    assert_equal [ "chair", Date.new(2026, 5, 2) ], [ OfficerTerm.find_by!(person: a).role, Registration.last.cause_on ]
    assert_equal Date.current, item.reload.applied_on
    assert_equal [ item ], ResolutionItem.applied.to_a
    assert_equal "もう記録に反映してあります", assert_raises(ArgumentError) { ResolutionItem::Application.apply!(item) }.message
    assert_equal "もう記録に反映してあります", assert_raises(ArgumentError) { ResolutionItem::Application.apply!(stale) }.message
    assert_equal 1, ResolutionItem::Application.count
    overriding(ResolutionItem::Application, :exists?, ->(*) { false }) do
      officer = resolution.items.create!(kind: "officer_election", title: "選任", payload: { "appointments" => [] })
      ResolutionItem::Application.apply!(officer)
      racing = ResolutionItem.find(officer.id).tap(&:application)
      racing.association(:application).target = nil
      assert_equal "もう記録に反映してあります", assert_raises(ArgumentError) { ResolutionItem::Application.apply!(racing) }.message
    end

    resolution.reload.items_attributes = [ { id: item.id, _destroy: "1" } ]
    assert_not resolution.save
    assert_match "記録に反映した議案は消せません", resolution.errors.full_messages.join
  end

  test "会議で決めた決議(同意なし)も、反映した議案があれば消せない" do
    chair = Person.create!(name: "理事A")
    resolution = Resolution.create!(body: "board", voting_method: "meeting", title: "架空の理事会", proposed_on: Date.new(2026, 5, 1),
                                    held_on: Date.new(2026, 5, 2), proposer: chair)
    item = resolution.items.create!(kind: "officer_election", title: "選任", payload: { "appointments" => [] })
    ResolutionItem::Application.apply!(item)
    assert_not resolution.reload.destroy
    assert_equal [ "記録に反映した議案のある決議は消せません" ], resolution.errors.full_messages
  end

  test "議案の反映が途中で失敗したら、外のトランザクションの中でも途中までの変更を残さない" do
    resolution, (a, b) = board_resolution("理事A", "理事B")
    [ a, b ].each { Consent.record!(resolution, person: it, consented_on: Date.new(2026, 5, 2)) }
    nobody = Person.create!(name: "任期の無い人")
    item = resolution.items.create!(kind: "officer_mutual_election", title: "互選",
                                    payload: { "appointments" => [ { "person_id" => a.id, "role" => "chair" }, { "person_id" => nobody.id, "role" => "vice_chair" } ] })
    op("resolutions") do
      assert_raises(ActiveRecord::RecordNotFound) { ResolutionItem::Application.apply!(item, by: @user) }
    end
    assert_equal "director", OfficerTerm.find_by!(person: a).role
    assert_empty Registration.all
    assert_not item.reload.applied?
  end

  test "事業報告の承認を反映すると、承認の節目を記録する" do
    resolution, (a, _) = board_resolution("理事A")
    item = resolution.items.create!(kind: "annual_report_approval", title: "承認", fiscal_year: 2025)
    Consent.record!(resolution, person: a, consented_on: Date.new(2026, 5, 2))
    ResolutionItem::Application.apply!(item, by: @user)
    assert_equal Date.new(2026, 5, 2), @report.reload.approved_on
    assert_equal [ [ "approved", @user ] ], @report.milestones.map { [ it.kind, it.recorded_by ] }
    general = resolution.items.create!(kind: "general", title: "一般")
    assert_raises(ArgumentError) { ResolutionItem::Application.apply!(general) }
  end
end
