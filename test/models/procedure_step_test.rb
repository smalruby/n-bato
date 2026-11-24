require "test_helper"

class ProcedureStepTest < ActiveSupport::TestCase
  setup do
    chair = Person.create!(name: "理事 一郎")
    auditor = Person.create!(name: "監事 花子")
    member = Person.create!(name: "会員 次郎")
    today = Date.current
    OfficerTerm.create!(person: chair, role: "chair", starts_on: today - 30, ends_on: today + 300)
    OfficerTerm.create!(person: auditor, role: "auditor", starts_on: today - 30, ends_on: today + 300)
    Membership.create!(person: member, fiscal_year: FiscalYear.current.year, kind: "regular")
  end

  test "返事を待つ人を役員・正会員の記録から出す" do
    election = ProcedureRun.create!(kind: "officer_election", period: 2026)
    assert_equal [ "理事 一郎(理事長)", "監事 花子(監事)" ], election.step("candidates").people_waited_for
    assert_equal [ "理事 一郎(理事長)" ], election.step("mutual_election").people_waited_for
    assert_equal [ "会員 次郎" ], election.step("general_meeting").people_waited_for
    assert_equal [], election.step("notify_city").people_waited_for
  end

  test "改選の手続きは年で数え、期限は 6 月 30 日" do
    election = ProcedureRun.create!(kind: "officer_election", period: 2026)
    assert_equal "2026年", election.period_label
    assert_equal Date.new(2026, 6, 30), election.due_on
  end

  test "チェックを外す・済みを解く・対象外にする" do
    run = ProcedureRun.create!(kind: "annual_report", period: 2025)
    step = run.step("close_books")
    step.check!("通帳を記帳した")
    step.uncheck!("通帳を記帳した")
    assert_not step.checked?("通帳を記帳した")
    assert step.applicable?, "出る条件の無い手順はいつも当てはまる"

    ProcedureStep::StatusChange.change!(step, status: "done")
    assert_equal "done", step.reload.status
    ProcedureStep::StatusChange.change!(step, status: "open")
    assert_nil step.reload.completed_on
    assert_not_equal "done", step.status

    assert_equal %w[done open], step.status_changes.map(&:status)

    tax = run.step("corporate_tax") # 対象外にできるのは、定義で optional の手順だけ
    ProcedureStep::StatusChange.change!(tax, status: "skipped", reason: "今年は対象外")
    assert_equal [ "skipped", "今年は対象外" ], [ tax.reload.status, tax.note ]
    ProcedureStep::StatusChange.change!(tax, status: "open")
    ProcedureStep::StatusChange.change!(tax, status: "skipped", reason: "")
    assert_equal "今年は対象外", tax.reload.note, "理由が空なら前のメモを残す"
    assert_equal %w[skipped open skipped], tax.status_changes.map(&:status)
  end

  test "公告・再提出の手順を済みにすると、事業報告に日付が入る" do
    report = create_annual_report!(2025, submitted_on: Date.new(2026, 6, 1), resubmit_needed_on: Date.new(2026, 7, 1))
    run = ProcedureRun.create!(kind: "annual_report", period: 2025)
    ProcedureStep::StatusChange.change!(run.step("publish_bs"), status: "done", on: Date.new(2026, 6, 10))
    ProcedureStep::StatusChange.change!(run.step("resubmit"), status: "done", on: Date.new(2026, 7, 5))
    report.reload
    assert_equal Date.new(2026, 6, 10), report.bs_published_on
    assert_equal Date.new(2026, 7, 5), report.resubmitted_on
  end
end
