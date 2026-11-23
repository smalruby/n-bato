require "test_helper"

class Bookkeeper::ProposalGeneratorTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls

    def initialize(response = nil, error: nil)
      @response = response
      @error = error
      @calls = []
    end

    def model = "fake-model"

    def complete_json(system:, content:, schema:)
      @calls << { system:, content:, schema: }
      raise @error if @error

      @response
    end
  end

  setup do
    Kaikeiou::SiwakeImporter.new(file_fixture("siwake_sample.txt").binread, filename: "s.txt").import
    @voucher = Voucher.create!(kind: "receipt", issued_on: Date.new(2025, 6, 1), description: "道場で使うケーブルを現金で買った")
    @voucher.files.attach(io: file_fixture("receipt.png").open, filename: "receipt.png", content_type: "image/png")
  end

  def response(entries, questions = [])
    { "entries" => entries, "questions" => questions }
  end

  def entry(**overrides)
    { "entry_date" => "2025-06-01", "debit_account_code" => 658, "debit_department_code" => 113,
      "credit_account_code" => 100, "credit_department_code" => 0, "amount" => 1980,
      "summary" => "消耗品を買った", "sub_summary" => "HDMI ケーブル", "rationale" => "道場で使う備品のため③事業の消耗品費",
      "confidence" => "high" }.merge(overrides.stringify_keys)
  end

  test "AI の答えから提案を作る" do
    client = FakeClient.new(response([ entry ], [ "レシートの店名が読めません" ]))
    proposals = Bookkeeper::ProposalGenerator.new(@voucher, client: client).call
    assert_equal 1, proposals.size
    p = proposals.first
    assert_equal 658, p.debit_account.code
    assert_equal 113, p.debit_department.code
    assert_nil p.credit_department
    assert_equal "fake-model", p.ai_model
    assert_equal "proposed", @voucher.reload.status
    assert_equal "レシートの店名が読めません", @voucher.ai_questions
  end

  test "プロンプトに科目・部門・過去の仕訳と画像を渡す" do
    client = FakeClient.new(response([]))
    Bookkeeper::ProposalGenerator.new(@voucher, client: client).call
    call = client.calls.first
    assert_match "658: 消耗品費(事業) [事業費 / その他経費]", call[:system]
    assert_match "113: ③事業", call[:system]
    assert_match "摘要「消耗品を買った」", call[:system]
    assert_equal "image", call[:content].first[:type]
    assert_equal "image/png", call[:content].first[:source][:media_type]
    assert_match "道場で使うケーブル", call[:content].last[:text]
    assert_equal false, call[:schema][:additionalProperties]
  end

  test "一覧に無いコードはエラーにして記帳しない" do
    client = FakeClient.new(response([ entry(debit_account_code: 999) ]))
    assert_empty Bookkeeper::ProposalGenerator.new(@voucher, client: client).call
    assert_equal "error", @voucher.reload.status
    assert_match "一覧に無いコード", @voucher.ai_error
  end

  test "API のエラーを記録する" do
    client = FakeClient.new(error: Bookkeeper::Client::Error.new("Claude API のエラー: overloaded"))
    Bookkeeper::ProposalGenerator.new(@voucher, client: client).call
    assert_equal "error", @voucher.reload.status
  end

  test "承認すると仕訳になり、承認者と日時が残る" do
    user = users(:one)
    proposal = Bookkeeper::ProposalGenerator.new(@voucher, client: FakeClient.new(response([ entry ]))).call.first
    journal = JournalProposal::Approval.approve!(proposal, by: user, entry: { amount: 2000 }).journal_entry
    assert_equal 2000, journal.debit_amount
    assert_equal proposal.reload.amount, proposal.amount # 提案は AI が出したまま(書き換えない)
    assert_equal user, journal.approved_by
    assert journal.approved_at
    assert_equal 2025, journal.fiscal_year
    assert_not journal.imported?
    assert_equal "booked", @voucher.reload.status
    assert_equal journal, proposal.reload.journal_entry
  end

  test "提案し直すと、確認待ちだった前の提案は消さずに取り下げになる" do
    gen = -> { Bookkeeper::ProposalGenerator.new(@voucher, client: FakeClient.new(response([ entry ]))).call }
    first = gen.call.first
    gen.call
    assert_equal 2, @voucher.journal_proposals.count
    assert_equal "withdrawn", first.reload.status
    assert_equal 1, @voucher.journal_proposals.pending.count
  end

  test "Claude Code が作った答えを API なしで登録する" do
    proposals = Bookkeeper::ProposalGenerator.new(@voucher).apply(response([ entry ]), model: "claude-code")
    assert_equal [ "claude-code" ], proposals.map(&:ai_model)
    assert_equal "proposed", @voucher.reload.status
  end
end
