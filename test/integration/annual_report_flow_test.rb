require "test_helper"

class AnnualReportFlowTest < ActionDispatch::IntegrationTest
  setup do
    import_sample
    Organization.create!(name: "NPO法人テスト", address: "島根県テスト市", representative_title: "理事長", representative_name: "役員A",
      first_fiscal_year: 2023, competent_authority: "テスト市", phone: "000-0000-0000")
    [2024, 2025].product((111..113).to_a).each { |year, code|
      Department.find_or_create_by!(fiscal_year: year, code: code) {
        it.name = "#{code}事業"
        it.full_name = "事業#{code}"
      }
    }
    people = (1..10).map { Person.create!(name: "会員#{it}", address: "テスト市#{it}") }
    people.each { Membership.create!(person: it, fiscal_year: 2024, kind: "regular") }
    OfficerTerm.create!(person: people[0], role: "chair", starts_on: Date.new(2022, 7, 1), ends_on: Date.new(2024, 6, 30))
    OfficerTerm.create!(person: people[1], role: "auditor", starts_on: Date.new(2022, 7, 1), ends_on: Date.new(2024, 6, 30))
    sign_in
  end

  test "事業報告書を作り、提出書類を一式で出す" do
    get annual_reports_path
    assert_match "期限切れ", response.body

    get new_annual_report_path(year: 2024)
    assert_response :success
    activities = Department.where(code: 111..113).order(:code).each_with_index.to_h do |d, i|
      [i.to_s, {department_id: d.id, position: i, content: "内容#{i}", schedule: "", beneficiaries: "", report: (i == 2) ? "| 日付 | 人数 |\n|---|---|\n| 5/1 | 3人 |" : ""}]
    end
    post annual_reports_path, params: {annual_report: {fiscal_year: 2024, achievements: "教室を開いた", member_counts: {regular: "13"},
                                                       letter_date: "2026-11-20", program_activities_attributes: activities}}
    assert_redirected_to annual_report_path(2024)
    follow_redirect!
    # 見直し第21回: PDF は別のタブ(↗)、題の上にパンくず
    assert_select "a[href=?][target=_blank][rel=noopener]", pack_annual_report_path(2024, format: :pdf), text: /↗/
    assert_select "nav.nb-crumb a[href=?]", annual_reports_path
    report = AnnualReport.find_by!(fiscal_year: 2024)
    assert_equal 13, report.member_count("regular")
    assert_equal 0, report.member_count("student")

    get document_annual_report_path(2024, "business_report")
    assert_response :success
    assert_match "教室を開いた", response.body
    assert_match "1,200", response.body # ③事業の消耗品費(活動計算書から)
    assert_match "<table>", response.body.gsub(/<table class="[^"]*">/, "")

    get document_annual_report_path(2024, "officer_roster")
    assert_match "会員1", response.body
    assert_match "理事長", response.body
    assert_match "令和６年４月１日から", response.body

    get document_annual_report_path(2024, "member_roster")
    assert_match "テスト市10", response.body

    get document_annual_report_path(2024, "letter")
    assert_match "令和８年１１月２０日", response.body
    assert_match "（あて先）(所轄庁の宛先が未設定)", response.body, "確認済みの所轄庁が無ければ、推測で埋めない"
    d = FilingDestination.create!(kind: "authority", name: "テスト市", addressee: "テスト市長　山田　太郎")
    FilingDestination::Confirmation.confirm!(d, by: users(:one))
    get document_annual_report_path(2024, "letter")
    assert_match "（あて先）テスト市長　山田　太郎", response.body
    assert_pdf pack_annual_report_path(2024, format: :pdf)
  end

  test "事業報告書の無い年度へ切り替えると一覧へ戻る" do
    report = AnnualReport.create!(fiscal_year: 2024)
    get year_switch_path(2025), headers: {"HTTP_REFERER" => "http://www.example.com#{annual_report_path(2024)}"}
    assert_redirected_to annual_reports_path
    get year_switch_path(2024), headers: {"HTTP_REFERER" => "http://www.example.com#{annual_report_path(2024)}"}
    assert_redirected_to annual_report_path(report.fiscal_year)
  end

  test "提出日を記録する" do
    AnnualReport.draft_for(2024).save!
    patch annual_report_path(2024), params: {annual_report: {submitted_on: "2026-11-20"}}
    assert_equal Date.new(2026, 11, 20), AnnualReport.find_by!(fiscal_year: 2024).submitted_on
    get annual_reports_path
    assert_match "提出済み", response.body
  end

  test "前年度を写して下書きを作る" do
    prev = AnnualReport.draft_for(2024)
    prev.achievements = "前年度の成果"
    prev.save!
    draft = AnnualReport.draft_for(2025)
    assert_equal "前年度の成果", draft.achievements
    assert_equal 3, draft.program_activities.size
  end

  test "編集の画面・保存できなければ戻す・書類一式を HTML で出す" do
    post annual_reports_path, params: {annual_report: {fiscal_year: "", achievements: "x"}}
    assert_response :unprocessable_entity

    AnnualReport.draft_for(2024).save!
    AnnualReport.draft_for(2025).save!
    get edit_annual_report_path(2024)
    assert_response :success
    patch annual_report_path(2024), params: {annual_report: {fiscal_year: 2025}}
    assert_response :unprocessable_entity

    get pack_annual_report_path(2024)
    assert_response :success
    assert_match "事業報告書等一式", response.body
  end
end
