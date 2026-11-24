require "test_helper"

class ProceduresHelperTest < ActionView::TestCase
  setup do
    @run = ProcedureRun.create!(kind: "annual_report", period: 2025)
  end

  test "手順の状態の補足" do
    step = @run.step("close_books")
    assert_equal "未着手", step_meta(step)

    step.check!("通帳を記帳した")
    assert_match %r{\A1/\d+ 確認\z}, step_meta(step)

    ProcedureStep::StatusChange.change!(step, status: "done", on: Date.new(2026, 4, 10))
    assert_equal "済み 2026/04/10", step_meta(step)

    skipped = @run.step("corporate_tax")
    ProcedureStep::StatusChange.change!(skipped, status: "skipped")
    assert_equal "対象外", step_meta(skipped)
  end

  test "記録から済みと分かる手順と、返事を待つ手順" do
    create_annual_report!(2025, submitted_on: Date.new(2026, 6, 1))
    assert_equal "済み(記録から)", step_meta(ProcedureRun.find(@run.id).step("submit"))

    election = ProcedureRun.create!(kind: "officer_election", period: 2026)
    person = Person.create!(name: "理事A")
    OfficerTerm.create!(person:, role: "director", starts_on: Date.current - 30, ends_on: Date.current + 300)
    step = election.step("mutual_election")
    step.note = "依頼した"
    assert_equal "waiting", step.status
    assert_equal "返事 0/1", step_meta(step)
  end

  test "期限の表示: 済み・超過・あと何日" do
    travel_to Date.new(2026, 6, 1) do
      assert_match "あと 29 日", due_badge(@run)
      assert_match "nb-due--soon", due_badge(@run)
    end
    travel_to Date.new(2026, 1, 1) do
      assert_no_match "nb-due--soon", due_badge(@run)
    end
    travel_to Date.new(2026, 7, 2) { assert_match "2 日超過", due_badge(@run) }

    create_annual_report!(2025)
    FiscalPeriod.create!(year: 2025)
    @run.steps.each { ProcedureStep::StatusChange.change!(it, status: it.definition.optional? ? "skipped" : "done") }
    assert_match "済み", due_badge(ProcedureRun.find(@run.id))
  end

  test "手順の定義のリンク: 事業報告が無ければ作る画面へ、帳票は出さない" do
    assert_match "事業報告を作る", procedure_link("annual_report_edit", @run)
    assert_nil procedure_link("document_business_report", @run)
    assert_nil procedure_link("pack", @run)

    AnnualReport.create!(fiscal_year: 2025)
    run = ProcedureRun.find(@run.id)
    { "annual_report_edit" => "事業報告を書く", "document_business_report" => "事業報告書(帳票)", "document_letter" => "提出書(帳票)",
      "pack" => "書類一式(帳票)", "resolutions" => "決議の一覧", "new_resolution" => "決議を作る", "people" => "会員・役員",
      "officer_terms" => "役員の任期", "registrations" => "登記", "articles" => "定款と事業(主な活動)",
      "fiscal_year" => "2025年度の会計", "balance_checks" => "残高の照合" }.each do |name, label|
      assert_match label, procedure_link(name, run)
    end
    assert_nil procedure_link("知らないリンク", run)
  end
end
