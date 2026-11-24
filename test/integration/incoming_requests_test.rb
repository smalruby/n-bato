require "test_helper"

# 依頼の画面の出来事(送る・決める・解決にする・送付状・下書きを消す)。docs/adr/0034。データは架空。
class IncomingRequestsTest < ActionDispatch::IntegrationTest
  class FakeClient
    def initialize(json) = @json = json

    def complete_json(**)
      raise Bookkeeper::Client::Error, "試しの失敗" if @json == :error

      @json
    end
  end

  REPLY = { "reply" => "整理しました", "request" => { "title" => "", "counterpart" => "", "received_on" => "", "due_on" => "" },
            "todos_new" => [ { "title" => "架空の書類を出す", "fiscal_year" => 2024, "kind" => "document", "assignee" => "理事長", "due_on" => "", "target" => "", "done_rule" => "", "note" => "" } ],
            "todos_update" => [] }.freeze

  setup { sign_in }

  def with_ai(json)
    before = ENV["ANTHROPIC_API_KEY"]
    ENV["ANTHROPIC_API_KEY"] = "test-key"
    Bookkeeper::Client.define_singleton_method(:new) { |*| FakeClient.new(json) }
    yield
  ensure
    Bookkeeper::Client.singleton_class.send(:remove_method, :new)
    before ? ENV["ANTHROPIC_API_KEY"] = before : ENV.delete("ANTHROPIC_API_KEY")
  end

  def without_ai
    before = ENV["ANTHROPIC_API_KEY"]
    ENV.delete("ANTHROPIC_API_KEY")
    skip "credentials に鍵がある環境では確かめない" if Bookkeeper::Client.configured?
    yield
  ensure
    before ? ENV["ANTHROPIC_API_KEY"] = before : ENV.delete("ANTHROPIC_API_KEY")
  end

  test "下書き → AI に送る → この案で決める → 全部済んだら解決 → 送付状" do
    post incoming_requests_path, params: { body: "架空の役所からの依頼の文" }
    req = IncomingRequest.last
    draft = req.messages.drafts.last
    with_ai(REPLY) { post incoming_request_message_delivery_path(req, draft), params: { send_attachments: "1" } }
    assert_redirected_to incoming_request_path(req, anchor: "thread-end")
    assert draft.reload.sent?
    assert draft.send_attachments
    reply = req.messages.last
    assert_equal "整理しました", reply.body

    get incoming_request_path(req)
    assert_select ".nb-msg--user", text: /架空の役所からの依頼の文/
    assert_select "form[action=?]", incoming_request_message_adoption_path(req, reply)

    post incoming_request_message_adoption_path(req, reply)
    assert_redirected_to incoming_request_path(req, anchor: "todos")
    todo = req.reload.todos.sole
    post incoming_request_message_adoption_path(req, reply)
    assert_equal "この案はもう決めてあります", flash[:alert]

    post incoming_request_settlement_path(req)
    assert_equal "まだ済んでいないやることがあります", flash[:alert]
    post todo_status_changes_path(todo), params: { status: "done", done_note: "出した" }
    post incoming_request_settlement_path(req)
    assert_match "解決にしました", flash[:notice]
    assert req.reload.resolved?

    with_ai({ "text" => "架空の送付状" }) { post incoming_request_cover_letter_path(req) }
    assert_redirected_to incoming_request_path(req, anchor: "cover")
    assert_equal "架空の送付状", req.reload.cover_letter
    with_ai(:error) { post incoming_request_cover_letter_path(req) }
    assert_match "下書きを作れませんでした", flash[:alert]
    assert_empty ModelVerification.mismatches
  end

  test "AI の鍵が無い・AI に送れないときは、下書きのまま" do
    post incoming_requests_path, params: { body: "架空の依頼" }
    req = IncomingRequest.last
    draft = req.messages.drafts.last
    without_ai { post incoming_request_message_delivery_path(req, draft) }
    assert_match "ANTHROPIC_API_KEY", flash[:alert]
    without_ai { post incoming_request_cover_letter_path(req) }
    assert_match "ANTHROPIC_API_KEY", flash[:alert]
    with_ai(:error) { post incoming_request_message_delivery_path(req, draft) }
    assert_match "AI に送れませんでした", flash[:alert]
    assert draft.reload.draft?
  end

  test "空の文は受け付けない。下書きを消すと、何も無い依頼は消える" do
    post incoming_requests_path, params: { body: " " }
    assert_redirected_to new_incoming_request_path
    post incoming_requests_path, params: { body: "架空の依頼" }
    req = IncomingRequest.last
    post incoming_request_messages_path(req), params: { body: "" }
    assert_equal "書いてから送ってください", flash[:alert]
    post incoming_request_messages_path(req), params: { body: "もう一つの下書き" }
    delete incoming_request_message_path(req, req.messages.drafts.last)
    assert_redirected_to incoming_request_path(req)
    delete incoming_request_message_path(req, req.messages.drafts.last)
    assert_redirected_to todos_path
    assert_not IncomingRequest.exists?(req.id)
  end

  test "B4: この案で決めるが途中で失敗したら、途中までの変更も残さない" do
    req = IncomingRequest.create!(title: "元の題")
    todo = req.todos.create!(title: "前からあるやること", kind: "ask")
    msg = IncomingRequestMessage.write!(req, role: "assistant", body: "案", proposal: {
      "request" => { "title" => "直した題" },
      "todos_new" => [ { "title" => "一つ目" }, { "title" => "" } ],
      "todos_update" => [ { "id" => todo.id, "status" => "doing" } ] })
    before = AuditChange.maximum(:id).to_i
    post incoming_request_message_adoption_path(req, msg)
    assert_empty AuditChange.where(id: (before + 1)..).where.not(auditable_type: "FiscalPeriod").pluck(:auditable_type), "操作履歴にも残さない"
    assert_redirected_to incoming_request_path(req)
    assert flash[:alert].present?
    assert_equal [ "元の題", [ "前からあるやること" ], "todo" ], [ req.reload.title, req.todos.map(&:title), todo.reload.status ]
    assert_not msg.reload.applied?
    assert_empty ModelVerification.mismatches
  end

  test "Q1: AI に送るを二度押ししても 404 にせず、もう送ってあると伝える(AI を二度呼ばない)" do
    post incoming_requests_path, params: { body: "架空の依頼" }
    req = IncomingRequest.last
    draft = req.messages.drafts.last
    with_ai(REPLY) { post incoming_request_message_delivery_path(req, draft) }
    with_ai(:error) { post incoming_request_message_delivery_path(req, draft) }
    assert_redirected_to incoming_request_path(req, anchor: "thread-end")
    assert_equal "この発言はもう AI に送ってあります", flash[:alert]
    assert_equal 1, req.messages.where(role: "assistant").count
  end

  # AI を待つ間に、もう一方の押下が先に送り終えた(押したときは下書きだった)
  class RacingClient
    def initialize(draft) = @draft = draft

    def complete_json(**)
      IncomingRequestMessage::Delivery.deliver!(IncomingRequestMessage.find(@draft.id), masked_body: "先に送った", send_attachments: false, reply: REPLY)
      REPLY
    end
  end

  test "Q1: AI を待つ間にもう一方が送り終えていたら、もう送ってあると伝え、返事を二重に残さない" do
    post incoming_requests_path, params: { body: "架空の依頼" }
    req = IncomingRequest.last
    draft = req.messages.drafts.last
    with_ai(REPLY) do
      Bookkeeper::Client.define_singleton_method(:new) { |*| RacingClient.new(draft) }
      post incoming_request_message_delivery_path(req, draft)
    end
    assert_redirected_to incoming_request_path(req, anchor: "thread-end")
    assert_equal IncomingRequestMessage::Delivery::ALREADY, flash[:alert]
    assert_equal [ "先に送った", 1 ], [ draft.reload.delivery.masked_body, req.messages.where(role: "assistant").count ]
    assert_empty ModelVerification.mismatches
  end

  test "Q2: 同じ状態にしたときは「元に戻せます」と言わない" do
    todo = Todo.create!(title: "架空のやること")
    post todo_status_changes_path(todo), params: { status: "doing" }
    assert_match "元に戻せます", flash[:notice]
    assert_no_difference -> { AuditOperation.count } do
      post todo_status_changes_path(todo), params: { status: "doing" }
    end
    assert_equal "「架空のやること」はもう作業中です", flash[:notice]
  end

  test "状態の分からない変化は受け付けない" do
    todo = Todo.create!(title: "架空のやること")
    post todo_status_changes_path(todo), params: { status: "nope" }
    assert_equal "状態が分かりません", flash[:alert]
  end
end
