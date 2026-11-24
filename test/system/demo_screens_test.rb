require "application_system_test_case"

# 架空のデータの環境で、AI がログインして画面を確かめる道筋(issue #14)
class DemoScreensTest < ApplicationSystemTestCase
  test "パスワードでログインし、左のメニューの画面をすべて開ける" do
    sign_in_as_ai
    assert_text "NPO法人見本こども会"

    links = all("nav.nb-nav a").map { [it.text.strip, it[:href]] }
    assert_operator links.size, :>=, 15
    links.each do |label, href|
      visit href
      assert_selector "main#main", wait: 5
      assert_no_text "Action Controller: Exception caught"
      assert_title(/N\(エヌ\)ばと/)
      assert_selector "nav.nb-nav a[aria-current=page]", text: label # いま開いている画面がメニューで選ばれている
    end
  end

  test "詳しい画面も開ける(手続き・決議・人・登記の申請・証憑・入会申込・依頼)" do
    sign_in_as_ai
    [procedure_path(ProcedureRun.order(:id).last), resolution_path(Resolution.order(:id).first), person_path(Person.order(:id).first),
      registration_filing_path(RegistrationFiling.order(:id).last), voucher_path(Voucher.order(:id).last),
      member_application_path(MemberApplication.order(:id).first), incoming_request_path(IncomingRequest.first),
      fiscal_year_path(@demo.year - 1), annual_report_path(@demo.year - 1), member_applications_path, balance_checks_path,
      opening_balances_path, siwake_imports_path, passkeys_path].each do |path|
      visit path
      assert_selector "main#main"
      assert_no_text "Action Controller: Exception caught"
    end
  end

  test "印刷用の書類(計算書類・元帳・議事録・登記の申請書)も開ける" do
    sign_in_as_ai
    year = @demo.year - 1
    gm = Resolution.find_by!(body: "general_meeting")
    [fiscal_year_statement_path(year, "activity"), fiscal_year_statement_path(year, "balance_sheet"), fiscal_year_ledgers_path(year),
      document_resolution_path(gm, "minutes"), document_registration_filing_path(RegistrationFiling.order(:id).last, "mutual_election")].each do |path|
      visit path
      assert_no_text "Action Controller: Exception caught"
      assert_operator page.text.strip.size, :>, 50, "#{path} が空です"
    end
  end

  test "入力するとすぐ保存され、元に戻す・やり直すができる" do
    sign_in_as_ai
    visit accounts_path
    account = Account.find_by!(fiscal_year: @demo.year, code: 510)
    input = find_field("#{account.display_name}の小区分")
    input.fill_in(with: "寄付(架空)")
    input.send_keys(:tab)

    assert_selector ".nb-save--saved", text: "保存しました"
    assert_equal "寄付(架空)", account.reload.group_name

    click_on "元に戻す"
    assert_field "#{account.display_name}の小区分", with: ""
    assert_nil account.reload.group_name.presence

    click_on "やり直す"
    assert_field "#{account.display_name}の小区分", with: "寄付(架空)"
    assert_equal "寄付(架空)", account.reload.group_name
  end

  test "仕訳の削除は 2 回押し(ダイアログを出さない。開発QAボード 第8回 8-3)" do
    sign_in_as_ai
    entry = JournalEntry.order(:id).find { it.editable? && !FiscalPeriod.for(it.fiscal_year)&.closed? } # 締めた年度は理由が要るので外す
    visit journal_entry_path(entry)

    click_on "削除"
    assert_button "もう一度押すと、この仕訳を削除します"
    assert JournalEntry.exists?(entry.id)

    click_on "もう一度押すと、この仕訳を削除します"
    assert_no_current_path journal_entry_path(entry)
    assert_not JournalEntry.exists?(entry.id)
  end

  test "他の年度に切り替えると、その年度の札と帯が出る" do
    sign_in_as_ai
    visit fiscal_years_path
    assert_selector ".nb-year-chip", text: "#{@demo.year}年度"

    closed = @demo.year - 2
    find(".nb-year-switch summary").click
    within(".nb-year-menu") { click_on "#{closed}年度" }
    assert_selector ".nb-year-chip", text: "#{closed}年度"
    assert_selector ".nb-year-band", text: "締めた年度です"
    assert_equal closed, User.find_by!(email_address: Demo::EMAIL).working_year
  end

  test "スマホの幅(390px)でも開けて、ページが横にはみ出さない" do
    sign_in_as_ai
    page.driver.with_playwright_page { it.set_viewport_size(width: 390, height: 844) }
    [root_path, todos_path, people_path, journal_entries_path, procedures_path, resolutions_path].each do |path|
      visit path
      assert_selector "main#main"
      assert_equal 0, horizontal_overflow, "#{path} が横にはみ出しています"
    end
  end
end
