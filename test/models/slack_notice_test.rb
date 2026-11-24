require "test_helper"

# Slack への知らせ(見直し第10回)。送り方は差し替え、送った文を確かめる。
class SlackNoticeTest < ActiveSupport::TestCase
  setup do
    @sent = []
    SlackNotice.poster = ->(text) { @sent << text; true }
    [ 2023, 2024, 2025, 2026 ].each { FiscalPeriod.find_or_create_by!(year: it) }
  end
  teardown { SlackNotice.poster = nil }

  test "期限のリマインド: 週のまとめ・3 日前・当日を、二度は送らない" do
    req = IncomingRequest.create!(title: "依頼")
    req.todos.create!(title: "3日後の作業", kind: "ask", assignee: "理事長", due_on: Date.new(2026, 11, 26))
    req.todos.create!(title: "今日の作業", kind: "ask", assignee: "理事長", due_on: Date.new(2026, 11, 23))
    SlackNotice::Digest.new(today: Date.new(2026, 11, 23)).run!
    assert @sent.any? { it.include?("今週のやること") && it.include?("3日後の作業") }
    assert @sent.any? { it.include?("期限まであと 3 日") }
    assert @sent.any? { it.include?("今日が期限") && it.include?("今日の作業") }
    n = @sent.size
    SlackNotice::Digest.new(today: Date.new(2026, 11, 23)).run!
    assert_equal n, @sent.size
  end

  test "締めた年度の変更は理由つきで送り、会員の記録は値を出さない" do
    SlackNotice::Activity.new.run!   # 続きの位置を決める
    Audit.operation(user: nil, scope: "t") do
      Audit.reason!("領収書と照合して直した")
      Person.create!(name: "会員 太郎", address: "テスト市1-2-3")
    end
    SlackNotice::Activity.new.run!
    msg = @sent.find { it.include?("締めた年度の変更") }
    assert msg
    assert_includes msg, "理由: 領収書と照合して直した"
    assert_no_match(/テスト市|会員 太郎/, msg)
  end

  test "年度を締めたら知らせる" do
    SlackNotice::Activity.new.run!
    Audit.operation(user: nil, scope: "t") { FiscalPeriod.find_by(year: 2023).update!(closed_at: Time.current) }
    SlackNotice::Activity.new.run!
    assert @sent.any? { it.include?("2023年度を締めました") }
  end

  test "締めた年度の変更: 会員以外の記録は、何をどう変えたかを出す" do
    cash = Account.create!(fiscal_year: 2023, code: 100, name: "現金")
    supplies = Account.create!(fiscal_year: 2023, code: 658, name: "消耗品費")
    SlackNotice::Activity.new.run!
    entry = nil
    Audit.operation(user: users(:one), scope: "t") do
      Audit.reason!("記帳の漏れ")
      entry = JournalEntry.create!(entry_date: Date.new(2023, 5, 1), debit_account: supplies, credit_account: cash, amount: 800, summary: "電池")
    end
    Audit.operation(user: users(:one), scope: "t") do
      Audit.reason!("金額の誤り")
      entry.update!(amount: 900)
    end
    SlackNotice::Activity.new.run!
    created, updated = @sent.select { it.include?("締めた年度の変更") }
    assert_includes created, "追加"
    assert_includes created, "?year=2023"
    assert_includes updated, "800 → 900"
  end

  test "年度を始めた・監査と提出の手順を済みにした・提出日を記録した" do
    AnnualReport.create!(fiscal_year: 2025)
    run = ProcedureRun.create!(kind: "annual_report", period: 2025)
    SlackNotice::Activity.new.run!
    Audit.operation(user: users(:one), scope: "t") { FiscalPeriod.create!(year: 2027) }
    Audit.operation(user: users(:one), scope: "t") { run.step("audit").complete! }
    Audit.operation(user: users(:one), scope: "t") { run.step("close_books").complete! }
    Audit.operation(user: users(:one), scope: "t") { AnnualReport.find_by(fiscal_year: 2025).update!(submitted_on: Date.new(2026, 6, 20)) }
    SlackNotice::Activity.new.run!
    assert @sent.any? { it.include?("2027年度を始めました") }
    assert @sent.any? { it.include?("監事の監査が済みました") }
    assert @sent.any? { it.include?("所轄庁への提出を記録しました* 2025年度(提出日 2026-06-20)") }
    assert_not @sent.any? { it.include?("close_books") }
  end

  class FakeHttp
    Response = Data.define(:body)
    attr_reader :requests

    def initialize(body) = (@body, @requests = body, [])

    def start(host, port, **opts)
      @requests << [ host, port, opts ]
      yield self
    end

    def request(req)
      @requests << req
      raise @body if @body.is_a?(Exception)

      Response.new(@body)
    end
  end

  test "Slack の chat.postMessage に送る(偽の HTTP で確かめる)" do
    http = FakeHttp.new(%({"ok":true}))
    with_env("SLACK_BOT_TOKEN" => "xoxb-test", "SLACK_CHANNEL_ID" => "C0TEST") do
      assert SlackNotice.chat_post_message("こんにちは", http:)
      assert_not SlackNotice.chat_post_message("x", http: FakeHttp.new(%({"ok":false,"error":"channel_not_found"})))
      assert_not SlackNotice.chat_post_message("x", http: FakeHttp.new("<html>"))
      assert_not SlackNotice.chat_post_message("x", http: FakeHttp.new(IOError.new("切れた")))
    end
    host, _, opts = http.requests.first
    req = http.requests.last
    assert_equal [ "slack.com", true ], [ host, opts[:use_ssl] ]
    assert_equal "Bearer xoxb-test", req["Authorization"]
    assert_equal({ "channel" => "C0TEST", "text" => "こんにちは", "unfurl_links" => false }, JSON.parse(req.body))
  end

  test "鍵が無ければ送らない" do
    SlackNotice.poster = nil
    with_env("SLACK_BOT_TOKEN" => nil) do
      assert_not SlackNotice.post!("k", "x")
      assert_not SlackNotice.chat_post_message("x", http: FakeHttp.new(%({"ok":true})))
    end
  end
end
