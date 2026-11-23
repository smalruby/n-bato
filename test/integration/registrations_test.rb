require "test_helper"

# 登記の画面と、登記の申請(見直し第20回)・住所・氏名の移り変わり。値はすべて架空。
class RegistrationsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    @org = ensure_organization
    @chair = Person.create!(name: "山田　太郎", address: "テスト県テスト市1-1")
    @vice = Person.create!(name: "田中　花子", address: "テスト県テスト市2-2")
    @term = OfficerTerm.create!(person: @chair, role: "chair", starts_on: Date.new(2024, 7, 1), ends_on: Date.new(2026, 6, 30))
    OfficerTerm.create!(person: @vice, role: "vice_chair", starts_on: Date.new(2024, 7, 1), ends_on: Date.new(2026, 6, 30))
    OfficerTerm.create!(person: Person.create!(name: "佐藤　次郎"), role: "director", starts_on: Date.new(2024, 7, 1), ends_on: Date.new(2026, 6, 30))
  end

  test "住所が変わった・氏名が変わった・取り消す(人の画面)" do
    post person_address_changes_path(@vice), params: { address: "テスト県テスト市3-3", year: "2025", month: "4", day: "" }
    assert_redirected_to person_path(@vice, anchor: "person-history")
    post person_name_changes_path(@vice), params: { name: "鈴木　花子", year: "2025", month: "9", day: "8", show_former_name: "1" }
    get person_path(@vice)
    assert_select "#person-history tbody tr", 3
    assert_select "#person-history", text: /2025\/04\(日は不明\)/
    assert_select "#person-history", text: /登記がいる\(期限は日が分かってから\)/
    assert_select "dd", text: "鈴木　花子（田中　花子）"
    get edit_person_path(@vice)
    assert_select "input[name='person[address]']", 0
    nc = @vice.reload.latest_name_change
    post person_change_cancellation_path(@vice, change_type: "name", change_id: nc.id), params: { reason: "打ち間違い" }
    assert nc.reload.cancelled?
    post person_change_cancellation_path(@vice, change_type: "address", change_id: 999_999), params: { reason: "x" }
    assert_response :not_found
    post person_change_cancellation_path(@vice, change_type: "zzz", change_id: 1), params: { reason: "x" }
    assert_equal "key not found: \"zzz\"", flash[:alert]
    post person_address_changes_path(@vice), params: { address: "", year: "2025", month: "5" }
    assert_match "新しい住所", flash[:alert]
    post person_name_changes_path(@vice), params: { name: "x", year: "", month: "" }
    assert_match "年と月", flash[:alert]
  end

  test "出来事の無い人は、記録の始まりの値を直せる(打ち間違い)" do
    patch person_path(@chair), params: { person: { name: "山田　一郎", address: "テスト県テスト市1-2" } }
    assert_equal "山田　一郎", @chair.reload.name
    assert_equal "テスト県テスト市1-2", @chair.address_at_start
    get edit_person_path(@chair)
    assert_select "input[name='person[address]']"
  end

  test "登記の画面: 申請システムへのボタン・登記がいること・申請を始める" do
    get registrations_path
    assert_select "a[href='https://www.touki-kyoutaku-online.moj.go.jp/'][target=_blank]", text: /登記・供託オンライン申請システムを開く/
    assert_select ".nb-online-now", text: /いまは使え/
    assert_select ".nb-online-note a[href*='condition']"
    reg = @term.registrations.first
    assert_select "input[name='registration_ids[]'][value='#{reg.id}']"
    post registration_filings_path, params: { registration_ids: [] }
    assert_match "1 つ以上", flash[:alert]
    post registration_filings_path, params: { registration_ids: Registration.pluck(:id) }
    filing = RegistrationFiling.last
    assert_redirected_to filing
    follow_redirect!
    assert_select "#matters-text", text: /「資格」理事/
    assert_select "button[data-controller=copy]", text: "登記すべき事項の文をコピー"
    assert_select ".nb-reg-steps li.is-now", text: "書類を作る"
    assert_select "a[href=?]", document_registration_filing_path(filing, doc: "mutual_election", format: :pdf)
    get registrations_path
    assert_select "a[href=?]", registration_filing_path(filing)
  end

  test "申請の流れ: 外す・足す・決議を選ぶ・申請した・受付・補正・完了" do
    regs = Registration.order(:id).to_a
    filing = RegistrationFiling.start!(regs)
    post exclude_registration_filing_path(filing, registration_id: regs.last.id)
    assert_nil regs.last.reload.registration_filing
    get registration_filing_path(filing)
    assert_select "select[name=registration_id] option[value='#{regs.last.id}']"
    post include_registration_filing_path(filing, registration_id: regs.last.id)
    assert_equal filing, regs.last.reload.registration_filing
    post include_registration_filing_path(filing, registration_id: regs.last.id)
    assert_match "ほかの申請", flash[:alert]
    post exclude_registration_filing_path(filing, registration_id: regs.last.id)
    proposer = @chair
    gm = Resolution.create!(body: "general_meeting", title: "役員の選任", proposed_on: Date.new(2024, 6, 1), proposer:)
    patch registration_filing_path(filing), params: { registration_filing: { general_meeting_resolution_id: gm.id } }
    assert_equal gm, filing.reload.general_meeting_resolution
    get registration_filing_path(filing)
    assert_select "a[href=?]", document_resolution_path(gm, doc: "minutes", format: :pdf)

    post registration_filing_submission_path(filing), params: { on: "", application_number: "1" }
    assert_match "日付", flash[:alert]
    post registration_filing_submission_path(filing), params: { on: "2026-12-01", application_number: "A-1" }
    assert_equal "submitted", filing.reload.status
    post exclude_registration_filing_path(filing, registration_id: regs.first.id)
    assert_match "変えられません", flash[:alert]
    post registration_filing_acceptance_path(filing), params: { on: "2026-12-02", receipt_number: "R-1" }
    post registration_filing_corrections_path(filing), params: { on: "2026-12-03", note: "" }
    assert_match "求められたこと", flash[:alert]
    post registration_filing_corrections_path(filing), params: { on: "2026-12-03", note: "日付を直す" }
    get registration_filing_path(filing)
    assert_select ".nb-reg-events", text: /申請番号 A-1/
    assert_select ".nb-reg-events", text: /受付番号 R-1/
    post registration_filing_completion_path(filing), params: { on: "2026-12-08" }
    assert filing.reload.completed?
    post registration_filing_acceptance_path(filing), params: { on: "2026-12-09" }
    assert_match "まだ申請", flash[:alert]
    post registration_filing_completion_path(filing), params: { on: "2026-12-09" }
    assert_match "終わった", flash[:alert]
    get registrations_path
    assert_select "h2", text: "登記したこと"
  end

  test "取り下げ・添付書類(内訳・互選書・定款)" do
    filing = RegistrationFiling.start!(Registration.all.to_a)
    FilingDestination::Confirmation.confirm!(FilingDestination.create!(kind: "registry", name: "テスト地方法務局"), by: users(:one))
    get document_registration_filing_path(filing, doc: "cover")
    assert_select "h1", "書面により提出する添付書面の内訳"
    assert_select "p", text: "テスト地方法務局　御中"
    assert_select "a", text: "← 登記の申請に戻る"
    get document_registration_filing_path(filing, doc: "mutual_election")
    assert_select "h1", "理 事 の 互 選 書"
    assert_select "p", text: /理事長に理事山田　太郎（テスト県テスト市1-1）を選定すること/
    assert_select "p", text: /\A理\p{Zs}事\p{Zs}佐藤　次郎/
    get document_registration_filing_path(filing, doc: "articles")
    assert_select "p", text: /定款の版が登録されていません/
    get document_registration_filing_path(filing, doc: "zzz")
    assert_response :not_found
    post registration_filing_withdrawal_path(filing), params: { on: "2026-12-01", reason: "" }
    assert_match "理由", flash[:alert]
    post registration_filing_withdrawal_path(filing), params: { on: "2026-12-01", reason: "まとめ直す" }
    assert filing.reload.withdrawn?
    post registration_filing_completion_path(filing), params: { on: "2026-12-01" }
    assert_match "終わった", flash[:alert]
  end

  test "住所・氏名の変更だけの申請は、互選書がいらない" do
    Person::AddressChange.record!(@vice, address: "テスト県テスト市3-3", moved_on: Date.new(2025, 4, 10))
    filing = RegistrationFiling.start!(Registration.where(kind: "address_change").to_a)
    get document_registration_filing_path(filing, doc: "mutual_election")
    assert_select "p", text: /互選書はいりません/
  end

  test "監査の役割では、申請を始めたり記録したりできない(見るだけ)" do
    filing = RegistrationFiling.start!(Registration.all.to_a)
    users(:one).update!(role: "auditor")
    get registration_filing_path(filing)
    assert_response :success
    assert_select "button", text: "申請したことを記録する", count: 0
    post registration_filings_path, params: { registration_ids: [] }
    assert_match "監査", flash[:alert]
    post registration_filing_submission_path(filing), params: { on: "2026-12-01" }
    assert_match "監査", flash[:alert]
    assert filing.reload.drafting?
  end
end
