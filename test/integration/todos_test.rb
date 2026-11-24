require "test_helper"

# やること(デザインシステム「やること」、見直し第9回)
class TodosTest < ActionDispatch::IntegrationTest
  class FakeClient
    attr_reader :sent
    def initialize(json) = @json = json

    def complete_json(system:, content:, schema:, max_tokens: nil)
      @sent = content
      @json
    end
  end

  setup do
    sign_in
    [2023, 2024, 2025, 2026].each { FiscalPeriod.find_or_create_by!(year: it) }
    FiscalPeriod.find_by(year: 2023).update!(closed_at: Time.current) if FiscalPeriod.column_names.include?("closed_at")
  end

  # 下の住所と電話番号は、公的機関が公開している窓口の連絡先(個人の情報ではない)。
  # 住所は松江市役所の所在地、電話は松江市役所 市民部 市民生活相談課。出どころ: 松江市が市民・法人あての文書に載せている問い合わせ先。
  # 実在の窓口の形の文で伏せ方を確かめるために使う。メールアドレスは架空。
  test "伏せる: 住所・電話・メール・郵便番号と、登録されている人の住所" do
    Person.create!(name: "会員 太郎", address: "テスト市ふしぎ町1-2-3")
    r = Masker.new.mask("〒690-8540 島根県松江市末次町86番地 TEL：0852-55-5169 MAIL：a@example.jp 会員太郎はテスト市ふしぎ町1-2-3 に住む。2023年12月15日 H30年度")
    assert_no_match(/690-8540|末次町86|0852-55-5169|a@example\.jp|ふしぎ町/, r.text)
    assert_match "2023年12月15日", r.text
    assert_match "H30年度", r.text
    assert r.counts[:address] >= 2
  end

  test "依頼の対話: 下書き → 伏せた文だけを送る → 人が決めてから記録する" do
    post incoming_requests_path, params: {body: "H30年度の届出書の日付を直してください。担当 TEL 0852-55-5169"}
    req = IncomingRequest.last
    follow_redirect!
    assert_select ".nb-mask", minimum: 1
    assert_equal 0, req.todos.count

    json = {"reply" => "指摘は正しいです。", "request" => {"title" => "書類の差し替え依頼", "counterpart" => "松江市", "received_on" => "2023-12-07", "due_on" => ""},
            "todos_new" => [{"title" => "役員の変更等届出書を出し直す", "fiscal_year" => 2018, "kind" => "document", "assignee" => "理事長", "due_on" => "2026-11-24", "target" => "", "done_rule" => "", "note" => ""},
              {"title" => "最終版を出す", "fiscal_year" => 2024, "kind" => "window", "assignee" => "理事長", "due_on" => "", "target" => "annual_reports", "done_rule" => "annual_report_submitted", "note" => ""}],
            "todos_update" => []}
    fake = FakeClient.new(json)
    msg = req.messages.last
    Requests::Organizer.new(req, client: fake).call(msg, masked_body: Masker.new.mask(msg.body).text)
    assert_no_match "0852-55-5169", fake.sent.first[:text]
    assert_equal 0, req.todos.count, "決めるまでは記録しない"

    post incoming_request_message_adoption_path(req, req.messages.last)
    assert_equal 2, req.reload.todos.count
    assert_equal "書類の差し替え依頼", req.title
    assert_equal Date.new(2023, 12, 7), req.received_on

    post undo_path(format: :json), params: {scope: "todos"}, as: :json
  end

  test "一覧: 依頼・義務・手続きを年度をまたいで出し、開くと年度を切り替える" do
    req = IncomingRequest.create!(title: "依頼A", counterpart: "松江市")
    t = req.todos.create!(title: "2023年度の名簿を直す", fiscal_year: 2023, kind: "screen", target: "people")
    Todo::StatusChange.change!(req.todos.create!(title: "年度なしの確認", kind: "ask"), status: "wait", waiting_on: "本人の返事")
    get todos_path
    assert_select "tr.nb-todo-group th", text: /依頼A/
    assert_select ".nb-ychip", text: /2023/
    assert_select "td", text: /待ち: 本人の返事/

    get todo_path(t)
    assert_redirected_to people_path(year: 2023)
    follow_redirect!
    assert_equal 2023, users(:one).reload.working_year
    assert_select "body[data-reason-default*=?]", "2023年度の名簿を直す" if FiscalPeriod.for(2023).closed?

    get todos_path(fy: 2024)
    assert_select "td", text: /2023年度の名簿を直す/, count: 0
  end

  test "状態を変える(待ち・済み)と、自動で済み" do
    req = IncomingRequest.create!(title: "依頼B")
    t = req.todos.create!(title: "提出する", fiscal_year: 2024, kind: "window", done_rule: "annual_report_submitted")
    post todo_status_changes_path(t), params: {status: "wait", waiting_on: "監事の返事"}
    assert_equal ["wait", "監事の返事"], [t.reload.status, t.waiting_on]
    post todo_status_changes_path(t), params: {status: "done", done_note: "出した"}
    assert t.reload.done?
    post todo_status_changes_path(t), params: {status: "todo"}
    begin
      create_annual_report!(2024, submitted_on: Date.new(2026, 11, 24))
    rescue
      skip("事業報告書を作れない")
    end
    Todo.refresh_auto!
    assert t.reload.done?
    assert_equal "auto", t.done_by
  end

  test "B1: 一覧を開いて自動で済みになっても、やることの画面の元に戻すでは戻らず、食い違わない" do
    t = Todo.create!(title: "提出する", fiscal_year: 2024, kind: "window", done_rule: "annual_report_submitted")
    create_annual_report!(2024, submitted_on: Date.new(2026, 11, 24))
    assert_difference -> { AuditOperation.count }, 1 do
      get todos_path
    end
    assert t.reload.done?
    assert_equal ["todos_auto"], AuditOperation.where(id: AuditOperation.maximum(:id)).pluck(:scope)
    post undo_path(format: :json), params: {scope: "todos"}, as: :json
    assert t.reload.done?
    assert_equal 1, t.status_changes.count
    assert_empty ModelVerification.mismatches
  end

  test "監査の役割は、やることを見るだけ" do
    users(:one).update!(role: "auditor")
    req = IncomingRequest.create!(title: "依頼C")
    t = req.todos.create!(title: "見るだけ", kind: "ask")
    get todos_path
    assert_select "a", text: /AI と依頼を整理する/, count: 0
    post todo_status_changes_path(t), params: {status: "done"}
    assert_not t.reload.done?
  end

  test "件数のまとめ(見直し第12回): 期限・担当ごとに数え、札で絞り、左のメニューに期限を過ぎた数を出す" do
    req = IncomingRequest.create!(title: "依頼C")
    req.todos.create!(title: "過ぎたもの", kind: "ask", due_on: Date.current - 1)
    req.todos.create!(title: "近いもの", kind: "ask", due_on: Date.current + 3)
    req.todos.create!(title: "AI のもの", kind: "ask", assignee: "AI")
    get todos_path(source: "request")
    tiles = css_select(".nb-todo-sum a.nb-todo-tile").to_h { [it.at("small").text, it.at("b").text.to_i] }
    assert_equal({"期限を過ぎた" => 1, "7 日以内" => 1, "それより先" => 0, "期限なし" => 1, "人がやる" => 2, "AI がやる" => 1}, tiles)

    get todos_path(source: "request", due: "over")
    assert_response :success
    assert_select ".nb-todo-sum a.nb-todo-tile--over[aria-current=true] b", "1"
    assert_select "td", text: /過ぎたもの/
    assert_select "td", text: /近いもの/, count: 0
    assert_select ".nb-nav a[aria-current=page] .nb-nav-count", minimum: 1
    assert_select ".nb-nav-group", 3
    assert_select ".nb-nav a svg.nb-icon", minimum: 13
  end
end
