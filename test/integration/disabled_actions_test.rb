require "test_helper"

# 使えない操作は灰色のボタン + (i) で理由を出す(デザインシステム DisabledAction、見直し第22回)。データは架空。
class DisabledActionsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    ensure_organization
    FiscalPeriod.ensure!
    @chair = Person.create!(name: "役員A")
    @member = Person.create!(name: "会員B")
    OfficerTerm.create!(person: @chair, role: "chair", starts_on: Date.current - 30, ends_on: Date.current + 300)
    [@chair, @member].each { Membership.create!(person: it, fiscal_year: FiscalYear.current.year, kind: "regular") }
    @resolution = Resolution.create!(body: "general_meeting", voting_method: "written", title: "書面決議", proposed_on: Date.current, proposer: @chair,
      items_attributes: [{position: 0, kind: "officer_election", title: "第1号議案", appointments_text: ""}])
  end

  # 灰色のボタンの aria-describedby が、説明(.nb-tip)の id を指す
  def assert_disabled_action(label)
    button = css_select(".nb-disabled-action button[aria-disabled=true]").find { it.text.strip == label }
    assert button, "灰色の「#{label}」がある"
    tip = css_select("##{button["aria-describedby"]}").first
    assert tip, "説明がつながっている"
    assert tip.key?("hidden"), "説明は閉じてある"
    trigger = css_select(".nb-info-tip[aria-controls='#{button["aria-describedby"]}']").first
    assert_equal ["使えない理由", "false"], [trigger["aria-label"], trigger["aria-expanded"]]
    tip
  end

  test "決議: 同意の無い決議は 2 回押しで消せる" do
    get resolution_path(@resolution)
    assert_select "form[data-controller=confirm-twice] button.nb-btn--danger", text: "削除"
    assert_select ".nb-disabled-action", count: 0
    delete resolution_path(@resolution)
    assert_redirected_to resolutions_path
    assert_not Resolution.exists?(@resolution.id)
  end

  test "決議: 同意を記録したら、削除は灰色で、理由・件数・リンク・代わりにを出す。取り消した同意も見える" do
    first = Consent.record!(@resolution, person: @chair, consented_on: Date.current)
    Consent::Cancellation.cancel!(first)
    Consent.record!(@resolution, person: @chair, consented_on: Date.current)
    get resolution_path(@resolution)
    tip = assert_disabled_action("削除")
    assert_match "この決議は消せません", tip.text
    assert_match "同意の記録が 2 件あります(取り消した 1 件を含む)", tip.text
    assert_match "代わりに: 件名・提案日・議案の中身は「編集」で直せます。", tip.text
    assert_select tip, "a[href='#consents']", text: "同意の記録を見る(2 件)"
    assert_select "#consents .nb-cancelled-tag", text: "取消"
    assert_select "#consents", text: /役員A .*に取り消した/

    delete resolution_path(@resolution)
    assert_redirected_to resolution_path(@resolution)
    assert_equal @resolution.destroy_blocked_reason.message, flash[:alert]
  end

  test "決議: 反映した議案は、編集の画面で「この議案を削除」が灰色。同意の取り消しも灰色" do
    [@chair, @member].each { Consent.record!(@resolution, person: it, consented_on: Date.current) }
    ResolutionItem::Application.apply!(@resolution.items.first)
    get resolution_path(@resolution)
    tip = assert_disabled_action("取り消す")
    assert_match "この同意は取り消せません", tip.text
    assert_select tip, "a[href='#items']", text: "議案を見る"
    assert_select "#items"

    get edit_resolution_path(@resolution)
    box = css_select("input[type=checkbox][disabled]").find { it["aria-describedby"] }
    assert box
    tip = css_select("##{box["aria-describedby"]}").first
    assert_match "この議案は消せません", tip.text
    assert_select ".nb-info .nb-info-tip"
  end

  test "年度: 次の年度を締めてあれば、締めを解くは灰色" do
    FiscalPeriod.where(year: ..(FiscalYear.current.year)).update_all(closed_on: Date.current)
    get fiscal_year_path(FiscalYear.current.year - 1)
    tip = assert_disabled_action("締めを解く")
    assert_match "この年度の締めは解けません", tip.text
    get fiscal_year_path(FiscalYear.current.year)
    assert_select "button", text: "締めを解く"
    assert_select ".nb-disabled-action", count: 0
  end

  test "手順: final を済みにしたら、済みを取り消すは灰色" do
    AnnualReport.create!(fiscal_year: 2025)
    run = ProcedureRun.start!(kind: "annual_report", period: 2025)
    ProcedureStep::StatusChange.change!(run.step("submit"), status: "done", on: Date.new(2026, 6, 28))
    get procedure_path(run, step: "submit")
    tip = assert_disabled_action("済みを取り消す")
    assert_match "この手順は取り消せません", tip.text

    get procedure_path(run, step: "audit")
    tip = assert_disabled_action("この手順を済みにする")
    assert_select tip, "a[href='#waits']"
    assert_select "#waits"
  end
end
