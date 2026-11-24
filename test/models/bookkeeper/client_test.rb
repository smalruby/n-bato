require "test_helper"

# Claude API の呼び出し。偽の API(FakeClaudeApi)で確かめる。本物の API は呼ばない。
class Bookkeeper::ClientTest < ActiveSupport::TestCase
  def complete(result)
    with_fake_claude(result) do |api|
      json = Bookkeeper::Client.new.complete_json(system: "指示", content: [ { type: "text", text: "問い" } ], schema: { type: "object" })
      [ json, api ]
    end
  end

  def reply(...) = FakeClaudeApi.reply(...)

  test "JSON Schema の形の答えを読む" do
    json, api = complete(reply(%({"answer":"はい"})))
    assert_equal({ "answer" => "はい" }, json)
    req = api.requests.sole
    assert_equal :"claude-opus-5-5", req[:model]
    assert_equal [ { type: "text", text: "指示" } ], req[:system_]
    assert_equal :json_schema, req.dig(:output_config, :format, :type)
  end

  test "断られた・途中で切れた・JSON でない・API のエラーは Error にする" do
    assert_match "断りました", assert_raises(Bookkeeper::Client::Error) { complete(reply("", stop_reason: :refusal)) }.message
    assert_match "途中で切れました", assert_raises(Bookkeeper::Client::Error) { complete(reply("{", stop_reason: :max_tokens)) }.message
    assert_match "JSON として読めません", assert_raises(Bookkeeper::Client::Error) { complete(reply("ではない")) }.message
    api_error = Anthropic::Errors::APIError.new(url: URI("https://api.example.com"), status: 500, message: "混んでいます")
    assert_match "Claude API のエラー: 混んでいます", assert_raises(Bookkeeper::Client::Error) { complete(api_error) }.message
  end

  test "鍵が無ければ呼ばない" do
    api = FakeClaudeApi.new({})
    with_env("ANTHROPIC_API_KEY" => nil) do
      skip "credentials に鍵がある環境" if Bookkeeper::Client.configured?
      assert_raises(Bookkeeper::Client::NotConfigured) { Bookkeeper::Client.new(api:).complete_json(system: "", content: [], schema: {}) }
    end
    assert_empty api.requests
  end

  def search(*results)
    with_fake_claude(*results) do |api|
      json = Bookkeeper::Client.new.search_json(system: "指示", prompt: "調べて", schema: { type: "object" }, max_uses: 3)
      [ json, api ]
    end
  end

  test "Web 検索つきで調べ、前後に文があっても JSON の部分を読む。途中で止まったら続きを頼む" do
    json, api = search(reply("調べ中", stop_reason: :pause_turn), reply(%(見つけました: {"name":"テスト市"} 以上)))
    assert_equal({ "name" => "テスト市" }, json)
    first, second = api.requests
    assert_equal [ { type: "web_search_20260209", name: "web_search", max_uses: 3 } ], first[:tools]
    assert_equal [ { role: "user", content: "調べて" } ], first[:messages]
    assert_equal [ "user", "assistant" ], second[:messages].map { it[:role].to_s }
    assert_equal({ type: :text, text: "調べ中" }, second[:messages].last[:content].first)
  end

  test "Web 検索でも、断られた・途中で切れた・JSON でない・API のエラーは Error にする" do
    assert_match "断りました", assert_raises(Bookkeeper::Client::Error) { search(reply("", stop_reason: :refusal)) }.message
    assert_match "途中で切れました", assert_raises(Bookkeeper::Client::Error) { search(reply("{", stop_reason: :max_tokens)) }.message
    assert_match "JSON として読めません", assert_raises(Bookkeeper::Client::Error) { search(reply("{ではない}")) }.message
    api_error = Anthropic::Errors::APIError.new(url: URI("https://api.example.com"), status: 500, message: "混んでいます")
    assert_match "Claude API のエラー: 混んでいます", assert_raises(Bookkeeper::Client::Error) { search(api_error) }.message
  end

  test "Web 検索も、鍵が無ければ呼ばない" do
    api = FakeClaudeApi.new({})
    with_env("ANTHROPIC_API_KEY" => nil) do
      skip "credentials に鍵がある環境" if Bookkeeper::Client.configured?
      assert_raises(Bookkeeper::Client::NotConfigured) { Bookkeeper::Client.new(api:).search_json(system: "", prompt: "", schema: {}) }
    end
    assert_empty api.requests
  end
end
