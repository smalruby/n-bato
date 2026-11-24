require "test_helper"

# 右ペイン「AI に聞く」。Claude API は偽物(FakeClaudeApi)にする。
class AssistantTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    ensure_organization
    FiscalPeriod.find_or_create_by!(year: 2025)
  end

  def answer(text, kind: "none") = { "answer" => text, "action" => { "kind" => kind } }
  def receipt = fixture_file_upload("receipt.png", "image/png")

  test "聞いたことが空なら AI を呼ばない" do
    with_fake_claude(answer("x")) do |api|
      post assistant_path, params: { q: "  " }
      assert_equal "聞きたいことを書いてください。", response.parsed_body["answer"]
      assert_empty api.requests
    end
  end

  test "画面の使い方を添えて聞き、答えを返す。画面の名前の形が違えば default" do
    with_fake_claude(answer("左のメニューから開きます")) do |api|
      post assistant_path, params: { q: "仕訳の直し方は?", screen: "Journal-Entries!" }
      assert_equal "左のメニューから開きます", response.parsed_body["answer"]
      assert_nil response.parsed_body["action"]
      system = api.requests.sole[:system_].first[:text]
      assert_match "いまの画面: default", system
      assert_match "いま画像は添えられていません", system
    end
  end

  test "画像なしで仕訳を頼まれたら、画像を添えるよう案内する" do
    with_fake_claude(answer("仕訳します", kind: "journal_from_receipt")) do
      post assistant_path, params: { q: "仕訳して", screen: "journal_entries" }
      assert_equal "仕訳します\n画像を添えてください", response.parsed_body["answer"]
      assert_nil response.parsed_body["action"]
    end
  end

  test "画像つきの頼みは操作の案にし、実行すると証憑を登録して AI 仕訳の案を作る" do
    with_fake_claude(answer("仕訳します", kind: "journal_from_receipt"), { "entries" => [], "questions" => [ "金額が読めません" ] }) do |api|
      post assistant_path, params: { q: "仕訳して", screen: "journal_entries", image: receipt }
      body = response.parsed_body
      assert_match "証憑として登録", body.dig("action", "label")
      assert_equal "image", api.requests.first[:messages].first[:content].last[:type]

      assert_difference -> { Voucher.count }, 1 do
        post assistant_perform_path, params: { token: body.dig("action", "token") }
      end
      voucher = Voucher.last
      assert response.parsed_body["ok"]
      assert_equal voucher_path(voucher), response.parsed_body["location"]
      assert voucher.files.attached?
      assert_equal "金額が読めません", voucher.ai_questions
      assert_equal "AI に頼んだ: 証憑を登録して仕訳の案を作った", AuditOperation.order(:id).last.label
    end
  end

  test "AI のエラーは答えの欄で知らせる" do
    with_fake_claude(FakeClaudeApi.reply("", stop_reason: :refusal)) do
      post assistant_path, params: { q: "仕訳して" }
      assert_match "AI に聞けませんでした(AI が回答を断りました)", response.parsed_body["answer"]
    end
  end

  test "監査の役割には操作の案を出さず、実行もさせない" do
    users(:one).update!(role: "auditor")
    with_fake_claude(answer("仕訳します", kind: "journal_from_receipt")) do
      post assistant_path, params: { q: "仕訳して", image: receipt }
      assert_nil response.parsed_body["action"]
      post assistant_perform_path, params: { token: "x" }
      assert_response :forbidden
    end
  end

  test "書き換えた操作の案は実行しない" do
    post assistant_perform_path, params: { token: "書き換えた" }
    assert_response :unprocessable_entity
    assert_match "操作の案が正しくありません", response.parsed_body["message"]
  end
end
