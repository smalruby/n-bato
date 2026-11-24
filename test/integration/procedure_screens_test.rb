require "test_helper"

# 年に一度の手続きの一覧と、手順のメモ・済みの取り消し・対象外
class ProcedureScreensTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    ensure_organization
    FiscalPeriod.ensure!
  end

  test "一覧: 操作している年度の手続きと、始められる手続き" do
    last_year = FiscalYear.current.year - 1
    get year_switch_path(last_year)
    get procedures_path
    assert_response :success
    assert_match "まだ始めた手続きはありません", response.body
    assert_select "form[action=?]", procedures_path(kind: "annual_report", period: last_year), 1, "まだ始めていなければ「始める」に出す"

    run = ProcedureRun.create!(kind: "annual_report", period: last_year)
    get procedures_path
    assert_select "a.nb-proc-name[href=?]", procedure_path(run), text: "事業報告書等の提出"
    assert_select ".nb-next a[href=?]", procedure_path(run, step: run.next_step.key)
    assert_select "form[action=?]", procedures_path(kind: "annual_report", period: last_year), 0, "始めた手続きは「始める」に出さない"
  end

  test "メモは自動保存、済みを取り消す、対象外にする" do
    run = ProcedureRun.create!(kind: "annual_report", period: 2025)
    patch procedure_step_path(run, "close_books", format: :json), params: { note: "通帳は来週", undo_scope: "procedure:#{run.id}" }
    assert response.parsed_body["ok"]
    assert_equal "通帳は来週", run.step("close_books").reload.note

    post complete_procedure_step_path(run, "close_books")
    post reopen_procedure_step_path(run, "close_books")
    assert_equal "済みを取り消しました", flash[:notice]
    assert_nil run.procedure_steps.find_by!(key: "close_books").completed_on

    post skip_procedure_step_path(run, "corporate_tax"), params: { reason: "収益事業はしていない" }
    assert_match "対象外にしました", flash[:notice]
    assert_equal "skipped", run.procedure_steps.find_by!(key: "corporate_tax").status
  end
end
