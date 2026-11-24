require "test_helper"

# 使えない操作の理由(BlockedReason。デザインシステム DisabledAction、見直し第22回)。データは架空。
# 画面の (i)・運用のスクリプト・モデルのエラーの文で同じ文を使うので、モデルが返す文をここで確かめる。
class BlockedReasonTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  def board_resolution(*names)
    people = names.map { Person.create!(name: it) }
    people.each { OfficerTerm.create!(person: it, role: "director", starts_on: Date.new(2026, 4, 1), ends_on: Date.new(2028, 3, 31)) }
    [ Resolution.create!(body: "board", voting_method: "written", title: "架空の理事会", proposed_on: Date.new(2026, 5, 1), proposer: people.first), people ]
  end

  test "1 つの文にすると、見出し・何があるか・決まり・代わりに の順に並ぶ" do
    r = BlockedReason.new(title: "消せません", reason: "残すためです。", what: "記録が 2 件あります", alternative: "代わりに: 直せます。")
    assert_equal "消せません。記録が 2 件あります。残すためです。代わりに: 直せます。", r.message
    assert_equal r.message, r.to_s
    assert_equal "消せません。残すためです。", BlockedReason.new(title: "消せません", reason: "残すためです。").message
    assert_not r.link?
    assert BlockedReason.new(title: "t", reason: "r", link_label: "見る", link_target: "#x").link?
  end

  test "決議: 同意(取り消したものも)を記録したら消せない。件数・取り消した件数・リンク・代わりにを出す" do
    resolution, (a, b) = board_resolution("理事A", "理事B")
    assert_nil resolution.destroy_blocked_reason

    Consent.record!(resolution, person: a, consented_on: Date.new(2026, 5, 2))
    blocked = resolution.destroy_blocked_reason
    assert_equal [ "この決議は消せません", "同意の記録が 1 件あります", "同意の記録を見る(1 件)", "#consents" ], [ blocked.title, blocked.what, blocked.link_label, blocked.link_target ]
    assert_match "同意を記録した決議は消せません", blocked.reason
    assert_match "「編集」で直せます", blocked.alternative

    Consent::Cancellation.cancel!(resolution.consents.sole, by: @user)
    Consent.record!(resolution, person: b, consented_on: Date.new(2026, 5, 3))
    assert_equal "同意の記録が 2 件あります(取り消した 1 件を含む)", resolution.reload.destroy_blocked_reason.what
    assert_not resolution.destroy
    assert_equal [ resolution.destroy_blocked_reason.message ], resolution.errors.full_messages
  end

  test "決議の議案・同意: 反映した議案は消せず、その決議の同意は取り消せない" do
    resolution, (a,) = board_resolution("理事A")
    item = resolution.items.create!(kind: "general", title: "第1号議案")
    Consent.record!(resolution, person: a, consented_on: Date.new(2026, 5, 2))
    consent = resolution.consents.sole
    assert_nil item.destroy_blocked_reason
    assert_nil consent.cancel_blocked_reason

    item.update!(kind: "officer_election", payload: { "appointments" => [] })
    ResolutionItem::Application.apply!(item.reload, on: Date.new(2026, 5, 10))
    blocked = item.reload.destroy_blocked_reason
    assert_equal [ "この議案は消せません", "2026/05/10 に記録に反映しました" ], [ blocked.title, blocked.what ]
    blocked = consent.reload.cancel_blocked_reason
    assert_equal [ "この同意は取り消せません", "記録に反映した議案が 1 件あります", "#items" ], [ blocked.title, blocked.what, blocked.link_target ]
    error = assert_raises(ArgumentError) { Consent::Cancellation.cancel!(consent, by: @user) }
    assert_equal blocked.message, error.message
  end

  test "同意を取り消してあれば、その理由" do
    resolution, (a,) = board_resolution("理事A")
    consent = Consent.record!(resolution, person: a, consented_on: Date.new(2026, 5, 2))
    Consent::Cancellation.cancel!(consent, by: @user)
    assert_equal "この同意は取り消せません。もう取り消してあります。", consent.reload.cancel_blocked_reason.message
  end

  test "会議で決めた決議は、反映した議案があれば消せない(議案へのリンク)" do
    chair = Person.create!(name: "理事A")
    resolution = Resolution.create!(body: "board", voting_method: "meeting", title: "架空の理事会", proposed_on: Date.new(2026, 5, 1), held_on: Date.new(2026, 5, 2), proposer: chair)
    ResolutionItem::Application.apply!(resolution.items.create!(kind: "officer_election", title: "選任", payload: { "appointments" => [] }))
    blocked = resolution.reload.destroy_blocked_reason
    assert_equal [ "記録に反映した議案が 1 件あります", "議案を見る", "#items" ], [ blocked.what, blocked.link_label, blocked.link_target ]
  end

  test "証憑・仕訳: 提案のある証憑は消せない。会計王から取り込んだ・承認でできた・取り消した仕訳は直せない" do
    Kaikeiou::SiwakeImporter.new(file_fixture("siwake_sample.txt").binread, filename: "s.txt").import
    imported = JournalEntry.where.not(siwake_import_id: nil).first
    blocked = imported.edit_blocked_reason
    assert_equal [ "この仕訳は直せません", "会計王から取り込みました(s.txt)", imported.siwake_import ], [ blocked.title, blocked.what, blocked.link_target ]
    assert_match "会計王で直して", blocked.alternative

    voucher = Voucher.create!(kind: "bank", issued_on: Date.new(2025, 6, 1), description: "架空の通帳")
    assert_nil voucher.destroy_blocked_reason
    proposal = JournalProposal.propose!(voucher:, model: "test", entry_date: Date.new(2025, 6, 1), amount: 20, debit_account: Account.find_by!(code: 106),
                                        credit_account: Account.find_by!(code: 550), summary: "利息", sub_summary: "", rationale: "テスト", confidence: "high")
    voucher.advance_status!
    blocked = voucher.destroy_blocked_reason
    assert_equal [ "この証憑は消せません", "AI の仕訳の提案が 1 件あります", "#proposals" ], [ blocked.title, blocked.what, blocked.link_target ]
    assert_match "記帳しない", blocked.alternative

    entry = Audit.operation(user: @user, scope: "vouchers") { JournalProposal::Approval.approve!(proposal, by: @user).journal_entry }
    assert_equal "booked", voucher.reload.status
    assert_nil voucher.destroy_blocked_reason.alternative, "記帳済みの証憑には「記帳しない」が無い"
    blocked = entry.edit_blocked_reason
    assert_equal [ "証憑を見る", voucher ], [ blocked.link_label, blocked.link_target ]
    assert_match "「取り消す」", blocked.alternative

    Audit.operation(user: @user, scope: "journal_entries") { JournalEntry::Cancellation.cancel!(entry, by: @user, reason: "架空の打ち間違い") }
    blocked = entry.reload.edit_blocked_reason
    assert_match "に取り消しました", blocked.what
    assert_nil blocked.alternative

    manual = JournalEntry.create!(entry_date: Date.new(2025, 6, 2), debit_account: Account.find_by!(code: 106), credit_account: Account.find_by!(code: 550), amount: 10)
    assert_nil manual.edit_blocked_reason
  end

  test "年度: 次の年度を締めてあれば締めを解けない。前の年度を締める前は会計王へ書き出せない" do
    [ 2024, 2025 ].each { Account.create!(fiscal_year: it, code: 100, name: "現金") }
    FiscalPeriod.ensure!
    p24, p25 = FiscalPeriod.for(2024), FiscalPeriod.for(2025)
    FiscalPeriod.where(year: ..2023).update_all(closed_on: Date.current)
    assert p25.provisional?
    blocked = p25.siwake_export_blocked_reason
    assert_equal [ "まだ書き出せません", "#{p24.label}をまだ締めていません" ], [ blocked.title, blocked.what ]
    assert_nil p24.siwake_export_blocked_reason
    assert_nil p24.reopen_blocked_reason

    p24.update!(closed_on: Date.current)
    p25.update!(closed_on: Date.current)
    blocked = p24.reload.reopen_blocked_reason
    assert_equal [ "この年度の締めは解けません", "#{p25.label}が締めてあります" ], [ blocked.title, blocked.what ]
    error = assert_raises(ArgumentError) { p24.reopen!(reason: "架空の理由") }
    assert_equal blocked.message, error.message
    assert_nil p25.reload.reopen_blocked_reason
  end

  test "手順: 返事がそろうまで・事業報告が無い・締める順が来ていないときは済みにできない" do
    [ 2024, 2025 ].each { Account.create!(fiscal_year: it, code: 100, name: "現金") }
    run = ProcedureRun.create!(kind: "annual_report", period: 2025)
    audit = run.step("audit")
    blocked = audit.complete_blocked_reason
    assert_equal [ "まだ済みにできません", "返事がそろったのは 0 / 1 です", "#waits" ], [ blocked.title, blocked.what, blocked.link_target ]
    assert_equal blocked.message, audit.blocked_reason
    audit.check!("監査報告書を受け取った")
    assert_nil audit.complete_blocked_reason
    assert_nil audit.blocked_reason

    assert_equal "2025年度の事業報告がまだありません", run.step("submit").complete_blocked_reason.what
    report = AnnualReport.create!(fiscal_year: 2025)
    ProcedureRun.find(run.id)
    assert_nil run.step("submit").complete_blocked_reason
    assert_equal "2025年度の記録がありません", run.step("close_year").complete_blocked_reason.what

    FiscalPeriod.ensure!
    assert_equal "提出した日がまだ記録されていません", ProcedureRun.find(run.id).step("close_year").complete_blocked_reason.what
    AnnualReport::Milestone.record!(report, "submitted", on: Date.new(2026, 6, 1))
    blocked = ProcedureRun.find(run.id).step("close_year").complete_blocked_reason
    assert_equal [ "まだ締められません", "#{FiscalPeriod.for(2024).label}をまだ締めていません" ], [ blocked.title, blocked.what ]
    FiscalPeriod.where(year: ..2024).update_all(closed_on: Date.current)
    assert_nil ProcedureRun.find(run.id).step("close_year").complete_blocked_reason
  end

  test "手順: final を済みにした・ほかの記録から済んだ手順は、済みを取り消せない" do
    run = ProcedureRun.create!(kind: "annual_report", period: 2025)
    report = AnnualReport.create!(fiscal_year: 2025)
    assert_nil run.step("submit").reopen_blocked_reason

    ProcedureStep::StatusChange.change!(run.step("submit"), status: "done", on: Date.new(2026, 6, 28), by: @user)
    blocked = ProcedureRun.find(run.id).step("submit").reopen_blocked_reason
    assert_equal [ "この手順は取り消せません", "2026/06/28 に済みにしました(提出した日を記録する)" ], [ blocked.title, blocked.what ]
    assert_match "事業報告・提出の画面で直せます", blocked.alternative

    ProcedureStep::StatusChange.change!(run.step("close_books"), status: "done", by: @user)
    assert_nil ProcedureRun.find(run.id).step("close_books").reopen_blocked_reason, "final でない手順は取り消せる"

    AnnualReport::Milestone.record!(report, "approved", on: Date.new(2026, 6, 20))
    step = ProcedureRun.find(run.id).step("general_meeting")
    assert_equal "done", step.status
    blocked = step.reopen_blocked_reason
    assert_match "ほかの記録", blocked.reason
    assert_match "事業報告・提出の画面", blocked.alternative
  end
end
