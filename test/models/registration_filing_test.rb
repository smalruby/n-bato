require "test_helper"

# 登記の申請(見直し第20回、docs/adr/0031)。値はすべて架空。
# 登記すべき事項の書き方の出典: https://houmukyoku.moj.go.jp/homu/content/001386707.pdf (NPO 法人の重任)・
# 001252906.pdf (住所移転)・001252648.pdf / 001252649.pdf (氏変更・旧氏の併記)
class RegistrationFilingTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @chair = Person.create!(name: "山田　太郎", address: "テスト県テスト市1-1")
    @vice = Person.create!(name: "田中　花子", address: "テスト県テスト市2-2")
    @old_chair = OfficerTerm.create!(person: @chair, role: "chair", starts_on: Date.new(2022, 7, 1), ends_on: Date.new(2024, 6, 30))
    @chair_term = OfficerTerm.create!(person: @chair, role: "chair", starts_on: Date.new(2024, 7, 1), ends_on: Date.new(2026, 6, 30))
    @vice_term = OfficerTerm.create!(person: @vice, role: "vice_chair", starts_on: Date.new(2024, 7, 1), ends_on: Date.new(2026, 6, 30))
  end

  def reg_for(term) = term.registrations.first

  test "代表権のある任期ができると登記の事由ができ、重任か就任かを決める" do
    assert reg_for(@chair_term).reappointment?, "前の任期からすき間なく続くので重任"
    assert_not reg_for(@vice_term).reappointment?, "初めての代表なので就任"
    assert_not reg_for(@old_chair).reappointment?
    assert reg_for(@chair_term).available?
    assert_equal Date.new(2024, 7, 15), reg_for(@chair_term).due_on
    assert reg_for(@old_chair).overdue?(Date.new(2026, 11, 24))
  end

  test "登記すべき事項: 重任・就任・住所移転・旧氏を併記した氏変更を、人ごとにまとめる" do
    Person::AddressChange.record!(@vice, address: "テスト県テスト市3-3", moved_on: Date.new(2025, 4, 10))
    Person::NameChange.record!(@vice, name: "鈴木　花子", changed_on: Date.new(2025, 9, 8), show_former_name: true)
    regs = [reg_for(@chair_term), reg_for(@vice_term), *Registration.where(kind: %w[address_change name_change])]
    filing = RegistrationFiling.start!(regs)
    st = filing.statement
    assert_equal <<~TEXT.chomp, st.matters
      「役員に関する事項」
      「資格」理事
      「住所」テスト県テスト市1-1
      「氏名」山田　太郎
      「原因年月日」令和6年7月1日重任
      「役員に関する事項」
      「資格」理事
      「住所」テスト県テスト市3-3
      「氏名」鈴木　花子（田中　花子）
      「原因年月日」令和6年7月1日就任
      「原因年月日」令和7年4月10日住所移転
      「原因年月日」令和7年9月8日田中　花子の氏変更
    TEXT
    assert_equal "理事の変更、理事の住所変更、理事の氏変更", st.reason
    assert_includes st.attachments, "就任承諾書は、社員総会議事録の記載を援用する。"
    assert_includes st.attachments, "理事の互選書（又は理事会議事録）　１通"
    assert(st.warnings.any? { it.include?("1 件の申請にまとめられるか") })
    assert_equal Date.new(2025, 9, 8), st.as_of
    earlier = st.warnings.select { it.include?("前の任期が Nばとに記録されていない") }
    assert_equal [@vice.reload.name], earlier.map { it.split(":").first }, "就任とした理由を確かめてもらう(重任の人には出さない)"
  end

  test "日が分からない住所の変更は、推測で日を埋めずに確かめることに出す" do
    Person::AddressChange.record!(@vice, address: "テスト県テスト市3-3", moved_on: Date.new(2025, 4, 1), date_precision: "month")
    filing = RegistrationFiling.start!(Registration.where(kind: "address_change").to_a)
    assert_includes filing.statement.matters, "「原因年月日」【日が不明: 2025/04(日は不明)。住民票で確かめる】住所移転"
    assert(filing.statement.warnings.any? { it.include?("住民票(除票を含む)") })
    assert_equal ["（住所・氏名の変更は、本人が申請するので添付書類はありません。旧氏を併記するときは戸籍の証明書など）"], filing.statement.attachments
  end

  test "氏と名を区切れない氏名・住所が空の人は、確かめることに出す" do
    @vice.update_columns(address: nil)
    Person::NameChange.record!(@vice, name: "鈴木花子", changed_on: Date.new(2025, 9, 8))
    filing = RegistrationFiling.start!(Registration.where(kind: "name_change").to_a)
    w = filing.statement.warnings
    assert(w.any? { it.include?("氏と名を空白で区切っていない") })
    assert(w.any? { it.include?("住所が空です") })
    assert_includes filing.statement.matters, "「住所」【住所が空】"
    assert_equal "理事の氏名変更", filing.statement.reason
  end

  test "始める・足す・外す: 書類を作っている間だけ" do
    assert_raises(ArgumentError) { RegistrationFiling.start!([]) }
    filing = RegistrationFiling.start!([reg_for(@chair_term)])
    assert_raises(ArgumentError) { RegistrationFiling.start!([reg_for(@chair_term)]) }
    assert_equal :done, filing.step_state("items")
    assert_equal :now, filing.step_state("documents")
    assert_equal :skip, filing.step_state("correcting")
    filing.include!(reg_for(@vice_term))
    assert_raises(ArgumentError) { filing.include!(reg_for(@vice_term)) }
    filing.exclude!(reg_for(@vice_term))
    assert_nil reg_for(@vice_term).reload.registration_filing
    filing.exclude!(reg_for(@vice_term)) # 入っていなければ何もしない
    filing.exclude!(reg_for(@chair_term))
    assert_equal :now, filing.reload.step_state("items")
    assert_raises(ArgumentError) { RegistrationFiling::Submission.submit!(filing, submitted_on: Date.current) }
  end

  test "申請した → 受付 → 補正 → 完了。完了で登記した日が入り、待っていたやることが作業中に戻る" do
    todo = Todo.create!(title: "登記後の証明書を送る", resume_rule: "registration_completed").tap { Todo::StatusChange.change!(it, status: "wait", waiting_on: "登記") }
    other = Todo.create!(title: "ほかの待ち").tap { Todo::StatusChange.change!(it, status: "wait") }
    filing = RegistrationFiling.start!([reg_for(@chair_term), reg_for(@vice_term)])
    assert_raises(ArgumentError) { RegistrationFiling::Acceptance.accept!(filing, accepted_on: Date.current) }
    assert_raises(ArgumentError) { RegistrationFiling::Completion.complete!(filing, completed_on: Date.current) }
    RegistrationFiling::Submission.submit!(filing, submitted_on: Date.new(2026, 12, 1), application_number: " 12345 ", by: @user)
    assert_equal "submitted", filing.reload.status
    assert_equal "12345", filing.submission.application_number
    assert_raises(ArgumentError) { filing.include!(Registration.create!(kind: "other", cause_on: Date.current)) }
    assert_raises(ArgumentError) { filing.exclude!(reg_for(@chair_term)) }
    assert_raises(ArgumentError) { RegistrationFiling::Submission.submit!(filing, submitted_on: Date.current) }
    assert_equal :now, filing.step_state("accepted")
    RegistrationFiling::Acceptance.accept!(filing, accepted_on: Date.new(2026, 12, 2), receipt_number: "678", by: @user)
    assert_equal "accepted", filing.reload.status
    assert_equal :now, filing.step_state("completed")
    assert_raises(ArgumentError) { RegistrationFiling::Correction.record!(filing, noticed_on: Date.current, note: " ") }
    RegistrationFiling::Correction.record!(filing, noticed_on: Date.new(2026, 12, 3), note: "互選書の日付", by: @user)
    assert_equal "correcting", filing.reload.status
    assert_equal :now, filing.step_state("correcting")
    RegistrationFiling::Completion.complete!(filing, completed_on: Date.new(2026, 12, 8), by: @user)
    filing.reload
    assert filing.completed? && filing.finished?
    assert_equal :done, filing.step_state("correcting")
    assert_equal :done, filing.step_state("completed")
    assert_equal [Date.new(2026, 12, 8)], filing.registrations.map(&:registered_on).uniq
    assert_equal "doing", todo.reload.status
    assert_match "登記が完了した(2026/12/08)", todo.note
    assert_equal "wait", other.reload.status
    assert_equal "登記の申請が完了したら", todo.resume_rule_label
    assert_raises(ArgumentError) { RegistrationFiling::Withdrawal.withdraw!(filing, withdrawn_on: Date.current, reason: "x") }
    assert_raises(ArgumentError) { RegistrationFiling::Correction.record!(filing, noticed_on: Date.current, note: "x") }
    assert_empty ModelVerification.mismatches
  end

  test "取り下げると、登記の事由は新しい申請に入れ直せる" do
    filing = RegistrationFiling.start!([reg_for(@chair_term)])
    assert_raises(ArgumentError) { RegistrationFiling::Withdrawal.withdraw!(filing, withdrawn_on: Date.current, reason: " ") }
    RegistrationFiling::Withdrawal.withdraw!(filing, withdrawn_on: Date.new(2026, 12, 1), reason: "まとめ直す", by: @user)
    assert filing.reload.withdrawn?
    assert reg_for(@chair_term).reload.available?
    assert RegistrationFiling.start!([reg_for(@chair_term)])
    assert_equal "書類を作っている", RegistrationFiling.new.status_label
  end

  test "その他の登記・期限の分からない事由はやることの一覧で「まだ」" do
    other = Registration.create!(kind: "other", cause_on: Date.new(2026, 4, 1), note: "資産の総額の変更")
    assert_equal "「原因年月日」令和8年4月1日資産の総額の変更", other.cause_line
    assert_nil other.person
    Person::AddressChange.record!(@vice, address: "テスト県テスト市3-3", moved_on: Date.new(2025, 4, 1), date_precision: "month")
    item = Compliance::Checklist.new(today: Date.new(2026, 11, 24)).items.find { it.title.include?("住所の変更") }
    assert_equal :open, item.status
  end

  test "model:verify: 状態・登記した日のずれを見つける" do
    filing = RegistrationFiling.start!([reg_for(@chair_term)])
    filing.update_columns(status: "completed")
    reg_for(@vice_term).update_columns(registered_on: Date.current)
    reg_for(@chair_term).update_columns(registered_on: Date.current)
    m = ModelVerification.mismatches
    assert(m.any? { it.include?("登記の申請 ##{filing.id}") })
    assert(m.any? { it.include?("登記の事由 ##{reg_for(@chair_term).id}") })
    assert(m.none? { it.include?("登記の事由 ##{reg_for(@vice_term).id}") }, "申請に入れずに記録した登記した日は、ずれにしない")
  end
end
